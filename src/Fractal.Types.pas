unit Fractal.Types;

interface

uses
  SysUtils;

type
  TFloat = Extended;

  TComplexPoint = record
    X, Y: TFloat;
  end;

  TPrecisionState = (psOk, psWarning, psLimit);

  // Fenêtre sur le plan complexe. Le pixel (PX, PY) a son centre en PX + 0,5 ; l'axe imaginaire monte.
  TViewport = record
    CenterX, CenterY: TFloat;
    Width: TFloat;
    PixelWidth, PixelHeight: Integer;
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
    function PrecisionState: TPrecisionState;
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
  kExtendedEpsilon = 1.0842021724855044e-19;  // 2^-63 : un ulp relatif en Extended
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
  Result.X := CenterX + (PX + 0.5 - PixelWidth / 2) * S;
  Result.Y := CenterY - (PY + 0.5 - PixelHeight / 2) * S;
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
  P: TComplexPoint;
begin
  // le point sous (PX, PY) reste immobile
  P := PixelToComplex(PX, PY);
  Result := Self;
  Result.Width := Width / Factor;
  Result.CenterX := P.X + (CenterX - P.X) / Factor;
  Result.CenterY := P.Y + (CenterY - P.Y) / Factor;
end;

{------------------------------------------------------------------------------}

function TViewport.Panned(DX, DY: Integer): TViewport;
begin
  // le contenu se déplace de (DX, DY) pixels
  Result := Self;
  Result.CenterX := CenterX - DX * PixelSize;
  Result.CenterY := CenterY + DY * PixelSize;
end;

{------------------------------------------------------------------------------}

function TViewport.FittedToRect(X1, Y1, X2, Y2: Integer): TViewport;
var
  T: Integer;
  C: TComplexPoint;
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
  C := PixelToComplex((X1 + X2) / 2 - 0.5, (Y1 + Y2) / 2 - 0.5);
  Result := Self;
  Result.CenterX := C.X;
  Result.CenterY := C.Y;
  Result.Width := (X2 - X1) * PixelSize;
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
begin
  // bande de lignes [Row0, Row0 + Rows) de l'image, suréchantillonnée Supersample x Supersample
  Result := Self;
  Result.PixelWidth := PixelWidth * Supersample;
  Result.PixelHeight := Rows * Supersample;
  Result.CenterY := CenterY - (Row0 + Rows / 2 - PixelHeight / 2) * PixelSize;
end;

{------------------------------------------------------------------------------}

function TViewport.PrecisionState: TPrecisionState;
var
  MinSize: TFloat;
begin
  MinSize := kLimitUlps * kExtendedEpsilon * Max(1.0, Max(Abs(CenterX), Abs(CenterY)));
  if PixelSize < MinSize then
    Result := psLimit
  else if PixelSize < MinSize * kWarningFactor then
    Result := psWarning
  else
    Result := psOk;
end;

{------------------------------------------------------------------------------}

function MakeViewport(ACenterX, ACenterY, AWidth: TFloat; APixelWidth, APixelHeight: Integer): TViewport;
begin
  Result.CenterX := ACenterX;
  Result.CenterY := ACenterY;
  Result.Width := AWidth;
  Result.PixelWidth := Max(1, APixelWidth);
  Result.PixelHeight := Max(1, APixelHeight);
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
