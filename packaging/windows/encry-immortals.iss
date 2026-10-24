; Inno Setup script for the Windows build.
; Build from packaging/windows with ISCC.exe /DMyAppVersion=0.2.1
#ifndef MyAppVersion
  #define MyAppVersion "0.2.0"
#endif
; VersionInfo* 只接受纯数字版本号，预发布标签（如 0.4.2-rc1）要由构建脚本另外传进来。
#ifndef MyAppVersionNumeric
  #define MyAppVersionNumeric MyAppVersion
#endif

#define MyAppName "Encry Immortals"
#define MyAppPublisher "Encry Immortals"
#define MyAppURL "https://github.com/tangthinker/encry-immortals-ui"
#define MyAppExeName "encry_immortals_ui.exe"
#define MyAppId "{{7E1C4E0E-2D3A-4A0D-9A2E-1B5D3F6C8A11}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={localappdata}\Programs\Encry Immortals
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir=..\..\build\installer
OutputBaseFilename=Encry-Immortals-{#MyAppVersion}-Windows-x64
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
SetupLogging=yes
VersionInfoVersion={#MyAppVersionNumeric}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersionNumeric}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
