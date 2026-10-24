#Requires -Version 7
# Removes what install.ps1 set up: entry points, user PATH entry, profile block and machine config.
# The sd root and the scripts in it are never touched.
$ErrorActionPreference = 'Stop'

$bin = Join-Path $env:LOCALAPPDATA 'sd\bin'
$configFile = Join-Path $env:APPDATA 'sd\config'
$sandbox = $env:SD_INSTALL_SANDBOX   # test hook: fake profile and user Path inside this folder, no registry
$profileFile = $sandbox ? "$sandbox\profile.ps1" : $PROFILE.CurrentUserAllHosts

$cfg = @{ name = 'sd' }
if (Test-Path -LiteralPath $configFile) {
    foreach ($line in Get-Content -LiteralPath $configFile) {
        if ($line -match '^\s*(root|name)\s*=\s*(.*?)\s*$') { $cfg[$Matches[1]] = $Matches[2] }
    }
}

# Entry points and config, then their folders if they are left empty.
Remove-Item -LiteralPath "$bin\$($cfg.name).cmd", "$bin\$($cfg.name)", $configFile -Force -ErrorAction Ignore
foreach ($dir in $bin, (Split-Path $bin), (Split-Path $configFile)) {
    if ((Test-Path -LiteralPath $dir) -and -not (Get-ChildItem -LiteralPath $dir -Force)) { Remove-Item -LiteralPath $dir }
}

# User PATH: REG_EXPAND_SZ, so read unexpanded and written back as such (see install.ps1).
$expand = { [Environment]::ExpandEnvironmentVariables($args[0]).TrimEnd('\') }
$userPath = $sandbox ? ((Test-Path "$sandbox\userpath.txt") ? ([IO.File]::ReadAllText("$sandbox\userpath.txt")).Trim() : '') :
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$entries = @($userPath -split ';')   # empty entries kept, so the rest is written back unchanged
$kept = @($entries | Where-Object { -not $_ -or (& $expand $_) -ine $bin })
if ($kept.Count -ne $entries.Count) {
    if ($sandbox) {
        [IO.File]::WriteAllText("$sandbox\userpath.txt", $kept -join ';')
    } else {
        [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true).SetValue('Path', ($kept -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
        # Setting and clearing a user variable makes .NET broadcast WM_SETTINGCHANGE, so new terminals see the new Path.
        [Environment]::SetEnvironmentVariable('SD_INSTALL_TMP', '1', 'User')
        [Environment]::SetEnvironmentVariable('SD_INSTALL_TMP', [NullString]::Value, 'User')   # a plain $null would leave it set to ""
    }
}

# Profiles (PowerShell, and git-bash's ~/.bashrc / ~/.bash_profile): drop the block; delete a file left empty.
$bashHome = $env:HOME ? $env:HOME : $env:USERPROFILE
foreach ($file in $profileFile, (Join-Path $bashHome '.bashrc'), (Join-Path $bashHome '.bash_profile')) {
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $text = [IO.File]::ReadAllText($file)
    $pattern = '(?s)(?:\r?\n)?# >>> sd >>>.*?# <<< sd <<<\r?\n?'
    if ($text -notmatch $pattern) { continue }
    $text = $text -replace $pattern, ''
    if ($text.Trim()) { [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($false)) } else { Remove-Item -LiteralPath $file }
}

Write-Host "Removed '$($cfg.name)' (entry points, PATH entry, profile blocks, machine config)."
Write-Host $(if ($cfg.root) { "Your sd root was NOT touched; your scripts are still in $($cfg.root)" } else { 'Your sd root, if you made one, was NOT touched.' })
Write-Host 'Restart your shell for the change to take effect.'
