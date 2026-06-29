# 64K ctx, q4_0 KV, deepseek think, temp 1.0, dense
#
# Qwopus3.6-27B-Coder-Compat (Jackrong) — agentic coding fine-tune via Claude Opus Trace Inversion.
# think ON variant: enables <think> chain-of-thought for complex multi-step design, SVG
# generation, and architecture work. Higher quality but slower decode.
# Weight-identical + improved chat template.
#
# Model card: https://huggingface.co/Jackrong/Qwopus3.6-27B-Coder-Compat-MTP-GGUF
#
# Note from model card: "Thinking ON and temp high, 0.9-1 good design and SVG results, but slower."
# For deterministic coding with think OFF, use the non-think variant of this script.
#
# Tuning sources:
#   club-3090 (noonghunna):  https://github.com/noonghunna/club-3090 — 3090 MTP production config
#   Ian Paterson (3090 Ti):  https://dev.to/ianlpaterson/three-months-of-speed-up-experiments-on-a-3090-ti
#
#   - MTP auto-detected from model architecture (no --spec-type needed)
#   - --spec-draft-n-max 6 (club-3090 "sweet spot" for Qwen MTP)
#   - --spec-draft-p-min 0.75 (Ian Paterson: critical — prevents MTP decode collapse on long outputs)
#   - q4_0 / q4_0 KV — consensus from both sources. Ian: q8_0 costs +1.8 GB / -25% throughput.
#     Club-3090: q4_0 is the 200K-verified path.
#   - b 4096 / ub 512 — club-3090 MTP defaults. -b doesn't drive VRAM (llama.cpp upstream property);
#     -ub 512 is the max-safe single-card value for activation-peak survival at high fill.
#   - 65536 context — safe and comfortable for 250 W 3090. Club-3090 runs 200K on 370 W cards.
#   - Added YaRN: --rope-scaling yarn --rope-scale 2 --yarn-orig-ctx 32768 for >32K ctx (per model card)
#   - think ON (deepseek format, preserve_thinking:true)
#   - temp 1.0 — higher temp for creative/design think tasks per model card guidance
#   - Uses beellama binary (beellama.cpp main build)
#
# VRAM budget (24 GB @ 250 W):
#   weights (Q4_K_M):              ~16.8 GB
#   KV at 64K (q4_0 K+V):           ~2.5 GB
#   MTP draft head + overhead:      ~0.5 GB
#   total:                          ~19.8 GB
#   headroom:                        ~4.2 GB

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus3.6-27B-Coder Q4_K_M + MTP (64k, think ON)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwopus3.6-27B-Coder-Q4_K_M"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 6 `
  --spec-draft-p-min 0.75 `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
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
  --reasoning on `
  --reasoning-loop-guard force-close `
  --reasoning-format deepseek `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 1.0 --top-p 0.95 --min-p 0.0
