@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo [*] Building C# Stress Master for Windows
echo ====================================================

set CS_DIR=%~dp0
set ROOT_DIR=%CS_DIR%..\..\
set RUN_WIN=%CS_DIR%run_win

if not exist "%RUN_WIN%" mkdir "%RUN_WIN%"

:: 1. Ensure ez_dbengine.dll is in place within run_win
if not exist "%RUN_WIN%\ez_dbengine.dll" (
    if exist "%ROOT_DIR%build_win\bin\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\ez_dbengine.dll" "%RUN_WIN%\"
    ) else if exist "%ROOT_DIR%build_win\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\ez_dbengine.dll" "%RUN_WIN%\"
    ) else (
        echo ❌ [Error] ez_dbengine.dll not found!
        echo 👉 Please run build_windows.bat at project root first.
        exit /b 1
    )
)
echo ✅ [OK] Dynamic library verified.

:: 2. Publish project to run_win
echo [*] Publishing C# project to %RUN_WIN%...
cd /d "%CS_DIR%"
call dotnet publish -c Release -r win-x64 --self-contained false -o "%RUN_WIN%"
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

:: 3. Copy test datasets
if exist "%ROOT_DIR%daily_2026-03-19.csv" (
    copy /Y "%ROOT_DIR%daily_2026-03-19.csv" "%RUN_WIN%\"
) else if exist "%CS_DIR%daily_2026-03-19.csv" (
    copy /Y "%CS_DIR%daily_2026-03-19.csv" "%RUN_WIN%\"
)

echo ====================================================
echo 🎉 Windows C# Build Complete!
echo 📍 Output directory: %RUN_WIN%
echo 👉 Run with: cd /d "%RUN_WIN%" ^&^& .\ez_stress_master.exe
echo ====================================================
cd /d %RUN_WIN%
ez_stress_master.exe
cd /d "%CS_DIR%"