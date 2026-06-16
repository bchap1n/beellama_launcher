# Qwen3.6-27B via LuceBox — port 8080 variant (matches LuceBox README defaults)
# Target: unsloth/Qwen3.6-27B-GGUF (non-MTP, DeltaNet layers)
# Draft:  Lucebox/Qwen3.6-27B-DFlash-GGUF (dflash-draft-3.6-q4_k_m.gguf)
#
# This is the same config as Qwen3.6-27B-Q4_K_M-dflash-lucebox.ps1
# but on port 8080 (LuceBox default) for side-by-side with other servers.
#
# NOTE: Qwen3.6-27B + LuceBox DFlash is currently underperforming on our
# Windows build (~0.1 tok/s). Gemma4 31B works at 32 tok/s.

. "$PSScriptRoot\beellama_common.ps1"

$LuceBoxBinary = Join-Path $RepoRoot "sources\lucebox-hub\server\build\dflash_server.exe"
if (-not (Test-Path $LuceBoxBinary)) {
    Write-Error "LuceBox binary not found: $LuceBoxBinary"
    exit 1
}

$env:DFLASH27B_KV_TQ3 = "1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + LuceBox DFlash (131k, TQ3 KV, port 8080)" -ForegroundColor Green
& $LuceBoxBinary `
  $Model["Qwen3.6-27B-Q4_K_M-DeltaNet"] `
  --draft $Drafter["LuceBox-Qwen-DFlash"] `
  --ddtree --ddtree-budget 22 `
  --fa-window 2048 `
  --port 8080 --host 0.0.0.0 `
  --max-ctx 131072 `
  --chunk 512 `
  --model-name "Qwen3.6-27B" `
  --think-max-tokens 15488 `
  --default-max-tokens 16000 `
  --hard-limit-reply-budget 4096
