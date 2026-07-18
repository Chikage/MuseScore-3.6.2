[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [string]$QtRoot = $env:QT_ROOT_DIR,
    [string]$SourceRoot,

    [ValidateSet("Debug", "RelWithDebInfo", "Release")]
    [string]$Configuration = "Release",

    [string]$XenTunerSourceDir = $env:MUSESCORE_XEN_TUNER_SOURCE_DIR,
    [string]$OpenSslRoot = $env:OPENSSL_ROOT_DIR,
    [switch]$NoWebEngine,
    [switch]$NoCompilerRuntime
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
if ($env:OS -eq "Windows_NT" -and -not [Environment]::Is64BitProcess) {
    throw "The Windows Qt 6 x64 deployment must run from a 64-bit PowerShell process."
}

if (-not $SourceRoot) {
    $SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
else {
    $SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)

function Find-QtTool {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [string]$RequestedQtRoot
    )

    $Candidates = @()
    if ($RequestedQtRoot) {
        $ResolvedQtRoot = [IO.Path]::GetFullPath($RequestedQtRoot)
        foreach ($Name in $Names) {
            $Candidates += (Join-Path $ResolvedQtRoot "bin\$Name")
        }
    }
    foreach ($Name in $Names) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($Command) {
            $Candidates += $Command.Source
        }
    }
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($Candidate)
        }
    }
    return $null
}

function Copy-QmlSources {
    param(
        [Parameter(Mandatory = $true)][string]$InputDirectory,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) {
        return
    }

    $InputDirectory = [IO.Path]::GetFullPath($InputDirectory).TrimEnd('\', '/')
    $PrefixLength = $InputDirectory.Length + 1
    Get-ChildItem -LiteralPath $InputDirectory -Recurse -File | Where-Object {
        $_.Extension -in @(".qml", ".js") -or $_.Name -eq "qmldir"
    } | ForEach-Object {
        $RelativePath = $_.FullName.Substring($PrefixLength)
        $Target = Join-Path $OutputDirectory $RelativePath
        $TargetParent = Split-Path -Parent $Target
        New-Item -ItemType Directory -Force -Path $TargetParent | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $Target -Force
    }
}

function Copy-OpenSslRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
        throw "OpenSSL runtime directory does not exist: $RuntimeRoot"
    }

    $RuntimeNames = @(
        @("libcrypto-3-x64.dll", "libcrypto-3.dll"),
        @("libssl-3-x64.dll", "libssl-3.dll")
    )
    foreach ($Alternatives in $RuntimeNames) {
        $Match = $null
        foreach ($Name in $Alternatives) {
            $Match = Get-ChildItem -LiteralPath $RuntimeRoot -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($Match) {
                break
            }
        }
        if (-not $Match) {
            throw "Could not find any of '$($Alternatives -join ', ')' below $RuntimeRoot"
        }
        Copy-Item -LiteralPath $Match.FullName -Destination (Join-Path $Destination $Match.Name) -Force
    }
}

if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
    throw "Install root does not exist: $InstallRoot"
}

$BinDirectory = Join-Path $InstallRoot "bin"
if (-not (Test-Path -LiteralPath $BinDirectory -PathType Container)) {
    throw "Installed bin directory does not exist: $BinDirectory"
}

$MuseScoreExecutable = Get-ChildItem -LiteralPath $BinDirectory -File -Filter "*.exe" |
    Where-Object { $_.Name -ne "QtWebEngineProcess.exe" -and $_.Name -notmatch 'crash-reporter' } |
    Sort-Object @{ Expression = { if ($_.Name -match '^(MuseScore|mscore)') { 0 } else { 1 } } }, Name |
    Select-Object -First 1
if (-not $MuseScoreExecutable) {
    throw "MuseScore executable was not found in $BinDirectory"
}

$QMake = Find-QtTool -Names @("qmake6.exe", "qmake.exe") -RequestedQtRoot $QtRoot
if (-not $QMake) {
    throw "Qt 6 qmake was not found. Set QT_ROOT_DIR or pass -QtRoot."
}
$QtVersion = (& $QMake -query QT_VERSION).Trim()
if ($LASTEXITCODE -ne 0 -or $QtVersion -notmatch '^6\.') {
    throw "$QMake does not belong to Qt 6 (reported '$QtVersion')"
}
$QtRoot = (& $QMake -query QT_INSTALL_PREFIX).Trim()
if ($LASTEXITCODE -ne 0 -or -not $QtRoot) {
    throw "$QMake did not report a valid QT_INSTALL_PREFIX"
}
$QtRoot = [IO.Path]::GetFullPath($QtRoot)
$WinDeployQt = Find-QtTool -Names @("windeployqt6.exe", "windeployqt.exe") -RequestedQtRoot $QtRoot
if (-not $WinDeployQt) {
    throw "windeployqt was not found below $QtRoot"
}

$QmlDeployDirectory = Join-Path $InstallRoot "qml"
$TemporaryQmlRoot = Join-Path ([IO.Path]::GetTempPath()) ("musescore-qml-scan-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $TemporaryQmlRoot | Out-Null

try {
    $QmlGroups = @(
        (Join-Path $SourceRoot "mscore"),
        (Join-Path $SourceRoot "telemetry"),
        (Join-Path $SourceRoot "share\plugins"),
        (Join-Path $InstallRoot "plugins\musescore-xen-tuner")
    )
    # Prefer the installed, allowlisted runtime produced by the shared staging
    # layer. Fall back to an explicitly supplied or vendored ordinary source
    # tree only when deployment is run independently against an older install.
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot "plugins\musescore-xen-tuner") -PathType Container)) {
        if ($XenTunerSourceDir) {
            $QmlGroups += [IO.Path]::GetFullPath($XenTunerSourceDir)
        }
        else {
            $QmlGroups += (Join-Path $SourceRoot "plugins\musescore-xen-tuner")
        }
    }

    $GroupIndex = 0
    foreach ($QmlGroup in $QmlGroups) {
        if (-not (Test-Path -LiteralPath $QmlGroup -PathType Container)) {
            continue
        }
        $GroupIndex++
        Copy-QmlSources -InputDirectory $QmlGroup -OutputDirectory (Join-Path $TemporaryQmlRoot "group-$GroupIndex")
    }

    # The Qt Quick Controls style is selected from C++, so qmlimportscanner
    # cannot infer it from the application's QML files alone.
    @(
        "import QtQuick",
        "import QtQuick.Controls",
        "import QtQuick.Controls.Fusion",
        "Item {}"
    ) | Set-Content -LiteralPath (Join-Path $TemporaryQmlRoot "musescore-deploy-imports.qml") -Encoding ASCII

    # CMake's legacy Windows install rule copies the complete Qt QML tree.
    # Replace it with the exact imports selected by windeployqt.
    if (Test-Path -LiteralPath $QmlDeployDirectory) {
        Remove-Item -LiteralPath $QmlDeployDirectory -Recurse -Force
    }
    $LegacyWebEngineResources = Join-Path $BinDirectory "webengineresources"
    if (Test-Path -LiteralPath $LegacyWebEngineResources) {
        Remove-Item -LiteralPath $LegacyWebEngineResources -Recurse -Force
    }
    if ($NoWebEngine) {
        Get-ChildItem -LiteralPath $BinDirectory -File -Filter "Qt6WebEngine*.dll" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Get-ChildItem -LiteralPath $BinDirectory -File -Filter "QtWebEngineProcess*.exe" -ErrorAction SilentlyContinue |
            Remove-Item -Force
        $WebEngineResources = Join-Path $BinDirectory "resources"
        if (Test-Path -LiteralPath $WebEngineResources -PathType Container) {
            Remove-Item -LiteralPath $WebEngineResources -Recurse -Force
        }
        $WebEngineLocales = Join-Path $BinDirectory "translations\qtwebengine_locales"
        if (Test-Path -LiteralPath $WebEngineLocales -PathType Container) {
            Remove-Item -LiteralPath $WebEngineLocales -Recurse -Force
        }
    }
    $QtConfPath = Join-Path $BinDirectory "qt.conf"
    if (Test-Path -LiteralPath $QtConfPath -PathType Leaf) {
        # CMake's legacy Windows rule installs build/qt.conf, which contains
        # two conflicting Prefix entries. Do not let windeployqt consume it.
        Remove-Item -LiteralPath $QtConfPath -Force
    }

    $DeployMode = if ($Configuration -eq "Debug") { "--debug" } else { "--release" }
    $Arguments = @(
        $DeployMode,
        "--force",
        "--verbose", "1",
        "--dir", $BinDirectory,
        "--libdir", $BinDirectory,
        "--plugindir", $BinDirectory,
        "--qml-deploy-dir", $QmlDeployDirectory,
        "--qmldir", $TemporaryQmlRoot,
        # The CI/runtime smoke test uses the offscreen QPA backend. It is not a
        # hard dependency of the GUI executable, so windeployqt will otherwise
        # omit it on some Qt SDK revisions.
        "--include-plugins", "qoffscreen"
    )
    if (-not $NoCompilerRuntime) {
        $Arguments += "--compiler-runtime"
    }
    $Arguments += $MuseScoreExecutable.FullName

    Write-Host "> $WinDeployQt $($Arguments -join ' ')"
    & $WinDeployQt @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "windeployqt failed with exit code $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $TemporaryQmlRoot) {
        Remove-Item -LiteralPath $TemporaryQmlRoot -Recurse -Force
    }
}

if ($OpenSslRoot) {
    Copy-OpenSslRuntime -RuntimeRoot $OpenSslRoot -Destination $BinDirectory
}

# MuseScore loads application data and QML from the install root (the parent of
# bin), while Qt plugins, helper executables and WebEngine resources live next
# to the executable. Keep those paths explicit and relative for portability.
$QtConf = @(
    "[Paths]",
    "Prefix=.",
    "Libraries=.",
    "LibraryExecutables=.",
    "Plugins=.",
    # Qt 6 reads this QLibraryInfo path from the QmlImports key. The old
    # Qml2Imports spelling is a Qt 5 compatibility name and can leave the
    # packaged Xen Tuner/side-panel modules undiscoverable.
    "QmlImports=../qml",
    # Qt's own and Qt WebEngine translations are deployed below bin by
    # windeployqt. MuseScore loads its application translations explicitly
    # from the install-root locale directory.
    "Translations=translations",
    "Data=."
)
$QtConf | Set-Content -LiteralPath (Join-Path $BinDirectory "qt.conf") -Encoding ASCII

Write-Host "Deployed Qt $QtVersion runtime to $InstallRoot"
Write-Host "Executable: $($MuseScoreExecutable.FullName)"
