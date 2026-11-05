#!/usr/bin/env bash
# 增量更新已安装的 Dnsmasq + SNIproxy，未指定域名时添加 Reddit。
set -euo pipefail

usage() {
    echo "用法: bash $0 [--dry-run] <SNI服务器IPv4> [域名 ...]"
    echo "不指定域名时添加 Reddit；--dry-run 仅显示规则，不修改配置或重启服务。"
}

fail() { echo "[错误] $*" >&2; exit 1; }

dry_run=0
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if [[ ${1:-} == --dry-run ]]; then dry_run=1; shift; fi
[[ $# -ge 1 ]] || { usage; exit 1; }
proxy_ip=$1
shift
[[ $proxy_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "请输入有效的 IPv4 地址。"
IFS=. read -r -a octets <<< "$proxy_ip"
for octet in "${octets[@]}"; do
    [[ $octet == 0 || $octet != 0* ]] || fail "IPv4 地址不能含前导零。"
    (( 10#$octet <= 255 )) || fail "IPv4 地址的每一段必须在 0-255 之间。"
done

domains=(
    redd.it reddit.app.link reddit.com reddit.map.fastly.net
    redditblog.com reddithelp.com redditinc.com redditmail.com
    redditmedia.com redditspace.com redditstatic.com redditstatus.com
    reddituploads.com reddituploads.com.cdn-cf.behance.net
    reddituploads.com.cdn-cf.dropbox.com
)
if [[ $# -gt 0 ]]; then domains=("$@"); fi
for domain in "${domains[@]}"; do
    [[ ${#domain} -le 253 && $domain =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] \
        || fail "无效域名: ${domain}（请使用小写域名，不带协议、通配符或路径）"
done

if (( dry_run )); then
    echo "# Dnsmasq 规则"
    for domain in "${domains[@]}"; do
        printf 'address=/%s/%s\nlocal=/%s/\n' "$domain" "$proxy_ip" "$domain"
    done
    echo "# SNIproxy table 规则（匹配域名本身及其子域名）"
    for domain in "${domains[@]}"; do printf '    (^|\.)%s$ *\n' "${domain//./\\.}"; done
    exit 0
fi

dnsmasq_conf=${DNSMASQ_CONF:-/etc/dnsmasq.d/custom_netflix.conf}
sniproxy_conf=${SNIPROXY_CONF:-/etc/sniproxy.conf}
for config in "$dnsmasq_conf" "$sniproxy_conf"; do
    [[ -f $config && -r $config && -w $config ]] || fail "配置不存在或不可读写: ${config}；请在已部署服务器上使用 sudo。"
done
for command in dnsmasq systemctl; do
    command -v "$command" >/dev/null || fail "未找到命令: $command"
done
table_pattern='^[[:space:]]*table[[:space:]]*[{][[:space:]]*(#.*)?$'
table_count=$(awk -v pattern="$table_pattern" '$0 ~ pattern { n++ } END { print n+0 }' "$sniproxy_conf")
[[ $table_count == 1 ]] || fail "仅支持本项目的单个默认 table { ... } 配置。"
[[ $(awk '/^[[:space:]]*table([[:space:]]|\{)/ { n++ } END { print n+0 }' "$sniproxy_conf") == 1 ]] \
    || fail "检测到多个 table，请手动选择需要更新的转发表。"

work_dir=$(mktemp -d)
applied=0
cleanup() {
    local result=$?
    if (( result != 0 && applied )); then
        echo "[错误] 更新失败，正在恢复备份。" >&2
        cat "$dnsmasq_backup" > "$dnsmasq_conf" || echo "[错误] 请手动恢复 $dnsmasq_backup" >&2
        cat "$sniproxy_backup" > "$sniproxy_conf" || echo "[错误] 请手动恢复 $sniproxy_backup" >&2
        systemctl restart sniproxy dnsmasq || echo "[错误] 配置恢复后服务重启失败，请检查 systemctl status。" >&2
    fi
    rm -rf -- "$work_dir"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

awk '1' "$dnsmasq_conf" > "$work_dir/dnsmasq.conf"
awk '1' "$sniproxy_conf" > "$work_dir/sniproxy.conf"
: > "$work_dir/sni-rules"
for domain in "${domains[@]}"; do
    dns_rule="address=/$domain/$proxy_ip"
    if ! grep -Fxq "$dns_rule" "$work_dir/dnsmasq.conf"; then
        if grep -Fq "address=/$domain/" "$work_dir/dnsmasq.conf"; then
            fail "$domain 已有不同的 DNS 地址映射，请先确认目标 IP。"
        fi
        printf '%s\n' "$dns_rule" >> "$work_dir/dnsmasq.conf"
    fi
    # Dnsmasq 2.86+ 会将未匹配 IPv4 的查询转发上游；防止 AAAA/HTTPS 记录绕过代理。
    if ! grep -Fxq "local=/$domain/" "$work_dir/dnsmasq.conf"; then
        printf 'local=/%s/\n' "$domain" >> "$work_dir/dnsmasq.conf"
    fi
    escaped_domain=${domain//./\\.}
    sni_pattern="(^|\\.)${escaped_domain}\$"
    legacy_pattern=".*${escaped_domain}\$"
    if ! SNI_CURRENT="$sni_pattern" SNI_LEGACY="$legacy_pattern" awk \
        '($1 == ENVIRON["SNI_CURRENT"] || $1 == ENVIRON["SNI_LEGACY"]) && $2 == "*" { found=1 } END { exit !found }' \
        "$work_dir/sniproxy.conf" "$work_dir/sni-rules"; then
        printf '    %s *\n' "$sni_pattern" >> "$work_dir/sni-rules"
    fi
done
awk -v pattern="$table_pattern" -v rules="$work_dir/sni-rules" '
    { print }
    $0 ~ pattern {
        while ((getline rule < rules) > 0) print rule
        close(rules)
    }
' "$work_dir/sniproxy.conf" > "$work_dir/sniproxy-new.conf"

if cmp -s "$dnsmasq_conf" "$work_dir/dnsmasq.conf" && cmp -s "$sniproxy_conf" "$work_dir/sniproxy-new.conf"; then
    echo "[完成] 规则已存在，无需修改或重启。"
    exit 0
fi
dnsmasq --test --conf-file="$work_dir/dnsmasq.conf"
backup_suffix=".backup.$(date +%Y%m%d_%H%M%S).$$"
# 隐藏备份，避免 Dnsmasq 的 conf-dir 将备份再次当作配置加载。
dnsmasq_backup="$(dirname "$dnsmasq_conf")/.$(basename "$dnsmasq_conf")${backup_suffix}"
sniproxy_backup="$(dirname "$sniproxy_conf")/.$(basename "$sniproxy_conf")${backup_suffix}"
cp -p "$dnsmasq_conf" "$dnsmasq_backup"
cp -p "$sniproxy_conf" "$sniproxy_backup"
echo "[备份] $dnsmasq_backup"
echo "[备份] $sniproxy_backup"
applied=1
cat "$work_dir/dnsmasq.conf" > "$dnsmasq_conf"
cat "$work_dir/sniproxy-new.conf" > "$sniproxy_conf"
dnsmasq --test
for service in sniproxy dnsmasq; do
    systemctl restart "$service"
    systemctl is-active --quiet "$service"
done
echo "[完成] 已同步 DNS 和 SNI 规则，目标 IP: $proxy_ip"
