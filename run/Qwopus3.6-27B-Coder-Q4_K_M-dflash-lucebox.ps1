# 256K ctx, TQ3 KV, KVFlash auto, chain, SWA 2048, fa-win 2048, think OFF, dense
# Source: lucebox
# Target: jackrong/Qwopus3.6-27B-Coder-Compat-MTP (replaced old non-MTP with Compat-MTP)
# Draft:  Lucebox/Qwen3.6-27B-DFlash-GGUF (dflash-draft-3.6-q4_k_m.gguf)
#
# Qwopus is an agentic coding fine-tune (Claude Opus trace inversion). Now using Compat-MTP version.
# 47-68 tok/s, 25-32% DFlash acceptance.

. "$PSScriptRoot\beellama_common.ps1"

$LuceBoxBinary = Join-Path $RepoRoot "sources\lucebox-hub\server\build\dflash_server.exe"
if (-not (Test-Path $LuceBoxBinary)) {
    Write-Error "LuceBox binary not found: $LuceBoxBinary"
    exit 1
}

$env:DFLASH27B_KV_TQ3 = "1"

Write-Host "Launching: Qwopus Coder + LuceBox DFlash + KVFlash (256k, chain, port 8080)" -ForegroundColor Green
& $LuceBoxBinary `
  $Model["Qwopus3.6-27B-Coder-Q4_K_M-DeltaNet"] `
  --draft $Drafter["LuceBox-Qwen-DFlash"] `
  --fa-window 2048 `
  --draft-swa 2048 `
  --port 8080 --host 0.0.0.0 `
  --max-ctx 262144 `
  --kvflash auto --kvflash-policy qk `
  --prefill-drafter $Drafter["LuceBox-Qwen-DFlash"] `
  --chunk 512 `
  --model-name "qwopus-coder-dflash" `
  --think-max-tokens 15488 `
  --default-max-tokens 16000 `
  --hard-limit-reply-budget 4096
