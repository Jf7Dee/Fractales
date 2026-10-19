unit TestFractalRustKernel;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.RustKernel, Fractal.Buffer,
  Fractal.Engine, TestUtils;

type
  // formule sans équivalent dans la DLL : la DLL doit répondre « formule inconnue »
  TUnknownKernelFormula = class(TMandelbrotFormula)
  public
    class function KernelId: Integer; override;
  end;

  // formule que la DLL ne sait pas calculer : le moteur doit retomber sur Delphi
  TNoKernelFormula = class(TMandelbrotFormula)
  public
    class function KernelId: Integer; override;
  end;

  TTestRustEngine = class(TTestCase)
  private
    FFake: TRustKernel;
    FMissing: TRustKernel;
    function RenderWith(Kernel: TEngineKernelType; RustKernel: TRustKernel; Formula: TFractalFormula;
      const V: TViewport; IsProgressive: Boolean): TRenderEngine;
    procedure CheckBuffersAgree(A, B: TIterationBuffer; MinRatio: Double; const Context: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRustModeMatchesDelphiWithFakeKernel;
    procedure TestFallsBackWhenDllMissing;
    procedure TestFallsBackForFormulaWithoutKernelId;
    procedure TestKernelErrorBecomesTileError;
    procedure TestNewRenderIsQuickInRustMode;
    procedure TestKernelEpsilonAndName;
    procedure TestRealKernelMatchesDelphi;
  end;

  TTestRustKernel = class(TTestCase)
  published
    procedure TestMissingFileIsUnavailable;
    procedure TestBadFormatFileIsUnavailable;
    procedure TestDllWithoutExportsIsUnavailable;
    procedure TestFakeKernelComputesRow;
    procedure TestKernelErrorRaises;
    procedure TestUnavailableKernelRaises;
    procedure TestDefaultKernelIsShared;
  end;

function TestBinFolder: string;
function FakeKernelFileName: string;

implementation

const
  kFakeKernelFile = 'FakeKernel.dll';
  kUnknownKernelId = 42;
  kRowCount = 5;
  kRowX0 = -2.5;
  kRowDX = 0.5;
  kWaitMs = 20000;
  kValueTolerance = 1e-3;
  kInsideTolerance = 0.001;   // ± 0,1 % de points intérieurs
  // Les seuls arrondis en Double des coordonnées changent l'itération d'échappement de 1,6 % des pixels de
  // Burning Ship (vue initiale, mesuré) : un pixel mal placé par le moteur, lui, fausserait des suites entières.
  kFakeMinRatio = 0.98;       // DLL factice : coordonnées arrondies en Double
  kRealMinRatio = 0.98;       // vraie DLL : coordonnées et calcul en Double
  kOddWidth = 203;            // ni multiple de 64 ni de 4 : tuiles de bord et suites courtes
  kOddHeight = 149;
  kCompareWidth = 200;
  kCompareHeight = 150;
  kHeavyMaxIter = 100000;
  kQuickRenderMs = 1000;

{------------------------------------------------------------------------------}

function TestBinFolder: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

{------------------------------------------------------------------------------}

function FakeKernelFileName: string;
begin
  Result := TestBinFolder + kFakeKernelFile;
end;

{------------------------------------------------------------------------------}

class function TUnknownKernelFormula.KernelId: Integer;
begin
  Result := kUnknownKernelId;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestMissingFileIsUnavailable;
var
  K: TRustKernel;
begin
  K := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('introuvable', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestBadFormatFileIsUnavailable;
var
  FileName: string;
  Lines: TStringList;
  K: TRustKernel;
begin
  // même erreur 193 qu'une DLL 64 bits : le message doit citer la bonne cible de compilation
  FileName := TestTempFolder + 'not_a_dll.dll';
  Lines := TStringList.Create;
  try
    Lines.Add('pas une DLL');
    Lines.SaveToFile(FileName);
  finally
    Lines.Free;
  end;
  K := TRustKernel.Create(FileName);
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('i686-pc-windows-msvc', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestDllWithoutExportsIsUnavailable;
var
  SystemDir: array[0..MAX_PATH] of Char;
  K: TRustKernel;
begin
  GetSystemDirectory(SystemDir, MAX_PATH);
  K := TRustKernel.Create(IncludeTrailingPathDelimiter(SystemDir) + 'version.dll');
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('fk_', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestFakeKernelComputesRow;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..kRowCount - 1] of Single;
  I: Integer;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TMandelbrotFormula.Create;
  try
    CheckTrue(K.IsAvailable, K.Status);
    K.ComputeRow(F, kRowX0, kRowDX, 0, kRowCount, @Values[0]);
    for I := 0 to kRowCount - 1 do
      CheckEquals(F.Iterate(kRowX0 + I * kRowDX, 0), Values[I], 0, Format('pixel %d', [I]));
    CheckEquals(kInside, Values[kRowCount - 1], 0);  // x = -0,5 : cardioïde
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestKernelErrorRaises;
var
  K: TRustKernel;
  F: TUnknownKernelFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TUnknownKernelFormula.Create;
  try
    try
      K.ComputeRow(F, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckTrue(Pos('(code 1)', E.Message) > 0, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestUnavailableKernelRaises;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
  F := TMandelbrotFormula.Create;
  try
    try
      K.ComputeRow(F, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckEquals(K.Status, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestDefaultKernelIsShared;
begin
  CheckSame(DefaultRustKernel, DefaultRustKernel);
  CheckEquals(DefaultRustKernel.IsAvailable, IsRustKernelAvailable);
  CheckEquals(DefaultRustKernel.Status, RustKernelStatus);
end;

{------------------------------------------------------------------------------}

class function TNoKernelFormula.KernelId: Integer;
begin
  Result := kKernelNone;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.SetUp;
begin
  FFake := TRustKernel.Create(FakeKernelFileName);
  FMissing := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TearDown;
begin
  FreeAndNil(FMissing);
  FreeAndNil(FFake);
end;

{------------------------------------------------------------------------------}

function TTestRustEngine.RenderWith(Kernel: TEngineKernelType; RustKernel: TRustKernel; Formula: TFractalFormula;
  const V: TViewport; IsProgressive: Boolean): TRenderEngine;
begin
  Result := TRenderEngine.Create(CpuCount);
  try
    Result.Kernel := Kernel;
    Result.RustKernel := RustKernel;
    Result.Render(V, Formula, IsProgressive);
    CheckTrue(Result.WaitUntilComplete(kWaitMs), 'rendu non terminé');
    CheckTrue(Result.Status.IsComplete, 'rendu incomplet');
  except
    Result.Free;
    raise;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.CheckBuffersAgree(A, B: TIterationBuffer; MinRatio: Double; const Context: string);
var
  X, Y, Matching, InsideA, InsideB, Total: Integer;
  VA, VB: Single;
begin
  CheckEquals(A.Width, B.Width, Context);
  CheckEquals(A.Height, B.Height, Context);
  Matching := 0;
  InsideA := 0;
  InsideB := 0;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
    begin
      CheckTrue(B.IsExact(X, Y), Format('%s : pixel (%d, %d) non calculé', [Context, X, Y]));
      VA := A.Value(X, Y);
      VB := B.Value(X, Y);
      if VA < 0 then
        Inc(InsideA);
      if VB < 0 then
        Inc(InsideB);
      if ((VA < 0) and (VB < 0)) or ((VA >= 0) and (VB >= 0) and (Abs(VA - VB) <= kValueTolerance)) then
        Inc(Matching);
    end;
  Total := A.Width * A.Height;
  CheckTrue(Matching >= MinRatio * Total, Format('%s : %d pixels concordants sur %d', [Context, Matching, Total]));
  CheckTrue(Abs(InsideA - InsideB) <= kInsideTolerance * Total,
    Format('%s : %d points intérieurs contre %d', [Context, InsideA, InsideB]));
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestRustModeMatchesDelphiWithFakeKernel;
var
  F: TFractalFormula;
  V: TViewport;
  ED, ER: TRenderEngine;
  I: Integer;
begin
  for I := 0 to FormulaClassCount - 1 do
  begin
    F := FormulaClassAt(I).Create;
    ED := nil;
    ER := nil;
    try
      V := MakeViewport(F.DefaultCenterX, F.DefaultCenterY, F.DefaultWidth, kOddWidth, kOddHeight);
      ED := RenderWith(ekDelphi, nil, F, V, True);
      ER := RenderWith(ekRust, FFake, F, V, True);
      CheckEquals(Ord(ekRust), Ord(ER.Status.Kernel), F.FormulaName);
      CheckEquals('', ER.TakeErrors, F.FormulaName);
      CheckBuffersAgree(ED.Buffer, ER.Buffer, kFakeMinRatio, F.FormulaName);
    finally
      ER.Free;
      ED.Free;
      F.Free;
    end;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestFallsBackWhenDllMissing;
var
  F: TMandelbrotFormula;
  E: TRenderEngine;
begin
  F := TMandelbrotFormula.Create;
  E := nil;
  try
    E := RenderWith(ekRust, FMissing, F, MakeViewport(-0.5, 0, 3, kOddWidth, kOddHeight), True);
    CheckEquals(Ord(ekDelphi), Ord(E.Status.Kernel));
    CheckEquals(Ord(ekDelphi), Ord(E.ResolveKernel(F)));
    CheckEquals('', E.TakeErrors);
  finally
    E.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestFallsBackForFormulaWithoutKernelId;
var
  F: TNoKernelFormula;
  E: TRenderEngine;
begin
  F := TNoKernelFormula.Create;
  E := nil;
  try
    E := RenderWith(ekRust, FFake, F, MakeViewport(-0.5, 0, 3, kOddWidth, kOddHeight), True);
    CheckEquals(Ord(ekDelphi), Ord(E.Status.Kernel));
    CheckEquals('', E.TakeErrors);
  finally
    E.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestKernelErrorBecomesTileError;
var
  F: TUnknownKernelFormula;
  E: TRenderEngine;
begin
  F := TUnknownKernelFormula.Create;
  E := nil;
  try
    E := RenderWith(ekRust, FFake, F, MakeViewport(-0.5, 0, 3, kOddWidth, kOddHeight), True);
    CheckEquals(Ord(ekRust), Ord(E.Status.Kernel));
    CheckTrue(Pos('Moteur Rust', E.TakeErrors) > 0);
  finally
    E.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestNewRenderIsQuickInRustMode;
var
  Heavy: TJuliaFormula;
  Light: TMandelbrotFormula;
  E: TRenderEngine;
  Start: Cardinal;
begin
  // Julia c = 0 : chaque pixel du disque unité coûte MaxIter itérations ; une suite en coûte jusqu'à 64 fois plus
  Heavy := TJuliaFormula.Create;
  Light := TMandelbrotFormula.Create;
  E := TRenderEngine.Create(CpuCount);
  try
    Heavy.SetParam(0, 0);
    Heavy.SetParam(1, 0);
    Heavy.MaxIter := kHeavyMaxIter;
    E.Kernel := ekRust;
    E.RustKernel := FFake;
    E.Render(MakeViewport(0, 0, 1, kCompareWidth, kCompareHeight), Heavy);
    Sleep(50);
    Start := GetTickCount;
    E.Render(MakeViewport(5, 5, 1, kCompareWidth, kCompareHeight), Light);
    CheckTrue(GetTickCount - Start < kQuickRenderMs, Format('nouveau rendu après %d ms', [GetTickCount - Start]));
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
  finally
    E.Free;
    Light.Free;
    Heavy.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestKernelEpsilonAndName;
begin
  CheckEquals(kExtendedEpsilon, TRenderEngine.GetEpsilon(ekDelphi), 0);
  CheckEquals(kDoubleEpsilon, TRenderEngine.GetEpsilon(ekRust), 0);
  CheckEquals('Delphi', TRenderEngine.GetDisplayName(ekDelphi));
  CheckEquals('Rust', TRenderEngine.GetDisplayName(ekRust));
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestRealKernelMatchesDelphi;
var
  RealKernel: TRustKernel;
  F: TFractalFormula;
  V: TViewport;
  ED, ER: TRenderEngine;
  I: Integer;
begin
  if not FileExists(TestBinFolder + kRustKernelFileName) then
  begin
    Status('fractal_kernel.dll absente de bin\ : comparaison avec le vrai moteur Rust ignorée.');
    Exit;
  end;
  RealKernel := TRustKernel.Create(TestBinFolder + kRustKernelFileName);
  try
    CheckTrue(RealKernel.IsAvailable, RealKernel.Status);
    for I := 0 to FormulaClassCount - 1 do
    begin
      F := FormulaClassAt(I).Create;
      ED := nil;
      ER := nil;
      try
        V := MakeViewport(F.DefaultCenterX, F.DefaultCenterY, F.DefaultWidth, kCompareWidth, kCompareHeight);
        ED := RenderWith(ekDelphi, nil, F, V, False);
        ER := RenderWith(ekRust, RealKernel, F, V, False);
        CheckEquals(Ord(ekRust), Ord(ER.Status.Kernel), F.FormulaName);
        CheckEquals('', ER.TakeErrors, F.FormulaName);
        CheckBuffersAgree(ED.Buffer, ER.Buffer, kRealMinRatio, F.FormulaName);
      finally
        ER.Free;
        ED.Free;
        F.Free;
      end;
    end;
  finally
    RealKernel.Free;
  end;
end;

initialization
  RegisterTest(TTestRustKernel.Suite);
  RegisterTest(TTestRustEngine.Suite);

end.
