#!/usr/bin/env bash

# ==========================================
# AWan VPS Toolbox
# 作者：阿晚
# 版本：2.0
# 轻量级 VPS 网络检测工具
# 不自动安装软件，不生成报告文件
# ==========================================

export LC_ALL=C
set +e

VERSION="2.0"

# ---------- 基础工具 ----------

has() {
    command -v "$1" >/dev/null 2>&1
}

line() {
    printf '%s\n' '------------------------------------------'
}

pause() {
    echo
    read -r -p "按回车键返回菜单..." _
}

title() {
    clear 2>/dev/null
    line
    printf '  AWan VPS Toolbox %s\n' "$VERSION"
    printf '  作者：阿晚\n'
    line
    printf '  %s\n' "$1"
    line
}

# 使用 curl 请求 URL；不安装任何软件
http_code() {
    curl -L -sS -o /dev/null \
        --connect-timeout 4 \
        --max-time 10 \
        -w '%{http_code}' "$1" 2>/dev/null
}

# ---------- 1. IP 基础信息 ----------

test_ip_info() {
    title "IP 基础信息"

    if ! has curl; then
        echo "[异常] 系统没有 curl，无法检测。"
        pause
        return
    fi

    echo "正在检测公网 IPv4..."
    IP4="$(curl -4 -fsSL --connect-timeout 4 --max-time 8 \
        https://api.ipify.org 2>/dev/null)"

    echo "正在检测公网 IPv6..."
    IP6="$(curl -6 -fsSL --connect-timeout 4 --max-time 8 \
        https://api64.ipify.org 2>/dev/null)"

    if [ -n "$IP4" ]; then
        echo "[正常] IPv4：$IP4"
    else
        echo "[异常] IPv4：未获取到"
    fi

    if [ -n "$IP6" ]; then
        echo "[正常] IPv6：$IP6"
    else
        echo "[异常] IPv6：未获取到或不支持"
    fi

    IP="$IP4"
    [ -n "$IP" ] || IP="$IP6"

    if [ -n "$IP" ]; then
        echo
        echo "正在查询 IP 地理信息..."
        curl -fsSL --connect-timeout 4 --max-time 10 \
            "https://ipwho.is/$IP" 2>/dev/null |
            grep -E '"(success|country|region|city|isp|org|asn)"[[:space:]]*:' |
            sed 's/^[[:space:]]*/  /'

        if [ "${PIPESTATUS[0]}" -ne 0 ]; then
            echo "地理信息查询失败。"
        fi
    fi

    pause
}

# ---------- 2. IP 风险信息 ----------

test_ip_risk() {
    title "IP 风险信息"

    if ! has curl; then
        echo "[异常] 系统没有 curl。"
        pause
        return
    fi

    IP="$(curl -fsSL --connect-timeout 4 --max-time 8 \
        https://api.ipify.org 2>/dev/null)"

    if [ -z "$IP" ]; then
        echo "[异常] 无法获取公网 IPv4。"
        pause
        return
    fi

    echo "公网 IPv4：$IP"
    echo
    echo "查询公开 IP 情报信息..."

    INFO="$(curl -fsSL --connect-timeout 4 --max-time 10 \
        "https://ipwho.is/$IP" 2>/dev/null)"

    if [ -n "$INFO" ]; then
        printf '%s\n' "$INFO" |
            grep -E '"(country|region|city|isp|org|asn|connection|proxy|hosting)"[[:space:]]*:'
    else
        echo "查询失败。"
    fi

    echo
    echo "说明：以上信息不等于完整的 IP 信誉评分。"
    echo "本模块不宣称 IP 一定纯净，也不保证所有平台都能使用。"

    pause
}

# ---------- 3. IPv4 / IPv6 ----------

test_ip_versions() {
    title "IPv4 / IPv6 连通性"

    if ! has curl; then
        echo "[异常] 系统没有 curl。"
        pause
        return
    fi

    for FAMILY in 4 6; do
        if [ "$FAMILY" = 4 ]; then
            LABEL="IPv4"
        else
            LABEL="IPv6"
        fi

        printf '%s：' "$LABEL"

        CODE="$(curl "-$FAMILY" -L -sS -o /dev/null \
            --connect-timeout 4 --max-time 8 \
            -w '%{http_code}' https://www.cloudflare.com 2>/dev/null)"
        RC=$?

        if [ "$RC" -eq 0 ] && [ -n "$CODE" ] && [ "$CODE" != "000" ]; then
            echo "[正常] HTTPS 可连接，状态码 $CODE"
        else
            echo "[异常] HTTPS 连接失败或不支持"
        fi
    done

    pause
}

# ---------- 4. DNS 测试 ----------

test_dns() {
    title "DNS 解析测试"

    DOMAINS="github.com cloudflare.com google.com youtube.com netflix.com openai.com"

    for DOMAIN in $DOMAINS; do
        printf '%-20s ' "$DOMAIN"

        if has getent; then
            RESULT="$(getent ahosts "$DOMAIN" 2>/dev/null | head -n 1)"
            if [ -n "$RESULT" ]; then
                echo "[正常] 解析成功"
            else
                echo "[异常] 解析失败"
            fi
        elif has nslookup; then
            if nslookup "$DOMAIN" >/dev/null 2>&1; then
                echo "[正常] 解析成功"
            else
                echo "[异常] 解析失败"
            fi
        else
            echo "[跳过] 缺少 getent/nslookup"
        fi
    done

    pause
}

# ---------- 5. HTTPS 网络测试 ----------

test_https() {
    title "HTTPS 网络测试"

    if ! has curl; then
        echo "[异常] 系统没有 curl。"
        pause
        return
    fi

    for URL in \
        https://github.com \
        https://www.cloudflare.com \
        https://www.google.com \
        https://www.youtube.com \
        https://www.netflix.com \
        https://chatgpt.com
    do
        printf '%-32s ' "$URL"

        RESULT="$(curl -L -sS -o /dev/null \
            --connect-timeout 5 --max-time 12 \
            -w 'HTTP %{http_code} | 总耗时 %{time_total}s' \
            "$URL" 2>/dev/null)"
        RC=$?

        if [ "$RC" -eq 0 ]; then
            echo "[正常] $RESULT"
        else
            echo "[异常] 连接失败或超时"
        fi
    done

    pause
}

# ---------- 6. 流媒体基础连通性 ----------

test_streaming() {
    title "流媒体网站检测"

    if ! has curl; then
        echo "[异常] 系统没有 curl。"
        pause
        return
    fi

    echo "本测试只检测网站的 HTTPS 响应。"
    echo "网站可访问不代表账号可用或地区内容已解锁。"
    echo

    for URL in \
        https://www.netflix.com \
        https://www.youtube.com \
        https://www.disneyplus.com \
        https://www.tiktok.com
    do
        printf '%-34s ' "$URL"

        CODE="$(http_code "$URL")"

        if [ -n "$CODE" ] && [ "$CODE" != "000" ]; then
            echo "[可连接] HTTP $CODE"
        else
            echo "[不可连接] 请求失败或超时"
        fi
    done

    pause
}

# ---------- 7. AI 网站连通性 ----------

test_ai() {
    title "AI 服务连通性"

    if ! has curl; then
        echo "[异常] 系统没有 curl。"
        pause
        return
    fi

    echo "仅检测网站是否响应，不检测账号、API 权限或服务资格。"
    echo

    for URL in \
        https://chatgpt.com \
        https://claude.ai \
        https://gemini.google.com \
        https://api.openai.com \
        https://www.perplexity.ai
    do
        printf '%-34s ' "$URL"

        CODE="$(http_code "$URL")"

        if [ -n "$CODE" ] && [ "$CODE" != "000" ]; then
            echo "[可连接] HTTP $CODE"
        else
            echo "[不可连接] 请求失败或超时"
        fi
    done

    pause
}

# ---------- 8. 中国三网线路 ----------

test_cn_network() {
    title "中国三网线路检测"

    echo "电信、联通、移动的真实线路质量"
    echo "需要国内测试节点或专门的测速服务。"
    echo
    echo "当前脚本不会把普通海外网站延迟冒充为三网延迟。"
    echo
    echo "[提示] 本模块暂不提供虚构的三网测速结果。"
    echo "后续可接入可靠的国内测试节点后再实现。"

    pause
}

# ---------- 9. TCP 端口 ----------

test_tcp() {
    title "TCP 端口连通性"

    if ! has timeout || ! has bash; then
        echo "[跳过] 系统缺少 timeout 或 bash。"
        pause
        return
    fi

    for TARGET in \
        github.com:443 \
        cloudflare.com:443 \
        google.com:443
    do
        HOST="${TARGET%:*}"
        PORT="${TARGET##*:}"

        printf '%-28s ' "$TARGET"

        if timeout 5 bash -c "exec 3<>/dev/tcp/$HOST/$PORT" 2>/dev/null; then
            echo "[正常] TCP 可连接"
        else
            echo "[异常] TCP 连接失败"
        fi
    done

    pause
}

# ---------- 10. 全部测试 ----------

test_all() {
    test_ip_info
    test_ip_risk
    test_ip_versions
    test_dns
    test_https
    test_streaming
    test_ai
    test_cn_network
    test_tcp
}

# ---------- 主菜单 ----------

while true; do
    title "VPS 网络诊断工具"

    cat <<'MENU'
  1. IP 基础信息
  2. IP 风险信息
  3. IPv4 / IPv6 测试
  4. DNS 解析测试
  5. 网络延迟与 HTTPS
  6. 流媒体网站检测
  7. AI 服务连通性
  8. 中国三网线路说明
  9. TCP 端口测试

  10. 全部测试
  0. 退出
MENU

    line
    read -r -p "请输入选项并按回车：" CHOICE

    case "$CHOICE" in
        1) test_ip_info ;;
        2) test_ip_risk ;;
        3) test_ip_versions ;;
        4) test_dns ;;
        5) test_https ;;
        6) test_streaming ;;
        7) test_ai ;;
        8) test_cn_network ;;
        9) test_tcp ;;
        10) test_all ;;
        0)
            echo "感谢使用 AWan VPS Toolbox。"
            echo "作者：阿晚"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            sleep 1
            ;;
    esac
done
