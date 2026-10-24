unit TestFractalRustKernel;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.HighFloat, Fractal.Types, Fractal.Formulas, Fractal.Perturbation,
  Fractal.RustKernel, Fractal.Buffer, Fractal.Engine, TestUtils;

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
    procedure CheckDeepRenderAgrees(RustKernel: TRustKernel; MinRatio: Double);
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
    procedure TestRustDeepRenderMatchesDelphiWithFakeKernel;
    procedure TestAbi1FallsBackToDelphiWhenDeep;
    procedure TestAbi2FallsBackToDelphiForBurningShip;
    procedure TestRealKernelPerturbedMatchesDelphi;
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
    procedure TestFakeKernelPerturbedMatchesDelphi;
    procedure TestPerturbedKernelErrorRaises;
    procedure TestPerturbedKernelRejectsOnePointOrbit;
    procedure TestAbi1KernelHasNoPerturbation;
    procedure TestFakeKernelIsAbi3;
    procedure TestAbi2KernelSupportsMandelbrotAndTricornOnly;
    procedure TestFakeKernelBurningShipMatchesDelphi;
  end;

function TestBinFolder: string;
function FakeKernelFileName: string;
function FakeKernelAbi1FileName: string;
function FakeKernelAbi2FileName: string;

const
  // Pointe de l'axe réel, (-2 ; 0) : sur l'axe le Burning Ship se réduit à x² + c, et ce point du bord est exact
  // (orbite 0, -2, 2, 2...). Différent de kBurningShipAntennaX, qui donne une image uniforme à 1e-200.
  kBurningShipDeepTipX = -2;

implementation

const
  kFakeKernelFile = 'FakeKernel.dll';
  kFakeKernelAbi1File = 'FakeKernelAbi1.dll';   // DLL factice compilée avec FAKE_ABI1 (build.sh tests)
  kFakeKernelAbi2File = 'FakeKernelAbi2.dll';   // DLL factice compilée avec FAKE_ABI2 (build.sh tests)
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
  // rangée perturbée : points d'intérêt de TestFractalPerturbation, à la taille de pixel de 1e-12
  kPerturbedMandelbrotX = 0.390797755594254;
  kPerturbedMandelbrotY = -0.230650338697738;
  kPerturbedTricornX = -0.104560602519813;
  kPerturbedTricornY = 0.228469084632435;
  kPerturbedPixelSize = 1e-12;
  kPerturbedRowLength = 1000;
  kPerturbedMaxIter = 10000;
  // rendu profond : c = i, point de Misiurewicz, taille de pixel hors de portée du palier 1
  kDeepCenterX = 0;
  kDeepCenterY = 1;
  kDeepPixelSize = 1e-30;
  kDeepMaxIter = 2000;

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

function FakeKernelAbi1FileName: string;
begin
  Result := TestBinFolder + kFakeKernelAbi1File;
end;

{------------------------------------------------------------------------------}

function FakeKernelAbi2FileName: string;
begin
  Result := TestBinFolder + kFakeKernelAbi2File;
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

// Orbite passée à la DLL, relue en TOrbit : les deux calculs partent des mêmes valeurs arrondies en Double.
function OrbitFromDoubles(const Values: TDoubleOrbit): TOrbit;
var
  I: Integer;
begin
  SetLength(Result, Length(Values) div 2);
  for I := 0 to High(Result) do
  begin
    Result[I].X := Values[2 * I];
    Result[I].Y := Values[2 * I + 1];
  end;
end;

{------------------------------------------------------------------------------}

// La DLL factice calcule par IteratePerturbed : sur les mêmes entrées en Double, résultat identique au bit près.
procedure TTestRustKernel.TestFakeKernelPerturbedMatchesDelphi;
var
  K: TRustKernel;
  Formulas: array[0..1] of TFractalFormula;
  CentersX, CentersY: array[0..1] of TFloat;
  Orbit, RoundedOrbit: TOrbit;
  DoubleOrbit: TDoubleOrbit;
  Values: array[0..kPerturbedRowLength - 1] of Single;
  Words, F, I, OutsideCount: Integer;
  DCX0, DDX, DCX, Z1Y: Double;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  Formulas[0] := TMandelbrotFormula.Create;
  Formulas[1] := TTricornFormula.Create;
  try
    CheckTrue(K.HasPerturbation, K.Status);
    CentersX[0] := kPerturbedMandelbrotX;
    CentersY[0] := kPerturbedMandelbrotY;
    CentersX[1] := kPerturbedTricornX;
    CentersY[1] := kPerturbedTricornY;
    Words := FracWordsForPixelSize(kPerturbedPixelSize);
    DDX := kPerturbedPixelSize;
    DCX0 := -(kPerturbedRowLength div 2) * DDX;
    for F := 0 to High(Formulas) do
    begin
      Formulas[F].MaxIter := kPerturbedMaxIter;
      CheckTrue(ComputeReferenceOrbit(Formulas[F], THighFloat.FromFloat(CentersX[F], Words),
        THighFloat.FromFloat(CentersY[F], Words), nil, Orbit));
      DoubleOrbit := MakeDoubleOrbit(Orbit);
      CheckEquals(2 * Length(Orbit), Length(DoubleOrbit), 'x et y alternés');
      Z1Y := Orbit[1].Y;
      CheckEquals(Z1Y, DoubleOrbit[3], 0, 'Z1.y arrondi en Double');
      RoundedOrbit := OrbitFromDoubles(DoubleOrbit);
      K.ComputeRowPerturbed(Formulas[F], DoubleOrbit, DCX0, DDX, 0, kPerturbedRowLength, @Values[0]);
      OutsideCount := 0;
      for I := 0 to kPerturbedRowLength - 1 do
      begin
        DCX := DCX0 + I * DDX;
        CheckEquals(Formulas[F].IteratePerturbed(RoundedOrbit, Length(RoundedOrbit), DCX, 0), Values[I], 0,
          Format('%s, pixel %d', [Formulas[F].FormulaName, I]));
        if Values[I] >= 0 then
          Inc(OutsideCount);
      end;
      // une ligne toute intérieure ou toute extérieure ne prouverait rien
      CheckTrue((OutsideCount > 0) and (OutsideCount < kPerturbedRowLength),
        Format('%s : %d pixels extérieurs', [Formulas[F].FormulaName, OutsideCount]));
    end;
  finally
    Formulas[1].Free;
    Formulas[0].Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Orbite nulle de PointCount points (Z0 = Z1 = ... = 0), en Double : x et y alternés.
function ZeroDoubleOrbit(PointCount: Integer = kMinOrbitLength): TDoubleOrbit;
var
  I: Integer;
begin
  SetLength(Result, 2 * PointCount);
  for I := 0 to High(Result) do
    Result[I] := 0;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestPerturbedKernelErrorRaises;
var
  K: TRustKernel;
  F: TJuliaFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TJuliaFormula.Create;
  try
    try
      K.ComputeRowPerturbed(F, ZeroDoubleOrbit, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckTrue(Pos('(code 5)', E.Message) > 0, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Une orbite d'un seul point ferait lire Z1 après le premier pas : argument invalide (code 3).
procedure TTestRustKernel.TestPerturbedKernelRejectsOnePointOrbit;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TMandelbrotFormula.Create;
  try
    Values[0] := kRowDX;
    try
      K.ComputeRowPerturbed(F, ZeroDoubleOrbit(kMinOrbitLength - 1), 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckTrue(Pos('(code 3)', E.Message) > 0, E.Message);
    end;
    CheckEquals(kRowDX, Values[0], 0, 'aucun pixel écrit');
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestAbi1KernelHasNoPerturbation;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(FakeKernelAbi1FileName);
  F := TMandelbrotFormula.Create;
  try
    CheckTrue(K.IsAvailable, K.Status);
    CheckFalse(K.HasPerturbation);
    CheckFalse(K.HasPerturbationFor(kKernelMandelbrot));
    CheckTrue(Pos('Delphi', K.Status) > 0, K.Status);
    try
      K.ComputeRowPerturbed(F, ZeroDoubleOrbit, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckTrue(Pos('perturbation', E.Message) > 0, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestFakeKernelIsAbi3;
var
  K: TRustKernel;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  try
    CheckTrue(K.IsAvailable, K.Status);
    CheckTrue(K.HasPerturbationFor(kKernelMandelbrot));
    CheckTrue(K.HasPerturbationFor(kKernelTricorn));
    CheckTrue(K.HasPerturbationFor(kKernelBurningShip));
    CheckFalse(K.HasPerturbationFor(kKernelJulia));
    CheckFalse(K.HasPerturbationFor(kKernelMultibrot));
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestAbi2KernelSupportsMandelbrotAndTricornOnly;
var
  K: TRustKernel;
begin
  K := TRustKernel.Create(FakeKernelAbi2FileName);
  try
    CheckTrue(K.IsAvailable, K.Status);
    CheckTrue(K.HasPerturbation);
    CheckTrue(K.HasPerturbationFor(kKernelMandelbrot));
    CheckTrue(K.HasPerturbationFor(kKernelTricorn));
    CheckFalse(K.HasPerturbationFor(kKernelBurningShip));
    CheckFalse(K.HasPerturbationFor(kKernelJulia));
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Comme TestFakeKernelPerturbedMatchesDelphi, pour le Burning Ship : référence sur la pointe de l'axe réel, rangée
// à cheval sur la pointe (extérieur à gauche, intérieur à droite).
procedure TTestRustKernel.TestFakeKernelBurningShipMatchesDelphi;
var
  K: TRustKernel;
  F: TBurningShipFormula;
  Orbit, RoundedOrbit: TOrbit;
  DoubleOrbit: TDoubleOrbit;
  Values: array[0..kPerturbedRowLength - 1] of Single;
  I, OutsideCount: Integer;
  DCX0, DDX, DCX: Double;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TBurningShipFormula.Create;
  try
    CheckTrue(K.HasPerturbationFor(F.KernelId), K.Status);
    F.MaxIter := kPerturbedMaxIter;
    DDX := kPerturbedPixelSize;
    DCX0 := -(kPerturbedRowLength div 2) * DDX;
    CheckTrue(ComputeReferenceOrbit(F, THighFloat.FromFloat(kBurningShipDeepTipX,
      FracWordsForPixelSize(kPerturbedPixelSize)), THighFloat.FromFloat(0, FracWordsForPixelSize(kPerturbedPixelSize)),
      nil, Orbit));
    DoubleOrbit := MakeDoubleOrbit(Orbit);
    RoundedOrbit := OrbitFromDoubles(DoubleOrbit);
    K.ComputeRowPerturbed(F, DoubleOrbit, DCX0, DDX, 0, kPerturbedRowLength, @Values[0]);
    OutsideCount := 0;
    for I := 0 to kPerturbedRowLength - 1 do
    begin
      DCX := DCX0 + I * DDX;
      CheckEquals(F.IteratePerturbed(RoundedOrbit, Length(RoundedOrbit), DCX, 0), Values[I], 0,
        Format('pixel %d', [I]));
      if Values[I] >= 0 then
        Inc(OutsideCount);
    end;
    CheckTrue((OutsideCount > 0) and (OutsideCount < kPerturbedRowLength),
      Format('%d pixels extérieurs', [OutsideCount]));
  finally
    F.Free;
    K.Free;
  end;
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

{------------------------------------------------------------------------------}

// Rendu profond (perturbation) de c = i en mode Rust : la DLL calcule chaque suite par fk_compute_row_perturbed.
// Le centre n'est pas sur l'axe réel : une erreur de signe sur δc en y retournerait l'image.
procedure TTestRustEngine.CheckDeepRenderAgrees(RustKernel: TRustKernel; MinRatio: Double);
var
  F: TMandelbrotFormula;
  V: TViewport;
  ED, ER: TRenderEngine;
begin
  F := TMandelbrotFormula.Create;
  ED := nil;
  ER := nil;
  try
    F.MaxIter := kDeepMaxIter;
    V := MakeViewport(kDeepCenterX, kDeepCenterY, kDeepPixelSize * kOddWidth, kOddWidth, kOddHeight);
    ED := RenderWith(ekDelphi, nil, F, V, True);
    ER := RenderWith(ekRust, RustKernel, F, V, True);
    CheckTrue(ED.Status.IsPerturbation, 'Delphi : palier 1 au lieu de la perturbation');
    CheckTrue(ER.Status.IsPerturbation, 'Rust : palier 1 au lieu de la perturbation');
    CheckEquals(Ord(ekRust), Ord(ER.Status.Kernel));
    CheckEquals(Ord(ekRust), Ord(ER.ResolveKernel(F, True)));
    CheckEquals('', ER.TakeErrors);
    CheckBuffersAgree(ED.Buffer, ER.Buffer, MinRatio, 'zoom profond');
  finally
    ER.Free;
    ED.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestRustDeepRenderMatchesDelphiWithFakeKernel;
begin
  CheckDeepRenderAgrees(FFake, kFakeMinRatio);
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestAbi1FallsBackToDelphiWhenDeep;
var
  Abi1: TRustKernel;
  F: TMandelbrotFormula;
  E: TRenderEngine;
begin
  Abi1 := TRustKernel.Create(FakeKernelAbi1FileName);
  F := TMandelbrotFormula.Create;
  E := nil;
  try
    CheckTrue(Abi1.IsAvailable, Abi1.Status);
    F.MaxIter := kDeepMaxIter;
    E := RenderWith(ekRust, Abi1, F, MakeViewport(kDeepCenterX, kDeepCenterY, kDeepPixelSize * kOddWidth, kOddWidth,
      kOddHeight), True);
    CheckTrue(E.Status.IsPerturbation, 'palier 1 au lieu de la perturbation');
    CheckEquals(Ord(ekDelphi), Ord(E.Status.Kernel));
    CheckEquals(Ord(ekDelphi), Ord(E.ResolveKernel(F, True)));
    CheckEquals(Ord(ekRust), Ord(E.ResolveKernel(F)));
    CheckEquals('', E.TakeErrors);
  finally
    E.Free;
    F.Free;
    Abi1.Free;
  end;
end;

{------------------------------------------------------------------------------}

// DLL v2 : perturbation pour Mandelbrot et Tricorn seulement. Le Burning Ship profond est calculé en Delphi, le
// Mandelbrot profond reste en Rust.
procedure TTestRustEngine.TestAbi2FallsBackToDelphiForBurningShip;
var
  Abi2: TRustKernel;
  BS: TBurningShipFormula;
  M: TMandelbrotFormula;
  E: TRenderEngine;
begin
  Abi2 := TRustKernel.Create(FakeKernelAbi2FileName);
  BS := TBurningShipFormula.Create;
  M := TMandelbrotFormula.Create;
  E := nil;
  try
    CheckTrue(Abi2.IsAvailable, Abi2.Status);
    BS.MaxIter := kDeepMaxIter;
    M.MaxIter := kDeepMaxIter;
    E := RenderWith(ekRust, Abi2, BS, MakeViewport(kBurningShipDeepTipX, 0, kDeepPixelSize * kOddWidth, kOddWidth,
      kOddHeight), True);
    CheckTrue(E.Status.IsComplete, 'rendu incomplet');
    CheckTrue(E.Status.IsPerturbation, 'palier 1 au lieu de la perturbation');
    CheckEquals(Ord(ekDelphi), Ord(E.Status.Kernel));
    CheckEquals(Ord(ekDelphi), Ord(E.ResolveKernel(BS, True)));
    CheckEquals('', E.TakeErrors);
    FreeAndNil(E);
    E := RenderWith(ekRust, Abi2, M, MakeViewport(kDeepCenterX, kDeepCenterY, kDeepPixelSize * kOddWidth, kOddWidth,
      kOddHeight), True);
    CheckTrue(E.Status.IsPerturbation, 'palier 1 au lieu de la perturbation');
    CheckEquals(Ord(ekRust), Ord(E.Status.Kernel));
    CheckEquals(Ord(ekRust), Ord(E.ResolveKernel(M, True)));
    CheckEquals('', E.TakeErrors);
  finally
    E.Free;
    M.Free;
    BS.Free;
    Abi2.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustEngine.TestRealKernelPerturbedMatchesDelphi;
var
  RealKernel: TRustKernel;
begin
  if not FileExists(TestBinFolder + kRustKernelFileName) then
  begin
    Status('fractal_kernel.dll absente de bin\ : zoom profond du vrai moteur Rust non comparé.');
    Exit;
  end;
  RealKernel := TRustKernel.Create(TestBinFolder + kRustKernelFileName);
  try
    CheckTrue(RealKernel.IsAvailable, RealKernel.Status);
    if not RealKernel.HasPerturbation then
    begin
      Status('fractal_kernel.dll en version 1, sans fk_compute_row_perturbed : zoom profond non comparé.');
      Exit;
    end;
    CheckDeepRenderAgrees(RealKernel, kRealMinRatio);
  finally
    RealKernel.Free;
  end;
end;

initialization
  RegisterTest(TTestRustKernel.Suite);
  RegisterTest(TTestRustEngine.Suite);

end.
