# 128K ctx, kvarn4/kvarn3 KV, b4096/ub512, think OFF, dense, vision OFF
# Source: beellama
# bytkim/Qwen3.6-27B-MTP-pi-tune — QLORA SFT multi-token-prediction tune of
# Qwen3.6-27B, purpose-built for no-thinking agentic coding through a PI-style
# harness. Packaged as GGUF for beellama.cpp / llama.cpp local agent loops.
#
# Model card: https://huggingface.co/bytkim/Qwen3.6-27B-MTP-pi-tune-GGUF
# Companion writeup: https://huggingface.co/blog/bytkim/qwen36-27b-reasoning
#
# Key design characteristics (from model card):
#   - No-Thinking by Design — trained on Qwen3.6's non-thinking path; returns
#     tool calls, edits, and structured output directly — no <thinking> preamble
#     burning wall time before the harness can act.
#   - MTP Decoding — multi-token prediction drafts future tokens; the main
#     decode path only accepts when it agrees. ~78% draft acceptance on agent
#     workloads (model card figure). At n-max=6 with 78% acceptance, effective
#     throughput multiplier is ~1.5-1.7× vs single-token decode.
#   - 128K tested context — 256K native on the base model, extensible to 1M
#     via RoPE scaling. Card reports 128K as the validated sweet spot.
#   - ~1.6k tok/s end-to-end agent throughput (model card figure).
#   - Tuned for decisive output — favors direct action over scratch-pad expansion,
#     designed for loops where waiting minutes per turn breaks the flow.
#
# VRAM budget (24 GB 3090):
#   weights (Q4_K_M):                    ~16.8 GB
#   KV at 128K (kvarn4 K, kvarn3 V):  ~3.5 GB  (estimated; depends on actual quant + GQA factor)
#   MTP draft head + CUDA overhead:       ~1.5 GB
#   total:                                ~21.8 GB
#   headroom:                              ~2.2 GB
#
# If you need 200K ctx on 3090, reduce to q4_0/q4_0 KV (~3.5 GB
# saved → ~3.5 GB total headroom, fits 200K).
#
# Vision is disabled — mmproj not loaded.
# To enable vision: add the --mmproj / --no-mmproj-offload flags back.
#
# To enable think for complex reasoning: change --reasoning off to --reasoning on
#   (not recommended per model card — this tune was trained for no-thinking).
# For even stronger PI-style coding: use the reasoning-trained companion release
#   bytkim/Qwen3.6-27B-MTP-pi-reasoning-GGUF.

. "$PSScriptRoot\beellama_common.ps1"

$ModelName = "Qwen3.6-27B-MTP-pi-tune-Q4_K_M"
Write-Host "Launching: $ModelName + MTP (128k, think OFF, beellama.cpp)" -ForegroundColor Green

# Build flag array manually (not Get-CommonFlags) so we can tune per-model.
# The common function defaults to mtp n-max=2 (Unsloth recommendation) but
# this model's MTP head is tuned to ~78% acceptance — higher n-max pays off.
$Flags = @(
    "-m",                           $Model[$ModelName],
    "--port",                       "$($Config.server.port)",
    "--host",                       $Config.server.host,
    "-np",                          "1",
    "--kv-unified",
    "--spec-type",                  "draft-mtp",
    "--spec-draft-n-max",           "6",
    "-ngl",                         "all",
    "--ctx-size",                   "128000",
    "-b",                           "4096",
    "-ub",                          "512",
    "--cache-type-k",               "kvarn4",
    "--cache-type-v",               "kvarn3",
    "--flash-attn",                 "on",
    "--cache-ram",                  "0",
    "--jinja",
    "--load-mode",                  "mlock",
    "--no-warmup",
    "--no-host",
    "--metrics",
    "--log-timestamps",
    "--log-prefix",
    "--log-colors",                 "off",
    "--reasoning",                  "off",
    "--chat-template-kwargs",       '{"preserve_thinking":false}',
    "--temp",                       "0.6",
    "--top-k",                      "20",
    "--min-p",                      "0.0"
)

& (Get-ServerBinary -Build "beellama") $Flags
