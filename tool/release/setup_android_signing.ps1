<#
.SYNOPSIS
    Prepares and validates Android release keystore secrets for GitHub Actions.
.DESCRIPTION
    Encodes a JKS/PKCS12 keystore to standard Base64, verifies the password
    and key alias using keytool, calculates the exact SHA-256 certificate
    fingerprint, and copies the Base64 string to the clipboard.
.PARAMETER KeystorePath
    Path to an existing .jks or .keystore file. If omitted, prompts to create one.
.PARAMETER KeyAlias
    The key alias within the keystore.
.PARAMETER StorePassword
    The keystore password. If omitted, prompts securely.
.PARAMETER KeyPassword
    The key password. If omitted, defaults to StorePassword.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$KeystorePath,

    [Parameter(Mandatory=$false)]
    [string]$KeyAlias = "quickshare",

    [Parameter(Mandatory=$false)]
    [string]$StorePassword,

    [Parameter(Mandatory=$false)]
    [string]$KeyPassword
)

$ErrorActionPreference = "Stop"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " QuickShare Studio — Android Release Signing Helper" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Locate or create keystore
if (-not $KeystorePath -or -not (Test-Path $KeystorePath)) {
    if ($KeystorePath -and -not (Test-Path $KeystorePath)) {
        Write-Warning "Keystore file not found at: $KeystorePath"
    }

    $defaultPath = Join-Path $PWD "android\release.jks"
    Write-Host "No valid keystore path supplied."
    $choice = Read-Host "Create a new permanent release keystore at '$defaultPath'? (Y/N)"
    if ($choice -match '^[Yy]') {
        if (-not $StorePassword) {
            $StorePassword = Read-Host "Enter keystore password (at least 6 characters)"
        }
        if (-not $KeyPassword) {
            $KeyPassword = $StorePassword
        }
        $KeyAlias = Read-Host "Enter key alias [default: quickshare]"
        if (-not $KeyAlias) { $KeyAlias = "quickshare" }

        $dname = "CN=QuickShare Studio, OU=Release, O=QuickShare, L=City, ST=State, C=US"
        Write-Host "Generating release keystore using keytool..." -ForegroundColor Yellow
        keytool -genkeypair -v -keystore $defaultPath -storetype JKS -alias $KeyAlias `
            -keyalg RSA -keysize 2048 -validity 10000 `
            -storepass $StorePassword -keypass $KeyPassword `
            -dname $dname

        $KeystorePath = $defaultPath
        Write-Host "Created keystore at: $KeystorePath" -ForegroundColor Green
    } else {
        $KeystorePath = Read-Host "Enter path to existing .jks or .keystore file"
        if (-not (Test-Path $KeystorePath)) {
            Write-Error "File not found: $KeystorePath"
            exit 1
        }
    }
}

# 2. Collect passwords if needed
if (-not $StorePassword) {
    $StorePassword = Read-Host "Enter keystore password"
}
if (-not $KeyPassword) {
    $KeyPassword = $StorePassword
}

# 3. Verify with keytool and extract SHA-256 fingerprint
Write-Host "`nVerifying keystore with keytool..." -ForegroundColor Yellow
$certOutput = keytool -list -v -keystore $KeystorePath -storepass $StorePassword -alias $KeyAlias 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to read keystore: $certOutput"
    exit 1
}

$sha256Line = $certOutput | Where-Object { $_ -match "SHA256:\s*([A-Fa-f0-9:]+)" }
if (-not $sha256Line) {
    Write-Error "Could not find SHA-256 certificate fingerprint in keytool output."
    exit 1
}

$rawFingerprint = ($Matches[1] -replace '[:\s]', '').ToLower()

# 4. Convert keystore bytes to pure Base64
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $KeystorePath))
$base64String = [System.Convert]::ToBase64String($bytes)

# Validate no invalid chars
$clean = $base64String -replace '\s', ''
if ($clean -match '[^A-Za-z0-9+/=]') {
    Write-Error "Keystore encoding produced non-Base64 characters."
    exit 1
}

# Copy to clipboard
$base64String | Set-Clipboard

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " SUCCESS! Keystore validated and Base64 copied to clipboard!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "`nSet the following GitHub Actions Secrets in your repository:" -ForegroundColor White
Write-Host "(Settings -> Secrets and variables -> Actions)`n" -ForegroundColor White

Write-Host "1. ANDROID_KEYSTORE_BASE64" -ForegroundColor Cyan
Write-Host "   -> [COPIED TO CLIPBOARD - Just press Ctrl+V in GitHub Secret input]" -ForegroundColor Green

Write-Host "`n2. ANDROID_KEYSTORE_PASSWORD" -ForegroundColor Cyan
Write-Host "   -> $StorePassword" -ForegroundColor Yellow

Write-Host "`n3. ANDROID_KEY_ALIAS" -ForegroundColor Cyan
Write-Host "   -> $KeyAlias" -ForegroundColor Yellow

Write-Host "`n4. ANDROID_KEY_PASSWORD" -ForegroundColor Cyan
Write-Host "   -> $KeyPassword" -ForegroundColor Yellow

Write-Host "`n5. ANDROID_RELEASE_CERT_SHA256" -ForegroundColor Cyan
Write-Host "   -> $rawFingerprint" -ForegroundColor Yellow

Write-Host "`nDo NOT commit $KeystorePath to Git. Ensure it remains in .gitignore.`n" -ForegroundColor Red
