#!/usr/bin/env bash
# Sets up sd on Linux/macOS: sd root, machine config, entry point, PATH and ~/.bashrc (SPEC §12).
# Safe to re-run; re-run with a new --name to rename the command. bash 3.2 compatible.
#   ./install.sh [--root <path>] [--name <name>]
repo=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bin=$HOME/.local/bin
configFile=${XDG_CONFIG_HOME:-$HOME/.config}/sd/config
rc=$HOME/.bashrc
warnings=()

die() { echo "install.sh: $*" >&2; exit 1; }
warn() { warnings[${#warnings[@]}]=$1; echo "warning: $1" >&2; }
ours() { [ -h "$1" ] && case $(readlink "$1") in "$repo"/*) return 0;; esac; return 1; }   # a symlink into this repo

Root= Name=
while [ $# -gt 0 ]; do
    case $1 in
        --root) [ $# -ge 2 ] || die "--root needs a value"; Root=$2; shift 2;;
        --name) [ $# -ge 2 ] || die "--name needs a value"; Name=$2; shift 2;;
        *) die "unknown argument '$1' (usage: ./install.sh [--root <path>] [--name <name>])";;
    esac
done

# ---- 1. Requirements ----------------------------------------------------------------------------
if [ "${BASH_VERSINFO[0]}" -lt 3 ] || { [ "${BASH_VERSINFO[0]}" -eq 3 ] && [ "${BASH_VERSINFO[1]}" -lt 2 ]; }; then
    warn "bash $BASH_VERSION is older than 3.2: sd may not work"
fi
command -v tar >/dev/null 2>&1 || warn "tar not found: --export and --import will not work"
command -v gzip >/dev/null 2>&1 || warn "gzip not found: --export and --import will not work"

# ---- 2. Values ----------------------------------------------------------------------------------
oldRoot= oldName=
re='^[[:space:]]*(root|name)[[:space:]]*=[[:space:]]*(.*[^[:space:]])'
if [ -r "$configFile" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ $re ]]; then
            if [ "${BASH_REMATCH[1]}" = root ]; then oldRoot=${BASH_REMATCH[2]}; else oldName=${BASH_REMATCH[2]}; fi
        fi
    done < "$configFile"
fi
if [ -z "$Root" ]; then
    default=${oldRoot:-$HOME/sd}
    read -r -p "sd root [$default]: " Root
    Root=${Root:-$default}
fi
if [ -z "$Name" ]; then
    default=${oldName:-sd}
    read -r -p "Command name [$default]: " Name
    Name=${Name:-$default}
fi
re='^[^[:space:]\/:*?"<>|-][^[:space:]\/:*?"<>|]*$'
[[ $Name =~ $re ]] || die "Invalid name '$Name': no whitespace or path characters, and it must not start with '-'."
case $Root in "~") Root=$HOME;; "~/"*) Root=$HOME/${Root#"~/"};; /*) ;; *) Root=$PWD/$Root;; esac
Root=${Root%/}; Root=${Root:-/}
if [ -d "$Root" ]; then Root=$(cd "$Root" && pwd)       # no realpath on old macOS
elif [ -d "$(dirname "$Root")" ]; then Root=$(cd "$(dirname "$Root")" && pwd)/$(basename "$Root"); fi
[ ! -e "$Root" ] || [ -d "$Root" ] || die "'$Root' exists and is not a folder."

# ---- 3. Name clash ------------------------------------------------------------------------------
# Anything but our own entry point (which includes a foreign file where that entry point would go).
other=
{ [ -e "$bin/$Name" ] || [ -h "$bin/$Name" ]; } && ! ours "$bin/$Name" && other=$bin/$Name
while IFS= read -r p; do
    if [ -n "$p" ] && ! { [ "$p" = "$bin/$Name" ] && ours "$p"; }; then other=$p; break; fi
done < <(type -ap "$Name" 2>/dev/null)
[ -n "$other" ] || case " $(type -at "$Name" 2>/dev/null | tr '\n' ' ')" in *" builtin "*|*" keyword "*) other="a shell builtin or keyword";; esac
if [ -n "$other" ]; then
    warn "'$Name' already resolves to another command: $other"
    read -r -p 'Use this name anyway? [y/N] ' answer
    case $answer in [yY]*) ;; *) echo Aborted.; exit 1;; esac
fi

# ---- 4. Root ------------------------------------------------------------------------------------
# Only a new (or empty) root gets the example; nothing in an existing root is ever overwritten.
if [ ! -d "$Root" ] || [ -z "$(ls -A "$Root")" ]; then
    mkdir -p "$Root" || die "cannot create '$Root'"
    sed 's/TODO: describe this script/Example script: prints its arguments/' "$repo/templates/script.sh" > "$Root/hello.sh"
    chmod +x "$Root/hello.sh"
fi
# Hook scripts and hooks.conf live in hooks/ (§9). Any root gets them: new files overwrite nothing.
[ -d "$Root/hooks" ] || mkdir "$Root/hooks" || die "cannot create '$Root/hooks'"
if [ -f "$Root/hooks.conf" ] && [ ! -e "$Root/hooks/hooks.conf" ]; then   # where it used to be
    mv "$Root/hooks.conf" "$Root/hooks/hooks.conf" || die "cannot move '$Root/hooks.conf' into hooks/"
    echo "Moved $Root/hooks.conf to $Root/hooks/hooks.conf."
elif [ ! -e "$Root/hooks/hooks.conf" ]; then
    cat > "$Root/hooks/hooks.conf" <<'HOOKS'
# Hooks: scripts in this folder that run before or after other scripts.
# One hook per line, whitespace-separated columns ('#' starts a comment):
#   state  when    target      hook
#   ON     BEFORE  dev/build   lint
#   OFF    AFTER   dev/*       notify
# state: ON | OFF.  when: BEFORE | AFTER.
# target: a script named from the sd root as you run it, or a glob; '*' matches any characters, including '/'.
# hook: a script in this folder, named from here (lint for lint.sh).
# Add one with: --hooks add BEFORE dev/build lint
# Manage entries with: --hooks, --hooks add|rm|on|off|edit
HOOKS
fi

# ---- 5. Machine config --------------------------------------------------------------------------
mkdir -p "$(dirname "$configFile")"
printf '# sd machine config\nroot = %s\nname = %s\n' "$Root" "$Name" > "$configFile"

# ---- 6. Entry point -----------------------------------------------------------------------------
mkdir -p "$bin"
if [ -n "$oldName" ] && [ "$oldName" != "$Name" ] && ours "$bin/$oldName"; then rm -f "$bin/$oldName"; fi
[ -x "$repo/bin/sd" ] || chmod +x "$repo/bin/sd"
ln -sf "$repo/bin/sd" "$bin/$Name" || die "cannot create $bin/$Name"

# ---- 7. PATH and ~/.bashrc ----------------------------------------------------------------------
q=$(printf %s "$repo/shell/sd-completion.bash" | sed "s/'/'\\''/g")   # single-quote safe
block="# >>> sd >>>
case \":\$PATH:\" in *\":\$HOME/.local/bin:\"*) ;; *) export PATH=\"\$HOME/.local/bin:\$PATH\" ;; esac
source '$q'
# <<< sd <<<"
tmp=$(mktemp "${TMPDIR:-/tmp}/sd-rc.XXXXXX") || die "cannot create a temporary file"
if [ -f "$rc" ] && grep -q '^# >>> sd >>>$' "$rc" && grep -q '^# <<< sd <<<$' "$rc"; then
    BLK=$block awk '/^# >>> sd >>>$/ && !done { print ENVIRON["BLK"]; skip = 1; done = 1; next }
                    skip { if (/^# <<< sd <<<$/) skip = 0; next }
                    { print }' "$rc" > "$tmp"
else
    if [ -s "$rc" ]; then
        cat "$rc" > "$tmp"
        [ -z "$(tail -c1 "$rc")" ] || echo >> "$tmp"   # the file's last line gets its newline
        echo >> "$tmp"
    fi
    printf '%s\n' "$block" >> "$tmp"
fi
cat "$tmp" > "$rc"   # not mv: keeps a symlinked or restricted ~/.bashrc as it is
rm -f "$tmp"

# ---- 8. Summary ---------------------------------------------------------------------------------
cat <<EOF2

sd is set up.
  root:     $Root
  hooks:    $Root/hooks
  name:     $Name
  config:   $configFile
  bin:      $bin/$Name -> $repo/bin/sd
  profile:  $rc
EOF2
if [ ${#warnings[@]} -gt 0 ]; then
    echo "Warnings:"
    for w in "${warnings[@]}"; do echo "  - $w"; done
fi
[ "$(uname -s)" != Darwin ] || echo "Note: on macOS, login shells read ~/.bash_profile; make sure it sources ~/.bashrc."
echo "Restart your shell to use \`$Name\`."
