#!/usr/bin/env bash
# VPS 网络检测工具
# 作者：阿晚
# 作者主页：https://nyki.cc
# 项目地址：https://github.com/nyki4/vps-ip-check
# 版本：3.1.0

export LC_ALL=C
VERSION="3.1.0"
TIMEOUT=8
CONNECT_TIMEOUT=4

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    BLUE=''
    BOLD=''
    RESET=''
fi

ok()   { printf '%s[正常]%s %s\n' "$GREEN" "$RESET" "$*"; }
fail() { printf '%s[失败]%s %s\n' "$RED" "$RESET" "$*"; }
warn() { printf '%s[异常]%s %s\n' "$YELLOW" "$RESET" "$*"; }
info() { printf '%s[信息]%s %s\n' "$BLUE" "$RESET" "$*"; }
line() { printf '%s\n' '------------------------------------------------------------'; }
title() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; line; }
have() { command -v "$1" >/dev/null 2>&1; }

CURL_ARGS=(
    --silent
    --show-error
    --location
    --max-time "$TIMEOUT"
    --connect-timeout "$CONNECT_TIMEOUT"
    --user-agent "vps-ip-check/$VERSION"
)

ms() {
    awk -v n="${1:-}" '
    BEGIN {
        if (n == "" || n !~ /^[0-9.]+$/) {
            print "未知"
        } else {
            printf "%.0f ms", n * 1000
        }
    }'
}

need_curl() {
    if ! have curl; then
        fail "未安装 curl"
        return 1
    fi
}

banner() {
    printf '\n%s' "$BOLD"
    printf '%s\n' '============================================================'
    printf '%s\n' '                   VPS 网络检测工具'
    printf '                       版本 %s\n' "$VERSION"
    printf '%s\n' '============================================================'
    printf '%s' "$RESET"
    printf '作者：阿晚\n'
    printf '作者主页：https://nyki.cc\n'
    printf '项目地址：https://github.com/nyki4/vps-ip-check\n'
    line
}

# 1. 出口 IP 与归属信息
test_ip() {
    title "一、出口 IP 与归属信息"
    need_curl || return

    local ipv4 ipv6 ip json

    ipv4="$(curl -4 "${CURL_ARGS[@]}" \
        https://api.ipify.org 2>/dev/null || true)"

    ipv6="$(curl -6 "${CURL_ARGS[@]}" \
        https://api64.ipify.org 2>/dev/null || true)"

    if [[ "$ipv4" =~ ^[0-9.]+$ ]]; then
        ok "IPv4：$ipv4"
    else
        warn "IPv4：获取失败"
        ipv4=""
    fi

    if [[ "$ipv6" == *:* ]]; then
        ok "IPv6：$ipv6"
    else
        warn "IPv6：获取失败或未配置"
        ipv6=""
    fi

    ip="$ipv4"
    [[ -n "$ip" ]] || ip="$ipv6"

    [[ -n "$ip" ]] || {
        warn "无法获取出口 IP，跳过归属查询"
        return
    }

    json="$(curl "${CURL_ARGS[@]}" \
        "https://ipwho.is/$ip" 2>/dev/null || true)"

    if [[ "$json" == *'"success":true'* ||
          "$json" == *'"success": true'* ]]; then

        local field value
        for field in country region city isp org asn; do
            value="$(printf '%s' "$json" |
                sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" |
                head -n1)"
            if [[ -n "$value" ]]; then
                case "$field" in
                    country) info "国家/地区：$value" ;;
                    region)  info "州/省：$value" ;;
                    city)    info "城市：$value" ;;
                    isp)     info "运营商：$value" ;;
                    org)     info "网络组织：$value" ;;
                    asn)     info "ASN：$value" ;;
                esac
            fi
        done
    else
        warn "IP 归属信息查询失败"
    fi
}

# 2. IPv4 / IPv6
test_ip_stack() {
    title "二、IPv4 / IPv6 连通性"
    need_curl || return

    local family result code timing

    for family in 4 6; do
        result="$(curl "-$family" "${CURL_ARGS[@]}" \
            -o /dev/null \
            -w '%{http_code}|%{time_total}' \
            https://www.cloudflare.com 2>/dev/null || true)"

        if [[ "$result" == *"|"* ]]; then
            code="${result%%|*}"
            timing="${result#*|}"

            if [[ "$code" =~ ^[0-9]{3}$ ]]; then
                ok "IPv$family HTTPS：HTTP $code"
                info "总耗时：$(ms "$timing")"
                continue
            fi
        fi

        warn "IPv$family HTTPS 连接失败"
    done

    if have ip; then
        local route
        route="$(ip -4 route show default 2>/dev/null | head -n1)"
        [[ -n "$route" ]] && info "IPv4 默认路由：$route" ||
            warn "未发现 IPv4 默认路由"

        route="$(ip -6 route show default 2>/dev/null | head -n1)"
        [[ -n "$route" ]] && info "IPv6 默认路由：$route" ||
            warn "未发现 IPv6 默认路由"
    fi
}

# 3. DNS
test_dns() {
    title "三、DNS 解析"

    local domain result start end elapsed
    local domains=(
        github.com
        google.com
        cloudflare.com
        www.microsoft.com
    )

    for domain in "${domains[@]}"; do
        start="$(date +%s)"

        if have getent; then
            result="$(getent ahosts "$domain" 2>/dev/null |
                awk '!seen[$1]++ {print $1}' | head -n3)"
        elif have python3; then
            result="$(python3 -c \
                'import socket,sys; print("\n".join(sorted(set(x[4][0] for x in socket.getaddrinfo(sys.argv[1],None)))))' \
                "$domain" 2>/dev/null || true)"
        else
            result=""
        fi

        end="$(date +%s)"
        elapsed=$(( (end - start) * 1000 ))

        if [[ -n "$result" ]]; then
            ok "$domain"
            printf '    地址：%s\n' "$(printf '%s' "$result" | tr '\n' ' ')"
            printf '    查询耗时：约 %s ms\n' "$elapsed"
        else
            warn "$domain 解析失败"
        fi
    done

    if [[ -r /etc/resolv.conf ]]; then
        printf '\n当前 DNS 服务器：\n'
        grep -E '^[[:space:]]*nameserver[[:space:]]+' \
            /etc/resolv.conf 2>/dev/null | head -n5
    fi
}

# 4. 网站延迟
test_latency() {
    title "四、网站连接延迟"
    need_curl || return

    local urls=(
        https://www.cloudflare.com
        https://www.google.com
        https://github.com
        https://www.microsoft.com
    )

    local url result code dns conn tls first total remote
    local tcp_ms tls_ms

    for url in "${urls[@]}"; do
        result="$(curl "${CURL_ARGS[@]}" \
            -o /dev/null \
            -w '%{http_code}|%{time_namelookup}|%{time_connect}|%{time_appconnect}|%{time_starttransfer}|%{time_total}|%{remote_ip}' \
            "$url" 2>/dev/null || true)"

        if [[ "$result" != *"|"* ]]; then
            warn "$url 连接失败"
            continue
        fi

        IFS='|' read -r code dns conn tls first total remote <<< "$result"

        if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
            warn "$url 请求失败"
            continue
        fi

        tcp_ms="$(awk -v a="$conn" -v b="$dns" \
            'BEGIN {printf "%.6f", (a>b ? a-b : 0)}')"

        tls_ms="$(awk -v a="$tls" -v b="$conn" \
            'BEGIN {printf "%.6f", (a>b ? a-b : 0)}')"

        ok "$url"
        printf '    HTTP 状态：%s\n' "$code"
        printf '    远端 IP：%s\n' "${remote:-未知}"
        printf '    DNS 解析：%s\n' "$(ms "$dns")"
        printf '    TCP 建连：%s\n' "$(ms "$tcp_ms")"
        printf '    TLS 握手：%s\n' "$(ms "$tls_ms")"
        printf '    首字节：%s\n' "$(ms "$first")"
        printf '    总耗时：%s\n' "$(ms "$total")"
    done
}

# 5. TCP 端口
test_tcp() {
    title "五、TCP 端口连通性"

    if ! have timeout; then
        warn "系统缺少 timeout，跳过端口检测"
        return
    fi

    local host port
    local targets=(
        "1.1.1.1 443"
        "8.8.8.8 443"
        "github.com 443"
        "github.com 22"
    )

    for target in "${targets[@]}"; do
        read -r host port <<< "$target"

        if timeout "$CONNECT_TIMEOUT" \
            bash -c ":</dev/tcp/$host/$port" 2>/dev/null; then
            ok "$host:$port TCP 连接成功"
        else
            warn "$host:$port TCP 连接失败或超时"
        fi
    done
}

# 6. 路由追踪
test_route() {
    title "六、路由追踪"

    if have traceroute; then
        info "目标：1.1.1.1"
        traceroute -m 8 -w 1 1.1.1.1 2>&1 | head -n12
    elif have tracepath; then
        tracepath 1.1.1.1 2>&1 | head -n12
    elif have ping; then
        info "未找到路由追踪工具，改用 ICMP 探测"
        ping -c 3 -W 2 1.1.1.1 2>&1 | tail -n5
    else
        warn "系统没有可用的路由检测工具"
    fi
}

# 7. 服务网站连通性
test_services() {
    title "七、流媒体与 AI 网站连通性"
    need_curl || return

    local urls=(
        https://www.netflix.com
        https://www.disneyplus.com
        https://www.youtube.com
        https://chatgpt.com
        https://claude.ai
        https://gemini.google.com
    )

    local url result code remote

    for url in "${urls[@]}"; do
        result="$(curl "${CURL_ARGS[@]}" \
            -o /dev/null \
            -w '%{http_code}|%{remote_ip}' \
            "$url" 2>/dev/null || true)"

        if [[ "$result" != *"|"* ]]; then
            warn "$url 连接失败"
            continue
        fi

        code="${result%%|*}"
        remote="${result#*|}"

        if [[ "$code" =~ ^[0-9]{3}$ ]]; then
            ok "$url：HTTP $code"
            printf '    远端 IP：%s\n' "${remote:-未知}"
        else
            warn "$url 请求失败"
        fi
    done

    info "此项只检测网站连通性，不代表账号可用或服务已解锁。"
}

# 8. 系统网络信息
test_system() {
    title "八、系统网络信息"

    info "检测时间：$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
    info "系统版本：$(uname -srm 2>/dev/null || echo 未知)"

    if have ip; then
        printf '\n网卡地址：\n'
        ip -brief address 2>/dev/null | head -n10

        printf '\n默认路由：\n'
        ip route show default 2>/dev/null
    else
        warn "系统缺少 ip 命令"
    fi

    printf '\nDNS 配置：\n'
    if [[ -r /etc/resolv.conf ]]; then
        grep -E '^[[:space:]]*nameserver[[:space:]]+' \
            /etc/resolv.conf 2>/dev/null || true
    else
        warn "无法读取 DNS 配置"
    fi
}

# 完整检测
test_all() {
    test_ip
    test_ip_stack
    test_dns
    test_latency
    test_tcp
    test_route
    test_services
    test_system

    line
    printf '检测结束\n'
    printf '作者：阿晚\n'
    printf '作者主页：https://nyki.cc\n'
    printf '项目地址：https://github.com/nyki4/vps-ip-check\n'
}

pause() {
    printf '\n按回车键返回菜单……'
    read -r _ || true
}

while true; do
    banner

    printf '  1. 完整检测\n'
    printf '  2. 出口 IP 与归属信息\n'
    printf '  3. IPv4 / IPv6 连通性\n'
    printf '  4. DNS 解析\n'
    printf '  5. 网站连接延迟\n'
    printf '  6. TCP 端口检测\n'
    printf '  7. 路由追踪\n'
    printf '  8. 流媒体与 AI 网站连通性\n'
    printf '  9. 系统网络信息\n'
    printf '  0. 退出\n'

    line
    printf '请输入选项 [0-9]：'

    read -r choice || exit 0

    case "$choice" in
        1) test_all; pause ;;
        2) test_ip; pause ;;
        3) test_ip_stack; pause ;;
        4) test_dns; pause ;;
        5) test_latency; pause ;;
        6) test_tcp; pause ;;
        7) test_route; pause ;;
        8) test_services; pause ;;
        9) test_system; pause ;;
        0)
            printf '项目地址：https://github.com/nyki4/vps-ip-check\n'
            exit 0
            ;;
        *)
            warn "无效选项，请输入 0-9"
            sleep 1
            ;;
    esac
done
