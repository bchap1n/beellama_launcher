. .\benchmark\quality_analysis.ps1

# Test 1: explantory text + bare code
$t1 = @'
Here's a PowerShell function that does what you asked:

function Get-FileReport {
    [CmdletBinding()]
    param([string] $Path, [switch] $Recurse)
    try {
        $files = Get-ChildItem -Path $Path -Recurse:$Recurse -File -ErrorAction Stop
        [PSCustomObject]@{ FileCount = $files.Count }
    } catch { Write-Error "fail" }
}

This function handles edge cases properly.
'@

$r1 = Invoke-QualityAnalysis -Code $t1 -PromptName "t1"
Write-Host "Test 1 (prose+code+prose): Grade=$($r1.Grade) Syntax=$($r1.SyntaxOk) Idiom=$($r1.IdiomScore)%"

# Test 2: fence wrapped
$t2 = @'
```powershell
function Get-FileReport {
    [CmdletBinding()]
    param([string] $Path, [switch] $Recurse)
    try {
        $files = Get-ChildItem -Path $Path -Recurse:$Recurse -File -ErrorAction Stop
        [PSCustomObject]@{ FileCount = $files.Count }
    } catch { Write-Error "fail" }
}
```
'@

$r2 = Invoke-QualityAnalysis -Code $t2 -PromptName "t2"
Write-Host "Test 2 (fence): Grade=$($r2.Grade) Syntax=$($r2.SyntaxOk) Idiom=$($r2.IdiomScore)%"

# Test 3: bare fence
$t3 = @'
```
function Get-FileReport {
    [CmdletBinding()]
    param([string] $Path, [switch] $Recurse)
    try {
        $files = Get-ChildItem -Path $Path -Recurse:$Recurse -File
        [PSCustomObject]@{ FileCount = $files.Count }
    } catch { Write-Error "fail" }
}
```
'@

$r3 = Invoke-QualityAnalysis -Code $t3 -PromptName "t3"
Write-Host "Test 3 (bare fence): Grade=$($r3.Grade) Syntax=$($r3.SyntaxOk) Idiom=$($r3.IdiomScore)%"
