; Readdict Windows 安装包脚本（Inno Setup 6）
; 构建命令：ISCC /DMyAppVersion=<version> setup.iss
; 分发布局：仓库根 pkg/ 内 bin/ + share/readdict/fonts（与 main.cpp 字体契约一致）

#ifndef MyAppVersion
#define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{8D5A0F41-6C2E-4B7A-9E3F-1A2D5C7B9E10}
AppName=Readdict
AppVersion={#MyAppVersion}
AppPublisher=Readdict
DefaultDirName={autopf}\Readdict
DefaultGroupName=Readdict
DisableProgramGroupPage=yes
OutputDir=installer
OutputBaseFilename=Readdict-{#MyAppVersion}-windows-x64-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog commandline
; 启动时显示语言选择页：中文 / 英文可切换
ShowLanguageDialog=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\pkg\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Readdict"; Filename: "{app}\bin\Readdict.exe"
Name: "{autodesktop}\Readdict"; Filename: "{app}\bin\Readdict.exe"; Tasks: desktopicon

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Run]
Filename: "{app}\bin\Readdict.exe"; Description: "{cm:LaunchProgram,Readdict}"; Flags: nowait postinstall skipifsilent
