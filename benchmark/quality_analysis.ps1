# quality_analysis.ps1
# Static code quality evaluation for LLM-generated PowerShell and .NET code.
# Zero remote dependencies — uses built-in PowerShell parser + PSScriptAnalyzer.
#
# Called by: run_benchmark.ps1 (quality.enabled = true)
# Standalone: Import-Module .\benchmark\quality_analysis.ps1 -Force

$ErrorActionPreference = "Stop"

# ---------- PSScriptAnalyzer availability ----------
$PSAModule = Get-Module -Name PSScriptAnalyzer -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if ($PSAModule) {
    Import-Module PSScriptAnalyzer -Force -ErrorAction SilentlyContinue
    $PSAAvailable = $true
} else {
    Write-Warning "PSScriptAnalyzer not installed. Install with: Install-Module PSScriptAnalyzer -Force"
    Write-Warning "Syntax checking still works; PSA rules will be skipped."
    $PSAAvailable = $false
}

# ---------- Quality config defaults ----------
$QualityDefaults = @{
    enabled         = $true
    timeoutSeconds  = 30
    psScriptAnalyzer = @{
        severity = @("Error", "Warning")
    }
    idiomChecks     = $true
}

# ---------- 1. Syntax Check ----------
function Test-PSSyntax {
    param([string]$Code)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $Code, [ref]$tokens, [ref]$errors
    )

    return [PSCustomObject]@{
        Ok       = ($errors.Count -eq 0)
        Errors   = @($errors | ForEach-Object { $_.Message })
        Count    = $errors.Count
    }
}

# ---------- 2. PSScriptAnalyzer ----------
function Invoke-PSAnalysis {
    param(
        [string]$Code,
        [string[]]$Severity = @("Error", "Warning")
    )

    if (-not $PSAAvailable) {
        return [PSCustomObject]@{
            Available = $false
            Errors    = 0
            Warnings  = 0
            Info      = 0
            Rules     = @()
        }
    }

    try {
        $results = Invoke-ScriptAnalyzer -ScriptDefinition $Code -Severity $Severity `
            -ErrorAction SilentlyContinue

        # Guard against null/empty results
        if (-not $results) { $results = @() }
        $grouped = if ($results.Count -gt 0) {
            $results | Group-Object Severity -AsHashTable -AsString
        } else { @{} }

        [PSCustomObject]@{
            Available = $true
            Errors    = if ($grouped.ContainsKey("Error")) { @($grouped["Error"]).Count } else { 0 }
            Warnings  = if ($grouped.ContainsKey("Warning")) { @($grouped["Warning"]).Count } else { 0 }
            Info      = if ($grouped.ContainsKey("Information")) { @($grouped["Information"]).Count } else { 0 }
            Rules     = @($results | Select-Object RuleName, Severity, Line, Message)
            Total     = @($results).Count
        }
    } catch {
        Write-Warning "PSA analysis failed: $_"
        return [PSCustomObject]@{ Available = $true; Errors = 0; Warnings = 0; Info = 0; Rules = @(); Total = 0 }
    }
}

# ---------- 3. Idiom Scoring ----------
function Measure-PSIdioms {
    param([string]$Code)

    $score = 0
    $max   = 0
    $checks = @()

    # --- Good patterns ---
    # Uses approved verb-noun naming
    $max++; if ($Code -match '\b(Get|Set|New|Remove|Start|Stop|Test|Invoke|Write|Read|Convert|Export|Import|Update|Add|Clear|Select|Format|Out|Enable|Disable|Find|Join|Split|Measure|Group|Sort|Compare|Wait|Debug|Trace|Limit|Resolve|Optimize)-[A-Z]\w+') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "approved-verb"; Description = "Uses approved PowerShell verb-noun naming"; Hit = ($Code -match '\b(Get|Set|New|Remove)-[A-Z]\w+') }

    # Has [CmdletBinding()] for functions
    $max++; if ($Code -match '\[CmdletBinding\(\)\]') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "cmdletbinding"; Description = "Uses [CmdletBinding()] on functions"; Hit = ($Code -match '\[CmdletBinding\(\)\]') }

    # Has param() block
    $max++; if ($Code -match '\bparam\s*\(') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "param-block"; Description = "Defines parameters with param() block"; Hit = ($Code -match '\bparam\s*\(') }

    # Uses try/catch for error handling
    $max++; if ($Code -match '\btry\s*\{') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "try-catch"; Description = "Uses try/catch error handling"; Hit = ($Code -match '\btry\s*\{') }

    # Pipeline usage (non-trivial)
    $max++; if ($Code -match '\|\s*\w') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "pipeline"; Description = "Uses PowerShell pipeline"; Hit = ($Code -match '\|\s*\w') }

    # Type annotations on parameters
    $max++; if ($Code -match '\[string\]\s*\$\w+|\[int\]\s*\$\w+|\[bool\]\s*\$\w+|\[array\]\s*\$\w+|\[hashtable\]\s*\$\w+|\[pscredential\]\s*\$\w+|\[switch\]\s*\$\w+') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "typed-params"; Description = "Uses type annotations on parameters"; Hit = ($Code -match '\[string\]\s*\$\w+|\[int\]\s*\$\w+') }

    # --- Anti-patterns (penalties) ---
    # += on arrays
    $max++; if ($Code -notmatch '\$\w+\s*\+=.*@\(\)|\$\w+\s*\+=') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "no-array-append"; Description = "Avoids += on arrays"; Hit = ($Code -notmatch '\$\w+\s*\+=.*@\(\)|\$\w+\s*\+=') }

    # Invoke-Expression
    $max++; if ($Code -notmatch 'Invoke-Expression|iex\b') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "no-invoke-expression"; Description = "Avoids Invoke-Expression"; Hit = ($Code -notmatch 'Invoke-Expression|iex\b') }

    # Write-Host for output (use Write-Output instead)
    $max++; if ($Code -notmatch 'Write-Host\b') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "no-write-host"; Description = "Avoids Write-Host for data output"; Hit = ($Code -notmatch 'Write-Host\b') }

    # begin/process/end blocks for pipeline functions
    $max++; if ($Code -match '\b(begin|process|end)\s*\{') { $score++ }
    $checks += [PSCustomObject]@{ Pattern = "pipeline-blocks"; Description = "Uses begin/process/end for pipeline support"; Hit = ($Code -match '\b(begin|process|end)\s*\{') }

    $pct = if ($max -gt 0) { [math]::Round(($score / $max) * 100, 1) } else { 0 }

    return [PSCustomObject]@{
        Score       = $score
        Max         = $max
        Percentage  = $pct
        Checks      = $checks
    }
}

# ---------- Helper: strip markdown code fences (handles reasoning model traces) ----------
function Extract-Code {
    param([string]$Text)

    # Strategy 1: Find the best function definition in raw text
    $fnMatches = [regex]::Matches($Text, '(?s)(function\s+\w+-\w+\s*\{)')
    if ($fnMatches.Count -gt 0) {
        $bestFn = $null; $bestScore = -1
        foreach ($m in $fnMatches) {
            $fnHeader = $m.Groups[1].Value
            $fnPos = $m.Index
            $remainder = $Text.Substring($fnPos + $fnHeader.Length)
            $braceCount = 1; $endPos = 0
            for ($i = 0; $i -lt $remainder.Length -and $braceCount -gt 0; $i++) {
                if ($remainder[$i] -eq '{') { $braceCount++ }
                if ($remainder[$i] -eq '}') { $braceCount-- }
                if ($braceCount -eq 0) { $endPos = $i; break }
            }
            if ($endPos -eq 0) { continue }
            $fnBody = $fnHeader + $remainder.Substring(0, $endPos + 1)
            $score = 0
            if ($fnBody -match '\[CmdletBinding') { $score += 10 }
            $score += $fnPos * 0.0001
            if ($score -gt $bestScore) { $bestScore = $score; $bestFn = $fnBody }
        }
        if ($bestFn) { return $bestFn.Trim() }
        $lastM = $fnMatches[$fnMatches.Count - 1]
        $lastHeader = $lastM.Groups[1].Value
        $lastRemainder = $Text.Substring($lastM.Index + $lastHeader.Length)
        return ($lastHeader + $lastRemainder).Trim()
    }
    # Strategy 2: Find the BEST fenced block (fallback for fence-heavy output)
    $fences = @()
    $pattern = '(?s)```(powershell|ps1|ps)?\s*\n(.+)```'
    $matches = [regex]::Matches($Text, $pattern)
    $firstFnFence = $true
    foreach ($m in $matches) {
        $lang  = $m.Groups[1].Value
        $body  = $m.Groups[2].Value.Trim()
        $score = 0
        if ($lang -in @('powershell','ps1','ps')) { $score += 10 }
        elseif ($lang -eq '') { $score += 5 }
        if ($body -match '\bfunction\s+\w+-\w+') {
            $score += 20
            if ($firstFnFence) { $score += 5; $firstFnFence = $false }
        }
        if ($body.Length -gt 50) { $score += 5 }
        $fences += [PSCustomObject]@{ Body=$body; Score=$score; Start=$m.Index }
    }

    if ($fences.Count -gt 0) {
        $best = ($fences | Sort-Object Score, Start -Descending | Select-Object -First 1)
        return $best.Body
    }

    # Strategy 3: Last-resort — find the last function definition
    $lines = $Text.Trim() -split '\r?\n'
    $start = 0
    # Find the LAST function header (after reasoning traces, before trailing prose)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i].Trim()
        if ($l -match '^function\s+\w+-\w+') {
            $start = $i; break
        }
    }
    # If no function found, fall back to first code-like line
    if ($start -eq 0) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i].Trim()
            if ($l -match '^(function\s|param\s*\(|\[CmdletBinding|\[Parameter|\[Validate|\$\w+\s*=|try\s*\{|if\s*\(|switch\s*\(|foreach\s*\(|for\s*\(|while\s*\(|using\s+|#requires)') {
                $start = $i; break
            }
        }
    }
    # Trim trailing prose
    $end = $lines.Count - 1
    for ($i = $lines.Count - 1; $i -ge $start; $i--) {
        $l = $lines[$i].Trim()
        if ($l.Length -gt 3 -and $l -notmatch '^This\s|^The\s|^You\s|^Note\s|^Make\s|^Use\s|^See\s|^For\s|^If you|^Adjust|^Replace|^Here|^That|^Now|^In this') {
            $end = $i; break
        }
    }
    ($lines[$start..$end] -join "`n").Trim()
}

# ---------- 4. Combined Quality Analysis ----------
function Invoke-QualityAnalysis {
    param(
        [string]$Code,
        [string]$PromptName,
        [hashtable]$Config = $QualityDefaults
    )

    $Code    = Extract-Code $Code
    $syntax  = Test-PSSyntax -Code $Code
    $psa     = Invoke-PSAnalysis -Code $Code -Severity $Config.psScriptAnalyzer.severity
    $idioms  = if ($Config.idiomChecks) { Measure-PSIdioms -Code $Code } else { $null }
    $isEmpty = ($Code.Trim().Length -lt 10) -or ($Code -match '^(Error|Sorry|I cannot|Unable to)')
    # Compute grade
    $grade = if ($isEmpty) { "F" }
        elseif (-not $syntax.Ok) { "F" }
        elseif ($psa.Available -and $psa.Errors -gt 3) { "D" }
        elseif ($psa.Available -and $psa.Errors -gt 0) { "C" }
        elseif ($psa.Available -and $psa.Warnings -gt 5) { "B" }
        elseif ($psa.Available -and $psa.Warnings -gt 2) { "B+" }
        elseif ($idioms -and $idioms.Percentage -ge 80) { "A" }
        elseif ($idioms -and $idioms.Percentage -ge 60) { "B+" }
        elseif ($idioms -and $idioms.Percentage -ge 40) { "B" }
        else { "C" }

    $idiomScore = ($idioms) ? $idioms.Score : 0
    $totalChecks = $idiomScore + ($syntax.Ok ? 1 : 0)

    return [PSCustomObject]@{
        Prompt          = $PromptName
        IsEmpty         = $isEmpty
        SyntaxOk        = $syntax.Ok
        SyntaxErrors    = $syntax.Count
        SyntaxMessages  = $syntax.Errors -join "; "
        PSAAvailable    = $psa.Available
        PSAErrors       = $psa.Errors
        PSAWarnings     = $psa.Warnings
        PSATotal        = $psa.Total
        IdiomScore      = if ($idioms) { $idioms.Percentage } else { -1 }
        IdiomHits       = if ($idioms) { $idioms.Score } else { 0 }
        IdiomMax        = if ($idioms) { $idioms.Max } else { 0 }
        TotalChecks     = $totalChecks
        Grade           = $grade
    }
}

