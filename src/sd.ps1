# Entry point for cmd and git-bash. Interactive pwsh sessions import sd.psm1 directly instead.
[Console]::OutputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new($false)   # so ▸ survives pipes
Import-Module "$PSScriptRoot/sd.psm1" -Force
Invoke-Sd @args
exit $LASTEXITCODE
