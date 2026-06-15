# 256K ctx, think OFF, unified
#
# Gemma 4 12B QAT (Unsloth) — max-context variant. Architectural limit: 262144.
# Sliding-window arch means only ~6 of 48 layers grow with context. At 256K q4_0 KV
# is ~4.7 GB, total ~12.3 GB — fits with ~11.7 GB headroom on 24 GB.
#
# Unsloth model page: https://unsloth.ai/docs/models/gemma-4
# GGUF: https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF
#
# Architecture: 48 layers, sliding-window (1024) + full-attention interleaved,
#   max_position_embeddings: 262144. QAT UD-Q4_K_XL weights: 6.7 GB.
#
# Tuning for single 3090 (24 GB @ 250 W):
#   - Context 262144 — architectural max. Sliding layers fixed at 1024 tokens each.
#     Only ~6 full-attention layers grow, keeping KV modest even at 256K.
#   - q4_0 / q4_0 KV — required at this context
#   - b 2048 / ub 512 — unchanged from base tuning
#   - --spec-draft-n-max 2 (MTP sweet spot; 3× speedup per Unsloth)
#   - --model-draft points to BF16 MTP draft head
#   - No mmproj — would add ~1 GB, still fits but not needed for text
#   - Uses llama.cpp upstream binary; falls back to beellama if llama.cpp not built
#
# VRAM budget (24 GB):
#   weights (UD-Q4_K_XL):               ~6.7 GB
#   KV at 262144 (q4_0 K+V):            ~4.7 GB
#   MTP BF16 draft + CUDA overhead:     ~0.9 GB
#   total:                              ~12.3 GB
#   headroom:                           ~11.7 GB

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Gemma 4 12B QAT UD-Q4_K_XL + MTP (256k, think OFF, llama.cpp)" -ForegroundColor Green
$MtpDraft = Join-Path (Split-Path $Model["Gemma4-12B-UD-Q4_K_XL"]) "gemma-4-12B-it-BF16-MTP.gguf"
& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Gemma4-12B-UD-Q4_K_XL"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  --model-draft $MtpDraft `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  -ngl 99 `
  --ctx-size 262144 `
  -b 2048 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --jinja `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --temp 1.0 --top-p 0.95 --top-k 64
