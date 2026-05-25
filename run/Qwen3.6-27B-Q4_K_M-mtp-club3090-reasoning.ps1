# Qwen3.6-27B Q4_K_M + MTP + reasoning — club-3090 tuned: 200K ctx, q4_0 KV, -ub 512
#
# Same as mtp-club3090.ps1 with reasoning ON.
# Club-3090 note: for reasoning workloads, tune MTP deeper (--spec-draft-n-max 5) since
# thinking text drafts well. Default n=2 kept here; override via env or edit.

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + MTP + reasoning (club-3090 200K, q4_0 KV)" -ForegroundColor Green
& (Get-ServerBinary -Build "beellama_fork") `
  -m $Model["Qwen3.6-27B-MTP-Q4_K_M"] `
  --mmproj $MmprojLookup["Unsloth-F32"] `
  --no-mmproj-offload `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  --spec-draft-n-max 2 `
  -ngl all `
  --ctx-size 200000 `
  -b 4096 -ub 512 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --reasoning-format deepseek `
  --no-mmap --mlock `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 0.6 --top-k 20 --min-p 0.0
