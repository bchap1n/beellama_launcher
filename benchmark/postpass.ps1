# postpass.ps1
# Agent-side benchmark enrichment — Phase 1: AST structural validation.
# Validates every 'expected' field from prompts-coding.json via AST inspection.
# No code execution. Safe for untrusted LLM output.
#
# Phase 1 (this script):  code extraction + AST validation
# Phase 2 (agent):        lsp diagnostics on temp files via PSES
# Phase 3 (agent):        merge execution.json → results_enriched.csv + HTML

param(
    [Parameter(Mandatory)]
    [string]$ResultsDir
)

$ErrorActionPreference = "Stop"
$BenchDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ---------- Load data ----------
$resultsPath = Join-Path $ResultsDir "results_full.json"
if (-not (Test-Path $resultsPath)) {
    Write-Error "results_full.json not found at $resultsPath. Re-run benchmark first."
    exit 1
}
$allResults = Get-Content $resultsPath -Raw | ConvertFrom-Json
if ($allResults -isnot [array]) { $allResults = @($allResults) }

$promptsPath = Join-Path $BenchDir "prompts-coding.json"
$prompts = Get-Content $promptsPath -Raw | ConvertFrom-Json
$promptMap = @{}
foreach ($p in $prompts) { $promptMap[$p.name] = $p }

$codingResults = @($allResults | Where-Object { $_.Type -eq "Coding" })
if ($codingResults.Count -eq 0) {
    Write-Warning "No Coding results found in $resultsPath."
    exit 0
}

# ---------- Setup output ----------
$postDir = Join-Path $ResultsDir "postpass"
$codeDir  = Join-Path $postDir "code"
$null = New-Item -ItemType Directory -Path $codeDir -Force

# ---------- Code extraction ----------
function Extract-Code {
    param([string]$Text)

    # Strategy 1: Find the best function definition in raw text
    # Scoring: +10 for CmdletBinding (main function), prefer later position
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
            if ($endPos -eq 0) { continue }  # no closing brace, skip
            $fnBody = $fnHeader + $remainder.Substring(0, $endPos + 1)
            $score = 0
            if ($fnBody -match '\[CmdletBinding') { $score += 10 }
            $score += $fnPos * 0.0001  # micro-bonus for later position (main func usually after helpers)
            if ($score -gt $bestScore) { $bestScore = $score; $bestFn = $fnBody }
        }
        if ($bestFn) { return $bestFn.Trim() }
        # If all lacked closing braces, return last function header to end
        $lastM = $fnMatches[$fnMatches.Count - 1]
        $lastHeader = $lastM.Groups[1].Value
        $lastRemainder = $Text.Substring($lastM.Index + $lastHeader.Length)
        return ($lastHeader + $lastRemainder).Trim()
    }

    # Strategy 2: Find the BEST fenced block (fallback for fence-heavy output)
    $fences = @()
    $pattern = '(?s)```(powershell|ps1|ps)?\s*\n(.+?)```'
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
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $l = $lines[$i].Trim()
        if ($l -match '^function\s+\w+-\w+') {
            $start = $i; break
        }
    }
    if ($start -eq 0) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $l = $lines[$i].Trim()
            if ($l -match '^(function\s|param\s*\(|\[CmdletBinding|\[Parameter|\[Validate|\$\w+\s*=|try\s*\{|if\s*\(|switch\s*\(|foreach\s*\(|for\s*\(|while\s*\(|using\s+|#requires)') {
                $start = $i; break
            }
        }
    }
    $end = $lines.Count - 1
    for ($i = $lines.Count - 1; $i -ge $start; $i--) {
        $l = $lines[$i].Trim()
        if ($l.Length -gt 3 -and $l -notmatch '^This\s|^The\s|^You\s|^Note\s|^Make\s|^Use\s|^See\s|^For\s|^If you|^Adjust|^Replace|^Here|^That|^Now|^In this') {
            $end = $i; break
        }
    }
    ($lines[$start..$end] -join "`n").Trim()
}

# ---------- AST helpers ----------
function Get-FunctionAst {
    param($Ast, [string]$Name)
    $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { -not $Name -or $_.Name -eq $Name }
}

function Test-CmdletBinding {
    param($Func)
    if ($func.Parameters) {
        # Check CmdletBinding attribute on param block
        $attrs = $func.Body.ParamBlock.Attributes
        foreach ($a in $attrs) {
            if ($a.TypeName.Name -eq "CmdletBinding") { return $a }
        }
    }
    # Also check AST param block
    if ($func.Body.ParamBlock) {
        $attrs = $func.Body.ParamBlock.Attributes
        foreach ($a in $attrs) {
            if ($a.TypeName.Name -eq "CmdletBinding") { return $a }
        }
    }
    return $null
}

function Test-TryCatch {
    param($Ast)
    $found = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TryStatementAst] }, $true)
    return ($found.Count -gt 0)
}

function Test-TypedParams {
    param($Func)
    if (-not $func.Body.ParamBlock) { return $false }
    foreach ($p in $func.Body.ParamBlock.Parameters) {
        if ($p.StaticType -and $p.StaticType.Name -ne "Object") { return $true }
        if ($p.Attributes.Count -gt 0) { return $true }  # [string], [int] etc come through as type constraints
    }
    return $false
}

function Test-BeginProcessEnd {
    param($Func)
    if ($func.Body.BeginBlock) { return $true }
    if ($func.Body.ProcessBlock) { return $true }
    if ($func.Body.EndBlock) { return $true }
    return $false
}

function Test-PipelineInput {
    param($Func)
    if (-not $func.Body.ParamBlock) { return $false }
    foreach ($p in $func.Body.ParamBlock.Parameters) {
        foreach ($attr in $p.Attributes) {
            if ($attr.TypeName.Name -match 'Parameter') {
                foreach ($na in $attr.NamedArguments) {
                    if ($na.ArgumentName -match 'ValueFromPipeline') { return $true }
                }
            }
        }
    }
    return $false
}

function Test-ShouldProcess {
    param($Func)
    $attr = Test-CmdletBinding $func
    if ($attr) {
        foreach ($na in $attr.NamedArguments) {
            if ($na.ArgumentName -eq "SupportsShouldProcess") { return $true }
        }
    }
    return $false
}

function Test-CommandUsage {
    param($Ast, [string]$Pattern)
    $cmds = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        $cmdName = $c.GetCommandName()
        if ($cmdName -and $cmdName -match $Pattern) { return $true }
    }
    return $false
}

function Test-ForEachParallel {
    param($Ast)
    $cmds = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        if ($c.Extent.Text -match 'ForEach-Object\s+-Parallel') { return $true }
    }
    return $false
}

function Test-CommentHelp {
    param($Ast)
    $helps = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommentHelpInfo] }, $true)
    if ($helps.Count -gt 0) { return $true }
    # Fallback: check raw text
    return ($ast.Extent.Text -match '<#.*\.SYNOPSIS')
}

# ---------- AST validation runner ----------
$astResults = @()

foreach ($r in $codingResults) {
    $promptName = $r.Prompt
    $config     = $r.Config
    $run        = $r.Run
    $label      = "$config-Run$run-$promptName"

    # Extract code
    $code = Extract-Code -Text $r.Content
    if ([string]::IsNullOrWhiteSpace($code) -or $code.Length -lt 10) {
        Write-Host "  SKIP $label : empty/short code" -ForegroundColor DarkGray
        $astResults += [PSCustomObject]@{
            Label      = $label
            Config     = $config
            Run        = $run
            Prompt     = $promptName
            CodeFile   = $null
            ParseOk    = $false
            ChecksPassed = 0
            ChecksTotal  = 0
            CheckDetails = @()
            Error      = "Empty or too-short code"
        }
        continue
    }

    # Write code to temp file (for LSP Phase 2)
    $safeName = "$config-Run$run-$promptName" -replace '[^\w\-]', '_'
    $codeFile = Join-Path $codeDir "$safeName.ps1"
    $code | Out-File -FilePath $codeFile -Encoding utf8

    # Parse AST
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors)
    $parseOk = ($errors.Count -eq 0)

    # Get expected checks from prompt definition
    $promptDef = $promptMap[$promptName]
    $expected = if ($promptDef.expected) { $promptDef.expected } else { @{} }
    $checkDetails = @()
    $checksPassed = 0
    $checksTotal  = 0

    foreach ($prop in $expected.PSObject.Properties) {
        $key = $prop.Name
        $want = $prop.Value
        $checksTotal++

        $got = $false
        $detail = ""

        switch ($key) {
            "hasCmdletBinding" {
                $funcs = Get-FunctionAst $ast
                $got = ($funcs | Where-Object { Test-CmdletBinding $_ }).Count -gt 0
                $detail = if ($got) { "found [CmdletBinding()]" } else { "no [CmdletBinding()] found" }
            }
            "hasTypedParams" {
                $funcs = Get-FunctionAst $ast
                $got = ($funcs | Where-Object { Test-TypedParams $_ }).Count -gt 0
                $detail = if ($got) { "typed parameters found" } else { "no typed parameters" }
            }
            "hasTryCatch" {
                $got = Test-TryCatch $ast
                $detail = if ($got) { "try/catch block found" } else { "no try/catch" }
            }
            "functionName" {
                $funcs = Get-FunctionAst $ast $want
                $got = ($funcs.Count -gt 0)
                $detail = if ($got) { "function $want defined" } else { "function $want NOT found" }
            }
            "hasBeginProcessEnd" {
                $funcs = Get-FunctionAst $ast
                $got = ($funcs | Where-Object { Test-BeginProcessEnd $_ }).Count -gt 0
                $detail = if ($got) { "begin/process/end blocks found" } else { "no begin/process/end blocks" }
            }
            "hasPipelineInput" {
                $funcs = Get-FunctionAst $ast
                $got = ($funcs | Where-Object { Test-PipelineInput $_ }).Count -gt 0
                $detail = if ($got) { "ValueFromPipeline found" } else { "no pipeline input binding" }
            }
            "usesInvokeRestMethod" {
                $got = Test-CommandUsage $ast "Invoke-RestMethod"
                $detail = if ($got) { "Invoke-RestMethod used" } else { "no Invoke-RestMethod call" }
            }
            "hasShouldProcess" {
                $funcs = Get-FunctionAst $ast
                $got = ($funcs | Where-Object { Test-ShouldProcess $_ }).Count -gt 0
                $detail = if ($got) { "SupportsShouldProcess enabled" } else { "no SupportsShouldProcess" }
            }
            "hasExportModuleMember" {
                $got = Test-CommandUsage $ast "Export-ModuleMember"
                $detail = if ($got) { "Export-ModuleMember found" } else { "no Export-ModuleMember" }
            }
            "hasTwoFunctions" {
                $funcs = Get-FunctionAst $ast
                $got = ($funcs.Count -ge 2)
                $detail = "found $($funcs.Count) function(s)"
            }
            "hasCommentHelp" {
                $got = Test-CommentHelp $ast
                $detail = if ($got) { "comment-based help found" } else { "no comment-based help" }
            }
            "usesPipelineCmdlets" {
                $got = (Test-CommandUsage $ast "Import-Csv") -or
                       (Test-CommandUsage $ast "Group-Object") -or
                       (Test-CommandUsage $ast "ForEach-Object")
                $detail = if ($got) { "pipeline cmdlets used" } else { "no pipeline cmdlets" }
            }
            "handlesWeekends" {
                $got = ($code -match 'Saturday|Sunday|DayOfWeek')
                $detail = if ($got) { "weekend handling found" } else { "no weekend-skipping logic" }
            }
            "handlesMissing" {
                $got = ($code -match '\$null|return\s+\$null')
                $detail = if ($got) { "null-return pattern found" } else { "no null-return pattern" }
            }
            "handlesMissingFile" {
                $got = ($code -match 'Test-Path|New-Item')
                $detail = if ($got) { "file-existence check found" } else { "no file-existence handling" }
            }
            "usesForEachParallel" {
                $got = Test-ForEachParallel $ast
                $detail = if ($got) { "ForEach-Object -Parallel found" } else { "no ForEach-Object -Parallel" }
            }
            default {
                $detail = "unknown check: $key"
                $got = $false
            }
        }

        if ($got -eq $want) { $checksPassed++ }
        $checkDetails += [PSCustomObject]@{
            Check    = $key
            Expected = $want
            Actual   = $got
            Passed   = ($got -eq $want)
            Detail   = $detail
        }
    }

    $result = [PSCustomObject]@{
        Label        = $label
        Config       = $config
        Run          = $run
        Prompt       = $promptName
        CodeFile     = $codeFile
        ParseOk      = $parseOk
        ParseErrors  = $errors.Count
        ChecksPassed = $checksPassed
        ChecksTotal  = $checksTotal
        CheckDetails = @($checkDetails)
        Error        = if (-not $parseOk) { ($errors | ForEach-Object { $_.Message }) -join "; " } else { "" }
    }
    $astResults += $result

    $pct = if ($checksTotal -gt 0) { [math]::Round(($checksPassed / $checksTotal) * 100) } else { 0 }
    $color = if ($checksPassed -eq $checksTotal -and $parseOk) { "Green" }
             elseif ($pct -ge 50) { "Yellow" }
             else { "Red" }
    Write-Host ("  {0,-45} parse={1}  struct={2}/{3} ({4}%)" -f `
        $label, $(if($parseOk){"OK"}else{"FAIL"}), $checksPassed, $checksTotal, $pct) -ForegroundColor $color
}

# ---------- Save AST validation manifest ----------
$astPath = Join-Path $postDir "ast_validation.json"
$astResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $astPath -Encoding utf8 -Force
Write-Host ""
Write-Host "  AST results: $astPath" -ForegroundColor Green

# ---------- Produce LSP manifest for Phase 2 ----------
$lspFiles = @($astResults | Where-Object { $_.CodeFile } | ForEach-Object { $_.CodeFile })
$lspManifest = @{
    phase       = 2
    description = "LSP diagnostics pass via powershell-editor-services"
    files       = $lspFiles
    astResults  = $astPath
    resultsDir  = $ResultsDir
}
$lspPath = Join-Path $postDir "lsp_manifest.json"
$lspManifest | ConvertTo-Json -Depth 3 | Out-File -FilePath $lspPath -Encoding utf8 -Force
Write-Host "  LSP manifest: $lspPath ($($lspFiles.Count) files)" -ForegroundColor Green
Write-Host ""

# ---------- Summary ----------
$totalChecks  = ($astResults | Measure-Object -Property ChecksTotal -Sum).Sum
$totalPassed  = ($astResults | Measure-Object -Property ChecksPassed -Sum).Sum
$parseOkCount = ($astResults | Where-Object { $_.ParseOk }).Count
Write-Host "  === Post-Pass Phase 1 Summary ===" -ForegroundColor Cyan
Write-Host "  Files extracted:  $($lspFiles.Count)"
Write-Host "  Parse OK:         $parseOkCount / $($codingResults.Count)"
Write-Host "  Structural:       $totalPassed / $totalChecks checks passed"
Write-Host "  Next (Phase 2):   agent runs 'lsp diagnostics' on $($lspFiles.Count) files"
Write-Host "  Next (Phase 3):   agent merges into results_enriched.csv + HTML"
Write-Host ""
