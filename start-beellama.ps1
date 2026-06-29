<#
.SYNOPSIS
    Interactive launcher for beeLLama inference server configurations.

.DESCRIPTION
    Scans the run/ directory for launch scripts, groups them by speculative
    decoding mode (DFlash, MTP, DFlash+MTP, none), and presents a numbered
    menu sorted by quant within each group.

    The choice and script are saved so they can be replayed instantly with
    -Rerun.

    Benchmark mode delegates to benchmark/run_benchmark.ps1 after
    selecting configurations via comma-separated index list.

.PARAMETER List
    Print the configuration menu and exit without launching.

.PARAMETER Rerun
    Re-launch the last interactive selection without prompting.
    Reads .last-run.json from the repo root. Fails if no previous
    selection exists or the saved script has been removed.

.PARAMETER Benchmark
    Enter benchmark mode. Shows the menu and accepts comma-separated
    indices (e.g. "1,4,9") to select configurations to benchmark.

.EXAMPLE
    .\start-beellama.ps1
    # Interactive menu — pick a config, launch.

.EXAMPLE
    .\start-beellama.ps1 -Rerun
    # Instantly re-launch the last selection.

.EXAMPLE
    .\start-beellama.ps1 -List
    # Display available configurations and exit.

.EXAMPLE
    .\start-beellama.ps1 -Benchmark
    # Show menu, then enter e.g. "1,4,9" to benchmark three configs.

.LINK
    https://github.com/bchap1n/beellama_launcher

.NOTES
    Requires PowerShell 7+. Launch scripts live in run/ and dot-source
    run/beellama_common.ps1 for shared model/drafter/binary resolution.
#>

param(
    [switch]$List,
    [switch]$Rerun,
    [switch]$Benchmark,
    [int]$MaxTokens
)

nvidia-smi -pl 250

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RunDir   = Join-Path $RepoRoot "run"
$LastRunFile = Join-Path $RepoRoot ".last-run.json"

if (-not (Test-Path $RunDir)) {
    Write-Error "Run directory not found: $RunDir"
    exit 1
}

# ---------- Parse script filenames ----------
# Convention: {Model}-{Quant}-{SpecMode}[-modifier].ps1
# Examples:   Qwen3.6-27B-Q4_K_M-dflash.ps1
#             Qwen3.6-27B-Q4_K_M-dflash-mtp-reasoning.ps1
#             Qwopus3.5-9B-Coder-none.ps1

# ---------- Resolve source binary from script content ----------
function getScriptSource {
    param([string]$Path)
    $lines = Get-Content $Path -TotalCount 80 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match 'Get-ServerBinary\s+-Build\s+"([^"]+)"') {
            return $Matches[1]
        }
        if ($line -match '# Source:\s*(\S+)') {
            return $Matches[1]
        }
    }
    Write-Host "  WARNING: $([System.IO.Path]::GetFileName($Path)) has no source declared — skipping" -ForegroundColor Yellow
    return $null
}

# ---------- Resolve ctx size from script content (authoritative over comment) ----------
function getScriptCtxSize {
    param([string]$Path)
    $lines = Get-Content $Path -TotalCount 80 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '--ctx-size\s+(\d+)') {
            return [int]$Matches[1]
        }
        if ($line -match '^\s*-c\s+(\d+)') {
            return [int]$Matches[1]
        }
    }
    return $null
}

function parseScriptName {
    param([string]$FileName)

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    # Known spec modes (order matters — match longest first)
    $specModes = @("dflash-mtp", "dflash", "ngram-mtp", "ik-two-stage", "mtp", "none")
    $specMode  = ""
    $modifiers = @()

    foreach ($sm in $specModes) {
        if ($BaseName -cmatch "-$([regex]::Escape($sm))(?:-(.+))?$") {
            $specMode  = $sm
            if ($Matches[1]) {
                $modifiers = $Matches[1] -split "-"
            }
            $modelQuant = $BaseName -creplace "-$([regex]::Escape($sm)).*$", ""
            break
        }
    }

    if (-not $specMode) {
        return $null
    }

    # Split model+quant: everything up to the last dash-separated quant token
    # e.g. "Qwen3.6-27B-Q4_K_M" → model "Qwen3.6-27B", quant "Q4_K_M"
    $quantPattern = "(Q\d+_K_[A-Z]+|Q\d+_K|BF16|F32|F16|none)"
    if ($modelQuant -match "^(.+)-($quantPattern)$") {
        $modelName = $Matches[1]
        $quant     = $Matches[2]
    } else {
        $modelName = $modelQuant
        $quant     = ""
    }

    # Extract key details from the script's first comment line
    $scriptPath = Join-Path $RunDir $FileName
    $description = ""
    $firstLine = Get-Content $scriptPath -TotalCount 1 -ErrorAction SilentlyContinue
    if ($firstLine -match "^#\s*(.+)") {
        $description = $Matches[1]
    }

    $ctxSize = getScriptCtxSize $scriptPath

    $ctxSuffix = if ($ctxSize) { " [$([int]($ctxSize/1024))k]" } else { "" }
    $displayName = "$modelName $quant [$specMode$(if ($modifiers) { ' ' + ($modifiers -join ' ') })]$ctxSuffix"

    return [PSCustomObject]@{
        FileName    = $FileName
        Path        = $scriptPath
        Model       = $modelName
        Quant       = $quant
        SpecMode    = $specMode
        Modifiers   = $modifiers
        Description = $description
        Source      = getScriptSource $scriptPath
        CtxSize     = $ctxSize
        DisplayName = $displayName
    }
}

# ---------- Collect and sort scripts ----------
$scripts = Get-ChildItem -Path $RunDir -Filter "*.ps1" |
    ForEach-Object { parseScriptName $_.Name } |
    Where-Object { $_ -ne $null -and $_.Source } |
    Sort-Object -Property Source, SpecMode, Model, Quant, { $_.Modifiers -join "" }

if ($scripts.Count -eq 0) {
    Write-Host "No launch scripts found in $RunDir" -ForegroundColor Red
    exit 1
}

# ---------- Display grouped menu ----------
function showMenu {
    param($entries)

    Write-Host ""
    Write-Host "  beeLLama Launch Configurations" -ForegroundColor Cyan
    Write-Host "  $('=' * 40)" -ForegroundColor DarkGray

    $currentGroup = ""
    $index = 1

    foreach ($e in $entries) {
        $group = "$($e.Source) - $($e.SpecMode)"
        if ($group -ne $currentGroup) {
            Write-Host ""
            # Color-code by source
            $groupColor = switch ($e.Source) {
                "beellama"        { "Green" }
                "beellama_fork"   { "Yellow" }
                "ik_llama"        { "Magenta" }
                "llama.cpp"       { "Cyan" }
                "beellama_prebuilt" { "DarkYellow" }
                "lucebox"         { "Blue" }
                default           { "Gray" }
            }
            Write-Host "  $group" -ForegroundColor $groupColor
            $currentGroup = $group
        }

        $modStr = if ($e.Modifiers.Count -gt 0) { " ($($e.Modifiers -join ', '))" } else { "" }
        $ctxStr = if ($e.CtxSize) { " [$([int]($e.CtxSize/1024))k]" } else { "" }
        $label  = "$($e.Model) $($e.Quant)$modStr$ctxStr"

        Write-Host ("    [{0,2}] {1,-50} {2}" -f $index, $label, $e.Description) -ForegroundColor DarkCyan
        $index++
    }

    Write-Host ""
    Write-Host "  $('=' * 40)" -ForegroundColor DarkGray
    Write-Host "   q = quit" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------- Shared: pick one script from numbered list ----------
function pickScript {
    param([string]$prompt)
    $sel = Read-Host $prompt
    if ($sel -eq "q" -or $sel -eq "Q") { return $null }
    $num = 0
    if (-not [int]::TryParse($sel, [ref]$num) -or $num -lt 1 -or $num -gt $scripts.Count) {
        Write-Host "Invalid selection: $sel" -ForegroundColor Red
        return $null
    }
    return $scripts[$num - 1]
}

# ==========================================================
#  BENCHMARK MODE
# ==========================================================
if ($Benchmark) {
    $BenchScript = Join-Path $RepoRoot "benchmark\run_benchmark.ps1"
    if (-not (Test-Path $BenchScript)) {
        Write-Error "Benchmark script not found: $BenchScript"
        exit 1
    }

    showMenu $scripts

    Write-Host "  Benchmark: pick 1–4 configs (comma-separated, in run order)" -ForegroundColor Cyan
    Write-Host "  Example: 1,4,9   or   1, 4, 3, 9" -ForegroundColor DarkGray
    Write-Host ""

    $raw = Read-Host "  Select [1-$($scripts.Count)]"
    if ($raw -eq "q" -or $raw -eq "Q") { exit 0 }

    # Parse comma-separated indices
    $benchScripts = @()
    foreach ($token in ($raw -split ",")) {
        $t = $token.Trim()
        if ($t -eq "") { continue }
        $num = 0
        if (-not [int]::TryParse($t, [ref]$num) -or $num -lt 1 -or $num -gt $scripts.Count) {
            Write-Host "  Invalid index: '$t'" -ForegroundColor Red
            exit 1
        }
        $benchScripts += $scripts[$num - 1].Path
    }

    $count = $benchScripts.Count
    if ($count -eq 0) {
        Write-Host "  No valid selections." -ForegroundColor Red
        exit 1
    }
    if ($count -gt 4) {
        Write-Host "  Max 4 configs allowed (got $count)." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "  Will benchmark $count config$(if ($count -gt 1) {'s'}):" -ForegroundColor Green
    foreach ($bp in $benchScripts) {
        Write-Host "    - $([System.IO.Path]::GetFileNameWithoutExtension($bp))" -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host "  Prompt mode:" -ForegroundColor Cyan
    Write-Host "    [1] Standard      (~150 tok short prompts)" -ForegroundColor DarkCyan
    Write-Host "    [2] LongCtx       (~125K tok prefill per prompt)" -ForegroundColor DarkCyan
    Write-Host "    [3] Coding Quality (PowerShell, static analysis scoring)" -ForegroundColor DarkCyan
    $promptChoice = Read-Host "  Select [1-3]"
    Write-Host ""

    # Launch orchestrator with MaxTokens passthrough
    $mtArg = if ($MaxTokens) { @("-MaxTokens", $MaxTokens) } else { @() }
    if ($promptChoice -eq "2") {
        & $BenchScript -Scripts $benchScripts -LongCtx @mtArg
    } elseif ($promptChoice -eq "3") {
        & $BenchScript -Scripts $benchScripts -Quality -Runs 1 @mtArg
    } else {
        & $BenchScript -Scripts $benchScripts @mtArg
    }
    exit 0
}

# ==========================================================
#  NORMAL LAUNCH MODE
# ==========================================================

# ---------- Rerun: replay last selection ----------
if ($Rerun) {
    if (-not (Test-Path $LastRunFile)) {
        Write-Host "No previous selection found. Run interactively first." -ForegroundColor Red
        exit 1
    }
    $last = Get-Content $LastRunFile -Raw | ConvertFrom-Json
    $chosen = $scripts | Where-Object { $_.FileName -eq $last.fileName } | Select-Object -First 1
    if (-not $chosen) {
        Write-Host "Last script '$($last.fileName)' no longer exists in $RunDir" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "  Rerun: $($chosen.DisplayName)" -ForegroundColor Green
    Write-Host "  Script: $($chosen.Path)" -ForegroundColor Cyan
    Write-Host ""

    & $chosen.Path
    exit 0
}

showMenu $scripts

if ($List) { exit 0 }

# ---------- Prompt for selection ----------
$chosen = pickScript "  Select configuration [1-$($scripts.Count)]"
if (-not $chosen) {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# ---------- Save selection for -Rerun ----------
@{ fileName = $chosen.FileName } |
    ConvertTo-Json | Set-Content $LastRunFile -Encoding utf8

Write-Host ""
Write-Host "  Launching: $($chosen.DisplayName)" -ForegroundColor Green
Write-Host "  Script:    $($chosen.Path)" -ForegroundColor Cyan
Write-Host ""

# ---------- Launch ----------
& $chosen.Path
