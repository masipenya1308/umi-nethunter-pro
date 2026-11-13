#!/bin/sh
# SPDX-License-Identifier: CC0-1.0
# build-kernel-deb.sh — build the umi kernel + DTB as a Debian linux-image package
#
#   sh kernel/build-kernel-deb.sh
#
# The Kali NetHunter Pro builder installs its own kernel from devices/qcom/packages/,
# picks the bootable image with `linux-version list` and takes the DTB from
# /usr/lib/linux-image-<ver>/qcom/. This script produces exactly that package from
# the *working* umi kernel tree (umi-mainline), so nothing here re-derives the port.
#
# Env: UMI_MAINLINE (default ../umi-mainline), TREE, OUT, KERNEL_REF, KERNEL_REPO,
#      JOBS, CROSS_COMPILE
# Out: kernel/out/linux-image-*.deb (+ headers), build/out/config-effective
set -e

HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UMI=${UMI_MAINLINE:-$HERE/../umi-mainline}
TREE=${TREE:-$HERE/build/linux}
OUT=${OUT:-$HERE/build/out}
KERNEL_REF=${KERNEL_REF:-v6.12}
# kernel.org is not reachable from GitHub runners often enough to bother retrying
KERNEL_REPO=${KERNEL_REPO:-https://github.com/gregkh/linux.git}
CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}
JOBS=${JOBS:-$(nproc)}
MK="ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE O=$OUT"

die() { echo "!! $*" >&2; exit 1; }

[ -f "$UMI/dts/sm8250-xiaomi-umi-common.dtsi" ] ||
	die "umi-mainline not found at $UMI — set UMI_MAINLINE=/path/to/umi-mainline"

[ -d "$TREE" ] || git clone --depth 1 --branch "$KERNEL_REF" "$KERNEL_REPO" "$TREE"

echo "== [1/3] umi-mainline recipe: tree surgery + verified config + build"
TREE="$TREE" OUT="$OUT" WS="$UMI" JOBS="$JOBS" CROSS_COMPILE="$CROSS_COMPILE" \
	sh "$UMI/scripts/build.sh"

echo "== [2/3] Kali delta: cmdline from the bootloader, container filesystems"
cat "$HERE/kernel/umi-nethunter.config" >> "$OUT/.config"
make -s -C "$TREE" $MK olddefconfig

expect() { # expect SYMBOL VALUE — empty VALUE means "must not be y/m"
	got=$(sed -n "s/^CONFIG_$1=\(.*\)\$/\1/p" "$OUT/.config" | tail -1)
	if [ -z "$2" ]; then
		case "$got" in y|m) die "CONFIG_$1=$got must be off for a distro rootfs";; esac
		echo "   OK   CONFIG_$1 off"
	else
		[ "$got" = "$2" ] || die "CONFIG_$1='$got', expected '$2' (see $OUT/.config)"
		echo "   OK   CONFIG_$1=$2"
	fi
}
# A silently demoted symbol is the failure mode this port keeps hitting: the
# build stays green and the phone boots into a dead end.
expect CMDLINE_FROM_BOOTLOADER y   # root=UUID=... comes from the boot image
expect CMDLINE_FORCE ""            # ...which FORCE would throw away
expect MODULES y
expect DRM_MSM y
expect DRM_PANEL_XIAOMI_UMI y      # =m would mean no display: no module loader in initramfs
expect TOUCHSCREEN_ST_FTS_V521 y
expect SCSI_UFS_QCOM y
expect EXT4_FS y
expect BLK_DEV_INITRD y
expect OVERLAY_FS y
expect VETH y
expect TUN y

echo "== [3/3] build + Debian package"
make -C "$TREE" $MK -j"$JOBS" Image.gz dtbs modules

DTB="$OUT/arch/arm64/boot/dts/qcom/sm8250-xiaomi-umi-wifi.dtb"
[ -s "$DTB" ] || die "missing $DTB"
# ABL matches the device on qcom,msm-id / qcom,board-id and silently falls back
# to fastboot without them; pack-umi.py refuses to pack a DTB that fails this.
python3 "$UMI/tools/dtb.py" ids "$DTB" || die "DTB ids check failed"

make -C "$TREE" $MK -j"$JOBS" bindeb-pkg

DEBDIR=$(dirname "$TREE")
mkdir -p "$HERE/kernel/out"
rm -f "$HERE/kernel/out"/linux-image-*.deb
cp -f "$DEBDIR"/linux-image-*.deb "$HERE/kernel/out/" 2>/dev/null ||
	die "bindeb-pkg produced no linux-image deb in $DEBDIR"
IMGDEB=$(ls "$HERE/kernel/out"/linux-image-*.deb | head -1)
# devices/qcom/bootloader.sh looks the DTB up by name in the installed package:
# /usr/lib/linux-image-<ver>/qcom/<chipset>-<vendor>-<model>-<variant>.dtb
dpkg-deb -c "$IMGDEB" | grep -q 'qcom/sm8250-xiaomi-umi-wifi.dtb$' ||
	die "$IMGDEB does not ship qcom/sm8250-xiaomi-umi-wifi.dtb"

cp -f "$OUT/.config" "$HERE/kernel/out/config-effective"
ls -l "$HERE/kernel/out"
echo "== done: nethunter/apply.sh <kali-nethunter-pro checkout>"
