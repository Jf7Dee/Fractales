unit Fractal.Adaptive;

// Lissage adaptatif des vidéos : repère, dans une image calculée au pas du pixel, les pixels qui ont du détail (leur
// couleur diffère trop de celle d'un voisin) ; seuls ceux-là sont ensuite recalculés avec tous les sous-pixels.

interface

uses
  Types;

const
  // écart maximal toléré entre deux pixels voisins, par canal R, G ou B (sur 255) : au-delà, les deux sont lissés
  kAdaptiveThreshold = 6;

// Colors : Width × Height couleurs, ligne par ligne (un octet par canal, l'ordre des canaux est indifférent). Marque
// les pixels dont un des 8 voisins diffère de plus de Threshold sur un canal, puis leurs voisins (marge d'un pixel,
// pour les détails plus fins qu'un pixel). Renvoie le nombre de pixels marqués.
function MarkDetail(const Colors: array of Cardinal; Width, Height, Threshold: Integer;
  out Marks: TBooleanDynArray): Integer;
// Masque de Width·SS × Height·SS sous-pixels : ceux des pixels marqués, élargis d'abord de Extra pixels (relief :
// la pente d'un pixel lit les sous-pixels de ses voisins).
function ExpandMask(const Marks: TBooleanDynArray; Width, Height, Supersample, Extra: Integer): TBooleanDynArray;

implementation

uses
  SysUtils, Math;

{------------------------------------------------------------------------------}

function IsDifferent(A, B: Cardinal; Threshold: Integer): Boolean;
begin
  Result := (Abs(Integer(A and $FF) - Integer(B and $FF)) > Threshold)
    or (Abs(Integer((A shr 8) and $FF) - Integer((B shr 8) and $FF)) > Threshold)
    or (Abs(Integer((A shr 16) and $FF) - Integer((B shr 16) and $FF)) > Threshold);
end;

{------------------------------------------------------------------------------}

// Pixels marqués, élargis de Radius pixels dans les deux sens (bornés à l'image).
function Dilate(const Marks: TBooleanDynArray; Width, Height, Radius: Integer): TBooleanDynArray;
var
  X, Y, X1, Y1: Integer;
begin
  SetLength(Result, Width * Height);
  for Y := 0 to Height - 1 do
    for X := 0 to Width - 1 do
      if Marks[Y * Width + X] then
        for Y1 := Max(0, Y - Radius) to Min(Height - 1, Y + Radius) do
          for X1 := Max(0, X - Radius) to Min(Width - 1, X + Radius) do
            Result[Y1 * Width + X1] := True;
end;

{------------------------------------------------------------------------------}

function MarkDetail(const Colors: array of Cardinal; Width, Height, Threshold: Integer;
  out Marks: TBooleanDynArray): Integer;
var
  Detail: TBooleanDynArray;
  X, Y, X1, Y1, I: Integer;
begin
  if Length(Colors) <> Width * Height then
    raise EArgumentException.CreateFmt('%d couleurs pour une image de %d x %d', [Length(Colors), Width, Height]);
  SetLength(Detail, Width * Height);
  for Y := 0 to Height - 1 do
    for X := 0 to Width - 1 do
      for Y1 := Max(0, Y - 1) to Min(Height - 1, Y + 1) do
        for X1 := Max(0, X - 1) to Min(Width - 1, X + 1) do
          if IsDifferent(Colors[Y * Width + X], Colors[Y1 * Width + X1], Threshold) then
            Detail[Y * Width + X] := True;
  Marks := Dilate(Detail, Width, Height, 1);
  Result := 0;
  for I := 0 to High(Marks) do
    if Marks[I] then
      Inc(Result);
end;

{------------------------------------------------------------------------------}

function ExpandMask(const Marks: TBooleanDynArray; Width, Height, Supersample, Extra: Integer): TBooleanDynArray;
var
  Wide: TBooleanDynArray;
  X, Y, SubWidth: Integer;
begin
  if Length(Marks) <> Width * Height then
    raise EArgumentException.CreateFmt('%d marques pour une image de %d x %d', [Length(Marks), Width, Height]);
  if Extra > 0 then
    Wide := Dilate(Marks, Width, Height, Extra)
  else
    Wide := Marks;
  SubWidth := Width * Supersample;
  SetLength(Result, SubWidth * Height * Supersample);
  for Y := 0 to Height * Supersample - 1 do
    for X := 0 to SubWidth - 1 do
      Result[Y * SubWidth + X] := Wide[(Y div Supersample) * Width + X div Supersample];
end;

end.
