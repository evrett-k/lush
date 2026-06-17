#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
LSP="lush-lsp"
VERSION="0.1.0"
DIST="dist"
BIN_DIR="$DIST/bin"

mkdir -p "$BIN_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "\n${BOLD}${CYAN}$*${NC}"; }
ok()   { echo -e "  ${GREEN}ok${NC}  $*"; }
die()  { echo -e "  ${RED}error${NC}  $*" >&2; exit 1; }
need() { command -v "$1" &>/dev/null || die "'$1' not found. Please install $1"; }

package_linux() {
    need nfpm
    need docker
    step "building and packaging linux (docker)"
    
    docker build -f Dockerfile.linux -t lush-build-linux .
    docker create --name lush-temp-linux lush-build-linux
    
    mkdir -p "$BIN_DIR/linux/x86_64-musl"
    docker cp lush-temp-linux:/usr/local/bin/lush "$BIN_DIR/linux/x86_64-musl/$NAME"
    docker cp lush-temp-linux:/usr/local/bin/lush-lsp "$BIN_DIR/linux/x86_64-musl/$LSP"
    docker rm lush-temp-linux

    nfpm pkg -t deb -p "$DIST/lush_${VERSION}_amd64.deb"
    nfpm pkg -t rpm -p "$DIST/lush-${VERSION}-1.x86_64.rpm"
    nfpm pkg -t apk -p "$DIST/lush-${VERSION}-x86_64.apk"
    
    ok "packaged linux formats"
}

build_macos() {
    step "building macos procursus targets (native)"
    cargo build --release
    
    mkdir -p "$BIN_DIR/macos"
    cp "target/release/$NAME" "$BIN_DIR/macos/$NAME"
    cp "target/release/$LSP" "$BIN_DIR/macos/$LSP"
    
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
    
    mkdir -p "$BIN_DIR/windows"
    docker cp lush-temp-win:/app/lush.exe "$BIN_DIR/windows/$NAME.exe"
    docker cp lush-temp-win:/app/lush-lsp.exe "$BIN_DIR/windows/$LSP.exe"
    docker rm lush-temp-win
    ok "windows portable binaries built"
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
