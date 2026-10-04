# QuickShare Studio - Live Development Runner
# Enables automated hot reload on save, automatic hot restart fallback, and compile error resilience.
param(
    [ValidateSet("chrome", "edge", "windows")]
    [string]$Device = "chrome",

    [int]$Port = 52835
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "========================================================" -ForegroundColor Green
Write-Host "       QuickShare Studio - Live Development Mode       " -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Device: $Device" -ForegroundColor Cyan
Write-Host "Root  : $ProjectRoot" -ForegroundColor Gray
Write-Host ""

# Check for Python
$PythonExe = (Get-Command python -ErrorAction SilentlyContinue)
if ($PythonExe) {
    Write-Host "[OK] Using Python file-watcher dev runner..." -ForegroundColor Green
    & python (Join-Path $ScriptDir "dev_runner.py") -d $Device -p $Port
} else {
    Write-Host "[WARN] Python not found on PATH. Falling back to native flutter run..." -ForegroundColor Yellow
    Write-Host "Press 'r' in this window for Hot Reload, 'R' for Hot Restart, 'q' to Quit." -ForegroundColor Cyan
    Set-Location $ProjectRoot
    flutter run -d $Device
}
