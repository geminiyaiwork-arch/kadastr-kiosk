; Inno Setup script — single-file installer for the Kadastr Kiosk (Windows)
; Versiya CI'dan /DMyAppVersion=... orqali beriladi (pubspec'ga mos). Yo'q bo'lsa — default.
#ifndef MyAppVersion
  #define MyAppVersion "1.8.28"
#endif
[Setup]
AppName=Kadastr Kiosk
AppVersion={#MyAppVersion}
AppPublisher=Andijon viloyati kadastr palatasi
DefaultDirName={localappdata}\KadastrKiosk
DefaultGroupName=Kadastr Kiosk
DisableProgramGroupPage=yes
OutputDir=..\installer_out
OutputBaseFilename=kadastr-kiosk-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
WizardStyle=modern
; Avto-yangilanish: ishlab turgan kioskни yopadi, yangilaydi (SOKIN rejim)
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Ish stoli yorlig‘i"; GroupDescription: "Qo‘shimcha:"
Name: "autostart"; Description: "Windows bilan avtomatik ishga tushsin (kiosk)"; GroupDescription: "Qo‘shimcha:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Kadastr Kiosk"; Filename: "{app}\kadastr_kiosk.exe"
Name: "{userdesktop}\Kadastr Kiosk"; Filename: "{app}\kadastr_kiosk.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "KadastrKiosk"; ValueData: """{app}\kadastr_kiosk.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\kadastr_kiosk.exe"; Description: "Hozir ishga tushirish"; Flags: nowait postinstall
