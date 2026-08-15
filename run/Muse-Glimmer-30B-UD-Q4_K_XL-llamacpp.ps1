# 32K ctx, q4_0 KV, b256/ub64, think OFF, vision OFF — LLAMA.CPP SMOKE PATH (Unsloth Dynamic 2.0)
# Source: unsloth/meta-glimmer30b-gguf — Muse-Glimmer-30B-UD-Q4_K_XL.gguf (15.88 GB) per https://unsloth.ai/docs/models/muse-glimmer
# Binary: sources/llama.cpp/build/bin/llama-server.exe (upstream master >=62bf73d, built with -DGGML_CUDA=ON)
# Model:  52L dense, 6656 hidden, 32Q/2KV, SWA [L,L,L,G]x13 W=2048, RoPE 500k, vocab 202k, 131072 max (262144 extended per Unsloth)
# Draft:  NONE (text-only; no kvarn/DFlash) — validates arch + GGUF before Bee port. Add DFlash via -dflash-llamacpp.ps1
#
# Purpose: Fast smoke after `git pull` in sources/llama.cpp — confirms GGUF loads,
#   chat template works, and --ctx-size validates. Unsloth guide (llama.cpp section) is minimal
#   (`--model <gguf> --mmproj <mmproj> --temp 1.0 --top-p 0.95 --top-k 64`); this harness adds
#   pinned --ctx-size, KV, flash-attn, jinja, reasoning flags for consistent server behavior.
#   If this fails, fix llama.cpp first; if it passes, port Bee (highctx etc).
#
# Tuning vs Unsloth guide:
#   - Unsloth says "no need to set context length as llama.cpp automatically uses the exact amount required"
#     — true for llama-cli single prompt, but for llama-server we still pin --ctx-size 32768 to reserve KV
#     deterministically on 3090 24GB. Bump to 65536 if you have headroom; 131072 needs kvarn (Bee only, not upstream).
#   - q4_0 KV (standard, not kvarn) — upstream has no kvarn/kvarn-swa/tail; those are beellama extensions.
#   - 32768 ctx ≈ 0.6 GB KV (q4_0) leaves headroom: 15.88 model + 0.6 KV + 0.5 overhead ≈ 17 GB. 65536 ≈ 1.3 GB KV.
#   - b256/ub64 per DFlash convention is fine for smoke; keep same batch
#   - Sampling per card & Unsloth: temp 1.0 top_p 0.95 top_k 64 (Unsloth: https://unsloth.ai/docs/models/muse-glimmer)
#   - Use env var for chat kwargs to bypass PS quote stripping (like Ornith-none)
#   - Added --alias per Unsloth llama-server example (--alias "unsloth-Muse-Glimmer-30B-GGUF")
. "$PSScriptRoot\beellama_common.ps1"

$env:LLAMA_ARG_CHAT_TEMPLATE_KWARGS = '{"preserve_thinking":false}'

Write-Host "Launching: Muse Glimmer 30B UD-Q4_K_XL (32k, think OFF, vision OFF, llama.cpp smoke) — Unsloth" -ForegroundColor Green

& (Get-ServerBinary -Build "llama.cpp") `
  -m $Model["Muse-Glimmer-30B-UD-Q4_K_XL"] `
  --alias "unsloth-Muse-Glimmer-30B-GGUF" `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 32768 `
  -b 256 -ub 64 `
  --cache-type-k q4_0 --cache-type-v q4_0 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --load-mode mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning off `
  --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0
