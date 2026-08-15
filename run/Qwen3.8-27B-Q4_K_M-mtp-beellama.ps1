# 128K ctx, q4_0 KV, b4096/ub512, think OFF, vision OFF, dense, MTP (beellama)
#
# Qwen3.8-27B (Unsloth GGUF) — today's release. Dense 27B, hybrid thinking, vision, 256K native ctx.
# MTP head ships inside the GGUF (no separate draft model), so --spec-type draft-mtp enables it.
# Using the sudoingX/qwen38-mtp tuned launch (measured on RTX 3090 24GB):
#   --spec-type draft-mtp --spec-draft-n-max 2  (+33% decode, acceptance 0.76-0.80)
# Context kept at 128K / q4_0 KV. Measured 128K resident = 23.0 GB (beellama) / 23.6 GB (llama.cpp)
# on the 24 GB 3090 — only ~1 GB margin, so do NOT raise -c past 128K or add vision without trimming.
# think OFF + vision OFF: no mmproj, --reasoning off, non-thinking sample params per unsloth model card
#   (temp 0.7, top-p 0.80, top-k 20, min-p 0.0, presence-penalty 1.5, repetition-penalty 1.0).
# Sources: https://unsloth.ai/docs/models/qwen3.8 | https://github.com/sudoingX/qwen38-mtp

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.8-27B Q4_K_M + MTP beellama (128k, think OFF, vision OFF)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.8-27B-Q4_K_M"] `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  -ngl all `
  --ctx-size 131072 `
  -b 4096 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --load-mode mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 `
  --presence-penalty 1.5 --repeat-penalty 1.0
