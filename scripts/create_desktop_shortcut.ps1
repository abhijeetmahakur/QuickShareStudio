$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
$ProgramsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
$WorkingDir = Split-Path -Parent $PSScriptRoot
$VbsLauncher = Join-Path $WorkingDir "QuickShare.vbs"
$IconPath = Join-Path $WorkingDir "app_icon.ico"
$WscriptExe = "$env:SystemRoot\System32\wscript.exe"

# 1. Desktop Shortcut
$DesktopShortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "QuickShare Studio.lnk"))
$DesktopShortcut.TargetPath = $WscriptExe
$DesktopShortcut.Arguments = "`"$VbsLauncher`""
$DesktopShortcut.WorkingDirectory = $WorkingDir
$DesktopShortcut.IconLocation = "$IconPath,0"
$DesktopShortcut.Description = "QuickShare Studio - Lab Share & PDF Studio"
$DesktopShortcut.Save()
Write-Host "Created Desktop shortcut: $DesktopPath\QuickShare Studio.lnk"

# 2. Start Menu Shortcut
$StartMenuShortcut = $WshShell.CreateShortcut((Join-Path $ProgramsPath "QuickShare Studio.lnk"))
$StartMenuShortcut.TargetPath = $WscriptExe
$StartMenuShortcut.Arguments = "`"$VbsLauncher`""
$StartMenuShortcut.WorkingDirectory = $WorkingDir
$StartMenuShortcut.IconLocation = "$IconPath,0"
$StartMenuShortcut.Description = "QuickShare Studio - Lab Share & PDF Studio"
$StartMenuShortcut.Save()
Write-Host "Created Start Menu shortcut: $ProgramsPath\QuickShare Studio.lnk"
