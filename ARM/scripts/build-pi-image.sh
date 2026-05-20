#!/usr/bin/env bash
set -euo pipefail

ARM_ROOT="${ARM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(cd "$ARM_ROOT/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ARM_ROOT/build}"

BASE_IMAGE="${BASE_IMAGE:-}"
OUT_IMAGE="${OUT_IMAGE:-$BUILD_DIR/images/lapee-arm-pi-alpha.img}"
RUNTIME_TARBALL="${RUNTIME_TARBALL:-$BUILD_DIR/images/lapee-arm-runtime.tar.gz}"
EXTRA_SIZE_MB="${EXTRA_SIZE_MB:-4096}"
INSTALL_RUNTIME_DEPS="${INSTALL_RUNTIME_DEPS:-1}"
COPY_REPO="${COPY_REPO:-1}"
REPO_DEST="${REPO_DEST:-/opt/lapee-arm-src}"

if [ "$(id -u)" -ne 0 ]; then
    echo "build-pi-image.sh must run as root. Use: sudo make image BASE_IMAGE=/path/to/raspios.img" >&2
    exit 1
fi

if [ -z "$BASE_IMAGE" ]; then
    cat >&2 <<EOF
BASE_IMAGE is required.

Example:
  sudo make image BASE_IMAGE=/path/to/raspios-bookworm-arm64.img

Build and package the runtime first:
  make build
  make runtime-tarball
EOF
    exit 1
fi

if [ ! -f "$BASE_IMAGE" ]; then
    echo "Base image not found: $BASE_IMAGE" >&2
    exit 1
fi

if [ ! -f "$RUNTIME_TARBALL" ]; then
    echo "Runtime tarball not found: $RUNTIME_TARBALL" >&2
    echo "Run: make runtime-tarball" >&2
    exit 1
fi

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        echo "Run: sudo make image-deps" >&2
        exit 1
    fi
}

require_cmd losetup
require_cmd mount
require_cmd rsync
require_cmd tar
require_cmd xargs
require_cmd sha256sum
require_cmd chroot
require_cmd cp
require_cmd truncate
require_cmd growpart
require_cmd partprobe
require_cmd resize2fs
require_cmd e2fsck

mkdir -p "$(dirname "$OUT_IMAGE")"

case "$BASE_IMAGE" in
    *.xz)
        require_cmd xz
        echo "Decompressing base image..."
        xz -dc "$BASE_IMAGE" > "$OUT_IMAGE"
        ;;
    *)
        echo "Copying base image..."
        cp --sparse=always "$BASE_IMAGE" "$OUT_IMAGE"
        ;;
esac

LOOP=""
ROOT_MNT=""
BOUND_MOUNTS=""
BOOT_MOUNTED=0

cleanup() {
    set +e
    for mountpoint in $BOUND_MOUNTS; do
        umount "$mountpoint" >/dev/null 2>&1
    done
    if [ "$BOOT_MOUNTED" = "1" ] && [ -n "$ROOT_MNT" ]; then
        umount "$ROOT_MNT/boot/firmware" >/dev/null 2>&1 || umount "$ROOT_MNT/boot" >/dev/null 2>&1
    fi
    if [ -n "$ROOT_MNT" ]; then
        umount "$ROOT_MNT" >/dev/null 2>&1
        rmdir "$ROOT_MNT" >/dev/null 2>&1
    fi
    if [ -n "$LOOP" ]; then
        losetup -d "$LOOP" >/dev/null 2>&1
    fi
}
trap cleanup EXIT

if [ "$EXTRA_SIZE_MB" -gt 0 ]; then
    echo "Expanding image by ${EXTRA_SIZE_MB} MiB..."
    truncate -s +"${EXTRA_SIZE_MB}M" "$OUT_IMAGE"
fi

LOOP="$(losetup --show -Pf "$OUT_IMAGE")"
sleep 1

part_path() {
    if [ -e "${LOOP}p$1" ]; then
        printf '%s\n' "${LOOP}p$1"
    else
        printf '%s\n' "${LOOP}$1"
    fi
}

BOOT_PART="$(part_path 1)"
ROOT_PART="$(part_path 2)"

if [ "$EXTRA_SIZE_MB" -gt 0 ]; then
    growpart "$LOOP" 2
    partprobe "$LOOP" >/dev/null 2>&1 || true
    e2fsck -fy "$ROOT_PART"
    resize2fs "$ROOT_PART"
fi

ROOT_MNT="$(mktemp -d)"
mount "$ROOT_PART" "$ROOT_MNT"

if [ -d "$ROOT_MNT/boot/firmware" ]; then
    mount "$BOOT_PART" "$ROOT_MNT/boot/firmware"
    BOOT_MOUNTED=1
elif [ -d "$ROOT_MNT/boot" ]; then
    mount "$BOOT_PART" "$ROOT_MNT/boot"
    BOOT_MOUNTED=1
fi

if [ "$INSTALL_RUNTIME_DEPS" = "1" ]; then
    echo "Installing runtime dependencies into image..."
    if [ "$(uname -m)" != "aarch64" ] && [ -x /usr/bin/qemu-aarch64-static ]; then
        install -m 0755 /usr/bin/qemu-aarch64-static "$ROOT_MNT/usr/bin/qemu-aarch64-static"
    fi

    for mp in dev proc sys; do
        mount --bind "/$mp" "$ROOT_MNT/$mp"
        BOUND_MOUNTS="$ROOT_MNT/$mp $BOUND_MOUNTS"
    done

    cp /etc/resolv.conf "$ROOT_MNT/etc/resolv.conf"
    install -m 0644 "$ARM_ROOT/image/apt-runtime-packages.txt" \
        "$ROOT_MNT/tmp/lapee-arm-runtime-packages.txt"
    chroot "$ROOT_MNT" env DEBIAN_FRONTEND=noninteractive apt-get update
    xargs chroot "$ROOT_MNT" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        < "$ROOT_MNT/tmp/lapee-arm-runtime-packages.txt"
    rm -f "$ROOT_MNT/tmp/lapee-arm-runtime-packages.txt"
fi

echo "Installing LapEE ARM runtime..."
tar -xzf "$RUNTIME_TARBALL" -C "$ROOT_MNT"

echo "Installing helper commands..."
install -d "$ROOT_MNT/usr/local/bin"
install -m 0755 "$ARM_ROOT/image/bin/lapee-arm-start-node" "$ROOT_MNT/usr/local/bin/lapee-arm-start-node"
install -m 0755 "$ARM_ROOT/image/bin/lapee-arm-stop" "$ROOT_MNT/usr/local/bin/lapee-arm-stop"
install -m 0755 "$ARM_ROOT/image/bin/lapee-arm-smoke" "$ROOT_MNT/usr/local/bin/lapee-arm-smoke"

if [ "$COPY_REPO" = "1" ]; then
    echo "Copying source tree into image at $REPO_DEST..."
    install -d "$ROOT_MNT$REPO_DEST"
    rsync -a \
        --exclude '.git/' \
        --exclude '.repo-git/' \
        --exclude 'ARM/build/' \
        --exclude 'build/' \
        --exclude '*.img' \
        --exclude '*.img.sha256' \
        --exclude '*.img.sig' \
        "$REPO_ROOT/" "$ROOT_MNT$REPO_DEST/"
fi

cat > "$ROOT_MNT/etc/lapee-arm-image.txt" <<EOF
LapEE ARM Raspberry Pi image
created-utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
runtime-tarball=$(basename "$RUNTIME_TARBALL")
source-dest=$REPO_DEST

Manual start:
  lapee-arm-start-node

Health check:
  lapee-arm-smoke

Stop:
  lapee-arm-stop
EOF

cat >> "$ROOT_MNT/etc/motd" <<'EOF'

LapEE ARM alpha image installed.
Start node/display manually: lapee-arm-start-node
Smoke test:                  lapee-arm-smoke
Stop node/display:           lapee-arm-stop

EOF

sync
cleanup
trap - EXIT
set -e

sha256sum "$OUT_IMAGE" > "$OUT_IMAGE.sha256"

echo "Image written: $OUT_IMAGE"
cat "$OUT_IMAGE.sha256"
