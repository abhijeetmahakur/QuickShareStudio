@echo off
setlocal
cd /d "%~dp0"
title QuickShare Studio

echo ========================================================
echo               QuickShare Studio Launcher
echo ========================================================
echo.

set "WEB_DIR="
if exist "%~dp0build\web\index.html" (
    set "WEB_DIR=%~dp0build\web"
) else if exist "%~dp0web\index.html" (
    set "WEB_DIR=%~dp0web"
)

if "%WEB_DIR%"=="" (
    echo [ERROR] Could not find the QuickShare web build directory.
    echo Please run 'flutter build web' first.
    pause
    exit /b 1
)

echo [OK] Located QuickShare web bundle.
echo [..] Starting local application server...

:: Start background python server
start /b "" python -m http.server 52830 --directory "%WEB_DIR%" >nul 2>&1
timeout /t 1 /nobreak >nul

set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
set "CHROME_X86=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
set "EDGE=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
set "EDGE_64=C:\Program Files\Microsoft\Edge\Application\msedge.exe"

echo [..] Launching QuickShare Studio window...

if exist "%CHROME%" (
    start "" "%CHROME%" --app=http://127.0.0.1:52830/index.html --window-size=1366,850
) else if exist "%CHROME_X86%" (
    start "" "%CHROME_X86%" --app=http://127.0.0.1:52830/index.html --window-size=1366,850
) else if exist "%EDGE%" (
    start "" "%EDGE%" --app=http://127.0.0.1:52830/index.html --window-size=1366,850
) else if exist "%EDGE_64%" (
    start "" "%EDGE_64%" --app=http://127.0.0.1:52830/index.html --window-size=1366,850
) else (
    start "" "http://127.0.0.1:52830/index.html"
)

echo.
echo ========================================================
echo QuickShare Studio is running!
echo You can minimize this window while using the application.
echo ========================================================
echo.
pause >nul
