#!/bin/sh
# Starts Front Tire Guides' program with SYNC: run once at boot, in the background, from SYNC's startup script (or
# by the F-Mods launcher). The program is restarted if it ever ends, with a pause so a fault can never spin.
T=/fs/images/fmods_apps_data/FrontTireGuides
RUN=/fs/tmpfs/frontguides
mkdir -p "$RUN"
# once a start: a second run (the startup line and the launcher both there, say) would run two programs.
# /fs/tmpfs is empty after every SYNC restart; the installer and the uninstaller take the mark away.
mkdir "$RUN/started" 2>/dev/null || exit 0
# QNX's ordinary priority (10; `on -p` sets it). The program raises its two time-critical threads itself.
(
    while :; do
        on -p 10 "$T/bin/guidesd" > /dev/null 2>&1
        sleep 10
    done
) &
