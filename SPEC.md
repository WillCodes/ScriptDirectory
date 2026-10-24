# sd — Specification

A lightweight script-directory runner, inspired by [ianthehenry/sd](https://github.com/ianthehenry/sd),
that works natively on Windows (PowerShell + `.bat`) and on Unix (bash).

`sd dev build 1 2` finds the script `build` under `<sd root>/dev/` and runs it with the arguments `1 2`.

Throughout this document `sd` refers to the command; its actual name is chosen at setup (see §3).

---

## 1. Goals and non-goals

**Goals**

- Run scripts by path-like words: `sd <namespace>... <script> [args...]`.
- Tab completion with descriptions, distinguishing folders from scripts, prefix matching with fuzzy fallback.
- Windows: `.bat` scripts run natively; `.sh` scripts run through git-bash. Unix: `.sh` / extensionless scripts.
- Hooks: scripts that run before/after other scripts, managed from the command line, stored in a hand-editable file.
- Export/import a subset of scripts and hooks.
- One setup script per platform; the user picks the sd root and the command name.

**Non-goals**

- The original sd's flags (`--cat`, `--edit`, `--really`, ...). Only the meta-commands in §10 exist.
- Installing dependencies. Setup never installs PowerShell, Git for Windows, or anything else.
- `.ps1` user scripts. They are never run.
- cmd tab completion and zsh completion (zsh can be added later via `--complete`, §8.1).

## 2. Requirements

| Platform | Required | Notes |
|---|---|---|
| Windows | PowerShell 7+ (`pwsh`) | Needed for the core and completion. |
| Windows | Git for Windows `bash` | Only needed to run `.sh` scripts. Found as `bash` on `PATH` unless that is WSL (`C:\Windows\System32\bash.exe`), else as `bin\bash.exe` in the Git install that `git.exe` on `PATH` belongs to. Setup warns if neither is found. |
| Windows | `tar` | Ships with Windows 10+. Used by export/import. |
| Unix (Linux, macOS) | bash 3.2+ | The core must not use bash 4+ features (associative arrays, `mapfile`, `${x,,}`, ...). |
| Unix | `tar`, `gzip` | Used by export/import. |

## 3. Terminology and configuration

| Term | Meaning |
|---|---|
| **sd root** | The folder holding the user's scripts. Chosen at setup, default `~/sd`. |
| **namespace** | A folder inside the root that is not a bundle. `sd dev` steps into `dev/`. |
| **script** | A runnable file (§5.2). |
| **bundle** | A folder that holds a script of the same name, e.g. `dev/build/build.bat`. It acts as one script (§5.3). |
| **script name** | A script's path relative to the root, using `/`, no extension: `dev/build`. |
| **hook** | A script in `<root>/hooks/` that is attached to other scripts in `hooks.conf` (§9). |
| **meta-command** | A built-in command starting with `--` (§10). |

### 3.1 Machine config file

Per-machine settings. Simple `key = value` lines; `#` starts a comment.

| Platform | Location |
|---|---|
| Windows | `%APPDATA%\sd\config` |
| Unix | `${XDG_CONFIG_HOME:-~/.config}/sd/config` |

```
# sd machine config
root = C:\Users\me\sd
name = sd
```

| Key | Meaning | Takes effect |
|---|---|---|
| `root` | Path to the sd root. | Immediately (read on every run). |
| `name` | The command name. | After re-running setup, which regenerates the entry points (§12). |

The environment variable `SD_ROOT`, if set, overrides `root`.

### 3.2 Root-level files

| Path | Purpose |
|---|---|
| `<root>/hooks/` | Hook scripts. Hidden from resolution, listing and completion. |
| `<root>/hooks.conf` | Hook configuration (§9.2). Kept in the root so it travels with the scripts (e.g. in git). |
| `<root>/**/.help` | Folder description (§6). |

## 4. Invocation

```
sd                              list the root
sd <word>... [args...]          resolve words to a namespace or script (§5)
sd --<meta-command> [...]       built-in commands (§10)
```

A first word starting with `--` is always a meta-command. Script and folder names must not start with `-`.
Names must not contain whitespace (they could not be referenced from `hooks.conf`).

## 5. Resolution

### 5.1 Algorithm

Start at `D = <root>`. For each word `w`, left to right:

1. If `w` names a **bundle** in `D` (§5.3): it is the script. Stop.
2. Else if `w` names a **namespace** (a folder in `D` that is not a bundle): set `D = D/w`, continue.
3. Else if `w` names a **loose script** in `D` (§5.2): it is the script. Stop.
4. Else: error `no script or folder '<w>' in <D-name>`, print the listing of `D` (§7), exit 1.

When a script is found, **all remaining words are passed to it as arguments, unchanged**, even if they match folder or script names.
`sd dev build dev` runs `dev/build` with the argument `dev`.

If the words run out while still in a namespace, print the listing of that namespace and exit 0.

Ignored at every level: entries whose names start with `.`, and `.ps1` files. Also ignored at the root: `hooks/` and `hooks.conf`.

Matching words to names is exact: case-sensitive on Unix, case-insensitive on Windows (following the file system).
Fuzzy matching only applies to completion (§8.2), never to running.

### 5.2 Loose scripts and priority

A loose script named `w` is one or more of these files in `D`: `w.bat`, `w.cmd`, `w.sh`, `w` (no extension, regular file).
The file that runs is picked by platform:

| Platform | Priority (first existing wins) | Not considered |
|---|---|---|
| Windows | `w.bat` → `w.cmd` → `w.sh` → `w` | `.ps1` |
| Unix | `w.sh` → `w` | `.bat`, `.cmd`, `.ps1` |

A name with no runnable file for the current platform (e.g. only `w.bat` on Unix) does not exist on that platform: it is not run, listed or completed.

### 5.3 Bundles

A folder `D/w/` is a **bundle** if it contains a runnable file named `w` (by §5.2, for the current platform).
The bundle's script file is chosen with the same priority. All other files in the bundle are private: never listed, completed or resolved.
A bundle has no subcommands: `sd dev build release` passes `release` to the bundle.

```
dev/build/
  build.bat     Windows: runs (setup, then calls build.sh)
  build.sh      Unix: runs. Windows: called by build.bat
  helper.py     private
```

### 5.4 Conflicts

If `D` has both a bundle or namespace folder `w/` and a loose script `w`, it is an error:
`ambiguous '<name>': both folder <path> and file <path> exist`, exit 1.
Listing and completion show the entry once, marked with `!` and the description `ambiguous`.

## 6. Descriptions

A script's description is the first matching line of its script file. On Windows the `.bat`/`.cmd` is checked first, then the `.sh`. For a bundle, the description comes from the bundle's script files, and `w/.help` is used if they have none.

| File type | Rule |
|---|---|
| `.sh` / extensionless | Skip the shebang line. The first line that starts with `#` gives the description: the text after `#` and spaces. |
| `.bat` / `.cmd` | Skip blank lines and `@echo off` (case-insensitive). The first line starting with `::` or `REM ` gives the description. |

Only the first 10 lines are scanned. No match means an empty description.

A namespace's description is the first non-empty line of `<folder>/.help`.

## 7. Listing

`sd` (root) and `sd <namespace>` print one entry per line, sorted case-insensitively, namespaces first:

```
tools/     Helper utilities
build    ▸ Build the project
deploy   ▸ Push to staging
```

- Namespaces have a trailing `/`. Scripts and bundles are marked `▸`. Conflicts are marked `!`.
- Names are padded to the longest name. A missing description leaves the description column empty.
- Exit code 0.

## 8. Completion

### 8.1 Protocol: `sd --complete`

```
sd --complete [<word>...] <partial>
```

Resolves the complete words like §5. If they lead to a script, it prints nothing (arguments are the script's business).
Otherwise it prints the candidates in the namespace reached that match `<partial>`, one per line:

```
<name>\t<type>\t<description>
```

`<type>` is `dir`, `script` or `conflict`. Each shell's completion code is a thin wrapper around this command.
When the first word is partial and starts with `--`, the candidates are the meta-commands.

### 8.2 Matching

1. **Prefix:** names starting with `<partial>`, case-insensitive. If there are any, return those.
2. **Fuzzy fallback:** names containing the characters of `<partial>` in order (subsequence), case-insensitive.
   Ranked by: earliest first match, then shortest matched span, then alphabetical.

An empty `<partial>` matches everything. Order otherwise follows §7.

### 8.3 PowerShell

- `Register-ArgumentCompleter -Native -CommandName <name>`.
- Each `CompletionResult` has `CompletionText` = the name, and `ListItemText` = the line from §7 (e.g. `build    ▸ Build the project`).
  So the menu shows every description, and only the name is inserted.
- Setup binds Tab to a handler that calls PSReadLine `MenuComplete` when the line starts with `<name> `, and `TabCompleteNext` (the default) otherwise.

### 8.4 bash

- `complete -F _sd_complete <name>`.
- Several candidates: `COMPREPLY` gets the display lines from §7 (shown, not inserted).
- Exactly one candidate: `COMPREPLY` gets just the name, so it is inserted.

### 8.5 cmd

No completion.

## 9. Hooks

### 9.1 Hook scripts

Hook scripts live in `<root>/hooks/`, may be nested (`hooks/git/fetch` → hook name `git/fetch`), and follow the loose script and bundle rules in §5.2–5.3.
They can't be run as `sd hooks ...`.

### 9.2 `hooks.conf`

Whitespace-separated columns, one hook per line. `#` starts a comment, blank lines are ignored.

```
# state  when    target      hook
on       before  dev/build   lint
on       after   dev/*       notify
off      before  *           log-start
```

| Column | Values |
|---|---|
| state | `on` / `off` |
| when | `before` / `after` |
| target | A script name or glob. `*` matches any characters, including `/`. `dev/*` matches `dev/build` and `dev/x/y`. `*` matches everything. |
| hook | A hook name, relative to `hooks/`. |

Entries are numbered from 1 in file order, not counting comments or blank lines. These numbers are what `sd --hooks` shows and takes.
A malformed line is reported on stderr with its line number and skipped. Other lines still run.

### 9.3 Execution

When script `T` is run with arguments `A`:

1. All `on` + `before` entries whose target matches `T` run in file order, each with arguments `A`.
   If one exits non-zero: stderr shows `hook '<hook>' (before <T>) failed with exit <n>`. The remaining before hooks, `T` and all after hooks are skipped. `sd` exits with the hook's code.
2. `T` runs with `A`.
3. All `on` + `after` entries whose target matches `T` run in file order, each with arguments `A`, whether `T` succeeded or not.
   A failing after hook prints a warning on stderr. Later hooks still run.
4. `sd` exits with `T`'s exit code.

Hooks fire only when a script is run through resolution. Listings, meta-commands and `--which` never fire them.
If a hook entry names a hook that does not exist, stderr shows a warning and the entry is skipped. A missing before hook does not count as a failure.

Hook environment, on top of §11:

| Variable | Value |
|---|---|
| `SD_TARGET` | The target script name, e.g. `dev/build`. |
| `SD_PHASE` | `before` / `after`. |
| `SD_EXIT_CODE` | The target's exit code (after hooks only). |

**No recursion:** hooks run with `SD_NO_HOOKS=1`, so `sd` calls made from a hook don't fire hooks.
**Opt out:** if `SD_NO_HOOKS=1` is set, `sd` fires no hooks. Nested `sd` calls from scripts otherwise fire hooks normally.

## 10. Meta-commands

| Command | Purpose |
|---|---|
| `--help` | Short usage summary and the list of meta-commands. |
| `--hooks ...` | Manage hooks (§10.1). |
| `--new <path> [--bundle] [--bat \| --sh]` | Create a script (§10.2). |
| `--which <word>... [args...]` | Show what would run (§10.3). |
| `--export <file> <path>...` | Export scripts and hooks (§10.4). |
| `--import <file> [--force]` | Import an export file (§10.5). |
| `--complete ...` | Completion protocol (§8.1). Hidden from `--help`. |

Unknown meta-command: error, show the `--help` text, exit 1.

### 10.1 `--hooks`

```
sd --hooks                              numbered list (state, when, target, hook)
sd --hooks add <before|after> <target> <hook>
sd --hooks rm <n>
sd --hooks on <n>
sd --hooks off <n>
sd --hooks edit                         open hooks.conf in the editor (§10.2), creating it if needed
```

- `add` appends an `on` line. It fails if the hook doesn't exist. It warns (but still adds) if the target matches no current script. It creates `hooks.conf` with a header comment if missing.
- `rm`, `on`, `off` change only the targeted line in place. Comments and formatting of other lines are kept.
- The list marks entries whose hook is missing.

### 10.2 `--new`

```
sd --new dev/build              loose script(s) in dev/
sd --new dev/build --bundle     dev/build/ bundle
sd --new hooks/lint             a hook script
sd --new dev/build --sh         only the .sh file
sd --new dev/build --bat        only the .bat file (Windows-only script)
```

- `<path>` is relative to the root, without an extension. Missing folders are created.
- Default files: Windows creates `.bat` + `.sh`, with the `.bat` handing off to the `.sh`. Unix creates `.sh`.
- Fails if any target file or a conflicting entry (§5.4) already exists.
- Templates contain a description placeholder line (§6), and the `.sh` is marked executable on Unix.

`.sh` template:

```bash
#!/usr/bin/env bash
# TODO: describe this script
set -euo pipefail

echo "args: $*"
```

`.bat` template (when a `.sh` is also created):

```bat
@echo off
:: TODO: describe this script
setlocal

:: Windows-specific setup goes here.

bash "%~dp0<name>.sh" %*
exit /b %ERRORLEVEL%
```

- After creation, the created files are opened in `$VISUAL`, or else `$EDITOR`, if either is set. Otherwise their paths are printed.

### 10.3 `--which`

Resolves like §5, without running anything or firing hooks, and prints:

```
name:        dev/build
kind:        bundle
file:        C:\Users\me\sd\dev\build\build.bat
runs with:   cmd
description: Build the project
args:        1 2
hooks:
  before  lint        (on,  1)
  after   notify      (on,  2)
  before  log-start   (off, 3)
```

For a namespace it prints the namespace path and its listing. Exit 0 if resolved, otherwise it follows §5.1 step 4.

### 10.4 `--export`

```
sd --export team.tar.gz dev/build dev/deploy tools hooks/lint
```

- `<path>`: a script name, a namespace (exported whole) or a hook (`hooks/<name>`), all relative to the root.
- All files for the given scripts are included, whatever the platform: `.bat`, `.sh` and whole bundle folders.
- A `hooks.conf` entry is included if its target matches an exported script, or its hook was named explicitly. Hook scripts used by included entries are added automatically.
- Archive layout: files at their root-relative paths, plus `sd-export.conf` at the archive root. It holds the included `hooks.conf` lines in `hooks.conf` format, with their state kept as it was.
- The summary on stdout lists the files and hook entries exported.

### 10.5 `--import`

```
sd --import team.tar.gz [--force]
```

1. Unpack into a temporary folder. Reject the archive if any entry has an absolute path, `..`, or a link.
2. Check for files that already exist in the root. If there are any and `--force` isn't given, list them and exit 1 without changing anything.
3. Copy the files into the root.
4. Add the `sd-export.conf` entries to the end of `hooks.conf` **as `off`**. An entry that matches an existing one on when + target + hook is skipped.
5. Print the files imported, the hook entries added (with their new numbers) and the `sd --hooks on <n>` command to switch each on.

## 11. Script execution

| File | How it runs |
|---|---|
| Windows `.bat` / `.cmd` | Run directly by PowerShell (`& $file @args`). |
| Windows `.sh` / extensionless | `bash <file> <args>`, with Git for Windows `bash` found as in §2 |
| Unix `.sh` / extensionless | Run directly if executable. Otherwise `bash <file> <args>`. |

- **Working directory:** the caller's current folder. `sd` never changes it.
- **Standard streams:** stdin/stdout/stderr pass through, so interactive scripts work.
- **Exit code:** as in §9.3.
- **Environment set for scripts and hooks:**

| Variable | Value |
|---|---|
| `SD_ROOT` | Absolute path of the root. |
| `SD_NAME` | Script name, e.g. `dev/build`. |
| `SD_DIR` | Folder holding the running file. |

**Nested calls:** scripts can call `sd` again. On Windows this works from PowerShell, cmd (`.bat` scripts) and git-bash (`.sh` scripts). Every route ends at the PowerShell core, so the Windows priority (§5.2) always applies.

**Argument caveat (Windows):** cmd parses arguments to `.bat` again, so `%`, `^`, `&`, `!` and `"` inside arguments may not reach the `.bat` code unchanged. This is cmd behaviour, documented rather than worked around.

## 12. Setup and uninstall

Setup is `install.ps1` (Windows, run with `pwsh`) or `install.sh` (Unix). The tool runs from wherever the repository is cloned. Moving the clone means re-running setup.

```
pwsh ./install.ps1 [-Root <path>] [-Name <name>]
./install.sh [--root <path>] [--name <name>]
```

Values not given are asked for interactively, with defaults taken from the existing machine config, else `~/sd` and `sd`.

Steps:

1. **Check requirements (§2).** Warn about missing pieces without installing anything. Exit only if PowerShell is below 7 (Windows).
2. **Check the name.** Warn if `<name>` already resolves to another command (e.g. the Rust `sd` tool), and ask for confirmation.
3. **Create the root** if missing, with one example script and a `hooks.conf` holding only the header comment.
4. **Write the machine config** (§3.1).
5. **Write entry points into the user bin folder** (`%LOCALAPPDATA%\sd\bin` on Windows, `~/.local/bin` on Unix), first removing those for any old name:
   - Windows: `<name>.cmd` (for cmd) and an extensionless `<name>` (for git-bash), both calling the PowerShell core.
   - Unix: `<name>`, a symlink to the bash core.
6. **Add the bin folder to the user PATH** if missing. On Windows this is the user `Path` variable; on Unix, a line in the profile block.
7. **Update the shell profile.**
   - Windows: `$PROFILE` imports the module, which defines the `<name>` function, completion and the Tab handler.
   - Unix: `~/.bashrc` sources the completion file.

   The added text sits between `# >>> sd >>>` and `# <<< sd <<<` and is replaced, not duplicated, on re-run.
8. **Print a summary** and "restart your shell".

Re-running setup is always safe. It is how to change the name (or edit `name` in the config, then re-run).

`uninstall.ps1` / `uninstall.sh` remove the entry points, the PATH entry, the profile block and the machine config. They **never** touch the sd root.

## 13. Errors and exit codes

| Situation | Exit |
|---|---|
| Listing, `--help`, successful meta-command | 0 |
| Script ran | the script's exit code (§9.3) |
| Before hook failed | the hook's exit code |
| Not found, ambiguous, bad usage, failed meta-command | 1 |

Errors go to stderr, starting with `<name>: `.

## 14. Cross-platform consistency

The bash core (Unix) and the PowerShell core (Windows) implement this spec separately. They are kept in step by one shared test case file, run against one sample root by a small runner on each platform (see PLAN.md).
Output formats (§7, §8.1, §10.3) are identical on both platforms, apart from path separators in file paths.
