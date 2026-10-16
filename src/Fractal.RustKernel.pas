unit Fractal.RustKernel;

// Chargement et appel de la DLL de calcul Rust (kernel-rust\, fractal_kernel.dll). Unité sans VCL.

interface

uses
  Windows, SysUtils, SyncObjs, Fractal.Formulas;

const
  kRustKernelFileName = 'fractal_kernel.dll';
  kRustAbiVersion = 1;
  kMaxKernelParams = 8;
  // codes de retour de fk_compute_row
  kRustOk = 0;
  kRustUnknownFormula = 1;
  kRustBadParamCount = 2;
  kRustInvalidArgument = 3;
  kRustInternalError = 4;

type
  ERustKernelError = class(Exception);

  TRustAbiVersionFunc = function: Cardinal; cdecl;
  TRustComputeRowFunc = function(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
    X0, DX, Y: Double; Count: Integer; Output: System.PSingle): Integer; cdecl;

  // Une DLL de calcul chargée. Elle n'a aucun état : plusieurs threads peuvent appeler ComputeRow à la fois.
  TRustKernel = class
  private
    FHandle: HMODULE;
    FComputeRow: TRustComputeRowFunc;
    FStatus: string;
    function FindExport(const Name: AnsiString): Pointer;
    procedure Unload(const Reason: string);
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function IsAvailable: Boolean;
    procedure ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer; Output: System.PSingle);
    property Status: string read FStatus;
  end;

function DefaultRustKernel: TRustKernel;
function IsRustKernelAvailable: Boolean;
function RustKernelStatus: string;

implementation

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
  if Version <> kRustAbiVersion then
  begin
    Unload(Format('Moteur Rust : %s est en version %d, version %d attendue.',
      [ExtractFileName(AFileName), Version, kRustAbiVersion]));
    Exit;
  end;
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
  FStatus := Reason;
end;

{------------------------------------------------------------------------------}

function TRustKernel.IsAvailable: Boolean;
begin
  Result := FHandle <> 0;
end;

{------------------------------------------------------------------------------}

procedure TRustKernel.ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer;
  Output: System.PSingle);
var
  Params: array[0..kMaxKernelParams - 1] of Double;
  I, Code: Integer;
begin
  if not IsAvailable then
    raise ERustKernelError.Create(FStatus);
  if Formula.ParamCount > kMaxKernelParams then
    raise ERustKernelError.CreateFmt('Moteur Rust : trop de paramètres pour %s.', [Formula.FormulaName]);
  for I := 0 to Formula.ParamCount - 1 do
    Params[I] := Formula.GetParam(I);
  Code := FComputeRow(Formula.KernelId, @Params[0], Formula.ParamCount, Formula.MaxIter, X0, DX, Y, Count, Output);
  if Code <> kRustOk then
    raise ERustKernelError.Create(RustErrorText(Code));
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
