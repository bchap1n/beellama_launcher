# 131K ctx, kvarn4 + SWA kvarn3 + tail 0, b256/ub64, think ON, vision ON, beellama — HIGH-CTX for 24GB VRAM (Unsloth Dynamic 2.0)
# Source: unsloth/meta-glimmer30b-gguf — Muse-Glimmer-30B-UD-Q4_K_XL.gguf (15.88 GB) + dflash-kquant.gguf (1.63 GB) + mmproj-kquant.gguf (1.40 GB)
#         per https://unsloth.ai/docs/models/muse-glimmer
#
# WHY NOT LuceBox dflash_server.exe:
#   lucebox-hub/server/src backends are qwen3/qwen35/gemma4/laguna/deepseek4 only —
#   there is NO muse_glimmer backend. Meta's dflash-kquant.gguf is beellama/llama.cpp
#   draft-dflash format (block-diffusion 5L/16), not a LuceBox draft. Attempting
#   `dflash_server --draft <glimmer-dflash>` will fail at model load (unsupported arch
#   / incompatible draft). Do not copy run/Gemma*-dflash-lucebox.ps1 recipe.
#   This script uses the beellama KVarN SWA + tail path (no host paging).
# Tuning for 131072 on 24GB VRAM (vision+think ON):
#   - VRAM budget: 15.88 model + 1.63 draft + 1.40 mmproj = 18.91 GB before KV.
#     Full 131K kvarn4 without tuning would push ~21 GB peak — tight but possible
#     via SWA leverage. This script adds explicit knobs for headroom:
#     * --cache-type-k kvarn4 --cache-type-v kvarn4 base
#     * --cache-type-k-swa kvarn3 --cache-type-v-swa kvarn3 (SWA layers at lower
#       precision — saves VRAM vs default inherit; 39/52 layers are SWA W=2048)
#     * --kv-tail-tokens 0 — intrinsic 128-token exact suffix only (smallest footprint).
#       `auto` (1024) spends VRAM on exact tail and does NOT help fit — use only for
#       quality at cost of VRAM. For SWA compact-native, use `full=1024,swa=1024` style
#       only if you have headroom.
#     * --cache-ram 0 — prompt-cache only on this build (Bee CHANGELOG: scoped to
#       server_prompt_cache, NOT active KV paging / NOT KVFlash). Active KV stays on
#       GPU. Do NOT set 49152 expecting host paging of cold KV.
#   - Think+Vision ON: send `Reasoning strength: high` (or xhigh) in system prompt;
#     keep --reasoning on + preserve_thinking:true so template can emit <think> blocks.
#     Sampling temp 1.0 top_p 0.95 top_k 64 per Muse card & Unsloth.
#   - If still OOM: drop --ctx-size 98304, or keep swa kvarn3 is already minimal.
#
# Paths: D:\.lmstudio\models\unsloth\meta-glimmer30b-gguf\{Muse-Glimmer-30B-UD-Q4_K_XL,dflash-kquant,mmproj-kquant}.gguf
. "$PSScriptRoot\beellama_common.ps1"

Write-Host "Launching: Muse Glimmer 30B UD-Q4_K_XL + DFlash + Vision + Think HIGH-CTX (131k, beellama, 24GB VRAM) — Unsloth" -ForegroundColor Green

$archCheck = Select-String -Path (Join-Path $RepoRoot "sources\beellama.cpp\src\llama-arch.cpp") -Pattern "muse_glimmer" -Quiet -ErrorAction SilentlyContinue
if (-not $archCheck) {
    Write-Warning "muse_glimmer arch not found in sources/beellama.cpp — merge upstream arch support before launching. See -dflash.ps1 BLOCKER."
}
foreach ($k in @("Muse-Glimmer-30B-UD-Q4_K_XL","Glimmer-DFlash","Glimmer")) {
    $p = if ($k -eq "Muse-Glimmer-30B-UD-Q4_K_XL") { $Model[$k] } elseif ($k -eq "Glimmer-DFlash") { $Drafter[$k] } else { $MmprojLookup[$k] }
    if (-not (Test-Path $p)) { Write-Error "Missing $k at $p"; exit 1 }
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
  --ctx-size 131072 `
  -b 256 -ub 64 `
  --cache-type-k kvarn4 --cache-type-v kvarn4 `
  --cache-type-k-swa kvarn3 --cache-type-v-swa kvarn3 `
  --kv-tail-tokens 0 --kv-tail-type f16 `
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
