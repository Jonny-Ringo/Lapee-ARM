#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/lapee-arm}"
CONFIG_DIR="${CONFIG_DIR:-/etc/lapee-arm}"
REL_DIR="${REL_DIR:-$BUILD_DIR/hyperbeam-src/_build/lapee/rel/hb}"

if [ "$(id -u)" -ne 0 ]; then
    echo "install-service.sh must run as root. Use: sudo make install" >&2
    exit 1
fi

if [ ! -x "$REL_DIR/bin/hb" ]; then
    echo "HyperBEAM release missing. Run: make build first." >&2
    exit 1
fi

install -d "$INSTALL_PREFIX" "$CONFIG_DIR" /etc/systemd/system
rm -rf "$INSTALL_PREFIX/hyperbeam"
cp -a "$REL_DIR" "$INSTALL_PREFIX/hyperbeam"
install -m 0644 "$ARM_ROOT/config/lapee-arm.json" "$CONFIG_DIR/lapee-arm.json"
install -m 0644 "$ARM_ROOT/systemd/lapee-hyperbeam.service" /etc/systemd/system/lapee-hyperbeam.service

systemctl daemon-reload
echo "Installed. Start with: systemctl enable --now lapee-hyperbeam"
