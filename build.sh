#!/bin/sh
# Builds the Front Tire Guides USB stick folder.
#   ./build.sh [out dir] [--uninstall]
# Copy the out dir's contents (DONTINDX.MSA and SyncMyMod/) to the top of an empty FAT32 stick and plug it into SYNC.
#
# The program is cross-built for QNX 6.5 armle-v7 in a Docker image holding a QNX 6.5 gcc (QNX_IMAGE, default
# qnx65-armv7-toolchain:8.5; QNX_CC names the compiler in it). --uninstall builds the same folder set to remove the mod.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/dist
uninstall=0
for a in "$@"; do
    case "$a" in --uninstall) uninstall=1 ;; *) out=$a ;; esac
done
QNX_IMAGE=${QNX_IMAGE:-qnx65-armv7-toolchain:8.5}
QNX_CC=${QNX_CC:-arm-unknown-nto-qnx6.5.0eabi-gcc}

rm -rf "$out"
files=$out/SyncMyMod/files
mkdir -p "$files/bin" "$files/screen" "$files/snippets" "$files/frontcamera"
cp "$here/installer/autoinstall.sh" "$here/installer/install.conf" "$out/SyncMyMod/"
cp "$here/installer/uninstall.sh" "$here/installer/start.sh" "$here/installer/names.sh" "$here/installer/hmi_patch.sh" \
    "$here/installer/hmi_block.sh" "$files/"
cp "$here/screen/GuidesLayer.qml" "$here/screen/GuidesOverlay.qml" "$here/screen/LiftRow.qml" "$here/screen/LineRow.qml" "$here"/screen/guides_*.png "$files/screen/"
cp "$here"/screen/snippets/*.qml.in "$files/snippets/"
cp "$here"/screen/frontcamera/* "$files/frontcamera/"
cp "$here/calibration/frontcam.json" "$out/SyncMyMod/frontcam.json"
date +%Y.%m.%d > "$files/version.txt"
docker run --rm --platform=linux/amd64 -v "$here/program":/src:ro -v "$files/bin":/out "$QNX_IMAGE" sh -c "
    $QNX_CC -O2 -Wall -Wextra -std=c99 -D_POSIX_C_SOURCE=200809L -D_QNX_SOURCE -Wl,--dynamic-list=/src/exports.dyn \
        -o /out/guidesd /src/guidesd.c /src/tirepath.c /src/mc_dl.c -lm"
chmod +x "$out/SyncMyMod/autoinstall.sh" "$files/uninstall.sh" "$files/start.sh" "$files/bin/guidesd"
[ "$uninstall" = 1 ] && sed -i.bak 's/^UNINSTALL=.*/UNINSTALL=1/' "$out/SyncMyMod/install.conf" && rm -f "$out/SyncMyMod/install.conf.bak"
: > "$out/DONTINDX.MSA"    # keeps SYNC from indexing the stick as media
echo "stick folder: $out ($(du -sh "$out" | cut -f1))"
