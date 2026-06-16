#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
VERSION="0.1.0"
DIST="dist"
T_LINUX_X64="x86_64-unknown-linux-musl"
T_WIN_X64="x86_64-pc-windows-msvc"

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
    step "building $target"
    if command -v cross &>/dev/null && [ "$target" != "$(rustc -Vv | grep host | cut -f2 -d' ')" ]; then
        cross build --release --target "$target"
    else
        cargo build --release --target "$target"
    fi
}

package() {
    need nfpm "install nfpm from https://nfpm.goreleaser.com/"
    build_binary "$T_LINUX_X64"
    nfpm pkg -t deb -p "$DIST/lush_${VERSION}_amd64.deb"
    nfpm pkg -t rpm -p "$DIST/lush-${VERSION}-1.x86_64.rpm"
    nfpm pkg -t apk -p "$DIST/lush-${VERSION}-x86_64.apk"
    ok "packaged with nfpm"
}

windows_portable() {
    build_binary "$T_WIN_X64"
    cp "target/$T_WIN_X64/release/${NAME}.exe" "$DIST/${NAME}-${VERSION}-portable-x86_64.exe"
    ok "windows portable x64"
}

# Default to package and windows
if [ $# -eq 0 ]; then
    package
    windows_portable
else
    for target in "$@"; do
        fn="${target//-/_}"
        if declare -f "$fn" >/dev/null; then
            "$fn"
        else
            warn "unknown target: $target"
        fi
    done
fi
