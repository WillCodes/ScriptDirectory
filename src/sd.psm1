# sd: run scripts by path-like words. See SPEC.md; section numbers (§n) refer to it.
# Runs inside the user's shell, so it never calls `exit`: the result is left in $global:LASTEXITCODE.

# Runnable extensions in priority order (§5.2). '' = extensionless.
$script:Exts = '.bat', '.cmd', '.sh', ''

# Meta-commands: name, usage, description. (--complete is hidden.)
$script:Meta = @(
    @('--help',   '',                                  'Show this help'),
    @('--hooks',  '[add|rm|on|off|edit ...]',          'Manage hooks'),
    @('--new',    '<path> [--bundle] [--bat | --sh]',  'Create a script'),
    @('--which',  '<word>... [args...]',               'Show what would run'),
    @('--export', '<file> <path>...',                  'Export scripts and hooks'),
    @('--import', '<file> [--force]',                  'Import an export file')
)

# ---- Output, config ---------------------------------------------------------------------------

function Write-SdError([string]$Message) {
    [Console]::Error.WriteLine("$($script:Cfg.Name): $Message")
    $global:LASTEXITCODE = 1
}

function Write-SdWarning([string]$Message) {
    [Console]::Error.WriteLine("$($script:Cfg.Name): warning: $Message")
}

# §3.1: %APPDATA%\sd\config, then SD_ROOT on top.
function Get-SdConfig {
    $cfg = @{ Root = Join-Path $HOME 'sd'; Name = 'sd' }
    $file = Join-Path $env:APPDATA 'sd\config'
    if (Test-Path -LiteralPath $file) {
        foreach ($line in Get-Content -LiteralPath $file) {
            if ($line -match '^\s*(root|name)\s*=\s*(.*?)\s*$') { $cfg[$Matches[1]] = $Matches[2] }
        }
    }
    if ($env:SD_ROOT) { $cfg.Root = $env:SD_ROOT }
    $cfg.Root = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($cfg.Root).TrimEnd('\')
    $cfg
}

# ---- Entries: what a folder contains (§5) -----------------------------------------------------

# The runnable files called $Name among $Files, best extension first.
function Select-SdFiles($Files, [string]$Name) {
    @($Files | Where-Object { $_.BaseName -eq $Name -and $_.Extension -in $script:Exts } |
        Sort-Object { [array]::IndexOf($script:Exts, $_.Extension.ToLower()) })
}

# Entries of folder $Dir: Name, Kind (namespace|bundle|loose|conflict), Path (folder, if any), Files.
function Get-SdEntries([string]$Dir) {
    $items = @(Get-ChildItem -LiteralPath $Dir | Where-Object { $_.Name -notlike '.*' })
    $entries = @{}
    foreach ($d in $items | Where-Object PSIsContainer) {
        if ($Dir -eq $script:Cfg.Root -and $d.Name -eq 'hooks') { continue }
        $files = Select-SdFiles (Get-ChildItem -LiteralPath $d.FullName -File) $d.Name
        $entries[$d.Name] = [pscustomobject]@{
            Name = $d.Name; Kind = ($files ? 'bundle' : 'namespace'); Path = $d.FullName; Files = $files }
    }
    $loose = $items | Where-Object { -not $_.PSIsContainer }
    foreach ($name in $loose.BaseName | Sort-Object -Unique) {
        $files = Select-SdFiles $loose $name
        if (-not $files) { continue }
        $folder = $entries[$name]
        $entries[$name] = $folder `
            ? [pscustomobject]@{ Name = $folder.Name; Kind = 'conflict'; Path = $folder.Path; Files = $files } `
            : [pscustomobject]@{ Name = $files[0].BaseName; Kind = 'loose'; Path = $null; Files = $files }
    }
    $entries.Values
}

# §5.1. Returns Kind = namespace (Name, Dir), bundle|loose (Name, File, Dir, Args, Entry),
# or notfound|ambiguous (Error, and Dir for the listing).
function Resolve-SdEntry([string[]]$Words) {
    $dir = $script:Cfg.Root
    $prefix = ''
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $w = $Words[$i]
        $e = $null
        if ($w -notmatch '[/\\]|^[-.]') { $e = Get-SdEntries $dir | Where-Object Name -eq $w | Select-Object -First 1 }
        if (-not $e) {
            $where = $prefix ? $prefix.TrimEnd('/') : 'the sd root'
            return [pscustomobject]@{ Kind = 'notfound'; Dir = $dir; Error = "no script or folder '$w' in $where" }
        }
        $name = "$prefix$($e.Name)"
        if ($e.Kind -eq 'conflict') {
            return [pscustomobject]@{ Kind = 'ambiguous'; Error =
                "ambiguous '$name': both folder $($e.Path) and file $($e.Files[0].FullName) exist" }
        }
        if ($e.Kind -ne 'namespace') {
            return [pscustomobject]@{ Kind = $e.Kind; Name = $name; File = $e.Files[0]; Dir = $e.Files[0].DirectoryName
                Args = @($Words | Select-Object -Skip ($i + 1)); Entry = $e }
        }
        $dir = $e.Path
        $prefix = "$name/"
    }
    [pscustomobject]@{ Kind = 'namespace'; Name = $prefix.TrimEnd('/'); Dir = $dir }
}

# §5.1 step 4 (and §5.4): the error, plus the listing of the folder for a word that wasn't found.
function Write-SdResolveError($R) {
    Write-SdError $R.Error
    if ($R.Kind -eq 'notfound') { Format-SdItems @(Get-SdItems $R.Dir) }
}

# ---- Descriptions and listing (§6, §7) --------------------------------------------------------

function Get-SdFileDescription($File) {
    $lines = @(Get-Content -LiteralPath $File.FullName -TotalCount 10)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = "$($lines[$i])".Trim()
        if ($File.Extension -in '.bat', '.cmd') {
            if ($line -match '^(?:::|REM )\s*(.*)$') { return $Matches[1] }
        } elseif ($line.StartsWith('#') -and -not ($i -eq 0 -and $line.StartsWith('#!'))) {
            return $line.Substring(1).Trim()
        }
    }
}

function Get-SdDescription($Entry) {
    if ($Entry.Kind -eq 'conflict') { return 'ambiguous' }
    foreach ($f in $Entry.Files) {
        $d = Get-SdFileDescription $f
        if ($d) { return $d }
    }
    $help = $Entry.Path ? (Join-Path $Entry.Path '.help') : $null   # namespaces, and bundles without a comment
    if ($help -and (Test-Path -LiteralPath $help)) {
        Get-Content -LiteralPath $help | Where-Object { $_.Trim() } | Select-Object -First 1 | ForEach-Object Trim
    }
}

# Items of folder $Dir in listing order: namespaces first, then the rest, each case-insensitively.
function Get-SdItems([string]$Dir) {
    foreach ($e in Get-SdEntries $Dir | Sort-Object { $_.Kind -ne 'namespace' }, Name) {
        $type = switch ($e.Kind) { 'namespace' { 'dir' } 'conflict' { 'conflict' } default { 'script' } }
        [pscustomobject]@{ Name = $e.Name; Type = $type; Desc = Get-SdDescription $e }
    }
}

function Format-SdItems($Items) {
    $marker = @{ dir = ' '; script = '▸'; conflict = '!'; meta = ' ' }
    $label = { param($i) $i.Name + ($i.Type -eq 'dir' ? '/' : '') }
    $width = ($Items | ForEach-Object { (& $label $_).Length } | Measure-Object -Maximum).Maximum
    foreach ($i in $Items) { ('{0} {1} {2}' -f (& $label $i).PadRight($width), $marker[$i.Type], $i.Desc).TrimEnd() }
}

# ---- Completion (§8) --------------------------------------------------------------------------

# Prefix matches if there are any, else subsequence matches ranked by first match, then span, then name.
function Select-SdMatches($Items, [string]$Partial) {
    $prefix = @($Items | Where-Object { $_.Name.StartsWith($Partial, 'OrdinalIgnoreCase') })
    if ($prefix) { return $prefix }
    $Items | ForEach-Object {
        $start = $pos = -1
        foreach ($c in $Partial.ToCharArray()) {
            $pos = $_.Name.IndexOf([string]$c, $pos + 1, [StringComparison]::OrdinalIgnoreCase)
            if ($pos -lt 0) { return }
            if ($start -lt 0) { $start = $pos }
        }
        [pscustomobject]@{ Item = $_; Name = $_.Name; Start = $start; Span = $pos - $start + 1 }
    } | Sort-Object Start, Span, Name | ForEach-Object Item
}

# The candidates for <words...> <partial> (§8.1): meta-commands for a first word starting with --,
# else the matches in the namespace the words reach. None once they reach a script or don't resolve.
function Get-SdCandidates([string[]]$Rest) {
    $partial = $Rest.Count ? $Rest[-1] : ''
    $words = @($Rest | Select-Object -SkipLast 1)
    if ($words.Count -eq 0 -and $partial.StartsWith('--')) {
        $items = $script:Meta | Sort-Object { $_[0] } | ForEach-Object { [pscustomobject]@{ Name = $_[0]; Type = 'meta'; Desc = $_[2] } }
    } else {
        $r = Resolve-SdEntry $words
        if ($r.Kind -ne 'namespace') { return }
        $items = Get-SdItems $r.Dir
    }
    Select-SdMatches $items $partial
}

# --complete [words...] <partial>
function Invoke-SdComplete([string[]]$Rest) {
    Get-SdCandidates $Rest | ForEach-Object { "$($_.Name)`t$($_.Type)`t$($_.Desc)" }
}

# ---- Running (§11) ----------------------------------------------------------------------------

# bash for .sh scripts: the one on PATH, unless that is WSL; else the bash of the Git for Windows
# that git.exe belongs to. ViaGit means its folder must be put on PATH while scripts run.
function Get-SdBash {
    if ($script:Bash -ne $null) { return $script:Bash }   # cached per Invoke-Sd call; $false = none
    $script:Bash = $false
    $onPath = Get-Command bash -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($onPath -and -not $onPath.Source.StartsWith("$env:SystemRoot\System32\", 'OrdinalIgnoreCase')) {
        $script:Bash = [pscustomobject]@{ Path = $onPath.Source; ViaGit = $false }
    } elseif ($git = Get-Command git.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1) {
        # git.exe sits in <Git>\cmd or <Git>\mingw64\bin; walk up to the folder that has bin\bash.exe.
        for ($d = Split-Path $git.Source; $d; $d = Split-Path $d) {
            if (Test-Path -LiteralPath "$d\bin\bash.exe") {
                $script:Bash = [pscustomobject]@{ Path = "$d\bin\bash.exe"; ViaGit = $true }
                break
            }
        }
    }
    $script:Bash
}

# Runs $Body with the given environment variables set, and puts every one of them back afterwards.
function Invoke-WithEnv([hashtable]$Vars, [scriptblock]$Body) {
    $saved = @{}
    foreach ($k in $Vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }   # $null = unset
    try {
        foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
        & $Body
    } finally {
        foreach ($k in $saved.Keys) {   # a plain $null would become "" (set but empty)
            [Environment]::SetEnvironmentVariable($k, $null -eq $saved[$k] ? [NullString]::Value : $saved[$k])
        }
    }
}

# Runs one resolved script with $ScriptArgs. Leaves its exit code in $LASTEXITCODE.
# Phase 5 wraps this with the before/after hooks.
function Invoke-SdScript($Entry, [string[]]$ScriptArgs) {
    $file = $Entry.File.FullName
    $isCmd = $Entry.File.Extension -in '.bat', '.cmd'
    $bash = Get-SdBash
    if (-not $isCmd -and -not $bash) {
        return Write-SdError 'bash not found: install Git for Windows (and put git on PATH) to run .sh scripts'
    }
    if (-not $isCmd -and [array]::IndexOf([IO.File]::ReadAllBytes($file), [byte]13) -ge 0) {
        Write-SdWarning "$file has CRLF line endings, bash will probably fail on it"
    }
    $vars = @{ SD_ROOT = $script:Cfg.Root; SD_NAME = $Entry.Name; SD_DIR = $Entry.Dir; MSYS_NO_PATHCONV = '1' }
    if ($bash -and $bash.ViaGit) { $vars.PATH = (Split-Path $bash.Path) + ";$env:PATH" }   # so a .bat can call bash
    $global:LASTEXITCODE = 0
    Invoke-WithEnv $vars {
        if ($isCmd) { & $file @ScriptArgs } else { & $bash.Path ($file -replace '\\', '/') @ScriptArgs }
    }
}

# ---- Meta-commands (§10) ----------------------------------------------------------------------

function Show-SdHelp {
    $name = $script:Cfg.Name
    "$name - run scripts from a folder tree"
    ''
    'usage:'
    "  $name                        list the sd root"
    "  $name <word>... [args...]    run a script, or list a namespace"
    ''
    'meta-commands:'
    foreach ($m in $script:Meta) { '  {0,-9}{1,-34} {2}' -f $m[0], $m[1], $m[2] }
}

function Show-SdWhich($R) {
    if ($R.Kind -in 'notfound', 'ambiguous') { return Write-SdResolveError $R }
    if ($R.Kind -eq 'namespace') {
        "namespace: $($R.Name ? $R.Name : '(root)')"
        return Format-SdItems @(Get-SdItems $R.Dir)
    }
    $runner = if ($R.File.Extension -in '.bat', '.cmd') { 'cmd' } else {
        $bash = Get-SdBash
        "bash ($($bash ? $bash.Path : 'not found'))"
    }
    "name:        $($R.Name)"
    "kind:        $($R.Kind -eq 'bundle' ? 'bundle' : 'script')"
    "file:        $($R.File.FullName)"
    "runs with:   $runner"
    "description: $(Get-SdDescription $R.Entry)"
    "args:        $($R.Args -join ' ')"
    # Phase 5: the "hooks:" section goes here.
}

# The contents of templates\script.<ext> for a script called $Name. The .bat hands off to the .sh
# unless there is no .sh, then it just echoes. LF for .sh, CRLF for .bat.
function Get-SdTemplate([string]$Ext, [string]$Name, [bool]$HasSh) {
    $text = (Get-Content -Raw "$PSScriptRoot\..\templates\script$Ext").Replace("`r`n", "`n").Replace('<name>', $Name)
    if ($Ext -eq '.bat') {
        if (-not $HasSh) { $text = $text -replace '(?m)^bash .*$', 'echo args: %*' }
        $text = $text.Replace("`n", "`r`n")
    }
    $text
}

function New-SdScript([string[]]$Rest) {
    $flags = @($Rest | Where-Object { $_ -like '--*' })
    $paths = @($Rest | Where-Object { $_ -notlike '--*' })
    $rel = $paths.Count -eq 1 ? ($paths[0] -replace '\\', '/').Trim('/') : ''
    $badName = $rel -eq '' -or ($rel.Split('/') | Where-Object { $_ -eq '' -or $_ -match '^[-.]|\s' })
    if ($badName -or ($flags | Where-Object { $_ -notin '--bundle', '--sh', '--bat' })) {
        return Write-SdError 'usage: --new <path> [--bundle] [--bat | --sh]  (names: no spaces, not starting with - or .)'
    }
    $sh = $flags -contains '--sh'; $bat = $flags -contains '--bat'
    if (-not $sh -and -not $bat) { $sh = $bat = $true }

    $loc = Join-Path $script:Cfg.Root $rel
    $base = Split-Path $loc -Leaf
    $target = $flags -contains '--bundle' ? (Join-Path $loc $base) : $loc   # path without extension
    $new = @(if ($sh) { "$target.sh" }; if ($bat) { "$target.bat" })

    # Existing target files, or an entry that would make the name ambiguous (§5.4).
    $clashes = @($new | Where-Object { Test-Path -LiteralPath $_ })
    if ($flags -contains '--bundle') {
        $parent = Split-Path $loc
        if (Test-Path -LiteralPath $parent) { $clashes += Select-SdFiles (Get-ChildItem -LiteralPath $parent -File) $base | ForEach-Object FullName }
        # An existing bundle may gain files; any other folder is a namespace and must not become one.
        if ((Test-Path -LiteralPath $loc) -and -not (Select-SdFiles (Get-ChildItem -LiteralPath $loc -File) $base)) { $clashes += $loc }
    } elseif (Test-Path -LiteralPath $loc -PathType Container) { $clashes += $loc }
    if ($clashes) {
        return $clashes | ForEach-Object { Write-SdError "cannot create '$rel': $_ already exists" }
    }

    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    $utf8 = [Text.UTF8Encoding]::new($false)
    foreach ($f in $new) {
        $ext = [IO.Path]::GetExtension($f)
        [IO.File]::WriteAllText($f, (Get-SdTemplate $ext (Split-Path $target -Leaf) $sh), $utf8)
    }
    $editor = $env:VISUAL ? $env:VISUAL : $env:EDITOR
    if ($editor) {   # through cmd so that values like `code --wait` work
        $quoted = ($new | ForEach-Object { "`"$_`"" }) -join ' '
        Start-Process cmd -ArgumentList "/c `"$editor $quoted`"" -Wait -NoNewWindow
    } else {
        $new
    }
}

function Invoke-SdMeta([string]$Command, [string[]]$Rest) {
    switch ($Command) {
        '--help'     { Show-SdHelp }
        '--complete' { Invoke-SdComplete $Rest }
        '--new'      { New-SdScript $Rest }
        '--which'    { Show-SdWhich (Resolve-SdEntry $Rest) }
        { $_ -in '--hooks', '--export', '--import' } { Write-SdError 'not implemented yet' }
        default      { Write-SdError "unknown meta-command '$Command'"; Show-SdHelp }
    }
}

# ---- Entry point ------------------------------------------------------------------------------

# Args are the words after the command name. Result code: $global:LASTEXITCODE.
function Invoke-Sd {
    $global:LASTEXITCODE = 0
    $script:Cfg = Get-SdConfig
    $script:Bash = $null
    if (-not (Test-Path -LiteralPath $script:Cfg.Root -PathType Container)) {
        return Write-SdError "sd root '$($script:Cfg.Root)' does not exist"
    }
    $words = @($args)
    if ($words.Count -and $words[0].StartsWith('--')) {
        return Invoke-SdMeta $words[0] @($words | Select-Object -Skip 1)
    }

    $r = Resolve-SdEntry $words
    switch ($r.Kind) {
        'namespace' { Format-SdItems @(Get-SdItems $r.Dir) }
        { $_ -in 'notfound', 'ambiguous' } { Write-SdResolveError $r }
        default     { Invoke-SdScript $r $r.Args }
    }
}

# ---- Shell integration (§8.3, §12) ------------------------------------------------------------

$script:CmdName = (Get-SdConfig).Name
Set-Item "Function:\global:$script:CmdName" { Invoke-Sd @args }

# Menu entries show the §7 listing line; only the name is inserted. Never writes errors into the prompt.
Register-ArgumentCompleter -Native -CommandName $script:CmdName -ScriptBlock {
    param($word, $ast, $cursor)
    try {
        $ErrorActionPreference = 'Stop'
        $script:Cfg = Get-SdConfig
        $words = @($ast.CommandElements | Select-Object -Skip 1 | Where-Object { $_.Extent.EndOffset -lt $cursor } |
            ForEach-Object { $_.Extent.Text.Trim('"', "'") })
        $items = @(Get-SdCandidates (@($words) + "$word"))
        $lines = @(Format-SdItems $items)
        for ($i = 0; $i -lt $items.Count; $i++) {
            $type = $items[$i].Type -eq 'dir' ? 'ProviderContainer' : 'ParameterValue'
            [Management.Automation.CompletionResult]::new($items[$i].Name, $lines[$i], $type, ($items[$i].Desc ? $items[$i].Desc : $items[$i].Name))
        }
    } catch { }
}

# Tab opens the menu after "<name> ", and does whatever it did before everywhere else.
if (Get-Module PSReadLine) {
    $name = $script:CmdName
    $prev = (Get-PSReadLineKeyHandler -Chord Tab).Function
    if (-not [Microsoft.PowerShell.PSConsoleReadLine].GetMethod("$prev")) { $prev = 'TabCompleteNext' }
    Set-PSReadLineKeyHandler -Key Tab -Description "$name menu completion" -ScriptBlock {
        $line = $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        $fn = $line -match "^\s*$([regex]::Escape($name))\s" ? 'MenuComplete' : $prev
        [Microsoft.PowerShell.PSConsoleReadLine]::$fn()
    }.GetNewClosure()
}

Export-ModuleMember -Function Invoke-Sd
