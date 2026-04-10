<#
    Algoramming Local TCP - Professional Windows Installer
    Registers the hardware bridge with Chrome securely.
#>

$ErrorActionPreference = "Stop"
$HOST_NAME = "com.algoramming.localtcp"
$INSTALL_DIR = "$env:APPDATA\Algoramming\LocalTCP"
$MANIFEST_NAME = "$HOST_NAME.json"

Write-Host "----------------------------------------------------" -ForegroundColor Cyan
Write-Host "🚀 Local TCP Bridge - Setup (Windows)" -ForegroundColor Cyan
Write-Host "----------------------------------------------------" -ForegroundColor Cyan

# 1. Create installation directory
if (!(Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR
}

# 2. Copy files (assuming we are in the temp unzip folder)
Copy-Item "index.js" -Destination "$INSTALL_DIR\index.js" -Force
Copy-Item "$MANIFEST_NAME" -Destination "$INSTALL_DIR\$MANIFEST_NAME" -Force

# 3. Register Manifest with Chrome
$REG_PATH = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HOST_NAME"
if (!(Test-Path $REG_PATH)) {
    New-Item -Path $REG_PATH -Force
}

# Update the manifest template with the absolute path
$MANIFEST_CONTENT = Get-Content "$INSTALL_DIR\$MANIFEST_NAME" -Raw
$ESCAPED_PATH = "$INSTALL_DIR\index.js".Replace("\", "\\")
$MANIFEST_CONTENT = $MANIFEST_CONTENT -replace "HOST_PATH", $ESCAPED_PATH
$MANIFEST_CONTENT | Out-File -FilePath "$INSTALL_DIR\$MANIFEST_NAME" -Encoding ascii

# Set Registry Key
Set-ItemProperty -Path $REG_PATH -Name "(default)" -Value "$INSTALL_DIR\$MANIFEST_NAME"

Write-Host "✅ Bridge installed successfully!" -ForegroundColor Green
Write-Host "📍 Location: $INSTALL_DIR" -ForegroundColor Gray
Write-Host ""
Write-Host "👉 Please restart Chrome to complete the setup." -ForegroundColor Yellow
Write-Host "----------------------------------------------------"
Pause
