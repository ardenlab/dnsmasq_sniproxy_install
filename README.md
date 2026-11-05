# Dnsmasq SNIproxy One-click Install

### 脚本概述：

* 原理简述：利用[Dnsmasq](http://thekelleys.org.uk/dnsmasq/doc.html)的DNS功能，将特定网站的DNS解析重定向到[SNIproxy](https://github.com/dlundquist/sniproxy)反向代理。

* 用途：让访问流媒体受限的VPS突破限制，前提是要有一个能流媒体的VPS。

* 特性：脚本默认解锁`Netflix Hulu HBO`[等](https://github.com/ardenlab/dnsmasq_sniproxy_install/blob/master/proxy-domains.txt)，如需增删流媒体域名请编辑文件`/etc/dnsmasq.d/custom_netflix.conf`和`/etc/sniproxy.conf`

* 脚本支持系统：CentOS7+, Debian9+, Ubuntu18+
    * 如果脚本最后显示的IP和实际公网IP不符，请修改一下文件`/etc/sniproxy.conf`中的IP地址

### 脚本用法：

    bash dnsmasq_sniproxy.sh [-h] [-i] [-f] [-id] [-fd] [-is] [-fs] [-u] [-ud] [-us]
      -h , --help                显示帮助信息
      -i , --install             安装 Dnsmasq + SNI Proxy
      -f , --fastinstall         快速安装 Dnsmasq + SNI Proxy
      -id, --installdnsmasq      仅安装 Dnsmasq
      -fd, --installdnsmasq      快速安装 Dnsmasq
      -is, --installsniproxy     仅安装 SNI Proxy
      -fs, --fastinstallsniproxy 快速安装 SNI Proxy
      -u , --uninstall           卸载 Dnsmasq + SNI Proxy
      -ud, --undnsmasq           卸载 Dnsmasq
      -us, --unsniproxy          卸载 SNI Proxy

### 快速安装（推荐）：
``` Bash
wget --no-check-certificate -O dnsmasq_sniproxy.sh https://raw.githubusercontent.com/ardenlab/dnsmasq_sniproxy_install/master/my_dnsmasq_sniproxy.sh && bash dnsmasq_sniproxy.sh -f
```
### 配置防火墙

``` Bash
wget --no-check-certificate -O ufw_quick_manage.sh https://raw.githubusercontent.com/ardenlab/dnsmasq_sniproxy_install/master/ufw_quick_manage.sh && bash ufw_quick_manage.sh
```

### 替换dnsmasq配置文件中的ip

``` Bash
wget --no-check-certificate -O replace_resolv_ip.sh https://raw.githubusercontent.com/ardenlab/dnsmasq_sniproxy_install/master/replace_resolv_ip.sh && bash replace_resolv_ip.sh
```


### 普通安装：
``` Bash
wget --no-check-certificate -O dnsmasq_sniproxy.sh https://raw.githubusercontent.com/ardenlab/dnsmasq_sniproxy_install/master/my_dnsmasq_sniproxy.sh && bash dnsmasq_sniproxy.sh -i
```

### 卸载方法：
``` Bash
wget --no-check-certificate -O dnsmasq_sniproxy.sh https://raw.githubusercontent.com/ardenlab/dnsmasq_sniproxy_install/master/my_dnsmasq_sniproxy.sh && bash dnsmasq_sniproxy.sh -u
```

### 使用方法：
将代理主机的 DNS 地址设置为安装了 dnsmasq 的主机 IP 即可，如果遇到问题，尝试在配置文件中只保留一个 DNS 地址。

为了防止滥用，建议不要公开 IP 地址，并使用防火墙进行适当的访问限制。

### 为已部署服务器添加 Reddit

本项目推荐入口 `my_dnsmasq_sniproxy.sh` 使用 `my-proxy-domains.txt`，该文件由 `tmp/` 中的源清单经 `bash extract_domains.sh` 生成。Reddit 的源清单位于 `tmp/custom_domain.txt`，已包含下面这些域名；仅修改仓库清单不会更新服务器现有配置。

| 域名 | 覆盖范围 |
| --- | --- |
| `reddit.com` | 网站及其子域名，如 `www`、`old`、`oauth`、`gateway` |
| `redd.it` | 图片、视频、预览和短链接，如 `i.redd.it`、`v.redd.it` |
| `redditmedia.com`、`redditstatic.com` | 媒体及静态资源 |
| `redditspace.com` | 聊天相关服务 |
| `reddit.app.link`、`redditmail.com`、`reddituploads.com` | App 链接、邮件链接和上传相关域名 |
| `redditblog.com`、`reddithelp.com`、`redditinc.com`、`redditstatus.com` | 博客、帮助、公司和状态页面 |
| `reddit.map.fastly.net` | Reddit 的 CDN 域名，包含其子域名 |
| `reddituploads.com.cdn-cf.behance.net`、`reddituploads.com.cdn-cf.dropbox.com` | 保留原清单中的兼容规则 |

域名范围核对自 [v2fly 的 Reddit 清单](https://github.com/v2fly/domain-list-community/blob/master/data/reddit) 和 [blackmatrix7 的 Reddit 清单](https://github.com/blackmatrix7/ios_rule_script/blob/master/rule/Clash/Reddit/Reddit.list)。这些是社区维护的分流规则，兼容规则不代表当前页面一定会请求这些域名。

将本地 `add_proxy_domains.sh` 复制到已部署的 Linux 服务器，或在服务器的项目目录中执行。把 `203.0.113.10` 换成 **SNI 转发服务器的公网 IPv4**：

```bash
# 先预览将要生成的规则
bash add_proxy_domains.sh --dry-run 203.0.113.10

# 不传域名时，默认添加上表中的 15 个 Reddit 域名
sudo bash add_proxy_domains.sh 203.0.113.10

# 以后也可以指定其他域名，根域名会同时覆盖子域名
sudo bash add_proxy_domains.sh 203.0.113.10 example.com example.net
```

脚本针对本项目默认的同机部署，同步更新 `/etc/dnsmasq.d/custom_netflix.conf` 和 `/etc/sniproxy.conf`，保留已有规则并自动备份、检查 DNS 配置、重启两个服务；失败时恢复备份，重复执行不会重复添加相同规则。SNI 新规则使用 `(^|\.)域名$`，同时匹配域名本身和子域名，并识别安装器生成的旧格式。DNS 与 SNI 分别部署在两台机器时，需在各自服务器上更新对应配置。

脚本还为所选域名添加 `local=/域名/`，防止 Dnsmasq 2.86+ 将 AAAA、HTTPS 等查询继续发往上游，使客户端绕过 IPv4 代理。该行为参考 [Dnsmasq 官方手册的 `--address` 说明](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)。备份使用隐藏文件名，避免被 `conf-dir` 自动加载。

从使用该 DNS 的客户端检查解析，下面的 `203.0.113.20` 应替换为 **Dnsmasq 服务器 IP**：

```bash
dig @203.0.113.20 www.reddit.com A +short
dig @203.0.113.20 i.redd.it A +short
dig @203.0.113.20 v.redd.it A +short
dig @203.0.113.20 matrix.redditspace.com A +short
```

上述结果应指向 SNI 服务器 IP。浏览器需使用这台 Dnsmasq 解析；若浏览器自带的安全 DNS 绕过了它，分流规则不会生效。HTTPS 转发可用 `curl --http1.1 -I --resolve www.reddit.com:443:203.0.113.10 https://www.reddit.com/` 测试，它保留原域名用于 SNI 和证书校验；HTTP 状态还取决于 Reddit 对出口 IP 的访问策略。

安装器仍从 GitHub 下载清单，因此尚未推送的本地修改不会被 README 中的在线安装命令获取；现有服务器直接使用上述增量脚本即可。

### 调试排错：
- 确认 sniproxy 运行状态

  查看sniproxy状态：`systemctl status sniproxy`

  如果 sniproxy 未运行，请检查是否有其他服务占用了 80、443 端口，导致端口冲突。可以使用 `netstat -tlunp | grep 443` 命令查看端口监听情况。

- 确认防火墙设置

  确保防火墙已放行 53、80、443 端口。在调试时，可以关闭防火墙： `systemctl stop firewalld.service`

  对于阿里云、腾讯云、AWS 等云服务提供商，安全组的端口设置同样需要放行。
  
  使用其他服务器进行测试： `telnet 1.2.3.4 53` 

- 域名解析测试

  在配置完 DNS 后，进行域名解析测试：`nslookup netflix.com` 检查 IP 是否为 Netflix 代理服务器的 IP。
  如果系统中没有 nslookup 命令，可以在 CentOS 上安装：`yum install -y bind-utils` 在 Ubuntu 和 Debian 上安装：`apt-get -y install dnsutils`

- 解决 systemd-resolve 服务占用 53 端口的问题
  
  使用 `netstat -tlunp | grep 53` 发现 53 端口被 systemd-resolved 占用
  修改`/etc/systemd/resolved.conf`文件：
  ```
  [Resolve]
  DNS=8.8.8.8 1.1.1.1 #取消注释，增加dns
  #FallbackDNS=
  #Domains=
  #LLMNR=no
  #MulticastDNS=no
  #DNSSEC=no
  #Cache=yes
  DNSStubListener=no  #取消注释，把yes改为no
  ```
  然后执行以下命令，并重启 systemd-resolved 服务：
  ```
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved.service
  ```
