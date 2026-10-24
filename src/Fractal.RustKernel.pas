unit Fractal.RustKernel;

// Chargement et appel de la DLL de calcul Rust (kernel-rust\, fractal_kernel.dll). Unité sans VCL.

interface

uses
  Windows, SysUtils, SyncObjs, Fractal.Types, Fractal.Formulas;

const
  kRustKernelFileName = 'fractal_kernel.dll';
  kRustAbiVersion = 4;               // + fk_compute_row_perturbed2 (Julia, deux orbites)
  kRustAbiVersionAbi3 = 3;           // fk_perturbation_supported répond 0 pour Julia et Multibrot : Delphi
  kRustAbiVersionAbi2 = 2;           // perturbation pour Mandelbrot et Tricorn seulement
  kRustAbiVersionNoPerturbation = 1; // fk_compute_row seule : le zoom profond reste en Delphi
  kMaxKernelParams = 8;
  // codes de retour de fk_compute_row et fk_compute_row_perturbed
  kRustOk = 0;
  kRustUnknownFormula = 1;
  kRustBadParamCount = 2;
  kRustInvalidArgument = 3;
  kRustInternalError = 4;
  kRustUnsupported = 5;              // formule sans perturbation (fk_compute_row_perturbed)

type
  ERustKernelError = class(Exception);

  // orbite de référence passée à la DLL : x0, y0, x1, y1, ... en Double
  TDoubleOrbit = array of Double;

  TRustAbiVersionFunc = function: Cardinal; cdecl;
  TRustComputeRowFunc = function(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
    X0, DX, Y: Double; Count: Integer; Output: System.PSingle): Integer; cdecl;
  TRustComputeRowPerturbedFunc = function(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
    RefOrbit: PDouble; RefLength: Integer; DCX0, DDX, DCY: Double; Count: Integer;
    Output: System.PSingle): Integer; cdecl;
  TRustComputeRowPerturbed2Func = function(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
    RefOrbit: PDouble; RefLength: Integer; CritOrbit: PDouble; CritLength: Integer; DCX0, DDX, DCY: Double;
    Count: Integer; Output: System.PSingle): Integer; cdecl;
  TRustPerturbationSupportedFunc = function(Formula: Integer): Integer; cdecl;
  TRustKernelParams = array[0..kMaxKernelParams - 1] of Double;

  // Une DLL de calcul chargée. Elle n'a aucun état : plusieurs threads peuvent appeler ComputeRow à la fois.
  TRustKernel = class
  private
    FHandle: HMODULE;
    FComputeRow: TRustComputeRowFunc;
    FComputeRowPerturbed: TRustComputeRowPerturbedFunc;   // nil en version 1
    FComputeRowPerturbed2: TRustComputeRowPerturbed2Func;   // nil hors version 4
    FPerturbationSupported: TRustPerturbationSupportedFunc;   // nil hors versions 3 et 4
    FAbiVersion: Cardinal;
    FStatus: string;
    function FindExport(const Name: AnsiString): Pointer;
    procedure LoadParams(Formula: TFractalFormula; out Params: TRustKernelParams);
    procedure Unload(const Reason: string);
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function IsAvailable: Boolean;
    function HasPerturbation: Boolean;
    function HasPerturbationFor(KernelId: Integer): Boolean;
    procedure ComputeRowPerturbed(Formula: TFractalFormula; const Orbit: TDoubleOrbit; DCX0, DDX, DCY: Double;
      Count: Integer; Output: System.PSingle);
    procedure ComputeRowPerturbed2(Formula: TFractalFormula; const Orbit, Critical: TDoubleOrbit;
      DCX0, DDX, DCY: Double; Count: Integer; Output: System.PSingle);
    procedure ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer; Output: System.PSingle);
    property Status: string read FStatus;
  end;

function DefaultRustKernel: TRustKernel;
function MakeDoubleOrbit(const Orbit: TOrbit): TDoubleOrbit;
function IsRustKernelAvailable: Boolean;
function RustKernelStatus: string;

implementation

const
  // formules que la DLL de version 2 sait calculer en perturbation
  kAbi2PerturbationKernels: array[0..1] of Integer = (kKernelMandelbrot, kKernelTricorn);

var
  KernelLock: TCriticalSection;
  DefaultKernel: TRustKernel;

{------------------------------------------------------------------------------}

function RustErrorText(Code: Integer): string;
begin
  case Code of
    kRustUnknownFormula:
      Result := 'formule inconnue';
    kRustBadParamCount:
      Result := 'nombre de paramètres incorrect';
    kRustInvalidArgument:
      Result := 'argument invalide';
    kRustInternalError:
      Result := 'erreur interne';
    kRustUnsupported:
      Result := 'formule sans perturbation';
  else
    Result := 'erreur inattendue';
  end;
  Result := Format('Moteur Rust : %s (code %d).', [Result, Code]);
end;

{------------------------------------------------------------------------------}

constructor TRustKernel.Create(const AFileName: string);
var
  AbiVersion: TRustAbiVersionFunc;
  Version: Cardinal;
  ErrorCode: Cardinal;
begin
  inherited Create;
  if not FileExists(AFileName) then
  begin
    FStatus := Format('Moteur Rust absent : %s introuvable.', [ExtractFileName(AFileName)]);
    Exit;
  end;
  FHandle := LoadLibrary(PChar(AFileName));
  if FHandle = 0 then
  begin
    ErrorCode := GetLastError;
    FStatus := Format('Moteur Rust : chargement de %s impossible (%s).',
      [ExtractFileName(AFileName), SysErrorMessage(ErrorCode)]);
    if ErrorCode = ERROR_BAD_EXE_FORMAT then
      FStatus := FStatus + ' DLL 64 bits ? Compilez-la avec --target i686-pc-windows-msvc.';
    Exit;
  end;
  AbiVersion := FindExport('fk_abi_version');
  FComputeRow := FindExport('fk_compute_row');
  if not Assigned(AbiVersion) or not Assigned(FComputeRow) then
  begin
    Unload(Format('Moteur Rust : %s ne contient pas fk_abi_version et fk_compute_row.',
      [ExtractFileName(AFileName)]));
    Exit;
  end;
  Version := AbiVersion;
  if (Version < kRustAbiVersionNoPerturbation) or (Version > kRustAbiVersion) then
  begin
    Unload(Format('Moteur Rust : %s est en version %d, version %d à %d attendue.',
      [ExtractFileName(AFileName), Version, kRustAbiVersionNoPerturbation, kRustAbiVersion]));
    Exit;
  end;
  FAbiVersion := Version;
  if Version >= kRustAbiVersionAbi2 then
    FComputeRowPerturbed := FindExport('fk_compute_row_perturbed');
  if Version >= kRustAbiVersionAbi3 then
  begin
    FPerturbationSupported := FindExport('fk_perturbation_supported');
    if not Assigned(FPerturbationSupported) then
    begin
      Unload(Format('Moteur Rust : %s (version %d) ne contient pas fk_perturbation_supported.',
        [ExtractFileName(AFileName), Version]));
      Exit;
    end;
  end;
  if Version = kRustAbiVersion then
  begin
    FComputeRowPerturbed2 := FindExport('fk_compute_row_perturbed2');
    if not Assigned(FComputeRowPerturbed2) then
    begin
      Unload(Format('Moteur Rust : %s (version %d) ne contient pas fk_compute_row_perturbed2.',
        [ExtractFileName(AFileName), Version]));
      Exit;
    end;
  end;
  if not HasPerturbation then
    FStatus := Format('Moteur Rust disponible, sans fk_compute_row_perturbed (version %d) : '
      + 'le zoom profond sera calculé en Delphi.', [Version])
  else if Version = kRustAbiVersionAbi2 then
    FStatus := Format('Moteur Rust disponible (version %d) : le Burning Ship profond sera calculé en Delphi.',
      [Version])
  else
    FStatus := 'Moteur Rust disponible.';
end;

{------------------------------------------------------------------------------}

destructor TRustKernel.Destroy;
begin
  if FHandle <> 0 then
    FreeLibrary(FHandle);
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

function TRustKernel.FindExport(const Name: AnsiString): Pointer;
begin
  // cdecl 32 bits : le nom peut être exporté avec ou sans le préfixe « _ » selon l'éditeur de liens
  Result := GetProcAddress(FHandle, PAnsiChar(Name));
  if Result = nil then
    Result := GetProcAddress(FHandle, PAnsiChar('_' + Name));
end;

{------------------------------------------------------------------------------}

procedure TRustKernel.Unload(const Reason: string);
begin
  FreeLibrary(FHandle);
  FHandle := 0;
  FComputeRow := nil;
  FComputeRowPerturbed := nil;
  FComputeRowPerturbed2 := nil;
  FPerturbationSupported := nil;
  FAbiVersion := 0;
  FStatus := Reason;
end;

{------------------------------------------------------------------------------}

function TRustKernel.IsAvailable: Boolean;
begin
  Result := FHandle <> 0;
end;

{------------------------------------------------------------------------------}

// Version 2 et export trouvé : la DLL calcule aussi les rangées du palier 2.
function TRustKernel.HasPerturbation: Boolean;
begin
  Result := IsAvailable and Assigned(FComputeRowPerturbed);
end;

{------------------------------------------------------------------------------}

// Version 1 : jamais ; version 2 : Mandelbrot et Tricorn ; versions 3 et 4 : la DLL répond elle-même, formule par
// formule (la 3 répond 0 pour Julia et Multibrot) ; en version 4, Julia exige aussi fk_compute_row_perturbed2.
function TRustKernel.HasPerturbationFor(KernelId: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if not HasPerturbation then
    Exit;
  if FAbiVersion >= kRustAbiVersionAbi3 then
  begin
    Result := FPerturbationSupported(KernelId) <> 0;
    if Result and (KernelId = kKernelJulia) and (FAbiVersion = kRustAbiVersion) then
      Result := Assigned(FComputeRowPerturbed2);
  end
  else
    for I := Low(kAbi2PerturbationKernels) to High(kAbi2PerturbationKernels) do
      if kAbi2PerturbationKernels[I] = KernelId then
        Result := True;
end;

{------------------------------------------------------------------------------}

// Pixels d'écart DCX0 + I·DDX (I = 0 .. Count − 1), DCY à la référence de l'orbite (même calcul qu'IteratePerturbed).
procedure TRustKernel.ComputeRowPerturbed(Formula: TFractalFormula; const Orbit: TDoubleOrbit; DCX0, DDX,
  DCY: Double; Count: Integer; Output: System.PSingle);
var
  Params: TRustKernelParams;
  RefOrbit: PDouble;
  Code: Integer;
begin
  if not IsAvailable then
    raise ERustKernelError.Create(FStatus);
  if not HasPerturbation then
    raise ERustKernelError.Create('Moteur Rust : DLL sans perturbation (fk_compute_row_perturbed absente).');
  LoadParams(Formula, Params);
  // orbite vide : la DLL répond « argument invalide »
  if Orbit = nil then
    RefOrbit := nil
  else
    RefOrbit := @Orbit[0];
  Code := FComputeRowPerturbed(Formula.KernelId, @Params[0], Formula.ParamCount, Formula.MaxIter, RefOrbit,
    Length(Orbit) div 2, DCX0, DDX, DCY, Count, Output);
  if Code <> kRustOk then
    raise ERustKernelError.Create(RustErrorText(Code));
end;

{------------------------------------------------------------------------------}

// Comme ComputeRowPerturbed, avec l'orbite critique W des formules HasPixelStart (Julia) ; Critical vide pour les
// autres formules (la DLL l'ignore). Pour Julia, (DCX0 + I·DDX ; DCY) est δ0 = pixel − référence.
procedure TRustKernel.ComputeRowPerturbed2(Formula: TFractalFormula; const Orbit, Critical: TDoubleOrbit;
  DCX0, DDX, DCY: Double; Count: Integer; Output: System.PSingle);
var
  Params: TRustKernelParams;
  RefOrbit, CritOrbit: PDouble;
  Code: Integer;
begin
  if not IsAvailable then
    raise ERustKernelError.Create(FStatus);
  if not Assigned(FComputeRowPerturbed2) then
    raise ERustKernelError.Create('Moteur Rust : DLL sans fk_compute_row_perturbed2 (version 4 requise).');
  LoadParams(Formula, Params);
  // orbites vides : la DLL répond « argument invalide » si elle en a besoin
  if Orbit = nil then
    RefOrbit := nil
  else
    RefOrbit := @Orbit[0];
  if Critical = nil then
    CritOrbit := nil
  else
    CritOrbit := @Critical[0];
  Code := FComputeRowPerturbed2(Formula.KernelId, @Params[0], Formula.ParamCount, Formula.MaxIter, RefOrbit,
    Length(Orbit) div 2, CritOrbit, Length(Critical) div 2, DCX0, DDX, DCY, Count, Output);
  if Code <> kRustOk then
    raise ERustKernelError.Create(RustErrorText(Code));
end;

{------------------------------------------------------------------------------}

procedure TRustKernel.ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer;
  Output: System.PSingle);
var
  Params: TRustKernelParams;
  Code: Integer;
begin
  if not IsAvailable then
    raise ERustKernelError.Create(FStatus);
  LoadParams(Formula, Params);
  Code := FComputeRow(Formula.KernelId, @Params[0], Formula.ParamCount, Formula.MaxIter, X0, DX, Y, Count, Output);
  if Code <> kRustOk then
    raise ERustKernelError.Create(RustErrorText(Code));
end;

{------------------------------------------------------------------------------}

procedure TRustKernel.LoadParams(Formula: TFractalFormula; out Params: TRustKernelParams);
var
  I: Integer;
begin
  if Formula = nil then
    raise ERustKernelError.Create('Moteur Rust : formule absente.');
  if Formula.ParamCount > kMaxKernelParams then
    raise ERustKernelError.CreateFmt('Moteur Rust : trop de paramètres pour %s.', [Formula.FormulaName]);
  for I := 0 to Formula.ParamCount - 1 do
    Params[I] := Formula.GetParam(I);
end;

{------------------------------------------------------------------------------}

function DefaultRustKernel: TRustKernel;
begin
  // chargée au premier usage, une seule fois, à côté de l'exécutable
  KernelLock.Enter;
  try
    if DefaultKernel = nil then
      DefaultKernel := TRustKernel.Create(ExtractFilePath(ParamStr(0)) + kRustKernelFileName);
    Result := DefaultKernel;
  finally
    KernelLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

// Orbite de référence arrondie en Double pour la DLL, x et y alternés.
function MakeDoubleOrbit(const Orbit: TOrbit): TDoubleOrbit;
var
  I: Integer;
begin
  SetLength(Result, 2 * Length(Orbit));
  for I := 0 to High(Orbit) do
  begin
    Result[2 * I] := Orbit[I].X;
    Result[2 * I + 1] := Orbit[I].Y;
  end;
end;

{------------------------------------------------------------------------------}

function IsRustKernelAvailable: Boolean;
begin
  Result := DefaultRustKernel.IsAvailable;
end;

{------------------------------------------------------------------------------}

function RustKernelStatus: string;
begin
  Result := DefaultRustKernel.Status;
end;

initialization
  KernelLock := TCriticalSection.Create;

finalization
  FreeAndNil(DefaultKernel);
  FreeAndNil(KernelLock);

end.
