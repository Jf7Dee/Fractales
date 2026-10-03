unit TestFractalPersistence;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Persistence,
  TestUtils;

type
  TTestPersistence = class(TTestCase)
  private
    function SampleLocation: TFractalLocation;
    procedure CheckRaisesFileError(const Text: string);
  published
    procedure TestTextRoundTrip;
    procedure TestCreateFormulaRestoresParams;
    procedure TestUnknownFormulaRaises;
    procedure TestMissingValuesUseDefaults;
    procedure TestOutOfRangeValuesAreClamped;
    procedure TestTextWithoutSectionRaises;
    procedure TestBinaryFileRaisesFileError;
    procedure TestNumbersAreInvariant;
    procedure TestFavoriteStore;
    procedure TestSanitizeFileName;
    procedure TestSaveToMissingFolderRaisesFileError;
    procedure TestHugeParamUsesDefault;
    procedure TestHugeRepeatsUsesDefault;
    procedure TestTinyWidthUsesDefault;
  end;

implementation

const
  kSampleX = -0.7436438870371587;
  kSampleY = 0.1318259042053119;
  kMinStretchAsDouble: Double = kMinStretch;  // Mapping.Stretch est un Double

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
    CheckEquals(kSampleX, B.CenterX, 1e-17);
    CheckEquals(kSampleY, B.CenterY, 1e-17);
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
    CheckEquals(TJuliaFormula.DefaultCenterX, L.CenterX, 0);
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
    CheckEquals(kSampleX, B.CenterX, 1e-17);
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

initialization
  RegisterTest(TTestPersistence.Suite);

end.
