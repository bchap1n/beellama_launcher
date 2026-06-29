# 64K ctx, q4_0 KV, b256/ub64, think ON, reasoning model, vision ON
# Source: llama.cpp (upstream)
# Target: Ornith-1.0-35B Q4_K_M (Qwen3.5 MoE, 40L, 256 experts/8 active)
# Model:  deepreinforce-ai/Ornith-1.0-35B-GGUF
#
# Tuning:
#   - Reasoning ON: model emits <think>...</think> blocks (core to its agentic coding performance)
#   - preserve_thinking:true keeps reasoning trace in the response
#   - No speculative decoding (no draft model available for this architecture)
#   - VRAM budget: ~20.5 GB model + 500 MB overhead + ~2.5 GB KV cache ≈ 23.5 GB on 24 GB 3090
#   - 64K context with q4_0 KV leaves ~500 MB headroom
#   - Sampling per model card: temp 0.6, top_p 0.95, top_k 20
#   - Flash attention ON (CUDA FA enabled at build time)

. "$PSScriptRoot\beellama_common.ps1"

# Use env var to bypass PowerShell's native-command quote stripping
$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"preserve_thinking":true}'

Write-Host "Launching: Ornith-1.0-35B Q4_K_M (64k, think ON, reasoning)" -ForegroundColor Green
& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Ornith-1.0-35B-Q4_K_M"] `
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
  --no-mmap --mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0
