# Qwen3.6-27B Q4_K_S + MTP — lighter VRAM, MTP, reasoning ON
# Uses unsloth MTP model (Q4_K_S quant) + fork build

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_S + MTP (122k, reasoning)" -ForegroundColor Green
& (Get-ServerBinary -Build "fork") `
  -m $Model["Qwen3.6-27B-MTP-Q4_K_S"] `
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
  --reasoning on `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 0.6 --top-k 20 --min-p 0.0
