# beellama_common.ps1
# Shared configuration for all beellama launch scripts.
# Reads config.json for base paths, exposes model/drafter/mmproj lookups
# and helper functions (Get-ServerBinary, Get-CommonFlags).
#
# Dot-source from any launch script in /run:
#   . "$PSScriptRoot\beellama_common.ps1"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $RepoRoot)
{
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

# ---------- Load config.json ----------
$ConfigPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $ConfigPath))
{
    Write-Error "config.json not found at $ConfigPath"
    exit 1
}
$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# ---------- Resolve base paths ----------
$AltModelsPath    = "D:\.lmstudio\models"       # alternate drive (DeltaNet models, LuceBox drafts, jackrong models moved off C:)

$ModelBase_Ornith   = Join-Path $AltModelsPath "deepreinforce-ai"
$ModelBase_Glimmer  = Join-Path $AltModelsPath "meta-models"
$ModelBase_UnslothGlimmer = Join-Path $AltModelsPath "unsloth\meta-glimmer30b-gguf"  # Unsloth Dynamic 2.0 GGUFs (UD-Q4_K_XL 15.88GB, mmproj-kquant 1.40GB, dflash 1.63GB)
# Qwen3.8-27B (Unsloth GGUF, MTP head baked in — no separate draft model) — today's release, D:\ alt drive
$ModelBase_Qwen38    = Join-Path $AltModelsPath "unsloth\qwen3.8-27B-gguf"
# ---------- Model catalog ----------
# Target models keyed by friendly name
$Model = @{
    # deepreinforce-ai Ornith-1.0-35B (Qwen3.5 MoE, 40L, 256 experts, agentic coding RL)
    "Ornith-1.0-35B-Q4_K_M"    = Join-Path $ModelBase_Ornith "ornith-1.0-35b-Q4_K_M.gguf"
    # Meta Muse Glimmer 30B — legacy KQuant path (D:\.lmstudio\models\meta-models, 15.61 GB) — kept as fallback
    # Dense 52L, 6656 hidden, 32Q/2KV, SWA 2048 [L,L,L,G] x13 = 39 local + 13 global, RoPE theta 500k, 131072 ctx, vocab 202k
    "Muse-Glimmer-30B-KQuant-17GB" = Join-Path $ModelBase_Glimmer "muse-glimmer-30B-kquant-17gb.gguf"
    # Unsloth Muse Glimmer 30B Dynamic 2.0 — D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf (per https://unsloth.ai/docs/models/muse-glimmer)
    # UD-Q4_K_XL 15.88GB is the 17GB-class 24GB-VRAM target (recommended start); UD-Q3/Q2 are headroom variants
    "Muse-Glimmer-30B-UD-Q4_K_XL" = Join-Path $ModelBase_UnslothGlimmer "Muse-Glimmer-30B-UD-Q4_K_XL.gguf"
    "Muse-Glimmer-30B-UD-Q3_K_XL" = Join-Path $ModelBase_UnslothGlimmer "Muse-Glimmer-30B-UD-Q3_K_XL.gguf"
    "Muse-Glimmer-30B-UD-Q2_K_XL" = Join-Path $ModelBase_UnslothGlimmer "Muse-Glimmer-30B-UD-Q2_K_XL.gguf"
    # Qwen3.8-27B (Unsloth, hybrid thinking + vision, 256K native ctx, MTP head in GGUF)
    #   Q4_K_M = standard 4-bit base (13-19 GB class); Q4_K_S = smaller 4-bit (vision/large-ctx budget);
    #   UD-Q4_K_XL = flagship Unsloth Dynamic 2.0 quant (highest fidelity 4-bit, ~16.7 GB)
    "Qwen3.8-27B-Q4_K_M"         = Join-Path $ModelBase_Qwen38 "Qwen3.8-27B-Q4_K_M.gguf"
    "Qwen3.8-27B-Q4_K_S"         = Join-Path $ModelBase_Qwen38 "Qwen3.8-27B-Q4_K_S.gguf"
    "Qwen3.8-27B-UD-Q4_K_XL"     = Join-Path $ModelBase_Qwen38 "Qwen3.8-27B-UD-Q4_K_XL.gguf"
}

# DFlash draft models (Ardenzard GGUFs for beellama.cpp DFlash)
$Drafter = @{
    # Muse Glimmer DFlash — Unsloth Dynamic 2.0 (1.63GB dflash-kquant.gguf)
    "Glimmer-DFlash" = Join-Path $ModelBase_UnslothGlimmer "dflash-kquant.gguf"
    # KVFlash scorer (Qwen3-0.6B) for chunk ranking in long-context paging
    "KVFlash-Qwen3-0.6B" = Join-Path $AltModelsPath "drafter\Qwen3-0.6B-BF16.gguf"
}

# Multimodal projectors
$MmprojLookup = @{
    "Ornith-bf16"   = Join-Path $ModelBase_Ornith   "mmproj-deepreinforce-ai_Ornith-1.0-35B-bf16.gguf"
    "Qwen38-BF16"   = Join-Path $ModelBase_Qwen38 "mmproj-BF16.gguf"
    "Glimmer"       = Join-Path $ModelBase_UnslothGlimmer "mmproj-kquant.gguf"
}

# ---------- Binary resolution ----------
# Picks the right llama-server.exe based on build type.
function Get-ServerBinary
{
    param(
        [ValidateSet("beellama_fork", "beellama", "beellama_prebuilt", "ik_llama", "llama.cpp")]
        [string]$Build = "beellama_fork"
    )

    $RelPath  = $Config.binaries.$Build
    $FullPath = Join-Path $RepoRoot $RelPath

    if (Test-Path $FullPath)
    {
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
function Get-CommonFlags
{
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
    if (-not $SkipMmproj -and $MmprojPath)
    {
        $Flags += "--mmproj", $MmprojPath
        $Flags += "--no-mmproj-offload"
    }

    # Speculative decoding
    if ($SpecMode -eq "dflash")
    {
        if (-not $DraftModel)
        {
            Write-Error "DFlash mode requires -DraftModel. Provide a DFlash draft GGUF path."
            exit 1
        }
        $Flags += "--spec-type",            "dflash"
        $Flags += "--spec-draft-model",     $DraftModel
        $Flags += "--spec-dflash-cross-ctx", $CrossCtx
        $Flags += "--spec-draft-ngl",       "all"
    } elseif ($SpecMode -eq "mtp")
    {
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
    if ($Reasoning)
    {
        $Flags += "--reasoning",              "on"
        $Flags += "--chat-template-kwargs",   '{"preserve_thinking":true}'
    } else
    {
        $Flags += "--reasoning",              "off"
        $Flags += "--chat-template-kwargs",   '{"preserve_thinking":false}'
    }

    return $Flags
}
