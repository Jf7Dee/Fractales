unit Fractal.Types;

interface

uses
  SysUtils, Fractal.HighFloat;

const
  kExtendedEpsilon = 1.0842021724855044e-19;  // 2^-63 : un ulp relatif en Extended (moteur Delphi)
  kDoubleEpsilon = 2.2204460492503131e-16;    // 2^-52 : un ulp relatif en Double (moteur Rust)

type
  TFloat = Fractal.HighFloat.TFloat;

  TComplexPoint = record
    X, Y: TFloat;
  end;

  TPrecisionState = (psOk, psWarning, psLimit);

  // Fenêtre sur le plan complexe. Le pixel (PX, PY) a son centre en PX + 0,5 ; l'axe imaginaire monte.
  TViewport = record
  private
    FExactX, FExactY: THighFloat;
    FCenterX, FCenterY: TFloat;   // approximations tenues à jour avec le centre exact
    function WordsForPixelSize(NewPixelSize: TFloat): Integer;
  public
    Width: TFloat;
    PixelWidth, PixelHeight: Integer;
    procedure SetCenter(const X, Y: THighFloat);
    function PixelOffset(PX, PY: TFloat): TComplexPoint;   // écart au centre exact, en TFloat
    function IsSameView(const B: TViewport): Boolean;   // centre exact, largeur et taille en pixels
    function PixelSize: TFloat;
    function Height: TFloat;
    function Zoom: TFloat;
    function PixelToComplex(PX, PY: TFloat): TComplexPoint;
    function ComplexToPixel(const P: TComplexPoint): TComplexPoint;
    function ZoomedAt(PX, PY, Factor: TFloat): TViewport;
    function Panned(DX, DY: Integer): TViewport;
    function FittedToRect(X1, Y1, X2, Y2: Integer): TViewport;
    function Resized(APixelWidth, APixelHeight: Integer): TViewport;
    function SubViewport(Supersample, Row0, Rows: Integer): TViewport;
    function PrecisionState(Epsilon: TFloat = kExtendedEpsilon): TPrecisionState;
    property CenterX: TFloat read FCenterX;
    property CenterY: TFloat read FCenterY;
    property ExactCenterX: THighFloat read FExactX;
    property ExactCenterY: THighFloat read FExactY;
  end;

const
  kInside = -1.0;
  kNotComputed = -2.0;
  kDefaultWidth = 4.0;

function MakeViewport(ACenterX, ACenterY, AWidth: TFloat; APixelWidth, APixelHeight: Integer): TViewport;
function AutoMaxIter(const V: TViewport): Integer;
function FloatToInvariant(Value: TFloat): string;
function InvariantToFloat(const S: string; Default: TFloat): TFloat;

implementation

uses
  Math;

const
  kMinWords = 2;                              // mots de fraction au minimum (voir Fractal.HighFloat)
  kLimitUlps = 64;                            // en dessous de 64 ulps par pixel, l'image se pixelise
  kWarningFactor = 8;
  kInvariantPrecision = 18;
  kAutoIterBase = 250;
  kAutoIterScale = 150;
  kAutoIterExponent = 1.4;
  kAutoIterMax = 1000000;
  kEnglishLocale = 1033;

var
  InvariantSettings: TFormatSettings;

{------------------------------------------------------------------------------}

function TViewport.PixelSize: TFloat;
begin
  Result := Width / PixelWidth;
end;

{------------------------------------------------------------------------------}

function TViewport.Height: TFloat;
begin
  Result := PixelSize * PixelHeight;
end;

{------------------------------------------------------------------------------}

function TViewport.Zoom: TFloat;
begin
  Result := kDefaultWidth / Width;
end;

{------------------------------------------------------------------------------}

function TViewport.PixelToComplex(PX, PY: TFloat): TComplexPoint;
var
  S: TFloat;
begin
  S := PixelSize;
  Result.X := FCenterX + (PX + 0.5 - PixelWidth / 2) * S;
  Result.Y := FCenterY - (PY + 0.5 - PixelHeight / 2) * S;
end;

{------------------------------------------------------------------------------}

function TViewport.ComplexToPixel(const P: TComplexPoint): TComplexPoint;
var
  S: TFloat;
begin
  S := PixelSize;
  Result.X := (P.X - CenterX) / S + PixelWidth / 2 - 0.5;
  Result.Y := (CenterY - P.Y) / S + PixelHeight / 2 - 0.5;
end;

{------------------------------------------------------------------------------}

function TViewport.ZoomedAt(PX, PY, Factor: TFloat): TViewport;
var
  D: TComplexPoint;
  Words: Integer;
begin
  // le point sous (PX, PY) reste immobile : nouveau centre = centre + D * (1 - 1 / Factor)
  D := PixelOffset(PX, PY);
  Result := Self;
  Result.Width := Width / Factor;
  Words := WordsForPixelSize(Result.PixelSize);
  Result.SetCenter(FExactX.AddFloat(D.X * (1 - 1 / Factor), Words), FExactY.AddFloat(D.Y * (1 - 1 / Factor), Words));
end;

{------------------------------------------------------------------------------}

function TViewport.Panned(DX, DY: Integer): TViewport;
var
  Words: Integer;
begin
  // le contenu se déplace de (DX, DY) pixels
  Result := Self;
  Words := WordsForPixelSize(PixelSize);
  Result.SetCenter(FExactX.AddFloat(-DX * PixelSize, Words), FExactY.AddFloat(DY * PixelSize, Words));
end;

{------------------------------------------------------------------------------}

function TViewport.FittedToRect(X1, Y1, X2, Y2: Integer): TViewport;
var
  T: Integer;
  C: TComplexPoint;
  Words: Integer;
begin
  if X1 > X2 then
  begin
    T := X1;
    X1 := X2;
    X2 := T;
  end;
  if Y1 > Y2 then
  begin
    T := Y1;
    Y1 := Y2;
    Y2 := T;
  end;
  if X2 - X1 < 1 then
    Exit(Self);
  C := PixelOffset((X1 + X2) / 2 - 0.5, (Y1 + Y2) / 2 - 0.5);
  Result := Self;
  Result.Width := (X2 - X1) * PixelSize;
  Words := WordsForPixelSize(Result.PixelSize);
  Result.SetCenter(FExactX.AddFloat(C.X, Words), FExactY.AddFloat(C.Y, Words));
end;

{------------------------------------------------------------------------------}

function TViewport.Resized(APixelWidth, APixelHeight: Integer): TViewport;
begin
  Result := Self;
  Result.PixelWidth := Max(1, APixelWidth);
  Result.PixelHeight := Max(1, APixelHeight);
end;

{------------------------------------------------------------------------------}

function TViewport.SubViewport(Supersample, Row0, Rows: Integer): TViewport;
var
  Words: Integer;
  DY: TFloat;
begin
  // bande de lignes [Row0, Row0 + Rows) de l'image, suréchantillonnée Supersample x Supersample
  DY := -(Row0 + Rows / 2 - PixelHeight / 2) * PixelSize;
  Result := Self;
  Result.PixelWidth := PixelWidth * Supersample;
  Result.PixelHeight := Rows * Supersample;
  Words := WordsForPixelSize(Result.PixelSize);
  Result.SetCenter(FExactX.WithFracWords(Words), FExactY.AddFloat(DY, Words));
end;

{------------------------------------------------------------------------------}

function TViewport.PrecisionState(Epsilon: TFloat): TPrecisionState;
var
  MinSize: TFloat;
begin
  MinSize := kLimitUlps * Epsilon * Max(1.0, Max(Abs(CenterX), Abs(CenterY)));
  if PixelSize < MinSize then
    Result := psLimit
  else if PixelSize < MinSize * kWarningFactor then
    Result := psWarning
  else
    Result := psOk;
end;

{------------------------------------------------------------------------------}

procedure TViewport.SetCenter(const X, Y: THighFloat);
begin
  FExactX := X;
  FExactY := Y;
  FCenterX := X.ToFloat;
  FCenterY := Y.ToFloat;
end;

{------------------------------------------------------------------------------}

function TViewport.PixelOffset(PX, PY: TFloat): TComplexPoint;
var
  S: TFloat;
begin
  S := PixelSize;
  Result.X := (PX + 0.5 - PixelWidth / 2) * S;
  Result.Y := -(PY + 0.5 - PixelHeight / 2) * S;
end;

{------------------------------------------------------------------------------}

function TViewport.IsSameView(const B: TViewport): Boolean;
begin
  Result := FExactX.IsEqual(B.FExactX) and FExactY.IsEqual(B.FExactY) and (Width = B.Width)
    and (PixelWidth = B.PixelWidth) and (PixelHeight = B.PixelHeight);
end;

{------------------------------------------------------------------------------}

function TViewport.WordsForPixelSize(NewPixelSize: TFloat): Integer;
begin
  // jamais moins de mots que le centre actuel ; une taille de pixel nulle ou négative n'ajoute rien
  Result := Max(FExactX.FracWords, FExactY.FracWords);
  if NewPixelSize > 0 then
    Result := Max(Result, FracWordsForPixelSize(NewPixelSize));
end;

{------------------------------------------------------------------------------}

function MakeViewport(ACenterX, ACenterY, AWidth: TFloat; APixelWidth, APixelHeight: Integer): TViewport;
var
  Words: Integer;
begin
  Result.Width := AWidth;
  Result.PixelWidth := Max(1, APixelWidth);
  Result.PixelHeight := Max(1, APixelHeight);
  Words := kMinWords;
  if Result.PixelSize > 0 then
    Words := FracWordsForPixelSize(Result.PixelSize);
  Result.SetCenter(THighFloat.FromFloat(ACenterX, Words), THighFloat.FromFloat(ACenterY, Words));
end;

{------------------------------------------------------------------------------}

function AutoMaxIter(const V: TViewport): Integer;
begin
  Result := kAutoIterBase + Round(kAutoIterScale * Power(Log10(Max(1.0, V.Zoom)), kAutoIterExponent));
  Result := Min(Result, kAutoIterMax);
end;

{------------------------------------------------------------------------------}

function FloatToInvariant(Value: TFloat): string;
begin
  Result := FloatToStrF(Value, ffGeneral, kInvariantPrecision, 0, InvariantSettings);
end;

{------------------------------------------------------------------------------}

function InvariantToFloat(const S: string; Default: TFloat): TFloat;
var
  E: Extended;
begin
  if TryStrToFloat(Trim(S), E, InvariantSettings) and not IsNan(E) and not IsInfinite(E) then
    Result := E
  else
    Result := Default;
end;

initialization
  // TFormatSettings.Create apparaît avec Delphi XE ; D2010 n'a que GetLocaleFormatSettings
  {$IF CompilerVersion >= 22}
  InvariantSettings := TFormatSettings.Create(kEnglishLocale);
  {$ELSE}
  GetLocaleFormatSettings(kEnglishLocale, InvariantSettings);
  {$IFEND}
  InvariantSettings.DecimalSeparator := '.';
  InvariantSettings.ThousandSeparator := ',';

end.
