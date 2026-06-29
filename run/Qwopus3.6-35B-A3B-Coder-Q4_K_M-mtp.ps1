# 64K ctx (YaRN scaling; card recommends 32K native), q4_0 KV, think OFF, temp 0.6, MTP
#
# Per model card: fine-tune target / recommended native = 32K tokens.
# We are using 64K max (with YaRN). Do not go higher than 64K.
#
# Qwopus3.6-35B-A3B-Coder (Jackrong) — MoE agentic coding fine-tune, thinking-off focused.
# 35B total / ~3B active params per token. MTP for speculative decoding.
# Optimized for execution efficiency in agent workflows: fast tool decisions,
# lower token waste, stable multi-turn coding/debugging.
# SWE-bench ~62.4% in thinking-off mode (Q5_K_M reference).
#
# Model card: https://huggingface.co/Jackrong/Qwopus3.6-35B-A3B-Coder-MTP-GGUF
#
# Tuning sources:
#   club-3090 style for MoE A3B MTP, user reports for 35B-A3B on 3090-class cards.
#   Examples from community: n-max 2 for A3B MTP, high ngl with partial expert offload.
#
#   - MTP: --spec-type draft-mtp, n-max 2 (common for this MoE; test 4 if stable)
#   - --spec-draft-p-min 0.75 (prevents collapse on long outputs)
#   - q4_0 KV for VRAM efficiency on quantized MoE
#   - For MoE on single 24GB: -ngl all --n-cpu-moe 25 (tune down if fits fully on GPU)
#   - b 4096 / ub 512 pattern from prior MTP (or 2048/1024 for MoE throughput)
#   - Reasoning OFF (core design: thinking-off agent)
#   - temp 0.6 for coding determinism
#   - Uses beellama binary for MTP support
#   - Context capped at 64K (YaRN scaling applied; card fine-tune target = 32K)
#
# VRAM budget estimate (24 GB @ 250 W, Q4_K_M):
#   weights (MoE Q4): ~16-18 GB (3B active dominant)
#   KV at 64K (q4_0): ~2-3 GB
#   MTP + overhead: ~1 GB
#   total: ~20-22 GB (tight; tune n-cpu-moe as needed)
#   Adjust n-cpu-moe if VRAM tight.

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus3.6-35B-A3B-Coder Q4_K_M + MTP (64k, think OFF)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwopus3.6-35B-A3B-Coder-Q4_K_M"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  --spec-draft-p-min 0.75 `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --n-cpu-moe 25 `
  --ctx-size 65536 `
  --rope-scaling yarn `
  --rope-scale 2 `
  --yarn-orig-ctx 32768 `
  -b 4096 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --no-mmap --mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.6 --top-p 0.95 --min-p 0.0
