# Blocks of ours in a Ford HMI QML file that more than one mod adds to. Front Tire Guides and Enhanced Camera Control
# each put their own rows on SYNC's camera settings page, and each must come and go without touching the other's.
# Sourced by autoinstall.sh and uninstall.sh (QNX 6.5 sh, a ksh). The same file ships in both mods.
#
#   hmi_block_in  <file> <snippet> <name> <stock md5> [where]   0 = in (or replaced), 1 = refused, nothing changed
#   hmi_block_out <file> <name> <stock md5>                     0 = out (or was not there), 1 = failed, nothing changed
#   hmi_block_has <file> <name>                                 0 = the block is in the file
#
# A block is the snippet between two marker lines, "// mod-begin <name>" and "// mod-end <name>", put just
# before the root item's closing brace, with the file's own line ends (Ford's QML is CRLF). <where> puts it elsewhere:
#   first             before any other block of ours at the end, so the order on the page does not depend on which
#                     package was installed first
#   imports           after the file's last "import" line (for an import of ours)
#   after:<text>      after the item that has <text> on one of its lines (an objectName): after the first line that
#                     is only a closing brace at that item's own indent (4 spaces) following it. Refused if not found.
# The file is only ever touched if, with every block of ours taken out, it is Ford's stock file (md5): so it is
# always "Ford's file plus whole blocks of ours", and taking the last block out leaves Ford's file byte for byte.
# The new file is written beside the old one and renamed in: never a missing or half-written page.

hmi_block_md5() { openssl md5 2>/dev/null | awk '{print $NF}'; }

# the file without block <name> ("*" = without any block of ours), to stdout
hmi_block_strip() {
    awk -v name="$2" '
        {
            t = $0; sub(/\r$/, "", t)
            if (!skip && t ~ /^[ \t]*\/\/ mod-begin /) {
                n = t; sub(/^[ \t]*\/\/ mod-begin /, "", n)
                if (name == "*" || n == name) { skip = 1; next }
            }
            if (skip) { if (t ~ /^[ \t]*\/\/ mod-end /) skip = 0; next }
            print
        }' "$1"
}

hmi_block_has() { grep -q "^[ 	]*// mod-begin $2" "$1" 2>/dev/null; }

hmi_block_stock() {   # 0 when the file is Ford's stock file plus (maybe) whole blocks of ours
    [ -f "$1" ] && [ "$(hmi_block_strip "$1" "*" | hmi_block_md5)" = "$2" ]
}

hmi_block_in() {
    f=$1 snip=$2 name=$3 md5=$4 where=${5:-}
    [ -f "$snip" ] || return 1
    hmi_block_stock "$f" "$md5" || return 1
    tmp=$f.new_by_mod
    hmi_block_strip "$f" "$name" > "$tmp.0" || { rm -f "$tmp.0"; return 1; }
    awk -v snip="$snip" -v name="$name" -v first="$where" '
        {
            line[NR] = $0; t = $0; if (sub(/\r$/, "", t)) crlf = 1
            if (t ~ /^[ \t]*}[ \t]*$/) last = NR
            if (first == "first" && !at && t ~ /^[ \t]*\/\/ mod-begin / && t !~ /-import$/) at = NR
            if (first == "imports" && t ~ /^import /) at = NR + 1
            if (substr(first, 1, 6) == "after:") {
                if (!seen && index(t, substr(first, 7))) seen = 1
                else if (seen && !at && t ~ /^    }[ \t]*$/) at = NR + 1
            }
        }
        END {
            if (!last) exit 1
            if (!at && (first == "imports" || substr(first, 1, 6) == "after:")) exit 1
            if (!at) at = last
            e = crlf ? "\r" : ""
            for (i = 1; i <= NR; i++) {
                if (i == at) {
                    print "    // mod-begin " name e
                    while ((getline s < snip) > 0) print s e
                    print "    // mod-end " name e
                }
                print line[i]
            }
        }' "$tmp.0" > "$tmp" || { rm -f "$tmp" "$tmp.0"; return 1; }
    rm -f "$tmp.0"
    # what is about to go in must itself be "Ford's file plus whole blocks", this block among them
    hmi_block_has "$tmp" "$name" && hmi_block_stock "$tmp" "$md5" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

hmi_block_out() {
    f=$1 name=$2 md5=$3
    [ -f "$f" ] || return 0
    hmi_block_has "$f" "$name" || return 0
    hmi_block_stock "$f" "$md5" || return 1
    tmp=$f.new_by_mod
    hmi_block_strip "$f" "$name" > "$tmp" && hmi_block_stock "$tmp" "$md5" && ! hmi_block_has "$tmp" "$name" ||
        { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

# ---- the "Front Camera" row in Driver Assistance and its page -------------------------------------------------
# Shared by the two mods like the blocks above: whichever installs first puts it in, and it goes when the last
# mod's rows leave the page. Four blocks in two Ford files, and one file of our own beside them.
FM_DIR=/fs/mp/fordhmi/qml/hmisettings/driverassistance
FM_MENU=$FM_DIR/DriverAssistSettingsMenu.qml
FM_MENU_MD5=8635ac0dd1ef6187a0cb825085e19f75     # Ford's stock file, SYNC 3.4.23188
FM_PAGE=$FM_DIR/RVCSettings.qml
FM_PAGE_MD5=4fa73e6c92a6a9818e08e2e5488d30a0     # Ford's stock file, SYNC 3.4.23188
FM_JS=$FM_DIR/front_camera.js
FM_ROW=$FM_DIR/FrontCameraRow.qml

front_menu_has() { hmi_block_has "$FM_MENU" front-camera-row && hmi_block_has "$FM_PAGE" front-camera-page && [ -f "$FM_JS" ] && [ -f "$FM_ROW" ]; }

# front_menu_out [force]: takes the row and the page's two faces out, unless rows of one of the two mods are still
# on the page ("force": whatever is there). 0 = out, or rightly left in.
front_menu_out() {
    if [ "${1:-}" != force ] && { hmi_block_has "$FM_PAGE" front-tire-guides || hmi_block_has "$FM_PAGE" enhanced-camera-control; }; then return 0; fi
    fm_rc=0
    hmi_block_out "$FM_MENU" front-camera-row "$FM_MENU_MD5" || fm_rc=1
    hmi_block_out "$FM_MENU" front-camera-import "$FM_MENU_MD5" || fm_rc=1
    hmi_block_out "$FM_PAGE" front-camera-page "$FM_PAGE_MD5" || fm_rc=1
    hmi_block_out "$FM_PAGE" front-camera-import "$FM_PAGE_MD5" || fm_rc=1
    if ! grep -q front_camera.js "$FM_MENU" "$FM_PAGE" 2>/dev/null; then rm -f "$FM_JS" "$FM_ROW"; fi
    return $fm_rc
}

# front_menu_in <dir with front_camera.js, FrontCameraRow.qml, frontmenu_import.qml.in, frontmenu_row.qml.in, frontpage.qml.in>
# 0 = in. 1 = not possible (a file is not Ford's stock file plus blocks of ours, or a step failed): everything of it
# taken out again, the two files as they were.
front_menu_in() {
    fm_src=$1
    hmi_block_stock "$FM_MENU" "$FM_MENU_MD5" && hmi_block_stock "$FM_PAGE" "$FM_PAGE_MD5" || return 1
    fm_had=0; front_menu_has && fm_had=1
    cp "$fm_src/front_camera.js" "$FM_JS" && cp "$fm_src/FrontCameraRow.qml" "$FM_ROW" && chmod 644 "$FM_JS" "$FM_ROW" &&
        hmi_block_in "$FM_PAGE" "$fm_src/frontmenu_import.qml.in" front-camera-import "$FM_PAGE_MD5" imports &&
        hmi_block_in "$FM_PAGE" "$fm_src/frontpage.qml.in" front-camera-page "$FM_PAGE_MD5" first &&
        hmi_block_in "$FM_MENU" "$fm_src/frontmenu_import.qml.in" front-camera-import "$FM_MENU_MD5" imports &&
        hmi_block_in "$FM_MENU" "$fm_src/frontmenu_row.qml.in" front-camera-row "$FM_MENU_MD5" "after:DriverAssistSettingsMenu_rearViewCamera" &&
        return 0
    [ "$fm_had" = 1 ] || front_menu_out force
    return 1
}
