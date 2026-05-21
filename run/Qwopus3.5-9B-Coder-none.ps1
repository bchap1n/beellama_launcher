# Qwopus 3.5 9B Coder — no speculative decoding
# Lightweight model for code completion, no DFlash or MTP

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus 3.5 9B Coder (128k, no speculation)" -ForegroundColor Green
& (Get-ServerBinary -Build "original") `
  -m $Model["Qwopus3.5-9B-Coder"] `
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
