unit Fractal.Settings;

// Réglages du programme conservés d'une séance à l'autre (Fractales.ini) et lieu de la dernière séance
// (Session.frac), tous deux à côté de l'exécutable. Fichier absent ou illisible : valeurs de départ, sans message.

interface

uses
  SysUtils, IniFiles, Fractal.Persistence;

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
    HiResPreset: Integer;
    HiResWidth: Integer;       // taille personnalisée
    HiResHeight: Integer;
    HiResSupersample: Integer;
  end;

function DefaultAppSettings: TAppSettings;
function LoadAppSettings(const FileName: string; NavModeCount: Integer): TAppSettings;
function SaveAppSettings(const FileName: string; const S: TAppSettings): Boolean;
function TryLoadSession(const FileName: string; Location: TFractalLocation): Boolean;
function TrySaveSession(const FileName: string; Location: TFractalLocation): Boolean;
function SettingsFilePath: string;
function SessionFilePath: string;

implementation

const
  kSectionEngine = 'Engine';
  kSectionNavigation = 'Navigation';
  kSectionFolders = 'Folders';
  kSectionHiRes = 'HiRes';
  kKeyKernel = 'Kernel';
  kKeyMode = 'Mode';
  kKeyLocations = 'Locations';
  kKeyImages = 'Images';
  kKeyHiRes = 'HiRes';
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
  Result.HiResPreset := kDefaultHiResPreset;
  Result.HiResWidth := kDefaultHiResWidth;
  Result.HiResHeight := kDefaultHiResHeight;
  Result.HiResSupersample := kDefaultSupersample;
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
      Result.HiResPreset := ReadBounded(Ini, kSectionHiRes, kKeyPreset, D.HiResPreset, 0, kHiResPresetCount - 1);
      Result.HiResWidth := ReadBounded(Ini, kSectionHiRes, kKeyWidth, D.HiResWidth, kMinHiResSize, kMaxHiResSize);
      Result.HiResHeight := ReadBounded(Ini, kSectionHiRes, kKeyHeight, D.HiResHeight, kMinHiResSize,
        kMaxHiResSize);
      Result.HiResSupersample := ReadBounded(Ini, kSectionHiRes, kKeySupersample, D.HiResSupersample,
        kMinSupersample, kMaxSupersample);
    finally
      Ini.Free;
    end;
  except
    Result := D;  // fichier illisible : démarrage habituel
  end;
end;

{------------------------------------------------------------------------------}

function SaveAppSettings(const FileName: string; const S: TAppSettings): Boolean;
var
  Ini: TMemIniFile;
  Kernel: string;
begin
  Result := False;
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
      Ini.WriteInteger(kSectionHiRes, kKeyPreset, S.HiResPreset);
      Ini.WriteInteger(kSectionHiRes, kKeyWidth, S.HiResWidth);
      Ini.WriteInteger(kSectionHiRes, kKeyHeight, S.HiResHeight);
      Ini.WriteInteger(kSectionHiRes, kKeySupersample, S.HiResSupersample);
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

end.
