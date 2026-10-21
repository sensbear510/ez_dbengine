@echo off
setlocal

set "BUILD_DIR=build_windows"

echo [1/3] Setting up build directory for CLI (Windows)...
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd "%BUILD_DIR%"

echo [2/3] Running CMake configuration...
cmake -G "Visual Studio 17 2022" -A x64 ..

echo [3/3] Compiling EZ-Shell CLI...
cmake --build . --config Debug

if %errorlevel% neq 0 goto :error

echo [4/4] Moving executable binaries to project root...
copy /y "bin\Debug\ez_shell.exe" "..\"
copy /y "bin\Debug\ez_test_agent.exe" "..\"

cd ..
echo -----------------------------------------------
echo Windows CLI Build Completed Successfully!
goto :end

:error
echo.
echo ===============================================
echo [ERROR] Build failed during the process!
echo ===============================================
cd ..
exit /b %errorlevel%

:end
endlocal