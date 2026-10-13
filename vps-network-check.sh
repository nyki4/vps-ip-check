#!/usr/bin/env bash
# ============================================================
# NYKI / VPS NETWORK CHECK
# VPS 网络检测工具
# 作者：阿晚
# 主页：https://nyki.cc
# 项目：https://github.com/nyki4/vps-network-check
# 版本：v2.4.0
# ============================================================
VERSION="2.4.0"
AUTHOR="阿晚"
HOMEPAGE="https://nyki.cc"
PROJECT="https://github.com/nyki4/vps-network-check"
RAW_URL="https://raw.githubusercontent.com/nyki4/vps-network-check/main/vps-network-check.sh"

# 隐私模式：默认开启
HIDE_IP=1
# 三网检测默认节点数（每个运营商）
PING_COUNT=4
PING_TIMEOUT=3

# 终端颜色
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_CYAN=$'\033[36m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
else
    C_RESET=""
    C_CYAN=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_BOLD=""
    C_DIM=""
fi

# Ctrl+C 优雅退出
trap 'printf "\n  已退出\n"; exit 0' INT

# ------------------------------------------------------------
# 基础工具
# ------------------------------------------------------------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# pause 返回码：
#   0 -> 返回菜单
#   1 -> 重新检测
pause() {
    local key=""
    printf '\n'
    printf '  %s[R]%s 重新检测    %s[Enter]%s 返回菜单\n' \
        "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
    if ! IFS= read -r -n 1 -s key; then
        printf '\n'
        return 0
    fi
    printf '\n'
    # 清空 stdin 残留字节（粘贴/方向键）
    while IFS= read -r -t 0.02 -n 1 _drain; do :; done
    [[ "$key" == "r" || "$key" == "R" ]] && return 1
    return 0
}

# 循环调用某个检测函数：返回 0 退出到菜单，返回 1 重新执行
retry_loop() {
    local fn="$1"
    while ! "$fn"; do :; done
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
    local char="$1"
    local count="$2"
    local result=""
    (( count < 0 )) && count=0
    printf -v result '%*s' "$count" ''
    result=${result// /"$char"}
    printf '%s' "$result"
}

# 统一边框宽度（全局只初始化一次）
BOX_WIDTH=60
init_layout() {
    local width
    width=$(get_width)
    (( width < 60 )) && BOX_WIDTH=$((width - 2))
    (( width >= 60 )) && BOX_WIDTH=60
    (( BOX_WIDTH < 40 )) && BOX_WIDTH=40
}

line() {
    printf '%s\n' "${C_DIM}$(repeat_char '─' "$BOX_WIDTH")${C_RESET}"
}
top_border() {
    printf '┌%s┐\n' "$(repeat_char '─' "$BOX_WIDTH")"
}
mid_border() {
    printf '├%s┤\n' "$(repeat_char '─' "$BOX_WIDTH")"
}
bottom_border() {
    printf '└%s┘\n' "$(repeat_char '─' "$BOX_WIDTH")"
}
box_text() {
    printf '│  %s\n' "$1"
}

# ------------------------------------------------------------
# 统一结果显示
# ------------------------------------------------------------
result_header() {
    local title="$1"
    clear 2>/dev/null || true
    top_border
    box_text "${C_CYAN}${C_BOLD}${title}${C_RESET}"
    mid_border
}

result_footer() {
    mid_border
    box_text "${C_DIM}检测完成${C_RESET}"
    bottom_border
}

item() {
    local label="$1"
    local value="$2"
    printf '  %-16s %s\n' "$label" "$value"
}

status_text() {
    case "$1" in
        正常|成功|开启|可用|已连接|可访问|优秀|良好|极快)
            printf '%s%s%s' "$C_GREEN" "$1" "$C_RESET"
            ;;
        异常|失败|关闭|不可用|超时|丢包|极差)
            printf '%s%s%s' "$C_RED" "$1" "$C_RESET"
            ;;
        警告|未知|未配置|未检测|一般|较差|缓慢)
            printf '%s%s%s' "$C_YELLOW" "$1" "$C_RESET"
            ;;
        *)
            printf '%s' "$1"
            ;;
    esac
}

# ------------------------------------------------------------
# IP 获取与隐藏
# ------------------------------------------------------------
get_ipv4() {
    local ip=""
    if has_cmd curl; then
        ip=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            printf '%s' "$ip"; return
        fi
    fi
    if has_cmd wget; then
        ip=$(wget -4 -qO- --timeout=5 https://api.ipify.org 2>/dev/null || true)
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            printf '%s' "$ip"; return
        fi
    fi
    return 1
}

get_ipv6() {
    local ip=""
    if has_cmd curl; then
        ip=$(curl -6 -fsS --max-time 5 https://api6.ipify.org 2>/dev/null || true)
        if [[ "$ip" == *:* ]]; then printf '%s' "$ip"; return; fi
    fi
    if has_cmd wget; then
        ip=$(wget -6 -qO- --timeout=5 https://api6.ipify.org 2>/dev/null || true)
        if [[ "$ip" == *:* ]]; then printf '%s' "$ip"; return; fi
    fi
    return 1
}

mask_ip() {
    local ip="$1"
    if [[ "$HIDE_IP" != 1 ]]; then printf '%s' "$ip"; return; fi
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local a b c d
        IFS='.' read -r a b c d <<< "$ip"
        printf '%s.%s.*.*' "$a" "$b"; return
    fi
    if [[ "$ip" == *:* ]]; then
        local part1 part2
        IFS=':' read -r part1 part2 _ <<< "$ip"
        printf '%s:%s:****:****' "${part1:-?}" "${part2:-?}"
        return
    fi
    printf '%s' "$ip"
}

mask_text() {
    local text="$1"
    if [[ "$HIDE_IP" != 1 ]]; then printf '%s' "$text"; return; fi
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
# 收紧 IPv6 正则：至少3段，且前后有边界
s = re.sub(
    r"(?i)(?<![0-9a-f:])"
    r"(?:[0-9a-f]{1,4}:){2,7}(?:[0-9a-f]{1,4}|:)"
    r"(?![0-9a-f:])",
    lambda m: m.group(0).split(":")[0] + ":****:****:****",
    s
)
sys.stdout.write(s)
'
    else
        # 降级：简单文本替换（可能误伤，但比泄漏强）
        printf '%s' "$text" | sed -E 's/([0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}\.[0-9]{1,3}/\1.*.*/g'
    fi
}

# ------------------------------------------------------------
# 三网检测模块
# ------------------------------------------------------------
# 公开三网测试节点（来源：公开DNS/公共节点，定期更新）
# 格式：运营商|地区|IP|说明
TRI_NET_NODES=(
    "电信|北京|219.141.136.10|北京电信"
    "电信|上海|202.96.209.133|上海电信"
    "电信|广州|58.60.188.222|广州电信163"
    "联通|北京|123.125.99.1|北京联通"
    "联通|上海|210.22.70.3|上海联通"
    "联通|广州|210.21.196.6|广州联通"
    "移动|北京|211.136.25.153|北京移动"
    "移动|上海|211.136.112.50|上海移动"
    "移动|广州|120.196.165.24|广州移动CMI"
)

# 单个节点 ping 检测
# 返回：延迟值(ms) 或 "超时"
tri_ping_node() {
    local ip="$1"
    local output
    output=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" 2>/dev/null || true)
    if [[ -z "$output" ]]; then printf '超时'; return; fi
    local avg
    avg=$(printf '%s\n' "$output" | grep -oE 'min/avg/max[^=]*= [^/]+/[^/]+' | head -n 1 | awk -F'/' '{print $5}')
    if [[ -z "$avg" ]]; then printf '超时'; return; fi
    printf '%.0f' "$avg"
}

# 根据延迟值返回质量等级
tri_quality() {
    local ms="$1"
    if [[ "$ms" == "超时" ]]; then printf '超时'; return; fi
    if (( $(echo "$ms < 50" | bc -l 2>/dev/null || echo 0) )); then printf '优秀'
    elif (( $(echo "$ms < 100" | bc -l 2>/dev/null || echo 0) )); then printf '良好'
    elif (( $(echo "$ms < 200" | bc -l 2>/dev/null || echo 0) )); then printf '一般'
    elif (( $(echo "$ms < 300" | bc -l 2>/dev/null || echo 0) )); then printf '较差'
    else printf '极差'; fi
}

# 三网延迟检测（主函数）
tri_net_ping() {
    result_header "三网延迟检测"

    if ! has_cmd ping; then
        item "检测状态" "缺少 ping 命令"
        result_footer
        pause
        return
    fi

    printf '  %-10s %-14s %-10s %-10s %s\n' "运营商" "节点" "延迟" "质量" "IP"
    line

    local current_isp=""
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    # 并行发起所有 ping
    local i=0
    local isp region ip desc
    for node in "${TRI_NET_NODES[@]}"; do
        IFS='|' read -r isp region ip desc <<< "$node"
        (
            local ms
            ms=$(tri_ping_node "$ip")
            local q
            q=$(tri_quality "$ms")
            printf '%s|%s|%s|%s|%s\n' "$isp" "$region" "$ip" "$ms" "$q" > "$tmp_dir/$i"
        ) &
        i=$((i + 1))
    done
    wait

    # 按运营商分组输出
    for isp_want in "电信" "联通" "移动"; do
        local first=1
        for f in "$tmp_dir"/*; do
            [[ -f "$f" ]] || continue
            local fi fo
            IFS='|' read -r fi fo rip rms rq < "$f"
            [[ "$fi" != "$isp_want" ]] && continue
            if (( first )); then
                printf '  %s%s%s\n' "$C_BOLD" "$isp_want" "$C_RESET"
                first=0
            fi
            local ms_disp="${rms}ms"
            [[ "$rms" == "超时" ]] && ms_disp="超时"
            printf '  %-10s %-14s %-10s %-10s %s\n' \
                "" "$fo" "$ms_disp" "$(status_text "$rq")" "$(mask_ip "$rip")"
        done
    done
    rm -rf "$tmp_dir"
    trap - RETURN

    printf '\n'
    item "检测说明" "基于 ICMP Ping，${PING_COUNT} 次采样"
    item "质量评级" "<50ms优秀 <100ms良好 <200ms一般"
    result_footer
    pause
}

# 三网节点自定义检测
tri_net_custom() {
    result_header "三网自定义节点检测"
    local target
    read -r -p "  输入目标 IP 或域名 > " target
    if [[ -z "$target" ]]; then
        item "检测状态" "$(status_text 失败)"
        result_footer
        pause
        return
    fi

    item "检测目标" "$(mask_ip "$target")"
    printf '\n  检测详情\n'

    if ! has_cmd ping; then
        item "检测状态" "缺少 ping 命令"
        result_footer
        pause
        return
    fi

    local output
    output=$(ping -c 4 -W 3 "$target" 2>&1 || true)
    if [[ "$HIDE_IP" == 1 ]]; then output=$(mask_text "$output"); fi

    local loss rtt
    loss=$(printf '%s\n' "$output" | grep -oE '[0-9.]+% packet loss' | tail -n 1 || true)
    rtt=$(printf '%s\n' "$output" | grep -oE 'min/avg/max[^=]*= [^ ]+' | tail -n 1 || true)

    item "丢包率" "${loss:-未知}"
    item "延迟统计" "${rtt:-未知}"

    printf '\n  原始输出\n'
    while IFS= read -r row; do
        [[ -n "$row" ]] && printf '    %s\n' "$row"
    done <<< "$output"

    result_footer
    pause
}

# ------------------------------------------------------------
# 网络检测模块（保持原有功能）
# ------------------------------------------------------------
ipv4_check() {
    result_header "IPv4 地址检测"
    local ip
    if ip=$(get_ipv4); then
        item "公网 IPv4" "$(mask_ip "$ip")"
        item "地址类型" "IPv4"
        item "检测状态" "$(status_text 正常)"
    else
        item "公网 IPv4" "未获取"
        item "检测状态" "$(status_text 异常)"
    fi
    result_footer
    pause
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
    result_footer
    pause
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
    if [[ -z "$ip" ]]; then
        item "查询结果" "$(status_text 未获取)"
        result_footer
        pause
        return
    fi
    item "查询地址" "$(mask_ip "$ip")"
    if ! has_cmd curl; then
        item "查询状态" "缺少 curl"
        result_footer
        pause
        return
    fi
    local data
    data=$(curl -fsS --max-time 8 "https://ipwho.is/${ip}" 2>/dev/null || true)
    if [[ -z "$data" ]]; then
        item "查询状态" "$(status_text 失败)"
        result_footer
        pause
        return
    fi
    if has_cmd python3; then
        printf '%s' "$data" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    if not d.get("success", True):
        print("查询失败"); sys.exit(0)
    conn=d.get("connection") or {}
    for k,v in [
        ("国家 / 地区",d.get("country")),
        ("城市",d.get("city")),
        ("运营商",conn.get("isp")),
        ("组织",conn.get("org")),
        ("ASN",conn.get("asn")),
        ("时区",(d.get("timezone") or {}).get("id"))
    ]:
        print("  %-16s %s" % (k, v or "未知"))
except Exception:
    print("  查询状态       数据解析失败")
'
    else
        item "查询状态" "缺少 Python 3，无法解析数据"
    fi
    result_footer
    pause
}

network_config() {
    result_header "本机网络配置"
    if has_cmd ip; then
        item "主机名" "$(hostname 2>/dev/null || echo 未知)"
        printf '\n  网络接口\n'
        ip -o link show 2>/dev/null | while IFS= read -r row; do
            printf '    %s\n' "$row"
        done
        printf '\n  IP 地址\n'
        local addresses
        addresses=$(ip -o addr show 2>/dev/null || true)
        if [[ "$HIDE_IP" == 1 ]]; then addresses=$(mask_text "$addresses"); fi
        while IFS= read -r row; do
            [[ -n "$row" ]] && printf '    %s\n' "$row"
        done <<< "$addresses"
        printf '\n  默认路由\n'
        local routes
        routes=$(ip route show default 2>/dev/null || true)
        if [[ "$HIDE_IP" == 1 ]]; then routes=$(mask_text "$routes"); fi
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
        awk '/^[[:space:]]*nameserver[[:space:]]+/ {
            printf "    %-16s %s\n", "DNS", $2
        }' /etc/resolv.conf
    else
        printf '    无法读取 /etc/resolv.conf\n'
    fi
    result_footer
    pause
}

dns_check() {
    result_header "DNS 解析检测"
    local domain
    read -r -p "  输入域名 > " domain
    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        item "检测状态" "$(status_text 失败)"
        item "错误信息" "域名格式无效"
        result_footer
        pause
        return
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
    elif has_cmd nslookup; then
        nslookup "$domain" 2>&1 | while IFS= read -r row; do printf '    %s\n' "$row"; done
    else
        item "检测状态" "缺少 DNS 查询工具"
    fi
    result_footer
    pause
}

system_info() {
    result_header "系统信息"
    item "主机名" "$(hostname 2>/dev/null || echo 未知)"
    item "系统内核" "$(uname -sr 2>/dev/null || echo 未知)"
    if [[ -r /etc/os-release ]]; then
        local os_name
        os_name=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-未知}")
        item "操作系统" "$os_name"
    fi
    item "运行时间" "$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo 未知)"
    item "CPU 架构" "$(uname -m 2>/dev/null || echo 未知)"
    if has_cmd nproc; then item "CPU 线程" "$(nproc 2>/dev/null)"; fi
    if has_cmd free; then
        local mem
        mem=$(free -h 2>/dev/null | awk '/^Mem:/ { printf "%s / %s", $3, $2 }')
        item "内存使用" "${mem:-未知}"
    fi
    if has_cmd df; then
        local disk
        disk=$(df -h / 2>/dev/null | awk 'NR==2 { printf "%s / %s (%s)", $3, $2, $5 }')
        item "系统磁盘" "${disk:-未知}"
    fi
    if has_cmd systemd-detect-virt; then
        item "虚拟化" "$(systemd-detect-virt 2>/dev/null || echo 未知)"
    fi
    # 容器内存限制
    if [[ -r /sys/fs/cgroup/memory.max ]]; then
        local limit
        limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null)
        [[ "$limit" != "max" && -n "$limit" ]] && \
            item "容器内存限制" "$(numfmt --to=iec "$limit" 2>/dev/null || echo "$limit")"
    fi
    result_footer
    pause
}

http_code() {
    local url="$1"
    if has_cmd curl; then
        curl -L -sS -o /dev/null --connect-timeout 4 --max-time 8 \
            -w '%{http_code}' "$url" 2>/dev/null || true
    elif has_cmd wget; then
        wget -q --spider --timeout=8 "$url" >/dev/null 2>&1
        [[ $? -eq 0 ]] && printf '200' || printf '000'
    else
        printf '000'
    fi
}

website_check() {
    result_header "网站连通性检测"
    local url
    read -r -p "  输入网址 > " url
    if [[ -z "$url" ]]; then
        item "检测状态" "$(status_text 失败)"
        result_footer; pause; return
    fi
    [[ "$url" =~ ^https?:// ]] || url="https://${url}"
    item "目标网址" "$url"
    local start end code
    start=$(date +%s)
    code=$(http_code "$url")
    end=$(date +%s)
    item "HTTP 状态码" "$code"
    item "响应耗时" "$((end - start)) s"
    if [[ "$code" != "000" ]]; then
        item "连接状态" "$(status_text 正常)"
    else
        item "连接状态" "$(status_text 异常)"
    fi
    result_footer
    pause
}

streaming_check() {
    result_header "流媒体检测"
    printf '  %-24s %-12s %s\n' "检测站点" "HTTP 状态" "连通性"
    line

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    local i=0
    while IFS='|' read -r name url; do
        [[ -z "$name" ]] && continue
        (
            local code
            code=$(http_code "$url")
            printf '%s|%s\n' "$name" "$code" > "$tmp_dir/$i"
        ) &
        i=$((i + 1))
    done <<'EOF'
Netflix|https://www.netflix.com/
YouTube|https://www.youtube.com/
Disney+|https://www.disneyplus.com/
Prime Video|https://www.primevideo.com/
ChatGPT|https://chatgpt.com/
EOF
    wait

    for f in "$tmp_dir"/*; do
        [[ -f "$f" ]] || continue
        local name code
        IFS='|' read -r name code < "$f"
        local state="异常"
        [[ "$code" != "000" ]] && state="可访问"
        printf '  %-24s %-12s %s\n' "$name" "$code" "$(status_text "$state")"
    done
    rm -rf "$tmp_dir"
    trap - RETURN

    printf '\n'
    item "检测说明" "仅代表网站 HTTP 可访问性"
    item "区域解锁" "需进一步验证，不以此结果判定"
    result_footer
    pause
}

network_quality() {
    result_header "网络质量检测"
    local target
    read -r -p "  检测目标 [默认 1.1.1.1] > " target
    target=${target:-1.1.1.1}
    item "检测目标" "$(mask_ip "$target")"
    if ! has_cmd ping; then
        item "检测状态" "缺少 ping 命令"
        result_footer; pause; return
    fi
    local output
    output=$(ping -c 4 -W 2 "$target" 2>&1 || true)
    if [[ "$HIDE_IP" == 1 ]]; then output=$(mask_text "$output"); fi
    local loss rtt
    loss=$(printf '%s\n' "$output" | grep -oE '[0-9.]+% packet loss' | tail -n 1 || true)
    rtt=$(printf '%s\n' "$output" | grep -oE 'min/avg/max[^=]*= [^ ]+' | tail -n 1 || true)
    item "丢包率" "${loss:-未知}"
    item "延迟统计" "${rtt:-未知}"
    printf '\n  检测详情\n'
    while IFS= read -r row; do
        [[ -n "$row" ]] && printf '    %s\n' "$row"
    done <<< "$output"
    result_footer
    pause
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
    elif has_cmd nc; then
        if nc -z -w 5 "$host" "$port" >/dev/null 2>&1; then
            item "连接状态" "$(status_text 正常)"
        else
            item "连接状态" "$(status_text 异常)"
        fi
    else
        item "检测状态" "需要 timeout 或 nc"
    fi
    result_footer
    pause
}

mtu_check() {
    result_header "MTU 排查"
    if ! has_cmd ping; then
        item "检测状态" "缺少 ping 命令"
        result_footer; pause; return
    fi
    local target
    read -r -p "  检测目标 [默认 1.1.1.1] > " target
    target=${target:-1.1.1.1}
    item "检测目标" "$(mask_ip "$target")"
    if ! ping -c 1 -W 2 -M do -s 1472 "$target" >/dev/null 2>&1; then
        item "MTU 1500" "$(status_text 警告)"
        item "说明" "大包探测失败，开始降低探测尺寸"
    else
        item "MTU 1500" "$(status_text 正常)"
        item "说明" "1472 字节载荷探测成功"
        result_footer; pause; return
    fi
    local size=1400 found=0
    while (( size >= 500 )); do
        if ping -c 1 -W 2 -M do -s "$size" "$target" >/dev/null 2>&1; then
            found=$((size + 28)); break
        fi
        size=$((size - 100))
    done
    if (( found > 0 )); then
        item "探测结果" "至少支持 MTU ${found}"
    else
        item "探测结果" "未找到可用尺寸"
    fi
    item "注意" "结果受防火墙和 ICMP 策略影响"
    result_footer
    pause
}

route_trace() {
    result_header "网络诊断与路由追踪"
    local target
    read -r -p "  追踪目标 [默认 1.1.1.1] > " target
    target=${target:-1.1.1.1}
    item "目标地址" "$(mask_ip "$target")"
    printf '\n  路由结果\n'
    if has_cmd traceroute; then
        if [[ "$HIDE_IP" == 1 ]]; then
            traceroute -n -m 12 -w 1 "$target" 2>&1 | mask_text |
                while IFS= read -r row; do printf '    %s\n' "$row"; done
        else
            traceroute -n -m 12 -w 1 "$target" 2>&1 |
                while IFS= read -r row; do printf '    %s\n' "$row"; done
        fi
    elif has_cmd tracepath; then
        if [[ "$HIDE_IP" == 1 ]]; then
            tracepath -m 12 "$target" 2>&1 | mask_text |
                while IFS= read -r row; do printf '    %s\n' "$row"; done
        else
            tracepath -m 12 "$target" 2>&1 |
                while IFS= read -r row; do printf '    %s\n' "$row"; done
        fi
    else
        item "检测状态" "未安装 traceroute / tracepath"
    fi
    result_footer
    pause
}

full_check() {
    result_header "全面检测"
    local total=6 ok=0 fail=0 unavailable=0
    local ip4 ip6 code
    printf '  %-26s %-12s %s\n' "检测项目" "状态" "结果"
    line

    ip4=$(get_ipv4 || true)
    if [[ -n "$ip4" ]]; then
        printf '  %-26s %-12s %s\n' "公网 IPv4" "$(status_text 正常)" "$(mask_ip "$ip4")"
        ok=$((ok + 1))
    else
        printf '  %-26s %-12s %s\n' "公网 IPv4" "$(status_text 异常)" "未获取"
        fail=$((fail + 1))
    fi

    ip6=$(get_ipv6 || true)
    if [[ -n "$ip6" ]]; then
        printf '  %-26s %-12s %s\n' "公网 IPv6" "$(status_text 正常)" "$(mask_ip "$ip6")"
        ok=$((ok + 1))
    else
        printf '  %-26s %-12s %s\n' "公网 IPv6" "$(status_text 未配置)" "不可用"
        unavailable=$((unavailable + 1))
    fi

    if has_cmd getent && getent hosts example.com >/dev/null 2>&1; then
        printf '  %-26s %-12s %s\n' "DNS 解析" "$(status_text 正常)" "example.com"
        ok=$((ok + 1))
    else
        printf '  %-26s %-12s %s\n' "DNS 解析" "$(status_text 异常)" "解析失败"
        fail=$((fail + 1))
    fi

    code=$(http_code "https://www.google.com/")
    if [[ "$code" != "000" ]]; then
        printf '  %-26s %-12s HTTP %s\n' "HTTPS 连接" "$(status_text 正常)" "$code"
        ok=$((ok + 1))
    else
        printf '  %-26s %-12s %s\n' "HTTPS 连接" "$(status_text 异常)" "连接失败"
        fail=$((fail + 1))
    fi

    if has_cmd ping && ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        printf '  %-26s %-12s %s\n' "ICMP 连通性" "$(status_text 正常)" "1.1.1.1"
        ok=$((ok + 1))
    else
        printf '  %-26s %-12s %s\n' "ICMP 连通性" "$(status_text 异常)" "探测失败"
        fail=$((fail + 1))
    fi

    code=$(http_code "https://www.cloudflare.com/")
    if [[ "$code" != "000" ]]; then
        printf '  %-26s %-12s HTTP %s\n' "网站连通性" "$(status_text 正常)" "$code"
        ok=$((ok + 1))
    else
        printf '  %-26s %-12s %s\n' "网站连通性" "$(status_text 异常)" "连接失败"
        fail=$((fail + 1))
    fi

    line
    printf '\n  检测汇总\n'
    item "检测项目" "$total"
    item "正常" "$(status_text "$ok")"
    item "异常" "$(status_text "$fail")"
    item "不可用" "$(status_text "$unavailable")"
    result_footer
    pause
}

toggle_hide_ip() {
    if [[ "$HIDE_IP" == 1 ]]; then HIDE_IP=0; else HIDE_IP=1; fi
}

# ------------------------------------------------------------
# 依赖预检
# ------------------------------------------------------------
check_deps() {
    # 拒绝 curl | bash（stdin 不是 TTY）
    if [[ ! -t 0 ]]; then
        printf '%s错误：交互式输入不可用。%s\n' "$C_RED" "$C_RESET" >&2
        printf '请使用：bash <(curl -fsSL %s)\n' "$RAW_URL" >&2
        printf '而不是：curl -fsSL %s | bash\n' "$RAW_URL" >&2
        exit 1
    fi

    local missing=()
    has_cmd curl || missing+=("curl")
    if (( ${#missing[@]} > 0 )); then
        printf '%s缺少必要命令: %s%s\n' "$C_RED" "${missing[*]}" "$C_RESET" >&2
        printf 'Ubuntu/Debian: apt install -y %s\n' "${missing[*]}" >&2
        printf 'RHEL/CentOS:   yum install -y %s\n' "${missing[*]}" >&2
        exit 1
    fi

    if [[ "$HIDE_IP" == 1 ]] && ! has_cmd python3; then
        printf '%s警告：未安装 python3，隐私模式对 IP 文本脱敏会降级。%s\n' \
            "$C_YELLOW" "$C_RESET" >&2
        printf '按回车继续，或 Ctrl+C 退出后安装 python3。\n' >&2
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
    box_text "${C_CYAN}网络检测${C_RESET}"
    box_text ""
    box_text "  01  全面检测"
    box_text "  02  IPv4 地址检测"
    box_text "  03  IPv6 地址检测"
    box_text "  04  IP 信息查询"
    box_text "  05  本机网络配置"
    box_text "  06  流媒体检测"
    box_text "  07  网络诊断与路由追踪"
    box_text "  08  DNS 解析检测"
    box_text "  09  系统信息"
    box_text "  10  网站连通性检测"
    box_text "  11  网络质量检测"
    box_text "  12  TCP 端口连通性检测"
    box_text "  13  MTU 排查"
    box_text ""
    box_text "${C_CYAN}三网检测${C_RESET}"
    box_text ""
    box_text "  15  三网延迟检测（电信/联通/移动）"
    box_text "  16  三网自定义节点检测"
    box_text ""
    mid_border
    box_text "${C_CYAN}隐私保护${C_RESET}"
    if [[ "$HIDE_IP" == 1 ]]; then
        box_text "  隐藏 IP 模式    ${C_GREEN}[已开启]${C_RESET}"
    else
        box_text "  隐藏 IP 模式    ${C_YELLOW}[已关闭]${C_RESET}"
    fi
    box_text "  14  切换隐藏 IP 模式"
    mid_border
    box_text ""
    box_text "  请输入选项  [01-16 / 00 退出]"
    bottom_border
    printf '\n'
    if ! read -r -p "  > " choice; then
        printf '\n  已退出\n'
        exit 0
    fi
    case "$choice" in
        1|01) retry_loop full_check ;;
        2|02) retry_loop ipv4_check ;;
        3|03) retry_loop ipv6_check ;;
        4|04) retry_loop ip_info ;;
        5|05) retry_loop network_config ;;
        6|06) retry_loop streaming_check ;;
        7|07) retry_loop route_trace ;;
        8|08) retry_loop dns_check ;;
        9|09) retry_loop system_info ;;
        10)   retry_loop website_check ;;
        11)   retry_loop network_quality ;;
        12)   retry_loop tcp_check ;;
        13)   retry_loop mtu_check ;;
        14)   toggle_hide_ip ;;
        15)   retry_loop tri_net_ping ;;
        16)   retry_loop tri_net_custom ;;
        0|00|q|Q|exit)
            printf '\n  感谢使用 %s\n' "VPS 网络检测工具"
            exit 0
            ;;
        *)
            printf '\n  %s无效选项，请重新输入。%s\n' "$C_YELLOW" "$C_RESET"
            sleep 1
            ;;
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
  --no-mask      关闭 IP 隐藏（等同于菜单 14）
EOF
        exit 0 ;;
    --no-mask) HIDE_IP=0 ;;
esac

if [[ -z "${NYC_SOURCED:-}" ]]; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        check_deps
        while true; do
            menu
        done
    fi
fi
