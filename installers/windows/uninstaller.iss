; Local TCP Bridge — Windows UNINSTALLER (Inno Setup)
; ------------------------------------------------------------
; Produces a downloadable .exe that REMOVES Local TCP Bridge, mirroring the
; one-click feel of the installer. It carries no payload — when run it simply
; reverses everything installer.iss set up (per-user, NO admin rights):
;   - Deletes %LOCALAPPDATA%\Algoramming\LocalTCP (binary + manifest)
;   - Removes the Chrome AND Edge Native Messaging registry keys (HKCU)
;   - Removes the Start Menu folder
;   - Removes the installer's Add/Remove Programs entry
;
; Build (on Windows, Inno Setup 6):  iscc uninstaller.iss
; Output: Output/localtcp-windows-uninstaller.exe

#define MyAppName "Local TCP Bridge"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Algoramming Systems Ltd."
#define MyAppURL "https://algoramming.com"
#define HostName "com.algoramming.localtcp"
; Must match installer.iss AppId so we can clean its Add/Remove Programs entry.
#define InstallerAppId "{B7F3A2E1-4C8D-4E5F-9A1B-0C1D2E3F4A5B}"

[Setup]
AppId={{C8A4B3F2-5D9E-4F60-AB2C-1D2E3F4A5B6C}
AppName={#MyAppName} Uninstaller
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
; No files are installed; use a temp dir and never leave anything behind.
DefaultDirName={localappdata}\Algoramming\LocalTCP-Uninstall
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=localtcp-windows-uninstaller
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; This is a remover, not an app — don't register it in Add/Remove Programs.
Uninstallable=no
CreateAppDir=no

[Code]
procedure RemoveBridge();
var
  AppDir: string;
begin
  AppDir := ExpandConstant('{localappdata}\Algoramming\LocalTCP');

  // 1. Native Messaging registry keys (Chrome + Edge, HKCU)
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Google\Chrome\NativeMessagingHosts\{#HostName}');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Microsoft\Edge\NativeMessagingHosts\{#HostName}');

  // 2. Installed files (binary + generated manifest) and the dir itself
  DelTree(AppDir, True, True, True);

  // 3. Start Menu folder created by the installer
  DelTree(ExpandConstant('{userprograms}\Local TCP Bridge'), True, True, True);

  // 4. The installer's own Add/Remove Programs entry (Inno _is1 key)
  RegDeleteKeyIncludingSubkeys(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#InstallerAppId}_is1');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
    RemoveBridge();
end;

[Messages]
SetupAppTitle=Local TCP Bridge Uninstaller
WelcomeLabel1=Remove Local TCP Bridge
WelcomeLabel2=This will remove the Local TCP Bridge from your computer.%n%nClick Next to continue.
FinishedHeadingLabel=Local TCP Bridge was removed
FinishedLabel=Local TCP Bridge has been removed.%n%nYou can also remove the extension from chrome://extensions.
