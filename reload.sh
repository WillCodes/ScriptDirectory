#!/usr/bin/env bash
# Uninstalls and installs sd again, e.g. after pulling changes. Keeps the root and name from the machine config
# (read before uninstall.sh removes it); --root / --name change them. The sd root is never touched.
# bash 3.2 compatible.
#   ./reload.sh [--root <path>] [--name <name>]
repo=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
configFile=${XDG_CONFIG_HOME:-$HOME/.config}/sd/config

die() { echo "reload.sh: $*" >&2; exit 1; }

root= name=
re='^[[:space:]]*(root|name)[[:space:]]*=[[:space:]]*(.*[^[:space:]])'
if [ -r "$configFile" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ $re ]]; then
            if [ "${BASH_REMATCH[1]}" = root ]; then root=${BASH_REMATCH[2]}; else name=${BASH_REMATCH[2]}; fi
        fi
    done < "$configFile"
fi
while [ $# -gt 0 ]; do
    case $1 in
        --root) [ $# -ge 2 ] || die "--root needs a value"; root=$2; shift 2;;
        --name) [ $# -ge 2 ] || die "--name needs a value"; name=$2; shift 2;;
        *) die "unknown argument '$1' (usage: ./reload.sh [--root <path>] [--name <name>])";;
    esac
done

values=()   # anything still unknown is asked for by install.sh
[ -n "$root" ] && values+=(--root "$root")
[ -n "$name" ] && values+=(--name "$name")

bash "$repo/uninstall.sh" || die "uninstall.sh failed"
echo
exec bash "$repo/install.sh" ${values[@]+"${values[@]}"}
