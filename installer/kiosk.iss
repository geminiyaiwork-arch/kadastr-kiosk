; Inno Setup script — single-file installer for the Kadastr Kiosk (Windows)
[Setup]
AppName=Kadastr Kiosk
AppVersion=1.0.0
AppPublisher=Andijon viloyati kadastr palatasi
DefaultDirName={autopf}\KadastrKiosk
DefaultGroupName=Kadastr Kiosk
DisableProgramGroupPage=yes
OutputDir=installer_out
OutputBaseFilename=kadastr-kiosk-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Ish stoli yorlig‘i"; GroupDescription: "Qo‘shimcha:"
Name: "autostart"; Description: "Windows bilan avtomatik ishga tushsin (kiosk)"; GroupDescription: "Qo‘shimcha:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Kadastr Kiosk"; Filename: "{app}\kadastr_kiosk.exe"
Name: "{commondesktop}\Kadastr Kiosk"; Filename: "{app}\kadastr_kiosk.exe"; Tasks: desktopicon

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "KadastrKiosk"; ValueData: """{app}\kadastr_kiosk.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\kadastr_kiosk.exe"; Description: "Hozir ishga tushirish"; Flags: nowait postinstall skipifsilent
