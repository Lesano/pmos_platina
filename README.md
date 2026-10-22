# Xiaomi Mi 8 Lite (platina) on postmarketOS – mainline notes

Work-in-progress notes and patches for running postmarketOS on the
Xiaomi Mi 8 Lite (`xiaomi-platina`, SDM660) using the
[sdm660-mainline](https://github.com/sdm660-mainline/linux) kernel
(`v7.0.14-sdm660`), built with pmbootstrap v3.11.1.

## Status

| Feature            | State                                              |
|--------------------|----------------------------------------------------|
| Boot (fastboot)    | Working                                            |
| USB networking/SSH | Working (see "Stability fixes")                    |
| Display + console  | Working (panel mode is 1080x2246, see Known issues) |
| Backlight (WLED)   | Working                                            |
| ADSP / CDSP        | Running with firmware from the stock `modem` partition |
| Touch (NT36672A)   | Working (axes and range verified, multitouch)      |
| GPU (Adreno 512)   | Working with freedreno (FD512), needs `FD_MESA_DEBUG=noubwc` |
| Phosh              | Working, animations smooth                         |
| Wi-Fi, modem, audio| Not working yet (audio: `No dais found in DT`)    |

## What was wrong with the display

The platina DTS had no display description, and `&mmcc` was explicitly
`status = "disabled"`. Without the multimedia clock controller the MDSS
and `mmss_smmu` failed with `-110` / missing clocks. The patch:

- enables `&mmcc`
- enables `&mdss`, `&mdss_dsi0`, `&mdss_dsi0_phy`, `&mmss_smmu`
- adds the panel node (`tianma,fhd-video`, `novatek,nt36672a`),
  reset on GPIO53, backlight `&pm660l_wled`
- adds a fixed `lcdb_fixed` regulator (the bootloader already
  sets LCDB to 5.4 V)

`msm` and `panel-novatek-nt36672a` are modules (`=m`), so they must be
loaded at boot (`/etc/modules-load.d/display.conf`).

## Stability fixes (rootfs)

The device used to drop off USB shortly after boot. Fixed by:

- disabling suspend in elogind (`IdleAction=ignore`, `AllowSuspend=no`)
- marking `usb0` as unmanaged in NetworkManager

See `scripts/post-install.sh`. These live in the rootfs, so re-apply
after every `pmbootstrap install`.

## Firmware

Blobs are proprietary and **not included**. Extract them from the
stock `modem` partition (`/dev/mmcblk1p74`, vfat, `image/` directory):
`adsp.*` and `cdsp.*`. Put them next to
`pmaports/firmware-xiaomi-platina/APKBUILD`, run
`pmbootstrap checksum` and `pmbootstrap build firmware-xiaomi-platina`,
and add it with `pmbootstrap config extra_packages firmware-xiaomi-platina`.

## Applying the DTS patch

```
git clone https://github.com/sdm660-mainline/linux
cd linux && git checkout v7.0.14-sdm660
git apply /path/to/patches/0001-*.patch
make ARCH=arm64 defconfig
make ARCH=arm64 qcom/sdm660-xiaomi-platina.dtb
```

Quick test without flashing: append the DTB to `vmlinuz`, build a boot
image with `mkbootimg` using the offsets from `deviceinfo`, then
`fastboot boot`. For a permanent install:
`pmbootstrap build linux-postmarketos-qcom-sdm660 --src=<kernel tree>`.

## Kernel command line

`clk_ignore_unused pd_ignore_unused regulator_ignore_unused consoleblank=0`

## TODO

- Touch: missing supply/reset in the DTS (`supply vcc not found`)
- Overlapping reserved-memory regions (qhee-code / removed_region, cdsp)
- Missing watchdog node
- Wi-Fi (`wlanmdsp.mbn`, `bdwlan.*`), modem (`mba.mbn`, `modem.*`), audio
- Make the display DTB permanent in the pmbootstrap kernel package

## Known issues

- `WARNING: drivers/clk/qcom/clk-rcg2.c:136` at boot:
  `mdp_clk_src: rcg didn't update its configuration.` Triggered while
  `msm` loads (`dpu_kms_init` -> `clk_set_rate`). Display and touch work
  afterwards. Not investigated yet.
- `novatek-nvt-ts: Error reading from 0x00: -6` and
  `supply vcc not found` appear early in boot, before the panel is on
  (the NT36672A is a TDDI chip). Touch works once the display is up.
- No Wi-Fi, modem or audio yet (`No dais found in DT`).
- `qcom_sns_reg` cannot find `qcom/sensors/sns.reg` (sensor registry
  firmware is not packaged).
- The device boots only through `scripts/boot-platina.sh`
  (`fastboot boot`); `flash_kernel` is intentionally not used.

## Packages

- `pmaports/firmware-xiaomi-platina`: ADSP/CDSP firmware (blobs not included)
- `pmaports/platina-tweaks`: elogind without suspend, NetworkManager
  ignoring `usb0`, display modules loaded at boot

Build with `pmbootstrap build <pkg>` and enable with
`pmbootstrap config extra_packages firmware-xiaomi-platina,platina-tweaks`
(UI: `console`).

## GPU (Adreno 512)

Enabled in the DTS with `&gpucc`, `&adreno_gpu` and
`&adreno_gpu_zap { firmware-name = "a512_zap.mdt"; }`. The zap shader
(`a512_zap.mdt` + `.b00`-`.b02`) comes from the stock `vendor`
partition (`firmware/` directory); extract it from `vendor.img` of the
MIUI fastboot ROM (`simg2img`, then loop-mount). The generic
`a530_pm4.fw` / `a530_pfp.fw` come from `linux-firmware-qcom`.
Mesa reports `FD512` (freedreno).

Warnings still present: `supply vdd/vddcx not found, using dummy regulator`.

## Phosh

UI: `pmbootstrap config ui phosh`. Notes:

- greetd/phrog reads `/etc/phrog/greetd-config.toml`. A wrapper
  `/etc/phrog/session.sh` is used as `command`; its first line must be
  `#!/bin/bash` with no blank line before it (otherwise `Exec format error`).
- The kernel has no usable ramoops/syslog by default: start `syslog`
  and read `logread` for session errors.
- Before the GPU worked, `WLR_RENDERER=pixman` and `GSK_RENDERER=cairo`
  were needed. They are no longer needed; `GSK_RENDERER=cairo` makes the
  UI feel laggy.
- With UBWC enabled some glyphs disappear. Workaround:
  `FD_MESA_DEBUG=noubwc` (set in `/etc/environment` or the session wrapper).

## Boot flow

`flash_kernel` is not used. Put the device in fastboot and run
`scripts/boot-platina.sh` (builds a boot image from the pmbootstrap
kernel + the patched DTB and runs `fastboot boot`). Add `debug` to get the
initramfs debug shell on telnet (`172.16.42.1`).

- Panel mode: `tianma,fhd-video` is the Poco F1 panel mode (1080x2246),
  the Mi 8 Lite is 1080x2280, so the last lines are duplicated at the
  bottom. `video=DSI-1:1080x2280@60` did not help. Needs a platina-specific
  mode (timings from the downstream DTS) in `panel-novatek-nt36672a`.
- `iio-sensor-proxy` and `modemmanager` fail (no sensor registry
  firmware, no modem yet).
