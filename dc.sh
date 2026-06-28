#!/bin/bash

set -euo pipefail

info() {
    echo "--> $*"
}

warn() {
    echo "    [警告] $*" >&2
}

error() {
    echo "    [错误] $*" >&2
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "当前不是 root，且未找到 sudo。"
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

cleanup_broken_xanmod_sources() {
    local file
    local found=false

    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [ -e "$file" ] || continue
        if grep -Eq 'deb\.xanmod\.org[[:space:]]+releases|Suites:[[:space:]]*releases' "$file" 2>/dev/null; then
            found=true
            info "检测到过期 XanMod APT 源: $file"
            run_as_root cp "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
            if [[ "$file" == *.sources ]]; then
                run_as_root sed -i '/deb\.xanmod\.org/,+10 s/^/# disabled by vps-easyset: /' "$file"
            else
                run_as_root sed -i -E '/deb\.xanmod\.org[[:space:]]+releases/s/^/# disabled by vps-easyset: /' "$file"
            fi
        fi
    done

    if [ "$found" = true ]; then
        warn "已禁用过期 XanMod releases 源；正确 XanMod 源应使用系统代号，例如 noble/bookworm。"
        info "刷新 APT 索引..."
        run_as_root apt-get update
    fi
}

install_docker_engine() {
    if command_exists docker; then
        info "检测到 Docker 已安装: $(docker --version)"
        return 0
    fi

    info "安装 Docker..."
    cleanup_broken_xanmod_sources

    if command_exists curl; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    else
        error "未找到 curl，无法下载安装脚本。"
        exit 1
    fi

    run_as_root sh /tmp/get-docker.sh

    if ! command_exists docker; then
        error "Docker 安装后仍未找到 docker 命令。"
        exit 1
    fi
}

install_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        info "检测到 Docker Compose 插件: $(docker compose version)"
        return 0
    fi

    info "安装 Docker Compose 插件..."
    cleanup_broken_xanmod_sources

    if ! run_as_root apt-get install -y docker-compose-plugin; then
        warn "通过 APT 安装 Compose 插件失败，回退安装独立 docker-compose 二进制。"
        local arch
        arch=$(uname -m)
        case "$arch" in
            x86_64) arch="x86_64" ;;
            aarch64|arm64) arch="aarch64" ;;
            armv7l) arch="armv7" ;;
            *)
                error "不支持的 Docker Compose 架构: $arch"
                exit 1
                ;;
        esac
        run_as_root curl -fL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}" -o /usr/local/bin/docker-compose
        run_as_root chmod +x /usr/local/bin/docker-compose
    fi

    if docker compose version >/dev/null 2>&1; then
        info "Docker Compose 插件版本: $(docker compose version)"
    elif command_exists docker-compose; then
        info "Docker Compose 独立版本: $(docker-compose --version)"
    else
        error "Docker Compose 安装失败。"
        exit 1
    fi
}

configure_docker_logging() {
    info "配置 Docker 日志大小限制..."
    run_as_root mkdir -p /etc/docker
    cat <<'EOF' | run_as_root tee /etc/docker/daemon.json >/dev/null
{
  "log-driver": "json-file",
  "log-opts": {
    "max-file": "3",
    "max-size": "10m"
  }
}
EOF
}

restart_and_verify_docker() {
    info "重启 Docker 服务..."

    if ! command_exists systemctl; then
        warn "未找到 systemctl，跳过服务重启；请手动确认 Docker 已运行。"
        return 0
    fi

    run_as_root systemctl daemon-reload

    if ! systemctl cat docker.service >/dev/null 2>&1; then
        error "未找到 docker.service，说明 Docker Engine 未正确安装。"
        exit 1
    fi

    run_as_root systemctl enable --now docker
    run_as_root systemctl restart docker

    if ! systemctl is-active --quiet docker; then
        error "docker.service 未处于 active 状态。"
        run_as_root systemctl status docker --no-pager || true
        exit 1
    fi

    info "Docker 服务状态: active"
}

main() {
    install_docker_engine
    install_docker_compose
    configure_docker_logging
    restart_and_verify_docker
    info "Docker 安装和配置完成！"
}

main "$@"
