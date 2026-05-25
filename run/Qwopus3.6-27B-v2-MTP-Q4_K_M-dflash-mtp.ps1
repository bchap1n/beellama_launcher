# Qwopus3.6-27B-v2 Q4_K_M + DFlash on MTP — 131k context, reasoning OFF, no mmproj
param(
    [ValidateSet("IQ4_XS","Q4_K_M","Q5_K_M")]
    [string]$DrafterQuant = "Q4_K_M"
)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus3.6-27B-v2 Q4_K_M + DFlash (131k, standard)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama_fork") `
  -m $Model["Qwopus3.6-27B-v2-MTP-Q4_K_M"] `
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
  --temp 1.0 --top-p 0.95 --min-p 0.0
