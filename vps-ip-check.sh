#!/usr/bin/env bash

# ============================================================
# VPS IP Check
# Author: nyki4
# Website: https://nyki.cc
# GitHub: https://github.com/nyki4
# Description: VPS public IP and network information checker
# Version: 1.0.0
# ============================================================

set -u
export LC_ALL=C

VERSION="1.0.0"
TIMEOUT=8

# ---------- Colors ----------

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    RESET=''
fi

# ---------- Basic functions ----------

print_line() {
    printf '%b\n' "${CYAN}------------------------------------------------------------${RESET}"
}

info() {
    printf '%b\n' "${BLUE}[INFO]${RESET} $*"
}

success() {
    printf '%b\n' "${GREEN}[ OK ]${RESET} $*"
}

warn() {
    printf '%b\n' "${YELLOW}[WARN]${RESET} $*"
}

fail() {
    printf '%b\n' "${RED}[FAIL]${RESET} $*"
}

# ---------- Dependencies ----------

HTTP_CLIENT=""

if command -v curl >/dev/null 2>&1; then
    HTTP_CLIENT="curl"
elif command -v wget >/dev/null 2>&1; then
    HTTP_CLIENT="wget"
fi

http_get() {
    local url="$1"

    if [[ "$HTTP_CLIENT" == "curl" ]]; then
        curl -4 -fsSL \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            "$url" 2>/dev/null
    elif [[ "$HTTP_CLIENT" == "wget" ]]; then
        wget -4 -q -T "$TIMEOUT" -O - "$url" 2>/dev/null
    else
        return 1
    fi
}

http_get_v6() {
    local url="$1"

    if [[ "$HTTP_CLIENT" == "curl" ]]; then
        curl -6 -fsSL \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            "$url" 2>/dev/null
    elif [[ "$HTTP_CLIENT" == "wget" ]]; then
        wget -6 -q -T "$TIMEOUT" -O - "$url" 2>/dev/null
    else
        return 1
    fi
}

# ---------- IP detection ----------

get_ipv4() {
    local ip=""

    for url in \
        "https://api.ipify.org" \
        "https://ipv4.icanhazip.com" \
        "https://checkip.amazonaws.com"
    do
        ip="$(http_get "$url" || true)"
        ip="${ip//$'\r'/}"
        ip="${ip//$'\n'/}"

        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done

    return 1
}

get_ipv6() {
    local ip=""

    for url in \
        "https://api6.ipify.org" \
        "https://ipv6.icanhazip.com"
    do
        ip="$(http_get_v6 "$url" || true)"
        ip="${ip//$'\r'/}"
        ip="${ip//$'\n'/}"

        if [[ "$ip" == *:* ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done

    return 1
}

# ---------- System information ----------

get_system_info() {
    local os="Unknown"
    local kernel="Unknown"
    local arch="Unknown"
    local virt="Unknown"

    if [[ -r /etc/os-release ]]; then
        os="$(
            . /etc/os-release
            printf '%s' "${PRETTY_NAME:-Unknown}"
        )"
    fi

    kernel="$(uname -r 2>/dev/null || printf 'Unknown')"
    arch="$(uname -m 2>/dev/null || printf 'Unknown')"

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt="$(systemd-detect-virt 2>/dev/null || true)"
        [[ -n "$virt" ]] || virt="None detected"
    fi

    printf 'Operating System : %s\n' "$os"
    printf 'Kernel           : %s\n' "$kernel"
    printf 'Architecture     : %s\n' "$arch"
    printf 'Virtualization   : %s\n' "$virt"
}

# ---------- IP information ----------

get_ip_details() {
    local ip="$1"
    local result=""

    printf '\n'
    print_line
    printf '%b\n' "${BOLD}IP Details: ${ip}${RESET}"
    print_line

    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 is not installed; showing basic IP information only."
        return 0
    fi

    # ipwho.is provides JSON data. Python is optional and is only used
    # to parse the response; no Python package is required.
    result="$(
        http_get "https://ipwho.is/${ip}" |
        python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)

    if not data.get("success", False):
        print("Query failed or service returned an error.")
        sys.exit(0)

    connection = data.get("connection") or {}

    fields = [
        ("Country", data.get("country")),
        ("Country Code", data.get("country_code")),
        ("Region", data.get("region")),
        ("City", data.get("city")),
        ("Postal Code", data.get("postal')),
        ("Continent", data.get("continent")),
        ("Latitude", data.get("latitude")),
        ("Longitude", data.get("longitude")),
        ("ISP", connection.get("isp")),
        ("Organization", connection.get("org")),
        ("ASN", connection.get("asn")),
        ("Domain", connection.get("domain")),
    ]

    for key, value in fields:
        if value is not None and value != "":
            print("{:<17}: {}".format(key, value))

except Exception:
    print("Unable to parse IP information.")
' 2>/dev/null
    )" || true

    if [[ -n "$result" ]]; then
        printf '%s\n' "$result"
    else
        warn "Unable to retrieve IP details. The API may be unavailable."
    fi
}

# ---------- Connectivity ----------

check_connectivity() {
    local url

    printf '\n'
    print_line
    printf '%b\n' "${BOLD}Network Connectivity${RESET}"
    print_line

    if [[ -z "$HTTP_CLIENT" ]]; then
        fail "Neither curl nor wget is installed."
        return
    fi

    for url in \
        "https://github.com" \
        "https://nyki.cc" \
        "https://ipwho.is"
    do
        if http_get "$url" >/dev/null 2>&1; then
            success "$url is reachable via IPv4"
        else
            warn "$url is unreachable via IPv4 or timed out"
        fi
    done
}

# ---------- Main ----------

main() {
    local ipv4=""
    local ipv6=""

    clear 2>/dev/null || true

    print_line
    printf '%b\n' "${BOLD}${CYAN}             VPS IP CHECK v${VERSION}${RESET}"
    printf '%b\n' "${BOLD}             Author: nyki4${RESET}"
    printf '%b\n' "             Website: https://nyki.cc"
    print_line

    printf '\n'
    printf '%b\n' "${BOLD}System Information${RESET}"
    print_line

    get_system_info

    printf '\n'
    printf '%b\n' "${BOLD}Public IP Detection${RESET}"
    print_line

    if [[ -z "$HTTP_CLIENT" ]]; then
        fail "curl or wget is required for IP detection."
        exit 1
    fi

    info "Detecting public IPv4..."

    if ipv4="$(get_ipv4)"; then
        success "IPv4: $ipv4"
        get_ip_details "$ipv4"
    else
        warn "IPv4 unavailable."
    fi

    printf '\n'
    info "Detecting public IPv6..."

    if ipv6="$(get_ipv6)"; then
        success "IPv6: $ipv6"
        get_ip_details "$ipv6"
    else
        warn "IPv6 unavailable. This may be normal if IPv6 is not configured."
    fi

    check_connectivity

    printf '\n'
    print_line
    printf '%b\n' "${GREEN}${BOLD}VPS IP check completed.${RESET}"
    printf '%b\n' "GitHub: https://github.com/nyki4"
    printf '%b\n' "Website: https://nyki.cc"
    print_line
}

main "$@"
