library FakeKernel;

// DLL de substitution pour les tests : mêmes exports que la DLL Rust (kernel-rust), mais calculée par
// Fractal.Formulas. Elle permet de vérifier le chargement et le moteur en mode Rust sur une machine sans Rust.
// Compilée avec FAKE_ABI1 (build.sh tests → FakeKernelAbi1.dll), elle imite une DLL de version 1 : sans
// fk_compute_row_perturbed. Compilée avec FAKE_ABI2 (FakeKernelAbi2.dll), elle imite une DLL de version 2 : sans
// fk_perturbation_supported. Compilée avec FAKE_ABI3 (FakeKernelAbi3.dll), elle imite une DLL de version 3 : sans
// fk_compute_row_perturbed2, et fk_perturbation_supported répond 0 pour Julia et Multibrot. Par défaut, version 4.

uses
  SysUtils,
  Fractal.HighFloat in '..\src\Fractal.HighFloat.pas',
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas';

const
{$IFDEF FAKE_ABI1}
  kAbiVersion = 1;
{$ELSE}
{$IFDEF FAKE_ABI2}
  kAbiVersion = 2;
{$ELSE}
{$IFDEF FAKE_ABI3}
  kAbiVersion = 3;
{$ELSE}
  kAbiVersion = 4;
{$ENDIF}
{$ENDIF}
{$ENDIF}
  kOk = 0;
  kUnknownFormula = 1;
  kBadParamCount = 2;
  kInvalidArgument = 3;
  kInternalError = 4;
  kUnsupported = 5;

function CreateFormula(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
  out F: TFractalFormula): Integer; forward;

{------------------------------------------------------------------------------}

function fk_abi_version: Cardinal; cdecl;
begin
  Result := kAbiVersion;
end;

{------------------------------------------------------------------------------}

function fk_compute_row(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer; X0, DX, Y: Double;
  Count: Integer; Output: PSingle): Integer; cdecl;
var
  F: TFractalFormula;
  I: Integer;
begin
  if (ParamCount < 0) or (MaxIter < 0) or (Count < 0) or (Output = nil) or ((ParamCount > 0) and (Params = nil)) then
    Exit(kInvalidArgument);
  try
    Result := CreateFormula(Formula, Params, ParamCount, MaxIter, F);
    if Result <> kOk then
      Exit;
    try
      for I := 0 to Count - 1 do
      begin
        Output^ := F.Iterate(X0 + I * DX, Y);
        Inc(Output);
      end;
    finally
      F.Free;
    end;
  except
    Result := kInternalError;
  end;
end;

{------------------------------------------------------------------------------}

// Formule de la DLL Rust d'identifiant Formula, paramètres et MaxIter réglés ; F = nil si le code n'est pas kOk.
function CreateFormula(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
  out F: TFractalFormula): Integer;
var
  FormulaClass: TFractalFormulaClass;
  I: Integer;
begin
  F := nil;
  FormulaClass := nil;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I).KernelId = Formula then
      FormulaClass := FormulaClassAt(I);
  if FormulaClass = nil then
    Exit(kUnknownFormula);
  F := FormulaClass.Create;
  try
    if ParamCount <> F.ParamCount then
    begin
      FreeAndNil(F);
      Exit(kBadParamCount);
    end;
    for I := 0 to ParamCount - 1 do
    begin
      F.SetParam(I, Params^);
      Inc(Params);
    end;
    F.MaxIter := MaxIter;
    Result := kOk;
  except
    FreeAndNil(F);
    raise;
  end;
end;

{$IFNDEF FAKE_ABI1}

{------------------------------------------------------------------------------}

// Orbite x0, y0, x1, y1, ... (2·PointCount valeurs en Double) relue en TOrbit.
function ReadOrbit(Source: PDouble; PointCount: Integer): TOrbit;
var
  I: Integer;
begin
  SetLength(Result, PointCount);
  for I := 0 to PointCount - 1 do
  begin
    Result[I].X := Source^;
    Inc(Source);
    Result[I].Y := Source^;
    Inc(Source);
  end;
end;

{------------------------------------------------------------------------------}

// Même contrat que fk_compute_row_perturbed de kernel-rust : RefOrbit = x0, y0, x1, y1, ... (2·RefLength valeurs).
// L'orbite en Double est relue en TOrbit et chaque pixel passe par IteratePerturbed. Julia (deux orbites) et une
// puissance non entière de Multibrot : kUnsupported.
function fk_compute_row_perturbed(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
  RefOrbit: PDouble; RefLength: Integer; DCX0, DDX, DCY: Double; Count: Integer; Output: PSingle): Integer; cdecl;
var
  F: TFractalFormula;
  Orbit: TOrbit;
  I: Integer;
  DCX: Double;
begin
  if (ParamCount < 0) or (MaxIter < 0) or (Count < 0) or (Output = nil) or ((ParamCount > 0) and (Params = nil))
    or (RefOrbit = nil) or (RefLength < kMinOrbitLength) then
    Exit(kInvalidArgument);
  try
    Result := CreateFormula(Formula, Params, ParamCount, MaxIter, F);
    if Result <> kOk then
      Exit;
    try
      if not F.IsPerturbationSupported or F.HasPixelStart then
        Exit(kUnsupported);
{$IFDEF FAKE_ABI3}
      // une DLL v3 ne sait pas perturber Multibrot
      if Formula = kKernelMultibrot then
        Exit(kUnsupported);
{$ENDIF}
{$IFDEF FAKE_ABI2}
      // une DLL v2 ne sait pas encore perturber le Burning Ship
      if Formula = kKernelBurningShip then
        Exit(kUnsupported);
{$ENDIF}
      Orbit := ReadOrbit(RefOrbit, RefLength);
      for I := 0 to Count - 1 do
      begin
        // arrondi en Double comme dans la DLL Rust et dans TestFakeKernelPerturbedMatchesDelphi
        DCX := DCX0 + I * DDX;
        Output^ := F.IteratePerturbed(Orbit, RefLength, DCX, DCY);
        Inc(Output);
      end;
    finally
      F.Free;
    end;
  except
    Result := kInternalError;
  end;
end;

{$IFNDEF FAKE_ABI2}

{------------------------------------------------------------------------------}

// Réponse sur l'identifiant seul, sans construire de formule (comme la DLL Rust) : 1 pour les cinq formules connues,
// 0 sinon ; une DLL v3 répond 0 pour Julia et Multibrot (limite connue).
function fk_perturbation_supported(Formula: Integer): Integer; cdecl;
begin
  case Formula of
    kKernelMandelbrot, kKernelBurningShip, kKernelTricorn:
      Result := 1;
{$IFNDEF FAKE_ABI3}
    kKernelMultibrot, kKernelJulia:
      Result := 1;
{$ENDIF}
  else
    Result := 0;
  end;
end;

{$IFNDEF FAKE_ABI3}

{------------------------------------------------------------------------------}

// Même contrat que fk_compute_row_perturbed2 de kernel-rust : comme fk_compute_row_perturbed, plus l'orbite critique
// W (CritOrbit, CritLength points), obligatoire pour Julia (kInvalidArgument sinon) et ignorée par les autres
// formules ; (DCX0 + I·DDX ; DCY) est δ0 pour Julia. Chaque pixel passe par IteratePerturbedCritical.
function fk_compute_row_perturbed2(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
  RefOrbit: PDouble; RefLength: Integer; CritOrbit: PDouble; CritLength: Integer; DCX0, DDX, DCY: Double;
  Count: Integer; Output: PSingle): Integer; cdecl;
var
  F: TFractalFormula;
  Orbit, Critical: TOrbit;
  I: Integer;
  DCX: Double;
begin
  if (ParamCount < 0) or (MaxIter < 0) or (Count < 0) or (Output = nil) or ((ParamCount > 0) and (Params = nil))
    or (RefOrbit = nil) or (RefLength < kMinOrbitLength) or (CritLength < 0) then
    Exit(kInvalidArgument);
  try
    Result := CreateFormula(Formula, Params, ParamCount, MaxIter, F);
    if Result <> kOk then
      Exit;
    try
      if not F.IsPerturbationSupported then
        Exit(kUnsupported);
      if F.HasPixelStart and ((CritOrbit = nil) or (CritLength < kMinOrbitLength)) then
        Exit(kInvalidArgument);
      Orbit := ReadOrbit(RefOrbit, RefLength);
      Critical := nil;
      if (CritOrbit <> nil) and (CritLength > 0) then
        Critical := ReadOrbit(CritOrbit, CritLength);
      for I := 0 to Count - 1 do
      begin
        DCX := DCX0 + I * DDX;
        Output^ := F.IteratePerturbedCritical(Orbit, RefLength, Critical, CritLength, DCX, DCY);
        Inc(Output);
      end;
    finally
      F.Free;
    end;
  except
    Result := kInternalError;
  end;
end;

{$ENDIF}
{$ENDIF}
{$ENDIF}

exports
{$IFNDEF FAKE_ABI1}
  fk_compute_row_perturbed,
{$IFNDEF FAKE_ABI2}
  fk_perturbation_supported,
{$IFNDEF FAKE_ABI3}
  fk_compute_row_perturbed2,
{$ENDIF}
{$ENDIF}
{$ENDIF}
  fk_abi_version,
  fk_compute_row;

begin
  // appelée par les threads du moteur : le gestionnaire de mémoire de la DLL doit se verrouiller
  IsMultiThread := True;
end.
