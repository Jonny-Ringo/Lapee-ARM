#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
REL_DIR="${REL_DIR:-$BUILD_DIR/hyperbeam-src/_build/lapee/rel/hb}"
CONFIG="${CONFIG:-$ARM_ROOT/config/lapee-arm.json}"

if [ ! -x "$REL_DIR/bin/hb" ]; then
    echo "HyperBEAM release missing. Run: make build" >&2
    exit 1
fi

export HB_CONFIG="${HB_CONFIG:-$CONFIG}"
export HB_MODE="${HB_MODE:-debug}"
export LAPEE_TPM_ALLOW_NO_NIF="${LAPEE_TPM_ALLOW_NO_NIF:-1}"
export LAPEE_TPM_TCTI="${LAPEE_TPM_TCTI:-device:/dev/tpm0}"

cd "$REL_DIR"
exec ./bin/hb foreground
