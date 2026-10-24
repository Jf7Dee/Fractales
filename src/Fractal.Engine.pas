unit Fractal.Engine;

interface

uses
  Windows, SysUtils, Classes, SyncObjs, Math, Fractal.HighFloat, Fractal.Types, Fractal.Formulas, Fractal.Buffer,
  Fractal.RustKernel;

const
  kTileSize = 64;
  kMaxErrorLines = 20;
  kIdleWaitMs = 250;
  kReferenceIterHeadroom = 1.25;   // MaxIter de l'orbite de référence = Ceil(MaxIter x 1,25) : réutilisable au zoom

type
  // noyau de calcul des pixels : Delphi (Extended, x87) ou DLL Rust (Double, SIMD)
  TEngineKernelType = (ekDelphi, ekRust);

const
  TEngineKernelToByte : Array[TEngineKernelType] of byte  = (0,1);
  TByteToEngineKernel : Array[0..1] of TEngineKernelType = (ekDelphi, ekRust);

type
  TTileJob = record
    Generation: Integer;
    TileIndex: Integer;
    PassIndex: Integer;
    X0, Y0, X1, Y1: Integer;  // X1, Y1 exclus
    Step: Integer;            // taille des blocs de la passe : 8, 4, 2 ou 1
    IsTaken: Boolean;
    IsReference: Boolean;     // orbite de référence de la perturbation : en tête, avant toute tuile
  end;

  TRenderStatus = record
    Generation: Integer;
    DoneJobs: Integer;
    TotalJobs: Integer;
    PassCount: Integer;
    ElapsedMs: Cardinal;
    IsCancelled: Boolean;
    Kernel: TEngineKernelType;
    IsPerturbation: Boolean;       // palier 2 : pixels calculés par écart à l'orbite de référence
    IsReferencePending: Boolean;   // orbite de référence en cours de calcul, aucune tuile commencée
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
    type
      // dernière orbite de référence installée, gardée d'un rendu à l'autre pour être réutilisée
      TReferenceOrbit = record
        ExactX, ExactY: THighFloat;
        Orbit: TOrbit;
        DoubleOrbit: TDoubleOrbit;   // la même en Double pour la DLL Rust, construite une fois au besoin
        FormulaClass: TClass;
        Params: array of Double;
        MaxIter: Integer;        // MaxIter de l'orbite, marge kReferenceIterHeadroom comprise
        FracWords: Integer;
        Width: TFloat;           // largeur de la vue qui l'a calculée
        IsFullLength: Boolean;   // l'orbite ne s'échappe pas avant MaxIter
      end;
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
    FIsCancelled: Boolean;
    FViewport: TViewport;
    FFormula: TFractalFormula;
    FBuffer: TIterationBuffer;
    FErrors: TStringList;
    FKernel: TEngineKernelType;
    FActiveKernel: TEngineKernelType;          // figé au début du rendu courant
    FRustKernel: TRustKernel;              // non possédé ; nil = DefaultRustKernel
    FActiveRustKernel: TRustKernel;        // figé au début du rendu courant (nil en mode Delphi)
    FIsPerturbation: Boolean;              // palier figé au début du rendu courant
    FIsReferenceReady: Boolean;            // sous FLock : tant qu'il est faux, aucune tuile n'est éligible
    FOrbit: TOrbit;                        // orbite de référence des tuiles du rendu courant
    FDoubleOrbit: TDoubleOrbit;            // FOrbit en Double, en mode Rust seulement
    FRefDeltaX, FRefDeltaY: TFloat;        // centre exact − référence, partie constante de δc
    FReference: TReferenceOrbit;           // sous FLock pendant un rendu
    FReferenceComputeCount: Integer;
    FIsEscapedReferenceReusable: Boolean;
    function TryTakeJob(out Job: TTileJob): Boolean;
    function ProcessJob(const Job: TTileJob): Boolean;
    function ProcessRustJob(const Job: TTileJob): Boolean;
    function ProcessReferenceJob(const Job: TTileJob): Boolean;
    class function ReferenceMaxIter(MaxIter: Integer): Integer;
    procedure InstallReference(Generation: Integer; const RefX, RefY: THighFloat; const Orbit: TOrbit;
      FracWords, OrbitMaxIter: Integer);
    function PixelValue(X, Y: Integer): Single;
    function IsReferenceReusable(const V: TViewport; Formula: TFractalFormula): Boolean;
    function CurrentRustKernel: TRustKernel;
    procedure FinishJob(const Job: TTileJob; IsCompleted: Boolean);
    procedure AddError(const Msg: string);
    procedure StopCurrent;
    procedure StartRender(const V: TViewport; Formula: TFractalFormula; IsProgressive, IsShift: Boolean;
      DX, DY: Integer);
    procedure QueueJobs(IsProgressive, ShouldComputeReference: Boolean);
    function GetReferenceComputeCount: Integer;
    function GetReferenceLength: Integer;
  public
    constructor Create(AThreadCount: Integer);
    destructor Destroy; override;
    procedure Render(const V: TViewport; Formula: TFractalFormula; IsProgressive: Boolean = True);
    procedure RenderShifted(const V: TViewport; Formula: TFractalFormula; DX, DY: Integer);
    procedure Cancel;
    function WaitUntilComplete(TimeoutMs: Cardinal): Boolean;
    function Status: TRenderStatus;
    function TakeErrors: string;
    class function GetDisplayName(aKernel:TEngineKernelType ): string;
    class function GetEpsilon(aKernel:TEngineKernelType ): TFloat;
    function ResolveKernel(Formula: TFractalFormula; IsPerturbation: Boolean = False): TEngineKernelType;
    property Buffer: TIterationBuffer read FBuffer;
    property Kernel: TEngineKernelType read FKernel write FKernel;
    property RustKernel: TRustKernel read FRustKernel write FRustKernel;
    // rendu HD par bandes : une référence échappée sert aussi aux bandes suivantes de même largeur
    property IsEscapedReferenceReusable: Boolean read FIsEscapedReferenceReusable write FIsEscapedReferenceReusable;
    property ReferenceComputeCount: Integer read GetReferenceComputeCount;   // tâches référence installées
    property ReferenceLength: Integer read GetReferenceLength;               // points de la dernière référence
  end;

function CpuCount: Integer;

implementation

uses
  Fractal.Perturbation;

const
  kProgressiveSteps: array[0..3] of Integer = (8, 4, 2, 1);
  kReferenceReuseWidths = 2;     // distance maximale référence - centre, en largeurs de vue, pour la réutiliser
  kReferenceCandidateGrid = 3;   // grille de kReferenceCandidateGrid x kReferenceCandidateGrid références candidates

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
  Result := not IsCancelled and (DoneJobs >= TotalJobs);
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
            if Job.IsReference then
              FEngine.AddError('Orbite de référence : ' + E.Message)
            else
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
  FLock.Enter;
  try
    FIsShuttingDown := True;
  finally
    FLock.Leave;
  end;
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

class function TRenderEngine.GetDisplayName(aKernel: TEngineKernelType): string;
begin
  if aKernel = ekRust then
    Result := 'Rust'
  else
    Result := 'Delphi';
end;

{------------------------------------------------------------------------------}

class function TRenderEngine.GetEpsilon(aKernel: TEngineKernelType): TFloat;
begin
  if aKernel = ekRust then
    Result := kDoubleEpsilon
  else
    Result := kExtendedEpsilon;
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
  NewKernel: TEngineKernelType;
  IsNewPerturbation, IsReused: Boolean;
begin
  // clonée avant l'arrêt : si le clonage échoue, le rendu courant reste intact
  NewFormula := Formula.Clone;
  NewKernel := ResolveKernel(NewFormula);
  // palier 2 dès que le palier 1 n'est plus sûr pour le noyau du rendu (psWarning) : bascule avant la pixelisation
  IsNewPerturbation := NewFormula.SupportsPerturbation and (V.PrecisionState(GetEpsilon(NewKernel)) <> psOk);
  if IsNewPerturbation then
    NewKernel := ResolveKernel(NewFormula, True);
  StopCurrent;
  FLock.Enter;
  try
    FErrors.Clear;
  finally
    FLock.Leave;
  end;
  FFormula.Free;
  FFormula := NewFormula;
  FActiveKernel := NewKernel;
  if NewKernel = ekRust then
    FActiveRustKernel := CurrentRustKernel
  else
    FActiveRustKernel := nil;
  FViewport := V;
  // aucune tâche ne tourne plus : l'orbite et la référence gardée se lisent sans verrou
  FIsPerturbation := IsNewPerturbation;
  FOrbit := nil;
  FDoubleOrbit := nil;
  IsReused := IsNewPerturbation and IsReferenceReusable(V, NewFormula);
  if IsReused then
  begin
    FOrbit := FReference.Orbit;
    if NewKernel = ekRust then
    begin
      // orbite installée en mode Delphi : convertie une seule fois, puis gardée avec elle
      if FReference.DoubleOrbit = nil then
        FReference.DoubleOrbit := MakeDoubleOrbit(FReference.Orbit);
      FDoubleOrbit := FReference.DoubleOrbit;
    end;
    FRefDeltaX := V.ExactCenterX.Sub(FReference.ExactX).ToFloat;
    FRefDeltaY := V.ExactCenterY.Sub(FReference.ExactY).ToFloat;
  end;
  if (FBuffer.Width <> V.PixelWidth) or (FBuffer.Height <> V.PixelHeight) then
    FBuffer.Resize(V.PixelWidth, V.PixelHeight)
  else if IsShift then
    FBuffer.Shift(DX, DY)
  else
    FBuffer.Clear;
  QueueJobs(IsProgressive, IsNewPerturbation and not IsReused);
end;

{------------------------------------------------------------------------------}

// Écart 2 : même formule (classe et paramètres), MaxIter de l'orbite (marge comprise) au moins égal à celui de la
// formule, précision suffisante, référence à moins de kReferenceReuseWidths largeurs du centre. Une référence
// échappée est recalculée pour redonner leur chance aux candidates de la nouvelle vue, sauf si
// IsEscapedReferenceReusable (bandes du rendu HD) et que la largeur de vue n'a pas changé.
function TRenderEngine.IsReferenceReusable(const V: TViewport; Formula: TFractalFormula): Boolean;
var
  I: Integer;
  MaxDistance: TFloat;
begin
  Result := False;
  if FReference.Orbit = nil then
    Exit;
  if not FReference.IsFullLength and not (FIsEscapedReferenceReusable and (FReference.Width = V.Width)) then
    Exit;
  if (FReference.FormulaClass <> Formula.ClassType) or (FReference.MaxIter < Formula.MaxIter) then
    Exit;
  if Length(FReference.Params) <> Formula.ParamCount then
    Exit;
  for I := 0 to High(FReference.Params) do
    if FReference.Params[I] <> Formula.GetParam(I) then
      Exit;
  if FReference.FracWords < FracWordsForPixelSize(V.PixelSize) then
    Exit;
  MaxDistance := kReferenceReuseWidths * V.Width;
  Result := (Abs(FReference.ExactX.Sub(V.ExactCenterX).ToFloat) <= MaxDistance)
    and (Abs(FReference.ExactY.Sub(V.ExactCenterY).ToFloat) <= MaxDistance);
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
    FIsCancelled := True;
    FCompleteEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
  // chaque thread actif s'arrête au pixel suivant : on l'attend pour qu'il n'écrive plus rien ensuite
  while FActiveJobs > 0 do
    SwitchToThread;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.QueueJobs(IsProgressive, ShouldComputeReference: Boolean);
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
    SetLength(FJobs, TileCount * StepCount + Ord(ShouldComputeReference));
    SetLength(FTileDone, TileCount);
    for T := 0 to TileCount - 1 do
      FTileDone[T] := 0;
    I := 0;
    if ShouldComputeReference then
    begin
      // tâche référence en tête : hors du compte des tuiles, elle débloque toutes les autres
      FillChar(FJobs[0], SizeOf(TTileJob), 0);
      FJobs[0].Generation := FGeneration;
      FJobs[0].TileIndex := -1;
      FJobs[0].IsReference := True;
      Inc(I);
    end;
    FIsReferenceReady := not ShouldComputeReference;
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
        FJobs[I].IsReference := False;
        Inc(I);
      end;
    FNextJob := 0;
    FTotalJobs := TileCount * StepCount;
    FDoneJobs := 0;
    FPassCount := StepCount;
    FIsCancelled := False;
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
    begin
      // tant que l'orbite de référence manque, seule sa tâche (en tête) est éligible
      if not FIsReferenceReady and not FJobs[I].IsReference then
        Break;
      if not FJobs[I].IsTaken
        and (FJobs[I].IsReference or (FTileDone[FJobs[I].TileIndex] = FJobs[I].PassIndex)) then
      begin
        FJobs[I].IsTaken := True;
        Job := FJobs[I];
        InterlockedIncrement(FActiveJobs);
        Exit(True);
      end;
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
begin
  if Job.IsReference then
    Exit(ProcessReferenceJob(Job));
  if FActiveKernel = ekRust then
    Exit(ProcessRustJob(Job));
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
        FBuffer.WriteAnchor(X, Y, Job.Step, PixelValue(X, Y));
      Inc(X, Job.Step);
    end;
    FBuffer.MarkDirty;
    Inc(Y, Job.Step);
  end;
  Result := True;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.PixelValue(X, Y: Integer): Single;
var
  P: TComplexPoint;
begin
  if FIsPerturbation then
  begin
    // δc = (centre exact − référence) + écart du pixel au centre exact
    P := FViewport.PixelOffset(X, Y);
    Result := FFormula.IteratePerturbed(FOrbit, Length(FOrbit), FRefDeltaX + P.X, FRefDeltaY + P.Y);
  end
  else
  begin
    P := FViewport.PixelToComplex(X, Y);
    Result := FFormula.Iterate(P.X, P.Y);
  end;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.ProcessRustJob(const Job: TTileJob): Boolean;
var
  Values: array[0..kTileSize - 1] of Single;
  X, Y, RunStart, Count, I: Integer;
  P: TComplexPoint;
  DX: Double;
begin
  // ancres consécutives à calculer regroupées en suites : un seul appel à la DLL par suite
  Result := False;
  DX := Job.Step * FViewport.PixelSize;
  Y := Job.Y0;
  while Y < Job.Y1 do
  begin
    X := Job.X0;
    while X < Job.X1 do
    begin
      if FBuffer.IsExact(X, Y) then
      begin
        Inc(X, Job.Step);
        Continue;
      end;
      RunStart := X;
      Count := 0;
      while (X < Job.X1) and not FBuffer.IsExact(X, Y) do
      begin
        Inc(Count);
        Inc(X, Job.Step);
      end;
      if Job.Generation <> FGeneration then
        Exit;
      if FIsPerturbation then
      begin
        // δc du premier pixel de la suite, comme PixelValue ; PixelOffset tient compte de l'axe imaginaire qui monte
        P := FViewport.PixelOffset(RunStart, Y);
        FActiveRustKernel.ComputeRowPerturbed(FFormula, FDoubleOrbit, FRefDeltaX + P.X, DX, FRefDeltaY + P.Y, Count,
          @Values[0]);
      end
      else
      begin
        P := FViewport.PixelToComplex(RunStart, Y);
        FActiveRustKernel.ComputeRow(FFormula, P.X, DX, P.Y, Count, @Values[0]);
      end;
      for I := 0 to Count - 1 do
        FBuffer.WriteAnchor(RunStart + I * Job.Step, Y, Job.Step, Values[I]);
    end;
    FBuffer.MarkDirty;
    Inc(Y, Job.Step);
  end;
  Result := True;
end;

{------------------------------------------------------------------------------}

// Choix de la référence. Un pixel qui survit à l'orbite de sa référence est rebasé sur Z0 avec un δ qui n'est plus
// petit, et perd δc en profondeur. On essaie donc d'abord le centre exact de la vue ; si son orbite s'échappe avant
// MaxIter, on essaie les autres points d'une grille kReferenceCandidateGrid x kReferenceCandidateGrid sur la vue
// (à ±1/3 de la largeur et de la hauteur autour du centre), et on s'arrête au premier dont l'orbite ne s'échappe
// pas. Sinon, on garde l'orbite la plus longue. Chaque calcul d'orbite s'interrompt dès que la génération change.
// L'orbite va jusqu'à ReferenceMaxIter : la marge la garde réutilisable quand l'auto-itération relève MaxIter.
// La recherche s'arrête dès qu'une orbite suffit au rendu courant (plus de MaxIter points), marge atteinte ou non.
function TRenderEngine.ProcessReferenceJob(const Job: TTileJob): Boolean;
var
  Generation, Words, CellCount, Candidate, Cell, Half: Integer;
  IsCancelled: TCancelCheck;
  StepX, StepY: TFloat;
  CX, CY, BestX, BestY: THighFloat;
  Orbit, Best: TOrbit;
  RefFormula: TFractalFormula;
begin
  Result := False;
  Generation := Job.Generation;
  IsCancelled :=
    function: Boolean
    begin
      Result := Generation <> FGeneration;
    end;
  // le centre peut porter moins de mots que la taille de pixel n'en demande (vue redimensionnée)
  Words := Max(Max(FViewport.ExactCenterX.FracWords, FViewport.ExactCenterY.FracWords),
    FracWordsForPixelSize(FViewport.PixelSize));
  StepX := FViewport.Width / kReferenceCandidateGrid;
  StepY := FViewport.Height / kReferenceCandidateGrid;
  Half := kReferenceCandidateGrid div 2;
  CellCount := kReferenceCandidateGrid * kReferenceCandidateGrid;
  Best := nil;
  // copie privée : la formule du rendu n'est jamais modifiée par un thread de calcul
  RefFormula := FFormula.Clone;
  try
    RefFormula.MaxIter := ReferenceMaxIter(FFormula.MaxIter);
    for Candidate := 0 to CellCount - 1 do
    begin
      // le candidat 0 est la case centrale, puis les autres cases dans l'ordre de la grille
      Cell := (Candidate + CellCount div 2) mod CellCount;
      CX := FViewport.ExactCenterX.AddFloat((Cell mod kReferenceCandidateGrid - Half) * StepX, Words);
      CY := FViewport.ExactCenterY.AddFloat((Half - Cell div kReferenceCandidateGrid) * StepY, Words);
      if not ComputeReferenceOrbit(RefFormula, CX, CY, IsCancelled, Orbit) then
        Exit;
      if Length(Orbit) > Length(Best) then
      begin
        Best := Orbit;
        BestX := CX;
        BestY := CY;
      end;
      if Length(Best) > FFormula.MaxIter then
        Break;
    end;
    InstallReference(Generation, BestX, BestY, Best, Words, RefFormula.MaxIter);
  finally
    RefFormula.Free;
  end;
  Result := True;
end;

{------------------------------------------------------------------------------}

class function TRenderEngine.ReferenceMaxIter(MaxIter: Integer): Integer;
begin
  Result := Min(Ceil(MaxIter * kReferenceIterHeadroom), kMaxMaxIter);
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.InstallReference(Generation: Integer; const RefX, RefY: THighFloat; const Orbit: TOrbit;
  FracWords, OrbitMaxIter: Integer);
var
  I: Integer;
begin
  FLock.Enter;
  try
    // une orbite abandonnée (génération dépassée) n'est jamais installée pour un rendu suivant
    if Generation <> FGeneration then
      Exit;
    FReference.ExactX := RefX;
    FReference.ExactY := RefY;
    FReference.Orbit := Orbit;
    // orbite en Double pour la DLL : une fois par orbite installée, jamais par tuile
    if FActiveKernel = ekRust then
      FReference.DoubleOrbit := MakeDoubleOrbit(Orbit)
    else
      FReference.DoubleOrbit := nil;
    FReference.FormulaClass := FFormula.ClassType;
    SetLength(FReference.Params, FFormula.ParamCount);
    for I := 0 to High(FReference.Params) do
      FReference.Params[I] := FFormula.GetParam(I);
    FReference.MaxIter := OrbitMaxIter;
    FReference.FracWords := FracWords;
    FReference.Width := FViewport.Width;
    FReference.IsFullLength := Length(Orbit) > OrbitMaxIter;
    FOrbit := Orbit;
    FDoubleOrbit := FReference.DoubleOrbit;
    FRefDeltaX := FViewport.ExactCenterX.Sub(RefX).ToFloat;
    FRefDeltaY := FViewport.ExactCenterY.Sub(RefY).ToFloat;
    FIsReferenceReady := True;
    Inc(FReferenceComputeCount);
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

procedure TRenderEngine.FinishJob(const Job: TTileJob; IsCompleted: Boolean);
begin
  FLock.Enter;
  try
    if IsCompleted and Job.IsReference and (Job.Generation = FGeneration) then
    begin
      // orbite en échec (exception déjà notée) : les tuiles repartent en calcul direct plutôt que d'attendre
      if not FIsReferenceReady then
      begin
        FIsPerturbation := False;
        FIsReferenceReady := True;
      end;
      FWorkEvent.SetEvent;
    end
    else if IsCompleted and (Job.Generation = FGeneration) then
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
  // rend la main quand plus rien ne tourne (terminé OU annulé) : l'appelant vérifie Status.IsComplete
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
    Result.IsCancelled := FIsCancelled;
    Result.Kernel := FActiveKernel;
    Result.IsPerturbation := FIsPerturbation;
    Result.IsReferencePending := FIsPerturbation and not FIsReferenceReady and not FIsCancelled;
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

{------------------------------------------------------------------------------}

function TRenderEngine.CurrentRustKernel: TRustKernel;
begin
  if FRustKernel <> nil then
    Result := FRustKernel
  else
    Result := DefaultRustKernel;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.ResolveKernel(Formula: TFractalFormula; IsPerturbation: Boolean): TEngineKernelType;
begin
  // la DLL par défaut n'est chargée que si le noyau Rust est demandé ; une DLL sans perturbation pour cette formule
  // laisse le palier 2 au moteur Delphi
  if (FKernel = ekRust) and (Formula.KernelId <> kKernelNone) and CurrentRustKernel.IsAvailable
    and (not IsPerturbation or CurrentRustKernel.HasPerturbationFor(Formula.KernelId)) then
    Result := ekRust
  else
    Result := ekDelphi;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.GetReferenceComputeCount: Integer;
begin
  FLock.Enter;
  try
    Result := FReferenceComputeCount;
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.GetReferenceLength: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FReference.Orbit);
  finally
    FLock.Leave;
  end;
end;

end.
