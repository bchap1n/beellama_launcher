# 128K ctx, kvarn4/kvarn3 KV, b4096/ub512, think ON, dense, vision ON
# Source: beellama
# bytkim/Qwen3.6-27B-MTP-pi-reasoning — reasoning-trained companion to pi-tune.
# Trained with chain-of-thought for complex multi-step coding, architecture,
# and logic tasks. Packaged as GGUF for beellama.cpp / llama.cpp local agent loops.
#
# Model card: https://huggingface.co/bytkim/Qwen3.6-27B-MTP-pi-reasoning-GGUF
#
# Key differences from pi-tune:
#   - Thinking-ON by design — trained on Qwen3.6's thinking path; emits
#     <think> reasoning tokens before code/tool-call output
#   - MTP Decoding — same ~78% draft acceptance on agent workloads
#   - 128K tested context — same base model, 256K native, 128K sweet spot
#   - Higher temp: 1.0 (thinking models benefit from more exploration)
#   - Better at: multi-step architecture, SVG/design, complex logic chains
#   - Weaker at: fast tool-call loops (pi-tune is better for harness turns)
#
# VRAM budget (24 GB 3090):
#   weights (Q4_K_M):                    ~16.8 GB
#   KV at 128K (kvarn4 K, kvarn3 V):  ~3.5 GB
#   MTP draft head + CUDA overhead:       ~1.5 GB
#   mmproj (Unsloth-F32, 1.3 GB):         ~1.3 GB
#   total:                                ~23.1 GB
#   headroom:                              ~0.9 GB

. "$PSScriptRoot\beellama_common.ps1"

$ModelName = "Qwen3.6-27B-MTP-pi-reasoning-Q4_K_M"
Write-Host "Launching: $ModelName + MTP (128k, think ON, beellama.cpp)" -ForegroundColor Green

$Flags = @(
    "-m",                           $Model[$ModelName],
    "--mmproj",                     $MmprojLookup["Unsloth-F32"],
    "--no-mmproj-offload",
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
    "--reasoning",                  "on",
    "--temp",                       "1.0",
    "--top-k",                      "20",
    "--min-p",                      "0.0"
)

& (Get-ServerBinary -Build "beellama") $Flags
