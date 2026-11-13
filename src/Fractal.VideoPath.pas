unit Fractal.VideoPath;

// Trajet de la caméra entre deux étapes d'une vidéo : survol (reculer, glisser, replonger) ou glissement latéral.

interface

uses
  SysUtils, Math, Fractal.HighFloat, Fractal.Types;

const
  kLateralSpeedWarning = 2.0;  // largeurs d'écran par seconde : au-delà, le glissement devient illisible
  kMinTravelSeconds = 2.0;
  kMaxTravelSeconds = 30.0;

type
  TVideoMoveMode = (vmFlyover, vmLateral);

  TCameraPose = record
    CenterX, CenterY: THighFloat;
    Width: TFloat;
  end;

// Fraction : part du temps du trajet écoulée (0 à 1) ; l'adoucissement est appliqué ici
function PoseBetween(const A, B: TCameraPose; Mode: TVideoMoveMode; Fraction: Double): TCameraPose;
function EaseInOut(Fraction: Double): Double;
function LateralScreensPerSecond(const A, B: TCameraPose; Seconds: Double): Double;
function SuggestedTravelSeconds(const A, B: TCameraPose; Mode: TVideoMoveMode): Double;
// Longueur perçue du survol (van Wijk et Nuij) entre deux largeurs distantes de D
function FlyoverLength(W0, W1, D: TFloat): TFloat;
// Longueur perçue d'un trajet : ds² = (du / w)² + (d ln w)² / ρ², sans adoucissement
function PathLength(const A, B: TCameraPose; Mode: TVideoMoveMode): TFloat;
// Pose après une longueur perçue S (bornée à 0..PathLength), sans adoucissement : A en 0, B à la longueur totale
function PoseAtLength(const A, B: TCameraPose; Mode: TVideoMoveMode; S: TFloat): TCameraPose;

implementation

const
  kRho = 1.4142135623730950488;  // √2 : compromis entre recul et glissement proposé par van Wijk et Nuij
  kRhoSquare = 2.0;
  kRhoFourth = 4.0;
  kSamePointRatio = 1e-9;        // distance négligeable devant la largeur : zoom pur
  kCenterMarginRatio = 1e-4;     // précision du centre : bien plus fine qu'un pixel
  kLengthSamples = 64;           // pas de l'intégration de la longueur d'un glissement latéral
  kNewtonIterations = 5;
  kNewtonTolerance = 1e-12;      // part de la longueur totale

{------------------------------------------------------------------------------}

function EaseInOut(Fraction: Double): Double;
begin
  Fraction := EnsureRange(Fraction, 0, 1);
  Result := Fraction * Fraction * Fraction * (Fraction * (6 * Fraction - 15) + 10);
end;

{------------------------------------------------------------------------------}

procedure Distance(const A, B: TCameraPose; out DX, DY, D: TFloat);
begin
  DX := B.CenterX.Sub(A.CenterX).ToFloat;
  DY := B.CenterY.Sub(A.CenterY).ToFloat;
  D := Hypot(DX, DY);
end;

{------------------------------------------------------------------------------}

// Négligeable devant la plus petite largeur : sinon, en descente profonde, l'arrivée resterait hors champ
function IsSamePoint(D, W0, W1: TFloat): Boolean;
begin
  Result := D <= kSamePointRatio * Min(W0, W1);
end;

{------------------------------------------------------------------------------}

// ArcSinh de la RTL (Ln(X + Sqrt(X² + 1))) perd toute précision pour X très négatif : symétrie impaire
function StableArcSinh(X: TFloat): TFloat;
begin
  Result := Ln(Abs(X) + Sqrt(X * X + 1));
  if X < 0 then
    Result := -Result;
end;

{------------------------------------------------------------------------------}

// Chemin de van Wijk et Nuij (2003), écrit sous une forme sans soustraction de grands nombres
function FlyoverB(W0, W1, D: TFloat): TFloat;
begin
  Result := (W1 * W1 - W0 * W0 + kRhoFourth * D * D) / (2 * W0 * kRhoSquare * D);
end;

{------------------------------------------------------------------------------}

function FlyoverLength(W0, W1, D: TFloat): TFloat;
begin
  if IsSamePoint(D, W0, W1) then
    Result := Abs(Ln(W1 / W0)) / kRho
  else
    Result := (StableArcSinh(FlyoverB(W1, W0, D)) + StableArcSinh(FlyoverB(W0, W1, D))) / kRho;
end;

{------------------------------------------------------------------------------}

// Après S sur le chemin, depuis le bout de largeur W0 : décalage parcouru (même unité que D) et largeur
procedure FlyoverFrom(W0, W1, D, S: TFloat; out Offset, Width: TFloat);
var
  R0: TFloat;
begin
  R0 := -StableArcSinh(FlyoverB(W0, W1, D));
  Offset := W0 / kRhoSquare * Sinh(kRho * S) / Cosh(kRho * S + R0);
  Width := W0 * Cosh(R0) / Cosh(kRho * S + R0);
end;

{------------------------------------------------------------------------------}

function LogLerp(W0, W1: TFloat; T: Double): TFloat;
begin
  Result := Exp(Ln(W0) + T * (Ln(W1) - Ln(W0)));
end;

{------------------------------------------------------------------------------}

// Centre à une fraction K de la distance, compté depuis le bout le plus proche : chaque bout garde la
// précision de sa propre largeur, même en zoom profond
function CenterFrom(const Origin: TCameraPose; DX, DY, K, Width: TFloat): TCameraPose;
var
  Words: Integer;
begin
  Words := Max(Max(Origin.CenterX.FracWords, Origin.CenterY.FracWords),
    FracWordsForPixelSize(Width * kCenterMarginRatio));
  Result.CenterX := Origin.CenterX.WithFracWords(Words).AddFloat(K * DX, Words);
  Result.CenterY := Origin.CenterY.WithFracWords(Words).AddFloat(K * DY, Words);
  Result.Width := Width;
end;

{------------------------------------------------------------------------------}

// Glissement latéral, au paramètre E (0 à 1) : centre linéaire, largeur en progression géométrique
function LateralPose(const A, B: TCameraPose; DX, DY: TFloat; E: Double): TCameraPose;
var
  Width: TFloat;
begin
  Width := LogLerp(A.Width, B.Width, E);
  if E <= 0.5 then
    Result := CenterFrom(A, DX, DY, E, Width)
  else
    Result := CenterFrom(B, -DX, -DY, 1 - E, Width);
end;

{------------------------------------------------------------------------------}

// Survol, après la longueur S (0 à Total) ; D est la distance des centres, non nulle
function FlyoverPose(const A, B: TCameraPose; DX, DY, D, Total, S: TFloat): TCameraPose;
var
  Offset, Width: TFloat;
begin
  if S <= Total / 2 then
  begin
    FlyoverFrom(A.Width, B.Width, D, S, Offset, Width);
    Result := CenterFrom(A, DX, DY, Offset / D, Width);
  end
  else
  begin
    FlyoverFrom(B.Width, A.Width, D, Total - S, Offset, Width);
    Result := CenterFrom(B, -DX, -DY, Offset / D, Width);
  end;
end;

{------------------------------------------------------------------------------}

function PoseBetween(const A, B: TCameraPose; Mode: TVideoMoveMode; Fraction: Double): TCameraPose;
var
  DX, DY, D, Total: TFloat;
  E: Double;
begin
  if (A.Width <= 0) or (B.Width <= 0) then
    raise EArgumentException.Create('PoseBetween : largeur non positive');
  if Fraction <= 0 then
    Exit(A);
  if Fraction >= 1 then
    Exit(B);
  E := EaseInOut(Fraction);
  Distance(A, B, DX, DY, D);
  if (Mode = vmLateral) or IsSamePoint(D, A.Width, B.Width) then
    Result := LateralPose(A, B, DX, DY, E)
  else
  begin
    Total := FlyoverLength(A.Width, B.Width, D);
    Result := FlyoverPose(A, B, DX, DY, D, Total, E * Total);
  end;
end;

{------------------------------------------------------------------------------}

// Vitesse perçue d'un glissement latéral au paramètre E : le centre avance de D par unité de E, la largeur suit
// LogLerp (d ln w / dE = LnRatio)
function LateralSpeed(W0, D, LnRatio: TFloat; E: Double): TFloat;
var
  W: TFloat;
begin
  W := LogLerp(W0, W0 * Exp(LnRatio), E);
  Result := Sqrt(Sqr(D / W) + Sqr(LnRatio) / kRhoSquare);
end;

{------------------------------------------------------------------------------}

// Longueurs cumulées aux kLengthSamples + 1 bornes de E régulières (Simpson sur chaque pas)
procedure LateralTable(const A, B: TCameraPose; D: TFloat; out Table: array of TFloat);
var
  I: Integer;
  H, LnRatio: TFloat;
begin
  LnRatio := Ln(B.Width / A.Width);
  H := 1 / kLengthSamples;
  Table[0] := 0;
  for I := 1 to kLengthSamples do
    Table[I] := Table[I - 1] + H / 6 * (LateralSpeed(A.Width, D, LnRatio, (I - 1) * H)
      + 4 * LateralSpeed(A.Width, D, LnRatio, (I - 0.5) * H) + LateralSpeed(A.Width, D, LnRatio, I * H));
end;

{------------------------------------------------------------------------------}

function PathLength(const A, B: TCameraPose; Mode: TVideoMoveMode): TFloat;
var
  DX, DY, D: TFloat;
  Table: array[0..kLengthSamples] of TFloat;
begin
  if (A.Width <= 0) or (B.Width <= 0) then
    raise EArgumentException.Create('PathLength : largeur non positive');
  Distance(A, B, DX, DY, D);
  if IsSamePoint(D, A.Width, B.Width) then
    Result := Abs(Ln(B.Width / A.Width)) / kRho
  else if Mode = vmFlyover then
    Result := FlyoverLength(A.Width, B.Width, D)
  else
  begin
    LateralTable(A, B, D, Table);
    Result := Table[kLengthSamples];
  end;
end;

{------------------------------------------------------------------------------}

// Longueur perçue du glissement latéral entre les paramètres E0 et E1 (Simpson)
function LateralSegment(W0, D, LnRatio: TFloat; E0, E1: Double): TFloat;
begin
  Result := (E1 - E0) / 6 * (LateralSpeed(W0, D, LnRatio, E0) + 4 * LateralSpeed(W0, D, LnRatio, (E0 + E1) / 2)
    + LateralSpeed(W0, D, LnRatio, E1));
end;

{------------------------------------------------------------------------------}

// Paramètre E d'un glissement latéral dont la longueur parcourue est S : la table cumulée donne le pas, puis des
// itérations de Newton (dérivée = vitesse perçue) l'affinent, sinon la vitesse ondulerait au rythme des pas
function LateralParam(const A, B: TCameraPose; D, S: TFloat; const Table: array of TFloat): Double;
var
  I, Iter: Integer;
  LnRatio, Delta, Tolerance, E0, E1: TFloat;
begin
  I := 0;
  while (I < kLengthSamples - 1) and (S >= Table[I + 1]) do
    Inc(I);
  E0 := I / kLengthSamples;
  E1 := (I + 1) / kLengthSamples;
  if Table[I + 1] <= Table[I] then
    Exit(E0);
  Result := E0 + (S - Table[I]) / (Table[I + 1] - Table[I]) / kLengthSamples;
  LnRatio := Ln(B.Width / A.Width);
  Tolerance := kNewtonTolerance * Table[kLengthSamples];
  for Iter := 1 to kNewtonIterations do
  begin
    Delta := Table[I] + LateralSegment(A.Width, D, LnRatio, E0, Result) - S;
    if Abs(Delta) < Tolerance then
      Break;
    Result := EnsureRange(Result - Delta / LateralSpeed(A.Width, D, LnRatio, Result), E0, E1);
  end;
end;

{------------------------------------------------------------------------------}

function PoseAtLength(const A, B: TCameraPose; Mode: TVideoMoveMode; S: TFloat): TCameraPose;
var
  DX, DY, D, Total: TFloat;
  Table: array[0..kLengthSamples] of TFloat;
  IsTabulated: Boolean;
begin
  if (A.Width <= 0) or (B.Width <= 0) then
    raise EArgumentException.Create('PoseAtLength : largeur non positive');
  Distance(A, B, DX, DY, D);
  IsTabulated := (Mode = vmLateral) and not IsSamePoint(D, A.Width, B.Width);
  if IsTabulated then
  begin
    LateralTable(A, B, D, Table);
    Total := Table[kLengthSamples];
  end
  else
    Total := PathLength(A, B, Mode);
  if not (S > 0) then
    Exit(A);
  if S >= Total then
    Exit(B);
  if IsSamePoint(D, A.Width, B.Width) then
    Result := LateralPose(A, B, DX, DY, S / Total)
  else if IsTabulated then
    Result := LateralPose(A, B, DX, DY, LateralParam(A, B, D, S, Table))
  else
    Result := FlyoverPose(A, B, DX, DY, D, Total, S);
end;

{------------------------------------------------------------------------------}

function LateralScreensPerSecond(const A, B: TCameraPose; Seconds: Double): Double;
var
  DX, DY, D: TFloat;
begin
  Distance(A, B, DX, DY, D);
  Result := D / (Min(A.Width, B.Width) * Max(Seconds, 1e-3));
end;

{------------------------------------------------------------------------------}

function SuggestedTravelSeconds(const A, B: TCameraPose; Mode: TVideoMoveMode): Double;
var
  DX, DY, D: TFloat;
begin
  Distance(A, B, DX, DY, D);
  if Mode = vmLateral then
    Result := D / Min(A.Width, B.Width)  // une largeur d'écran par seconde
  else
    Result := 2 + 1.5 * FlyoverLength(A.Width, B.Width, D);
  Result := EnsureRange(Result, kMinTravelSeconds, kMaxTravelSeconds);
end;

end.
