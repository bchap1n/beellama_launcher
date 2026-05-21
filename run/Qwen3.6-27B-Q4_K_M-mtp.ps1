# Qwen3.6-27B Q4_K_M + MTP — auto-detected multi-token prediction
# Uses unsloth MTP model + fork build; no explicit --spec-type needed

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + MTP (122k, standard)" -ForegroundColor Green
& (Get-ServerBinary -Build "fork") `
  -m $Model["Qwen3.6-27B-MTP-Q4_K_M"] `
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
