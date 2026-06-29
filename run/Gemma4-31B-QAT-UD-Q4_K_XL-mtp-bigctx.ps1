# 81K ctx, think OFF, b1024, dense, vision ON
#
# Gemma 4 31B QAT (Unsloth) — max-context variant. Pushes to 81920 on 24 GB.
# This is the VRAM ceiling for 31B: at 81K the full-attn KV reaches ~4.9 GB,
# total ~23.4 GB with ~0.6 GB headroom. Batch reduced to b1024 for margin.
#
# Unsloth model page: https://unsloth.ai/docs/models/gemma-4/qat
# GGUF: https://huggingface.co/unsloth/gemma-4-31B-it-qat-GGUF
#
#
# Tuning for single 3090 (24 GB @ 250 W):
#   - Context 81920 — max safe for 31B Q4_K_XL on 24 GB. 98304+ doesn't fit.
#   - q4_0 / q4_0 KV — required at this context; q8_0 would not fit
#   - b 1024 / ub 512 — reduced batch for VRAM margin at high context
#   - No mmproj mounted (mmproj-F32.gguf is 2.3 GB — would not fit)
#   - Uses llama.cpp upstream binary; falls back to beellama if llama.cpp not built
#
# VRAM budget (24 GB):
#   weights (UD-Q4_K_XL):              ~17.3 GB
#   KV at 81920 (q4_0 K+V):             ~5.1 GB
#   MTP draft head + CUDA overhead:     ~1.0 GB
#   total:                              ~23.4 GB
#   headroom:                            ~0.6 GB

. "$PSScriptRoot\beellama_common.ps1"

$MtpDraft = Join-Path (Split-Path $Model["Gemma4-31B-QAT-UD-Q4_K_XL"]) "mtp-gemma-4-31B-it.gguf"
Write-Host "Launching: Gemma 4 31B QAT UD-Q4_K_XL + MTP (81k, think OFF, llama.cpp)" -ForegroundColor Green
& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Gemma4-31B-QAT-UD-Q4_K_XL"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  --model-draft $MtpDraft `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  -ngl 99 `
  --ctx-size 81920 `
  -b 1024 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --jinja `
  --no-mmap --mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --temp 1.0 --top-p 0.95 --top-k 64
