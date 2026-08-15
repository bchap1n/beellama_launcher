# Quick smoke test for quality_analysis.ps1
. .\benchmark\quality_analysis.ps1

$goodCode = @'
function Get-FileReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [switch] $Recurse
    )
    try {
        $files = Get-ChildItem -Path $Path -Recurse:$Recurse -File -ErrorAction Stop
        [PSCustomObject]@{
            FileCount  = $files.Count
            TotalBytes = ($files | Measure-Object -Property Length -Sum).Sum
            NewestFile = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        }
    } catch {
        Write-Error "Failed: $_"
    }
}
'@

$badCode = 'Invoke-Expression "$input"; Write-Host "done"'

Write-Host "=== Good Code ===" -ForegroundColor Green
$good = Invoke-QualityAnalysis -Code $goodCode -PromptName "good_test"
$good | Format-List

Write-Host ""
Write-Host "=== Bad Code ===" -ForegroundColor Red
$bad = Invoke-QualityAnalysis -Code $badCode -PromptName "bad_test"
$bad | Format-List

Write-Host ""
Write-Host "=== Idiom Checks ===" -ForegroundColor Cyan
$idioms = Measure-PSIdioms -Code $goodCode
$idioms.Checks | Format-Table Pattern, Description, Hit
Write-Host "Score: $($idioms.Percentage)% ($($idioms.Score)/$($idioms.Max))"
