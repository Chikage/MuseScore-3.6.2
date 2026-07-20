@echo off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
PUSHD "%~dp0"
CALL :MAIN %*
SET "SCRIPT_EXIT_CODE=!ERRORLEVEL!"
POPD
EXIT /B !SCRIPT_EXIT_CODE!

:MAIN

REM Default build is 64-bit
REM 32-bit compilation is available using "32" as a second parameter when you run msvc_build.bat
REM How to use:
REM BUILD 64-bit:
REM    "msvc_build.bat debug" builds 64-bit Debug version of MuseScore without optimizations
REM    "msvc_build.bat relwithdebinfo" builds optimized 64-bit version of MuseScore with almost all debug symbols
REM    "msvc_build.bat release" builds fully optimized 64-bit version of MuseScore without command line output
REM
REM BUILD 32-bit:
REM    "msvc_build.bat debug 32" builds 32-bit Debug version of MuseScore
REM    "msvc_build.bat relwithdebinfo 32" builds 32-bit RelWithDebInfo version of MuseScore
REM    "msvc_build.bat release 32" builds 32-bit Release version of MuseScore
REM
REM INSTALL 64-bit:
REM    "msvc_build.bat install" put all required files of 64-bit Release build to install folder (msvc.install_x64)
REM    "msvc_build.bat installdebug" put all required files of 64-bit Debug build to install folder (msvc.install_x64)
REM    "msvc_build.bat installrelwithdebinfo" put all required files of 64-bit RelWithDebInfo build to install folder (msvc.install_x64)
REM
REM INSTALL 32-bit:
REM    "msvc_build.bat install 32" put all required files of 32-bit Release build to install folder (msvc.install_x86)
REM    "msvc_build.bat installdebug 32" put all required files of 32-bit Debug build to install folder (msvc.install_x86)
REM    "msvc_build.bat installrelwithdebinfo 32" put all required files of 32-bit RelWithDebInfo build to install folder (msvc.install_x86)
REM
REM PACKAGE:
REM    "msvc_build.bat package" pack the installer for already built and installed 64-bit Release build (msvc.build_x64/MuseScore-*.msi)
REM    "msvc_build.bat package 32" pack the installer for already built and installed 32-bit Release build (msvc.build_x86/MuseScore-*.msi)
REM
REM CLEAN:
REM    "msvc_build.bat clean" remove all files in msvc.* folders and the folders itself
REM
REM Windows Portable build is triggered by defining BUILD_WIN_PORTABLE environment variable to "ON" before launching this script, e.g.
REM SET BUILD_WIN_PORTABLE=ON

REM BUILD_64 and BUILD_FOR_WINSTORE are used in CMakeLists.txt
SET BUILD_FOR_WINSTORE=OFF
SET "BUILD_FOLDER=msvc.build"
SET "INSTALL_FOLDER=msvc.install"

IF "%2"=="32" (
    SET PLATFORM_NAME=Win32
    SET "ARCH=x86"
    SET BUILD_64=OFF
) ELSE (
    IF NOT "%2"=="" (
        IF NOT "%2"=="64" (
            echo Invalid second argument
            EXIT /B 2
        ) ELSE (
            SET PLATFORM_NAME=x64
            SET "ARCH=x64"
            SET BUILD_64=ON
        )
    ) ELSE (
        SET PLATFORM_NAME=x64
        SET "ARCH=x64"
        SET BUILD_64=ON
    )
)

IF NOT "%3"=="" (
   SET BUILD_NUMBER="%3"
   SET BUILD_AUTOUPDATE="ON"
)

ECHO "BUILD_WIN_PORTABLE: %BUILD_WIN_PORTABLE%"
IF "%BUILD_WIN_PORTABLE%"=="ON" (
    SET "INSTALL_FOLDER=MuseScorePortable\App\MuseScore"
    SET "BUILD_AUTOUPDATE=OFF"
    SET "WIN_PORTABLE_OPT=-DBUILD_PORTABLEAPPS=ON"
)

ECHO "INSTALL_FOLDER: %INSTALL_FOLDER%"
ECHO "WIN_PORTABLE_OPT: %WIN_PORTABLE_OPT%"

IF /I "%1"=="release" (
   SET CONFIGURATION_STR="release"
   GOTO :BUILD
)

IF /I "%1"=="debug" (
   SET CONFIGURATION_STR="debug"
   GOTO :BUILD
)

IF /I "%1"=="relwithdebinfo" (
   SET CONFIGURATION_STR="relwithdebinfo"
   GOTO :BUILD
)

IF /I "%1"=="install" (
   SET "BUILD_FOLDER=%BUILD_FOLDER%_%ARCH%"
   SET CONFIGURATION_STR="release"
   GOTO :INSTALL
)

IF /I "%1"=="installdebug" (
   SET "BUILD_FOLDER=%BUILD_FOLDER%_%ARCH%"
   SET CONFIGURATION_STR="debug"
   GOTO :INSTALL
)

IF /I "%1"=="installrelwithdebinfo" (
   SET "BUILD_FOLDER=%BUILD_FOLDER%_%ARCH%"
   SET CONFIGURATION_STR="relwithdebinfo"
   GOTO :INSTALL
)

IF /I "%1"=="package" (
   CALL :SETUP_BUILD_ENVIRONMENT
   IF ERRORLEVEL 1 GOTO :FAIL
   cd "%BUILD_FOLDER%_%ARCH%"
   cmake --build . --config RelWithDebInfo --target package
   EXIT /B !ERRORLEVEL!
)

IF /I "%1"=="revision" (
   echo revisionStep
   git rev-parse --short=7 HEAD > local_build_revision.env
   GOTO :END
)

IF /I "%1"=="clean" (
   for /d %%G in ("msvc.*") do rd /s /q "%%~G"
   for /d %%G in ("MuseScorePortable") do rd /s /q "%%~G"
   GOTO :END
) ELSE (
   echo No valid parameters are set
   EXIT /B 2
)

:SETUP_BUILD_ENVIRONMENT
   CALL :FIND_VISUAL_STUDIO
   IF ERRORLEVEL 1 EXIT /B 1

   CALL :ACTIVATE_VISUAL_STUDIO
   IF ERRORLEVEL 1 EXIT /B 1

   CALL :FIND_CMAKE
   IF ERRORLEVEL 1 EXIT /B 1

   CALL :FIND_QT
   IF ERRORLEVEL 1 EXIT /B 1

   EXIT /B 0

:FIND_VISUAL_STUDIO
   REM VS_INSTALL_PATH may be supplied explicitly or inherited from a Developer Command Prompt.
   IF NOT DEFINED VS_INSTALL_PATH IF DEFINED VSINSTALLDIR SET "VS_INSTALL_PATH=%VSINSTALLDIR%"

   SET "REQUESTED_VS_MAJOR="
   SET "REQUESTED_VS_UPPER="
   SET "REQUESTED_VS_YEAR="
   IF /I "%GENERATOR_NAME%"=="Visual Studio 18 2026" (
      SET "REQUESTED_VS_MAJOR=18"
      SET "REQUESTED_VS_UPPER=19"
      SET "REQUESTED_VS_YEAR=2026"
   )
   IF /I "%GENERATOR_NAME%"=="Visual Studio 17 2022" (
      SET "REQUESTED_VS_MAJOR=17"
      SET "REQUESTED_VS_UPPER=18"
      SET "REQUESTED_VS_YEAR=2022"
   )
   IF /I "%GENERATOR_NAME%"=="Visual Studio 16 2019" (
      SET "REQUESTED_VS_MAJOR=16"
      SET "REQUESTED_VS_UPPER=17"
      SET "REQUESTED_VS_YEAR=2019"
   )
   IF /I "%GENERATOR_NAME%"=="Visual Studio 15 2017" (
      SET "REQUESTED_VS_MAJOR=15"
      SET "REQUESTED_VS_UPPER=16"
      SET "REQUESTED_VS_YEAR=2017"
   )

   IF DEFINED VS_INSTALL_PATH (
      EXIT /B 0
   )

   CALL :FIND_VSWHERE
   IF ERRORLEVEL 1 (
      ECHO Error: vswhere.exe was not found and no Visual Studio environment is active.
      ECHO Install Visual Studio 2017 or later with the Desktop development with C++ workload.
      EXIT /B 1
   )

   IF DEFINED REQUESTED_VS_MAJOR (
      CALL :FIND_VISUAL_STUDIO_VERSION !REQUESTED_VS_MAJOR! !REQUESTED_VS_UPPER! !REQUESTED_VS_YEAR!
   ) ELSE IF DEFINED GENERATOR_NAME (
      ECHO Error: unsupported GENERATOR_NAME "%GENERATOR_NAME%".
      ECHO Also set VS_INSTALL_PATH when using a custom Visual Studio generator.
      EXIT /B 1
   ) ELSE (
      REM Prefer VS 2026, then retain compatibility with the previous supported releases.
      CALL :FIND_VISUAL_STUDIO_VERSION 18 19 2026
      IF NOT DEFINED VS_INSTALL_PATH CALL :FIND_VISUAL_STUDIO_VERSION 17 18 2022
      IF NOT DEFINED VS_INSTALL_PATH CALL :FIND_VISUAL_STUDIO_VERSION 16 17 2019
      IF NOT DEFINED VS_INSTALL_PATH CALL :FIND_VISUAL_STUDIO_VERSION 15 16 2017
   )

   IF NOT DEFINED VS_INSTALL_PATH (
      ECHO Error: no supported Visual Studio installation was found.
      ECHO Supported releases: 2026, 2022, 2019, and 2017.
      ECHO The Desktop development with C++ workload is required.
      EXIT /B 1
   )

   EXIT /B 0

:FIND_VSWHERE
   SET "VSWHERE="
   IF EXIST "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" SET "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
   IF NOT DEFINED VSWHERE IF EXIST "%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe" SET "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
   IF NOT DEFINED VSWHERE FOR /F "delims=" %%I IN ('where vswhere.exe 2^>NUL') DO IF NOT DEFINED VSWHERE SET "VSWHERE=%%~fI"
   IF NOT DEFINED VSWHERE EXIT /B 1
   EXIT /B 0

:FIND_VISUAL_STUDIO_VERSION
   SET "FOUND_VS_PATH="
   FOR /F "usebackq delims=" %%I IN (`"!VSWHERE!" -latest -products * -prerelease -version [%~1^,%~2^) -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) DO IF NOT DEFINED FOUND_VS_PATH SET "FOUND_VS_PATH=%%I"
   IF NOT DEFINED FOUND_VS_PATH FOR /F "usebackq delims=" %%I IN (`"!VSWHERE!" -latest -products * -version [%~1^,%~2^) -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) DO IF NOT DEFINED FOUND_VS_PATH SET "FOUND_VS_PATH=%%I"
   IF NOT DEFINED FOUND_VS_PATH EXIT /B 1

   SET "VS_INSTALL_PATH=!FOUND_VS_PATH!"
   IF NOT DEFINED GENERATOR_NAME SET "GENERATOR_NAME=Visual Studio %~1 %~3"
   EXIT /B 0

:SET_GENERATOR_FROM_ACTIVE_VS
   FOR /F "tokens=1 delims=." %%V IN ("%VisualStudioVersion%") DO SET "ACTIVE_VS_MAJOR=%%V"
   IF "%ACTIVE_VS_MAJOR%"=="18" SET "GENERATOR_NAME=Visual Studio 18 2026"
   IF "%ACTIVE_VS_MAJOR%"=="17" SET "GENERATOR_NAME=Visual Studio 17 2022"
   IF "%ACTIVE_VS_MAJOR%"=="16" SET "GENERATOR_NAME=Visual Studio 16 2019"
   IF "%ACTIVE_VS_MAJOR%"=="15" SET "GENERATOR_NAME=Visual Studio 15 2017"
   EXIT /B 0

:ACTIVATE_VISUAL_STUDIO
   SET "VS_DEV_CMD=%VS_INSTALL_PATH%\Common7\Tools\VsDevCmd.bat"
   IF NOT EXIST "%VS_DEV_CMD%" (
      ECHO Error: Visual Studio environment script was not found:
      ECHO   %VS_DEV_CMD%
      EXIT /B 1
   )

   SET "VS_DEV_ARCH=x64"
   IF "%ARCH%"=="x86" SET "VS_DEV_ARCH=x86"
   SET "VS_HOST_ARCH=x86"
   IF /I "%PROCESSOR_ARCHITECTURE%"=="AMD64" SET "VS_HOST_ARCH=x64"
   IF /I "%PROCESSOR_ARCHITEW6432%"=="AMD64" SET "VS_HOST_ARCH=x64"
   IF /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" SET "VS_HOST_ARCH=arm64"
   IF /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" SET "VS_HOST_ARCH=arm64"

   SET "VSCMD_SKIP_SENDTELEMETRY=1"
   CALL "%VS_DEV_CMD%" -no_logo -arch=!VS_DEV_ARCH! -host_arch=!VS_HOST_ARCH!
   IF ERRORLEVEL 1 (
      ECHO Error: Visual Studio failed to initialize the !VS_DEV_ARCH! build environment.
      EXIT /B 1
   )

   IF NOT DEFINED GENERATOR_NAME CALL :SET_GENERATOR_FROM_ACTIVE_VS
   IF NOT DEFINED GENERATOR_NAME (
      ECHO Error: the Visual Studio version could not be mapped to a supported CMake generator.
      ECHO Set GENERATOR_NAME explicitly when using a custom Visual Studio installation.
      EXIT /B 1
   )

   where /Q cl.exe
   IF ERRORLEVEL 1 (
      ECHO Error: cl.exe is unavailable after Visual Studio environment initialization.
      ECHO Verify that the Desktop development with C++ workload is installed.
      EXIT /B 1
   )
   where /Q msbuild.exe
   IF ERRORLEVEL 1 (
      ECHO Error: msbuild.exe is unavailable after Visual Studio environment initialization.
      EXIT /B 1
   )

   ECHO Visual Studio: %GENERATOR_NAME%
   ECHO VS path: %VS_INSTALL_PATH%
   EXIT /B 0

:FIND_CMAKE
   SET "VS_CMAKE_BIN=%VS_INSTALL_PATH%\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
   where /Q cmake.exe
   IF ERRORLEVEL 1 (
      IF EXIST "!VS_CMAKE_BIN!\cmake.exe" SET "PATH=!VS_CMAKE_BIN!;!PATH!"
   )

   where /Q cmake.exe
   IF ERRORLEVEL 1 (
      ECHO Error: cmake.exe was not found in PATH or in the selected Visual Studio installation.
      ECHO Install CMake, or add its bin directory to PATH.
      EXIT /B 1
   )

   CALL :CMAKE_SUPPORTS_GENERATOR
   IF ERRORLEVEL 1 IF EXIST "!VS_CMAKE_BIN!\cmake.exe" (
      SET "PATH=!VS_CMAKE_BIN!;!PATH!"
      CALL :CMAKE_SUPPORTS_GENERATOR
   )
   IF ERRORLEVEL 1 (
      ECHO Error: the installed CMake does not provide generator "%GENERATOR_NAME%".
      IF /I "%GENERATOR_NAME%"=="Visual Studio 18 2026" ECHO Visual Studio 2026 requires CMake 4.2 or later.
      EXIT /B 1
   )

   FOR /F "tokens=3" %%V IN ('cmake --version ^| findstr /B /C:"cmake version"') DO SET "DETECTED_CMAKE_VERSION=%%V"
   ECHO CMake: !DETECTED_CMAKE_VERSION!
   EXIT /B 0

:CMAKE_SUPPORTS_GENERATOR
   cmake --help | findstr /C:"%GENERATOR_NAME%" >NUL
   EXIT /B !ERRORLEVEL!

:FIND_QT
   SET "QT_PREFIX="
   CALL :USE_QT_FROM_PATH
   IF NOT ERRORLEVEL 1 EXIT /B 0

   IF DEFINED QT_PATH CALL :SEARCH_QT_ROOT "%QT_PATH%"
   IF DEFINED QT_PREFIX EXIT /B 0
   IF DEFINED QTDIR CALL :SEARCH_QT_ROOT "%QTDIR%"
   IF DEFINED QT_PREFIX EXIT /B 0
   IF DEFINED QT_DIR CALL :SEARCH_QT_ROOT "%QT_DIR%"
   IF DEFINED QT_PREFIX EXIT /B 0
   IF EXIST "%SystemDrive%\Qt" CALL :SEARCH_QT_ROOT "%SystemDrive%\Qt"
   IF DEFINED QT_PREFIX EXIT /B 0
   IF EXIST "%USERPROFILE%\Qt" CALL :SEARCH_QT_ROOT "%USERPROFILE%\Qt"
   IF DEFINED QT_PREFIX EXIT /B 0

   ECHO Error: a compatible Qt 5 MSVC installation was not found.
   ECHO Add qmake.exe to PATH or set QT_PATH to a Qt kit, for example:
   ECHO   set QT_PATH=C:\Qt\5.15.2\msvc2019_64
   EXIT /B 1

:USE_QT_FROM_PATH
   where /Q qmake.exe
   IF ERRORLEVEL 1 EXIT /B 1
   CALL :VALIDATE_ACTIVE_QT
   EXIT /B !ERRORLEVEL!

:SEARCH_QT_ROOT
   IF NOT EXIST "%~1" EXIT /B 1

   CALL :TRY_QT_PREFIX "%~1"
   IF DEFINED QT_PREFIX EXIT /B 0

   FOR %%P IN (5.15* 5.14* 5.13* 5.12* 5.11* 5.10* 5.9* 5.8* 5.*) DO (
      FOR /F "delims=" %%V IN ('DIR /B /AD /O:-N "%~1\%%P" 2^>NUL') DO IF NOT DEFINED QT_PREFIX CALL :TRY_QT_VERSION "%~1\%%V"
   )
   IF DEFINED QT_PREFIX EXIT /B 0
   EXIT /B 1

:TRY_QT_VERSION
   CALL :TRY_QT_PREFIX "%~1"
   IF DEFINED QT_PREFIX EXIT /B 0

   IF "%ARCH%"=="x64" (
      FOR %%K IN (msvc2026_64 msvc2022_64 msvc2019_64 msvc2017_64 msvc2015_64) DO IF NOT DEFINED QT_PREFIX IF EXIST "%~1\%%K\bin\qmake.exe" CALL :TRY_QT_PREFIX "%~1\%%K"
   ) ELSE (
      FOR %%K IN (msvc2026 msvc2022 msvc2019 msvc2017 msvc2015) DO IF NOT DEFINED QT_PREFIX IF EXIST "%~1\%%K\bin\qmake.exe" CALL :TRY_QT_PREFIX "%~1\%%K"
   )
   IF DEFINED QT_PREFIX EXIT /B 0
   EXIT /B 1

:TRY_QT_PREFIX
   IF NOT EXIST "%~1\bin\qmake.exe" EXIT /B 1
   SET "PATH_BEFORE_QT=!PATH!"
   SET "PATH=%~1\bin;!PATH!"
   CALL :VALIDATE_ACTIVE_QT
   IF ERRORLEVEL 1 (
      SET "PATH=!PATH_BEFORE_QT!"
      EXIT /B 1
   )
   EXIT /B 0

:VALIDATE_ACTIVE_QT
   SET "DETECTED_QT_PREFIX="
   SET "DETECTED_QT_BIN="
   SET "DETECTED_QT_ARCHDATA="
   SET "DETECTED_QT_ARCH="
   SET "DETECTED_QT_SPEC="
   SET "DETECTED_QT_VERSION="
   FOR /F "delims=" %%Q IN ('qmake -query QT_INSTALL_PREFIX 2^>NUL') DO SET "DETECTED_QT_PREFIX=%%Q"
   FOR /F "delims=" %%Q IN ('qmake -query QT_INSTALL_BINS 2^>NUL') DO SET "DETECTED_QT_BIN=%%Q"
   FOR /F "delims=" %%Q IN ('qmake -query QT_INSTALL_ARCHDATA 2^>NUL') DO SET "DETECTED_QT_ARCHDATA=%%Q"
   FOR /F "delims=" %%Q IN ('qmake -query QMAKE_XSPEC 2^>NUL') DO SET "DETECTED_QT_SPEC=%%Q"
   FOR /F "delims=" %%Q IN ('qmake -query QT_VERSION 2^>NUL') DO SET "DETECTED_QT_VERSION=%%Q"
   IF EXIST "!DETECTED_QT_ARCHDATA!\mkspecs\qconfig.pri" FOR /F "tokens=3" %%Q IN ('findstr /B /C:"QT_ARCH =" "!DETECTED_QT_ARCHDATA!\mkspecs\qconfig.pri"') DO SET "DETECTED_QT_ARCH=%%Q"

   IF NOT "!DETECTED_QT_VERSION:~0,2!"=="5." EXIT /B 1
   ECHO !DETECTED_QT_SPEC! | findstr /I /C:"msvc" >NUL
   IF ERRORLEVEL 1 EXIT /B 1
   IF NOT DEFINED DETECTED_QT_PREFIX EXIT /B 1
   IF NOT DEFINED DETECTED_QT_ARCH EXIT /B 1
   IF "%ARCH%"=="x64" IF /I NOT "!DETECTED_QT_ARCH!"=="x86_64" IF /I NOT "!DETECTED_QT_ARCH!"=="amd64" EXIT /B 1
   IF "%ARCH%"=="x86" IF /I "!DETECTED_QT_ARCH!"=="x86_64" EXIT /B 1
   IF "%ARCH%"=="x86" IF /I "!DETECTED_QT_ARCH!"=="amd64" EXIT /B 1

   SET "QT_PREFIX=!DETECTED_QT_PREFIX!"
   SET "PATH=!DETECTED_QT_BIN!;!PATH!"
   SET "CMAKE_PREFIX_PATH=!QT_PREFIX!;!CMAKE_PREFIX_PATH!"
   SET "QT_PLUGIN_PATH=!QT_PREFIX!\plugins"
   SET "QML2_IMPORT_PATH=!QT_PREFIX!\qml"
   ECHO Qt: !DETECTED_QT_VERSION! ^(!DETECTED_QT_SPEC!, !DETECTED_QT_ARCH!^)
   ECHO Qt path: !QT_PREFIX!
   EXIT /B 0

:BUILD
   CALL :SETUP_BUILD_ENVIRONMENT
   IF ERRORLEVEL 1 GOTO :FAIL
   echo Generator is: %GENERATOR_NAME%
   echo Platform is: %PLATFORM_NAME%
   SET "BUILD_FOLDER=%BUILD_FOLDER%_%ARCH%"
   echo Build folder is: %BUILD_FOLDER%
   IF NOT "%BUILD_WIN_PORTABLE%"=="ON" (
      SET "INSTALL_FOLDER=%INSTALL_FOLDER%_%ARCH%"
   )
   echo Install folder is: %INSTALL_FOLDER%
   if not exist "%BUILD_FOLDER%\" mkdir "%BUILD_FOLDER%"
   if not exist "%INSTALL_FOLDER%\" mkdir "%INSTALL_FOLDER%"

IF NOT "%MSCORE_STABLE_BUILD%" == "" (
    IF NOT "%CRASH_LOG_SERVER_URL%" == "" (
        IF "%BUILD_FOR_WINSTORE%" == "OFF" (
            SET CRASH_REPORT_URL_OPT=-DCRASH_REPORT_URL=%CRASH_LOG_SERVER_URL% -DBUILD_CRASH_REPORTER=ON
        )
    )

    IF NOT "%TELEMETRY_TRACK_ID%" == "" (
        SET TELEMETRY_TRACK_ID_OPT=-DTELEMETRY_TRACK_ID=%TELEMETRY_TRACK_ID%
    )
)

IF "%MUSESCORE_BUILD_CONFIG%" == "" (
    SET MUSESCORE_BUILD_CONFIG="dev"
)

SET "INSTALL_FOLDER=%INSTALL_FOLDER:\=/%"
REM -DCMAKE_BUILD_NUMBER=%BUILD_NUMBER% -DCMAKE_BUILD_AUTOUPDATE=%BUILD_AUTOUPDATE% %CRASH_REPORT_URL_OPT% are used for CI only
   cd "%BUILD_FOLDER%"
   IF EXIST "CMakeCache.txt" (
      echo Using existing CMake configuration to save time.
      echo To force reconfiguration, delete CMakeCache.txt or run "msvc_build.bat clean".
      echo You only need to do this if you want to use different build options to before.
      REM Note: If a CMakeLists.txt file was edited then the build system will detect it
      REM and run CMake again automatically with the same options as before.
   ) ELSE (
      echo Building CMake configuration...
      cmake -G "%GENERATOR_NAME%" -A "%PLATFORM_NAME%" -DCMAKE_INSTALL_PREFIX=../%INSTALL_FOLDER% -DCMAKE_BUILD_TYPE=%CONFIGURATION_STR% -DMUSESCORE_BUILD_CONFIG=%MUSESCORE_BUILD_CONFIG% -DMUSESCORE_REVISION=%MUSESCORE_REVISION% -DBUILD_FOR_WINSTORE=%BUILD_FOR_WINSTORE% -DBUILD_64=%BUILD_64% -DCMAKE_BUILD_NUMBER=%BUILD_NUMBER% -DBUILD_AUTOUPDATE=%BUILD_AUTOUPDATE% %CRASH_REPORT_URL_OPT% %TELEMETRY_TRACK_ID_OPT% %WIN_PORTABLE_OPT% ..
      IF !ERRORLEVEL! NEQ 0 (
         set OLD_ERRORLEVEL=!ERRORLEVEL!
         del /f "CMakeCache.txt"
         exit /b !OLD_ERRORLEVEL!
      )
   )
   echo Building MuseScore...
   cmake --build . --config %CONFIGURATION_STR% --target mscore
   EXIT /B !ERRORLEVEL!

:INSTALL
   CALL :SETUP_BUILD_ENVIRONMENT
   IF ERRORLEVEL 1 GOTO :FAIL
   cd "%BUILD_FOLDER%"
   echo Installing MuseScore files...
   cmake --build . --config %CONFIGURATION_STR% --target install
   EXIT /B !ERRORLEVEL!

:FAIL
exit /b 1

:END
exit /b !ERRORLEVEL!
