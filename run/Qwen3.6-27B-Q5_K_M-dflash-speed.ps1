# Qwen3.6-27B Q5_K_M + DFlash — 64k context, reasoning ON, greedy-draft
param(
    [ValidateSet("Q5_K_M")]
    [string]$DrafterQuant = "Q5_K_M"
)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q5_K_M + DFlash (64k, speed)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama_fork") `
  -m $Model["Qwen3.6-27B-Q5_K_M"] `
  --spec-draft-model $Drafter["DFlash-$DrafterQuant"] `
  --spec-type dflash `
  --spec-dflash-cross-ctx 256 `
  --spec-draft-ngl all `
  --spec-draft-temp 0 `
  --no-spec-dm-adaptive `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 65536 `
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
  --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
