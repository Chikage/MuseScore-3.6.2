[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [ValidateSet("Debug", "RelWithDebInfo", "Release")]
    [string]$Configuration = "Release",

    [string]$ExpectedXenTunerRoot,
    [switch]$NoWebEngine,
    [bool]$RequireXenTuner = $true,
    [switch]$RequireOpenSsl,
    [switch]$SkipDependencyScan,
    [switch]$RunSmokeTests,
    [string]$SmokeScore,

    [ValidateRange(1, 600)]
    [int]$SmokeTimeoutSeconds = 90
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
if ($env:OS -eq "Windows_NT" -and -not [Environment]::Is64BitProcess) {
    throw "The Windows Qt 6 x64 verifier must run from a 64-bit PowerShell process."
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if ($ExpectedXenTunerRoot) {
    $ExpectedXenTunerRoot = [IO.Path]::GetFullPath($ExpectedXenTunerRoot)
}
$Failures = New-Object 'System.Collections.Generic.List[string]'
$ValidatedXenTunerRuntimeFileCount = 0

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    [void]$script:Failures.Add($Message)
}

function Assert-PathExists {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $Path = Join-Path $InstallRoot $RelativePath
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-Failure "Missing required path: $RelativePath"
    }
}

function Get-FileHashMap {
    param([Parameter(Mandatory = $true)][string]$Root)

    $NormalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $PrefixLength = $NormalizedRoot.Length + 1
    $Hashes = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($File in (Get-ChildItem -LiteralPath $NormalizedRoot -Recurse -File -Force)) {
        $RelativePath = $File.FullName.Substring($PrefixLength).Replace('\', '/')
        $Hashes.Add($RelativePath, (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash)
    }
    return ,$Hashes
}

function Assert-FileHashMapUnchanged {
    param(
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string,string]]$Before,
        [Parameter(Mandatory = $true)][Collections.Generic.Dictionary[string,string]]$After,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($Before.Count -ne $After.Count) {
        Add-Failure "$Description file count changed from $($Before.Count) to $($After.Count)"
    }
    foreach ($RelativePath in $Before.Keys) {
        if (-not $After.ContainsKey($RelativePath)) {
            Add-Failure "$Description removed a file: $RelativePath"
        }
        elseif ($After[$RelativePath] -ine $Before[$RelativePath]) {
            Add-Failure "$Description modified a file: $RelativePath"
        }
    }
    foreach ($RelativePath in $After.Keys) {
        if (-not $Before.ContainsKey($RelativePath)) {
            Add-Failure "$Description added a file: $RelativePath"
        }
    }
}

function Get-XenTunerManifestHashMap {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Utf8 = New-Object Text.UTF8Encoding($false, $true)
    $Hashes = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $LineNumber = 0
    foreach ($Line in [IO.File]::ReadAllLines($Path, $Utf8)) {
        $LineNumber++
        if ($Line -notmatch '^([0-9A-Fa-f]{64})  (.+)$') {
            throw "Invalid Xen Tuner manifest entry at line ${LineNumber}: $Line"
        }

        $Hash = $Matches[1].ToUpperInvariant()
        $RelativePath = $Matches[2]
        $Segments = @($RelativePath -split '/')
        if ($RelativePath.StartsWith('/') -or
            $RelativePath.Contains('\') -or
            [IO.Path]::IsPathRooted($RelativePath) -or
            $Segments -contains '' -or
            $Segments -contains '.' -or
            $Segments -contains '..') {
            throw "Unsafe Xen Tuner manifest path at line ${LineNumber}: $RelativePath"
        }
        if ($Hashes.ContainsKey($RelativePath)) {
            throw "Duplicate Xen Tuner manifest path at line ${LineNumber}: $RelativePath"
        }
        $Hashes.Add($RelativePath, $Hash)
    }
    return ,$Hashes
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$Argument)

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $Builder = New-Object Text.StringBuilder
    [void]$Builder.Append('"')
    $BackslashCount = 0
    foreach ($Character in $Argument.ToCharArray()) {
        if ($Character -eq [char]92) {
            $BackslashCount++
            continue
        }
        if ($Character -eq [char]34) {
            if ($BackslashCount -gt 0) {
                [void]$Builder.Append((('\' * ($BackslashCount * 2)) -join ''))
            }
            [void]$Builder.Append('\"')
            $BackslashCount = 0
            continue
        }
        if ($BackslashCount -gt 0) {
            [void]$Builder.Append((('\' * $BackslashCount) -join ''))
            $BackslashCount = 0
        }
        [void]$Builder.Append($Character)
    }
    if ($BackslashCount -gt 0) {
        [void]$Builder.Append((('\' * ($BackslashCount * 2)) -join ''))
    }
    [void]$Builder.Append('"')
    return $Builder.ToString()
}

function Invoke-ProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [string]$WorkingDirectory,
        [hashtable]$Environment = @{}
    )

    $StartInfo = New-Object Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $Executable
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    if ($WorkingDirectory) {
        $StartInfo.WorkingDirectory = $WorkingDirectory
    }
    foreach ($Name in $Environment.Keys) {
        $StartInfo.EnvironmentVariables[[string]$Name] = [string]$Environment[$Name]
    }

    $ArgumentListProperty = $StartInfo.GetType().GetProperty("ArgumentList")
    if ($ArgumentListProperty) {
        $NativeArgumentList = $ArgumentListProperty.GetValue($StartInfo, $null)
        foreach ($Argument in $Arguments) {
            $NativeArgumentList.Add([string]$Argument)
        }
    }
    else {
        $StartInfo.Arguments = (($Arguments | ForEach-Object {
            ConvertTo-WindowsCommandLineArgument -Argument ([string]$_)
        }) -join ' ')
    }

    $Process = New-Object Diagnostics.Process
    $Process.StartInfo = $StartInfo
    try {
        if (-not $Process.Start()) {
            throw "Unable to start process: $Executable"
        }
        $StandardOutputTask = $Process.StandardOutput.ReadToEndAsync()
        $StandardErrorTask = $Process.StandardError.ReadToEndAsync()
        $TimedOut = -not $Process.WaitForExit($TimeoutSeconds * 1000)
        if ($TimedOut) {
            try {
                $Process.Kill()
            }
            catch {
                if (-not $Process.HasExited) {
                    throw
                }
            }
        }
        $Process.WaitForExit()
        $StandardOutput = $StandardOutputTask.GetAwaiter().GetResult()
        $StandardError = $StandardErrorTask.GetAwaiter().GetResult()
        return [PSCustomObject]@{
            ExitCode = $Process.ExitCode
            TimedOut = $TimedOut
            StandardOutput = $StandardOutput
            StandardError = $StandardError
        }
    }
    finally {
        $Process.Dispose()
    }
}

function Get-PeMachine {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $Reader = New-Object IO.BinaryReader($Stream)
        if ($Reader.ReadUInt16() -ne 0x5A4D) {
            return $null
        }
        $Stream.Position = 0x3C
        $PeOffset = $Reader.ReadInt32()
        if ($PeOffset -lt 0 -or $PeOffset -gt ($Stream.Length - 6)) {
            return $null
        }
        $Stream.Position = $PeOffset
        if ($Reader.ReadUInt32() -ne 0x00004550) {
            return $null
        }
        return $Reader.ReadUInt16()
    }
    finally {
        $Stream.Dispose()
    }
}

function Find-DumpBin {
    $Command = Get-Command "dumpbin.exe" -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    $VsWhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $VsWhere -PathType Leaf)) {
        return $null
    }
    $VisualStudioRoot = (& $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if (-not $VisualStudioRoot) {
        return $null
    }

    $MsvcToolsRoot = Join-Path $VisualStudioRoot "VC\Tools\MSVC"
    if (-not (Test-Path -LiteralPath $MsvcToolsRoot -PathType Container)) {
        return $null
    }
    foreach ($VersionDirectory in (Get-ChildItem -LiteralPath $MsvcToolsRoot -Directory | Sort-Object Name -Descending)) {
        $Candidate = Join-Path $VersionDirectory.FullName "bin\Hostx64\x64\dumpbin.exe"
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            return $Candidate
        }
    }
    return $null
}

function Test-IsSystemDependency {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -match '^(api-ms-win-|ext-ms-win-)') {
        return $true
    }
    if ($Name -ieq "ucrtbase.dll") {
        return $true
    }
    if ($env:WINDIR) {
        # Every packaged PE is required to be x64. SysWOW64 contains 32-bit
        # DLLs and must not satisfy an x64 dependency check.
        $SystemDirectory = Join-Path $env:WINDIR "System32"
        if (Test-Path -LiteralPath (Join-Path $SystemDirectory $Name) -PathType Leaf) {
            return $true
        }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $InstallRoot -PathType Container)) {
    throw "Install root does not exist: $InstallRoot"
}

$BinDirectory = Join-Path $InstallRoot "bin"
$MuseScoreExecutable = Get-ChildItem -LiteralPath $BinDirectory -File -Filter "*.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "QtWebEngineProcess.exe" -and $_.Name -notmatch 'crash-reporter' } |
    Sort-Object -Property @(@{ Expression = { if ($_.Name -match '^(MuseScore|mscore)') { 0 } else { 1 } } }, "Name") |
    Select-Object -First 1
if (-not $MuseScoreExecutable) {
    Add-Failure "MuseScore executable was not found in bin"
}

$DebugSuffix = if ($Configuration -eq "Debug") { "d" } else { "" }
foreach ($RelativePath in @(
    "bin\qt.conf",
    "bin\Qt6Core$DebugSuffix.dll",
    "bin\Qt6Core5Compat$DebugSuffix.dll",
    "bin\Qt6Gui$DebugSuffix.dll",
    "bin\Qt6Widgets$DebugSuffix.dll",
    "bin\Qt6Qml$DebugSuffix.dll",
    "bin\Qt6Quick$DebugSuffix.dll",
    "bin\Qt6QuickControls2$DebugSuffix.dll",
    "bin\platforms\qoffscreen$DebugSuffix.dll",
    "bin\platforms\qwindows$DebugSuffix.dll",
    "qml\QtQml\qmldir",
    "qml\QtQml\Models\qmldir",
    "qml\QtQuick\qmldir",
    "qml\QtQuick\Controls\qmldir",
    "qml\QtQuick\Controls\Fusion\qmldir",
    "qml\QtQuick\Dialogs\qmldir",
    "qml\QtQuick\Layouts\qmldir",
    "qml\QtQuick\Window\qmldir",
    "qml\Qt\labs\settings\qmldir",
    "locale\languages.xml",
    "styles"
)) {
    Assert-PathExists $RelativePath
}

if (-not $NoWebEngine) {
    foreach ($RelativePath in @(
        "bin\Qt6WebEngineCore$DebugSuffix.dll",
        "bin\Qt6WebEngineWidgets$DebugSuffix.dll",
        "bin\QtWebEngineProcess.exe",
        "bin\resources\icudtl.dat",
        "bin\resources\qtwebengine_resources.pak",
        "bin\resources\qtwebengine_resources_100p.pak",
        "bin\resources\qtwebengine_resources_200p.pak",
        "bin\translations\qtwebengine_locales"
    )) {
        Assert-PathExists $RelativePath
    }
}
else {
    $UnexpectedWebEnginePaths = @()
    $UnexpectedWebEnginePaths += @(Get-ChildItem -LiteralPath $BinDirectory -File -Filter "Qt6WebEngine*.dll" -ErrorAction SilentlyContinue)
    $UnexpectedWebEnginePaths += @(Get-Item -LiteralPath (Join-Path $BinDirectory "QtWebEngineProcess.exe") -ErrorAction SilentlyContinue)
    $UnexpectedWebEnginePaths += @(Get-ChildItem -LiteralPath (Join-Path $BinDirectory "resources") -File -Filter "qtwebengine*.pak" -ErrorAction SilentlyContinue)
    foreach ($UnexpectedWebEnginePath in $UnexpectedWebEnginePaths) {
        Add-Failure "WebEngine runtime is present in a -NoWebEngine package: $($UnexpectedWebEnginePath.FullName.Substring($InstallRoot.Length + 1))"
    }
}

if ($RequireXenTuner) {
    $InstalledXenTunerRoot = Join-Path $InstallRoot "plugins\musescore-xen-tuner"
    $InstalledXenTunerManifest = Join-Path $InstallRoot "plugins\musescore-xen-tuner.runtime.manifest"
    foreach ($RelativePath in @(
        "plugins\musescore-xen-tuner\LICENSE",
        "plugins\musescore-xen-tuner\Key Signature\42.json",
        "plugins\musescore-xen-tuner\tunings\default.txt",
        "plugins\musescore-xen-tuner\Xen Tuner\xen tuner.qml",
        "plugins\musescore-xen-tuner\Xen Tuner\export midx.qml",
        "plugins\musescore-xen-tuner\Xen Tuner\midx_powershell_writer.ps1",
        "plugins\musescore-xen-tuner\Xen Tuner\runtime\fns.ms.js",
        "plugins\musescore-xen-tuner\Xen Tuner\runtime\modules\00-runtime.js",
        "plugins\musescore-xen-tuner\Xen Tuner\runtime\modules\08-operations.js",
        "plugins\musescore-xen-tuner\Xen Tuner\runtime\tables\generated-tables.js",
        "plugins\musescore-xen-tuner\Xen Tuner\runtime\tables\lookup-tables.js",
        "plugins\musescore-xen-tuner\xen-tuner.config.json",
        "plugins\musescore-xen-tuner.runtime.manifest"
    )) {
        Assert-PathExists $RelativePath
    }

    $InstalledHashes = $null
    $ManifestHashes = $null
    $InstalledManifestHash = $null
    if ((Test-Path -LiteralPath $InstalledXenTunerRoot -PathType Container) -and
        (Test-Path -LiteralPath $InstalledXenTunerManifest -PathType Leaf)) {
        try {
            $InstalledManifestHash = (Get-FileHash -LiteralPath $InstalledXenTunerManifest -Algorithm SHA256).Hash
            $ManifestHashes = Get-XenTunerManifestHashMap -Path $InstalledXenTunerManifest
            $InstalledHashes = Get-FileHashMap -Root $InstalledXenTunerRoot
            $ValidatedXenTunerRuntimeFileCount = $ManifestHashes.Count
            if ($ManifestHashes.Count -eq 0) {
                Add-Failure "Packaged Xen Tuner manifest is empty"
            }
            if ($InstalledHashes.Count -ne $ManifestHashes.Count) {
                Add-Failure "Packaged Xen Tuner runtime contains $($InstalledHashes.Count) files, but its manifest lists $($ManifestHashes.Count)"
            }

            foreach ($RelativePath in $ManifestHashes.Keys) {
                if (-not $InstalledHashes.ContainsKey($RelativePath)) {
                    Add-Failure "Packaged Xen Tuner runtime is missing manifest file: $RelativePath"
                }
                elseif ($InstalledHashes[$RelativePath] -ine $ManifestHashes[$RelativePath]) {
                    Add-Failure "Packaged Xen Tuner runtime differs from its manifest: $RelativePath"
                }
            }
            foreach ($RelativePath in $InstalledHashes.Keys) {
                if (-not $ManifestHashes.ContainsKey($RelativePath)) {
                    Add-Failure "Packaged Xen Tuner runtime contains a file absent from its manifest: $RelativePath"
                }
            }
        }
        catch {
            Add-Failure "Unable to validate the packaged Xen Tuner manifest: $($_.Exception.Message)"
        }
    }

    if ($ExpectedXenTunerRoot) {
        if (-not (Test-Path -LiteralPath $ExpectedXenTunerRoot -PathType Container)) {
            Add-Failure "Expected Xen Tuner staging root does not exist: $ExpectedXenTunerRoot"
        }
        else {
            $ExpectedManifest = "$ExpectedXenTunerRoot.manifest"
            if (-not (Test-Path -LiteralPath $ExpectedManifest -PathType Leaf)) {
                Add-Failure "Expected Xen Tuner staging manifest does not exist: $ExpectedManifest"
            }
            else {
                try {
                    $ExpectedManifestHashes = Get-XenTunerManifestHashMap -Path $ExpectedManifest
                    $ExpectedHashes = Get-FileHashMap -Root $ExpectedXenTunerRoot
                    if ($ExpectedManifestHashes.Count -eq 0) {
                        Add-Failure "Expected Xen Tuner staging manifest is empty"
                    }
                    if ($ExpectedHashes.Count -ne $ExpectedManifestHashes.Count) {
                        Add-Failure "Expected Xen Tuner staging root contains $($ExpectedHashes.Count) files, but its manifest lists $($ExpectedManifestHashes.Count)"
                    }
                    foreach ($RelativePath in $ExpectedManifestHashes.Keys) {
                        if (-not $ExpectedHashes.ContainsKey($RelativePath)) {
                            Add-Failure "Expected Xen Tuner staging root is missing manifest file: $RelativePath"
                        }
                        elseif ($ExpectedHashes[$RelativePath] -ine $ExpectedManifestHashes[$RelativePath]) {
                            Add-Failure "Expected Xen Tuner staging root differs from its manifest: $RelativePath"
                        }
                    }
                    foreach ($RelativePath in $ExpectedHashes.Keys) {
                        if (-not $ExpectedManifestHashes.ContainsKey($RelativePath)) {
                            Add-Failure "Expected Xen Tuner staging root contains a file absent from its manifest: $RelativePath"
                        }
                    }

                    if (Test-Path -LiteralPath $InstalledXenTunerRoot -PathType Container) {
                        if ($null -eq $InstalledHashes) {
                            $InstalledHashes = Get-FileHashMap -Root $InstalledXenTunerRoot
                        }
                        foreach ($RelativePath in $ExpectedHashes.Keys) {
                            if (-not $InstalledHashes.ContainsKey($RelativePath)) {
                                Add-Failure "Packaged Xen Tuner runtime is missing staged file: $RelativePath"
                            }
                            elseif ($InstalledHashes[$RelativePath] -ine $ExpectedHashes[$RelativePath]) {
                                Add-Failure "Packaged Xen Tuner runtime hash mismatch: $RelativePath"
                            }
                        }
                        foreach ($RelativePath in $InstalledHashes.Keys) {
                            if (-not $ExpectedHashes.ContainsKey($RelativePath)) {
                                Add-Failure "Packaged Xen Tuner runtime contains an unstaged file: $RelativePath"
                            }
                        }
                    }

                    $ExpectedManifestHash = (Get-FileHash -LiteralPath $ExpectedManifest -Algorithm SHA256).Hash
                    if ($InstalledManifestHash -and $ExpectedManifestHash -ine $InstalledManifestHash) {
                        Add-Failure "Packaged Xen Tuner manifest differs from the CMake staging manifest"
                    }
                }
                catch {
                    Add-Failure "Unable to validate the expected Xen Tuner staging manifest: $($_.Exception.Message)"
                }
            }
        }
    }
}

if ($RequireOpenSsl) {
    $Crypto = Get-ChildItem -LiteralPath $BinDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @("libcrypto-3-x64.dll", "libcrypto-3.dll") } |
        Select-Object -First 1
    $Ssl = Get-ChildItem -LiteralPath $BinDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @("libssl-3-x64.dll", "libssl-3.dll") } |
        Select-Object -First 1
    if (-not $Crypto) {
        Add-Failure "OpenSSL 3 libcrypto runtime is missing from bin"
    }
    if (-not $Ssl) {
        Add-Failure "OpenSSL 3 libssl runtime is missing from bin"
    }
}

$QtConfPath = Join-Path $BinDirectory "qt.conf"
if (Test-Path -LiteralPath $QtConfPath -PathType Leaf) {
    $QtConfText = Get-Content -LiteralPath $QtConfPath -Raw
    if ($QtConfText -match '(?im)^\s*[^#;=]+\s*=\s*[A-Za-z]:[\\/]') {
        Add-Failure "qt.conf contains an absolute Windows path"
    }
    $ExpectedQtConfLines = @(
        "[Paths]",
        "Prefix=.",
        "Libraries=.",
        "LibraryExecutables=.",
        "Plugins=.",
        "QmlImports=../qml",
        "Translations=translations",
        "Data=."
    )
    $ActualQtConfLines = @(Get-Content -LiteralPath $QtConfPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($ActualQtConfLines.Count -ne $ExpectedQtConfLines.Count) {
        Add-Failure "qt.conf has an unexpected number of non-empty lines"
    }
    else {
        for ($Index = 0; $Index -lt $ExpectedQtConfLines.Count; $Index++) {
            if ($ActualQtConfLines[$Index] -cne $ExpectedQtConfLines[$Index]) {
                Add-Failure "qt.conf line $($Index + 1) should be '$($ExpectedQtConfLines[$Index])', got '$($ActualQtConfLines[$Index])'"
            }
        }
    }
}

$PeFiles = @(Get-ChildItem -LiteralPath $InstallRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".exe", ".dll") })
$UnexpectedQt5Files = @($PeFiles | Where-Object { $_.Name -like "Qt5*.dll" })
foreach ($UnexpectedQt5File in $UnexpectedQt5Files) {
    Add-Failure "Stale Qt 5 runtime is present in the Qt 6 package: $($UnexpectedQt5File.FullName.Substring($InstallRoot.Length + 1))"
}
foreach ($PeFile in $PeFiles) {
    $Machine = Get-PeMachine -Path $PeFile.FullName
    if ($null -eq $Machine) {
        Add-Failure "Invalid PE executable/library: $($PeFile.FullName.Substring($InstallRoot.Length + 1))"
    }
    elseif ($Machine -ne 0x8664) {
        Add-Failure ("Non-x64 PE file (machine 0x{0:X4}): {1}" -f $Machine, $PeFile.FullName.Substring($InstallRoot.Length + 1))
    }
}

if (-not $SkipDependencyScan) {
    $DumpBin = Find-DumpBin
    if (-not $DumpBin) {
        Add-Failure "dumpbin.exe was not found; install the Visual C++ x64 tools or pass -SkipDependencyScan for tree-only verification"
    }
    else {
        $CompilerRuntimePattern = '^(vcruntime|msvcp|concrt|vcomp)[0-9_]*.*\.dll$'
        foreach ($PeFile in $PeFiles) {
            $Output = & $DumpBin /nologo /dependents $PeFile.FullName 2>&1
            if ($LASTEXITCODE -ne 0) {
                Add-Failure "dumpbin failed for $($PeFile.FullName.Substring($InstallRoot.Length + 1))"
                continue
            }

            $Dependencies = $Output | ForEach-Object {
                if ($_ -match '^\s+([A-Za-z0-9_.+\-]+\.dll)\s*$') {
                    $Matches[1]
                }
            } | Sort-Object -Unique

            foreach ($Dependency in $Dependencies) {
                $BesideModule = Join-Path $PeFile.DirectoryName $Dependency
                $BesideExecutable = Join-Path $BinDirectory $Dependency
                $ResolvedLocally = ((Test-Path -LiteralPath $BesideModule -PathType Leaf) -or (Test-Path -LiteralPath $BesideExecutable -PathType Leaf))

                if ($ResolvedLocally) {
                    continue
                }
                if ($Dependency -match $CompilerRuntimePattern) {
                    Add-Failure "Compiler runtime is not bundled: $Dependency (required by $($PeFile.Name))"
                    continue
                }
                if (-not (Test-IsSystemDependency -Name $Dependency)) {
                    Add-Failure "Unresolved packaged dependency: $Dependency (required by $($PeFile.FullName.Substring($InstallRoot.Length + 1)))"
                }
            }
        }
    }
}

if ($RunSmokeTests -and $Failures.Count -eq 0) {
    $SmokeRoot = Join-Path ([IO.Path]::GetTempPath()) ("musescore-windows-smoke-" + [Guid]::NewGuid().ToString("N"))
    $SmokeFailureCountBefore = $Failures.Count
    $Utf8NoBom = New-Object Text.UTF8Encoding($false)
    $XenTunerRuntimeHashesBeforeSmoke = $null
    $XenTunerManifestHashBeforeSmoke = $null
    try {
        if (-not $MuseScoreExecutable) {
            throw "MuseScore executable is unavailable for smoke testing"
        }

        if (-not $SmokeScore) {
            $SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
            $SmokeScore = Join-Path $SourceRoot "mtest\libmscore\unrollrepeats\pickup-measure-test.mscx"
        }
        $SmokeScore = [IO.Path]::GetFullPath($SmokeScore)
        if (-not (Test-Path -LiteralPath $SmokeScore -PathType Leaf)) {
            throw "Smoke-test score does not exist: $SmokeScore"
        }

        $ConfigDirectory = Join-Path $SmokeRoot "config"
        $ProfileDirectory = Join-Path $SmokeRoot "profile"
        $LocalAppDataDirectory = Join-Path $ProfileDirectory "AppData\Local"
        $RoamingAppDataDirectory = Join-Path $ProfileDirectory "AppData\Roaming"
        $TemporaryDirectory = Join-Path $SmokeRoot "temp"
        $OutputPdf = Join-Path $SmokeRoot "export.pdf"
        $DiagnosticLog = Join-Path $SmokeRoot "musescore.log"
        foreach ($Directory in @(
            $ConfigDirectory,
            $LocalAppDataDirectory,
            $RoamingAppDataDirectory,
            $TemporaryDirectory
        )) {
            New-Item -ItemType Directory -Force -Path $Directory | Out-Null
        }

        $SmokeEnvironment = @{
            "APPDATA" = $RoamingAppDataDirectory
            "HOME" = $ProfileDirectory
            "LOCALAPPDATA" = $LocalAppDataDirectory
            "MUSESCORE_DIAGNOSTIC_LOG" = $DiagnosticLog
            "QT_QPA_PLATFORM" = "offscreen"
            "QT_QUICK_BACKEND" = "software"
            "QTWEBENGINE_DISABLE_SANDBOX" = "1"
            "TEMP" = $TemporaryDirectory
            "TMP" = $TemporaryDirectory
            "USERPROFILE" = $ProfileDirectory
        }
        $VersionEnvironment = $SmokeEnvironment.Clone()
        $VersionEnvironment["QT_QPA_PLATFORM"] = "windows"

        if ($RequireXenTuner) {
            try {
                $XenTunerRuntimeHashesBeforeSmoke = Get-FileHashMap -Root $InstalledXenTunerRoot
                $XenTunerManifestHashBeforeSmoke = (Get-FileHash -LiteralPath $InstalledXenTunerManifest -Algorithm SHA256).Hash
            }
            catch {
                Add-Failure "Unable to capture the Xen Tuner runtime baseline before smoke testing: $($_.Exception.Message)"
            }
        }

        Write-Host "Running packaged MuseScore version smoke test with the native Windows platform plugin"
        $VersionResult = Invoke-ProcessWithTimeout `
            -Executable $MuseScoreExecutable.FullName `
            -Arguments @("--version") `
            -TimeoutSeconds $SmokeTimeoutSeconds `
            -WorkingDirectory $SmokeRoot `
            -Environment $VersionEnvironment
        [IO.File]::WriteAllText((Join-Path $SmokeRoot "version.stdout.txt"), $VersionResult.StandardOutput, $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $SmokeRoot "version.stderr.txt"), $VersionResult.StandardError, $Utf8NoBom)
        if ($VersionResult.TimedOut -or $VersionResult.ExitCode -ne 0) {
            Write-Host $VersionResult.StandardOutput
            Write-Host $VersionResult.StandardError
            Add-Failure "MuseScore --version smoke test failed (exit $($VersionResult.ExitCode), timed out: $($VersionResult.TimedOut))"
        }

        Write-Host "Running packaged score export and first-start plugin discovery smoke test"
        $ExportResult = Invoke-ProcessWithTimeout `
            -Executable $MuseScoreExecutable.FullName `
            -Arguments @(
                "-F", "-s", "-m", "-w",
                "-c", $ConfigDirectory,
                "-o", $OutputPdf,
                $SmokeScore
            ) `
            -TimeoutSeconds $SmokeTimeoutSeconds `
            -WorkingDirectory $SmokeRoot `
            -Environment $SmokeEnvironment
        [IO.File]::WriteAllText((Join-Path $SmokeRoot "export.stdout.txt"), $ExportResult.StandardOutput, $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $SmokeRoot "export.stderr.txt"), $ExportResult.StandardError, $Utf8NoBom)
        if ($ExportResult.TimedOut -or $ExportResult.ExitCode -ne 0) {
            Write-Host $ExportResult.StandardOutput
            Write-Host $ExportResult.StandardError
            Add-Failure "Packaged score export smoke test failed (exit $($ExportResult.ExitCode), timed out: $($ExportResult.TimedOut))"
        }
        elseif (-not (Test-Path -LiteralPath $OutputPdf -PathType Leaf)) {
            Add-Failure "Packaged score export did not create a PDF"
        }
        else {
            $PdfBytes = [IO.File]::ReadAllBytes($OutputPdf)
            if ($PdfBytes.Length -lt 5 -or [Text.Encoding]::ASCII.GetString($PdfBytes, 0, 5) -ne "%PDF-") {
                Add-Failure "Packaged score export output is not a valid PDF"
            }
        }

        if ($RequireXenTuner) {
            # The export above uses -F and intentionally clears the isolated
            # configuration. Seed the same first-start keys that the startup
            # wizard would write, then run a short GUI process so the normal
            # PluginManager discovery path creates plugins.xml. Merely running
            # a no-GUI export cannot exercise plugin discovery.
            $SettingsDirectory = Join-Path $ConfigDirectory "MuseScore"
            $SettingsFile = Join-Path $SettingsDirectory "MuseScore3.ini"
            New-Item -ItemType Directory -Force -Path $SettingsDirectory | Out-Null
            @(
                "[application]",
                "startup\firstStart=false",
                "[ui]",
                "application\startup\showTours=false",
                "application\startup\showStartCenter=false"
            ) | Set-Content -LiteralPath $SettingsFile -Encoding ASCII

            Write-Host "Running packaged first-start Xen Tuner discovery smoke test"
            $DiscoveryResult = Invoke-ProcessWithTimeout `
                -Executable $MuseScoreExecutable.FullName `
                -Arguments @(
                    "-s", "-m", "-w",
                    "-c", $ConfigDirectory,
                    $SmokeScore
                ) `
                -TimeoutSeconds $SmokeTimeoutSeconds `
                -WorkingDirectory $SmokeRoot `
                -Environment $SmokeEnvironment
            [IO.File]::WriteAllText((Join-Path $SmokeRoot "discovery.stdout.txt"), $DiscoveryResult.StandardOutput, $Utf8NoBom)
            [IO.File]::WriteAllText((Join-Path $SmokeRoot "discovery.stderr.txt"), $DiscoveryResult.StandardError, $Utf8NoBom)
            if (-not $DiscoveryResult.TimedOut -and $DiscoveryResult.ExitCode -ne 0) {
                Write-Host $DiscoveryResult.StandardOutput
                Write-Host $DiscoveryResult.StandardError
                Add-Failure "First-start Xen Tuner discovery failed (exit $($DiscoveryResult.ExitCode))"
            }

            $PluginListPath = Join-Path $ConfigDirectory "plugins.xml"
            if (-not (Test-Path -LiteralPath $PluginListPath -PathType Leaf)) {
                Add-Failure "MuseScore did not persist plugins.xml during first-start discovery"
            }
            else {
                try {
                    $PluginDocument = New-Object Xml.XmlDocument
                    $PluginDocument.Load($PluginListPath)
                    $DefaultPluginSuffix = "plugins/musescore-xen-tuner/Xen Tuner/xen tuner.qml"
                    $MatchingPlugins = @($PluginDocument.SelectNodes("/museScore/Plugin") | Where-Object {
                        $PathNode = $_.SelectSingleNode("path")
                        if (-not $PathNode) {
                            return $false
                        }
                        $NormalizedPath = $PathNode.InnerText.Replace('\', '/')
                        return $NormalizedPath.EndsWith($DefaultPluginSuffix, [StringComparison]::OrdinalIgnoreCase)
                    })
                    if ($MatchingPlugins.Count -ne 1) {
                        Add-Failure "Expected exactly one discovered Xen Tuner entry in plugins.xml; found $($MatchingPlugins.Count)"
                    }
                    else {
                        $LoadNode = $MatchingPlugins[0].SelectSingleNode("load")
                        if (-not $LoadNode -or $LoadNode.InnerText.Trim() -ne "1") {
                            Add-Failure "Xen Tuner was discovered but was not marked load=1 on first start"
                        }
                    }
                }
                catch {
                    Add-Failure "Unable to validate first-start plugins.xml: $($_.Exception.Message)"
                }
            }

            if (Test-Path -LiteralPath $DiagnosticLog -PathType Leaf) {
                Remove-Item -LiteralPath $DiagnosticLog -Force
            }
            Write-Host "Invoking the packaged Xen Tuner QML entry point"
            $PluginResult = Invoke-ProcessWithTimeout `
                -Executable $MuseScoreExecutable.FullName `
                -Arguments @(
                    "-s", "-m", "-w",
                    "-c", $ConfigDirectory,
                    "-p", "musescore-xen-tuner/Xen Tuner/xen tuner.qml",
                    $SmokeScore
                ) `
                -TimeoutSeconds $SmokeTimeoutSeconds `
                -WorkingDirectory $SmokeRoot `
                -Environment $SmokeEnvironment
            [IO.File]::WriteAllText((Join-Path $SmokeRoot "plugin.stdout.txt"), $PluginResult.StandardOutput, $Utf8NoBom)
            [IO.File]::WriteAllText((Join-Path $SmokeRoot "plugin.stderr.txt"), $PluginResult.StandardError, $Utf8NoBom)
            if ($PluginResult.TimedOut -or $PluginResult.ExitCode -ne 0) {
                Write-Host $PluginResult.StandardOutput
                Write-Host $PluginResult.StandardError
                Add-Failure "Xen Tuner plugin-mode smoke test failed (exit $($PluginResult.ExitCode), timed out: $($PluginResult.TimedOut))"
            }

            $PluginDiagnostics = $PluginResult.StandardOutput + "`n" + $PluginResult.StandardError
            if (Test-Path -LiteralPath $DiagnosticLog -PathType Leaf) {
                $PluginDiagnostics += "`n" + (Get-Content -LiteralPath $DiagnosticLog -Raw)
            }
            $QmlFailurePattern = 'module ".*" is not installed|Type .* unavailable|QQmlComponent: Component is not ready|creating component .* failed|invalid QML root|Cannot load library'
            if ($PluginDiagnostics -match $QmlFailurePattern) {
                Write-Host $PluginDiagnostics
                Add-Failure "Xen Tuner produced a QML load error during plugin-mode smoke testing"
            }

            try {
                if ($null -ne $XenTunerRuntimeHashesBeforeSmoke) {
                    $XenTunerRuntimeHashesAfterSmoke = Get-FileHashMap -Root $InstalledXenTunerRoot
                    Assert-FileHashMapUnchanged `
                        -Before $XenTunerRuntimeHashesBeforeSmoke `
                        -After $XenTunerRuntimeHashesAfterSmoke `
                        -Description "Packaged Xen Tuner runtime during smoke testing"
                }

                if (-not (Test-Path -LiteralPath $InstalledXenTunerManifest -PathType Leaf)) {
                    Add-Failure "Packaged Xen Tuner runtime manifest was removed during smoke testing"
                }
                elseif ($XenTunerManifestHashBeforeSmoke) {
                    $XenTunerManifestHashAfterSmoke = (Get-FileHash -LiteralPath $InstalledXenTunerManifest -Algorithm SHA256).Hash
                    if ($XenTunerManifestHashAfterSmoke -ine $XenTunerManifestHashBeforeSmoke) {
                        Add-Failure "Packaged Xen Tuner runtime manifest was modified during smoke testing"
                    }
                }
            }
            catch {
                Add-Failure "Unable to verify Xen Tuner runtime immutability after smoke testing: $($_.Exception.Message)"
            }

            $XenTunerUserRoots = @()
            foreach ($AppDataRoot in @($RoamingAppDataDirectory, $LocalAppDataDirectory)) {
                $XenTunerUserRoots += @(Get-ChildItem -LiteralPath $AppDataRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Name -ieq "musescore-xen-tuner" -and
                        $_.Parent.Name -ieq "plugins"
                    })
            }
            $XenTunerUserRoots = @($XenTunerUserRoots | Sort-Object FullName -Unique)
            if ($XenTunerUserRoots.Count -eq 0) {
                Add-Failure "Xen Tuner did not create its writable AppData directory below the isolated APPDATA or LOCALAPPDATA roots"
            }
            else {
                if ($XenTunerUserRoots.Count -ne 1) {
                    Add-Failure "Expected exactly one Xen Tuner writable AppData directory; found $($XenTunerUserRoots.Count)"
                }
                foreach ($XenTunerUserRoot in $XenTunerUserRoots) {
                    $UserConfigPath = Join-Path $XenTunerUserRoot.FullName "config\xen-tuner.config.json"
                    if (-not (Test-Path -LiteralPath $UserConfigPath -PathType Leaf)) {
                        Add-Failure "Xen Tuner did not create its writable user configuration below isolated AppData: $UserConfigPath"
                    }
                    elseif ((Get-Item -LiteralPath $UserConfigPath).Length -eq 0) {
                        Add-Failure "Xen Tuner created an empty writable user configuration: $UserConfigPath"
                    }

                    $UserLogDirectory = Join-Path $XenTunerUserRoot.FullName "logs"
                    $UserLogs = @(Get-ChildItem -LiteralPath $UserLogDirectory -File -Filter "*.log" -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Length -gt 0 })
                    if ($UserLogs.Count -eq 0) {
                        Add-Failure "Xen Tuner did not create a non-empty operation log below isolated AppData: $UserLogDirectory"
                    }
                }
            }
        }
    }
    catch {
        Add-Failure "Windows packaged runtime smoke test could not complete: $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $SmokeRoot) {
            if ($Failures.Count -gt $SmokeFailureCountBefore) {
                Write-Host "Smoke-test diagnostics retained at: $SmokeRoot"
            }
            else {
                Remove-Item -LiteralPath $SmokeRoot -Recurse -Force
            }
        }
    }
}

if ($Failures.Count -gt 0) {
    Write-Host "Windows Qt 6 deployment verification failed:" -ForegroundColor Red
    foreach ($Failure in $Failures) {
        Write-Host "  - $Failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Windows Qt 6 deployment verification passed."
Write-Host "  Root: $InstallRoot"
Write-Host "  PE files checked: $($PeFiles.Count)"
if ($RequireXenTuner) {
    Write-Host "  Xen Tuner runtime files checked: $ValidatedXenTunerRuntimeFileCount"
}
if ($SkipDependencyScan) {
    Write-Host "  Dependency scan: skipped"
}
else {
    Write-Host "  Dependency scan: passed"
}
if ($RunSmokeTests) {
    Write-Host "  Runtime smoke tests: passed"
}
