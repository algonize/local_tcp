<#
    Algoramming Local TCP - Professional Windows Installer
    Registers the hardware bridge with Chrome securely.
#>

$ErrorActionPreference = "Stop"
$HOST_NAME = "com.algoramming.localtcp"
$INSTALL_DIR = "$env:APPDATA\Algoramming\LocalTCP"
$MANIFEST_NAME = "$HOST_NAME.json"

function Ensure-NodeInstalled {
    Write-Host "🔍 Detecting Node.js environment..." -ForegroundColor Gray
    $NODE_PATH = (Get-Command node -ErrorAction SilentlyContinue).Source

    if (!$NODE_PATH) {
        Write-Host "⚠️ Node.js not found. Attempting automatic installation..." -ForegroundColor Yellow
        
        # Check if winget is available
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "📦 Found Winget. Installing Node.js LTS..." -ForegroundColor Cyan
            winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
            
            if ($LASTEXITCODE -ne 0) {
                throw "Winget failed to install Node.js. Please install it manually from https://nodejs.org/"
            }

            # Refresh Environment Path for the current session
            Write-Host "🔄 Refreshing system path..." -ForegroundColor Gray
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            $NODE_PATH = (Get-Command node -ErrorAction SilentlyContinue).Source
            if (!$NODE_PATH) {
                throw "Node.js installation completed but 'node' is still not found in path. Please restart your computer."
            }
        } else {
            throw "Node.js is missing and 'winget' was not found. Please install Node.js manually: https://nodejs.org/"
        }
    }
    return $NODE_PATH
}

function Run-Installer {
    try {
        Write-Host "----------------------------------------------------" -ForegroundColor Cyan
        Write-Host "🚀 Local TCP Bridge - Smart Installer (Windows)" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------" -ForegroundColor Cyan

        # 1. Ensure Node is present
        $NODE_PATH = Ensure-NodeInstalled
        Write-Host "📍 Using Node at: $NODE_PATH" -ForegroundColor Green

        # 2. Create installation directory
        if (!(Test-Path $INSTALL_DIR)) {
            Write-Host "📁 Creating directory: $INSTALL_DIR" -ForegroundColor Gray
            New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
        }

        # 3. Copy files
        Write-Host "📂 Installing files..." -ForegroundColor Gray
        Copy-Item "$PSScriptRoot\index.js" -Destination "$INSTALL_DIR\index.js" -Force
        Copy-Item "$PSScriptRoot\$MANIFEST_NAME" -Destination "$INSTALL_DIR\$MANIFEST_NAME" -Force

        # 4. Create robust .bat launcher
        Write-Host "🔧 Creating execution launcher..." -ForegroundColor Gray
        $BAT_PATH = "$INSTALL_DIR\run_bridge.bat"
        $BAT_CONTENT = "@echo off`r`n`"$NODE_PATH`" `"%~dp0index.js`" %*"
        $BAT_CONTENT | Out-File -FilePath $BAT_PATH -Encoding UTF8

        # 5. Register with Chrome
        Write-Host "🔗 Registering with Chrome..." -ForegroundColor Gray
        $REG_PATH = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HOST_NAME"
        if (!(Test-Path $REG_PATH)) {
            New-Item -Path $REG_PATH -Force | Out-Null
        }

        # Update the manifest
        $MANIFEST_CONTENT = Get-Content "$INSTALL_DIR\$MANIFEST_NAME" -Raw
        $ESCAPED_BAT_PATH = $BAT_PATH.Replace("\", "\\")
        $MANIFEST_CONTENT = $MANIFEST_CONTENT -replace "HOST_PATH", $ESCAPED_BAT_PATH
        $MANIFEST_CONTENT | Out-File -FilePath "$INSTALL_DIR\$MANIFEST_NAME" -Encoding UTF8

        # Set Registry Key
        Set-ItemProperty -Path $REG_PATH -Name "(default)" -Value "$INSTALL_DIR\$MANIFEST_NAME"

        Write-Host ""
        Write-Host "✅ Bridge installed successfully!" -ForegroundColor Green
        Write-Host "----------------------------------------------------"
        Write-Host "IMPORTANT: Please restart Chrome to apply changes."
        Write-Host "----------------------------------------------------"
        Pause
    }
    catch {
        Write-Host ""
        Write-Host "❌ ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "----------------------------------------------------"
        Write-Host "If issues persist, visit: https://nodejs.org/ to install Node manually."
        Write-Host "----------------------------------------------------"
        Pause
        exit 1
    }
}

Run-Installer
