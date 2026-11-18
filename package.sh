#!/bin/sh
# Packs the stick folders for a release: dist/front-tire-guides-<version>.zip (install) and
# dist/front-tire-guides-<version>-uninstall.zip, each with a short READ ME. Needs what build.sh needs.
#   ./package.sh [out dir]
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-$here/dist}
v=$(date +%Y.%m.%d)
mkdir -p "$out"
for kind in install uninstall; do
    dir=$out/$kind
    if [ $kind = install ]; then sh "$here/build.sh" "$dir" > /dev/null; zip=$out/front-tire-guides-$v.zip
    else sh "$here/build.sh" "$dir" --uninstall > /dev/null; zip=$out/front-tire-guides-$v-uninstall.zip; fi
    cat > "$dir/READ ME.txt" <<TXT
Front Tire Guides $v ($kind) for SYNC 3.4 (made for builds 22110, 22200, 22251, 23088, 23188 and 26057) with the F-Mods jailbreak (FMods Tools 2.8 or newer).

1. Copy DONTINDX.MSA and the SyncMyMod folder to the top of an empty FAT32 USB stick. One mod per stick.
2. With the truck parked and the engine running, plug the stick into SYNC and wait for the message that it is done.
3. Pull the stick. SYNC restarts.

Full instructions, what it changes and how to remove it: https://github.com/Trist0ne/front-tire-guides
Not made or endorsed by Ford or F-Mods. At your own risk.
TXT
    rm -f "$zip"
    (cd "$dir" && zip -q -r -X "$zip" DONTINDX.MSA SyncMyMod "READ ME.txt" -x '*/._*' -x '*.DS_Store')
    rm -rf "$dir"
    echo "$zip ($(du -h "$zip" | cut -f1))"
done
