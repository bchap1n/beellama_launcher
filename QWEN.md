# beeLLama Launcher — QWEN.md

## Project Overview

PowerShell-based launch and benchmark harness for [beellama.cpp](https://github.com/Anbeeld/beellama.cpp), optimized for running **Qwen3.6-27B** on a **single RTX 3090** with speculative decoding (DFlash, MTP, or both).

The repo manages:
- **Launch scripts** (`run/`) — one per model + quant + spec-decoding combo
- **Interactive launcher** (`start-beellama.ps1`) — grouped menu, drafter selection, `-Rerun` replay
- **Benchmark suite** (`benchmark/`) — automated server launch, prompt execution, HTML/CSV reporting
- **Build tooling** (`sources/`) — clone and build beellama.cpp (beellama + beellama_fork)

### Target Hardware

- GPU: NVIDIA RTX 3090 (24 GB VRAM, power-limited to 250W at launch)
- OS: Windows (PowerShell 7+)
- Build toolchain: MSVC, CUDA 13.2, CMake, Ninja

### Speculative Decoding Modes

| Mode | Binary | Draft Mechanism |
|------|--------|-----------------|
| `dflash` | beellama or beellama_fork | Cross-attention drafter model (Ardenzard-tuned) |
| `mtp` | beellama_fork | Model's built-in Multi-Token Prediction layers |
| `dflash-mtp` | beellama or beellama_fork | DFlash on MTP-capable model |
| `none` | beellama or beellama_fork | No speculation |

MTP and DFlash are **mutually exclusive per launch**.

### Models

| Model | Quants | Source |
|-------|--------|--------|
| Qwen3.6-27B | Q4_K_M, Q5_K_M | lmstudio-community / unsloth |
| Qwen3.6-27B-MTP | Q4_K_M, Q4_K_S, Q5_K_S | unsloth |
| Qwopus3.5-9B-Coder | BF16 | Jackrong |

DFlash drafters from `Ardenzard/Qwen3.6-27B-DFlash-GGUF` (IQ4_XS, Q4_K_M, Q5_K_M).

Models live under LM Studio's default path (`%USERPROFILE%\.lmstudio\models`).

## Directory Structure

```
start-beellama.ps1          # Interactive launcher (menu, -Rerun, -Benchmark)
run/
  config.json               # Paths: binaries, LM Studio models, server defaults
  beellama_common.ps1       # Shared helpers (Get-ServerBinary, Get-CommonFlags)
  Qwen3.6-27B-Q4_K_M-dflash.ps1       # One script per config
  Qwen3.6-27B-Q4_K_M-mtp.ps1
  ...

benchmark/
  benchmark.config.json     # Runs, tokens, timeouts, prompts file
  prompts.json              # Prompt definitions (Code + Reasoning)
  run_benchmark.ps1         # Benchmark orchestrator (server lifecycle + HTML report)
  <timestamp>/              # Timestamped result directories

sources/                    # Build scripts (source repos are gitignored)
  setup-sources.ps1         # Clone beellama.cpp repos
  setup-dependencies.ps1    # Validate CUDA, MSVC, Ninja, CMake
  build-beellama.ps1        # Build beellama
  build-beellama-fork.ps1   # Build beellama_fork

archive/                    # Old scripts kept for reference
logs/                       # Server logs
models/                     # Local model overrides (gitignored)
.key/                       # Secrets (gitignored)
```

## Quick Start

```powershell
# 1. Clone + setup sources
git clone https://github.com/bchap1n/beellama_launcher.git
cd beellama_launcher
.\sources\setup-sources.ps1

# 2. Verify build dependencies
.\sources\setup-dependencies.ps1

# 3. Build (beellama for DFlash, beellama_fork for MTP)
.\sources\build-beellama.ps1
.\sources\build-beellama-fork.ps1

# 4. Launch interactively
.\start-beellama.ps1

# 5. Re-run last selection
.\start-beellama.ps1 -Rerun

# 6. Benchmark mode
.\start-beellama.ps1 -Benchmark
```

## Configuration

Edit `run/config.json` to customize:
- **lmstudioModelsPath** — base path to GGUF models (default: `%USERPROFILE%\.lmstudio\models`)
- **binaries** — relative paths to `llama-server.exe` (beellama_fork, beellama, beellama_prebuilt)
- **server** — default port (`8082`) and host (`0.0.0.0`)

Edit `benchmark/benchmark.config.json` to tune benchmark parameters (runs, tokens, cooldown, retries).

## Launch Script Convention

Scripts in `run/` follow the naming pattern:
```
{Model}-{Quant}-{SpecMode}[-modifier].ps1
```
Examples:
- `Qwen3.6-27B-Q4_K_M-dflash.ps1`
- `Qwen3.6-27B-Q4_K_M-dflash-mtp-reasoning.ps1`
- `Qwopus3.5-9B-Coder-none.ps1`

Each script dot-sources `beellama_common.ps1` for model/drafter/binary resolution and launches `llama-server.exe` with the appropriate flags.

## Benchmark Suite

The benchmark orchestrator (`benchmark/run_benchmark.ps1`) supports three modes:
- **Single** — benchmark one configuration
- **Pair** — benchmark two configurations side by side
- **VS** — auto-match spec modes for the same model+quant (e.g., dflash vs mtp vs dflash-mtp)

Each run produces a timestamped directory containing:
- `results.csv` — per-prompt measurements
- `results.html` — styled comparison report with bar charts
- `<config>.log` — server stdout
- `<config>.err.log` — server stderr
- `<config>.metrics.txt` — scraped `/metrics` endpoint

## Key Files

| File | Purpose |
|------|---------|
| `start-beellama.ps1` | Interactive launcher with menu, -Rerun, -Benchmark |
| `run/beellama_common.ps1` | Shared functions: Get-ServerBinary, Get-CommonFlags |
| `run/config.json` | Model paths, binary paths, server defaults |
| `benchmark/run_benchmark.ps1` | Benchmark orchestrator (716 lines) |
| `benchmark/prompts.json` | 4 prompts: 2 Code, 2 Reasoning |
| `benchmark/benchmark.config.json` | Benchmark parameters |
| `.last-run.json` | Auto-saved last interactive selection |

## Development Notes

- DFlash scripts use Ardenzard's 3090-optimized tuning: `-b 256 -ub 64`, cross-ctx 256, `turbo4` KV cache
- MTP scripts use the `beellama_fork` build; `--spec-type` is NOT passed (auto-detected from model)
- `--spec-draft-n-max 2` for MTP (per Unsloth recommendation)
- Reasoning-mode scripts add `--reasoning on` and `preserve_thinking:true`
- Multimodal projectors: BF16 for lmstudio-community, F32 for unsloth
- `start-beellama.ps1` sets GPU power limit to 250W via `nvidia-smi -pl 250`

## Open TODOs

- Add llama.cpp upstream build option for latest features
- Investigate why MTP+DFlash performs worse than either alone
- Add a 9B model (Qwen or Gemma) for code completion
- Optimize Q5_K_M to be a viable pair-programming speed
- Consider cloud model fallback (NousResearch deal)
- Hermes: evaluate Windows native beta or containerized deployment
