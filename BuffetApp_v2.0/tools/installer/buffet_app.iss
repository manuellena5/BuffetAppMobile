; Buffet_App - Inno Setup Script
; Requiere: Inno Setup 6 (Windows)
; Uso:
;  1) flutter build windows --release
;  2) Compilar este .iss con ISCC.exe o abrirlo en Inno Setup GUI

#define MyAppName "Buffet_App"
#define MyAppPublisher "Buffet_App"
#define MyAppURL ""
#define MyAppExeName "Buffet_App.exe"
#define MyAppVersion "1.2.1"

[Setup]
AppId={{B6B2F80C-1A3A-4E55-9A1E-9DDB0B41E0E1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename={#MyAppName}_Setup_{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; Nota: La DB NO se instala junto a la app.
; Por diseño, la app crea/usa la DB en %LOCALAPPDATA%\Buffet_App\barcancha.db.

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear ícono en el Escritorio"; GroupDescription: "Accesos directos"; Flags: unchecked

[Files]
; Flutter Windows release output
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Ejecutar {#MyAppName}"; Flags: nowait postinstall skipifsilent
