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
need() { command -v "$1" &>/dev/null || die "'$1' not found"; }

mkdir -p "$DIST"

build_binary() {
    local target="$1"
    cargo build --release --target "$target"
}

deb() {
    build_binary "x86_64-unknown-linux-musl"
    local bin="target/x86_64-unknown-linux-musl/release/$NAME"
    local pkgroot="$DIST/deb/${NAME}_${VERSION}_amd64"
    mkdir -p "$pkgroot/usr/bin"
    cp "$bin" "$pkgroot/usr/bin/$NAME"
    # Create simple deb structure
    mkdir -p "$pkgroot/DEBIAN"
    echo "Package: $NAME
Version: $VERSION
Architecture: amd64
Maintainer: dev
Description: $NAME" > "$pkgroot/DEBIAN/control"
    dpkg-deb --build "$pkgroot" "$DIST/${NAME}_${VERSION}_amd64.deb"
    ok "deb"
}

windows_portable() {
    build_binary "x86_64-pc-windows-msvc"
    cp "target/x86_64-pc-windows-msvc/release/${NAME}.exe" "$DIST/${NAME}-${VERSION}-portable-x86_64.exe"
    ok "windows portable x64"
}

# (Add other functions here as needed)

TARGETS=("$@")
for target in "${TARGETS[@]}"; do
    fn="${target//-/_}"
    if declare -f "$fn" >/dev/null; then
        "$fn"
    else
        warn "unknown target: $target"
    fi
done
