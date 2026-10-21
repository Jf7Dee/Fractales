library FakeKernel;

// DLL de substitution pour les tests : mêmes exports que la DLL Rust (kernel-rust), mais calculée par
// Fractal.Formulas. Elle permet de vérifier le chargement et le moteur en mode Rust sur une machine sans Rust.

uses
  SysUtils,
  Fractal.HighFloat in '..\src\Fractal.HighFloat.pas',
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas';

const
  kAbiVersion = 1;
  kOk = 0;
  kUnknownFormula = 1;
  kBadParamCount = 2;
  kInvalidArgument = 3;
  kInternalError = 4;

{------------------------------------------------------------------------------}

function fk_abi_version: Cardinal; cdecl;
begin
  Result := kAbiVersion;
end;

{------------------------------------------------------------------------------}

function fk_compute_row(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer; X0, DX, Y: Double;
  Count: Integer; Output: PSingle): Integer; cdecl;
var
  FormulaClass: TFractalFormulaClass;
  F: TFractalFormula;
  I: Integer;
begin
  if (ParamCount < 0) or (MaxIter < 0) or (Count < 0) or (Output = nil) or ((ParamCount > 0) and (Params = nil)) then
    Exit(kInvalidArgument);
  FormulaClass := nil;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I).KernelId = Formula then
      FormulaClass := FormulaClassAt(I);
  if FormulaClass = nil then
    Exit(kUnknownFormula);
  try
    F := FormulaClass.Create;
    try
      if ParamCount <> F.ParamCount then
        Exit(kBadParamCount);
      for I := 0 to ParamCount - 1 do
      begin
        F.SetParam(I, Params^);
        Inc(Params);
      end;
      F.MaxIter := MaxIter;
      for I := 0 to Count - 1 do
      begin
        Output^ := F.Iterate(X0 + I * DX, Y);
        Inc(Output);
      end;
      Result := kOk;
    finally
      F.Free;
    end;
  except
    Result := kInternalError;
  end;
end;

exports
  fk_abi_version,
  fk_compute_row;

begin
  // appelée par les threads du moteur : le gestionnaire de mémoire de la DLL doit se verrouiller
  IsMultiThread := True;
end.
