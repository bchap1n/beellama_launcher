# 131K ctx, kvarn4 KV, b256/ub64, think OFF, dense, vision OFF — BEELLAMA (Unsloth Dynamic 2.0)
# Source: unsloth/meta-glimmer30b-gguf — Muse-Glimmer-30B-UD-Q4_K_XL.gguf (15.88 GB) per https://unsloth.ai/docs/models/muse-glimmer
# Draft:  dflash-kquant.gguf (1.63 GB) — first-party DFlash 5L block-16 SWA 2048 layers 1/13/25/37/49
# Model:  52L dense, 6656 hidden, 32Q/2KV, SWA [L,L,L,G]x13 (39 local + 13 global), RoPE 500k, vocab 202k, 131072 ctx (262144 extended)
#
# Tuning:
#   - DFlash draft-dflash block-diffusion: -b 256 -ub 64 per AGENTS.md DFlash convention
#     (do NOT use Gemma b2048/ub512 — those are MTP/none). --spec-type draft-dflash
#     --spec-draft-n-max 15 pinned (upstream defaults 3 even with block-16; Bee's `block_size-1` would also be 15 but pin explicitly to avoid trap) + --spec-draft-ngl all; --spec-dm-controller profit (default).
#   - KVarN kvarn4/kvarn4: global + SWA share same width by default. SWA window 2048 is
#     the VRAM lever — only 13/52 layers need full ctx KV; 39 local layers capped at W=2048.
#     At 131K with kvarn4, expect ~2-3 GB KV (vs ~5 GB q4_0). Tightest fit on 24 GB 3090
#     is here: 15.88 + 1.63 + ~2.5 KV + 0.5 overhead ≈ 20.5 GB. If OOM at peak fill, drop to
#     98304 or add --cache-type-k-swa kvarn3 --cache-type-v-swa kvarn3 + --kv-tail-tokens 0.
#   - No vision: saves 1.40 GB mmproj + activations; highest ctx variant.
#   - Think OFF: model card uses system-prompt `Reasoning strength: <low|medium|high|xhigh>`
#     (not Qwen deepseek tags). For no-think, either omit strength or send `low`; keep
#     --reasoning off and preserve_thinking:false so template does not expect <think> blocks.
#   - Sampling per card & Unsloth: temp 1.0 top_p 0.95 top_k 64 (not Qwen 0.6-0.7/0.8).
#
# Paths: D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\{Muse-Glimmer-30B-UD-Q4_K_XL,dflash-kquant,mmproj-kquant}.gguf

. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Muse Glimmer 30B UD-Q4_K_XL + DFlash (131k, think OFF, vision OFF, beellama) — Unsloth" -ForegroundColor Green

# Preflight: source + binary — source may be ported while binary is still stale
$archCheck = Select-String -Path (Join-Path $RepoRoot "sources\beellama.cpp\src\llama-arch.cpp") -Pattern "muse_glimmer" -Quiet -ErrorAction SilentlyContinue
$binPath = $null; try { $binPath = Get-ServerBinary -Build "beellama" } catch {}
$binStale = $true; if ($binPath -and (Test-Path $binPath)) {
    $binStale = (Get-Item $binPath).LastWriteTime -lt [DateTime]"2026-08-11"
}
if (-not $archCheck) {
    Write-Warning "muse_glimmer arch not found in sources/beellama.cpp — cherry-pick 62bf73d onto feature/muse-glimmer first."
} elseif ($binStale) {
    Write-Warning "sources/beellama.cpp/build/bin/llama-server.exe is stale (pre-c87dd99). Rebuild Bee: call vcvarsall.bat x64; cmake -B build -G Ninja -DGGML_CUDA=ON -S .; ninja"
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
  --ctx-size 131072 `
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
