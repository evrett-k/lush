#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
VERSION="0.1.0"
DIST="dist"
T_LINUX_X64="x86_64-unknown-linux-musl"
T_LINUX_X86="i686-unknown-linux-musl"
T_LINUX_ARM64="aarch64-unknown-linux-musl"
T_MACOS_ARM64="aarch64-apple-darwin"
T_MACOS_X64="x86_64-apple-darwin"
T_WIN_X64="x86_64-pc-windows-msvc"
T_WIN_X86="i686-pc-windows-msvc"
T_WIN_ARM64="aarch64-pc-windows-msvc"
T_FREEBSD_X64="x86_64-unknown-freebsd"
T_OPENBSD_X64="x86_64-unknown-openbsd"

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
need() { command -v "$1" &>/dev/null || die "'$1' not found"; }

mkdir -p "$DIST"

build_binary() {
    local target="$1"
    if command -v cross &>/dev/null && [ "$target" != "$(rustc -Vv | grep host | cut -f2 -d' ')" ]; then
        cross build --release --target "$target"
    else
        cargo build --release --target "$target"
    fi
}

# --- LINUX/UNIX ---

deb() {
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local pkgroot="$DIST/deb/${NAME}_${VERSION}_amd64"
    mkdir -p "$pkgroot/usr/bin"
    cp "$bin" "$pkgroot/usr/bin/$NAME"
    mkdir -p "$pkgroot/DEBIAN"
    echo "Package: $NAME
Version: $VERSION
Architecture: amd64
Maintainer: dev
Description: $NAME" > "$pkgroot/DEBIAN/control"
    dpkg-deb --build "$pkgroot" "$DIST/${NAME}_${VERSION}_amd64.deb"
    ok "deb"
}

nix() { ok "nix stub"; }
linux_static_amd64() { build_binary "$T_LINUX_X64"; ok "linux-static-amd64"; }
linux_static_x86() { build_binary "$T_LINUX_X86"; ok "linux-static-x86"; }
linux_static_arm64() { build_binary "$T_LINUX_ARM64"; ok "linux-static-arm64"; }

# --- BSD ---

freebsd() {
    build_binary "$T_FREEBSD_X64"
    ok "freebsd build"
}

openbsd() {
    build_binary "$T_OPENBSD_X64"
    ok "openbsd build"
}

# --- MACOS ---

_procursus_arch() {
    local arch_name="$1"
    local cargo_target="$2"
    build_binary "$cargo_target"
    local bin="target/$cargo_target/release/$NAME"
    local pkgroot="$DIST/procursus/${NAME}_${VERSION}_${arch_name}"
    mkdir -p "$pkgroot/opt/procursus/bin"
    install -m 755 "$bin" "$pkgroot/opt/procursus/bin/$NAME"
    ok "procursus $arch_name built"
}

procursus_arm64() { _procursus_arch "darwin-arm64" "$T_MACOS_ARM64"; }
procursus_amd64() { _procursus_arch "darwin-amd64" "$T_MACOS_X64"; }

macos_pkg() { ok "macos-pkg stub"; }
macos_dmg() { ok "macos-dmg stub"; }
brew() { ok "brew stub"; }

# --- WINDOWS ---

windows_msi() { ok "windows-msi stub"; }
windows_portable() {
    build_binary "$T_WIN_X64"
    cp "target/$T_WIN_X64/release/${NAME}.exe" "$DIST/${NAME}-${VERSION}-portable-x86_64.exe"
    ok "windows portable x64"
}
windows32_portable() {
    build_binary "$T_WIN_X86"
    cp "target/$T_WIN_X86/release/${NAME}.exe" "$DIST/${NAME}-${VERSION}-portable-i686.exe"
    ok "windows portable x86"
}
windows_arm64_portable() {
    build_binary "$T_WIN_ARM64"
    cp "target/$T_WIN_ARM64/release/${NAME}.exe" "$DIST/${NAME}-${VERSION}-portable-arm64.exe"
    ok "windows portable arm64"
}

TARGETS=("$@")
for target in "${TARGETS[@]}"; do
    fn="${target//-/_}"
    if declare -f "$fn" >/dev/null; then
        "$fn"
    else
        warn "unknown target: $target"
    fi
done
