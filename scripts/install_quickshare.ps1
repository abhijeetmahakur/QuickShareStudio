# QuickShare Studio Windows Installation Script
# Installs QuickShare Studio into %LOCALAPPDATA%\Programs\QuickShare Studio
# Registers the application in Windows Registry (Installed Apps) and creates Start Menu & Desktop shortcuts.

param(
    # Copy the existing build\web as-is instead of rebuilding it from lib\ first.
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$SourceDir = Split-Path -Parent $PSScriptRoot
$InstallDir = "$env:LOCALAPPDATA\Programs\QuickShare Studio"
$Version = (Get-Content (Join-Path $SourceDir "VERSION") -Raw).Trim()
$AppName = "QuickShare Studio"
$Publisher = "QuickShare Studio"

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "         QuickShare Studio Desktop Installation" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

# 0. Rebuild the web bundle so the installed app reflects the current source code.
# Without this, edits in lib\ never reach the installed app (it serves a static copy of build\web).
if (-not $SkipBuild) {
    Write-Host "[0/5] Building release web bundle from source (flutter build web)..." -ForegroundColor Yellow
    Push-Location $SourceDir
    try {
        # --wasm: faster skwasm renderer (falls back to JS automatically on older browsers).
        # --no-web-resources-cdn: bundle the renderer instead of downloading it from gstatic on every launch.
        & flutter build web --release --wasm --no-web-resources-cdn
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed (exit code $LASTEXITCODE); installed app left unchanged." }
    } finally {
        Pop-Location
    }
}

# 1. Terminate running instances or orphan servers
Write-Host "[1/5] Checking for running instances..." -ForegroundColor Yellow
Get-Process -Name "QuickShareStudio" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name = 'python.exe' or Name = 'pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*http.server 52830*" -or $_.CommandLine -like "*server.py*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. Ensure target directory exists
if (!(Test-Path $InstallDir)) {
    Write-Host "      Creating install directory at $InstallDir..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
} else {
    Write-Host "      Existing installation directory found at $InstallDir." -ForegroundColor Yellow
}

# 3. Copy binaries and application assets
Write-Host "[2/5] Copying application bundle and launcher assets..." -ForegroundColor Yellow

$IconSource = Join-Path $SourceDir "app_icon.ico"
$WebSource = Join-Path $SourceDir "build\web"
$WebDest = Join-Path $InstallDir "web"

Copy-Item -Path $IconSource -Destination (Join-Path $InstallDir "app_icon.ico") -Force
Copy-Item -Path (Join-Path $SourceDir "scripts\launch.vbs") -Destination (Join-Path $InstallDir "launch.vbs") -Force
Copy-Item -Path (Join-Path $SourceDir "scripts\launch.ps1") -Destination (Join-Path $InstallDir "launch.ps1") -Force
Copy-Item -Path (Join-Path $SourceDir "scripts\server.py") -Destination (Join-Path $InstallDir "server.py") -Force

if (Test-Path $WebDest) {
    Remove-Item -Path $WebDest -Recurse -Force
}
Copy-Item -Path $WebSource -Destination $WebDest -Recurse -Force

Write-Host "      Web bundle and silent launchers deployed successfully." -ForegroundColor Green

# 4. Create uninstaller scripts
Write-Host "[3/5] Generating uninstaller scripts..." -ForegroundColor Yellow

$UninstallPs1 = @"
# QuickShare Studio Uninstaller
`$ErrorActionPreference = "SilentlyContinue"

# 1. Terminate running instances
Get-Process -Name "QuickShareStudio" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name = 'python.exe' or Name = 'pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -like "*server.py*" } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }

# 2. Remove Shortcuts
`$desktopLnk = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) "QuickShare Studio.lnk"
if (Test-Path `$desktopLnk) { Remove-Item -Path `$desktopLnk -Force }

`$startLnk = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) "QuickShare Studio.lnk"
if (Test-Path `$startLnk) { Remove-Item -Path `$startLnk -Force }

# 3. Remove Registry Uninstall Key
`$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\QuickShareStudio"
if (Test-Path `$regKey) { Remove-Item -Path `$regKey -Recurse -Force }

# 4. Schedule directory removal
`$installFolder = "$InstallDir"
Start-Process cmd.exe -ArgumentList "/c timeout /t 2 /nobreak >nul & rmdir /s /q ```"`$installFolder```"" -WindowStyle Hidden
"@

$UninstallBat = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0uninstall.ps1"
"@

Set-Content -Path (Join-Path $InstallDir "uninstall.ps1") -Value $UninstallPs1 -Encoding UTF8
Set-Content -Path (Join-Path $InstallDir "uninstall.bat") -Value $UninstallBat -Encoding ASCII

# 5. Create Desktop and Start Menu Shortcuts
Write-Host "[4/5] Creating Start Menu and Desktop shortcuts..." -ForegroundColor Yellow

$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
$ProgramsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
$WscriptExe = "$env:SystemRoot\System32\wscript.exe"
$VbsLauncher = Join-Path $InstallDir "launch.vbs"
$InstalledIcon = Join-Path $InstallDir "app_icon.ico"

# Desktop shortcut
$DesktopLnk = Join-Path $DesktopPath "QuickShare Studio.lnk"
$Shortcut = $WshShell.CreateShortcut($DesktopLnk)
$Shortcut.TargetPath = $WscriptExe
$Shortcut.Arguments = "`"$VbsLauncher`""
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.IconLocation = "$InstalledIcon,0"
$Shortcut.Description = "QuickShare Studio - Cross-Device File Sharing & PDF Studio"
$Shortcut.Save()
Write-Host "      Created Desktop shortcut: $DesktopLnk" -ForegroundColor Green

# Start Menu shortcut
$StartLnk = Join-Path $ProgramsPath "QuickShare Studio.lnk"
$StartShortcut = $WshShell.CreateShortcut($StartLnk)
$StartShortcut.TargetPath = $WscriptExe
$StartShortcut.Arguments = "`"$VbsLauncher`""
$StartShortcut.WorkingDirectory = $InstallDir
$StartShortcut.IconLocation = "$InstalledIcon,0"
$StartShortcut.Description = "QuickShare Studio - Cross-Device File Sharing & PDF Studio"
$StartShortcut.Save()
Write-Host "      Created Start Menu shortcut: $StartLnk" -ForegroundColor Green

# 6. Register in Windows Registry (Installed Apps)
Write-Host "[5/5] Registering in Windows 'Installed Apps' registry..." -ForegroundColor Yellow

$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\QuickShareStudio"
if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# Calculate estimated size in KB
$TotalBytes = (Get-ChildItem -Path $InstallDir -Recurse | Measure-Object -Property Length -Sum).Sum
$EstimatedSizeKB = [math]::Round($TotalBytes / 1024)
$InstallDate = (Get-Date -Format "yyyyMMdd")

Set-ItemProperty -Path $RegPath -Name "DisplayName" -Value $AppName -Type String
Set-ItemProperty -Path $RegPath -Name "DisplayVersion" -Value $Version -Type String
Set-ItemProperty -Path $RegPath -Name "Publisher" -Value $Publisher -Type String
Set-ItemProperty -Path $RegPath -Name "DisplayIcon" -Value "$InstalledIcon,0" -Type String
Set-ItemProperty -Path $RegPath -Name "InstallLocation" -Value $InstallDir -Type String
Set-ItemProperty -Path $RegPath -Name "InstallDate" -Value $InstallDate -Type String
Set-ItemProperty -Path $RegPath -Name "UninstallString" -Value "`"$InstallDir\uninstall.bat`"" -Type String
Set-ItemProperty -Path $RegPath -Name "QuietUninstallString" -Value "`"$InstallDir\uninstall.bat`"" -Type String
Set-ItemProperty -Path $RegPath -Name "EstimatedSize" -Value $EstimatedSizeKB -Type DWord
Set-ItemProperty -Path $RegPath -Name "NoModify" -Value 1 -Type DWord
Set-ItemProperty -Path $RegPath -Name "NoRepair" -Value 1 -Type DWord
Set-ItemProperty -Path $RegPath -Name "Comments" -Value "QuickShare Studio - Cross-Device File Sharing & PDF Studio" -Type String
Set-ItemProperty -Path $RegPath -Name "URLInfoAbout" -Value "https://github.com/QuickShareStudio" -Type String
Set-ItemProperty -Path $RegPath -Name "HelpLink" -Value "https://github.com/QuickShareStudio" -Type String

Write-Host "      Registered under HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\QuickShareStudio" -ForegroundColor Green
Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " QuickShare Studio successfully installed and registered!" -ForegroundColor Green
Write-Host " You can now find it in Windows Settings > Installed Apps," -ForegroundColor Green
Write-Host " on your Desktop, and in the Start Menu." -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Cyan
