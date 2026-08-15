# 65K ctx, kvarn4 KV, b256/ub64, think OFF, dense, vision ON — BEELLAMA (Unsloth Dynamic 2.0)
# Source: unsloth/meta-glimmer30b-gguf — Muse-Glimmer-30B-UD-Q4_K_XL.gguf (15.88 GB) + dflash-kquant.gguf (1.63 GB) + mmproj-kquant.gguf (1.40 GB)
# Model:  52L dense, 6656 hidden, 32Q/2KV, SWA [L,L,L,G]x13 W=2048, RoPE 500k, 131072 max (262144 extended), ViT-G/14 50L
#
# Tuning:
#   - DFlash 256/64 draft-dflash, --spec-draft-n-max 15 pinned (upstream 3 vs Bee block_size-1=15; pin to avoid trap), profit controller default.
#   - Lower ctx 65536 for vision: 1.40 GB mmproj + vision activations cost VRAM; 65K
#     keeps peak under 24 GB: 15.88 + 1.63 + 1.40 + ~1.3 KV + 0.5 ≈ 20.7 GB.
#     Raise to 98304 if you add --cache-type-k-swa kvarn3 + --kv-tail-tokens 0, but
#     65K is the safe vision default on 3090 (24 GB, 250W).
#   - KVarN kvarn4 both sides; SWA override inherits same width (explicit
#     --cache-type-k-swa kvarn4 --cache-type-v-swa kvarn4 only if you need to tune SWA).
#   - Sampling: temp 1.0 top_p 0.95 top_k 64 per Glimmer card & Unsloth.
#   - Think OFF: use system prompt `Reasoning strength: low` or omit; --reasoning off.
#
# Paths: D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\{Muse-Glimmer-30B-UD-Q4_K_XL,dflash-kquant,mmproj-kquant}.gguf

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Muse Glimmer 30B UD-Q4_K_XL + DFlash + Vision (65k, think OFF, beellama) — Unsloth" -ForegroundColor Green

$archCheck = Select-String -Path (Join-Path $RepoRoot "sources\beellama.cpp\src\llama-arch.cpp") -Pattern "muse_glimmer" -Quiet -ErrorAction SilentlyContinue
if (-not $archCheck) {
    Write-Warning "muse_glimmer arch not found in sources/beellama.cpp — merge upstream arch support before launching."
}
if (-not (Test-Path $Drafter["Glimmer-DFlash"])) {
    Write-Error "DFlash draft not found: $($Drafter['Glimmer-DFlash']) — expected D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\dflash-kquant.gguf"
    exit 1
}
if (-not (Test-Path $MmprojLookup["Glimmer"])) {
    Write-Error "Mmproj not found: $($MmprojLookup['Glimmer']) — expected D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\mmproj-kquant.gguf"
    exit 1
}

& (Get-ServerBinary -Build "beellama") `
  -m $Model["Muse-Glimmer-30B-UD-Q4_K_XL"] `
  --mmproj $MmprojLookup["Glimmer"] `
  --no-mmproj-offload `
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
  --reasoning off `
  --chat-template-kwargs '{"preserve_thinking":false}' `
  --temp 1.0 --top-p 0.95 --top-k 64 --min-p 0.0
