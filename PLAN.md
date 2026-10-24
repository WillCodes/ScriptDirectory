# sd — Implementation Plan

Builds what [SPEC.md](SPEC.md) describes. Section references (§n) point to the spec.

## Repository layout

```
bin/
  sd                    bash core (Unix). Under git-bash on Windows, hands off to the PowerShell core.
src/
  sd.psm1               PowerShell core + `<name>` function + completer + Tab handler
  sd.ps1                thin entry for cmd / git-bash: imports sd.psm1, runs it, exits with its code
shell/
  sd-completion.bash    bash completion, wraps `--complete`
templates/
  script.sh  script.bat templates for --new (§10.2)
install.ps1  install.sh
uninstall.ps1  uninstall.sh
tests/
  root/                 sample sd root (fixture)
  cases.txt             shared test cases
  run.ps1  run.sh       test runners
README.md  SPEC.md  PLAN.md
.gitattributes          *.sh, bin/sd, templates/* → eol=lf; *.bat, *.cmd → eol=crlf
```

Both cores are kept as single files where reasonable. The aim is a tool someone can read in one sitting.

## Phases

Each phase ends with its test cases passing on the platforms it covers.
Windows is developed and tested first (your daily setup). The bash core follows, written against the same cases.

### Phase 1: Fixture, test cases, runners

- `tests/root/` covering:
  - a namespace with `.help`
  - loose `.sh` only, `.bat` only, and `.bat` + `.sh` scripts
  - a bundle with a private helper
  - a conflict
  - a hidden dot-file and an ignored `.ps1`
  - `hooks/` with a passing and a failing hook
  - `hooks.conf`

  Each fixture script prints a marker naming its own file and arguments (e.g. `build.sh: 1 2`), so tests can tell which file ran.
- `tests/cases.txt`, one case per line:

  ```
  # platform | exit | command          | expected stdout (substring; empty = don't check)
  all        | 0    | dev build 1 2    | build.sh: 1 2
  win        | 0    | dev both x       | both.bat: x
  unix       | 1    | winonly          |
  ```

- `run.ps1` / `run.sh`, each about 40 lines. They copy `tests/root` to a temporary folder, set `SD_ROOT` to it, run every case for the current platform through the core, and report pass/fail with a diff of the output. Tests that change files (`--hooks add`, `--new`, `--import`) run in order on the same copy.
- Target: about 25 cases. Coverage: resolution, priority, bundles, conflicts, argument passing, listings, `--complete` prefix + fuzzy, hook order / abort / after-on-failure, `--hooks` editing, `--which`, `--new`, export→import round trip.

**Done when:** the runners execute and report every case as failing, since there's no core yet.

### Phase 2: PowerShell core

In `src/sd.psm1`, one exported `Invoke-Sd` plus internal functions:

- Reading the machine config + `SD_ROOT` (§3.1).
- Resolution (§5): `Resolve-SdEntry` returns `{ Kind, Name, File, Runner, Args }` or an error.
- Descriptions (§6), listing (§7), `--complete` + matching (§8.1–8.2).
- Running scripts (§11).
  - `.bat` runs via `&`, `.sh` via `bash`.
  - `SD_*` variables are set before the run and restored afterwards, because the function runs inside the user's shell.
  - The exit code comes from `$LASTEXITCODE`.
- `--help`, `--which` (§10.3), `--new` (§10.2).

`src/sd.ps1`: `Import-Module`, `Invoke-Sd @args`, `exit $LASTEXITCODE`.

**Done when:** all non-hook, non-export `win`/`all` cases pass via `pwsh src/sd.ps1`.

### Phase 3: Windows shell integration

- The module reads `name` from the machine config. It defines a function with that name that calls `Invoke-Sd`.
- `Register-ArgumentCompleter -Native`, with `ListItemText` = listing line and `CompletionText` = name (§8.3).
- The Tab handler: `MenuComplete` when the line starts with `<name> `, the default otherwise.
- The `bin/sd` hand-off: on `MINGW*`/`MSYS*` (from `uname -s`), it runs `exec pwsh -NoLogo -NoProfile -File <repo>/src/sd.ps1 "$@"`, unless `SD_BASH_CORE=1` is set (used by `run.sh` to test the bash core under git-bash). `--complete` is the exception: it is answered by the bash core with the Windows rules, for fast git-bash completion.

**Done when:** manual checks in pwsh pass:
- Tab menu shows descriptions plus folder/script markers.
- Fuzzy fallback works.
- `sd` from a `.bat` (via `<name>.cmd`) and from a `.sh` (via git-bash) both run the `.bat` first.

These checks are manual. Testing them automatically would cost more than it's worth.

### Phase 4: Windows setup / uninstall

`install.ps1` and `uninstall.ps1` per §12:
- the requirements check, including spotting WSL `bash`
- the command-name clash check
- creating the root
- the machine config
- the `<name>.cmd` and `<name>` entry points in `%LOCALAPPDATA%\sd\bin`
- the user PATH entry
- the `$PROFILE` block between markers

**Done when:**
- A fresh install from a clean user profile works.
- Re-running with a new `-Name` replaces the old entry points and function.
- Uninstall leaves no trace except the sd root.

### Phase 5: Hooks (PowerShell)

- Parsing `hooks.conf` (§9.2): keep raw lines, so editing doesn't touch comments or formatting.
- Glob matching: convert to a regex (`*` → `.*`, escape everything else).
- Running per §9.3, with `SD_NO_HOOKS=1` set for hooks.
- `--hooks` list/add/rm/on/off/edit (§10.1).

**Done when:** all hook cases pass on Windows.

### Phase 6: Export / import (PowerShell)

- Choosing what to export (§10.4): files + matching hook entries + the hook scripts they use. Uses `tar -czf`.
- `--import` (§10.5): unpack to a temp folder, the safety checks, the existing-file check, copy, add hook entries as `off`, print the summary.

**Done when:** the round-trip cases pass, and a hand-made archive containing `..` is rejected.

### Phase 7: Bash core + bash completion

- `bin/sd`: everything from phases 2, 5 and 6 for Unix, bash 3.2-compatible.
- `shell/sd-completion.bash` (§8.4).
- `install.sh` / `uninstall.sh` (§12).

**Done when:**
- All `all`/`unix` cases pass on Linux and on bash 3.2 (macOS, or a `bash:3.2` Docker image if no Mac is available).
- A manual completion check in bash passes.

### Phase 8: README and finish

`README.md`:
- what it is and a quick start (install, first script, running it)
- the layout rules: namespaces, loose scripts, bundles, Windows/Unix priority
- descriptions
- completion
- hooks, with a full `hooks.conf` example
- the meta-command reference
- export/import
- **configuration: where the machine config lives, how to change the root and the command name**
- uninstall
- known limitations (argument characters through `.bat`, no cmd completion, no zsh yet)

Final pass: run both test runners, do a fresh install on Windows, review against the spec.

## Order and dependencies

```
1 → 2 → 3 → 4
      ↘ 5 → 6 → 7 → 8
```

Phases 3–4 (integration, setup) and 5–6 (hooks, export) both build only on phase 2, so either order works. Doing 3–4 first gives a usable tool sooner. Phase 7 reuses decisions settled on Windows in phases 2–6.

## Risks and how they're handled

| Risk | Handling |
|---|---|
| The two cores drift apart | Shared `cases.txt`. Any behaviour change gets a case first. |
| `bash` on PATH is WSL | Setup and `--which` show which `bash` is used. Setup warns about WSL. |
| CRLF line endings in `.sh` files break bash | `.gitattributes`. `--new` writes LF. The core warns when a `.sh` it's about to run contains `\r`. |
| Paths with spaces (e.g. `D:\Coding\Projects\Script Directory`) | Everything quoted. The fixture root path in tests contains a space. |
| git-bash rewriting `/path`-like arguments | `MSYS_NO_PATHCONV=1` set when calling `bash` for `.sh` scripts. |
| `SD_*` variables leaking into the user's session | Saved and restored around each run (phase 2). |
| Name clash with an existing `sd` | Name chosen at setup, checked for clashes (§12). |
