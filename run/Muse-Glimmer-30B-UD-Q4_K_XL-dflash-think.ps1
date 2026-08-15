# 65K ctx, kvarn4 KV, b256/ub64, think ON, dense, vision OFF — BEELLAMA (Unsloth Dynamic 2.0)
# Source: unsloth/meta-glimmer30b-gguf — Muse-Glimmer-30B-UD-Q4_K_XL.gguf (15.88 GB) + dflash-kquant.gguf (1.63 GB)
# Model:  52L dense, SWA 2048, 131072 max ctx (262144 extended), vocab 202k
#
# Tuning:
#   - Moderate ctx 65536 for think: thinking traces fill ctx quickly; 65K leaves
#     headroom for generation while staying under 24 GB without vision.
#     If you need more thinking budget, raise to 98304 and add
#     --cache-type-k-swa kvarn3 --cache-type-v-swa kvarn3 or --kv-tail-tokens 0.
#     Highest no-vision ctx (131K) is in Muse-Glimmer-30B-UD-Q4_K_XL-dflash.ps1.
#   - DFlash 256/64 draft-dflash, --spec-draft-n-max 15 pinned, profit controller default.
#   - KVarN kvarn4 — tightest fit for think+ctx; SWA lever is window 2048.
#     VRAM: 15.88 + 1.63 + ~1.3 KV + 0.5 ≈ 19.3 GB at 65K.
#   - Think ON: Glimmer card controls effort via SYSTEM PROMPT
#     `Reasoning strength: high` (complex tasks) or `xhigh` (max), `medium`/`low`
#     for speed. Do NOT copy Qwen deepseek `preserve_thinking` deepseek-format
#     blindly — enable --reasoning on so jinja template exposes <think> blocks
#     if the GGUF chat template supports it, then send strength in system prompt.
#     Example system:  "Reasoning strength: high"
#   - Sampling: temp 1.0 top_p 0.95 top_k 64 per card & Unsloth (not Qwen 0.6/20).
#   - Flash-attn on, kv-unified, load-mode mlock, jinja on per beellama v0.4.3.
#
# Paths: D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\{Muse-Glimmer-30B-UD-Q4_K_XL,dflash-kquant}.gguf

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Muse Glimmer 30B UD-Q4_K_XL + DFlash (65k, think ON, beellama) — Unsloth" -ForegroundColor Green

$archCheck = Select-String -Path (Join-Path $RepoRoot "sources\beellama.cpp\src\llama-arch.cpp") -Pattern "muse_glimmer" -Quiet -ErrorAction SilentlyContinue
if (-not $archCheck) {
    Write-Warning "muse_glimmer arch not found in sources/beellama.cpp — merge upstream arch support before launching."
}

& (Get-ServerBinary -Build "beellama") `
  -m $Model["Muse-Glimmer-30B-UD-Q4_K_XL"] `
  --spec-draft-model $Drafter["Glimmer-DFlash"] `
  --spec-type draft-dflash `
  --spec-draft-n-max 15 --spec-draft-ngl all `
  --port $Config.server.port --host $Config.server.host `
  -np 1 `
  --kv-unified `
  -ngl all `
  --ctx-size 65536 `
  -b 256 -ub 64 `
  --cache-type-k kvarn4 --cache-type-v kvarn4 `
  --flash-attn on `
  --cache-ram 0 `
  --jinja `
  --load-mode mlock `
  --no-warmup `
  --no-host --metrics `
  --log-timestamps --log-prefix --log-colors off `
  --reasoning on --reasoning-preserve `
  --chat-template-kwargs '{"preserve_thinking":true}' `
  --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0
