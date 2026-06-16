#!/usr/bin/env bash
# github-build.sh
# A targeted build script for GitHub Actions

set -euo pipefail

# This script simply dispatches to the main build.sh logic
# but is explicitly designed to handle the specific targets that 
# work in a clean CI environment.

# If a target fails, we log it but continue building others
targets=(
    "linux-static-amd64"
    "linux-static-x86"
    "linux-static-arm64"
    "deb"
    "rhel"
    "suse"
    "nix"
    "freebsd"
    "openbsd"
    "procursus-arm64"
    "procursus-amd64"
    "windows-portable"
    "windows32-portable"
    "windows-arm64-portable"
)

echo "Running targeted CI builds..."
for target in "${targets[@]}"; do
    echo "Building $target..."
    if ./build.sh "$target"; then
        echo "  ✓ $target passed"
    else
        echo "  ✗ $target failed"
    fi
done
