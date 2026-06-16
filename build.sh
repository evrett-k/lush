#!/usr/bin/env bash
set -uo pipefail

NAME="lush"
VERSION="0.1.0"
DESCRIPTION="A Lua-powered shell"
MAINTAINER="evrett-k"
MAINTAINER_EMAIL="evrett.k@proton.me"
URL="https://github.com/everett-k/lush"
LICENSE="GPLv3"
DIST="dist"

T_LINUX_X64="x86_64-unknown-linux-musl"
T_LINUX_X86="i686-unknown-linux-musl"
T_LINUX_ARM64="aarch64-unknown-linux-musl"
T_MACOS_X64="x86_64-apple-darwin"
T_MACOS_ARM64="aarch64-apple-darwin"
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

step() { echo -e "\n${BOLD}${CYAN}$*${NC}"; }
ok()   { echo -e "  ${GREEN}ok${NC}  $*"; }
warn() { echo -e "  ${YELLOW}warn${NC}  $*"; }
die()  { echo -e "  ${RED}error${NC}  $*" >&2; exit 1; }

need() { command -v "$1" &>/dev/null || die "'$1' not found — ${2:-install it and retry}"; }

mkdir -p "$DIST"

ensure_target() {
    rustup target list --installed 2>/dev/null | grep -q "^$1$" || rustup target add "$1"
}

build_binary() {
    local target="$1"
    step "building $target"
    ensure_target "$target"
    cargo build --release --target "$target"
    local bin="target/$target/release/$NAME"
    strip "$bin" 2>/dev/null || true
    ok "$bin"
}

# For Linux cross-compilation we use Docker so the build host doesn't need
# musl/gcc cross toolchains installed directly
build_binary_docker() {
    local target="$1"
    need docker "install Docker from https://docs.docker.com/get-docker/"

    # Build the image if it doesn't exist yet
    if ! docker image inspect lush-builder >/dev/null 2>&1; then
        step "building lush-builder docker image"
        docker build -t lush-builder .
    fi

    step "building $target (via Docker)"
    docker run --rm \
        -v "$(pwd)":/src \
        -w /src \
        -e OPENSSL_STATIC=1 \
        -e OPENSSL_DIR=/usr \
        -e PKG_CONFIG_ALL_STATIC=1 \
        -e RUSTFLAGS="-C target-feature=+crt-static" \
        lush-builder \
        sh -c "rustup target add $target && cargo build --release --target $target"
    ok "target/$target/release/$NAME"
}

docker_build() {
    need docker "install Docker from https://docs.docker.com/get-docker/"
    step "building lush-builder docker image"
    docker build --no-cache -t lush-builder .
    ok "lush-builder image ready"
}

rhel() {
    need rpmbuild "sudo dnf install rpm-build"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local topdir; topdir="$(pwd)/$DIST/rhel/rpmbuild"
    mkdir -p "$topdir"/{SPECS,SOURCES,BUILD,BUILDROOT,RPMS,SRPMS}
    local stagename="${NAME}-${VERSION}"
    local stagedir="$topdir/SOURCES/$stagename"
    mkdir -p "$stagedir/usr/bin"
    cp "$bin" "$stagedir/usr/bin/$NAME"
    tar -czf "$topdir/SOURCES/${stagename}.tar.gz" -C "$topdir/SOURCES" "$stagename"
    rm -rf "$stagedir"
    cat > "$topdir/SPECS/${NAME}.spec" <<SPEC
Name:           ${NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        ${DESCRIPTION}
License:        ${LICENSE}
URL:            ${URL}
Source0:        %{name}-%{version}.tar.gz
Group:          Shells
BuildArch:      x86_64

%description
${DESCRIPTION}

%prep
%setup -q

%install
install -D -m 0755 usr/bin/%{name} %{buildroot}%{_bindir}/%{name}

%files
%{_bindir}/%{name}
SPEC
    rpmbuild --define "_topdir $topdir" --define "__strip /bin/true" -bb "$topdir/SPECS/${NAME}.spec" >/dev/null
    find "$topdir/RPMS" -name "*.rpm" -exec cp {} "$DIST/" \;
    ok "red hat rpm"
}

suse() {
    need rpmbuild "sudo zypper install rpm-build"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local topdir; topdir="$(pwd)/$DIST/suse/rpmbuild"
    mkdir -p "$topdir"/{SPECS,SOURCES,BUILD,BUILDROOT,RPMS,SRPMS}
    local stagename="${NAME}-${VERSION}"
    local stagedir="$topdir/SOURCES/$stagename"
    mkdir -p "$stagedir/usr/bin"
    echo "${LICENSE}" > "$stagedir/LICENSE"
    cp "$bin" "$stagedir/usr/bin/$NAME"
    tar -czf "$topdir/SOURCES/${stagename}.tar.gz" -C "$topdir/SOURCES" "$stagename"
    rm -rf "$stagedir"
    cat > "$topdir/SPECS/${NAME}-suse.spec" <<SPEC
Name:           ${NAME}
Version:        ${VERSION}
Release:        1
Summary:        ${DESCRIPTION}
License:        ${LICENSE}
URL:            ${URL}
Source0:        %{name}-%{version}.tar.gz
Vendor:         openSUSE
BuildArch:      x86_64

%description
${DESCRIPTION}

%prep
%setup -q

%install
install -D -m 0755 usr/bin/%{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSE
%{_bindir}/%{name}
SPEC
    rpmbuild --define "_topdir $topdir" --define "dist .opensuse" --define "__strip /bin/true" -bb "$topdir/SPECS/${NAME}-suse.spec" >/dev/null
    find "$topdir/RPMS" -name "*.rpm" | while read -r rpm; do
        cp "$rpm" "$DIST/$(basename "$rpm" .rpm)-suse.rpm"
    done
    ok "suse rpm"
}

arch() {
    need makepkg "must run on arch linux"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local pkgdir="$DIST/arch"
    mkdir -p "$pkgdir"
    cp "$bin" "$pkgdir/$NAME"
    cat > "$pkgdir/PKGBUILD" <<PKGBUILD
pkgname=${NAME}
pkgver=${VERSION}
pkgrel=1
pkgdesc="${DESCRIPTION}"
arch=('x86_64')
url="${URL}"
license=('${LICENSE}')
options=('!strip')
source=("${NAME}")
sha256sums=('SKIP')

package() {
    install -Dm755 "\${srcdir}/${NAME}" "\${pkgdir}/usr/bin/${NAME}"
}
PKGBUILD
    (cd "$pkgdir" && SRCDEST=. PKGDEST=. makepkg -f --nodeps --nocheck >/dev/null 2>&1)
    find "$pkgdir" -maxdepth 1 -name "*.pkg.tar.zst" -exec cp {} "$DIST/" \;
    ok "arch package"
}

deb() {
    need dpkg-deb "sudo apt-get install dpkg-dev"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local pkgroot="$DIST/deb/${NAME}_${VERSION}_amd64"
    mkdir -p "$pkgroot/usr/bin" "$pkgroot/DEBIAN"
    install -m 755 "$bin" "$pkgroot/usr/bin/$NAME"
    local kib; kib="$(du -sk "$pkgroot/usr" | cut -f1)"
    cat > "$pkgroot/DEBIAN/control" <<CONTROL
Package: ${NAME}
Version: ${VERSION}
Architecture: amd64
Section: shells
Priority: optional
Installed-Size: ${kib}
Maintainer: ${MAINTAINER} <${MAINTAINER_EMAIL}>
Homepage: ${URL}
Description: ${DESCRIPTION}
CONTROL
    dpkg-deb --build --root-owner-group "$pkgroot" "$DIST/${NAME}_${VERSION}_amd64.deb" >/dev/null
    ok "debian deb"
}

alpine() {
    need abuild "apk add alpine-sdk"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local apkdir="$DIST/alpine"
    mkdir -p "$apkdir"
    cp "$bin" "$apkdir/$NAME"
    local sign_key="${ABUILD_SIGN_KEY:-}"
    if [[ -z "$sign_key" ]]; then
        abuild-keygen -a -n -i 2>/dev/null || true
        sign_key="$(ls "$HOME/.abuild/"*.rsa 2>/dev/null | head -1 || true)"
        [[ -n "$sign_key" ]] || die "could not locate abuild signing key"
    fi
    cat > "$apkdir/APKBUILD" <<APKBUILD
pkgname=${NAME}
pkgver=${VERSION}
pkgrel=0
pkgdesc="${DESCRIPTION}"
url="${URL}"
arch="x86_64"
license="${LICENSE}"
options="!check"
source="${NAME}"
sha512sums="SKIP"

package() {
    install -Dm755 "\${srcdir}/${NAME}" "\${pkgdir}/usr/bin/${NAME}"
}
APKBUILD
    (cd "$apkdir" && PACKAGER_PRIVKEY="$sign_key" REPODEST="$(pwd)/packages" abuild -F checksum >/dev/null && PACKAGER_PRIVKEY="$sign_key" REPODEST="$(pwd)/packages" abuild -F >/dev/null)
    find "$apkdir/packages" -name "*.apk" -exec cp {} "$DIST/" \;
    ok "alpine apk"
}

void() {
    need xbps-create "xbps-install xtools"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local stagedir="$DIST/void/stage"
    mkdir -p "$stagedir/usr/bin"
    install -m 755 "$bin" "$stagedir/usr/bin/$NAME"
    (cd "$stagedir" && xbps-create -A x86_64 -n "${NAME}-${VERSION}_1" -s "${DESCRIPTION}" -l "${LICENSE}" -m "${MAINTAINER}" . >/dev/null)
    find "$stagedir" -maxdepth 1 -name "*.xbps" -exec mv {} "$(pwd)/$DIST/" \;
    ok "void xbps"
}

nix() {
    cat > "$DIST/lush.nix" <<'NIX'
{ lib, rustPlatform, pkg-config }:
rustPlatform.buildRustPackage {
  pname = "lush";
  version = "0.1.0";
  src = ../.;
  cargoLock.lockFile = ../Cargo.lock;
  nativeBuildInputs = [ pkg-config ];
  checkFlags = [ "--skip=repl" ];
  meta = with lib; {
    description = "a Lua-powered shell with native Unix commands";
    homepage = "https://github.com/everett-k/lush";
    license = licenses.gpl3Only;
    mainProgram = "lush";
    platforms = platforms.unix;
  };
}
NIX
    cat > "$DIST/default.nix" <<'NIX'
{ pkgs ? import <nixpkgs> {} }:
pkgs.callPackage ./lush.nix {}
NIX
    ok "nix derivation"
}

linux_static_amd64() {
    build_binary_docker "$T_LINUX_X64" "rust:alpine"
    tar -czf "$DIST/${NAME}-${VERSION}-linux-amd64-static.tar.gz" -C "target/$T_LINUX_X64/release" "$NAME"
    ok "linux amd64 static tarball"
}

linux_static_x86() {
    build_binary_docker "$T_LINUX_X86" "rust:alpine"
    tar -czf "$DIST/${NAME}-${VERSION}-linux-i686-static.tar.gz" -C "target/$T_LINUX_X86/release" "$NAME"
    ok "linux i686 static tarball"
}

linux_static_arm64() {
    build_binary_docker "$T_LINUX_ARM64" "ghcr.io/cross-rs/aarch64-unknown-linux-musl:latest"
    tar -czf "$DIST/${NAME}-${VERSION}-linux-arm64-static.tar.gz" -C "target/$T_LINUX_ARM64/release" "$NAME"
    ok "linux arm64 static tarball"
}

freebsd() {
    build_binary "$T_FREEBSD_X64"
    tar -czf "$DIST/${NAME}-${VERSION}-freebsd-amd64.tar.gz" -C "target/$T_FREEBSD_X64/release" "$NAME"
    ok "freebsd tarball"
}

openbsd() {
    build_binary "$T_OPENBSD_X64"
    tar -czf "$DIST/${NAME}-${VERSION}-openbsd-amd64.tar.gz" -C "target/$T_OPENBSD_X64/release" "$NAME"
    ok "openbsd tarball"
}

appimage() {
    need appimagetool "wget https://github.com/AppImage/AppImageKit/releases/latest/download/appimagetool-x86_64.AppImage"
    build_binary "$T_LINUX_X64"
    local bin="target/$T_LINUX_X64/release/$NAME"
    local appdir="$DIST/appimage/${NAME}.AppDir"
    mkdir -p "$appdir/usr/bin"
    install -m 755 "$bin" "$appdir/usr/bin/$NAME"
    cat > "$appdir/${NAME}.desktop" <<DESKTOP
[Desktop Entry]
Name=Lush
Comment=${DESCRIPTION}
Exec=${NAME}
Icon=${NAME}
Type=Application
Categories=System;TerminalEmulator;
Terminal=true
DESKTOP
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' | base64 -d > "$appdir/${NAME}.png"
    cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
exec "$(dirname "$(readlink -f "$0")")/usr/bin/lush" "$@"
APPRUN
    chmod +x "$appdir/AppRun"
    ARCH=x86_64 appimagetool "$appdir" "$DIST/${NAME}-${VERSION}-x86_64.AppImage" >/dev/null 2>&1
    ok "appimage"
}

_macos_universal() {
    local outbin="$DIST/macos/${NAME}-universal"
    if [[ ! -f "$outbin" ]]; then
        need lipo "requires xcode command line tools"
        build_binary "$T_MACOS_ARM64"
        build_binary "$T_MACOS_X64"
        mkdir -p "$DIST/macos"
        lipo -create "target/$T_MACOS_ARM64/release/$NAME" "target/$T_MACOS_X64/release/$NAME" -output "$outbin"
    fi
}

macos_pkg() {
    need pkgbuild "xcode-select --install"
    _macos_universal
    local stagedir="$DIST/macos/pkg-stage"
    mkdir -p "$stagedir/usr/local/bin"
    install -m 755 "$DIST/macos/${NAME}-universal" "$stagedir/usr/local/bin/$NAME"
    pkgbuild --root "$stagedir" --identifier "sh.lush.${NAME}" --version "${VERSION}" --install-location "/" "$DIST/${NAME}-${VERSION}.pkg" >/dev/null
    ok "macos pkg"
}

macos_dmg() {
    need hdiutil "macos only"
    _macos_universal
    local dmgstage="$DIST/macos/dmg-stage"
    mkdir -p "$dmgstage"
    install -m 755 "$DIST/macos/${NAME}-universal" "$dmgstage/$NAME"
    hdiutil create -volname "Lush ${VERSION}" -srcfolder "$dmgstage" -ov -format UDZO "$DIST/${NAME}-${VERSION}.dmg" >/dev/null
    ok "macos dmg"
}

brew() {
    _macos_universal
    local tarball="$DIST/${NAME}-${VERSION}-macos-universal.tar.gz"
    tar -czf "$tarball" -C "$DIST/macos" "${NAME}-universal"
    local checksum; checksum=$(shasum -a 256 "$tarball" | awk '{print $1}')
    cat > "$DIST/${NAME}.rb" <<RB
class Lush < Formula
  desc "${DESCRIPTION}"
  homepage "${URL}"
  url "https://github.com/everett-k/lush/releases/download/v${VERSION}/${NAME}-${VERSION}-macos-universal.tar.gz"
  sha256 "${checksum}"

  def install
    bin.install "${NAME}-universal" => "${NAME}"
  end
end
RB
    ok "homebrew formula"
}

_procursus_arch() {
    local arch_name="$1"
    local cargo_target="$2"
    need dpkg-deb "apt-get install dpkg-dev"
    build_binary "$cargo_target"
    local bin="target/$cargo_target/release/$NAME"
    local prefix="opt/procursus"
    local pkgroot="$DIST/procursus/${NAME}_${VERSION}_${arch_name}"
    mkdir -p "$pkgroot/$prefix/bin" "$pkgroot/$prefix/share/doc/$NAME" "$pkgroot/DEBIAN"
    install -m 755 "$bin" "$pkgroot/$prefix/bin/$NAME"
    echo "${LICENSE}" > "$pkgroot/$prefix/share/doc/$NAME/copyright"
    local kib; kib="$(du -sk "$pkgroot/$prefix" | cut -f1)"
    cat > "$pkgroot/DEBIAN/control" <<CONTROL
Package: ${NAME}
Version: ${VERSION}
Architecture: ${arch_name}
Section: Shells
Priority: optional
Installed-Size: ${kib}
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
CONTROL
    dpkg-deb --build --root-owner-group "$pkgroot" "$DIST/${NAME}_${VERSION}_${arch_name}.deb" >/dev/null
    ok "procursus $arch_name deb"
}

procursus_arm64() { _procursus_arch "darwin-arm64" "$T_MACOS_ARM64"; }
procursus_amd64() { _procursus_arch "darwin-amd64" "$T_MACOS_X64"; }

windows_msi() {
    need cargo-wix "cargo install cargo-wix"
    need candle "install wix toolset v3"
    ensure_target "$T_WIN_X64"
    [[ ! -f "wix/main.wxs" ]] && cargo wix init --force >/dev/null
    cargo wix --target "$T_WIN_X64" --nocapture --output "$DIST/${NAME}-${VERSION}-x86_64.msi" >/dev/null
    ok "windows msi"
}

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

ALL_TARGETS=(
    docker_build
    rhel suse arch deb alpine void nix
    linux_static_amd64 linux_static_x86 linux_static_arm64
    freebsd openbsd
    appimage macos_pkg macos_dmg brew
    procursus_arm64 procursus_amd64
    windows_msi windows_portable windows32_portable windows_arm64_portable
)

TARGETS=("$@")
[[ ${#TARGETS[@]} -eq 0 ]] && TARGETS=("${ALL_TARGETS[@]}")

SUCCESSES=()
FAILURES=()

for target in "${TARGETS[@]}"; do
    fn="${target//-/_}"
    if declare -f "$fn" >/dev/null; then
        if (set -e; "$fn"); then
            SUCCESSES+=("$target")
        else
            FAILURES+=("$target")
        fi
    else
        warn "unknown target: $target"
        FAILURES+=("$target")
    fi
done

echo
if [[ ${#SUCCESSES[@]} -gt 0 ]]; then
    echo -e "${GREEN}passed${NC}"
    for s in "${SUCCESSES[@]}"; do echo "  $s"; done
    echo
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo -e "${RED}failed${NC}"
    for f in "${FAILURES[@]}"; do echo "  $f"; done
    exit 1
fi

echo -e "${CYAN}all done — output in ./$DIST/${NC}"
