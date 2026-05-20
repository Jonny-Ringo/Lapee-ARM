#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not found. Run this on Debian/Raspberry Pi OS." >&2
    exit 1
fi

$SUDO apt-get update
$SUDO apt-get install -y \
    binfmt-support \
    ca-certificates \
    cloud-guest-utils \
    dosfstools \
    e2fsprogs \
    file \
    parted \
    qemu-user-static \
    rsync \
    util-linux \
    xz-utils

echo "LapEE ARM image-builder dependencies installed."
