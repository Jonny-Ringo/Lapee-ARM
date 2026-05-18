# LapEE ARM Port for Raspberry Pi 4

This directory is the Raspberry Pi OS / Raspbian ARM64 port layer for the
imported LapEE project in `../upstream-lapee`.

The upstream project builds a full x86_64 UEFI laptop appliance image with
Buildroot, Secure Boot, TPM 2.0 measured boot, and a signed UKI at
`EFI/Boot/BootX64.efi`. A Raspberry Pi 4 running Raspberry Pi OS is a different
target:

- CPU: ARM64, not x86_64.
- Boot path: Raspberry Pi firmware, not PC UEFI by default.
- Runtime OS: Debian/Raspberry Pi OS packages, not Buildroot initramfs.
- TPM/TME: no built-in PC TPM or Intel TME/AMD SME. A discrete TPM HAT can be
  added later, but the default Pi 4 path is a non-attested HyperBEAM node.

So this port does not claim LapEE-equivalent attestation. It rebuilds the
LapEE-flavored HyperBEAM runtime natively on ARM64, stages the LapEE overlay,
and runs it as a systemd service on Raspberry Pi OS.

## Layout

```text
ARM/
  Makefile
  config/lapee-arm.json
  scripts/install-deps.sh
  scripts/build-hyperbeam.sh
  scripts/run-hyperbeam.sh
  scripts/install-service.sh
  systemd/lapee-hyperbeam.service
```

Build output goes under `ARM/build/` and installed runtime files go under:

```text
/opt/lapee-arm/hyperbeam
/etc/lapee-arm/lapee-arm.json
```

## Quick Start on Raspberry Pi OS 64-bit

Run these commands on the Pi:

```sh
cd /path/to/Lapee-ARM/ARM
make deps
make build
sudo make install
sudo systemctl enable --now lapee-hyperbeam
```

Then check:

```sh
systemctl status lapee-hyperbeam
curl http://127.0.0.1:8734/~meta@1.0/info
curl http://127.0.0.1:8734/~system@1.0/all
```

If you have no TPM, TPM endpoints are expected to be unavailable or degraded.
The service sets `LAPEE_TPM_ALLOW_NO_NIF=1` so the overlay can load for
development and non-attested operation.

## Build Notes

The build script:

1. Clones pinned HyperBEAM from `https://github.com/permaweb/HyperBEAM`.
2. Checks out the same `HYPERBEAM_VERSION` used by upstream LapEE.
3. Stages `../upstream-lapee/hyperbeam-overlay` into the checkout.
4. Builds `./rebar3 as lapee release` natively for ARM64.

If the Pi has limited RAM, add swap before building. HyperBEAM and native NIF
dependencies are not tiny.

## Attestation Status

This first ARM port is "LapEE-inspired", not a replacement for the x86 laptop
image. Preserved:

- LapEE HyperBEAM overlay modules.
- `system@1.0` machine-report surface.
- `green-zone@1.0` and related overlay code where it does not require unavailable
  hardware.
- The operator config layering model through `HB_CONFIG`.

Changed:

- No UKI, Secure Boot enrollment, PCR-15 measured boot, or TME/SME gate.
- No USB image builder yet.
- No default TPM-backed boot attestation on a stock Pi 4.

Next useful work is a Pi image-builder path that starts from Raspberry Pi OS
Lite arm64, installs this runtime into the root filesystem, and optionally
supports a TPM HAT with `LAPEE_TPM_TCTI=device:/dev/tpm0`.
