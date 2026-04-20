[Setup]
AppId={{DA3F45DE-00B2-4EFC-81B0-BA101DCA73E8}
AppName=SkyStream
AppVersion={#AppVersion}
AppPublisher=SkyStream
AppPublisherURL=https://github.com/skystream
AppSupportURL=https://github.com/skystream
AppUpdatesURL=https://github.com/skystream
DefaultDirName={autopf}\SkyStream
DefaultGroupName=SkyStream
DisableProgramGroupPage=yes
OutputBaseFilename=SkyStream-Windows-{#OutputArch}-Setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
ArchitecturesAllowed={#AppArch}
ArchitecturesInstallIn64BitMode={#AppArch}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#AppDir}\skystream.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "skystream.exe,libmpv-2.dll,data\flutter_assets\packages\flutter_torrent_server\assets\torrserver\*"
; Keep libmpv separate so installer compression/decompression behavior is explicit.
Source: "{#AppDir}\libmpv-2.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#AppDir}\data\flutter_assets\packages\flutter_torrent_server\assets\torrserver\{#TorrServerBinary}"; DestDir: "{app}\data\flutter_assets\packages\flutter_torrent_server\assets\torrserver"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\SkyStream"; Filename: "{app}\skystream.exe"
Name: "{autodesktop}\SkyStream"; Filename: "{app}\skystream.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\skystream.exe"; Description: "{cm:LaunchProgram,SkyStream}"; Flags: nowait postinstall skipifsilent
