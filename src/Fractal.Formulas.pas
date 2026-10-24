unit Fractal.Formulas;

interface

uses
  SysUtils, Math, Fractal.HighFloat, Fractal.Types;

const
  kEscapeRadius2 = 65536.0;  // rayon d'échappement 256 : lissage précis
  kMinMaxIter = 16;
  kMaxMaxIter = 1000000;
  kDefaultMaxIter = 1000;
  // identifiants des formules dans la DLL Rust (fk_compute_row)
  kKernelNone = -1;
  kKernelMandelbrot = 0;
  kKernelMultibrot = 1;
  kKernelJulia = 2;
  kKernelBurningShip = 3;
  kKernelTricorn = 4;
  kParamSliderSteps = 1000;  // crans du curseur d'un paramètre de formule
  // longueur minimale d'une orbite de référence : après le premier pas, la perturbation lit Orbit[1]
  kMinOrbitLength = 2;
  // puissance entière de Multibrot : seules 2..kMaxPerturbedPower sont perturbables, à kIntegerPowerTolerance près
  kMaxPerturbedPower = 10;
  kIntegerPowerTolerance = 1e-9;

type
  TFormulaParam = record
    Name: string;
    Caption: string;
    DefaultValue: Double;
    MinValue: Double;
    MaxValue: Double;
    IsIntegerSnapped: Boolean;  // le curseur aimante les valeurs proches d'un entier (puissance de Multibrot)
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
    procedure DeclareParam(const AName, ACaption: string; ADefault, AMin, AMax: Double;
      AIsIntegerSnapped: Boolean = False);
    procedure ParamsChanged; virtual;
    function SmoothValue(N: Integer; Modulus2, LogPower: TFloat): Single;
  public
    constructor Create; virtual;
    class function FormulaName: string; virtual; abstract;
    class function DisplayName: string; virtual; abstract;
    class function DefaultCenterX: TFloat; virtual;
    class function DefaultCenterY: TFloat; virtual;
    class function DefaultWidth: TFloat; virtual;
    class function KernelId: Integer; virtual;
    function Clone: TFractalFormula;
    function Iterate(const CX, CY: TFloat): Single; virtual; abstract;
    function IsPerturbationSupported: Boolean; virtual;
    // vrai si l'itération part du pixel (Z0 = pixel, c dans les paramètres : Julia) ; faux si Z0 = 0 et c = pixel
    class function HasPixelStart: Boolean; virtual;
    // un pas de l'orbite de référence, en haute précision ; lève une exception si non pris en charge
    procedure StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat); virtual;
    // vrai si le prochain pas donnerait un Z trop grand pour la partie entière de THighFloat (il échappe alors
    // forcément) : ce pas se fait en Extended par StepFloat, car seul son module compte (échappement, lissage)
    function ShouldStepInFloat(ZX, ZY: TFloat): Boolean; virtual;
    // le pas de la formule en Extended, pour les seuls cas où ShouldStepInFloat est vrai
    function StepFloat(ZX, ZY, CX, CY: TFloat): TComplexPoint; virtual;
    // pixel d'écart (DCX, DCY) à la référence ; Orbit[0] = 0 ; même convention de compte et de lissage qu'Iterate
    function IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single; virtual;
    // comme IteratePerturbed, avec l'orbite critique W (W0 = 0) des formules HasPixelStart, où (DX, DY) est δ0 =
    // pixel - référence ; par défaut, W est ignorée et l'appel revient à IteratePerturbed(Orbit, OrbitLength, DX, DY)
    function IteratePerturbedCritical(const Orbit: TOrbit; OrbitLength: Integer; const Critical: TOrbit;
      CriticalLength: Integer; DX, DY: TFloat): Single; virtual;
    function ParamCount: Integer;
    function ParamInfo(Index: Integer): TFormulaParam;
    function GetParam(Index: Integer): Double;
    procedure SetParam(Index: Integer; Value: Double);
    procedure ResetParams;
    function IndexOfParam(const AName: string): Integer;
    property MaxIter: Integer read FMaxIter write SetMaxIter;
  end;

  TMandelbrotFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    class function KernelId: Integer; override;
    function Iterate(const CX, CY: TFloat): Single; override;
    function IsPerturbationSupported: Boolean; override;
    procedure StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat); override;
    function IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single; override;
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
    class function KernelId: Integer; override;
    function Iterate(const CX, CY: TFloat): Single; override;
    function IsPerturbationSupported: Boolean; override;
    procedure StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat); override;
    function ShouldStepInFloat(ZX, ZY: TFloat): Boolean; override;
    function StepFloat(ZX, ZY, CX, CY: TFloat): TComplexPoint; override;
    function IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single; override;
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
    class function KernelId: Integer; override;
    function Iterate(const CX, CY: TFloat): Single; override;
    function IsPerturbationSupported: Boolean; override;
    class function HasPixelStart: Boolean; override;
    procedure StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat); override;
    function IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single; override;
    function IteratePerturbedCritical(const Orbit: TOrbit; OrbitLength: Integer; const Critical: TOrbit;
      CriticalLength: Integer; DX, DY: TFloat): Single; override;
  end;

  TBurningShipFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    class function DefaultCenterY: TFloat; override;
    class function KernelId: Integer; override;
    function Iterate(const CX, CY: TFloat): Single; override;
    function IsPerturbationSupported: Boolean; override;
    procedure StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat); override;
    function IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single; override;
  end;

  TTricornFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    class function KernelId: Integer; override;
    function Iterate(const CX, CY: TFloat): Single; override;
    function IsPerturbationSupported: Boolean; override;
    procedure StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat); override;
    function IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single; override;
  end;

procedure RegisterFormula(AClass: TFractalFormulaClass);
function FormulaClassCount: Integer;
function FormulaClassAt(Index: Integer): TFractalFormulaClass;
function FindFormulaClass(const AName: string): TFractalFormulaClass;
function ParamToSliderPosition(const Info: TFormulaParam; Value: Double): Integer;
function SliderPositionToParam(const Info: TFormulaParam; Position: Integer): Double;
// vrai si Power est un entier de 2 à kMaxPerturbedPower (tolérance kIntegerPowerTolerance)
function IsIntegerPower(Power: TFloat): Boolean;
// |c + d| - |c| sans perte de précision (Burning Ship perturbé) ; partagé avec la DLL factice des tests
function DiffAbs(C, D: TFloat): TFloat;

implementation

const
  kLn2 = 0.69314718055994530942;
  kNoPerturbationMessage = '%s : perturbation non prise en charge';
  kNotIntegerPowerMessage = 'Multibrot : puissance %g non entière, perturbation impossible';
  // |z|^p au-delà de 2^30 : proche de la limite de la partie entière de THighFloat (2^32), et déjà échappé
  kFloatStepLogBound = 30 * kLn2;
  kBadOrbitMessage = 'Orbite de référence invalide (longueur %d, tableau de %d points)';
  kNoCriticalOrbitMessage = 'Julia : la perturbation exige l''orbite critique (IteratePerturbedCritical)';

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

class function TFractalFormula.KernelId: Integer;
begin
  Result := kKernelNone;  // pas d'équivalent dans la DLL Rust : le moteur Delphi calcule
end;

{------------------------------------------------------------------------------}

function TFractalFormula.IsPerturbationSupported: Boolean;
begin
  Result := False;
end;

{------------------------------------------------------------------------------}

class function TFractalFormula.HasPixelStart: Boolean;
begin
  Result := False;
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat);
begin
  raise Exception.CreateFmt(kNoPerturbationMessage, [FormulaName]);
end;

{------------------------------------------------------------------------------}

function TFractalFormula.ShouldStepInFloat(ZX, ZY: TFloat): Boolean;
begin
  Result := False;
end;

{------------------------------------------------------------------------------}

function TFractalFormula.StepFloat(ZX, ZY, CX, CY: TFloat): TComplexPoint;
begin
  raise Exception.CreateFmt(kNoPerturbationMessage, [FormulaName]);
end;

{------------------------------------------------------------------------------}

function TFractalFormula.IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single;
begin
  raise Exception.CreateFmt(kNoPerturbationMessage, [FormulaName]);
end;

{------------------------------------------------------------------------------}

function TFractalFormula.IteratePerturbedCritical(const Orbit: TOrbit; OrbitLength: Integer; const Critical: TOrbit;
  CriticalLength: Integer; DX, DY: TFloat): Single;
begin
  // Z0 = 0 : le rebasage vers Z0 suffit, l'orbite critique ne sert pas
  Result := IteratePerturbed(Orbit, OrbitLength, DX, DY);
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.SetMaxIter(Value: Integer);
begin
  FMaxIter := EnsureRange(Value, kMinMaxIter, kMaxMaxIter);
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.DeclareParam(const AName, ACaption: string; ADefault, AMin, AMax: Double;
  AIsIntegerSnapped: Boolean);
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
  FParamInfos[I].IsIntegerSnapped := AIsIntegerSnapped;
  FParamValues[I] := ADefault;
end;

{------------------------------------------------------------------------------}

procedure TFractalFormula.ParamsChanged;
begin
  // rien par défaut : les formules qui mettent des valeurs en cache le redéfinissent
end;

{------------------------------------------------------------------------------}

// Garde commune aux IteratePerturbed : une orbite de moins de kMinOrbitLength points ou une longueur hors du
// tableau fausserait tout le calcul.
procedure CheckOrbit(const Orbit: TOrbit; OrbitLength: Integer);
begin
  if (OrbitLength < kMinOrbitLength) or (OrbitLength > Length(Orbit)) then
    raise EArgumentException.CreateFmt(kBadOrbitMessage, [OrbitLength, Length(Orbit)]);
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

procedure TFractalFormula.ResetParams;
var
  I: Integer;
begin
  // chaque paramètre reprend la valeur déclarée par DeclareParam ; MaxIter n'est pas touché
  for I := 0 to ParamCount - 1 do
    SetParam(I, FParamInfos[I].DefaultValue);
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

class function TMandelbrotFormula.KernelId: Integer;
begin
  Result := kKernelMandelbrot;
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

function TMandelbrotFormula.IsPerturbationSupported: Boolean;
begin
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TMandelbrotFormula.StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat);
var
  NewX, NewY: THighFloat;
begin
  // z := z^2 + c
  NewX := ZX.Sqr.Sub(ZY.Sqr).Add(CX);
  NewY := ZX.Mul(ZY).Twice.Add(CY);
  ZX := NewX;
  ZY := NewY;
end;

{------------------------------------------------------------------------------}

function TMandelbrotFormula.IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single;
var
  DX, DY, ZX, ZY, R2, NewDX, NewDY: TFloat;
  N, M: Integer;
begin
  CheckOrbit(Orbit, OrbitLength);
  DX := 0;
  DY := 0;
  N := 0;
  M := 0;
  while N < FMaxIter do
  begin
    ZX := Orbit[M].X + DX;
    ZY := Orbit[M].Y + DY;
    R2 := ZX * ZX + ZY * ZY;
    if R2 > kEscapeRadius2 then
      Exit(SmoothValue(N, R2, kLn2));
    if (R2 < DX * DX + DY * DY) or (M = OrbitLength - 1) then
    begin
      // rebasage : la référence redevient Z0 = 0
      DX := ZX;
      DY := ZY;
      M := 0;
    end;
    // δ' = 2·Z·δ + δ² + δc
    NewDX := 2 * (Orbit[M].X * DX - Orbit[M].Y * DY) + DX * DX - DY * DY + DCX;
    NewDY := 2 * (Orbit[M].X * DY + Orbit[M].Y * DX) + 2 * DX * DY + DCY;
    DX := NewDX;
    DY := NewDY;
    Inc(M);
    Inc(N);
  end;
  Result := kInside;
end;

{------------------------------------------------------------------------------}

constructor TMultibrotFormula.Create;
begin
  inherited Create;
  DeclareParam('power', 'Puissance n', 3, 1.5, 10, True);
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

class function TMultibrotFormula.KernelId: Integer;
begin
  Result := kKernelMultibrot;
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

function TMultibrotFormula.IsPerturbationSupported: Boolean;
begin
  Result := IsIntegerPower(FPower);
end;

{------------------------------------------------------------------------------}

procedure TMultibrotFormula.StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat);
var
  PX, PY, NewX, NewY: THighFloat;
  K: Integer;
begin
  if not IsIntegerPower(FPower) then
    raise EArgumentException.CreateFmt(kNotIntegerPowerMessage, [FPower]);
  // z := z^p + c, par p - 1 multiplications complexes successives
  PX := ZX;
  PY := ZY;
  for K := 2 to Round(FPower) do
  begin
    NewX := PX.Mul(ZX).Sub(PY.Mul(ZY));
    NewY := PX.Mul(ZY).Add(PY.Mul(ZX));
    PX := NewX;
    PY := NewY;
  end;
  ZX := PX.Add(CX);
  ZY := PY.Add(CY);
end;

{------------------------------------------------------------------------------}

function TMultibrotFormula.ShouldStepInFloat(ZX, ZY: TFloat): Boolean;
var
  R2: TFloat;
begin
  R2 := ZX * ZX + ZY * ZY;
  Result := IsIntegerPower(FPower) and (R2 > 1) and (0.5 * Ln(R2) * Round(FPower) > kFloatStepLogBound);
end;

{------------------------------------------------------------------------------}

function TMultibrotFormula.StepFloat(ZX, ZY, CX, CY: TFloat): TComplexPoint;
var
  PX, PY, T: TFloat;
  K: Integer;
begin
  if not IsIntegerPower(FPower) then
    raise EArgumentException.CreateFmt(kNotIntegerPowerMessage, [FPower]);
  PX := ZX;
  PY := ZY;
  for K := 2 to Round(FPower) do
  begin
    T := PX * ZX - PY * ZY;
    PY := PX * ZY + PY * ZX;
    PX := T;
  end;
  Result.X := PX + CX;
  Result.Y := PY + CY;
end;

{------------------------------------------------------------------------------}

function TMultibrotFormula.IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single;
var
  Binomial: array[0..kMaxPerturbedPower] of TFloat;   // C(p, k)
  PowX, PowY: array[0..kMaxPerturbedPower] of TFloat;  // Z^j
  DX, DY, ZX, ZY, R2, SX, SY, TX, TY: TFloat;
  N, M, K, P: Integer;
begin
  if not IsIntegerPower(FPower) then
    raise EArgumentException.CreateFmt(kNotIntegerPowerMessage, [FPower]);
  CheckOrbit(Orbit, OrbitLength);
  P := Round(FPower);
  Binomial[0] := 1;
  for K := 1 to P do
    Binomial[K] := Binomial[K - 1] * (P - K + 1) / K;
  PowX[0] := 1;
  PowY[0] := 0;
  DX := 0;
  DY := 0;
  N := 0;
  M := 0;
  while N < FMaxIter do
  begin
    ZX := Orbit[M].X + DX;
    ZY := Orbit[M].Y + DY;
    R2 := ZX * ZX + ZY * ZY;
    if R2 > kEscapeRadius2 then
      Exit(SmoothValue(N, R2, FLogPower));
    if (R2 < DX * DX + DY * DY) or (M = OrbitLength - 1) then
    begin
      // rebasage : la référence redevient Z0 = 0
      DX := ZX;
      DY := ZY;
      M := 0;
    end;
    // puissances de Z : Z^j pour j = 0..p-1
    for K := 1 to P - 1 do
    begin
      PowX[K] := PowX[K - 1] * Orbit[M].X - PowY[K - 1] * Orbit[M].Y;
      PowY[K] := PowX[K - 1] * Orbit[M].Y + PowY[K - 1] * Orbit[M].X;
    end;
    // δ' = Σ C(p,k)·Z^(p-k)·δ^k + δc, en Horner : S := C(p,p) ; S := S·δ + C(p,k)·Z^(p-k) pour k = p-1..1 ;
    // δ' := S·δ + δc
    SX := 1;
    SY := 0;
    for K := P - 1 downto 1 do
    begin
      TX := SX * DX - SY * DY;
      TY := SX * DY + SY * DX;
      SX := TX + Binomial[K] * PowX[P - K];
      SY := TY + Binomial[K] * PowY[P - K];
    end;
    TX := SX * DX - SY * DY + DCX;
    TY := SX * DY + SY * DX + DCY;
    DX := TX;
    DY := TY;
    Inc(M);
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

class function TJuliaFormula.KernelId: Integer;
begin
  Result := kKernelJulia;
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

function TJuliaFormula.IsPerturbationSupported: Boolean;
begin
  Result := True;
end;

{------------------------------------------------------------------------------}

class function TJuliaFormula.HasPixelStart: Boolean;
begin
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TJuliaFormula.StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat);
var
  NewX, NewY: THighFloat;
begin
  // z := z^2 + c, c pris dans les paramètres au nombre de mots de Z (CX, CY ignorés : Z0 est le point de départ)
  NewX := ZX.Sqr.Sub(ZY.Sqr).Add(THighFloat.FromFloat(FCX, ZX.FracWords));
  NewY := ZX.Mul(ZY).Twice.Add(THighFloat.FromFloat(FCY, ZY.FracWords));
  ZX := NewX;
  ZY := NewY;
end;

{------------------------------------------------------------------------------}

function TJuliaFormula.IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single;
begin
  // sans orbite critique, le rebasage n'a pas de point de chute exact (Z0 n'est pas le point critique 0)
  raise EArgumentException.Create(kNoCriticalOrbitMessage);
end;

{------------------------------------------------------------------------------}

// δ0 = (DX, DY) = pixel - référence ; δ' = 2·Z·δ + δ² (pas de δc). On itère sur Z ; quand |z|² < |δ|² ou en fin
// d'orbite, on rebase sur l'orbite critique W (W0 = 0) : δ := z, m := 0 ; sur W, même règle, toujours vers W0.
function TJuliaFormula.IteratePerturbedCritical(const Orbit: TOrbit; OrbitLength: Integer; const Critical: TOrbit;
  CriticalLength: Integer; DX, DY: TFloat): Single;
var
  Ref: TOrbit;
  RefLength, N, M: Integer;
  ZX, ZY, R2, NewDX, NewDY: TFloat;
begin
  CheckOrbit(Orbit, OrbitLength);
  CheckOrbit(Critical, CriticalLength);
  Ref := Orbit;
  RefLength := OrbitLength;
  N := 0;
  M := 0;
  while N < FMaxIter do
  begin
    ZX := Ref[M].X + DX;
    ZY := Ref[M].Y + DY;
    R2 := ZX * ZX + ZY * ZY;
    if R2 > kEscapeRadius2 then
      Exit(SmoothValue(N, R2, kLn2));
    if (R2 < DX * DX + DY * DY) or (M = RefLength - 1) then
    begin
      // rebasage sur W : W0 = 0, donc δ := z
      DX := ZX;
      DY := ZY;
      M := 0;
      Ref := Critical;
      RefLength := CriticalLength;
    end;
    NewDX := 2 * (Ref[M].X * DX - Ref[M].Y * DY) + DX * DX - DY * DY;
    NewDY := 2 * (Ref[M].X * DY + Ref[M].Y * DX) + 2 * DX * DY;
    DX := NewDX;
    DY := NewDY;
    Inc(M);
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

class function TBurningShipFormula.KernelId: Integer;
begin
  Result := kKernelBurningShip;
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

// |c + d| - |c| sans soustraire deux grands nombres voisins : d garde toute sa précision quand il est minuscule.
// Bornes de la spec : (c >= 0, c + d >= 0) donne d ; (c < 0, c + d > 0) donne 2c + d.
function DiffAbs(C, D: TFloat): TFloat;
begin
  if C >= 0 then
  begin
    if C + D >= 0 then
      Result := D
    else
      Result := -(2 * C + D);
  end
  else
  begin
    if C + D > 0 then
      Result := 2 * C + D
    else
      Result := -D;
  end;
end;

{------------------------------------------------------------------------------}

function TBurningShipFormula.IsPerturbationSupported: Boolean;
begin
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TBurningShipFormula.StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat);
var
  NewX, NewY: THighFloat;
begin
  // (x, y) := (x^2 - y^2 + cx, 2·|x·y| - cy), simultané
  NewX := ZX.Sqr.Sub(ZY.Sqr).Add(CX);
  NewY := ZX.Mul(ZY).Abs.Twice.Sub(CY);
  ZX := NewX;
  ZY := NewY;
end;

{------------------------------------------------------------------------------}

function TBurningShipFormula.IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single;
var
  DX, DY, ZX, ZY, R2, NewDX, NewDY: TFloat;
  N, M: Integer;
begin
  CheckOrbit(Orbit, OrbitLength);
  DX := 0;
  DY := 0;
  N := 0;
  M := 0;
  while N < FMaxIter do
  begin
    ZX := Orbit[M].X + DX;
    ZY := Orbit[M].Y + DY;
    R2 := ZX * ZX + ZY * ZY;
    if R2 > kEscapeRadius2 then
      Exit(SmoothValue(N, R2, kLn2));
    if (R2 < DX * DX + DY * DY) or (M = OrbitLength - 1) then
    begin
      // rebasage : la référence redevient Z0 = 0
      DX := ZX;
      DY := ZY;
      M := 0;
    end;
    // δx' = 2·(X·δx - Y·δy) + δx^2 - δy^2 + δcx
    // δy' = 2·diffabs(X·Y, X·δy + Y·δx + δx·δy) - δcy
    NewDX := 2 * (Orbit[M].X * DX - Orbit[M].Y * DY) + DX * DX - DY * DY + DCX;
    NewDY := 2 * DiffAbs(Orbit[M].X * Orbit[M].Y, Orbit[M].X * DY + Orbit[M].Y * DX + DX * DY) - DCY;
    DX := NewDX;
    DY := NewDY;
    Inc(M);
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

class function TTricornFormula.KernelId: Integer;
begin
  Result := kKernelTricorn;
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

function TTricornFormula.IsPerturbationSupported: Boolean;
begin
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TTricornFormula.StepReference(var ZX, ZY: THighFloat; const CX, CY: THighFloat);
var
  NewX, NewY: THighFloat;
begin
  // z := conj(z)^2 + c
  NewX := ZX.Sqr.Sub(ZY.Sqr).Add(CX);
  NewY := CY.Sub(ZX.Mul(ZY).Twice);
  ZX := NewX;
  ZY := NewY;
end;

{------------------------------------------------------------------------------}

function TTricornFormula.IteratePerturbed(const Orbit: TOrbit; OrbitLength: Integer; DCX, DCY: TFloat): Single;
var
  DX, DY, ZX, ZY, R2, NewDX, NewDY: TFloat;
  N, M: Integer;
begin
  CheckOrbit(Orbit, OrbitLength);
  DX := 0;
  DY := 0;
  N := 0;
  M := 0;
  while N < FMaxIter do
  begin
    ZX := Orbit[M].X + DX;
    ZY := Orbit[M].Y + DY;
    R2 := ZX * ZX + ZY * ZY;
    if R2 > kEscapeRadius2 then
      Exit(SmoothValue(N, R2, kLn2));
    if (R2 < DX * DX + DY * DY) or (M = OrbitLength - 1) then
    begin
      // rebasage : la référence redevient Z0 = 0
      DX := ZX;
      DY := ZY;
      M := 0;
    end;
    // δ' = conj(2·Z·δ + δ²) + δc
    NewDX := 2 * (Orbit[M].X * DX - Orbit[M].Y * DY) + DX * DX - DY * DY + DCX;
    NewDY := -(2 * (Orbit[M].X * DY + Orbit[M].Y * DX) + 2 * DX * DY) + DCY;
    DX := NewDX;
    DY := NewDY;
    Inc(M);
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

{------------------------------------------------------------------------------}

function ParamToSliderPosition(const Info: TFormulaParam; Value: Double): Integer;
begin
  // linéaire entre MinValue et MaxValue, cran le plus proche ; hors intervalle ou NaN : bornée
  if IsNan(Value) or (Info.MaxValue <= Info.MinValue) then
    Exit(0);
  Result := EnsureRange(Round((Value - Info.MinValue) / (Info.MaxValue - Info.MinValue) * kParamSliderSteps), 0,
    kParamSliderSteps);
end;

{------------------------------------------------------------------------------}

function SliderPositionToParam(const Info: TFormulaParam; Position: Integer): Double;
var
  Nearest: Integer;
begin
  Position := EnsureRange(Position, 0, kParamSliderSteps);
  Result := Info.MinValue + Position * (Info.MaxValue - Info.MinValue) / kParamSliderSteps;
  if Info.IsIntegerSnapped then
  begin
    // aimantation : à moins d'un demi-cran d'un entier, la valeur exacte de cet entier (le cran ne tombe pas dessus)
    Nearest := Round(Result);
    if Abs(Result - Nearest) <= 0.5 * (Info.MaxValue - Info.MinValue) / kParamSliderSteps then
      Result := Nearest;
  end;
end;

{------------------------------------------------------------------------------}

function IsIntegerPower(Power: TFloat): Boolean;
var
  Nearest: Integer;
begin
  Result := False;
  if IsNan(Power) or (Power < 0) or (Power > kMaxPerturbedPower + 1) then
    Exit;
  Nearest := Round(Power);
  Result := (Abs(Power - Nearest) < kIntegerPowerTolerance) and (Nearest >= 2) and (Nearest <= kMaxPerturbedPower);
end;

initialization
  RegisterFormula(TMandelbrotFormula);
  RegisterFormula(TMultibrotFormula);
  RegisterFormula(TJuliaFormula);
  RegisterFormula(TBurningShipFormula);
  RegisterFormula(TTricornFormula);

end.
