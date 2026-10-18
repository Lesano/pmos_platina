#!/bin/sh
# Run with the rootfs mounted at /mnt/r (from the initramfs debug shell)
R=${1:-/mnt/r}
mkdir -p $R/etc/elogind/logind.conf.d $R/etc/elogind/sleep.conf.d
printf '[Login]\nIdleAction=ignore\n' > $R/etc/elogind/logind.conf.d/99-nosuspend.conf
printf '[Sleep]\nAllowSuspend=no\nAllowHibernation=no\nAllowSuspendThenHibernate=no\nAllowHybridSleep=no\n' > $R/etc/elogind/sleep.conf.d/99-nosuspend.conf
mkdir -p $R/etc/NetworkManager/conf.d
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' > $R/etc/NetworkManager/conf.d/99-usb0.conf
mkdir -p $R/etc/modules-load.d
printf 'msm\npanel-novatek-nt36672a\n' > $R/etc/modules-load.d/display.conf
