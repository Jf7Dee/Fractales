unit TestFractalPersistence;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Types, Fractal.HighFloat, Fractal.Formulas, Fractal.Palette,
  Fractal.Persistence,
  TestUtils;

type
  TTestPersistence = class(TTestCase)
  private
    function SampleLocation: TFractalLocation;
    function NameAt(DX, DY, Zoom: TFloat): string;
    procedure CheckRaisesFileError(const Text: string);
    function DeepViewport: TViewport;
    function DeepLocation(const V: TViewport): TFractalLocation;
  published
    procedure TestDeepLocationRoundTrip;
    procedure TestOldFileReadsIdentically;
    procedure TestDeepLocationTextRoundTrip;
    procedure TestTextRoundTrip;
    procedure TestCreateFormulaRestoresParams;
    procedure TestUnknownFormulaRaises;
    procedure TestMissingValuesUseDefaults;
    procedure TestOutOfRangeValuesAreClamped;
    procedure TestTextWithoutSectionRaises;
    procedure TestBinaryFileRaisesFileError;
    procedure TestNumbersAreInvariant;
    procedure TestApplyToHugeCenterDoesNotRaise;
    procedure TestFavoriteStore;
    procedure TestSanitizeFileName;
    procedure TestSaveToMissingFolderRaisesFileError;
    procedure TestHugeParamUsesDefault;
    procedure TestHugeRepeatsUsesDefault;
    procedure TestTinyWidthUsesDefault;
    procedure TestSuggestedNameAtDefaultView;
    procedure TestSuggestedNameDirections;
    procedure TestSuggestedNameZoomLabel;
    procedure TestUniqueBaseName;
    procedure TestEffectsRoundTrip;
    procedure TestNoEffectsColorsSectionUnchanged;
    procedure TestOldFileGivesDefaultEffects;
    procedure TestInvalidEffectsUseDefaults;
  end;

implementation

const
  kSampleX = -0.7436438870371587;
  kSampleY = 0.1318259042053119;
  kMinStretchAsDouble: Double = kMinStretch;  // Mapping.Stretch est un Double
  kDeepWidth = 1e-50;
  kDeepPixels = 800;
  kDeepCenterX = '-0.74364388703715870475219150611477400123456789012345678901234567890123456789';
  kDeepCenterY = '0.13182590420531197049313205638513901234567890123456789012345678901234567891';
  kOldFileCenterX = '-0.743643887037158704';
  kWhenSuffix = '_20261016-0912';  // date de NameAt
  // section [Colors] d'un lieu sans effets, telle qu'écrite par master (référence figée)
  kFrozenColorsSection = '[Colors]'#13#10'Offset=0.299999999999999989'#13#10'Repeats=40'#13#10
    + 'Stretch=0.800000000000000044'#13#10'Invert=1'#13#10;

{------------------------------------------------------------------------------}

function TTestPersistence.SampleLocation: TFractalLocation;
var
  F: TMultibrotFormula;
  P: TGradientPalette;
  M: TColorMapping;
begin
  F := TMultibrotFormula.Create;
  P := CreateBuiltInPalette(1);
  try
    F.SetParam(0, 4.5);
    F.MaxIter := 3000;
    M := DefaultColorMapping;
    M.Offset := 0.3;
    M.Repeats := 40;
    M.Stretch := 0.8;
    M.IsInverted := True;
    Result := TFractalLocation.Create;
    Result.CaptureFrom(F, MakeViewport(kSampleX, kSampleY, 1.5e-10, 800, 600), False, P, M);
  finally
    P.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.CheckRaisesFileError(const Text: string);
var
  L: TFractalLocation;
  IsRaised: Boolean;
begin
  L := TFractalLocation.Create;
  try
    IsRaised := False;
    try
      L.LoadFromText(Text);
    except
      on EFractalFileError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised, Text);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestTextRoundTrip;
var
  A, B: TFractalLocation;
begin
  A := SampleLocation;
  B := TFractalLocation.Create;
  try
    B.LoadFromText(A.SaveToText);
    CheckEquals('Multibrot', B.FormulaName);
    CheckEquals(kSampleX, B.CenterX.ToFloat, 1e-17);
    CheckEquals(kSampleY, B.CenterY.ToFloat, 1e-17);
    CheckEquals(1.5e-10, B.Width, 1e-26);
    CheckEquals(3000, B.MaxIter);
    CheckFalse(B.IsAutoIter);
    CheckEquals(0.3, B.Mapping.Offset, 1e-9);
    CheckEquals(40.0, B.Mapping.Repeats, 1e-9);
    CheckEquals(0.8, B.Mapping.Stretch, 1e-9);
    CheckTrue(B.Mapping.IsInverted);
    CheckEquals('Feu', B.Palette.Name);
    CheckEquals(A.Palette.StopCount, B.Palette.StopCount);
    CheckEquals(Integer(A.Palette.Stop(2).Color), Integer(B.Palette.Stop(2).Color));
  finally
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestCreateFormulaRestoresParams;
var
  A: TFractalLocation;
  F: TFractalFormula;
begin
  A := SampleLocation;
  try
    F := A.CreateFormula;
    try
      CheckTrue(F is TMultibrotFormula);
      CheckEquals(4.5, F.GetParam(0), 1e-12);
      CheckEquals(3000, F.MaxIter);
    finally
      F.Free;
    end;
  finally
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestUnknownFormulaRaises;
begin
  CheckRaisesFileError('[Fractal]'#13#10'Formula=Inexistante');
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestMissingValuesUseDefaults;
var
  L: TFractalLocation;
  F: TFractalFormula;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Julia');
    CheckEquals(TJuliaFormula.DefaultCenterX, L.CenterX.ToFloat, 0);
    CheckEquals(TJuliaFormula.DefaultWidth, L.Width, 0);
    CheckEquals(kDefaultMaxIter, L.MaxIter);
    CheckTrue(L.IsAutoIter);
    CheckTrue(L.Palette.StopCount >= 2);
    F := L.CreateFormula;
    try
      CheckEquals(-0.8, F.GetParam(0), 1e-12);
    finally
      F.Free;
    end;
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestOutOfRangeValuesAreClamped;
var
  L: TFractalLocation;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'MaxIter=5'#13#10'Width=-3'#13#10 +
      '[Colors]'#13#10'Repeats=99999'#13#10'Stretch=0');
    CheckEquals(kMinMaxIter, L.MaxIter);
    CheckEquals(TMandelbrotFormula.DefaultWidth, L.Width, 0);
    CheckEquals(kMaxRepeats, L.Mapping.Repeats, 0);
    CheckEquals(kMinStretchAsDouble, L.Mapping.Stretch, 0);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestTextWithoutSectionRaises;
begin
  CheckRaisesFileError('bonjour');
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestBinaryFileRaisesFileError;
var
  FileName: string;
  Stream: TFileStream;
  Bytes: array[0..1023] of Byte;
  I: Integer;
  L: TFractalLocation;
  IsRaised: Boolean;
begin
  FileName := TestTempFolder + 'binaire.frac';
  for I := 0 to High(Bytes) do
    Bytes[I] := Byte(I * 7 + 3);
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Bytes, SizeOf(Bytes));
  finally
    Stream.Free;
  end;
  L := TFractalLocation.Create;
  try
    IsRaised := False;
    try
      L.LoadFromFile(FileName);
    except
      on EFractalFileError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestPersistence.DeepViewport: TViewport;
var
  X, Y: THighFloat;
  Words: Integer;
begin
  Result := MakeViewport(0, 0, kDeepWidth, kDeepPixels, kDeepPixels);
  Words := FracWordsForPixelSize(Result.PixelSize);
  CheckTrue(THighFloat.TryParse(kDeepCenterX, Words, X));
  CheckTrue(THighFloat.TryParse(kDeepCenterY, Words, Y));
  Result.SetCenter(X, Y);
end;

{------------------------------------------------------------------------------}

function TTestPersistence.DeepLocation(const V: TViewport): TFractalLocation;
var
  F: TMandelbrotFormula;
  P: TGradientPalette;
begin
  F := TMandelbrotFormula.Create;
  P := CreateBuiltInPalette(1);
  try
    Result := TFractalLocation.Create;
    Result.CaptureFrom(F, V, True, P, DefaultColorMapping);
  finally
    P.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestDeepLocationRoundTrip;
var
  A, B: TFractalLocation;
  V, W: TViewport;
  FileName: string;
begin
  V := DeepViewport;
  A := DeepLocation(V);
  B := TFractalLocation.Create;
  FileName := TestTempFolder + 'deep.frac';
  try
    A.SaveToFile(FileName);
    B.LoadFromFile(FileName);
    W := MakeViewport(0, 0, 4, kDeepPixels, kDeepPixels);
    B.ApplyTo(W);
    CheckTrue(V.IsSameView(W));
  finally
    DeleteFile(FileName);
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestOldFileReadsIdentically;
var
  L: TFractalLocation;
  V: TViewport;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'CenterX=' + kOldFileCenterX + #13#10'CenterY=0.5'#13#10
      + 'Width=3'#13#10);
    V := MakeViewport(0, 0, 4, kDeepPixels, kDeepPixels);
    L.ApplyTo(V);
    CheckTrue(InvariantToFloat(kOldFileCenterX, 0) = V.CenterX);
    CheckTrue(V.CenterY = 0.5);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestDeepLocationTextRoundTrip;
var
  A, B: TFractalLocation;
begin
  A := DeepLocation(DeepViewport);
  B := TFractalLocation.Create;
  try
    B.LoadFromText(A.SaveToText);
    CheckTrue(A.CenterX.IsEqual(B.CenterX));
    CheckTrue(A.CenterY.IsEqual(B.CenterY));
  finally
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestApplyToHugeCenterDoesNotRaise;
var
  A, B: TFractalLocation;
  V: TViewport;
begin
  A := SampleLocation;
  B := TFractalLocation.Create;
  try
    B.LoadFromText(StringReplace(A.SaveToText, 'CenterX=-0.7436438870', 'CenterX=1e20'#13#10'Junk=', []));
    V := MakeViewport(0, 0, 4, 800, 600);
    B.ApplyTo(V);
    CheckTrue(Abs(V.CenterX) <= kMaxCenterCoordinate);
  finally
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestNumbersAreInvariant;
var
  A: TFractalLocation;
begin
  A := SampleLocation;
  try
    CheckTrue(Pos('CenterX=-0.7436438870', A.SaveToText) > 0);
  finally
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestFavoriteStore;
var
  Folder, Stored: string;
  Store: TFavoriteStore;
  A, B: TFractalLocation;
  Names: TStringList;
begin
  Folder := TestTempFolder + 'Favoris\';
  if FileExists(Folder + 'Spirale_ double.frac') then
    SysUtils.DeleteFile(Folder + 'Spirale_ double.frac');
  Store := TFavoriteStore.Create(Folder);
  A := SampleLocation;
  B := TFractalLocation.Create;
  Names := TStringList.Create;
  try
    Stored := Store.Save('Spirale: double', A);
    CheckEquals('Spirale_ double', Stored);
    Store.List(Names);
    CheckTrue(Names.IndexOf(Stored) >= 0);
    Store.Load(Stored, B);
    CheckEquals(kSampleX, B.CenterX.ToFloat, 1e-17);
    Store.Delete(Stored);
    Store.List(Names);
    CheckEquals(-1, Names.IndexOf(Stored));
  finally
    Names.Free;
    B.Free;
    A.Free;
    Store.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestSanitizeFileName;
begin
  CheckEquals('a_b_c_d_e_f_g_h_i_j', SanitizeFileName('a/b\c:d*e?f"g<h>i|j'));
  CheckEquals('Sans nom', SanitizeFileName('   '));
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestSaveToMissingFolderRaisesFileError;
var
  A: TFractalLocation;
  IsRaised: Boolean;
begin
  A := SampleLocation;
  try
    IsRaised := False;
    try
      A.SaveToFile(TestTempFolder + 'absent\sous\x.frac');
    except
      on EFractalFileError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestHugeParamUsesDefault;
var
  L: TFractalLocation;
  F: TFractalFormula;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Multibrot'#13#10'[Params]'#13#10'power=1e400');
    F := L.CreateFormula;
    try
      CheckEquals(3, F.GetParam(0), 1e-12);
    finally
      F.Free;
    end;
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestHugeRepeatsUsesDefault;
var
  L: TFractalLocation;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'[Colors]'#13#10'Repeats=1e400');
    CheckEquals(DefaultColorMapping.Repeats, L.Mapping.Repeats, 0);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestTinyWidthUsesDefault;
var
  L: TFractalLocation;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'Width=1e-4000');
    CheckTrue(L.Width = TMandelbrotFormula.DefaultWidth, 'largeur par défaut');
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Nom proposé pour Mandelbrot, le centre décalé de (DX, DY) largeurs initiales, au facteur de zoom donné.
function TTestPersistence.NameAt(DX, DY, Zoom: TFloat): string;
var
  V: TViewport;
begin
  V := MakeViewport(TMandelbrotFormula.DefaultCenterX + DX * TMandelbrotFormula.DefaultWidth,
    TMandelbrotFormula.DefaultCenterY + DY * TMandelbrotFormula.DefaultWidth, TMandelbrotFormula.DefaultWidth / Zoom,
    800, 600);
  Result := SuggestedName(TMandelbrotFormula, V, EncodeDate(2026, 10, 16) + EncodeTime(9, 12, 0, 0));
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestSuggestedNameAtDefaultView;
var
  V: TViewport;
begin
  CheckEquals('Mandelbrot_centre_x1' + kWhenSuffix, NameAt(0, 0, 1));
  V := MakeViewport(TBurningShipFormula.DefaultCenterX, TBurningShipFormula.DefaultCenterY,
    TBurningShipFormula.DefaultWidth, 800, 600);
  CheckEquals('BurningShip_centre_x1_20261016-0912',
    SuggestedName(TBurningShipFormula, V, EncodeDate(2026, 10, 16) + EncodeTime(9, 12, 0, 0)));
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestSuggestedNameDirections;
begin
  // le Y complexe croît vers le haut de l'écran
  CheckEquals('Mandelbrot_N_x1' + kWhenSuffix, NameAt(0, 0.5, 1));
  CheckEquals('Mandelbrot_NE_x1' + kWhenSuffix, NameAt(0.5, 0.5, 1));
  CheckEquals('Mandelbrot_E_x1' + kWhenSuffix, NameAt(0.5, 0, 1));
  CheckEquals('Mandelbrot_SE_x1' + kWhenSuffix, NameAt(0.5, -0.5, 1));
  CheckEquals('Mandelbrot_S_x1' + kWhenSuffix, NameAt(0, -0.5, 1));
  CheckEquals('Mandelbrot_SO_x1' + kWhenSuffix, NameAt(-0.5, -0.5, 1));
  CheckEquals('Mandelbrot_O_x1' + kWhenSuffix, NameAt(-0.5, 0, 1));
  CheckEquals('Mandelbrot_NO_x1' + kWhenSuffix, NameAt(-0.5, 0.5, 1));
  CheckEquals('Mandelbrot_centre_x1' + kWhenSuffix, NameAt(0.01, -0.01, 1), 'proche du centre initial');
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestSuggestedNameZoomLabel;
begin
  CheckEquals('Mandelbrot_centre_x2.5' + kWhenSuffix, NameAt(0, 0, 2.5));
  CheckEquals('Mandelbrot_centre_x0.5' + kWhenSuffix, NameAt(0, 0, 0.5));
  CheckEquals('Mandelbrot_centre_x350' + kWhenSuffix, NameAt(0, 0, 350));
  CheckEquals('Mandelbrot_centre_x1e3' + kWhenSuffix, NameAt(0, 0, 1000));
  CheckEquals('Mandelbrot_centre_x2.4e5' + kWhenSuffix, NameAt(0, 0, 240000));
  CheckEquals('Mandelbrot_centre_x1e6' + kWhenSuffix, NameAt(0, 0, 999000), 'mantisse arrondie à 10');
  CheckEquals('Mandelbrot_centre_x3.7e18' + kWhenSuffix, NameAt(0, 0, 3.7e18));
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestUniqueBaseName;
var
  Folder: string;

  procedure Touch(const FileName: string);
  begin
    TFileStream.Create(FileName, fmCreate).Free;
  end;

begin
  Folder := TestTempFolder + 'Unique' + PathDelim;
  ForceDirectories(Folder);
  SysUtils.DeleteFile(Folder + 'Vue.png');
  SysUtils.DeleteFile(Folder + 'Vue_2.png');
  CheckEquals('Vue', UniqueBaseName(Folder, 'Vue', '.png'));
  Touch(Folder + 'Vue.png');
  CheckEquals('Vue_2', UniqueBaseName(Folder, 'Vue', '.png'));
  CheckEquals('Vue', UniqueBaseName(Folder, 'Vue', '.frac'), 'autre extension');
  Touch(Folder + 'Vue_2.png');
  CheckEquals('Vue_3', UniqueBaseName(Folder, 'Vue', '.png'));
end;

function ColorsSectionOf(const AText: string): string;   // de [Colors] (inclus) jusqu'à la ligne vide
var
  Start, Stop: Integer;
begin
  Start := Pos('[Colors]', AText);
  Result := '';
  if Start > 0 then
  begin
    Stop := Start;
    while (Stop < Length(AText)) and not ((AText[Stop] = #10) and CharInSet(AText[Stop + 1], [#13, #10])) do
      Inc(Stop);
    Result := Copy(AText, Start, Stop - Start + 1);
  end;
end;

{------------------------------------------------------------------------------}

function LocationWithMapping(const AMapping: TColorMapping): TFractalLocation;
var
  F: TMultibrotFormula;
  P: TGradientPalette;
begin
  F := TMultibrotFormula.Create;
  P := CreateBuiltInPalette(1);
  try
    Result := TFractalLocation.Create;
    Result.CaptureFrom(F, MakeViewport(kSampleX, kSampleY, 1.5e-10, 800, 600), False, P, AMapping);
  finally
    P.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestEffectsRoundTrip;
var
  A, B, C: TFractalLocation;
  M: TColorMapping;
  FileName: string;
begin
  M := DefaultColorMapping;
  M.Mode := cmBands;
  M.BandWidth := 0.2;
  M.Shading := 0.7;
  M.HasContours := True;
  M.ContourWidth := 0.15;
  M.HasRelief := True;
  M.LightAngle := 135;
  M.ReliefIntensity := 0.6;
  M.ReliefHeight := 3.5;
  M := ClampColorMapping(M);
  A := LocationWithMapping(M);
  B := TFractalLocation.Create;
  C := TFractalLocation.Create;
  try
    // texte (PNG)
    B.LoadFromText(A.SaveToText);
    CheckTrue(B.Mapping.Mode = cmBands);
    CheckEquals(M.BandWidth, B.Mapping.BandWidth, 1e-9);
    CheckEquals(M.Shading, B.Mapping.Shading, 1e-9);
    CheckTrue(B.Mapping.HasContours);
    CheckEquals(M.ContourWidth, B.Mapping.ContourWidth, 1e-9);
    CheckTrue(B.Mapping.HasRelief);
    CheckEquals(M.LightAngle, B.Mapping.LightAngle, 1e-9);
    CheckEquals(M.ReliefIntensity, B.Mapping.ReliefIntensity, 1e-9);
    CheckEquals(M.ReliefHeight, B.Mapping.ReliefHeight, 1e-9);
    // fichier .frac
    FileName := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'effects_roundtrip.frac';
    A.SaveToFile(FileName);
    try
      C.LoadFromFile(FileName);
    finally
      DeleteFile(FileName);
    end;
    CheckTrue(C.Mapping.Mode = cmBands);
    CheckEquals(M.BandWidth, C.Mapping.BandWidth, 1e-9);
    CheckEquals(M.Shading, C.Mapping.Shading, 1e-9);
    CheckTrue(C.Mapping.HasContours);
    CheckEquals(M.ContourWidth, C.Mapping.ContourWidth, 1e-9);
    CheckTrue(C.Mapping.HasRelief);
    CheckEquals(M.LightAngle, C.Mapping.LightAngle, 1e-9);
    CheckEquals(M.ReliefIntensity, C.Mapping.ReliefIntensity, 1e-9);
    CheckEquals(M.ReliefHeight, C.Mapping.ReliefHeight, 1e-9);
  finally
    C.Free;
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestNoEffectsColorsSectionUnchanged;
var
  A: TFractalLocation;
begin
  A := SampleLocation;
  try
    CheckEquals(kFrozenColorsSection, ColorsSectionOf(A.SaveToText));
  finally
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestOldFileGivesDefaultEffects;
var
  L: TFractalLocation;
  D: TColorMapping;
begin
  D := DefaultColorMapping;
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'[Colors]'#13#10'Offset=0.25'#13#10);
    CheckTrue(L.Mapping.Mode = cmSmooth);
    CheckEquals(D.BandWidth, L.Mapping.BandWidth, 0);
    CheckEquals(D.Shading, L.Mapping.Shading, 0);
    CheckFalse(L.Mapping.HasContours);
    CheckEquals(D.ContourWidth, L.Mapping.ContourWidth, 0);
    CheckFalse(L.Mapping.HasRelief);
    CheckEquals(D.LightAngle, L.Mapping.LightAngle, 0);
    CheckEquals(D.ReliefIntensity, L.Mapping.ReliefIntensity, 0);
    CheckEquals(D.ReliefHeight, L.Mapping.ReliefHeight, 0);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPersistence.TestInvalidEffectsUseDefaults;
var
  L: TFractalLocation;
  D: TColorMapping;
begin
  D := DefaultColorMapping;
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'[Colors]'#13#10'Mode=Zigzag'#13#10'BandWidth=abc'#13#10
      + 'Shading=1e999'#13#10'Contours=oui'#13#10'ContourWidth='#13#10'Relief=x'#13#10'LightAngle=??'#13#10
      + 'ReliefIntensity=nan'#13#10'ReliefHeight=--'#13#10);
    CheckTrue(L.Mapping.Mode = cmSmooth);
    CheckEquals(D.BandWidth, L.Mapping.BandWidth, 0);
    CheckEquals(D.Shading, L.Mapping.Shading, 0);
    CheckFalse(L.Mapping.HasContours);
    CheckEquals(D.ContourWidth, L.Mapping.ContourWidth, 0);
    CheckFalse(L.Mapping.HasRelief);
    CheckEquals(D.LightAngle, L.Mapping.LightAngle, 0);
    CheckEquals(D.ReliefIntensity, L.Mapping.ReliefIntensity, 0);
    CheckEquals(D.ReliefHeight, L.Mapping.ReliefHeight, 0);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

initialization
  RegisterTest(TTestPersistence.Suite);

end.
