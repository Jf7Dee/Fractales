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

implementation

const
  kRho = 1.4142135623730950488;  // √2 : compromis entre recul et glissement proposé par van Wijk et Nuij
  kRhoSquare = 2.0;
  kRhoFourth = 4.0;
  kSamePointRatio = 1e-9;        // distance négligeable devant la largeur : zoom pur
  kCenterMarginRatio = 1e-4;     // précision du centre : bien plus fine qu'un pixel

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

function PoseBetween(const A, B: TCameraPose; Mode: TVideoMoveMode; Fraction: Double): TCameraPose;
var
  DX, DY, D, Total, S, Offset, Width: TFloat;
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
  begin
    Width := LogLerp(A.Width, B.Width, E);
    if E <= 0.5 then
      Result := CenterFrom(A, DX, DY, E, Width)
    else
      Result := CenterFrom(B, -DX, -DY, 1 - E, Width);
    Exit;
  end;
  Total := FlyoverLength(A.Width, B.Width, D);
  S := E * Total;
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
