# build-ik-llama.ps1
# Builds ik_llama.cpp from source with CUDA support.
# Target: sources/ik_llama.cpp
#
# ik_llama.cpp is ikawrakow's fork with IQK quants, fused CUDA kernels,
# Hadamard KV transforms, two-stage spec-dec (ngram+MTP), and more.
#
# Usage:
#   .\sources\build-ik-llama.ps1              # Configure + build
#   .\sources\build-ik-llama.ps1 -CleanFirst  # Remove previous build before configuring
#   .\sources\build-ik-llama.ps1 -BuildOnly   # Skip configure, just build

param(
    [switch]$CleanFirst,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

# ---------- Paths ----------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SrcDir     = Join-Path $ScriptDir "ik_llama.cpp"
$BuildDir   = Join-Path $SrcDir "build"
$VcVarsAll  = "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat"
$CMakePath  = "C:\Program Files\CMake\bin\cmake.exe"
$NvccPath   = "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2/bin/nvcc.exe"

# ---------- Pre-flight ----------
if (-not (Test-Path $SrcDir)) {
    Write-Error "ik_llama.cpp source directory not found: $SrcDir`nRun: git clone https://github.com/ikawrakow/ik_llama.cpp sources/ik_llama.cpp"
    exit 1
}

# ---------- Clean ----------
if ($CleanFirst -and (Test-Path $BuildDir)) {
    Write-Host "[ik-llama] Removing previous build directory ..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildDir
}

# ---------- Configure ----------
if (-not $BuildOnly) {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }

    Write-Host "[ik-llama] Configuring ik_llama.cpp (Ninja + CUDA) ..." -ForegroundColor Cyan
    cmd /c "`"$VcVarsAll`" x64 && `"$CMakePath`" -B `"$BuildDir`" -G Ninja -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_COMPILER=`"$NvccPath`" -S `"$SrcDir`""
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ik-llama] Configure failed (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
}

# ---------- Build ----------
Write-Host "[ik-llama] Compiling (this may take several minutes) ..." -ForegroundColor Cyan
cmd /c "`"$VcVarsAll`" x64 && ninja -C `"$BuildDir`""
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ik-llama] Build failed (exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}

# ---------- Verify ----------
$BinaryPath = Join-Path $BuildDir "bin\llama-server.exe"
if (Test-Path $BinaryPath) {
    Write-Host ""
    Write-Host "[ik-llama] SUCCESS - binary at $BinaryPath" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Error "[ik-llama] Binary not found at expected path. Check build output above."
    exit 1
}
