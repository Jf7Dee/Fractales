unit TestFractalBla;

interface

uses
  TestFramework, Fractal.Types, Fractal.HighFloat, Fractal.Formulas, Fractal.Bla, Fractal.Perturbation,
  TestFractalPerturbation;

type
  TTestBla = class(TTestCase)
  private
    function SmallOrbit(Length: Integer): TOrbit;
    function EntryOffset(const T: TBlaTable; Level, Index: Integer): Integer;
    procedure CheckBlaAgrees(Formula: TFractalFormula; const TextX, TextY: string; Width: TFloat;
      const Msg: string);
  published
    procedure TestBlaLevelZeroMandelbrot;
    procedure TestBlaMergeMatchesTwoSteps;
    procedure TestBlaRadiusIsMin;
    procedure TestBlaMultibrotCoefficient;
    procedure TestBlaJuliaHasNoB;
    procedure TestBlaUnsupportedIsEmpty;
    procedure TestBlaShortOrbitIsEmpty;
    procedure TestBlaLevelLayout;
    procedure TestBlaMandelbrotAgrees;
    procedure TestBlaMultibrot3Agrees;
    procedure TestBlaMultibrot10Agrees;
    procedure TestBlaJuliaAgrees;
    procedure TestBlaEmptyTableIsExact;
    procedure TestBlaKeepsInside;
    procedure TestBlaShortOrbit;
    procedure TestBlaReferencePixel;
  end;

implementation

uses
  Windows, SysUtils, Math;

const
  kOrbitLength = 1100;   // au-dessus de kBlaMinOrbitLength
  kGridWidth = 64;
  kGridHeight = 36;
  kMinCloseShare = 0.99;       // part des pixels extérieurs dont la valeur lissée est à kMaxSmoothGap près
  kMaxSmoothGap = 1e-2;
  kMinVerdictShare = 0.999;    // part des pixels de même verdict intérieur / extérieur
  // MandelBrot-EdgeAndPoint.fscn de JF, étape à 2,7e-21
  kMandelEdgeX = '-1.269244456763666571610919100892510106196634760814933921635132653005868275724498099';
  kMandelEdgeY = '0.414615855565136680422778953557587126819279394093401979516945263145456585974080602';
  kMandelEdgeWidth = 2.72673885671193503E-21;
  kMandelEdgeMaxIter = 5000;
  // MultiBroth_1.fscn de JF, première étape (environ 40 000 itérations par pixel)
  kMultiBroth1X = '0.6436032989752984374817305594833887051524012044957825545579532636106783601909397218300741567511592';
  kMultiBroth1Y = '0.3192585403317653763008687900976260312288946415772095488687299432276187153103164694680194451662740';
  kMultiBroth1Width = 2.33279729810509063E-55;
  kMultiBroth1MaxIter = 41477;
  // Multibrot 10 et Julia : juste au-delà de kBlaMinOrbitLength pour avoir une table. Les bords de
  // TestFractalPerturbation ne conviennent pas : celui de Multibrot 10 est la ligne « échappe à 500 itérations »
  // (au pixel 1e-12 et moins, tout s'y échappe vers 500), et la Julia de c par défaut est une poussière (tout s'échappe)
  kDeepMaxIter = 1100;
  kMultibrot10PixelSize = 1e-8;   // une bonne part des points y tient 1100 itérations
  // Julia connexe (lapin de Douady, c = -0,12 + 0,75i) : un vrai intérieur, donc une référence qui ne s'échappe pas
  kRabbitCX = -0.12;
  kRabbitCY = 0.75;
  kRabbitWidth = 1.6;

{------------------------------------------------------------------------------}

// Orbite de test : Z0 = 0, Z1 = (0.5, 0.25), puis de petits points variés
function TTestBla.SmallOrbit(Length: Integer): TOrbit;
var
  I: Integer;
begin
  SetLength(Result, Length);
  Result[0].X := 0;
  Result[0].Y := 0;
  Result[1].X := 0.5;
  Result[1].Y := 0.25;
  for I := 2 to Length - 1 do
  begin
    Result[I].X := 0.3 * Cos(I);
    Result[I].Y := 0.3 * Sin(I);
  end;
end;

{------------------------------------------------------------------------------}

function TTestBla.EntryOffset(const T: TBlaTable; Level, Index: Integer): Integer;
begin
  Result := (BlaLevelStart(T.Steps, Level) + Index) * kBlaEntrySize;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaLevelZeroMandelbrot;
var
  F: TFractalFormula;
  T: TBlaTable;
  O: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    T := BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-20);
    CheckEquals(kOrbitLength - 1, T.Steps, 'pas');
    O := EntryOffset(T, 0, 0);
    CheckEquals(1, T.Data[O + 0], 1e-15, 'AX');
    CheckEquals(0.5, T.Data[O + 1], 1e-15, 'AY');
    CheckEquals(1, T.Data[O + 2], 0, 'BX');
    CheckEquals(0, T.Data[O + 3], 0, 'BY');
    Check(T.Data[O + 4] > 0, 'R');
    CheckEquals(1, T.Data[O + 5], 0, 'Len');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// δ' = A·δ + B·δc : deux entrées de niveau 0 appliquées l'une après l'autre = l'entrée de niveau 1
procedure TTestBla.TestBlaMergeMatchesTwoSteps;
var
  F: TFractalFormula;
  T: TBlaTable;
  DX, DY, NX, NY, MX, MY: Double;
  O, K: Integer;
const
  DCX = 3e-13;
  DCY = 0;
begin
  F := TMandelbrotFormula.Create;
  try
    T := BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-12);
    DX := 1e-12;
    DY := 2e-12;
    for K := 0 to 1 do
    begin
      O := EntryOffset(T, 0, K);
      NX := T.Data[O] * DX - T.Data[O + 1] * DY + T.Data[O + 2] * DCX - T.Data[O + 3] * DCY;
      NY := T.Data[O] * DY + T.Data[O + 1] * DX + T.Data[O + 2] * DCY + T.Data[O + 3] * DCX;
      DX := NX;
      DY := NY;
    end;
    O := EntryOffset(T, 1, 0);
    CheckEquals(2, T.Data[O + 5], 0, 'Len');
    MX := T.Data[O] * 1e-12 - T.Data[O + 1] * 2e-12 + T.Data[O + 2] * DCX - T.Data[O + 3] * DCY;
    MY := T.Data[O] * 2e-12 + T.Data[O + 1] * 1e-12 + T.Data[O + 2] * DCY + T.Data[O + 3] * DCX;
    CheckEquals(DX, MX, 1e-24, 'X');
    CheckEquals(DY, MY, 1e-24, 'Y');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaRadiusIsMin;
var
  F: TFractalFormula;
  T: TBlaTable;
begin
  F := TMandelbrotFormula.Create;
  try
    T := BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-20);
    Check(T.Data[EntryOffset(T, 1, 0) + 4] <= T.Data[EntryOffset(T, 0, 0) + 4], 'R fusionné <= Rx');
    Check(T.Data[EntryOffset(T, 2, 0) + 4] <= T.Data[EntryOffset(T, 1, 0) + 4], 'niveau 2 <= niveau 1');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// A = 3·Z² pour Z = (0.5, 0.25) : Z² = (0.1875, 0.25)
procedure TTestBla.TestBlaMultibrotCoefficient;
var
  F: TFractalFormula;
  T: TBlaTable;
  O: Integer;
begin
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 3);
    T := BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-20);
    O := EntryOffset(T, 0, 0);
    CheckEquals(0.5625, T.Data[O], 1e-15, 'AX');
    CheckEquals(0.75, T.Data[O + 1], 1e-15, 'AY');
    CheckEquals(1, T.Data[O + 2], 0, 'BX');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaJuliaHasNoB;
var
  F: TFractalFormula;
  T: TBlaTable;
  O: Integer;
begin
  F := TJuliaFormula.Create;
  try
    T := BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 0);
    O := EntryOffset(T, 0, 0);
    CheckEquals(1, T.Data[O], 1e-15, 'AX');
    CheckEquals(0, T.Data[O + 2], 0, 'BX');
    CheckEquals(0, T.Data[O + 3], 0, 'BY');
    Check((T.Data[O + 4] > 0) and not IsInfinite(T.Data[O + 4]) and not IsNan(T.Data[O + 4]), 'R fini');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaUnsupportedIsEmpty;
var
  F: TFractalFormula;
begin
  F := TBurningShipFormula.Create;
  try
    CheckFalse(F.IsBlaSupported, 'Burning Ship');
    CheckEquals(0, Length(BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-20).Data), 'Burning Ship');
  finally
    F.Free;
  end;
  F := TTricornFormula.Create;
  try
    CheckEquals(0, Length(BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-20).Data), 'Tricorn');
  finally
    F.Free;
  end;
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 2.5);
    CheckFalse(F.IsBlaSupported, 'Multibrot 2,5');
    CheckEquals(0, Length(BuildBlaTable(F, SmallOrbit(kOrbitLength), kOrbitLength, 1e-20).Data), 'Multibrot 2,5');
    F.SetParam(0, 3);
    CheckTrue(F.IsBlaSupported, 'Multibrot 3');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaShortOrbitIsEmpty;
var
  F: TFractalFormula;
begin
  F := TMandelbrotFormula.Create;
  try
    CheckEquals(0, Length(BuildBlaTable(F, SmallOrbit(1000), 1000, 1e-20).Data));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaLevelLayout;
var
  F: TFractalFormula;
  T: TBlaTable;
  Steps: Integer;
begin
  CheckEquals(4, BlaLevelCount(5), 'niveaux');
  CheckEquals(5, BlaLevelEntries(5, 0), 'niveau 0');
  CheckEquals(3, BlaLevelEntries(5, 1), 'niveau 1');
  CheckEquals(2, BlaLevelEntries(5, 2), 'niveau 2');
  CheckEquals(1, BlaLevelEntries(5, 3), 'niveau 3');
  CheckEquals(8, BlaLevelStart(5, 2), 'début du niveau 2');
  // nombre impair de pas : la dernière entrée du niveau 1 ne couvre qu'un pas
  F := TMandelbrotFormula.Create;
  try
    T := BuildBlaTable(F, SmallOrbit(1026), 1026, 1e-20);
    Steps := T.Steps;
    CheckEquals(1025, Steps);
    CheckEquals(BlaLevelCount(Steps), T.LevelCount, 'LevelCount');
    CheckEquals(1, T.Data[EntryOffset(T, 1, BlaLevelEntries(Steps, 1) - 1) + 5], 0, 'Len tronqué');
    CheckEquals(Steps, T.Data[EntryOffset(T, T.LevelCount - 1, 0) + 5], 0, 'Len du dernier niveau');
    CheckEquals((BlaLevelStart(Steps, T.LevelCount - 1) + 1) * kBlaEntrySize, Length(T.Data), 'taille');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Grille kGridWidth x kGridHeight sur la vue : même résultat, aux seuils près, avec et sans BLA ; la table doit
// exister (sinon le test ne prouverait rien)
procedure TTestBla.CheckBlaAgrees(Formula: TFractalFormula; const TextX, TextY: string; Width: TFloat;
  const Msg: string);
var
  V: TViewport;
  Orbit, Critical: TOrbit;
  Table, CriticalTable: TBlaTable;
  P: TComplexPoint;
  X, Y, Exterior, Close, SameVerdict, Candidate: Integer;
  RefX, RefY: THighFloat;
  RefDX, RefDY: TFloat;
  Plain, Bla: Single;
  T0, PlainMs, BlaMs: Cardinal;
begin
  V := MakeExactViewport(TextX, TextY, Width, kGridWidth, kGridHeight);
  Critical := nil;
  if Formula.HasPixelStart then
    CheckTrue(ComputeCriticalOrbit(Formula, V.ExactCenterX.FracWords, nil, Critical), Msg + ' : orbite critique');
  // comme le moteur : le centre, sinon le premier point d'une grille 5 x 5 de la vue dont l'orbite ne s'échappe pas
  Candidate := -1;
  repeat
    if Candidate < 0 then
    begin
      RefDX := 0;
      RefDY := 0;
    end
    else
    begin
      RefDX := ((Candidate mod 5) - 2) / 6 * V.Width;
      RefDY := ((Candidate div 5) - 2) / 6 * V.Height;
    end;
    RefX := V.ExactCenterX.AddFloat(RefDX, V.ExactCenterX.FracWords);
    RefY := V.ExactCenterY.AddFloat(RefDY, V.ExactCenterY.FracWords);
    CheckTrue(ComputeReferenceOrbit(Formula, RefX, RefY, nil, Orbit), Msg + ' : orbite');
    Inc(Candidate);
  until (Length(Orbit) > Formula.MaxIter) or (Candidate >= 25);
  if Formula.HasPixelStart then
    Table := BuildBlaTable(Formula, Orbit, Length(Orbit), 0)
  else
    Table := BuildBlaTable(Formula, Orbit, Length(Orbit), Hypot(RefDX, RefDY) + 0.5 * Hypot(V.Width, V.Height));
  CriticalTable := BuildBlaTable(Formula, Critical, Length(Critical), 0);
  CheckTrue(Length(Table.Data) > 0, Msg + ' : table vide (orbite de ' + IntToStr(Length(Orbit)) + ' points)');
  Exterior := 0;
  Close := 0;
  SameVerdict := 0;
  PlainMs := 0;
  BlaMs := 0;
  for Y := 0 to kGridHeight - 1 do
    for X := 0 to kGridWidth - 1 do
    begin
      P := V.PixelOffset(X, Y);
      P.X := P.X - RefDX;
      P.Y := P.Y - RefDY;
      T0 := GetTickCount;
      Plain := Formula.IteratePerturbedCritical(Orbit, Length(Orbit), Critical, Length(Critical), P.X, P.Y);
      Inc(PlainMs, GetTickCount - T0);
      T0 := GetTickCount;
      Bla := Formula.IteratePerturbedCriticalBla(Orbit, Length(Orbit), Table, Critical, Length(Critical),
        CriticalTable, P.X, P.Y);
      Inc(BlaMs, GetTickCount - T0);
      if (Plain < 0) = (Bla < 0) then
        Inc(SameVerdict);
      if (Plain >= 0) and (Bla >= 0) then
      begin
        Inc(Exterior);
        if Abs(Plain - Bla) <= kMaxSmoothGap then
          Inc(Close);
      end;
    end;
  Status(Format('%s : %d ms sans BLA, %d ms avec ; %d extérieurs, %d proches, %d verdicts identiques sur %d',
    [Msg, PlainMs, BlaMs, Exterior, Close, SameVerdict, kGridWidth * kGridHeight]));
  CheckTrue(SameVerdict >= kMinVerdictShare * kGridWidth * kGridHeight,
    Format('%s : %d verdicts identiques sur %d', [Msg, SameVerdict, kGridWidth * kGridHeight]));
  CheckTrue(Close >= kMinCloseShare * Exterior, Format('%s : %d proches sur %d extérieurs', [Msg, Close, Exterior]));
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaMandelbrotAgrees;
var
  F: TFractalFormula;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kMandelEdgeMaxIter;
    CheckBlaAgrees(F, kMandelEdgeX, kMandelEdgeY, kMandelEdgeWidth, 'Mandelbrot 2,7e-21');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaMultibrot3Agrees;
var
  F: TFractalFormula;
begin
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 3);
    F.MaxIter := kMultiBroth1MaxIter;
    CheckBlaAgrees(F, kMultiBroth1X, kMultiBroth1Y, kMultiBroth1Width, 'MultiBroth_1 2,33e-55');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaMultibrot10Agrees;
var
  F: TFractalFormula;
begin
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 10);
    F.MaxIter := kDeepMaxIter;
    CheckBlaAgrees(F, kMultibrot10X, kMultibrot10Y, kMultibrot10PixelSize * kGridWidth, 'Multibrot 10 au pixel 1e-8');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBla.TestBlaJuliaAgrees;
var
  F: TFractalFormula;
begin
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    F.SetParam(0, kRabbitCX);
    F.SetParam(1, kRabbitCY);
    CheckBlaAgrees(F, '0', '0', kRabbitWidth, 'Julia lapin');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// table vide : exactement le calcul sans BLA
procedure TTestBla.TestBlaEmptyTableIsExact;
var
  F: TFractalFormula;
  V: TViewport;
  Orbit: TOrbit;
  Empty: TBlaTable;
  P: TComplexPoint;
  X: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kMandelEdgeMaxIter;
    V := MakeExactViewport(kMandelEdgeX, kMandelEdgeY, kMandelEdgeWidth, kGridWidth, kGridHeight);
    CheckTrue(ComputeReferenceOrbit(F, V.ExactCenterX, V.ExactCenterY, nil, Orbit));
    Empty.Data := nil;
    Empty.Steps := 0;
    Empty.LevelCount := 0;
    for X := 0 to kGridWidth - 1 do
    begin
      P := V.PixelOffset(X, 7);
      CheckEquals(F.IteratePerturbed(Orbit, Length(Orbit), P.X, P.Y),
        F.IteratePerturbedBla(Orbit, Length(Orbit), Empty, P.X, P.Y), 0, 'pixel ' + IntToStr(X));
    end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// un pixel qui ne s'échappe pas avant MaxIter reste intérieur : aucun saut ne dépasse MaxIter
procedure TTestBla.TestBlaKeepsInside;
var
  F: TFractalFormula;
  CX, CY: THighFloat;
  Orbit: TOrbit;
  Table: TBlaTable;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 3001;
    CheckTrue(THighFloat.TryParse('-0.1', 4, CX) and THighFloat.TryParse('0.1', 4, CY));
    CheckTrue(ComputeReferenceOrbit(F, CX, CY, nil, Orbit));
    Table := BuildBlaTable(F, Orbit, Length(Orbit), 1e-10);
    CheckTrue(Length(Table.Data) > 0, 'table');
    CheckEquals(kInside, F.IteratePerturbedBla(Orbit, Length(Orbit), Table, 1e-10, 0), 0, 'proche');
    CheckEquals(kInside, F.IteratePerturbedBla(Orbit, Length(Orbit), Table, 0, 0), 0, 'référence');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// référence qui s'échappe tôt (orbite courte tronquée par le rebasage) : les sauts ne passent jamais la fin
procedure TTestBla.TestBlaShortOrbit;
var
  F: TFractalFormula;
  CX, CY: THighFloat;
  Orbit: TOrbit;
  Table: TBlaTable;
  Plain, Bla: Single;
  I: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 3001;
    // intérieur de la cardioïde : orbite pleine, puis tronquée à kBlaMinOrbitLength + 5 points
    CheckTrue(THighFloat.TryParse('-0.1', 4, CX) and THighFloat.TryParse('0.1', 4, CY));
    CheckTrue(ComputeReferenceOrbit(F, CX, CY, nil, Orbit));
    SetLength(Orbit, kBlaMinOrbitLength + 5);
    Table := BuildBlaTable(F, Orbit, Length(Orbit), 1e-6);
    CheckTrue(Length(Table.Data) > 0, 'table');
    for I := 0 to 20 do
    begin
      Plain := F.IteratePerturbed(Orbit, Length(Orbit), 1e-7 * I, 3e-8 * I);
      Bla := F.IteratePerturbedBla(Orbit, Length(Orbit), Table, 1e-7 * I, 3e-8 * I);
      CheckEquals(Plain < 0, Bla < 0, 'verdict ' + IntToStr(I));
      if Plain >= 0 then
        CheckEquals(Plain, Bla, kMaxSmoothGap, 'valeur ' + IntToStr(I));
    end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// pixel de la référence (δc = 0) : pas de division par zéro, même résultat
procedure TTestBla.TestBlaReferencePixel;
var
  F: TFractalFormula;
  V: TViewport;
  Orbit: TOrbit;
  Table: TBlaTable;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kMandelEdgeMaxIter;
    V := MakeExactViewport(kMandelEdgeX, kMandelEdgeY, kMandelEdgeWidth, kGridWidth, kGridHeight);
    CheckTrue(ComputeReferenceOrbit(F, V.ExactCenterX, V.ExactCenterY, nil, Orbit));
    Table := BuildBlaTable(F, Orbit, Length(Orbit), 0);
    CheckEquals(F.IteratePerturbed(Orbit, Length(Orbit), 0, 0),
      F.IteratePerturbedBla(Orbit, Length(Orbit), Table, 0, 0), kMaxSmoothGap);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TTestBla.Suite);

end.
