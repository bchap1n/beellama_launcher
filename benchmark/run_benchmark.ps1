# run_benchmark.ps1
# Automated benchmark orchestrator - launches servers, runs prompts, stops servers.
# Generates timestamped output folder with results.csv and results.html.
#
# Called by:  start-beellama.ps1 -Benchmark
# Standalone: .\benchmark\run_benchmark.ps1 -Scripts @("run\Qwen3.6-27B-Q4_K_M-dflash.ps1")

param(
    [Parameter(Mandatory)]
    [string[]]$Scripts,
    [int]$Runs,
    [int]$MaxTokens,
    [string]$ServerUrl,
    [int]$ServerTimeoutSec,
    [string]$ConfigFile,
    [int]$ConfigCooldownSec,
    [switch]$LongCtx,
    [switch]$Quality
)

$ErrorActionPreference = "Stop"
$BenchDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ---------- Load config (file defaults, then CLI overrides) ----------
$defaults = @{
    runs               = 3
    maxTokens          = 2048
    warmupRuns         = 3
    warmupTokens       = 256
    cooldownSec        = 0
    configCooldownSec  = 60
    retries            = 2
    serverUrl          = "http://localhost:8082"
    serverTimeoutSec   = 180
    promptsFile        = "prompts.json"
}

$cfgPath = if ($ConfigFile) { $ConfigFile } else { Join-Path $BenchDir "benchmark.config.json" }
if (Test-Path $cfgPath) {
    $fileCfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    foreach ($key in @($defaults.Keys)) {
        $val = $fileCfg.PSObject.Properties[$key]
        if ($val) { $defaults[$key] = $val.Value }
    }
}

# CLI overrides (only when explicitly provided)
if ($PSBoundParameters.ContainsKey('Runs'))             { $defaults['runs']             = $Runs }
if ($PSBoundParameters.ContainsKey('MaxTokens'))        { $defaults['maxTokens']        = $MaxTokens }
if ($PSBoundParameters.ContainsKey('ServerUrl'))         { $defaults['serverUrl']        = $ServerUrl }
if ($PSBoundParameters.ContainsKey('ServerTimeoutSec'))  { $defaults['serverTimeoutSec'] = $ServerTimeoutSec }
if ($PSBoundParameters.ContainsKey('ConfigCooldownSec'))  { $defaults['configCooldownSec'] = $ConfigCooldownSec }

$Runs              = $defaults['runs']
$MaxTokens         = $defaults['maxTokens']
# Safety: if resolution yields 0, default to 2048 (thinking models need room)
if ($MaxTokens -le 0) { $MaxTokens = 2048; Write-Warning "MaxTokens was 0, defaulting to 2048" }
$WarmupRuns        = $defaults['warmupRuns']
$WarmupTokens      = $defaults['warmupTokens']
$CooldownSec       = $defaults['cooldownSec']
$ConfigCooldownSec = $defaults['configCooldownSec']
$Retries           = $defaults['retries']
$ServerUrl         = $defaults['serverUrl']
$ServerTimeoutSec  = $defaults['serverTimeoutSec']

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutputDir = Join-Path $BenchDir $timestamp
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
# ---------- Load prompts ----------
$promptsFile = $defaults['promptsFile']
if ($LongCtx) {
    $promptsFile = "prompts-longctx.json"
}
# Quality mode: -Quality flag forces it, otherwise read config
if (-not $fileCfg.PSObject.Properties["quality"]) { $fileCfg | Add-Member -NotePropertyName "quality" -NotePropertyValue ([PSCustomObject]@{}) -Force }
if ($Quality) {
    $fileCfg.quality | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force
    if (-not $fileCfg.quality.PSObject.Properties["promptsFile"]) {
        $fileCfg.quality | Add-Member -NotePropertyName "promptsFile" -NotePropertyValue "prompts-coding.json" -Force
    }
}
if ($fileCfg.quality.PSObject.Properties["enabled"] -and $fileCfg.quality.enabled) {
    $promptsFile = if ($fileCfg.quality.PSObject.Properties["promptsFile"]) { $fileCfg.quality.promptsFile } else { "prompts-coding.json" }
}
$promptsPath = Join-Path $BenchDir $promptsFile
if (Test-Path $promptsPath) {
    $prompts = Get-Content $promptsPath -Raw | ConvertFrom-Json
} else {
    Write-Warning "Prompts file not found at $promptsPath - using built-in defaults."
    $prompts = @(
        @{ name = "code_binary_search"; type = "Code"; messages = @(
            @{ role = "system"; content = "You are a helpful coding assistant." }
            @{ role = "user"; content = "Write a Python function that implements binary search on a sorted list. Include type hints, docstring, and handle edge cases." }
        )}
        @{ name = "code_linked_list"; type = "Code"; messages = @(
            @{ role = "system"; content = "You are a helpful coding assistant." }
            @{ role = "user"; content = "Implement a singly linked list in Python with insert, delete, search, and reverse methods. Include type hints." }
        )}
        @{ name = "reason_math"; type = "Reasoning"; messages = @(
            @{ role = "system"; content = "You are a helpful assistant. Think step by step." }
            @{ role = "user"; content = "A train leaves station A at 9:00 AM traveling at 60 mph. Another train leaves station B (300 miles away) at 10:00 AM traveling toward station A at 90 mph. At what time do they meet? Show your work." }
        )}
        @{ name = "reason_logic"; type = "Reasoning"; messages = @(
            @{ role = "system"; content = "You are a helpful assistant. Think step by step." }
            @{ role = "user"; content = "There are 5 houses in a row, each painted a different color. Each house is occupied by a person of a different nationality. Each person drinks a different beverage, smokes a different brand of cigar, and keeps a different pet. The Brit lives in the red house. The Swede keeps dogs. The Dane drinks tea. The green house is immediately to the left of the white house. The green house owner drinks coffee. The person who smokes Pall Mall keeps birds. The owner of the yellow house smokes Dunhill. The man living in the center house drinks milk. The Norwegian lives in the first house. Who owns the fish?" }
        )}
    )
}

# Derive distinct prompt names for per-prompt comparison table
$promptNames = $prompts | ForEach-Object { $_.name } | Select-Object -Unique

# ---------- Helpers ----------


# Always load standard prompts for warmup (long-context warmup would take hours)
if ($LongCtx) {
    $warmupPath = Join-Path $BenchDir $defaults['promptsFile']
    if (Test-Path $warmupPath) {
        $warmupPrompts = Get-Content $warmupPath -Raw | ConvertFrom-Json
    } else {
        $warmupPrompts = $prompts
    }
} else {
    $warmupPrompts = $prompts
}
function waitForServer {
    param([string]$url, [int]$timeoutSec)
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-RestMethod -Uri "$url/health" -TimeoutSec 5 -ErrorAction Stop
            if ($r.status -eq "ok") { return $true }
        } catch { }
        Start-Sleep -Seconds 2
    }
    return $false
}

function stopServer {
    param([int]$Port = 8082)
    # Kill known server process names
    Get-Process "llama-server", "dflash_server" -ErrorAction SilentlyContinue | Stop-Process -Force
    # Also kill anything listening on the port (catches servers from other sessions)
    $pids = (& netstat -ano 2>$null | Select-String ":$Port.*LISTENING" | ForEach-Object {
        ($_ -replace '.*LISTENING\s+(\d+).*','$1').Trim()
    } | Where-Object { $_ -match '^\d+$' })
    foreach ($p in $pids) {
        Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

# Extract --port from a launch script
function getScriptPort {
    param([string]$scriptPath)
    $lines = Get-Content $scriptPath -TotalCount 60 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '--port\s+(\d+)') {
            return $Matches[1]
        }
    }
    return "8082"  # default fallback
}

function runPromptStreaming {
    param($prompt, [string]$url, [int]$maxTokens)

    $bodyObj = @{
        model          = "default"
        messages       = @($prompt.messages)
        max_tokens     = $maxTokens
        temperature    = 0.6
        top_k          = 20
        stream         = $true
        stream_options = @{ include_usage = $true }
    }
    $jsonBody = $bodyObj | ConvertTo-Json -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client  = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(300)

    $content = [System.Net.Http.ByteArrayContent]::new($bodyBytes)
    $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/json")

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Post,
            "$url/v1/chat/completions"
        )
        $request.Content = $content

        $response = $client.SendAsync(
            $request,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()

        $response.EnsureSuccessStatusCode() | Out-Null

        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream)

        $ttftMs           = -1
        $completionTokens = 0
        $promptTokens     = 0
        $totalContent     = ""

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not $line -or -not $line.StartsWith("data: ")) { continue }
            $data = $line.Substring(6).Trim()
            if ($data -eq "[DONE]") { break }

            try {
                $chunk = $data | ConvertFrom-Json
            } catch {
                # Regex fallback: thinking models produce content with characters
                # that break ConvertFrom-Json (unescaped quotes, backslashes, etc.)
                $tok = $null
                if ($data -match '"content"\s*:\s*"((?:[^"\\]|\\.)*)"') {
                    $tok = [regex]::Unescape($Matches[1])
                }
                if (-not $tok -and $data -match '"reasoning_content"\s*:\s*"((?:[^"\\]|\\.)*)"') {
                    $tok = [regex]::Unescape($Matches[1])
                }
                if ($tok) {
                    if ($ttftMs -lt 0) { $ttftMs = $sw.ElapsedMilliseconds }
                    $totalContent += $tok
                }
                continue
            }

            if ($chunk.choices -and $chunk.choices.Count -gt 0) {
                $delta = $chunk.choices[0].delta
                # Capture both regular content and reasoning content
                $tok = $delta.content
                if (-not $tok) { $tok = $delta.reasoning_content }
                if ($tok) {
                    if ($ttftMs -lt 0) { $ttftMs = $sw.ElapsedMilliseconds }
                    $totalContent += $tok
                }
            }

            if ($chunk.usage) {
                $promptTokens     = $chunk.usage.prompt_tokens
                $completionTokens = $chunk.usage.completion_tokens
            }
        }

        $reader.Close()
        $stream.Close()
    } catch {
        $sw.Stop()
        $client.Dispose()
        throw $_
    }
    $sw.Stop()
    $client.Dispose()

    # If usage wasn't in stream, estimate from content length
    if ($completionTokens -eq 0 -and $totalContent.Length -gt 0) {
        $completionTokens = [math]::Max(1, [math]::Round($totalContent.Length / 4.0))
    }

    $ms = $sw.ElapsedMilliseconds
    $decodeMs = if ($ttftMs -ge 0 -and $ms -gt $ttftMs) { $ms - $ttftMs } else { $ms }
    return [PSCustomObject]@{
        Prompt           = $prompt.name
        Type             = $prompt.type
        PromptTokens     = $promptTokens
        CompletionTokens = $completionTokens
        WallTimeMs       = $ms
        TTFT_Ms          = if ($ttftMs -ge 0) { $ttftMs } else { $ms }
        TokPerSec        = if ($ms -gt 0) { [math]::Round($completionTokens / ($ms / 1000.0), 2) } else { 0 }
        DecodeTokPerSec  = if ($decodeMs -gt 0) { [math]::Round($completionTokens / ($decodeMs / 1000.0), 2) } else { 0 }
        Content          = $totalContent
    }
}

function runPromptWithRetry {
    param($prompt, [string]$url, [int]$maxTokens, [int]$retries)
    for ($attempt = 0; $attempt -le $retries; $attempt++) {
        try {
            $result = runPromptStreaming -prompt $prompt -url $url -maxTokens $maxTokens
            if ($result) { return $result }
        } catch {
            $label = if ($attempt -lt $retries) { "retrying ($($attempt+1)/$retries)" } else { "giving up" }
            Write-Warning "    Request failed for $($prompt.name) (attempt $($attempt+1)): $_ - $label"
        }
        if ($attempt -lt $retries) { Start-Sleep -Seconds 2 }
    }
    return $null
}

function getMedian {
    param([double[]]$values)
    if ($values.Count -eq 0) { return 0 }
    $sorted = $values | Sort-Object
    $mid = [math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 0) {
        return [math]::Round(($sorted[$mid - 1] + $sorted[$mid]) / 2.0, 2)
    }
    return [math]::Round($sorted[$mid], 2)
}

function getStdDev {
    param([double[]]$values)
    if ($values.Count -lt 2) { return 0 }
    $mean = ($values | Measure-Object -Average).Average
    $sumSq = ($values | ForEach-Object { ($_ - $mean) * ($_ - $mean) } | Measure-Object -Sum).Sum
    return [math]::Round([math]::Sqrt($sumSq / ($values.Count - 1)), 2)
}

function scrapeMetrics {
    param([string]$url, [string]$outPath)
    try {
        $raw = Invoke-RestMethod -Uri "$url/metrics" -TimeoutSec 10 -ErrorAction Stop
        $raw | Out-File -FilePath $outPath -Encoding utf8
        return $raw
    } catch {
        Write-Warning "  Could not scrape /metrics: $_"
        return $null
    }
}

function detectSpecMode {
    param([string]$fileName)
    $modes = @("dflash-mtp", "dflash", "ngram-mtp", "mtp", "none")
    foreach ($m in $modes) {
        if ($fileName -match "-$([regex]::Escape($m))(?:-|$)") { return $m }
    }
    return "unknown"
}

function specModeColor {
    param([string]$mode)
    switch ($mode) {
        "dflash"     { return "#3fb950" }
        "mtp"        { return "#d29922" }
        "dflash-mtp" { return "#bc8cff" }
        "ngram-mtp"  { return "#58a6ff" }
        "none"       { return "#8b949e" }
        default      { return "#58a6ff" }
    }
}

# ---------- Validate scripts ----------
$resolved = @()
foreach ($s in $Scripts) {
    $full = if ([System.IO.Path]::IsPathRooted($s)) { $s } else { Join-Path (Get-Location) $s }
    if (-not (Test-Path $full)) {
        Write-Error "Script not found: $full"
        exit 1
    }
    $resolved += (Resolve-Path $full).Path
}
$Scripts = $resolved

# ---------- Banner ----------
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "       BeeLlama Benchmark Suite" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Configs:    $($Scripts.Count)"
Write-Host "  Runs:       $Runs"
Write-Host "  Warmup:     $WarmupRuns x $WarmupTokens tok"
$promptMode = if ($LongCtx) { "long-context (~125K tok prefill)" } else { "standard" }
Write-Host "  Prompts:    $promptMode"
Write-Host "  MaxTokens:  $MaxTokens"
Write-Host "  Cooldown:   ${CooldownSec}s (between runs), ${ConfigCooldownSec}s (between configs)"
Write-Host "  Retries:    $Retries"
Write-Host "  Output:     $OutputDir"
Write-Host ""

stopServer

# ---------- Run each config ----------
$allResults = @()

for ($ci = 0; $ci -lt $Scripts.Count; $ci++) {
    $scriptPath = $Scripts[$ci]
    $configName = [System.IO.Path]::GetFileNameWithoutExtension($scriptPath)
    $firstLine  = Get-Content $scriptPath -TotalCount 1 -ErrorAction SilentlyContinue
    $label      = if ($firstLine -match "^#\s*(.+)") { $Matches[1] } else { $configName }

    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Config $($ci + 1)/$($Scripts.Count): $label" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    # Launch server in background with log capture
    Write-Host "  Starting server..." -ForegroundColor Yellow
    $serverLog  = Join-Path $OutputDir "$configName.log"
    $configPort = getScriptPort $scriptPath
    $configUrl  = "http://localhost:$configPort"

    $serverProc = Start-Process "pwsh.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -PassThru -NoNewWindow `
        -RedirectStandardOutput $serverLog `
        -RedirectStandardError (Join-Path $OutputDir "$configName.err.log")

    # Wait for health
    Write-Host "  Waiting for server on port $configPort (up to ${ServerTimeoutSec}s)..." -ForegroundColor Yellow
    if (-not (waitForServer -url $configUrl -timeoutSec $ServerTimeoutSec)) {
        Write-Warning "  Server failed to start for: $configName - skipping."
        Write-Warning "  Check logs: $serverLog"
        if (Test-Path $serverLog) {
            Get-Content $serverLog -Tail 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
        $errLog = Join-Path $OutputDir "$configName.err.log"
        if ((Test-Path $errLog) -and (Get-Item $errLog).Length -gt 0) {
            Write-Host "  stderr:" -ForegroundColor Red
            Get-Content $errLog -Tail 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }
        stopServer
        if (-not $serverProc.HasExited) { $serverProc | Stop-Process -Force -ErrorAction SilentlyContinue }
        continue
    }
    Write-Host "  Server healthy." -ForegroundColor Green
    # Warmup (discard results, always uses standard prompts)
    Write-Host "  Warmup ($WarmupRuns runs x $($warmupPrompts.Count) prompts @ $WarmupTokens tok)..." -ForegroundColor Yellow
    for ($w = 1; $w -le $WarmupRuns; $w++) {
        foreach ($p in $warmupPrompts) {
            $null = runPromptWithRetry -prompt $p -url $configUrl -maxTokens $WarmupTokens -retries 1
        }
    }
    Write-Host "  Warmup done." -ForegroundColor Green

    # Benchmark runs
    for ($run = 1; $run -le $Runs; $run++) {
        Write-Host "  --- Run $run/$Runs ---" -ForegroundColor DarkCyan
        foreach ($p in $prompts) {
            $tokLimit = if ($p.PSObject.Properties["maxTokens"]) { $p.maxTokens } else { $MaxTokens }
            $result = runPromptWithRetry -prompt $p -url $configUrl -maxTokens $tokLimit -retries $Retries
            if ($result) {
                $result | Add-Member -NotePropertyName "Run"    -NotePropertyValue $run
                $result | Add-Member -NotePropertyName "Config" -NotePropertyValue $configName
                $result | Add-Member -NotePropertyName "Label"  -NotePropertyValue $label
                $allResults += $result
                Write-Host ("    {0,-25} {1,5} tok  {2,8} ms  TTFT {3,6} ms  {4,7} tok/s  {5,7} dec tok/s" -f `
                    $result.Prompt, $result.CompletionTokens, $result.WallTimeMs, $result.TTFT_Ms, $result.TokPerSec, $result.DecodeTokPerSec)
            }
        }
        if ($CooldownSec -gt 0 -and $run -lt $Runs) {
            Write-Host "    (cooldown ${CooldownSec}s)" -ForegroundColor DarkGray
            Start-Sleep -Seconds $CooldownSec
            }
    }

    # Scrape server metrics before stopping
    $metricsFile = Join-Path $OutputDir "$configName.metrics.txt"
    $null = scrapeMetrics -url $configUrl -outPath $metricsFile

    # Stop server
    Write-Host "  Stopping server..." -ForegroundColor Yellow
    stopServer
    if (-not $serverProc.HasExited) { $serverProc | Stop-Process -Force -ErrorAction SilentlyContinue }
    Write-Host "  Server stopped." -ForegroundColor Green

    # Cooldown between configs — gives GPU time to shed heat before next model loads.
    # Critical for single-GPU VS runs where back-to-back configs cause thermal throttling.
    if ($ci -lt $Scripts.Count - 1 -and $ConfigCooldownSec -gt 0) {
        Write-Host "  Cooling down (${ConfigCooldownSec}s)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $ConfigCooldownSec
    }
    Write-Host ""
}

# ---------- Quality Analysis (if enabled and Coding prompts present) ----------
$qualityCfg   = $fileCfg.PSObject.Properties["quality"]
$qualityMode  = ($qualityCfg -and $qualityCfg.Value.enabled -eq $true)
$codingResults = @($allResults | Where-Object { $_.Type -eq "Coding" })
$configs = $allResults | Select-Object -ExpandProperty Config -Unique
if ($qualityMode -and $codingResults.Count -gt 0) {
    Write-Host ""
    Write-Host "  === Quality Analysis (PowerShell static analysis) ===" -ForegroundColor Cyan

    # Load quality module
    $qaModule = Join-Path $BenchDir "quality_analysis.ps1"
    if (Test-Path $qaModule) {
        . $qaModule
    } else {
        Write-Warning "Quality module not found: $qaModule"
        $qualityMode = $false
    }

    if ($qualityMode) {
        $qaCfg = $qualityCfg.Value
        $qaHash = @{
            enabled          = $qaCfg.enabled
            timeoutSeconds   = $qaCfg.timeoutSeconds
            psScriptAnalyzer = @{ severity = @($qaCfg.psScriptAnalyzer.severity) }
            idiomChecks      = $qaCfg.idiomChecks
        }

        # Add quality fields to each Coding result
        foreach ($r in $codingResults) {
            $qa = Invoke-QualityAnalysis -Code $r.Content -PromptName $r.Prompt -Config $qaHash
            $r | Add-Member -NotePropertyName "QASyntaxOk"    -NotePropertyValue $qa.SyntaxOk
            $r | Add-Member -NotePropertyName "QAPSAErrors"   -NotePropertyValue $qa.PSAErrors
            $r | Add-Member -NotePropertyName "QAPSAWarnings" -NotePropertyValue $qa.PSAWarnings
            $r | Add-Member -NotePropertyName "QAIdiomScore"  -NotePropertyValue $qa.IdiomScore
            $r | Add-Member -NotePropertyName "QAGrade"       -NotePropertyValue $qa.Grade

            Write-Host ("    {0,-28} syntax={1}  PSA err={2} warn={3}  idiom={4}%  grade={5}" -f `
                $r.Prompt, $(if($qa.SyntaxOk){"OK"}else{"FAIL"}), $qa.PSAErrors, $qa.PSAWarnings, $qa.IdiomScore, $qa.Grade)
        }

        # Per-config quality averages
        Write-Host ""
        Write-Host "  --- Per-Config Quality Averages ---" -ForegroundColor DarkYellow
        foreach ($cfg in $configs) {
            $cfgCoding = @($codingResults | Where-Object { $_.Config -eq $cfg })
            if ($cfgCoding.Count -eq 0) { continue }

            $avgIdiom  = [math]::Round(($cfgCoding | Measure-Object -Property QAIdiomScore -Average).Average, 1)
            $avgPsaErr = [math]::Round(($cfgCoding | Measure-Object -Property QAPSAErrors -Average).Average, 1)
            $synOk     = ($cfgCoding | Where-Object { $_.QASyntaxOk }).Count
            $gradeA    = ($cfgCoding | Where-Object { $_.QAGrade -eq "A" }).Count

            Write-Host ("    {0,-40} syntax {1}/{2}  idiom {3}%  PSA err {4}  A-grades {5}/{6}" -f `
                $cfg, $synOk, $cfgCoding.Count, $avgIdiom, $avgPsaErr, $gradeA, $cfgCoding.Count)
        }

        # Head-to-head comparison (only when multiple configs)
        if ($configs.Count -gt 1) {
            Write-Host ""
            Write-Host "  === Head-to-Head Quality Comparison ===" -ForegroundColor Cyan
            Write-Host ("  {0,-30} {1,8} {2,8} {3,8} {4,8} {5}" -f `
                "Config", "Idiom%", "PSA Err", "Syn OK", "A-Grade", "Wins")
            Write-Host ("  {0}" -f ("-" * 75))

            # Find best in each category
            $bestIdiom = ($configs | ForEach-Object {
                $c = $_; $r = @($codingResults | Where-Object { $_.Config -eq $c })
                if ($r.Count -eq 0) { return @{C=$c;V=0} }
                @{C=$c;V=[math]::Round(($r | Measure-Object -Property QAIdiomScore -Average).Average,1)}
            } | Sort-Object V -Descending | Select-Object -First 1).C
            $bestPsa = ($configs | ForEach-Object {
                $c = $_; $r = @($codingResults | Where-Object { $_.Config -eq $c })
                if ($r.Count -eq 0) { return @{C=$c;V=999} }
                @{C=$c;V=[math]::Round(($r | Measure-Object -Property QAPSAErrors -Average).Average,1)}
            } | Sort-Object V | Select-Object -First 1).C
            $bestA = ($configs | ForEach-Object {
                $c = $_; $r = @($codingResults | Where-Object { $_.Config -eq $c -and $_.QAGrade -eq "A" })
                @{C=$c;V=$r.Count}
            } | Sort-Object V -Descending | Select-Object -First 1).C

            foreach ($c in $configs) {
                $r = @($codingResults | Where-Object { $_.Config -eq $c })
                if ($r.Count -eq 0) { continue }
                $idiom = [math]::Round(($r | Measure-Object -Property QAIdiomScore -Average).Average, 1)
                $psaE  = [math]::Round(($r | Measure-Object -Property QAPSAErrors -Average).Average, 1)
                $sOk   = ($r | Where-Object { $_.QASyntaxOk }).Count
                $aGrd  = ($r | Where-Object { $_.QAGrade -eq "A" }).Count
                $wins  = @()
                if ($c -eq $bestIdiom) { $wins += "idiom" }
                if ($c -eq $bestPsa)   { $wins += "clean" }
                if ($c -eq $bestA)     { $wins += "A-grade" }
                $winStr = if ($wins.Count -gt 0) { ($wins -join ",") + " *" } else { "" }
                Write-Host ("  {0,-30} {1,6}% {2,6} {3,6}/{4} {5,6}/{6}  {7}" -f `
                    $c, $idiom, $psaE, $sOk, $r.Count, $aGrd, $r.Count, $winStr)
            }
        }
    }
}

if ($allResults.Count -eq 0) {
    Write-Error "No results collected. Check server logs."
    exit 1
}


# ---------- Export results ----------
$csvPath = Join-Path $OutputDir "results.csv"
$csvProps = @("Config","Label","Run","Prompt","Type","PromptTokens","CompletionTokens","WallTimeMs","TTFT_Ms","TokPerSec","DecodeTokPerSec")
if ($qualityMode) { $csvProps += @("QASyntaxOk","QAPSAErrors","QAPSAWarnings","QAIdiomScore","QAGrade") }
$allResults | Select-Object $csvProps |
    Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "  CSV: $csvPath" -ForegroundColor Yellow

# Save full JSON for post-pass enrichment (Content preserved in JSON, not CSV)
$jsonPath = Join-Path $OutputDir "results_full.json"
$allResults | ConvertTo-Json -Depth 5 | Out-File -FilePath $jsonPath -Encoding utf8
Write-Host "  JSON: $jsonPath" -ForegroundColor Yellow

# ---------- Compute per-config statistics ----------
$configStats = @()
foreach ($cfg in $configs) {
    $cfgResults = $allResults | Where-Object { $_.Config -eq $cfg }
    $lbl  = ($cfgResults | Select-Object -First 1).Label
    $mode = detectSpecMode $cfg

    $tokValues  = @($cfgResults | ForEach-Object { $_.DecodeTokPerSec })

    $median    = getMedian $tokValues
    $mean      = [math]::Round(($tokValues | Measure-Object -Average).Average, 2)
    $stddev    = getStdDev $tokValues
    $minTok    = [math]::Round(($tokValues | Measure-Object -Minimum).Minimum, 2)
    $maxTok    = [math]::Round(($tokValues | Measure-Object -Maximum).Maximum, 2)
    $ttftValues = @($cfgResults | ForEach-Object { $_.TTFT_Ms })
    $medianTtft = getMedian $ttftValues
    $meanTtft   = [math]::Round(($ttftValues | Measure-Object -Average).Average, 0)

    # Sustained throughput: total completion tokens / total wall time
    $totalCompTok = ($cfgResults | Measure-Object -Property CompletionTokens -Sum).Sum
    $totalWallMs  = ($cfgResults | Measure-Object -Property WallTimeMs -Sum).Sum
    $sustained   = if ($totalWallMs -gt 0) { [math]::Round($totalCompTok / ($totalWallMs / 1000.0), 2) } else { 0 }
    $peak         = $maxTok
    $decodeMean   = [math]::Round(($cfgResults | ForEach-Object { $_.DecodeTokPerSec } | Measure-Object -Average).Average, 2)

    # Outlier count (>30% deviation from median)
    $outliers = @($tokValues | Where-Object { $median -gt 0 -and [math]::Abs($_ - $median) / $median -gt 0.30 }).Count

    $configStats += [PSCustomObject]@{
        Config      = $cfg
        Label       = $lbl
        SpecMode    = $mode
        Color       = specModeColor $mode
        Median      = $median
        Mean        = $mean
        StdDev      = $stddev
        Min         = $minTok
        Max         = $maxTok
        Peak        = $peak
        Sustained   = $sustained
        MedianTTFT  = $medianTtft
        MeanTTFT    = $meanTtft
        Outliers    = $outliers
        RunCount    = $tokValues.Count
    }
}
$maxMedian = ($configStats | Measure-Object -Property Median -Maximum).Maximum

# ---------- Console summary ----------
Write-Host ""
Write-Host "  === Summary (median decode tok/s over $Runs runs) ===" -ForegroundColor Cyan
foreach ($cs in $configStats) {
    $marker = if ($cs.Median -eq $maxMedian -and $configStats.Count -gt 1) { " *" } else { "" }
    Write-Host ("  {0,-45} {1,8} tok/s (med)  {2,8} tok/s (mean)  TTFT {3,5} ms{4}" -f `
        $cs.Label, $cs.Median, $cs.Mean, $cs.MedianTTFT, $marker)
}
Write-Host ""

# Outlier report
$hasOutliers = $false
foreach ($cs in $configStats) {
    if ($cs.Outliers -gt 0) {
        if (-not $hasOutliers) {
            Write-Host "  --- Outlier Flags (>30% deviation from median) ---" -ForegroundColor DarkYellow
            $hasOutliers = $true
        }
        Write-Host "    $($cs.Config): $($cs.Outliers) outlier(s) in $($cs.RunCount) measurements" -ForegroundColor DarkYellow
    }
}
if ($hasOutliers) { Write-Host "" }

# Stats table
Write-Host "  === Statistical Summary ===" -ForegroundColor Cyan
Write-Host ("  {0,-30} {1,8} {2,8} {3,8} {4,8} {5,8} {6,10} {7,8}" -f `
    "Config", "Dec tok/s", "Mean", "StdDev", "Min", "Max", "Thruput", "TTFT(ms)")
Write-Host ("  {0}" -f ("-" * 98))
foreach ($cs in $configStats) {
    Write-Host ("  {0,-30} {1,8} {2,8} {3,8} {4,8} {5,8} {6,10} {7,8}" -f `
        $cs.Config, $cs.Median, $cs.Mean, $cs.StdDev, $cs.Min, $cs.Max, $cs.Sustained, $cs.MedianTTFT)
}
Write-Host ""

# ---------- Grade distribution (quality mode) ----------
$gradeHtml = ""
if ($qualityMode) {
    $grades = @("A","B+","B","C","D","F")
    $gradeColors = @{A="#3fb950"; "B+"="#56d364"; B="#d29922"; C="#db6d28"; D="#f85149"; F="#f85149"}
    foreach ($cfg in $configs) {
        $cfgCoding = @($codingResults | Where-Object { $_.Config -eq $cfg })
        if ($cfgCoding.Count -eq 0) { continue }
        $gDist = $cfgCoding | Group-Object QAGrade -NoElement | ForEach-Object { @{ Grade=$_.Name; Count=$_.Count } }
        $maxCount = ($gDist | Measure-Object -Property Count -Maximum).Maximum
        $bars = ($grades | ForEach-Object {
            $g = $_; $c = ($gDist | Where-Object { $_.Grade -eq $g } | Select-Object -First 1)
            $cnt = if ($c) { $c.Count } else { 0 }
            $w = if ($maxCount -gt 0) { [math]::Round(($cnt / $maxCount) * 100) } else { 0 }
            "<div class='grade-bar' style='--grade-color:$($gradeColors[$g])'><span class='grade-label'>$g</span>" +
            "<span class='grade-fill' style='width:${w}%'></span><span class='grade-count'>$cnt</span></div>"
        }) -join ""
        $gradeHtml += "<div class='grade-card'><div class='grade-name'>$cfg</div><div class='grade-bars'>$bars</div></div>"
    }
}

# ---------- DeepSeek analysis ----------
$analysisHtml = ""
$dsKey = if ($env:DEEPSEEK_API_KEY) { $env:DEEPSEEK_API_KEY } else { [Environment]::GetEnvironmentVariable("DEEPSEEK_API_KEY","User") }
if ($dsKey) {
    Write-Host ""
    Write-Host "  Running DeepSeek analysis..." -ForegroundColor Cyan
    try {
        $anaPrompt = Get-Content (Join-Path $BenchDir "prompts-analysis.json") -Raw | ConvertFrom-Json
        # Build data summary
        $data = @()
        foreach ($cfg in $configs) {
            $cs = $configStats | Where-Object { $_.Config -eq $cfg }
            $cfgCoding = @($codingResults | Where-Object { $_.Config -eq $cfg })
            $aGrd = if ($cfgCoding) { ($cfgCoding | Where-Object { $_.QAGrade -eq "A" }).Count } else { 0 }
            $syn  = if ($cfgCoding) { ($cfgCoding | Where-Object { $_.QASyntaxOk }).Count } else { 0 }
            $avg  = if ($cfgCoding.Count -gt 0) { [math]::Round(($cfgCoding | Measure-Object -Property QAIdiomScore -Average).Average, 1) } else { 0 }
            $data += "  $cfg | $($cs.Median) tok/s | idiom $($avg)% | syntax $syn/$($cfgCoding.Count) | A-grades $aGrd/$($cfgCoding.Count)"

            # Check for post-pass AST results (may have run in a prior phase)
            $astFile = Join-Path $OutputDir "postpass\ast_validation.json"
            if (Test-Path $astFile) {
                try {
                    $astData = Get-Content $astFile -Raw | ConvertFrom-Json
                    if ($astData -isnot [array]) { $astData = @($astData) }
                    $cfgAst = @($astData | Where-Object { $_.Config -eq $cfg })
                    if ($cfgAst.Count -gt 0) {
                        $astPct = [math]::Round(($cfgAst | Measure-Object -Property ChecksPassed -Sum).Sum / [math]::Max(1, ($cfgAst | Measure-Object -Property ChecksTotal -Sum).Sum) * 100, 1)
                        $parseOk = ($cfgAst | Where-Object { $_.ParseOk }).Count
                        $data += "    -> AST structural: $astPct% ($($cfgAst | Measure-Object -Property ChecksPassed -Sum).Sum/$($cfgAst | Measure-Object -Property ChecksTotal -Sum).Sum checks), parse OK: $parseOk/$($cfgAst.Count)"
                        # Per-prompt detail for failed prompts
                        $failed = @($cfgAst | Where-Object { $_.ChecksPassed -lt $_.ChecksTotal })
                        if ($failed.Count -gt 0) {
                            $data += "    -> Failed prompts: $(($failed | ForEach-Object { "$($_.Prompt) ($($_.ChecksPassed)/$($_.ChecksTotal))" }) -join ", ")"
                        }
                    }
                } catch { }
            }
        }
        $isCompare = $configs.Count -gt 1
        $templateKey = if ($isCompare) { "template_compare" } else { "template_single" }
        $extra = if ($isCompare) { "6) Which model wins for coding quality and why." } else { "" }
        $body = $anaPrompt.$templateKey -f ($data -join "`n"), $extra, $configs.Count

        $headers = @{ "Authorization" = "Bearer $dsKey"; "Content-Type" = "application/json" }
        $payload = @{ model = "deepseek-chat"; messages = @(@{role="system";content=$anaPrompt.system},@{role="user";content=$body}); max_tokens=500; temperature=0.3 } | ConvertTo-Json
        $resp = Invoke-RestMethod -Uri "https://api.deepseek.com/v1/chat/completions" -Method Post -Headers $headers -Body $payload -TimeoutSec 30
        $verdict = $resp.choices[0].message.content.Trim()
        Write-Host "  DeepSeek analysis:" -ForegroundColor Green
        $verdict -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        $analysisHtml = "<div class='section'>deepseek analysis</div><div class='analysis-text'>" + ($verdict -replace "`n","<br>") + "</div>"
    } catch {
        Write-Warning "  DeepSeek analysis failed: $_"
        $analysisHtml = "<div class='section'>deepseek analysis</div><p class='dim'>Analysis unavailable: $_</p>"
    }
}

# ---------- Generate HTML report ----------

# Build summary cards
$cardsHtml = ""
foreach ($cs in $configStats) {
    $winClass = if ($cs.Median -eq $maxMedian -and $configStats.Count -gt 1) { " winner" } else { "" }
    $cardsHtml += @"
    <div class="card$winClass" style="--accent:$($cs.Color)">
      <style>.card[style*="--accent:$($cs.Color)"]::before{background:$($cs.Color)}</style>
      <div class="name">$($cs.Config)</div>
      <div class="desc">$($cs.Label)</div>
      <div class="big">$($cs.Median)<span class="unit">tok/s</span></div>
      <div class="sub">avg $($cs.Mean) // sd $($cs.StdDev) // ttft $($cs.MedianTTFT)ms</div>
    </div>
"@
}

# Build per-prompt comparison rows (tok/s median + TTFT)
$compRows = ""
foreach ($pn in $promptNames) {
    $pType = ($allResults | Where-Object { $_.Prompt -eq $pn } | Select-Object -First 1).Type
    $cells = ""
    $promptMax = 0
    $promptMedians = @{}
    $promptTtfts   = @{}
    $promptGradeStrs = @{}
    foreach ($cfg in $configs) {
        $pResults = $allResults | Where-Object { $_.Config -eq $cfg -and $_.Prompt -eq $pn }
        $tokVals  = @($pResults | ForEach-Object { $_.DecodeTokPerSec })
        $ttftVals = @($pResults | ForEach-Object { $_.TTFT_Ms })
        $med = getMedian $tokVals
        $promptMedians[$cfg] = $med
        $promptTtfts[$cfg]   = getMedian $ttftVals

        # Collect grades for this prompt+config (quality mode only)
        $gradeStr = ""
        if ($qualityMode) {
            $pGrades = @($pResults | Where-Object { $_.QAGrade } | ForEach-Object { $_.QAGrade })
            if ($pGrades.Count -gt 0) {
                $modeGrade = ($pGrades | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
                $gradeColorMap = @{A="#3fb950"; "B+"="#56d364"; B="#d29922"; C="#db6d28"; D="#f85149"; F="#f85149"}
                $gc = $gradeColorMap[$modeGrade]
                if (-not $gc) { $gc = "#71717a" }
                $gradeStr = "<span class='grade-badge' style='background:${gc}20;color:${gc};border:1px solid ${gc}50'>$modeGrade</span>"
            }
        }
        $promptGradeStrs[$cfg] = $gradeStr
        if ($med -gt $promptMax) { $promptMax = $med }
    }
    foreach ($cfg in $configs) {
        $med  = $promptMedians[$cfg]
        $ttft = $promptTtfts[$cfg]
        $gradeStr = $promptGradeStrs[$cfg]
        $pct  = if ($promptMax -gt 0) { [math]::Round(($med / $promptMax) * 100) } else { 0 }
        $cs   = $configStats | Where-Object { $_.Config -eq $cfg }
        $winMark = if ($med -eq $promptMax -and $configStats.Count -gt 1) { ' class="winner-cell"' } else { "" }
        $cells += @"
      <td$winMark>
        <div class="bar-row"><div class="bar" style="width:${pct}%;background:$($cs.Color)"></div><span>$med$gradeStr</span></div>
        <div class="ttft-label">TTFT ${ttft} ms</div>
      </td>
"@
    }
    $compRows += "    <tr><td>$pn</td><td>$pType</td>$cells</tr>`n"
}

# Config column headers
$cfgHeaders = ""
foreach ($cfg in $configs) { $cfgHeaders += "      <th>$cfg</th>`n" }

# Statistics rows
$statsRows = ""
foreach ($cs in $configStats) {
    $outLabel = if ($cs.Outliers -gt 0) { "$($cs.Outliers)/$($cs.RunCount)" } else { "-" }
    $statsRows += @"
    <tr>
      <td style="border-left:3px solid $($cs.Color)">$($cs.Config)</td>
      <td>$($cs.Median)</td><td>$($cs.Mean)</td><td>$($cs.StdDev)</td>
      <td>$($cs.Min)</td><td>$($cs.Max)</td>
      <td>$($cs.Sustained)</td>
      <td>$($cs.MedianTTFT)ms</td>
      <td>$outLabel</td>
    </tr>
"@
}

# Full results rows
$fullRows = ""
foreach ($r in ($allResults | Sort-Object Config, Run, Prompt)) {
    # Flag outliers
    $cs = $configStats | Where-Object { $_.Config -eq $r.Config }
    $isOutlier = ($cs.Median -gt 0 -and [math]::Abs($r.TokPerSec - $cs.Median) / $cs.Median -gt 0.30)
    $outlierMark = if ($isOutlier) { ' class="outlier"' } else { "" }
    $fullRows += "    <tr$outlierMark><td>$($r.Config)</td><td>$($r.Run)</td><td>$($r.Prompt)</td><td>$($r.Type)</td><td>$($r.PromptTokens)</td><td>$($r.CompletionTokens)</td><td>$($r.WallTimeMs)</td><td>$($r.TTFT_Ms)</td><td>$($r.TokPerSec)</td></tr>`n"
}

$htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>beeLLama bench // $timestamp</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Inter:wght@400;600;800&display=swap');
  :root {
    --bg: #09090b; --surface: #111113; --border: #1e1e22;
    --text: #a1a1aa; --bright: #e4e4e7; --dim: #52525b;
    --neon-green: #22d3ee; --neon-pink: #f472b6; --neon-purple: #a78bfa;
    --neon-orange: #fb923c; --neon-gray: #71717a;
    --win: #22d3ee;
  }
  * { margin:0; padding:0; box-sizing:border-box; }
  body { font-family:'Inter',system-ui,sans-serif; background:var(--bg); color:var(--text); padding:1.25rem 1.5rem; line-height:1.4; max-width:1400px; margin:0 auto; }

  /* Header */
  .header { display:flex; align-items:baseline; gap:1rem; margin-bottom:.4rem; }
  .header h1 { font-family:'JetBrains Mono',monospace; font-size:1.1rem; font-weight:700; color:var(--bright); letter-spacing:-.02em; }
  .header h1 span { color:var(--neon-green); }
  .header .tag { font-size:.6rem; font-family:'JetBrains Mono',monospace; color:var(--dim); background:var(--surface); border:1px solid var(--border); border-radius:3px; padding:.1rem .4rem; }
  .meta { display:flex; gap:.75rem; font-size:.65rem; font-family:'JetBrains Mono',monospace; color:var(--dim); margin-bottom:1rem; flex-wrap:wrap; }
  .meta span { background:var(--surface); border:1px solid var(--border); border-radius:3px; padding:.1rem .4rem; }

  /* Cards grid */
  .cards { display:grid; grid-template-columns:repeat(auto-fit, minmax(200px, 1fr)); gap:.6rem; margin-bottom:1rem; }
  .card { background:var(--surface); border:1px solid var(--border); border-radius:6px; padding:.75rem .85rem; position:relative; overflow:hidden; }
  .card::before { content:''; position:absolute; top:0; left:0; width:3px; height:100%; }
  .card .name { font-family:'JetBrains Mono',monospace; font-size:.6rem; color:var(--dim); text-transform:uppercase; letter-spacing:.06em; margin-bottom:.1rem; }
  .card .desc { font-size:.65rem; color:var(--text); margin-bottom:.35rem; }
  .card .big { font-size:1.6rem; font-weight:800; color:var(--bright); line-height:1; }
  .card .big .unit { font-size:.7rem; font-weight:400; color:var(--dim); margin-left:.2rem; }
  .card .sub { font-size:.6rem; color:var(--dim); margin-top:.2rem; font-family:'JetBrains Mono',monospace; }
  .card.winner { border-color:color-mix(in srgb, var(--win) 40%, transparent); background:linear-gradient(135deg, var(--surface) 0%, color-mix(in srgb, var(--win) 6%, var(--surface)) 100%); }
  .card.winner .big { color:var(--win); text-shadow:0 0 20px color-mix(in srgb, var(--win) 30%, transparent); }

  /* Section labels */
  .section { font-family:'JetBrains Mono',monospace; font-size:.6rem; font-weight:700; text-transform:uppercase; letter-spacing:.08em; color:var(--dim); margin:1rem 0 .4rem; display:flex; align-items:center; gap:.5rem; }
  .section::after { content:''; flex:1; height:1px; background:var(--border); }

  /* Tables */
  table { width:100%; border-collapse:collapse; font-size:.7rem; margin-bottom:.75rem; }
  th { font-family:'JetBrains Mono',monospace; font-size:.55rem; font-weight:600; text-transform:uppercase; letter-spacing:.06em; color:var(--dim); padding:.35rem .5rem; text-align:left; border-bottom:1px solid var(--border); }
  td { padding:.3rem .5rem; border-bottom:1px solid color-mix(in srgb, var(--border) 50%, transparent); color:var(--text); }
  tr:hover td { background:color-mix(in srgb, var(--surface) 80%, var(--neon-green) 3%); }
  .winner-cell { color:var(--win); font-weight:700; }
  .outlier td { color:var(--neon-orange); background:color-mix(in srgb, var(--neon-orange) 5%, transparent); }

  /* Bars */
  .bar-row { display:flex; align-items:center; gap:.4rem; }
  .bar { height:14px; border-radius:2px; min-width:2px; opacity:.85; }
  .bar-row span { font-size:.65rem; font-family:'JetBrains Mono',monospace; white-space:nowrap; min-width:2.5rem; }
  .ttft-label { font-size:.55rem; color:var(--dim); font-family:'JetBrains Mono',monospace; }

  /* Collapsible raw data */
  details { margin-top:.5rem; }
  details summary { font-family:'JetBrains Mono',monospace; font-size:.6rem; font-weight:600; text-transform:uppercase; letter-spacing:.08em; color:var(--dim); cursor:pointer; padding:.3rem 0; user-select:none; }
  details summary:hover { color:var(--text); }
  details summary::marker { color:var(--neon-green); }

  /* Two-column layout for stats + prompts */
  .grid-2 { display:grid; grid-template-columns:1fr 1fr; gap:.75rem; }
  @media (max-width:900px) { .grid-2 { grid-template-columns:1fr; } }

  .footer { font-family:'JetBrains Mono',monospace; color:var(--dim); font-size:.55rem; margin-top:.75rem; text-align:right; }
  .footer span { color:var(--neon-green); }
  .grade-card { margin-bottom:.5rem; }
  .grade-name { font-family:'JetBrains Mono',monospace; font-size:.5rem; color:var(--dim); margin-bottom:.15rem; }
  .grade-bar { display:flex; align-items:center; gap:.3rem; margin:.1rem 0; }
  .grade-label { font-size:.45rem; width:.8rem; text-align:right; color:var(--dim); }
  .grade-fill { display:inline-block; height:6px; background:var(--grade-color); border-radius:3px; min-width:2px; }
  .grade-count { font-size:.4rem; color:var(--dim); margin-left:.2rem; }
  .analysis-text { font-family:'JetBrains Mono',monospace; font-size:.6rem; color:var(--bright); line-height:1.6; margin:0; padding:.6rem; background:var(--surface); border-radius:4px; }
  .grade-badge { font-family:'JetBrains Mono',monospace; font-size:.55rem; font-weight:700; padding:0 .25rem; border-radius:2px; margin-left:.3rem; }
</head>
<body>

<div class="header">
  <h1><span>//</span> bee<span>LL</span>ama bench</h1>
  <span class="tag">v2</span>
</div>
<div class="meta">
  <span>$timestamp</span>
  <span>$Runs runs</span>
  <span>$WarmupRuns warmup</span>
  <span>$MaxTokens max tok</span>
  <span>$($prompts.Count) prompts</span>
  $(if ($qualityMode) { "<span>quality benchmark</span>" } else { "" })
</div>

<div class="cards">
$cardsHtml
</div>

$(if ($analysisHtml) { $analysisHtml } else { "" })

<div class="grid-2">
<div>
  <div class="section">per-prompt comparison</div>
  <table>
    <thead>
      <tr>
        <th>Prompt</th>
        <th>Type</th>
$cfgHeaders
      </tr>
    </thead>
    <tbody>
$compRows
    </tbody>
  </table>
</div>
<div>
  <div class="section">statistics</div>
  <table>
    <thead>
      <tr>
        <th>Config</th>
        <th>Med</th><th>Avg</th><th>SD</th>
        <th>Min</th><th>Max</th>
        <th>Sust.</th>
        <th>TTFT</th>
        <th>Out</th>
      </tr>
    </thead>
    <tbody>
$statsRows
    </tbody>
  </table>
</div>
</div>

<details>
  <summary>all individual results ($($allResults.Count) rows)</summary>
  <table>
    <thead>
      <tr><th>Config</th><th>Run</th><th>Prompt</th><th>Type</th><th>P.Tok</th><th>C.Tok</th><th>ms</th><th>TTFT</th><th>tok/s</th></tr>
    </thead>
    <tbody>
$fullRows
    </tbody>
  </table>
</details>

<p class="footer"><span>//</span> beeLLama benchmark suite</p>

$(if ($gradeHtml) {
    "<div class='section'>per-config grade distribution</div><div class='grid-2'><div>$gradeHtml</div></div>"
} else { "" })


</body>
</html>
"@
# Write HTML report and open in browser
$htmlPath = Join-Path $OutputDir "results.html"
$htmlContent | Out-File -FilePath $htmlPath -Encoding utf8
Write-Host "  HTML: $htmlPath" -ForegroundColor Yellow
Start-Process $htmlPath

Write-Host ""
Write-Host "  Benchmark complete." -ForegroundColor Green
Write-Host ""
