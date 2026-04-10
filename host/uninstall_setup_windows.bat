@echo off
:: Algonize Local TCP - Windows Uninstaller
:: Double-click this file to remove the bridge from your system

set HOST_NAME=com.algonize.localtcp
set TARGET_MANIFEST=%TEMP%\%HOST_NAME%.json

echo ----------------------------------------------------
echo 🗑️ Algonize Local TCP Bridge - Uninstaller
echo ----------------------------------------------------

:: Delete Registry Key
REG DELETE "HKCU\Software\Google\Chrome\NativeMessagingHosts\%HOST_NAME%" /f

:: Delete Temporary Manifest
if exist "%TARGET_MANIFEST%" (
    del "%TARGET_MANIFEST%"
)

echo.
echo ✅ Bridge registration removed from Windows.
echo.
pause
