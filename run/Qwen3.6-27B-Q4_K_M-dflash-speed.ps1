# 131K ctx, turbo4 KV, b256/ub64, think OFF, dense, vision ON, greedy draft

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + DFlash IQ4_XS (131k, speed)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.6-27B-Q4_K_M"] `
  --mmproj $MmprojLookup["Unsloth-F32"] `
  --no-mmproj-offload `
  --spec-draft-model $Drafter["DFlash-IQ4_XS"] `
  --spec-type dflash `
  --spec-dflash-cross-ctx 256 `
  --spec-draft-ngl all `
  --spec-draft-temp 0 `
  --no-spec-dm-adaptive `
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
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0
