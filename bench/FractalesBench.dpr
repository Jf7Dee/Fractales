program FractalesBench;

// Banc d'essai Delphi : mêmes scènes que bench-rust, rendues par le vrai Fractal.Engine (sans passes progressives).

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas',
  Fractal.RustKernel in '..\src\Fractal.RustKernel.pas',
  Fractal.Buffer in '..\src\Fractal.Buffer.pas',
  Fractal.Engine in '..\src\Fractal.Engine.pas';

const
  kWidth = 1920;
  kHeight = 1080;
  kRuns = 5;
  kSceneCount = 3;

type
  TScene = record
    Name: string;
    Formula: TFractalFormula;
    Viewport: TViewport;
  end;

  TMeasure = record
    MedianMs: Double;
    InsideCount: Integer;
    Checksum: Double;
  end;

var
  Scenes: array[0..kSceneCount - 1] of TScene;

{------------------------------------------------------------------------------}

function ElapsedMs(Start, Stop, Frequency: Int64): Double;
begin
  Result := (Stop - Start) * 1000.0 / Frequency;
end;

{------------------------------------------------------------------------------}

function Median(var Values: array of Double): Double;
var
  I, J: Integer;
  T: Double;
begin
  for I := 1 to High(Values) do
  begin
    T := Values[I];
    J := I - 1;
    while (J >= 0) and (Values[J] > T) do
    begin
      Values[J + 1] := Values[J];
      Dec(J);
    end;
    Values[J + 1] := T;
  end;
  Result := Values[High(Values) div 2];
end;

{------------------------------------------------------------------------------}

procedure ComputeChecksum(Buffer: TIterationBuffer; out InsideCount: Integer; out Checksum: Double);
var
  X, Y: Integer;
  V: Single;
begin
  InsideCount := 0;
  Checksum := 0;
  for Y := 0 to Buffer.Height - 1 do
    for X := 0 to Buffer.Width - 1 do
    begin
      V := Buffer.Value(X, Y);
      if V < 0 then
        Inc(InsideCount)
      else
        Checksum := Checksum + V;
    end;
end;

{------------------------------------------------------------------------------}

function MeasureScene(const Scene: TScene; ThreadCount: Integer): TMeasure;
var
  Engine: TRenderEngine;
  Times: array[0..kRuns - 1] of Double;
  Frequency, Start, Stop: Int64;
  Run: Integer;
begin
  QueryPerformanceFrequency(Frequency);
  Engine := TRenderEngine.Create(ThreadCount);
  try
    for Run := 0 to kRuns - 1 do
    begin
      QueryPerformanceCounter(Start);
      Engine.Render(Scene.Viewport, Scene.Formula, False);
      Engine.WaitUntilComplete(INFINITE);
      QueryPerformanceCounter(Stop);
      Times[Run] := ElapsedMs(Start, Stop, Frequency);
    end;
    if not Engine.Status.IsComplete then
      raise Exception.Create('rendu incomplet');
    Result.MedianMs := Median(Times);
    ComputeChecksum(Engine.Buffer, Result.InsideCount, Result.Checksum);
  finally
    Engine.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure BuildScenes;
var
  Julia: TJuliaFormula;
begin
  Scenes[0].Name := 'Vue d''ensemble';
  Scenes[0].Formula := TMandelbrotFormula.Create;
  Scenes[0].Formula.MaxIter := 1000;
  Scenes[0].Viewport := MakeViewport(-0.5, 0, 3, kWidth, kHeight);

  Scenes[1].Name := 'Vue profonde';
  Scenes[1].Formula := TMandelbrotFormula.Create;
  Scenes[1].Formula.MaxIter := 5000;
  Scenes[1].Viewport := MakeViewport(-0.743643887037151, 0.131825904205330, 1e-9, kWidth, kHeight);

  Julia := TJuliaFormula.Create;
  Julia.SetParam(Julia.IndexOfParam('cx'), 0);
  Julia.SetParam(Julia.IndexOfParam('cy'), 0);
  Julia.MaxIter := 2000;
  Scenes[2].Name := 'Interieur lourd';
  Scenes[2].Formula := Julia;
  Scenes[2].Viewport := MakeViewport(0, 0, 3, kWidth, kHeight);
end;

{------------------------------------------------------------------------------}

procedure PrintLine(const Scene: TScene; ThreadCount: Integer; const M: TMeasure);
begin
  Writeln(Format('%-16s | %7d | %8d | %10.1f | %10d | %16.1f',
    [Scene.Name, Scene.Formula.MaxIter, ThreadCount, M.MedianMs, M.InsideCount, M.Checksum]));
end;

{------------------------------------------------------------------------------}

var
  I: Integer;

begin
  try
    BuildScenes;
    Writeln(Format('Delphi 2010 (Extended 80 bits, x87) - %d x %d, mediane de %d rendus, %d coeurs logiques',
      [kWidth, kHeight, kRuns, CpuCount]));
    Writeln('Scene            | MaxIter | Threads  |   ms (med) |  Interieur |   Somme lissee');
    for I := 0 to kSceneCount - 1 do
    begin
      PrintLine(Scenes[I], 1, MeasureScene(Scenes[I], 1));
      PrintLine(Scenes[I], CpuCount, MeasureScene(Scenes[I], CpuCount));
    end;
    for I := 0 to kSceneCount - 1 do
      Scenes[I].Formula.Free;
  except
    on E: Exception do
    begin
      Writeln('ERREUR : ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
