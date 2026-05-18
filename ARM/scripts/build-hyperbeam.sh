#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
UPSTREAM_ROOT="${UPSTREAM_ROOT:-$(cd "$ARM_ROOT/../upstream-lapee" && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
HYPERBEAM_REPO="${HYPERBEAM_REPO:-https://github.com/permaweb/HyperBEAM.git}"
HYPERBEAM_VERSION="${HYPERBEAM_VERSION:-$(awk -F'\\?= ' '/^HYPERBEAM_VERSION/ {print $2; exit}' "$UPSTREAM_ROOT/buildroot-external/package/hyperbeam/hyperbeam.mk")}"
SRC_DIR="${HYPERBEAM_SRC:-$BUILD_DIR/hyperbeam-src}"
REL_DIR="$SRC_DIR/_build/lapee/rel/hb"

find_release_dir() {
    if [ -x "$REL_DIR/bin/hb" ]; then
        printf '%s\n' "$REL_DIR"
        return 0
    fi
    found=$(find "$SRC_DIR/_build" -path '*/bin/hb' -type f 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then
        chmod +x "$found" 2>/dev/null || true
        dirname "$(dirname "$found")"
        return 0
    fi
    return 1
}

mkdir -p "$BUILD_DIR"

if [ ! -d "$SRC_DIR/.git" ]; then
    git clone "$HYPERBEAM_REPO" "$SRC_DIR"
fi

git -C "$SRC_DIR" fetch --tags origin
git -C "$SRC_DIR" checkout --detach "$HYPERBEAM_VERSION"
git -C "$SRC_DIR" submodule update --init --recursive

LAPEE_HB_OVERLAY_DIR="$UPSTREAM_ROOT/hyperbeam-overlay" \
    sh "$UPSTREAM_ROOT/scripts/stage-hyperbeam-overlay.sh" "$SRC_DIR"

if ! command -v rebar3 >/dev/null 2>&1; then
    curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o "$SRC_DIR/rebar3"
    chmod +x "$SRC_DIR/rebar3"
    REBAR="$SRC_DIR/rebar3"
else
    REBAR=rebar3
fi

export LAPEE_TSS2_PREFIX="${LAPEE_TSS2_PREFIX:-/usr}"
export CFLAGS="${CFLAGS:-} -Wno-error=incompatible-pointer-types"
export OPENSSL_DIR="${OPENSSL_DIR:-/usr}"
export OPENSSL_NO_VENDOR=1

cd "$SRC_DIR"
"$REBAR" as lapee compile
"$REBAR" as lapee release

REL_DIR=$(find_release_dir) || {
    echo "HyperBEAM release command finished, but no rel/hb/bin/hb was found under $SRC_DIR/_build." >&2
    exit 1
}
echo "HyperBEAM ARM release built at $REL_DIR"
