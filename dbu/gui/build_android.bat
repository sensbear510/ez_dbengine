@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: 1. Parameter validation and build mode normalization (Default: Release)
set "BUILD_TYPE=Release"
set "FLUTTER_MODE=release"
set "APK_FILENAME=app-release.apk"

if /i "%~1"=="debug" (
    set "BUILD_TYPE=Debug"
    set "FLUTTER_MODE=debug"
    set "APK_FILENAME=app-debug.apk"
) else if /i "%~1"=="release" (
    set "BUILD_TYPE=Release"
    set "FLUTTER_MODE=release"
    set "APK_FILENAME=app-release.apk"
) else if not "%~1"=="" (
    echo [ERROR] Invalid build mode: "%~1"
    echo Usage: %~nx0 [release^|debug]
    exit /b 1
)

echo ==============================================================================
echo [ez_engine] Building Android APK (!BUILD_TYPE!) ...
echo ==============================================================================

:: 2. Execute Flutter Android build
call flutter build apk --!FLUTTER_MODE!
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Flutter build apk failed!
    exit /b !ERRORLEVEL!
)

:: 3. Locate source APK directory
set "SRC_DIR=%~dp0build\app\outputs\flutter-apk"
set "SRC_APK=!SRC_DIR!\!APK_FILENAME!"

if not exist "!SRC_APK!" (
    echo [ERROR] Generated APK artifact not found: !SRC_APK!
    exit /b 1
)

:: 4. Target release path: %USERPROFILE%\work\ez_dbengine\dbu\gui\run_android\<BUILD_TYPE>
set "DEST_DIR=%USERPROFILE%\work\ez_dbengine\dbu\gui\run_android\!BUILD_TYPE!"
if not exist "!DEST_DIR!" (
    mkdir "!DEST_DIR!" 2>nul
)

:: 5. Copy and rename APK to lowercase ezdbutility.apk
set "DEST_APK=!DEST_DIR!\ezdbutility.apk"
echo [*] Copying !SRC_APK! to !DEST_APK! ...
copy /y "!SRC_APK!" "!DEST_APK!" >nul
if !ERRORLEVEL! NEQ 0 (
    echo [ERROR] Failed to copy APK!
    exit /b 1
)

:: Synchronize SHA-1 checksum if generated
if exist "!SRC_DIR!\app.apk.sha1" (
    copy /y "!SRC_DIR!\app.apk.sha1" "!DEST_DIR!\ezdbutility.apk.sha1" >nul 2>&1
)

echo ==============================================================================
echo [SUCCESS] Android APK (!BUILD_TYPE!) Build Finished!
echo Environment Path:
echo   !DEST_DIR!\
echo Package File:
echo   !DEST_APK!
echo ==============================================================================

:END
endlocal