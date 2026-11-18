#!/bin/sh
# Front Tire Guides: USB installer for SYNC 3 build 3.4.23188 with the F-Mods jailbreak (FMods Tools 2.8 or newer).
# The jailbreak's USB installer runs SyncMyMod/autoinstall.sh from the stick; the line it shows on SYNC's screen is
# whatever is written to /fs/tmpfs/status ("ERROR ..." in red, "PROGRESS n" for the bar, "REBOOT" to restart).
#
# What it puts on SYNC (all of it taken out again by uninstall.sh; names in names.sh):
#   the program          /fs/images/fmods_apps_data/FrontTireGuides
#   the screen layer     /fs/mp/fordhmi/qml/hmirvc/frontguides
#   the calibration      /fs/rwdata/frontguides/frontcam.json   (from the stick; one already on SYNC is kept if the
#                        stick has none)
#   the start            one line in SYNC's startup script, straight after Ford's line that launches SYNC's
#                        services (or a script for the F-Mods launcher: EARLY_START=0, or that line not found)
#   in Ford's files      a Loader in the camera popup; a button in the camera view row; our rows on the camera
#                        settings page and the "Front Camera" entry in Driver Assistance
# A Ford file is only changed if it is Ford's stock file (plus blocks of these mods); otherwise the install stops,
# or for the settings page goes on without it. Every change is undone if a later step fails.
PATH=/fs/rwdata/dev:$PATH
STICK=/fs/usb0/SyncMyMod
DISPLAY_FILE=/fs/tmpfs/status
VERSION=$(cat "$STICK/files/version.txt" 2>/dev/null)
. "$STICK/files/names.sh"
. "$STICK/files/hmi_patch.sh"
. "$STICK/files/hmi_block.sh"
. "$STICK/install.conf"

say() { echo "$1" > "$DISPLAY_FILE" 2>/dev/null; sleep "${2:-1}" 2>/dev/null; }
progress() { echo "PROGRESS $1" > "$DISPLAY_FILE" 2>/dev/null; }
finish() {   # wait for the stick to be pulled, then the jailbreak's installer restarts SYNC
    sync
    while [ -e /fs/usb0 ]; do sleep 1; done
    say "REBOOT" 3
    exit "${1:-0}"
}
refuse() {   # before anything was changed
    say "ERROR $1"
    finish 1
}
rw=0
undo() {     # after changes: put everything back, then stop
    say "ERROR $1 Undoing the install..." 2
    /bin/sh "$STICK/files/uninstall.sh" > /dev/null 2>&1
    [ "$rw" = 1 ] && remount_ro.sh
    sync
    say "ERROR $1 Front Tire Guides is not installed." 2
    finish 1
}

[ -x "$(command -v instutility)" ] && { instutility & sleep 2; }
say "Front Tire Guides $VERSION" 2

if [ "${UNINSTALL:-0}" = 1 ]; then
    say "Removing Front Tire Guides from SYNC..." 1
    /bin/sh "$STICK/files/uninstall.sh" > /dev/null 2>&1   # (/bin/sh by its path: "sh" need not be on the installer's PATH)
    if [ -e "$PROGRAMS" ] || [ -e "$SCREEN" ] || [ -e "$LAUNCHER" ] || grep -q "$MARK" "$STARTUP" 2>/dev/null ||
        grep -q "$LAYER_MARK" "$RVCPOPUP" 2>/dev/null || grep -q "$BUTTON_MARK" "$VIEWBTNS" 2>/dev/null ||
        hmi_block_has "$PAGE" "$BLOCK"; then
        say "ERROR Front Tire Guides could not be removed completely." 2
        finish 1
    fi
    say "Front Tire Guides removed. Remove the USB stick to restart SYNC." 2
    finish 0
fi

# -- checks (nothing changed yet) -------------------------------------------------------------------------------
progress 5
grep -q "_3.4.23188_" /fs/mp/Version.inf 2>/dev/null || refuse "Made for SYNC 3 build 3.4.23188 only."
LINE=$(grep FMODS_TOOLS /fs/rwdata/dev/mods_tools.txt 2>/dev/null)
[ -n "$LINE" ] || refuse "FMods Tools not found: install the F-Mods jailbreak and FMods Tools first."
TOOLS=$(echo "$LINE" | awk -F_ '{print $NF}')
awk 'BEGIN { exit !('"$TOOLS"' >= 2.8) }' 2>/dev/null || refuse "FMods Tools 2.8 or newer needed."
[ -f "$STICK/files/bin/guidesd" ] || refuse "The program is missing from the stick."
[ -f "$STICK/frontcam.json" ] || [ -f "$SETTINGS/frontcam.json" ] || refuse "No camera calibration (frontcam.json) on the stick."
fords_files() {   # Ford's camera popup and view buttons: stock, or holding this mod's own marks. Says what is not.
    grep -q "$LAYER_MARK" "$RVCPOPUP" 2>/dev/null || [ "$(openssl md5 < "$RVCPOPUP" 2>/dev/null | awk '{print $NF}')" = "$RVCPOPUP_MD5" ] ||
        { echo "SYNC's camera popup isn't Ford's stock file (another mod?)."; return 1; }
    [ "${VIEW_BUTTON:-1}" = 1 ] || return 0
    grep -q "$BUTTON_MARK" "$VIEWBTNS" 2>/dev/null || [ "$(openssl md5 < "$VIEWBTNS" 2>/dev/null | awk '{print $NF}')" = "$VIEWBTNS_MD5" ] ||
        { echo "SYNC's camera view buttons aren't Ford's stock file (another mod?). Set VIEW_BUTTON=0 to install without the button."; return 1; }
}
why=$(fords_files) || refuse "$why"
START=line   # older FMods Tools: our line at the end of the startup script
awk 'BEGIN { exit !('"$TOOLS"' >= 3.0) }' && grep -q launch_fmodslauncher.sh "$STARTUP" 2>/dev/null && START=launcher
# (Ford's launch line not found as expected in the startup script: left alone, started as above)
if [ "${EARLY_START:-1}" = 1 ] && [ "$(grep -c "$ANCHOR" "$STARTUP" 2>/dev/null)" = 1 ]; then START=early; fi

# -- install ----------------------------------------------------------------------------------------------------
progress 10
say "Setting the file system read-write..." 1
remount_rw.sh || refuse "Couldn't make the file system writable."
rw=1
[ -d "$PROGRAMS" ] && { say "Stopping what is installed..." 1; stop_ours; }

progress 30
say "Copying the program..." 1
rm -rf "$PROGRAMS"
mkdir -p "$PROGRAMS/bin" && cp "$STICK/files/bin/guidesd" "$PROGRAMS/bin/" &&
    cp "$STICK/files/start.sh" "$STICK/files/uninstall.sh" "$STICK/files/names.sh" "$STICK/files/hmi_patch.sh" "$STICK/files/hmi_block.sh" \
        "$STICK/files/version.txt" "$STICK/install.conf" "$PROGRAMS/" || undo "Copying the program failed."
chmod +x "$PROGRAMS/bin/guidesd" "$PROGRAMS/start.sh" "$PROGRAMS/uninstall.sh"

progress 45
say "Copying the screen layer..." 1
rm -rf "$SCREEN"
mkdir -p "$SCREEN" && cp "$STICK"/files/screen/* "$SCREEN/" || undo "Copying the screen layer failed."

mkdir -p "$SETTINGS"
if [ -f "$STICK/frontcam.json" ]; then
    cp "$STICK/frontcam.json" "$SETTINGS/frontcam.json" || undo "Copying the camera calibration failed."
fi

progress 60
say "Starting it with SYNC..." 1
OURLINE="[ -x $PROGRAMS/start.sh ] && $PROGRAMS/start.sh &  # $MARK"
case "$START" in
early)   # one line, straight after Ford's launch line
    rm -f "$LAUNCHER"
    startup_line_out || undo "Updating SYNC's startup script failed."
    at=$(grep -n "$ANCHOR" "$STARTUP" | awk -F: '{ print $1 }')
    awk -v at="$at" -v l="$OURLINE" '{ print } NR == at { print l }' "$STARTUP" > /tmp/front_tire_guides_startup &&
        [ "$(grep -c "$MARK" /tmp/front_tire_guides_startup)" = 1 ] && startup_swap /tmp/front_tire_guides_startup 1 ||
        undo "Updating SYNC's startup script failed."
    ;;
launcher)
    startup_line_out || undo "Updating SYNC's startup script failed."
    mkdir -p "${LAUNCHER%/*}" &&
        printf '#!/bin/sh\n# %s: starts Front Tire Guides with SYNC (run by the F-Mods launcher)\n[ -x %s/start.sh ] && %s/start.sh\n' \
            "$MARK" "$PROGRAMS" "$PROGRAMS" > "$LAUNCHER" && chmod +x "$LAUNCHER" || undo "Adding the launcher script failed."
    ;;
line)
    rm -f "$LAUNCHER"
    startup_line_out || undo "Updating SYNC's startup script failed."
    { cat "$STARTUP"; printf '%s\n' "$OURLINE"; } > /tmp/front_tire_guides_startup && startup_swap /tmp/front_tire_guides_startup 1 ||
        undo "Updating SYNC's startup script failed."
    ;;
esac

progress 75
say "Adding the guides to the front camera view..." 1
hmi_patch_out "$VIEWBTNS" "$BACKUP" CameraViewButtons   # Ford's files back first, so a changed setting takes effect
hmi_patch_out "$RVCPOPUP" "$BACKUP" RVCPopup
hmi_patch_in "$RVCPOPUP" "$STICK/files/snippets/layer_loader.qml.in" "$LAYER_MARK" "$BACKUP" RVCPopup ||
    undo "Adding the layer to the camera popup failed."
if [ "${VIEW_BUTTON:-1}" = 1 ]; then
    hmi_patch_in "$VIEWBTNS" "$STICK/files/snippets/switch_button.qml.in" "$BUTTON_MARK" "$BACKUP" CameraViewButtons \
        "model: HmiActionModel {" || undo "Adding the button to the camera view buttons failed."
fi

# The settings page is a nicety: if Ford's page isn't the stock file (plus blocks of these mods), the install goes on
# without it. Likewise the Driver Assistance entry: without it, our rows stay on Ford's camera settings page.
PAGE_IN=0
MENU_IN=0
if [ "${SETTINGS_PAGE:-1}" = 1 ] && hmi_block_stock "$PAGE" "$PAGE_MD5"; then
    progress 88
    say "Adding the settings page..." 1
    hmi_block_in "$PAGE" "$STICK/files/snippets/settings_rows.qml.in" "$BLOCK" "$PAGE_MD5" || undo "Adding our rows to the settings page failed."
    PAGE_IN=1
    if front_menu_in "$STICK/files/frontcamera"; then MENU_IN=1; fi
else
    hmi_block_out "$PAGE" "$BLOCK" "$PAGE_MD5"
    front_menu_out
fi

progress 95
say "Setting the file system read-only..." 1
remount_ro.sh
rw=0
sync
# SYNC's update overlay images are back on top now: each change must still be what SYNC sees
hidden=""
[ -x "$PROGRAMS/bin/guidesd" ] || hidden="$hidden the program,"
[ -f "$SCREEN/GuidesLayer.qml" ] || hidden="$hidden the screen layer,"
case "$START" in launcher) [ -x "$LAUNCHER" ] || hidden="$hidden the launcher script," ;; *) grep -q "$MARK" "$STARTUP" || hidden="$hidden the startup script," ;; esac
grep -q "$LAYER_MARK" "$RVCPOPUP" || hidden="$hidden RVCPopup.qml,"
[ "${VIEW_BUTTON:-1}" = 1 ] && ! grep -q "$BUTTON_MARK" "$VIEWBTNS" && hidden="$hidden CameraViewButtons.qml,"
[ "$PAGE_IN" = 1 ] && ! hmi_block_has "$PAGE" "$BLOCK" && hidden="$hidden RVCSettings.qml,"
[ "$MENU_IN" = 1 ] && ! front_menu_has && hidden="$hidden DriverAssistSettingsMenu.qml,"
if [ -n "$hidden" ]; then
    remount_rw.sh
    rw=1
    undo "SYNC shows another copy of${hidden%,} (an update overlay image covers it)."
fi
progress 100
say "Front Tire Guides $VERSION installed. Remove the USB stick to restart SYNC." 2
finish 0
