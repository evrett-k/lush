#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
VERSION="0.1.0"
DIST="dist"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

warn() { echo -e "  ${YELLOW}warn${NC}  $*"; }
step() { echo -e "\n${BOLD}${CYAN}$*${NC}"; }
ok()   { echo -e "  ${GREEN}ok${NC}  $*"; }
die()  { echo -e "  ${RED}error${NC}  $*" >&2; exit 1; }
need() { command -v "$1" &>/dev/null || die "'$1' not found. Please install $1"; }

mkdir -p "$DIST"

package_linux() {
    need nfpm
    need docker
    step "building and packaging linux (docker)"
    
    docker build -f Dockerfile.linux -t lush-build-linux .
    docker create --name lush-temp-linux lush-build-linux
    mkdir -p bin
    docker cp lush-temp-linux:/usr/local/bin/lush bin/lush
    docker rm lush-temp-linux
# Package using nfpm
nfpm pkg -t deb -p "$DIST/lush_${VERSION}_amd64.deb" || echo "Deb packaging failed"
nfpm pkg -t rpm -p "$DIST/lush-${VERSION}-1.x86_64.rpm" || echo "RPM packaging failed"
nfpm pkg -t apk -p "$DIST/lush-${VERSION}-x86_64.apk" || echo "APK packaging failed"

    
    ok "packaged linux formats"
}

build_macos() {
    step "building macos procursus targets (native)"
    cargo build --release
    
    local pkg_dir="procursus_pkg"
    mkdir -p "$pkg_dir/opt/procursus/bin" "$pkg_dir/DEBIAN"
    cp "target/release/$NAME" "$pkg_dir/opt/procursus/bin/$NAME"
    
    cat > "$pkg_dir/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Section: shells
Priority: optional
Architecture: iphoneos-arm64
Maintainer: Your Name <you@example.com>
Description: A Lua-powered shell
EOF
    
    dpkg-deb --build "$pkg_dir" "$DIST/${NAME}_${VERSION}_procursus.deb"
    rm -rf "$pkg_dir"
    ok "macos procursus package created"
}

build_windows() {
    step "building windows targets (docker)"
    docker build -f Dockerfile.windows -t lush-build-win .
    docker create --name lush-temp-win lush-build-win
    docker cp lush-temp-win:/app/lush.exe "$DIST/lush-${VERSION}-universal.exe"
    docker rm lush-temp-win
    ok "windows portable binary built"
}

case "${1:-}" in
    linux) package_linux ;;
    macos) build_macos ;;
    windows) build_windows ;;
    all) 
        package_linux
        build_macos
        build_windows
        ;;
    *)
        echo "Usage: $0 {linux|macos|windows|all}"
        exit 1
        ;;
esac
