unit TestFractalPerturbation;

interface

uses
  TestFramework, Fractal.HighFloat, Fractal.Types, Fractal.Formulas, Fractal.Perturbation;

const
  // Lieux partagés avec TestFractalEngine et TestFractalRustKernel (Burning Ship, axe et favori de JF).
  // Antenne : cx trouvé hors ligne par bissection (60 pas, MaxIter 10000, Extended, vue 200 x 150 au pixel 1e-12,
  // cy = 0) entre un point 100 % extérieur (-1,8) et un point 0 % extérieur (-1,775) : environ 50 % de pixels
  // extérieurs sur la sous-grille.
  kBurningShipAntennaX = -1.78802612188722658;
  // Favori BurningShip_O_x1.5e14_20261024-1100.frac
  kBurningShipFavouriteCenterX = '-1.97764332392038208691244765792158434937619029395172813310368221039931841';
  kBurningShipFavouriteCenterY = '0.00000040943449145950818875937261165274938022740420622961170582366426700';
  kBurningShipFavouriteWidth = 2.69976921794239817E-14;
  kBurningShipFavouriteMaxIter = 6388;   // itérations du fichier favori de JF
  // Point du bord près de l'axe : le centre de JF est à 100 % extérieur à sa largeur, donc on cherche le bord sur la
  // verticale qui descend de ce centre vers l'axe. Bissection exacte (THighFloat, 100 pas, MaxIter
  // kBurningShipBorderMaxIter) entre un point intérieur (cy du favori x 5/60) et un point extérieur (x 7/60), cx
  // inchangé. Avec MaxIter 10000 le bord est mal conditionné : la vérité à 192 bits et à 320 bits diverge dès 3000
  // itérations et l'Extended ne suit plus dès 1000 ; d'où ce MaxIter bas. Environ 55 % de pixels extérieurs, au pixel
  // 1e-16 comme 10^6 fois plus fin.
  kBurningShipBorderX = kBurningShipFavouriteCenterX;
  kBurningShipBorderY = '0.00000004159599724145695425193358193503';
  kBurningShipBorderMaxIter = 300;
  // Bord du corps du navire, hors de l'axe (|X·Y| de la référence grand devant δ) : bissection exacte (THighFloat,
  // 120 pas, MaxIter kBurningShipBodyMaxIter) du segment (-0,5 ; 0,5) intérieur vers (-1 ; 0,75) extérieur. Avec 300
  // itérations la vue ne concorde qu'à 88 % (orbites trop sensibles pour l'Extended) ; 150 est sûr. Vue au
  // pixel 1e-27 : l'Extended naïf |c + d| - |c| y perd tout δ (2^-64 de |c| ~ 1e-20 >> δ·X ~ 1e-27).
  kBurningShipBodyX = '-0.868566310663065831244242013278299537360098976';
  kBurningShipBodyY = '0.684283155331532915622121006639149768680049488';
  kBurningShipBodyMaxIter = 150;
  kBurningShipBodyPixelSize = 1e-27;

type
  // Un pas direct (Extended) de l'itération d'une formule, pour comparer l'orbite de référence à Iterate.
  TDirectStep = reference to procedure(var X, Y: TFloat);

  // Valeurs de référence « exactes » (THighFloat) sur une sous-grille régulière de la vue.
  TGroundTruth = record
    FormulaName: string;
    View: TViewport;
    MaxIter: Integer;
    Values: array of Single;   // kInside ou valeur lissée, ligne par ligne
  end;

  TTestPerturbation = class(TTestCase)
  private
    function MakeScene(CenterX, CenterY: TFloat): TViewport;
    function MakeExactScene(const TextX, TextY: string; Width: TFloat): TViewport;
    function TruthFor(Formula: TFractalFormula; const V: TViewport): TGroundTruth;
    // IsMixRequired : exige 10 à 90 % de pixels extérieurs (sinon le test ne prouve rien) ; False pour une vue
    // volontairement toute extérieure, où les valeurs lissées restent comparées à kSmoothTolerance.
    function Concordance(Formula: TFractalFormula; const V: TViewport; ShiftX: TFloat; AMaxIter: Integer;
      const ViewLabel: string; IsMixRequired: Boolean): Double;
    procedure CheckConcordance(Formula: TFractalFormula; CenterX, CenterY, ShiftX: TFloat); overload;
    procedure CheckConcordance(Formula: TFractalFormula; const V: TViewport; ShiftX: TFloat; AMaxIter: Integer;
      const ViewLabel: string; IsMixRequired: Boolean); overload;
    procedure CheckReferenceOrbit(Formula: TFractalFormula; RefX, RefY: TFloat; DirectStep: TDirectStep);
  published
    procedure TestSupportsPerturbation;
    procedure TestDiffAbs;
    procedure TestReferenceOrbitMatchesIterate;
    procedure TestBurningShipReferenceMatchesIterate;
    procedure TestBurningShipAxisMatchesExact;
    procedure TestBurningShipFavouriteMatchesExact;
    procedure TestBurningShipNearAxisBorderMatchesExact;
    procedure TestBurningShipDeepBodyMatchesExact;
    procedure TestPerturbedMatchesDirect;
    procedure TestReferenceEscapingEarlyStillMatches;
    procedure TestReferenceOrbitCancels;
    procedure TestUnsupportedFormulaRaises;
    procedure TestOnePointOrbitRaises;
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
  // 256 bits : le pixel le plus fin utilisé est 1e-27 (~90 bits), et le chaos des orbites en consomme encore
  kTruthFracWords = 8;
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

// Vue 200 x 150 de largeur Width, centrée sur les chaînes décimales exactes (lues par THighFloat.TryParse).
function TTestPerturbation.MakeExactScene(const TextX, TextY: string; Width: TFloat): TViewport;
var
  X, Y: THighFloat;
  Words: Integer;
begin
  Result := MakeViewport(0, 0, Width, kViewWidth, kViewHeight);
  Words := FracWordsForPixelSize(Result.PixelSize);
  Check(THighFloat.TryParse(TextX, Words, X), 'centre X lisible');
  Check(THighFloat.TryParse(TextY, Words, Y), 'centre Y lisible');
  Result.SetCenter(X, Y);
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
    if (TruthCache[I].FormulaName = Formula.FormulaName) and TruthCache[I].View.IsSameView(V)
      and (TruthCache[I].MaxIter = Formula.MaxIter) then
      Exit(TruthCache[I]);
  Result.FormulaName := Formula.FormulaName;
  Result.View := V;
  Result.MaxIter := Formula.MaxIter;
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
function TTestPerturbation.Concordance(Formula: TFractalFormula; const V: TViewport; ShiftX: TFloat;
  AMaxIter: Integer; const ViewLabel: string; IsMixRequired: Boolean): Double;
var
  Orbit: TOrbit;
  Truth: TGroundTruth;
  RefX: THighFloat;
  X, Y, Index, Agree, EscapeCount: Integer;
  Offset: TComplexPoint;
  Perturbed: Single;
  IsSame: Boolean;
begin
  Formula.MaxIter := AMaxIter;
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
  Status(Format('%s [%s], décalage %g : %d pixels, extérieur %.1f %%, concordance %.2f %%',
    [Formula.FormulaName, ViewLabel, ShiftX, Index, 100 * EscapeCount / Index, 100 * Agree / Index]));
  if IsMixRequired then
  begin
    Check(EscapeCount >= kMinEscapeFraction * Index, 'trop peu de pixels extérieurs : test sans valeur');
    Check(EscapeCount <= kMaxEscapeFraction * Index, 'trop peu de pixels intérieurs : test sans valeur');
  end;
  Result := Agree / Index;
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.CheckConcordance(Formula: TFractalFormula; CenterX, CenterY, ShiftX: TFloat);
begin
  CheckConcordance(Formula, MakeScene(CenterX, CenterY), ShiftX, kTestMaxIter,
    Format('pixel %g, centre %g ; %g', [kPixelSize, CenterX, CenterY]), True);
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.CheckConcordance(Formula: TFractalFormula; const V: TViewport; ShiftX: TFloat;
  AMaxIter: Integer; const ViewLabel: string; IsMixRequired: Boolean);
var
  Ratio: Double;
begin
  try
    Ratio := Concordance(Formula, V, ShiftX, AMaxIter, ViewLabel, IsMixRequired);
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
  Check(TBurningShipFormula.SupportsPerturbation, 'Burning Ship');
  Check(not TJuliaFormula.SupportsPerturbation, 'Julia');
  Check(not TFractalFormula.SupportsPerturbation, 'base');
end;

{------------------------------------------------------------------------------}

// Les quatre cas du tableau de la spec (valeurs exactes en binaire), les bornes, et c ~ 1 avec d minuscule.
procedure TTestPerturbation.TestDiffAbs;
const
  kTiny = 1e-300;
begin
  CheckEquals(1, DiffAbs(3, 1), 'c >= 0, c + d >= 0 : d');
  CheckEquals(-1, DiffAbs(3, -5), 'c >= 0, c + d < 0 : -(2c + d)');
  CheckEquals(-1, DiffAbs(-3, 5), 'c < 0, c + d > 0 : 2c + d');
  CheckEquals(-1, DiffAbs(-3, 1), 'c < 0, c + d <= 0 : -d');
  CheckEquals(2, DiffAbs(0, -2), 'c = 0, d < 0');
  CheckEquals(2, DiffAbs(0, 2), 'c = 0, d > 0');
  CheckEquals(-2, DiffAbs(2, -2), 'c + d = 0, c > 0');
  CheckEquals(-2, DiffAbs(-2, 2), 'c + d = 0, c < 0');
  Check(DiffAbs(1, kTiny) = kTiny, 'c ~ 1, d ~ 1e-300 : d exactement');
end;

{------------------------------------------------------------------------------}

// Orbite de référence de (RefX, RefY) comparée à l'itération directe : longueur, Z0 = 0 et dernier point échappé.
// DirectStep fait un pas de la formule en Extended. Le point doit échapper vite, avant que le chaos de l'orbite ne
// sépare l'Extended de la haute précision.
procedure TTestPerturbation.CheckReferenceOrbit(Formula: TFractalFormula; RefX, RefY: TFloat; DirectStep: TDirectStep);
var
  Orbit: TOrbit;
  X, Y, LastR2: TFloat;
  N: Integer;
begin
  Check(Assigned(DirectStep), 'pas direct absent');
  Formula.MaxIter := kTestMaxIter;
  Check(ComputeReferenceOrbit(Formula, THighFloat.FromFloat(RefX, kOrbitFracWords),
    THighFloat.FromFloat(RefY, kOrbitFracWords),
    function: Boolean
    begin
      Result := False;
    end, Orbit), 'orbite');
  Check(Formula.Iterate(RefX, RefY) >= 0, 'le point doit échapper');
  X := 0;
  Y := 0;
  N := 0;
  while (N < Formula.MaxIter) and (X * X + Y * Y <= kEscapeRadius2) do
  begin
    DirectStep(X, Y);
    Inc(N);
  end;
  LastR2 := Sqr(Orbit[High(Orbit)].X) + Sqr(Orbit[High(Orbit)].Y);
  CheckEquals(N + 1, Length(Orbit), 'longueur');
  CheckEquals(0, Orbit[0].X, 'Z0.X');
  CheckEquals(0, Orbit[0].Y, 'Z0.Y');
  Check(Abs(LastR2 - (X * X + Y * Y)) <= kRelativeTolerance * LastR2, 'dernier |Z|2');
  Check(LastR2 > kEscapeRadius2, 'le dernier point échappe');
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestReferenceOrbitMatchesIterate;
const
  kRefX = -0.75;
  kRefY = 0.1;
var
  F: TFractalFormula;
begin
  F := TMandelbrotFormula.Create;
  try
    CheckReferenceOrbit(F, kRefX, kRefY,
      procedure(var X, Y: TFloat)
      var
        X2, Y2: TFloat;
      begin
        X2 := X * X;
        Y2 := Y * Y;
        Y := 2 * X * Y + kRefY;
        X := X2 - Y2 + kRefX;
      end);
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPerturbation.TestBurningShipReferenceMatchesIterate;
const
  kRefX = -1.0;
  kRefY = 0.75;   // s'échappe en une douzaine d'itérations
var
  F: TFractalFormula;
begin
  F := TBurningShipFormula.Create;
  try
    CheckReferenceOrbit(F, kRefX, kRefY,
      procedure(var X, Y: TFloat)
      var
        X2, Y2: TFloat;
      begin
        X2 := X * X;
        Y2 := Y * Y;
        Y := 2 * Abs(X * Y) - kRefY;
        X := X2 - Y2 + kRefX;
      end);
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue centrée exactement sur l'axe (cy = 0) : des pixels de part et d'autre du pli |x·y|.
// cx = kBurningShipAntennaX ; fraction de pixels extérieurs mesurée au journal (Status).
procedure TTestPerturbation.TestBurningShipAxisMatchesExact;
begin
  CheckConcordance(TBurningShipFormula.Create, MakeScene(kBurningShipAntennaX, 0), 0, kTestMaxIter, 'axe', True);
end;

{------------------------------------------------------------------------------}

// Lieu d'essai de JF : son centre exact, sa largeur et ses 6388 itérations, puis la même vue 10^6 fois plus étroite.
// Ces vues sont entièrement extérieures (la mixité 10-90 % est donc levée, IsMixRequired = False) : la concordance
// porte sur les valeurs lissées, comparées à kSmoothTolerance.
procedure TTestPerturbation.TestBurningShipFavouriteMatchesExact;
const
  kDeepFactor = 1e-6;
begin
  CheckConcordance(TBurningShipFormula.Create,
    MakeExactScene(kBurningShipFavouriteCenterX, kBurningShipFavouriteCenterY, kBurningShipFavouriteWidth), 0,
    kBurningShipFavouriteMaxIter, 'favori JF', False);
  CheckConcordance(TBurningShipFormula.Create,
    MakeExactScene(kBurningShipFavouriteCenterX, kBurningShipFavouriteCenterY,
      kBurningShipFavouriteWidth * kDeepFactor), 0, kBurningShipFavouriteMaxIter, 'favori JF x 1e-6', False);
end;

{------------------------------------------------------------------------------}

// Bord près de l'axe (voir kBurningShipBorderY) : vue mêlant intérieur et extérieur, à la largeur du favori puis
// 10^6 fois plus étroite.
procedure TTestPerturbation.TestBurningShipNearAxisBorderMatchesExact;
const
  kDeepFactor = 1e-6;
begin
  CheckConcordance(TBurningShipFormula.Create,
    MakeExactScene(kBurningShipBorderX, kBurningShipBorderY, kBurningShipFavouriteWidth), 0,
    kBurningShipBorderMaxIter, 'bord près de l''axe', True);
  CheckConcordance(TBurningShipFormula.Create,
    MakeExactScene(kBurningShipBorderX, kBurningShipBorderY, kBurningShipFavouriteWidth * kDeepFactor), 0,
    kBurningShipBorderMaxIter, 'bord près de l''axe x 1e-6', True);
end;

{------------------------------------------------------------------------------}

// Vue profonde hors de l'axe, où |X·Y| de la référence est grand devant δ : un DiffAbs naïf (|c + d| - |c|) y perd
// tout δ et la concordance s'effondre ; c'est ce test (et non les vues à 1e-12) qui protège la technique de diffabs.
procedure TTestPerturbation.TestBurningShipDeepBodyMatchesExact;
begin
  CheckConcordance(TBurningShipFormula.Create,
    MakeExactScene(kBurningShipBodyX, kBurningShipBodyY, kBurningShipBodyPixelSize * kViewWidth), 0,
    kBurningShipBodyMaxIter, 'corps du navire, pixel 1e-27', True);
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

{------------------------------------------------------------------------------}

// Après le premier pas, IteratePerturbed lit Orbit[1] : une orbite d'un seul point est refusée.
procedure TTestPerturbation.TestOnePointOrbitRaises;
var
  F: TMandelbrotFormula;
  Orbit: TOrbit;
  IsRaised: Boolean;
begin
  F := TMandelbrotFormula.Create;
  try
    SetLength(Orbit, kMinOrbitLength);
    Orbit[0].X := 0;
    Orbit[0].Y := 0;
    Orbit[1] := Orbit[0];
    IsRaised := False;
    try
      F.IteratePerturbed(Orbit, kMinOrbitLength - 1, 0, 0);
    except
      on EArgumentException do
        IsRaised := True;
    end;
    Check(IsRaised, 'IteratePerturbed doit refuser une orbite d''un seul point');
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TTestPerturbation.Suite);

end.
