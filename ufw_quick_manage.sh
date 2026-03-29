#!/bin/bash

# UFW快速管理脚本
# 用于快速添加或删除IP访问规则

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 安装UFW（如果未安装）
install_ufw_if_needed() {
    if command -v ufw >/dev/null 2>&1; then
        log_info "UFW已安装"
        return 0
    fi
    
    log_info "UFW未安装，正在自动安装..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y ufw
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ufw
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ufw
    else
        log_error "无法确定包管理器，请手动安装UFW: apt install ufw 或 yum install ufw"
        exit 1
    fi
    log_success "UFW安装完成"
}

# 显示帮助信息
show_help() {
    echo -e "${GREEN}UFW快速管理脚本使用说明：${NC}"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项："
    echo "  init         - 初始化UFW防火墙（首次使用）"
    echo "  add IP       - 添加IP访问53/80/443端口的权限"
    echo "  remove IP    - 移除IP的访问权限"
    echo "  open PORT    - 开放端口（允许任意IP连接）"
    echo "  close PORT   - 关闭已开放的端口"
    echo "  list         - 显示当前防火墙规则"
    echo "  status       - 显示UFW状态"
    echo "  backup       - 备份当前规则"
    echo "  help         - 显示此帮助信息"
    echo
    echo "示例："
    echo "  $0 init                    # 首次初始化"
    echo "  $0 add 192.168.1.100      # 添加IP权限"
    echo "  $0 remove 192.168.1.100   # 移除IP权限"
    echo "  $0 open 8080              # 开放8080端口"
    echo "  $0 open 8080/udp          # 开放8080 UDP端口"
    echo "  $0 close 8080             # 关闭8080端口"
    echo "  $0 list                   # 查看规则"
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
        return 0
    else
        return 1
    fi
}

# 检测SSH端口
detect_ssh_port() {
    local ssh_port=""
    
    # 方法1: 使用ss命令检测
    if command -v ss >/dev/null 2>&1; then
        ssh_port=$(ss -tunpl 2>/dev/null | grep -E "sshd|ssh" | grep LISTEN | awk '{print $5}' | cut -d':' -f2 | head -1 2>/dev/null)
    fi
    
    # 方法2: 如果ss失败，尝试netstat
    if [[ -z "$ssh_port" ]] && command -v netstat >/dev/null 2>&1; then
        ssh_port=$(netstat -tlnp 2>/dev/null | grep -E "sshd|ssh" | awk '{print $4}' | cut -d':' -f2 | head -1 2>/dev/null)
    fi
    
    # 方法3: 检查配置文件
    if [[ -z "$ssh_port" ]] && [[ -f /etc/ssh/sshd_config ]]; then
        ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 2>/dev/null)
    fi
    
    # 方法4: 检查当前SSH连接
    if [[ -z "$ssh_port" ]] && [[ -n "$SSH_CLIENT" ]]; then
        ssh_port=$(echo $SSH_CLIENT | awk '{print $3}' 2>/dev/null)
    fi
    
    # 验证检测到的端口号
    if [[ -n "$ssh_port" ]] && [[ "$ssh_port" =~ ^[0-9]+$ ]] && [[ "$ssh_port" -ge 1 ]] && [[ "$ssh_port" -le 65535 ]]; then
        log_info "自动检测到SSH端口：$ssh_port" >&2
        echo $ssh_port
        return 0
    fi
    
    # 如果无法自动检测，提示手动输入
    log_warning "无法自动检测SSH端口" >&2
    echo >&2
    echo -e "${YELLOW}请手动输入当前SSH端口号：${NC}" >&2
    echo "（可以通过以下命令查看SSH端口：）" >&2
    echo "  ss -tunpl | grep ssh" >&2
    echo "  netstat -tlnp | grep ssh" >&2
    echo "  grep Port /etc/ssh/sshd_config" >&2
    echo "  echo \$SSH_CLIENT" >&2
    echo >&2
    read -p "SSH端口号 (直接回车使用默认的22): " ssh_port
    
    # 如果用户直接回车，使用默认端口22
    if [[ -z "$ssh_port" ]]; then
        ssh_port="22"
        log_info "使用默认SSH端口：22" >&2
    fi
    
    # 验证输入的端口号
    if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || [[ "$ssh_port" -lt 1 ]] || [[ "$ssh_port" -gt 65535 ]]; then
        log_error "无效的端口号：$ssh_port" >&2
        return 1
    fi
    
    log_info "将使用端口：$ssh_port" >&2
    echo $ssh_port
}

# 添加IP访问规则
add_ip_rule() {
    local ip=$1
    
    if ! validate_ip "$ip"; then
        log_error "IP地址格式不正确：$ip"
        return 1
    fi
    
    log_info "为 $ip 添加访问规则..."
    
    # 添加DNS端口规则
    ufw allow from $ip to any port 53
    log_success "已添加DNS端口(53)访问规则"
    
    # 添加HTTP端口规则
    ufw allow from $ip to any port 80
    log_success "已添加HTTP端口(80)访问规则"
    
    # 添加HTTPS端口规则
    ufw allow from $ip to any port 443
    log_success "已添加HTTPS端口(443)访问规则"
    
    log_success "已为 $ip 添加所有访问规则"
}

# 验证端口号格式（支持 port 或 port/proto）
validate_port() {
    local port_input=$1
    local port_num="${port_input%%/*}"
    local proto="${port_input#*/}"

    # Extract port number (strip protocol if present)
    if [[ "$port_input" == */* ]]; then
        if [[ "$proto" != "tcp" && "$proto" != "udp" ]]; then
            log_error "无效的协议：$proto（仅支持 tcp 或 udp）"
            return 1
        fi
    fi

    if [[ ! "$port_num" =~ ^[0-9]+$ ]] || [[ "$port_num" -lt 1 ]] || [[ "$port_num" -gt 65535 ]]; then
        log_error "无效的端口号：$port_num（范围：1-65535）"
        return 1
    fi

    return 0
}

# 开放端口（允许任意IP连接）
open_port() {
    local port=$1

    if ! validate_port "$port"; then
        return 1
    fi

    log_info "开放端口 $port（允许任意IP连接）..."
    ufw allow $port
    log_success "端口 $port 已开放"
}

# 关闭已开放的端口
close_port() {
    local port=$1

    if ! validate_port "$port"; then
        return 1
    fi

    log_info "关闭端口 $port..."
    ufw delete allow $port 2>/dev/null && log_success "端口 $port 已关闭" || log_warning "端口 $port 的开放规则不存在或已删除"
}

# 移除IP访问规则
remove_ip_rule() {
    local ip=$1
    
    if ! validate_ip "$ip"; then
        log_error "IP地址格式不正确：$ip"
        return 1
    fi
    
    log_info "移除 $ip 的访问规则..."
    
    # 移除规则（需要确认每一条）
    ufw delete allow from $ip to any port 53 2>/dev/null || log_warning "DNS端口(53)规则不存在或已删除"
    ufw delete allow from $ip to any port 80 2>/dev/null || log_warning "HTTP端口(80)规则不存在或已删除"
    ufw delete allow from $ip to any port 443 2>/dev/null || log_warning "HTTPS端口(443)规则不存在或已删除"
    
    log_success "已移除 $ip 的访问规则"
}

# 显示当前规则
show_rules() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  当前UFW防火墙规则${NC}"
    echo -e "${BLUE}================================${NC}"
    ufw status numbered
    echo
}

# 显示UFW状态
show_status() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  UFW防火墙详细状态${NC}"
    echo -e "${BLUE}================================${NC}"
    ufw status verbose
    echo
}

# 备份规则
backup_rules() {
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_file="/root/ufw_backup_$backup_date.txt"
    
    log_info "正在备份UFW规则..."
    ufw status numbered > "$backup_file"
    log_success "规则已备份到：$backup_file"
}

# 初始化UFW配置
init_ufw() {
    log_info "开始初始化UFW防火墙配置..."
    
    # 安装UFW
    install_ufw_if_needed
    
    # 检查UFW状态
    if ufw status | grep -q "Status: active"; then
        echo
        echo -e "${YELLOW}UFW已处于激活状态，是否要重置现有规则？${NC}"
        read -p "输入 y 重置，输入 n 保留现有规则: " reset_choice
        if [[ $reset_choice =~ ^[Yy]$ ]]; then
            log_info "重置现有规则..."
            ufw --force reset
        fi
    fi
    
    # 获取允许访问的IP
    echo
    echo -e "${YELLOW}请输入允许访问53/80/443端口的IP地址：${NC}"
    read -p "IP地址 (例如: 192.168.1.100 或 192.168.1.0/24): " allowed_ip
    
    if ! validate_ip "$allowed_ip"; then
        log_error "IP地址格式不正确"
        return 1
    fi
    
    # 配置基础规则
    log_info "配置基础防火墙规则..."
    ufw default deny incoming
    ufw default allow outgoing
    
    # 检测并保持SSH访问
    log_info "检测当前SSH端口..."
    ssh_port=$(detect_ssh_port)
    
    if [[ $? -ne 0 ]]; then
        log_error "SSH端口检测失败，初始化中止"
        return 1
    fi
    
    # 验证ssh_port不为空且为有效端口号
    if [[ -n "$ssh_port" ]] && [[ "$ssh_port" =~ ^[0-9]+$ ]] && [[ "$ssh_port" -ge 1 ]] && [[ "$ssh_port" -le 65535 ]]; then
        ufw allow $ssh_port/tcp
        log_success "已保留SSH端口 $ssh_port 的访问权限"
    else
        log_error "SSH端口无效：'$ssh_port'，初始化中止"
        return 1
    fi
    
    # 允许本地回环
    ufw allow in on lo
    ufw allow out on lo
    
    # 添加指定IP的访问权限
    add_ip_rule "$allowed_ip"
    
    # 启用UFW
    log_info "启用UFW防火墙..."
    ufw --force enable
    log_success "UFW防火墙已启用"
    
    # 显示最终状态
    show_status
    
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  UFW防火墙初始化完成！${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "${YELLOW}提示：${NC}"
    echo "- 只有 $allowed_ip 可以访问53/80/443端口"
    echo "- SSH端口 $ssh_port 对所有IP开放（安全考虑）"
    echo "- 使用 '$0 add <IP>' 添加更多允许的IP"
    echo "- 使用 '$0 list' 查看当前规则"
}

# 交互式菜单
interactive_menu() {
    while true; do
        echo
        echo -e "${GREEN}========== UFW快速管理菜单 ==========${NC}"
        echo "1. 初始化UFW防火墙"
        echo "2. 添加IP访问规则（限定IP访问53/80/443）"
        echo "3. 移除IP访问规则"
        echo "4. 开放端口（允许任意IP连接）"
        echo "5. 关闭已开放的端口"
        echo "6. 显示当前规则"
        echo "7. 显示UFW状态"
        echo "8. 备份当前规则"
        echo "9. 退出"
        echo -e "${GREEN}====================================${NC}"

        read -p "请选择操作 (1-9): " choice

        case $choice in
            1)
                init_ufw
                ;;
            2)
                read -p "请输入要添加的IP地址: " ip
                add_ip_rule "$ip"
                ;;
            3)
                read -p "请输入要移除的IP地址: " ip
                remove_ip_rule "$ip"
                ;;
            4)
                echo -e "${YELLOW}支持格式：端口号(如 8080)、端口/协议(如 8080/tcp、53/udp)${NC}"
                read -p "请输入要开放的端口: " port
                open_port "$port"
                ;;
            5)
                echo -e "${YELLOW}支持格式：端口号(如 8080)、端口/协议(如 8080/tcp、53/udp)${NC}"
                read -p "请输入要关闭的端口: " port
                close_port "$port"
                ;;
            6)
                show_rules
                ;;
            7)
                show_status
                ;;
            8)
                backup_rules
                ;;
            9)
                log_info "退出程序"
                exit 0
                ;;
            *)
                log_warning "无效选择，请输入1-9"
                ;;
        esac
    done
}

# 主函数
main() {
    check_root
    
    case "${1:-}" in
        init)
            init_ufw
            ;;
        add)
            install_ufw_if_needed
            if [[ -z "${2:-}" ]]; then
                log_error "请提供IP地址"
                echo "用法: $0 add <IP地址>"
                exit 1
            fi
            add_ip_rule "$2"
            ;;
        remove)
            install_ufw_if_needed
            if [[ -z "${2:-}" ]]; then
                log_error "请提供IP地址"
                echo "用法: $0 remove <IP地址>"
                exit 1
            fi
            remove_ip_rule "$2"
            ;;
        open)
            install_ufw_if_needed
            if [[ -z "${2:-}" ]]; then
                log_error "请提供端口号"
                echo "用法: $0 open <端口号>  (例如: 8080, 8080/tcp, 53/udp)"
                exit 1
            fi
            open_port "$2"
            ;;
        close)
            install_ufw_if_needed
            if [[ -z "${2:-}" ]]; then
                log_error "请提供端口号"
                echo "用法: $0 close <端口号>  (例如: 8080, 8080/tcp, 53/udp)"
                exit 1
            fi
            close_port "$2"
            ;;
        list)
            install_ufw_if_needed
            show_rules
            ;;
        status)
            install_ufw_if_needed
            show_status
            ;;
        backup)
            install_ufw_if_needed
            backup_rules
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            # 没有参数时启动交互式菜单
            interactive_menu
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@" 