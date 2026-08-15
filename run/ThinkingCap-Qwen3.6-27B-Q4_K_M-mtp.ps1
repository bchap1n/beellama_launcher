# 64K ctx, kvarn4/kvarn3 KV, b4096/ub512, think ON, temp 0.6/top_p 0.95, vision OFF
# Source: beellama
# BottleCapAI/ThinkingCap-Qwen3.6-27B — brevity finetune of Qwen3.6-27B that
# keeps full accuracy with ~46% fewer thinking tokens. MTP draft head baked
# into every quant. Packaged as GGUF by protoLabsAI.
#
# Model card (base): https://huggingface.co/bottlecapai/ThinkingCap-Qwen3.6-27B
# Model card (GGUF): https://huggingface.co/protoLabsAI/ThinkingCap-Qwen3.6-27B-MTP-GGUF
#
# Key design characteristics (from model card):
#   - Brevity Thinking — trained on Qwen3.6's thinking path; emits <think>
#     reasoning tokens but uses ~46% fewer of them than base Qwen3.6-27B.
#     Near-empty <think> on hard problems, direct solution follows.
#   - MTP Decoding — multi-token prediction baked into every quant file;
#     ~62% mean draft acceptance, mean accepted length 2.83.
#     At n-max=3 with 62% acceptance: ~1.5× throughput vs single-token decode.
#   - 128K native context — same Qwen3.6-27B base, extensible via RoPE scaling.
#   - Critical: do NOT decode greedy (temp 0). The model can loop and never
#     close </think> without the sampling diversity. Use temp 0.6, top_p 0.95,
#     top_k 20 — the author's intended sampling.
#   - Quant-integrity verified: quant_sensitivity 93%, function_call 94%.
#     Low-bit rungs (Q3_K_M, IQ3_M) hold at parity with NVFP4 reference.
#
# VRAM budget (24 GB 3090):
#   weights (Q4_K_M):                    ~17.0 GB
#   KV at 64K (kvarn4 K, kvarn3 V):   ~1.8 GB  (estimated; depends on actual quant + GQA factor)
#   MTP draft head + CUDA overhead:       ~1.5 GB
#   total:                                ~20.3 GB
#   headroom:                              ~3.7 GB
#
# Vision is disabled — mmproj not loaded.
# To enable vision: add --mmproj / --no-mmproj-offload with a compatible projector.

. "$PSScriptRoot\beellama_common.ps1"

$ModelName = "ThinkingCap-Qwen3.6-27B-Q4_K_M"
Write-Host "Launching: $ModelName + MTP (64k, think ON, beellama.cpp)" -ForegroundColor Green

# Build flag array manually (not Get-CommonFlags) so we can tune per-model.
# Model card: n-max 2 = max acceptance, 3 = max throughput. Use 3.
# Sampling: temp 0.6, top_p 0.95, top_k 20 — author's intended; greedy loops.
$Flags = @(
    "-m",                           $Model[$ModelName],
    "--port",                       "$($Config.server.port)",
    "--host",                       $Config.server.host,
    "-np",                          "1",
    "--kv-unified",
    "--spec-type",                  "draft-mtp",
    "--spec-draft-n-max",           "3",
    "-ngl",                         "all",
    "--ctx-size",                   "65536",
    "-b",                           "4096",
    "-ub",                          "512",
    "--cache-type-k",               "kvarn4",
    "--cache-type-v",               "kvarn3",
    "--flash-attn",                 "on",
    "--cache-ram",                  "0",
    "--load-mode",                  "mlock",
    "--jinja",
    "--no-warmup",
    "--no-host",
    "--metrics",
    "--log-timestamps",
    "--log-prefix",
    "--log-colors",                 "off",
    "--reasoning",                  "on",
    "--chat-template-kwargs",       '{"preserve_thinking":true}',
    "--temp",                       "0.6",
    "--top-p",                      "0.95",
    "--top-k",                      "20",
    "--min-p",                      "0.0"
)

& (Get-ServerBinary -Build "beellama") $Flags
