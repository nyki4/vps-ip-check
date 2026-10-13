#!/usr/bin/env bash
# ============================================================
# NYKI VPS IP 检测工具
# Version : 2.3.0
# Author  : 阿晚
# Website : https://nyki.cc
# Project : github.com/nyki4/vps-ip-check
# ============================================================
VERSION="2.3.0"
AUTHOR="阿晚"
WEBSITE="nyki.cc"
PROJECT="github.com/nyki4/vps-ip-check"
HIDE_IP=0
COLOR=0
ASCII_MODE=0
PANEL_WIDTH=46
CONNECT_TIMEOUT=5
MAX_TIME=12
C_RESET=''
C_CYAN=''
C_GREEN=''
C_YELLOW=''
C_RED=''
C_BLUE=''
C_GRAY=''
C_BOLD=''
# -------------------- 初始化 --------------------
init_terminal() {
    local cols charset
    charset=$(locale charmap 2>/dev/null || true)
    case "$charset" in
        *UTF-8*|*utf8*) ASCII_MODE=0 ;;
        *) ASCII_MODE=1 ;;
    esac
    if [[ -t 1 && -t 0 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
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
    cols=$(tput cols 2>/dev/null || printf '80')
    if [[ "$cols" =~ ^[0-9]+$ ]] && (( cols < 54 )); then
        PANEL_WIDTH=38
    fi
}
clear_screen() {
    if [[ -t 0 && -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
}
pause_screen() {
    printf '\n'
    if [[ -t 0 ]]; then
        read -r -p "按回车键返回主菜单..." _
    fi
}
repeat_char() {
    local char="$1"
    local count="$2"
    local i
    for ((i = 0; i < count; i++)); do
        printf '%s' "$char"
    done
}
draw_line() {
    local char="${1:--}"
    if (( ASCII_MODE )); then
        printf '+'
        repeat_char "$char" "$((PANEL_WIDTH - 2))"
        printf '+\n'
    else
        printf '╭'
        repeat_char '─' "$((PANEL_WIDTH - 2))"
        printf '╮\n'
    fi
}
draw_bottom() {
    if (( ASCII_MODE )); then
        printf '+'
        repeat_char '-' "$((PANEL_WIDTH - 2))"
        printf '+\n'
    else
        printf '╰'
        repeat_char '─' "$((PANEL_WIDTH - 2))"
        printf '╯\n'
    fi
}
panel_title() {
    clear_screen
    printf '%s' "$C_CYAN"
    draw_line
    printf '%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
    printf '%s' "$C_CYAN"
    draw_line
    printf '%s' "$C_RESET"
}
status() {
    local label="$1"
    local value="$2"
    local type="${3:-info}"
    local color="$C_CYAN"
    case "$type" in
        success) color="$C_GREEN" ;;
        warning) color="$C_YELLOW" ;;
        error) color="$C_RED" ;;
    esac
    printf '  %-12s %b%s%b\n' "$label：" "$color" "$value" "$C_RESET"
}
info() {
    printf '  %s\n' "$1"
}
# -------------------- IP 脱敏 --------------------
mask_one_ip() {
    local address="$1"
    if (( ! HIDE_IP )); then
        printf '%s' "$address"
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$address" | python3 -c '
import sys, ipaddress
raw=sys.stdin.read().strip()
try:
    ip=ipaddress.ip_address(raw)
    if ip.version == 4:
        p=str(ip).split(".")
        print(".".join(p[:3])+".***")
    else:
        p=ip.exploded.split(":")
        print(":".join(p[:2])+":****:****:****:****:****:****")
except ValueError:
    print("[地址已隐藏]")
' 2>/dev/null
        return
    fi
    if [[ "$address" == *:* ]]; then
        printf '[IPv6 已隐藏]'
    elif [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        printf '%s' "$address" |
            sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$/\1.***/'
    else
        printf '[地址已隐藏]'
    fi
}
# -------------------- HTTP 请求 --------------------
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
http_code() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -L -s -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -w '%{http_code}' "$url" 2>/dev/null
    else
        printf '000'
    fi
}
http_timing() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -L -s -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -w '%{time_total}' "$url" 2>/dev/null
    else
        printf '未知'
    fi
}
get_ipv4() {
    local ip
    ip=$(http_get "https://api.ipify.org") || return 1
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$ip" | python3 -c '
import sys, ipaddress
try:
    a=ipaddress.ip_address(sys.stdin.read().strip())
    print(a if a.version == 4 else "")
except ValueError:
    print("")
' 2>/dev/null
    else
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            printf '%s' "$ip"
        else
            return 1
        fi
    fi
}
get_ipv6() {
    local ip
    command -v curl >/dev/null 2>&1 || return 1
    ip=$(curl -6 -fsSL \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        https://api6.ipify.org 2>/dev/null) || return 1
    if [[ "$ip" == *:* ]]; then
        printf '%s' "$ip"
    else
        return 1
    fi
}
json_field() {
    local json="$1"
    local path="$2"
    command -v python3 >/dev/null 2>&1 || {
        printf '需要 Python 3'
        return 1
    }
    printf '%s' "$json" | python3 -c '
import sys,json
try:
    obj=json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        if isinstance(obj,dict):
            obj=obj.get(k)
        else:
            obj=None
            break
    if obj is None or isinstance(obj,(dict,list)):
        print("未知")
    else:
        print(str(obj).replace("\n"," ").replace("\r"," ")[:120])
except Exception:
    print("未知")
' "$path" 2>/dev/null
}
query_ip_info() {
    local ip="$1"
    http_get "https://ipwho.is/${ip}"
}
# -------------------- 菜单 --------------------
show_banner() {
    clear_screen
    printf '%s' "$C_CYAN"
    if (( ASCII_MODE )); then
        printf '+----------------------------------------------+\n'
        printf '|                                              |\n'
        printf '|           NYKI VPS IP CHECK                 |\n'
        printf '|               NETWORK CHECK                 |\n'
        printf '|                                              |\n'
        printf '+----------------------------------------------+\n'
    else
        printf '╭──────────────────────────────────────────────╮\n'
        printf '│                                              │\n'
        printf '│           NYKI VPS IP 检测工具               │\n'
        printf '│               NETWORK CHECK                  │\n'
        printf '│                                              │\n'
        printf '╰──────────────────────────────────────────────╯\n'
    fi
    printf '%s\n' "$C_RESET"
    printf '  版本：%s\n' "$VERSION"
    printf '  作者：%s\n' "$AUTHOR"
    printf '  网站：%s\n' "$WEBSITE"
    printf '  项目：%s\n' "$PROJECT"
    printf '%s' "$C_CYAN"
    draw_line
    printf '%s' "$C_RESET"
    printf '  [01]  全面检测\n'
    printf '  [02]  IPv4 地址检测\n'
    printf '  [03]  IPv6 地址检测\n'
    printf '  [04]  IP 归属地查询\n'
    printf '  [05]  IP 基础信息\n'
    printf '  [06]  流媒体检测\n'
    printf '  [07]  网络诊断与路由追踪\n'
    printf '  [08]  DNS 解析检测\n'
    printf '  [09]  系统信息\n'
    printf '  [10]  网站连通性检测\n'
    printf '  [11]  网络质量检测\n'
    printf '%s' "$C_CYAN"
    draw_line
    printf '%s' "$C_RESET"
    if (( HIDE_IP )); then
        printf '  隐藏 IP 模式：%s[开启]%s\n' "$C_GREEN" "$C_RESET"
    else
        printf '  隐藏 IP 模式：%s[关闭]%s\n' "$C_YELLOW" "$C_RESET"
    fi
    printf '\n'
    printf '  [12]  切换隐藏 IP 模式\n'
    printf '  [00]  退出\n'
    printf '%s' "$C_CYAN"
    draw_bottom
    printf '%s' "$C_RESET"
}
# -------------------- IPv4 --------------------
check_ipv4() {
    panel_title "IPv4 地址检测"
    local ip timing
    if ip=$(get_ipv4) && [[ -n "$ip" ]]; then
        status "检测状态" "成功" success
        status "公网 IPv4" "$(mask_one_ip "$ip")" success
        timing=$(http_timing "https://api.ipify.org")
        status "请求耗时" "${timing} 秒"
    else
        status "检测状态" "失败或不可用" warning
        info "请检查 IPv4 出口和网络连接。"
    fi
    draw_bottom
    pause_screen
}
# -------------------- IPv6 --------------------
check_ipv6() {
    panel_title "IPv6 地址检测"
    local ip timing
    if ip=$(get_ipv6) && [[ -n "$ip" ]]; then
        status "检测状态" "成功" success
        status "公网 IPv6" "$(mask_one_ip "$ip")" success
        timing=$(http_timing "https://api6.ipify.org")
        status "请求耗时" "${timing} 秒"
    else
        status "检测状态" "不可用或受限" warning
        info "当前网络可能没有可用的 IPv6 出口。"
    fi
    draw_bottom
    pause_screen
}
# -------------------- IP 归属地 --------------------
lookup_ip() {
    panel_title "IP 归属地查询"
    local ip data country region city isp timezone
    if ! ip=$(get_ipv4) || [[ -z "$ip" ]]; then
        status "查询状态" "无法获取公网 IPv4" warning
        draw_bottom
        pause_screen
        return
    fi
    if ! data=$(query_ip_info "$ip"); then
        status "查询状态" "第三方服务连接失败" error
        draw_bottom
        pause_screen
        return
    fi
    local ok
    ok=$(json_field "$data" "success")
    if [[ "$ok" != "True" && "$ok" != "true" ]]; then
        status "查询状态" "查询失败" warning
        draw_bottom
        pause_screen
        return
    fi
    country=$(json_field "$data" "country")
    region=$(json_field "$data" "region")
    city=$(json_field "$data" "city")
    isp=$(json_field "$data" "connection.isp")
    timezone=$(json_field "$data" "timezone.id")
    status "公网 IPv4" "$(mask_one_ip "$ip")"
    status "国家/地区" "$country"
    status "州/省" "$region"
    status "城市" "$city"
    status "运营商" "$isp"
    status "时区" "$timezone"
    draw_bottom
    pause_screen
}
# -------------------- IP 基础信息 --------------------
ip_basic() {
    panel_title "IP 基础信息"
    local ip data country region city isp org asn timezone
    if ! ip=$(get_ipv4) || [[ -z "$ip" ]]; then
        status "查询状态" "无法获取公网 IPv4" warning
        draw_bottom
        pause_screen
        return
    fi
    if ! data=$(query_ip_info "$ip"); then
        status "查询状态" "第三方服务连接失败" error
        draw_bottom
        pause_screen
        return
    fi
    if [[ "$(json_field "$data" "success")" != "true" &&
          "$(json_field "$data" "success")" != "True" ]]; then
        status "查询状态" "查询失败" warning
        draw_bottom
        pause_screen
        return
    fi
    country=$(json_field "$data" "country")
    region=$(json_field "$data" "region")
    city=$(json_field "$data" "city")
    isp=$(json_field "$data" "connection.isp")
    org=$(json_field "$data" "connection.org")
    asn=$(json_field "$data" "connection.asn")
    timezone=$(json_field "$data" "timezone.id")
    status "公网 IPv4" "$(mask_one_ip "$ip")"
    status "国家/地区" "$country"
    status "州/省" "$region"
    status "城市" "$city"
    status "运营商" "$isp"
    status "组织" "$org"
    status "时区" "$timezone"
    if (( HIDE_IP )); then
        status "ASN 编号" "已隐藏"
    else
        status "ASN 编号" "$asn"
    fi
    draw_bottom
    pause_screen
}
# -------------------- 流媒体检测 --------------------
streaming_check() {
    panel_title "流媒体网站连通性"
    local names=(
        "Netflix"
        "YouTube"
        "Disney+"
        "ChatGPT"
        "Google"
    )
    local urls=(
        "https://www.netflix.com"
        "https://www.youtube.com"
        "https://www.disneyplus.com"
        "https://chatgpt.com"
        "https://www.google.com"
    )
    local i code timing
    for i in "${!names[@]}"; do
        code=$(http_code "${urls[$i]}")
        if [[ "$code" =~ ^[0-9]{3}$ ]] &&
           (( 10#$code >= 200 && 10#$code < 400 )); then
            status "${names[$i]}" "HTTP $code" success
        elif [[ "$code" =~ ^[0-9]{3}$ ]] &&
             (( 10#$code >= 400 )); then
            status "${names[$i]}" "HTTP $code" warning
        else
            status "${names[$i]}" "连接失败或超时" error
        fi
    done
    info "HTTP 连通性不代表地区内容解锁。"
    draw_bottom
    pause_screen
}
# -------------------- 网络诊断与路由 --------------------
network_diagnostic() {
    panel_title "网络诊断与路由追踪"
    local ip gateway
    if ip=$(get_ipv4) && [[ -n "$ip" ]]; then
        status "公网 IPv4" "$(mask_one_ip "$ip")" success
    else
        status "公网 IPv4" "不可用" warning
    fi
    if command -v ip >/dev/null 2>&1; then
        gateway=$(ip route 2>/dev/null |
            awk '/^default/ {print $3; exit}')
        if [[ -n "$gateway" ]]; then
            status "默认网关" "$(mask_one_ip "$gateway")"
        else
            status "默认网关" "未检测到" warning
        fi
    fi
    if (( HIDE_IP )); then
        info "隐藏模式已开启，跳过详细路由节点输出。"
    elif command -v traceroute >/dev/null 2>&1; then
        printf '\n  路由追踪（最多 5 跳）\n'
        traceroute -n -m 5 -w 1 1.1.1.1 2>/dev/null |
            head -n 7
    elif command -v tracepath >/dev/null 2>&1; then
        printf '\n  路由追踪（最多 5 跳）\n'
        tracepath -m 5 1.1.1.1 2>/dev/null |
            head -n 7
    else
        status "路由追踪" "未安装 traceroute/tracepath" warning
    fi
    draw_bottom
    pause_screen
}
# -------------------- DNS --------------------
dns_check() {
    panel_title "DNS 解析检测"
    local domains=(
        "google.com"
        "cloudflare.com"
        "github.com"
        "nyki.cc"
    )
    local domain result start end elapsed
    for domain in "${domains[@]}"; do
        start=$(date +%s)
        result=""
        if command -v getent >/dev/null 2>&1; then
            result=$(getent ahosts "$domain" 2>/dev/null |
                awk 'NR==1 {print $1}')
        elif command -v nslookup >/dev/null 2>&1; then
            result=$(nslookup "$domain" 2>/dev/null |
                awk '/^Address: / {print $2; exit}')
        fi
        end=$(date +%s)
        elapsed=$((end - start))
        if [[ -n "$result" ]]; then
            status "$domain" "$(mask_one_ip "$result")" success
            status "  解析耗时" "${elapsed} 秒"
        else
            status "$domain" "解析失败或工具不可用" warning
        fi
    done
    draw_bottom
    pause_screen
}
# -------------------- 系统信息 --------------------
system_info() {
    panel_title "系统信息"
    local os kernel arch uptime_text hostname cpu_cores load
    if [[ -r /etc/os-release ]]; then
        os=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-Linux}")
    else
        os=$(uname -s 2>/dev/null || printf '未知')
    fi
    kernel=$(uname -r 2>/dev/null || printf '未知')
    arch=$(uname -m 2>/dev/null || printf '未知')
    uptime_text=$(uptime -p 2>/dev/null || uptime 2>/dev/null || printf '未知')
    hostname=$(hostname 2>/dev/null || printf '未知')
    cpu_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '未知')
    load=$(awk '{print $1 " / " $2 " / " $3}' /proc/loadavg 2>/dev/null)
    status "操作系统" "$os"
    status "内核版本" "$kernel"
    status "系统架构" "$arch"
    status "CPU 核心" "$cpu_cores"
    status "系统负载" "${load:-未知}"
    status "运行时间" "$uptime_text"
    if (( HIDE_IP )); then
        status "主机名称" "已隐藏"
    else
        status "主机名称" "$hostname"
    fi
    if command -v free >/dev/null 2>&1; then
        local memory
        memory=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}')
        status "内存使用" "${memory:-未知}"
    fi
    local disk
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
    status "根分区" "${disk:-未知}"
    draw_bottom
    pause_screen
}
# -------------------- 网站连通性 --------------------
website_check() {
    panel_title "网站连通性检测"
    local names=(
        "Google"
        "Cloudflare"
        "GitHub"
        "NYKI"
    )
    local urls=(
        "https://www.google.com"
        "https://www.cloudflare.com"
        "https://github.com"
        "https://nyki.cc"
    )
    local i code timing
    for i in "${!names[@]}"; do
        code=$(http_code "${urls[$i]}")
        timing=$(http_timing "${urls[$i]}")
        if [[ "$code" =~ ^[0-9]{3}$ ]] &&
           (( 10#$code >= 200 && 10#$code < 400 )); then
            status "${names[$i]}" "HTTP $code" success
            status "  响应时间" "${timing} 秒"
        elif [[ "$code" =~ ^[0-9]{3}$ ]] &&
             (( 10#$code >= 400 )); then
            status "${names[$i]}" "HTTP $code" warning
            status "  响应时间" "${timing} 秒"
        else
            status "${names[$i]}" "连接失败或超时" error
        fi
    done
    draw_bottom
    pause_screen
}
# -------------------- 网络质量 --------------------
network_quality() {
    panel_title "网络质量检测"
    local target start end elapsed loss
    if command -v ping >/dev/null 2>&1; then
        for target in 1.1.1.1 8.8.8.8; do
            printf '\n  目标：%s\n' "$(mask_one_ip "$target")"
            local output
            output=$(ping -c 4 -W 2 "$target" 2>&1)
            local rc=$?
            if (( rc == 0 )); then
                loss=$(printf '%s\n' "$output" |
                    awk -F',' '/packet loss/ {gsub(/ /,"",$3); print $3}')
                elapsed=$(printf '%s\n' "$output" |
                    awk -F'/' '/^(rtt|round-trip)/ {print $5}')
                status "丢包率" "${loss:-未知}" success
                status "平均延迟" "${elapsed:-未知} ms" success
            else
                status "连接状态" "Ping 失败或受限" warning
            fi
        done
    else
        status "Ping 检测" "系统未安装 ping" warning
    fi
    start=$(date +%s)
    if http_get "https://www.google.com" >/dev/null; then
        end=$(date +%s)
        status "HTTPS 请求" "成功" success
        status "总耗时" "$((end - start)) 秒"
    else
        status "HTTPS 请求" "失败或超时" warning
    fi
    draw_bottom
    pause_screen
}
# -------------------- 全面检测 --------------------
full_check() {
    panel_title "全面检测"
    local start end ip4 ip6 data code timing dns_result
    start=$(date +%s)
    printf '\n  [1/7] 公网 IPv4\n'
    if ip4=$(get_ipv4) && [[ -n "$ip4" ]]; then
        status "结果" "$(mask_one_ip "$ip4")" success
    else
        status "结果" "不可用" warning
    fi
    printf '\n  [2/7] 公网 IPv6\n'
    if ip6=$(get_ipv6) && [[ -n "$ip6" ]]; then
        status "结果" "$(mask_one_ip "$ip6")" success
    else
        status "结果" "不可用或受限" warning
    fi
    printf '\n  [3/7] IP 归属地\n'
    if [[ -n "${ip4:-}" ]] && data=$(query_ip_info "$ip4"); then
        if [[ "$(json_field "$data" "success")" == "true" ||
              "$(json_field "$data" "success")" == "True" ]]; then
            status "国家/地区" "$(json_field "$data" "country")"
            status "运营商" "$(json_field "$data" "connection.isp")"
        else
            status "结果" "查询失败" warning
        fi
    else
        status "结果" "查询失败" warning
    fi
    printf '\n  [4/7] DNS 解析\n'
    if command -v getent >/dev/null 2>&1; then
        dns_result=$(getent hosts github.com 2>/dev/null)
    elif command -v nslookup >/dev/null 2>&1; then
        dns_result=$(nslookup github.com 2>/dev/null)
    else
        dns_result=""
    fi
    if [[ -n "$dns_result" ]]; then
        status "结果" "正常" success
    else
        status "结果" "失败或工具不可用" warning
    fi
    printf '\n  [5/7] HTTPS 连通性\n'
    code=$(http_code "https://www.google.com")
    if [[ "$code" =~ ^[0-9]{3}$ ]] &&
       (( 10#$code >= 200 && 10#$code < 400 )); then
        status "结果" "HTTP $code" success
    else
        status "结果" "连接失败或异常响应" warning
    fi
    printf '\n  [6/7] IPv4 出口\n'
    if command -v curl >/dev/null 2>&1 &&
       curl -4 -fsSL -o /dev/null \
           --connect-timeout "$CONNECT_TIMEOUT" \
           --max-time "$MAX_TIME" \
           https://www.google.com 2>/dev/null; then
        status "结果" "正常" success
    else
        status "结果" "异常或受限" warning
    fi
    printf '\n  [7/7] 系统信息\n'
    status "系统" "$(uname -s 2>/dev/null || printf '未知')"
    status "架构" "$(uname -m 2>/dev/null || printf '未知')"
    status "内核" "$(uname -r 2>/dev/null || printf '未知')"
    end=$(date +%s)
    printf '\n'
    status "检测耗时" "$((end - start)) 秒"
    draw_bottom
    pause_screen
}
# -------------------- 隐藏 IP --------------------
toggle_hide_ip() {
    if (( HIDE_IP )); then
        HIDE_IP=0
    else
        HIDE_IP=1
    fi
}
# -------------------- 主程序 --------------------
main() {
    init_terminal
    if ! command -v curl >/dev/null 2>&1 &&
       ! command -v wget >/dev/null 2>&1; then
        printf '错误：请先安装 curl 或 wget。\n'
        exit 1
    fi
    while true; do
        show_banner
        local choice
        printf '\n  请输入选项 [00-12]：'
        if ! read -r choice; then
            printf '\n'
            break
        fi
        case "$choice" in
            1|01) full_check ;;
            2|02) check_ipv4 ;;
            3|03) check_ipv6 ;;
            4|04) lookup_ip ;;
            5|05) ip_basic ;;
            6|06) streaming_check ;;
            7|07) network_diagnostic ;;
            8|08) dns_check ;;
            9|09) system_info ;;
            10) website_check ;;
            11) network_quality ;;
            12) toggle_hide_ip ;;
            0|00)
                printf '\n感谢使用 NYKI VPS IP 检测工具！\n'
                break
                ;;
            *)
                printf '\n无效选项，请重新输入。\n'
                sleep 1
                ;;
        esac
    done
}
main "$@"
