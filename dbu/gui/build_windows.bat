@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: 1. Parameter validation and build mode normalization (Default: Release)
set "BUILD_TYPE=Release"
set "FLUTTER_MODE=release"

if /i "%~1"=="debug" (
    set "BUILD_TYPE=Debug"
    set "FLUTTER_MODE=debug"
) else if /i "%~1"=="release" (
    set "BUILD_TYPE=Release"
    set "FLUTTER_MODE=release"
) else if not "%~1"=="" (
    echo [ERROR] Invalid build mode: "%~1"
    echo Usage: %~nx0 [release^|debug]
    exit /b 1
)

echo ==============================================================================
echo [ez_engine] Building Windows GUI (!BUILD_TYPE!) ...
echo ==============================================================================

:: 2. Execute Flutter Windows build
call flutter build windows --!FLUTTER_MODE!
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Flutter build windows failed!
    exit /b !ERRORLEVEL!
)

:: 3. Locate source bundle directory
set "SRC_BUNDLE=%~dp0build\windows\x64\runner\!BUILD_TYPE!"
if not exist "!SRC_BUNDLE!" (
    set "SRC_BUNDLE=%~dp0build\windows\runner\!BUILD_TYPE!"
)

if not exist "!SRC_BUNDLE!" (
    echo [ERROR] Source build directory not found: !SRC_BUNDLE!
    exit /b 1
)

:: 4. Target release path: %USERPROFILE%\work\ez_dbengine\dbu\gui\run_win\<BUILD_TYPE>
set "DEST_DIR=%USERPROFILE%\work\ez_dbengine\dbu\gui\run_win\!BUILD_TYPE!"
if not exist "!DEST_DIR!" (
    mkdir "!DEST_DIR!" 2>nul
)

echo [*] Synchronizing files from !SRC_BUNDLE! to !DEST_DIR! ...
xcopy "!SRC_BUNDLE!\*" "!DEST_DIR!\" /E /Y /I /Q >nul
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Failed to copy files!
    exit /b 1
)

:: 5. Rename executable to ezDBUtility.exe
if exist "!DEST_DIR!\gui.exe" (
    if exist "!DEST_DIR!\ezDBUtility.exe" del /f /q "!DEST_DIR!\ezDBUtility.exe"
    ren "!DEST_DIR!\gui.exe" ezDBUtility.exe
)

echo ==============================================================================
echo [SUCCESS] Windows GUI (!BUILD_TYPE!) Build Finished!
echo Environment Path:
echo   !DEST_DIR!\
echo Executable:
echo   !DEST_DIR!\ezDBUtility.exe
echo ==============================================================================

:: 6. Package installer via Inno Setup (Release mode only)
if /i "!BUILD_TYPE!"=="Debug" (
    echo [*] Debug mode active. Skipping Inno Setup packaging.
    goto :END
)

echo.
echo ==============================================================================
echo [ez_engine] Building Installer via Inno Setup ...
echo ==============================================================================

set "ISS_FILE=%~dp0installer.iss"
if not exist "!ISS_FILE!" (
    echo [WARN] installer.iss not found. Skipping installer generation.
    goto :END
)

:: Locate iscc.exe executable
set "ISCC_CMD="
where iscc >nul 2>nul
if !ERRORLEVEL! EQU 0 (
    set "ISCC_CMD=iscc"
) else if exist "%ProgramFiles(x86)%\Inno Setup 6\iscc.exe" (
    set "ISCC_CMD=%ProgramFiles(x86)%\Inno Setup 6\iscc.exe"
) else if exist "%ProgramFiles%\Inno Setup 6\iscc.exe" (
    set "ISCC_CMD=%ProgramFiles%\Inno Setup 6\iscc.exe"
) else if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\iscc.exe" (
    set "ISCC_CMD=%LOCALAPPDATA%\Programs\Inno Setup 6\iscc.exe"
)

if "!ISCC_CMD!"=="" (
    echo [ERROR] iscc.exe not found! Please verify Inno Setup 6 is installed or added to PATH.
    exit /b 1
)

:: Compile installer
echo [*] Compiler: "!ISCC_CMD!"
"!ISCC_CMD!" "!ISS_FILE!"
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Inno Setup packaging failed!
    exit /b !ERRORLEVEL!
)

echo ==============================================================================
echo [SUCCESS] Installer Package Created Successfully!
echo ==============================================================================

:END
endlocal