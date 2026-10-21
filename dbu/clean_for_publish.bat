@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo [ez_dbengine] Cleaning build cache and local files...
echo ===================================================

REM 1. Remove temporary log files
if exist "output.log" (
    echo Deleting output.log...
    del /f /q "output.log"
)

REM 2. Clean Dart / Flutter caches (.dart_tool, .flutter-plugins*)
echo [1/8] Cleaning Dart/Flutter tool caches and dependency files...
for /d /r . %%d in (.dart_tool) do (
    if exist "%%d" rd /s /q "%%d"
)
del /s /f /q .flutter-plugins-dependencies 2>nul
del /s /f /q .flutter-plugins 2>nul

REM 3. Clean platform ephemeral engine artifacts
echo [2/8] Cleaning platform ephemeral directories...
for /d /r . %%d in (ephemeral) do (
    if exist "%%d" rd /s /q "%%d"
)

REM 4. Clean build output directories (build, obj, bin)
echo [3/8] Cleaning build, obj, and bin directories...
for /d /r . %%d in (build) do (
    if exist "%%d" rd /s /q "%%d"
)
for /d /r . %%d in (obj) do (
    if exist "%%d" rd /s /q "%%d"
)
if exist "ffi\cs\bin" rd /s /q "ffi\cs\bin"

REM 5. Clean Android local configuration and Gradle cache
echo [4/8] Cleaning Android local environment and cache (.gradle, local.properties)...
for /d /r . %%d in (.gradle) do (
    if exist "%%d" rd /s /q "%%d"
)
for /d /r . %%d in (.kotlin) do (
    if exist "%%d" rd /s /q "%%d"
)
del /s /f /q local.properties 2>nul

REM 6. Clean IDE settings (.idea, *.iml, .vs)
echo [5/8] Cleaning IDE configuration files (.idea, *.iml, .vs)...
for /d /r . %%d in (.idea) do (
    if exist "%%d" rd /s /q "%%d"
)
for /d /r . %%d in (.vs) do (
    if exist "%%d" rd /s /q "%%d"
)
del /s /f /q *.iml 2>nul

REM 7. Clean C++ CMake / MSVC build directories and objects
echo [6/8] Cleaning C++ intermediate build artifacts...
if exist "ffi\cpp\build_linux" rd /s /q "ffi\cpp\build_linux"
if exist "ffi\cpp\build_win" rd /s /q "ffi\cpp\build_win"
del /s /f /q *.pdb *.ilk *.exp *.obj *.o 2>nul

REM 8. Clean Node.js modules
echo [7/8] Cleaning Node.js node_modules...
if exist "ffi\node.js\node_modules" rd /s /q "ffi\node.js\node_modules"

echo ===================================================
echo [8/8] Cleanup complete! Project is clean for release.
echo Downstream build steps:
echo   - Flutter/Dart: run 'flutter pub get'
echo   - Node.js:      run 'npm install'
echo   - C++ / C#:     run the respective build scripts
echo ===================================================
pause