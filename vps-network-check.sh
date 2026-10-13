#!/usr/bin/env bash
# ============================================================
# NYKI / VPS NETWORK CHECK
# VPS 网络检测工具
# Author: 阿晚
# Website: https://nyki.cc
# Project: https://github.com/nyki4/vps-ip-check
# Version: v2.3.0
# ============================================================
VERSION="v2.3.0"
AUTHOR="阿晚"
WEBSITE="nyki.cc"
PROJECT="github.com/nyki4/vps-ip-check"
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=C
# ---------- 颜色 ----------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_CYAN=$'\033[36m'
    C_BLUE=$'\033[34m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_WHITE=$'\033[97m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_CYAN=""
    C_BLUE=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_WHITE=""
fi
# ---------- 全局设置 ----------
HIDE_IP=1
CONNECT_TIMEOUT=5
IP_API_TIMEOUT=8
PING_COUNT=4
# ---------- 基础工具 ----------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}
clear_screen() {
    if [[ -t 1 ]] && has_cmd clear; then
        clear
    else
        printf '\n'
    fi
}
line() {
    printf '%s\n' \
        "${C_DIM}────────────────────────────────────────────────────────${C_RESET}"
}
print_status() {
    local status="$1"
    case "$status" in
        OK|正常|成功|通畅|可用|支持|已开启)
            printf '%s%s%s' "$C_GREEN" "$status" "$C_RESET"
            ;;
        FAIL|异常|失败|不通|不可用|不支持|关闭)
            printf '%s%s%s' "$C_RED" "$status" "$C_RESET"
            ;;
        WARN|注意|未知|受限|未检测|跳过)
            printf '%s%s%s' "$C_YELLOW" "$status" "$C_RESET"
            ;;
        *)
            printf '%s' "$status"
            ;;
    esac
}
# 隐藏 IPv4 地址最后一段。
mask_ipv4() {
    local ip="$1"
    local a b c d extra
    IFS='.' read -r a b c d extra <<< "$ip"
    if [[ -z "$extra" &&
          "$a" =~ ^[0-9]+$ &&
          "$b" =~ ^[0-9]+$ &&
          "$c" =~ ^[0-9]+$ &&
          "$d" =~ ^[0-9]+$ ]]; then
        printf '%s.%s.%s.*' "$a" "$b" "$c"
    else
        printf '%s' "$ip"
    fi
}
# 隐藏 IPv6 地址，保留前缀用于识别。
mask_ipv6() {
    local ip="$1"
    local prefix
    [[ "$ip" == *:* ]] || {
        printf '%s' "$ip"
        return
    }
    prefix="${ip%%:*}"
    if [[ "$ip" == *::* ]]; then
        printf '%s:…' "$prefix"
    else
        printf '%s:…' "$prefix"
    fi
}
mask_ip() {
    local ip="$1"
    if (( HIDE_IP == 0 )); then
        printf '%s' "$ip"
        return
    fi
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        mask_ipv4 "$ip"
    elif [[ "$ip" == *:* ]]; then
        mask_ipv6 "$ip"
    else
        printf '%s' "$ip"
    fi
}
# 对文本中常见的 IPv4 地址进行脱敏。
# 不依赖 Python 等额外组件。
mask_text() {
    local text="$1"
    if (( HIDE_IP == 0 )); then
        printf '%s' "$text"
        return
    fi
    if has_cmd perl; then
        printf '%s' "$text" |
            perl -pe '
                s/(?<![0-9.])(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}(?![0-9])/$1.*/g
            '
    else
        printf '%s' "$text"
    fi
}
# 统一结果字段格式。
row() {
    local label="$1"
    local value="$2"
    local status="${3:-}"
    value="$(mask_text "$value")"
    printf '  %-14s : %s' "$label" "$value"
    if [[ -n "$status" ]]; then
        printf '  [%s]' "$(print_status "$status")"
    fi
    printf '\n'
}
section() {
    printf '\n%s%s%s\n' "$C_CYAN" "$1" "$C_RESET"
}
# ---------- 页面框架 ----------
print_brand() {
    printf '%s%sNYKI%s %s/ VPS NETWORK CHECK%s\n' \
        "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
    printf '%sVPS 网络检测工具%s\n' "$C_WHITE" "$C_RESET"
    printf '%s作者   %s%s\n' "$C_DIM" "$AUTHOR" "$C_RESET"
    printf '%s主页   %s%s\n' "$C_DIM" "$WEBSITE" "$C_RESET"
    printf '%s项目   %s%s\n' "$C_DIM" "$PROJECT" "$C_RESET"
    printf '%s版本   %s%s\n' "$C_DIM" "$VERSION" "$C_RESET"
    line
}
result_header() {
    local title="$1"
    clear_screen
    print_brand
    printf '%s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
    line
}
result_footer() {
    line
    printf '%s[R]%s 重新检测    %s[回车]%s 返回主菜单\n' \
        "$C_CYAN" "$C_RESET" "$C_CYAN" "$C_RESET"
}
# 所有检测统一从这里进入。
# 输入 r/R 重新运行当前检测函数。
# 回车或其他输入返回主菜单。
run_check() {
    local title="$1"
    local func="$2"
    local action
    while true; do
        result_header "$title"
        "$func"
        result_footer
        printf '> '
        IFS= read -r action || action=""
        case "$action" in
            r|R)
                continue
                ;;
            *)
                break
                ;;
        esac
    done
}
pause_return() {
    printf '\n按回车返回主菜单...'
    IFS= read -r _
}
# ---------- 网络基础函数 ----------
get_ipv4() {
    local result=""
    if has_cmd curl; then
        result="$(
            curl -4 -fsS \
                --connect-timeout "$CONNECT_TIMEOUT" \
                --max-time "$IP_API_TIMEOUT" \
                https://api.ipify.org 2>/dev/null
        )"
    fi
    if [[ -z "$result" ]] && has_cmd wget; then
        result="$(
            wget -4 -qO- \
                --timeout="$IP_API_TIMEOUT" \
                https://api.ipify.org 2>/dev/null
        )"
    fi
    if [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$result"
    else
        return 1
    fi
}
get_ipv6() {
    local result=""
    if has_cmd curl; then
        result="$(
            curl -6 -fsS \
                --connect-timeout "$CONNECT_TIMEOUT" \
                --max-time "$IP_API_TIMEOUT" \
                https://api6.ipify.org 2>/dev/null
        )"
    fi
    if [[ -z "$result" ]] && has_cmd wget; then
        result="$(
            wget -6 -qO- \
                --timeout="$IP_API_TIMEOUT" \
                https://api6.ipify.org 2>/dev/null
        )"
    fi
    if [[ "$result" == *:* ]]; then
        printf '%s' "$result"
    else
        return 1
    fi
}
get_os() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s' "${PRETTY_NAME:-Linux}"
    elif has_cmd uname; then
        uname -s
    else
        printf '未知'
    fi
}
get_default_route() {
    if has_cmd ip; then
        ip route show default 2>/dev/null |
            awk 'NR==1 {
                for (i=1;i<=NF;i++)
                    if ($i=="via") {print $(i+1); exit}
            }'
    fi
}
# ---------- 01 全面检测 ----------
full_check() {
    local ip4="" ip6="" gateway="" dns="" latency=""
    local passed=0 failed=0 unavailable=0
    section "01 / 基础网络"
    if ip4="$(get_ipv4)"; then
        row "公网 IPv4" "$ip4" "正常"
        ((passed++))
    else
        row "公网 IPv4" "无法获取或当前网络不支持" "不可用"
        ((unavailable++))
    fi
    if ip6="$(get_ipv6)"; then
        row "公网 IPv6" "$ip6" "正常"
        ((passed++))
    else
        row "公网 IPv6" "无法获取或当前网络不支持" "不可用"
        ((unavailable++))
    fi
    gateway="$(get_default_route)"
    if [[ -n "$gateway" ]]; then
        row "默认网关" "$gateway" "正常"
        ((passed++))
    else
        row "默认网关" "未获取到默认路由" "注意"
        ((failed++))
    fi
    section "02 / 连通性"
    if has_cmd ping && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        row "IPv4 连通性" "1.1.1.1 可达" "正常"
        ((passed++))
    else
        row "IPv4 连通性" "目标无响应或 ICMP 受限" "异常"
        ((failed++))
    fi
    if has_cmd curl &&
       curl -fsS -o /dev/null \
           --connect-timeout "$CONNECT_TIMEOUT" \
           --max-time "$IP_API_TIMEOUT" \
           https://www.cloudflare.com; then
        row "HTTPS 连接" "Cloudflare 可访问" "正常"
        ((passed++))
    else
        row "HTTPS 连接" "连接失败或受到限制" "异常"
        ((failed++))
    fi
    section "03 / DNS"
    if has_cmd getent &&
       getent ahosts example.com >/dev/null 2>&1; then
        row "DNS 解析" "example.com 解析成功" "正常"
        ((passed++))
    else
        row "DNS 解析" "解析失败或缺少 getent" "异常"
        ((failed++))
    fi
    section "04 / 检测汇总"
    row "正常项目" "$passed"
    row "异常项目" "$failed"
    row "不可用项目" "$unavailable"
    printf '\n%s提示：%s 部分网络可能限制 ICMP、IPv6 或外部 API，单项异常不一定代表服务器整体故障。%s\n' \
        "$C_DIM" "" "$C_RESET"
}
# ---------- 02 IPv4 检测 ----------
ipv4_check() {
    local ip4="" gateway="" route=""
    section "公网地址"
    if ip4="$(get_ipv4)"; then
        row "公网 IPv4" "$ip4" "正常"
    else
        row "公网 IPv4" "获取失败" "异常"
    fi
    section "本机网络"
    if has_cmd ip; then
        route="$(ip -4 route get 1.1.1.1 2>/dev/null | head -n 1)"
        gateway="$(get_default_route)"
        if [[ -n "$route" ]]; then
            row "路由信息" "$route"
        else
            row "路由信息" "未获取到 IPv4 路由" "注意"
        fi
        if [[ -n "$gateway" ]]; then
            row "默认网关" "$gateway"
        else
            row "默认网关" "未检测到" "注意"
        fi
    else
        row "网络工具" "未安装 iproute2" "注意"
    fi
    section "连通性"
    if has_cmd ping && ping -4 -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        row "IPv4 Ping" "1.1.1.1 可达" "正常"
    else
        row "IPv4 Ping" "无响应或 ICMP 受限" "异常"
    fi
    if has_cmd curl &&
       curl -4 -fsS -o /dev/null \
           --connect-timeout "$CONNECT_TIMEOUT" \
           --max-time "$IP_API_TIMEOUT" \
           https://api.ipify.org; then
        row "IPv4 HTTPS" "连接成功" "正常"
    else
        row "IPv4 HTTPS" "连接失败" "异常"
    fi
}
# ---------- 03 IPv6 检测 ----------
ipv6_check() {
    local ip6="" route=""
    section "公网地址"
    if ip6="$(get_ipv6)"; then
        row "公网 IPv6" "$ip6" "正常"
    else
        row "公网 IPv6" "无法获取或不支持 IPv6" "不可用"
    fi
    section "本机网络"
    if has_cmd ip; then
        route="$(ip -6 route show default 2>/dev/null | head -n 1)"
        if [[ -n "$route" ]]; then
            row "默认路由" "$route"
        else
            row "默认路由" "未发现 IPv6 默认路由" "注意"
        fi
        ip -o -6 addr show scope global 2>/dev/null |
            while IFS= read -r entry; do
                row "本机 IPv6" "$entry"
            done
    else
        row "网络工具" "未安装 iproute2" "注意"
    fi
    section "连通性"
    if has_cmd ping && ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
        row "IPv6 Ping" "Cloudflare DNS 可达" "正常"
    else
        row "IPv6 Ping" "无响应或 IPv6 不可用" "异常"
    fi
    if has_cmd curl &&
       curl -6 -fsS -o /dev/null \
           --connect-timeout "$CONNECT_TIMEOUT" \
           --max-time "$IP_API_TIMEOUT" \
           https://api6.ipify.org; then
        row "IPv6 HTTPS" "连接成功" "正常"
    else
        row "IPv6 HTTPS" "连接失败" "异常"
    fi
}
# ---------- 04 IP 信息查询 ----------
ip_info_check() {
    local ip4="" data=""
    if ! has_cmd curl; then
        row "依赖检查" "请安装 curl 后重试" "异常"
        return
    fi
    if ! ip4="$(get_ipv4)"; then
        row "公网 IPv4" "无法获取" "异常"
        return
    fi
    section "查询对象"
    row "公网 IPv4" "$ip4"
    section "IP 地理信息"
    data="$(
        curl -fsS \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$IP_API_TIMEOUT" \
            "https://ipapi.co/${ip4}/json/" 2>/dev/null
    )"
    if [[ -z "$data" ]]; then
        row "查询结果" "API 请求失败" "异常"
        return
    fi
    if has_cmd python3; then
        printf '%s' "$data" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("查询结果       : 数据解析失败")
    sys.exit(0)
fields=[
    ("国家/地区","country_name"),
    ("国家代码","country_code"),
    ("城市","city"),
    ("地区","region"),
    ("邮政编码","postal"),
    ("时区","timezone"),
    ("网络组织","org"),
    ("ASN","asn")
]
for label,key in fields:
    value=d.get(key)
    if value:
        value=str(value).replace("\n"," ")
        print(f"{label:<14} : {value}")
if d.get("error"):
    print("查询提示       : API 返回错误")
' | while IFS= read -r entry; do
            printf '  %s\n' "$(mask_text "$entry")"
        done
    else
        row "查询结果" "未安装 Python 3，无法解析 JSON" "注意"
    fi
}
# ---------- 05 本机网络配置 ----------
network_config() {
    section "系统与内核"
    row "操作系统" "$(get_os)"
    row "内核版本" "$(uname -r 2>/dev/null || printf '未知')"
    row "主机名称" "$(hostname 2>/dev/null || printf '未知')"
    row "系统架构" "$(uname -m 2>/dev/null || printf '未知')"
    section "网络接口"
    if has_cmd ip; then
        ip -brief addr show 2>/dev/null |
            while IFS= read -r entry; do
                row "接口" "$entry"
            done
        section "默认路由"
        ip route show default 2>/dev/null |
            while IFS= read -r entry; do
                row "IPv4 路由" "$entry"
            done
        ip -6 route show default 2>/dev/null |
            while IFS= read -r entry; do
                row "IPv6 路由" "$entry"
            done
    else
        row "网络工具" "未安装 iproute2" "注意"
    fi
    section "DNS 配置"
    if [[ -r /etc/resolv.conf ]]; then
        awk '/^[[:space:]]*nameserver[[:space:]]+/ {
            print $2
        }' /etc/resolv.conf |
            while IFS= read -r server; do
                row "DNS 服务器" "$server"
            done
    else
        row "DNS 配置" "无法读取 /etc/resolv.conf" "注意"
    fi
}
# ---------- 06 流媒体检测 ----------
streaming_check() {
    local url status
    if ! has_cmd curl; then
        row "依赖检查" "请先安装 curl" "异常"
        return
    fi
    section "平台连通性"
    local -a sites=(
        "Netflix|https://www.netflix.com"
        "YouTube|https://www.youtube.com"
        "Disney+|https://www.disneyplus.com"
        "OpenAI|https://chatgpt.com"
        "Google|https://www.google.com"
        "BBC|https://www.bbc.com"
    )
    local item name
    for item in "${sites[@]}"; do
        name="${item%%|*}"
        url="${item#*|}"
        status="$(
            curl -L -sS -o /dev/null \
                --connect-timeout "$CONNECT_TIMEOUT" \
                --max-time "$IP_API_TIMEOUT" \
                -w '%{http_code}' "$url" 2>/dev/null
        )"
        if [[ "$status" =~ ^[0-9]{3}$ ]] &&
           (( 10#$status >= 200 && 10#$status < 500 )); then
            row "$name" "HTTP $status" "可达"
        elif [[ "$status" =~ ^[0-9]{3}$ ]]; then
            row "$name" "HTTP $status" "异常"
        else
            row "$name" "连接失败或超时" "不可用"
        fi
    done
    printf '\n%s说明：网站可访问不代表已获得对应平台的流媒体播放权限。%s\n' \
        "$C_DIM" "$C_RESET"
}
# ---------- 07 网络诊断与路由追踪 ----------
network_diagnosis() {
    local target
    printf '请输入诊断目标 [默认 1.1.1.1]：'
    IFS= read -r target
    target="${target:-1.1.1.1}"
    if [[ ! "$target" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
        row "输入检查" "目标格式不合法" "异常"
        return
    fi
    section "目标信息"
    row "诊断目标" "$target"
    section "Ping 检测"
    if has_cmd ping; then
        ping -c "$PING_COUNT" -W 3 "$target" 2>&1 |
            while IFS= read -r entry; do
                printf '  %s\n' "$(mask_text "$entry")"
            done
    else
        row "Ping" "未安装 ping" "不可用"
    fi
    section "路由追踪"
    if has_cmd tracepath; then
        tracepath -m 12 "$target" 2>&1 |
            while IFS= read -r entry; do
                printf '  %s\n' "$(mask_text "$entry")"
            done
    elif has_cmd traceroute; then
        traceroute -m 12 -w 2 "$target" 2>&1 |
            while IFS= read -r entry; do
                printf '  %s\n' "$(mask_text "$entry")"
            done
    else
        row "路由追踪" "请安装 tracepath 或 traceroute" "不可用"
    fi
}
# ---------- 08 DNS 解析检测 ----------
dns_check() {
    local domain result
    printf '请输入域名 [默认 example.com]：'
    IFS= read -r domain
    domain="${domain:-example.com}"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        row "输入检查" "域名格式不合法" "异常"
        return
    fi
    section "DNS 查询"
    row "查询域名" "$domain"
    if has_cmd dig; then
        result="$(dig +time=3 +tries=1 +short A "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            while IFS= read -r entry; do
                [[ -n "$entry" ]] && row "IPv4 结果" "$entry"
            done <<< "$result"
        else
            row "IPv4 结果" "没有返回记录" "注意"
        fi
        result="$(dig +time=3 +tries=1 +short AAAA "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            while IFS= read -r entry; do
                [[ -n "$entry" ]] && row "IPv6 结果" "$entry"
            done <<< "$result"
        else
            row "IPv6 结果" "没有返回记录" "注意"
        fi
        result="$(dig +time=3 +tries=1 +short NS "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            while IFS= read -r entry; do
                [[ -n "$entry" ]] && row "NS 记录" "$entry"
            done <<< "$result"
        fi
    elif has_cmd getent; then
        result="$(getent ahosts "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            printf '%s\n' "$result" |
                awk '!seen[$1]++ {print $1}' |
                while IFS= read -r entry; do
                    row "解析结果" "$entry"
                done
        else
            row "解析结果" "查询失败" "异常"
        fi
    else
        row "依赖检查" "请安装 dnsutils 或 getent" "异常"
    fi
}
# ---------- 09 系统信息 ----------
system_info() {
    section "系统信息"
    row "操作系统" "$(get_os)"
    row "内核版本" "$(uname -r 2>/dev/null || printf '未知')"
    row "系统架构" "$(uname -m 2>/dev/null || printf '未知')"
    row "主机名称" "$(hostname 2>/dev/null || printf '未知')"
    row "运行时间" "$(uptime -p 2>/dev/null || uptime 2>/dev/null || printf '未知')"
    section "CPU 与内存"
    if [[ -r /proc/cpuinfo ]]; then
        row "CPU 型号" "$(
            awk -F ': ' '/model name/ {print $2; exit}' /proc/cpuinfo
        )"
        row "CPU 核心" "$(
            awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo
        )"
    else
        row "CPU 信息" "无法读取 /proc/cpuinfo" "注意"
    fi
    if has_cmd free; then
        free -h 2>/dev/null |
            awk 'NR==2 {
                printf "  %-14s : 总计 %s / 已用 %s / 可用 %s\n",
                    "内存", $2, $3, $7
            }'
    else
        row "内存信息" "未安装 free" "注意"
    fi
    section "磁盘"
    if has_cmd df; then
        df -hP / 2>/dev/null |
            awk 'NR==2 {
                printf "  %-14s : 容量 %s / 已用 %s / 可用 %s / 使用率 %s\n",
                    "根分区", $2, $3, $4, $5
            }'
    fi
    section "虚拟化信息"
    if has_cmd systemd-detect-virt; then
        row "虚拟化类型" "$(systemd-detect-virt 2>/dev/null || printf '未识别')"
    elif [[ -d /proc/vz ]]; then
        row "虚拟化类型" "OpenVZ"
    elif grep -qi hypervisor /proc/cpuinfo 2>/dev/null; then
        row "虚拟化类型" "检测到 Hypervisor 标志"
    else
        row "虚拟化类型" "未知"
    fi
}
# ---------- 10 网站连通性检测 ----------
website_check() {
    local url code time_total
    printf '请输入网址 [默认 https://www.cloudflare.com]：'
    IFS= read -r url
    url="${url:-https://www.cloudflare.com}"
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/[^[:space:]]*)?$ ]]; then
        row "输入检查" "网址格式不合法，仅支持 HTTP/HTTPS URL" "异常"
        return
    fi
    section "HTTP 检测"
    row "目标网址" "$url"
    if ! has_cmd curl; then
        row "依赖检查" "请先安装 curl" "异常"
        return
    fi
    code="$(
        curl -L -sS -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time 20 \
            -w '%{http_code}' "$url" 2>/dev/null
    )"
    time_total="$(
        curl -L -sS -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time 20 \
            -w '%{time_total}' "$url" 2>/dev/null
    )"
    if [[ "$code" =~ ^[0-9]{3}$ ]] && (( 10#$code >= 200 && 10#$code < 400 )); then
        row "HTTP 状态码" "$code" "正常"
    elif [[ "$code" =~ ^[0-9]{3}$ ]]; then
        row "HTTP 状态码" "$code" "异常"
    else
        row "HTTP 状态码" "连接失败或超时" "异常"
    fi
    if [[ "$time_total" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        row "总耗时" "${time_total} 秒"
    else
        row "总耗时" "未获取"
    fi
}
# ---------- 11 网络质量检测 ----------
network_quality() {
    local target="1.1.1.1"
    local output loss avg
    section "检测目标"
    row "Ping 目标" "$target"
    row "检测次数" "$PING_COUNT"
    if ! has_cmd ping; then
        row "依赖检查" "未安装 ping" "异常"
        return
    fi
    output="$(ping -c "$PING_COUNT" -W 3 "$target" 2>&1)"
    printf '%s\n' "$output" |
        while IFS= read -r entry; do
            printf '  %s\n' "$(mask_text "$entry")"
        done
    loss="$(
        printf '%s\n' "$output" |
            awk -F ', ' '/packet loss/ {
                for (i=1;i<=NF;i++)
                    if ($i ~ /packet loss/) {
                        print $i
                        exit
                    }
            }'
    )"
    avg="$(
        printf '%s\n' "$output" |
            awk -F ' = ' '/^rtt |^round-trip / {
                split($2,a,"/")
                if (a[2] != "") print a[2] " ms"
            }'
    )"
    section "质量摘要"
    row "丢包率" "${loss:-未获取}"
    row "平均延迟" "${avg:-未获取}"
    printf '\n%s提示：该结果受目标节点、路由和 ICMP 策略影响。%s\n' \
        "$C_DIM" "$C_RESET"
}
# ---------- 12 TCP 端口连通性检测 ----------
tcp_check() {
    local host port result
    printf '请输入目标主机 [默认 example.com]：'
    IFS= read -r host
    host="${host:-example.com}"
    printf '请输入 TCP 端口 [默认 443]：'
    IFS= read -r port
    port="${port:-443}"
    if [[ ! "$host" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
        row "输入检查" "主机格式不合法" "异常"
        return
    fi
    if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] ||
       (( 10#$port < 1 || 10#$port > 65535 )); then
        row "输入检查" "端口必须是 1-65535 的整数" "异常"
        return
    fi
    section "TCP 连接测试"
    row "目标主机" "$host"
    row "目标端口" "$port"
    if has_cmd timeout; then
        if timeout 5 bash -c \
            'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" \
            >/dev/null 2>&1; then
            result="TCP 连接成功"
            row "测试结果" "$result" "正常"
        else
            row "测试结果" "连接失败、被拒绝或超时" "异常"
        fi
    elif has_cmd nc; then
        if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
            row "测试结果" "TCP 连接成功" "正常"
        else
            row "测试结果" "连接失败、被拒绝或超时" "异常"
        fi
    else
        row "依赖检查" "请安装 timeout 或 netcat" "异常"
    fi
}
# ---------- 13 MTU 排查 ----------
mtu_check() {
    local target="1.1.1.1"
    local size low=0 high=1472 mid found=0
    section "MTU 路径检测"
    row "目标地址" "$target"
    row "检测方式" "IPv4 DF 分片禁止探测"
    if ! has_cmd ping; then
        row "依赖检查" "未安装 ping" "异常"
        return
    fi
    if ! ping -4 -c 1 -W 3 "$target" >/dev/null 2>&1; then
        row "目标连通性" "目标无响应，MTU 结果可能不准确" "注意"
    fi
    # 二分探测可通过的最大 ICMP payload。
    # 适用于支持 ping -M do 的 Linux。
    while (( low <= high )); do
        mid=$(( (low + high) / 2 ))
        if ping -4 -M do -c 1 -W 2 -s "$mid" "$target" \
            >/dev/null 2>&1; then
            found="$mid"
            low=$(( mid + 1 ))
        else
            high=$(( mid - 1 ))
        fi
    done
    if (( found > 0 )); then
        size=$(( found + 28 ))
        row "最大载荷" "${found} bytes"
        row "估算路径 MTU" "${size} bytes" "正常"
        if (( size < 1500 )); then
            row "排查提示" "路径可能存在较小 MTU 或额外封装" "注意"
        else
            row "排查提示" "已探测到标准以太网 MTU" "正常"
        fi
    else
        row "检测结果" "未能确认 MTU，请检查网络或 ping 权限" "异常"
    fi
    printf '\n%s注意：该方法依赖 ICMP 与 DF 探测，防火墙可能影响结果。%s\n' \
        "$C_DIM" "$C_RESET"
}
# ---------- 主菜单 ----------
show_menu() {
    clear_screen
    print_brand
    printf '%s检测功能%s\n' "$C_BOLD" "$C_RESET"
    printf '  %s01%s  全面检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s02%s  IPv4 地址检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s03%s  IPv6 地址检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s04%s  IP 信息查询\n' "$C_CYAN" "$C_RESET"
    printf '  %s05%s  本机网络配置\n' "$C_CYAN" "$C_RESET"
    printf '  %s06%s  流媒体检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s07%s  网络诊断与路由追踪\n' "$C_CYAN" "$C_RESET"
    printf '  %s08%s  DNS 解析检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s09%s  系统信息\n' "$C_CYAN" "$C_RESET"
    printf '  %s10%s  网站连通性检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s11%s  网络质量检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s12%s  TCP 端口连通性检测\n' "$C_CYAN" "$C_RESET"
    printf '  %s13%s  MTU 排查\n' "$C_CYAN" "$C_RESET"
    line
    printf '%s隐私设置%s\n' "$C_BOLD" "$C_RESET"
    if (( HIDE_IP )); then
        printf '  隐藏 IP 模式  [%s已开启%s]\n' "$C_GREEN" "$C_RESET"
    else
        printf '  隐藏 IP 模式  [%s已关闭%s]\n' "$C_YELLOW" "$C_RESET"
    fi
    printf '  %s14%s  切换隐藏 IP 模式\n' "$C_CYAN" "$C_RESET"
    line
    printf '  %s00%s  退出\n' "$C_CYAN" "$C_RESET
    printf '\n'
}
main() {
    local choice
    while true; do
        show_menu
        printf '请输入选项 [00-14]：'
        IFS= read -r choice || break
        case "$choice" in
            1|01)
                run_check "全面检测" full_check
                ;;
            2|02)
                run_check "IPv4 地址检测" ipv4_check
                ;;
            3|03)
                run_check "IPv6 地址检测" ipv6_check
                ;;
            4|04)
                run_check "IP 信息查询" ip_info_check
                ;;
            5|05)
                run_check "本机网络配置" network_config
                ;;
            6|06)
                run_check "流媒体检测" streaming_check
                ;;
            7|07)
                run_check "网络诊断与路由追踪" network_diagnosis
                ;;
            8|08)
                run_check "DNS 解析检测" dns_check
                ;;
            9|09)
                run_check "系统信息" system_info
                ;;
            10)
                run_check "网站连通性检测" website_check
                ;;
            11)
                run_check "网络质量检测" network_quality
                ;;
            12)
                run_check "TCP 端口连通性检测" tcp_check
                ;;
            13)
                run_check "MTU 排查" mtu_check
                ;;
            14)
                if (( HIDE_IP )); then
                    HIDE_IP=0
                else
                    HIDE_IP=1
                fi
                ;;
            0|00|q|Q)
                clear_screen
                printf '%s感谢使用 VPS 网络检测工具。%s\n' \
                    "$C_CYAN" "$C_RESET"
                printf '项目地址：%s\n' "$PROJECT"
                exit 0
                ;;
            *)
                printf '\n%s无效选项，请输入 00-14。%s\n' \
                    "$C_YELLOW" "$C_RESET"
                sleep 1
                ;;
        esac
    done
}
main "$@"
