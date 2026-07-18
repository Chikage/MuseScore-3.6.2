@echo off
setlocal enableextensions enabledelayedexpansion

cd /d "%~dp0"

set "BUILD_MODE=%~1"
set "BUILD_ARCH=%~2"
if not "%~3"=="" set "QT_MAJOR_VERSION=%~3"

if "%BUILD_MODE%"=="" set "BUILD_MODE=release"
if "%BUILD_ARCH%"=="" set "BUILD_ARCH=64"
if "%QT_MAJOR_VERSION%"=="" set "QT_MAJOR_VERSION=6"

if not "%QT_MAJOR_VERSION%"=="5" if not "%QT_MAJOR_VERSION%"=="6" (
    echo Invalid Qt major version: %QT_MAJOR_VERSION%. Use 5 or 6.
    exit /b 2
)

if "%QT_MAJOR_VERSION%"=="6" if not "%BUILD_ARCH%"=="64" (
    echo Qt 6 Windows builds support x64 only. Use Qt 5 for the legacy x86 target.
    exit /b 2
)

if "%QT_MAJOR_VERSION%"=="6" (
    if /I "%BUILD_MODE%"=="all" (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_windows_qt6.ps1" -Configuration Release
        exit /b !errorlevel!
    )
    if /I "%BUILD_MODE%"=="install" (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_windows_qt6.ps1" -Configuration Release
        exit /b !errorlevel!
    )
    if /I "%BUILD_MODE%"=="release" (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_windows_qt6.ps1" -Configuration Release -SkipInstall
        exit /b !errorlevel!
    )
    if /I "%BUILD_MODE%"=="relwithdebinfo" (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_windows_qt6.ps1" -Configuration RelWithDebInfo -SkipInstall
        exit /b !errorlevel!
    )
    if /I "%BUILD_MODE%"=="debug" (
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_windows_qt6.ps1" -Configuration Debug -SkipInstall
        exit /b !errorlevel!
    )
    echo Unsupported Qt 6 build mode: %BUILD_MODE%.
    echo Use release, relwithdebinfo, debug, install, or all.
    exit /b 2
)

if /I "%BUILD_MODE%"=="all" (
    call "%~dp0msvc_build.bat" release %BUILD_ARCH%
    if errorlevel 1 exit /b !errorlevel!
    call "%~dp0msvc_build.bat" install %BUILD_ARCH%
    exit /b !errorlevel!
)

call "%~dp0msvc_build.bat" %BUILD_MODE% %BUILD_ARCH%
exit /b !errorlevel!
