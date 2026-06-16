# Qwen3.6-27B Q4_K_M via LuceBox — matches LuceBox README defaults
# Target: unsloth/Qwen3.6-27B-GGUF (non-MTP, DeltaNet layers)
# Draft:  Lucebox/Qwen3.6-27B-DFlash-GGUF (dflash-draft-3.6-q4_k_m.gguf)
#
# README reference (RTX 3090 defaults):
#   DFLASH27B_KV_TQ3=1
#   --ddtree --ddtree-budget 22 --fa-window 2048
#
# Tuning:
#   - DFlash DDTree spec decode (--ddtree)
#   - TQ3_0 KV cache (default when DFLASH27B_KV_TQ3=1 and ctx > 6144)
#   - Context 131072 — safe for 16.8 GB weights + 1.0 GB drafter on 24 GB
#   - Port 8082, host 127.0.0.1

. "$PSScriptRoot\beellama_common.ps1"

$LuceBoxBinary = Join-Path $RepoRoot "sources\lucebox-hub\server\build\dflash_server.exe"
if (-not (Test-Path $LuceBoxBinary)) {
    Write-Error "LuceBox binary not found: $LuceBoxBinary"
    exit 1
}

$env:DFLASH27B_KV_TQ3 = "1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + LuceBox DFlash (131k, TQ3 KV, port 8082)" -ForegroundColor Green
& $LuceBoxBinary `
  $Model["Qwen3.6-27B-Q4_K_M-DeltaNet"] `
  --draft $Drafter["LuceBox-Qwen-DFlash"] `
  --ddtree --ddtree-budget 22 `
  --fa-window 2048 `
  --port 8082 --host 127.0.0.1 `
  --max-ctx 131072 `
  --chunk 512 `
  --model-name "Qwen3.6-27B" `
  --think-max-tokens 15488 `
  --default-max-tokens 16000 `
  --hard-limit-reply-budget 4096
