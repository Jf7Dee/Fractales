unit TestFractalAdaptive;

interface

uses
  Types, TestFramework, Fractal.Adaptive;

type
  TTestAdaptive = class(TTestCase)
  private
    function Plain(Width, Height: Integer; Color: Cardinal): TCardinalDynArray;
    function CountMarks(const Marks: TBooleanDynArray): Integer;
  published
    procedure TestFlatMarksNothing;
    procedure TestVerticalEdgeMarksBand;
    procedure TestIsolatedPixelMarksNeighbourhood;
    procedure TestThresholdIsStrict;
    procedure TestExpandMaskSupersample;
    procedure TestCornerPixels;
  end;

implementation

uses
  SysUtils;

const
  kBlack = $000000;
  kWhite = $FFFFFF;
  kGrey = $102030;

{------------------------------------------------------------------------------}

function TTestAdaptive.Plain(Width, Height: Integer; Color: Cardinal): TCardinalDynArray;
var
  I: Integer;
begin
  SetLength(Result, Width * Height);
  for I := 0 to High(Result) do
    Result[I] := Color;
end;

{------------------------------------------------------------------------------}

function TTestAdaptive.CountMarks(const Marks: TBooleanDynArray): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Marks) do
    if Marks[I] then
      Inc(Result);
end;

{------------------------------------------------------------------------------}

procedure TTestAdaptive.TestFlatMarksNothing;
var
  Marks: TBooleanDynArray;
begin
  CheckEquals(0, MarkDetail(Plain(8, 5, kGrey), 8, 5, kAdaptiveThreshold, Marks));
  CheckEquals(40, Length(Marks));
  CheckEquals(0, CountMarks(Marks));
end;

{------------------------------------------------------------------------------}

// Bord net entre les colonnes 4 et 5 : elles sont marquées, plus la marge d'un pixel (colonnes 3 à 6).
procedure TTestAdaptive.TestVerticalEdgeMarksBand;
const
  kW = 10;
  kH = 6;
var
  Colors: TCardinalDynArray;
  Marks: TBooleanDynArray;
  X, Y: Integer;
begin
  Colors := Plain(kW, kH, kBlack);
  for Y := 0 to kH - 1 do
    for X := 5 to kW - 1 do
      Colors[Y * kW + X] := kWhite;
  CheckEquals(4 * kH, MarkDetail(Colors, kW, kH, kAdaptiveThreshold, Marks));
  for Y := 0 to kH - 1 do
    for X := 0 to kW - 1 do
      CheckEquals((X >= 3) and (X <= 6), Marks[Y * kW + X], Format('pixel %d,%d', [X, Y]));
end;

{------------------------------------------------------------------------------}

// Un pixel différent : lui et ses 8 voisins, plus la marge, soit un bloc 5×5 ; borné au coin de l'image.
procedure TTestAdaptive.TestIsolatedPixelMarksNeighbourhood;
const
  kW = 9;
  kH = 9;
var
  Colors: TCardinalDynArray;
  Marks: TBooleanDynArray;
  X, Y: Integer;
begin
  Colors := Plain(kW, kH, kGrey);
  Colors[4 * kW + 4] := kWhite;
  CheckEquals(25, MarkDetail(Colors, kW, kH, kAdaptiveThreshold, Marks));
  for Y := 0 to kH - 1 do
    for X := 0 to kW - 1 do
      CheckEquals((Abs(X - 4) <= 2) and (Abs(Y - 4) <= 2), Marks[Y * kW + X], Format('pixel %d,%d', [X, Y]));
  Colors := Plain(kW, kH, kGrey);
  Colors[0] := kWhite;
  CheckEquals(9, MarkDetail(Colors, kW, kH, kAdaptiveThreshold, Marks), 'coin');
end;

{------------------------------------------------------------------------------}

// Écart sur un seul canal égal au seuil : rien ; seuil + 1 : marqué.
procedure TTestAdaptive.TestThresholdIsStrict;
const
  kW = 6;
  kH = 4;
var
  Colors: TCardinalDynArray;
  Marks: TBooleanDynArray;
  X, Y: Integer;
  Delta: Cardinal;
begin
  for Delta := kAdaptiveThreshold to kAdaptiveThreshold + 1 do
  begin
    Colors := Plain(kW, kH, kGrey);
    for Y := 0 to kH - 1 do
      for X := 3 to kW - 1 do
        Colors[Y * kW + X] := kGrey + Delta shl 8;
    if Delta = kAdaptiveThreshold then
      CheckEquals(0, MarkDetail(Colors, kW, kH, kAdaptiveThreshold, Marks), 'écart égal au seuil')
    else
      CheckEquals(4 * kH, MarkDetail(Colors, kW, kH, kAdaptiveThreshold, Marks), 'écart au-delà du seuil');
  end;
end;

{------------------------------------------------------------------------------}

// SS 3 : un pixel marqué donne ses 3×3 sous-pixels ; Extra 1 élargit d'un pixel avant (9×9 sous-pixels).
procedure TTestAdaptive.TestExpandMaskSupersample;
const
  kW = 4;
  kH = 4;
  kSS = 3;
var
  Marks, Sub: TBooleanDynArray;
  X, Y: Integer;
begin
  SetLength(Marks, kW * kH);
  Marks[1 * kW + 1] := True;
  Sub := ExpandMask(Marks, kW, kH, kSS, 0);
  CheckEquals(kW * kSS * kH * kSS, Length(Sub));
  for Y := 0 to kH * kSS - 1 do
    for X := 0 to kW * kSS - 1 do
      CheckEquals((X div kSS = 1) and (Y div kSS = 1), Sub[Y * kW * kSS + X], Format('sous-pixel %d,%d', [X, Y]));
  Sub := ExpandMask(Marks, kW, kH, kSS, 1);
  CheckEquals(81, CountMarks(Sub));
  for Y := 0 to kH * kSS - 1 do
    for X := 0 to kW * kSS - 1 do
      CheckEquals((X < 9) and (Y < 9), Sub[Y * kW * kSS + X], Format('Extra 1, sous-pixel %d,%d', [X, Y]));
end;

{------------------------------------------------------------------------------}

// Bords et coins : pas de débordement, image d'un seul pixel comprise.
procedure TTestAdaptive.TestCornerPixels;
var
  Colors: TCardinalDynArray;
  Marks, Sub: TBooleanDynArray;
begin
  Colors := Plain(3, 3, kGrey);
  Colors[8] := kWhite;
  CheckEquals(9, MarkDetail(Colors, 3, 3, kAdaptiveThreshold, Marks));
  CheckEquals(0, MarkDetail(Plain(1, 1, kWhite), 1, 1, kAdaptiveThreshold, Marks));
  CheckEquals(1, Length(Marks));
  SetLength(Marks, 2 * 2);
  Marks[3] := True;
  Sub := ExpandMask(Marks, 2, 2, 2, 1);
  CheckEquals(16, CountMarks(Sub));
end;

{------------------------------------------------------------------------------}

initialization
  RegisterTest(TTestAdaptive.Suite);

end.
