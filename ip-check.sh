#!/usr/bin/env bash

# VPS IP Check - lightweight diagnostic script
# No installation, no report files.

set +e
export LC_ALL=C

if ! command -v curl >/dev/null 2>&1; then
    echo "错误：当前系统没有 curl，脚本无法运行。"
    echo "本脚本不会自动安装任何软件。"
    exit 1
fi

line() {
    printf '%s\n' "--------------------------------------------------"
}

section() {
    echo
    line
    printf '  %s\n' "$1"
    line
}

fetch() {
    curl -4 -fsSL --connect-timeout 4 --max-time 8 "$1" 2>/dev/null
}

fetch6() {
    curl -6 -fsSL --connect-timeout 4 --max-time 8 "$1" 2>/dev/null
}

section "VPS IP CHECK"
printf '检测时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
printf '主机名称：%s\n' "$(hostname 2>/dev/null)"
printf '系统内核：%s\n' "$(uname -sr 2>/dev/null)"

section "1. 公网 IP 检测"

IP4="$(fetch https://api.ipify.org)"
IP6="$(fetch6 https://api64.ipify.org)"

if [ -n "$IP4" ]; then
    printf '公网 IPv4：%s\n' "$IP4"
else
    echo "公网 IPv4：未检测到或连接失败"
fi

if [ -n "$IP6" ]; then
    printf '公网 IPv6：%s\n' "$IP6"
else
    echo "公网 IPv6：未检测到或连接失败"
fi

section "2. IP 地理位置与运营商"

if [ -n "$IP4" ]; then
    INFO="$(fetch "https://ipwho.is/$IP4")"
    if [ -n "$INFO" ]; then
        printf '%s\n' "$INFO" |
            grep -E '"(success|country|region|city|isp|org|asn|connection)"' |
            sed 's/^[[:space:]]*//'
    else
        echo "IPv4 地理信息查询失败"
    fi
elif [ -n "$IP6" ]; then
    INFO="$(fetch "https://ipwho.is/$IP6")"
    if [ -n "$INFO" ]; then
        printf '%s\n' "$INFO" |
            grep -E '"(success|country|region|city|isp|org|asn|connection)"' |
            sed 's/^[[:space:]]*//'
    else
        echo "IP 地理信息查询失败"
    fi
else
    echo "没有可查询的公网 IP"
fi

section "3. DNS 解析检测"

for domain in github.com cloudflare.com google.com youtube.com; do
    printf '%-20s ' "$domain"
    if command -v getent >/dev/null 2>&1; then
        RESULT="$(getent ahosts "$domain" 2>/dev/null | head -n 1)"
        if [ -n "$RESULT" ]; then
            echo "解析正常"
        else
            echo "解析失败"
        fi
    else
        RESULT="$(fetch "https://$domain")"
        if [ -n "$RESULT" ]; then
            echo "HTTPS 可访问"
        else
            echo "解析或连接失败"
        fi
    fi
done

section "4. HTTPS 连通性与耗时"

for url in \
    https://github.com \
    https://www.cloudflare.com \
    https://www.google.com \
    https://www.youtube.com
do
    curl -L -o /dev/null -sS \
        --connect-timeout 5 --max-time 12 \
        -w '%{url_effective} | HTTP %{http_code} | DNS %{time_namelookup}s | 连接 %{time_connect}s | 总计 %{time_total}s\n' \
        "$url" 2>/dev/null

    if [ "$?" -ne 0 ]; then
        echo "$url | 连接失败或超时"
    fi
done

section "5. IPv4 / IPv6 HTTPS 测试"

for family in 4 6; do
    if [ "$family" = 4 ]; then
        LABEL="IPv4"
    else
        LABEL="IPv6"
    fi

    printf '%s：' "$LABEL"

    CODE="$(curl "-$family" -L -o /dev/null -sS \
        --connect-timeout 4 --max-time 8 \
        -w '%{http_code}' https://www.cloudflare.com 2>/dev/null)"
    RC="$?"

    if [ "$RC" -eq 0 ] && [ -n "$CODE" ] && [ "$CODE" != "000" ]; then
        printf 'HTTPS 正常，HTTP 状态码 %s\n' "$CODE"
    else
        echo "连接失败或不可用"
    fi
done

section "6. 常见 TCP 端口连通性"

if command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    for target in \
        github.com:443 \
        cloudflare.com:443 \
        google.com:443
    do
        HOST="${target%:*}"
        PORT="${target##*:}"
        printf '%-25s ' "$target"

        if timeout 5 bash -c \
            "exec 3<>/dev/tcp/$HOST/$PORT" 2>/dev/null; then
            echo "TCP 可连接"
        else
            echo "TCP 连接失败"
        fi
    done
else
    echo "系统缺少 timeout，跳过 TCP 端口测试"
fi

section "检测完成"
echo "提示：连接结果受 VPS 网络、目标网站策略及防火墙影响。"
echo "本脚本不会安装软件，也不会生成报告文件。"
line
