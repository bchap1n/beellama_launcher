# 131K ctx, think ON, unified
#
# Gemma 4 12B QAT (Unsloth) — think ON variant. Enables <|channel>thought for complex
# multi-step tasks. Same tuning as the base script with think toggled on.
#
# Unsloth model page: https://unsloth.ai/docs/models/gemma-4
# GGUF: https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF
#
# Architecture (estimated from 31B config — same Gemma 4 family):
#   ~36-48 layers, sliding-window + full-attention pattern, GQA with ~8-16 kv_heads
#   Native max_position_embeddings: 262144
#   QAT UD-Q4_K_XL weights on disk: 6.7 GB
#
# Architecture notes (vs Qwen):
#   - Thinking toggle: --reasoning on/off (same as Qwen)
#   - Thinking format: <|channel>thought blocks (different markup from deepseek)
#   - MTP: --spec-type draft-mtp (explicit flag needed for upstream llama.cpp)
#   - Sampling: Google defaults — temp 1.0, top-p 0.95, top-k 64 (no min-p)
#
# Tuning for single 3090 (24 GB @ 250 W):
#   - Context 131072 — comfortable; ~12.5 GB total, ~11.5 GB headroom
#   - q4_0 / q4_0 KV — consensus choice. q8_0 costs +1.8 GB / -25% throughput.
#   - b 2048 / ub 512 — roomy batches
#   - --spec-draft-n-max 2 (MTP sweet spot; 3× speedup per Unsloth)
#   - --model-draft points to BF16 MTP draft head
#   - No mmproj mounted by default (add for vision)
#   - Uses llama.cpp upstream binary; falls back to beellama if llama.cpp not built
#
# VRAM budget (24 GB):
#   weights (UD-Q4_K_XL):               ~6.7 GB
#   KV at 131072 (q4_0 K+V):            ~5.0 GB
#   MTP draft head + CUDA overhead:     ~0.5 GB
#   total:                              ~12.2 GB
#   headroom:                           ~11.8 GB

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Gemma 4 12B QAT UD-Q4_K_XL + MTP (131k, think ON, llama.cpp)" -ForegroundColor Green
$MtpDraft = Join-Path (Split-Path $Model["Gemma4-12B-UD-Q4_K_XL"]) "gemma-4-12B-it-BF16-MTP.gguf"
& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Gemma4-12B-UD-Q4_K_XL"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  --model-draft $MtpDraft `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  -ngl 99 `
  --ctx-size 131072 `
  -b 2048 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --jinja `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --temp 1.0 --top-p 0.95 --top-k 64
