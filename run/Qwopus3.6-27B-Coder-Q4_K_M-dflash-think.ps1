# 64K ctx, turbo4 KV, b256/ub64, think ON, temp 1.0, dense

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwopus3.6-27B-Coder Q4_K_M + DFlash IQ4_XS (64k, think ON)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwopus3.6-27B-Coder-Q4_K_M"] `
  --spec-draft-model $Drafter["DFlash-IQ4_XS"] `
  --spec-type dflash `
  --spec-dflash-cross-ctx 256 `
  --spec-draft-ngl all `
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
  --reasoning-loop-guard force-close `
  --no-warmup `
  --reasoning-format deepseek `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 1.0 --top-p 0.95 --min-p 0.0
