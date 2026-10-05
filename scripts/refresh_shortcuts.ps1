$WshShell = New-Object -ComObject WScript.Shell
$DesktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
$ProgramsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
$InstalledDir = "C:\Users\Abhijeet\AppData\Local\Programs\QuickShare Studio"
$InstalledIcon = Join-Path $InstalledDir "app_icon.ico"
$WorkingIcon = "c:\Users\Abhijeet\Desktop\QUICK SHARE\app_icon.ico"

# 1. Ensure the icon in installed dir is updated
if (Test-Path $WorkingIcon) {
    if (-not (Test-Path $InstalledDir)) {
        New-Item -ItemType Directory -Path $InstalledDir -Force | Out-Null
    }
    Copy-Item -Path $WorkingIcon -Destination $InstalledIcon -Force
    Write-Host "Copied updated app_icon.ico to $InstalledIcon"
}

# 2. Update Desktop Shortcut
$DesktopLnk = Join-Path $DesktopPath "QuickShare Studio.lnk"
if (Test-Path $DesktopLnk) {
    # Delete old shortcut and create clean new one so Windows drops old icon cache entry
    Remove-Item -Path $DesktopLnk -Force
}
$sc = $WshShell.CreateShortcut($DesktopLnk)
$sc.TargetPath = "$env:SystemRoot\System32\wscript.exe"
$sc.Arguments = "`"$InstalledDir\launch.vbs`""
$sc.WorkingDirectory = $InstalledDir
$sc.IconLocation = "$InstalledIcon,0"
$sc.Description = "QuickShare Studio - Cross-Device File Sharing & PDF Studio"
$sc.Save()
Write-Host "Created fresh Desktop shortcut with new icon: $DesktopLnk"

# 3. Update Start Menu Shortcut
$StartLnk = Join-Path $ProgramsPath "QuickShare Studio.lnk"
if (Test-Path $StartLnk) {
    Remove-Item -Path $StartLnk -Force
}
$sc2 = $WshShell.CreateShortcut($StartLnk)
$sc2.TargetPath = "$env:SystemRoot\System32\wscript.exe"
$sc2.Arguments = "`"$InstalledDir\launch.vbs`""
$sc2.WorkingDirectory = $InstalledDir
$sc2.IconLocation = "$InstalledIcon,0"
$sc2.Description = "QuickShare Studio - Cross-Device File Sharing & PDF Studio"
$sc2.Save()
Write-Host "Created fresh Start Menu shortcut with new icon: $StartLnk"

# 4. Notify Windows Shell of association / icon change
$Signature = @'
[DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern void SHChangeNotify(uint wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
'@
$Shell32 = Add-Type -MemberDefinition $Signature -Name "Win32SHChangeNotify" -Namespace "Win32Functions" -PassThru
$Shell32::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
Write-Host "Triggered Windows Shell icon refresh (SHCNE_ASSOCCHANGED)."

# 5. Also touch ie4uinit to reload icon cache
Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -Wait -NoNewWindow -ErrorAction SilentlyContinue
Write-Host "Triggered ie4uinit icon cache refresh."
