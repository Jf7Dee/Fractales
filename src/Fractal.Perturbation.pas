unit Fractal.Perturbation;

// Orbite de référence en haute précision, base de la perturbation des zooms profonds.

interface

uses
  SysUtils, Fractal.HighFloat, Fractal.Types, Fractal.Formulas;

const
  kCancelCheckInterval = 256;   // itérations entre deux vérifications de l'annulation

type
  TCancelCheck = reference to function: Boolean;

// Orbite Z0 = 0, Z1, ... de la référence (CX, CY), jusqu'à l'échappement inclus ou MaxIter + 1 points.
// Renvoie False si IsCancelled répond True (vérifié toutes les kCancelCheckInterval = 256 itérations).
function ComputeReferenceOrbit(Formula: TFractalFormula; const CX, CY: THighFloat; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;

implementation

const
  kOrbitGrowStep = 1024;   // pas d'agrandissement du tableau de l'orbite
  kNilFormulaMessage = 'ComputeReferenceOrbit : formule absente';

{------------------------------------------------------------------------------}

function ComputeReferenceOrbit(Formula: TFractalFormula; const CX, CY: THighFloat; IsCancelled: TCancelCheck;
  out Orbit: TOrbit): Boolean;
var
  ZX, ZY: THighFloat;
  Point: TComplexPoint;
  Count, K: Integer;
begin
  if Formula = nil then
    raise EArgumentException.Create(kNilFormulaMessage);
  Orbit := nil;
  Result := False;
  ZX := THighFloat.Zero(CX.FracWords);
  ZY := THighFloat.Zero(CX.FracWords);
  Count := 0;
  K := 0;
  while True do
  begin
    if (K mod kCancelCheckInterval = 0) and Assigned(IsCancelled) and IsCancelled() then
    begin
      Orbit := nil;
      Exit;
    end;
    Point.X := ZX.ToFloat;
    Point.Y := ZY.ToFloat;
    if Count >= Length(Orbit) then
      SetLength(Orbit, Count + kOrbitGrowStep);
    Orbit[Count] := Point;
    Inc(Count);
    // Zk échappe (|Z|² > R²) ou k = MaxIter : le dernier point est stocké puis on s'arrête
    if (Point.X * Point.X + Point.Y * Point.Y > kEscapeRadius2) or (K >= Formula.MaxIter) then
      Break;
    Formula.StepReference(ZX, ZY, CX, CY);
    Inc(K);
  end;
  SetLength(Orbit, Count);
  Result := True;
end;

end.
