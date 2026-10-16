#!/usr/bin/env bash
# ============================================================
# NYKI / VPS NETWORK CHECK
# VPS 网络检测工具
# 作者：阿晚
# 主页：https://nyki.cc
# 项目：https://github.com/nyki4/vps-network-check
# 版本：v4.2.1
# ============================================================
VERSION="4.2.1"
AUTHOR="阿晚"
HOMEPAGE="https://nyki.cc"
PROJECT="https://github.com/nyki4/vps-network-check"
RAW_URL="https://raw.githubusercontent.com/nyki4/vps-network-check/main/vps-network-check.sh"

HIDE_IP=1
PING_COUNT=4
PING_TIMEOUT=3

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

AI_SERVICES=(
    "ChatGPT|status_code|https://chatgpt.com/api/auth/session"
    "Claude|status_code|https://claude.ai/api/organizations"
    "Gemini|status_code|https://gemini.google.com/"
    "Grok|status_code|https://grok.x.ai/"
    "Copilot|status_code|https://copilot.microsoft.com/"
    "Perplexity|status_code|https://www.perplexity.ai/"
    "Sora|status_code|https://sora.com/"
    "Midjourney|status_code|https://www.midjourney.com/"
)

STREAMING_SERVICES=(
    "Netflix|status_code|https://www.netflix.com/"
    "Disney+|status_code|https://www.disneyplus.com/"
    "HBO Max|status_code|https://www.max.com/"
    "Prime Video|status_code|https://www.primevideo.com/"
    "Spotify|status_code|https://open.spotify.com/"
    "TikTok|status_code|https://www.tiktok.com/"
    "YouTube|status_code|https://www.youtube.com/"
)

# IP 获取源（按顺序尝试）
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

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
else
    C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_DIM=""
fi

# ------------------------------------------------------------
# 全局临时目录管理与优雅退出
# ------------------------------------------------------------
TMP_DIRS=()
cleanup_all() {
    local d
    for d in "${TMP_DIRS[@]}"; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done
    printf '\n  已退出\n'
    exit 0
}
trap cleanup_all INT TERM

new_tmp_dir() {
    local d
    d=$(mktemp -d)
    TMP_DIRS+=("$d")
    printf '%s' "$d"
}

# ------------------------------------------------------------
# 基础工具
# ------------------------------------------------------------
has_cmd() { command -v "$1" >/dev/null 2>&1; }

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

# ------------------------------------------------------------
# IP 获取与脱敏
# ------------------------------------------------------------
get_ipv4() {
    local url ip
    for url in "${IPV4_SOURCES[@]}"; do
        ip=$(curl -4 -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]')
        [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { printf '%s' "$ip"; return 0; }
    done
    return 1
}

get_ipv6() {
    local url ip
    for url in "${IPV6_SOURCES[@]}"; do
        ip=$(curl -6 -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]')
        [[ "$ip" == *:* && "$ip" != *" "* ]] && { printf '%s' "$ip"; return 0; }
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
        printf '%s' "$text" | sed -E 's/([0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}/\1.*.*/g'
    fi
}

# ------------------------------------------------------------
# 关于本项目
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

    printf '\n  %sMIT License%s\n' "$C_DIM" "$C_RESET"
    printf '\n'

    read -r -n 1 -s -p "  按任意键返回菜单..." _ || true
    printf '\n'
}

# ------------------------------------------------------------
# IP 类型检测
# ------------------------------------------------------------
ip_type_check() {
    result_header "IP 类型检测"

    local ip
    ip=$(get_ipv4 || true)

    if [[ -z "$ip" ]]; then
        item "检测状态" "$(status_text 失败)"
        item "错误信息" "未获取到公网 IPv4"
        result_footer; pause; return
    fi

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
    country=$(printf '%s' "$json" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
    region=$(printf '%s' "$json"  | sed -n 's/.*"regionName":"\([^"]*\)".*/\1/p')
    city=$(printf '%s' "$json"    | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
    isp=$(printf '%s' "$json"     | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
    org=$(printf '%s' "$json"     | sed -n 's/.*"org":"\([^"]*\)".*/\1/p')
    asn_line=$(printf '%s' "$json" | sed -n 's/.*"as":"\([^"]*\)".*/\1/p')
    asname=$(printf '%s' "$json"  | sed -n 's/.*"asname":"\([^"]*\)".*/\1/p')
    mobile=$(printf '%s' "$json"  | grep -o '"mobile":\(true\|false\)' | cut -d: -f2)
    proxy=$(printf '%s' "$json"   | grep -o '"proxy":\(true\|false\)' | cut -d: -f2)
    hosting=$(printf '%s' "$json" | grep -o '"hosting":\(true\|false\)' | cut -d: -f2)

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
    if [[ "$hosting" == "true" ]]; then
        net_type="IDC 机房"
    elif [[ "$proxy" == "true" ]]; then
        net_type="代理 / VPN"
    elif [[ "$mobile" == "true" ]]; then
        net_type="移动网络"
    else
        net_type="家庭宽带 / 企业专线"
    fi

    if [[ "$hosting" == "true" || "$proxy" == "true" ]]; then
        native_judge="可能为机房 / 代理 IP"
    elif [[ "$asname" =~ (Telecom|Unicom|Mobile|Chinanet|Broadband|Comcast|Verizon) ]]; then
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
# 三网延迟检测
# ------------------------------------------------------------
tri_ping_node() {
    local ip="$1"
    local output
    output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" 2>/dev/null || true)
    [[ -z "$output" ]] && { printf '超时'; return; }
    local avg
    avg=$(printf '%s\n' "$output" | grep -oE 'min/avg/max[^=]*= [^/]+/[^/]+' | head -n 1 | awk -F'/' '{print $5}')
    [[ -z "$avg" ]] && { printf '超时'; return; }
    printf '%.0f' "$avg"
}

tri_quality() {
    local ms="$1"
    [[ "$ms" == "超时" ]] && { printf '超时'; return; }
    local n
    n=$(awk "BEGIN{printf \"%.0f\", $ms}" 2>/dev/null || echo 0)
    if (( n < 50 )); then printf '优秀'
    elif (( n < 100 )); then printf '良好'
    elif (( n < 200 )); then printf '一般'
    elif (( n < 300 )); then printf '较差'
    else printf '极差'; fi
}

tri_net_ping() {
    result_header "三网延迟检测"

    has_cmd ping || { item "检测状态" "缺少 ping 命令"; result_footer; pause; return; }

    printf '  %-8s %-10s %8s %s\n' "运营商" "节点" "延迟" "质量"
    printf '  %s\n' "$(repeat_char '─' 40)"

    local tmp_dir; tmp_dir=$(new_tmp_dir)

    local i=0 node isp region ip
    for node in "${TRI_NET_NODES[@]}"; do
        IFS='|' read -r isp region ip <<< "$node"
        printf -v fname '%02d' "$i"
        (
            local ms q
            ms=$(tri_ping_node "$ip"); q=$(tri_quality "$ms")
            printf '%s|%s|%s|%s\n' "$isp" "$region" "$ms" "$q" > "$tmp_dir/$fname"
        ) &
        i=$((i + 1))
    done
    wait

    local last_isp=""
    for isp_want in "电信" "联通" "移动"; do
        for f in "$tmp_dir"/*; do
            [[ -f "$f" ]] || continue
            local fi fregion fms fq
            IFS='|' read -r fi fregion fms fq < "$f"
            [[ "$fi" != "$isp_want" ]] && continue
            local isp_disp="$fi"; [[ "$fi" == "$last_isp" ]] && isp_disp=""; last_isp="$fi"
            local ms_disp="${fms}ms"; [[ "$fms" == "超时" ]] && ms_disp="超时"
            printf '  %-8s %-10s %8s %s\n' \
                "$isp_disp" "$fregion" "$ms_disp" "$(status_text "$fq")"
        done
    done

    rm -rf "$tmp_dir"
    printf '  %s\n' "$(repeat_char '─' 40)"
    printf '\n'
    item "检测说明" "ICMP Ping，每节点 ${PING_COUNT} 次采样"
    result_footer; pause
}

# ------------------------------------------------------------
# 回程路由检测（traceroute + batch ASN + 特征段匹配）
# ------------------------------------------------------------
extract_hops() {
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}'
}

# 批量查询 IP 的 ASN 信息（ip-api.com/batch，一次最多 100 个 IP）
# 输入：IP 列表（参数）
# 输出：每行 "IP|ASN|ORG"
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
    response=$(curl -fsS --max-time 10 \
        -X POST -H "Content-Type: application/json" \
        -d "$json_array" \
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

# 查询单个 IP 的 ASN（从 map 文件中读取）
lookup_asn() {
    local ip="$1" map_file="$2"
    [[ -f "$map_file" ]] || { printf '?'; return; }
    local r
    r=$(grep "^${ip}|" "$map_file" 2>/dev/null | head -n1 | cut -d'|' -f2)
    printf '%s' "${r:-?}"
}

# 判断回程线路类型
# 参数：ASN map 文件路径，然后是该目标的 hops 数组
detect_line_type() {
    local map_file="$1"; shift
    local hops=("$@")

    (( ${#hops[@]} == 0 )) && { printf '不可达'; return; }

    local total=${#hops[@]}
    local first_5943_idx=-1
    local has_5943=0 has_9929=0 has_cmin2=0 has_cmi=0 has_163=0 has_4837=0
    local i=0 h

    for h in "${hops[@]}"; do
        case "$h" in
            59.43.*)  has_5943=1; [[ $first_5943_idx -eq -1 ]] && first_5943_idx=$i ;;
            218.105.*|210.51.*) has_9929=1 ;;
            221.183.*|211.136.*) has_cmin2=1 ;;
            120.196.*) has_cmi=1 ;;
            202.97.*)  has_163=1 ;;
            219.158.*) has_4837=1 ;;
        esac
        i=$((i + 1))
    done

    if (( has_5943 )); then
        # GIA：CN2 出现在前 1/3 段；GT：只在中后段
        local threshold=$((total / 3))
        if (( first_5943_idx >= 0 && first_5943_idx <= threshold )); then
            printf 'CN2 GIA (优化)'
        else
            printf 'CN2 GT (半优化)'
        fi
        return
    fi

    (( has_9929 ))  && { printf '联通 9929 (优化)'; return; }
    (( has_cmin2 )) && { printf '移动 CMIN2 (优化)'; return; }
    (( has_4837 ))  && { printf '联通 4837 (普通)'; return; }
    (( has_cmi ))   && { printf '移动 CMI (普通)'; return; }
    (( has_163 ))   && { printf '电信 163 (普通)'; return; }

    # 特征段无命中，降级到 ASN 查询
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

    printf '  %-6s %-6s %-16s %s\n' "运营商" "地区" "线路类型" "关键跳 IP"
    printf '  %s\n' "$(repeat_char '─' 52)"

    local tmp_dir; tmp_dir=$(new_tmp_dir)

    # 阶段 1：并行 traceroute，各自写文件
    local i=0 node isp region ip
    for node in "${TRI_NET_NODES[@]}"; do
        IFS='|' read -r isp region ip <<< "$node"
        printf -v fname '%02d' "$i"
        (
            if [[ "$trace_cmd" == "traceroute" ]]; then
                traceroute -n -m 15 -w 1 "$ip" > "$tmp_dir/trace_$fname" 2>&1
            else
                tracepath -m 15 "$ip" > "$tmp_dir/trace_$fname" 2>&1
            fi
        ) &
        i=$((i + 1))
    done
    wait

    # 阶段 2：收集所有 IP，去重
    local all_hops=()
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

    # 阶段 3：一次 batch 查询 ASN（去重后通常 < 100 个）
    local asn_map="$tmp_dir/asn_map"
    : > "$asn_map"
    if (( ${#unique_hops[@]} > 0 && ${#unique_hops[@]} <= 100 )); then
        batch_asn_lookup "${unique_hops[@]}" > "$asn_map" 2>/dev/null || true
    fi

    # 阶段 4：逐目标判断线路
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

        local line_type key_ip="—"
        line_type=$(detect_line_type "$asn_map" "${hops_arr[@]}")

        # 取最后一个特征段 IP 作为关键跳
        local h
        for h in "${hops_arr[@]}"; do
            case "$h" in
                59.43.*|218.105.*|210.51.*|219.158.*|221.183.*|211.136.*|120.196.*|202.97.*)
                    key_ip="$h" ;;
            esac
        done

        local disp_type="$line_type"
        if [[ "$line_type" == *"优化"* ]]; then
            disp_type="${C_GREEN}${line_type}${C_RESET}"
        elif [[ "$line_type" == *"普通"* ]]; then
            disp_type="${C_YELLOW}${line_type}${C_RESET}"
        fi

        printf '  %-6s %-6s %-16b %s\n' \
            "$isp" "$region" "$disp_type" "$(mask_ip "$key_ip")"

        i=$((i + 1))
    done

    rm -rf "$tmp_dir"
    printf '  %s\n' "$(repeat_char '─' 52)"
    printf '\n'
    item "检测说明" "traceroute 路径 + 特征段匹配 + ASN"
    item "线路参考" "59.43=CN2 / 218.105=9929 / 221.183=CMIN2"
    result_footer; pause
}

# ------------------------------------------------------------
# AI 服务检测
# ------------------------------------------------------------
ai_check_all() {
    result_header "AI 服务检测（入口可达性）"

    printf '  %-14s %-10s %s\n' "服务" "状态" "说明"
    line

    local tmp_dir; tmp_dir=$(new_tmp_dir)

    local i=0 svc name dtype url
    for svc in "${AI_SERVICES[@]}"; do
        IFS='|' read -r name dtype url <<< "$svc"
        printf -v fname '%02d' "$i"
        (
            local state="不可达" note=""
            local code
            code=$(curl -L -sS -o /dev/null \
                --connect-timeout 4 --max-time 10 \
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                -w '%{http_code}' "$url" 2>/dev/null || true)

            case "$code" in
                200|401) state="可达" ;;
                403) state="受限"; note="地区限制" ;;
                000) state="不可达"; note="连接失败" ;;
                *) state="可达"; note="HTTP $code" ;;
            esac

            printf '%s|%s|%s\n' "$name" "$state" "$note" > "$tmp_dir/$fname"
        ) &
        i=$((i + 1))
    done
    wait

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
# 流媒体检测
# ------------------------------------------------------------
streaming_check_all() {
    result_header "流媒体检测（入口可达性）"

    printf '  %-16s %-10s %s\n' "平台" "状态" "说明"
    line

    local tmp_dir; tmp_dir=$(new_tmp_dir)

    local i=0 svc name dtype url
    for svc in "${STREAMING_SERVICES[@]}"; do
        IFS='|' read -r name dtype url <<< "$svc"
        printf -v fname '%02d' "$i"
        (
            local state="不可达" note=""
            local code
            code=$(curl -L -sS -o /dev/null \
                --connect-timeout 4 --max-time 10 \
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                -w '%{http_code}' "$url" 2>/dev/null || true)

            case "$code" in
                200) state="入口可达" ;;
                403) state="受限"; note="地区限制" ;;
                000) state="不可达"; note="连接失败" ;;
                *) state="入口可达"; note="HTTP $code" ;;
            esac

            printf '%s|%s|%s\n' "$name" "$state" "$note" > "$tmp_dir/$fname"
        ) &
        i=$((i + 1))
    done
    wait

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
# 网络检测模块
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

    local country city conn_isp conn_org conn_asn tz
    country=$(printf '%s' "$data" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
    city=$(printf '%s' "$data"    | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
    conn_isp=$(printf '%s' "$data" | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
    conn_org=$(printf '%s' "$data" | sed -n 's/.*"org":"\([^"]*\)".*/\1/p')
    conn_asn=$(printf '%s' "$data" | sed -n 's/.*"asn":"\?\([^",]*\)"\?.*/\1/p')
    tz=$(printf '%s' "$data"       | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')

    item "国家 / 地区" "${country:-未知}"
    item "城市" "${city:-未知}"
    item "运营商" "${conn_isp:-未知}"
    item "组织" "${conn_org:-未知}"
    item "ASN" "${conn_asn:-未知}"
    item "时区" "${tz:-未知}"
    result_footer; pause
}

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
        awk '/^[[:space:]]*nameserver[[:space:]]+/ { printf "    %-16s %s\n", "DNS", $2 }' /etc/resolv.conf
    else
        printf '    无法读取 /etc/resolv.conf\n'
    fi
    result_footer; pause
}

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
    if has_cmd getent; then
        local result
        result=$(getent ahosts "$domain" 2>/dev/null | awk '!seen[$1]++ {print $1}' || true)
        if [[ -n "$result" ]]; then
            printf '\n  解析结果\n'
            while IFS= read -r addr; do item "地址" "$(mask_ip "$addr")"; done <<< "$result"
            item "检测状态" "$(status_text 正常)"
        else
            item "检测状态" "$(status_text 失败)"
        fi
    else
        item "检测状态" "缺少 getent 命令"
    fi
    result_footer; pause
}

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
        local mem; mem=$(free -h 2>/dev/null | awk '/^Mem:/ { printf "%s / %s", $3, $2 }')
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

http_code() {
    local url="$1"
    has_cmd curl || { printf '000'; return; }
    curl -L -sS -o /dev/null --connect-timeout 4 --max-time 8 \
        -H "User-Agent: Mozilla/5.0" -w '%{http_code}' "$url" 2>/dev/null || true
}

website_check() {
    result_header "网站连通性检测"
    local url
    read -r -p "  输入网址 > " url
    [[ -z "$url" ]] && { item "检测状态" "$(status_text 失败)"; result_footer; pause; return; }
    [[ "$url" =~ ^https?:// ]] || url="https://${url}"
    item "目标网址" "$url"
    local start end code
    start=$(date +%s); code=$(http_code "$url"); end=$(date +%s)
    item "HTTP 状态码" "$code"
    item "响应耗时" "$((end - start)) s"
    [[ "$code" != "000" ]] && item "连接状态" "$(status_text 正常)" || item "连接状态" "$(status_text 异常)"
    result_footer; pause
}

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
        rtt=$(printf '%s\n' "$output" | grep -oE 'min/avg/max[^=]*= [^ ]+' | tail -n 1 || true)
        item "丢包率" "${loss:-未知}"
        item "延迟统计" "${rtt:-未知}"
        printf '\n  检测详情\n'
        while IFS= read -r row; do [[ -n "$row" ]] && printf '    %s\n' "$row"; done <<< "$output"
        result_footer
        local rc; pause; rc=$?
        (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
        (( rc == 1 )) && continue
        break
    done
}

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
        if timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" >/dev/null 2>&1; then
            item "连接状态" "$(status_text 正常)"
        else
            item "连接状态" "$(status_text 异常)"
        fi
    else
        item "检测状态" "需要 timeout 命令"
    fi
    result_footer; pause
}

mtu_check() {
    result_header "MTU 排查"
    has_cmd ping || { item "检测状态" "缺少 ping 命令"; result_footer; pause; return; }
    local target="1.1.1.1"
    while true; do
        item "检测目标" "$(mask_ip "$target")"
        if ! ping -c 1 -W 2 -M do -s 1472 "$target" >/dev/null 2>&1; then
            item "MTU 1500" "$(status_text 警告)"
            item "说明" "大包探测失败，开始降低探测尺寸"
        else
            item "MTU 1500" "$(status_text 正常)"
            item "说明" "1472 字节载荷探测成功"
            result_footer
            local rc; pause; rc=$?
            (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
            (( rc == 1 )) && continue
            break
        fi
        local size=1400 found=0
        while (( size >= 500 )); do
            if ping -c 1 -W 2 -M do -s "$size" "$target" >/dev/null 2>&1; then
                found=$((size + 28)); break
            fi
            size=$((size - 100))
        done
        (( found > 0 )) && item "探测结果" "至少支持 MTU ${found}" || item "探测结果" "未找到可用尺寸"
        item "注意" "结果受防火墙和 ICMP 策略影响"
        result_footer
        local rc; pause; rc=$?
        (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
        (( rc == 1 )) && continue
        break
    done
}

route_trace() {
    result_header "路由追踪"
    local target="1.1.1.1"
    has_cmd traceroute || has_cmd tracepath || { item "检测状态" "未安装 traceroute"; result_footer; pause; return; }
    while true; do
        item "目标地址" "$(mask_ip "$target")"
        printf '\n  路由结果\n'
        if has_cmd traceroute; then
            traceroute -n -m 15 -w 1 "$target" 2>&1 | ([[ "$HIDE_IP" == 1 ]] && mask_text || cat) |
                while IFS= read -r row; do printf '    %s\n' "$row"; done
        else
            tracepath -m 15 "$target" 2>&1 | ([[ "$HIDE_IP" == 1 ]] && mask_text || cat) |
                while IFS= read -r row; do printf '    %s\n' "$row"; done
        fi
        result_footer
        local rc; pause; rc=$?
        (( rc == 2 )) && { read -r -p "  新目标 > " target; target=${target:-1.1.1.1}; continue; }
        (( rc == 1 )) && continue
        break
    done
}

full_check() {
    result_header "全面检测"
    local total=7 ok=0 fail=0 unavailable=0
    local ip4 ip6 code

    printf '  %-22s %-12s %s\n' "检测项目" "状态" "结果"
    line

    # IPv4 / IPv6 并行获取
    local tmp_dir; tmp_dir=$(new_tmp_dir)
    ( get_ipv4 > "$tmp_dir/ip4" 2>/dev/null ) &
    ( get_ipv6 > "$tmp_dir/ip6" 2>/dev/null ) &
    wait
    ip4=$(cat "$tmp_dir/ip4" 2>/dev/null || true)
    ip6=$(cat "$tmp_dir/ip6" 2>/dev/null || true)
    rm -rf "$tmp_dir"

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

    code=$(http_code "https://www.google.com/")
    if [[ "$code" != "000" ]]; then
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

    code=$(http_code "https://chatgpt.com/api/auth/session")
    if [[ "$code" != "000" ]]; then
        printf '  %-22s %-12s HTTP %s\n' "ChatGPT 可达" "$(status_text 正常)" "$code"
        ok=$((ok + 1))
    else
        printf '  %-22s %-12s %s\n' "ChatGPT 可达" "$(status_text 异常)" "连接失败"
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
    box_text "  08  网络质量检测"
    box_text "  09  TCP 端口连通性检测"
    box_text "  10  MTU 排查"
    box_text "  11  路由追踪"
    box_text ""
    box_text "${C_CYAN}回程与三网${C_RESET}"
    box_text ""
    box_text "  12  三网回程路由检测"
    box_text "  13  三网延迟检测"
    box_text ""
    box_text "${C_CYAN}应用检测${C_RESET}"
    box_text ""
    box_text "  14  AI 服务检测"
    box_text "  15  流媒体检测"
    box_text "  16  网站连通性检测"
    box_text ""
    box_text "${C_CYAN}系统与帮助${C_RESET}"
    box_text ""
    box_text "  17  系统信息"
    box_text "  18  关于本项目"
    box_text ""
    mid_border
    box_text "${C_CYAN}隐私保护${C_RESET}"
    if [[ "$HIDE_IP" == 1 ]]; then
        box_text "  隐藏 IP 模式    ${C_GREEN}[已开启]${C_RESET}"
    else
        box_text "  隐藏 IP 模式    ${C_YELLOW}[已关闭]${C_RESET}"
    fi
    box_text "  19  切换隐藏 IP 模式"
    mid_border
    box_text ""
    box_text "  请输入选项  [01-19 / 00 退出]"
    bottom_border
    printf '\n'
    if ! read -r -p "  > " choice; then
        printf '\n  已退出\n'
        exit 0
    fi

    # 剥离前导零
    choice="${choice#0}"; choice="${choice#0}"

    case "$choice" in
        1)  retry_loop full_check ;;
        2)  retry_loop ipv4_check ;;
        3)  retry_loop ipv6_check ;;
        4)  retry_loop ip_info ;;
        5)  retry_loop ip_type_check ;;
        6)  retry_loop network_config ;;
        7)  retry_loop dns_check ;;
        8)  retry_loop network_quality ;;
        9)  retry_loop tcp_check ;;
        10) retry_loop mtu_check ;;
        11) retry_loop route_trace ;;
        12) retry_loop backtrace_check ;;
        13) retry_loop tri_net_ping ;;
        14) retry_loop ai_check_all ;;
        15) retry_loop streaming_check_all ;;
        16) retry_loop website_check ;;
        17) retry_loop system_info ;;
        18) about ;;
        19) toggle_hide_ip ;;
        ""|q|Q|exit)
            printf '\n  感谢使用 %s\n' "VPS 网络检测工具"
            exit 0 ;;
        *)
            printf '\n  %s无效选项，请重新输入。%s\n' "$C_YELLOW" "$C_RESET"
            sleep 1 ;;
    esac
}

# ------------------------------------------------------------
# 参数处理 & 程序入口
# ------------------------------------------------------------
case "${1:-}" in
    -v|--version) printf 'v%s\n' "$VERSION"; exit 0 ;;
    -h|--help)
        cat <<EOF
NYKI / VPS NETWORK CHECK v${VERSION}

用法:
  bash <(curl -fsSL ${RAW_URL}) [选项]

选项:
  -h, --help     显示帮助
  -v, --version  显示版本
  --no-mask      关闭 IP 隐藏（等同于菜单 19）
EOF
        exit 0 ;;
    --no-mask) HIDE_IP=0 ;;
esac

if [[ -z "${NYC_SOURCED:-}" ]]; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        check_deps
        while true; do menu; done
    fi
fi
