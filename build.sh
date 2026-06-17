#!/usr/bin/env bash
set -euo pipefail

NAME="lush"
VERSION="0.1.0"
DIST="dist"

mkdir -p "$DIST"

step() { echo -e "\n\033[1;36m$*\033[0m"; }
ok()   { echo -e "  \033[0;32mok\033[0m  $*"; }

build() {
    step "Building binaries..."
    cargo build --release
    cp "target/release/$NAME" "$DIST/$NAME"
    cp "target/release/lush-lsp" "$DIST/lush-lsp"
    ok "Binaries built to $DIST/"
}

case "${1:-}" in
    build) build ;;
    *) echo "Usage: $0 {build}"; exit 1 ;;
esac
