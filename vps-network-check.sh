#!/usr/bin/env bash
# ============================================================
# NYKI / VPS NETWORK CHECK
# VPS 网络检测工具
# 作者：阿晚
# 主页：https://nyki.cc
# 项目：https://github.com/nyki4/vps-ip-check
# 版本：v2.3.0
# ============================================================
VERSION="v2.3.0"
AUTHOR="阿晚"
WEBSITE="nyki.cc"
PROJECT="github.com/nyki4/vps-ip-check"
HIDE_IP=1
TIMEOUT=5
# ---------- 颜色 ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
else
    RESET=""
    BOLD=""
    DIM=""
    CYAN=""
    GREEN=""
    YELLOW=""
    RED=""
fi
# ---------- 基础函数 ----------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}
pause_key() {
    local unused
    IFS= read -r unused || true
}
clear_screen() {
    if [[ -t 1 ]] && has_cmd clear; then
        clear
    else
        printf '\n'
    fi
}
separator() {
    printf '%s────────────────────────────────────────────────────%s\n' \
        "$DIM" "$RESET"
}
status() {
    case "$1" in
        正常|成功|可达|已开启)
            printf '%s%s%s' "$GREEN" "$1" "$RESET"
            ;;
        异常|失败|不可用|不通)
            printf '%s%s%s' "$RED" "$1" "$RESET"
            ;;
        注意|未知|受限|不支持)
            printf '%s%s%s' "$YELLOW" "$1" "$RESET"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}
mask_ip() {
    local value="$1"
    if (( HIDE_IP == 0 )); then
        printf '%s' "$value"
        return
    fi
    if [[ "$value" =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}$ ]]; then
        printf '%s.*' "${BASH_REMATCH[1]}"
    elif [[ "$value" == *:* ]]; then
        printf '%s:…' "${value%%:*}"
    else
        printf '%s' "$value"
    fi
}
row() {
    local label="$1"
    local value="${2:-未获取}"
    local state="${3:-}"
    value="$(mask_ip "$value")"
    printf '  %-14s : %s' "$label" "$value"
    if [[ -n "$state" ]]; then
        printf '  [%s]' "$(status "$state")"
    fi
    printf '\n'
}
ask() {
    local prompt="$1"
    local default="${2:-}"
    local answer
    printf '%s' "$prompt"
    IFS= read -r answer || answer=""
    printf '%s' "${answer:-$default}"
}
# ---------- 页面 ----------
brand() {
    printf '%s%sNYKI%s / VPS NETWORK CHECK%s\n' \
        "$BOLD" "$CYAN" "$RESET" "$RESET"
    printf 'VPS 网络检测工具\n'
    printf '%s作者   %s%s\n' "$DIM" "$AUTHOR" "$RESET"
    printf '%s主页   %s%s\n' "$DIM" "$WEBSITE" "$RESET"
    printf '%s项目   %s%s\n' "$DIM" "$PROJECT" "$RESET"
    printf '%s版本   %s%s\n' "$DIM" "$VERSION" "$RESET"
    separator
}
page_title() {
    clear_screen
    brand
    printf '%s%s%s\n' "$BOLD" "$1" "$RESET"
    separator
}
# 统一检测入口：
# r/R = 重测；回车 = 返回主菜单。
run_check() {
    local title="$1"
    local function_name="$2"
    local answer
    while true; do
        page_title "$title"
        "$function_name"
        printf '\n'
        separator
        printf '[R] 重新检测    [回车] 返回主菜单\n'
        printf '> '
        IFS= read -r answer || answer=""
        case "$answer" in
            r|R) continue ;;
            *)   break ;;
        esac
    done
}
# ---------- 网络函数 ----------
get_public_ip() {
    local family="$1"
    local result=""
    if has_cmd curl; then
        result="$(
            curl "-$family" -fsS \
                --connect-timeout "$TIMEOUT" \
                --max-time 10 \
                https://api.ipify.org 2>/dev/null
        )" || result=""
    elif has_cmd wget; then
        result="$(
            wget "-$family" -qO- \
                --timeout=10 \
                https://api.ipify.org 2>/dev/null
        )" || result=""
    fi
    if [[ "$family" == "4" ]]; then
        [[ "$result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    else
        [[ "$result" == *:* ]] || return 1
    fi
    printf '%s' "$result"
}
get_default_gateway() {
    if has_cmd ip; then
        ip route show default 2>/dev/null |
            awk 'NR==1 {
                for (i=1;i<=NF;i++) {
                    if ($i=="via") {
                        print $(i+1)
                        exit
                    }
                }
            }'
    fi
}
# ---------- 01 全面检测 ----------
check_all() {
    local ip4="" ip6="" gateway=""
    printf '\n基础网络\n'
    if ip4="$(get_public_ip 4)"; then
        row "公网 IPv4" "$ip4" "正常"
    else
        row "公网 IPv4" "无法获取" "不可用"
    fi
    if ip6="$(get_public_ip 6)"; then
        row "公网 IPv6" "$ip6" "正常"
    else
        row "公网 IPv6" "无法获取或不支持" "不可用"
    fi
    gateway="$(get_default_gateway)"
    row "默认网关" "${gateway:-未发现}" "$([[ -n "$gateway" ]] && echo 正常 || echo 注意)"
    printf '\n网络连通性\n'
    if has_cmd ping && ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        row "IPv4 Ping" "1.1.1.1 可达" "正常"
    else
        row "IPv4 Ping" "无响应或 ICMP 受限" "异常"
    fi
    if has_cmd curl &&
        curl -fsS -o /dev/null \
            --connect-timeout "$TIMEOUT" \
            --max-time 10 https://www.cloudflare.com; then
        row "HTTPS 连接" "Cloudflare 可访问" "正常"
    else
        row "HTTPS 连接" "连接失败或超时" "异常"
    fi
    printf '\nDNS 解析\n'
    if has_cmd getent && getent ahosts example.com >/dev/null 2>&1; then
        row "DNS 查询" "example.com 解析成功" "正常"
    elif has_cmd nslookup && nslookup example.com >/dev/null 2>&1; then
        row "DNS 查询" "example.com 解析成功" "正常"
    else
        row "DNS 查询" "解析失败或缺少工具" "异常"
    fi
}
# ---------- 02 IPv4 检测 ----------
check_ipv4() {
    local ip gateway route
    printf '\n公网地址\n'
    if ip="$(get_public_ip 4)"; then
        row "公网 IPv4" "$ip" "正常"
    else
        row "公网 IPv4" "无法获取" "异常"
    fi
    printf '\n本机路由\n'
    gateway="$(get_default_gateway)"
    row "默认网关" "${gateway:-未发现}"
    if has_cmd ip; then
        route="$(ip -4 route get 1.1.1.1 2>/dev/null | head -n 1)"
        row "路由信息" "${route:-未发现}"
    else
        row "路由信息" "缺少 ip 命令" "不可用"
    fi
    printf '\n连通性\n'
    if has_cmd ping && ping -4 -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        row "Ping 测试" "成功" "正常"
    else
        row "Ping 测试" "失败或 ICMP 受限" "异常"
    fi
}
# ---------- 03 IPv6 检测 ----------
check_ipv6() {
    local ip route
    printf '\n公网地址\n'
    if ip="$(get_public_ip 6)"; then
        row "公网 IPv6" "$ip" "正常"
    else
        row "公网 IPv6" "无法获取或不支持" "不可用"
    fi
    printf '\n本机 IPv6\n'
    if has_cmd ip; then
        route="$(ip -6 route show default 2>/dev/null | head -n 1)"
        row "默认路由" "${route:-未发现}"
        ip -o -6 addr show scope global 2>/dev/null |
            while IFS= read -r entry; do
                row "接口地址" "$entry"
            done
    else
        row "网络工具" "缺少 ip 命令" "不可用"
    fi
    printf '\n连通性\n'
    if has_cmd ping && ping -6 -c 1 -W 3 2606:4700:4700::1111 >/dev/null 2>&1; then
        row "IPv6 Ping" "成功" "正常"
    else
        row "IPv6 Ping" "失败或 IPv6 不可用" "异常"
    fi
}
# ---------- 04 IP 信息查询 ----------
check_ip_info() {
    local ip data
    if ! has_cmd curl; then
        row "依赖检查" "请安装 curl" "不可用"
        return
    fi
    if ! ip="$(get_public_ip 4)"; then
        row "公网 IPv4" "无法获取" "异常"
        return
    fi
    row "查询地址" "$ip"
    data="$(
        curl -fsS --connect-timeout "$TIMEOUT" --max-time 10 \
            "https://ipapi.co/${ip}/json/" 2>/dev/null
    )" || data=""
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
 print("查询结果       : JSON 解析失败")
 sys.exit(0)
fields=[
 ("国家/地区","country_name"),
 ("国家代码","country_code"),
 ("城市","city"),
 ("地区","region"),
 ("时区","timezone"),
 ("网络组织","org"),
 ("ASN","asn")
]
for label,key in fields:
 v=d.get(key)
 if v:
  print(f"{label:<14} : {str(v).replace(chr(10), chr(32))}")
' 2>/dev/null |
            while IFS= read -r entry; do
                printf '  %s\n' "$entry"
            done
    else
        row "查询结果" "缺少 python3，无法解析数据" "不可用"
    fi
}
# ---------- 05 本机网络配置 ----------
check_network_config() {
    printf '\n系统信息\n'
    row "操作系统" "$(
        if [[ -r /etc/os-release ]]; then
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-Linux}"
        else
            uname -s
        fi
    )"
    row "内核版本" "$(uname -r)"
    row "主机名称" "$(hostname 2>/dev/null || echo 未知)"
    row "系统架构" "$(uname -m)"
    printf '\n网络接口\n'
    if has_cmd ip; then
        ip -brief addr show 2>/dev/null |
            while IFS= read -r entry; do
                row "接口" "$entry"
            done
    else
        row "网络工具" "缺少 ip 命令" "不可用"
    fi
    printf '\nDNS 配置\n'
    if [[ -r /etc/resolv.conf ]]; then
        awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' \
            /etc/resolv.conf |
            while IFS= read -r entry; do
                row "DNS 服务器" "$entry"
            done
    else
        row "DNS 配置" "无法读取" "不可用"
    fi
}
# ---------- 06 流媒体检测 ----------
check_streaming() {
    local name url code
    if ! has_cmd curl; then
        row "依赖检查" "请安装 curl" "不可用"
        return
    fi
    local -a sites=(
        "Netflix|https://www.netflix.com"
        "YouTube|https://www.youtube.com"
        "Disney+|https://www.disneyplus.com"
        "OpenAI|https://chatgpt.com"
        "Google|https://www.google.com"
        "BBC|https://www.bbc.com"
    )
    printf '\n网站连通性\n'
    for entry in "${sites[@]}"; do
        name="${entry%%|*}"
        url="${entry#*|}"
        code="$(
            curl -L -sS -o /dev/null \
                --connect-timeout "$TIMEOUT" \
                --max-time 10 \
                -w '%{http_code}' "$url" 2>/dev/null
        )" || code=""
        if [[ "$code" =~ ^[0-9]{3}$ ]] && (( 10#$code >= 200 && 10#$code < 500 )); then
            row "$name" "HTTP $code" "可达"
        elif [[ "$code" =~ ^[0-9]{3}$ ]]; then
            row "$name" "HTTP $code" "异常"
        else
            row "$name" "连接失败或超时" "不可用"
        fi
    done
    printf '\n%s网站可访问不代表已获得流媒体播放权限。%s\n' "$DIM" "$RESET"
}
# ---------- 07 网络诊断与路由追踪 ----------
check_route() {
    local target
    target="$(ask '请输入目标 [默认 1.1.1.1]：' '1.1.1.1')"
    if [[ ! "$target" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
        row "输入检查" "目标格式不合法" "异常"
        return
    fi
    row "诊断目标" "$target"
    printf '\nPing 检测\n'
    if has_cmd ping; then
        ping -c 4 -W 3 "$target" 2>&1 |
            while IFS= read -r entry; do
                printf '  %s\n' "$entry"
            done
    else
        row "Ping" "缺少 ping 命令" "不可用"
    fi
    printf '\n路由追踪\n'
    if has_cmd tracepath; then
        tracepath -m 12 "$target" 2>&1 |
            while IFS= read -r entry; do
                printf '  %s\n' "$entry"
            done
    elif has_cmd traceroute; then
        traceroute -m 12 -w 2 "$target" 2>&1 |
            while IFS= read -r entry; do
                printf '  %s\n' "$entry"
            done
    else
        row "路由追踪" "请安装 tracepath 或 traceroute" "不可用"
    fi
}
# ---------- 08 DNS 解析检测 ----------
check_dns() {
    local domain result
    domain="$(ask '请输入域名 [默认 example.com]：' 'example.com')"
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        row "输入检查" "域名格式不合法" "异常"
        return
    fi
    row "查询域名" "$domain"
    if has_cmd dig; then
        printf '\nA 记录\n'
        result="$(dig +time=3 +tries=1 +short A "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            while IFS= read -r entry; do
                row "IPv4" "$entry"
            done <<< "$result"
        else
            row "IPv4" "没有记录" "注意"
        fi
        printf '\nAAAA 记录\n'
        result="$(dig +time=3 +tries=1 +short AAAA "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            while IFS= read -r entry; do
                row "IPv6" "$entry"
            done <<< "$result"
        else
            row "IPv6" "没有记录" "注意"
        fi
        printf '\nNS 记录\n'
        result="$(dig +time=3 +tries=1 +short NS "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            while IFS= read -r entry; do
                row "NS" "$entry"
            done <<< "$result"
        else
            row "NS" "没有记录" "注意"
        fi
    elif has_cmd getent; then
        result="$(getent ahosts "$domain" 2>/dev/null)"
        if [[ -n "$result" ]]; then
            printf '%s\n' "$result" |
                awk '!seen[$1]++ {print $1}' |
                while IFS= read -r entry; do
                    row "解析地址" "$entry"
                done
        else
            row "DNS 结果" "解析失败" "异常"
        fi
    else
        row "依赖检查" "请安装 dig 或 getent" "不可用"
    fi
}
# ---------- 09 系统信息 ----------
check_system() {
    printf '\n系统信息\n'
    row "操作系统" "$(
        if [[ -r /etc/os-release ]]; then
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-Linux}"
        else
            uname -s
        fi
    )"
    row "内核版本" "$(uname -r)"
    row "主机名称" "$(hostname 2>/dev/null || echo 未知)"
    row "系统架构" "$(uname -m)"
    row "运行时间" "$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo 未知)"
    printf '\nCPU 信息\n'
    if [[ -r /proc/cpuinfo ]]; then
        row "CPU 型号" "$(
            awk -F ': ' '/model name/ {print $2; exit}' /proc/cpuinfo
        )"
        row "CPU 核心" "$(
            awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo
        )"
    else
        row "CPU 信息" "无法读取" "不可用"
    fi
    printf '\n内存与磁盘\n'
    if has_cmd free; then
        row "内存" "$(free -h 2>/dev/null | awk '/^Mem:/ {print "总计 "$2" / 已用 "$3" / 可用 "$7}')"
    else
        row "内存" "缺少 free 命令" "不可用"
    fi
    if has_cmd df; then
        row "根分区" "$(df -hP / 2>/dev/null | awk 'NR==2 {print "容量 "$2" / 已用 "$3" / 可用 "$4" / 使用率 "$5}')"
    fi
    if has_cmd systemd-detect-virt; then
        row "虚拟化" "$(systemd-detect-virt 2>/dev/null || echo 未识别)"
    fi
}
# ---------- 10 网站连通性检测 ----------
check_website() {
    local url code elapsed
    url="$(ask '请输入网址 [默认 https://www.cloudflare.com]：' 'https://www.cloudflare.com')"
    if [[ ! "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        row "输入检查" "请输入有效的 HTTP/HTTPS 网址" "异常"
        return
    fi
    if ! has_cmd curl; then
        row "依赖检查" "请安装 curl" "不可用"
        return
    fi
    row "检测网址" "$url"
    code="$(
        curl -L -sS -o /dev/null \
            --connect-timeout "$TIMEOUT" \
            --max-time 20 \
            -w '%{http_code}' "$url" 2>/dev/null
    )" || code=""
    elapsed="$(
        curl -L -sS -o /dev/null \
            --connect-timeout "$TIMEOUT" \
            --max-time 20 \
            -w '%{time_total}' "$url" 2>/dev/null
    )" || elapsed=""
    if [[ "$code" =~ ^[0-9]{3}$ ]] && (( 10#$code >= 200 && 10#$code < 400 )); then
        row "HTTP 状态码" "$code" "正常"
    elif [[ "$code" =~ ^[0-9]{3}$ ]]; then
        row "HTTP 状态码" "$code" "异常"
    else
        row "HTTP 状态码" "连接失败或超时" "异常"
    fi
    row "请求耗时" "${elapsed:+${elapsed} 秒}"
}
# ---------- 11 网络质量检测 ----------
check_quality() {
    local target="1.1.1.1"
    local output loss avg
    if ! has_cmd ping; then
        row "依赖检查" "请安装 ping" "不可用"
        return
    fi
    row "检测目标" "$target"
    row "检测次数" "4"
    output="$(ping -c 4 -W 3 "$target" 2>&1)" || true
    printf '\nPing 结果\n'
    while IFS= read -r entry; do
        printf '  %s\n' "$entry"
    done <<< "$output"
    loss="$(
        printf '%s\n' "$output" |
            sed -nE 's/.* ([0-9.]+)% packet loss.*/\1%/p'
    )"
    avg="$(
        printf '%s\n' "$output" |
            awk -F ' = ' '/^rtt |^round-trip / {
                split($2,a,"/")
                if (a[2] != "") print a[2] " ms"
            }'
    )"
    printf '\n质量摘要\n'
    row "丢包率" "${loss:-未获取}"
    row "平均延迟" "${avg:-未获取}"
}
# ---------- 12 TCP 端口连通性检测 ----------
check_tcp() {
    local host port
    host="$(ask '请输入目标主机 [默认 example.com]：' 'example.com')"
    port="$(ask '请输入 TCP 端口 [默认 443]：' '443')"
    if [[ ! "$host" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
        row "输入检查" "主机格式不合法" "异常"
        return
    fi
    if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] ||
        (( 10#$port < 1 || 10#$port > 65535 )); then
        row "输入检查" "端口必须是 1-65535 的整数" "异常"
        return
    fi
    row "目标主机" "$host"
    row "目标端口" "$port"
    if has_cmd nc; then
        if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
            row "TCP 连接" "连接成功" "正常"
        else
            row "TCP 连接" "连接失败或超时" "异常"
        fi
    elif has_cmd timeout; then
        if timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" >/dev/null 2>&1; then
            row "TCP 连接" "连接成功" "正常"
        else
            row "TCP 连接" "连接失败或超时" "异常"
        fi
    else
        row "依赖检查" "请安装 nc 或 timeout" "不可用"
    fi
}
# ---------- 13 MTU 排查 ----------
check_mtu() {
    local target="1.1.1.1"
    local low=0 high=1472 mid found=-1 mtu
    if ! has_cmd ping; then
        row "依赖检查" "请安装 ping" "不可用"
        return
    fi
    row "检测目标" "$target"
    row "检测方式" "IPv4 DF 探测"
    if ! ping -4 -M do -c 1 -W 2 "$target" >/dev/null 2>&1; then
        row "基础连通性" "目标无响应，结果可能不准确" "注意"
    fi
    while (( low <= high )); do
        mid=$(( (low + high) / 2 ))
        if ping -4 -M do -c 1 -W 2 -s "$mid" "$target" >/dev/null 2>&1; then
            found="$mid"
            low=$(( mid + 1 ))
        else
            high=$(( mid - 1 ))
        fi
    done
    if (( found >= 0 )); then
        mtu=$(( found + 28 ))
        row "最大载荷" "${found} bytes"
        row "估算路径 MTU" "${mtu} bytes"
        if (( mtu < 1500 )); then
            row "检测提示" "路径 MTU 可能小于 1500" "注意"
        else
            row "检测提示" "探测到标准 MTU" "正常"
        fi
    else
        row "检测结果" "无法确定 MTU" "异常"
    fi
    printf '\n%s注意：防火墙过滤 ICMP 时，MTU 探测可能不准确。%s\n' "$DIM" "$RESET"
}
# ---------- 菜单 ----------
show_menu() {
    clear_screen
    brand
    printf '%s检测功能%s\n' "$BOLD" "$RESET"
    printf '  01  全面检测\n'
    printf '  02  IPv4 地址检测\n'
    printf '  03  IPv6 地址检测\n'
    printf '  04  IP 信息查询\n'
    printf '  05  本机网络配置\n'
    printf '  06  流媒体检测\n'
    printf '  07  网络诊断与路由追踪\n'
    printf '  08  DNS 解析检测\n'
    printf '  09  系统信息\n'
    printf '  10  网站连通性检测\n'
    printf '  11  网络质量检测\n'
    printf '  12  TCP 端口连通性检测\n'
    printf '  13  MTU 排查\n'
    separator
    if (( HIDE_IP )); then
        printf '隐私设置：隐藏 IP 模式 [%s已开启%s]\n' "$GREEN" "$RESET"
    else
        printf '隐私设置：隐藏 IP 模式 [%s已关闭%s]\n' "$YELLOW" "$RESET"
    fi
    printf '  14  切换隐藏 IP 模式\n'
    separator
    printf '  00  退出\n\n'
}
main() {
    local choice
    while true; do
        show_menu
        printf '请输入选项 [00-14]：'
        IFS= read -r choice || break
        case "$choice" in
            1|01) run_check "全面检测" check_all ;;
            2|02) run_check "IPv4 地址检测" check_ipv4 ;;
            3|03) run_check "IPv6 地址检测" check_ipv6 ;;
            4|04) run_check "IP 信息查询" check_ip_info ;;
            5|05) run_check "本机网络配置" check_network_config ;;
            6|06) run_check "流媒体检测" check_streaming ;;
            7|07) run_check "网络诊断与路由追踪" check_route ;;
            8|08) run_check "DNS 解析检测" check_dns ;;
            9|09) run_check "系统信息" check_system ;;
            10) run_check "网站连通性检测" check_website ;;
            11) run_check "网络质量检测" check_quality ;;
            12) run_check "TCP 端口连通性检测" check_tcp ;;
            13) run_check "MTU 排查" check_mtu ;;
            14)
                if (( HIDE_IP )); then
                    HIDE_IP=0
                else
                    HIDE_IP=1
                fi
                ;;
            0|00|q|Q)
                printf '\n感谢使用 VPS 网络检测工具。\n'
                printf '项目地址：%s\n' "$PROJECT"
                exit 0
                ;;
            *)
                printf '\n%s无效选项，请输入 00-14。%s\n' "$YELLOW" "$RESET"
                sleep 1
                ;;
        esac
    done
}
main "$@"
