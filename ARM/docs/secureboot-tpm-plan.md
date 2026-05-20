# Secure Boot / TPM Plan for Raspberry Pi LapEE ARM

This branch is for work that may break the easy Raspberry Pi OS runtime path.
`main` stays the known-good ARM node/display build.

## Goal

Build a Raspberry Pi variant that can make a LapEE-style attestation claim:

- the boot chain only accepted trusted code,
- the running HyperBEAM node is bound to that boot chain,
- the node can return signed evidence that a verifier can check remotely.

This is not automatically true just because HyperBEAM runs on a Pi. A stock Pi 4
does not have the same PC UEFI + TPM measured-boot model as the original LapEE
laptop target.

## Candidate Secure Boot Base

`raspberrypi/rpi-sb-provisioner` is the likely starting point for provisioning
Raspberry Pi secure boot. It appears useful for:

- generating/provisioning signed Raspberry Pi boot images,
- managing device-specific secure-boot material,
- producing a repeatable provisioning workflow instead of hand-editing EEPROM
  state.

Secure boot by itself is not a TPM quote. It can prove the device only boots
signed firmware/boot artifacts, but a remote verifier still needs fresh,
signed evidence from the running device.

## What We Need To Add

0. Reproducible Pi image builder

   The first step is an image that boots with the working LapEE ARM runtime
   already installed. This is now staged under `ARM/image/` and the public
   targets are:

   ```text
   make runtime-tarball
   sudo make image BASE_IMAGE=/path/to/raspios-arm64.img
   ```

   This is not the attestation boundary yet. It gives us the artifact that the
   secure-boot/TPM work can lock down and measure.

1. Secure boot image path

   Build a Pi boot image whose firmware, kernel, initramfs, cmdline, and rootfs
   trust boundary are controlled. The runtime must not be able to silently
   replace the node/config after boot.

2. TPM hardware path

   Use a TPM 2.0 HAT or other supported TPM device exposed at `/dev/tpm0`.
   The current ARM service already sets:

   ```text
   LAPEE_TPM_TCTI=device:/dev/tpm0
   ```

   but on a stock Pi with no TPM this only degrades gracefully.

3. Measured boot bridge

   Add an early trusted measurement step that extends PCRs with:

   - secure-boot policy/version,
   - kernel/initramfs/cmdline hashes,
   - rootfs or dm-verity root hash,
   - `/etc/lapee-arm/lapee-arm.json`,
   - HyperBEAM release hash,
   - node operator identity/address.

   This step must run from code protected by the secure boot chain. Otherwise a
   modified OS could fake the measurements.

4. Attestation endpoint

   Extend the ARM runtime so a verifier can request:

   ```text
   GET /~measurement@1.0/info
   GET /~measurement@1.0/boot
   GET /~measurement@1.0/fresh?nonce=<nonce>
   ```

   and receive a TPM quote plus event log that includes the Pi secure-boot
   claims and the HyperBEAM node identity.

5. Verifier policy

   Add a Pi-specific verifier profile. It should not pretend to be the original
   UEFI laptop profile. It should say something like:

   ```text
   platform: raspberry-pi-secureboot-tpm
   secure-boot: raspberry-pi
   measured-boot: tpm2-pcr-policy
   lapee-equivalence: arm-profile
   ```

## Acceptance Criteria

Before calling this LapEE-equivalent for the Pi, we need all of these:

- secure boot is enabled and locked/provisioned,
- unsigned boot artifacts fail to boot,
- TPM 2.0 quote works with a verifier nonce,
- PCR/event log includes the HyperBEAM release/config/operator address,
- changing the runtime, config, or node identity changes the attested evidence,
- `make smoke` passes after the attested boot.

Until then, the honest claim is:

```text
LapEE ARM node with Raspberry Pi secure-boot/TPM work in progress.
```
