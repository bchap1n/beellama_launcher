# 200K ctx, q4_0 KV, b4096/ub512, think ON, dense, vision ON, club-3090
#
# Same as mtp-club3090.ps1 with think ON.
# Club-3090 note: for think workloads, tune MTP deeper (--spec-draft-n-max 5) since
# think text drafts well. Default n=2 kept here; override via env or edit.

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + MTP + think (club-3090 200K, q4_0 KV)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama") `
  -m $Model["Qwen3.6-27B-Q4_K_M"] `
  --mmproj $MmprojLookup["Unsloth-F32"] `
  --no-mmproj-offload `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  --spec-type draft-mtp `
  --spec-draft-n-max 6 `
  -ngl all `
  --ctx-size 200000 `
  -b 4096 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --reasoning-format deepseek `
  --no-mmap --mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 0.6 --top-k 20 --min-p 0.0
