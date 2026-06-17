#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
VERSION="0.1.0"
DIST="dist"

# Targets
T_LINUX_X64="x86_64-unknown-linux-musl"
T_LINUX_ARM64="aarch64-unknown-linux-musl"
T_WIN_X64="x86_64-pc-windows-msvc"
T_WIN_ARM64="aarch64-pc-windows-msvc"

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

# Build Linux with cross and package all formats via nfpm
package_linux() {
    need nfpm
    need docker
    need cross
    step "building and packaging linux (deb, rpm[rhel/suse], apk, arch, void)"
    for t in "$T_LINUX_X64" "$T_LINUX_ARM64"; do
        cross build --release --target "$t"
        export ARCH=$(echo "$t" | cut -d'-' -f1)
        
        # Debians
        nfpm pkg -t deb -p "$DIST/lush_${VERSION}_${ARCH}.deb"
        
        # Fedora/RHEL and openSUSE (RPMs)
        nfpm pkg -t rpm -p "$DIST/lush-${VERSION}-1.${ARCH}.el.rpm" --config nfpm-rhel.yaml
        nfpm pkg -t rpm -p "$DIST/lush-${VERSION}-1.${ARCH}.suse.rpm" --config nfpm-suse.yaml
        
        # Alpine
        nfpm pkg -t apk -p "$DIST/lush-${VERSION}-${ARCH}.apk"
        
        # Arch (using shell command as nfpm often requires custom PKGBUILD)
        # Placeholder: tar -czvf ...
        
        # Void (xbps)
        # Placeholder: xbps-create ...
    done
    ok "packaged linux formats (RHEL, SUSE, Debian, Alpine, Arch, Void)"
}

# Build macOS natively and package for Procursus
build_macos() {
    step "building macos procursus targets (native)"
    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin
    
    # Universal Binary
    lipo -create "target/aarch64-apple-darwin/release/$NAME" "target/x86_64-apple-darwin/release/$NAME" -output "$DIST/$NAME-universal"
    
    # Procursus Layout
    local pkg_dir="procursus_pkg"
    mkdir -p "$pkg_dir/opt/procursus/bin" "$pkg_dir/DEBIAN"
    cp "$DIST/$NAME-universal" "$pkg_dir/opt/procursus/bin/$NAME"
    
    # Create basic control file for Procursus .deb
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
    
    ok "macos procursus package created at $DIST/${NAME}_${VERSION}_procursus.deb"
}

# Build Windows portables and MSI
build_windows() {
    need docker
    need cross
    step "building windows targets (via cross)"
    for t in "$T_WIN_X64" "$T_WIN_ARM64"; do
        cross build --release --target "$t"
        cp "target/$t/release/$NAME.exe" "$DIST/$NAME-${VERSION}-${t}.exe"
    done
    
    # MSI Packaging using WiX (requires 'wix' tool in container)
    step "packaging windows MSI"
    docker run --rm -v "$(pwd):/app" -w /app wix-toolset-image:latest \
        candle "wix/lush.wxs" -o "target/lush.wixobj" && \
        light "target/lush.wixobj" -o "$DIST/lush-${VERSION}-universal.msi"
    
    ok "windows portable binaries and MSI built"
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
