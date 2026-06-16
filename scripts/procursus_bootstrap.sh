#!/usr/bin/env bash
# Procursus bootstrap helper for Lush
set -euo pipefail

bootstrap_procursus() {
    if [ -d "/opt/procursus" ]; then
        echo "Procursus is already installed"
        return 0
    fi

    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root to install Procursus"
        exit 1
    fi

    local arch=$(uname -m)
    local url=""
    if [ "$arch" = "arm64" ]; then
        url="https://apt.procurs.us/bootstraps/big_sur/bootstrap-darwin-arm64.tar.zst"
    else
        url="https://apt.procurs.us/bootstraps/big_sur/bootstrap-darwin-amd64.tar.zst"
    fi

    echo "Downloading and bootstrapping Procursus..."
    curl -L -o /tmp/bootstrap.tar.zst "$url"
    tar --zstd -xf /tmp/bootstrap.tar.zst -C /
    echo 'export PATH="/opt/procursus/bin:$PATH"' >> /etc/paths.d/procursus
    rm /tmp/bootstrap.tar.zst
    echo "Procursus installed to /opt/procursus"
}

# Add this to build.sh or use as a standalone utility
case "${1:-}" in
    bootstrap) bootstrap_procursus ;;
    *) echo "Usage: $0 {bootstrap}" ;;
esac
