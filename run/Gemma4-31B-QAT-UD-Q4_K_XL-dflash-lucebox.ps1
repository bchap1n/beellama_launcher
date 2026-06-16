# 256K ctx, q4_0 KV, KVFlash auto, DDTree, fa-win 1024, think OFF
# Source: lucebox
# Target: unsloth/gemma-4-31B-it-qat-GGUF (UD-Q4_K_XL, dense)
# Draft:  Lucebox/gemma-4-31B-it-DFlash-GGUF (Q8_0, 1.63 GB)
#
# KVFlash pages cold KV to host RAM — GPU pool ~72 MB regardless of context.
# Full-attention layers pooled; SWA rings (50 of 60 layers) untouched.
# VRAM: ~17.3 GB weights + ~1.6 GB draft + ~0.1 GB KVFlash + ~1 GB overhead
#       ≈ 20 GB total on 24 GB card.
#   - Port 8081, host 127.0.0.1

. "$PSScriptRoot\beellama_common.ps1"

$LuceBoxBinary = Join-Path $RepoRoot "sources\lucebox-hub\server\build\dflash_server.exe"
if (-not (Test-Path $LuceBoxBinary)) {
    Write-Error "LuceBox binary not found: $LuceBoxBinary"
    exit 1
}

Write-Host "Launching: Gemma 4 31B QAT + LuceBox + KVFlash (256k, think OFF, port 8081)" -ForegroundColor Green
& $LuceBoxBinary `
  $Model["Gemma4-31B-QAT-UD-Q4_K_XL"] `
  --draft $Drafter["LuceBox-Gemma4-31B-DFlash"] `
  --ddtree `
  --port 8081 --host 127.0.0.1 `
  --max-ctx 262144 `
  --kvflash auto `
  --fa-window 1024 `
  --model-name "gemma4-31b-qat-lucebox" `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --default-max-tokens 16000
