unit TestFractalRustKernel;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.RustKernel, TestUtils;

type
  // formule sans équivalent dans la DLL : la DLL doit répondre « formule inconnue »
  TUnknownKernelFormula = class(TMandelbrotFormula)
  public
    class function KernelId: Integer; override;
  end;

  TTestRustKernel = class(TTestCase)
  published
    procedure TestMissingFileIsUnavailable;
    procedure TestBadFormatFileIsUnavailable;
    procedure TestDllWithoutExportsIsUnavailable;
    procedure TestFakeKernelComputesRow;
    procedure TestKernelErrorRaises;
    procedure TestUnavailableKernelRaises;
    procedure TestDefaultKernelIsShared;
  end;

function TestBinFolder: string;
function FakeKernelFileName: string;

implementation

const
  kFakeKernelFile = 'FakeKernel.dll';
  kUnknownKernelId = 42;
  kRowCount = 5;
  kRowX0 = -2.5;
  kRowDX = 0.5;

{------------------------------------------------------------------------------}

function TestBinFolder: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

{------------------------------------------------------------------------------}

function FakeKernelFileName: string;
begin
  Result := TestBinFolder + kFakeKernelFile;
end;

{------------------------------------------------------------------------------}

class function TUnknownKernelFormula.KernelId: Integer;
begin
  Result := kUnknownKernelId;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestMissingFileIsUnavailable;
var
  K: TRustKernel;
begin
  K := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('introuvable', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestBadFormatFileIsUnavailable;
var
  FileName: string;
  Lines: TStringList;
  K: TRustKernel;
begin
  // même erreur 193 qu'une DLL 64 bits : le message doit citer la bonne cible de compilation
  FileName := TestTempFolder + 'not_a_dll.dll';
  Lines := TStringList.Create;
  try
    Lines.Add('pas une DLL');
    Lines.SaveToFile(FileName);
  finally
    Lines.Free;
  end;
  K := TRustKernel.Create(FileName);
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('i686-pc-windows-msvc', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestDllWithoutExportsIsUnavailable;
var
  SystemDir: array[0..MAX_PATH] of Char;
  K: TRustKernel;
begin
  GetSystemDirectory(SystemDir, MAX_PATH);
  K := TRustKernel.Create(IncludeTrailingPathDelimiter(SystemDir) + 'version.dll');
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('fk_', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestFakeKernelComputesRow;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..kRowCount - 1] of Single;
  I: Integer;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TMandelbrotFormula.Create;
  try
    CheckTrue(K.IsAvailable, K.Status);
    K.ComputeRow(F, kRowX0, kRowDX, 0, kRowCount, @Values[0]);
    for I := 0 to kRowCount - 1 do
      CheckEquals(F.Iterate(kRowX0 + I * kRowDX, 0), Values[I], 0, Format('pixel %d', [I]));
    CheckEquals(kInside, Values[kRowCount - 1], 0);  // x = -0,5 : cardioïde
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestKernelErrorRaises;
var
  K: TRustKernel;
  F: TUnknownKernelFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TUnknownKernelFormula.Create;
  try
    try
      K.ComputeRow(F, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckTrue(Pos('(code 1)', E.Message) > 0, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestUnavailableKernelRaises;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
  F := TMandelbrotFormula.Create;
  try
    try
      K.ComputeRow(F, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckEquals(K.Status, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestRustKernel.TestDefaultKernelIsShared;
begin
  CheckSame(DefaultRustKernel, DefaultRustKernel);
  CheckEquals(DefaultRustKernel.IsAvailable, IsRustKernelAvailable);
  CheckEquals(DefaultRustKernel.Status, RustKernelStatus);
end;

initialization
  RegisterTest(TTestRustKernel.Suite);

end.
