#Requires -Version 7
# Uninstalls and installs sd again, e.g. after pulling changes. Keeps the root and name from the machine config
# (read before uninstall.ps1 removes it); -Root / -Name change them. The sd root is never touched.
#   pwsh ./reload.ps1 [-Root <path>] [-Name <name>]
param([string]$Root, [string]$Name)
$ErrorActionPreference = 'Stop'

$configFile = Join-Path $env:APPDATA 'sd\config'
$old = @{}
if (Test-Path -LiteralPath $configFile) {
    foreach ($line in Get-Content -LiteralPath $configFile) {
        if ($line -match '^\s*(root|name)\s*=\s*(.*?)\s*$') { $old[$Matches[1]] = $Matches[2] }
    }
}
$values = @{}   # anything still unknown is asked for by install.ps1
if ($Root -or $old.root) { $values.Root = $Root ? $Root : $old.root }
if ($Name -or $old.name) { $values.Name = $Name ? $Name : $old.name }

& "$PSScriptRoot\uninstall.ps1"
Write-Host ''
& "$PSScriptRoot\install.ps1" @values
