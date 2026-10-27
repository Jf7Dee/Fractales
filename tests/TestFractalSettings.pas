unit TestFractalSettings;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Persistence,
  Fractal.Settings, TestUtils;

type
  TTestSettings = class(TTestCase)
  private
    function SampleSettings: TAppSettings;
    function SampleLocation: TFractalLocation;
    procedure WriteText(const FileName, Text: string);
  published
    procedure TestSettingsRoundTrip;
    procedure TestMissingFileGivesDefaults;
    procedure TestInvalidValuesGiveDefaults;
    procedure TestUnreadableFileGivesDefaults;
    procedure TestSaveToMissingFolderFailsSilently;
    procedure TestSessionRoundTrip;
    procedure TestMissingSessionNotLoaded;
    procedure TestCorruptSessionNotLoaded;
    procedure TestSaveSessionToMissingFolderFailsSilently;
  end;

implementation

const
  kNavModeCount = 2;
  kSampleX = -0.743643887037151;
  kSampleY = 0.131825904205330;

{------------------------------------------------------------------------------}

function TTestSettings.SampleSettings: TAppSettings;
begin
  Result := DefaultAppSettings;
  Result.IsRustEngine := True;
  Result.NavModeIndex := 1;
  Result.LocationFolder := 'D:\Fractales\Lieux é\';
  Result.ImageFolder := 'D:\Images\';
  Result.HiResFolder := 'E:\Rendus HD\';
  Result.HiResPreset := 4;
  Result.HiResWidth := 2000;
  Result.HiResHeight := 1500;
  Result.HiResSupersample := 3;
end;

{------------------------------------------------------------------------------}

function TTestSettings.SampleLocation: TFractalLocation;
var
  F: TFractalFormula;
  P: TGradientPalette;
  M: TColorMapping;
begin
  F := TMandelbrotFormula.Create;
  P := CreateBuiltInPalette(1);
  try
    M := DefaultColorMapping;
    M.Repeats := 40;
    M.Mode := cmBands;
    M.HasRelief := True;
    Result := TFractalLocation.Create;
    Result.CaptureFrom(F, MakeViewport(kSampleX, kSampleY, 1.5e-10, 800, 600), False, P, M);
  finally
    P.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.WriteText(const FileName, Text: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(FileName, TEncoding.UTF8);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestSettingsRoundTrip;
var
  FileName: string;
  S, R: TAppSettings;
begin
  FileName := TestTempFolder + 'settings-roundtrip.ini';
  S := SampleSettings;
  CheckTrue(SaveAppSettings(FileName, S));
  R := LoadAppSettings(FileName, kNavModeCount);
  CheckTrue(R.IsRustEngine);
  CheckEquals(1, R.NavModeIndex);
  CheckEquals(S.LocationFolder, R.LocationFolder);
  CheckEquals(S.ImageFolder, R.ImageFolder);
  CheckEquals(S.HiResFolder, R.HiResFolder);
  CheckEquals(4, R.HiResPreset);
  CheckEquals(2000, R.HiResWidth);
  CheckEquals(1500, R.HiResHeight);
  CheckEquals(3, R.HiResSupersample);
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestMissingFileGivesDefaults;
var
  R, D: TAppSettings;
begin
  R := LoadAppSettings(TestTempFolder + 'absent.ini', kNavModeCount);
  D := DefaultAppSettings;
  CheckFalse(R.IsRustEngine);
  CheckEquals(D.NavModeIndex, R.NavModeIndex);
  CheckEquals('', R.LocationFolder);
  CheckEquals(D.HiResPreset, R.HiResPreset);
  CheckEquals(D.HiResSupersample, R.HiResSupersample);
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestInvalidValuesGiveDefaults;
var
  FileName: string;
  R, D: TAppSettings;
begin
  FileName := TestTempFolder + 'settings-invalid.ini';
  WriteText(FileName, '[Engine]'#13#10'Kernel=Fortran'#13#10'[Navigation]'#13#10'Mode=7'#13#10
    + '[HiRes]'#13#10'Preset=-1'#13#10'Width=abc'#13#10'Height=99999'#13#10'Supersample=9');
  R := LoadAppSettings(FileName, kNavModeCount);
  D := DefaultAppSettings;
  CheckFalse(R.IsRustEngine);
  CheckEquals(D.NavModeIndex, R.NavModeIndex);
  CheckEquals(D.HiResPreset, R.HiResPreset);
  CheckEquals(D.HiResWidth, R.HiResWidth);
  CheckEquals(D.HiResHeight, R.HiResHeight);
  CheckEquals(D.HiResSupersample, R.HiResSupersample);
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestUnreadableFileGivesDefaults;
var
  FileName: string;
  Stream: TFileStream;
  R: TAppSettings;
begin
  FileName := TestTempFolder + 'settings-locked.ini';
  CheckTrue(SaveAppSettings(FileName, SampleSettings));
  // ouvert sans partage : la lecture échoue
  Stream := TFileStream.Create(FileName, fmOpenReadWrite or fmShareExclusive);
  try
    R := LoadAppSettings(FileName, kNavModeCount);
  finally
    Stream.Free;
  end;
  CheckFalse(R.IsRustEngine);
  CheckEquals('', R.LocationFolder);
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestSaveToMissingFolderFailsSilently;
begin
  CheckFalse(SaveAppSettings(TestTempFolder + 'absent\sous\Fractales.ini', SampleSettings));
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestSessionRoundTrip;
var
  FileName: string;
  Saved, Loaded: TFractalLocation;
begin
  FileName := TestTempFolder + 'Session.frac';
  Saved := SampleLocation;
  Loaded := TFractalLocation.Create;
  try
    CheckTrue(TrySaveSession(FileName, Saved));
    CheckTrue(TryLoadSession(FileName, Loaded));
    // le centre relu s'écrit avec plus de chiffres (même valeur) : on compare le début de son texte
    CheckTrue(Pos('CenterX=-0.743643887037151000009120582756594330', Loaded.SaveToText) > 0);
    CheckEquals(Saved.FormulaName, Loaded.FormulaName);
    CheckEquals(Saved.Width, Loaded.Width, 1e-25);
    CheckEquals(Saved.MaxIter, Loaded.MaxIter);
    CheckEquals(40, Loaded.Mapping.Repeats, 1e-12);
    CheckTrue(Loaded.Mapping.Mode = cmBands);
    CheckTrue(Loaded.Mapping.HasRelief);
  finally
    Loaded.Free;
    Saved.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestMissingSessionNotLoaded;
var
  Location: TFractalLocation;
begin
  Location := TFractalLocation.Create;
  try
    CheckFalse(TryLoadSession(TestTempFolder + 'absent.frac', Location));
    CheckFalse(TryLoadSession(TestTempFolder + 'absent.frac', nil));
  finally
    Location.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestCorruptSessionNotLoaded;
var
  FileName: string;
  Location: TFractalLocation;
begin
  FileName := TestTempFolder + 'Session-corrompue.frac';
  WriteText(FileName, '[Location]'#13#10'Formula=Inconnue'#13#10'CenterX=n''importe quoi');
  Location := TFractalLocation.Create;
  try
    CheckFalse(TryLoadSession(FileName, Location));
  finally
    Location.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestSettings.TestSaveSessionToMissingFolderFailsSilently;
var
  Location: TFractalLocation;
begin
  Location := SampleLocation;
  try
    CheckFalse(TrySaveSession(TestTempFolder + 'absent\sous\Session.frac', Location));
    CheckFalse(TrySaveSession(TestTempFolder + 'Session-nil.frac', nil));
  finally
    Location.Free;
  end;
end;

initialization
  RegisterTest(TTestSettings.Suite);

end.
