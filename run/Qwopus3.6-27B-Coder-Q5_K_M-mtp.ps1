# 64K ctx, q4_0 KV, think OFF, temp 0.6, dense
#
# Qwopus3.6-27B-Coder-Compat (Jackrong) — agentic coding fine-tune via Claude Opus Trace Inversion.
# Weight-identical to non-Compat + improved chat template for tool calling.
# Scored 67% on SWE-bench verified (full 500) with think disabled at Q5_K_M on 5090.
# Native 32K context; beyond that uses YaRN rope scaling (added below).
#
# Model card: https://huggingface.co/Jackrong/Qwopus3.6-27B-Coder-Compat-MTP-GGUF
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
#     At 64K ctx this is very safe (lower ctx reduces activation peaks). Ian's -ub 256 is also valid.
#   - Added YaRN: --rope-scaling yarn --rope-scale 2 --yarn-orig-ctx 32768 for >32K ctx (per model card)
#   - Reasoning OFF — this model was validated at 67% SWE-bench with think disabled
#   - temp 0.6 — conservative for deterministic coding; raise to 0.9-1.0 for design tasks
#   - Uses beellama binary (beellama.cpp main build)
#
# VRAM budget (24 GB @ 250 W):
#   weights (Q5_K_M):              ~19.0 GB
#   KV at 64K (q4_0 K+V):           ~2.5 GB
#   MTP draft head + overhead:      ~0.5 GB
#   total:                          ~22.0 GB
#   headroom:                        ~2.0 GB

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus3.6-27B-Coder Q5_K_M + MTP (64k, think OFF)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwopus3.6-27B-Coder-Q5_K_M"] `
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
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.6 --top-p 0.95 --min-p 0.0
