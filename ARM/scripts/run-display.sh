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
PROFILE_DIR="${LAPEE_CHROMIUM_PROFILE:-/tmp/lapee-arm-chromium}"
DISPLAY_LOG="${LAPEE_DISPLAY_LOG:-/tmp/lapee-arm-display.log}"
if [ -f "$CONFIG" ]; then
    DEVICE_COUNT=$(grep -c '"name":' "$CONFIG" || true)
else
    DEVICE_COUNT=0
fi
if [ "$OPERATOR" = "unknown" ] && command -v journalctl >/dev/null 2>&1; then
    for _ in 1 2 3 4 5; do
        OPERATOR=$(
            journalctl -u lapee-hyperbeam -n 120 --no-pager 2>/dev/null |
                sed -n 's/.*Operator:[[:space:]]*//p' |
                awk 'NF {print $1}' |
                tail -n 1
        )
        [ -n "$OPERATOR" ] && break
        sleep 1
    done
    OPERATOR="${OPERATOR:-unknown}"
fi
URL="${URL}?operator=$OPERATOR&devices=$DEVICE_COUNT"

if command -v xset >/dev/null 2>&1; then
    xset s off -dpms s noblank >/dev/null 2>&1 || true
fi

FLAGS=(
    --kiosk
    --no-first-run
    --noerrdialogs
    --disable-infobars
    --disable-background-networking
    --disable-component-update
    --disable-default-apps
    --disable-extensions
    --disable-gpu
    --disable-notifications
    --disable-software-rasterizer=false
    --disable-sync
    --disable-translate
    --disable-component-extensions-with-background-pages
    --disable-domain-reliability
    --disable-logging
    --disable-features=MediaRouter,OptimizationHints,PushMessaging
    --disable-session-crashed-bubble
    --log-level=3
    --metrics-recording-only
    --password-store=basic
    --use-gl=swiftshader
    --user-data-dir="$PROFILE_DIR"
    --app="$URL"
)

if command -v pkill >/dev/null 2>&1; then
    pkill -f "$PROFILE_DIR" >/dev/null 2>&1 || true
    sleep 1
fi

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    export XAUTHORITY="${XAUTHORITY:-$USER_HOME/.Xauthority}"
    CMD=(sudo -u "$SUDO_USER" env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" "$BROWSER" "${FLAGS[@]}")
else
    CMD=("$BROWSER" "${FLAGS[@]}")
fi

if [ "${LAPEE_DISPLAY_DETACH:-0}" = "1" ]; then
    nohup "${CMD[@]}" >"$DISPLAY_LOG" 2>&1 &
    echo "Display started in kiosk mode. Log: $DISPLAY_LOG"
    exit 0
fi

exec "${CMD[@]}"
