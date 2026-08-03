#!/bin/bash
# Two surgical changes to hurryman2212/OpenW1700k-test@offload-oc. Everything else --
# the NPU/PPE offload stack, kmod-br-netfilter, the +200 MHz overclock, the W1700K
# LuCI apps -- is left exactly as composed.
#
#  1. Bump the mt76 pin from 2026-07-24 (50480826) to upstream master b2704cf5
#     (2026-08-01), +14 commits. Picks up four MLO fixes, two of them directly in
#     the paths that failed here:
#       06b69763 mt7996: fix infinite loop in PS sync event parsing
#       da2c90d2 mt7996: send the STA_REC before the per-station VoW setup
#       8a03e88f reject out-of-range link ids in mt76_vif_link()
#       b2704cf5 mt7996: fix out-of-bounds link array access in mt7996_tx()
#
#  2. Drop the fork-only mac80211 patch that emits a switchdev FDB DEL on station
#     disconnect. With MLO enabled it fails with -ENOENT on every disconnect
#     (`mt7530 ... failed to delete <sta> vid 0 from fdb: -2`); on the offload
#     builds it wedged the station table until reboot. The commit adds exactly one
#     file, so removing that file is the whole revert -- no git revert, no conflict.
#
# The workflow runs this as `bash $bp/custom.sh &>/dev/null ||:` -- output and exit
# status are both discarded. A silent failure yields a build with neither change, so
# verify from the artifact: mt76 package version must read 2026.08.01~b2704cf5.
set -euo pipefail

# This REPLACES user/default/custom.sh -- only one survives the rsync into
# user/current/ -- so its two moves must happen here, or those files stay in files/
# and get baked into the rootfs as junk. 998-single-wiphy.patch matters on this
# hardware: three radios behind a single phy0.
LUCI_ASU=feeds/luci/applications/luci-app-attendedsysupgrade/htdocs/luci-static/resources/view/attendedsysupgrade
if [ -f files/overview.js ] && [ -d "$LUCI_ASU" ]; then
  mv files/overview.js "$LUCI_ASU/overview.js"
  echo "custom.sh: installed attendedsysupgrade overview.js"
fi
if [ -f files/998-single-wiphy.patch ]; then
  mkdir -p feeds/luci/modules/luci-mod-status/patches
  mv files/998-single-wiphy.patch feeds/luci/modules/luci-mod-status/patches/998-single-wiphy.patch
  echo "custom.sh: installed 998-single-wiphy.patch"
fi

MK=package/kernel/mt76/Makefile
SHA=b2704cf5a4068b672bf47ad5bf6b4802b6770a90
DATE=2026-08-01
FDB_PATCH=package/kernel/mac80211/patches/subsys/990-mac80211-emit-switchdev-fdb-del-on-sta-disconnect.patch

[ -f "$MK" ] || { echo "custom.sh: $MK not found" >&2; exit 1; }

sed -i \
  -e "s|^PKG_SOURCE_DATE:=.*|PKG_SOURCE_DATE:=${DATE}|" \
  -e "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=${SHA}|" \
  -e "s|^PKG_MIRROR_HASH:=.*|PKG_MIRROR_HASH:=skip|" \
  "$MK"

grep -q "^PKG_SOURCE_VERSION:=${SHA}$" "$MK" || { echo "custom.sh: mt76 pin not applied" >&2; exit 1; }
grep -q "^PKG_MIRROR_HASH:=skip$" "$MK" || { echo "custom.sh: mirror hash not cleared" >&2; exit 1; }
echo "custom.sh: mt76 pinned to ${SHA} (${DATE})"

# Fail loudly if the patch moved or was renamed upstream -- silently building WITH it
# would invalidate the entire point of this profile.
[ -f "$FDB_PATCH" ] || { echo "custom.sh: $FDB_PATCH not found; tree changed, refusing" >&2; exit 1; }
rm -f "$FDB_PATCH"
echo "custom.sh: dropped switchdev FDB DEL patch"

# Nothing else may still reference it.
if grep -rl "switchdev.*fdb.*del\|emit switchdev FDB" package/kernel/mac80211/patches/ 2>/dev/null | grep -q .; then
  echo "custom.sh: warning: other mac80211 patches still mention switchdev FDB DEL" >&2
fi
