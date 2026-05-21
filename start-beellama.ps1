<#
.SYNOPSIS
    Interactive launcher for beeLLama inference server configurations.

.DESCRIPTION
    Scans the run/ directory for launch scripts, groups them by speculative
    decoding mode (DFlash, MTP, DFlash+MTP, none), and presents a numbered
    menu sorted by quant within each group.

    DFlash configurations prompt for drafter quant (IQ4_XS, Q4_K_M, Q5_K_M)
    after selection. The choice and script are saved so they can be replayed
    instantly with -Rerun.

    Benchmark mode delegates to benchmark/run_benchmark.ps1 and supports
    single-config, paired, and VS (spec-mode comparison) runs.

.PARAMETER List
    Print the configuration menu and exit without launching.

.PARAMETER Rerun
    Re-launch the last interactive selection without prompting.
    Reads .last-run.json from the repo root. Fails if no previous
    selection exists or the saved script has been removed.

.PARAMETER Benchmark
    Enter benchmark mode. Presents sub-menu to choose Single, Pair,
    or VS comparison, then hands off to the benchmark orchestrator.

.EXAMPLE
    .\start-beellama.ps1
    # Interactive menu — pick a config, choose drafter, launch.

.EXAMPLE
    .\start-beellama.ps1 -Rerun
    # Instantly re-launch the last selection.

.EXAMPLE
    .\start-beellama.ps1 -List
    # Display available configurations and exit.

.EXAMPLE
    .\start-beellama.ps1 -Benchmark
    # Enter benchmark mode (Single / Pair / VS).

.LINK
    https://github.com/bchap1n/beellama_launcher

.NOTES
    Requires PowerShell 7+. Launch scripts live in run/ and dot-source
    run/beellama_common.ps1 for shared model/drafter/binary resolution.
#>

param(
    [switch]$List,
    [switch]$Rerun,
    [switch]$Benchmark
)

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
#             Qwen3.6-27B-Q4_K_M-dflash+mtp-reasoning.ps1
#             Qwopus3.5-9B-Coder-none.ps1

function parseScriptName {
    param([string]$FileName)

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    # Known spec modes (order matters — match longest first)
    $specModes = @("dflash+mtp", "dflash", "mtp", "none")
    $specMode  = ""
    $modifiers = @()

    foreach ($sm in $specModes) {
        if ($BaseName -match "-$([regex]::Escape($sm))(?:-(.+))?$") {
            $specMode  = $sm
            if ($Matches[1]) {
                $modifiers = $Matches[1] -split "-"
            }
            $modelQuant = $BaseName -replace "-$([regex]::Escape($sm)).*$", ""
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

    return [PSCustomObject]@{
        FileName    = $FileName
        Path        = $scriptPath
        Model       = $modelName
        Quant       = $quant
        SpecMode    = $specMode
        Modifiers   = $modifiers
        Description = $description
        DisplayName = "$modelName $quant [$specMode$(if ($modifiers) { ' ' + ($modifiers -join ' ') })]"
    }
}

# ---------- Collect and sort scripts ----------
$scripts = Get-ChildItem -Path $RunDir -Filter "*.ps1" |
    ForEach-Object { parseScriptName $_.Name } |
    Where-Object { $_ -ne $null } |
    Sort-Object -Property SpecMode, Quant, { $_.Modifiers -join "" }, Model

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
        $group = $e.SpecMode
        if ($group -ne $currentGroup) {
            Write-Host ""
            # Color-code by spec mode
            $groupColor = switch ($e.SpecMode) {
                "dflash"     { "Green" }
                "mtp"        { "Yellow" }
                "dflash+mtp" { "Magenta" }
                default      { "Gray" }
            }
            Write-Host "  $($e.SpecMode)" -ForegroundColor $groupColor
            $currentGroup = $group
        }

        $modStr = if ($e.Modifiers.Count -gt 0) { " ($($e.Modifiers -join ', '))" } else { "" }
        $label  = "$($e.Quant)$modStr"
        if ($e.Model -ne "Qwen3.6-27B") { $label = "$($e.Model) $label" }

        Write-Host ("    [{0,2}] {1,-30} {2}" -f $index, $label, $e.Description) -ForegroundColor DarkCyan
        $index++
    }

    Write-Host ""
    Write-Host "  $('=' * 40)" -ForegroundColor DarkGray
    Write-Host "   q = quit" -ForegroundColor DarkGray
    Write-Host ""
}

# ---------- Shared: prompt for DFlash drafter quant ----------
function pickDrafter {
    param([PSCustomObject]$entry)
    if ($entry.SpecMode -notlike "*dflash*") { return $null }

    Write-Host ""
    Write-Host "  DFlash drafter quant:" -ForegroundColor Yellow
    Write-Host "    [1] IQ4_XS  (default, smallest VRAM)" -ForegroundColor DarkCyan
    Write-Host "    [2] Q4_K_M" -ForegroundColor DarkCyan
    Write-Host "    [3] Q5_K_M" -ForegroundColor DarkCyan
    $sel = Read-Host "  Select drafter [1-3] (Enter = IQ4_XS)"
    switch ($sel) {
        "2" { return "Q4_K_M" }
        "3" { return "Q5_K_M" }
        default { return "IQ4_XS" }
    }
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

    Write-Host ""
    Write-Host "  beeLLama Benchmark Mode" -ForegroundColor Cyan
    Write-Host "  $('=' * 40)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    [1] Single   - benchmark one configuration" -ForegroundColor White
    Write-Host "    [2] Pair     - benchmark two configurations" -ForegroundColor White
    Write-Host "    [3] VS       - compare spec modes (dflash vs mtp vs dflash+mtp)" -ForegroundColor White
    Write-Host ""
    Write-Host "  $('=' * 40)" -ForegroundColor DarkGray
    Write-Host "   q = quit" -ForegroundColor DarkGray
    Write-Host ""

    $mode = Read-Host "  Select mode [1-3]"
    if ($mode -eq "q" -or $mode -eq "Q") { exit 0 }

    $benchScripts = @()
    $benchDrafter = $null

    switch ($mode) {
        "1" {
            # Single: pick one
            showMenu $scripts
            $pick = pickScript "  Select configuration [1-$($scripts.Count)]"
            if (-not $pick) { exit 0 }
            $benchDrafter = pickDrafter $pick
            $benchScripts = @($pick.Path)
        }
        "2" {
            # Pair: pick two
            showMenu $scripts
            Write-Host "  Pick first configuration:" -ForegroundColor Yellow
            $pickA = pickScript "  Config A [1-$($scripts.Count)]"
            if (-not $pickA) { exit 0 }
            Write-Host "  Pick second configuration:" -ForegroundColor Yellow
            $pickB = pickScript "  Config B [1-$($scripts.Count)]"
            if (-not $pickB) { exit 0 }
            $benchScripts = @($pickA.Path, $pickB.Path)
            # Prompt for drafter if either config is DFlash
            $anyDflash = @($pickA, $pickB) | Where-Object { $_.SpecMode -like "*dflash*" } | Select-Object -First 1
            if ($anyDflash) { $benchDrafter = pickDrafter $anyDflash }
        }
        "3" {
            # VS: auto-match spec modes for same model+quant+modifiers
            # Group scripts by Model + Quant + Modifiers, find groups with 2+ spec modes
            $vsGroups = @{}
            foreach ($s in $scripts) {
                $modKey = if ($s.Modifiers.Count -gt 0) { $s.Modifiers -join "+" } else { "base" }
                $groupKey = "$($s.Model)|$($s.Quant)|$modKey"
                if (-not $vsGroups.ContainsKey($groupKey)) { $vsGroups[$groupKey] = @() }
                $vsGroups[$groupKey] += $s
            }

            # Filter to groups with 2+ different spec modes
            $validGroups = @()
            foreach ($key in $vsGroups.Keys) {
                $group = $vsGroups[$key]
                $specModes = $group | Select-Object -ExpandProperty SpecMode -Unique
                if ($specModes.Count -ge 2) {
                    $validGroups += [PSCustomObject]@{
                        Key       = $key
                        Scripts   = $group
                        SpecModes = $specModes
                    }
                }
            }

            if ($validGroups.Count -eq 0) {
                Write-Host "  No model+quant combos found with multiple spec modes." -ForegroundColor Red
                exit 1
            }

            Write-Host ""
            Write-Host "  VS Comparisons Available" -ForegroundColor Cyan
            Write-Host "  $('=' * 40)" -ForegroundColor DarkGray
            Write-Host ""

            $idx = 1
            foreach ($vg in $validGroups) {
                $parts = $vg.Key -split "\|"
                $modelName = $parts[0]
                $quant     = $parts[1]
                $modLabel  = $parts[2]
                $modeList  = ($vg.SpecModes | Sort-Object) -join " vs "
                $display   = "$modelName $quant"
                if ($modLabel -ne "base") { $display += " ($modLabel)" }

                Write-Host ("    [{0,2}] {1,-40} {2}" -f $idx, $display, $modeList) -ForegroundColor DarkCyan
                $idx++
            }

            Write-Host ""
            Write-Host "  $('=' * 40)" -ForegroundColor DarkGray
            Write-Host "   q = quit" -ForegroundColor DarkGray
            Write-Host ""

            $vsSel = Read-Host "  Select comparison [1-$($validGroups.Count)]"
            if ($vsSel -eq "q" -or $vsSel -eq "Q") { exit 0 }
            $vsNum = 0
            if (-not [int]::TryParse($vsSel, [ref]$vsNum) -or $vsNum -lt 1 -or $vsNum -gt $validGroups.Count) {
                Write-Host "Invalid selection: $vsSel" -ForegroundColor Red
                exit 1
            }

            $chosen = $validGroups[$vsNum - 1]
            $benchScripts = $chosen.Scripts | Sort-Object SpecMode | ForEach-Object { $_.Path }

            # Prompt for drafter if any config is DFlash
            $anyDflash = $chosen.Scripts | Where-Object { $_.SpecMode -like "*dflash*" } | Select-Object -First 1
            if ($anyDflash) { $benchDrafter = pickDrafter $anyDflash }

            Write-Host ""
            Write-Host "  Will benchmark $($benchScripts.Count) configs:" -ForegroundColor Green
            foreach ($bp in $benchScripts) {
                Write-Host "    - $([System.IO.Path]::GetFileNameWithoutExtension($bp))" -ForegroundColor Cyan
            }
            Write-Host ""
        }
        default {
            Write-Host "Invalid mode: $mode" -ForegroundColor Red
            exit 1
        }
    }

    if ($benchScripts.Count -eq 0) {
        Write-Host "No scripts selected." -ForegroundColor Red
        exit 1
    }

    # Launch orchestrator
    $benchArgs = @{ Scripts = $benchScripts }
    if ($benchDrafter) { $benchArgs['DrafterQuant'] = $benchDrafter }
    & $BenchScript @benchArgs
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
    $drafterQ = $last.drafterQuant

    Write-Host ""
    Write-Host "  Rerun: $($chosen.DisplayName)" -ForegroundColor Green
    Write-Host "  Script:  $($chosen.Path)" -ForegroundColor Cyan
    if ($drafterQ) { Write-Host "  Drafter: DFlash-$drafterQ" -ForegroundColor Cyan }
    Write-Host ""

    if ($drafterQ) {
        & $chosen.Path -DrafterQuant $drafterQ
    } else {
        & $chosen.Path
    }
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

$drafterQ = pickDrafter $chosen

# ---------- Save selection for -Rerun ----------
@{ fileName = $chosen.FileName; drafterQuant = $drafterQ } |
    ConvertTo-Json | Set-Content $LastRunFile -Encoding utf8

Write-Host ""
Write-Host "  Launching: $($chosen.DisplayName)" -ForegroundColor Green
Write-Host "  Script:    $($chosen.Path)" -ForegroundColor Cyan
if ($drafterQ) { Write-Host "  Drafter:   DFlash-$drafterQ" -ForegroundColor Cyan }
Write-Host ""

# ---------- Launch ----------
if ($drafterQ) {
    & $chosen.Path -DrafterQuant $drafterQ
} else {
    & $chosen.Path
}
