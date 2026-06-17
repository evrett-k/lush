#!/bin/bash
# run to automatically install procursus ( apt / dpkg ) onto macOS
# installs to /opt/procursus/ and adds bin to path

if [ -d "/opt/procursus" ]; then
    echo "procursus is already installed"
    exit 1
fi

if [ "$whoami" !="root"]; then
    echo "please run as root"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "arm64e" ]; then
    URL="https://apt.procurs.us/bootstraps/big_sur/bootstrap-darwin-arm64.tar.zst"
else
    URL="https://apt.procurs.us/bootstraps/big_sur/bootstrap-darwin-amd64.tar.zst"
fi

curl -L -o /tmp/bootstrap.tar.zst "$URL"
tar --zstd -xf /tmp/bootstrap.tar.zst -C /
echo 'export PATH="/opt/procursus/bin:$PATH"' >> ~/.zshrc
rm /tmp/bootstrap.tar.zst
