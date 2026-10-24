unit Fractal.HighFloat;

// Réel à virgule fixe en haute précision, pour le centre de vue des zooms profonds et l'orbite de référence.

interface

uses
  SysUtils, Math;

type
  TFloat = Extended;

  THighWords = array of Cardinal;

  // Réel à virgule fixe, signe + grandeur : FWords[0] = partie entière, FWords[1..FracWords] = fraction
  // (poids fort d'abord). Valeur immuable : aucune opération ne modifie ses opérandes ni un tableau partagé.
  THighFloat = record
  private
    FIsNegative: Boolean;
    FWords: THighWords;
  public
    class function Zero(AFracWords: Integer): THighFloat; static;
    class function FromFloat(Value: TFloat; AFracWords: Integer): THighFloat; static;
    class function TryParse(const S: string; AFracWords: Integer; out Value: THighFloat): Boolean; static;
    function FracWords: Integer;
    function WithFracWords(AFracWords: Integer): THighFloat;   // tronque ou complète par des zéros
    function Add(const B: THighFloat): THighFloat;
    function Sub(const B: THighFloat): THighFloat;
    function Mul(const B: THighFloat): THighFloat;
    function Sqr: THighFloat;
    function Twice: THighFloat;
    function Abs: THighFloat;
    function AddFloat(Value: TFloat; AFracWords: Integer): THighFloat;
    function ToFloat: TFloat;
    function ToString(Digits: Integer): string;   // décimal, Digits chiffres après le point, point « . »
    function IsEqual(const B: THighFloat): Boolean;
  end;

function FracWordsForPixelSize(PixelSize: TFloat): Integer;   // ceil((-log2(PixelSize) + 64) / 32), au moins 2

implementation

const
  kWordBits = 32;
  kWordBase = 4294967296.0;                   // 2^32
  kWordBaseInteger: UInt64 = 4294967296;      // 2^32, pour le calcul entier
  kWordMask = $FFFFFFFF;                      // mot de poids faible d'un UInt64
  kMantissaBits = 64;                         // mantisse d'un Extended
  kMinFracWords = 2;
  kExtraBits = 64;                            // bits de garde au-delà de la taille de pixel
  kMaxExponent10 = 10000;                     // exposant décimal toléré par TryParse
  kMaxExponentDigits = 6;                     // chiffres d'exposant lus par TryParse : au-delà, hors kMaxExponent10
  kMaxIntegerDigits = 10;                     // 2^32 - 1 = 4294967295
  kRoundDigit = 5;

{------------------------------------------------------------------------------}

procedure RaiseBadFracWords;
begin
  raise EArgumentException.Create('THighFloat : nombre de mots de fraction négatif');
end;

{------------------------------------------------------------------------------}

procedure RaiseOverflow;
begin
  raise EOverflow.Create('THighFloat : dépassement de la partie entière');
end;

{------------------------------------------------------------------------------}

// Copie de A sur N mots (complétée par des zéros ou tronquée) ; toujours un tableau neuf.
function PadWords(const A: THighWords; N: Integer): THighWords;
var
  I: Integer;
begin
  SetLength(Result, N);
  for I := 0 to Min(N, Length(A)) - 1 do
    Result[I] := A[I];
end;

{------------------------------------------------------------------------------}

function IsZeroMagnitude(const A: THighWords): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(A) do
    if A[I] <> 0 then
      Exit;
  Result := True;
end;

{------------------------------------------------------------------------------}

// A et B ont le même nombre de mots.
function CompareMagnitude(const A, B: THighWords): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(A) do
    if A[I] <> B[I] then
    begin
      if A[I] > B[I] then
        Result := 1
      else
        Result := -1;
      Exit;
    end;
end;

{------------------------------------------------------------------------------}

// A et B ont le même nombre de mots. Lève EOverflow si la retenue sort de la partie entière.
function AddMagnitude(const A, B: THighWords): THighWords;
var
  I: Integer;
  Sum, Carry: UInt64;
begin
  SetLength(Result, Length(A));
  Carry := 0;
  for I := High(A) downto 0 do
  begin
    Sum := UInt64(A[I]) + B[I] + Carry;
    Result[I] := Cardinal(Sum and kWordMask);
    Carry := Sum shr kWordBits;
  end;
  if Carry <> 0 then
    RaiseOverflow;
end;

{------------------------------------------------------------------------------}

// A et B ont le même nombre de mots et A >= B.
function SubMagnitude(const A, B: THighWords): THighWords;
var
  I: Integer;
  Diff: Int64;
  Borrow: Integer;
begin
  SetLength(Result, Length(A));
  Borrow := 0;
  for I := High(A) downto 0 do
  begin
    Diff := Int64(A[I]) - B[I] - Borrow;
    if Diff < 0 then
    begin
      Diff := Diff + Int64(1) shl kWordBits;
      Borrow := 1;
    end
    else
      Borrow := 0;
    Result[I] := Cardinal(Diff);
  end;
end;

{------------------------------------------------------------------------------}

function MakeValue(IsNegative: Boolean; const AWords: THighWords): THighFloat;
begin
  Result.FWords := AWords;
  Result.FIsNegative := IsNegative and not IsZeroMagnitude(AWords);   // pas de zéro négatif
end;

{------------------------------------------------------------------------------}

class function THighFloat.Zero(AFracWords: Integer): THighFloat;
var
  W: THighWords;
begin
  if AFracWords < 0 then
    RaiseBadFracWords;
  SetLength(W, AFracWords + 1);
  Result := MakeValue(False, W);
end;

{------------------------------------------------------------------------------}

class function THighFloat.FromFloat(Value: TFloat; AFracWords: Integer): THighFloat;
var
  W: THighWords;
  N, B, Pos, E: Integer;
  M, Rem: TFloat;
  Hi, Lo: Int64;
  IsBitSet: Boolean;
begin
  if AFracWords < 0 then
    RaiseBadFracWords;
  if IsNan(Value) or IsInfinite(Value) then
    raise EArgumentException.Create('THighFloat : valeur non finie');
  N := AFracWords + 1;
  SetLength(W, N);
  if Value <> 0 then
  begin
    Frexp(System.Abs(Value), M, E);           // |Value| = M * 2^E, M dans [0,5 ; 1[
    M := M * kWordBase;
    Hi := Trunc(M);
    Rem := (M - Hi) * kWordBase;
    Lo := Trunc(Rem);                         // mantisse = Hi * 2^32 + Lo, exacte sur 64 bits
    for B := 0 to kMantissaBits - 1 do
    begin
      if B >= kWordBits then
        IsBitSet := ((Hi shr (B - kWordBits)) and 1) <> 0
      else
        IsBitSet := ((Lo shr B) and 1) <> 0;
      if not IsBitSet then
        Continue;
      Pos := B + E - kMantissaBits + kWordBits * AFracWords;   // rang du bit, 0 = poids faible de la fraction
      if Pos < 0 then
        Continue;                             // sous la résolution : tronqué
      if Pos >= kWordBits * N then
        RaiseOverflow;
      W[N - 1 - Pos div kWordBits] := W[N - 1 - Pos div kWordBits] or (Cardinal(1) shl (Pos mod kWordBits));
    end;
  end;
  Result := MakeValue(Value < 0, W);
end;

{------------------------------------------------------------------------------}

class function THighFloat.TryParse(const S: string; AFracWords: Integer; out Value: THighFloat): Boolean;
var
  I, Len, Exp10, PointPos, K, WordIdx, ExpDigits: Integer;
  IsNeg, IsExpNeg: Boolean;
  IntDigits, FracDigits, AllDigits, IntPart, Dec: string;
  Digits: array of Byte;
  IntValue: Int64;
  Carry, T: UInt64;
  W: THighWords;
begin
  Result := False;
  Value := Zero(Max(AFracWords, 0));
  if AFracWords < 0 then
    Exit;
  Len := Length(S);
  I := 1;
  IsNeg := False;
  if (I <= Len) and ((S[I] = '-') or (S[I] = '+')) then
  begin
    IsNeg := S[I] = '-';
    Inc(I);
  end;
  while (I <= Len) and (S[I] >= '0') and (S[I] <= '9') do
  begin
    IntDigits := IntDigits + S[I];
    Inc(I);
  end;
  if (I <= Len) and (S[I] = '.') then
  begin
    Inc(I);
    while (I <= Len) and (S[I] >= '0') and (S[I] <= '9') do
    begin
      FracDigits := FracDigits + S[I];
      Inc(I);
    end;
  end;
  if (IntDigits = '') and (FracDigits = '') then
    Exit;
  Exp10 := 0;
  if (I <= Len) and ((S[I] = 'e') or (S[I] = 'E')) then
  begin
    Inc(I);
    IsExpNeg := False;
    if (I <= Len) and ((S[I] = '-') or (S[I] = '+')) then
    begin
      IsExpNeg := S[I] = '-';
      Inc(I);
    end;
    ExpDigits := 0;
    while (I <= Len) and (S[I] >= '0') and (S[I] <= '9') do
    begin
      if ExpDigits < kMaxExponentDigits then
        Exp10 := Exp10 * 10 + Ord(S[I]) - Ord('0');
      Inc(ExpDigits);
      Inc(I);
    end;
    if ExpDigits = 0 then
      Exit;
    if IsExpNeg then
      Exp10 := -Exp10;
  end;
  if I <= Len then
    Exit;                                     // caractères en trop
  if System.Abs(Exp10) > kMaxExponent10 then
    Exit;

  AllDigits := IntDigits + FracDigits;
  PointPos := Length(IntDigits) + Exp10;      // nombre de chiffres de AllDigits avant le point
  if PointPos <= 0 then
  begin
    IntPart := '';
    Dec := StringOfChar('0', -PointPos) + AllDigits;
  end
  else if PointPos >= Length(AllDigits) then
  begin
    IntPart := AllDigits + StringOfChar('0', PointPos - Length(AllDigits));
    Dec := '';
  end
  else
  begin
    IntPart := Copy(AllDigits, 1, PointPos);
    Dec := Copy(AllDigits, PointPos + 1, MaxInt);
  end;
  K := 1;
  while (K < Length(IntPart)) and (IntPart[K] = '0') do
    Inc(K);
  IntPart := Copy(IntPart, K, MaxInt);
  if Length(IntPart) > kMaxIntegerDigits then
    Exit;
  IntValue := 0;
  for K := 1 to Length(IntPart) do
    IntValue := IntValue * 10 + Ord(IntPart[K]) - Ord('0');
  if IntValue > High(Cardinal) then
    Exit;

  SetLength(W, AFracWords + 1);
  W[0] := Cardinal(IntValue);
  SetLength(Digits, Length(Dec));
  for K := 1 to Length(Dec) do
    Digits[K - 1] := Ord(Dec[K]) - Ord('0');
  for WordIdx := 1 to AFracWords do
  begin
    Carry := 0;                               // fraction décimale * 2^32 : la retenue finale est le mot suivant
    for K := High(Digits) downto 0 do
    begin
      T := UInt64(Digits[K]) * kWordBaseInteger + Carry;
      Digits[K] := Byte(T mod 10);
      Carry := T div 10;
    end;
    W[WordIdx] := Cardinal(Carry);
  end;
  Value := MakeValue(IsNeg, W);
  Result := True;
end;

{------------------------------------------------------------------------------}

function THighFloat.FracWords: Integer;
begin
  Result := Max(Length(FWords) - 1, 0);
end;

{------------------------------------------------------------------------------}

function THighFloat.WithFracWords(AFracWords: Integer): THighFloat;
begin
  if AFracWords < 0 then
    RaiseBadFracWords;
  Result := MakeValue(FIsNegative, PadWords(FWords, AFracWords + 1));
end;

{------------------------------------------------------------------------------}

function THighFloat.Add(const B: THighFloat): THighFloat;
var
  N: Integer;
  WA, WB: THighWords;
begin
  N := Max(FracWords, B.FracWords) + 1;
  WA := PadWords(FWords, N);
  WB := PadWords(B.FWords, N);
  if FIsNegative = B.FIsNegative then
    Result := MakeValue(FIsNegative, AddMagnitude(WA, WB))
  else if CompareMagnitude(WA, WB) >= 0 then
    Result := MakeValue(FIsNegative, SubMagnitude(WA, WB))
  else
    Result := MakeValue(B.FIsNegative, SubMagnitude(WB, WA));
end;

{------------------------------------------------------------------------------}

function THighFloat.Sub(const B: THighFloat): THighFloat;
var
  Negated: THighFloat;
begin
  Negated.FWords := B.FWords;                 // tableau partagé, jamais écrit
  Negated.FIsNegative := not B.FIsNegative;
  Result := Add(Negated);
end;

{------------------------------------------------------------------------------}

function THighFloat.Mul(const B: THighFloat): THighFloat;
var
  F, N, I, J: Integer;
  WA, WB, P, R: THighWords;
  T, Carry: UInt64;
begin
  F := Max(FracWords, B.FracWords);
  N := F + 1;
  WA := PadWords(FWords, N);
  WB := PadWords(B.FWords, N);
  SetLength(P, 2 * N);                        // produit entier, poids faible d'abord (indices inversés)
  for I := 0 to N - 1 do
  begin
    Carry := 0;
    for J := 0 to N - 1 do
    begin
      T := UInt64(WA[N - 1 - I]) * WB[N - 1 - J] + P[I + J] + Carry;
      P[I + J] := Cardinal(T and kWordMask);
      Carry := T shr kWordBits;
    end;
    P[I + N] := Cardinal(Carry);
  end;
  if P[2 * N - 1] <> 0 then
    RaiseOverflow;
  SetLength(R, N);                            // on retire F mots de fraction : troncature vers zéro
  for I := 0 to N - 1 do
    R[N - 1 - I] := P[F + I];
  Result := MakeValue(FIsNegative <> B.FIsNegative, R);
end;

{------------------------------------------------------------------------------}

function THighFloat.Sqr: THighFloat;
begin
  Result := Mul(Self);
end;

{------------------------------------------------------------------------------}

function THighFloat.Twice: THighFloat;
begin
  Result := Add(Self);
end;

{------------------------------------------------------------------------------}

function THighFloat.Abs: THighFloat;
begin
  Result := MakeValue(False, FWords);   // signe et grandeur : il suffit de retirer le signe
end;

{------------------------------------------------------------------------------}

function THighFloat.AddFloat(Value: TFloat; AFracWords: Integer): THighFloat;
begin
  Result := Add(FromFloat(Value, AFracWords));
end;

{------------------------------------------------------------------------------}

function THighFloat.ToFloat: TFloat;
var
  I: Integer;
  Acc: TFloat;
begin
  Acc := 0;
  for I := 0 to High(FWords) do
    Acc := Acc * kWordBase + FWords[I];
  Result := Ldexp(Acc, -kWordBits * FracWords);
  if FIsNegative then
    Result := -Result;
end;

{------------------------------------------------------------------------------}

function THighFloat.ToString(Digits: Integer): string;
var
  Fr: THighWords;
  Dg: array of Byte;
  I, K: Integer;
  Carry, T: UInt64;
  IntPart: Int64;
  IsNonZero: Boolean;
begin
  if Digits < 0 then
    Digits := 0;
  Fr := PadWords(FWords, FracWords + 1);
  SetLength(Dg, Digits + 1);                  // un chiffre de plus, pour l'arrondi au plus proche
  for I := 0 to Digits do
  begin
    Carry := 0;
    for K := FracWords downto 1 do
    begin
      T := UInt64(Fr[K]) * 10 + Carry;
      Fr[K] := Cardinal(T and kWordMask);
      Carry := T shr kWordBits;
    end;
    Dg[I] := Byte(Carry);
  end;
  IntPart := 0;
  if Length(FWords) > 0 then
    IntPart := FWords[0];
  if Dg[Digits] >= kRoundDigit then
  begin
    K := Digits - 1;
    while (K >= 0) and (Dg[K] = 9) do
    begin
      Dg[K] := 0;
      Dec(K);
    end;
    if K >= 0 then
      Inc(Dg[K])
    else
      Inc(IntPart);
  end;
  IsNonZero := IntPart <> 0;
  Result := IntToStr(IntPart);
  if Digits > 0 then
    Result := Result + '.';
  for I := 0 to Digits - 1 do
  begin
    Result := Result + Chr(Ord('0') + Dg[I]);
    if Dg[I] <> 0 then
      IsNonZero := True;
  end;
  if FIsNegative and IsNonZero then
    Result := '-' + Result;
end;

{------------------------------------------------------------------------------}

function THighFloat.IsEqual(const B: THighFloat): Boolean;
var
  N: Integer;
begin
  N := Max(FracWords, B.FracWords) + 1;
  Result := (FIsNegative = B.FIsNegative) and (CompareMagnitude(PadWords(FWords, N), PadWords(B.FWords, N)) = 0);
end;

{------------------------------------------------------------------------------}

function FracWordsForPixelSize(PixelSize: TFloat): Integer;
begin
  if not (PixelSize > 0) then
    raise EArgumentException.Create('FracWordsForPixelSize : taille de pixel non positive');
  Result := Max(Ceil((-Log2(PixelSize) + kExtraBits) / kWordBits), kMinFracWords);
end;

end.
