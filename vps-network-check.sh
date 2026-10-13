#!/usr/bin/env bash
# ============================================================
# NYKI // NETWORK DIAGNOSTICS
# VPS 网络检测工具
# Version : 2.3.0
# Author  : 阿晚 (AWAN)
# Website : https://nyki.cc
# Project : https://github.com/nyki4/vps-ip-check
# ============================================================
VERSION="2.3.0"
AUTHOR="AWAN / 阿晚"
WEBSITE="nyki.cc"
PROJECT="github.com/nyki4/vps-ip-check"
# ---------- 基础配置 ----------
APP_NAME="VPS 网络检测工具"
HIDE_IP=0
CONNECT_TIMEOUT=5
MAX_TIME=10
PING_COUNT=5
PANEL_WIDTH=54
# ---------- 颜色 ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_WHITE=$'\033[97m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
    C_WHITE=""
fi
# ---------- 基础工具 ----------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}
pause_screen() {
    printf '\n'
    read -r -p "按 Enter 返回主菜单..." _unused
}
line() {
    printf '%s\n' "------------------------------------------------------"
}
status_ok() {
    printf '%s[正常]%s %s\n' "$C_GREEN" "$C_RESET" "$*"
}
status_warn() {
    printf '%s[注意]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"
}
status_fail() {
    printf '%s[异常]%s %s\n' "$C_RED" "$C_RESET" "$*"
}
status_unknown() {
    printf '%s[未知]%s %s\n' "$C_DIM" "$C_RESET" "$*"
}
status_skip() {
    printf '%s[跳过]%s %s\n' "$C_DIM" "$C_RESET" "$*"
}
# ---------- IP 地址校验 ----------
is_ipv4() {
    local ip="$1"
    local a b c d extra
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS='.' read -r a b c d extra <<< "$ip"
    [[ -z "${extra:-}" ]] || return 1
    local octet
    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#$octet <= 255 )) || return 1
    done
    return 0
}
is_ipv6() {
    local ip="$1"
    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9a-fA-F:.]+$ ]] || return 1
    if has_cmd python3; then
        printf '%s' "$ip" | python3 -c '
import ipaddress, sys
try:
    ipaddress.IPv6Address(sys.stdin.read())
    sys.exit(0)
except Exception:
    sys.exit(1)
' >/dev/null 2>&1
        return $?
    fi
    # 无 Python 时使用系统工具辅助校验。
    if has_cmd ping6; then
        return 0
    fi
    return 1
}
# ---------- IP 脱敏 ----------
mask_one_ip() {
    local ip="$1"
    (( HIDE_IP == 1 )) || {
        printf '%s' "$ip"
        return
    }
    if is_ipv4 "$ip"; then
        local a b c d
        IFS='.' read -r a b c d <<< "$ip"
        printf '%s.%s.*.*' "$a" "$b"
        return
    fi
    if [[ "$ip" == *:* ]]; then
        # IPv6 脱敏采取保守策略，避免意外泄露完整地址。
        if has_cmd python3; then
            printf '%s' "$ip" | python3 -c '
import ipaddress, sys
try:
    a = ipaddress.IPv6Address(sys.stdin.read())
    print(a.exploded.split(":")[0] + ":" + a.exploded.split(":")[1] + ":****:****:****:****:****:****")
except Exception:
    print("[IPv6 已隐藏]")
' 2>/dev/null
        else
            printf '%s' '[IPv6 已隐藏]'
        fi
        return
    fi
    printf '%s' "$ip"
}
# 对可能混合 IP 地址的文本做尽可能保守的脱敏。
mask_text() {
    local text="$1"
    (( HIDE_IP == 1 )) || {
        printf '%s' "$text"
        return
    }
    if has_cmd python3; then
        printf '%s' "$text" | python3 -c '
import ipaddress, re, sys
s = sys.stdin.read()
def repl(m):
    token = m.group(0).strip("[](),;")
    prefix = m.group(0)[:len(m.group(0)) - len(m.group(0).lstrip("([,;"))]
    suffix = m.group(0)[len(m.group(0).rstrip("]),;")):]
    try:
        a = ipaddress.ip_address(token)
        if a.version == 4:
            parts = str(a).split(".")
            masked = ".".join(parts[:2] + ["*", "*"])
        else:
            parts = a.exploded.split(":")
            masked = parts[0] + ":" + parts[1] + ":****:****:****:****:****:****"
        return prefix + masked + suffix
    except Exception:
        return "[IP 已隐藏]"
pattern = r"(?<![0-9A-Fa-f:.])(?:\d{1,3}(?:\.\d{1,3}){3}|[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7})(?![0-9A-Fa-f:.])"
print(re.sub(pattern, repl, s), end="")
' 2>/dev/null || printf '%s' '[内容已隐藏]'
    else
        # 没有 Python 时，宁可隐藏可能包含 IP 的整段文本。
        printf '%s' '[详细内容已隐藏：缺少 Python 3]'
    fi
}
# ---------- HTTP 请求 ----------
http_get() {
    local url="$1"
    local timeout="${2:-$MAX_TIME}"
    if has_cmd curl; then
        curl -fsSL \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$timeout" \
            "$url" 2>/dev/null
    elif has_cmd wget; then
        wget -q -T "$timeout" -O - "$url" 2>/dev/null
    else
        return 127
    fi
}
http_code() {
    local url="$1"
    has_cmd curl || {
        printf '%s' "未知"
        return
    }
    curl -L -sS -o /dev/null \
        --connect-timeout "$CONNECT_TIMEOUT" \
        --max-time "$MAX_TIME" \
        -w '%{http_code}' "$url" 2>/dev/null || true
}
json_field() {
    local json="$1"
    local field="$2"
    has_cmd python3 || return 1
    printf '%s' "$json" | python3 -c '
import json, sys
path = sys.argv[1]
try:
    obj = json.load(sys.stdin)
    for part in path.split("."):
        if isinstance(obj, dict):
            obj = obj.get(part)
        else:
            obj = None
            break
    if obj is not None and not isinstance(obj, (dict, list)):
        print(obj)
except Exception:
    pass
' "$field" 2>/dev/null
}
# ---------- 公网 IP 获取 ----------
get_public_ipv4() {
    local ip=""
    if has_cmd curl; then
        ip="$(curl -4 -fsSL \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://api.ipify.org 2>/dev/null)" || ip=""
    fi
    if ! is_ipv4 "$ip"; then
        ip="$(http_get 'https://ipv4.icanhazip.com' "$MAX_TIME" 2>/dev/null | tr -d '[:space:]')"
    fi
    is_ipv4 "$ip" && printf '%s' "$ip"
}
get_public_ipv6() {
    local ip=""
    if has_cmd curl; then
        ip="$(curl -6 -fsSL \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://api6.ipify.org 2>/dev/null)" || ip=""
    fi
    if ! is_ipv6 "$ip"; then
        ip="$(curl -6 -fsSL \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://ipv6.icanhazip.com 2>/dev/null | tr -d '[:space:]')" || ip=""
    fi
    is_ipv6 "$ip" && printf '%s' "$ip"
}
# ---------- 通用界面 ----------
header() {
    clear 2>/dev/null || true
    printf '%s\n' "$C_CYAN"
    printf '%s\n' "======================================================"
    printf '%s\n' " NYKI // NETWORK DIAGNOSTICS"
    printf '%s\n' " VPS NETWORK CHECK SYSTEM"
    printf '%s\n' "======================================================"
    printf '%s\n' "$C_RESET"
    printf '  工具名称  : %s\n' "$APP_NAME"
    printf '  VERSION   : v%s\n' "$VERSION"
    printf '  DEVELOPER : %s\n' "$AUTHOR"
    printf '  PLATFORM  : Linux VPS\n'
    printf '  PROJECT   : %s\n' "$PROJECT"
    printf '  WEBSITE   : %s\n' "$WEBSITE"
    line
}
section() {
    printf '\n%s[%s]%s\n' "$C_CYAN" "$*" "$C_RESET"
    line
}
show_menu() {
    header
    printf '%s功能菜单%s\n' "$C_BOLD" "$C_RESET"
    line
    printf '  [01] 全面检测\n'
    printf '  [02] IPv4 地址检测\n'
    printf '  [03] IPv6 地址检测\n'
    printf '  [04] IP 信息查询\n'
    printf '  [05] 本机网络配置\n'
    printf '  [06] 流媒体检测\n'
    printf '  [07] 网络诊断与路由追踪\n'
    printf '  [08] DNS 解析检测\n'
    printf '  [09] 系统信息\n'
    printf '  [10] 网站连通性检测\n'
    printf '  [11] 网络质量检测\n'
    printf '  [12] TCP 端口连通性检测\n'
    printf '  [13] MTU 排查\n'
    line
    printf '  PRIVACY   隐藏 IP 模式：'
    if (( HIDE_IP == 1 )); then
        printf '%s[开启]%s\n' "$C_GREEN" "$C_RESET"
    else
        printf '%s[关闭]%s\n' "$C_YELLOW" "$C_RESET"
    fi
    printf '\n'
    printf '  [14] 切换隐藏 IP 模式\n'
    printf '  [00] 退出\n'
    line
}
# ---------- IPv4 检测 ----------
check_ipv4() {
    section "IPv4 地址检测"
    local ip
    ip="$(get_public_ipv4)"
    if is_ipv4 "$ip"; then
        status_ok "公网 IPv4：$(mask_one_ip "$ip")"
    else
        status_fail "未能获取公网 IPv4 地址"
    fi
    if has_cmd curl; then
        if curl -4 -fsSL -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://www.cloudflare.com 2>/dev/null; then
            status_ok "IPv4 HTTPS 连通性正常"
        else
            status_fail "IPv4 HTTPS 测试失败"
        fi
    else
        status_unknown "缺少 curl，无法执行 HTTPS 连通性测试"
    fi
}
# ---------- IPv6 检测 ----------
check_ipv6() {
    section "IPv6 地址检测"
    local ip
    ip="$(get_public_ipv6)"
    if is_ipv6 "$ip"; then
        status_ok "公网 IPv6：$(mask_one_ip "$ip")"
    else
        status_warn "未获取到公网 IPv6 地址"
    fi
    if has_cmd curl; then
        if curl -6 -fsSL -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://www.cloudflare.com 2>/dev/null; then
            status_ok "IPv6 HTTPS 连通性正常"
        else
            status_fail "IPv6 HTTPS 测试失败或当前网络不支持 IPv6"
        fi
    else
        status_unknown "缺少 curl，无法执行 IPv6 HTTPS 测试"
    fi
}
# ---------- IP 信息查询 ----------
ip_info() {
    section "IP 信息查询"
    local ip family json country region city isp org asn
    printf '选择查询类型：\n'
    printf '  [4] IPv4\n'
    printf '  [6] IPv6\n'
    printf '  [0] 返回\n'
    read -r -p "请输入选项：" family
    case "$family" in
        4) ip="$(get_public_ipv4)" ;;
        6) ip="$(get_public_ipv6)" ;;
        0) return ;;
        *) status_warn "无效选项"; return ;;
    esac
    if [[ -z "$ip" ]]; then
        status_fail "无法获取对应协议的公网 IP"
        return
    fi
    printf '查询地址：%s\n' "$(mask_one_ip "$ip")"
    json="$(http_get "https://ipwho.is/$ip" "$MAX_TIME")" || {
        status_fail "IP 信息接口请求失败"
        return
    }
    local success
    success="$(json_field "$json" success)"
    if [[ "$success" != "True" && "$success" != "true" ]]; then
        status_fail "IP 信息查询未成功"
        return
    fi
    country="$(json_field "$json" country)"
    region="$(json_field "$json" region)"
    city="$(json_field "$json" city)"
    isp="$(json_field "$json" connection.isp)"
    org="$(json_field "$json" connection.org)"
    asn="$(json_field "$json" connection.asn)"
    printf '国家/地区：%s\n' "${country:-未知}"
    printf '地区：%s\n' "${region:-未知}"
    printf '城市：%s\n' "${city:-未知}"
    printf '运营商：%s\n' "${isp:-未知}"
    printf '组织：%s\n' "${org:-未知}"
    printf 'ASN：%s\n' "${asn:-未知}"
}
# ---------- 本机网络配置 ----------
network_config() {
    section "本机网络配置"
    if has_cmd hostname; then
        printf '主机名：'
        if (( HIDE_IP == 1 )); then
            printf '[已隐藏]\n'
        else
            hostname 2>/dev/null || printf '未知\n'
        fi
    fi
    if has_cmd ip; then
        printf '\n网卡地址：\n'
        if (( HIDE_IP == 1 )); then
            ip -o addr show 2>/dev/null |
                while IFS= read -r row; do
                    printf '%s\n' "$(mask_text "$row")"
                done
        else
            ip -brief addr show 2>/dev/null || ip addr show 2>/dev/null
        fi
        printf '\n默认路由：\n'
        if (( HIDE_IP == 1 )); then
            ip route show default 2>/dev/null | while IFS= read -r row; do
                printf '%s\n' "$(mask_text "$row")"
            done
            ip -6 route show default 2>/dev/null | while IFS= read -r row; do
                printf '%s\n' "$(mask_text "$row")"
            done
        else
            ip route show default 2>/dev/null
            ip -6 route show default 2>/dev/null
        fi
    else
        status_unknown "系统中没有 ip 命令"
    fi
    printf '\nDNS 配置：\n'
    if [[ -r /etc/resolv.conf ]]; then
        if (( HIDE_IP == 1 )); then
            sed -n 's/^[[:space:]]*nameserver[[:space:]]*/DNS：/p' /etc/resolv.conf |
                while IFS= read -r row; do
                    printf '%s\n' "$(mask_text "$row")"
                done
        else
            grep -E '^[[:space:]]*nameserver' /etc/resolv.conf || true
        fi
    else
        status_unknown "无法读取 /etc/resolv.conf"
    fi
}
# ---------- DNS 检测 ----------
dns_check() {
    section "DNS 解析检测"
    local domain="${1:-example.com}"
    local server result
    printf '检测域名：%s\n' "$domain"
    if has_cmd getent; then
        result="$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u)"
        if [[ -n "$result" ]]; then
            status_ok "系统 DNS 解析成功"
            while IFS= read -r row; do
                [[ -n "$row" ]] && printf '  %s\n' "$(mask_one_ip "$row")"
            done <<< "$result"
        else
            status_fail "系统 DNS 解析失败"
        fi
    elif has_cmd nslookup; then
        result="$(nslookup "$domain" 2>&1)"
        printf '%s\n' "$(mask_text "$result")"
    else
        status_unknown "缺少 getent 和 nslookup"
    fi
    if has_cmd dig; then
        for server in 1.1.1.1 8.8.8.8 9.9.9.9; do
            result="$(dig +time=3 +tries=1 +short @"$server" "$domain" A 2>/dev/null)"
            if [[ -n "$result" ]]; then
                status_ok "公共 DNS $server 解析成功"
                while IFS= read -r row; do
                    [[ -n "$row" ]] && printf '  %s\n' "$(mask_one_ip "$row")"
                done <<< "$result"
            else
                status_warn "公共 DNS $server 无有效 A 记录"
            fi
        done
    else
        status_skip "缺少 dig，跳过公共 DNS 对比"
    fi
}
# ---------- 系统信息 ----------
system_info() {
    section "系统信息"
    printf '操作系统：'
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf '%s\n' "${PRETTY_NAME:-未知}"
    else
        uname -s
    fi
    printf '内核版本：'
    uname -r
    printf '系统架构：'
    uname -m
    printf '运行时间：'
    if has_cmd uptime; then
        uptime -p 2>/dev/null || uptime
    else
        status_unknown "缺少 uptime"
    fi
    printf 'Shell：%s\n' "${BASH_VERSION:-未知}"
    if has_cmd free; then
        printf '\n内存：\n'
        free -h
    fi
    if has_cmd df; then
        printf '\n磁盘：\n'
        df -h / 2>/dev/null
    fi
}
# ---------- 网站连通性 ----------
website_check() {
    section "网站连通性检测"
    local url code
    read -r -p "输入网址（默认 https://www.cloudflare.com）：" url
    url="${url:-https://www.cloudflare.com}"
    [[ "$url" =~ ^https?:// ]] || url="https://$url"
    if ! has_cmd curl; then
        status_fail "网站检测需要 curl"
        return
    fi
    code="$(http_code "$url")"
    if [[ "$code" =~ ^[0-9]{3}$ ]] && [[ "$code" != "000" ]]; then
        if (( 10#$code >= 200 && 10#$code < 400 )); then
            status_ok "HTTP 状态码：$code"
        else
            status_warn "HTTP 状态码：$code（服务器返回非成功状态）"
        fi
    else
        status_fail "请求失败或连接超时"
    fi
}
# ---------- 网络质量 ----------
network_quality() {
    section "网络质量检测"
    local target="${1:-1.1.1.1}"
    printf '测试目标：%s\n' "$(mask_one_ip "$target")"
    if has_cmd ping; then
        local output
        output="$(ping -c "$PING_COUNT" -W 2 "$target" 2>&1)"
        local rc=$?
        printf '%s\n' "$(mask_text "$output")"
        if (( rc == 0 )); then
            status_ok "Ping 测试完成"
        else
            status_warn "Ping 测试未完全成功，可能是 ICMP 被限制"
        fi
    else
        status_unknown "缺少 ping 命令"
    fi
    if has_cmd curl; then
        local timing
        timing="$(curl -sS -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            -w 'DNS=%{time_namelookup}s Connect=%{time_connect}s TLS=%{time_appconnect}s Total=%{time_total}s' \
            https://www.cloudflare.com 2>/dev/null)" || timing=""
        if [[ -n "$timing" ]]; then
            printf 'HTTPS 耗时：%s\n' "$timing"
        else
            status_warn "HTTPS 计时请求失败"
        fi
    fi
}
# ---------- TCP 端口检测 ----------
tcp_check() {
    section "TCP 端口连通性检测"
    local host port
    read -r -p "目标主机或 IP：" host
    [[ -n "$host" ]] || {
        status_warn "目标不能为空"
        return
    }
    read -r -p "目标端口：" port
    [[ "$port" =~ ^[0-9]+$ ]] || {
        status_fail "端口必须是数字"
        return
    }
    (( port >= 1 && port <= 65535 )) || {
        status_fail "端口范围必须是 1-65535"
        return
    }
    printf '目标：%s:%s\n' "$(mask_one_ip "$host")" "$port"
    if has_cmd python3; then
        if python3 - "$host" "$port" "$CONNECT_TIMEOUT" <<'PY'
import socket, sys
host, port, timeout = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
try:
    with socket.create_connection((host, port), timeout=timeout):
        print("TCP connection succeeded")
    sys.exit(0)
except Exception as e:
    print(type(e).__name__ + ": " + str(e))
    sys.exit(1)
PY
        then
            status_ok "TCP 端口可连接"
        else
            status_fail "TCP 连接失败；请检查目标服务、防火墙和路由"
        fi
    elif has_cmd nc; then
        if nc -z -w "$CONNECT_TIMEOUT" "$host" "$port" 2>/dev/null; then
            status_ok "TCP 端口可连接"
        else
            status_fail "TCP 连接失败"
        fi
    else
        status_unknown "需要 Python 3 或 nc 才能执行 TCP 检测"
    fi
}
# ---------- MTU 排查 ----------
mtu_check() {
    section "MTU 排查"
    if ! has_cmd ping; then
        status_unknown "缺少 ping 命令，无法执行 MTU 探测"
        return
    fi
    local target size payload success=0
    read -r -p "目标地址（默认 1.1.1.1）：" target
    target="${target:-1.1.1.1}"
    printf '将尝试使用 IPv4 DF 探测，不会修改网卡 MTU。\n'
    # 常见 IPv4 MTU 探测：IP 头 20 字节 + ICMP 头 8 字节。
    for size in 1472 1464 1452 1400 1300 1200; do
        payload=$size
        printf '尝试负载 %s 字节... ' "$payload"
        if ping -4 -c 1 -W 2 -M do -s "$payload" "$target" >/dev/null 2>&1; then
            printf '成功\n'
            success=$payload
            break
        else
            printf '失败或未响应\n'
        fi
    done
    if (( success > 0 )); then
        printf '\n'
        status_ok "已找到可响应的探测负载：$success 字节"
        printf '估算路径 MTU 至少约为：%s 字节\n' "$((success + 28))"
        status_warn "这是粗略估算；目标可能过滤 ICMP，需结合实际业务复核"
    else
        status_warn "没有收到有效探测响应，不能据此断定 MTU 存在问题"
    fi
}
# ---------- 路由追踪 ----------
route_trace() {
    section "网络诊断与路由追踪"
    local target
    read -r -p "目标地址（默认 1.1.1.1）：" target
    target="${target:-1.1.1.1}"
    printf '目标：%s\n' "$(mask_one_ip "$target")"
    if (( HIDE_IP == 1 )); then
        status_warn "隐藏 IP 模式已开启：路由输出将进行脱敏"
    fi
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
        status_unknown "缺少 traceroute 和 tracepath"
    fi
    printf '\n'
    status_warn "路由中某一跳不响应，不一定代表该节点存在故障"
}
# ---------- 流媒体检测 ----------
streaming_check() {
    section "流媒体检测"
    if ! has_cmd curl; then
        status_unknown "缺少 curl，无法进行流媒体可达性检测"
        return
    fi
    local url code
    for url in \
        "https://www.netflix.com" \
        "https://www.youtube.com" \
        "https://www.disneyplus.com" \
        "https://www.google.com"
    do
        code="$(http_code "$url")"
        if [[ "$code" =~ ^[0-9]{3}$ ]] && [[ "$code" != "000" ]]; then
            if (( 10#$code < 500 )); then
                status_ok "$url 可访问（HTTP $code）"
            else
                status_warn "$url 返回 HTTP $code"
            fi
        else
            status_fail "$url 请求失败或超时"
        fi
    done
    printf '\n'
    status_warn "本功能只检查网站可达性，不代表已验证账号、播放权限或区域解锁"
}
# ---------- 全面检测 ----------
full_check() {
    section "全面检测"
    printf '\n%s1/7 公网 IPv4%s\n' "$C_CYAN" "$C_RESET"
    local ipv4
    ipv4="$(get_public_ipv4)"
    if is_ipv4 "$ipv4"; then
        status_ok "IPv4：$(mask_one_ip "$ipv4")"
    else
        status_fail "IPv4 地址获取失败"
    fi
    printf '\n%s2/7 公网 IPv6%s\n' "$C_CYAN" "$C_RESET"
    local ipv6
    ipv6="$(get_public_ipv6)"
    if is_ipv6 "$ipv6"; then
        status_ok "IPv6：$(mask_one_ip "$ipv6")"
    else
        status_warn "未获取到公网 IPv6"
    fi
    printf '\n%s3/7 DNS%s\n' "$C_CYAN" "$C_RESET"
    if has_cmd getent; then
        if getent ahosts example.com >/dev/null 2>&1; then
            status_ok "系统 DNS 解析正常"
        else
            status_fail "系统 DNS 解析失败"
        fi
    else
        status_unknown "缺少 getent"
    fi
    printf '\n%s4/7 HTTPS 连通性%s\n' "$C_CYAN" "$C_RESET"
    if has_cmd curl; then
        if curl -fsSL -o /dev/null \
            --connect-timeout "$CONNECT_TIMEOUT" \
            --max-time "$MAX_TIME" \
            https://www.cloudflare.com 2>/dev/null; then
            status_ok "HTTPS 请求成功"
        else
            status_fail "HTTPS 请求失败"
        fi
    else
        status_unknown "缺少 curl"
    fi
    printf '\n%s5/7 网络质量%s\n' "$C_CYAN" "$C_RESET"
    if has_cmd ping; then
        local ping_output
        ping_output="$(ping -c 3 -W 2 1.1.1.1 2>&1)"
        if (( $? == 0 )); then
            status_ok "ICMP 探测有响应"
            printf '%s\n' "$(mask_text "$ping_output" | tail -n 3)"
        else
            status_warn "ICMP 探测失败，可能是目标过滤或网络异常"
        fi
    else
        status_unknown "缺少 ping"
    fi
    printf '\n%s6/7 TCP/HTTPS%s\n' "$C_CYAN" "$C_RESET"
    if has_cmd curl; then
        local code
        code="$(http_code 'https://www.google.com')"
        if [[ "$code" =~ ^[0-9]{3}$ ]] && [[ "$code" != "000" ]]; then
            status_ok "HTTPS 服务返回 HTTP $code"
        else
            status_fail "HTTPS 连接失败"
        fi
    else
        status_unknown "缺少 curl"
    fi
    printf '\n%s7/7 检测提示%s\n' "$C_CYAN" "$C_RESET"
    status_warn "全面检测仅提供基础诊断；流媒体和 MTU 需单独测试"
    printf '\n'
    line
    printf '全面检测完成。\n'
}
# ---------- 隐藏模式切换 ----------
toggle_privacy() {
    if (( HIDE_IP == 0 )); then
        HIDE_IP=1
        status_ok "隐藏 IP 模式已开启"
        status_warn "后续输出将尽可能脱敏；建议避免分享未脱敏的系统日志"
    else
        HIDE_IP=0
        status_warn "隐藏 IP 模式已关闭"
    fi
}
# ---------- 主循环 ----------
main() {
    while true; do
        show_menu
        read -r -p "NYKI > " choice
        case "$choice" in
            1|01)
                full_check
                pause_screen
                ;;
            2|02)
                check_ipv4
                pause_screen
                ;;
            3|03)
                check_ipv6
                pause_screen
                ;;
            4|04)
                ip_info
                pause_screen
                ;;
            5|05)
                network_config
                pause_screen
                ;;
            6|06)
                streaming_check
                pause_screen
                ;;
            7|07)
                route_trace
                pause_screen
                ;;
            8|08)
                dns_check
                pause_screen
                ;;
            9|09)
                system_info
                pause_screen
                ;;
            10)
                website_check
                pause_screen
                ;;
            11)
                network_quality
                pause_screen
                ;;
            12)
                tcp_check
                pause_screen
                ;;
            13)
                mtu_check
                pause_screen
                ;;
            14)
                toggle_privacy
                sleep 1
                ;;
            0|00|q|Q|exit)
                printf '\n感谢使用 %s。\n' "$APP_NAME"
                exit 0
                ;;
            *)
                status_warn "无效选项，请重新输入"
                sleep 1
                ;;
        esac
    done
}
# ---------- 环境检查 ----------
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '请使用 Bash 运行此脚本。\n' >&2
    exit 1
fi
main "$@"
