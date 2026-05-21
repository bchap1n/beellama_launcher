# Qwen3.6-27B Q5_K_S — no speculative decoding
# Uses unsloth Q5_K_S model without DFlash or MTP
# Best for: Q5 quality without speculation overhead

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q5_K_S (122k, no speculation)" -ForegroundColor Green
& (Get-ServerBinary -Build "fork") `
  -m $Model["Qwen3.6-27B-Q5_K_S"] `
  --mmproj $MmprojLookup["Unsloth-F32"] `
  --no-mmproj-offload `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 122800 `
  -b 2048 -ub 256 `
  --cache-type-k turbo4 --cache-type-v turbo3_tcq `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.6 --top-k 20 --min-p 0.0
