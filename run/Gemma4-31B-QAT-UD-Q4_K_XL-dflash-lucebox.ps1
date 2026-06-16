# Source: lucebox
# 256K ctx, q4_0 KV, DFlash DDTree, KVFlash, dense
#
# LuceBox dflash_server with native Gemma 4 backend + LuceBox DFlash draft.
# KVFlash pages cold KV to host RAM — GPU pool stays ~72 MB regardless of context.
# Full-attention layers are pooled; SWA rings (50 of 60 layers) untouched.
#
# DFlash draft: Lucebox/gemma-4-31B-it-DFlash-GGUF (Q8_0, 1.63 GB)
#
# Tuning:
#   - Context 262144 — KVFlash makes GPU KV near-constant, so 256K costs almost nothing extra
#   - KVFlash: --kvflash auto (auto-sizes GPU pool from free VRAM)
#   - DFlash DDTree spec decode (--ddtree)
#   - Port 8082, host 127.0.0.1
#
# VRAM budget (24 GB):
#   weights (UD-Q4_K_XL):              ~17.3 GB
#   DFlash draft (Q8_0):                ~1.6 GB
#   KVFlash pool (auto):                 ~0.1 GB
#   CUDA overhead:                      ~1.0 GB
#   total:                              ~20.0 GB
#   headroom:                            ~4.0 GB

. "$PSScriptRoot\beellama_common.ps1"

$LuceBoxBinary = Join-Path $RepoRoot "sources\lucebox-hub\server\build\dflash_server.exe"
if (-not (Test-Path $LuceBoxBinary)) {
    Write-Error "LuceBox binary not found: $LuceBoxBinary"
    exit 1
}

Write-Host "Launching: Gemma 4 31B QAT + LuceBox + KVFlash (256k, think OFF, port 8082)" -ForegroundColor Green
& $LuceBoxBinary `
  $Model["Gemma4-31B-QAT-UD-Q4_K_XL"] `
  --draft $Drafter["LuceBox-Gemma4-31B-DFlash"] `
  --ddtree `
  --port 8082 --host 127.0.0.1 `
  --max-ctx 262144 `
  --kvflash auto `
  --fa-window 1024 `
  --model-name "gemma4-31b-qat-lucebox" `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --default-max-tokens 16000
