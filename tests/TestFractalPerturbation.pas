unit TestFractalPerturbation;

interface

uses
  TestFramework, Fractal.HighFloat, Fractal.Types, Fractal.Formulas, Fractal.Perturbation;

type
  // Valeurs de référence « exactes » (THighFloat) sur une sous-grille régulière de la vue.
  TGroundTruth = record
    FormulaName: string;
    Values: array of Single;   // kInside ou valeur lissée, ligne par ligne
  end;

  TTestPerturbation = class(TTestCase)
  private
    function MakeScene(CenterX, CenterY: TFloat): TViewport;
    function TruthFor(Formula: TFractalFormula; const V: TViewport): TGroundTruth;
    function Concordance(Formula: TFractalFormula; CenterX, CenterY, ShiftX: TFloat): Double;
    procedure CheckConcordance(Formula: TFractalFormula; CenterX, CenterY, ShiftX: TFloat);
  published
    procedure TestSupportsPerturbation;
    procedure TestReferenceOrbitMatchesIterate;
    procedure TestPerturbedMatchesDirect;
    procedure TestReferenceEscapingEarlyStillMatches;
    procedure TestReferenceOrbitCancels;
    procedure TestUnsupportedFormulaRaises;
  end;

implementation

uses
  SysUtils, Math;

const
  // Centres trouvés hors ligne par bissection (48 pas, MaxIter 10000, Extended) le long d'un rayon issu de
  // l'origine, entre un point intérieur (0) et un point extérieur (2,5) : Mandelbrot à 5,75 radians, Tricorn à
  // 2 radians. Au pixel 1e-12, chaque vue mêle intérieur et extérieur. Parmi les rayons essayés, on garde ceux où
  // l'Extended reste fiable : avec une référence décalée de 0,3, l'itération perturbée retombe sur de l'Extended
  // pur, qui dérive en profondeur.
  kMandelbrotX = 0.390797755594254;
  kMandelbrotY = -0.230650338697738;
  kTricornX = -0.104560602519813;
  kTricornY = 0.228469084632435;
  kPixelSize = 1e-12;
  kViewWidth = 200;
  kViewHeight = 150;
  kTestMaxIter = 10000;   // les points d'intérêt échappent jusqu'à plusieurs milliers d'itérations
  kSampleStep = 17;       // une sous-grille : la vérité exacte coûte cher
  kTruthFracWords = 6;    // 192 bits, bien au-delà du pixel de 1e-12
  kMinConcordance = 0.98;
  kSmoothTolerance = 1e-3;
  kMinEscapeFraction = 0.1;   // en dessous ou au-dessus, le test ne prouve rien
  kMaxEscapeFraction = 0.9;
  kEarlyShift = 0.3;
  kOrbitFracWords = 8;
  kRelativeTolerance = 1e-9;
  kCancelInterval = 256;
  kLn2 = 0.69314718055994530942;

var
  TruthCache: array of TGroundTruth;

{------------------------------------------------------------------------------}

function TTestPerturbation.MakeScene(CenterX, CenterY: TFloat): TViewport;
begin
  Result := MakeViewport(CenterX, CenterY, kPixelSize * kViewWidth, kViewWidth, kViewHeight);
end;

{------------------------------------------------------------------------------}

// Itération en haute précision du pixel (PX, PY), même convention de compte et de lissage qu'Iterate.
function ExactValue(Formula: TFractalFormula; const V: TViewport; PX, PY: Integer): Single;
var
  Offset: TComplexPoint;
  CX, CY, ZX, ZY: THighFloat;
  N: Integer;
  X, Y, R2, Mu: TFloat;
begin
  Offset := V.PixelOffset(PX, PY);
  CX := V.ExactCenterX.WithFracWords(kTruthFracWords).AddFloat(Offset.X, kTruthFracWords);
  CY := V.ExactCenterY.WithFracWords(kTruthFracWords).AddFloat(Offset.Y, kTruthFracWords);
  ZX := THighFloat.Zero(kTruthFracWords);
  ZY := ZX;
  for N := 0 to Formula.MaxIter - 1 do
  begin
    X := ZX.ToFloat;
    Y := ZY.ToFloat;
    R2 := X * X + Y * Y;
    if R2 > kEscapeRadius2 then
    begin
      Mu := Max(0, N + 1 - Ln(0.5 * Ln(R2)) / kLn2);
      Exit(Mu);
    end;
    Formula.StepReference(ZX, ZY, CX, CY);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

function TTestPerturbation.TruthFor(Formula: TFractalFormula; const V: TViewport): TGroundTruth;
var
  I, X, Y: Integer;
begin
  for I := 0 to High(TruthCache) do
    if TruthCache[I].FormulaName = Formula.FormulaName then
      Exit(TruthCache[I]);
  Result.FormulaName := Formula.FormulaName;
  SetLength(Result.Values, 0);
  Y := 0;
  while Y < kViewHeight do
  begin
    X := 0;
    while X < kViewWidth do
    begin
      SetLength(Result.Values, Length(Result.Values) + 1);
      Result.Values[High(Result.Values)] := ExactValue(Formula, V, X, Y);
      Inc(X, kSampleStep);
    end;
    Inc(Y, kSampleStep);
  end;
  SetLength(TruthCache, Length(TruthCache) + 1);
  TruthCache[High(TruthCache)] := Result;
end;

{------------------------------------------------------------------------------}

// Part des pixels échantillonnés pour lesquels IteratePerturbed concorde avec la vérité exacte (même verdict ;
// valeurs lissées proches si les deux sont à l'extérieur). La référence est au centre décalé de ShiftX.
function TTestPerturbation.Concordance(Formula: TFractalFormula; CenterX, CenterY, ShiftX: TFloat): Double;
var
  V: TViewport;
  Orbit: TOrbit;
  Truth: TGroundTruth;
  RefX: THighFloat;
  X, Y, Index, Agree, EscapeCount: Integer;
  Offset: TComplexPoint;
  Perturbed: Single;
  IsSame: Boolean;
begin
  Formula.MaxIter := kTestMaxIter;
  V := MakeScene(CenterX, CenterY);
  Truth := TruthFor(Formula, V);
  RefX := V.ExactCenterX.AddFloat(ShiftX, V.ExactCenterX.FracWords);
  Check(ComputeReferenceOrbit(Formula, RefX, V.ExactCenterY,
    function: Boolean
    begin
      Result := False;
    end, Orbit), 'orbite de référence');
  Agree := 0;
  EscapeCount := 0;
  Index := 0;
  Y := 0;
  while Y < kViewHeight do
  begin
    X := 0;
    while X < kViewWidth do
    begin
      Offset := V.PixelOffset(X, Y);
      Perturbed := Formula.IteratePerturbed(Orbit, Length(Orbit), Offset.X - ShiftX, Offset.Y);
      IsSame := (Truth.Values[Index] < 0) = (Perturbed < 0);
      if Truth.Values[Index] >= 0 then
      begin
        Inc(EscapeCount);
        if IsSame then
          IsSame := Abs(Truth.Values[Index] - Perturbed) < kSmoothTolerance;
      end;
      if IsSame then
        Inc(Agree);
      Inc(Index);
      Inc(X, kSampleStep);
    end;
    Inc(Y, kSampleStep);
  end;
  Status(Format('%s, décalage %g : %d pixels, extérieur %.1f %%, concordance %.2f %%',
    [Formula.FormulaName, ShiftX, Index, 100 * EscapeCount / Index, 100 * Agree / Index]));
  Check(EscapeCount >= kMinEscapeFraction * Index, 'trop peu de pixels extérieurs : test sans valeur');
  Check(EscapeCount <= kMaxEscapeFraction * Index, 'trop peu de pixels intérieurs : test sans valeur');
  Result := Agree / Index;
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.CheckConcordance(Formula: TFractalFormula; CenterX, CenterY, ShiftX: TFloat);
var
  Ratio: Double;
begin
  try
    Ratio := Concordance(Formula, CenterX, CenterY, ShiftX);
    Check(Ratio >= kMinConcordance, Format('%s : concordance %.4f', [Formula.FormulaName, Ratio]));
  finally
    Formula.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestSupportsPerturbation;
begin
  Check(TMandelbrotFormula.SupportsPerturbation, 'Mandelbrot');
  Check(TTricornFormula.SupportsPerturbation, 'Tricorn');
  Check(not TJuliaFormula.SupportsPerturbation, 'Julia');
  Check(not TFractalFormula.SupportsPerturbation, 'base');
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestReferenceOrbitMatchesIterate;
const
  kRefX = -0.75;
  kRefY = 0.1;
var
  F: TFractalFormula;
  Orbit: TOrbit;
  X, Y, X2, Y2, LastR2: TFloat;
  N: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kTestMaxIter;
    Check(ComputeReferenceOrbit(F, THighFloat.FromFloat(kRefX, kOrbitFracWords),
      THighFloat.FromFloat(kRefY, kOrbitFracWords),
      function: Boolean
      begin
        Result := False;
      end, Orbit), 'orbite');
    Check(F.Iterate(kRefX, kRefY) >= 0, 'le point doit échapper');
    X := 0;
    Y := 0;
    N := 0;
    X2 := 0;
    Y2 := 0;
    while N < F.MaxIter do
    begin
      X2 := X * X;
      Y2 := Y * Y;
      if X2 + Y2 > kEscapeRadius2 then
        Break;
      Y := 2 * X * Y + kRefY;
      X := X2 - Y2 + kRefX;
      Inc(N);
    end;
    LastR2 := Sqr(Orbit[High(Orbit)].X) + Sqr(Orbit[High(Orbit)].Y);
    CheckEquals(N + 1, Length(Orbit), 'longueur');
    CheckEquals(0, Orbit[0].X, 'Z0.X');
    CheckEquals(0, Orbit[0].Y, 'Z0.Y');
    Check(Abs(LastR2 - (X2 + Y2)) <= kRelativeTolerance * LastR2, 'dernier |Z|2');
    Check(LastR2 > kEscapeRadius2, 'le dernier point échappe');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestPerturbedMatchesDirect;
begin
  CheckConcordance(TMandelbrotFormula.Create, kMandelbrotX, kMandelbrotY, 0);
  CheckConcordance(TTricornFormula.Create, kTricornX, kTricornY, 0);
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestReferenceEscapingEarlyStillMatches;
begin
  CheckConcordance(TMandelbrotFormula.Create, kMandelbrotX, kMandelbrotY, kEarlyShift);
  CheckConcordance(TTricornFormula.Create, kTricornX, kTricornY, kEarlyShift);
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestReferenceOrbitCancels;
var
  F: TFractalFormula;
  Orbit: TOrbit;
  Calls: Integer;
  IsDone: Boolean;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kTestMaxIter;
    Calls := 0;
    // le point 0 n'échappe jamais : sans annulation, l'orbite irait jusqu'à MaxIter
    IsDone := ComputeReferenceOrbit(F, THighFloat.Zero(kOrbitFracWords), THighFloat.Zero(kOrbitFracWords),
      function: Boolean
      begin
        Inc(Calls);
        Result := Calls >= 2;
      end, Orbit);
    Check(not IsDone, 'annulée');
    CheckEquals(2, Calls, 'deux vérifications');
    Check(Length(Orbit) <= kCancelInterval + 1, 'moins de 300 itérations');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestUnsupportedFormulaRaises;
var
  F: TFractalFormula;
  ZX, ZY, C: THighFloat;
  IsRaised: Boolean;
begin
  F := TJuliaFormula.Create;
  try
    ZX := THighFloat.Zero(kOrbitFracWords);
    ZY := ZX;
    C := ZX;
    IsRaised := False;
    try
      F.StepReference(ZX, ZY, C, C);
    except
      on Exception do
        IsRaised := True;
    end;
    Check(IsRaised, 'StepReference doit lever une exception');
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TTestPerturbation.Suite);

end.
