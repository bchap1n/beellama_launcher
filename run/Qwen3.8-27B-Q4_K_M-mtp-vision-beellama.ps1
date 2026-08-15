# 64K ctx, q4_0 KV, b4096/ub512, think OFF, vision ON, dense, MTP (beellama)
#
# Qwen3.8-27B (Unsloth GGUF) - Dense 27B, hybrid thinking, vision, 256K native ctx.
# MTP head ships inside the GGUF (no separate draft model), so --spec-type draft-mtp enables it.
# Using the sudoingX/qwen38-mtp tuned launch (measured on RTX 3090 24GB):
#   --spec-type draft-mtp --spec-draft-n-max 2  (+33% decode, acceptance 0.76-0.80)
# VISION ON: --mmproj mmproj-BF16 (Qwen38-BF16). mmproj + vision activations add
#   ~1.5-2 GB VRAM, so ctx trimmed from 128K to 64K (q4_0 KV) to hold peak under
#   24 GB on the 3090/250W: ~16 GB model + ~1.8 GB mmproj + ~2.5 GB KV + 0.5 overhead ~ 20.8 GB.
#   Do NOT raise -c back to 128K with vision on (that measured 23.0 GB vision-off).
# think OFF: --reasoning off + non-thinking sample params per unsloth model card
#   (temp 0.7, top-p 0.80, top-k 20, min-p 0.0, presence-penalty 1.5, repetition-penalty 1.0).
# Sources: https://unsloth.ai/docs/models/qwen3.8 | https://github.com/sudoingX/qwen38-mtp

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.8-27B Q4_K_M + MTP beellama (64k, think OFF, vision ON)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.8-27B-Q4_K_M"] `
  --mmproj $MmprojLookup["Qwen38-BF16"] `
  --no-mmproj-offload `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  -ngl all `
  --ctx-size 65536 `
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
