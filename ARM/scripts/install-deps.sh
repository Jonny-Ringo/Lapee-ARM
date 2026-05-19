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
    clang \
    cmake \
    curl \
    git \
    erlang \
    erlang-dev \
    erlang-os-mon \
    erlang-ssl \
    erlang-tools \
    libclang-dev \
    libssl-dev \
    libgmp-dev \
    libtss2-dev \
    pkg-config \
    protobuf-compiler \
    python3 \
    rebar3 \
    rustc \
    cargo

echo "ARM/Raspberry Pi OS dependencies installed."
