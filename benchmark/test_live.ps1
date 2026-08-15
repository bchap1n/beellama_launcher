. .\benchmark\quality_analysis.ps1
$code = Get-Content "$env:TEMP\bench_quality_test.ps1" -Raw
$r = Invoke-QualityAnalysis -Code $code -PromptName "live_test"
$r | Format-List
Write-Host "--- Idiom Details ---"
$idioms = Measure-PSIdioms -Code $code
$idioms.Checks | Format-Table Pattern, Hit -AutoSize
Write-Host "Score: $($idioms.Percentage)% ($($idioms.Score)/$($idioms.Max))"
