#!/usr/bin/env bash
set -euo pipefail

NAME="lush"
LSP="lush-lsp"
VERSION="0.1.0"
DIST="dist"
BIN_DIR="$DIST/bin"

mkdir -p "$BIN_DIR"

step() { echo -e "\n\033[1;36m$*\033[0m"; }
ok()   { echo -e "  \033[0;32mok\033[0m  $*"; }
die()  { echo -e "  \033[0;31merror\033[0m  $*" >&2; exit 1; }

package_linux() {
    for arch in x86_64 aarch64; do
        step "Building and packaging Linux $arch..."
        # Use Docker to build for specific arch
        docker build --build-arg ARCH=$arch -f Dockerfile.linux -t lush-build-$arch .
        docker create --name lush-temp-$arch lush-build-$arch
        
        mkdir -p "$BIN_DIR/linux/$arch"
        docker cp lush-temp-$arch:/usr/local/bin/lush "$BIN_DIR/linux/$arch/$NAME"
        docker cp lush-temp-$arch:/usr/local/bin/lush-lsp "$BIN_DIR/linux/$arch/$LSP"
        docker rm lush-temp-linux-$arch 2>/dev/null || true
        docker rm lush-temp-$arch

        # nfpm needs the arch in the environment
        export ARCH=$arch
        nfpm pkg -t deb -p "$DIST/lush_${VERSION}_${arch}.deb"
        nfpm pkg -t rpm -p "$DIST/lush-${VERSION}-1.${arch}.rpm"
        nfpm pkg -t apk -p "$DIST/lush-${VERSION}-${arch}.apk"
    done
}

build_macos() {
    step "Building macOS (Procursus/Universal)"
    cargo build --release
    
    mkdir -p "$BIN_DIR/macos"
    cp "target/release/$NAME" "$BIN_DIR/macos/$NAME"
    cp "target/release/$LSP" "$BIN_DIR/macos/$LSP"
    
    # Procursus layout (Deb)
    local pkg_dir="procursus_pkg"
    mkdir -p "$pkg_dir/opt/procursus/bin" "$pkg_dir/DEBIAN"
    cp "target/release/$NAME" "$pkg_dir/opt/procursus/bin/$NAME"
    
    cat > "$pkg_dir/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Section: shells
Architecture: iphoneos-arm64
Maintainer: Your Name <you@example.com>
Description: A Lua-powered shell
EOF
    dpkg-deb --build "$pkg_dir" "$DIST/${NAME}_${VERSION}_procursus.deb"
    rm -rf "$pkg_dir"
}

build_windows() {
    step "Building Windows (Portable + MSI)"
    docker build -f Dockerfile.windows -t lush-build-win .
    docker create --name lush-temp-win lush-build-win
    
    mkdir -p "$BIN_DIR/windows"
    docker cp lush-temp-win:/app/lush.exe "$BIN_DIR/windows/$NAME.exe"
    docker cp lush-temp-win:/app/lush-lsp.exe "$BIN_DIR/windows/$LSP.exe"
    
    # Placeholder for MSI (requires wix image)
    # docker run -v "$(pwd):/app" wix-builder ...
    docker rm lush-temp-win
}

case "${1:-}" in
    linux) package_linux ;;
    macos) build_macos ;;
    windows) build_windows ;;
    all) package_linux; build_macos; build_windows ;;
    *) echo "Usage: $0 {linux|macos|windows|all}"; exit 1 ;;
esac
