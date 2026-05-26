; Скрипт установщика для Woozzee WB - Приложение для комплексного управления кабинетом WB
; Версия для автообновления (тихий режим)

#define MyAppName "Woozzee WB"
#define MyAppVersion "3.0.1"
#define MyAppPublisher "СМАРТ СОЛЮШНС"
#define MyAppURL "https://sosna.tech/"
#define MyAppExeName "woozzee.exe"

[Setup]
AppId={{BFA2BA85-6D0E-460F-8461-D565141F5942}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Папка установки по умолчанию
DefaultDirName={autopf}\{#MyAppName}

; Папка в меню Пуск
DefaultGroupName={#MyAppName}

; Папка для сохранения установщика
OutputDir=C:\dev\dart\woozzee\build\windows\x64\setup_app
OutputBaseFilename=Woozzee_WB_Setup_3.0.1

; Иконка установщика
SetupIconFile=C:\dev\dart\woozzee\assets\icons\main_icon.ico

; Настройки сжатия
Compression=lzma
SolidCompression=yes
WizardStyle=modern

; Права доступа (обычный пользователь)
PrivilegesRequired=lowest

; Настройки для тихого режима
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
CreateAppDir=yes
UsePreviousAppDir=yes
AppendDefaultDirName=no
AppendDefaultGroupName=no
CloseApplications=no
RestartApplications=no

; Отключение всех диалогов (полностью тихий режим)
DisableReadyMemo=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Задача создания ярлыка на рабочем столе (всегда создаем при автообновлении)
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
; Основные файлы приложения - ИСПРАВЛЕННЫЕ ПУТИ
Source: "C:\dev\dart\woozzee\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\dev\dart\woozzee\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Ярлык в меню Пуск
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
; Ярлык на рабочем столе (создается если пользователь выбрал эту опцию)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Запустить приложение после установки (даже в тихом режиме)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall

[Code]
// Функция для автоматического пропуска всех страниц в тихом режиме
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // Если установка запущена в тихом режиме, пропускаем все страницы
  if WizardSilent() then
    Result := True
  else
    Result := False;
end;

// Функция выполняется на этапе подготовки к установке
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  // На этапе подготовки к установке (перед копированием файлов)
  if CurStep = ssInstall then
  begin
    // Пытаемся закрыть запущенное приложение, если оно уже установлено
    try
      if FileExists(ExpandConstant('{app}\{#MyAppExeName}')) then
      begin
        Exec('taskkill.exe', '/f /im {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      end;
    except
      // Игнорируем ошибки при попытке закрыть приложение
    end;
  end;
end;

// Основная функция инициализации
function InitializeSetup(): Boolean;
begin
  Result := True;
end;