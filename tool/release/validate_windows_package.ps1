param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath
)

$ErrorActionPreference = "Stop"

function Assert-X64PeFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Windows binary is missing: $Path"
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt 0x40) {
            throw "Windows binary is truncated: $Path"
        }

        $reader = [System.IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "Windows binary has no valid DOS header: $Path"
        }

        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0x40 -or $peOffset -gt ($stream.Length - 6)) {
            throw "Windows binary has an invalid PE header offset: $Path"
        }

        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "Windows binary has no valid PE signature: $Path"
        }

        if ($reader.ReadUInt16() -ne 0x8664) {
            throw "Windows binary is not an x64 image: $Path"
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-ReleaseBundle {
    param([string]$Directory)

    $requiredFiles = @(
        "quickshare.exe",
        "flutter_windows.dll",
        "url_launcher_windows_plugin.dll",
        "data\icudtl.dat",
        "data\app.so"
    )
    foreach ($relativePath in $requiredFiles) {
        $path = Join-Path $Directory $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Windows release bundle is missing $relativePath in $Directory"
        }
    }

    foreach ($binary in @("quickshare.exe", "flutter_windows.dll", "url_launcher_windows_plugin.dll")) {
        Assert-X64PeFile (Join-Path $Directory $binary)
    }
}

function Test-ApplicationStartup {
    param(
        [string]$Directory,
        [string]$Description
    )

    $executable = Join-Path $Directory "quickshare.exe"
    $process = Start-Process -FilePath $executable -WorkingDirectory $Directory -PassThru
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        $pluginLoaded = $false
        while ([DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 500
            $process.Refresh()
            if ($process.HasExited) {
                throw "$Description exited during startup with code $($process.ExitCode)."
            }

            $pluginLoaded = @($process.Modules | Where-Object {
                $_.ModuleName -ieq "url_launcher_windows_plugin.dll"
            }).Count -gt 0
            if ($pluginLoaded) {
                break
            }
        }

        if (-not $pluginLoaded) {
            throw "$Description did not load url_launcher_windows_plugin.dll."
        }

        Write-Host "$Description started and loaded url_launcher_windows_plugin.dll."
    }
    finally {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
        # Stop-Process returns before Windows releases the app's DLLs; wait so
        # the next copy and the temporary folder cleanup are not blocked.
        if (-not $process.WaitForExit(15000)) {
            Write-Warning "$Description was still running 15 seconds after it was stopped."
        }
    }
}

function Remove-TemporaryDirectory {
    param([string]$Path)

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    # The packages already passed every check, so a locked temporary file must
    # not fail the release.
    Write-Warning "Could not remove the smoke-test folder ${Path}: files are still in use."
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("QuickShare-Windows-Smoke-" + [Guid]::NewGuid().ToString("N"))
$zipDirectory = Join-Path $temporaryDirectory "zip"
$installDirectory = Join-Path $temporaryDirectory "installed"
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null

try {
    Assert-ReleaseBundle $ReleaseDirectory
    Test-ApplicationStartup $ReleaseDirectory "Build output"

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $zipDirectory
    Assert-ReleaseBundle $zipDirectory
    $sourceHash = (Get-FileHash (Join-Path $ReleaseDirectory "url_launcher_windows_plugin.dll") -Algorithm SHA256).Hash
    $zipHash = (Get-FileHash (Join-Path $zipDirectory "url_launcher_windows_plugin.dll") -Algorithm SHA256).Hash
    if ($sourceHash -ne $zipHash) {
        throw "The Windows ZIP contains a different url_launcher_windows_plugin.dll than the build output."
    }
    Test-ApplicationStartup $zipDirectory "Windows ZIP"

    $installerArguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$installDirectory`""
    $installer = Start-Process -FilePath $InstallerPath -ArgumentList $installerArguments -Wait -PassThru
    if ($installer.ExitCode -ne 0) {
        throw "The Windows installer exited with code $($installer.ExitCode)."
    }

    Assert-ReleaseBundle $installDirectory
    $installedHash = (Get-FileHash (Join-Path $installDirectory "url_launcher_windows_plugin.dll") -Algorithm SHA256).Hash
    if ($sourceHash -ne $installedHash) {
        throw "The Windows installer contains a different url_launcher_windows_plugin.dll than the build output."
    }
    Test-ApplicationStartup $installDirectory "Installed application"
}
finally {
    Remove-TemporaryDirectory $temporaryDirectory
}
