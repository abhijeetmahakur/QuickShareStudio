# QuickShare Studio - One-Command Automated Release Script
param(
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " QuickShare Studio Automated Release Pipeline " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Run Flutter analyze and tests
Write-Host "`n[1/5] Running code analysis and tests..." -ForegroundColor Yellow
flutter analyze lib test
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter analyze found issues. Please fix them before releasing."
    exit 1
}

flutter test test/transfer/ test/update_check_test.dart test/qr_scanner_test.dart test/device_pairing_test.dart
if ($LASTEXITCODE -ne 0) {
    Write-Error "Tests failed. Please fix failing tests before releasing."
    exit 1
}
Write-Host "Analysis and tests passed successfully." -ForegroundColor Green

# 2. Bump version in pubspec.yaml and related files
Write-Host "`n[2/5] Bumping version numbers..." -ForegroundColor Yellow
$pubspecPath = "pubspec.yaml"
$pubspecContent = Get-Content $pubspecPath -Raw

if ($pubspecContent -match 'version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)') {
    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3] + 1
    $build = [int]$Matches[4] + 1

    $newVersion = "$major.$minor.$patch"
    $newFullVersion = "$newVersion+$build"
    Write-Host "Bumping version from $($Matches[1]).$($Matches[2]).$($Matches[3])+$($Matches[4]) to $newFullVersion" -ForegroundColor Green

    # Update pubspec.yaml
    $updatedPubspec = $pubspecContent -replace 'version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+', "version: $newFullVersion"
    Set-Content -Path $pubspecPath -Value $updatedPubspec -NoNewline

    # Update VERSION file
    Set-Content -Path "VERSION" -Value "$newVersion`n" -NoNewline

    # Update quickshare.iss
    if (Test-Path "windows/installer/quickshare.iss") {
        $issContent = Get-Content "windows/installer/quickshare.iss" -Raw
        $updatedIss = $issContent -replace '#define MyAppVersion\s*"[^"]+"', "#define MyAppVersion `"$newVersion`""
        Set-Content -Path "windows/installer/quickshare.iss" -Value $updatedIss -NoNewline
    }

    # Update constants.dart
    if (Test-Path "lib/core/constants.dart") {
        $constContent = Get-Content "lib/core/constants.dart" -Raw
        $updatedConst = $constContent -replace "appVersion\s*=\s*'[^']+'", "appVersion = '$newVersion'"
        Set-Content -Path "lib/core/constants.dart" -Value $updatedConst -NoNewline
    }

    # Update CHANGELOG.md
    if (Test-Path "CHANGELOG.md") {
        $changelog = Get-Content "CHANGELOG.md" -Raw
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        if (-not ($changelog -match "## \[$newVersion\]")) {
            $header = "## [$newVersion] - $dateStr`n`n### Changed`n- Maintenance update and performance improvements.`n`n"
            $changelog = $changelog -replace "(# Changelog\s*\n\s*All notable changes to QuickShare Studio[^\n]*\n\s*)", "`$1`n$header"
            Set-Content -Path "CHANGELOG.md" -Value $changelog -NoNewline
        }
    }
} else {
    Write-Error "Could not parse version from pubspec.yaml."
    exit 1
}

# 3. Commit and push
Write-Host "`n[3/5] Staging changes and committing..." -ForegroundColor Yellow
if (-not $Message) {
    $Message = "feat(release): bump to v$newVersion and publish release"
}

git add -A
git commit -m $Message
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Nothing new to commit or commit failed."
}

Write-Host "`n[4/5] Pushing to main..." -ForegroundColor Yellow
git push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Error "git push origin main failed."
    exit 1
}

# Tag and push tag as well
git tag "v$newVersion"
git push origin "v$newVersion"

# 4. Finish
Write-Host "`n[5/5] Release triggered successfully!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "New Version Tag   : v$newVersion" -ForegroundColor Yellow
Write-Host "GitHub Action Run : https://github.com/abhijeetmahakur/QuickShareStudio/actions" -ForegroundColor Cyan
Write-Host "GitHub Release    : https://github.com/abhijeetmahakur/QuickShareStudio/releases/tag/v$newVersion" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
