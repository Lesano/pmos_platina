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
| Display + console  | Working with the patch in `patches/` (sharp image) |
| Backlight (WLED)   | Probes; brightness control not fully verified      |
| ADSP / CDSP        | Running with firmware from the stock `modem` partition |
| Touch (NT36672A)   | Not working (`Error reading from 0x00: -6`)        |
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
