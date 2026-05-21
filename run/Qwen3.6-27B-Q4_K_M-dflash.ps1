# Qwen3.6-27B Q4_K_M + DFlash - 131k context, reasoning OFF
# Best for: balanced throughput, 3090-optimized (Ardenzard tuning)
param(
    [ValidateSet("IQ4_XS","Q4_K_M","Q5_K_M")]
    [string]$DrafterQuant = "IQ4_XS"
)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + DFlash (131k, standard)" -ForegroundColor Green
& (Get-ServerBinary -Build "original") `
  -m $Model["Qwen3.6-27B-Q4_K_M"] `
  --mmproj $MmprojLookup["LmStudio-BF16"] `
  --no-mmproj-offload `
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
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
