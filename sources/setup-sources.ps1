# setup-sources.ps1
# Clones or updates the beellama.cpp source repositories into /sources.
# Run this once after cloning the beellama repo, or any time you want to pull updates.
#
# Usage:
#   .\sources\setup-sources.ps1             # Clone if missing, pull if present
#   .\sources\setup-sources.ps1 -ForceClone # Remove and re-clone

param([switch]$ForceClone)

$ErrorActionPreference = "Stop"
$SourcesDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$repos = @(
    @{
        Name   = "beellama.cpp"
        Url    = "https://github.com/Anbeeld/beellama.cpp.git"
        Branch = "main"
    },
    @{
        Name   = "beellama.cpp_fork"
        Url    = "https://github.com/bchap1n/beellama.cpp.git"
        Branch = "mtp-support"
    },
    @{
        Name   = "llama.cpp"
        Url    = "https://github.com/ggml-org/llama.cpp.git"
        Branch = "master"
    }
)

foreach ($repo in $repos) {
    $targetDir = Join-Path $SourcesDir $repo.Name

    if ($ForceClone -and (Test-Path $targetDir)) {
        Write-Host "[setup] Removing existing $($repo.Name)..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $targetDir
    }

    if (-not (Test-Path $targetDir)) {
        Write-Host "[setup] Cloning $($repo.Name) ($($repo.Url) @ $($repo.Branch))..." -ForegroundColor Cyan
        git clone --branch $repo.Branch --single-branch $repo.Url $targetDir
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to clone $($repo.Name)"
            continue
        }
        Write-Host "[setup] $($repo.Name) cloned successfully." -ForegroundColor Green
    } else {
        Write-Host "[setup] Updating $($repo.Name)..." -ForegroundColor Cyan
        Push-Location $targetDir
        try {
            git fetch origin
            git pull --ff-only
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Pull failed for $($repo.Name). You may need to resolve conflicts manually."
            } else {
                Write-Host "[setup] $($repo.Name) updated." -ForegroundColor Green
            }
        } finally {
            Pop-Location
        }
    }
}

Write-Host ""
Write-Host "[setup] Done. Sources are in: $SourcesDir" -ForegroundColor Green
Write-Host "Next steps:"
Write-Host "  1. Run .\sources\setup-dependencies.ps1 to verify build tools"
Write-Host "  2. Run .\sources\build-beellama.ps1 or .\sources\build-beellama-fork.ps1"
Write-Host "  3. Run .\sources\build-llama-cpp.ps1 (upstream, for n-gram speculation)"
