<#
    Algoramming Local TCP - Professional Windows Uninstaller
    Removes the hardware bridge and Chrome registration.
#>

$ErrorActionPreference = "Stop"
$HOST_NAME = "com.algoramming.localtcp"
$INSTALL_DIR = "$env:APPDATA\Algoramming\LocalTCP"
$REG_PATH = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HOST_NAME"

function Run-Uninstaller {
    try {
        Write-Host "----------------------------------------------------" -ForegroundColor Yellow
        Write-Host "🗑️ Local TCP Bridge - Uninstaller (Windows)" -ForegroundColor Yellow
        Write-Host "----------------------------------------------------" -ForegroundColor Yellow

        # 1. Remove Registry Key
        if (Test-Path $REG_PATH) {
            Write-Host "🔗 Removing Chrome registration..." -ForegroundColor Gray
            Remove-Item -Path $REG_PATH -Force
            Write-Host "✅ Chrome registration removed." -ForegroundColor Green
        } else {
            Write-Host "ℹ️ Chrome registration not found. Skipping." -ForegroundColor Gray
        }

        # 2. Remove Files
        if (Test-Path $INSTALL_DIR) {
            Write-Host "📁 Removing bridge files..." -ForegroundColor Gray
            Remove-Item -Path $INSTALL_DIR -Recurse -Force
            Write-Host "✅ Bridge files removed." -ForegroundColor Green
        } else {
            Write-Host "ℹ️ Installation directory not found. Skipping." -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Done. The bridge has been completely removed." -ForegroundColor Cyan
        Write-Host "----------------------------------------------------"
        Pause
    }
    catch {
        Write-Host ""
        Write-Host "❌ ERROR during uninstallation: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "----------------------------------------------------"
        Write-Host "If you hit permission issues, try running PowerShell as Administrator."
        Write-Host "----------------------------------------------------"
        Pause
        exit 1
    }
}

Run-Uninstaller
