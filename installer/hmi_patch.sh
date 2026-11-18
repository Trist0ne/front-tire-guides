# Adding one snippet to a Ford HMI QML file, and putting the file back. Sourced by autoinstall.sh and uninstall.sh
# (QNX 6.5 sh, a ksh: no readlink or stat, so a link's target is read from ls -l).
#
#   hmi_patch_in  <file> <snippet> <marker> <backup dir> <name> [<block>]   0 = patched or already patched, 1 = refused
#   hmi_patch_out <file> <backup dir> <name>                                0 = restored or nothing to restore
#
# The backup is the file itself (<name>.orig) or, when the file is a symbolic link,
# its target (<name>.link), so uninstall puts back exactly what was there. The snippet goes just before the root
# item's closing brace, or with <block> (text of the line that opens a block, e.g. "model: HmiActionModel {") just
# before that block's closing brace (found by counting braces; it must be a line of its own), with the file's own
# line ends (Ford's QML is CRLF), and is found again by <marker>.

hmi_link_target() {   # prints a symbolic link's target, nothing for anything else
    [ -h "$1" ] || return 0
    ls -l "$1" | sed 's/.* -> //'
}

hmi_patch_in() {
    f=$1 snip=$2 marker=$3 bk=$4 name=$5 block=${6:-}
    [ -f "$f" ] && [ -f "$snip" ] || return 1
    grep -q "$marker" "$f" && return 0
    mkdir -p "$bk"
    target=$(hmi_link_target "$f")
    if [ -n "$target" ]; then
        [ -f "$bk/$name.link" ] || printf '%s\n' "$target" > "$bk/$name.link"
    else
        if [ ! -f "$bk/$name.orig" ]; then   # the backup must be whole before Ford's file is touched (a full disk)
            cp -p "$f" "$bk/$name.orig" && cmp -s "$f" "$bk/$name.orig" || { rm -f "$bk/$name.orig"; return 1; }
        fi
    fi
    tmp=$f.new_by_mod   # beside Ford's file, so the last step is a rename: never a missing or half-written file
    # the last line that is only "}" closes the root item (or, with a block, the line that brings that block's brace
    # count back to zero): the snippet goes in front of it
    awk -v snip="$snip" -v block="$block" '
        {
            line[NR] = $0; t = $0; if (sub(/\r$/, "", t)) crlf = 1
            if (block == "") { if (t ~ /^[ \t]*}[ \t]*$/) last = NR; next }
            if (last || bad) next
            if (!open && index(t, block)) open = 1
            if (!open) next
            u = t; depth += gsub(/[{]/, "", u); u = t; depth -= gsub(/[}]/, "", u)
            if (depth <= 0) { if (t ~ /^[ \t]*}[ \t]*$/) last = NR; else bad = 1 }
        }
        END {
            if (!last) exit 1
            for (i = 1; i <= NR; i++) {
                if (i == last) while ((getline s < snip) > 0) print s (crlf ? "\r" : "")
                print line[i]
            }
        }' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
    grep -q "$marker" "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

hmi_patch_out() {
    f=$1 bk=$2 name=$3
    if [ -f "$bk/$name.link" ]; then
        rm -f "$f" && ln -s "$(cat "$bk/$name.link")" "$f" && rm -f "$bk/$name.link"
    elif [ -f "$bk/$name.orig" ]; then
        cp -p "$bk/$name.orig" "$f.new_by_mod" && mv -f "$f.new_by_mod" "$f" && rm -f "$bk/$name.orig"
    fi
}
