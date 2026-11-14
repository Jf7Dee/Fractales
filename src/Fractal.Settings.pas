unit Fractal.Settings;

// Réglages du programme conservés d'une séance à l'autre (Fractales.ini) et lieu de la dernière séance
// (Session.frac), tous deux à côté de l'exécutable. Fichier absent ou illisible : valeurs de départ, sans message.

interface

uses
  SysUtils, Classes, IniFiles, Fractal.Persistence, Fractal.Update;

const
  kSettingsFileName = 'Fractales.ini';
  kSessionFileName = 'Session.frac';
  kHiResPresetCount = 5;       // Vue actuelle, Full HD, 4K, 8K, Personnalisée
  kDefaultHiResPreset = 2;     // 4K
  kDefaultHiResWidth = 3840;
  kDefaultHiResHeight = 2160;
  kMinSupersample = 1;
  kMaxSupersample = 3;
  kDefaultSupersample = 2;

type
  TAppSettings = record
    IsRustEngine: Boolean;
    NavModeIndex: Integer;     // rang dans kNavigationModes
    LocationFolder: string;    // derniers dossiers des enregistrements volontaires ; vide = choix de Windows
    ImageFolder: string;
    HiResFolder: string;
    VideoScenarioFolder: string;  // fenêtre Vidéo : scénarios et vidéos vont chacun dans leur dossier
    VideoFolder: string;
    HiResPreset: Integer;
    HiResWidth: Integer;       // taille personnalisée
    HiResHeight: Integer;
    HiResSupersample: Integer;
    Update: TUpdateConfig;     // section [MiseAJour]
    VideoFfmpegPath: string;   // section [Video] ; vide = ffmpeg.exe à côté de l'exe
  end;

  // Aperçu ou génération vidéo lancé et pas encore terminé (section [RendusInterrompus]) : proposé au démarrage
  TInterruptedRender = record
    OutputFile: string;    // vidéo ou aperçu encodé ; ses morceaux sont à côté
    IsPreview: Boolean;
    Divisor: Integer;      // taille de l'aperçu, comme TVideoRenderer ; 0 = automatique
    ScenarioFile: string;  // '' = scénario jamais enregistré
  end;

  TInterruptedRenders = array of TInterruptedRender;

function DefaultAppSettings: TAppSettings;
function LoadAppSettings(const FileName: string; NavModeCount: Integer): TAppSettings;
function SaveAppSettings(const FileName: string; const S: TAppSettings): Boolean;
function TryLoadSession(const FileName: string; Location: TFractalLocation): Boolean;
function TrySaveSession(const FileName: string; Location: TFractalLocation): Boolean;
function SettingsFilePath: string;
function SessionFilePath: string;
// Lus et écrits directement dans le fichier, pour survivre à un arrêt brutal ; SaveAppSettings les garde
function LoadInterruptedRenders(const FileName: string): TInterruptedRenders;
procedure AddInterruptedRender(const FileName: string; const R: TInterruptedRender);  // remplace la même sortie
procedure RemoveInterruptedRender(const FileName, OutputFile: string);

implementation

const
  kSectionEngine = 'Engine';
  kSectionNavigation = 'Navigation';
  kSectionFolders = 'Folders';
  kSectionHiRes = 'HiRes';
  kSectionVideo = 'Video';
  kSectionInterrupted = 'RendusInterrompus';
  kKeyInterrupted = 'Rendu';
  kInterruptedSeparator = '|';  // interdit dans un chemin Windows
  kKeyFfmpegPath = 'FfmpegPath';
  kKeyKernel = 'Kernel';
  kKeyMode = 'Mode';
  kKeyLocations = 'Locations';
  kKeyImages = 'Images';
  kKeyHiRes = 'HiRes';
  kKeyVideoScenarios = 'VideoScenarios';
  kKeyVideos = 'Videos';
  kKeyPreset = 'Preset';
  kKeyWidth = 'Width';
  kKeyHeight = 'Height';
  kKeySupersample = 'Supersample';
  kKernelRust = 'Rust';
  kKernelDelphi = 'Delphi';
  kMinHiResSize = 16;          // mêmes bornes que la fenêtre de rendu HD
  kMaxHiResSize = 32768;

{------------------------------------------------------------------------------}

function DefaultAppSettings: TAppSettings;
begin
  Result.IsRustEngine := False;
  Result.NavModeIndex := 0;
  Result.LocationFolder := '';
  Result.ImageFolder := '';
  Result.HiResFolder := '';
  Result.VideoScenarioFolder := '';
  Result.VideoFolder := '';
  Result.HiResPreset := kDefaultHiResPreset;
  Result.HiResWidth := kDefaultHiResWidth;
  Result.HiResHeight := kDefaultHiResHeight;
  Result.HiResSupersample := kDefaultSupersample;
  Result.Update := DefaultUpdateConfig;
end;

{------------------------------------------------------------------------------}

function ReadBounded(Ini: TCustomIniFile; const Section, Key: string; Default, Lowest, Highest: Integer): Integer;
begin
  Result := Ini.ReadInteger(Section, Key, Default);
  if (Result < Lowest) or (Result > Highest) then
    Result := Default;
end;

{------------------------------------------------------------------------------}

function LoadAppSettings(const FileName: string; NavModeCount: Integer): TAppSettings;
var
  Ini: TMemIniFile;
  D: TAppSettings;
begin
  D := DefaultAppSettings;
  Result := D;
  if not FileExists(FileName) then
    Exit;
  try
    Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
    try
      Result.IsRustEngine := SameText(Ini.ReadString(kSectionEngine, kKeyKernel, kKernelDelphi), kKernelRust);
      Result.NavModeIndex := ReadBounded(Ini, kSectionNavigation, kKeyMode, D.NavModeIndex, 0, NavModeCount - 1);
      Result.LocationFolder := Ini.ReadString(kSectionFolders, kKeyLocations, '');
      Result.ImageFolder := Ini.ReadString(kSectionFolders, kKeyImages, '');
      Result.HiResFolder := Ini.ReadString(kSectionFolders, kKeyHiRes, '');
      Result.VideoScenarioFolder := Ini.ReadString(kSectionFolders, kKeyVideoScenarios, '');
      Result.VideoFolder := Ini.ReadString(kSectionFolders, kKeyVideos, '');
      Result.VideoFfmpegPath := Ini.ReadString(kSectionVideo, kKeyFfmpegPath, '');
      Result.HiResPreset := ReadBounded(Ini, kSectionHiRes, kKeyPreset, D.HiResPreset, 0, kHiResPresetCount - 1);
      Result.HiResWidth := ReadBounded(Ini, kSectionHiRes, kKeyWidth, D.HiResWidth, kMinHiResSize, kMaxHiResSize);
      Result.HiResHeight := ReadBounded(Ini, kSectionHiRes, kKeyHeight, D.HiResHeight, kMinHiResSize,
        kMaxHiResSize);
      Result.HiResSupersample := ReadBounded(Ini, kSectionHiRes, kKeySupersample, D.HiResSupersample,
        kMinSupersample, kMaxSupersample);
      Result.Update := ReadUpdateConfig(Ini);
    finally
      Ini.Free;
    end;
  except
    Result := D;  // fichier illisible : démarrage habituel
  end;
end;

{------------------------------------------------------------------------------}

// Remplace toute la section
procedure WriteInterruptedRenders(Ini: TCustomIniFile; const Renders: TInterruptedRenders);
var
  I: Integer;
begin
  Ini.EraseSection(kSectionInterrupted);
  for I := 0 to High(Renders) do
    Ini.WriteString(kSectionInterrupted, kKeyInterrupted + IntToStr(I + 1),
      Renders[I].OutputFile + kInterruptedSeparator + IntToStr(Ord(Renders[I].IsPreview)) + kInterruptedSeparator +
      IntToStr(Renders[I].Divisor) + kInterruptedSeparator + Renders[I].ScenarioFile);
end;

{------------------------------------------------------------------------------}

function SaveAppSettings(const FileName: string; const S: TAppSettings): Boolean;
var
  Ini: TMemIniFile;
  Kernel: string;
  Renders: TInterruptedRenders;
begin
  Result := False;
  Renders := LoadInterruptedRenders(FileName);  // écrits en cours de séance, à garder
  try
    Ini := TMemIniFile.Create('', TEncoding.UTF8);
    try
      if S.IsRustEngine then
        Kernel := kKernelRust
      else
        Kernel := kKernelDelphi;
      Ini.WriteString(kSectionEngine, kKeyKernel, Kernel);
      Ini.WriteInteger(kSectionNavigation, kKeyMode, S.NavModeIndex);
      Ini.WriteString(kSectionFolders, kKeyLocations, S.LocationFolder);
      Ini.WriteString(kSectionFolders, kKeyImages, S.ImageFolder);
      Ini.WriteString(kSectionFolders, kKeyHiRes, S.HiResFolder);
      Ini.WriteString(kSectionFolders, kKeyVideoScenarios, S.VideoScenarioFolder);
      Ini.WriteString(kSectionFolders, kKeyVideos, S.VideoFolder);
      Ini.WriteString(kSectionVideo, kKeyFfmpegPath, S.VideoFfmpegPath);
      Ini.WriteInteger(kSectionHiRes, kKeyPreset, S.HiResPreset);
      Ini.WriteInteger(kSectionHiRes, kKeyWidth, S.HiResWidth);
      Ini.WriteInteger(kSectionHiRes, kKeyHeight, S.HiResHeight);
      Ini.WriteInteger(kSectionHiRes, kKeySupersample, S.HiResSupersample);
      WriteUpdateConfig(Ini, S.Update);
      WriteInterruptedRenders(Ini, Renders);
      Ini.Rename(FileName, False);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
    Result := True;
  except
    // dossier en lecture seule : rien n'est conservé, sans message
  end;
end;

{------------------------------------------------------------------------------}

function TryLoadSession(const FileName: string; Location: TFractalLocation): Boolean;
begin
  Result := False;
  if (Location = nil) or not FileExists(FileName) then
    Exit;
  try
    Location.LoadFromFile(FileName);
    Result := True;
  except
    // lieu illisible : démarrage habituel
  end;
end;

{------------------------------------------------------------------------------}

function TrySaveSession(const FileName: string; Location: TFractalLocation): Boolean;
begin
  Result := False;
  if Location = nil then
    Exit;
  try
    Location.SaveToFile(FileName);
    Result := True;
  except
    // dossier en lecture seule : rien n'est conservé, sans message
  end;
end;

{------------------------------------------------------------------------------}

function SettingsFilePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + kSettingsFileName;
end;

{------------------------------------------------------------------------------}

function SessionFilePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + kSessionFileName;
end;

{------------------------------------------------------------------------------}

function LoadInterruptedRenders(const FileName: string): TInterruptedRenders;
var
  Ini: TMemIniFile;
  Keys, Fields: TStringList;
  I, N: Integer;
begin
  SetLength(Result, 0);
  if not FileExists(FileName) then
    Exit;
  Keys := TStringList.Create;
  Fields := TStringList.Create;
  try
    try
      Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
      try
        Ini.ReadSection(kSectionInterrupted, Keys);
        Fields.Delimiter := kInterruptedSeparator;
        Fields.StrictDelimiter := True;
        for I := 0 to Keys.Count - 1 do
        begin
          Fields.DelimitedText := Ini.ReadString(kSectionInterrupted, Keys[I], '');
          if (Fields.Count <> 4) or (Fields[0] = '') then
            Continue;  // ligne abîmée : oubliée
          N := Length(Result);
          SetLength(Result, N + 1);
          Result[N].OutputFile := Fields[0];
          Result[N].IsPreview := Fields[1] = '1';
          Result[N].Divisor := StrToIntDef(Fields[2], 0);
          Result[N].ScenarioFile := Fields[3];
        end;
      finally
        Ini.Free;
      end;
    except
      SetLength(Result, 0);  // fichier illisible : rien à proposer
    end;
  finally
    Fields.Free;
    Keys.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure SaveInterruptedRenders(const FileName: string; const Renders: TInterruptedRenders);
var
  Ini: TMemIniFile;
begin
  try
    Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
    try
      WriteInterruptedRenders(Ini, Renders);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    // dossier en lecture seule : la reprise au démarrage ne sera pas proposée, sans message
  end;
end;

{------------------------------------------------------------------------------}

procedure AddInterruptedRender(const FileName: string; const R: TInterruptedRender);
var
  Renders: TInterruptedRenders;
  N: Integer;
begin
  RemoveInterruptedRender(FileName, R.OutputFile);
  Renders := LoadInterruptedRenders(FileName);
  N := Length(Renders);
  SetLength(Renders, N + 1);
  Renders[N] := R;
  SaveInterruptedRenders(FileName, Renders);
end;

{------------------------------------------------------------------------------}

procedure RemoveInterruptedRender(const FileName, OutputFile: string);
var
  Renders: TInterruptedRenders;
  I, N: Integer;
begin
  Renders := LoadInterruptedRenders(FileName);
  N := 0;
  for I := 0 to High(Renders) do
    if not SameText(Renders[I].OutputFile, OutputFile) then
    begin
      Renders[N] := Renders[I];
      Inc(N);
    end;
  if N < Length(Renders) then
  begin
    SetLength(Renders, N);
    SaveInterruptedRenders(FileName, Renders);
  end;
end;

end.
