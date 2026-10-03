unit Fractal.Engine;

interface

uses
  Windows, SysUtils, Classes, SyncObjs, Math, Fractal.Types, Fractal.Formulas, Fractal.Buffer;

const
  kTileSize = 64;
  kMaxErrorLines = 20;
  kIdleWaitMs = 250;

type
  TTileJob = record
    Generation: Integer;
    TileIndex: Integer;
    PassIndex: Integer;
    X0, Y0, X1, Y1: Integer;  // X1, Y1 exclus
    Step: Integer;            // taille des blocs de la passe : 8, 4, 2 ou 1
    IsTaken: Boolean;
  end;

  TRenderStatus = record
    Generation: Integer;
    DoneJobs: Integer;
    TotalJobs: Integer;
    PassCount: Integer;
    ElapsedMs: Cardinal;
    function IsComplete: Boolean;
    function CurrentPass: Integer;
  end;

  TRenderEngine = class;

  TRenderWorker = class(TThread)
  private
    FEngine: TRenderEngine;
  protected
    procedure Execute; override;
  public
    constructor Create(AEngine: TRenderEngine);
  end;

  TRenderEngine = class
  private
    FLock: TCriticalSection;
    FWorkEvent: TEvent;
    FCompleteEvent: TEvent;
    FWorkers: array of TRenderWorker;
    FJobs: array of TTileJob;
    FTileDone: array of Integer;
    FNextJob: Integer;
    FGeneration: Integer;
    FActiveJobs: Integer;
    FDoneJobs: Integer;
    FTotalJobs: Integer;
    FPassCount: Integer;
    FStartTick: Cardinal;
    FElapsedMs: Cardinal;
    FIsShuttingDown: Boolean;
    FViewport: TViewport;
    FFormula: TFractalFormula;
    FBuffer: TIterationBuffer;
    FErrors: TStringList;
    function TryTakeJob(out Job: TTileJob): Boolean;
    function ProcessJob(const Job: TTileJob): Boolean;
    procedure FinishJob(const Job: TTileJob; IsCompleted: Boolean);
    procedure AddError(const Msg: string);
    procedure StopCurrent;
    procedure StartRender(const V: TViewport; Formula: TFractalFormula; IsProgressive, IsShift: Boolean;
      DX, DY: Integer);
    procedure QueueJobs(IsProgressive: Boolean);
  public
    constructor Create(AThreadCount: Integer);
    destructor Destroy; override;
    procedure Render(const V: TViewport; Formula: TFractalFormula; IsProgressive: Boolean = True);
    procedure RenderShifted(const V: TViewport; Formula: TFractalFormula; DX, DY: Integer);
    procedure Cancel;
    function WaitUntilComplete(TimeoutMs: Cardinal): Boolean;
    function Status: TRenderStatus;
    function TakeErrors: string;
    property Buffer: TIterationBuffer read FBuffer;
  end;

function CpuCount: Integer;

implementation

const
  kProgressiveSteps: array[0..3] of Integer = (8, 4, 2, 1);

{------------------------------------------------------------------------------}

function CpuCount: Integer;
var
  Info: TSystemInfo;
begin
  GetSystemInfo(Info);
  Result := Max(1, Info.dwNumberOfProcessors);
end;

{------------------------------------------------------------------------------}

function TRenderStatus.IsComplete: Boolean;
begin
  Result := DoneJobs >= TotalJobs;
end;

{------------------------------------------------------------------------------}

function TRenderStatus.CurrentPass: Integer;
var
  JobsPerPass: Integer;
begin
  if (PassCount = 0) or (TotalJobs = 0) then
    Exit(PassCount);
  JobsPerPass := Max(1, TotalJobs div PassCount);
  Result := Min(PassCount, DoneJobs div JobsPerPass + 1);
end;

{------------------------------------------------------------------------------}

constructor TRenderWorker.Create(AEngine: TRenderEngine);
begin
  FEngine := AEngine;
  inherited Create(False);
end;

{------------------------------------------------------------------------------}

procedure TRenderWorker.Execute;
var
  Job: TTileJob;
  IsCompleted: Boolean;
begin
  while not Terminated do
    if FEngine.TryTakeJob(Job) then
    begin
      IsCompleted := False;
      try
        try
          IsCompleted := FEngine.ProcessJob(Job);
        except
          on E: Exception do
          begin
            FEngine.AddError(Format('Tuile (%d, %d) : %s', [Job.X0, Job.Y0, E.Message]));
            IsCompleted := True;
          end;
        end;
      finally
        FEngine.FinishJob(Job, IsCompleted);
      end;
    end
    else
      FEngine.FWorkEvent.WaitFor(kIdleWaitMs);
end;

{------------------------------------------------------------------------------}

constructor TRenderEngine.Create(AThreadCount: Integer);
var
  I: Integer;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWorkEvent := TEvent.Create(nil, True, False, '');
  FCompleteEvent := TEvent.Create(nil, True, True, '');
  FErrors := TStringList.Create;
  FBuffer := TIterationBuffer.Create(0, 0);
  FViewport := MakeViewport(0, 0, kDefaultWidth, 1, 1);
  SetLength(FWorkers, Max(1, AThreadCount));
  for I := 0 to High(FWorkers) do
    FWorkers[I] := TRenderWorker.Create(Self);
end;

{------------------------------------------------------------------------------}

destructor TRenderEngine.Destroy;
var
  I: Integer;
begin
  StopCurrent;
  FIsShuttingDown := True;
  for I := 0 to High(FWorkers) do
    FWorkers[I].Terminate;
  FWorkEvent.SetEvent;
  for I := 0 to High(FWorkers) do
  begin
    FWorkers[I].WaitFor;
    FWorkers[I].Free;
  end;
  FFormula.Free;
  FBuffer.Free;
  FErrors.Free;
  FCompleteEvent.Free;
  FWorkEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.Render(const V: TViewport; Formula: TFractalFormula; IsProgressive: Boolean);
begin
  StartRender(V, Formula, IsProgressive, False, 0, 0);
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.RenderShifted(const V: TViewport; Formula: TFractalFormula; DX, DY: Integer);
begin
  StartRender(V, Formula, True, True, DX, DY);
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.StartRender(const V: TViewport; Formula: TFractalFormula; IsProgressive, IsShift: Boolean;
  DX, DY: Integer);
var
  NewFormula: TFractalFormula;
begin
  // clonée avant l'arrêt : si le clonage échoue, le rendu courant reste intact
  NewFormula := Formula.Clone;
  StopCurrent;
  FFormula.Free;
  FFormula := NewFormula;
  FViewport := V;
  if (FBuffer.Width <> V.PixelWidth) or (FBuffer.Height <> V.PixelHeight) then
    FBuffer.Resize(V.PixelWidth, V.PixelHeight)
  else if IsShift then
    FBuffer.Shift(DX, DY)
  else
    FBuffer.Clear;
  QueueJobs(IsProgressive);
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.StopCurrent;
begin
  FLock.Enter;
  try
    Inc(FGeneration);
    SetLength(FJobs, 0);
    FNextJob := 0;
    FTotalJobs := 0;
    FDoneJobs := 0;
    FCompleteEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
  // chaque thread actif s'arrête au pixel suivant : on l'attend pour qu'il n'écrive plus rien ensuite
  while FActiveJobs > 0 do
    SwitchToThread;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.QueueJobs(IsProgressive: Boolean);
var
  TilesX, TilesY, TileCount, StepCount, T, P, I, J, Tmp: Integer;
  Order: array of Integer;
  Dist: array of Double;
  DX, DY: Double;
begin
  TilesX := (FBuffer.Width + kTileSize - 1) div kTileSize;
  TilesY := (FBuffer.Height + kTileSize - 1) div kTileSize;
  TileCount := TilesX * TilesY;
  SetLength(Order, TileCount);
  SetLength(Dist, TileCount);
  for T := 0 to TileCount - 1 do
  begin
    Order[T] := T;
    DX := (T mod TilesX + 0.5) * kTileSize - FBuffer.Width / 2;
    DY := (T div TilesX + 0.5) * kTileSize - FBuffer.Height / 2;
    Dist[T] := DX * DX + DY * DY;
  end;
  // tri par insertion du centre vers les bords : quelques milliers de tuiles au plus
  for I := 1 to TileCount - 1 do
  begin
    Tmp := Order[I];
    J := I - 1;
    while (J >= 0) and (Dist[Order[J]] > Dist[Tmp]) do
    begin
      Order[J + 1] := Order[J];
      Dec(J);
    end;
    Order[J + 1] := Tmp;
  end;
  if IsProgressive then
    StepCount := Length(kProgressiveSteps)
  else
    StepCount := 1;

  FLock.Enter;
  try
    SetLength(FJobs, TileCount * StepCount);
    SetLength(FTileDone, TileCount);
    for T := 0 to TileCount - 1 do
      FTileDone[T] := 0;
    I := 0;
    for P := 0 to StepCount - 1 do
      for J := 0 to TileCount - 1 do
      begin
        T := Order[J];
        FJobs[I].Generation := FGeneration;
        FJobs[I].TileIndex := T;
        FJobs[I].PassIndex := P;
        FJobs[I].X0 := (T mod TilesX) * kTileSize;
        FJobs[I].Y0 := (T div TilesX) * kTileSize;
        FJobs[I].X1 := Min(FJobs[I].X0 + kTileSize, FBuffer.Width);
        FJobs[I].Y1 := Min(FJobs[I].Y0 + kTileSize, FBuffer.Height);
        if IsProgressive then
          FJobs[I].Step := kProgressiveSteps[P]
        else
          FJobs[I].Step := 1;
        FJobs[I].IsTaken := False;
        Inc(I);
      end;
    FNextJob := 0;
    FTotalJobs := Length(FJobs);
    FDoneJobs := 0;
    FPassCount := StepCount;
    FStartTick := GetTickCount;
    FElapsedMs := 0;
    if FTotalJobs = 0 then
      FCompleteEvent.SetEvent
    else
      FWorkEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.TryTakeJob(out Job: TTileJob): Boolean;
var
  I: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    while (FNextJob < Length(FJobs)) and FJobs[FNextJob].IsTaken do
      Inc(FNextJob);
    // une passe d'une tuile n'est éligible qu'une fois les passes précédentes de cette tuile terminées
    for I := FNextJob to High(FJobs) do
      if not FJobs[I].IsTaken and (FTileDone[FJobs[I].TileIndex] = FJobs[I].PassIndex) then
      begin
        FJobs[I].IsTaken := True;
        Job := FJobs[I];
        InterlockedIncrement(FActiveJobs);
        Exit(True);
      end;
    if not FIsShuttingDown then
      FWorkEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.ProcessJob(const Job: TTileJob): Boolean;
var
  X, Y: Integer;
  P: TComplexPoint;
begin
  Result := False;
  Y := Job.Y0;
  while Y < Job.Y1 do
  begin
    X := Job.X0;
    while X < Job.X1 do
    begin
      if Job.Generation <> FGeneration then
        Exit;
      if not FBuffer.IsExact(X, Y) then
      begin
        P := FViewport.PixelToComplex(X, Y);
        FBuffer.WriteAnchor(X, Y, Job.Step, FFormula.Iterate(P.X, P.Y));
      end;
      Inc(X, Job.Step);
    end;
    FBuffer.MarkDirty;
    Inc(Y, Job.Step);
  end;
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.FinishJob(const Job: TTileJob; IsCompleted: Boolean);
begin
  FLock.Enter;
  try
    if IsCompleted and (Job.Generation = FGeneration) then
    begin
      Inc(FTileDone[Job.TileIndex]);
      Inc(FDoneJobs);
      if FDoneJobs = FTotalJobs then
      begin
        FElapsedMs := GetTickCount - FStartTick;
        FCompleteEvent.SetEvent;
      end
      else
        FWorkEvent.SetEvent;
    end;
    InterlockedDecrement(FActiveJobs);
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.AddError(const Msg: string);
begin
  FLock.Enter;
  try
    if FErrors.Count < kMaxErrorLines then
      FErrors.Add(Msg);
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.Cancel;
begin
  StopCurrent;
  FCompleteEvent.SetEvent;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.WaitUntilComplete(TimeoutMs: Cardinal): Boolean;
begin
  Result := FCompleteEvent.WaitFor(TimeoutMs) = wrSignaled;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.Status: TRenderStatus;
begin
  FLock.Enter;
  try
    Result.Generation := FGeneration;
    Result.DoneJobs := FDoneJobs;
    Result.TotalJobs := FTotalJobs;
    Result.PassCount := FPassCount;
    if FDoneJobs < FTotalJobs then
      Result.ElapsedMs := GetTickCount - FStartTick
    else
      Result.ElapsedMs := FElapsedMs;
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.TakeErrors: string;
begin
  FLock.Enter;
  try
    Result := TrimRight(FErrors.Text);
    FErrors.Clear;
  finally
    FLock.Leave;
  end;
end;

end.
