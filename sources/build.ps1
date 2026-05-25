Remove-Item -Recurse "~\Documents\github\beellama\sources\beellama.cpp_fork\build" -Force; 
#cmd /c "`"C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat`" x64 && ninja -C `"C:\Users\brock\Documents\github\beellama\beellama.cpp_fork\build`""

mkdir "~\Documents\github\beellama\sources\beellama.cpp_fork\build"

cd "~\Documents\github\beellama\sources\beellama.cpp_fork\build"

cmd /c "`"C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat`" x64 && `"C:\Program Files\CMake\bin\cmake.exe`" -B build -G Ninja -DGGML_CUDA=ON -DGGML_NATIVE=ON -DGGML_CUDA_FA=ON -DGGML_CUDA_FA_ALL_QUANTS=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_COMPILER=`"C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.2/bin/nvcc.exe`" -S `"C:\Users\brock\Documents\github\beellama\sources\beellama.cpp_fork`""

cmd /c "`"C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat`" x64 && ninja -C `"C:\Users\brock\Documents\github\beellama\beellama.cpp_fork\build`""


#& C:\Users\brock\Documents\github\beellama\run_Q4_MTP_native.ps1