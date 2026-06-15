# 131K ctx, turbo4 KV, b256/ub64, think ON
param(
    [ValidateSet("IQ4_XS","Q4_K_M")]
    [string]$DrafterQuant = "IQ4_XS"
)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + DFlash (131k, think)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.6-27B-Q4_K_M"] `
  --spec-draft-model $Drafter["DFlash-$DrafterQuant"] `
  --spec-type dflash `
  --spec-dflash-cross-ctx 256 `
  --spec-draft-ngl all `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 131072 `
  -b 256 -ub 64 `
  --cache-type-k turbo4 --cache-type-v turbo4 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0

