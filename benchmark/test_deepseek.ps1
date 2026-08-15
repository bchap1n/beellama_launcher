# Standalone test: DeepSeek analysis against existing benchmark results
param([string]$ResultsDir = "2026-06-19_20-02-46")

$ErrorActionPreference = "Stop"
$BenchDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Load analysis prompt
$anaPrompt = Get-Content (Join-Path $BenchDir "prompts-analysis.json") -Raw | ConvertFrom-Json

# Build data from existing CSV
$csv = Import-Csv (Join-Path $BenchDir $ResultsDir "results.csv")

# Per-config summary
$configs = $csv | Select-Object -ExpandProperty Config -Unique
$data = @()
foreach ($cfg in $configs) {
    $cRows = $csv | Where-Object { $_.Config -eq $cfg }
    $tokVals = @($cRows | ForEach-Object { if ($_.DecodeTokPerSec) { [double]$_.DecodeTokPerSec } else { 0 } })
    $sorted = $tokVals | Sort-Object
    $mid = [math]::Floor($sorted.Count / 2)
    $med = if ($sorted.Count -gt 0) { [math]::Round($sorted[$mid], 1) } else { 0 }

    # Quality columns
    $hasQuality = ($cRows | Where-Object { $_.PSObject.Properties["QASyntaxOk"] }).Count -gt 0
    $syn = if ($hasQuality) { ($cRows | Where-Object { $_.QASyntaxOk -eq "True" -or $_.QASyntaxOk -eq "true" -or $_.QASyntaxOk -eq $true }).Count } else { 0 }
    $idiomVals = if ($hasQuality) { @($cRows | ForEach-Object { [double]$_.QAIdiomScore }) } else { @(0) }
    $idiom = [math]::Round(($idiomVals | Measure-Object -Average).Average, 1)
    $aGrd = if ($hasQuality) { ($cRows | Where-Object { $_.QAGrade -eq "A" }).Count } else { 0 }
    
    $data += "  $cfg | $med tok/s | idiom $idiom% | syntax $syn/$($cRows.Count) | A-grades $aGrd/$($cRows.Count)"
}

$comparison = if ($configs.Count -gt 1) { "6) Which model wins for coding quality and why." } else { "" }
$body = $anaPrompt.template -f ($data -join "`n"), $comparison

Write-Host "=== Prompt to DeepSeek ===" -ForegroundColor Cyan
Write-Host "System: $($anaPrompt.system.Substring(0,80))..." -ForegroundColor DarkGray
Write-Host ""
Write-Host $body
Write-Host ""

# Call DeepSeek
$env:DEEPSEEK_API_KEY = [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY", "User")
if (-not $env:DEEPSEEK_API_KEY) {
    Write-Error "DEEPSEEK_API_KEY not set. Run: op read ... | Set-EnvironmentVariable"
    exit 1
}

Write-Host "=== DeepSeek Verdict ===" -ForegroundColor Green
$headers = @{ "Authorization" = "Bearer $env:DEEPSEEK_API_KEY"; "Content-Type" = "application/json" }
$payload = @{ 
    model = "deepseek-chat"
    messages = @(@{role="system";content=$anaPrompt.system}, @{role="user";content=$body})
    max_tokens = 500
    temperature = 0.3
} | ConvertTo-Json

$resp = Invoke-RestMethod -Uri "https://api.deepseek.com/v1/chat/completions" -Method Post -Headers $headers -Body $payload -TimeoutSec 30
$verdict = $resp.choices[0].message.content.Trim()
Write-Host $verdict
Write-Host ""
Write-Host "Tokens used: $($resp.usage.completion_tokens) (completion) / $($resp.usage.total_tokens) (total)"
