# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

This repo is a **PowerShell launcher harness** for [BeeLlama.cpp](https://github.com/Anbeeld/beellama.cpp), Anbeeld's fork of llama.cpp. It manages launch configurations, benchmarking, and builds for running **Qwen3.6-27B** on a single RTX 3090 (24 GB VRAM, power-limited to 250 W).

The beellama.cpp source is cloned into `sources/` (gitignored). This repo is the harness on top of it.

## Quick Start

```powershell
# 1. Clone and build beellama.cpp source
.\sources\setup-sources.ps1
.\sources\setup-dependencies.ps1
.\sources\build-beellama.ps1        # beellama build (DFlash)
.\sources\build-beellama-fork.ps1   # beellama_fork build (MTP)
.\sources\build-ik-llama.ps1        # ik_llama build (two-stage spec-dec)

# 2. Launch interactively (sets GPU to 250 W, shows menu)
.\start-beellama.ps1

# 3. Re-run last selection without prompting
.\start-beellama.ps1 -Rerun

# 4. Run benchmark suite
.\start-beellama.ps1 -Benchmark
```

## Build Environment

The build scripts target this specific environment:

| Tool | Expected Version/Path | Notes |
|------|-----------------------|-------|
| MSVC | VS 2026 Insiders (`C:\Program Files\Microsoft Visual Studio\18\Insiders\`) | `vcvarsall.bat` must be present |
| CUDA | 13.2 (`C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\`) | nvcc must be on that path |
| CMake | 3.31.x (NOT 4.x) | CMake 4.3 has a known bug with `enable_language(CUDA)` in subdirectories — see `sources/BUILD_NOTES.md` for the full investigation |
| Ninja | Any recent version on PATH | `winget install Ninja-build.Ninja` |

Run `.\sources\setup-dependencies.ps1` to validate all build tools are present. If builds fail, check `sources/BUILD_NOTES.md` for troubleshooting (CMake version issues, Ninja vs VS generator tradeoffs).

## Directory Structure

```
start-beellama.ps1          # Interactive launcher: menu, -Rerun, -Benchmark
run/
  config.json               # Binary paths, LM Studio model base path, server port
  beellama_common.ps1       # Shared helpers: Get-ServerBinary, Get-CommonFlags
  *.ps1                     # One launch script per model+quant+spec-mode combo
  archive/                  # Retired scripts (not scanned by the launcher)
benchmark/
  benchmark.config.json     # Runs, tokens, cooldown, retries
  prompts.json              # 4 prompts: 2 Code, 2 Reasoning
  run_benchmark.ps1         # Orchestrator: server lifecycle, HTML/CSV report
  <timestamp>/              # Per-run output: results.html, results.csv, *.log, *.metrics.txt
sources/                    # Build scripts (cloned repos are gitignored)
  setup-sources.ps1
  setup-dependencies.ps1
  build-beellama.ps1
  build-beellama-fork.ps1
  build-ik-llama.ps1        # ik_llama.cpp build (IQK quants, two-stage spec-dec)
  club-3090/                # noonghunna/club-3090 reference repo (Docker-based, Linux)
  BUILD_NOTES.md            # Build environment quirks & troubleshooting
tools/                      # Serial proxy tunnel for VMware (see tools/README.md)
logs/                       # Server logs (gitignored)
prebuilt/                   # Drop prebuilt llama-server.exe here as fallback
.last-run.json              # Auto-saved last interactive selection (for -Rerun, gitignored)
```

## Launch Scripts

Scripts in `run/` follow this naming convention:

```
{Model}-{Quant}-{SpecMode}[-modifier].ps1
```

Examples: `Qwen3.6-27B-Q4_K_M-dflash.ps1`, `Qwen3.6-27B-Q4_K_M-dflash-reasoning.ps1`, `Qwen3.6-27B-Q5_K_S-none.ps1`

Known modifiers:
- `reasoning` — enables `--reasoning on` + `preserve_thinking:true`
- `speed` — Ardenzard-tuned for maximum decode throughput on Q4
- `club3090` — club-3090 tuned: `-ub 512`, `-c 200000`, q4_0 KV, `--reasoning-format deepseek`
- `ik-two-stage` — ik_llama two-stage spec-dec (ngram-mod + MTP), `--merge-qkv`, `-khad`/`-vhad`

Each script must:
1. Dot-source `beellama_common.ps1` to get model/drafter/binary resolution
2. Accept `-DrafterQuant` param if the spec mode is `dflash` or `dflash-mtp`
3. Call `Get-ServerBinary -Build "beellama"|"beellama_fork"` to resolve the binary path
4. Pass `-m $Model["<key>"]` and `-spec-draft-model $Drafter["DFlash-$DrafterQuant"]` (for DFlash)

**Speculative modes and which binary they require:**

| SpecMode | Binary | Notes |
|----------|--------|-------|
| `dflash` | `beellama` or `beellama_fork` | Cross-attention drafter (Ardenzard GGUFs). Use `beellama_fork` if the target model has MTP tensors (Unsloth models). Use `beellama` for standard lmstudio-community models. |
| `mtp` | `beellama_fork` | Auto-detected; do NOT pass `--spec-type` |
| `dflash-mtp` | `beellama` or `beellama_fork` | DFlash on MTP-capable model. DFlash handles speculation; MTP heads are present but unused. |
| `none` | `beellama` or `beellama_fork` | No speculation. Use `beellama_fork` if the model has MTP tensors. |
| `ngram-mtp` | `llama.cpp` | Stacked: `draft-mtp,ngram-mod,ngram-map-k4v` (upstream llama.cpp only) |
| `ik-two-stage` | `ik_llama` | **NEW** — Two-stage spec-dec (ngram-mod + MTP fallback). ik_llama-exclusive: `--merge-qkv`, `-khad`/`-vhad`, `--recurrent-ckpt-mode`. Code +35% vs MTP-only. Uses `--spec-stage` chains. |
| `mtp-club3090` | `beellama_fork` | **NEW** — MTP with club-3090 tuning: `-ub 512`, `-c 200000`, q4_0 KV, `--reasoning-format deepseek`. Verified 200K cliff-survival. |

MTP and DFlash are mutually exclusive per launch. The `beellama_fork` build (now synced with upstream v0.2.0) supports both DFlash and MTP, and includes the qwen35 MTP tensor loading fix. The `beellama` build does NOT have the MTP tensor fix — use it only with standard (non-MTP) models.

### ik_llama.cpp (club-3090 advanced-quant track)

ik_llama.cpp is ikawrakow's llama.cpp fork with exclusive optimizations relevant to single-card 3090:

| Feature | Flag | Benefit |
|---------|------|---------|
| Fused QKV projection | `--merge-qkv` / `-mqkv` | ~2-4% decode uplift |
| Hadamard KV transforms | `-khad` / `-vhad` | Better quantized-KV accuracy (zero VRAM cost) |
| Recurrent checkpoint | `--recurrent-ckpt-mode auto` | Cheaper MTP rejections on DeltaNet hybrid layers |
| Two-stage spec-dec | `--spec-stage ngram-mod:... --spec-stage mtp:...` | +35% code decode vs MTP-only |
| Parallel tool calls | `--parallel-tool-calls` | Multiple tool calls per response |
| IQK imatrix quants | `IQ4_KS`, `IQ5_KS` | Better quality-per-bit than k-quants |

Club-3090 measured (1× 3090 @ 370 W): ik_llama + IQ4_KS + MTP = ~60/69 TPS (~18-20% faster than mainline MTP). Two-stage = ~59/98 TPS (+35% code).

Build: `.\sources\build-ik-llama.ps1` (same MSVC + CUDA 13.2 toolchain). Binary resolves to `sources\ik_llama.cpp\build\bin\llama-server.exe`.

ik_llama uses `-ctk`/`-ctv` for KV cache type (instead of `--cache-type-k`/`--cache-type-v`). The `--spec-stage` flag replaces `--spec-type` for two-stage chaining. MTP is enabled via `--multi-token-prediction` + `--draft-max N` (single-stage) or `--spec-stage mtp:n_max=N,...` (two-stage).

## Shared Helpers (`run/beellama_common.ps1`)

Dot-source this in every run script. It exposes:

- **`$Model`** — hashtable of target model paths keyed by friendly name (e.g., `"Qwen3.6-27B-Q4_K_M"`)
- **`$Drafter`** — hashtable of DFlash draft model paths (e.g., `"DFlash-IQ4_XS"`, `"DFlash-Q4_K_M"`, `"DFlash-Q5_K_M"`)
- **`$Config`** — parsed `config.json`
- **`Get-ServerBinary -Build <beellama_fork|beellama|beellama_prebuilt|ik_llama|llama.cpp>`** — resolves binary path with fallback chain
- **`Get-CommonFlags`** — returns a `@()` array of server CLI args. Key params:
  - `-SpecMode dflash|mtp|none`
  - `-DraftModel <path>` (required for dflash)
  - `-CtxSize`, `-CacheK`, `-CacheV`, `-CrossCtx`, `-BatchSize`, `-UBatchSize`
  - `-MmprojPath`, `-Reasoning`, `-SkipMmproj`

Note: some run scripts inline their flags rather than using `Get-CommonFlags` — both styles are valid.

### Model Sources

`beellama_common.ps1` resolves models from three sources under `lmstudioModelsPath`:

| Source | Path under LM Studio | Contains | Used with |
|--------|---------------------|----------|-----------|
| lmstudio-community | `lmstudio-community\Qwen3.6-27B-GGUF` | Standard Qwen3.6-27B GGUFs (Q4_K_M) | `beellama` binary + DFlash |
| unsloth | `unsloth\Qwen3.6-27B-MTP-GGUF` | MTP-enabled GGUFs (Q4_K_M, Q4_K_S, Q5_K_M, Q5_K_S) | `beellama_fork` binary + MTP, or `beellama` binary + `none` |
| Ardenzard | `Ardenzard\Qwen3.6-27B-DFlash-GGUF` | DFlash draft GGUFs (IQ4_XS, Q4_K_M, Q5_K_M) | Draft models only, not target models |
| ubergarm | `ubergarm\Qwen3.6-27B-GGUF` | IQK imatrix GGUFs (IQ4_KS, IQ5_KS) | `ik_llama` binary + MTP or two-stage |

Getting this right is critical when creating new launch scripts: MTP models need the `beellama_fork` binary (even for `none` spec mode, since the model has MTP heads), while standard models use the `beellama` binary with DFlash. IQK quants need the `ik_llama` binary for the fused IQK dequant kernels; they'll run on other binaries but slower.

### Batch Size Tuning

DFlash scripts use **`-b 256 -ub 64`** (Ardenzard 3090 tuning — small batches favor cross-attention latency). MTP and `none` scripts use **`-b 2048 -ub 256`** (Unsloth recommendation — large batches for throughput). These are consistent per-spec-mode patterns; deviating from them degrades performance.

## Configuration (`run/config.json`)

```json
{
  "lmstudioModelsPath": "%USERPROFILE%\\.lmstudio\\models",
  "binaries": {
    "llama.cpp": "sources\\llama.cpp\\build\\bin\\llama-server.exe",
    "beellama_fork": "sources\\beellama.cpp_fork\\build\\bin\\llama-server.exe",
    "beellama": "sources\\beellama.cpp\\build\\bin\\llama-server.exe",
    "beellama_prebuilt": "prebuilt\\llama-server.exe",
    "ik_llama": "sources\\ik_llama.cpp\\build\\bin\\llama-server.exe"
  },
  "sourcesDir": "sources",
  "server": { "port": 8082, "host": "0.0.0.0" }
}
```

Edit `lmstudioModelsPath` if models are not in the default LM Studio location. Edit `binaries` if build output paths change.

## Benchmark Suite

`start-beellama.ps1 -Benchmark` delegates to `benchmark/run_benchmark.ps1`, which supports three modes:

- **Single** — one configuration
- **Pair** — two configurations side by side
- **VS** — auto-matches scripts with the same model+quant across spec modes (e.g., dflash vs mtp)

Each run produces a timestamped directory under `benchmark/` containing:
- `results.html` — styled bar-chart comparison report
- `results.csv` — raw per-prompt measurements
- `<config>.log` / `<config>.err.log` — server stdout/stderr
- `<config>.metrics.txt` — scraped `/metrics` endpoint

Tune benchmark parameters in `benchmark/benchmark.config.json` (runs, tokens, cooldown, retries). Prompts are in `benchmark/prompts.json` (2 Code + 2 Reasoning).

## beellama.cpp Background

This section covers the fork itself — relevant when writing server flags or touching `sources/`.

### Fork Features

- **DFlash**: cross-attention speculative decoding. DFlash drafters are GGUFs from `Ardenzard/Qwen3.6-27B-DFlash-GGUF`. Target hidden states are captured via `llama_set_eval_callback` into a 4096-token CPU ring per layer.
- **TurboQuant / TCQ KV cache**: `--cache-type-k` / `--cache-type-v` accept `turbo2`, `turbo3`, `turbo4`, `turbo2_tcq`, `turbo3_tcq`. Requires `GGML_CUDA_FA_ALL_QUANTS=ON` at build time.
- **Adaptive draft-max**: `profit` (default) and `fringe` server controllers. Use `--no-spec-dm-adaptive` for fixed-depth benchmarks.
- **DDTree**: tree verification. `--spec-branch-budget 0` = flat; positive = branch nodes beyond main path.
- **MTP**: multi-token prediction via the `beellama_fork` build; `--spec-draft-n-max 2` per Unsloth recommendation.
- **Reasoning loop guard**: `--reasoning-loop-guard force-close` with configurable window/interval.
- **CopySpec**: model-free speculation via rolling-hash suffix match; explicit `--spec-type copyspec`.

### Typical DFlash flags (3090 Ardenzard tuning)

```powershell
-b 256 -ub 64
--spec-dflash-cross-ctx 256
--cache-type-k turbo4 --cache-type-v turbo4
--flash-attn on
--no-mmap --mlock
```

### Fork-Specific Source Files

- `src/models/dflash_draft.cpp` — DFlash draft model graph
- `common/speculative.cpp` — DFlash state, ring buffer, CopySpec, tree construction
- `tools/server/server-context.cpp` — speculative scheduling, verification, rollback
- `tools/server/server-adaptive-dm.h` — profit/fringe adaptive controllers
- `tools/server/server-loop-guard.cpp` — reasoning loop guard
- `ggml/src/ggml-turbo-quant.c` — CPU quantize/dequantize for TurboQuant/TCQ
- `ggml/src/ggml-cuda/turbo-quant-cuda.cuh` — CUDA kernels for TurboQuant/TCQ

### Debug Environment Variables

| Variable | Effect |
|---|---|
| `GGML_DFLASH_PROFILE=1` | Enables timing breakdowns in the DFlash pipeline |
| `GGML_DFLASH_GPU_RING=0` | Forces CPU-only ring, disables GPU cross-ring |
| `GGML_DFLASH_MAX_CTX=N` | Caps cross-attention context length (default 4096) |

### Key Docs in `sources/beellama.cpp*/docs/`

- `beellama-args.md` — complete argument reference
- `beellama-features.md` — feature matrix vs public llama.cpp / TheTom / buun
- `speculative.md` — speculative decoding types, CLI options, statistics format
- `quickstart-qwen36-dflash.md` — step-by-step Qwen 3.6 + DFlash guide

For build troubleshooting, see `sources/BUILD_NOTES.md` (CMake version issues, VS 2026 Insiders + Ninja workaround).

## Git Conventions

- Do not commit unless explicitly asked.
- Do not treat benchmark output from prior runs as current evidence — re-run with exact model, command, hardware, and commit ID.
- Keep fork-specific changes in `sources/` small and scoped.

## Key third party online resources for tuning local run scripts/config

Important research for tuning local run scripts/config on DFlash beellama.cppp vs MTP on 3090:
"https://dev.to/ianlpaterson/three-months-of-speed-up-experiments-on-a-3090-ti-autoregressive-dflash-mtp-for-qwen36-27b-59ef"

llama.cpp branch fusing MTP + TurboQuant KV could be useful for work in beellama.cpp_fork\mtp
"https://github.com/Indras-Mirror/llama.cpp-turboq-mtp"
