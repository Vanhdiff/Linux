#define AppId "{{9F0A8F77-5C76-4B4D-BD4A-81C2E12E9A10}"
#define AppName "Trading Desk"
#define AppVersion "1.0.0"
#define AppPublisher "Trading Desk"
#define AppExeName "trading_desk.exe"
#define BuildRoot "build\\windows\\x64\\runner\\Release"
#define BackendRoot "backend"
#define PythonSourceRoot "installer\\python-runtime"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
OutputDir=installer
OutputBaseFilename=trading-desk-setup-1.0.0
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BuildRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BackendRoot}\run.py"; DestDir: "{app}\backend"; Flags: ignoreversion
Source: "{#BackendRoot}\app\*"; DestDir: "{app}\backend\app"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "__pycache__\*,*.pyc"
Source: "{#BackendRoot}\.deps\*"; DestDir: "{app}\backend\.deps"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "__pycache__\*,*.pyc"
Source: "{#BackendRoot}\data\.gitkeep"; DestDir: "{app}\backend\data"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\python.exe"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\pythonw.exe"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\python3.dll"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\python311.dll"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\vcruntime140.dll"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\vcruntime140_1.dll"; DestDir: "{app}\python"; Flags: ignoreversion
Source: "{#PythonSourceRoot}\DLLs\*"; DestDir: "{app}\python\DLLs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PythonSourceRoot}\Lib\*"; DestDir: "{app}\python\Lib"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "__pycache__\*,*.pyc,test\*,tests\*,idlelib\*,turtledemo\*,tkinter\test\*,unittest\test\*,ensurepip\*,site-packages\pip\*,site-packages\pip-23.2.1.dist-info\*,site-packages\setuptools\*,site-packages\setuptools-65.5.0.dist-info\*,site-packages\pkg_resources\*,site-packages\_distutils_hack\*"
Source: "installer\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: waituntilterminated runhidden
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
