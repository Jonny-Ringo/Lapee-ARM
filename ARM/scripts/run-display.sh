#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/lapee-arm}"

if [ -f "$INSTALL_PREFIX/display/index.html" ]; then
    DISPLAY_FILE="$INSTALL_PREFIX/display/index.html"
else
    DISPLAY_FILE="$ARM_ROOT/display/index.html"
fi

if [ ! -f "$DISPLAY_FILE" ]; then
    echo "LapEE display page missing: $DISPLAY_FILE" >&2
    exit 1
fi

BROWSER="${LAPEE_BROWSER:-}"
if [ -z "$BROWSER" ]; then
    for candidate in chromium chromium-browser google-chrome; do
        if command -v "$candidate" >/dev/null 2>&1; then
            BROWSER="$candidate"
            break
        fi
    done
fi

if [ -z "$BROWSER" ]; then
    cat >&2 <<EOF
No browser found. Install Chromium on Raspberry Pi OS:
  sudo apt-get install -y chromium
EOF
    exit 1
fi

URL="file://$DISPLAY_FILE"
export DISPLAY="${DISPLAY:-:0}"
OPERATOR="${LAPEE_OPERATOR:-unknown}"
CONFIG="${LAPEE_CONFIG:-/etc/lapee-arm/lapee-arm.json}"
if [ -f "$CONFIG" ]; then
    DEVICE_COUNT=$(grep -c '"name":' "$CONFIG" || true)
else
    DEVICE_COUNT=0
fi
URL="${URL}?operator=$OPERATOR&devices=$DEVICE_COUNT"

FLAGS=(
    --kiosk
    --noerrdialogs
    --disable-infobars
    --disable-gpu
    --disable-software-rasterizer=false
    --use-gl=swiftshader
    --app="$URL"
)

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    export XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}"
    exec sudo -u "$SUDO_USER" env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
        "$BROWSER" "${FLAGS[@]}"
fi

exec "$BROWSER" "${FLAGS[@]}"
