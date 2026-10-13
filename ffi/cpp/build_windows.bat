@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo [*] Building C++ FFI Targets for Windows
echo ====================================================

set CPP_DIR=%~dp0
set ROOT_DIR=%CPP_DIR%..\..\
set RUN_WIN=%CPP_DIR%run_win

if not exist "%RUN_WIN%" mkdir "%RUN_WIN%"

:: 1. Check and acquire ez_dbengine.dll and import lib
if not exist "%RUN_WIN%\ez_dbengine.dll" (
    if exist "%ROOT_DIR%build_win\bin\Release\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\Release\ez_dbengine.dll" "%RUN_WIN%\"
    ) else if exist "%ROOT_DIR%build_win\bin\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\ez_dbengine.dll" "%RUN_WIN%\"
    ) else (
        echo ❌ [Error] ez_dbengine.dll not found!
        echo 👉 Please run build_windows.bat at project root first.
        exit /b 1
    )
)

if not exist "%RUN_WIN%\ez_dbengine.lib" (
    if exist "%ROOT_DIR%build_win\lib\Release\ez_dbengine.lib" (
        copy /Y "%ROOT_DIR%build_win\lib\Release\ez_dbengine.lib" "%RUN_WIN%\"
    ) else if exist "%ROOT_DIR%build_win\lib\ez_dbengine.lib" (
        copy /Y "%ROOT_DIR%build_win\lib\ez_dbengine.lib" "%RUN_WIN%\"
    )
)
echo ✅ [OK] Windows libraries verified.

:: 2. Copy test datasets
if exist "%ROOT_DIR%daily_2026-03-19.csv" (
    copy /Y "%ROOT_DIR%daily_2026-03-19.csv" "%RUN_WIN%\"
) else if exist "%CPP_DIR%daily_2026-03-19.csv" (
    copy /Y "%CPP_DIR%daily_2026-03-19.csv" "%RUN_WIN%\"
)

:: 3. Invoke CMake to build test project (using dedicated Windows directory build_win)
set BUILD_DIR=%CPP_DIR%build_win
:: Purge and recreate build directory if Linux forward-slash path cache is detected to ensure clean state
if exist "%BUILD_DIR%\CMakeCache.txt" (
    findstr /C:"/home/" "%BUILD_DIR%\CMakeCache.txt" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo 🧹 [Clean] Detected foreign Linux CMakeCache, purging build directory...
        rmdir /s /q "%BUILD_DIR%"
    )
)
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"
cmake ..
cmake --build . --config Release
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

echo ====================================================
echo 🎉 Windows C++ Build Complete!
echo 📍 Output directory: %RUN_WIN%
echo ====================================================
cd /d %RUN_WIN%
ez_stress_master.exe
cd /d "%CPP_DIR%"