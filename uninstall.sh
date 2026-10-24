#!/usr/bin/env bash
# Removes what install.sh set up: entry point, ~/.bashrc block and machine config.
# The sd root and the scripts in it are never touched. bash 3.2 compatible.
repo=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin=$HOME/.local/bin
configFile=${XDG_CONFIG_HOME:-$HOME/.config}/sd/config
rc=$HOME/.bashrc

name=sd root=
re='^[[:space:]]*(root|name)[[:space:]]*=[[:space:]]*(.*[^[:space:]])'
if [ -r "$configFile" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ $re ]]; then
            if [ "${BASH_REMATCH[1]}" = root ]; then root=${BASH_REMATCH[2]}; else name=${BASH_REMATCH[2]}; fi
        fi
    done < "$configFile"
fi

# Entry point (only our own symlink) and config, then the config folder if it is left empty.
if [ -h "$bin/$name" ]; then case $(readlink "$bin/$name") in "$repo"/*) rm -f "$bin/$name";; esac; fi
rm -f "$configFile"
rmdir "$(dirname "$configFile")" 2>/dev/null

# ~/.bashrc: drop the block (and the blank line install.sh put before it).
if [ -f "$rc" ] && grep -q '^# >>> sd >>>$' "$rc" && grep -q '^# <<< sd <<<$' "$rc"; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/sd-rc.XXXXXX") || { echo "uninstall.sh: cannot create a temporary file" >&2; exit 1; }
    awk '/^# >>> sd >>>$/ && !skip { held = 0; skip = 1; next }
         skip { if (/^# <<< sd <<<$/) skip = 0; next }
         /^$/ { if (held) print ""; held = 1; next }
         { if (held) print ""; held = 0; print }
         END { if (held) print "" }' "$rc" > "$tmp"
    if [ -z "$(tr -d '[:space:]' < "$tmp")" ]; then rm -f "$rc"   # nothing else was in it
    else cat "$tmp" > "$rc"; fi   # not mv: keeps a symlinked or restricted ~/.bashrc as it is
    rm -f "$tmp"
fi

echo "Removed '$name' (entry point, profile block, machine config)."
if [ -n "$root" ]; then echo "Your sd root was NOT touched; your scripts are still in $root"
else echo "Your sd root, if you made one, was NOT touched."; fi
echo "Restart your shell for the change to take effect."
