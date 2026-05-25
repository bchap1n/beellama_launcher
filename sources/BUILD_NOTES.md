# Build Session Notes — 2026-05-18

## Problem

CMake 4.3 (via Scoop) was failing with:
```
CMake Error at CMakeDetermineCompilerId.cmake:682: No CUDA toolset found.
```
at `ggml/src/ggml-cuda/CMakeLists.txt:58 (enable_language)`.

**Root cause**: CMake 4.3 has a bug where `enable_language(CUDA)` in a subdirectory (after a nested `project()` call in `ggml/CMakeLists.txt`) fails to discover the CUDA compiler with CUDA 13.2, even though `find_package(CUDAToolkit)` succeeds.

## Environment

- **OS**: Windows 11
- **VS**: Visual Studio 2026 Insiders (v18.7.0) — only VS installation
- **CUDA**: 13.2.78 at `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.2\`
- **Scoop CMake**: 4.3.2 (broken)

## What We Tried (and Failed)

| Attempt | Result |
|---------|--------|
| `-DCMAKE_CUDA_COMPILER=<path>` | Cache var doesn't survive nested `project()` boundary |
| `set CMAKE_CUDA_COMPILER` env var | Same — subdirectory `project()` resets state |
| Patch `ggml/src/ggml-cuda/CMakeLists.txt` to set `CMAKE_CUDA_COMPILER` from `CUDAToolkit_NVCC_COMPILER` | Still failed — CMake 4.3's language detection is broken |
| CMake 3.28.3 + VS generator | Too old to recognize VS 2026 Insiders |
| CMake 3.28.3 + Ninja | Same — doesn't know about VS 2026 |
| CMake 3.31.8 + VS generator | Still doesn't recognize VS 2026 Insiders |

## What Worked

**CMake 3.31.8 + Ninja generator + explicit nvcc path**

- CMake 3.31.8 was installed via MSI to `C:\Program Files\CMake\` (not via Scoop)
- Ninja was used as the generator (not the VS project generator) — this was necessary because CMake 3.31.8 doesn't recognize Visual Studio 2026 Insiders
- Ninja still uses the MSVC compilers (`cl.exe`) for C/C++ — it only changes the build system, not the compilers
- CUDA compiler (`nvcc.exe`) was passed explicitly via `-DCMAKE_CUDA_COMPILER`

### Configure command
```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat" x64
& "C:\Program Files\CMake\bin\cmake.exe" -B build -G Ninja ^
  -DGGML_CUDA=ON -DGGML_NATIVE=ON ^
  -DGGML_CUDA_FA=ON -DGGML_CUDA_FA_ALL_QUANTS=ON ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_COMPILER='C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2/bin/nvcc.exe' ^
  -S "C:\Users\brock\Documents\github\beellama\beellama.cpp_fork"
```

### Build command
```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat" x64
cd C:\Users\brock\Documents\github\beellama\beellama.cpp_fork\build
ninja
```

## VS vs Ninja — Clarification

We used **Ninja**, not the Visual Studio project generator. Key difference:

| | VS Generator | Ninja (what we used) |
|---|---|---|
| Build system | `.sln` + `.vcxproj` files, built by MSBuild | `build.ninja`, built by `ninja` |
| Compilers | MSVC (`cl.exe`) | MSVC (`cl.exe`) — same |
| CUDA support | VS generator + CMake | Ninja + CMake — same |
| IDE integration | Full VS IDE support | No native VS IDE integration |
| Why we needed it | CMake 3.31.8 doesn't know about VS 2026 | Ninja doesn't care about VS version |

**Bottom line**: the compilers (MSVC + nvcc) are identical. Only the build orchestration layer differs. The binaries are the same quality.

## Persistent State

- CMake 3.31.8 installed at `C:\Program Files\CMake\` (MSI, outside Scoop)
- Scoop's CMake is held (pinned) to prevent auto-upgrade back to 4.x
- Scoop's CMake shim is broken (points to an uninstalled version) — ignore it, use the MSI-installed CMake directly
- No code changes were needed — the `ggml/src/ggml-cuda/CMakeLists.txt` patch was reverted

## To Rebuild

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat" x64
"C:\Program Files\CMake\bin\cmake.exe" --build build
```

## To Reconfigure (e.g., after changing CMake options)

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat" x64
"C:\Program Files\CMake\bin\cmake.exe" -B build -G Ninja ^
  -DGGML_CUDA=ON -DGGML_NATIVE=ON ^
  -DGGML_CUDA_FA=ON -DGGML_CUDA_FA_ALL_QUANTS=ON ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_CUDA_COMPILER='C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2/bin/nvcc.exe' ^
  -S "C:\Users\brock\Documents\github\beellama\beellama.cpp_fork"
ninja -C build
```
