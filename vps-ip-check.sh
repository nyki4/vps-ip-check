#!/usr/bin/env bash

# ============================================================
# VPS IP 信息检测工具
# 作者：nyki4
# 网站：https://nyki.cc
# GitHub：https://github.com/nyki4
# 版本：1.1.0
# 说明：检测 VPS 公网 IP、归属地、运营商及基础网络信息
# ============================================================

set -u
export LC_ALL=C

VERSION="1.1.0"
TIMEOUT=8

# ---------- 终端颜色 ----------

if [[ -t 1 ]]; then
    红色='\033[0;31m'
    绿色='\033[0;32m'
    黄色='\033[0;33m'
    蓝色='\033[0;34m'
    青色='\033[0;36m'
    加粗='\033[1m'
    重置='\033[0m'
else
    红色=''
    绿色=''
    黄色=''
    蓝色=''
    青色=''
    加粗=''
    重置=''
fi

# ---------- 输出函数 ----------

分隔线() {
    printf '%b\n' "${青色}============================================================${重置}"
}

提示() {
    printf '%b\n' "${蓝色}[提示]${重置} $*"
}

成功() {
    printf '%b\n' "${绿色}[成功]${重置} $*"
}

警告() {
    printf '%b\n' "${黄色}[警告]${重置} $*"
}

错误() {
    printf '%b\n' "${红色}[错误]${重置} $*"
}

# ---------- 检查依赖 ----------

HTTP工具=""

if command -v curl >/dev/null 2>&1; then
    HTTP工具="curl"
elif command -v wget >/dev/null 2>&1; then
    HTTP工具="wget"
fi

请求网页() {
    local 地址="$1"

    if [[ "$HTTP工具" == "curl" ]]; then
        curl -4 -fsSL \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            "$地址" 2>/dev/null
    elif [[ "$HTTP工具" == "wget" ]]; then
        wget -4 -q -T "$TIMEOUT" -O - "$地址" 2>/dev/null
    else
        return 1
    fi
}

请求网页IPv6() {
    local 地址="$1"

    if [[ "$HTTP工具" == "curl" ]]; then
        curl -6 -fsSL \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            "$地址" 2>/dev/null
    elif [[ "$HTTP工具" == "wget" ]]; then
        wget -6 -q -T "$TIMEOUT" -O - "$地址" 2>/dev/null
    else
        return 1
    fi
}

# ---------- 检测公网 IPv4 ----------

检测IPv4() {
    local 地址=""
    local IP=""

    for 地址 in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        IP="$(请求网页 "$地址" || true)"
        IP="${IP//$'\r'/}"
        IP="${IP//$'\n'/}"

        if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf '%s\n' "$IP"
            return 0
        fi
    done

    return 1
}

# ---------- 检测公网 IPv6 ----------

检测IPv6() {
    local 地址=""
    local IP=""

    for 地址 in \
        "https://api6.ipify.org" \
        "https://ipv6.icanhazip.com"
    do
        IP="$(请求网页IPv6 "$地址" || true)"
        IP="${IP//$'\r'/}"
        IP="${IP//$'\n'/}"

        if [[ "$IP" == *:* ]]; then
            printf '%s\n' "$IP"
            return 0
        fi
    done

    return 1
}

# ---------- 检测系统信息 ----------

检测系统() {
    local 系统="未知"
    local 内核="未知"
    local 架构="未知"
    local 虚拟化="未知"

    if [[ -r /etc/os-release ]]; then
        系统="$(
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-未知}"
        )"
    fi

    内核="$(uname -r 2>/dev/null || printf '未知')"
    架构="$(uname -m 2>/dev/null || printf '未知')"

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        虚拟化="$(systemd-detect-virt 2>/dev/null || true)"
        [[ -n "$虚拟化" ]] || 虚拟化="未检测到"
    fi

    printf '操作系统：%s\n' "$系统"
    printf '内核版本：%s\n' "$内核"
    printf '系统架构：%s\n' "$架构"
    printf '虚拟化类型：%s\n' "$虚拟化"
}

# ---------- 查询 IP 归属地 ----------

查询IP信息() {
    local IP="$1"
    local 结果=""

    printf '\n'
    分隔线
    printf '%b\n' "${加粗}IP 地址详细信息：${IP}${重置}"
    分隔线

    if ! command -v python3 >/dev/null 2>&1; then
        警告 "未安装 Python 3，跳过详细 IP 信息查询。"
        return 0
    fi

    结果="$(
        请求网页 "https://ipwho.is/${IP}" |
        python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)

    if not data.get("success", False):
        print("IP 信息查询失败，服务可能不可用。")
        sys.exit(0)

    connection = data.get("connection") or {}

    fields = [
        ("国家或地区", data.get("country")),
        ("国家代码", data.get("country_code")),
        ("省份或州", data.get("region")),
        ("城市", data.get("city")),
        ("邮政编码", data.get("postal")),
        ("所属大洲", data.get("continent")),
        ("纬度", data.get("latitude")),
        ("经度", data.get("longitude")),
        ("运营商", connection.get("isp")),
        ("所属组织", connection.get("org")),
        ("自治系统号 ASN", connection.get("asn")),
        ("关联域名", connection.get("domain")),
    ]

    for key, value in fields:
        if value is not None and value != "":
            print("{}：{}".format(key, value))

except Exception:
    print("无法解析 IP 信息。")
' 2>/dev/null
    )" || true

    if [[ -n "$结果" ]]; then
        printf '%s\n' "$结果"
    else
        警告 "IP 归属地查询失败，请检查网络或稍后重试。"
    fi
}

# ---------- 网络连通性检测 ----------

检测网络() {
    local 地址=""

    printf '\n'
    分隔线
    printf '%b\n' "${加粗}网络连通性检测${重置}"
    分隔线

    for 地址 in \
        "https://github.com" \
        "https://nyki.cc" \
        "https://ipwho.is"
    do
        if 请求网页 "$地址" >/dev/null 2>&1; then
            成功 "$地址 可以通过 IPv4 访问"
        else
            警告 "$地址 无法访问或连接超时"
        fi
    done
}

# ---------- 主程序 ----------

主程序() {
    local IPv4=""
    local IPv6=""

    printf '\033[2J\033[H' 2>/dev/null || true

    分隔线
    printf '%b\n' "${加粗}${青色}                  VPS IP 信息检测工具${重置}"
    printf '%b\n' "                       版本：${VERSION}"
    printf '%b\n' "                       作者：nyki4"
    printf '%b\n' "                       网站：https://nyki.cc"
    分隔线

    printf '\n'
    printf '%b\n' "${加粗}一、服务器系统信息${重置}"
    分隔线
    检测系统

    printf '\n'
    printf '%b\n' "${加粗}二、公网 IP 地址检测${重置}"
    分隔线

    if [[ -z "$HTTP工具" ]]; then
        错误 "未找到 curl 或 wget，请先安装其中一个工具。"
        exit 1
    fi

    提示 "正在检测公网 IPv4 地址……"

    if IPv4="$(检测IPv4)"; then
        成功 "公网 IPv4：${IPv4}"
        查询IP信息 "$IPv4"
    else
        警告 "未检测到可用的公网 IPv4 地址。"
    fi

    printf '\n'
    提示 "正在检测公网 IPv6 地址……"

    if IPv6="$(检测IPv6)"; then
        成功 "公网 IPv6：${IPv6}"
        查询IP信息 "$IPv6"
    else
        警告 "未检测到可用的公网 IPv6 地址。"
        提示 "如果 VPS 没有配置 IPv6，这属于正常情况。"
    fi

    检测网络

    printf '\n'
    分隔线
    printf '%b\n' "${绿色}${加粗}检测完成！感谢使用。${重置}"
    printf '%b\n' "GitHub：https://github.com/nyki4"
    printf '%b\n' "个人网站：https://nyki.cc"
    分隔线
}

主程序 "$@"
