# 128K ctx, kvarn4/kvarn3 KV, b2048/ub256, think ON, reasoning model
# Source: beellama.cpp (turbo KV types not available in upstream llama.cpp)
# Target: Ornith-1.0-35B Q4_K_M (Qwen3.5 MoE, 40L, 256 experts/8 active)
# Model:  deepreinforce-ai/Ornith-1.0-35B-GGUF
#
# Tuning:
#   - Reasoning ON: model emits <think>...</think> blocks (core to its agentic coding performance)
#   - preserve_thinking:true keeps reasoning trace in the response
#   - No speculative decoding (no draft model available for this architecture)
#   - VRAM budget: ~20.5 GB model + 500 MB overhead + ~3.5 GB KV cache (kvarn4/kvarn3 at 128K)
#     ≈ 24.5 GB on 24 GB 3090 — tight. If OOM at peak fill, add --n-cpu-moe 2-4.
#   - kvarn4 K / kvarn3 V per house 128K pattern (pi-tune, pi-reasoning, ThinkingCap).
#   - b2048/ub256 per Unsloth/none recommendation (CLAUDE.md) — was b256/ub64 (DFlash pattern), now corrected
#   - Sampling per model card: temp 0.6, top_p 0.95, top_k 20
#   - Flash attention ON (CUDA FA enabled at build time)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Ornith-1.0-35B Q4_K_M (128k, think ON, reasoning, beellama)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Ornith-1.0-35B-Q4_K_M"] `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 128000 `
  -b 2048 -ub 256 `
  --cache-type-k kvarn4 --cache-type-v kvarn3 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --load-mode mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0
