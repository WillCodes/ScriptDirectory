# bash completion for sd (SPEC §8.4). Sourced from ~/.bashrc by install.sh; bash 3.2 compatible.
# Thin wrapper around `<name> --complete`; the command name comes from the machine config (§3.1).

_sd_name=sd
_sd_re='^[[:space:]]*name[[:space:]]*=[[:space:]]*(.*[^[:space:]])'
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/sd/config" ]; then
    while IFS= read -r _sd_line || [ -n "$_sd_line" ]; do
        [[ $_sd_line =~ $_sd_re ]] && _sd_name=${BASH_REMATCH[1]}
    done < "${XDG_CONFIG_HOME:-$HOME/.config}/sd/config"
fi

_sd_complete() {
    local cur=${COMP_WORDS[COMP_CWORD]} out n t d l i width=0 mark all=1
    local names=() lines=() types=() descs=()
    out=$("${COMP_WORDS[0]}" --complete "${COMP_WORDS[@]:1:COMP_CWORD-1}" "$cur" 2>/dev/null) || return 0
    while IFS=$'\t' read -r n t d; do
        [ -n "$n" ] || continue
        names[${#names[@]}]=$n; types[${#types[@]}]=$t; descs[${#descs[@]}]=$d
        [ "$t" = dir ] && n=$n/
        [ ${#n} -gt "$width" ] && width=${#n}
        lines[${#lines[@]}]=$n
    done <<< "$out"
    COMPREPLY=()
    # A lone match is inserted, unless nothing was typed: then it's a folder's contents, shown like any other.
    if [ ${#names[@]} -eq 1 ] && [ -n "$cur" ]; then COMPREPLY=("${names[0]}"); return 0; fi
    for i in "${!names[@]}"; do   # §7 display lines: padded name, marker, description
        case ${types[i]} in script) mark=▸;; conflict) mark='!';; *) mark=' ';; esac
        printf -v l '%-*s %s %s' "$width" "${lines[i]}" "$mark" "${descs[i]}"
        COMPREPLY[i]=${l%"${l##*[![:space:]]}"}
        [[ ${COMPREPLY[i]} == "$cur"* ]] || all=0
    done
    # Readline replaces the typed word with the longest common prefix of COMPREPLY. Fuzzy (and
    # differently-cased) matches don't start with the typed word, so that prefix could shorten or
    # change it. A blank extra entry makes the prefix empty, which readline treats as "insert nothing".
    # A single display line needs it too, or readline would insert that line.
    if [ ${#COMPREPLY[@]} -eq 1 ] || [ $all = 0 ]; then COMPREPLY[${#COMPREPLY[@]}]=' '; fi
}

complete -F _sd_complete "$_sd_name"
unset _sd_name _sd_re _sd_line
