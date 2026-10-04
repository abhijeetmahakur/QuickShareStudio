@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0QuickShareStudio.exe" (
    start "" "%~dp0QuickShareStudio.exe"
    exit /b 0
)

set "WEB_DIR="
if exist "%~dp0build\web\index.html" (
    set "WEB_DIR=%~dp0build\web"
) else if exist "%~dp0web\index.html" (
    set "WEB_DIR=%~dp0web"
)

if "%WEB_DIR%"=="" exit /b 1

set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
set "CHROME_X86=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
set "EDGE=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
set "EDGE_64=C:\Program Files\Microsoft\Edge\Application\msedge.exe"

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
exit /b 0
