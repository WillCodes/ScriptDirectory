# Runs tests/cases.txt (platforms: all, win) against src/sd.ps1 on a temporary copy of tests/root.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$tmp  = Join-Path ([IO.Path]::GetTempPath()) "sd test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$root = Join-Path $tmp 'sd root'
New-Item -ItemType Directory $tmp | Out-Null
Copy-Item "$PSScriptRoot/root" $root -Recurse -Force
$env:SD_ROOT = $root
Remove-Item Env:VISUAL, Env:EDITOR, Env:SD_NO_HOOKS -ErrorAction SilentlyContinue
Set-Location $tmp
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)   # so ▸ survives
$pwsh = (Get-Process -Id $PID).Path

# Runs sd with the given words; returns exit code, stdout and stderr (UTF-8, separately captured).
function Invoke-Case([string[]]$Words) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $psi.WorkingDirectory = $tmp   # Set-Location doesn't change the process cwd that children inherit
    foreach ($a in @('-NoLogo', '-NoProfile', '-File', "$repo/src/sd.ps1") + $Words) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $psi.RedirectStandardOutput = $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    [pscustomobject]@{ Code = $p.ExitCode; Out = $out.Result -replace "`r`n", "`n"; Err = $err.Result -replace "`r`n", "`n" }
}

$pass = 0; $fail = 0; $n = 0
foreach ($line in Get-Content "$PSScriptRoot/cases.txt" -Encoding utf8) {
    $n++
    if ($line.Trim() -eq '' -or $line.Trim().StartsWith('#')) { continue }
    $platform, $code, $cmd, $exp = ($line -split '\|', 4) | ForEach-Object { $_.Trim() }
    if ($platform -notin 'all', 'win') { continue }
    $words = @($cmd -split '\s+' | Where-Object { $_ -ne '' } | ForEach-Object { $_ -replace '^""$', '' })
    $exp = $exp.Replace('\t', "`t").Replace('\n', "`n")
    $not = $exp.StartsWith('!'); if ($not) { $exp = $exp.Substring(1) }
    $r = Invoke-Case $words
    $found = $r.Out.Contains($exp) -or $r.Err.Contains($exp)
    if ($r.Code -eq [int]$code -and ($exp -eq '' -or $found -ne $not)) {
        $pass++; Write-Host "PASS line $n  sd $cmd"
    } else {
        $fail++; Write-Host "FAIL line $n  sd $cmd" -ForegroundColor Red
        Write-Host "  exit: expected $code, got $($r.Code)"
        Write-Host "  expected$(if ($not) { ' NOT' }): $($exp -replace "`t", '\t' -replace "`n", '\n')"
        Write-Host "  stdout: $($r.Out.TrimEnd())"
        Write-Host "  stderr: $($r.Err.TrimEnd())"
    }
}
Set-Location $PSScriptRoot
Remove-Item $tmp -Recurse -Force
Write-Host "$pass passed, $fail failed"
exit ($fail -gt 0 ? 1 : 0)
