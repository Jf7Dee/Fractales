unit TestFractalEngine;

interface

uses
  Windows, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Engine;

type
  TRaisingFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TTestEngine = class(TTestCase)
  private
    function SmallViewport: TViewport;
    function CreateHeavyFormula: TFractalFormula;
    function CountNegativeValues(E: TRenderEngine): Integer;
  published
    procedure TestRenderCompletesWithExactPixels;
    procedure TestValuesMatchDirectIteration;
    procedure TestMultiThreadMatchesSingleThread;
    procedure TestNoStaleWritesAfterNewRender;
    procedure TestShiftedRenderMatchesFreshRender;
    procedure TestErrorsAreReported;
    procedure TestCancelIsQuick;
    procedure TestDestroyWhileRendering;
  end;

implementation

const
  kWaitMs = 10000;

{------------------------------------------------------------------------------}

class function TRaisingFormula.FormulaName: string;
begin
  Result := 'Raising';
end;

{------------------------------------------------------------------------------}

class function TRaisingFormula.DisplayName: string;
begin
  Result := 'Raising';
end;

{------------------------------------------------------------------------------}

function TRaisingFormula.Iterate(const CX, CY: TFloat): Single;
begin
  if CX > 0 then
    raise Exception.Create('boom');
  Result := 0;
end;

{------------------------------------------------------------------------------}

function TTestEngine.SmallViewport: TViewport;
begin
  Result := MakeViewport(-0.5, 0, 3, 200, 150);
end;

{------------------------------------------------------------------------------}

function TTestEngine.CreateHeavyFormula: TFractalFormula;
begin
  // Julia c = 0 : le disque unité est intérieur, chaque pixel coûte MaxIter itérations
  Result := TJuliaFormula.Create;
  Result.SetParam(0, 0);
  Result.SetParam(1, 0);
  Result.MaxIter := 1000000;
end;

{------------------------------------------------------------------------------}

function TTestEngine.CountNegativeValues(E: TRenderEngine): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 0 to E.Buffer.Height - 1 do
    for X := 0 to E.Buffer.Width - 1 do
      if E.Buffer.Value(X, Y) < 0 then
        Inc(Result);
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestRenderCompletesWithExactPixels;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  X, Y, N: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals(4, E.Status.PassCount);
    N := 0;
    for Y := 0 to E.Buffer.Height - 1 do
      for X := 0 to E.Buffer.Width - 1 do
        if not E.Buffer.IsExact(X, Y) then
          Inc(N);
    CheckEquals(0, N);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestValuesMatchDirectIteration;
const
  kSamples: array[0..3, 0..1] of Integer = ((0, 0), (17, 33), (199, 149), (100, 75));
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  P: TComplexPoint;
  I: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    for I := 0 to High(kSamples) do
    begin
      P := SmallViewport.PixelToComplex(kSamples[I, 0], kSamples[I, 1]);
      CheckEquals(F.Iterate(P.X, P.Y), E.Buffer.Value(kSamples[I, 0], kSamples[I, 1]), 0);
    end;
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestMultiThreadMatchesSingleThread;
var
  E1, E8: TRenderEngine;
  F: TMandelbrotFormula;
  X, Y, N: Integer;
begin
  E1 := TRenderEngine.Create(1);
  E8 := TRenderEngine.Create(8);
  F := TMandelbrotFormula.Create;
  try
    E1.Render(SmallViewport, F);
    E8.Render(SmallViewport, F);
    CheckTrue(E1.WaitUntilComplete(kWaitMs));
    CheckTrue(E8.WaitUntilComplete(kWaitMs));
    N := 0;
    for Y := 0 to E1.Buffer.Height - 1 do
      for X := 0 to E1.Buffer.Width - 1 do
        if E1.Buffer.Value(X, Y) <> E8.Buffer.Value(X, Y) then
          Inc(N);
    CheckEquals(0, N);
  finally
    F.Free;
    E8.Free;
    E1.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestNoStaleWritesAfterNewRender;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  Light: TMandelbrotFormula;
  Round: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  Heavy := CreateHeavyFormula;
  Light := TMandelbrotFormula.Create;
  try
    for Round := 1 to 5 do
    begin
      E.Render(MakeViewport(0, 0, 1, 160, 120), Heavy);
      Sleep(30);
      // tout s'échappe autour de (5, 5) : une valeur négative ne peut venir que du rendu précédent
      E.Render(MakeViewport(5, 5, 1, 160, 120), Light);
      CheckTrue(E.WaitUntilComplete(kWaitMs));
      CheckEquals(0, CountNegativeValues(E), Format('tour %d', [Round]));
    end;
  finally
    Light.Free;
    Heavy.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestShiftedRenderMatchesFreshRender;
var
  E, Fresh: TRenderEngine;
  F: TMandelbrotFormula;
  V2: TViewport;
  X, Y, N: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  Fresh := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    V2 := SmallViewport.Panned(17, -9);
    E.RenderShifted(V2, F, 17, -9);
    Fresh.Render(V2, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(Fresh.WaitUntilComplete(kWaitMs));
    N := 0;
    for Y := 0 to E.Buffer.Height - 1 do
      for X := 0 to E.Buffer.Width - 1 do
        if Abs(E.Buffer.Value(X, Y) - Fresh.Buffer.Value(X, Y)) > 1e-3 then
          Inc(N);
    CheckTrue(N <= E.Buffer.Width * E.Buffer.Height div 100, Format('%d pixels différents', [N]));
  finally
    F.Free;
    Fresh.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestErrorsAreReported;
var
  E: TRenderEngine;
  R: TRaisingFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  R := TRaisingFormula.Create;
  try
    E.Render(SmallViewport, R);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(Pos('boom', E.TakeErrors) > 0);
    CheckEquals('', E.TakeErrors);
  finally
    R.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestCancelIsQuick;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  T: Cardinal;
begin
  E := TRenderEngine.Create(CpuCount);
  Heavy := CreateHeavyFormula;
  try
    E.Render(MakeViewport(0, 0, 1, 160, 120), Heavy);
    Sleep(30);
    T := GetTickCount;
    E.Cancel;
    CheckTrue(GetTickCount - T < 500, Format('%d ms', [GetTickCount - T]));
  finally
    Heavy.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestDestroyWhileRendering;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  T: Cardinal;
begin
  Heavy := CreateHeavyFormula;
  try
    E := TRenderEngine.Create(CpuCount);
    E.Render(MakeViewport(0, 0, 1, 160, 120), Heavy);
    Sleep(30);
    T := GetTickCount;
    E.Free;
    CheckTrue(GetTickCount - T < 1000, Format('%d ms', [GetTickCount - T]));
  finally
    Heavy.Free;
  end;
end;

initialization
  RegisterTest(TTestEngine.Suite);

end.
