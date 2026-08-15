# 128K ctx, q4_0 KV, b4096/ub512, think OFF, vision ON, dense, MTP (beellama)
#
# Qwen3.8-27B Q4_K_S (Unsloth GGUF) - Dense 27B, hybrid thinking, vision, 256K native ctx.
# Uses the SMALL Q4_K_S quant (15.0 GB) to make room for the vision projector.
#   Q4_K_S + mmproj-BF16 (0.89 GB) + q4_0 KV @ 128K (~5 GB) + ~0.5 overhead ~ 21.4 GB,
#   well under the 24 GB 3090/250W budget. (128K vision was infeasible on Q4_K_M.)
# MTP head ships inside the GGUF, so --spec-type draft-mtp enables it (no draft model):
#   --spec-type draft-mtp --spec-draft-n-max 2 (+33% decode, acceptance 0.76-0.80).
# think OFF + vision ON: --mmproj Qwen38-BF16, --reasoning off, non-thinking sample
#   params per unsloth card (temp 0.7, top-p 0.80, top-k 20, min-p 0.0,
#   presence-penalty 1.5, repetition-penalty 1.0).
# Sources: https://unsloth.ai/docs/models/qwen3.8 | https://github.com/sudoingX/qwen38-mtp

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.8-27B Q4_K_S + MTP beellama (128k, think OFF, vision ON)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.8-27B-Q4_K_S"] `
  --mmproj $MmprojLookup["Qwen38-BF16"] `
  --no-mmproj-offload `
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
