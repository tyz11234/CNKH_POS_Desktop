; Compile with installer/build-installer.ps1 after flutter build windows --release.
; Keep AppId and the application data paths stable across upgrades.
#ifndef AppVersion
  #error AppVersion must be supplied by the release script
#endif
#ifndef AppBuild
  #error AppBuild must be supplied by the release script
#endif
#ifndef BundleDir
  #error BundleDir must point to the complete Flutter Windows release bundle
#endif
#ifndef InstallerOutputDir
  #define InstallerOutputDir "..\dist"
#endif

[Setup]
AppId={{E9F48268-7B21-4A7D-A9E0-2DE768705BE7}
AppName=CNKH POS Desktop
AppVersion={#AppVersion}+{#AppBuild}
AppPublisher=CNKH
AppPublisherURL=https://github.com/tyz11234/CNKH_POS_Desktop
VersionInfoVersion={#AppVersion}.{#AppBuild}
DefaultDirName={localappdata}\Programs\CNKH POS Desktop
DefaultGroupName=CNKH POS Desktop
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#InstallerOutputDir}
OutputBaseFilename=CNKH_POS_Desktop-windows-x64-v{#AppVersion}-{#AppBuild}-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\cnkh_pos_desktop.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
RestartIfNeededByRun=no
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
chinesesimplified.DesktopShortcut=创建桌面快捷方式
english.DesktopShortcut=Create a desktop shortcut
chinesesimplified.StartApp=启动 CNKH POS Desktop
english.StartApp=Launch CNKH POS Desktop

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; Flags: unchecked

[Files]
; Install application files only. Never delete, move, or seed the database in
; Documents, receipts, backups, pictures, or any other existing business data.
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\CNKH POS Desktop"; Filename: "{app}\cnkh_pos_desktop.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\CNKH POS Desktop"; Filename: "{app}\cnkh_pos_desktop.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\cnkh_pos_desktop.exe"; Description: "{cm:StartApp}"; Flags: nowait postinstall skipifsilent unchecked
