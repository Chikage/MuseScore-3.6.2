@echo off
setlocal enableextensions

cd /d "%~dp0"

set "BUILD_MODE=%~1"
set "BUILD_ARCH=%~2"

if "%BUILD_MODE%"=="" set "BUILD_MODE=release"
if "%BUILD_ARCH%"=="" set "BUILD_ARCH=64"

if /I "%BUILD_MODE%"=="all" (
    call "%~dp0msvc_build.bat" release %BUILD_ARCH%
    if errorlevel 1 exit /b %errorlevel%
    call "%~dp0msvc_build.bat" install %BUILD_ARCH%
    exit /b %errorlevel%
)

call "%~dp0msvc_build.bat" %BUILD_MODE% %BUILD_ARCH%
exit /b %errorlevel%
