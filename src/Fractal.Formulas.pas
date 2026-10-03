unit Fractal.Formulas;

interface

uses
  SysUtils, Math, Fractal.Types;

const
  kEscapeRadius2 = 65536.0;  // rayon d'échappement 256 : lissage précis
  kMinMaxIter = 16;
  kMaxMaxIter = 1000000;
  kDefaultMaxIter = 1000;

type
  TFormulaParam = record
    Name: string;
    Caption: string;
    DefaultValue: Double;
    MinValue: Double;
    MaxValue: Double;
  end;

  TFractalFormula = class;
  TFractalFormulaClass = class of TFractalFormula;

  TFractalFormula = class
  private
    FParamInfos: array of TFormulaParam;
    FParamValues: array of Double;
    FMaxIter: Integer;
    procedure SetMaxIter(Value: Integer);
  protected
    procedure DeclareParam(const AName, ACaption: string; ADefault, AMin, AMax: Double);
    procedure ParamsChanged; virtual;
    function SmoothValue(N: Integer; Modulus2, LogPower: TFloat): Single;
  public
    constructor Create; virtual;
    class function FormulaName: string; virtual; abstract;
    class function DisplayName: string; virtual; abstract;
    class function DefaultCenterX: TFloat; virtual;
    class function DefaultCenterY: TFloat; virtual;
    class function DefaultWidth: TFloat; virtual;
    function Clone: TFractalFormula;
    function Iterate(const CX, CY: TFloat): Single; virtual; abstract;
    function ParamCount: Integer;
    function ParamInfo(Index: Integer): TFormulaParam;
    function GetParam(Index: Integer): Double;
    procedure SetParam(Index: Integer; Value: Double);
    function IndexOfParam(const AName: string): Integer;
    property MaxIter: Integer read FMaxIter write SetMaxIter;
  end;

  TMandelbrotFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TMultibrotFormula = class(TFractalFormula)
  private
    FPower: TFloat;
    FLogPower: TFloat;
  protected
    procedure ParamsChanged; override;
  public
    constructor Create; override;
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultWidth: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TJuliaFormula = class(TFractalFormula)
  private
    FCX: TFloat;
    FCY: TFloat;
  protected
    procedure ParamsChanged; override;
  public
    constructor Create; override;
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultWidth: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TBurningShipFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    class function DefaultCenterY: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TTricornFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

procedure RegisterFormula(AClass: TFractalFormulaClass);
function FormulaClassCount: Integer;
function FormulaClassAt(Index: Integer): TFractalFormulaClass;
function FindFormulaClass(const AName: string): TFractalFormulaClass;

implementation

const
  kLn2 = 0.69314718055994530942;

var
  FormulaRegistry: array of TFractalFormulaClass;

{------------------------------------------------------------------------------}

constructor TFractalFormula.Create;
begin
  inherited Create;
  FMaxIter := kDefaultMaxIter;
end;

{------------------------------------------------------------------------------}

class function TFractalFormula.DefaultCenterX: TFloat;
begin
  Result := 0;
end;

{------------------------------------------------------------------------------}

class function TFractalFormula.DefaultCenterY: TFloat;
begin
  Result := 0;
end;

{------------------------------------------------------------------------------}

class function TFractalFormula.DefaultWidth: TFloat;
begin
  Result := kDefaultWidth;
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.SetMaxIter(Value: Integer);
begin
  FMaxIter := EnsureRange(Value, kMinMaxIter, kMaxMaxIter);
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.DeclareParam(const AName, ACaption: string; ADefault, AMin, AMax: Double);
var
  I: Integer;
begin
  I := Length(FParamInfos);
  SetLength(FParamInfos, I + 1);
  SetLength(FParamValues, I + 1);
  FParamInfos[I].Name := AName;
  FParamInfos[I].Caption := ACaption;
  FParamInfos[I].DefaultValue := ADefault;
  FParamInfos[I].MinValue := AMin;
  FParamInfos[I].MaxValue := AMax;
  FParamValues[I] := ADefault;
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.ParamsChanged;
begin
  // rien par défaut : les formules qui mettent des valeurs en cache le redéfinissent
end;

{------------------------------------------------------------------------------}

function TFractalFormula.SmoothValue(N: Integer; Modulus2, LogPower: TFloat): Single;
var
  Mu: TFloat;
begin
  Mu := N + 1 - Ln(0.5 * Ln(Modulus2)) / LogPower;
  if Mu < 0 then
    Mu := 0;
  Result := Mu;
end;

{------------------------------------------------------------------------------}

function TFractalFormula.Clone: TFractalFormula;
var
  I: Integer;
begin
  Result := TFractalFormulaClass(ClassType).Create;
  Result.MaxIter := FMaxIter;
  for I := 0 to High(FParamValues) do
    Result.SetParam(I, FParamValues[I]);
end;

{------------------------------------------------------------------------------}

function TFractalFormula.ParamCount: Integer;
begin
  Result := Length(FParamInfos);
end;

{------------------------------------------------------------------------------}

function TFractalFormula.ParamInfo(Index: Integer): TFormulaParam;
begin
  Result := FParamInfos[Index];
end;

{------------------------------------------------------------------------------}

function TFractalFormula.GetParam(Index: Integer): Double;
begin
  Result := FParamValues[Index];
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.SetParam(Index: Integer; Value: Double);
begin
  if (Index < 0) or (Index >= Length(FParamValues)) then
    raise Exception.CreateFmt('Paramètre %d inexistant pour %s', [Index, FormulaName]);
  if IsNan(Value) then
    Value := FParamInfos[Index].DefaultValue;
  FParamValues[Index] := EnsureRange(Value, FParamInfos[Index].MinValue, FParamInfos[Index].MaxValue);
  ParamsChanged;
end;

{------------------------------------------------------------------------------}

function TFractalFormula.IndexOfParam(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FParamInfos) do
    if SameText(FParamInfos[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

{------------------------------------------------------------------------------}

class function TMandelbrotFormula.FormulaName: string;
begin
  Result := 'Mandelbrot';
end;

{------------------------------------------------------------------------------}

class function TMandelbrotFormula.DisplayName: string;
begin
  Result := 'Mandelbrot';
end;

{------------------------------------------------------------------------------}

class function TMandelbrotFormula.DefaultCenterX: TFloat;
begin
  Result := -0.5;
end;

{------------------------------------------------------------------------------}

function TMandelbrotFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2, Q: TFloat;
  N: Integer;
begin
  // cardioïde principale et bulbe de période 2 : intérieur garanti, inutile d'itérer
  Q := (CX - 0.25) * (CX - 0.25) + CY * CY;
  if (Q * (Q + (CX - 0.25)) <= 0.25 * CY * CY) or ((CX + 1) * (CX + 1) + CY * CY <= 0.0625) then
    Exit(kInside);
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    Y := 2 * X * Y + CY;
    X := X2 - Y2 + CX;
    Inc(N);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

constructor TMultibrotFormula.Create;
begin
  inherited Create;
  DeclareParam('power', 'Puissance n', 3, 1.5, 10);
  ParamsChanged;
end;

{------------------------------------------------------------------------------}

class function TMultibrotFormula.FormulaName: string;
begin
  Result := 'Multibrot';
end;

{------------------------------------------------------------------------------}

class function TMultibrotFormula.DisplayName: string;
begin
  Result := 'Multibrot (z^n)';
end;

{------------------------------------------------------------------------------}

class function TMultibrotFormula.DefaultWidth: TFloat;
begin
  Result := 3.0;
end;

{------------------------------------------------------------------------------}

procedure TMultibrotFormula.ParamsChanged;
begin
  FPower := GetParam(0);
  FLogPower := Ln(FPower);
end;

{------------------------------------------------------------------------------}

function TMultibrotFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, M, R, T: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    M := X * X + Y * Y;
    if M > kEscapeRadius2 then
      Exit(SmoothValue(N, M, FLogPower));
    if M = 0 then
    begin
      X := CX;
      Y := CY;
    end
    else
    begin
      // z^n en polaire : accepte une puissance non entière
      R := Exp(0.5 * Ln(M) * FPower);
      T := ArcTan2(Y, X) * FPower;
      X := R * Cos(T) + CX;
      Y := R * Sin(T) + CY;
    end;
    Inc(N);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

constructor TJuliaFormula.Create;
begin
  inherited Create;
  DeclareParam('cx', 'c (réel)', -0.8, -2, 2);
  DeclareParam('cy', 'c (imaginaire)', 0.156, -2, 2);
  ParamsChanged;
end;

{------------------------------------------------------------------------------}

class function TJuliaFormula.FormulaName: string;
begin
  Result := 'Julia';
end;

{------------------------------------------------------------------------------}

class function TJuliaFormula.DisplayName: string;
begin
  Result := 'Julia';
end;

{------------------------------------------------------------------------------}

class function TJuliaFormula.DefaultWidth: TFloat;
begin
  Result := 3.5;
end;

{------------------------------------------------------------------------------}

procedure TJuliaFormula.ParamsChanged;
begin
  FCX := GetParam(0);
  FCY := GetParam(1);
end;

{------------------------------------------------------------------------------}

function TJuliaFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2: TFloat;
  N: Integer;
begin
  X := CX;
  Y := CY;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    Y := 2 * X * Y + FCY;
    X := X2 - Y2 + FCX;
    Inc(N);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

class function TBurningShipFormula.FormulaName: string;
begin
  Result := 'BurningShip';
end;

{------------------------------------------------------------------------------}

class function TBurningShipFormula.DisplayName: string;
begin
  Result := 'Burning Ship';
end;

{------------------------------------------------------------------------------}

class function TBurningShipFormula.DefaultCenterX: TFloat;
begin
  Result := -0.45;
end;

{------------------------------------------------------------------------------}

class function TBurningShipFormula.DefaultCenterY: TFloat;
begin
  Result := 0.5;
end;

{------------------------------------------------------------------------------}

function TBurningShipFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    // - CY : le navire apparaît à l'endroit avec un axe imaginaire qui monte
    Y := 2 * Abs(X * Y) - CY;
    X := X2 - Y2 + CX;
    Inc(N);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

class function TTricornFormula.FormulaName: string;
begin
  Result := 'Tricorn';
end;

{------------------------------------------------------------------------------}

class function TTricornFormula.DisplayName: string;
begin
  Result := 'Tricorn';
end;

{------------------------------------------------------------------------------}

class function TTricornFormula.DefaultCenterX: TFloat;
begin
  Result := -0.3;
end;

{------------------------------------------------------------------------------}

function TTricornFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    Y := -2 * X * Y + CY;
    X := X2 - Y2 + CX;
    Inc(N);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

procedure RegisterFormula(AClass: TFractalFormulaClass);
begin
  SetLength(FormulaRegistry, Length(FormulaRegistry) + 1);
  FormulaRegistry[High(FormulaRegistry)] := AClass;
end;

{------------------------------------------------------------------------------}

function FormulaClassCount: Integer;
begin
  Result := Length(FormulaRegistry);
end;

{------------------------------------------------------------------------------}

function FormulaClassAt(Index: Integer): TFractalFormulaClass;
begin
  Result := FormulaRegistry[Index];
end;

{------------------------------------------------------------------------------}

function FindFormulaClass(const AName: string): TFractalFormulaClass;
var
  I: Integer;
begin
  for I := 0 to High(FormulaRegistry) do
    if SameText(FormulaRegistry[I].FormulaName, AName) then
      Exit(FormulaRegistry[I]);
  Result := nil;
end;

initialization
  RegisterFormula(TMandelbrotFormula);
  RegisterFormula(TMultibrotFormula);
  RegisterFormula(TJuliaFormula);
  RegisterFormula(TBurningShipFormula);
  RegisterFormula(TTricornFormula);

end.
