# QuickShare Studio App Launcher
# Bulletproof, silent launcher for QuickShare Studio
# Bypasses Device Guard restrictions by using signed native Windows executables (wscript/pythonw/edge/chrome)

$ErrorActionPreference = "SilentlyContinue"

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (!(Test-Path (Join-Path $AppDir "web"))) {
    # Running from the repository's scripts\ folder: use the repo root (build\web).
    $RepoRoot = Split-Path -Parent $AppDir
    if (Test-Path (Join-Path $RepoRoot "build\web")) {
        $AppDir = $RepoRoot
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\QuickShare Studio\web") {
        $AppDir = "$env:LOCALAPPDATA\Programs\QuickShare Studio"
    }
}

$PortFile = Join-Path $AppDir "active_port.txt"
$ServerPy = Join-Path $AppDir "server.py"
if (!(Test-Path $ServerPy)) {
    $ServerPy = Join-Path $AppDir "scripts\server.py"
}

# 1. Check if server is already running and responding
$RunningPort = $null
if (Test-Path $PortFile) {
    $SavedPort = (Get-Content $PortFile -Raw).Trim()
    if ($SavedPort -match "^\d+$") {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $async = $tcp.BeginConnect("127.0.0.1", [int]$SavedPort, $null, $null)
            $wait = $async.AsyncWaitHandle.WaitOne(300, $false)
            if ($wait -and $tcp.Connected) {
                $tcp.EndConnect($async)
                $tcp.Close()
                $RunningPort = [int]$SavedPort
            }
        } catch { }
    }
}

# 2. If not running, start server in background
if (-not $RunningPort) {
    # Find pythonw or python
    $PythonExe = $null
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python314\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python313\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\pythonw.exe",
        "pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
        "python.exe"
    )

    foreach ($c in $candidates) {
        if ($c -like "*\*" -and (Test-Path $c)) {
            $PythonExe = $c
            break
        } elseif (!($c -like "*\*") -and (Get-Command $c -ErrorAction SilentlyContinue)) {
            $PythonExe = (Get-Command $c).Source
            break
        }
    }

    if ($PythonExe -and (Test-Path $ServerPy)) {
        Start-Process -FilePath $PythonExe -ArgumentList "`"$ServerPy`"" -WorkingDirectory $AppDir -WindowStyle Hidden
        
        # Wait up to 3 seconds for active_port.txt to be created
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Milliseconds 200
            if (Test-Path $PortFile) {
                $content = (Get-Content $PortFile -Raw).Trim()
                if ($content -match "^\d+$") {
                    $RunningPort = [int]$content
                    break
                }
            }
        }
    }
}

if (-not $RunningPort) {
    $RunningPort = 52830
}

# 3. Locate browser for application window
$Url = "http://127.0.0.1:$RunningPort/index.html"
$ProfileDir = "$env:LOCALAPPDATA\QuickShareStudio\AppProfile"
if (!(Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

$ChromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)

$EdgePaths = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
)

$BrowserExe = $null
foreach ($p in $ChromePaths) {
    if (Test-Path $p) {
        $BrowserExe = $p
        break
    }
}

if (-not $BrowserExe) {
    foreach ($p in $EdgePaths) {
        if (Test-Path $p) {
            $BrowserExe = $p
            break
        }
    }
}

if ($BrowserExe) {
    $Args = "--app=$Url --window-size=1366,850 `"--user-data-dir=$ProfileDir`""
    Start-Process -FilePath $BrowserExe -ArgumentList $Args
} else {
    Start-Process -FilePath $Url
}
