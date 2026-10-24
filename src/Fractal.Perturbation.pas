unit Fractal.Perturbation;

// Orbite de référence en haute précision, base de la perturbation des zooms profonds.

interface

uses
  SysUtils, Fractal.HighFloat, Fractal.Types, Fractal.Formulas;

const
  kCancelCheckInterval = 256;   // itérations entre deux vérifications de l'annulation

type
  TCancelCheck = reference to function: Boolean;

// Orbite Z0, Z1, ... de la référence (CX, CY), jusqu'à l'échappement inclus ou MaxIter + 1 points : Z0 = 0 et
// c = (CX, CY), ou, si Formula.HasPixelStart (Julia), Z0 = (CX, CY) et c pris dans les paramètres.
// Renvoie False si IsCancelled répond True (vérifié toutes les kCancelCheckInterval = 256 itérations).
function ComputeReferenceOrbit(Formula: TFractalFormula; const CX, CY: THighFloat; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;

// Orbite critique W0 = 0, W1, ... d'une formule HasPixelStart (c dans les paramètres), en FracWords mots, avec le
// même pas StepReference et le même arrêt que ComputeReferenceOrbit ; False si annulée.
function ComputeCriticalOrbit(Formula: TFractalFormula; FracWords: Integer; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;

implementation

const
  kOrbitGrowStep = 1024;   // pas d'agrandissement du tableau de l'orbite
  kNilFormulaMessage = '%s : formule absente';
  kNoPixelStartMessage = 'ComputeCriticalOrbit : %s part de 0, sans orbite critique';

{------------------------------------------------------------------------------}

// Orbite de Z0 = (StartX, StartY) pour le paramètre (CX, CY), commune à la référence et à l'orbite critique.
function ComputeOrbit(Formula: TFractalFormula; const StartX, StartY, CX, CY: THighFloat; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;
var
  ZX, ZY: THighFloat;
  Point, FloatPoint: TComplexPoint;
  Count, K: Integer;
  IsFloatStep: Boolean;
begin
  Orbit := nil;
  Result := False;
  ZX := StartX;
  ZY := StartY;
  Count := 0;
  K := 0;
  IsFloatStep := False;
  while True do
  begin
    if (K mod kCancelCheckInterval = 0) and Assigned(IsCancelled) and IsCancelled() then
    begin
      Orbit := nil;
      Exit;
    end;
    if IsFloatStep then
      Point := FloatPoint
    else
    begin
      Point.X := ZX.ToFloat;
      Point.Y := ZY.ToFloat;
    end;
    if Count >= Length(Orbit) then
      SetLength(Orbit, Count + kOrbitGrowStep);
    Orbit[Count] := Point;
    Inc(Count);
    // le point issu de StepFloat a échappé par construction : fin de l'orbite
    if IsFloatStep then
      Break;
    // Zk échappe (|Z|² > R²) ou k = MaxIter : le dernier point est stocké puis on s'arrête
    if (Point.X * Point.X + Point.Y * Point.Y > kEscapeRadius2) or (K >= Formula.MaxIter) then
      Break;
    if not IsFloatStep and Formula.ShouldStepInFloat(Point.X, Point.Y) then
    begin
      // ce pas déborderait la partie entière de THighFloat : il échappe, son module en Extended suffit
      FloatPoint := Formula.StepFloat(Point.X, Point.Y, CX.ToFloat, CY.ToFloat);
      IsFloatStep := True;
    end
    else
      Formula.StepReference(ZX, ZY, CX, CY);
    Inc(K);
  end;
  SetLength(Orbit, Count);
  Result := True;
end;

{------------------------------------------------------------------------------}

function ComputeReferenceOrbit(Formula: TFractalFormula; const CX, CY: THighFloat; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;
var
  Zero: THighFloat;
begin
  if Formula = nil then
    raise EArgumentException.CreateFmt(kNilFormulaMessage, ['ComputeReferenceOrbit']);
  if Formula.HasPixelStart then
    Exit(ComputeOrbit(Formula, CX, CY.WithFracWords(CX.FracWords), CX, CY, IsCancelled, Orbit));
  Zero := THighFloat.Zero(CX.FracWords);
  Result := ComputeOrbit(Formula, Zero, Zero, CX, CY, IsCancelled, Orbit);
end;

{------------------------------------------------------------------------------}

function ComputeCriticalOrbit(Formula: TFractalFormula; FracWords: Integer; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;
var
  Zero: THighFloat;
begin
  if Formula = nil then
    raise EArgumentException.CreateFmt(kNilFormulaMessage, ['ComputeCriticalOrbit']);
  if not Formula.HasPixelStart then
    raise EArgumentException.CreateFmt(kNoPixelStartMessage, [Formula.FormulaName]);
  Zero := THighFloat.Zero(FracWords);
  // c est dans les paramètres : les arguments CX, CY du pas ne servent pas
  Result := ComputeOrbit(Formula, Zero, Zero, Zero, Zero, IsCancelled, Orbit);
end;

end.
