# 256K ctx (max), turbo4 K / turbo3_tcq V, b4096/ub512, think OFF, vision OFF, dense, MTP (beellama)
#
# Qwen3.8-27B (Unsloth GGUF) - Dense 27B, hybrid thinking, vision, 256K native ctx.
# MAX CONTEXT = 256K (the model's native limit). To fit 256K on the 24 GB 3090/250W,
# q4_0 KV is infeasible (~10 GB -> ~28 GB total), so use the beellama turbo KV house
#   pattern: --cache-type-k turbo4 --cache-type-v turbo3_tcq (~3.5 GB per 128K ->
#   ~7 GB at 256K). Est. peake: ~16 GB model + ~7 GB KV + 0.5 overhead ~ 23.5 GB.
#   Tight: do NOT also enable vision or raise -b past 4096 here.
# MTP head ships inside the GGUF, so --spec-type draft-mtp enables it (no draft model):
#   --spec-type draft-mtp --spec-draft-n-max 2 (+33% decode, acceptance 0.76-0.80).
# think OFF + vision OFF (no mmproj): --reasoning off, non-thinking sample params.
#   (temp 0.7, top-p 0.80, top-k 20, min-p 0.0, presence-penalty 1.5, repetition-penalty 1.0).
# Sources: https://unsloth.ai/docs/models/qwen3.8 | https://github.com/sudoingX/qwen38-mtp

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.8-27B Q4_K_M + MTP beellama (256k MAX, think OFF, vision OFF, turbo KV)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.8-27B-Q4_K_M"] `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  -ngl all `
  --ctx-size 262144 `
  -b 4096 -ub 512 `
  --cache-type-k turbo4 --cache-type-v turbo3_tcq `
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
