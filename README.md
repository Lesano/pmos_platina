# Xiaomi Mi 8 Lite (platina) on postmarketOS – mainline notes

Work-in-progress notes and patches for running postmarketOS on the Xiaomi Mi 8 Lite (`xiaomi-platina`, SDM660) using the [sdm660-mainline](https://github.com/sdm660-mainline/linux) kernel (`v7.0.14-sdm660`), built with pmbootstrap v3.11.1.

## Status

| Feature             | State                                                              |
|---------------------|--------------------------------------------------------------------|
| Boot (fastboot)     | Working (`scripts/boot-platina.sh`)                                |
| USB networking/SSH  | Working (see "Stability fixes")                                    |
| Display + console   | Working (panel mode is 1080x2246, see Known issues)                |
| Backlight (WLED)    | Working                                                            |
| ADSP / CDSP         | Running with firmware from the stock `modem` partition             |
| Touch (NT36672A)    | Working                                                            |
| GPU (Adreno 512)    | Working with freedreno (FD512)                                     |
| Phosh               | Working with the GPU                                               |
| Wi-Fi, Bluetooth    | Not working yet (next step)                                        |
| Modem, audio        | Not working yet (audio: `No dais found in DT`)                     |

## Repository layout

- `patches/`: kernel patches, generated with `git format-patch` on top of `v7.0.14-sdm660`
  - `0001-sdm660-xiaomi-platina-enable-display.patch`
  - `0002-sdm660-xiaomi-platina-enable-GPU-and-touch.patch`
  - `kernel-config-sdm660.aarch64`: kernel config used by the pmaports kernel package
- `pmaports/`: local packages (copy them to `pmaports/temp/` of your pmaports checkout)
  - `firmware-xiaomi-platina`: ADSP/CDSP firmware (blobs not included)
  - `platina-tweaks`: elogind without suspend, NetworkManager ignoring `usb0`, display module loaded at boot
  - `device-xiaomi-platina`: device package with the kernel command line below
- `scripts/`
  - `boot-platina.sh`: builds a boot image and runs `fastboot boot`
  - `post-install.sh`: rootfs fixes, re-apply after every `pmbootstrap install`

## Rebuilding from scratch

```
# 1. pmbootstrap and pmaports (device: xiaomi-platina, UI: console first, init: openrc)
pmbootstrap init

# 2. Kernel source, shallow clone of the tag is enough
git clone --depth 1 --branch v7.0.14-sdm660 https://github.com/sdm660-mainline/linux ~/kernel-src/linux
cd ~/kernel-src/linux
git checkout -b platina-base
git am /path/to/pmos_platina/patches/000*.patch

# 3. Local packages, device package and kernel config
cp -r pmaports/firmware-xiaomi-platina pmaports/platina-tweaks <pmaports>/temp/
cp patches/kernel-config-sdm660.aarch64 <pmaports>/device/*/linux-postmarketos-qcom-sdm660/config-postmarketos-qcom-sdm660.aarch64
pmbootstrap checksum platina-tweaks
pmbootstrap checksum linux-postmarketos-qcom-sdm660

# 4. Build kernel from the patched tree, then build the rootfs
pmbootstrap build --force --src=~/kernel-src/linux linux-postmarketos-qcom-sdm660
pmbootstrap config extra_packages firmware-xiaomi-platina,platina-tweaks
pmbootstrap install
pmbootstrap flasher flash_rootfs      # device in fastboot

# 5. DTB used by the boot script (needs gcc-aarch64-linux-gnu, flex, bison, openssl-devel, dtc)
cd ~/kernel-src/linux
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/sdm660-xiaomi-platina.dtb

# 6. Boot
scripts/boot-platina.sh
```

Always run `pmbootstrap install` after rebuilding the kernel, so the `vmlinuz` used by the boot script and the modules in the rootfs come from the same build (see "Kernel and modules must match").

## What was wrong with the display

The platina DTS had no display description, and `&mmcc` was explicitly `status = "disabled"`. Without the multimedia clock controller the MDSS and `mmss_smmu` failed with `-110` / missing clocks. Patch 0001:

- enables `&mmcc`
- enables `&mdss`, `&mdss_dsi0`, `&mdss_dsi0_phy`, `&mmss_smmu`
- adds the panel node (`tianma,fhd-video`, `novatek,nt36672a`), reset on GPIO53, backlight `&pm660l_wled`
- adds a fixed `lcdb_fixed` regulator (the bootloader already sets LCDB to 5.4 V)

## Kernel and modules must match

`panel-novatek-nt36672a` is built into the kernel (`CONFIG_DRM_PANEL_NOVATEK_NT36672A=y`). It used to be a module, and a module built against a different `vmlinux` than the running kernel is rejected:

```
failed to validate module [panel_novatek_nt36672a] BTF: -22
modprobe: ERROR: could not insert 'panel_novatek_nt36672a': Invalid argument
```

The kernel version string (`7.0.14-sdm660`) is the same for every build, so `uname -r` and `vermagic` do not reveal the mismatch. The result was a black screen with only `simpledrm` registered. Building the panel in removes that failure mode. `msm` is still a module and is loaded at boot through `/etc/modules-load.d/display.conf` (shipped by `platina-tweaks`).

## Stability fixes (rootfs)

The device used to drop off USB shortly after boot. Fixed by:

- disabling suspend in elogind (`IdleAction=ignore`, `AllowSuspend=no`)
- marking `usb0` as unmanaged in NetworkManager

See `scripts/post-install.sh`. These live in the rootfs, so re-apply after every `pmbootstrap install` unless `platina-tweaks` is installed.

## Firmware and blobs

Blobs are proprietary and **not included**. Keep a copy outside the repo and outside the pmbootstrap work directory (for example `~/platina-blobs/`).

- ADSP/CDSP: extract `adsp.*` and `cdsp.*` from the stock `modem` partition (`/dev/mmcblk1p74`, vfat, `image/` directory). Put them next to `pmaports/firmware-xiaomi-platina/APKBUILD`, run `pmbootstrap checksum` and `pmbootstrap build firmware-xiaomi-platina`.
- GPU zap shader: `a512_zap.mdt` + `.b00`-`.b02` come from the stock `vendor` partition (`firmware/` directory). Extract them from `vendor.img` of the MIUI fastboot ROM (`simg2img`, then loop-mount), or from the `vendor` partition on the device if it is still intact. The generic `a530_pm4.fw` / `a530_pfp.fw` come from `linux-firmware-qcom`.

The `pmbootstrap flasher flash_rootfs` step does not touch the `modem` partition, so the ADSP/CDSP blobs can be extracted again at any time.

## GPU (Adreno 512)

Enabled in the DTS (patch 0002) with `&gpucc`, `&adreno_gpu` and `&adreno_gpu_zap { firmware-name = "a512_zap.mdt"; }`. Mesa reports `FD512` (freedreno).

Warnings still present: `supply vdd/vddcx not found, using dummy regulator`.

## Phosh

UI: `pmbootstrap config ui phosh`. Notes:

- greetd/phrog reads `/etc/phrog/greetd-config.toml`. A wrapper `/etc/phrog/session.sh` is used as `command`; its first line must be `#!/bin/bash` with no blank line before it (otherwise `Exec format error`).
- The kernel has no usable ramoops/syslog by default: start `syslog` and read `logread` for session errors.
- Before the GPU worked, `WLR_RENDERER=pixman` and `GSK_RENDERER=cairo` were needed. They are no longer needed; `GSK_RENDERER=cairo` makes the UI feel laggy.
- With UBWC enabled some glyphs disappeared in earlier builds. Workaround: `FD_MESA_DEBUG=noubwc` (set in `/etc/environment` or the session wrapper).

## Boot flow

`flash_kernel` is not used. Put the device in fastboot and run `scripts/boot-platina.sh`. It concatenates the `vmlinuz` from `work/chroot_rootfs_xiaomi-platina/boot` with the DTB built from the kernel tree, builds a boot image with `mkbootimg` and runs `fastboot boot`. Add `debug` to get the initramfs debug shell on telnet (`172.16.42.1`).

Because the DTB comes from the kernel tree, rebuild it after every DTS change (step 5 above).

## Kernel command line

`clk_ignore_unused pd_ignore_unused regulator_ignore_unused consoleblank=0`

`video=DSI-1:1080x2280@60` is intentionally not used: the panel driver does not offer that mode, and it did not fix the resolution (see Known issues).

## Known issues

- `WARNING: drivers/clk/qcom/clk-rcg2.c:136` at boot: `mdp_clk_src: rcg didn't update its configuration.` Triggered while `msm` loads (`dpu_kms_init` -> `clk_set_rate`). Display and touch work afterwards. Not investigated yet.
- `novatek-nvt-ts: Error reading from 0x00: -6` and `supply vcc not found` appear early in boot, before the panel is on (the NT36672A is a TDDI chip). Touch works once the display is up.
- Panel mode: `tianma,fhd-video` is the Poco F1 panel mode (1080x2246), the Mi 8 Lite is 1080x2280, so the last lines are duplicated at the bottom. Needs a platina-specific mode (timings from the downstream DTS) in `panel-novatek-nt36672a`. Changing only the vertical size, or passing `video=` on the command line, left the screen black or had no effect.
- `qcom_sns_reg` cannot find `qcom/sensors/sns.reg` (sensor registry firmware is not packaged).
- `iio-sensor-proxy` and `modemmanager` fail (no sensor registry firmware, no modem yet).
- The device boots only through `scripts/boot-platina.sh` (`fastboot boot`); `flash_kernel` is intentionally not used.

## TODO

- Wi-Fi (WCN3990, `ath10k_snoc`): DTS node, `wlanmdsp.mbn` and `bdwlan.*` from the `modem` partition
- Bluetooth (WCN3990 over UART): DTS node and QCA firmware
- Platina-specific panel mode (1080x2280)
- Overlapping reserved-memory regions (qhee-code / removed_region, cdsp)
- Missing watchdog node
- Modem (`mba.mbn`, `modem.*`), audio
- Make the display DTB permanent in the pmbootstrap kernel package instead of the boot script
