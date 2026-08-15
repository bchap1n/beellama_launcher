# 65K ctx, q4_0 KV, b256/ub64, think ON, vision ON — LLAMA.CPP DFLASH (Unsloth Dynamic 2.0)
# Source: unsloth/meta-glimmer30b-gguf — Muse-Glimmer-30B-UD-Q4_K_XL.gguf (15.88 GB) + dflash-kquant.gguf (1.63 GB) + mmproj-kquant.gguf (1.40 GB)
#         per https://unsloth.ai/docs/models/muse-glimmer ; https://huggingface.co/unsloth/Muse-Glimmer-30B-GGUF
# Binary: sources/llama.cpp/build/bin/llama-server.exe (upstream master >=62bf73d, -DGGML_CUDA=ON)
# Model:  52L dense, 6656 hidden, 32Q/2KV, SWA [L,L,L,G]x13 W=2048, RoPE 500k, 131072 max (262144 extended per Unsloth)
#
# Purpose: 4th slot — think+vision highest ctx that fits 24GB on vanilla llama.cpp
#   (no beellama KVarN). This is the Unsloth-recommended llama.cpp path, now with first-party draft-dflash.
#   Use for full-model validation before Bee KVarN. Unsloth's minimal llama-server example is:
#     ./llama-server --model <UD-Q4_K_XL> --mmproj <mmproj-BF16> --temp 1.0 --top-p 0.95 --top-k 64
#   This harness adds pinning for deterministic server behavior on 3090 24GB.
#
# Tuning vs Unsloth guide + vs beellama highctx:
#   - Unsloth ships mmproj-BF16.gguf (3.84GB) in their `hf download --include "*mmproj-BF16*"` example for simplicity
#     on Mac unified memory. For 3090 VRAM we use mmproj-kquant.gguf (1.40GB) — saves 2.4GB VRAM,
#     critical to keep vision+draft+131K KV under 24GB. Same ViT-G/14.
#   - Upstream has NO kvarn/kvarn-swa/tail — use q4_0/q4_0 only. SWA still W=2048 but managed by upstream KV cache.
#     65536 ctx ~1.3 GB KV (q4_0) + 18.91 GB model/draft/mmproj ≈ 20.2 GB on 3090. 98304 (~2.0 GB KV, ~20.9 GB)
#     also fits — bump --ctx-size to 98304 to test upper bound, drop to 49152 if OOM. 131072 q4_0 would be ~2.6GB KV
#     → ~21.5 GB, tight — prefer Bee kvarn path for 131K.
#   - DFlash: Unsloth guide omits draft for brevity, but Glimmer ships dflash-kquant.gguf (5L block-16 SWA 2048, layers 1/13/25/37/49).
#     Harness adds --spec-type draft-dflash --spec-draft-model <glimmer> --spec-draft-ngl all --spec-draft-n-max 15 pinned
#     (upstream defaults 3 even with block-16, log showed n_max=3); keep -b 256 -ub 64 per AGENTS.md DFlash.
#   - Vision: --mmproj + --no-mmproj-offload (keep ViT on GPU; Unsloth example loads mmproj implicitly)
#   - Think: --reasoning on + preserve_thinking:true + system prompt `Reasoning strength: high` per card
#     (not just --reasoning flag). Unsloth: low/medium/high/xhigh controllable via system prompt.
#   - Sampling: temp 1.0 top_p 0.95 top_k 64 per Muse card & Unsloth (identical)
#   - Unsloth says "no need to set context length as llama.cpp automatically uses the exact amount required"
#     for llama-cli single-turn; for server we pin --ctx-size for KV reservation. Use --alias per Unsloth example.
. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Muse Glimmer 30B UD-Q4_K_XL + DFlash + Vision (65k, think ON, llama.cpp) — Unsloth" -ForegroundColor Green

$archCheck = Select-String -Path (Join-Path $RepoRoot "sources\llama.cpp\src\llama-arch.cpp") -Pattern "muse_glimmer" -Quiet -ErrorAction SilentlyContinue
if (-not $archCheck) { Write-Warning "muse_glimmer arch not found in sources/llama.cpp — pull to >=62bf73d (master) and rebuild llama.cpp." }
if (-not (Test-Path $Model["Muse-Glimmer-30B-UD-Q4_K_XL"])) { Write-Error "Missing Glimmer model at $($Model['Muse-Glimmer-30B-UD-Q4_K_XL']) — expected D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\Muse-Glimmer-30B-UD-Q4_K_XL.gguf"; exit 1 }
if (-not (Test-Path $Drafter["Glimmer-DFlash"])) { Write-Error "Missing Glimmer dflash at $($Drafter['Glimmer-DFlash'])"; exit 1 }
if (-not (Test-Path $MmprojLookup["Glimmer"])) { Write-Error "Missing Glimmer mmproj at $($MmprojLookup['Glimmer'])"; exit 1 }
if (-not (Test-Path (Get-ServerBinary -Build "llama.cpp"))) {
    Write-Error "llama.cpp binary missing at $(Get-ServerBinary -Build 'llama.cpp') — rebuild sources/llama.cpp/build/bin/llama-server.exe"
    exit 1
}

& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Muse-Glimmer-30B-UD-Q4_K_XL"] `
  --mmproj $MmprojLookup["Glimmer"] `
  --no-mmproj-offload `
  --alias "unsloth-Muse-Glimmer-30B-GGUF" `
  --spec-draft-model $Drafter["Glimmer-DFlash"] `
  --spec-type draft-dflash `
  --spec-draft-n-max 15 --spec-draft-ngl all `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 65536 `
  -b 256 -ub 64 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --load-mode mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on --reasoning-preserve `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0
