# sd

A small script-directory runner for Windows and Unix. Put scripts in a folder tree, then run them by path-like words:

```
sd dev build 1 2      # runs <root>/dev/build with the arguments "1 2"
```

You get a listing of what is there, tab completion with descriptions, optional before/after hooks, and export/import for sharing scripts. It is a single PowerShell module plus a single bash script. The whole thing is meant to be read in one sitting.

Inspired by [ianthehenry/sd](https://github.com/ianthehenry/sd). It is a different, much smaller tool: only the meta-commands listed below exist. The full rules are in [SPEC.md](SPEC.md).

- **Windows:** `.bat` scripts run natively, `.sh` scripts run through Git for Windows' bash. Works from PowerShell, cmd and git-bash.
- **Unix:** `.sh` and extensionless scripts, bash completion.

## Quick start

Clone the repo anywhere (it runs from where it is cloned; if you move it, re-run setup), then:

```powershell
# Windows (PowerShell 7+)
pwsh ./install.ps1
```
```bash
# Linux / macOS
./install.sh
```

Setup asks for the **root** (where your scripts live, default `~/sd`) and the **command name** (default `sd`), or take them as `-Root`/`-Name` (`--root`/`--name` for `install.sh`). It creates the root with an example script, adds the command to your `PATH` and your shell profile, and never installs anything for you. Restart your shell afterwards.

Make and run a first script:

```
$ sd --new hello/world --sh
C:\Users\me\sd\hello\world.sh        # opened in $VISUAL / $EDITOR if set, else the path is printed
$ sd hello world a b
args: a b
$ sd hello
world ▸ TODO: describe this script
```

Edit the `# TODO` line in the script to change what the listing shows. Run `sd` alone to list the root and `sd --help` for the commands.

## Layout

A script is found by walking the words left to right, one folder per word. Everything after the script's name is passed to it unchanged, even if it looks like a folder name.

```
~/sd/
  hooks/             hook scripts (hidden, see Hooks)
  hooks.conf         hook configuration
  hello.sh           loose script:  sd hello
  deploy.sh          loose script:  sd deploy
  deploy.bat           the Windows version of the same script
  dev/               namespace:     sd dev ...
    .help              its description ("Development tools")
    build/             bundle:        sd dev build
      build.bat          Windows: runs this
      build.sh           Unix: runs this (Windows: called by build.bat)
      helper.py          private, never listed or run
    sub/deep.sh      sd dev sub deep
```

- **Namespace:** a folder that is not a bundle. `sd dev` lists it, `sd dev build` steps in.
- **Loose script:** `name.bat`, `name.cmd`, `name.sh` or an extensionless `name`.
- **Bundle:** a folder holding a script of the same name (`dev/build/build.sh`). It acts as one script, can't have subcommands (`sd dev build release` passes `release` to it), and its other files are private.
- **Priority:** Windows picks `.bat`, then `.cmd`, then `.sh`, then extensionless. Unix picks `.sh`, then extensionless. A name with no file for the current platform doesn't exist there: it is not run, listed or completed.
- **Ignored:** anything starting with `.`, and every `.ps1` file (never run). At the root, also `hooks/` and `hooks.conf`.
- **Conflicts:** a folder and a loose script with the same name (`clash/` and `clash.sh`) is an error when you use it, and shows as `!  ambiguous` in listings.
- **Names:** no spaces, and must not start with `-` (a first word starting with `--` is a meta-command).
- Matching is case-sensitive on Unix, case-insensitive on Windows. Only completion is fuzzy.

Listing a namespace (real output):

```
$ sd dev
sub/     Nested namespace
build  ▸ Build the project
deploy ▸ Push to staging
```

Namespaces come first and end in `/`, scripts and bundles are marked `▸`. A word that doesn't exist prints the error and the listing of where you were, with exit code 1:

```
$ sd dev nope
sd: no script or folder 'nope' in dev
sub/     Nested namespace
...
```

## Descriptions

The listing and completion menu show a one-line description:

| File | Description is... |
|---|---|
| `.sh` / extensionless | the first `#` comment line (not the `#!` line) |
| `.bat` / `.cmd` | the first `::` or `REM ` line (after `@echo off`) |
| namespace | the first non-empty line of `<folder>/.help` |

Only the first 10 lines are scanned. A bundle uses its script files, falling back to `<bundle>/.help`.

## Completion

Press Tab after the command name.

- **PowerShell:** setup binds Tab so that it opens a `MenuComplete` menu after `sd `, showing every entry with its description. Only the name is inserted, followed by a space, so you can keep pressing Tab (`sd de` → `sd dev ` → `sd dev sub `). The menu shows one entry per line, and picking a folder opens the next menu straight away (Esc stops). A folder with just one entry still shows it, with a `(stop here)` option, instead of filling it in. Elsewhere Tab does whatever it did before.
- **bash:** several matches print the listing lines (shown, not inserted); a single match is inserted. If any match is fuzzy, the menu has one blank extra entry (see Known limitations).
- **Matching:** names that start with what you typed. If there are none, names containing your letters in order (`bd` finds `build`), best match first.
- **cmd:** none.

Completion is a thin wrapper around `sd --complete [words...] <partial>`, which prints `name<TAB>type<TAB>description` lines (type is `dir`, `script`, `conflict` or `meta`). That is the hook for adding another shell.

```
$ sd --complete dev bd
build	script	Build the project
```

## Hooks

Hooks are scripts in `<root>/hooks/` that run before or after other scripts. They're attached in `<root>/hooks.conf`, which lives in the root so it travels with your scripts (for example in git):

```
# state  when    target          hook
on       before  hooked/*        pass
on       after   hooked/*        after
on       before  hooked/blocked  fail
off      before  *               fail
on       before  hooked/ok       missing
```

Columns are whitespace-separated; `#` starts a comment. `state` is `on`/`off`, `when` is `before`/`after`, `target` is a script name or a glob (`*` matches any characters including `/`, so `dev/*` matches `dev/x/y`), and `hook` is a name under `hooks/` (nested like `git/fetch` is fine). Entries are numbered from 1 in file order. A malformed line is reported with its line number and skipped.

When `sd hooked ok a b` runs:

1. The matching `on` + `before` hooks run in file order with the same arguments. If one exits non-zero, `sd` prints `hook 'fail' (before hooked/blocked) failed with exit 7`, skips everything else and exits with that code.
2. The script runs.
3. The matching `on` + `after` hooks run, whether the script succeeded or not. A failing one only warns.
4. `sd` exits with the script's exit code.

```
$ sd hooked ok a b
pass hook: before hooked/ok a b
sd: warning: hook 'missing' not found (hooks.conf entry 5)
ok.sh: a b
after hook: hooked/ok exit=0
```

Hooks see these variables, on top of the ones in [Environment](#environment-variables-scripts-see):

| Variable | Value |
|---|---|
| `SD_TARGET` | the target script name, e.g. `hooked/ok` |
| `SD_PHASE` | `before` or `after` |
| `SD_EXIT_CODE` | the target's exit code (after hooks only) |
| `SD_NO_HOOKS` | `1`: `sd` calls made from a hook don't fire hooks |

Set `SD_NO_HOOKS=1` yourself to run without hooks. Listings, meta-commands and `--which` never fire hooks.

Manage the file from the command line (other lines and comments are left alone) or just edit it:

```
$ sd --hooks
1  on   before  hooked/*        pass
...
5  on   before  hooked/ok       missing  (missing)
$ sd --hooks add before dev/build lint     # fails if hooks/lint doesn't exist
$ sd --hooks off 3                         # also: on <n>, rm <n>, edit
```

## Meta-commands

| Command | Does |
|---|---|
| `sd --help` | usage and this list |
| `sd --new <path> [--bundle] [--bat \| --sh]` | create a script from a template (below) |
| `sd --which <word>... [args...]` | show what would run, without running it |
| `sd --hooks [add\|rm\|on\|off\|edit ...]` | list and manage hooks |
| `sd --export <file> <path>...` | export scripts and hooks |
| `sd --import <file> [--force]` | import an export file |
| `sd --complete ...` | completion protocol (hidden from `--help`) |

`--new` takes a path relative to the root, without extension, and creates missing folders. On Windows it makes a `.bat` that hands off to a `.sh`; on Unix just a `.sh` (marked executable). `--sh` / `--bat` create only that file, `--bundle` creates `<path>/<name>.*`. It refuses to overwrite anything or to create an ambiguous name. `sd --new hooks/lint` makes a hook.

`--which` resolves like running does and prints (real output, path shortened):

```
$ sd --which hooked ok x
name:        hooked/ok
kind:        script
file:        C:\Users\me\sd\hooked\ok.sh
runs with:   bash (C:\Program Files\Git\bin\bash.exe)
description: Hooked ok
args:        x
hooks:
  before  pass      (on,  1)
  after   after     (on,  2)
  before  fail      (off, 4)
  before  missing   (on,  5) missing
```

Unknown meta-command: error plus the help text, exit 1. Errors go to stderr and start with the command name.

## Export and import

```
$ sd --export team.tar.gz hooked tools hooks/lint
```

Each `<path>` is a script, a namespace (taken whole) or `hooks/<name>`. All platforms' files for a script come along (`.bat`, `.sh`, whole bundles). The `hooks.conf` entries whose target matches an exported script, or whose hook you named, are included, and so are the hook scripts they use. The archive is a `.tar.gz` with files at their root-relative paths plus `sd-export.conf` holding the entries.

```
$ sd --import team.tar.gz
imported 6 file(s):
  hooked/blocked.sh
  ...
hook entries added (all off):
  1  before  hooked/*  pass
  ...
switch them on with:
  sd --hooks on 1
  ...
```

- **Imported hook entries arrive `off`.** Nothing runs until you read the scripts and turn the entries on. An entry already in `hooks.conf` (same when + target + hook) is skipped.
- **Safety checks**, before anything is unpacked into the root: the archive is rejected if any entry has an absolute path, `..`, or is a link or device; if it has no `sd-export.conf`; or if it contains a `hooks.conf` (which would replace yours).
- **Existing files** are never overwritten silently: the import lists them and changes nothing, unless you pass `--force`.

## Configuration

The per-machine config is a tiny `key = value` file (`#` for comments):

| Platform | Location |
|---|---|
| Windows | `%APPDATA%\sd\config` |
| Unix | `${XDG_CONFIG_HOME:-~/.config}/sd/config` |

```
# sd machine config
root = C:\Users\me\sd
name = sd
```

- **Change the root:** edit `root`. It is read on every run, so it takes effect immediately. Move your scripts yourself; `sd` never does.
- **Override it for one shell or command:** set `SD_ROOT`. It beats `root` in the file.
- **Change the command name:** edit `name`, or re-run setup (`./install.sh --name foo`, `pwsh ./install.ps1 -Name foo`). The entry points are generated files, and **re-running setup is what renames them**: the `cmd` and git-bash entry points on Windows, the symlink in `~/.local/bin` on Unix (old ones are removed). Editing `name` alone only renames the PowerShell function and the bash completion, after you restart the shell.
- Setup warns, and asks, if the name is already another command (for example the Rust `sd` tool).
- Re-running setup is always safe: it updates what it wrote, and never overwrites anything in an existing root.

What setup touches:

| | Windows | Unix |
|---|---|---|
| Entry points | `%LOCALAPPDATA%\sd\bin\<name>.cmd` and `<name>` (git-bash) | `~/.local/bin/<name>`, a symlink to `bin/sd` |
| `PATH` | user `Path`, adds that folder | a line in `~/.bashrc` |
| Profile | `$PROFILE.CurrentUserAllHosts` imports `src/sd.psm1` | `~/.bashrc` sources `shell/sd-completion.bash` |

Profile changes sit between `# >>> sd >>>` and `# <<< sd <<<` and are replaced, not duplicated.

## Environment variables scripts see

| Variable | Value |
|---|---|
| `SD_ROOT` | absolute path of the root |
| `SD_NAME` | script name, e.g. `dev/build` |
| `SD_DIR` | the folder holding the running file |

Scripts run in your current folder (`sd` never changes it), with stdin/stdout/stderr passed through, so interactive scripts work. Scripts can call `sd` again: from PowerShell, from `.bat` files and from git-bash, all routes end up at the same PowerShell core. On Windows, if bash was found through `git.exe`, its folder is put on `PATH` while scripts run, so a `.bat` can call `bash`.

## Uninstall

```
pwsh ./uninstall.ps1        # Windows
./uninstall.sh              # Unix
```

Removes the entry points, the `PATH` entry, the profile block and the machine config. It **never touches your sd root**. Restart your shell.

## Running the tests

```
pwsh -NoProfile -File tests/run.ps1     # PowerShell core
bash tests/run.sh                       # bash core
```

Both run the same [tests/cases.txt](tests/cases.txt) against a temporary copy of [tests/root](tests/root), so the two cores stay in step. Under git-bash, `bin/sd` hands over to the PowerShell core; set `SD_BASH_CORE=1` to force the bash core (`tests/run.sh` does).

## Requirements

| | Needed |
|---|---|
| Windows | PowerShell 7+ (`pwsh`); `tar` (ships with Windows 10+) |
| Windows, for `.sh` scripts | Git for Windows. `bash` is taken from `PATH` (unless that is WSL), else from next to `git.exe` |
| Unix | bash 3.2+, `tar`, `gzip` |

Setup warns about anything missing and installs nothing. `.sh` files with CRLF line endings get a warning, since bash will probably choke on them.

## Known limitations

- cmd parses arguments to `.bat` files again, so `%`, `^`, `&`, `!` and `"` in arguments may not arrive unchanged. This is cmd, and isn't worked around.
- No tab completion in cmd, and no zsh completion yet (`sd --complete` is there to build it on).
- The bash core has been tested under git-bash 5.2, but not yet on a real Linux or macOS, or on bash 3.2.
- On macOS, login shells read `~/.bash_profile`, so make it source `~/.bashrc`.
- With fuzzy matches, the bash completion menu shows one blank extra entry. That stops readline from replacing the word you typed with the matches' common prefix.
- `.ps1` user scripts are never run.
