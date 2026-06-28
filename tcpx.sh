#!/usr/bin/env bash

set -Eeuo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/coldrook/vps-easyset/refs/heads/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { echo "[信息] $*"; }
warn() { echo "[注意] $*"; }
error() { echo "[错误] $*" >&2; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "请使用 root 权限运行：sudo bash $0"
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_os() {
    if [ ! -r /etc/os-release ]; then
        error "无法读取 /etc/os-release，暂不支持该系统。"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-unknown}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-${OS_ID} ${OS_VERSION_ID}}"

    case "$OS_ID" in
        ubuntu|debian)
            ;;
        *)
            error "当前系统为 ${OS_PRETTY_NAME}，此脚本仅支持 Debian/Ubuntu。"
            exit 1
            ;;
    esac

    if [ "$(uname -m)" != "x86_64" ]; then
        error "XanMod 仅支持 x86_64，当前架构：$(uname -m)。"
        exit 1
    fi

    info "系统：${OS_PRETTY_NAME}"
    info "架构：$(uname -m)"
    info "当前内核：$(uname -r)"
}

check_supported_version() {
    local major
    major="${OS_VERSION_ID%%.*}"

    case "$OS_ID" in
        ubuntu)
            if ! [[ "$major" =~ ^[0-9]+$ ]] || [ "$major" -lt 20 ]; then
                error "Ubuntu ${OS_VERSION_ID} 版本过低，建议 Ubuntu 20.04+。"
                exit 1
            fi
            ;;
        debian)
            if ! [[ "$major" =~ ^[0-9]+$ ]] || [ "$major" -lt 11 ]; then
                error "Debian ${OS_VERSION_ID} 版本过低，建议 Debian 11+。"
                exit 1
            fi
            ;;
    esac
}

ensure_downloader() {
    if command_exists curl || command_exists wget; then
        return 0
    fi

    error "未找到 curl 或 wget，请先安装其中之一。"
    exit 1
}

download_file() {
    local url="$1"
    local output="$2"

    if command_exists curl; then
        curl -fsSL "$url" -o "$output"
    else
        wget -qO "$output" "$url"
    fi
}

prepare_child_script() {
    local name="$1"
    local local_path="${SCRIPT_DIR}/${name}"
    local temp_path

    if [ -f "$local_path" ]; then
        info "使用本地脚本：${local_path}" >&2
        chmod +x "$local_path" 2>/dev/null || true
        printf '%s\n' "$local_path"
        return 0
    fi

    temp_path="$(mktemp -t "${name}.XXXXXX")"
    info "未找到本地 ${name}，正在从 GitHub 下载..." >&2
    download_file "${REPO_RAW_BASE}/${name}" "$temp_path"
    chmod +x "$temp_path"
    printf '%s\n' "$temp_path"
}

confirm_step() {
    local prompt="$1"
    local answer
    read -r -p "$prompt [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

get_installed_xanmod_kernel() {
    local installed current
    current="$(uname -r)"

    if [[ "$current" == *xanmod* ]]; then
        printf '%s\n' "$current"
        return 0
    fi

    installed=$(dpkg-query -W -f='${Package} ${Version}\n' 'linux-image-*-xanmod*' 2>/dev/null | awk '{print $2}' | sort -V | tail -n 1 || true)
    if [ -n "$installed" ]; then
        printf '%s\n' "$installed"
        return 0
    fi

    return 1
}

normalize_xanmod_version() {
    local value="$1"
    echo "$value" | grep -oE '[0-9]+(\.[0-9]+)+(-x64v[0-9]+)?-xanmod[0-9]+' | head -n 1 | sed -E 's/-x64v[0-9]+//'
}

get_cpu_x64_level() {
    local cpu_support_info cpu_level
    cpu_support_info=$(/usr/bin/awk '
    BEGIN {
        while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
        if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
        if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
        if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
        if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
        if (level > 0) { print level; exit 0 }
        exit 1
    }' 2>/dev/null || true)

    cpu_level="${cpu_support_info:-}"
    if [[ "$cpu_level" =~ ^[0-9]+$ ]] && [ "$cpu_level" -gt 0 ]; then
        printf '%s\n' "$cpu_level"
        return 0
    fi

    return 1
}

get_latest_xanmod_version() {
    local cpu_level="$1"
    local sf_base_url="https://sourceforge.net/projects/xanmod/files/releases/lts/"
    local raw_html_main latest_version_dir latest_version_url raw_html_version arch_dir_suffix files_page_url raw_html_files image_file latest_version

    raw_html_main=$(download_stdout "$sf_base_url" || true)
    latest_version_dir=$(echo "$raw_html_main" | grep -o '<span class="name">[0-9][^<]*-xanmod[0-9]*</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | sort -V | tail -n 1)
    [ -n "$latest_version_dir" ] || return 1

    latest_version_url="${sf_base_url}${latest_version_dir}/"
    raw_html_version=$(download_stdout "$latest_version_url" || true)
    arch_dir_suffix=$(echo "$raw_html_version" | grep -o '<span class="name">.*x64v'"${cpu_level}"'[^<]*</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)

    if [ -z "$arch_dir_suffix" ] && [ "$cpu_level" -eq 4 ]; then
        cpu_level=3
        arch_dir_suffix=$(echo "$raw_html_version" | grep -o '<span class="name">.*x64v'"${cpu_level}"'[^<]*</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)
    fi
    [ -n "$arch_dir_suffix" ] || return 1

    files_page_url="${latest_version_url}${arch_dir_suffix}/"
    raw_html_files=$(download_stdout "$files_page_url" || true)
    image_file=$(echo "$raw_html_files" | grep -o '<span class="name">linux-image-.*-x64v'"${cpu_level}"'-xanmod.*\.deb</span>' | sed -e 's/<span class="name">//' -e 's,</span>,,' | head -n 1)
    [ -n "$image_file" ] || return 1

    latest_version=$(normalize_xanmod_version "$image_file")
    [ -n "$latest_version" ] || return 1
    printf '%s\n' "$latest_version"
}

version_lt() {
    local current="$1"
    local latest="$2"
    [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | head -n 1)" != "$latest" ] && [ "$current" != "$latest" ]
}

download_stdout() {
    local url="$1"
    if command_exists curl; then
        curl -fsSL "$url"
    else
        wget -qO - "$url"
    fi
}

handle_xanmod_kernel() {
    local xanmod_script="$1"
    local installed_kernel installed_version cpu_level latest_version

    installed_kernel=$(get_installed_xanmod_kernel || true)
    if [ -z "$installed_kernel" ]; then
        warn "未检测到已安装的 XanMod 内核。"
        if confirm_step "是否开始安装 XanMod 内核？"; then
            bash "$xanmod_script" install
        else
            warn "已跳过 XanMod 内核安装。"
        fi
        return 0
    fi

    info "检测到已安装的 XanMod 内核/版本：${installed_kernel}"
    installed_version=$(normalize_xanmod_version "$installed_kernel")
    if [ -z "$installed_version" ]; then
        warn "无法解析当前 XanMod 版本，将跳过版本比较。"
        return 0
    fi

    cpu_level=$(get_cpu_x64_level || true)
    if [ -z "$cpu_level" ]; then
        warn "无法检测 CPU x86-64-v 等级，将跳过官网版本比较。"
        return 0
    fi

    info "正在检测 XanMod 官网最新 LTS 版本..."
    latest_version=$(get_latest_xanmod_version "$cpu_level" || true)
    if [ -z "$latest_version" ]; then
        warn "无法从官网检测最新 XanMod 版本，将直接进入内核参数优化步骤。"
        return 0
    fi

    info "当前版本：${installed_version}"
    info "官网版本：${latest_version}"
    if version_lt "$installed_version" "$latest_version"; then
        warn "当前 XanMod 版本低于官网最新版本。"
        if confirm_step "是否更新 XanMod 内核？"; then
            bash "$xanmod_script" install
        else
            warn "已跳过 XanMod 内核更新。"
        fi
    else
        info "XanMod 已是最新或不低于官网版本，跳过内核安装。"
    fi
}

main() {
    require_root
    detect_os
    check_supported_version
    ensure_downloader

    local xanmod_script optimize_script
    xanmod_script="$(prepare_child_script manage_xanmod_kernel.sh)"
    optimize_script="$(prepare_child_script optimize_kernel_parameters.sh)"

    echo "=========================================="
    echo "  VPS TCP/XanMod 一键入口"
    echo "=========================================="
    echo "执行顺序："
    echo "  1. 安装 XanMod 内核"
    echo "  2. 优化内核网络参数"
    echo ""
    warn "安装内核后通常需要重启才能启用新内核；若当前未运行 XanMod，部分优化需重启后再次执行才完全生效。"
    echo ""

    handle_xanmod_kernel "$xanmod_script"

    echo ""
    if confirm_step "是否继续执行内核参数优化？"; then
        bash "$optimize_script"
    else
        warn "已跳过内核参数优化。"
    fi

    echo ""
    info "流程结束。"
    info "如已安装新内核，请重启后使用 uname -r 确认是否进入 XanMod 内核。"
}

main "$@"
