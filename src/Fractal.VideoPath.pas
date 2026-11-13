unit Fractal.VideoPath;

// Trajet de la caméra entre deux étapes d'une vidéo : survol (reculer, glisser, replonger) ou glissement latéral.

interface

uses
  SysUtils, Math, Fractal.HighFloat, Fractal.Types;

const
  kRho = 1.4142135623730950488;  // √2 : compromis entre recul et glissement proposé par van Wijk et Nuij
  kLateralSpeedWarning = 2.0;  // largeurs d'écran par seconde : au-delà, le glissement devient illisible
  kMinTravelSeconds = 2.0;
  kMaxTravelSeconds = 30.0;

type
  TVideoMoveMode = (vmFlyover, vmLateral);

  TCameraPose = record
    CenterX, CenterY: THighFloat;
    Width: TFloat;
  end;

  TCameraPoses = array of TCameraPose;
  TVideoMoveModes = array of TVideoMoveMode;

// Fraction : part du temps du trajet écoulée (0 à 1) ; l'adoucissement est appliqué ici
function PoseBetween(const A, B: TCameraPose; Mode: TVideoMoveMode; Fraction: Double): TCameraPose;
function EaseInOut(Fraction: Double): Double;
function LateralScreensPerSecond(const A, B: TCameraPose; Seconds: Double): Double;
function SuggestedTravelSeconds(const A, B: TCameraPose; Mode: TVideoMoveMode): Double;
// Longueur perçue du survol (van Wijk et Nuij) entre deux largeurs distantes de D
function FlyoverLength(W0, W1, D: TFloat): TFloat;
// Longueur perçue d'un trajet, métrique du survol pour les deux modes : ds² = ρ²(du / w)² + (d ln w)² / ρ² (un
// glissement pur d'une largeur d'écran mesure ρ), sans adoucissement
function PathLength(const A, B: TCameraPose; Mode: TVideoMoveMode): TFloat;
// Pose après une longueur perçue S (bornée à 0..PathLength), sans adoucissement : A en 0, B à la longueur totale
function PoseAtLength(const A, B: TCameraPose; Mode: TVideoMoveMode; S: TFloat): TCameraPose;
// Longueur parcourue après la fraction de temps T (0 à 1) d'un enchaînement de longueur Total : rampe de départ sur
// RampIn, palier, rampe d'arrivée sur RampOut (fractions du temps, ramenées à une somme <= 1), vitesse en 3x² - 2x³
// sur les rampes
function ChainDistance(T, Total, RampIn, RampOut: Double): Double;
// Fenêtre de l'arrondi autour d'une étape de passage, de part et d'autre, d'après les longueurs des deux trajets,
// bornée en longueur perçue
function CornerWindow(LenIn, LenOut: TFloat): TFloat;
// Parcours de l'arrondi du passage par B (trajet A → B en ModeIn, puis B → C en ModeOut) ; 0 sans arrondi
function CornerLength(const A, B, C: TCameraPose; ModeIn, ModeOut: TVideoMoveMode): TFloat;
// Pose sur cet arrondi après le parcours S : de l'entrée (0, sur A → B) à la sortie (CornerLength, sur B → C)
function CornerPose(const A, B, C: TCameraPose; ModeIn, ModeOut: TVideoMoveMode; S: TFloat): TCameraPose;
// Enchaînement sans arrêt de Poses[0] à Poses[High] (Modes[I] : trajet qui arrive à Poses[I]), à la fraction de
// temps T avec les rampes de ChainDistance ; bouts exacts
function ChainPose(const Poses: array of TCameraPose; const Modes: array of TVideoMoveMode;
  T, RampIn, RampOut: Double): TCameraPose;
// Parcours total de l'enchaînement, et parcours au passage le plus près de Poses[Index] (milieu de son arrondi)
procedure ChainMeasure(const Poses: array of TCameraPose; const Modes: array of TVideoMoveMode; Index: Integer;
  out Total, PassLength: TFloat);

implementation

const
  kRhoSquare = 2.0;
  kRhoFourth = 4.0;
  kSamePointRatio = 1e-9;        // distance négligeable devant la largeur : zoom pur
  kCenterMarginRatio = 1e-4;     // précision du centre : bien plus fine qu'un pixel
  kLengthSamples = 64;           // pas de l'intégration de la longueur d'un glissement latéral
  kNewtonIterations = 5;
  kNewtonTolerance = 1e-12;      // part de la longueur totale
  kCornerRatio = 0.25;           // fenêtre d'un arrondi : part du plus court des deux trajets
  kMaxCornerWindow = 1.0;        // et au plus cette longueur perçue : sur une plongée profonde, une fenêtre plus
                                 // large couvrirait des largeurs très différentes et l'arrondi ferait un détour
  kCornerSamples = 64;           // pas de la table de parcours d'un arrondi
  kTangentStepRatio = 1e-4;      // pas des différences finies des tangentes : part de la fenêtre
  kBounceRatio = 0.5;            // retournement du zoom : plus grand, le creux de vitesse dure plus longtemps
  kReversalApproach = 2.0;       // retournement du zoom : au plus profond, au plus 2 fois la largeur de l'étape

type
  TCornerVector = array[0..2] of TFloat;  // décalage du centre par rapport à l'étape (X, Y), puis Ln(largeur)

  // Arrondi d'une étape de passage : courbe d'Hermite parcourue à vitesse perçue constante ; quand le zoom s'inverse,
  // une vitesse fictive Bounce, nulle aux bouts, s'ajoute à celle de la courbe : la caméra ralentit sans s'arrêter
  TCornerCurve = record
    Window: TFloat;                 // de part et d'autre de l'étape, sur chacun des deux trajets
    Corner, Entry, Leave: TCameraPose;
    Q0, M0, Q2, M2: TCornerVector;  // bouts et tangentes
    Bounce: TFloat;
    Words: Integer;
    Table: array[0..kCornerSamples] of TFloat;  // parcours cumulé aux paramètres réguliers
  end;

  // Enchaînement, indexé par étape : trajet qui y arrive, fenêtre et arrondi autour d'elle
  TChainLayout = record
    Lengths, Windows, CornerLengths: array of TFloat;
    Corners: array of TCornerCurve;
    Total: TFloat;
  end;

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

// Vitesse perçue d'un glissement latéral au paramètre E (métrique du survol) : le centre avance de D par unité de E,
// la largeur suit LogLerp (d ln w / dE = LnRatio)
function LateralSpeed(W0, D, LnRatio: TFloat; E: Double): TFloat;
var
  W: TFloat;
begin
  W := LogLerp(W0, W0 * Exp(LnRatio), E);
  Result := Sqrt(kRhoSquare * Sqr(D / W) + Sqr(LnRatio) / kRhoSquare);
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

// Primitive de la vitesse adoucie 3x² - 2x³ sur 0..X
function SmoothArea(X: Double): Double;
begin
  Result := X * X * X * (1 - X / 2);
end;

{------------------------------------------------------------------------------}

function ChainDistance(T, Total, RampIn, RampOut: Double): Double;
var
  Cruise, Speed, X: Double;
begin
  T := EnsureRange(T, 0, 1);
  RampIn := EnsureRange(RampIn, 0, 1);
  RampOut := EnsureRange(RampOut, 0, 1 - RampIn);
  Cruise := 1 - RampIn / 2 - RampOut / 2;  // au moins 1/2
  Speed := Total / Cruise;
  if (RampIn > 0) and (T < RampIn) then
    Result := Speed * RampIn * SmoothArea(T / RampIn)
  else if (RampOut > 0) and (T > 1 - RampOut) then
  begin
    X := Max(1 - T, 0) / RampOut;
    Result := Total - Speed * RampOut * SmoothArea(X);
  end
  else
    Result := Speed * (RampIn / 2 + T - RampIn);
end;

{------------------------------------------------------------------------------}

function CornerWindow(LenIn, LenOut: TFloat): TFloat;
begin
  Result := Min(kCornerRatio * Min(LenIn, LenOut), kMaxCornerWindow);
end;

{------------------------------------------------------------------------------}

// Décalage d'une pose par rapport à l'étape Corner, mesuré en précision étendue, et Ln de sa largeur
procedure CornerCoords(const Corner, P: TCameraPose; out Q: TCornerVector);
begin
  Q[0] := P.CenterX.Sub(Corner.CenterX).ToFloat;
  Q[1] := P.CenterY.Sub(Corner.CenterY).ToFloat;
  Q[2] := Ln(P.Width);
end;

{------------------------------------------------------------------------------}

// Norme perçue d'une vitesse exprimée dans les coordonnées de CornerCoords, à la largeur Width
function PerceivedNorm(const V: TCornerVector; Width: TFloat): TFloat;
begin
  Result := Sqrt(kRhoSquare * (Sqr(V[0] / Width) + Sqr(V[1] / Width)) + Sqr(V[2]) / kRhoSquare);
end;

{------------------------------------------------------------------------------}

// Direction du trajet A → B à la longueur S, de norme perçue 1 : différences finies centrées de pas Step
procedure PathTangent(const A, B: TCameraPose; Mode: TVideoMoveMode; S, Step: TFloat; out T: TCornerVector);
var
  P, Q: TCameraPose;
  Norm: TFloat;
  K: Integer;
begin
  P := PoseAtLength(A, B, Mode, S - Step);
  Q := PoseAtLength(A, B, Mode, S + Step);
  T[0] := Q.CenterX.Sub(P.CenterX).ToFloat / (2 * Step);
  T[1] := Q.CenterY.Sub(P.CenterY).ToFloat / (2 * Step);
  T[2] := Ln(Q.Width / P.Width) / (2 * Step);
  Norm := PerceivedNorm(T, Sqrt(P.Width) * Sqrt(Q.Width));
  if Norm > 0 then
    for K := 0 to 2 do
      T[K] := T[K] / Norm;
end;

{------------------------------------------------------------------------------}

// Point X et dérivée V de la courbe d'Hermite au paramètre U (0 à 1)
procedure CornerPoint(const C: TCornerCurve; U: Double; out X, V: TCornerVector);
var
  H00, H10, H01, H11, D00, D10, D01, D11: Double;
  K: Integer;
begin
  H00 := (1 + 2 * U) * Sqr(1 - U);
  H10 := U * Sqr(1 - U);
  H01 := Sqr(U) * (3 - 2 * U);
  H11 := Sqr(U) * (U - 1);
  D00 := 6 * U * (U - 1);
  D10 := (1 - U) * (1 - 3 * U);
  D01 := -D00;
  D11 := U * (3 * U - 2);
  for K := 0 to 2 do
  begin
    X[K] := H00 * C.Q0[K] + H10 * C.M0[K] + H01 * C.Q2[K] + H11 * C.M2[K];
    V[K] := D00 * C.Q0[K] + D10 * C.M0[K] + D01 * C.Q2[K] + D11 * C.M2[K];
  end;
end;

{------------------------------------------------------------------------------}

// Vitesse de parcours au paramètre U : vitesse perçue de la courbe, augmentée du rebond (nul aux bouts)
function CornerSpeed(const C: TCornerCurve; U: Double): TFloat;
var
  X, V: TCornerVector;
begin
  CornerPoint(C, U, X, V);
  Result := Sqrt(Sqr(PerceivedNorm(V, Exp(X[2]))) + Sqr(C.Bounce * 4 * U * (1 - U)));
end;

{------------------------------------------------------------------------------}

// Parcours entre les paramètres U0 et U1 (Simpson)
function CornerSegment(const C: TCornerCurve; U0, U1: Double): TFloat;
begin
  Result := (U1 - U0) / 6 * (CornerSpeed(C, U0) + 4 * CornerSpeed(C, (U0 + U1) / 2) + CornerSpeed(C, U1));
end;

{------------------------------------------------------------------------------}

// Bouts et tangentes de l'arrondi pour la fenêtre H ; renvoie la part de retournement du zoom (0 à 1) : parts de
// zoom des deux directions de signes contraires, la courbe fait alors presque demi-tour
function CornerEnds(const A, B, C: TCameraPose; ModeIn, ModeOut: TVideoMoveMode; LenIn, H: TFloat;
  var Curve: TCornerCurve): TFloat;
var
  Step: TFloat;
  T0, T2: TCornerVector;
  K: Integer;
begin
  Step := kTangentStepRatio * H;
  Curve.Window := H;
  Curve.Entry := PoseAtLength(A, B, ModeIn, LenIn - H);
  Curve.Leave := PoseAtLength(B, C, ModeOut, H);
  CornerCoords(B, Curve.Entry, Curve.Q0);
  CornerCoords(B, Curve.Leave, Curve.Q2);
  PathTangent(A, B, ModeIn, LenIn - H, Step, T0);
  PathTangent(B, C, ModeOut, H, Step, T2);
  for K := 0 to 2 do
  begin
    Curve.M0[K] := 2 * H * T0[K];
    Curve.M2[K] := 2 * H * T2[K];
  end;
  Result := Max(0, -(T0[2] / kRho) * (T2[2] / kRho));
end;

{------------------------------------------------------------------------------}

// Arrondi du passage par B entre les trajets A → B (longueur LenIn) et B → C (LenOut) : courbe d'Hermite des
// décalages par rapport à B et de Ln(largeur), tangente aux deux trajets ; False s'il n'y a pas d'arrondi
function BuildCorner(const A, B, C: TCameraPose; ModeIn, ModeOut: TVideoMoveMode; LenIn, LenOut: TFloat;
  out Curve: TCornerCurve): Boolean;
var
  H, Reversal, ReversalWindow: TFloat;
  I: Integer;
begin
  H := CornerWindow(LenIn, LenOut);
  Result := H > 0;
  if not Result then
    Exit;
  Curve.Corner := B;
  Reversal := CornerEnds(A, B, C, ModeIn, ModeOut, LenIn, H, Curve);
  // Retournement : en zoom pur, l'entrée est à ρH au-dessus de B en Ln(largeur) et la courbe descend jusqu'à ρH / 2 ;
  // la fenêtre est réduite pour que le point le plus profond reste à kReversalApproach fois la largeur de B (moins
  // réduite à mesure que le retournement s'efface, pour rester continu)
  if Reversal > 0 then
  begin
    ReversalWindow := 2 * Ln(kReversalApproach) / kRho / Reversal;
    if H > ReversalWindow then
    begin
      H := ReversalWindow;
      Reversal := CornerEnds(A, B, C, ModeIn, ModeOut, LenIn, H, Curve);
    end;
  end;
  Curve.Bounce := kBounceRatio * 2 * H * Reversal;
  Curve.Words := Max(Max(Max(B.CenterX.FracWords, B.CenterY.FracWords),
    Max(Curve.Entry.CenterX.FracWords, Curve.Entry.CenterY.FracWords)),
    Max(Curve.Leave.CenterX.FracWords, Curve.Leave.CenterY.FracWords));
  Curve.Table[0] := 0;
  for I := 1 to kCornerSamples do
    Curve.Table[I] := Curve.Table[I - 1] + CornerSegment(Curve, (I - 1) / kCornerSamples, I / kCornerSamples);
  Result := Curve.Table[kCornerSamples] > 0;
end;

{------------------------------------------------------------------------------}

// Paramètre U de l'arrondi après le parcours S : la table donne le pas, Newton l'affine (comme LateralParam)
function CornerParam(const C: TCornerCurve; S: TFloat): Double;
var
  I, Iter: Integer;
  Delta, Tolerance, Speed: TFloat;
  U0, U1: Double;
begin
  I := 0;
  while (I < kCornerSamples - 1) and (S >= C.Table[I + 1]) do
    Inc(I);
  U0 := I / kCornerSamples;
  U1 := (I + 1) / kCornerSamples;
  if C.Table[I + 1] <= C.Table[I] then
    Exit(U0);
  Result := U0 + (S - C.Table[I]) / (C.Table[I + 1] - C.Table[I]) / kCornerSamples;
  Tolerance := kNewtonTolerance * C.Table[kCornerSamples];
  for Iter := 1 to kNewtonIterations do
  begin
    Delta := C.Table[I] + CornerSegment(C, U0, Result) - S;
    Speed := CornerSpeed(C, Result);
    if (Abs(Delta) < Tolerance) or not (Speed > 0) then
      Break;
    Result := EnsureRange(Result - Delta / Speed, U0, U1);
  end;
end;

{------------------------------------------------------------------------------}

// Pose sur l'arrondi après le parcours S, centre recomposé depuis l'étape comme dans CenterFrom
function CornerAt(const C: TCornerCurve; S: TFloat): TCameraPose;
var
  X, V: TCornerVector;
  Words: Integer;
begin
  if not (S > 0) then
    Exit(C.Entry);
  if S >= C.Table[kCornerSamples] then
    Exit(C.Leave);
  CornerPoint(C, CornerParam(C, S), X, V);
  Result.Width := Exp(X[2]);
  Words := Max(C.Words, FracWordsForPixelSize(Result.Width * kCenterMarginRatio));
  Result.CenterX := C.Corner.CenterX.WithFracWords(Words).AddFloat(X[0], Words);
  Result.CenterY := C.Corner.CenterY.WithFracWords(Words).AddFloat(X[1], Words);
end;

{------------------------------------------------------------------------------}

function CornerLength(const A, B, C: TCameraPose; ModeIn, ModeOut: TVideoMoveMode): TFloat;
var
  Curve: TCornerCurve;
begin
  if BuildCorner(A, B, C, ModeIn, ModeOut, PathLength(A, B, ModeIn), PathLength(B, C, ModeOut), Curve) then
    Result := Curve.Table[kCornerSamples]
  else
    Result := 0;
end;

{------------------------------------------------------------------------------}

function CornerPose(const A, B, C: TCameraPose; ModeIn, ModeOut: TVideoMoveMode; S: TFloat): TCameraPose;
var
  Curve: TCornerCurve;
begin
  if BuildCorner(A, B, C, ModeIn, ModeOut, PathLength(A, B, ModeIn), PathLength(B, C, ModeOut), Curve) then
    Result := CornerAt(Curve, S)
  else
    Result := B;
end;

{------------------------------------------------------------------------------}

// Partie du trajet I parcourue hors des fenêtres d'arrondi de ses deux bouts
function ChainPiece(const Layout: TChainLayout; I: Integer): TFloat;
begin
  Result := Layout.Lengths[I] - Layout.Windows[I - 1] - Layout.Windows[I];
end;

{------------------------------------------------------------------------------}

procedure CheckChain(const Poses: array of TCameraPose; const Modes: array of TVideoMoveMode);
begin
  if (Length(Poses) < 2) or (Length(Modes) <> Length(Poses)) then
    raise EArgumentException.Create('Enchaînement : au moins deux étapes et un mode par étape');
end;

{------------------------------------------------------------------------------}

// Longueurs des trajets, fenêtres et arrondis des étapes de passage, parcours total de l'enchaînement
procedure LayoutChain(const Poses: array of TCameraPose; const Modes: array of TVideoMoveMode;
  out Layout: TChainLayout);
var
  I, Last: Integer;
begin
  CheckChain(Poses, Modes);
  Last := High(Poses);
  SetLength(Layout.Lengths, Last + 1);
  SetLength(Layout.Windows, Last + 1);
  SetLength(Layout.CornerLengths, Last + 1);
  SetLength(Layout.Corners, Last + 1);
  Layout.Lengths[0] := 0;
  for I := 1 to Last do
    Layout.Lengths[I] := PathLength(Poses[I - 1], Poses[I], Modes[I]);
  for I := 0 to Last do
  begin
    Layout.Windows[I] := 0;
    Layout.CornerLengths[I] := 0;
    if (I > 0) and (I < Last) and BuildCorner(Poses[I - 1], Poses[I], Poses[I + 1], Modes[I], Modes[I + 1],
      Layout.Lengths[I], Layout.Lengths[I + 1], Layout.Corners[I]) then
    begin
      Layout.Windows[I] := Layout.Corners[I].Window;
      Layout.CornerLengths[I] := Layout.Corners[I].Table[kCornerSamples];
    end;
  end;
  Layout.Total := 0;
  for I := 1 to Last do
    Layout.Total := Layout.Total + ChainPiece(Layout, I) + Layout.CornerLengths[I];
end;

{------------------------------------------------------------------------------}

function ChainPose(const Poses: array of TCameraPose; const Modes: array of TVideoMoveMode;
  T, RampIn, RampOut: Double): TCameraPose;
var
  Layout: TChainLayout;
  S, Acc, Piece: TFloat;
  I, Last: Integer;
begin
  CheckChain(Poses, Modes);
  Last := High(Poses);
  if T >= 1 then
    Exit(Poses[Last]);
  if not (T > 0) then
    Exit(Poses[0]);
  LayoutChain(Poses, Modes, Layout);
  S := ChainDistance(T, Layout.Total, RampIn, RampOut);
  Acc := 0;
  for I := 1 to Last do
  begin
    Piece := ChainPiece(Layout, I);
    if (S < Acc + Piece) or (I = Last) then
      Exit(PoseAtLength(Poses[I - 1], Poses[I], Modes[I], Layout.Windows[I - 1] + S - Acc));
    Acc := Acc + Piece;
    if S < Acc + Layout.CornerLengths[I] then
      Exit(CornerAt(Layout.Corners[I], S - Acc));
    Acc := Acc + Layout.CornerLengths[I];
  end;
  Result := Poses[Last];
end;

{------------------------------------------------------------------------------}

procedure ChainMeasure(const Poses: array of TCameraPose; const Modes: array of TVideoMoveMode; Index: Integer;
  out Total, PassLength: TFloat);
var
  Layout: TChainLayout;
  I: Integer;
begin
  LayoutChain(Poses, Modes, Layout);
  if (Index < 0) or (Index > High(Poses)) then
    raise EArgumentOutOfRangeException.CreateFmt('Enchaînement : étape %d hors limites', [Index]);
  Total := Layout.Total;
  PassLength := 0;
  for I := 1 to Index do
  begin
    PassLength := PassLength + ChainPiece(Layout, I);
    if I < Index then
      PassLength := PassLength + Layout.CornerLengths[I]
    else if Layout.CornerLengths[I] > 0 then
      PassLength := PassLength + Layout.Corners[I].Table[kCornerSamples div 2];  // milieu de l'arrondi
  end;
  if Index = High(Poses) then
    PassLength := Total;
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
