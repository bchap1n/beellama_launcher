. .\benchmark\quality_analysis.ps1

$wrapped = @'
```powershell
function Get-FileReport {
    [CmdletBinding()]
    param(
        [string] $Path,
        [switch] $Recurse
    )
    try {
        $files = Get-ChildItem -Path $Path -Recurse:$Recurse -File -ErrorAction Stop
        [PSCustomObject]@{ FileCount = $files.Count }
    } catch { Write-Error "fail" }
}
```
'@

Write-Host "=== Raw (with fence) ==="
$r = Invoke-QualityAnalysis -Code $wrapped -PromptName "wrapped"
Write-Host "Grade: $($r.Grade)  Syntax: $($r.SyntaxOk)  Idiom: $($r.IdiomScore)%  PSA err: $($r.PSAErrors)"
Write-Host ""

Write-Host "=== Clean Code ==="
$clean = @'
function Get-FileReport {
    [CmdletBinding()]
    param(
        [string] $Path,
        [switch] $Recurse
    )
    try {
        $files = Get-ChildItem -Path $Path -Recurse:$Recurse -File -ErrorAction Stop
        [PSCustomObject]@{ FileCount = $files.Count }
    } catch { Write-Error "fail" }
}
'@
$r2 = Invoke-QualityAnalysis -Code $clean -PromptName "clean"
Write-Host "Grade: $($r2.Grade)  Syntax: $($r2.SyntaxOk)  Idiom: $($r2.IdiomScore)%  PSA err: $($r2.PSAErrors)"
