# beellama_common.ps1
# Shared configuration for all beellama launch scripts.
# Reads config.json for base paths, exposes model/drafter/mmproj lookups
# and helper functions (Get-ServerBinary, Get-CommonFlags).
#
# Dot-source from any launch script in /run:
#   . "$PSScriptRoot\beellama_common.ps1"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

# ---------- Load config.json ----------
$ConfigPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $ConfigPath)) {
    Write-Error "config.json not found at $ConfigPath"
    exit 1
}
$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# ---------- Resolve base paths ----------
$LmStudioModels = [Environment]::ExpandEnvironmentVariables($Config.lmstudioModelsPath)

$ModelBase_LmStudio  = Join-Path $LmStudioModels "lmstudio-community\Qwen3.6-27B-GGUF"
$ModelBase_Unsloth   = Join-Path $LmStudioModels "unsloth\Qwen3.6-27B-MTP-GGUF"
$ModelBase_Ardenzard = Join-Path $LmStudioModels "Ardenzard\Qwen3.6-27B-DFlash-GGUF"

# ---------- Model catalog ----------
# Target models keyed by friendly name
$Model = @{
    "Qwen3.6-27B-Q4_K_M"       = Join-Path $ModelBase_LmStudio "Qwen3.6-27B-Q4_K_M.gguf"
    "Qwen3.6-27B-Q5_K_M"       = Join-Path $ModelBase_Unsloth  "Qwen3.6-27B-Q5_K_M.gguf"
    "Qwen3.6-27B-Q5_K_S"       = Join-Path $ModelBase_Unsloth  "Qwen3.6-27B-Q5_K_S.gguf"
    "Qwen3.6-27B-MTP-Q4_K_M"   = Join-Path $ModelBase_Unsloth  "Qwen3.6-27B-Q4_K_M.gguf"
    "Qwen3.6-27B-MTP-Q4_K_S"   = Join-Path $ModelBase_Unsloth  "Qwen3.6-27B-Q4_K_S.gguf"
    "Qwopus3.5-9B-Coder"       = Join-Path $LmStudioModels "Jackrong\Qwopus3.5-9B-Coder-GGUF\Qwopus3.5-9B-coder-Exp-BF16.gguf"
}

# DFlash draft models
$Drafter = @{
    "DFlash-IQ4_XS" = Join-Path $ModelBase_Ardenzard "Qwen3.6-27B-DFlash-IQ4_XS.gguf"
    "DFlash-Q4_K_M" = Join-Path $ModelBase_Ardenzard "Qwen3.6-27B-DFlash-Q4_K_M.gguf"
    "DFlash-Q5_K_M" = Join-Path $ModelBase_Ardenzard "Qwen3.6-27B-DFlash-Q5_K_M.gguf"
    "DFlash-Q8"     = Join-Path $LmStudioModels "spiritbuun\Qwen3.6-27B-DFlash-GGUF\dflash-draft-3.6-q8_0.GGUF"
}

# Multimodal projectors
$MmprojLookup = @{
    "LmStudio-BF16" = Join-Path $ModelBase_LmStudio "mmproj-Qwen3.6-27B-BF16.gguf"
    "Unsloth-F32"   = Join-Path $ModelBase_Unsloth  "mmproj-F32.gguf"
}

# ---------- Binary resolution ----------
# Picks the right llama-server.exe based on build type.
# DFlash-only configs use "original"; MTP/fork configs use "fork"; fallback to "prebuilt".
function Get-ServerBinary {
    param(
        [ValidateSet("fork", "original", "prebuilt")]
        [string]$Build = "fork"
    )

    $RelPath  = $Config.binaries.$Build
    $FullPath = Join-Path $RepoRoot $RelPath

    if (Test-Path $FullPath) {
        return $FullPath
    }

    # Fallback: try each binary in priority order
    foreach ($b in @("fork", "original", "prebuilt")) {
        $p = Join-Path $RepoRoot ($Config.binaries.$b)
        if (Test-Path $p) {
            Write-Warning "Preferred build '$Build' not found. Falling back to '$b'."
            return $p
        }
    }

    Write-Error "No llama-server.exe found. Run sources\setup-sources.ps1 and build, or place a prebuilt binary under prebuilt\."
    exit 1
}

# ---------- Common launch flags ----------
# Returns an array of CLI arguments for llama-server.
#
# SpecMode controls speculative decoding:
#   "dflash" — cross-attention draft (requires -DraftModel)
#   "mtp"    — multi-token prediction (auto-detected by fork; do NOT pass --spec-type)
#   "none"   — no speculative decoding
#
# MTP and DFlash are mutually exclusive per launch.
function Get-CommonFlags {
    param(
        [ValidateSet("mtp", "dflash", "none")]
        [string]$SpecMode = "dflash",
        [string]$DraftModel = "",
        [string]$CtxSize = "122800",
        [string]$CacheK = "turbo4",
        [string]$CacheV = "turbo4",
        [string]$CrossCtx = "256",
        [string]$BatchSize = "256",
        [string]$UBatchSize = "64",
        [string]$MmprojPath = "",
        [switch]$Reasoning,
        [switch]$SkipMmproj
    )
    $Flags = @()

    # Multimodal projector
    if (-not $SkipMmproj -and $MmprojPath) {
        $Flags += "--mmproj", $MmprojPath
        $Flags += "--no-mmproj-offload"
    }

    # Speculative decoding
    if ($SpecMode -eq "dflash") {
        if (-not $DraftModel) {
            Write-Error "DFlash mode requires -DraftModel. Provide a DFlash draft GGUF path."
            exit 1
        }
        $Flags += "--spec-type",            "dflash"
        $Flags += "--spec-draft-model",     $DraftModel
        $Flags += "--spec-dflash-cross-ctx", $CrossCtx
        $Flags += "--spec-draft-ngl",       "all"
    }
    elseif ($SpecMode -eq "mtp") {
        # MTP: auto-detected by fork; set draft token count per Unsloth recommendation
        $Flags += "--spec-draft-n-max", "2"
    }
    # "none": no speculative decoding flags

    # Server + inference flags
    $Flags += @(
        "--port",           "$($Config.server.port)",
        "--host",           $Config.server.host,
        "-np",              "1",
        "--kv-unified",
        "-ngl",             "all",
        "--ctx-size",       $CtxSize,
        "-b",               $BatchSize,
        "-ub",              $UBatchSize,
        "--cache-type-k",   $CacheK,
        "--cache-type-v",   $CacheV,
        "--flash-attn",     "on",
        "--cache-ram",      "0",
        "--jinja",
        "--no-mmap",
        "--mlock",
        "--no-host",
        "--metrics",
        "--log-timestamps",
        "--log-prefix",
        "--log-colors",     "off",
        "--temp",           "0.6",
        "--top-k",          "20",
        "--min-p",          "0.0"
    )

    # Reasoning mode
    if ($Reasoning) {
        $Flags += "--reasoning",              "on"
        $Flags += "--chat-template-kwargs",   '{"preserve_thinking":true}'
    } else {
        $Flags += "--reasoning",              "off"
        $Flags += "--chat-template-kwargs",   '{"preserve_thinking":false}'
    }

    return $Flags
}
