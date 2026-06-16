# 131K ctx, q4_0 KV, think OFF, temp 0.6
#
# Qwopus3.6-27B-Coder (Jackrong) — agentic coding fine-tune via Claude Opus Trace Inversion.
# Scored 67% on SWE-bench verified (full 500) with think disabled at Q5_K_M on 5090.
# Native 32K context; beyond that uses YaRN rope scaling (same base architecture as Qwen3.6).
#
# Model card: https://huggingface.co/Jackrong/Qwopus3.6-27B-Coder-MTP-GGUF
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
#     At 131K ctx this is safe; higher ctx would need -ub lower (club-3090: -ub 1024 at 131K,
#     -ub 512 at 200K). Ian's -ub 256 at 131K is also valid (+186 MiB vs defaults).
#   - Reasoning OFF — this model was validated at 67% SWE-bench with think disabled
#   - temp 0.6 — conservative for deterministic coding; raise to 0.9-1.0 for design tasks
#   - Uses beellama binary (beellama.cpp main build)
#
# VRAM budget (24 GB @ 250 W):
#   weights (Q4_K_M):              ~16.8 GB
#   KV at 131K (q4_0 K+V):          ~5.0 GB
#   MTP draft head + overhead:      ~0.5 GB
#   total:                          ~22.3 GB
#   headroom:                        ~1.7 GB

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus3.6-27B-Coder Q4_K_M + MTP (131k, think OFF)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwopus3.6-27B-Coder-Q4_K_M"] `
  --spec-type draft-mtp `
  --spec-draft-n-max 6 `
  --spec-draft-p-min 0.75 `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 131072 `
  -b 4096 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.6 --top-p 0.95 --min-p 0.0
