# beeLLama

PowerShell launch scripts for [beellama.cpp](https://github.com/Anbeeld/beellama.cpp) — running Qwen3.6-27B with DFlash and/or MTP speculative decoding on an RTX 3090.

## Quick Start

```powershell
# 1. Clone this repo
git clone https://github.com/bchap1n/beellama_launcher.git
cd beellama_launcher

# 2. Clone beellama.cpp sources
.\sources\setup-sources.ps1

# 3. Verify build dependencies (MSVC, CUDA 13.2, Ninja, CMake)
.\sources\setup-dependencies.ps1

# 4. Build (original for DFlash, fork for MTP)
.\sources\build-beellama.ps1
.\sources\build-beellama-fork.ps1

# 5. Launch interactively
.\start-beellama.ps1
```

## Repository Structure

```
config.json                 # Paths: lmstudio models, binaries, server defaults
beellama_common.ps1         # Shared functions (Get-ServerBinary, Get-CommonFlags)
start-beellama.ps1          # Interactive grouped launcher

run/                        # Launch configurations (one per model+spec+mode combo)
  Qwen3.6-27B-Q4_K_M-dflash.ps1
  Qwen3.6-27B-Q4_K_M-mtp-reasoning.ps1
  Qwen3.6-27B-Q4_K_M-dflash+mtp.ps1
  Qwopus3.5-9B-Coder-none.ps1
  ...

benchmark/                  # Benchmark harness and results
  run_benchmark.ps1
  results.html

sources/                    # Build tooling (source repos are gitignored)
  setup-sources.ps1         # Clone/update beellama.cpp repos
  setup-dependencies.ps1    # Validate CUDA, Ninja, CMake, MSVC
  build-beellama.ps1        # Build original beellama.cpp
  build-beellama-fork.ps1   # Build MTP fork

archive/                    # Old scripts kept for reference
```

## Models

Target models default path uses LM Studio's model directory (`%USERPROFILE%\.lmstudio\models`). I like using LM Studio to download and manage models, but you can point config.json to any local path.

| Target | Quants | Spec Mode | Binary | Source |
|--------|--------|-----------|--------|--------|
| Qwen3.6-27B | Q4_K_M | DFlash | original | [lmstudio-community](https://huggingface.co/lmstudio-community/Qwen3.6-27B-GGUF) |
| Qwen3.6-27B | Q5_K_S | DFlash | original | [unsloth](https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF) |
| Qwen3.6-27B-MTP | Q4_K_M, Q4_K_S | MTP, DFlash+MTP | fork | [unsloth](https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF) |
| Qwopus3.5-9B-Coder | BF16 | none | original | [Jackrong](https://huggingface.co/Jackrong/Qwopus3.5-9B-Coder-GGUF) |

### Speculative Decoding Modes Explained

Three distinct configurations are supported. **MTP and DFlash are mutually exclusive per launch** — you cannot use both simultaneously.

| Mode | What it does | `--spec-type` | `--spec-draft-n-max` |
|------|--------------|---------------|---------------------|
| **Pure MTP** (`mtp`) | Uses the model's internal Multi-Token Prediction layers to generate draft tokens. No separate drafter model. | *(auto-detected)* | `2` (per Unsloth recommendation) |
| **DFlash on MTP model** (`dflash+mtp`) | Uses **DFlash** speculation. The MTP layers are present in the model but **inactive**. A separate DFlash drafter handles speculation. | `dflash` | *(unused)* |
| **Pure DFlash** (`dflash`) | Uses DFlash speculation on a standard model (no MTP layers). Same mechanism as `dflash+mtp`. | `dflash` | *(unused)* |

**Why run `dflash+mtp`?** You may already have the MTP model downloaded, or want to compare DFlash vs MTP performance on the same base model without re-downloading. The MTP architecture does not interfere with DFlash operation — it simply sits unused.

### DFlash Drafters

DFlash scripts prompt for drafter quant at launch (default: IQ4_XS). Drafters from [Ardenzard/Qwen3.6-27B-DFlash-GGUF](https://huggingface.co/Ardenzard/Qwen3.6-27B-DFlash-GGUF), tuned for single RTX 3090:

| Drafter | Notes |
|---------|-------|
| **IQ4_XS** (default) | Best all-around, smallest VRAM footprint |
| Q4_K_M | Strong on long code tasks |
| Q5_K_M | Higher quality, more VRAM |

DFlash configs use Ardenzard's 3090-optimized settings: `-b 256 -ub 64`, cross-ctx 256, `turbo4`/`turbo4` KV cache.

### Multimodal Projectors

Scripts that load mmproj use the projector bundled with their model source (BF16 for lmstudio-community, F32 for unsloth).

## Configuration

Edit `run/config.json` to set paths for your environment:
- **lmstudioModelsPath** — base path to LM Studio models (default: `%USERPROFILE%\.lmstudio\models`)
- **binaries** — relative paths to llama-server.exe builds
- **server** — default port (`8082`) and host (`0.0.0.0`)
