# 192K ctx, turbo4 K / turbo3_tcq V, b4096/ub512, think OFF, vision OFF, dense, MTP (beellama)
#
# Qwen3.8-27B UD-Q4_K_XL (Unsloth GGUF) - Dense 27B, hybrid thinking, vision, 256K native ctx.
# LARGEST quant = Unsloth Dynamic 2.0 UD-Q4_K_XL (16.7 GB, flagship 4-bit, highest fidelity).
#   Chosen as the primary download per unsloth docs (--include "*UD-Q4_K_XL*").
# CONTEXT ADJUSTED TO LARGEST THAT FITS: 192K with turbo KV.
#   UD-Q4_K_XL + turbo KV @ 192K (~5.25 GB) + ~0.5 overhead ~ 22.4 GB on the 24 GB 3090.
#   (256K turbo ~ 24.2 GB is over budget; 192K is the largest safe step. Drop -b to 2048
#   or ~256K with a knife-edge if you accept OOM risk.)
# MTP head ships inside the GGUF, so --spec-type draft-mtp enables it (no draft model):
#   --spec-type draft-mtp --spec-draft-n-max 2 (+33% decode, acceptance 0.76-0.80).
# think OFF + vision OFF (no mmproj): --reasoning off, non-thinking sample params
#   per unsloth card (temp 0.7, top-p 0.80, top-k 20, min-p 0.0,
#   presence-penalty 1.5, repetition-penalty 1.0).
# Sources: https://unsloth.ai/docs/models/qwen3.8 | https://github.com/sudoingX/qwen38-mtp

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.8-27B UD-Q4_K_XL + MTP beellama (192k, think OFF, vision OFF, turbo KV)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.8-27B-UD-Q4_K_XL"] `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  --spec-type draft-mtp `
  --spec-draft-n-max 2 `
  -ngl all `
  --ctx-size 196608 `
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
