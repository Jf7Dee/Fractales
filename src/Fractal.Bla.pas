unit Fractal.Bla;

// Approximation bilinéaire (BLA) de la perturbation : δ(m + Len) ≈ A·δ(m) + B·δc tant que |δ(m)| < R. La table est
// construite une fois par rendu à partir de l'orbite de référence, puis lue par toutes les tuiles (Delphi) ou passée
// telle quelle à la DLL Rust.
//
// Format, partagé avec kernel-rust : Steps = OrbitLength - 1 pas de base ; le pas m (1 <= m <= Steps) mène de
// l'itération m à m + 1 avec Z = Orbit[m]. Le niveau k a ceil(Steps / 2^k) entrées ; l'entrée j couvre les pas
// 1 + j·2^k et suivants (2^k pas, la dernière éventuellement moins). Niveaux concaténés 0, 1, 2… jusqu'au premier
// qui n'a qu'une entrée. Une entrée = kBlaEntrySize Double : AX, AY, BX, BY, R, Len.

interface

uses
  Fractal.Types, Fractal.Formulas;

const
  kBlaEntrySize = 6;
  // erreur relative tolérée sur δ : 2^-44. Mesuré sur MultiBroth_1 (64 x 36, 40 000 itérations) : 2^-24 laisse 1,7 %
  // des pixels à plus de 1e-2 de la valeur sans BLA, 2^-44 aucun (écart max 0,008), pour un temps quasi identique
  // (x 50 sur le calcul sans BLA)
  kBlaEpsilon = 1 / 17592186044416;
  kBlaMinOrbitLength = 1024;      // en dessous, la table coûte plus qu'elle ne fait gagner

function BlaLevelCount(Steps: Integer): Integer;
function BlaLevelEntries(Steps, Level: Integer): Integer;
// indice (en entrées, pas en Double) de la première entrée du niveau
function BlaLevelStart(Steps, Level: Integer): Integer;
// MaxDeltaC : |δc| maximal des pixels de l'image (0 pour Julia) ; table vide si la formule n'a pas de BLA ou si
// l'orbite est plus courte que kBlaMinOrbitLength
function BuildBlaTable(Formula: TFractalFormula; const Orbit: TOrbit; OrbitLength: Integer; MaxDeltaC: TFloat;
  Epsilon: TFloat = kBlaEpsilon): TBlaTable;
// Saut au point M de l'orbite (M >= 1), à l'itération N : l'entrée alignée du plus haut niveau dont le rayon
// contient δ, qui ne dépasse ni MaxIter ni la fin de l'orbite. δ devient A·δ + B·δc. Renvoie le nombre de pas sautés,
// 0 si aucun (table vide comprise) : l'appelant fait alors le pas normal.
function BlaJump(const T: TBlaTable; M, N, MaxIter, OrbitLength: Integer; var DX, DY: TFloat;
  DCX, DCY: TFloat): Integer;

implementation

uses
  SysUtils, Math;

{------------------------------------------------------------------------------}

function BlaLevelEntries(Steps, Level: Integer): Integer;
begin
  Result := (Steps + (1 shl Level) - 1) shr Level;
end;

{------------------------------------------------------------------------------}

function BlaLevelCount(Steps: Integer): Integer;
begin
  Result := 1;
  while BlaLevelEntries(Steps, Result - 1) > 1 do
    Inc(Result);
end;

{------------------------------------------------------------------------------}

function BlaLevelStart(Steps, Level: Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 0 to Level - 1 do
    Inc(Result, BlaLevelEntries(Steps, K));
end;

{------------------------------------------------------------------------------}

// x puis y, à l'offset Dst : A = Ay·Ax, B = Ay·Bx + By, R = min(Rx, (Ry - |Bx|·Cmax) / |Ax|)
procedure MergeEntries(var D: array of Double; X, Y, Dst: Integer; MaxDeltaC: TFloat);
var
  AX, AY, BX, BY, AbsAX, RY: Double;
begin
  AX := D[Y] * D[X] - D[Y + 1] * D[X + 1];
  AY := D[Y] * D[X + 1] + D[Y + 1] * D[X];
  BX := D[Y] * D[X + 2] - D[Y + 1] * D[X + 3] + D[Y + 2];
  BY := D[Y] * D[X + 3] + D[Y + 1] * D[X + 2] + D[Y + 3];
  AbsAX := Hypot(D[X], D[X + 1]);
  if AbsAX = 0 then
    RY := 0
  else
    RY := Max(0, (D[Y + 4] - Hypot(D[X + 2], D[X + 3]) * MaxDeltaC) / AbsAX);
  D[Dst + 4] := Min(D[X + 4], RY);
  D[Dst + 5] := D[X + 5] + D[Y + 5];
  D[Dst] := AX;
  D[Dst + 1] := AY;
  D[Dst + 2] := BX;
  D[Dst + 3] := BY;
end;

{------------------------------------------------------------------------------}

function BuildBlaTable(Formula: TFractalFormula; const Orbit: TOrbit; OrbitLength: Integer; MaxDeltaC: TFloat;
  Epsilon: TFloat): TBlaTable;
var
  Steps, Level, J, O, Src, Count, PrevCount, PrevStart, Start, K: Integer;
  A, B: TComplexPoint;
  Ratio, AbsZ: TFloat;
begin
  Result.Data := nil;
  Result.Steps := 0;
  Result.LevelCount := 0;
  Result.LevelStarts := nil;
  if Formula = nil then
    raise EArgumentException.Create('BuildBlaTable : formule absente');
  if not Formula.IsBlaSupported or (OrbitLength < kBlaMinOrbitLength) or (OrbitLength > Length(Orbit)) then
    Exit;
  Steps := OrbitLength - 1;
  Result.Steps := Steps;
  Result.LevelCount := BlaLevelCount(Steps);
  SetLength(Result.LevelStarts, Result.LevelCount);
  for Level := 0 to Result.LevelCount - 1 do
    Result.LevelStarts[Level] := BlaLevelStart(Steps, Level);
  SetLength(Result.Data, (Result.LevelStarts[Result.LevelCount - 1] + 1) * kBlaEntrySize);
  // niveau 0 : un pas de la formule au point Z = Orbit[m]
  for J := 0 to Steps - 1 do
  begin
    Formula.BlaStep(Orbit[1 + J], A, B, Ratio);
    AbsZ := Hypot(Orbit[1 + J].X, Orbit[1 + J].Y);
    O := J * kBlaEntrySize;
    Result.Data[O] := A.X;
    Result.Data[O + 1] := A.Y;
    Result.Data[O + 2] := B.X;
    Result.Data[O + 3] := B.Y;
    Result.Data[O + 4] := Max(0, (Epsilon * AbsZ * Ratio - Hypot(B.X, B.Y) * MaxDeltaC) / (Hypot(A.X, A.Y) + 1));
    Result.Data[O + 5] := 1;
  end;
  // niveaux suivants : fusion de deux entrées voisines ; une entrée seule en fin de niveau est recopiée
  for Level := 1 to Result.LevelCount - 1 do
  begin
    PrevStart := BlaLevelStart(Steps, Level - 1);
    PrevCount := BlaLevelEntries(Steps, Level - 1);
    Start := BlaLevelStart(Steps, Level);
    Count := BlaLevelEntries(Steps, Level);
    for J := 0 to Count - 1 do
    begin
      Src := (PrevStart + 2 * J) * kBlaEntrySize;
      O := (Start + J) * kBlaEntrySize;
      if 2 * J + 1 < PrevCount then
        MergeEntries(Result.Data, Src, Src + kBlaEntrySize, O, MaxDeltaC)
      else
        for K := 0 to kBlaEntrySize - 1 do
          Result.Data[O + K] := Result.Data[Src + K];
    end;
  end;
end;

{------------------------------------------------------------------------------}

function BlaJump(const T: TBlaTable; M, N, MaxIter, OrbitLength: Integer; var DX, DY: TFloat;
  DCX, DCY: TFloat): Integer;
var
  Level, Top, O, Len: Integer;
  R, D2, NewDX: TFloat;
begin
  Result := 0;
  if (T.Data = nil) or (M < 1) or (M > T.Steps) then
    Exit;
  // niveaux alignés sur M - 1 : autant que de zéros de poids faible
  Top := 0;
  while (Top < T.LevelCount - 1) and (((M - 1) shr Top) and 1 = 0) and (((M - 1) shr Top) <> 0) do
    Inc(Top);
  if M = 1 then
    Top := T.LevelCount - 1;
  D2 := DX * DX + DY * DY;
  for Level := Top downto 0 do
  begin
    O := (T.LevelStarts[Level] + ((M - 1) shr Level)) * kBlaEntrySize;
    R := T.Data[O + 4];
    if D2 >= R * R then
      Continue;
    Len := Round(T.Data[O + 5]);
    if (N + Len > MaxIter) or (M + Len > OrbitLength - 1) then
      Continue;
    NewDX := T.Data[O] * DX - T.Data[O + 1] * DY + T.Data[O + 2] * DCX - T.Data[O + 3] * DCY;
    DY := T.Data[O] * DY + T.Data[O + 1] * DX + T.Data[O + 2] * DCY + T.Data[O + 3] * DCX;
    DX := NewDX;
    Exit(Len);
  end;
end;

end.
