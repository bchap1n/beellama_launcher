# 200K ctx, q4_0 KV, b4096/ub512, think OFF, vision, club-3090
#
# Optimizations from club-3090 research (noonghunna/club-3090):
#   -ub 512        Smaller micro-batch avoids activation peaks at high fill (was -ub 256).
#                  Club-3090 verify-stress passes 7/7 incl. 91K needle at this setting.
#   -c 200000      200K max-safe default (fills ~183K with ~1.1 GB margin). 262144 boots
#                  but walls at ~125K (FA scratch at high fill). For faster prefill at
#                  lower ctx, use -c 131072 -ub 1024.
#   -b 4096        Larger batch for throughput; on mainline -b doesn't drive VRAM.
#                  Club-3090 default (was -b 2048).
#   --cache-type-k q4_0 --cache-type-v q4_0
#                  Dense 4-bit KV — Ampere-fast, max context. turbo4 is quality-favored;
#                  q4_0 is the club-3090 verified path for 200K survival.
#   --reasoning-format deepseek
#                  Prevents opencode/client hangs where reasoning_content deltas never
#                  resolve to content (club-3090 #97).
#   --jinja         Native (GGUF-embedded) Jinja template — club-3090 A/B'd vs froggeric:
#                  native won 8-pack 102 vs 95. Kept for compatibility.
#   --no-mmap --mlock  DFlash tuning retained (harmless for MTP, ensures predictable VRAM).
#
# Club-3090 reference: models/qwen3.6-27b/llama-cpp/compose/single/mtp.yml
# Measured: ~51 narr / ~60 code TPS (Q4_K_M + MTP n=2, 200K, 1× 3090 @ 370 W)

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Qwen3.6-27B Q4_K_M + MTP (club-3090 200K, q4_0 KV)" -ForegroundColor Green
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
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 0.6 --top-k 20 --min-p 0.0
