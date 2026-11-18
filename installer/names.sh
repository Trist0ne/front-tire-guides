# Front Tire Guides: where everything lives on SYNC, and Ford's files it adds to. Sourced by autoinstall.sh and
# uninstall.sh, so the two can never disagree.
PROGRAMS=/fs/images/fmods_apps_data/FrontTireGuides          # the program, the start script, the uninstaller
BACKUP=/fs/images/fmods_apps_data/FrontTireGuides_backup     # Ford's files as they were (hmi_patch.sh)
SCREEN=/fs/mp/fordhmi/qml/hmirvc/frontguides                 # the screen layer's files
SETTINGS=/fs/rwdata/frontguides                              # calibration, lift, the line settings, the switch
RUN=/fs/tmpfs/frontguides                                    # what the program writes while SYNC is up
STARTUP=/fs/mp/scripts/startup_gf.sh
LAUNCHER=/fs/mp/scripts/fmods/front_tire_guides.sh
MARK=front-tire-guides                                       # marks our line in the startup script
# Ford's line that launches SYNC's services; our line goes straight after it
ANCHOR='^on -p 20  *\$GF_ROOT/apps/SS_LaunchProcesses .*&$'
# Ford's files, and what the stock ones of SYNC 3.4.23188 hash to
RVCPOPUP=/fs/mp/fordhmi/qml/hmirvc/RVCPopup.qml
RVCPOPUP_MD5=4af7d8e09f2ce71b853b154651672511
VIEWBTNS=/fs/mp/fordhmi/qml/hmirvc/components/CameraViewButtons.qml
VIEWBTNS_MD5=bbfa8c58f6d31082f11989d5d497b774
PAGE=/fs/mp/fordhmi/qml/hmisettings/driverassistance/RVCSettings.qml
PAGE_MD5=4fa73e6c92a6a9818e08e2e5488d30a0
BLOCK=front-tire-guides                                      # our rows on the camera settings page
LAYER_MARK="front tire guides layer"                         # our Loader in the camera popup
BUTTON_MARK="front tire guides switch"                       # our button in the view row

# Ford's startup script rewritten safely: the new text (a file) must differ from the old by exactly $2 lines and keep
# Ford's launch line. It is written beside the old one and swapped in with one rename, so a power cut leaves either
# the old script or the new one whole, never half of one (SYNC's services and the USB installer start from it).
startup_swap() {   # startup_swap <new text> <lines added: 1, -1...>
    _o=$(wc -l < "$STARTUP") && _n=$(wc -l < "$1") && [ "$((_o + $2))" = "$((_n))" ] || return 1
    [ "$(grep -c "$ANCHOR" "$1")" = "$(grep -c "$ANCHOR" "$STARTUP")" ] || return 1
    cp -p "$STARTUP" "$STARTUP.new_by_mod" && cat "$1" > "$STARTUP.new_by_mod" && sync &&
        [ "$(wc -c < "$1")" = "$(wc -c < "$STARTUP.new_by_mod")" ] && mv -f "$STARTUP.new_by_mod" "$STARTUP" && sync
}
startup_line_out() {   # our line out of Ford's startup script, wherever it is
    [ -f "$STARTUP" ] && grep -q "$MARK" "$STARTUP" || return 0
    grep -v "$MARK" "$STARTUP" > /tmp/front_tire_guides_startup && startup_swap /tmp/front_tire_guides_startup "-$(grep -c "$MARK" "$STARTUP")"
    _rc=$?
    rm -f "$STARTUP.new_by_mod"
    return $_rc
}
# Our program and its restart loop, stopped (the loop is a shell script, found by its arguments).
stop_ours() {
    for pid in $( (pidin arg 2>/dev/null || ps -eo pid=,args= 2>/dev/null) |
            awk '/FrontTireGuides\/start\.sh|FrontTireGuides\/bin\/guidesd/ && !/awk/ {print $1}'); do
        kill -9 "$pid" 2>/dev/null
    done
    slay -f guidesd > /dev/null 2>&1 || pkill -f bin/guidesd > /dev/null 2>&1
    rm -rf "$RUN"
}
