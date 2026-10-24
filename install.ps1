#Requires -Version 7
# Sets up sd on Windows: sd root, machine config, entry points, user PATH and PowerShell profile.
# Safe to re-run; re-run with a new -Name to rename the command.
#   pwsh ./install.ps1 [-Root <path>] [-Name <name>]
param([string]$Root, [string]$Name)
$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot
$bin = Join-Path $env:LOCALAPPDATA 'sd\bin'
$configFile = Join-Path $env:APPDATA 'sd\config'
$sandbox = $env:SD_INSTALL_SANDBOX   # test hook: fake profile and user Path inside this folder, no registry
$profileFile = $sandbox ? "$sandbox\profile.ps1" : $PROFILE.CurrentUserAllHosts
$warnings = [Collections.Generic.List[string]]::new()

function Warn($Message) { $warnings.Add($Message); Write-Host "warning: $Message" -ForegroundColor Yellow }

function Save($Path, $Text) {   # UTF-8 without BOM; $Text carries its own line endings
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

# The user Path is REG_EXPAND_SZ with %VAR% entries, so it is read unexpanded and written back as such.
function Get-UserPath {
    if ($sandbox) { return (Test-Path "$sandbox\userpath.txt") ? ([IO.File]::ReadAllText("$sandbox\userpath.txt")).Trim() : '' }
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}

function Set-UserPath($Value) {
    if ($sandbox) { return Save "$sandbox\userpath.txt" $Value }
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true).SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    # Setting and clearing a user variable makes .NET broadcast WM_SETTINGCHANGE, so new terminals see the new Path.
    [Environment]::SetEnvironmentVariable('SD_INSTALL_TMP', '1', 'User')
    [Environment]::SetEnvironmentVariable('SD_INSTALL_TMP', [NullString]::Value, 'User')   # a plain $null would leave it set to ""
}

# ---- 1. Requirements ----------------------------------------------------------------------------
# The module's own bash lookup is reused, so setup and the tool always agree.
$m = Import-Module "$repo/src/sd.psm1" -PassThru -Force
$wslBash = Get-Command bash -CommandType Application -ErrorAction Ignore | Select-Object -First 1
if ($wslBash -and $wslBash.Source.StartsWith("$env:SystemRoot\System32\", 'OrdinalIgnoreCase')) {
    Warn "bash on PATH is WSL ($($wslBash.Source)); sd only uses Git for Windows bash"
}
if (-not (& $m { Get-SdBash })) { Warn 'Git for Windows bash not found: .sh scripts cannot run until it is installed (and git is on PATH)' }
if (-not (Get-Command tar -ErrorAction Ignore)) { Warn 'tar not found: --export and --import will not work' }

# ---- 2. Values ----------------------------------------------------------------------------------
$old = @{}
if (Test-Path -LiteralPath $configFile) {
    foreach ($line in Get-Content -LiteralPath $configFile) {
        if ($line -match '^\s*(root|name)\s*=\s*(.*?)\s*$') { $old[$Matches[1]] = $Matches[2] }
    }
}
if (-not $Root) {
    $default = $old.root ? $old.root : (Join-Path $HOME 'sd')
    $Root = Read-Host "sd root [$default]"
    if (-not $Root) { $Root = $default }
}
if (-not $Name) {
    $default = $old.name ? $old.name : 'sd'
    $Name = Read-Host "Command name [$default]"
    if (-not $Name) { $Name = $default }
}
if ($Name -notmatch '^[^\s\\/:*?"<>|-][^\s\\/:*?"<>|]*$') {
    Write-Error "Invalid name '$Name': no whitespace or path characters, and it must not start with '-'." -ErrorAction Continue
    exit 1
}
$Root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root).TrimEnd('\')

# ---- 3. Name clash ------------------------------------------------------------------------------
# Anything but our own entry points and the function our module defines.
$others = @(Get-Command $Name -All -ErrorAction Ignore | Where-Object {
    -not ([string]$_.Source).StartsWith("$bin\", 'OrdinalIgnoreCase') -and
    -not ($_.CommandType -eq 'Function' -and $_.ScriptBlock.Module -eq $m) })
if ($others) {
    Warn "'$Name' already resolves to another command: $($others[0].Source ? $others[0].Source : $others[0].Definition)"
    if ((Read-Host 'Use this name anyway? [y/N]') -notmatch '^y') { Write-Host 'Aborted.'; exit 1 }
}

# ---- 4. Root ------------------------------------------------------------------------------------
# Only a new (or empty) root gets the example; nothing in an existing root is ever overwritten.
if (-not (Test-Path -LiteralPath $Root) -or -not (Get-ChildItem -LiteralPath $Root -Force)) {
    $describe = { $args[0].Replace('TODO: describe this script', 'Example script: prints its arguments') }
    Save "$Root\hello.sh" (& $describe (& $m { Get-SdTemplate '.sh' 'hello' $true }))
    Save "$Root\hello.bat" (& $describe (& $m { Get-SdTemplate '.bat' 'hello' $true }))
}
# Hook scripts and hooks.conf live in hooks\. Any root gets them: new files overwrite nothing.
if (-not (Test-Path -LiteralPath "$Root\hooks" -PathType Container)) { $null = New-Item -ItemType Directory -Path "$Root\hooks" }
if ((Test-Path -LiteralPath "$Root\hooks.conf" -PathType Leaf) -and -not (Test-Path -LiteralPath "$Root\hooks\hooks.conf")) {
    Move-Item -LiteralPath "$Root\hooks.conf" "$Root\hooks\hooks.conf"   # where it used to be
    Write-Host "Moved $Root\hooks.conf to $Root\hooks\hooks.conf."
} elseif (-not (Test-Path -LiteralPath "$Root\hooks\hooks.conf")) {
    Save "$Root\hooks\hooks.conf" @'
# Hooks: scripts in this folder that run before or after other scripts.
# One hook per line, whitespace-separated columns ('#' starts a comment):
#   state  when    target      hook
#   ON     BEFORE  dev/build   lint
#   OFF    AFTER   dev/*       notify
# state: ON | OFF.  when: BEFORE | AFTER.
# target: a script named from the sd root as you run it, or a glob; '*' matches any characters, including '/'.
# hook: a script in this folder, named from here (lint for lint.bat or lint.sh).
# Add one with: --hooks add BEFORE dev/build lint
# Manage entries with: --hooks, --hooks add|rm|on|off|edit
'@
}

# ---- 5. Machine config --------------------------------------------------------------------------
Save $configFile "# sd machine config`nroot = $Root`nname = $Name`n"

# ---- 6. Entry points ----------------------------------------------------------------------------
if ($old.name -and $old.name -ine $Name) { Remove-Item -LiteralPath "$bin\$($old.name).cmd", "$bin\$($old.name)" -Force -ErrorAction Ignore }
$core = "$repo\src\sd.ps1"
Save "$bin\$Name.cmd" "@pwsh -NoLogo -NoProfile -File `"$core`" %*`r`n@exit /b %ERRORLEVEL%`r`n"
Save "$bin\$Name" "#!/bin/sh`nexec pwsh -NoLogo -NoProfile -File `"$($core.Replace('\', '/'))`" `"`$@`"`n"

# ---- 7. User PATH -------------------------------------------------------------------------------
$expand = { [Environment]::ExpandEnvironmentVariables($args[0]).TrimEnd('\') }
$userPath = Get-UserPath
if (-not ($userPath -split ';' | Where-Object { $_ -and (& $expand $_) -ieq (& $expand $bin) })) {
    # Appended without reformatting the rest, so uninstall can restore it exactly.
    Set-UserPath ($userPath ? ($userPath.EndsWith(';') ? "$userPath$bin;" : "$userPath;$bin") : $bin)
}
if (-not ($env:PATH -split ';' | Where-Object { (& $expand $_) -ieq $bin })) { $env:PATH = "$bin;$env:PATH" }

# ---- 8. Profiles --------------------------------------------------------------------------------
# Inserts or replaces the block between "# >>> sd >>>" and "# <<< sd <<<" in $Path, keeping the rest.
# $Nl is the line ending; with -KeepEndings a file that already has LF endings keeps them.
function Set-SdBlock($Path, [string[]]$Lines, $Nl, [switch]$KeepEndings) {
    $text = (Test-Path -LiteralPath $Path) ? [IO.File]::ReadAllText($Path) : ''
    if ($KeepEndings -and $text.Contains("`n") -and -not $text.Contains("`r`n")) { $Nl = "`n" }
    $block = (@('# >>> sd >>>') + $Lines + '# <<< sd <<<') -join $Nl
    $pattern = '(?s)# >>> sd >>>.*?# <<< sd <<<'
    if ($text -match $pattern) {
        $text = [regex]::Replace($text, $pattern, { $block })
    } else {
        if ($text -and -not $text.EndsWith("`n")) { $text += $Nl }
        if ($text) { $text += $Nl }
        $text += $block + $Nl
    }
    Save $Path $text
}

Set-SdBlock $profileFile "Import-Module '$("$repo\src\sd.psm1".Replace("'", "''"))'" "`r`n" -KeepEndings

# git-bash: ~/.bashrc sources the bash completion (LF, or bash chokes). Git for Windows only reads ~/.bashrc through
# a login file, and creates one with a warning if there is none, so a missing ~/.bash_profile is made here instead.
$bashrc = $null
if (& $m { Get-SdBash }) {
    $bashHome = $env:HOME ? $env:HOME : $env:USERPROFILE
    $bashrc = Join-Path $bashHome '.bashrc'
    $posix = "$repo\shell\sd-completion.bash" -replace '\\', '/'
    $posix = ('/' + $posix.Substring(0, 1).ToLower() + $posix.Substring(2)).Replace("'", "'\''")   # D:/x -> /d/x
    Set-SdBlock $bashrc "[ -f '$posix' ] && source '$posix'" "`n"
    if (-not (@('.bash_profile', '.bash_login', '.profile' | ForEach-Object { Test-Path -LiteralPath (Join-Path $bashHome $_) }) -contains $true)) {
        Set-SdBlock (Join-Path $bashHome '.bash_profile') 'test -f ~/.bashrc && . ~/.bashrc' "`n"
    }
}

# ---- 9. Summary ---------------------------------------------------------------------------------
Write-Host @"

sd is ready
  root:     $Root
  hooks:    $Root\hooks
  name:     $Name
  config:   $configFile
  bin:      $bin
  profile:  $profileFile
"@
if ($bashrc) { Write-Host "  bash:     $bashrc (completion in git-bash)" }
if ($warnings) { Write-Host "Warnings:"; $warnings | ForEach-Object { Write-Host "  - $_" } }
Write-Host "Restart your shell to use ``$Name``."
