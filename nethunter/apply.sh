#!/bin/sh
# SPDX-License-Identifier: CC0-1.0
# apply.sh — put the umi device support into a kali-nethunter-pro checkout
#
#   sh nethunter/apply.sh /path/to/kali-nethunter-pro
#
# Idempotent: a patch that is already applied is skipped. The kernel package,
# if one was built, is copied where devices/qcom/packages-base.yaml dpkg -i's it.
set -e

HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TARGET=${1:-$HERE/../kali-nethunter-pro}

die() { echo "!! $*" >&2; exit 1; }

[ -f "$TARGET/build.sh" ] || die "no kali-nethunter-pro checkout at $TARGET"
cd "$TARGET"

for p in "$HERE"/nethunter/patches/*.patch; do
	# --ignore-whitespace: a Windows checkout with core.autocrlf=true has CRLF in
	# the tree while the patches are LF. Everything except line endings is still
	# checked.
	if git apply --ignore-whitespace --reverse --check "$p" 2>/dev/null; then
		echo "   already applied: $(basename "$p")"
		continue
	fi
	git apply --ignore-whitespace "$p" 2>/dev/null ||
		die "failed to apply $(basename "$p") — checkout out of date?"
	echo "   applied: $(basename "$p")"
done

mkdir -p devices/qcom/packages
if ls "$HERE"/kernel/out/linux-image-*.deb >/dev/null 2>&1; then
	cp -f "$HERE"/kernel/out/linux-image-*.deb devices/qcom/packages/
else
	echo "   note: kernel/out has no linux-image-*.deb yet."
	echo "         Run kernel/build-kernel-deb.sh, or drop a package into"
	echo "         $TARGET/devices/qcom/packages/ yourself."
fi

ls -l devices/qcom/packages
echo "== next: ./build.sh -a arm64 -v sm8250 -D phosh"
