# setup-dependencies.ps1
# Validates that all required build tools are available for compiling beellama.cpp.
# Reports what is found and what is missing.
#
# Required: MSVC (cl.exe via vcvarsall.bat), CUDA toolkit, Ninja, CMake
# Usage:    .\sources\setup-dependencies.ps1

$ErrorActionPreference = "Continue"

Write-Host "`n=== BeeLlama Build Dependencies ===" -ForegroundColor Cyan

$allGood = $true

# ---------- MSVC ----------
$vcvarsall = "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat"
if (Test-Path $vcvarsall) {
    Write-Host "[OK]  MSVC vcvarsall.bat found" -ForegroundColor Green
    Write-Host "      $vcvarsall" -ForegroundColor DarkGray
} else {
    Write-Host "[MISSING] MSVC vcvarsall.bat not found at expected path" -ForegroundColor Red
    Write-Host "          Expected: $vcvarsall" -ForegroundColor DarkGray
    Write-Host "          Install Visual Studio with C++ workload" -ForegroundColor Yellow
    $allGood = $false
}

# ---------- CUDA ----------
$cudaPath = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2"
$nvcc = Join-Path $cudaPath "bin\nvcc.exe"
if (Test-Path $nvcc) {
    $nvccVersion = & $nvcc --version 2>&1 | Select-String "release" | ForEach-Object { $_.ToString().Trim() }
    Write-Host "[OK]  CUDA toolkit found" -ForegroundColor Green
    Write-Host "      $nvccVersion" -ForegroundColor DarkGray
} else {
    Write-Host "[MISSING] CUDA toolkit (nvcc) not found" -ForegroundColor Red
    Write-Host "          Expected: $nvcc" -ForegroundColor DarkGray
    Write-Host "          Install CUDA Toolkit from https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
    $allGood = $false
}

# ---------- Ninja ----------
$ninja = Get-Command ninja -ErrorAction SilentlyContinue
if ($ninja) {
    $ninjaVersion = & ninja --version 2>&1
    Write-Host "[OK]  Ninja found ($ninjaVersion)" -ForegroundColor Green
    Write-Host "      $($ninja.Source)" -ForegroundColor DarkGray
} else {
    Write-Host "[MISSING] Ninja not found on PATH" -ForegroundColor Red
    Write-Host "          Install via: winget install Ninja-build.Ninja" -ForegroundColor Yellow
    $allGood = $false
}

# ---------- CMake ----------
$cmake = Get-Command cmake -ErrorAction SilentlyContinue
if ($cmake) {
    $cmakeVersion = & cmake --version 2>&1 | Select-Object -First 1
    Write-Host "[OK]  CMake found ($cmakeVersion)" -ForegroundColor Green
    Write-Host "      $($cmake.Source)" -ForegroundColor DarkGray
} else {
    Write-Host "[MISSING] CMake not found on PATH" -ForegroundColor Red
    Write-Host "          Install via: winget install Kitware.CMake" -ForegroundColor Yellow
    $allGood = $false
}

# ---------- Git ----------
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $gitVersion = & git --version 2>&1
    Write-Host "[OK]  Git found ($gitVersion)" -ForegroundColor Green
} else {
    Write-Host "[MISSING] Git not found on PATH" -ForegroundColor Red
    $allGood = $false
}

# ---------- Summary ----------
Write-Host ""
if ($allGood) {
    Write-Host "All dependencies found. Ready to build." -ForegroundColor Green
} else {
    Write-Host "Some dependencies are missing. Install them and re-run this script." -ForegroundColor Yellow
}
