# LapEE ARM Raspberry Pi Image Builder

This is the first image-builder path for the `Secureboot-TPM` branch.

It does not yet produce a secure-boot-provisioned or TPM-attested image. It
does produce a Raspberry Pi OS image with the working LapEE ARM HyperBEAM
runtime installed, helper commands added, and the source tree copied into
`/opt/lapee-arm-src`.

## Build Flow

Run on a Raspberry Pi 4/5 or a Linux arm64 host when possible. Cross-building
from x86_64 may work if `qemu-user-static` and binfmt are configured, but the
native Pi path is the least surprising.

1. Build and package the working runtime:

   ```sh
   cd ~/Lapee-ARM/ARM
   make deps
   make build
   make runtime-tarball
   ```

2. Install image-builder dependencies on the host:

   ```sh
   sudo make image-deps
   ```

3. Build an image from a Raspberry Pi OS arm64 base image:

   ```sh
   sudo make image BASE_IMAGE=/path/to/raspios-arm64.img
   ```

   The output defaults to:

   ```text
   ARM/build/images/lapee-arm-pi-alpha.img
   ARM/build/images/lapee-arm-pi-alpha.img.sha256
   ```

## Useful Options

```sh
sudo make image \
  BASE_IMAGE=/path/to/raspios-arm64.img \
  OUT_IMAGE=build/images/lapee-arm-pi-alpha.img \
  RUNTIME_TARBALL=build/images/lapee-arm-runtime.tar.gz \
  EXTRA_SIZE_MB=4096
```

Set `INSTALL_RUNTIME_DEPS=0` if the base image already has the runtime/display
packages you need and you want to skip chroot apt work.

Set `COPY_REPO=0` if you only want the installed runtime and do not want
`/opt/lapee-arm-src` in the image.

## Image Commands

After flashing and booting the image, start the node/display manually:

```sh
lapee-arm-start-node
```

Run the smoke test:

```sh
lapee-arm-smoke
```

Stop the node/display:

```sh
lapee-arm-stop
```

## Next Secure Boot / TPM Layer

This image builder is phase 0. The next branch work is to feed this image into
the Raspberry Pi secure-boot provisioning flow, add a TPM HAT path, and bind the
HyperBEAM runtime/config/operator identity into TPM evidence.

