library FakeKernel;

// DLL de substitution pour les tests : mêmes exports que la DLL Rust (kernel-rust), mais calculée par
// Fractal.Formulas. Elle permet de vérifier le chargement et le moteur en mode Rust sur une machine sans Rust.
// Compilée avec FAKE_ABI1 (build.sh tests → FakeKernelAbi1.dll), elle imite une DLL de version 1 : sans
// fk_compute_row_perturbed. Compilée avec FAKE_ABI2 (FakeKernelAbi2.dll), elle imite une DLL de version 2 : sans
// fk_perturbation_supported. Par défaut, version 3.

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
  kAbiVersion = 3;
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

// Même contrat que fk_compute_row_perturbed de kernel-rust : RefOrbit = x0, y0, x1, y1, ... (2·RefLength valeurs).
// L'orbite en Double est relue en TOrbit et chaque pixel passe par IteratePerturbed.
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
      // la DLL factice reste en version 3 (Multibrot non perturbé) jusqu'à l'ABI 4
      if not F.IsPerturbationSupported or (Formula = kKernelMultibrot) then
        Exit(kUnsupported);
{$IFDEF FAKE_ABI2}
      // une DLL v2 ne sait pas encore perturber le Burning Ship
      if Formula = kKernelBurningShip then
        Exit(kUnsupported);
{$ENDIF}
      SetLength(Orbit, RefLength);
      for I := 0 to RefLength - 1 do
      begin
        Orbit[I].X := RefOrbit^;
        Inc(RefOrbit);
        Orbit[I].Y := RefOrbit^;
        Inc(RefOrbit);
      end;
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

// Réponse d'après le registre des formules (instance temporaire aux valeurs par défaut) : 1 si la
// formule d'identifiant Formula existe et supporte la perturbation, 0 sinon.
function fk_perturbation_supported(Formula: Integer): Integer; cdecl;
var
  I: Integer;
  F: TFractalFormula;
begin
  Result := 0;
  if Formula = kKernelMultibrot then
    Exit;   // version 3 : Multibrot non perturbé (la version 4 viendra avec l'ABI 4)
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I).KernelId = Formula then
    begin
      // la prise en charge dépend désormais de l'instance (puissance de Multibrot) : instance temporaire, valeurs
      // par défaut, comme le fait la DLL Rust pour un identifiant seul
      F := FormulaClassAt(I).Create;
      try
        if F.IsPerturbationSupported then
          Result := 1;
      finally
        F.Free;
      end;
    end;
end;

{$ENDIF}
{$ENDIF}

exports
{$IFNDEF FAKE_ABI1}
  fk_compute_row_perturbed,
{$IFNDEF FAKE_ABI2}
  fk_perturbation_supported,
{$ENDIF}
{$ENDIF}
  fk_abi_version,
  fk_compute_row;

begin
  // appelée par les threads du moteur : le gestionnaire de mémoire de la DLL doit se verrouiller
  IsMultiThread := True;
end.
