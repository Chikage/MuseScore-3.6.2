[CmdletBinding()]
param(
    [ValidateSet("Debug", "RelWithDebInfo", "Release")]
    [string]$Configuration = "Release",

    [string]$QtRoot = $env:QT_ROOT_DIR,
    [string]$BuildDir,
    [string]$InstallDir,
    [string]$Generator = "Visual Studio 17 2022",
    [string]$XenTunerSourceDir = $env:MUSESCORE_XEN_TUNER_SOURCE_DIR,
    [string]$OpenSslRoot = $env:OPENSSL_ROOT_DIR,

    [switch]$Clean,
    [switch]$SkipInstall,
    [switch]$SkipDeploy,
    [switch]$SkipVerify,
    [switch]$SkipSmoke,
    [switch]$NoWebEngine,

    [string[]]$CMakeArgument = @()
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
if ($env:OS -eq "Windows_NT" -and -not [Environment]::Is64BitProcess) {
    throw "The Windows Qt 6 x64 build must run from a 64-bit PowerShell process."
}

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$ConfigurationLower = $Configuration.ToLowerInvariant()

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }
    return [IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][object[]]$Arguments
    )

    Write-Host "> $Command $($Arguments -join ' ')"
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command"
    }
}

function Find-QMake {
    param([string]$RequestedQtRoot)

    $Candidates = @()
    if ($RequestedQtRoot) {
        $ResolvedQtRoot = Resolve-RepositoryPath -Path $RequestedQtRoot -BasePath $SourceRoot
        $Candidates += (Join-Path $ResolvedQtRoot "bin\qmake6.exe")
        $Candidates += (Join-Path $ResolvedQtRoot "bin\qmake.exe")
    }

    foreach ($Name in @("qmake6.exe", "qmake.exe", "qmake6", "qmake")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) {
            $Candidates += $Command.Source
        }
    }

    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
            continue
        }
        $Version = (& $Candidate -query QT_VERSION).Trim()
        if ($LASTEXITCODE -eq 0 -and $Version -match '^6\.') {
            return [IO.Path]::GetFullPath($Candidate)
        }
    }

    throw "Qt 6 qmake was not found. Set QT_ROOT_DIR or pass -QtRoot to a 64-bit Qt 6 installation."
}

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $Reader = New-Object IO.BinaryReader($Stream)
        if ($Reader.ReadUInt16() -ne 0x5A4D) {
            throw "Not a PE file: $Path"
        }
        $Stream.Position = 0x3C
        $PeOffset = $Reader.ReadInt32()
        if ($PeOffset -lt 0 -or $PeOffset -gt ($Stream.Length - 6)) {
            throw "Invalid PE header offset: $Path"
        }
        $Stream.Position = $PeOffset
        if ($Reader.ReadUInt32() -ne 0x00004550) {
            throw "Invalid PE signature: $Path"
        }
        return $Reader.ReadUInt16()
    }
    finally {
        $Stream.Dispose()
    }
}

if (-not $BuildDir) {
    $BuildDir = "build.windows-qt6-x64-$ConfigurationLower"
}
if (-not $InstallDir) {
    $InstallDir = "build.artifacts/windows/qt6/x64/$ConfigurationLower"
}

$BuildDir = Resolve-RepositoryPath -Path $BuildDir -BasePath $SourceRoot
$InstallDir = Resolve-RepositoryPath -Path $InstallDir -BasePath $SourceRoot

if ($SkipInstall) {
    $SkipDeploy = $true
    $SkipVerify = $true
    $SkipSmoke = $true
}
elseif ($SkipDeploy) {
    $SkipVerify = $true
    $SkipSmoke = $true
}
elseif ($SkipVerify) {
    $SkipSmoke = $true
}

$QMake = Find-QMake -RequestedQtRoot $QtRoot
$QtVersion = (& $QMake -query QT_VERSION).Trim()
if ($LASTEXITCODE -ne 0 -or $QtVersion -notmatch '^6\.') {
    throw "$QMake does not belong to Qt 6 (reported '$QtVersion')"
}
$QtRoot = (& $QMake -query QT_INSTALL_PREFIX).Trim()
if ($LASTEXITCODE -ne 0 -or -not $QtRoot) {
    throw "$QMake did not report QT_INSTALL_PREFIX"
}
$QtRoot = [IO.Path]::GetFullPath($QtRoot)

$QtCoreDll = Join-Path $QtRoot "bin\Qt6Core.dll"
if (-not (Test-Path -LiteralPath $QtCoreDll -PathType Leaf)) {
    throw "The selected Qt installation does not contain $QtCoreDll"
}
if ((Get-PeMachine -Path $QtCoreDll) -ne 0x8664) {
    throw "Qt 6 x86 is not supported by this migration target. Select a Qt 6 x64 installation."
}

$DependenciesRoot = Join-Path $SourceRoot "dependencies"
foreach ($RequiredDependencyPath in @("include", "libx64")) {
    $Candidate = Join-Path $DependenciesRoot $RequiredDependencyPath
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
        throw "Missing Windows dependency staging directory: $Candidate"
    }
}

if ($XenTunerSourceDir) {
    $XenTunerSourceDir = Resolve-RepositoryPath -Path $XenTunerSourceDir -BasePath $SourceRoot
    if (-not (Test-Path -LiteralPath $XenTunerSourceDir -PathType Container)) {
        throw "Xen Tuner staging directory does not exist: $XenTunerSourceDir"
    }
}

if ($OpenSslRoot) {
    $OpenSslRoot = Resolve-RepositoryPath -Path $OpenSslRoot -BasePath $SourceRoot
    if (-not (Test-Path -LiteralPath $OpenSslRoot -PathType Container)) {
        throw "OpenSSL runtime directory does not exist: $OpenSslRoot"
    }
}

if ($Clean) {
    foreach ($Directory in @($BuildDir, $InstallDir)) {
        if (Test-Path -LiteralPath $Directory) {
            Write-Host "Removing $Directory"
            Remove-Item -LiteralPath $Directory -Recurse -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
if (-not $SkipInstall) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

$UseWebEngine = if ($NoWebEngine) { "OFF" } else { "ON" }
$ConfigureArguments = @(
    "-S", $SourceRoot,
    "-B", $BuildDir,
    "-G", $Generator,
    "-A", "x64",
    "-DMSCORE_QT_MAJOR_VERSION=6",
    "-DQT_QMAKE_EXECUTABLE=$QMake",
    "-DCMAKE_PREFIX_PATH=$QtRoot",
    "-DCMAKE_INSTALL_PREFIX=$InstallDir",
    "-DCMAKE_BUILD_TYPE=$Configuration",
    "-DCMAKE_LIBRARY_PATH=$(Join-Path $DependenciesRoot 'libx64')",
    "-DBUILD_64=ON",
    "-DBUILD_FOR_WINSTORE=OFF",
    "-DBUILD_AUTOUPDATE=OFF",
    "-DBUILD_CRASH_REPORTER=OFF",
    "-DBUILD_TELEMETRY_MODULE=OFF",
    "-DBUILD_JACK=OFF",
    "-DMUSESCORE_BUNDLE_XEN_TUNER=ON",
    "-DDOWNLOAD_SOUNDFONT=OFF",
    "-DBUILD_WEBENGINE=$UseWebEngine"
)

if ($XenTunerSourceDir) {
    # The top-level/plugin staging implementation owns how this directory is
    # consumed. This Windows entry point only forwards an already available
    # source tree and deliberately performs no network/plugin acquisition.
    $ConfigureArguments += "-DMUSESCORE_XEN_TUNER_SOURCE_DIR=$XenTunerSourceDir"
}
$ConfigureArguments += $CMakeArgument

Write-Host "Configuring MuseScore with Qt $QtVersion ($QtRoot)"
Invoke-Checked -Command "cmake" -Arguments $ConfigureArguments
Invoke-Checked -Command "cmake" -Arguments @(
    "--build", $BuildDir,
    "--config", $Configuration,
    "--target", "mscore",
    "--parallel"
)

if (-not $SkipInstall) {
    Invoke-Checked -Command "cmake" -Arguments @(
        "--install", $BuildDir,
        "--config", $Configuration,
        "--prefix", $InstallDir
    )
}

if (-not $SkipDeploy) {
    $DeployParameters = @{
        InstallRoot = $InstallDir
        QtRoot = $QtRoot
        SourceRoot = $SourceRoot
        Configuration = $Configuration
    }
    if ($XenTunerSourceDir) {
        $DeployParameters["XenTunerSourceDir"] = $XenTunerSourceDir
    }
    if ($OpenSslRoot) {
        $DeployParameters["OpenSslRoot"] = $OpenSslRoot
    }
    if ($NoWebEngine) {
        $DeployParameters["NoWebEngine"] = $true
    }
    & (Join-Path $PSScriptRoot "deploy_windows_qt6.ps1") @DeployParameters
    if ($LASTEXITCODE -ne 0) {
        throw "Windows Qt 6 deployment failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipVerify) {
    $VerifyParameters = @{
        InstallRoot = $InstallDir
        Configuration = $Configuration
        ExpectedXenTunerRoot = (Join-Path $BuildDir "share\xen-tuner-runtime")
    }
    if ($OpenSslRoot) {
        $VerifyParameters["RequireOpenSsl"] = $true
    }
    if ($NoWebEngine) {
        $VerifyParameters["NoWebEngine"] = $true
    }
    if (-not $SkipSmoke) {
        $VerifyParameters["RunSmokeTests"] = $true
    }
    & (Join-Path $PSScriptRoot "verify_windows_qt6.ps1") @VerifyParameters
    if ($LASTEXITCODE -ne 0) {
        throw "Windows Qt 6 deployment verification failed with exit code $LASTEXITCODE"
    }
}

Write-Host "Windows Qt 6 x64 build completed."
Write-Host "Build directory: $BuildDir"
if (-not $SkipInstall) {
    Write-Host "Install directory: $InstallDir"
}
