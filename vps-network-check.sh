#!/usr/bin/env bash
# ============================================================
# NYKI / VPS NETWORK CHECK
# VPS 网络检测工具
# Version : 2.3.0
# Author  : 阿晚
# Project : https://github.com/nyki4/vps-ip-check
# Website : https://nyki.cc
# ============================================================
VERSION="2.3.0"
APP_NAME="VPS 网络检测工具"
AUTHOR="阿晚"
PROJECT="github.com/nyki4/vps-ip-check"
WEBSITE="nyki.cc"
HIDE_IP=0
CONNECT_TIMEOUT=5
MAX_TIME=10
PING_COUNT=5
# ---------- 终端颜色 ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    WHITE=$'\033[97m'
else
    RESET=""
    BOLD=""
    DIM=""
    CYAN=""
    GREEN=""
    YELLOW=""
    RED=""
    WHITE=""
fi
# ---------- 基础工具 ----------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}
line() {
    printf '%s\n' '  ──────────────────────────────────────────'
}
section() {
    printf '\n  %s%s%s\n' "$BOLD" "$1" "$RESET"
    line
}
ok() {
    printf '  %s[正常]%s %s\n' "$GREEN" "$RESET" "$*"
}
warn() {
    printf '  %s[注意]%s %s\n' "$YELLOW" "$RESET" "$*"
}
fail() {
    printf '  %s[异常]%s %s\n' "$RED" "$RESET" "$*"
}
unknown() {
    printf '  %s[未知]%s %s\n' "$DIM" "$RESET" "$*"
}
pause_screen() {
    printf '\n'
    read -r -p "按 Enter 返回菜单..." _
}
# ---------- IP 校验 ----------
is_ipv4() {
    local ip="$1" a b c d extra octet
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS='.' read -r a b c d extra <<< "$ip"
    [[ -z "${extra:-}" ]] || return 1
    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#$octet <= 255 )) || return 1
    done
}
is_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9a-fA-F:.]+$ ]] || return 1
    if has_cmd python3; then
        printf '%s' "$ip" | python3 -c '
import ipaddress,sys
try:
    ipaddress.IPv6Address(sys.stdin.read())
except Exception:
    sys.exit(1)
' >/dev/null 2>&1
    else
        return 1
    fi
}
# ---------- IP 脱敏 ----------
mask_ip() {
    local ip="$1"
    if (( HIDE_IP == 0 )); then
        printf '%s' "$ip"
        return
    fi
    if is_ipv4 "$ip"; then
        local a b c d
        IFS='.' read -r a b c d <<< "$ip"
        printf '%s.%s.*.*' "$a" "$b"
    elif [[ "$ip" == *:* ]]; then
        if has_cmd python3; then
            printf '%s' "$ip" | python3 -c '
import ipaddress,sys
try:
    a=ipaddress.IPv6Address(sys.stdin.read())
    p=a.exploded.split(":")
    print(p[0]+":"+p[1]+":****:****:****:****:****:****")
except Exception:
    print("[IPv6 已隐藏]")
' 2>/dev/null
        else
            printf '%s' '[IPv6 已隐藏]'
        fi
    else
        printf '%s' "$ip"
    fi
}
mask_text() {
    local text="$1"
    if (( HIDE_IP == 0 )); then
        printf '%s' "$text"
        return
    fi
    if has_cmd python3; then
        printf '%s' "$text" | python3 -c '
import ipaddress,re,sys
s=sys.stdin.read()
pat=r"(?<![0-9A-Fa-f:.])(?:\d{1,3}(?:\.\d{1,3}){3}|[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7})(?![0-9A-Fa-f:.])"
def sub(m):
    v=m.group(0)
    try:
        a=ipaddress.ip_address(v)
        if a.version==4:
            p=str(a).split(".")
            return ".".join(p[:2]+["*","*"])
        p=a.exploded.split(":")
        return p[0]+":"+p[1]+":****:****:****:****:****:****"
    except Exception:
        return v
print(re.sub(pat,sub,s),end="")
' 2>/dev/null || printf '%s' '[详细内容已隐藏]'
    else
        printf '%s' '[详细内容已隐藏：缺少 Python 3]'
    fi
}
# ---------- HTTP 请求 ----------
http_get() {
    local url="$1" timeout="${2:-$MAX_TIME}"
    if has_cmd curl; then
        curl -fsSL --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$timeout" "$url" 2>/dev/null
    elif has_cmd wget; then
        wget -q -T "$timeout" -O - "$url" 2>/dev/null
    else
        return 127
    fi
}
http_code() {
    local url="$1"
    has_cmd curl || return 127
    curl -sSL -o /dev/null \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        -w '%{http_code}' "$url" 2>/dev/null || true
}
json_field() {
    local json="$1" path="$2"
    has_cmd python3 || return 1
    printf '%s' "$json" | python3 -c '
import json,sys
try:
    o=json.load(sys.stdin)
    for p in sys.argv[1].split("."):
        o=o.get(p) if isinstance(o,dict) else None
    if o is not None and not isinstance(o,(dict,list)):
        print(o)
except Exception:
    pass
' "$path" 2>/dev/null
}
# ---------- 获取公网 IP ----------
get_ipv4() {
    local ip=""
    if has_cmd curl; then
        ip="$(curl -4 -fsSL --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" https://api.ipify.org 2>/dev/null)" || ip=""
    fi
    if ! is_ipv4 "$ip"; then
        ip="$(http_get https://ipv4.icanhazip.com "$MAX_TIME" 2>/dev/null |
            tr -d '[:space:]')"
    fi
    is_ipv4 "$ip" && printf '%s' "$ip"
}
get_ipv6() {
    local ip=""
    if has_cmd curl; then
        ip="$(curl -6 -fsSL --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" https://api6.ipify.org 2>/dev/null)" || ip=""
    fi
    if ! is_ipv6 "$ip"; then
        ip="$(curl -6 -fsSL --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" https://ipv6.icanhazip.com 2>/dev/null |
            tr -d '[:space:]')" || ip=""
    fi
    is_ipv6 "$ip" && printf '%s' "$ip"
}
# ---------- 界面 ----------
header() {
    clear 2>/dev/null || true
    printf '\n'
    printf '  %sNYKI%s / VPS NETWORK CHECK\n' "$CYAN" "$RESET"
    printf '  %s\n' "$APP_NAME"
    line
    printf '  版本  v%s\n' "$VERSION"
    printf '  作者  %s\n' "$AUTHOR"
    printf '  项目  %s\n' "$PROJECT"
    printf '  网站  %s\n' "$WEBSITE"
    printf '\n'
}
show_menu() {
    header
    section "网络检测"
    printf '   01  全面检测\n'
    printf '   02  IPv4 地址检测\n'
    printf '   03  IPv6 地址检测\n'
    printf '   04  IP 信息查询\n'
    printf '   05  本机网络配置\n'
    printf '   06  流媒体检测\n'
    printf '   07  网络诊断与路由追踪\n'
    printf '   08  DNS 解析检测\n'
    printf '   09  系统信息\n'
    printf '   10  网站连通性检测\n'
    printf '   11  网络质量检测\n'
    printf '   12  TCP 端口连通性检测\n'
    printf '   13  MTU 排查\n'
    section "隐私设置"
    if (( HIDE_IP == 1 )); then
        printf '  隐藏 IP 模式  %s[开启]%s\n' "$GREEN" "$RESET"
    else
        printf '  隐藏 IP 模式  %s[关闭]%s\n' "$YELLOW" "$RESET"
    fi
    printf '\n'
    printf '   14  切换隐藏 IP 模式\n'
    printf '   00  退出\n'
    line
}
# ---------- IPv4 ----------
check_ipv4() {
    section "IPv4 地址检测"
    local ip
    ip="$(get_ipv4)"
    if is_ipv4 "$ip"; then
        ok "公网 IPv4：$(mask_ip "$ip")"
    else
        fail "未能获取公网 IPv4 地址"
    fi
    if has_cmd curl; then
        if curl -4 -fsSL -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://www.cloudflare.com 2>/dev/null; then
            ok "IPv4 HTTPS 连通性正常"
        else
            fail "IPv4 HTTPS 测试失败"
        fi
    else
        unknown "缺少 curl"
    fi
}
# ---------- IPv6 ----------
check_ipv6() {
    section "IPv6 地址检测"
    local ip
    ip="$(get_ipv6)"
    if is_ipv6 "$ip"; then
        ok "公网 IPv6：$(mask_ip "$ip")"
    else
        warn "未获取到公网 IPv6 地址"
    fi
    if has_cmd curl; then
        if curl -6 -fsSL -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://www.cloudflare.com 2>/dev/null; then
            ok "IPv6 HTTPS 连通性正常"
        else
            warn "IPv6 HTTPS 失败或当前网络不支持 IPv6"
        fi
    else
        unknown "缺少 curl"
    fi
}
# ---------- IP 信息 ----------
ip_info() {
    section "IP 信息查询"
    local family ip json success
    printf '  [4] IPv4\n'
    printf '  [6] IPv6\n'
    printf '  [0] 返回\n'
    read -r -p "  选择类型：" family
    case "$family" in
        4) ip="$(get_ipv4)" ;;
        6) ip="$(get_ipv6)" ;;
        0) return ;;
        *) warn "无效选项"; return ;;
    esac
    [[ -n "$ip" ]] || {
        fail "未获取到公网 IP"
        return
    }
    printf '\n  查询地址：%s\n' "$(mask_ip "$ip")"
    json="$(http_get "https://ipwho.is/$ip" "$MAX_TIME")" || {
        fail "IP 信息接口请求失败"
        return
    }
    success="$(json_field "$json" success)"
    [[ "$success" == "True" || "$success" == "true" ]] || {
        fail "IP 信息查询失败"
        return
    }
    printf '  国家/地区：%s\n' "$(json_field "$json" country)"
    printf '  地区：%s\n' "$(json_field "$json" region)"
    printf '  城市：%s\n' "$(json_field "$json" city)"
    printf '  运营商：%s\n' "$(json_field "$json" connection.isp)"
    printf '  组织：%s\n' "$(json_field "$json" connection.org)"
    printf '  ASN：%s\n' "$(json_field "$json" connection.asn)"
}
# ---------- 本机网络配置 ----------
network_config() {
    section "本机网络配置"
    printf '  主机名：'
    if (( HIDE_IP == 1 )); then
        printf '[已隐藏]\n'
    elif has_cmd hostname; then
        hostname 2>/dev/null || printf '未知\n'
    else
        printf '未知\n'
    fi
    if has_cmd ip; then
        printf '\n  网卡地址：\n'
        if (( HIDE_IP == 1 )); then
            ip -o addr show 2>/dev/null |
                while IFS= read -r row; do
                    mask_text "$row"
                    printf '\n'
                done
        else
            ip -brief addr show 2>/dev/null || ip addr show
        fi
        printf '\n  默认路由：\n'
        if (( HIDE_IP == 1 )); then
            {
                ip route show default 2>/dev/null
                ip -6 route show default 2>/dev/null
            } | while IFS= read -r row; do
                mask_text "$row"
                printf '\n'
            done
        else
            ip route show default 2>/dev/null
            ip -6 route show default 2>/dev/null
        fi
    else
        unknown "缺少 ip 命令"
    fi
    printf '\n  DNS 配置：\n'
    if [[ -r /etc/resolv.conf ]]; then
        grep -E '^[[:space:]]*nameserver' /etc/resolv.conf |
            while IFS= read -r row; do
                if (( HIDE_IP == 1 )); then
                    printf '  %s\n' "$(mask_text "$row")"
                else
                    printf '  %s\n' "$row"
                fi
            done
    else
        unknown "无法读取 DNS 配置"
    fi
}
# ---------- DNS ----------
dns_check() {
    section "DNS 解析检测"
    local domain result server
    read -r -p "  输入域名（默认 example.com）：" domain
    domain="${domain:-example.com}"
    printf '\n  检测域名：%s\n' "$domain"
    if has_cmd getent; then
        result="$(getent ahosts "$domain" 2>/dev/null |
            awk '{print $1}' | sort -u)"
        if [[ -n "$result" ]]; then
            ok "系统 DNS 解析成功"
            while IFS= read -r row; do
                [[ -n "$row" ]] && printf '    %s\n' "$(mask_ip "$row")"
            done <<< "$result"
        else
            fail "系统 DNS 解析失败"
        fi
    elif has_cmd nslookup; then
        result="$(nslookup "$domain" 2>&1)"
        printf '%s\n' "$(mask_text "$result")"
    else
        unknown "缺少 getent 和 nslookup"
    fi
    if has_cmd dig; then
        for server in 1.1.1.1 8.8.8.8 9.9.9.9; do
            result="$(dig +time=3 +tries=1 +short @"$server" "$domain" A 2>/dev/null)"
            if [[ -n "$result" ]]; then
                ok "公共 DNS $server 解析成功"
                while IFS= read -r row; do
                    [[ -n "$row" ]] && printf '    %s\n' "$(mask_ip "$row")"
                done <<< "$result"
            else
                warn "公共 DNS $server 没有返回 A 记录"
            fi
        done
    else
        warn "缺少 dig，跳过公共 DNS 对比"
    fi
}
# ---------- 系统信息 ----------
system_info() {
    section "系统信息"
    printf '  操作系统：'
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s\n' "${PRETTY_NAME:-未知}"
    else
        uname -s
    fi
    printf '  内核版本：%s\n' "$(uname -r)"
    printf '  系统架构：%s\n' "$(uname -m)"
    printf '  Bash 版本：%s\n' "$BASH_VERSION"
    if has_cmd uptime; then
        printf '  运行时间：'
        uptime -p 2>/dev/null || uptime
    fi
    if has_cmd free; then
        printf '\n  内存信息：\n'
        free -h
    fi
    if has_cmd df; then
        printf '\n  根分区：\n'
        df -h / 2>/dev/null
    fi
}
# ---------- 网站连通性 ----------
website_check() {
    section "网站连通性检测"
    local url code
    read -r -p "  输入网址（默认 https://www.cloudflare.com）：" url
    url="${url:-https://www.cloudflare.com}"
    [[ "$url" =~ ^https?:// ]] || url="https://$url"
    if ! has_cmd curl; then
        unknown "缺少 curl"
        return
    fi
    code="$(http_code "$url")"
    if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
        if (( 10#$code >= 200 && 10#$code < 400 )); then
            ok "HTTP 状态码：$code"
        else
            warn "HTTP 状态码：$code"
        fi
    else
        fail "请求失败或连接超时"
    fi
}
# ---------- 网络质量 ----------
network_quality() {
    section "网络质量检测"
    local target output
    read -r -p "  测试目标（默认 1.1.1.1）：" target
    target="${target:-1.1.1.1}"
    printf '\n  测试目标：%s\n' "$(mask_ip "$target")"
    if has_cmd ping; then
        output="$(ping -c "$PING_COUNT" -W 2 "$target" 2>&1)"
        local rc=$?
        printf '%s\n' "$(mask_text "$output")"
        if (( rc == 0 )); then
            ok "Ping 测试完成"
        else
            warn "Ping 未完全成功，目标可能限制 ICMP"
        fi
    else
        unknown "缺少 ping"
    fi
    if has_cmd curl; then
        local timing
        timing="$(curl -sS -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -w 'DNS=%{time_namelookup}s 连接=%{time_connect}s TLS=%{time_appconnect}s 总耗时=%{time_total}s' \
            https://www.cloudflare.com 2>/dev/null)" || timing=""
        if [[ -n "$timing" ]]; then
            printf '\n  HTTPS 耗时：%s\n' "$timing"
        else
            warn "HTTPS 计时请求失败"
        fi
    fi
}
# ---------- TCP 端口 ----------
tcp_check() {
    section "TCP 端口连通性检测"
    local host port
    read -r -p "  目标主机或 IP：" host
    [[ -n "$host" ]] || {
        warn "目标不能为空"
        return
    }
    read -r -p "  目标端口：" port
    [[ "$port" =~ ^[0-9]+$ ]] || {
        fail "端口必须是数字"
        return
    }
    (( port >= 1 && port <= 65535 )) || {
        fail "端口范围为 1-65535"
        return
    }
    printf '\n  检测目标：%s:%s\n' "$(mask_ip "$host")" "$port"
    if has_cmd python3; then
        if python3 - "$host" "$port" "$CONNECT_TIMEOUT" <<'PY'
import socket,sys
host,port,timeout=sys.argv[1],int(sys.argv[2]),float(sys.argv[3])
try:
    with socket.create_connection((host,port),timeout=timeout):
        print("TCP 连接成功")
except Exception as e:
    print("连接失败："+type(e).__name__)
    sys.exit(1)
PY
        then
            ok "TCP 端口可连接"
        else
            fail "连接失败，请检查目标服务、防火墙和路由"
        fi
    elif has_cmd nc; then
        if nc -z -w "$CONNECT_TIMEOUT" "$host" "$port" 2>/dev/null; then
            ok "TCP 端口可连接"
        else
            fail "TCP 连接失败"
        fi
    else
        unknown "需要 Python 3 或 nc"
    fi
}
# ---------- MTU ----------
mtu_check() {
    section "MTU 排查"
    if ! has_cmd ping; then
        unknown "缺少 ping，无法执行 MTU 探测"
        return
    fi
    local target size success=0
    read -r -p "  目标地址（默认 1.1.1.1）：" target
    target="${target:-1.1.1.1}"
    printf '\n  尝试 IPv4 DF 探测，不会修改网卡配置。\n'
    for size in 1472 1464 1452 1400 1300 1200; do
        printf '  负载 %s 字节：' "$size"
        if ping -4 -c 1 -W 2 -M do -s "$size" "$target" >/dev/null 2>&1; then
            printf '收到响应\n'
            success=$size
            break
        else
            printf '失败或未响应\n'
        fi
    done
    if (( success > 0 )); then
        ok "成功响应的探测负载：$success 字节"
        printf '  对应估算路径 MTU：约 %s 字节\n' "$((success + 28))"
        warn "仅为粗略估算，目标过滤 ICMP 时结果可能不准确"
    else
        warn "未获得有效响应，不能据此断定 MTU 异常"
    fi
}
# ---------- 路由追踪 ----------
route_trace() {
    section "网络诊断与路由追踪"
    local target
    read -r -p "  目标地址（默认 1.1.1.1）：" target
    target="${target:-1.1.1.1}"
    printf '\n  目标：%s\n' "$(mask_ip "$target")"
    if has_cmd traceroute; then
        if (( HIDE_IP == 1 )); then
            traceroute -m 12 -w 1 "$target" 2>&1 |
                while IFS= read -r row; do
                    printf '%s\n' "$(mask_text "$row")"
                done
        else
            traceroute -m 12 -w 1 "$target" 2>&1
        fi
    elif has_cmd tracepath; then
        if (( HIDE_IP == 1 )); then
            tracepath -m 12 "$target" 2>&1 |
                while IFS= read -r row; do
                    printf '%s\n' "$(mask_text "$row")"
                done
        else
            tracepath -m 12 "$target" 2>&1
        fi
    else
        unknown "缺少 traceroute 和 tracepath"
    fi
    warn "路由节点不响应，不一定代表该节点存在故障"
}
# ---------- 流媒体可达性 ----------
streaming_check() {
    section "流媒体检测"
    if ! has_cmd curl; then
        unknown "缺少 curl"
        return
    fi
    local url code
    for url in \
        https://www.netflix.com \
        https://www.youtube.com \
        https://www.disneyplus.com \
        https://www.google.com
    do
        code="$(http_code "$url")"
        if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
            if (( 10#$code < 500 )); then
                ok "$url 可访问（HTTP $code）"
            else
                warn "$url 返回 HTTP $code"
            fi
        else
            fail "$url 请求失败或超时"
        fi
    done
    warn "这里只检测网站可达性，不代表已验证区域解锁或播放权限"
}
# ---------- 全面检测 ----------
full_check() {
    section "全面检测"
    local ip output code
    printf '\n  1/6  IPv4\n'
    ip="$(get_ipv4)"
    if is_ipv4 "$ip"; then
        ok "公网 IPv4：$(mask_ip "$ip")"
    else
        fail "公网 IPv4 获取失败"
    fi
    printf '\n  2/6  IPv6\n'
    ip="$(get_ipv6)"
    if is_ipv6 "$ip"; then
        ok "公网 IPv6：$(mask_ip "$ip")"
    else
        warn "未获取到公网 IPv6"
    fi
    printf '\n  3/6  DNS\n'
    if has_cmd getent && getent ahosts example.com >/dev/null 2>&1; then
        ok "系统 DNS 解析成功"
    else
        warn "DNS 解析失败或缺少 getent"
    fi
    printf '\n  4/6  HTTPS\n'
    if has_cmd curl && curl -fsSL -o /dev/null \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" https://www.cloudflare.com 2>/dev/null; then
        ok "HTTPS 请求成功"
    else
        fail "HTTPS 请求失败或缺少 curl"
    fi
    printf '\n  5/6  网络质量\n'
    if has_cmd ping; then
        output="$(ping -c 3 -W 2 1.1.1.1 2>&1)"
        if (( $? == 0 )); then
            ok "ICMP 探测有响应"
            printf '%s\n' "$(mask_text "$output" | tail -n 3)"
        else
            warn "ICMP 探测失败，可能是目标限制"
        fi
    else
        unknown "缺少 ping"
    fi
    printf '\n  6/6  HTTPS 状态\n'
    code="$(http_code https://www.google.com)"
    if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
        ok "HTTP 状态码：$code"
    else
        warn "未能获取 HTTP 状态"
    fi
    printf '\n'
    line
    printf '  全面检测完成。需要时可单独运行 DNS、端口和 MTU 检测。\n'
}
# ---------- 隐藏模式 ----------
toggle_privacy() {
    if (( HIDE_IP == 0 )); then
        HIDE_IP=1
        ok "隐藏 IP 模式已开启"
    else
        HIDE_IP=0
        warn "隐藏 IP 模式已关闭"
    fi
    sleep 1
}
# ---------- 主循环 ----------
main() {
    while true; do
        show_menu
        read -r -p "  请输入选项：" choice
        case "$choice" in
            1|01) full_check; pause_screen ;;
            2|02) check_ipv4; pause_screen ;;
            3|03) check_ipv6; pause_screen ;;
            4|04) ip_info; pause_screen ;;
            5|05) network_config; pause_screen ;;
            6|06) streaming_check; pause_screen ;;
            7|07) route_trace; pause_screen ;;
            8|08) dns_check; pause_screen ;;
            9|09) system_info; pause_screen ;;
            10) website_check; pause_screen ;;
            11) network_quality; pause_screen ;;
            12) tcp_check; pause_screen ;;
            13) mtu_check; pause_screen ;;
            14) toggle_privacy ;;
            0|00|q|Q|exit)
                printf '\n  感谢使用 %s。\n\n' "$APP_NAME"
                exit 0
                ;;
            *)
                warn "无效选项，请重新输入"
                sleep 1
                ;;
        esac
    done
}
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '请使用 Bash 运行此脚本。\n' >&2
    exit 1
fi
main "$@"
