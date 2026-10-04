@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title QuickShare Studio - Live Development Mode

echo ========================================================
echo       QuickShare Studio - Live Development Runner
echo ========================================================
echo.
echo  Code changes saved in lib/ will automatically Hot Reload.
echo  Structural / model changes will automatically Hot Restart.
echo.

set "DEVICE=chrome"
if not "%~1"=="" (
    set "DEVICE=%~1"
)

echo Target Device: %DEVICE%
echo.

where python >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [OK] Launching dev watcher...
    python scripts\dev_runner.py -d %DEVICE%
) else (
    echo [WARN] Python not found on PATH. Falling back to flutter run...
    echo Hot reload key: 'r', Hot restart key: 'R'
    flutter run -d %DEVICE%
)

if %ERRORLEVEL% neq 0 (
    echo.
    echo Development session ended with exit code %ERRORLEVEL%.
    pause
)
