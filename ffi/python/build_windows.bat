@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo [*] Setting up Python FFI Environment (Windows)
echo ====================================================

set PY_DIR=%~dp0
set ROOT_DIR=%PY_DIR%..\..\

:: 1. 確保 ez_dbengine.dll 就位
if not exist "%PY_DIR%\ez_dbengine.dll" (
    if exist "%ROOT_DIR%build_win\bin\Release\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\Release\ez_dbengine.dll" "%PY_DIR%\"
    ) else if exist "%ROOT_DIR%build_win\bin\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\ez_dbengine.dll" "%PY_DIR%\"
    ) else (
        echo ❌ [Error] ez_dbengine.dll not found!
        echo 👉 Please run build_windows.bat at project root first.
        exit /b 1
    )
)
echo ✅ [OK] Dynamic library verified.

:: 2. 複製測試資料
if exist "%ROOT_DIR%daily_2026-03-19.csv" (
    copy /Y "%ROOT_DIR%daily_2026-03-19.csv" "%PY_DIR%\"
)

echo ====================================================
echo 🎉 Python Environment Ready!
echo 👉 Run with: cd %PY_DIR% && python test_ez_stress.py
echo ====================================================
cd /d "%PY_DIR%"