@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo [*] Building Flutter Stress App for Windows
echo ====================================================

set FLUTTER_DIR=%~dp0
set ROOT_DIR=%FLUTTER_DIR%..\..\
set RUN_WIN=%FLUTTER_DIR%run_win
set PKG_DIR=%FLUTTER_DIR%ez_dbengine
set TEST_APP_DIR=%FLUTTER_DIR%test\ez_stress_app

if not exist "%RUN_WIN%" mkdir "%RUN_WIN%"

:: 1. Verify and ensure ez_dbengine.dll is present in run_win
if not exist "%RUN_WIN%\ez_dbengine.dll" (
    if exist "%ROOT_DIR%build_win\bin\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\bin\ez_dbengine.dll" "%RUN_WIN%\"
    ) else if exist "%ROOT_DIR%build_win\ez_dbengine.dll" (
        copy /Y "%ROOT_DIR%build_win\ez_dbengine.dll" "%RUN_WIN%\"
    ) else (
        echo ❌ [Error] ez_dbengine.dll not found in %RUN_WIN%!
        echo 👉 Please run build_windows.bat at project root first.
        exit /b 1
    )
)
echo ✅ [OK] Dynamic library verified.

:: 2. Resolve fixed version dependencies
echo [*] Resolving dependencies with flutter pub get...
cd /d "%PKG_DIR%"
call flutter pub get
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

cd /d "%TEST_APP_DIR%"
call flutter pub get
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

:: 3. Build full Windows Release App via Flutter
echo [*] Compiling Windows App via flutter build windows --release...
call flutter build windows --release
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

:: 4. Sync Flutter Release artifacts to run_win
set BUNDLE_DIR=%TEST_APP_DIR%\build\windows\x64\runner\Release
echo [*] Syncing runner artifacts into %RUN_WIN%...
xcopy /E /Y /Q "%BUNDLE_DIR%\*" "%RUN_WIN%\"

echo ====================================================
echo 🎉 Windows Flutter App Build Complete!
echo 📍 Output directory: %RUN_WIN%
echo 👉 Run with: %RUN_WIN%\ez_stress_app.exe
echo ====================================================
cd /d %RUN_WIN%
ez_stress_app.exe
cd /d "%FLUTTER_DIR%"