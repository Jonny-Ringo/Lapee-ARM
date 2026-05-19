#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
REL_DIR="${REL_DIR:-$BUILD_DIR/hyperbeam-src/_build/lapee/rel/hb}"
CONFIG="${CONFIG:-$ARM_ROOT/config/lapee-arm.json}"

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

if ! REL_DIR=$(find_release_dir); then
    echo "HyperBEAM release missing. Run: make build" >&2
    echo "Looked under: $BUILD_DIR" >&2
    exit 1
fi

if command -v systemctl >/dev/null 2>&1 &&
   systemctl is-active --quiet lapee-hyperbeam.service; then
    echo "lapee-hyperbeam.service is already running." >&2
    echo "Stop it before foreground debugging: sudo make stop" >&2
    exit 1
fi

export HB_CONFIG="${HB_CONFIG:-$CONFIG}"
export HB_MODE="${HB_MODE:-debug}"
export LAPEE_TPM_ALLOW_NO_NIF="${LAPEE_TPM_ALLOW_NO_NIF:-1}"
export LAPEE_TPM_TCTI="${LAPEE_TPM_TCTI:-device:/dev/tpm0}"

cd "$REL_DIR"
exec ./bin/hb foreground
