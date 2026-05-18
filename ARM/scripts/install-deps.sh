#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not found. Run this on Raspberry Pi OS / Debian arm64." >&2
    exit 1
fi

$SUDO apt-get update
$SUDO apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    erlang \
    erlang-dev \
    erlang-os-mon \
    erlang-ssl \
    erlang-tools \
    libssl-dev \
    libgmp-dev \
    libtss2-dev \
    pkg-config \
    python3 \
    rebar3 \
    rustc \
    cargo

echo "ARM/Raspberry Pi OS dependencies installed."
