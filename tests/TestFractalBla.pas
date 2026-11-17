unit TestFractalBla;

interface

uses
  TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Bla;

type
  TTestBla = class(TTestCase)
  private
    function SmallOrbit(Length: Integer): TOrbit;
    function EntryOffset(const T: TBlaTable; Level, Index: Integer): Integer;
  published
    procedure TestBlaLevelZeroMandelbrot;
    procedure TestBlaMergeMatchesTwoSteps;
    procedure TestBlaRadiusIsMin;
    procedure TestBlaMultibrotCoefficient;
    procedure TestBlaJuliaHasNoB;
    procedure TestBlaUnsupportedIsEmpty;
    procedure TestBlaShortOrbitIsEmpty;
    procedure TestBlaLevelLayout;
  end;

implementation

uses
  SysUtils, Math;

const
  kOrbitLength = 1100;   // au-dessus de kBlaMinOrbitLength

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

initialization
  RegisterTest(TTestBla.Suite);

end.
