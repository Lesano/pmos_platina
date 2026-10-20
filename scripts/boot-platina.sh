#!/bin/bash
# Usage: boot-platina.sh [debug]
set -e
CH=~/platinapmos/work/chroot_rootfs_xiaomi-platina/boot
DTB=~/kernel-src/linux/arch/arm64/boot/dts/qcom/sdm660-xiaomi-platina.dtb
CMD="clk_ignore_unused pd_ignore_unused regulator_ignore_unused consoleblank=0"
[ "$1" = "debug" ] && CMD="$CMD pmos.debug-shell"

cat $CH/vmlinuz $DTB > /tmp/kernel-dtb
mkbootimg --kernel /tmp/kernel-dtb --ramdisk $CH/initramfs \
  --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00f00000 --tags_offset 0x00000100 --pagesize 4096 \
  --cmdline "$CMD" -o /tmp/boot-platina.img
fastboot boot /tmp/boot-platina.img
