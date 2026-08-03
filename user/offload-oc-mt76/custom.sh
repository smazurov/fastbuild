#!/bin/bash
set -euo pipefail

# Replaces user/default/custom.sh, so its moves must happen here too.
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
PS_PATCH=package/kernel/mt76/patches/9990-wifi-mt76-mt7996-validate-PS-sync-event-TLVs.patch
FDB_PATCH=package/kernel/mac80211/patches/subsys/990-mac80211-emit-switchdev-fdb-del-on-sta-disconnect.patch

[ -f "$MK" ] || { echo "custom.sh: $MK not found" >&2; exit 1; }

sed -i \
  -e "s|^PKG_SOURCE_DATE:=.*|PKG_SOURCE_DATE:=${DATE}|" \
  -e "s|^PKG_SOURCE_VERSION:=.*|PKG_SOURCE_VERSION:=${SHA}|" \
  -e "s|^PKG_MIRROR_HASH:=.*|PKG_MIRROR_HASH:=skip|" \
  "$MK"

# The workflow discards this script's output and exit status, so verify here.
grep -q "^PKG_SOURCE_VERSION:=${SHA}$" "$MK" || { echo "custom.sh: mt76 pin not applied" >&2; exit 1; }
grep -q "^PKG_MIRROR_HASH:=skip$" "$MK" || { echo "custom.sh: mirror hash not cleared" >&2; exit 1; }
echo "custom.sh: mt76 pinned to ${SHA} (${DATE})"

# Superseded by upstream 06b69763, an ancestor of the pin above; all 3 hunks now fail.
if [ -f "$PS_PATCH" ]; then
  rm -f "$PS_PATCH"
  echo "custom.sh: dropped PS-sync TLV patch"
fi

# Fails -ENOENT on every MLO disconnect and wedges the station table.
[ -f "$FDB_PATCH" ] || { echo "custom.sh: $FDB_PATCH not found; tree changed, refusing" >&2; exit 1; }
rm -f "$FDB_PATCH"
echo "custom.sh: dropped switchdev FDB DEL patch"

if grep -rl "switchdev.*fdb.*del\|emit switchdev FDB" package/kernel/mac80211/patches/ 2>/dev/null | grep -q .; then
  echo "custom.sh: warning: other mac80211 patches still mention switchdev FDB DEL" >&2
fi
