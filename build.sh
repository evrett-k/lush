#!/usr/bin/env bash
set -euo pipefail

NAME="lush"
LSP="lush-lsp"
VERSION="0.1.0"
DIST="dist"
BIN_DIR="$DIST/bin"
LOG_DIR="logs"

mkdir -p "$BIN_DIR" "$LOG_DIR"

step() { echo -e "\n\033[1;36m$*\033[0m"; }
ok()   { echo -e "  \033[0;32mok\033[0m  $*"; }
die()  { echo -e "  \033[0;31merror\033[0m  $*" >&2; exit 1; }
need() { command -v "$1" &>/dev/null || die "'$1' not found. Please install $1"; }

# Wrapper to log stdout/stderr
run_log() {
    local logfile="$LOG_DIR/$1.log"
    shift
    "$@" > "$logfile" 2>&1
}

package_linux() {
    for arch in x86_64 aarch64; do
        step "Building/Packaging Linux $arch..."
        
        # Build
        run_log "build_linux_$arch" docker build --build-arg ARCH=$arch -f Dockerfile.linux -t lush-build-$arch .
        docker create --name lush-temp-$arch lush-build-$arch
        
        mkdir -p "$BIN_DIR/linux/$arch"
        docker cp lush-temp-$arch:/usr/local/bin/lush "$BIN_DIR/linux/$arch/$NAME"
        docker cp lush-temp-$arch:/usr/local/bin/lush-lsp "$BIN_DIR/linux/$arch/$LSP"
        docker rm lush-temp-$arch

        # Package
        export ARCH=$arch
        run_log "nfpm_$arch" nfpm pkg
    done
    ok "packaged linux"
}

build_macos() {
    step "Building macOS (Procursus/Universal)"
    run_log "build_macos" cargo build --release
    
    mkdir -p "$BIN_DIR/macos"
    cp "target/release/$NAME" "$BIN_DIR/macos/$NAME"
    cp "target/release/$LSP" "$BIN_DIR/macos/$LSP"
    
    # Procursus layout (Deb)
    for arch in arm64 amd64; do
        local pkg_dir="procursus_pkg_$arch"
        mkdir -p "$pkg_dir/opt/procursus/bin" "$pkg_dir/DEBIAN"
        cp "target/release/$NAME" "$pkg_dir/opt/procursus/bin/$NAME"
        
        cat > "$pkg_dir/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Section: shells
Architecture: $arch
Maintainer: Everett K <everett.kamulda@outlook.com>
Description: A Lua-powered shell
EOF
        dpkg-deb --build "$pkg_dir" "$DIST/lush_${VERSION}_macos-$arch.deb"
        rm -rf "$pkg_dir"
    done
    ok "macos package created"
}

build_windows() {
    step "Building Windows (Portable)"
    run_log "build_windows" docker build -f Dockerfile.windows -t lush-build-win .
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
    all) package_linux; build_macos; build_windows ;;
    *) echo "Usage: $0 {linux|macos|windows|all}"; exit 1 ;;
esac
