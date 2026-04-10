<#
    Algoramming Local TCP - Professional Windows Installer
    Registers the hardware bridge with Chrome securely.
#>

$ErrorActionPreference = "Stop"
$HOST_NAME = "com.algoramming.localtcp"
$INSTALL_DIR = "$env:APPDATA\Algoramming\LocalTCP"
$MANIFEST_NAME = "$HOST_NAME.json"

# 1. Detect Node Path
Write-Host "🔍 Detecting Node.js environment..." -ForegroundColor Cyan
$NODE_PATH = (Get-Command node -ErrorAction SilentlyContinue).Source

if (!$NODE_PATH) {
    Write-Host "❌ Error: Node.js was not found in your system path." -ForegroundColor Red
    Write-Host "Please install Node.js and try again."
    Pause
    exit 1
}

Write-Host "📍 Found Node at: $NODE_PATH" -ForegroundColor Green

# 2. Create installation directory
if (!(Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Force -Path $INSTALL_DIR
}

# 3. Copy files
Write-Host "📂 Installing files to: $INSTALL_DIR" -ForegroundColor Gray
Copy-Item "$PSScriptRoot\index.js" -Destination "$INSTALL_DIR\index.js" -Force
Copy-Item "$PSScriptRoot\$MANIFEST_NAME" -Destination "$INSTALL_DIR\$MANIFEST_NAME" -Force

# 4. Create robust .bat launcher (The most stable method for Windows Chrome)
Write-Host "🔧 Creating execution launcher..." -ForegroundColor Gray
$BAT_PATH = "$INSTALL_DIR\run_bridge.bat"
$BAT_CONTENT = "@echo off`r`n`"$NODE_PATH`" `"%~dp0index.js`" %*"
$BAT_CONTENT | Out-File -FilePath $BAT_PATH -Encoding ascii

# 5. Register with Chrome
$REG_PATH = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HOST_NAME"
if (!(Test-Path $REG_PATH)) {
    New-Item -Path $REG_PATH -Force
}

# Update the manifest to point to the .bat launcher
$MANIFEST_CONTENT = Get-Content "$INSTALL_DIR\$MANIFEST_NAME" -Raw
$ESCAPED_BAT_PATH = $BAT_PATH.Replace("\", "\\")
$MANIFEST_CONTENT = $MANIFEST_CONTENT -replace "HOST_PATH", $ESCAPED_BAT_PATH
$MANIFEST_CONTENT | Out-File -FilePath "$INSTALL_DIR\$MANIFEST_NAME" -Encoding ascii

# Set Registry Key
Set-ItemProperty -Path $REG_PATH -Name "(default)" -Value "$INSTALL_DIR\$MANIFEST_NAME"

Write-Host "✅ Bridge installed successfully!" -ForegroundColor Green
Write-Host "----------------------------------------------------"
Pause
