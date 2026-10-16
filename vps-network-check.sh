#!/usr/bin/env bash
# ============================================================
# NYKI / VPS NETWORK CHECK
# 作者：阿晚 · nyki.cc
# 项目：github.com/nyki4/vps-network-check
# 版本：v5.1.0
# ============================================================
VERSION="5.1.0"
AUTHOR="阿晚"
HOMEPAGE="https://nyki.cc"
PROJECT="https://github.com/nyki4/vps-network-check"
RAW_URL="https://raw.githubusercontent.com/nyki4/vps-network-check/main/vps-network-check.sh"

HIDE_IP=1
PING_COUNT=3
PING_TIMEOUT=2
TRACE_MAX_HOPS=12
TRACE_TIMEOUT=1
CURL_CONNECT_TIMEOUT=3
CURL_MAX_TIME=6
NYC_NOTIFY_URL="${NYC_NOTIFY_URL:-}"
NYC_NOTIFY_TELEGRAM="${NYC_NOTIFY_TELEGRAM:-}"

TRI_NET_NODES=(
    "电信|北京|219.141.136.10"
    "电信|上海|202.96.209.133"
    "电信|广州|58.60.188.222"
    "联通|北京|123.125.99.1"
    "联通|上海|210.22.70.3"
    "联通|广州|210.21.196.6"
    "移动|北京|211.136.25.153"
    "移动|上海|211.136.112.50"
    "移动|广州|120.196.165.24"
)

IPV6_ROUTE_TARGETS=(
    "Cloudflare|2606:4700:4700::1111"
    "Google|2001:4860:4860::8888"
    "OpenDNS|2620:0:ccc::2"
)

AI_SERVICES=(
    "ChatGPT|ai_chatgpt"
    "Claude|ai_claude"
    "Gemini|ai_gemini"
    "Grok|ai_grok"
    "Copilot|ai_copilot"
    "Perplexity|ai_perplexity"
    "Sora|ai_sora"
    "Midjourney|ai_midjourney"
)

STREAMING_SERVICES=(
    "Netflix|streaming_netflix"
    "Disney+|streaming_disney"
    "HBO Max|streaming_hbomax"
    "Prime Video|streaming_prime"
    "Spotify|streaming_spotify"
    "TikTok|streaming_tiktok"
    "YouTube|streaming_youtube"
)

IPV4_SOURCES=(
    "https://api.ipify.org"
    "https://ipv4.icanhazip.com"
    "https://ip1.icanhazip.com"
    "https://ifconfig.me/ip"
    "https://ipinfo.io/ip"
)
IPV6_SOURCES=(
    "https://api6.ipify.org"
    "https://ipv6.icanhazip.com"
    "https://ifconfig.co/ip"
)

CACHED_IPV4=""
CACHED_IPV6=""
CACHE_IPV4_TRYED=0
CACHE_IPV6_TRYED=0

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
else
    C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_DIM=""
fi

TMP_DIRS=()
SPINNER_PID=""
cleanup_all() {
    spinner_stop 2>/dev/null || true
    local d
    for d in "${TMP_DIRS[@]}"; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done
    printf '\n  已退出\n'
    exit 0
}
trap cleanup_all INT TERM

new_tmp_dir() {
    local d; d=$(mktemp -d)
    TMP_DIRS+=("$d")
    printf '%s' "$d"
}

# ------------------------------------------------------------
# 基础工具
# ------------------------------------------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

spinner_start() {
    [[ ! -t 1 ]] && return
    local msg="${1:-处理中}"
    (
        while true; do
            for c in '|' '/' '-' '\'; do
                printf '\r  %s%s%s %s' "$C_CYAN" "$c" "$C_RESET" "$msg" >&2
                sleep 0.15
            done
        done
    ) &
    SPINNER_PID=$!
}

spinner_stop() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
        [[ -t 1 ]] && printf '\r%*s\r' 72 '' >&2
    fi
}

# 并行任务进度显示
# 用法：run_parallel_with_progress <进度文件> <总数>
# 子进程完成后追加 "<显示名>" 到进度文件
run_parallel_with_progress() {
    local progress_file="$1"
    local total="$2"
    local shown=0
    local start_ts; start_ts=$(date +%s)

    while (( shown < total )); do
        local current=0
        [[ -f "$progress_file" ]] && current=$(wc -l < "$progress_file" 2>/dev/null | tr -d ' ')
        [[ -z "$current" ]] && current=0

        while (( shown < current )); do
            local line
            line=$(sed -n "$((shown+1))p" "$progress_file" 2>/dev/null)
            printf '  %s[%2d/%d]%s %s\n' \
                "$C_DIM" "$((shown+1))" "$total" "$C_RESET" "$line"
            shown=$((shown+1))
        done
        (( shown < total )) && sleep 0.08
    done
    printf '  %s用时 %ds%s\n' "$C_DIM" "$(( $(date +%s) - start_ts ))" "$C_RESET"
}

pause() {
    local key=""
    printf '\n'
    printf '  %s[R]%s 重新检测    %s[T]%s 换目标    %s[Enter]%s 返回菜单\n' \
        "$C_CYAN" "$C_RESET" "$C_YELLOW" "$C_RESET" "$C_DIM" "$C_RESET"
    if ! IFS= read -r -n 1 -s key; then
        printf '\n'; return 0
    fi
    printf '\n'
    while IFS= read -r -t 0.05 -n 1 _drain; do :; done
    [[ "$key" == "r" || "$key" == "R" ]] && return 1
    [[ "$key" == "t" || "$key" == "T" ]] && return 2
    return 0
}

retry_loop() {
    local fn="$1"
    while true; do
        "$fn"; local rc=$?
        (( rc == 0 )) && break
    done
}

get_width() {
    local width
    width=$(tput cols 2>/dev/null || printf '72')
    [[ "$width" =~ ^[0-9]+$ ]] || width=72
    (( width < 48 )) && width=48
    (( width > 100 )) && width=100
    printf '%s' "$width"
}

repeat_char() {
    local char="$1" count="$2" result=""
    (( count < 0 )) && count=0
    printf -v result '%*s' "$count" ''
    result=${result// /"$char"}
    printf '%s' "$result"
}

BOX_WIDTH=60
init_layout() {
    local width; width=$(get_width)
    (( width < 60 )) && BOX_WIDTH=$((width - 2))
    (( width >= 60 )) && BOX_WIDTH=60
    (( BOX_WIDTH < 40 )) && BOX_WIDTH=40
}

line() { printf '%s\n' "${C_DIM}$(repeat_char '─' "$BOX_WIDTH")${C_RESET}"; }
top_border()    { printf '┌%s┐\n' "$(repeat_char '─' "$BOX_WIDTH")"; }
mid_border()    { printf '├%s┤\n' "$(repeat_char '─' "$BOX_WIDTH")"; }
bottom_border() { printf '└%s┘\n' "$(repeat_char '─' "$BOX_WIDTH")"; }
box_text()      { printf '│  %s\n' "$1"; }

result_header() {
    clear 2>/dev/null || true
    top_border
    box_text "${C_CYAN}${C_BOLD}${1}${C_RESET}"
    mid_border
}

result_footer() {
    mid_border
    box_text "${C_DIM}检测完成${C_RESET}"
    bottom_border
}

item() { printf '  %-16s %s\n' "$1" "$2"; }

status_text() {
    case "$1" in
        正常|成功|开启|可用|已连接|可访问|优秀|良好|极快|低风险|可能为原生|可达|入口可达)
            printf '%s%s%s' "$C_GREEN" "$1" "$C_RESET" ;;
        异常|失败|关闭|不可用|超时|丢包|极差|高风险|不可达|受限)
            printf '%s%s%s' "$C_RED" "$1" "$C_RESET" ;;
        警告|未知|未配置|未检测|一般|较差|缓慢|中等风险|无法判断|部分受限)
            printf '%s%s%s' "$C_YELLOW" "$1" "$C_RESET" ;;
        *) printf '%s' "$1" ;;
    esac
}

json_field() {
    local json="$1" key="$2" out=""
    if out=$(printf '%s' "$json" | grep -oP "\"${key}\"\s*:\s*\"?\K[^\",}]+" 2>/dev/null | head -n1) && [[ -n "$out" ]]; then
        printf '%s' "$out"; return
    fi
    printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\?\([^\",}]*\)\"\?.*/\1/p" | head -n1
}

# ------------------------------------------------------------
# IP 获取与脱敏
# ------------------------------------------------------------
get_ipv4() {
    if (( CACHE_IPV4_TRYED )); then
        [[ -n "$CACHED_IPV4" ]] && { printf '%s' "$CACHED_IPV4"; return 0; }
        return 1
    fi
    CACHE_IPV4_TRYED=1
    local url ip
    for url in "${IPV4_SOURCES[@]}"; do
        ip=$(curl -4 -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            CACHED_IPV4="$ip"; printf '%s' "$ip"; return 0
        fi
    done
    return 1
}

get_ipv6() {
    if (( CACHE_IPV6_TRYED )); then
        [[ -n "$CACHED_IPV6" ]] && { printf '%s' "$CACHED_IPV6"; return 0; }
        return 1
    fi
    CACHE_IPV6_TRYED=1
    local url ip
    for url in "${IPV6_SOURCES[@]}"; do
        ip=$(curl -6 -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" == *:* && "$ip" != *" "* ]]; then
            CACHED_IPV6="$ip"; printf '%s' "$ip"; return 0
        fi
    done
    return 1
}

mask_ip() {
    local ip="$1"
    [[ "$HIDE_IP" != 1 ]] && { printf '%s' "$ip"; return; }
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local a b c d; IFS='.' read -r a b c d <<< "$ip"
        printf '%s.%s.*.*' "$a" "$b"; return
    fi
    if [[ "$ip" == *:* ]]; then
        local p1 p2; IFS=':' read -r p1 p2 _ <<< "$ip"
        printf '%s:%s:****:****' "${p1:-?}" "${p2:-?}"; return
    fi
    printf '%s' "$ip"
}

mask_text() {
    local text="$1"
    [[ "$HIDE_IP" != 1 ]] && { printf '%s' "$text"; return; }
    if has_cmd python3; then
        printf '%s' "$text" | python3 -c '
import re, sys
s = sys.stdin.read()
def ipv4(m):
    p = m.group(0).split(".")
    if len(p) == 4 and all(x.isdigit() and int(x) <= 255 for x in p):
        return ".".join(p[:2]) + ".*.*"
    return m.group(0)
s = re.sub(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])", ipv4, s)
s = re.sub(
    r"(?i)(?<![0-9a-f:])(?:[0-9a-f]{1,4}:){2,7}(?:[0-9a-f]{1,4}|:)(?![0-9a-f:])",
    lambda m: m.group(0).split(":")[0] + ":****:****:****", s)
sys.stdout.write(s)
'
    else
        printf '%s' "$text" | sed -E \
            -e 's/([0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}/\1.*.*/g' \
            -e 's/([0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}):[0-9a-fA-F:]{4,}/\1:****:****/g'
    fi
}

# ------------------------------------------------------------
# 通知
# ------------------------------------------------------------
json_escape() {
    awk 'BEGIN{ORS=""} {
        gsub(/\\/,"\\\\"); gsub(/"/,"\\\"")
        if (NR>1) print "\\n"
        print
    }'
}

notify_result() {
    local title="$1" body="$2"
    [[ -z "$NYC_NOTIFY_URL" && -z "$NYC_NOTIFY_TELEGRAM" ]] && return
    local text="[NYKI] ${title}
${body}"
    if [[ -n "$NYC_NOTIFY_URL" ]]; then
        local escaped; escaped=$(printf '%s' "$text" | json_escape)
        ( curl -fsS --max-time 10 -X POST -H "Content-Type: application/json" \
            -d "{\"text\":\"${escaped}\"}" "$NYC_NOTIFY_URL" >/dev/null 2>&1 ) &
    fi
    if [[ -n "$NYC_NOTIFY_TELEGRAM" ]]; then
        local token chat_id
        IFS=':' read -r token chat_id <<< "$NYC_NOTIFY_TELEGRAM"
        if [[ -n "$token" && -n "$chat_id" ]]; then
            ( curl -fsS --max-time 10 -X POST \
                "https://api.telegram.org/bot${token}/sendMessage" \
                --data-urlencode "chat_id=${chat_id}" \
                --data-urlencode "text=${text}" >/dev/null 2>&1 ) &
        fi
    fi
}

# ------------------------------------------------------------
# AI 服务检测函数
# ------------------------------------------------------------
_http_probe() {
    local url="$1" follow="${2:--L}"
    local opts=(-sS -w '\n%{http_code}' --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME"
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    local resp code
    if [[ "$follow" == "-L" ]]; then
        resp=$(curl -sSL "${opts[@]}" "$url" 2>/dev/null || true)
    else
        resp=$(curl "${opts[@]}" "$url" 2>/dev/null || true)
    fi
    code=$(printf '%s' "$resp" | tail -n1)
    local body=$(printf '%s' "$resp" | head -n -1)
    printf '%s|%s' "$code" "$body"
}

ai_chatgpt() {
    local r code body
    r=$(_http_probe "https://chatgpt.com/api/auth/session" "-L")
    code="${r%%|*}"; body="${r#*|}"
    case "$code" in
        200) printf '可达' ;;
        401)
            if printf '%s' "$body" | grep -qi "unsupported_country\|country_unsupported"; then
                printf '受限|地区限制'
            else
                printf '可达|未登录'
            fi ;;
        403) printf '受限|Cloudflare 拦截' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '可达|HTTP %s' "$code" ;;
    esac
}

ai_claude() {
    local r code
    r=$(_http_probe "https://claude.ai/api/organizations")
    code="${r%%|*}"
    case "$code" in
        401) printf '可达|未登录' ;;
        200) printf '可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

ai_gemini() {
    local redirect code
    redirect=$(curl -sS -o /dev/null -w '%{redirect_url}' \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0" "https://gemini.google.com/" 2>/dev/null || true)
    code=$(curl -sS -o /dev/null -w '%{http_code}' -L \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0" "https://gemini.google.com/" 2>/dev/null || true)
    if [[ "$redirect" == *"sorry"* ]]; then
        printf '受限|地区限制'
    elif [[ "$code" == "200" ]]; then
        printf '可达'
    elif [[ "$code" == "000" ]]; then
        printf '不可达|连接失败'
    else
        printf '未知|HTTP %s' "$code"
    fi
}

ai_grok() {
    local r code
    r=$(_http_probe "https://grok.x.ai/")
    code="${r%%|*}"
    case "$code" in
        200) printf '可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

ai_copilot() {
    local r code
    r=$(_http_probe "https://copilot.microsoft.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '可达|HTTP %s' "$code" ;;
    esac
}

ai_perplexity() {
    local r code
    r=$(_http_probe "https://www.perplexity.ai/")
    code="${r%%|*}"
    case "$code" in
        200) printf '可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '可达|HTTP %s' "$code" ;;
    esac
}

ai_sora() {
    local r code
    r=$(_http_probe "https://sora.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '可达' ;;
        401) printf '可达|需登录' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

ai_midjourney() {
    local r code
    r=$(_http_probe "https://www.midjourney.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '可达|HTTP %s' "$code" ;;
    esac
}

# ------------------------------------------------------------
# 流媒体检测函数
# ------------------------------------------------------------
streaming_netflix() {
    local code
    code=$(curl -sS -o /dev/null -L \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -w '%{http_code}' "https://www.netflix.com/title/81280792" 2>/dev/null || true)
    case "$code" in
        200) printf '入口可达' ;;
        404) printf '部分受限|仅原创剧' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

streaming_disney() {
    local redirect code
    redirect=$(curl -sS -o /dev/null -w '%{redirect_url}' -L \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0" "https://www.disneyplus.com/" 2>/dev/null || true)
    if [[ "$redirect" == *"unavailable"* ]]; then
        printf '受限|地区不支持'; return
    fi
    code=$(curl -sS -o /dev/null -L \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0" -w '%{http_code}' \
        "https://www.disneyplus.com/" 2>/dev/null || true)
    case "$code" in
        200) printf '入口可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

streaming_hbomax() {
    local r code
    r=$(_http_probe "https://www.max.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '入口可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

streaming_prime() {
    local r code
    r=$(_http_probe "https://www.primevideo.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '入口可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '未知|HTTP %s' "$code" ;;
    esac
}

streaming_spotify() {
    local r code
    r=$(_http_probe "https://open.spotify.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '入口可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '入口可达|HTTP %s' "$code" ;;
    esac
}

streaming_tiktok() {
    local code html region
    code=$(curl -sS -o /dev/null -L \
        --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        -w '%{http_code}' "https://www.tiktok.com/" 2>/dev/null || true)
    [[ "$code" == "000" ]] && { printf '不可达|连接失败'; return; }
    html=$(curl -sSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
        "https://www.tiktok.com/" 2>/dev/null || true)
    region=$(printf '%s' "$html" | grep -oE '"region":"[A-Z]+"' | head -n1 | cut -d'"' -f4)
    if [[ -n "$region" ]]; then
        printf '入口可达|地区 %s' "$region"
    else
        printf '入口可达'
    fi
}

streaming_youtube() {
    local r code
    r=$(_http_probe "https://www.youtube.com/")
    code="${r%%|*}"
    case "$code" in
        200) printf '入口可达' ;;
        403) printf '受限|地区限制' ;;
        000) printf '不可达|连接失败' ;;
        *)   printf '入口可达|HTTP %s' "$code" ;;
    esac
}

# ------------------------------------------------------------
# 关于
# ------------------------------------------------------------
about() {
    clear 2>/dev/null || true
    printf '\n'
    printf '  %s%sNYKI / VPS NETWORK CHECK%s\n' "$C_CYAN" "$C_BOLD" "$C_RESET"
    printf '  %s\n\n' "$(repeat_char '─' 50)"
    printf '  %-10s %s\n' "版本" "v${VERSION}"
    printf '  %-10s %s\n' "作者" "${AUTHOR}"
    printf '  %-10s %s\n' "主页" "${HOMEPAGE}"
    printf '  %-10s %s\n' "项目" "${PROJECT}"
    printf '\n  %s项目简介%s\n' "$C_CYAN" "$C_RESET"
    printf '  %s\n' "$(repeat_char '─' 50)"
    printf '  面向海外 VPS 的网络检测工具。纯 bash 实现，\n'
    printf '  零插件、零依赖、零 Python。\n'
    printf '\n  %s设计原则%s\n' "$C_CYAN" "$C_RESET"
    printf '  %s\n' "$(repeat_char '─' 50)"
    printf '   %s零依赖%s  只用系统自带的 curl / ping / traceroute\n' "$C_GREEN" "$C_RESET"
    printf '   %s不假装%s  可达性检测不宣称解锁或无风控\n' "$C_GREEN" "$C_RESET"
    printf '   %s可维护%s  节点与平台全部抽成配置数组\n' "$C_GREEN" "$C_RESET"
    printf '\n  %sMIT License%s\n\n' "$C_DIM" "$C_RESET"
    printf '  按任意键返回菜单...'
    read -r -n 1 -s _ || true
    printf '\n'
}

# ------------------------------------------------------------
# 01 全面检测
# ------------------------------------------------------------
chatgpt_probe() {
    local r code body
    r=$(_http_probe "https://chatgpt.com/api/auth/session" "-L")
    code="${r%%|*}"; body="${r#*|}"
    case "$code" in
        200) printf '正常|HTTP 200' ;;
        401)
            if printf '%s' "$body" | grep -qi "unsupported_country\|country_unsupported"; then
                printf '异常|地区限制'
            else
                printf '正常|HTTP 401'
            fi ;;
        403) printf '异常|Cloudflare 拦截' ;;
        000) printf '异常|连接失败' ;;
        *)   printf '正常|HTTP %s' "$code" ;;
    esac
}

full_check() {
    result_header "全面检测"
    local total=7 ok=0 fail=0 unavailable=0
    local ip4 ip6 code

    printf '  %-22s %-12s %s\n' "检测项目" "状态" "结果"
    line

    local tmp_dir; tmp_dir=$(new_tmp_dir)
    local prog="$tmp_dir/progress"; : > "$prog"

    ( get_ipv4 > "$tmp_dir/ip4" 2>/dev/null; printf '获取 IPv4\n' >> "$prog" ) &
    ( get_ipv6 > "$tmp_dir/ip6" 2>/dev/null; printf '获取 IPv6\n' >> "$prog" ) &
    run_parallel_with_progress "$prog" 2

    ip4=$(cat "$tmp_dir/ip4" 2>/dev/null | tr -d '[:space:]')
    ip6=$(cat "$tmp_dir/ip6" 2>/dev/null | tr -d '[:space:]')
    rm -rf "$tmp_dir"

    [[ -n "$ip4" ]] && { CACHED_IPV4="$ip4"; CACHE_IPV4_TRYED=1; }
    [[ -n "$ip6" ]] && { CACHED_IPV6="$ip6"; CACHE_IPV6_TRYED=1; }

    if [[ -n "$ip4" ]]; then
        printf '  %-22s %-12s %s\n' "公网 IPv4" "$(status_text 正常)" "$(mask_ip "$ip4")"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "公网 IPv4" "$(status_text 异常)" "未获取"
        fail=$((fail + 1))
    fi

    if [[ -n "$ip6" ]]; then
        printf '  %-22s %-12s %s\n' "公网 IPv6" "$(status_text 正常)" "$(mask_ip "$ip6")"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "公网 IPv6" "$(status_text 未配置)" "不可用"
        unavailable=$((unavailable + 1))
    fi

    if has_cmd getent && getent hosts example.com >/dev/null 2>&1; then
        printf '  %-22s %-12s %s\n' "DNS 解析" "$(status_text 正常)" "example.com"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "DNS 解析" "$(status_text 异常)" "解析失败"
        fail=$((fail + 1))
    fi

    code=$(curl -sS -o /dev/null -L --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0" -w '%{http_code}' "https://www.google.com/" 2>/dev/null || true)
    if [[ "$code" != "000" && -n "$code" ]]; then
        printf '  %-22s %-12s HTTP %s\n' "HTTPS 连接" "$(status_text 正常)" "$code"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "HTTPS 连接" "$(status_text 异常)" "连接失败"
        fail=$((fail + 1))
    fi

    if has_cmd ping && ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        printf '  %-22s %-12s %s\n' "ICMP 连通性" "$(status_text 正常)" "1.1.1.1"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "ICMP 连通性" "$(status_text 异常)" "探测失败"
        fail=$((fail + 1))
    fi

    local cgpt; cgpt=$(chatgpt_probe)
    local cgpt_state="${cgpt%%|*}" cgpt_note="${cgpt#*|}"
    if [[ "$cgpt_state" == "正常" ]]; then
        printf '  %-22s %-12s %s\n' "ChatGPT 可达" "$(status_text 正常)" "$cgpt_note"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "ChatGPT 可达" "$(status_text 异常)" "$cgpt_note"
        fail=$((fail + 1))
    fi

    if has_cmd traceroute || has_cmd tracepath; then
        printf '  %-22s %-12s %s\n' "回程路由工具" "$(status_text 正常)" "已安装"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "回程路由工具" "$(status_text 警告)" "缺少 traceroute"
        unavailable=$((unavailable + 1))
    fi

    line
    printf '\n  检测汇总\n'
    item "检测项目" "$total"
    item "正常" "$(status_text "$ok")"
    item "异常" "$(status_text "$fail")"
    item "不可用" "$(status_text "$unavailable")"
    result_footer

    if [[ -n "$NYC_NOTIFY_URL" || -n "$NYC_NOTIFY_TELEGRAM" ]]; then
        local notify_body="主机: $(hostname 2>/dev/null || echo unknown)
IPv4: ${ip4:+$(mask_ip "$ip4")}${ip4:-未获取}
IPv6: ${ip6:+$(mask_ip "$ip6")}${ip6:-未配置}
汇总: ${ok} 正常 / ${fail} 异常 / ${unavailable} 不可用
时间: $(date '+%Y-%m-%d %H:%M:%S')"
        notify_result "全面检测" "$notify_body"
        printf '\n  %s通知已发送%s\n' "$C_DIM" "$C_RESET"
    fi
    pause
}

# ------------------------------------------------------------
# 02-05 IP 相关
# ------------------------------------------------------------
ipv4_check() {
    result_header "IPv4 地址检测"
    local ip
    if ip=$(get_ipv4); then
        item "公网 IPv4" "$(mask_ip "$ip")"
        item "检测状态" "$(status_text 正常)"
    else
        item "公网 IPv4" "未获取"
        item "检测状态" "$(status_text 异常)"
    fi
    result_footer; pause
}

ipv6_check() {
    result_header "IPv6 地址检测"
    local ip
    if ip=$(get_ipv6); then
        item "公网 IPv6" "$(mask_ip "$ip")"
        local v6type="全局单播"
        [[ "$ip" == fe80:* ]] && v6type="链路本地"
        [[ "$ip" == "::1" ]]  && v6type="回环"
        [[ "$ip" == fd* || "$ip" == fc* ]] && v6type="唯一本地"
        item "地址类型" "$v6type"
        item "检测状态" "$(status_text 正常)"
    else
        item "公网 IPv6" "未获取"
        item "检测状态" "$(status_text 未配置)"
    fi
    result_footer; pause
}

ip_info() {
    result_header "IP 信息查询"
    local ip
    printf '  查询地址类型  [4] IPv4  [6] IPv6\n'
    read -r -p "  请选择 [4/6] > " choice
    case "$choice" in
        6) ip=$(get_ipv6 || true) ;;
        *) ip=$(get_ipv4 || true) ;;
    esac
    [[ -z "$ip" ]] && { item "查询结果" "$(status_text 未获取)"; result_footer; pause; return; }
    item "查询地址" "$(mask_ip "$ip")"
    local data
    data=$(curl -fsS --max-time 8 "https://ipwho.is/${ip}" 2>/dev/null || true)
    [[ -z "$data" ]] && { item "查询状态" "$(status_text 失败)"; result_footer; pause; return; }
    item "国家 / 地区" "$(json_field "$data" "country")"
    item "城市" "$(json_field "$data" "city")"
    item "运营商" "$(json_field "$data" "isp")"
    item "组织" "$(json_field "$data" "org")"
    item "ASN" "$(json_field "$data" "asn")"
    item "时区" "$(json_field "$data" "id")"
    result_footer; pause
}

ip_type_check() {
    result_header "IP 类型检测"
    local ip; ip=$(get_ipv4 || true)
    [[ -z "$ip" ]] && {
        item "检测状态" "$(status_text 失败)"
        item "错误信息" "未获取到公网 IPv4"
        result_footer; pause; return
    }
    item "检测地址" "$(mask_ip "$ip")"
    local json
    json=$(curl -fsS --max-time 6 \
        "http://ip-api.com/json/${ip}?fields=status,country,regionName,city,isp,org,as,asname,mobile,proxy,hosting&lang=zh-CN" \
        2>/dev/null || true)
    if [[ -z "$json" ]] || ! printf '%s' "$json" | grep -q '"status":"success"'; then
        item "查询状态" "$(status_text 失败)"
        result_footer; pause; return
    fi
    local country region city isp org asn_line asname mobile proxy hosting
    country=$(json_field "$json" "country")
    region=$(json_field "$json" "regionName")
    city=$(json_field "$json" "city")
    isp=$(json_field "$json" "isp")
    org=$(json_field "$json" "org")
    asn_line=$(json_field "$json" "as")
    asname=$(json_field "$json" "asname")
    mobile=$(json_field "$json" "mobile"); [[ "$mobile" != "true" ]] && mobile="false"
    proxy=$(json_field "$json" "proxy");  [[ "$proxy" != "true" ]] && proxy="false"
    hosting=$(json_field "$json" "hosting"); [[ "$hosting" != "true" ]] && hosting="false"
    local location="$country"
    [[ -n "$region" ]] && location="$location $region"
    [[ -n "$city" ]] && location="$location $city"
    printf '\n'
    item "地理位置" "${location:-未知}"
    item "ASN" "${asn_line:-未知}"
    item "ISP" "${isp:-未知}"
    item "组织" "${org:-未知}"
    line
    local net_type native_judge risk_level
    if [[ "$hosting" == "true" ]]; then net_type="IDC 机房"
    elif [[ "$proxy" == "true" ]]; then net_type="代理 / VPN"
    elif [[ "$mobile" == "true" ]]; then net_type="移动网络"
    else net_type="家庭宽带 / 企业专线"; fi
    if [[ "$hosting" == "true" || "$proxy" == "true" ]]; then
        native_judge="可能为机房 / 代理 IP"
    elif [[ "$asname" =~ (Telecom|Unicom|Mobile|Chinanet|Broadband|Comcast|Verizon|AT\&T) ]] || \
         [[ "$org" =~ (Telecom|Unicom|Mobile|Chinanet|Broadband|Comcast|Verizon|AT\&T) ]]; then
        native_judge="可能为原生 IP"
    else
        native_judge="无法判断"
    fi
    [[ "$hosting" == "true" || "$proxy" == "true" ]] && risk_level="高风险" || risk_level="低风险"
    item "网络类型" "$net_type"
    item "原生性判断" "$(status_text "$native_judge")"
    item "风控参考" "$(status_text "$risk_level")"
    printf '\n'
    item "说明" "原生性为近似判断，非权威结论"
    result_footer; pause
}

# ------------------------------------------------------------
# 06 本机网络配置
# ------------------------------------------------------------
network_config() {
    result_header "本机网络配置"
    if has_cmd ip; then
        item "主机名" "$(hostname 2>/dev/null || echo 未知)"
        printf '\n  网络接口\n'
        ip -o link show 2>/dev/null | while IFS= read -r row; do printf '    %s\n' "$row"; done
        printf '\n  IP 地址\n'
        local addresses; addresses=$(ip -o addr show 2>/dev/null || true)
        [[ "$HIDE_IP" == 1 ]] && addresses=$(mask_text "$addresses")
        while IFS= read -r row; do [[ -n "$row" ]] && printf '    %s\n' "$row"; done <<< "$addresses"
        printf '\n  默认路由\n'
        local routes; routes=$(ip route show default 2>/dev/null || true)
        [[ "$HIDE_IP" == 1 ]] && routes=$(mask_text "$routes")
        if [[ -n "$routes" ]]; then
            while IFS= read -r row; do printf '    %s\n' "$row"; done <<< "$routes"
        else
            printf '    未配置\n'
        fi
    else
        item "检测状态" "系统缺少 ip 命令"
    fi
    printf '\n  DNS 服务器\n'
    if [[ -r /etc/resolv.conf ]]; then
        local has_stub=0
        while IFS= read -r ns; do
            printf '    %-16s %s\n' "DNS" "$ns"
            [[ "$ns" == "127.0.0.53" || "$ns" == "127.0.0.1" ]] && has_stub=1
        done < <(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf)
        if (( has_stub )) && [[ -r /run/systemd/resolve/resolv.conf ]]; then
            printf '    %s(stub 解析器，实际上游)%s\n' "$C_DIM" "$C_RESET"
            while IFS= read -r ns; do
                printf '    %-16s %s\n' "" "$ns"
            done < <(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /run/systemd/resolve/resolv.conf)
        fi
    else
        printf '    无法读取 /etc/resolv.conf\n'
    fi
    result_footer; pause
}

# ------------------------------------------------------------
# 07 DNS 解析检测
# ------------------------------------------------------------
dns_check() {
    result_header "DNS 解析检测"
    local domain
    read -r -p "  输入域名 > " domain
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        item "检测状态" "$(status_text 失败)"
        item "错误信息" "域名格式无效"
        result_footer; pause; return
    fi
    item "查询域名" "$domain"
    local result=""
    if has_cmd getent; then
        result=$(getent ahosts "$domain" 2>/dev/null | awk '!seen[$1]++ {print $1}')
    elif has_cmd dig; then
        result=$( { dig +short "$domain" A; dig +short "$domain" AAAA; } 2>/dev/null | grep -vE '^$')
    elif has_cmd nslookup; then
        result=$(nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}' | grep -v '#' | sort -u)
    fi
    if [[ -n "$result" ]]; then
        printf '\n  解析结果\n'
        while IFS= read -r addr; do
            [[ -n "$addr" ]] && item "地址" "$(mask_ip "$addr")"
        done <<< "$result"
        item "检测状态" "$(status_text 正常)"
    else
        item "检测状态" "$(status_text 失败)"
        item "说明" "未获取到解析结果或缺少工具"
    fi
    result_footer; pause
}

# ------------------------------------------------------------
# 08 DNS 出口检测
# ------------------------------------------------------------
dns_egress_check() {
    result_header "DNS 出口检测"
    local exit_ipv4; exit_ipv4=$(get_ipv4 || true)
    [[ -n "$exit_ipv4" ]] && item "流量出口 IP" "$(mask_ip "$exit_ipv4")"

    local dns_egress=""
    if has_cmd dig; then
        dns_egress=$(dig +short +time=3 +tries=1 whoami.akamai.net 2>/dev/null | head -n1)
    elif has_cmd nslookup; then
        dns_egress=$(nslookup whoami.akamai.net 2>/dev/null | awk '/^Address: / {print $2; exit}')
    fi

    if [[ -n "$dns_egress" ]]; then
        item "DNS 出口 IP" "$(mask_ip "$dns_egress")"
        if [[ -n "$exit_ipv4" && "$dns_egress" != "$exit_ipv4" ]]; then
            item "泄漏评估" "$(status_text 警告)"
            item "说明" "DNS 出口与流量出口不一致"
        else
            item "泄漏评估" "$(status_text 正常)"
            item "说明" "DNS 出口与流量出口一致"
        fi
    else
        item "DNS 出口 IP" "未获取"
        item "泄漏评估" "$(status_text 未知)"
        item "说明" "需要 dig 或 nslookup 才能检测"
    fi
    printf '\n'
    if [[ -r /etc/resolv.conf ]]; then
        printf '  DNS 服务器\n'
        while IFS= read -r d; do
            local type="公共 DNS"
            case "$d" in
                127.*|::1) type="本地解析器" ;;
                10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*) type="私有网络" ;;
            esac
            printf '    %-22s %s\n' "$d" "$type"
        done < <(awk '/^[[:space:]]*nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf)
    fi
    result_footer; pause
}

# ------------------------------------------------------------
# 09 网络质量检测
# ------------------------------------------------------------
network_quality() {
    result_header "网络质量检测"
    local target="1.1.1.1"
    has_cmd ping || { item "检测状态" "缺少 ping 命令"; result_footer; pause; return; }
    while true; do
        item "检测目标" "$(mask_ip "$target")"
        local output loss rtt
        output=$(ping -c 4 -W 2 "$target" 2>&1 || true)
        [[ "$HIDE_IP" == 1 ]] && output=$(mask_text "$output")
        loss=$(printf '%s\n' "$output" | grep -oE '[0-9.]+% packet loss' | tail -n 1 || true)
        rtt=$(printf '%s\n' "$output" |
            grep -oE '(rtt|round-trip) min/avg/max[^=]*= [0-9.]+/[0-9.]+/[0-9.]+(/[0-9.]+)?' |
            head -n1 | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+(/[0-9.]+)?' || true)
        item "丢包率" "${loss:-未知}"
        item "延迟统计" "${rtt:+${rtt} ms}${rtt:-未知}"
        printf '\n  检测详情\n'
        while IFS= read -r row; do [[ -n "$row" ]] && printf '    %s\n' "$row"; done <<< "$output"
        result_footer
        local rc; pause; rc=$?
        (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
        (( rc == 1 )) && continue
        break
    done
}

# ------------------------------------------------------------
# 10 TCP 端口
# ------------------------------------------------------------
tcp_check() {
    result_header "TCP 端口连通性检测"
    local host port
    read -r -p "  目标主机 > " host
    read -r -p "  TCP 端口 > " port
    if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ ]] ||
       (( 10#$port < 1 || 10#$port > 65535 )); then
        item "检测状态" "$(status_text 失败)"
        item "错误信息" "主机或端口无效"
        result_footer; pause; return
    fi
    item "目标主机" "$(mask_ip "$host")"
    item "目标端口" "$port"
    if has_cmd timeout; then
        if timeout 5 bash -c 'cat < /dev/null > "/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
            item "连接状态" "$(status_text 正常)"
        else
            item "连接状态" "$(status_text 异常)"
        fi
    elif has_cmd nc; then
        if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
            item "连接状态" "$(status_text 正常)"
        else
            item "连接状态" "$(status_text 异常)"
        fi
    else
        item "检测状态" "需要 timeout 或 nc"
    fi
    result_footer; pause
}

# ------------------------------------------------------------
# 11 MTU
# ------------------------------------------------------------
mtu_probe() {
    local target="$1"
    local lo=0 hi=1472 mid
    if ! ping -c 1 -W 2 -M do -s 100 "$target" >/dev/null 2>&1; then
        printf '0'; return
    fi
    if ping -c 1 -W 2 -M do -s "$hi" "$target" >/dev/null 2>&1; then
        printf '1500'; return
    fi
    while (( hi - lo > 1 )); do
        mid=$(( (lo + hi) / 2 ))
        if ping -c 1 -W 2 -M do -s "$mid" "$target" >/dev/null 2>&1; then
            lo=$mid
        else
            hi=$mid
        fi
    done
    (( lo > 0 )) && printf '%d' "$((lo + 28))" || printf '0'
}

mtu_check() {
    result_header "MTU 排查"
    has_cmd ping || { item "检测状态" "缺少 ping 命令"; result_footer; pause; return; }
    local target="1.1.1.1"
    while true; do
        item "检测目标" "$(mask_ip "$target")"
        spinner_start "MTU 二分探测中"
        local mtu; mtu=$(mtu_probe "$target")
        spinner_stop
        if [[ "$mtu" == "1500" ]]; then
            item "探测 MTU" "$(status_text 正常) 1500"
            item "说明" "标准以太网 MTU"
        elif [[ "$mtu" == "0" ]]; then
            item "探测 MTU" "$(status_text 失败)"
            item "说明" "不支持 DF 或探测失败"
        else
            item "探测 MTU" "$(status_text 警告) $mtu"
            item "说明" "非标准 MTU，可能经过隧道"
        fi
        item "提示" "结果受防火墙和 ICMP 策略影响"
        result_footer
        local rc; pause; rc=$?
        (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
        (( rc == 1 )) && continue
        break
    done
}

# ------------------------------------------------------------
# 12 路由追踪
# ------------------------------------------------------------
route_trace() {
    result_header "路由追踪"
    local target="1.1.1.1"
    has_cmd traceroute || has_cmd tracepath || { item "检测状态" "未安装 traceroute"; result_footer; pause; return; }
    while true; do
        item "目标地址" "$(mask_ip "$target")"
        printf '\n  路由结果\n'
        local output
        if has_cmd traceroute; then
            output=$(traceroute -n -q 1 -m "$TRACE_MAX_HOPS" -w "$TRACE_TIMEOUT" "$target" 2>&1 || true)
        else
            output=$(tracepath -m "$TRACE_MAX_HOPS" "$target" 2>&1 || true)
        fi
        [[ "$HIDE_IP" == 1 ]] && output=$(mask_text "$output")
        while IFS= read -r row; do printf '    %s\n' "$row"; done <<< "$output"
        if printf '%s' "$output" | grep -qE '^\s*[0-9]+\s+\* \* \*' && \
           ! printf '%s' "$output" | grep -qE '^\s*[0-9]+\s+[0-9]'; then
            printf '\n'
            item "提示" "ICMP 被过滤，可尝试 TCP 模式"
        fi
        result_footer
        local rc; pause; rc=$?
        (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
        (( rc == 1 )) && continue
        break
    done
}

# ------------------------------------------------------------
# 13 三网回程路由
# ------------------------------------------------------------
extract_hops() { grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}'; }

batch_asn_lookup() {
    local ips=("$@")
    (( ${#ips[@]} == 0 )) && return
    local json_array="[" first=1 ip
    for ip in "${ips[@]}"; do
        (( first )) || json_array+=","
        json_array+="\"$ip\""
        first=0
    done
    json_array+="]"
    local response
    response=$(curl -fsS --max-time 10 -X POST \
        -H "Content-Type: application/json" -d "$json_array" \
        "http://ip-api.com/batch?fields=query,as,org" 2>/dev/null || true)
    [[ -z "$response" ]] && return
    printf '%s' "$response" | grep -oE '\{[^{}]*\}' | while IFS= read -r entry; do
        local q asn org
        q=$(printf '%s' "$entry" | sed -n 's/.*"query":"\([^"]*\)".*/\1/p')
        asn=$(printf '%s' "$entry" | sed -n 's/.*"as":"AS\([0-9]\+\).*/\1/p')
        org=$(printf '%s' "$entry" | sed -n 's/.*"org":"\([^"]*\)".*/\1/p')
        [[ -n "$q" ]] && printf '%s|%s|%s\n' "$q" "${asn:-?}" "${org:-?}"
    done
}

lookup_asn() {
    local ip="$1" map_file="$2"
    [[ -f "$map_file" ]] || { printf '?'; return; }
    local r; r=$(grep "^${ip}|" "$map_file" 2>/dev/null | head -n1 | cut -d'|' -f2)
    printf '%s' "${r:-?}"
}

detect_line_type() {
    local map_file="$1"; shift
    local hops=("$@")
    (( ${#hops[@]} == 0 )) && { printf '不可达'; return; }
    local total=${#hops[@]}
    local has_5943=0 has_20297=0 has_9929=0 has_cmin2=0 has_cmi=0 has_4837=0
    local i=0 h
    for h in "${hops[@]}"; do
        case "$h" in
            59.43.*) has_5943=1 ;;
            202.97.*) has_20297=1 ;;
            218.105.*|210.51.*) has_9929=1 ;;
            221.183.*|211.136.*) has_cmin2=1 ;;
            120.196.*) has_cmi=1 ;;
            219.158.*) has_4837=1 ;;
        esac
        i=$((i + 1))
    done
    if (( has_5943 )); then
        (( has_20297 )) && printf 'CN2 GT (半优化)' || printf 'CN2 GIA (优化)'
        return
    fi
    (( has_9929 ))  && { printf '联通 9929 (优化)'; return; }
    (( has_cmin2 )) && { printf '移动 CMIN2 (优化)'; return; }
    (( has_4837 ))  && { printf '联通 4837 (普通)'; return; }
    (( has_cmi ))   && { printf '移动 CMI (普通)'; return; }
    (( has_20297 )) && { printf '电信 163 (普通)'; return; }
    for h in "${hops[@]}"; do
        case "$(lookup_asn "$h" "$map_file")" in
            4809)  printf 'CN2 (AS4809)'; return ;;
            9929)  printf '联通 9929 (AS9929)'; return ;;
            58807) printf '移动 CMIN2 (AS58807)'; return ;;
            4837)  printf '联通 4837 (AS4837)'; return ;;
            58453) printf '移动 CMI (AS58453)'; return ;;
            4134)  printf '电信 163 (AS4134)'; return ;;
        esac
    done
    printf '未知'
}

line_asn() {
    case "$1" in
        *CN2*)    printf 'AS4809' ;;
        *9929*)   printf 'AS9929' ;;
        *CMIN2*)  printf 'AS58807' ;;
        *4837*)   printf 'AS4837' ;;
        *CMI*)    printf 'AS58453' ;;
        *163*)    printf 'AS4134' ;;
        *)        printf '' ;;
    esac
}

backtrace_check() {
    result_header "三网回程路由检测"

    local trace_cmd=""
    has_cmd traceroute && trace_cmd="traceroute"
    has_cmd tracepath && [[ -z "$trace_cmd" ]] && trace_cmd="tracepath"
    if [[ -z "$trace_cmd" ]]; then
        item "检测状态" "系统缺少 traceroute / tracepath"
        item "安装命令" "apt install -y traceroute"
        result_footer; pause; return
    fi

    local total=${#TRI_NET_NODES[@]}
    printf '  %s阶段 1/3%s  并行 traceroute (%d 节点)\n' \
        "$C_CYAN" "$C_RESET" "$total"
    printf '  %s\n' "$(repeat_char '─' 50)"

    local tmp_dir; tmp_dir=$(new_tmp_dir)
    local prog="$tmp_dir/progress"; : > "$prog"

    local i=0 node isp region ip
    for node in "${TRI_NET_NODES[@]}"; do
        IFS='|' read -r isp region ip <<< "$node"
        printf -v fname '%02d' "$i"
        (
            if [[ "$trace_cmd" == "traceroute" ]]; then
                traceroute -n -q 1 -m "$TRACE_MAX_HOPS" -w "$TRACE_TIMEOUT" "$ip" > "$tmp_dir/trace_$fname" 2>&1
            else
                tracepath -m "$TRACE_MAX_HOPS" "$ip" > "$tmp_dir/trace_$fname" 2>&1
            fi
            printf '%s %s\n' "$isp" "$region" >> "$prog"
        ) &
        i=$((i + 1))
    done
    run_parallel_with_progress "$prog" "$total"

    # 阶段 2
    printf '\n  %s阶段 2/3%s  查询 ASN\n' "$C_CYAN" "$C_RESET"
    local all_hops=() tf
    for tf in "$tmp_dir"/trace_*; do
        [[ -f "$tf" ]] || continue
        while IFS= read -r h; do
            [[ -n "$h" ]] && all_hops+=("$h")
        done < <(extract_hops < "$tf")
    done
    local unique_hops=()
    if (( ${#all_hops[@]} > 0 )); then
        mapfile -t unique_hops < <(printf '%s\n' "${all_hops[@]}" | sort -u)
    fi
    printf '  收集到 %d 个去重跳点\n' "${#unique_hops[@]}"
    local asn_map="$tmp_dir/asn_map"; : > "$asn_map"
    if (( ${#unique_hops[@]} > 0 && ${#unique_hops[@]} <= 100 )); then
        batch_asn_lookup "${unique_hops[@]}" > "$asn_map" 2>/dev/null || true
        printf '  ASN 查询完成，命中 %s 条\n' "$(wc -l < "$asn_map" | tr -d ' ')"
    fi

    # 阶段 3
    printf '\n  %s阶段 3/3%s  线路分析\n\n' "$C_CYAN" "$C_RESET"
    printf '  %-6s %-6s %-22s %s\n' "运营商" "地区" "线路类型 (ASN)" "关键跳 IP"
    printf '  %s\n' "$(repeat_char '─' 56)"

    i=0
    for node in "${TRI_NET_NODES[@]}"; do
        IFS='|' read -r isp region ip <<< "$node"
        printf -v fname '%02d' "$i"
        local tf="$tmp_dir/trace_$fname"
        local hops_arr=()
        if [[ -f "$tf" ]]; then
            while IFS= read -r h; do
                [[ "$h" == "$ip" ]] && continue
                [[ -n "$h" ]] && hops_arr+=("$h")
            done < <(extract_hops < "$tf" | sort -u)
        fi
        local line_type; line_type=$(detect_line_type "$asn_map" "${hops_arr[@]}")
        local key_ip="—" h
        for h in "${hops_arr[@]}"; do
            case "$h" in 59.43.*) key_ip="$h" ;; esac
        done
        if [[ "$key_ip" == "—" ]]; then
            for h in "${hops_arr[@]}"; do
                case "$h" in
                    218.105.*|210.51.*|219.158.*|221.183.*|211.136.*|120.196.*|202.97.*)
                        key_ip="$h" ;;
                esac
            done
        fi
        local asn_disp; asn_disp=$(line_asn "$line_type")
        local type_disp="$line_type"
        [[ -n "$asn_disp" ]] && type_disp="$line_type $asn_disp"
        local colored="$type_disp"
        if [[ "$line_type" == *"优化"* ]]; then
            colored="${C_GREEN}${type_disp}${C_RESET}"
        elif [[ "$line_type" == *"普通"* ]]; then
            colored="${C_YELLOW}${type_disp}${C_RESET}"
        fi
        printf '  %-6s %-6s %-22b %s\n' \
            "$isp" "$region" "$colored" "$(mask_ip "$key_ip")"
        i=$((i + 1))
    done
    rm -rf "$tmp_dir"
    printf '  %s\n' "$(repeat_char '─' 56)"
    printf '\n'
    item "检测说明" "traceroute 路径 + 特征段 + ASN"
    result_footer; pause
}

# ------------------------------------------------------------
# 14 IPv6 路由追踪
# ------------------------------------------------------------
ipv6_route_check() {
    result_header "IPv6 路由追踪"
    local trace_cmd=""
    has_cmd traceroute6 && trace_cmd="traceroute6"
    has_cmd traceroute && [[ -z "$trace_cmd" ]] && trace_cmd="traceroute -6"
    has_cmd tracepath6 && [[ -z "$trace_cmd" ]] && trace_cmd="tracepath6"
    if [[ -z "$trace_cmd" ]]; then
        item "检测状态" "系统缺少 traceroute6 / tracepath6"
        item "安装命令" "apt install -y traceroute"
        result_footer; pause; return
    fi
    local v6; v6=$(get_ipv6 || true)
    if [[ -z "$v6" ]]; then
        item "检测状态" "$(status_text 未配置)"
        item "说明" "本机无公网 IPv6，无法测试"
        result_footer; pause; return
    fi
    item "本机 IPv6" "$(mask_ip "$v6")"
    printf '\n'
    local t name addr output
    for t in "${IPV6_ROUTE_TARGETS[@]}"; do
        IFS='|' read -r name addr <<< "$t"
        printf '  %s%s%s  %s\n' "$C_CYAN" "$name" "$C_RESET" "$(mask_ip "$addr")"
        if [[ "$trace_cmd" == "traceroute -6" ]]; then
            output=$(traceroute -6 -n -q 1 -m "$TRACE_MAX_HOPS" -w "$TRACE_TIMEOUT" "$addr" 2>&1 || true)
        else
            output=$("$trace_cmd" -n -q 1 -m "$TRACE_MAX_HOPS" -w "$TRACE_TIMEOUT" "$addr" 2>&1 || true)
        fi
        [[ "$HIDE_IP" == 1 ]] && output=$(mask_text "$output")
        while IFS= read -r row; do printf '    %s\n' "$row"; done <<< "$output"
        printf '\n'
    done
    result_footer; pause
}

# ------------------------------------------------------------
# 15 三网延迟检测
# ------------------------------------------------------------
tri_ping_node() {
    local ip="$1"
    local output
    output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" 2>&1 || true)
    [[ -z "$output" ]] && { printf 'TIMEOUT'; return; }
    if printf '%s' "$output" | grep -qi "Destination Host Unreachable\|Network is unreachable"; then
        printf 'UNREACHABLE'; return
    fi
    local rtt
    rtt=$(printf '%s\n' "$output" |
        grep -oE '(rtt|round-trip) min/avg/max[^=]*= [0-9.]+/[0-9.]+/[0-9.]+' |
        head -n1 | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+' || true)
    [[ -z "$rtt" ]] && { printf 'TIMEOUT'; return; }
    printf '%s' "$rtt"
}

tri_quality() {
    local val="$1"
    case "$val" in
        TIMEOUT)     printf '超时'; return ;;
        UNREACHABLE) printf '不可达'; return ;;
    esac
    local avg; avg=$(printf '%s' "$val" | cut -d/ -f2)
    local n; n=$(awk "BEGIN{printf \"%.0f\", $avg}" 2>/dev/null || echo 0)
    if (( n < 50 )); then printf '优秀'
    elif (( n < 100 )); then printf '良好'
    elif (( n < 200 )); then printf '一般'
    elif (( n < 300 )); then printf '较差'
    else printf '极差'; fi
}

tri_net_ping() {
    result_header "三网延迟检测"
    has_cmd ping || { item "检测状态" "缺少 ping 命令"; result_footer; pause; return; }

    printf '  %s并行 Ping (%d 节点，每节点 %d 次)\n%s' \
        "$C_CYAN" "${#TRI_NET_NODES[@]}" "$PING_COUNT" "$C_RESET"
    printf '  %s\n' "$(repeat_char '─' 50)"

    local tmp_dir; tmp_dir=$(new_tmp_dir)
    local prog="$tmp_dir/progress"; : > "$prog"

    local i=0 node isp region ip
    for node in "${TRI_NET_NODES[@]}"; do
        IFS='|' read -r isp region ip <<< "$node"
        printf -v fname '%02d' "$i"
        (
            local rtt q
            rtt=$(tri_ping_node "$ip")
            q=$(tri_quality "$rtt")
            printf '%s|%s|%s|%s\n' "$isp" "$region" "$rtt" "$q" > "$tmp_dir/$fname"
            printf '%s %s\n' "$isp" "$region" >> "$prog"
        ) &
        i=$((i + 1))
    done
    run_parallel_with_progress "$prog" "${#TRI_NET_NODES[@]}"

    printf '\n  %-6s %-6s %22s %s\n' "运营商" "节点" "延迟 min/avg/max" "质量"
    printf '  %s\n' "$(repeat_char '─' 50)"

    local last_isp=""
    for isp_want in "电信" "联通" "移动"; do
        for f in "$tmp_dir"/*; do
            [[ -f "$f" ]] || continue
            local fi fregion frtt fq
            IFS='|' read -r fi fregion frtt fq < "$f"
            [[ "$fi" != "$isp_want" ]] && continue
            local isp_disp="$fi"; [[ "$fi" == "$last_isp" ]] && isp_disp=""; last_isp="$fi"
            local disp
            case "$frtt" in
                TIMEOUT)     disp="超时" ;;
                UNREACHABLE) disp="不可达" ;;
                *)           disp="${frtt}ms" ;;
            esac
            printf '  %-6s %-6s %22s %s\n' \
                "$isp_disp" "$fregion" "$disp" "$(status_text "$fq")"
        done
    done
    rm -rf "$tmp_dir"
    printf '  %s\n' "$(repeat_char '─' 50)"
    printf '\n'
    item "检测说明" "ICMP Ping，每节点 ${PING_COUNT} 次采样"
    result_footer; pause
}

# ------------------------------------------------------------
# 16 AI 服务检测
# ------------------------------------------------------------
ai_check_all() {
    result_header "AI 服务检测（入口可达性）"
    printf '  %s并行检测 (%d 服务)\n%s' \
        "$C_CYAN" "${#AI_SERVICES[@]}" "$C_RESET"
    printf '  %s\n' "$(repeat_char '─' 50)"

    local tmp_dir; tmp_dir=$(new_tmp_dir)
    local prog="$tmp_dir/progress"; : > "$prog"

    local i=0 svc name fn
    for svc in "${AI_SERVICES[@]}"; do
        IFS='|' read -r name fn <<< "$svc"
        printf -v fname '%02d' "$i"
        (
            local r state note
            r=$("$fn")
            state="${r%%|*}"
            note="${r#*|}"
            [[ "$note" == "$state" ]] && note=""
            printf '%s|%s|%s\n' "$name" "$state" "$note" > "$tmp_dir/$fname"
            printf '%s\n' "$name" >> "$prog"
        ) &
        i=$((i + 1))
    done
    run_parallel_with_progress "$prog" "${#AI_SERVICES[@]}"

    printf '\n  %-14s %-10s %s\n' "服务" "状态" "说明"
    line
    for f in "$tmp_dir"/*; do
        [[ -f "$f" ]] || continue
        local name state note
        IFS='|' read -r name state note < "$f"
        printf '  %-14s %-10s %s\n' "$name" "$(status_text "$state")" "$note"
    done
    rm -rf "$tmp_dir"
    printf '\n'
    item "说明" "入口可达性检测，不代表账号无风控"
    result_footer; pause
}

# ------------------------------------------------------------
# 17 流媒体检测
# ------------------------------------------------------------
streaming_check_all() {
    result_header "流媒体检测（入口可达性）"
    printf '  %s并行检测 (%d 平台)\n%s' \
        "$C_CYAN" "${#STREAMING_SERVICES[@]}" "$C_RESET"
    printf '  %s\n' "$(repeat_char '─' 50)"

    local tmp_dir; tmp_dir=$(new_tmp_dir)
    local prog="$tmp_dir/progress"; : > "$prog"

    local i=0 svc name fn
    for svc in "${STREAMING_SERVICES[@]}"; do
        IFS='|' read -r name fn <<< "$svc"
        printf -v fname '%02d' "$i"
        (
            local r state note
            r=$("$fn")
            state="${r%%|*}"
            note="${r#*|}"
            [[ "$note" == "$state" ]] && note=""
            printf '%s|%s|%s\n' "$name" "$state" "$note" > "$tmp_dir/$fname"
            printf '%s\n' "$name" >> "$prog"
        ) &
        i=$((i + 1))
    done
    run_parallel_with_progress "$prog" "${#STREAMING_SERVICES[@]}"

    printf '\n  %-16s %-10s %s\n' "平台" "状态" "说明"
    line
    for f in "$tmp_dir"/*; do
        [[ -f "$f" ]] || continue
        local name state note
        IFS='|' read -r name state note < "$f"
        printf '  %-16s %-10s %s\n' "$name" "$(status_text "$state")" "$note"
    done
    rm -rf "$tmp_dir"
    printf '\n'
    item "说明" "HTTP 入口可达性，不代表内容解锁"
    item "完整解锁" "建议使用 RegionRestrictionCheck"
    result_footer; pause
}

# ------------------------------------------------------------
# 18 网站连通性
# ------------------------------------------------------------
website_check() {
    result_header "网站连通性检测"
    local url
    read -r -p "  输入网址 > " url
    [[ -z "$url" ]] && { item "检测状态" "$(status_text 失败)"; result_footer; pause; return; }
    [[ "$url" =~ ^https?:// ]] || url="https://${url}"
    item "目标网址" "$url"
    local start end code err_file err_msg
    err_file=$(mktemp)
    start=$(date +%s)
    code=$(curl -L -sS -o /dev/null --connect-timeout "$CURL_CONNECT_TIMEOUT" --max-time "$CURL_MAX_TIME" \
        -H "User-Agent: Mozilla/5.0" -w '%{http_code}' "$url" 2>"$err_file" || true)
    end=$(date +%s)
    err_msg=$(cat "$err_file" 2>/dev/null); rm -f "$err_file"
    item "HTTP 状态码" "$code"
    item "响应耗时" "$((end - start)) s"
    if [[ "$code" == "000" ]]; then
        if printf '%s' "$err_msg" | grep -qi "SSL certificate"; then
            item "连接状态" "$(status_text 警告)"
            item "说明" "SSL 证书验证失败"
        elif printf '%s' "$err_msg" | grep -qi "timed out"; then
            item "连接状态" "$(status_text 异常)"
            item "说明" "连接超时"
        elif printf '%s' "$err_msg" | grep -qi "resolve"; then
            item "连接状态" "$(status_text 异常)"
            item "说明" "域名解析失败"
        else
            item "连接状态" "$(status_text 异常)"
        fi
    else
        item "连接状态" "$(status_text 正常)"
    fi
    result_footer; pause
}

# ------------------------------------------------------------
# 19 系统信息
# ------------------------------------------------------------
system_info() {
    result_header "系统信息"
    item "主机名" "$(hostname 2>/dev/null || echo 未知)"
    item "系统内核" "$(uname -sr 2>/dev/null || echo 未知)"
    if [[ -r /etc/os-release ]]; then
        local os_name; os_name=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-未知}")
        item "操作系统" "$os_name"
    fi
    item "运行时间" "$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo 未知)"
    item "CPU 架构" "$(uname -m 2>/dev/null || echo 未知)"
    has_cmd nproc && item "CPU 线程" "$(nproc 2>/dev/null)"
    if has_cmd free; then
        local mem
        mem=$(free -h 2>/dev/null | awk '/^Mem:/ { printf "%s / %s", $3, $2 }')
        [[ -z "$mem" ]] && mem=$(free -m 2>/dev/null | awk '/^Mem:/ { printf "%sM / %sM", $3, $2 }')
        item "内存使用" "${mem:-未知}"
    fi
    if has_cmd df; then
        local disk; disk=$(df -h / 2>/dev/null | awk 'NR==2 { printf "%s / %s (%s)", $3, $2, $5 }')
        item "系统磁盘" "${disk:-未知}"
    fi
    has_cmd systemd-detect-virt && item "虚拟化" "$(systemd-detect-virt 2>/dev/null || echo 未知)"
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        local limit; limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
        [[ "$limit" != "max" && -n "$limit" ]] && \
            item "容器内存限制" "$(numfmt --to=iec "$limit" 2>/dev/null || echo "$limit")"
    fi
    result_footer; pause
}

toggle_hide_ip() {
    if [[ "$HIDE_IP" == 1 ]]; then HIDE_IP=0; else HIDE_IP=1; fi
}

# ------------------------------------------------------------
# 依赖预检
# ------------------------------------------------------------
check_deps() {
    if [[ ! -t 0 ]]; then
        printf '%s错误：交互式输入不可用。%s\n' "$C_RED" "$C_RESET" >&2
        printf '请使用：bash <(curl -fsSL %s)\n' "$RAW_URL" >&2
        printf '而不是：curl -fsSL %s | bash\n' "$RAW_URL" >&2
        exit 1
    fi
    if ! has_cmd curl; then
        printf '%s缺少必要命令: curl%s\n' "$C_RED" "$C_RESET" >&2
        printf 'Ubuntu/Debian: apt install -y curl\n' >&2
        printf 'RHEL/CentOS:   yum install -y curl\n' >&2
        exit 1
    fi
    local soft_missing=()
    has_cmd ping || soft_missing+=("ping")
    has_cmd traceroute || has_cmd tracepath || soft_missing+=("traceroute")
    if (( ${#soft_missing[@]} > 0 )); then
        printf '%s提示：缺少 %s，部分功能不可用%s\n' \
            "$C_YELLOW" "${soft_missing[*]}" "$C_RESET" >&2
        printf 'Ubuntu: apt install -y iputils-ping traceroute\n' >&2
        printf '按回车继续...' >&2
        read -r _ || exit 1
    fi
}

# ------------------------------------------------------------
# 主菜单
# ------------------------------------------------------------
menu() {
    init_layout
    clear 2>/dev/null || true
    top_border
    box_text "${C_CYAN}${C_BOLD}NYKI / VPS NETWORK CHECK${C_RESET}  ${C_DIM}v${VERSION}${C_RESET}"
    box_text "VPS 网络检测工具"
    box_text ""
    box_text "作者    ${AUTHOR}"
    box_text "主页    ${HOMEPAGE}"
    box_text "项目    ${PROJECT}"
    mid_border
    box_text ""
    box_text "${C_CYAN}IP 检测${C_RESET}"
    box_text ""
    box_text "  01  全面检测"
    box_text "  02  IPv4 地址检测"
    box_text "  03  IPv6 地址检测"
    box_text "  04  IP 信息查询"
    box_text "  05  IP 类型检测"
    box_text ""
    box_text "${C_CYAN}网络检测${C_RESET}"
    box_text ""
    box_text "  06  本机网络配置"
    box_text "  07  DNS 解析检测"
    box_text "  08  DNS 出口检测"
    box_text "  09  网络质量检测"
    box_text "  10  TCP 端口连通性检测"
    box_text "  11  MTU 排查"
    box_text "  12  路由追踪"
    box_text ""
    box_text "${C_CYAN}回程与三网${C_RESET}"
    box_text ""
    box_text "  13  三网回程路由检测"
    box_text "  14  IPv6 路由追踪"
    box_text "  15  三网延迟检测"
    box_text ""
    box_text "${C_CYAN}应用检测${C_RESET}"
    box_text ""
    box_text "  16  AI 服务检测"
    box_text "  17  流媒体检测"
    box_text "  18  网站连通性检测"
    box_text ""
    box_text "${C_CYAN}系统与帮助${C_RESET}"
    box_text ""
    box_text "  19  系统信息"
    box_text "  20  关于本项目"
    box_text ""
    mid_border
    box_text "${C_CYAN}隐私保护${C_RESET}"
    if [[ "$HIDE_IP" == 1 ]]; then
        box_text "  隐藏 IP 模式    ${C_GREEN}[已开启]${C_RESET}"
    else
        box_text "  隐藏 IP 模式    ${C_YELLOW}[已关闭]${C_RESET}"
    fi
    box_text "  21  切换隐藏 IP 模式"
    mid_border
    box_text ""
    box_text "  请输入选项  [01-21 / 00 退出]"
    bottom_border
    printf '\n'
    if ! read -r -p "  > " choice; then
        printf '\n  已退出\n'; exit 0
    fi
    choice="${choice#0}"; choice="${choice#0}"
    case "$choice" in
        1)  retry_loop full_check ;;
        2)  retry_loop ipv4_check ;;
        3)  retry_loop ipv6_check ;;
        4)  retry_loop ip_info ;;
        5)  retry_loop ip_type_check ;;
        6)  retry_loop network_config ;;
        7)  retry_loop dns_check ;;
        8)  retry_loop dns_egress_check ;;
        9)  retry_loop network_quality ;;
        10) retry_loop tcp_check ;;
        11) retry_loop mtu_check ;;
        12) retry_loop route_trace ;;
        13) retry_loop backtrace_check ;;
        14) retry_loop ipv6_route_check ;;
        15) retry_loop tri_net_ping ;;
        16) retry_loop ai_check_all ;;
        17) retry_loop streaming_check_all ;;
        18) retry_loop website_check ;;
        19) retry_loop system_info ;;
        20) about ;;
        21) toggle_hide_ip ;;
        ""|q|Q|exit)
            printf '\n  感谢使用 %s\n' "VPS 网络检测工具"
            exit 0 ;;
        *)
            printf '\n  %s无效选项，请重新输入。%s\n' "$C_YELLOW" "$C_RESET"
            sleep 1 ;;
    esac
}

# ------------------------------------------------------------
# 参数处理 & 入口
# ------------------------------------------------------------
while (( $# > 0 )); do
    case "$1" in
        -v|--version) printf 'v%s\n' "$VERSION"; exit 0 ;;
        -h|--help)
            cat <<EOF
NYKI / VPS NETWORK CHECK v${VERSION}

用法:
  bash <(curl -fsSL ${RAW_URL}) [选项]

选项:
  -h, --help                显示帮助
  -v, --version             显示版本
  --no-mask                 关闭 IP 隐藏
  --notify <url>            通用 Webhook
  --notify-telegram <t:c>   Telegram Bot，格式 token:chat_id

环境变量:
  NYC_NOTIFY_URL            同 --notify
  NYC_NOTIFY_TELEGRAM       同 --notify-telegram
EOF
            exit 0 ;;
        --no-mask) HIDE_IP=0; shift ;;
        --notify) NYC_NOTIFY_URL="${2:-}"; shift 2 ;;
        --notify-telegram) NYC_NOTIFY_TELEGRAM="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "${NYC_SOURCED:-}" ]]; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        check_deps
        while true; do menu; done
    fi
fi
