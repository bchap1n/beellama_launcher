# build-llama-cpp.ps1
# Builds upstream llama.cpp from source with CUDA + n-gram speculation support.
# Target: sources/llama.cpp
#
# Tracks upstream main to get new features like --spec-ngram-map-k4v-size-m
# (commit b9235+) before they land in forks.
#
# Usage:
#   .\sources\build-llama-cpp.ps1              # Configure + build
#   .\sources\build-llama-cpp.ps1 -CleanFirst  # Remove previous build before configuring
#   .\sources\build-llama-cpp.ps1 -BuildOnly   # Skip configure, just build

param(
    [switch]$CleanFirst,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

# ---------- Paths ----------
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SrcDir     = Join-Path $ScriptDir "llama.cpp"
$BuildDir   = Join-Path $SrcDir "build"
$VcVarsAll  = "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat"
$CMakePath  = "C:\Program Files\CMake\bin\cmake.exe"
$NvccPath   = "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2/bin/nvcc.exe"

# ---------- Pre-flight ----------
if (-not (Test-Path $SrcDir)) {
    Write-Error "Source directory not found: $SrcDir`nRun setup-sources.ps1 first."
    exit 1
}

# ---------- Clean ----------
if ($CleanFirst -and (Test-Path $BuildDir)) {
    Write-Host "[build] Removing previous build directory ..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BuildDir
}

# ---------- Configure ----------
if (-not $BuildOnly) {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    }

    Write-Host "[build] Configuring upstream llama.cpp (Ninja + CUDA) ..." -ForegroundColor Cyan
    cmd /c "`"$VcVarsAll`" x64 && `"$CMakePath`" -B `"$BuildDir`" -G Ninja -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON -DGGML_CUDA_FA_ALL_QUANTS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_COMPILER=`"$NvccPath`" -S `"$SrcDir`""
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[build] Configure failed (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
}

# ---------- Build ----------
Write-Host "[build] Compiling (this may take several minutes) ..." -ForegroundColor Cyan
cmd /c "`"$VcVarsAll`" x64 && ninja -C `"$BuildDir`""
if ($LASTEXITCODE -ne 0) {
    Write-Error "[build] Build failed (exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}

# ---------- Verify ----------
$BinaryPath = Join-Path $BuildDir "bin\llama-server.exe"
if (Test-Path $BinaryPath) {
    Write-Host ""
    Write-Host "[build] SUCCESS - binary at $BinaryPath" -ForegroundColor Green

    # Verify n-gram speculation support
    Write-Host ""
    Write-Host "[build] Checking for n-gram speculation support ..." -ForegroundColor Yellow
    $help = & $BinaryPath --help 2>&1 | Out-String
    if ($help -match "spec-ngram-map-k4v") {
        Write-Host "[build] --spec-ngram-map-k4v-size-m: AVAILABLE" -ForegroundColor Green
    } else {
        Write-Host "[build] --spec-ngram-map-k4v-size-m: NOT FOUND (commit may predate b9235)" -ForegroundColor DarkYellow
    }
} else {
    Write-Host ""
    Write-Error "[build] Binary not found at expected path. Check build output above."
    exit 1
}
