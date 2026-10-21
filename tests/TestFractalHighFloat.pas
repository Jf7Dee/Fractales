unit TestFractalHighFloat;

interface

uses
  TestFramework, Fractal.HighFloat;

type
  TTestHighFloat = class(TTestCase)
  private
    function LongValue(AFracWords: Integer): THighFloat;
  published
    procedure TestFromFloatToFloatRoundTrip;
    procedure TestArithmeticMatchesExtended;
    procedure TestSqrAndTwice;
    procedure TestPrecisionBeyondExtended;
    procedure TestToStringAndParse;
    procedure TestParseInvariantFormats;
    procedure TestOperandsAreNeverModified;
    procedure TestFracWordsForPixelSize;
    procedure TestOverflowRaises;
  end;

implementation

uses
  SysUtils;

const
  kLongText = '-1.234567890123456789012345678901234567890123456789';
  kTinyText = '-0.000000000000000000000000000001234567890123456789';
  kTinyDigits = 48;
  kPairCount = 200;
  kRelEps = 1e-17;

{------------------------------------------------------------------------------}

function TTestHighFloat.LongValue(AFracWords: Integer): THighFloat;
begin
  Check(THighFloat.TryParse(kLongText, AFracWords, Result), 'analyse de kLongText');
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestFromFloatToFloatRoundTrip;
const
  kValues: array[0..4] of Extended = (-1.75, 0, 1 / 3, 255.9, 1e-18);
var
  I: Integer;
  V, R: Extended;
begin
  for I := Low(kValues) to High(kValues) do
  begin
    V := kValues[I];
    R := THighFloat.FromFloat(V, 4).ToFloat;
    Check(R = V, Format('valeur %d : %s <> %s', [I, FloatToStr(R), FloatToStr(V)]));
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestArithmeticMatchesExtended;

  procedure CheckClose(Expected, Actual: Extended; const AWhat: string);
  begin
    Check(Abs(Actual - Expected) <= kRelEps * Abs(Expected), AWhat + ' : ' + FloatToStr(Actual) + ' <> '
      + FloatToStr(Expected));
  end;

var
  I: Integer;
  X, Y: Extended;
  A, B: THighFloat;
begin
  RandSeed := 1;
  for I := 1 to kPairCount do
  begin
    X := Random * 8 - 4;
    Y := Random * 8 - 4;
    A := THighFloat.FromFloat(X, 3);
    B := THighFloat.FromFloat(Y, 3);
    CheckClose(X + Y, A.Add(B).ToFloat, 'Add');
    CheckClose(X - Y, A.Sub(B).ToFloat, 'Sub');
    CheckClose(X * Y, A.Mul(B).ToFloat, 'Mul');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestSqrAndTwice;
var
  A: THighFloat;
begin
  A := LongValue(10);
  Check(A.Sqr.IsEqual(A.Mul(A)), 'Sqr');
  Check(A.Twice.IsEqual(A.Add(A)), 'Twice');
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestPrecisionBeyondExtended;
var
  X, One: THighFloat;
  D: Extended;
begin
  One := THighFloat.FromFloat(1, 12);
  X := One.AddFloat(1e-100, 12);
  D := X.Sub(One).ToFloat;
  Check(Abs(D - 1e-100) <= 1e-15 * 1e-100, 'écart 1e-100 : ' + FloatToStr(D));
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestToStringAndParse;
var
  X, Y: THighFloat;
begin
  Check(THighFloat.TryParse(kTinyText, 8, X), 'analyse');
  CheckEquals(kTinyText, X.ToString(kTinyDigits));
  Check(THighFloat.TryParse(X.ToString(kTinyDigits), 8, Y), 'ré-analyse');
  Check(Y.IsEqual(X), 'aller-retour');
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestParseInvariantFormats;
var
  X: THighFloat;
begin
  Check(THighFloat.TryParse('1.5E+2', 4, X), '1.5E+2');
  CheckEquals(150, X.ToFloat, 0);
  Check(THighFloat.TryParse('3e-5', 4, X), '3e-5');
  CheckEquals(3e-5, X.ToFloat, 1e-18);
  Check(THighFloat.TryParse('-1.25', 4, X), '-1.25');
  CheckEquals(-1.25, X.ToFloat, 0);
  Check(not THighFloat.TryParse('abc', 4, X), 'abc');
  Check(not THighFloat.TryParse('', 4, X), 'vide');
  Check(not THighFloat.TryParse('1e', 4, X), '1e');
  Check(not THighFloat.TryParse('1.2.3', 4, X), '1.2.3');
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestOperandsAreNeverModified;
var
  A, B, C, Start, Last: THighFloat;
  S: string;
begin
  A := LongValue(6);
  B := THighFloat.FromFloat(0.75, 6);
  Start := LongValue(6);
  C := A;                                     // le tableau est partagé
  Last := A.Add(B);
  Last := A.Sub(B);
  Last := B.Sub(A);
  Last := A.Mul(B);
  Last := A.Sqr;
  Last := A.Twice;
  Last := A.AddFloat(1.5, 8);
  Last := A.WithFracWords(2);
  Last := A.WithFracWords(9);
  S := A.ToString(20);
  Check(C.IsEqual(Start), 'copie C');
  Check(A.IsEqual(Start), 'opérande A');
  Check(B.IsEqual(THighFloat.FromFloat(0.75, 6)), 'opérande B');
  CheckEquals(9, Last.FracWords, 'FracWords du dernier résultat');
  Check(S <> '', 'ToString');
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestFracWordsForPixelSize;
begin
  CheckEquals(4, FracWordsForPixelSize(1e-16));
  CheckEquals(34, FracWordsForPixelSize(1e-300));
  CheckEquals(2, FracWordsForPixelSize(1));
end;

{------------------------------------------------------------------------------}

procedure TTestHighFloat.TestOverflowRaises;
var
  A: THighFloat;
  IsRaised: Boolean;
begin
  A := THighFloat.FromFloat(3e9, 2);
  IsRaised := False;
  try
    A.Twice;
  except
    on EOverflow do
      IsRaised := True;
  end;
  Check(IsRaised, 'Add');
  IsRaised := False;
  try
    A.Mul(A);
  except
    on EOverflow do
      IsRaised := True;
  end;
  Check(IsRaised, 'Mul');
end;

initialization
  RegisterTest(TTestHighFloat.Suite);

end.
