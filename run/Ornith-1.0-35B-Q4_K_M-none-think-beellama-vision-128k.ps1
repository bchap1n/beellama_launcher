# 128K ctx, kvarn4/kvarn3 KV, b1024/ub256, think ON, reasoning model, vision ON
# Source: beellama.cpp (fork)
# Target: Ornith-1.0-35B Q4_K_M (Qwen3.5 MoE, 40L, 256 experts/8 active)
# Model:  deepreinforce-ai/Ornith-1.0-35B-GGUF
#
# Tuning:
#   - Reasoning ON: model emits <think>...</think> blocks (core to its agentic coding performance)
#   - preserve_thinking:true keeps reasoning trace in the response
#   - No speculative decoding (no draft model available for this architecture)
#   - Using beellama.cpp backend to match the fork used by the Qwopus 35B-A3B MTP script
#   - Vision: mmproj enabled (add ~1-2 GB VRAM for projector + activations)
#   - VRAM budget: ~20.5 GB model + ~1.5 GB mmproj + 500 MB overhead + ~3.5 GB KV cache (kvarn4/kvarn3 at 128K)
#     ≈ 26.0 GB — exceeds 24 GB. --n-cpu-moe 6 offloads 6 MoE layers (~2.0 GB),
#     bringing GPU total to ~24.0 GB. Tune --n-cpu-moe up if OOM at peak fill.
#   - b1024/ub256 — b is conservative (1024 not 2048) for VRAM headroom with mmproj loaded
#   - Sampling per model card: temp 0.6, top_p 0.95, top_k 20
#   - Flash attention ON (CUDA FA enabled at build time)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Ornith-1.0-35B Q4_K_M (128k, think ON, reasoning, beellama, vision)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Ornith-1.0-35B-Q4_K_M"] `
  --mmproj $MmprojLookup["Ornith-bf16"] `
  --no-mmproj-offload `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --n-cpu-moe 6 `
  --ctx-size 128000 `
  -b 1024 -ub 256 `
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
