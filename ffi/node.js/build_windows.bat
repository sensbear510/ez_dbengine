@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo [*] Setting up Node.js FFI Environment (Windows)
echo ====================================================

set NODE_DIR=%~dp0
set ROOT_DIR=%NODE_DIR%..\..\

:: 1. Ensure ez_dbengine.dll is in place
if not exist "%NODE_DIR%\ez_dbengine.dll" (
    if exist "%ROOT_DIR%build_win\bin\Release\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\Release\ez_dbengine.dll" "%NODE_DIR%\"
    ) else if exist "%ROOT_DIR%build_win\bin\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\ez_dbengine.dll" "%NODE_DIR%\"
    ) else (
        echo ❌ [Error] ez_dbengine.dll not found!
        echo 👉 Please run build_windows.bat at project root first.
        exit /b 1
    )
)
echo ✅ [OK] Dynamic library verified.

:: 2. Check if Windows-specific koffi module exists
if not exist "%NODE_DIR%\node_modules\koffi" (
    echo [*] Windows koffi not found, installing npm dependencies...
    cd /d "%NODE_DIR%"
    call npm install
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
) else (
    echo [OK] Windows dependencies already installed.
)

echo ====================================================
echo 🎉 Node.js Environment Ready!
echo 👉 Run with: cd "%NODE_DIR%" ^&^& node ez_stress_master.js
echo ====================================================
cd /d "%NODE_DIR%"
node ez_stress_master.js