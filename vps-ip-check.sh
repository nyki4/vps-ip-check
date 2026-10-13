#!/usr/bin/env bash
# ============================================================
# NYKI VPS IP 检测工具
# 作者：nyki4
# 网站：https://nyki.cc
# GitHub：https://github.com/nyki4/vps-ip-check
# 版本：2.0.0
#
# 支持：Debian / Ubuntu / CentOS / Rocky Linux 等
# 依赖：bash、curl 或 wget
# 可选：python3、ping、dig、traceroute
#
# 注意：
# 1. 本程序只进行网络查询和诊断，不修改系统配置。
# 2. IP 信息由第三方服务提供，结果仅供参考。
# 3. 流媒体测试仅检测指定服务的 HTTP 访问情况，
#    不保证能够判断地区解锁状态。
# ============================================================
set -u
umask 077
VERSION="2.0.0"
AUTHOR="nyki4"
WEBSITE="https://nyki.cc"
GITHUB="https://github.com/nyki4/vps-ip-check"
TIMEOUT=8
export LC_ALL=C
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8
# ---------- 颜色 ----------
if [[ -t 1 ]]; then
    R='\033[31m'
    G='\033[32m'
    Y='\033[33m'
    B='\033[34m'
    M='\033[35m'
    C='\033[36m'
    W='\033[37m'
    BD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    R=''
    G=''
    Y=''
    B=''
    M=''
    C=''
    W=''
    BD=''
    DIM=''
    NC=''
fi
# ---------- 全局变量 ----------
HTTP=""
IPV4=""
IPV6=""
REPORT=""
REPORT_ENABLED=0
# ---------- 基础输出 ----------
标题() {
    printf '%b\n' "${C}${BD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf '%b\n' "${C}${BD}               NYKI VPS IP 检测工具${NC}"
    printf '%b\n' "${C}${BD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
分隔线() {
    printf '%b\n' "${DIM}----------------------------------------------------${NC}"
}
提示() {
    printf '%b\n' "${B}[提示]${NC} $*"
}
成功() {
    printf '%b\n' "${G}[成功]${NC} $*"
}
警告() {
    printf '%b\n' "${Y}[警告]${NC} $*"
}
失败() {
    printf '%b\n' "${R}[失败]${NC} $*"
}
等待() {
    printf '\n'
    read -r -p "按回车键返回菜单..." _
}
# ---------- 依赖检查 ----------
检查依赖() {
    if command -v curl >/dev/null 2>&1; then
        HTTP="curl"
    elif command -v wget >/dev/null 2>&1; then
        HTTP="wget"
    else
        失败 "未找到 curl 或 wget，无法进行网络查询。"
        提示 "Debian / Ubuntu 可执行：apt-get update && apt-get install -y curl"
        return 1
    fi
    return 0
}
# ---------- HTTP 请求 ----------
请求() {
    local url="$1"
    local family="${2:-4}"
    if [[ "$HTTP" == "curl" ]]; then
        if [[ "$family" == "6" ]]; then
            curl -6 -fsSL \
                --connect-timeout "$TIMEOUT" \
                --max-time "$TIMEOUT" \
                "$url" 2>/dev/null
        elif [[ "$family" == "any" ]]; then
            curl -fsSL \
                --connect-timeout "$TIMEOUT" \
                --max-time "$TIMEOUT" \
                "$url" 2>/dev/null
        else
            curl -4 -fsSL \
                --connect-timeout "$TIMEOUT" \
                --max-time "$TIMEOUT" \
                "$url" 2>/dev/null
        fi
    else
        if [[ "$family" == "6" ]]; then
            wget -6 -q -T "$TIMEOUT" -O - "$url" 2>/dev/null
        elif [[ "$family" == "any" ]]; then
            wget -q -T "$TIMEOUT" -O - "$url" 2>/dev/null
        else
            wget -4 -q -T "$TIMEOUT" -O - "$url" 2>/dev/null
        fi
    fi
}
# ---------- 记录检测结果 ----------
记录() {
    printf '%s\n' "$*" 
    if [[ "$REPORT_ENABLED" == "1" && -n "$REPORT" ]]; then
        printf '%s\n' "$*" >> "$REPORT"
    fi
}
记录空行() {
    printf '\n'
    if [[ "$REPORT_ENABLED" == "1" && -n "$REPORT" ]]; then
        printf '\n' >> "$REPORT"
    fi
}
# ---------- 公网 IP 检测 ----------
检测IPv4() {
    local url ip
    for url in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        ip="$(请求 "$url" 4 || true)"
        ip="${ip//$'\r'/}"
        ip="${ip//$'\n'/}"
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    return 1
}
检测IPv6() {
    local url ip
    for url in \
        "https://api6.ipify.org" \
        "https://ipv6.icanhazip.com"
    do
        ip="$(请求 "$url" 6 || true)"
        ip="${ip//$'\r'/}"
        ip="${ip//$'\n'/}"
        if [[ "$ip" == *:* && "$ip" != *[!0-9a-fA-F:]* ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    return 1
}
获取IP() {
    local family="$1"
    if [[ "$family" == "4" ]]; then
        检测IPv4
    else
        检测IPv6
    fi
}
# ---------- IP 归属地与 ASN ----------
查询IP信息() {
    local ip="$1"
    local json=""
    local parsed=""
    [[ -n "$ip" ]] || return 1
    记录空行
    记录 "IP 地址：$ip"
    记录 "查询服务：ipwho.is"
    记录 "----------------------------------------------------"
    json="$(请求 "https://ipwho.is/${ip}" any || true)"
    if [[ -z "$json" ]]; then
        记录 "查询结果：第三方接口无法连接。"
        return 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        parsed="$(
            printf '%s' "$json" |
            python3 -c '
import json
import sys
try:
    d = json.load(sys.stdin)
    if not d.get("success", False):
        print("查询结果：接口未能返回有效信息")
        sys.exit(0)
    c = d.get("connection") or {}
    fields = [
        ("国家或地区", d.get("country")),
        ("国家代码", d.get("country_code")),
        ("省份或州", d.get("region")),
        ("城市", d.get("city")),
        ("所属大洲", d.get("continent")),
        ("邮政编码", d.get("postal")),
        ("纬度", d.get("latitude")),
        ("经度", d.get("longitude")),
        ("运营商", c.get("isp")),
        ("所属组织", c.get("org")),
        ("ASN", c.get("asn")),
        ("关联域名", c.get("domain")),
    ]
    for k, v in fields:
        if v is not None and v != "":
            print("{}：{}".format(k, v))
except Exception:
    print("查询结果：无法解析第三方返回的数据")
' 2>/dev/null
        )" || true
        if [[ -n "$parsed" ]]; then
            while IFS= read -r line; do
                记录 "$line"
            done <<< "$parsed"
        else
            记录 "查询结果：数据解析失败。"
        fi
    else
        记录 "未安装 Python 3，无法解析详细归属地信息。"
        记录 "建议安装 Python 3 后重新运行。"
    fi
}
# ---------- 系统信息 ----------
检测系统信息() {
    local os="未知"
    local kernel="未知"
    local arch="未知"
    local virt="未知"
    local uptime_info="未知"
    if [[ -r /etc/os-release ]]; then
        os="$(
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-未知}"
        )"
    fi
    kernel="$(uname -r 2>/dev/null || printf '未知')"
    arch="$(uname -m 2>/dev/null || printf '未知')"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt="$(systemd-detect-virt 2>/dev/null || true)"
        [[ -n "$virt" ]] || virt="未检测到虚拟化环境"
    fi
    if [[ -r /proc/uptime ]]; then
        uptime_info="$(
            awk '{printf "%d 小时 %d 分钟", $1/3600, ($1%3600)/60}' \
                /proc/uptime 2>/dev/null
        )"
    fi
    记录 "操作系统：$os"
    记录 "内核版本：$kernel"
    记录 "系统架构：$arch"
    记录 "虚拟化类型：$virt"
    记录 "运行时间：$uptime_info"
    if command -v nproc >/dev/null 2>&1; then
        记录 "CPU 逻辑核心数：$(nproc 2>/dev/null || printf '未知')"
    fi
    if [[ -r /proc/meminfo ]]; then
        awk '
        /^MemTotal:/ {
            printf "物理内存：%.0f MB\n", $2/1024
        }
        /^MemAvailable:/ {
            printf "可用内存：%.0f MB\n", $2/1024
        }
        ' /proc/meminfo |
        while IFS= read -r line; do
            记录 "$line"
        done
    fi
}
# ---------- 网络连通性 ----------
检测HTTP连通性() {
    local url="$1"
    local code=""
    if [[ "$HTTP" == "curl" ]]; then
        code="$(
            curl -L -sS \
                --connect-timeout "$TIMEOUT" \
                --max-time "$TIMEOUT" \
                -o /dev/null \
                -w '%{http_code}' \
                "$url" 2>/dev/null
        )" || true
    else
        if 请求 "$url" any >/dev/null 2>&1; then
            code="200"
        fi
    fi
    if [[ "$code" =~ ^[0-9]{3}$ ]] &&
       (( 10#$code >= 200 && 10#$code < 400 )); then
        记录 "[正常] $url (HTTP $code)"
        return 0
    fi
    记录 "[异常] $url (HTTP ${code:-连接失败})"
    return 1
}
网络诊断() {
    local url
    记录 "网络连通性检测"
    记录 "----------------------------------------------------"
    for url in \
        "https://github.com" \
        "https://www.cloudflare.com" \
        "https://nyki.cc"
    do
        检测HTTP连通性 "$url" || true
    done
}
# ---------- DNS 检测 ----------
检测DNS() {
    local domain=""
    记录 "DNS 域名解析检测"
    记录 "----------------------------------------------------"
    for domain in \
        "github.com" \
        "google.com" \
        "cloudflare.com" \
        "nyki.cc"
    do
        if command -v getent >/dev/null 2>&1; then
            local result
            result="$(getent ahosts "$domain" 2>/dev/null || true)"
            if [[ -n "$result" ]]; then
                local address
                address="$(printf '%s\n' "$result" | awk 'NR==1 {print $1}')"
                记录 "[正常] $domain -> $address"
            else
                记录 "[异常] $domain 解析失败"
            fi
        elif command -v nslookup >/dev/null 2>&1; then
            if nslookup "$domain" >/dev/null 2>&1; then
                记录 "[正常] $domain 解析成功"
            else
                记录 "[异常] $domain 解析失败"
            fi
        else
            记录 "系统未安装 getent 或 nslookup，无法进行 DNS 检测。"
            return
        fi
    done
}
# ---------- 延迟检测 ----------
检测延迟() {
    local host=""
    local result=""
    记录 "网络延迟检测"
    记录 "----------------------------------------------------"
    if ! command -v ping >/dev/null 2>&1; then
        记录 "系统未安装 ping，跳过 ICMP 延迟测试。"
        return
    fi
    for host in "1.1.1.1" "8.8.8.8" "223.5.5.5"; do
        result="$(ping -c 2 -W 3 "$host" 2>/dev/null || true)"
        if printf '%s\n' "$result" | grep -q 'time='; then
            local avg
            avg="$(
                printf '%s\n' "$result" |
                awk -F'/' '/^(rtt|round-trip)/ {print $5}'
            )"
            记录 "[可达] $host，平均延迟：${avg:-请查看原始结果} ms"
        else
            记录 "[不可达] $host，可能是网络限制或 ICMP 被屏蔽"
        fi
    done
}
# ---------- 路由追踪 ----------
检测路由() {
    local target="1.1.1.1"
    记录 "路由追踪"
    记录 "----------------------------------------------------"
    if command -v traceroute >/dev/null 2>&1; then
        traceroute -m 8 -w 1 "$target" 2>&1 |
        while IFS= read -r line; do
            记录 "$line"
        done
    elif command -v tracepath >/dev/null 2>&1; then
        tracepath "$target" 2>&1 |
        while IFS= read -r line; do
            记录 "$line"
        done
    else
        记录 "未安装 traceroute 或 tracepath，跳过路由追踪。"
    fi
}
# ---------- 流媒体访问测试 ----------
检测流媒体() {
    local url=""
    记录 "流媒体服务访问检测"
    记录 "----------------------------------------------------"
    记录 "说明：HTTP 可访问不代表已解锁指定地区内容。"
    记录 ""
    for url in \
        "https://www.netflix.com" \
        "https://www.youtube.com" \
        "https://www.disneyplus.com" \
        "https://www.tiktok.com"
    do
        检测HTTP连通性 "$url" || true
    done
    记录 ""
    记录 "本项只测试基础 HTTP 访问，不判断账号、地区或播放权限。"
}
# ---------- IP 风险查询 ----------
检测IP风险() {
    local ip="${1:-}"
    local url=""
    local data=""
    [[ -n "$ip" ]] || {
        记录 "没有可用于查询的公网 IP。"
        return
    }
    记录 "IP 风险信息查询"
    记录 "----------------------------------------------------"
    记录 "检测 IP：$ip"
    记录 "说明：以下为第三方公开信息，不代表完整风险评分。"
    记录 ""
    # 查询 IPinfo 的基础信息接口。
    # 不使用 API 密钥时，返回内容及字段可能受到服务限制。
    url="https://ipinfo.io/${ip}/json"
    data="$(请求 "$url" any || true)"
    if [[ -z "$data" ]]; then
        记录 "IPinfo 接口暂时不可用。"
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$data" |
        python3 -c '
import json
import sys
try:
    d = json.load(sys.stdin)
    fields = [
        ("IP", "ip"),
        ("主机名", "hostname"),
        ("城市", "city"),
        ("地区", "region"),
        ("国家", "country"),
        ("组织及 ASN", "org"),
        ("邮政编码", "postal"),
        ("时区", "timezone"),
    ]
    for label, key in fields:
        value = d.get(key)
        if value:
            print("{}：{}".format(label, value))
except Exception:
    print("无法解析查询结果")
' 2>/dev/null |
        while IFS= read -r line; do
            记录 "$line"
        done
    else
        记录 "未安装 Python 3，无法解析 JSON。"
    fi
    记录 ""
    记录 "注意：基础 IP 查询不等于代理识别或欺诈风险评分。"
}
# ---------- 创建检测报告 ----------
开始报告() {
    local dir="${HOME:-/tmp}/nyki-vps-reports"
    if ! mkdir -p "$dir" 2>/dev/null; then
        dir="/tmp/nyki-vps-reports"
        mkdir -p "$dir" 2>/dev/null || return 1
    fi
    REPORT="${dir}/vps-ip-report-$(date +%Y%m%d-%H%M%S).txt"
    REPORT_ENABLED=1
    {
        printf '%s\n' "NYKI VPS IP 检测报告"
        printf '%s\n' "作者：$AUTHOR"
        printf '%s\n' "网站：$WEBSITE"
        printf '%s\n' "版本：$VERSION"
        printf '%s\n' "检测时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf '%s\n' "主机名：$(hostname 2>/dev/null || printf '未知')"
        printf '%s\n' "===================================================="
    } > "$REPORT"
    if [[ ! -w "$REPORT" ]]; then
        REPORT_ENABLED=0
        return 1
    fi
    return 0
}
结束报告() {
    if [[ "$REPORT_ENABLED" == "1" && -n "$REPORT" ]]; then
        printf '\n报告已保存到：%s\n' "$REPORT"
        REPORT_ENABLED=0
    fi
}
# ---------- 检测任务 ----------
任务系统信息() {
    记录 "系统信息"
    记录 "----------------------------------------------------"
    检测系统信息
}
任务IPv4() {
    记录 "公网 IPv4 检测"
    记录 "----------------------------------------------------"
    IPV4="$(检测IPv4 || true)"
    if [[ -n "$IPV4" ]]; then
        记录 "公网 IPv4：$IPV4"
        查询IP信息 "$IPV4" || true
    else
        记录 "未检测到可用的公网 IPv4。"
    fi
}
任务IPv6() {
    记录 "公网 IPv6 检测"
    记录 "----------------------------------------------------"
    IPV6="$(检测IPv6 || true)"
    if [[ -n "$IPV6" ]]; then
        记录 "公网 IPv6：$IPV6"
        查询IP信息 "$IPV6" || true
    else
        记录 "未检测到可用的公网 IPv6。"
    fi
}
任务全部检测() {
    开始报告 || 警告 "无法创建报告文件，将仅在屏幕显示结果。"
    记录 "NYKI VPS IP 全面检测"
    记录 "检测时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
    记录 "===================================================="
    任务系统信息
    记录空行
    任务IPv4
    记录空行
    任务IPv6
    记录空行
    记录 "网络诊断"
    网络诊断
    记录空行
    检测DNS
    记录空行
    检测延迟
    记录空行
    检测流媒体
    记录空行
    if [[ -n "$IPV4" ]]; then
        检测IP风险 "$IPV4"
    fi
    结束报告
}
# ---------- 单项菜单操作 ----------
单项执行() {
    local option="$1"
    case "$option" in
        1)
            开始报告 || true
            任务全部检测
            ;;
        2)
            开始报告 || true
            任务IPv4
            结束报告
            ;;
        3)
            开始报告 || true
            任务IPv6
            结束报告
            ;;
        4)
            开始报告 || true
            if [[ -z "$IPV4" ]]; then
                IPV4="$(检测IPv4 || true)"
            fi
            if [[ -n "$IPV4" ]]; then
                查询IP信息 "$IPV4" || true
            else
                记录 "未检测到可查询的 IPv4。"
            fi
            结束报告
            ;;
        5)
            开始报告 || true
            if [[ -z "$IPV4" ]]; then
                IPV4="$(检测IPv4 || true)"
            fi
            if [[ -n "$IPV4" ]]; then
                检测IP风险 "$IPV4"
            else
                记录 "未检测到可用于查询的 IPv4。"
            fi
            结束报告
            ;;
        6)
            开始报告 || true
            检测流媒体
            结束报告
            ;;
        7)
            开始报告 || true
            网络诊断
            记录空行
            检测延迟
            记录空行
            检测路由
            结束报告
            ;;
        8)
            开始报告 || true
            检测DNS
            结束报告
            ;;
        9)
            开始报告 || true
            任务系统信息
            结束报告
            ;;
        10)
            开始报告 || true
            任务IPv4
            记录空行
            任务IPv6
            记录空行
            检测DNS
            记录空行
            网络诊断
            结束报告
            ;;
        *)
            警告 "无效选项，请重新输入。"
            ;;
    esac
}
# ---------- 主菜单 ----------
显示菜单() {
    clear 2>/dev/null || true
    标题
    printf '%b\n' "  ${W}作者：${G}${AUTHOR}${NC}"
    printf '%b\n' "  ${W}官网：${C}${WEBSITE}${NC}"
    printf '%b\n' "  ${W}版本：${Y}${VERSION}${NC}"
    分隔线
    printf '%b\n' "  ${G}[01]${NC} 全面检测       一键检测全部基础项目"
    printf '%b\n' "  ${G}[02]${NC} IPv4 检测      查询公网 IPv4 地址"
    printf '%b\n' "  ${G}[03]${NC} IPv6 检测      查询公网 IPv6 地址"
    printf '%b\n' "  ${G}[04]${NC} IP 归属地      查询国家、地区、运营商、ASN"
    printf '%b\n' "  ${G}[05]${NC} IP 风险信息    查询公开 IP 信息"
    printf '%b\n' "  ${G}[06]${NC} 流媒体检测    测试常见服务的 HTTP 访问"
    printf '%b\n' "  ${G}[07]${NC} 网络诊断      连通性、延迟、路由"
    printf '%b\n' "  ${G}[08]${NC} DNS 检测      检查常见域名解析"
    printf '%b\n' "  ${G}[09]${NC} 系统信息      系统、架构、内存、虚拟化"
    printf '%b\n' "  ${G}[10]${NC} 快速网络检测  IP、DNS、连通性"
    printf '%b\n' "  ${R}[ 0]${NC} 退出程序"
    分隔线
    printf '\n'
}
主菜单() {
    local choice=""
    if ! 检查依赖; then
        exit 1
    fi
    while true; do
        显示菜单
        read -r -p "请输入选项编号：" choice || exit 0
        case "$choice" in
            0)
                printf '\n'
                成功 "感谢使用 NYKI VPS IP 检测工具！"
                printf '%s\n' "官网：$WEBSITE"
                exit 0
                ;;
            1|01|2|02|3|03|4|04|5|05|6|06|7|07|8|08|9|09|10)
                printf '\n'
                单项执行 "$((10#$choice))"
                printf '\n'
                等待
                ;;
            *)
                警告 "输入错误，请输入 0 至 10 之间的选项。"
                sleep 1
                ;;
        esac
    done
}
# ---------- 启动 ----------
主菜单
