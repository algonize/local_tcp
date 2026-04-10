<#
    Algoramming Local TCP - Professional Windows Uninstaller
    Removes the hardware bridge and Chrome registration.
#>

$ErrorActionPreference = "Stop"
$HOST_NAME = "com.algoramming.localtcp"
$INSTALL_DIR = "$env:APPDATA\Algoramming\LocalTCP"
$REG_PATH = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HOST_NAME"

Write-Host "----------------------------------------------------" -ForegroundColor Yellow
Write-Host "🗑️ Local TCP Bridge - Uninstaller (Windows)" -ForegroundColor Yellow
Write-Host "----------------------------------------------------" -ForegroundColor Yellow

# 1. Remove Registry Key
if (Test-Path $REG_PATH) {
    Remove-Item -Path $REG_PATH -Force
    Write-Host "✅ Chrome registration removed." -ForegroundColor Green
}

# 2. Remove Files
if (Test-Path $INSTALL_DIR) {
    Remove-Item -Path $INSTALL_DIR -Recurse -Force
    Write-Host "✅ Bridge files removed." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. The bridge has been completely removed." -ForegroundColor Cyan
Write-Host "----------------------------------------------------"
Pause
