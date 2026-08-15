# postpass_merge.ps1
# Phase 3: Merges AST validation + PSES diagnostics into enriched CSV + HTML.
# Works gracefully if PSES results are missing (partial merge).
#
# Usage: .\postpass_merge.ps1 -ResultsDir <benchmark-output-dir>

param(
    [Parameter(Mandatory)]
    [string]$ResultsDir
)

$ErrorActionPreference = "Stop"
$BenchDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$postDir = Join-Path $ResultsDir "postpass"

# ---------- Load data sources ----------
$resultsPath  = Join-Path $ResultsDir "results_full.json"
$astPath      = Join-Path $postDir "ast_validation.json"
$psesPath     = Join-Path $postDir "pses_diagnostics.json"

if (-not (Test-Path $resultsPath)) {
    Write-Error "results_full.json not found at $resultsPath"
    exit 1
}
$allResults = Get-Content $resultsPath -Raw | ConvertFrom-Json
if ($allResults -isnot [array]) { $allResults = @($allResults) }

$astResults = @{}
if (Test-Path $astPath) {
    $astData = Get-Content $astPath -Raw | ConvertFrom-Json
    if ($astData -isnot [array]) { $astData = @($astData) }
    foreach ($a in $astData) { $astResults[$a.Label] = $a }
} else {
    Write-Warning "No AST results at $astPath — will skip enrichment"
}

$psesResults = @{}
if (Test-Path $psesPath) {
    $psesData = Get-Content $psesPath -Raw | ConvertFrom-Json
    if ($psesData -isnot [array]) { $psesData = @($psesData) }
    foreach ($p in $psesData) { $psesResults[$p.Label] = $p }
} else {
    Write-Warning "No PSES results at $psesPath — will skip LSP enrichment"
}

# ---------- Enrich each result row ----------
$enriched = @()
foreach ($r in $allResults) {
    $label = "$($r.Config)-Run$($r.Run)-$($r.Prompt)"

    $ast  = $astResults[$label]
    $pses = $psesResults[$label]

    $enrichedRow = [PSCustomObject]@{
        Config           = $r.Config
        Label            = $r.Label
        Run              = $r.Run
        Prompt           = $r.Prompt
        Type             = $r.Type
        PromptTokens     = $r.PromptTokens
        CompletionTokens = $r.CompletionTokens
        WallTimeMs       = $r.WallTimeMs
        TTFT_Ms          = $r.TTFT_Ms
        TokPerSec        = $r.TokPerSec
        DecodeTokPerSec  = $r.DecodeTokPerSec
    }

    # Static quality fields (from original benchmark)
    if ($r.PSObject.Properties["QASyntaxOk"])    { $enrichedRow | Add-Member -NotePropertyName "QASyntaxOk"    -NotePropertyValue $r.QASyntaxOk }
    if ($r.PSObject.Properties["QAPSAErrors"])   { $enrichedRow | Add-Member -NotePropertyName "QAPSAErrors"   -NotePropertyValue $r.QAPSAErrors }
    if ($r.PSObject.Properties["QAPSAWarnings"]) { $enrichedRow | Add-Member -NotePropertyName "QAPSAWarnings" -NotePropertyValue $r.QAPSAWarnings }
    if ($r.PSObject.Properties["QAIdiomScore"])  { $enrichedRow | Add-Member -NotePropertyName "QAIdiomScore"  -NotePropertyValue $r.QAIdiomScore }
    if ($r.PSObject.Properties["QAGrade"])       { $enrichedRow | Add-Member -NotePropertyName "QAGrade"       -NotePropertyValue $r.QAGrade }

    # AST structural validation
    if ($ast) {
        $enrichedRow | Add-Member -NotePropertyName "ASTParseOk"     -NotePropertyValue $ast.ParseOk
        $enrichedRow | Add-Member -NotePropertyName "ASTChecksPassed" -NotePropertyValue $ast.ChecksPassed
        $enrichedRow | Add-Member -NotePropertyName "ASTChecksTotal"  -NotePropertyValue $ast.ChecksTotal
        $pct = if ($ast.ChecksTotal -gt 0) { [math]::Round(($ast.ChecksPassed / $ast.ChecksTotal) * 100) } else { 0 }
        $enrichedRow | Add-Member -NotePropertyName "ASTScore"       -NotePropertyValue $pct
    }

    # PSES LSP diagnostics
    if ($pses) {
        $enrichedRow | Add-Member -NotePropertyName "PSESErrors"     -NotePropertyValue $pses.Errors
        $enrichedRow | Add-Member -NotePropertyName "PSESWarnings"   -NotePropertyValue $pses.Warnings
        $enrichedRow | Add-Member -NotePropertyName "PSESTotal"      -NotePropertyValue $pses.Total
    }

    $enriched += $enrichedRow
}

# ---------- Export enriched CSV ----------
$csvPath = Join-Path $ResultsDir "results_enriched.csv"
$enriched | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "  Enriched CSV: $csvPath" -ForegroundColor Yellow

# ---------- Console summary ----------
Write-Host ""
Write-Host "  === Enriched Results Summary ===" -ForegroundColor Cyan

$codingResults = @($allResults | Where-Object { $_.Type -eq "Coding" })
$configs = $enriched | Select-Object -ExpandProperty Config -Unique

Write-Host ("  {0,-25} {1,8} {2,8} {3,10} {4,8} {5,8}" -f `
    "Config", "Idiom%", "PSA Err", "AST Struct", "PSES Err", "A-Grade")
Write-Host ("  " + ("-" * 75))

foreach ($cfg in $configs) {
    $cfgRows = @($enriched | Where-Object { $_.Config -eq $cfg -and $_.Type -eq "Coding" })
    if ($cfgRows.Count -eq 0) { continue }

    $avgIdiom = if ($cfgRows[0].PSObject.Properties["QAIdiomScore"]) {
        [math]::Round(($cfgRows | Where-Object { $_.QAIdiomScore -ge 0 } | Measure-Object -Property QAIdiomScore -Average).Average, 1)
    } else { "-" }
    $avgPsa = if ($cfgRows[0].PSObject.Properties["QAPSAErrors"]) {
        [math]::Round(($cfgRows | Measure-Object -Property QAPSAErrors -Average).Average, 1)
    } else { "-" }
    $avgAst = if ($cfgRows[0].PSObject.Properties["ASTScore"]) {
        [math]::Round(($cfgRows | Where-Object { $_.ASTScore -ge 0 } | Measure-Object -Property ASTScore -Average).Average, 1)
    } else { "-" }
    $avgPses = if ($cfgRows[0].PSObject.Properties["PSESErrors"]) {
        [math]::Round(($cfgRows | Measure-Object -Property PSESErrors -Average).Average, 1)
    } else { "-" }
    $aGrade = if ($cfgRows[0].PSObject.Properties["QAGrade"]) {
        ($cfgRows | Where-Object { $_.QAGrade -eq "A" }).Count
    } else { "-" }

    Write-Host ("  {0,-25} {1,6}% {2,6} {3,8}% {4,6} {5,6}" -f `
        $cfg, $avgIdiom, $avgPsa, $avgAst, $avgPses, $aGrade)
}

# ---------- Summary per-prompt PSES diagnostics ----------
if ($psesResults.Count -gt 0) {
    Write-Host ""
    Write-Host "  === PSES Diagnostics per Prompt ===" -ForegroundColor Cyan
    $promptNames = $enriched | Where-Object { $_.Type -eq "Coding" } | Select-Object -ExpandProperty Prompt -Unique
    foreach ($pn in $promptNames) {
        $pRows = @($enriched | Where-Object { $_.Prompt -eq $pn })
        $totalPses = ($pRows | Where-Object { $_.PSObject.Properties["PSESTotal"] } | Measure-Object -Property PSESTotal -Sum).Sum
        $totalErr  = ($pRows | Where-Object { $_.PSObject.Properties["PSESErrors"] } | Measure-Object -Property PSESErrors -Sum).Sum
        Write-Host ("    {0,-30} PSES total={1,4}  errors={2,4}" -f $pn, $totalPses, $totalErr)
    }
}

Write-Host ""
Write-Host "  Merge complete. Files:" -ForegroundColor Green
Write-Host "    $csvPath" -ForegroundColor Yellow
if (Test-Path $astPath)   { Write-Host "    $astPath (AST validation)" -ForegroundColor DarkGray }
if (Test-Path $psesPath)  { Write-Host "    $psesPath (PSES diagnostics)" -ForegroundColor DarkGray }
Write-Host ""
