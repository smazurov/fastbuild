#!/bin/bash
# Bump the mt76 pin past mainline's 2026-07-01 (59676919) to pick up the MLO fixes:
#   8a03e88f wifi: mt76: reject out-of-range link ids in mt76_vif_link()
#   b2704cf5 wifi: mt76: mt7996: fix out-of-bounds link array access in mt7996_tx()
# Both landed 2026-08-01; b2704cf5 is mt76 master HEAD and has 8a03e88f as an ancestor.
#
# The workflow invokes this as `bash $bp/custom.sh &>/dev/null ||:` — output and exit
# status are both discarded, so a silent failure here yields a build with the OLD pin.
# Verify from the built package version, which must read 2026.08.01~b2704cf5.
set -euo pipefail

MK=package/kernel/mt76/Makefile
SHA=b2704cf5a4068b672bf47ad5bf6b4802b6770a90
DATE=2026-08-01

[ -f "$MK" ] || { echo "custom.sh: $MK not found" >&2; exit 1; }

sed -i \
  -e "s|^PKG_SOURCE_DATE:=.*|PKG_SOURCE_DATE:=${DATE}|" \
  -e "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=${SHA}|" \
  -e "s|^PKG_MIRROR_HASH:=.*|PKG_MIRROR_HASH:=skip|" \
  "$MK"

grep -q "^PKG_SOURCE_VERSION:=${SHA}$" "$MK" || { echo "custom.sh: pin not applied" >&2; exit 1; }
grep -q "^PKG_MIRROR_HASH:=skip$" "$MK" || { echo "custom.sh: mirror hash not cleared" >&2; exit 1; }

echo "custom.sh: mt76 pinned to ${SHA} (${DATE})"

# Graft the useful W1700K LuCI apps from the OpenW1700k fork. They are plain LuCI
# packages under package/ there, with no dependency on the fork's kernel patches to
# *build*. Whether flowsense/npu display anything meaningful on a mainline kernel is
# untested -- they read fork-specific counters.
#
# airoha_fan is deliberately NOT taken from the fork: mainline already ships an
# identical copy at target/linux/airoha/an7581/base-files/etc/init.d/airoha_fan.
FORK_URL=https://github.com/OpenWRT-fanboy/OpenW1700k
FORK_REF=ubi2
FORK_PKGS="luci-app-mlo luci-app-w1700k-fancontrol luci-app-airoha-npu luci-app-airoha-flowsense"

SRC=$(mktemp -d)
git clone --depth 1 --filter=blob:none --sparse -b "$FORK_REF" "$FORK_URL" "$SRC/fork"
git -C "$SRC/fork" sparse-checkout set $(for p in $FORK_PKGS; do printf 'package/%s ' "$p"; done)

mkdir -p package/w1700k
for p in $FORK_PKGS; do
  [ -d "$SRC/fork/package/$p" ] || { echo "custom.sh: fork package $p missing" >&2; exit 1; }
  cp -a "$SRC/fork/package/$p" package/w1700k/
  echo "CONFIG_PACKAGE_${p}=y" >> .config
  echo "custom.sh: grafted $p"
done
rm -rf "$SRC"
