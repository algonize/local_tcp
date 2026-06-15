<#
    Local TCP Bridge — Windows Uninstaller

    NOTE: The standard way to uninstall is:
        Settings → Apps → "Local TCP Bridge" → Uninstall
    (The one-click installer registers a proper uninstaller automatically.)

    This script is a fallback for manual cleanup only.
    Run: Right-click → "Run with PowerShell"
#>

$ErrorActionPreference = "SilentlyContinue"
$HOST_NAME = "com.algoramming.localtcp"

Write-Host "Uninstalling Local TCP Bridge..." -ForegroundColor Cyan

# Registry (Chrome + Edge)
$regPaths = @(
    "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HOST_NAME",
    "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$HOST_NAME"
)
foreach ($p in $regPaths) {
    if (Test-Path $p) {
        Remove-Item -Path $p -Recurse -Force
        Write-Host "  [OK] Unregistered: $p" -ForegroundColor Green
    }
}

# Install directory
$dir = "$env:LOCALAPPDATA\Algoramming\LocalTCP"
if (Test-Path $dir) {
    Remove-Item -Path $dir -Recurse -Force
    Write-Host "  [OK] Removed: $dir" -ForegroundColor Green
}

# Remove empty parent folder
$parent = "$env:LOCALAPPDATA\Algoramming"
if ((Test-Path $parent) -and -not (Get-ChildItem $parent)) {
    Remove-Item -Path $parent -Force
}

Write-Host ""
Write-Host "[SUCCESS] Local TCP Bridge removed." -ForegroundColor Green
Write-Host "Restart Chrome. You can also remove the extension from chrome://extensions."
Pause
