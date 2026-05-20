#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"
REL_DIR="${REL_DIR:-$BUILD_DIR/hyperbeam-src/_build/lapee/rel/hb}"
OUT_TARBALL="${OUT_TARBALL:-$BUILD_DIR/images/lapee-arm-runtime.tar.gz}"

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

if ! REL_DIR="$(find_release_dir)"; then
    echo "HyperBEAM release missing. Run: make build" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT_TARBALL")"
STAGE="$(mktemp -d)"
cleanup() {
    rm -rf "$STAGE"
}
trap cleanup EXIT

install -d \
    "$STAGE/opt/lapee-arm/bin" \
    "$STAGE/opt/lapee-arm/display" \
    "$STAGE/etc/lapee-arm" \
    "$STAGE/etc/systemd/system"

cp -a "$REL_DIR" "$STAGE/opt/lapee-arm/hyperbeam"
install -m 0755 "$ARM_ROOT/scripts/run-display.sh" "$STAGE/opt/lapee-arm/bin/lapee-display"
install -m 0644 "$ARM_ROOT/display/index.html" "$STAGE/opt/lapee-arm/display/index.html"
if [ -f "$ARM_ROOT/display/Example_Pi_4.jpg" ]; then
    install -m 0644 "$ARM_ROOT/display/Example_Pi_4.jpg" "$STAGE/opt/lapee-arm/display/Example_Pi_4.jpg"
fi
install -m 0644 "$ARM_ROOT/config/lapee-arm.json" "$STAGE/etc/lapee-arm/lapee-arm.json"
install -m 0644 "$ARM_ROOT/systemd/lapee-hyperbeam.service" \
    "$STAGE/etc/systemd/system/lapee-hyperbeam.service"

COMMIT="$(git -C "$ARM_ROOT/.." rev-parse --short HEAD 2>/dev/null || printf unknown)"
cat > "$STAGE/etc/lapee-arm/image-runtime.txt" <<EOF
LapEE ARM runtime package
source-commit=$COMMIT
created-utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
release-dir=$REL_DIR
EOF

tar -C "$STAGE" -czf "$OUT_TARBALL" .
sha256sum "$OUT_TARBALL" > "$OUT_TARBALL.sha256"

echo "Runtime package: $OUT_TARBALL"
cat "$OUT_TARBALL.sha256"
