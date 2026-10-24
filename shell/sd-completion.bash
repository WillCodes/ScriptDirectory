# bash completion for sd (SPEC §8.4). Sourced from ~/.bashrc by install.sh; bash 3.2 compatible.
# Thin wrapper around `bin/sd --complete`, called directly: under git-bash that answers in bash too, with the
# Windows rules, instead of starting PowerShell per Tab. The command name comes from the machine config (§3.1).

_SD_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/sd
_sd_name=sd
_sd_re='^[[:space:]]*name[[:space:]]*=[[:space:]]*(.*[^[:space:]])'
_sd_config=${XDG_CONFIG_HOME:-$HOME/.config}/sd/config
case $OSTYPE in msys*|cygwin*) [ -n "$APPDATA" ] && _sd_config=$(cygpath -u "$APPDATA")/sd/config ;; esac   # git-bash
if [ -r "$_sd_config" ]; then
    while IFS= read -r _sd_line || [ -n "$_sd_line" ]; do
        [[ $_sd_line =~ $_sd_re ]] && _sd_name=${BASH_REMATCH[1]}
    done < "$_sd_config"
fi

_sd_complete() {
    local cur=${COMP_WORDS[COMP_CWORD]} out n t d l i p width=0 mark half pad
    local names=() lines=() types=() descs=() key="$HISTCMD $COMP_POINT $COMP_LINE"
    COMPREPLY=()
    # Readline prints the list again on every Tab. Once it's shown for this line (at this prompt: HISTCMD), stay quiet.
    [ -z "$cur" ] && [ "$key" = "${_SD_LISTED:-}" ] && return 0
    out=$("$_SD_BIN" --complete "${COMP_WORDS[@]:1:COMP_CWORD-1}" "$cur" 2>/dev/null) || return 0
    out=${out//$'\r'/}   # in case a CRLF .help or script line slips through
    while IFS=$'\t' read -r n t d; do
        [ -n "$n" ] || continue
        names[${#names[@]}]=$n; types[${#types[@]}]=$t; descs[${#descs[@]}]=$d
        [ "$t" = dir ] && n=$n/
        [ ${#n} -gt "$width" ] && width=${#n}
        lines[${#lines[@]}]=$n
    done <<< "$out"
    [ ${#names[@]} -gt 0 ] || return 0
    # In the middle of a word, Tab only completes it, never lists: one match is filled in (with a space); several
    # fill in what they share, without a space (compopt, bash 4+), or nothing if that adds nothing.
    if [ -n "$cur" ]; then
        if [ ${#names[@]} -eq 1 ]; then COMPREPLY=("${names[0]}"); return 0; fi
        p=${names[0]}
        for n in "${names[@]}"; do while [[ $n != "$p"* ]]; do p=${p%?}; done; done
        [ ${#p} -gt ${#cur} ] && compopt -o nospace 2>/dev/null && COMPREPLY=("$p")
        return 0
    fi
    # After a space, Tab lists what comes next.
    _SD_LISTED=$key
    # Keep sd's order (namespaces first) instead of readline's alphabetical one: bash 4.4+.
    if [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }; then
        compopt -o nosort 2>/dev/null
    fi
    half=$(( ${COLUMNS:-80} / 2 ))
    for i in "${!names[@]}"; do   # §7 display lines: padded name, marker, description
        case ${types[i]} in script) mark=▸;; conflict) mark='!';; *) mark=' ';; esac
        printf -v l '%-*s %s %s' "$width" "${lines[i]}" "$mark" "${descs[i]}"
        l=${l%"${l##*[![:space:]]}"}
        # Readline fits as many columns as the longest entry allows; past half the screen, that's one per row.
        [ ${#l} -lt $half ] && printf -v pad '%*s' $((half - ${#l})) '' && l=$l$pad
        COMPREPLY[i]=$l
    done
    # The lines are shown, never inserted: readline would insert their longest common prefix (or a lone line),
    # and a blank extra entry makes that prefix empty.
    COMPREPLY[${#COMPREPLY[@]}]=' '
}

complete -F _sd_complete "$_sd_name"
# List the matches on the first Tab, not the second. This is a readline setting, so it applies to every command.
[[ $- == *i* ]] && bind 'set show-all-if-ambiguous on' 2>/dev/null
unset _sd_name _sd_re _sd_line _sd_config
