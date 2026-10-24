#!/usr/bin/env bash
# Runs tests/cases.txt (platforms: all, unix) against bin/sd on a temporary copy of tests/root.
# Bash 3.2 compatible.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sd test-XXXXXX")
trap 'cd "$here"; rm -rf "$tmp"' EXIT
mkdir "$tmp/work" && cp -R "$here/root" "$tmp/work/sd root" || exit 1
export SD_ROOT="$tmp/work/sd root" SD_BASH_CORE=1
unset VISUAL EDITOR SD_NO_HOOKS
cd "$tmp/work" || exit 1
set -f                                  # command words are never glob-expanded
nl=$'\n'; tab=$'\t'; cr=$'\r'; bs='\'

trim() { _t=${1#"${1%%[![:space:]]*}"}; _t=${_t%"${_t##*[![:space:]]}"}; }

pass=0; fail=0; n=0
while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    trim "$line"
    case "$_t" in ''|'#'*) continue;; esac
    trim "${line%%|*}"; platform=$_t; rest=${line#*|}
    trim "${rest%%|*}"; code=$_t; rest=${rest#*|}
    trim "${rest%%|*}"; cmd=$_t; rest=${rest#*|}
    trim "$rest"; exp=$_t
    case "$platform" in all|unix) ;; *) continue;; esac
    words=($cmd)
    for i in "${!words[@]}"; do [ "${words[$i]}" = '""' ] && words[$i]=''; done
    exp=${exp//\\t/$tab}; exp=${exp//\\n/$nl}
    not=0; case "$exp" in '!'*) not=1; exp=${exp#!};; esac

    out=$("$repo/bin/sd" "${words[@]}" 2>"$tmp/stderr" </dev/null); rc=$?
    err=$(cat "$tmp/stderr"); out=${out//$cr/}; err=${err//$cr/}
    found=0
    case "$out" in *"$exp"*) found=1;; esac
    case "$err" in *"$exp"*) found=1;; esac

    if [ "$rc" = "$code" ] && { [ -z "$exp" ] || [ "$found" != "$not" ]; }; then
        pass=$((pass + 1)); echo "PASS line $n  sd $cmd"
    else
        fail=$((fail + 1)); echo "FAIL line $n  sd $cmd"
        echo "  exit: expected $code, got $rc"
        d=${exp//$tab/${bs}t}; d=${d//$nl/${bs}n}
        [ $not = 1 ] && echo "  expected NOT: $d" || echo "  expected: $d"
        echo "  stdout: $out"
        echo "  stderr: $err"
    fi
done < "$here/cases.txt"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
