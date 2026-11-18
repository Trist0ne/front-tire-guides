#!/bin/sh
# Front Tire Guides uninstaller. Takes out exactly what the installer added and puts Ford's files back as they were.
# Run by the stick with UNINSTALL=1, or by hand on SYNC. Safe to run twice.
# The "Front Camera" entry in Driver Assistance is shared with Enhanced Camera Control: it stays while that mod's
# switches are on the page, and goes with the last of the two.
PATH=/fs/rwdata/dev:$PATH
here=$(dirname "$0")
. "$here/names.sh"
. "$here/hmi_patch.sh"
. "$here/hmi_block.sh"

command -v remount_rw.sh > /dev/null && remount_rw.sh
stop_ours
hmi_block_out "$PAGE" "$BLOCK" "$PAGE_MD5"
front_menu_out
hmi_patch_out "$VIEWBTNS" "$BACKUP" CameraViewButtons
hmi_patch_out "$RVCPOPUP" "$BACKUP" RVCPopup
startup_line_out
rm -f "$LAUNCHER"
rm -rf "$SCREEN" "$SETTINGS" "$PROGRAMS"
rmdir "$BACKUP" 2>/dev/null
command -v remount_ro.sh > /dev/null && remount_ro.sh
sync
exit 0
