; Local TCP Bridge — Windows One-Click Installer (Inno Setup)
; ------------------------------------------------------------
; Build (on Windows, with Inno Setup 6 installed):
;   1. Run host-go/build.sh (or `go build`) to produce
;      dist/localtcp-windows-amd64.exe
;   2. Compile this script:  iscc installer.iss
;   3. Output: Output/LocalTCP-Setup-Windows.exe
;   4. (Recommended) Code-sign the exe to avoid SmartScreen warnings:
;      signtool sign /fd SHA256 /a Output/LocalTCP-Setup-Windows.exe
;
; What it does (NO admin rights required — installs per-user):
;   - Copies localtcp.exe to %LOCALAPPDATA%\Algoramming\LocalTCP
;   - Writes the Native Messaging manifest with the correct absolute path
;   - Registers the host for Chrome AND Edge (HKCU)
;   - Uninstaller cleanly reverses everything

#define MyAppName "Local TCP Bridge"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Algoramming Systems Ltd."
#define MyAppURL "https://algoramming.com"
#define HostName "com.algoramming.localtcp"
#define ExtensionId "ngbakchodnmhndnghhejmocfadjfekkf"

[Setup]
AppId={{B7F3A2E1-4C8D-4E5F-9A1B-0C1D2E3F4A5B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={localappdata}\Algoramming\LocalTCP
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=LocalTCP-Setup-Windows
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#MyAppName}

[Files]
Source: "..\..\host-go\dist\localtcp-windows-amd64.exe"; DestDir: "{app}"; DestName: "localtcp.exe"; Flags: ignoreversion

[Icons]
; Double-click uninstall straight from the Start Menu
Name: "{userprograms}\Local TCP Bridge\Uninstall Local TCP Bridge"; Filename: "{uninstallexe}"

[Registry]
; Chrome
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\{#HostName}"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\{#HostName}.json"; Flags: uninsdeletekey
; Microsoft Edge (Chromium)
Root: HKCU; Subkey: "Software\Microsoft\Edge\NativeMessagingHosts\{#HostName}"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\{#HostName}.json"; Flags: uninsdeletekey

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ManifestPath, ExePath, Json: string;
begin
  if CurStep = ssPostInstall then
  begin
    ManifestPath := ExpandConstant('{app}\{#HostName}.json');
    // JSON requires escaped backslashes in the path
    ExePath := ExpandConstant('{app}\localtcp.exe');
    StringChangeEx(ExePath, '\', '\\', True);

    Json :=
      '{' + #13#10 +
      '  "name": "{#HostName}",' + #13#10 +
      '  "description": "Your browser can finally talk with local TCP.",' + #13#10 +
      '  "path": "' + ExePath + '",' + #13#10 +
      '  "type": "stdio",' + #13#10 +
      '  "allowed_origins": [' + #13#10 +
      '    "chrome-extension://{#ExtensionId}/"' + #13#10 +
      '  ]' + #13#10 +
      '}';

    SaveStringToFile(ManifestPath, Json, False);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    DeleteFile(ExpandConstant('{app}\{#HostName}.json'));
end;

[Messages]
SetupAppTitle=Local TCP Bridge Setup
FinishedLabel=Local TCP Bridge has been installed.%n%nPlease RESTART Chrome completely (close all windows) to activate the bridge.
