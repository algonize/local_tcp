@echo off
:: Algonize Local TCP - Windows Setup
:: Double-click this file (Run as Administrator) to register the bridge

set HOST_NAME=com.algonize.localtcp
set MANIFEST_NAME=com.algonize.localtcp.json
set DIR=%~dp0
set TARGET_MANIFEST=%TEMP%\%HOST_NAME%.json
set SOURCE_MANIFEST=%DIR%%MANIFEST_NAME%

echo ----------------------------------------------------
echo 🚀 Algonize Local TCP Bridge - Setup (Windows)
echo ----------------------------------------------------

:: 1. Create a version of the manifest with the absolute path
:: We use PowerShell to do the search and replace
powershell -Command "(gc '%SOURCE_MANIFEST%') -replace 'HOST_PATH', '%DIR%index.js'.Replace('\', '\\') | Out-File -encoding ASCII '%TARGET_MANIFEST%'"

:: Add Registry Key
:: HKEY_CURRENT_USER allows installation without admin, but Chrome expects it here
REG ADD "HKCU\Software\Google\Chrome\NativeMessagingHosts\%HOST_NAME%" /ve /t REG_SZ /d "%TARGET_MANIFEST%" /f

if %errorlevel% equ 0 (
    echo ✅ Bridge registered successfully in Windows Registry.
    echo 📍 Target: %TARGET_MANIFEST%
) else (
    echo ❌ Failed to register. Please try running as Administrator.
)

echo.
echo ⚠️  IMPORTANT: Please ensure your Extension ID is whitelisted
echo    in the %MANIFEST_NAME% file.
echo.
pause
