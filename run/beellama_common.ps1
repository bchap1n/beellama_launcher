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
$LmStudioModels   = [Environment]::ExpandEnvironmentVariables($Config.lmstudioModelsPath)
$AltModelsPath    = "D:\.lmstudio\models"       # alternate drive (DeltaNet models, LuceBox drafts, jackrong models moved off C:)

$ModelBase_Unsloth   = Join-Path $LmStudioModels "unsloth\Qwen3.6-27B-MTP-GGUF"
$ModelBase_Ardenzard = Join-Path $LmStudioModels "Ardenzard\Qwen3.6-27B-DFlash-GGUF"
$ModelBase_Jackrong  = Join-Path $AltModelsPath "jackrong"
$ModelBase_GemmaAlt  = Join-Path $AltModelsPath "unsloth"
$ModelBase_Gemma     = Join-Path $LmStudioModels "unsloth"
$ModelBase_LuceBox   = Join-Path $LmStudioModels "Lucebox"
$ModelBase_Ornith   = Join-Path $AltModelsPath "deepreinforce-ai"

# ---------- Model catalog ----------
# Target models keyed by friendly name
$Model = @{
    "Qwen3.6-27B-Q4_K_M"       = Join-Path $ModelBase_Unsloth "Qwen3.6-27B-Q4_K_M.gguf"
    # Jackrong Qwopus Coder (agentic coding fine-tune, Claude Opus trace inversion) — Compat-MTP on alt D:\jackrong
    "Qwopus3.6-27B-Coder-Q5_K_M"     = "D:\.lmstudio\models\jackrong\Qwopus3.6-27B-Coder-Compat-MTP-GGUF\Qwopus3.6-27B-Coder-Compat-MTP-Q5_K_M.gguf"
    # Qwen3.6-27B non-MTP (standard Unsloth, DeltaNet — for LuceBox)
    "Qwen3.6-27B-Q4_K_M-DeltaNet"         = Join-Path $AltModelsPath "unsloth\Qwen3.6-27B-Q4_K_M.gguf"
    # Qwopus Coder Compat-MTP (jackrong — for LuceBox; using MTP file)
    "Qwopus3.6-27B-Coder-Q4_K_M-DeltaNet" = Join-Path $AltModelsPath "jackrong\Qwopus3.6-27B-Coder-Compat-MTP-GGUF\Qwopus3.6-27B-Coder-Compat-MTP-Q4_K_M.gguf"
    # Gemma 4 (Unsloth GGUFs)
    "Gemma4-12B-UD-Q4_K_XL"           = Join-Path $ModelBase_Gemma "gemma-4-12B-it-qat-GGUF\gemma-4-12B-it-qat-UD-Q4_K_XL.gguf"
    "Gemma4-31B-QAT-UD-Q4_K_XL"       = Join-Path $ModelBase_Gemma "gemma-4-31B-it-qat-GGUF\gemma-4-31B-it-qat-UD-Q4_K_XL.gguf"
    # Gemma 4 (balanced combo — alt drive, non-QAT)
    "Gemma4-31B-Q4_K_S"               = Join-Path $ModelBase_GemmaAlt "gemma-4-31B-it-GGUF\gemma-4-31B-it-Q4_K_S.gguf"
    # bytkim Qwen3.6-27B MTP pi-tune (QLORA SFT for PI harness, no-thinking agentic coding)
    "Qwen3.6-27B-MTP-pi-tune-Q4_K_M" = Join-Path $AltModelsPath "bytkim\Qwen3.6-27B-MTP-pi-tune-Q4_K_M.gguf"
    # bytkim Qwen3.6-27B MTP pi-reasoning (QLORA SFT, thinking-trained companion to pi-tune)
    "Qwen3.6-27B-MTP-pi-reasoning-Q4_K_M" = Join-Path $AltModelsPath "bytkim\Qwen3.6-27B-MTP-pi-reasoning-Q4_K_M.gguf"
    # yuxinlu1 Gemma 4 v2 12B (MTP fine-tune, separate draft heads)
    "Gemma4-12B-v2-Q6_K"          = Join-Path $AltModelsPath "yuxinlu1\gemma4-v2-Q6_K.gguf"
    # deepreinforce-ai Ornith-1.0-35B (Qwen3.5 MoE, 40L, 256 experts, agentic coding RL)
    "Ornith-1.0-35B-Q4_K_M"    = Join-Path $ModelBase_Ornith "ornith-1.0-35b-Q4_K_M.gguf"
    # Jackrong Qwopus 35B-A3B Coder MTP (MoE 35B/3B active, thinking-off agentic coding)
    "Qwopus3.6-35B-A3B-Coder-Q4_K_M" = "D:\.lmstudio\models\jackrong\Qwopus3.6-35B-A3B-Coder-MTP-Q4_K_M.gguf"
}

# DFlash draft models (Ardenzard GGUFs for beellama.cpp DFlash)
$Drafter = @{
    "DFlash-IQ4_XS" = Join-Path $ModelBase_Ardenzard "Qwen3.6-27B-DFlash-IQ4_XS.gguf"
    # Anbeeld DFlash drafts (for beellama.cpp DFlash)
    "Anbeeld-Gemma4-31B-DFlash-IQ4_XS" = Join-Path $AltModelsPath "anbeeld\gemma-4-31B-it-DFlash-GGUF\gemma4-31b-it-dflash-IQ4_XS.gguf"
    # LuceBox DFlash drafts (lucebox-hub native spec decode)
    "LuceBox-Gemma4-31B-DFlash" = Join-Path $ModelBase_LuceBox "gemma-4-31B-it-DFlash-GGUF\gemma-4-31B-it-DFlash-q8_0.gguf"
    # LuceBox Qwen3.6-27B DFlash draft (non-MTP, for use with unsloth/Qwen3.6-27B-GGUF)
    "LuceBox-Qwen-DFlash" = Join-Path $AltModelsPath "Lucebox\Qwen3.6-27B-DFlash-GGUF\dflash-draft-3.6-q4_k_m.gguf"
    # KVFlash scorer (Qwen3-0.6B) for chunk ranking in long-context paging
    "KVFlash-Qwen3-0.6B" = Join-Path $AltModelsPath "drafter\Qwen3-0.6B-BF16.gguf"
}

# Multimodal projectors
$MmprojLookup = @{
    "Unsloth-F32"   = Join-Path $ModelBase_Unsloth  "mmproj-F32.gguf"
    "Coder-F32"     = Join-Path $ModelBase_Jackrong "Qwopus3.6-27B-Coder-Compat-MTP-GGUF\mmproj-F32.gguf"
    "Gemma12B-F32"  = Join-Path $ModelBase_Gemma    "gemma-4-12B-it-qat-GGUF\mmproj-F32.gguf"
    "Gemma31B-F32"  = Join-Path $ModelBase_Gemma    "gemma-4-31B-it-qat-GGUF\mmproj-F32.gguf"
    "Ornith-bf16"   = Join-Path $ModelBase_Ornith   "mmproj-deepreinforce-ai_Ornith-1.0-35B-bf16.gguf"
}

# ---------- Binary resolution ----------
# Picks the right llama-server.exe based on build type.
function Get-ServerBinary {
    param(
        [ValidateSet("beellama_fork", "beellama", "beellama_prebuilt", "ik_llama", "llama.cpp")]
        [string]$Build = "beellama_fork"
    )

    $RelPath  = $Config.binaries.$Build
    $FullPath = Join-Path $RepoRoot $RelPath

    if (Test-Path $FullPath) {
        return $FullPath
    }

    Write-Error "Build '$Build' not found at: $FullPath"
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
        # MTP: explicit spec-type required by main beellama.cpp (fork auto-detects it)
        $Flags += "--spec-type", "draft-mtp", "--spec-draft-n-max", "2"
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
