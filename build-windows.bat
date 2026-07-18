@echo off
setlocal enableextensions

cd /d "%~dp0"

set "BUILD_MODE=%~1"
set "BUILD_ARCH=%~2"
if not "%~3"=="" set "QT_MAJOR_VERSION=%~3"

if "%BUILD_MODE%"=="" set "BUILD_MODE=release"
if "%BUILD_ARCH%"=="" set "BUILD_ARCH=64"
if "%QT_MAJOR_VERSION%"=="" set "QT_MAJOR_VERSION=5"

if not "%QT_MAJOR_VERSION%"=="5" if not "%QT_MAJOR_VERSION%"=="6" (
    echo Invalid Qt major version: %QT_MAJOR_VERSION%. Use 5 or 6.
    exit /b 2
)

if /I "%BUILD_MODE%"=="all" (
    call "%~dp0msvc_build.bat" release %BUILD_ARCH%
    if errorlevel 1 exit /b %errorlevel%
    call "%~dp0msvc_build.bat" install %BUILD_ARCH%
    exit /b %errorlevel%
)

call "%~dp0msvc_build.bat" %BUILD_MODE% %BUILD_ARCH%
exit /b %errorlevel%
