#!/usr/bin/env bash
# ============================================================
# NYKI VPS IP 检测工具
# Version: 2.1.0
# Author: nyki4
# Website: https://nyki.cc
#
# 特性：
#   - 中文交互面板
#   - IPv4 / IPv6 检测
#   - IP 归属地查询
#   - IP 基础信息查询
#   - 流媒体网站连通性检测
#   - 网络诊断与路由追踪
#   - DNS 解析检测
#   - 系统信息
#   - 快速网络检测
#   - 全局隐藏 IP 模式
#
# 不生成报告，不主动保存检测结果或日志。
# ============================================================
VERSION="2.1.0"
AUTHOR="nyki4"
WEBSITE="nyki.cc"
HIDE_IP=0
COLOR=0
USE_ASCII=0
PANEL_WIDTH=46
CONNECT_TIMEOUT=5
MAX_TIME=12
# -------------------- 颜色 --------------------
C_RESET=''
C_CYAN=''
C_GREEN=''
C_YELLOW=''
C_RED=''
C_BLUE=''
C_GRAY=''
C_BOLD=''
init_terminal() {
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" &&
          -z "${NO_COLOR:-}" ]]; then
        COLOR=1
        C_RESET=$'\033[0m'
        C_CYAN=$'\033[36m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_RED=$'\033[31m'
        C_BLUE=$'\033[34m'
        C_GRAY=$'\033[90m'
        C_BOLD=$'\033[1m'
    fi
    if [[ ! -t 1 || ! -t 0 ]]; then
        COLOR=0
        C_RESET=''
        C_CYAN=''
        C_GREEN=''
        C_YELLOW=''
        C_RED=''
        C_BLUE=''
        C_GRAY=''
        C_BOLD=''
    fi
    if ! locale charmap 2>/dev/null | grep -qi 'UTF-8'; then
        USE_ASCII=1
    fi
    local term_width
    term_width=$(tput cols 2>/dev/null || printf '80')
    if [[ "$term_width" =~ ^[0-9]+$ ]] &&
       (( term_width < 52 )); then
        PANEL_WIDTH=38
    fi
}
# -------------------- 基础工具 --------------------
pause_screen() {
    printf '\n'
    if [[ -t 0 ]]; then
        read -r -p "按回车键返回主菜单..." _
    fi
}
clear_screen() {
    if [[ -t 1 && -t 0 ]]; then
        printf '\033[2J\033[H'
    fi
}
print_line() {
    local char="${1:--}"
    local width="$PANEL_WIDTH"
    local i
    printf '%s' "$C_CYAN"
    for ((i = 0; i < width; i++)); do
        printf '%s' "$char"
    done
    printf '%s\n' "$C_RESET"
}
print_title() {
    local title="$1"
    printf '\n'
    print_line '='
    printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
    print_line '='
}
print_status() {
    local label="$1"
    local value="$2"
    local status="${3:-info}"
    case "$status" in
        success) value="${C_GREEN}${value}${C_RESET}" ;;
        warning) value="${C_YELLOW}${value}${C_RESET}" ;;
        error)   value="${C_RED}${value}${C_RESET}" ;;
        *)       value="${C_CYAN}${value}${C_RESET}" ;;
    esac
    printf '  %-12s %b\n' "$label" "$value"
}
show_error() {
    printf '%s[错误]%s %s\n' "$C_RED" "$C_RESET" "$1"
}
show_warning() {
    printf '%s[提示]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
}
show_success() {
    printf '%s[成功]%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}
# -------------------- IP 脱敏 --------------------
mask_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        if (( HIDE_IP )); then
            printf '%s' "$ip" |
                sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$/\1.***/'
        else
            printf '%s' "$ip"
        fi
    else
        printf '%s' "$ip"
    fi
}
mask_ipv6() {
    local ip="$1"
    if (( ! HIDE_IP )); then
        printf '%s' "$ip"
        return
    fi
    # IPv6 地址通常含有冒号；隐藏中间部分，避免泄露完整地址。
    if [[ "$ip" == *:* ]]; then
        printf '%s' "$ip" |
            sed -E 's/^([^:]+):([^:]+):.*/\1:\2:****:****/'
    else
        printf '%s' "$ip"
    fi
}
mask_ip() {
    local value="$1"
    local result="$value"
    if (( ! HIDE_IP )); then
        printf '%s' "$value"
        return
    fi
    # IPv4 地址脱敏
    result=$(printf '%s' "$result" |
        sed -E \
        's/([0-9]{1,3}\.){3}[0-9]{1,3}/&/g')
    local ipv4
    local ipv6
    local token
    # 逐个处理文本中的 IPv4 地址
    while IFS= read -r ipv4; do
        [[ -z "$ipv4" ]] && continue
        token=$(mask_ipv4 "$ipv4")
        result="${result//"$ipv4"/"$token"}"
    done < <(
        printf '%s\n' "$result" |
        grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' |
        sort -u
    )
    # 处理文本中的 IPv6 地址。
    # 不保证能识别所有带端口、区域标识符或特殊格式的 IPv6。
    while IFS= read -r ipv6; do
        [[ -z "$ipv6" ]] && continue
        token=$(mask_ipv6 "$ipv6")
        result="${result//"$ipv6"/"$token"}"
    done < <(
        printf '%s\n' "$result" |
        grep -oE '([0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:]{0,}' |
        sort -u
    )
    printf '%s' "$result"
}
# 分享时也应考虑主机名、ASN 和运营商信息可能具有识别性。
# 本工具只将主机名和 ASN 作为独立字段处理，不承诺隐藏所有间接识别信息。
display_ip() {
    mask_ip "$1"
}
# -------------------- 网络请求 --------------------
http_get() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            "$url" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T "$MAX_TIME" -O - "$url" 2>/dev/null
    else
        return 1
    fi
}
check_dependencies() {
    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1; then
        show_error "缺少 curl 或 wget，无法进行网络检测。"
        printf 'Debian/Ubuntu: apt-get install curl\n'
        printf 'Alpine Linux: apk add curl\n'
        return 1
    fi
    return 0
}
get_public_ipv4() {
    local ip
    ip=$(http_get "https://api.ipify.org") || return 1
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        printf '%s' "$ip"
        return 0
    fi
    return 1
}
get_public_ipv6() {
    local ip
    if command -v curl >/dev/null 2>&1; then
        ip=$(curl -6 -fsSL \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://api6.ipify.org 2>/dev/null) || return 1
    else
        return 1
    fi
    if [[ "$ip" == *:* ]]; then
        printf '%s' "$ip"
        return 0
    fi
    return 1
}
# -------------------- 面板 --------------------
show_banner() {
    clear_screen
    printf '%s\n' "$C_CYAN"
    if (( USE_ASCII )); then
        printf '+--------------------------------------------+\n'
        printf '|           NYKI VPS IP CHECK                |\n'
        printf '|           VPS NETWORK TOOL                 |\n'
        printf '+--------------------------------------------+\n'
    else
        printf '╭──────────────────────────────────────────────╮\n'
        printf '│                                              │\n'
        printf '│          NYKI VPS IP 检测工具                │\n'
        printf '│          VPS NETWORK DIAGNOSTICS             │\n'
        printf '│                                              │\n'
        printf '╰──────────────────────────────────────────────╯\n'
    fi
    printf '%s\n' "$C_RESET"
    printf '  版本    %s\n' "$VERSION"
    printf '  作者    %s\n' "$AUTHOR"
    printf '  网站    %s\n' "$WEBSITE"
    printf '\n'
    print_line '-'
    printf '  [01]  全面检测\n'
    printf '  [02]  IPv4 地址检测\n'
    printf '  [03]  IPv6 地址检测\n'
    printf '  [04]  IP 归属地查询\n'
    printf '  [05]  IP 基础信息\n'
    printf '  [06]  流媒体网站连通性\n'
    printf '  [07]  网络诊断与路由追踪\n'
    printf '  [08]  DNS 解析检测\n'
    printf '  [09]  系统信息\n'
    printf '  [10]  快速网络检测\n'
    printf '\n'
    print_line '-'
    if (( HIDE_IP )); then
        printf '  隐藏 IP    %s[开启]%s\n' "$C_GREEN" "$C_RESET"
    else
        printf '  隐藏 IP    %s[关闭]%s\n' "$C_YELLOW" "$C_RESET"
    fi
    printf '\n'
    print_line '-'
    printf '  [11]  切换隐藏 IP 模式\n'
    printf '  [00]  退出工具\n'
    printf '\n'
}
# -------------------- IPv4 --------------------
check_ipv4() {
    print_title "IPv4 地址检测"
    local ip
    if ip=$(get_public_ipv4); then
        print_status "检测状态" "成功" success
        print_status "公网 IPv4" "$(display_ip "$ip")" success
    else
        print_status "检测状态" "失败或不可用" error
        show_warning "服务器可能没有 IPv4 出口，或查询服务暂时不可用。"
    fi
    pause_screen
}
# -------------------- IPv6 --------------------
check_ipv6() {
    print_title "IPv6 地址检测"
    if ! command -v curl >/dev/null 2>&1; then
        show_error "IPv6 检测需要 curl。"
        pause_screen
        return
    fi
    local ip
    if ip=$(get_public_ipv6); then
        print_status "检测状态" "成功" success
        print_status "公网 IPv6" "$(display_ip "$ip")" success
    else
        print_status "检测状态" "不可用" warning
        show_warning "可能未配置 IPv6、无 IPv6 出口，或查询服务暂时不可用。"
    fi
    pause_screen
}
# -------------------- IP 归属地 --------------------
lookup_ip_info() {
    print_title "IP 归属地查询"
    local ip
    if ! ip=$(get_public_ipv4); then
        show_error "无法获取公网 IPv4，暂时无法查询。"
        pause_screen
        return
    fi
    printf '  查询中，请稍候……\n'
    # 使用 HTTPS 查询服务；真实 IP 会发送给第三方 API。
    local data
    data=$(http_get "https://ipwho.is/${ip}") || {
        show_error "查询服务暂时不可用。"
        pause_screen
        return
    }
    if command -v python3 >/dev/null 2>&1; then
        local country region city isp
        country=$(printf '%s' "$data" | python3 -c \
            'import sys,json; d=json.load(sys.stdin); print(d.get("country") or "未知")' 2>/dev/null)
        region=$(printf '%s' "$data" | python3 -c \
            'import sys,json; d=json.load(sys.stdin); print(d.get("region") or "未知")' 2>/dev/null)
        city=$(printf '%s' "$data" | python3 -c \
            'import sys,json; d=json.load(sys.stdin); print(d.get("city") or "未知")' 2>/dev/null)
        isp=$(printf '%s' "$data" | python3 -c \
            'import sys,json; d=json.load(sys.stdin); print((d.get("connection") or {}).get("isp") or "未知")' 2>/dev/null)
        print_status "公网 IPv4" "$(display_ip "$ip")"
        print_status "国家/地区" "${country:-未知}"
        print_status "州/省" "${region:-未知}"
        print_status "城市" "${city:-未知}"
        print_status "运营商" "${isp:-未知}"
    else
        print_status "公网 IPv4" "$(display_ip "$ip")"
        show_warning "安装 python3 后可显示结构化归属地信息。"
    fi
    pause_screen
}
# -------------------- IP 基础信息 --------------------
ip_basic_info() {
    print_title "IP 基础信息"
    local ip
    if ! ip=$(get_public_ipv4); then
        show_error "无法获取公网 IPv4。"
        pause_screen
        return
    fi
    local data
    data=$(http_get "https://ipwho.is/${ip}") || {
        show_error "查询服务暂时不可用。"
        pause_screen
        return
    }
    if ! command -v python3 >/dev/null 2>&1; then
        show_warning "该功能需要 python3 解析查询结果。"
        pause_screen
        return
    fi
    local country city isp org asn
    country=$(printf '%s' "$data" | python3 -c \
        'import sys,json; print(json.load(sys.stdin).get("country") or "未知")' 2>/dev/null)
    city=$(printf '%s' "$data" | python3 -c \
        'import sys,json; print(json.load(sys.stdin).get("city") or "未知")' 2>/dev/null)
    isp=$(printf '%s' "$data" | python3 -c \
        'import sys,json; print((json.load(sys.stdin).get("connection") or {}).get("isp") or "未知")' 2>/dev/null)
    org=$(printf '%s' "$data" | python3 -c \
        'import sys,json; print((json.load(sys.stdin).get("connection") or {}).get("org") or "未知")' 2>/dev/null)
    asn=$(printf '%s' "$data" | python3 -c \
        'import sys,json; print((json.load(sys.stdin).get("connection") or {}).get("asn") or "未知")' 2>/dev/null)
    print_status "公网 IPv4" "$(display_ip "$ip")"
    print_status "国家/地区" "${country:-未知}"
    print_status "城市" "${city:-未知}"
    print_status "运营商" "${isp:-未知}"
    print_status "组织" "${org:-未知}"
    if (( HIDE_IP )); then
        print_status "ASN 编号" "已隐藏"
    else
        print_status "ASN 编号" "${asn:-未知}"
    fi
    show_warning "此处显示的是基础网络信息，不代表 IP 风险评分或黑名单检测。"
    pause_screen
}
# -------------------- 流媒体连通性 --------------------
check_streaming() {
    print_title "流媒体网站连通性"
    local urls=(
        "Netflix|https://www.netflix.com"
        "YouTube|https://www.youtube.com"
        "Disney+|https://www.disneyplus.com"
        "OpenAI|https://chatgpt.com"
        "Google|https://www.google.com"
    )
    local item name url code
    for item in "${urls[@]}"; do
        name="${item%%|*}"
        url="${item#*|}"
        if command -v curl >/dev/null 2>&1; then
            code=$(curl -L -s -o /dev/null \
                --connect-timeout "$CONNECT_TIMEOUT" \
                --max-time "$MAX_TIME" \
                -w '%{http_code}' "$url" 2>/dev/null)
        else
            code=""
        fi
        if [[ "$code" =~ ^[0-9]{3}$ ]] &&
           (( 10#$code >= 200 && 10#$code < 500 )); then
            print_status "$name" "HTTP $code" success
        elif [[ "$code" =~ ^[0-9]{3}$ ]]; then
            print_status "$name" "HTTP $code" warning
        else
            print_status "$name" "连接失败或超时" error
        fi
    done
    show_warning "这里只测试网站 HTTP 连通性，不代表流媒体地区解锁结果。"
    pause_screen
}
# -------------------- 网络诊断 --------------------
network_diagnostics() {
    print_title "网络诊断与路由追踪"
    local ip
    if ip=$(get_public_ipv4); then
        print_status "公网 IPv4" "$(display_ip "$ip")" success
    else
        print_status "公网 IPv4" "不可用" warning
    fi
    local start end elapsed
    start=$(date +%s)
    if http_get "https://www.google.com" >/dev/null; then
        end=$(date +%s)
        elapsed=$((end - start))
        print_status "HTTPS 连通性" "成功" success
        print_status "请求耗时" "${elapsed} 秒"
    else
        print_status "HTTPS 连通性" "失败或超时" error
    fi
    printf '\n'
    printf '  路由追踪工具：\n'
    local target="1.1.1.1"
    if (( HIDE_IP )); then
        show_warning "隐藏 IP 模式已开启，跳过详细路由节点输出，避免泄露中间节点地址。"
    elif command -v traceroute >/dev/null 2>&1; then
        printf '  目标：%s\n' "$target"
        traceroute -m 5 -w 1 "$target" 2>&1 | head -n 8
    elif command -v tracepath >/dev/null 2>&1; then
        printf '  目标：%s\n' "$target"
        tracepath -m 5 "$target" 2>&1 | head -n 8
    else
        show_warning "未安装 traceroute 或 tracepath，跳过路由追踪。"
    fi
    pause_screen
}
# -------------------- DNS --------------------
dns_check() {
    print_title "DNS 解析检测"
    local domains=(
        "google.com"
        "cloudflare.com"
        "github.com"
    )
    local domain result
    for domain in "${domains[@]}"; do
        if command -v getent >/dev/null 2>&1; then
            result=$(getent ahosts "$domain" 2>/dev/null | head -n 1)
        elif command -v nslookup >/dev/null 2>&1; then
            result=$(nslookup "$domain" 2>/dev/null |
                awk '/^Address: / {print $2; exit}')
        else
            show_warning "缺少 getent 或 nslookup，无法检测 DNS。"
            break
        fi
        if [[ -n "$result" ]]; then
            if (( HIDE_IP )); then
                result=$(mask_ip "$result")
            fi
            print_status "$domain" "$result" success
        else
            print_status "$domain" "解析失败" error
        fi
    done
    pause_screen
}
# -------------------- 系统信息 --------------------
system_info() {
    print_title "系统信息"
    local os kernel arch uptime_text
    if [[ -r /etc/os-release ]]; then
        os=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}")
    else
        os="Linux"
    fi
    kernel=$(uname -r 2>/dev/null || printf '未知')
    arch=$(uname -m 2>/dev/null || printf '未知')
    uptime_text=$(uptime -p 2>/dev/null || uptime 2>/dev/null || printf '未知')
    print_status "操作系统" "$os"
    print_status "内核版本" "$kernel"
    print_status "系统架构" "$arch"
    print_status "运行时间" "$uptime_text"
    if command -v free >/dev/null 2>&1; then
        local memory
        memory=$(free -h | awk '/^Mem:/ {print $3 " / " $2}')
        print_status "内存使用" "${memory:-未知}"
    fi
    if command -v df >/dev/null 2>&1; then
        local disk
        disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2}')
        print_status "根分区使用" "${disk:-未知}"
    fi
    pause_screen
}
# -------------------- 快速检测 --------------------
quick_check() {
    print_title "快速网络检测"
    local start end
    start=$(date +%s)
    local ip
    if ip=$(get_public_ipv4); then
        print_status "IPv4 出口" "$(display_ip "$ip")" success
    else
        print_status "IPv4 出口" "不可用" warning
    fi
    if command -v curl >/dev/null 2>&1 &&
       curl -4 -fsSL -o /dev/null \
           --connect-timeout "$CONNECT_TIMEOUT" \
           --max-time "$MAX_TIME" \
           https://www.google.com 2>/dev/null; then
        print_status "IPv4 网络" "正常" success
    else
        print_status "IPv4 网络" "异常或受限" warning
    fi
    if command -v curl >/dev/null 2>&1 &&
       curl -6 -fsSL -o /dev/null \
           --connect-timeout "$CONNECT_TIMEOUT" \
           --max-time "$MAX_TIME" \
           https://www.google.com 2>/dev/null; then
        print_status "IPv6 网络" "正常" success
    else
        print_status "IPv6 网络" "不可用或受限" warning
    fi
    end=$(date +%s)
    print_status "检测耗时" "$((end - start)) 秒"
    pause_screen
}
# -------------------- 全面检测 --------------------
full_check() {
    print_title "全面检测"
    local ip4 ip6
    if ip4=$(get_public_ipv4); then
        print_status "公网 IPv4" "$(display_ip "$ip4")" success
    else
        print_status "公网 IPv4" "不可用" warning
    fi
    if ip6=$(get_public_ipv6); then
        print_status "公网 IPv6" "$(display_ip "$ip6")" success
    else
        print_status "公网 IPv6" "不可用" warning
    fi
    printf '\n'
    printf '  正在检测 HTTPS 连通性……\n'
    if http_get "https://www.google.com" >/dev/null; then
        print_status "HTTPS 网络" "正常" success
    else
        print_status "HTTPS 网络" "异常或受限" warning
    fi
    printf '\n'
    printf '  正在查询 IP 归属地……\n'
    local data
    if [[ -n "${ip4:-}" ]] &&
       data=$(http_get "https://ipwho.is/${ip4}"); then
        if command -v python3 >/dev/null 2>&1; then
            local country region isp
            country=$(printf '%s' "$data" | python3 -c \
                'import sys,json; print(json.load(sys.stdin).get("country") or "未知")' 2>/dev/null)
            region=$(printf '%s' "$data" | python3 -c \
                'import sys,json; print(json.load(sys.stdin).get("region") or "未知")' 2>/dev/null)
            isp=$(printf '%s' "$data" | python3 -c \
                'import sys,json; print((json.load(sys.stdin).get("connection") or {}).get("isp") or "未知")' 2>/dev/null)
            print_status "国家/地区" "${country:-未知}"
            print_status "州/省" "${region:-未知}"
            print_status "运营商" "${isp:-未知}"
        else
            show_warning "安装 python3 后可显示详细归属地。"
        fi
    else
        show_warning "IP 归属地查询失败。"
    fi
    printf '\n'
    show_warning "流媒体检测、DNS 解析及路由追踪可在主菜单单独运行。"
    pause_screen
}
# -------------------- 隐藏 IP 开关 --------------------
toggle_hide_ip() {
    if (( HIDE_IP )); then
        HIDE_IP=0
        show_warning "隐藏 IP 模式已关闭。"
    else
        HIDE_IP=1
        show_success "隐藏 IP 模式已开启。"
        show_warning "IP 地址、DNS 结果及部分网络信息将进行脱敏。"
        show_warning "归属地查询仍可能向第三方服务发送真实公网 IP。"
    fi
    sleep 1
}
# -------------------- 主程序 --------------------
main() {
    init_terminal
    if ! check_dependencies; then
        exit 1
    fi
    while true; do
        show_banner
        local choice
        printf '  请输入选项 [00-11]：'
        read -r choice || break
        # 允许输入 1、01、10、11、0、00
        case "$choice" in
            1|01)  full_check ;;
            2|02)  check_ipv4 ;;
            3|03)  check_ipv6 ;;
            4|04)  lookup_ip_info ;;
            5|05)  ip_basic_info ;;
            6|06)  check_streaming ;;
            7|07)  network_diagnostics ;;
            8|08)  dns_check ;;
            9|09)  system_info ;;
            10)    quick_check ;;
            11)    toggle_hide_ip ;;
            0|00)  printf '\n感谢使用 NYKI VPS IP 检测工具！\n'; break ;;
            *)     show_error "无效选项，请重新输入。"; sleep 1 ;;
        esac
    done
}
main "$@"
