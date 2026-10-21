@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo [*] Building Rust Stress Master for Windows
echo ====================================================

set RUST_DIR=%~dp0
set ROOT_DIR=%RUST_DIR%..\..\
set RUN_WIN=%RUST_DIR%run_win

if not exist "%RUN_WIN%" mkdir "%RUN_WIN%"

:: 1. 確保 ez_dbengine.dll 與 ez_dbengine.lib 就位
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

:: 2. 複製測試資料
if exist "%ROOT_DIR%daily_2026-03-19.csv" (
    copy /Y "%ROOT_DIR%daily_2026-03-19.csv" "%RUN_WIN%\"
) else if exist "%RUST_DIR%daily_2026-03-19.csv" (
    copy /Y "%RUST_DIR%daily_2026-03-19.csv" "%RUN_WIN%\"
)

:: 3. 呼叫 Cargo 編譯
cd /d "%RUST_DIR%"
cargo build --release
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

:: 4. 同步執行檔至 run_win
copy /Y "%RUST_DIR%target\release\ez_stress_master.exe" "%RUN_WIN%\"

echo ====================================================
echo 🎉 Windows Rust Build Complete!
echo 📍 Output directory: %RUN_WIN%
echo 🚀 Running Stress Benchmark...
echo ====================================================

cd /d "%RUN_WIN%"
ez_stress_master.exe
cd /d "%RUST_DIR%"