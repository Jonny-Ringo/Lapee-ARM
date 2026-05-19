#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/lapee-arm}"
CONFIG_DIR="${CONFIG_DIR:-/etc/lapee-arm}"
REL_DIR="${REL_DIR:-$BUILD_DIR/hyperbeam-src/_build/lapee/rel/hb}"

find_release_dir() {
    if [ -x "$REL_DIR/bin/hb" ]; then
        printf '%s\n' "$REL_DIR"
        return 0
    fi
    found=$(find "$BUILD_DIR" -path '*/bin/hb' -type f 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then
        chmod +x "$found" 2>/dev/null || true
        dirname "$(dirname "$found")"
        return 0
    fi
    return 1
}

if [ "$(id -u)" -ne 0 ]; then
    echo "install-service.sh must run as root. Use: sudo make install" >&2
    exit 1
fi

if ! REL_DIR=$(find_release_dir); then
    echo "HyperBEAM release missing. Run: make build first." >&2
    echo "Looked under: $BUILD_DIR" >&2
    exit 1
fi

install -d "$INSTALL_PREFIX" "$CONFIG_DIR" /etc/systemd/system
rm -rf "$INSTALL_PREFIX/hyperbeam"
cp -a "$REL_DIR" "$INSTALL_PREFIX/hyperbeam"
install -m 0644 "$ARM_ROOT/config/lapee-arm.json" "$CONFIG_DIR/lapee-arm.json"
install -m 0644 "$ARM_ROOT/systemd/lapee-hyperbeam.service" /etc/systemd/system/lapee-hyperbeam.service
install -d "$INSTALL_PREFIX/splash"
install -m 0644 "$ARM_ROOT/../upstream-lapee/buildroot-external/board/lapee/files/lapee_splash.erl" \
    "$INSTALL_PREFIX/splash/lapee_splash.erl"
erlc -o "$INSTALL_PREFIX/splash" "$INSTALL_PREFIX/splash/lapee_splash.erl"
install -m 0644 "$ARM_ROOT/systemd/lapee-splash.service" /etc/systemd/system/lapee-splash.service

systemctl daemon-reload
echo "Installed. Start with: systemctl enable --now lapee-hyperbeam"
echo "Optional display service, start manually only: systemctl start lapee-splash"
