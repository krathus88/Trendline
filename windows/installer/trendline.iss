; Windows installer for Trendline (Inno Setup 6).
;
; Build it with tool/build_windows_installer.ps1, which builds the release
; app first and passes the version from pubspec.yaml. By hand:
;   ISCC.exe /DAppVersion=0.1.0 windows\installer\trendline.iss
;
; Installs for the current user only (no admin rights), into
; %LOCALAPPDATA%\Programs\Trendline, with a Start menu shortcut and an
; uninstaller in Settings > Apps.

#ifndef AppVersion
  #error Pass the version: /DAppVersion=x.y.z
#endif

#define AppName "Trendline"
#define AppExe "trendline.exe"
#define UrlScheme "com.krathus.trendline"
#define SettingsKey "Software\com.krathus\Trendline"
; Where the app's encrypted local data lives (sign-in and the on-device
; copies of Today, foods, recipes, weigh-ins and barcode lookups):
; %APPDATA%\<CompanyName>\<ProductName> from windows\runner\Runner.rc.
#define DataCompany "com.krathus"
#define DataProduct "trendline"
; flutter_secure_storage_windows keeps everything in this one file.
#define DataFile "flutter_secure_storage.dat"

[Setup]
; Never change AppId: upgrades and the uninstaller find the app by it.
AppId={{0EBE9AFB-991C-4E91-ACD7-75B9B73680F7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Krathus88
AppPublisherURL=https://github.com/krathus88/Trendline
AppSupportURL=https://github.com/krathus88/Trendline
VersionInfoVersion={#AppVersion}
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; The app must be closed to be updated or removed.
CloseApplications=yes
RestartApplications=no
OutputDir=..\..\build\windows\installer
OutputBaseFilename=Trendline-Setup-{#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole release folder: the exe needs the DLLs and data next to it.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; The sign-in link, as the app registers it on every start
; (windows\runner\url_scheme.cpp), so Discord sign-in works on the first
; run too. Removed on uninstall.
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}"; ValueType: string; ValueName: ""; ValueData: "URL:Trendline sign-in"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKCU; Subkey: "Software\Classes\{#UrlScheme}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
; The window's last size and place (windows\runner\window_placement.h),
; written by the app; only removed here.
Root: HKCU; Subkey: "{#SettingsKey}"; Flags: uninsdeletekey dontcreatekey
Root: HKCU; Subkey: "Software\{#DataCompany}"; Flags: uninsdeletekeyifempty dontcreatekey

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Health data must not outlive the app: removing it also deletes the
; sign-in and every on-device copy (all encrypted, all in this one file),
; as signing out does. Only that file by name, then the folders only if
; they're left empty, so nothing else is ever deleted. Data in the account
; itself stays until the account is deleted.
Type: files; Name: "{userappdata}\{#DataCompany}\{#DataProduct}\{#DataFile}"
Type: dirifempty; Name: "{userappdata}\{#DataCompany}\{#DataProduct}"
Type: dirifempty; Name: "{userappdata}\{#DataCompany}"
