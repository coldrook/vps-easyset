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

    if confirm_step "是否开始安装 XanMod 内核？"; then
        bash "$xanmod_script" install
    else
        warn "已跳过 XanMod 内核安装。"
    fi

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
