# PowerShell bundle
Write-Output "ps1bun.ps1: $args"
bash "$PSScriptRoot/ps1bun.sh" @args
exit $LASTEXITCODE
