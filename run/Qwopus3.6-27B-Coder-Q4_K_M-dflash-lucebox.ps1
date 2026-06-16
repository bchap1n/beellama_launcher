# 131K ctx, TQ3 KV, DDTree 22, SWA 2048, fa-win 0, think OFF
# Source: lucebox
# Target: jackrong/Qwopus3.6-27B-Coder-Q4_K_M (non-MTP, DeltaNet, block_count=65)
# Draft:  Lucebox/Qwen3.6-27B-DFlash-GGUF (dflash-draft-3.6-q4_k_m.gguf)
#
# Qwopus is an agentic coding fine-tune (Claude Opus trace inversion). Same
# qwen35 arch as Qwen3.6, so the same LuceBox drafter and flags work.
# 47-68 tok/s, 25-32% DFlash acceptance. Patched loader for block_count=65.

. "$PSScriptRoot\beellama_common.ps1"

$LuceBoxBinary = Join-Path $RepoRoot "sources\lucebox-hub\server\build\dflash_server.exe"
if (-not (Test-Path $LuceBoxBinary)) {
    Write-Error "LuceBox binary not found: $LuceBoxBinary"
    exit 1
}

$env:DFLASH27B_KV_TQ3 = "1"

Write-Host "Launching: Qwopus Coder + LuceBox DFlash (131k, TQ3 KV, port 8080)" -ForegroundColor Green
& $LuceBoxBinary `
  $Model["Qwopus3.6-27B-Coder-Q4_K_M-DeltaNet"] `
  --draft $Drafter["LuceBox-Qwen-DFlash"] `
  --ddtree --ddtree-budget 22 `
  --fa-window 0 `
  --draft-swa 2048 `
  --port 8080 --host 0.0.0.0 `
  --max-ctx 131072 `
  --chunk 512 `
  --model-name "qwopus-coder-dflash" `
  --think-max-tokens 15488 `
  --default-max-tokens 16000 `
  --hard-limit-reply-budget 4096
