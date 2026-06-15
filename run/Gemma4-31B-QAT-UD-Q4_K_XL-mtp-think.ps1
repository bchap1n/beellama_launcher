# 65K ctx, think ON, dense
#
# Gemma 4 31B QAT (Unsloth) — think ON variant. Enables <|channel>thought for complex
# multi-step tasks. Context kept at 65K due to 31B VRAM constraints.
#
# Unsloth model page: https://unsloth.ai/docs/models/gemma-4/qat
# GGUF: https://huggingface.co/unsloth/gemma-4-31B-it-qat-GGUF
#
# Architecture (from GGUF config.json):
#   60 layers: 50× sliding_attention (window=1024) + 10× full_attention
#   num_kv_heads=16, head_dim=256, global_kv_heads=4, global_head_dim=512
#   Native max_position_embeddings: 262144
#
#   The sliding window is the key to VRAM: 50 of 60 layers have KV fixed at 1024 tokens.
#   Only the 10 full-attention layers grow with context. At 65K:
#     Sliding layers (fixed):   0.2 GB
#     Full-attn layers (65K):   3.9 GB
#     Total KV (q4_0 K+V):     ~4.1 GB
#
# Architecture notes (vs Qwen):
#   - Thinking toggle: --reasoning on/off (same as Qwen)
#   - Thinking format: <|channel>thought blocks (different markup from deepseek)
#   - Sampling: Google defaults — temp 1.0, top-p 0.95, top-k 64 (no min-p)
#
# Tuning for single 3090 (24 GB @ 250 W):
#   - Context 65536 — sweet spot per sliding-window KV math. 81920 possible (~23.4 GB).
#     Kept at 65K for think (extra activation memory during think blocks).
#   - q4_0 / q4_0 KV — consensus choice.
#   - b 2048 / ub 512 — at 65K ctx with ~1.6 GB headroom
#   - No mmproj mounted (mmproj-F32.gguf is 2.3 GB — costs too much VRAM for text-only)
#   - Uses llama.cpp upstream binary; falls back to beellama if llama.cpp not built
#
# VRAM budget (24 GB):
#   weights (UD-Q4_K_XL):              ~17.3 GB
#   KV at 65536 (q4_0 K+V):             ~4.1 GB
#   MTP draft head + CUDA overhead:     ~1.0 GB
#   total:                              ~22.4 GB
#   headroom:                            ~1.6 GB

. "$PSScriptRoot\beellama_common.ps1"

$MtpDraft = Join-Path (Split-Path $Model["Gemma4-31B-QAT-UD-Q4_K_XL"]) "mtp-gemma-4-31B-it.gguf"
Write-Host "Launching: Gemma 4 31B QAT UD-Q4_K_XL + MTP (65k, think ON, llama.cpp)" -ForegroundColor Green
& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Gemma4-31B-QAT-UD-Q4_K_XL"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  --model-draft $MtpDraft `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  -ngl 99 `
  --ctx-size 65536 `
  -b 2048 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --jinja `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --temp 1.0 --top-p 0.95 --top-k 64
