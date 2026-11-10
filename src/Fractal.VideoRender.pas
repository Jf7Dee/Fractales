unit Fractal.VideoRender;

// Rendu d'une vidéo : chaque image du scénario est rendue par THiResRenderer dans un flux PNG, puis passée à
// FFmpeg, à un récepteur (aperçu en direct, tests), ou aux deux. Les images d'une pause ne sont rendues qu'une fois.
// Avant le rendu, une image sur kProbeEvery est calculée en petit : ce profil de coût guide l'estimation du temps
// restant, car une image coûte très différemment selon la profondeur et la part d'intérieur à l'écran.

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.HiRes, Fractal.VideoPath, Fractal.VideoScenario, Fractal.VideoEncoder, SyncObjs;

const
  kPreviewDivisor = 4;  // l'aperçu est rendu au quart de la taille

type
  // Appelé dans le fil de rendu, une fois par image
  TVideoFrameSink = procedure(Png: TStream) of object;

  TVideoRenderer = class(TThread)
  private
    FScenario: TVideoScenario;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FKernel: TEngineKernelType;
    FFfmpegExe: string;
    FOutputFile: string;
    FIsPreview: Boolean;
    FSink: TVideoFrameSink;
    FWidth, FHeight: Integer;
    FFramesTotal: Integer;
    FFramesDone: Integer;
    FRenderCount: Integer;
    FStartTick: Cardinal;
    FCost: array of Double;  // coût prévu cumulé : FCost[I] = images 0..I-1 ; vide = pas de profil
    FIsProfiling: Boolean;
    FProbesDone: Integer;
    FProbesTotal: Integer;
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    FPipe: TFfmpegPipe;          // visé par Cancel depuis le fil principal, sous FPipeLock
    FPipeLock: TCriticalSection;
    function RenderFrame(const Pose: TCameraPose; Formula: TFractalFormula; Target: TStream;
      Width, Height, Supersample: Integer): Boolean;
    function Profile(Formula: TFractalFormula; Target: TStream): Boolean;
    function GetSecondsLeft: Double;
  protected
    procedure Execute; override;
  public
    // Le scénario et la palette sont copiés : le fil travaille sur ses propres instances.
    // OutputFile vide : pas de FFmpeg (le récepteur seul reçoit les images).
    // Divisor : 0 = automatique (kPreviewDivisor en aperçu, 1 sinon)
    constructor Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
      Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean;
      Sink: TVideoFrameSink = nil; Divisor: Integer = 0);
    destructor Destroy; override;
    procedure Cancel;  // à préférer à Terminate : arrête aussi FFmpeg, même pendant la finalisation de la vidéo
    property FramesTotal: Integer read FFramesTotal;
    property FramesDone: Integer read FFramesDone;
    property RenderCount: Integer read FRenderCount;  // images réellement calculées (pauses réutilisées)
    property IsProfiling: Boolean read FIsProfiling;   // pré-calcul du profil de coût en cours
    property ProbesDone: Integer read FProbesDone;
    property ProbesTotal: Integer read FProbesTotal;
    property SecondsLeft: Double read GetSecondsLeft;
    property FrameWidth: Integer read FWidth;
    property FrameHeight: Integer read FHeight;
    property ErrorMessage: string read FErrorMessage;
    property IsSucceeded: Boolean read FIsSucceeded;
    property IsDone: Boolean read FIsDone;
  end;

implementation

const
  kPollMs = 50;
  kProbeEvery = 15;   // une image du profil par demi-seconde de trajet
  kProbeDivisor = 8;  // rapportée à la pleine taille, sans lissage

{------------------------------------------------------------------------------}

constructor TVideoRenderer.Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean; Sink: TVideoFrameSink;
  Divisor: Integer);
begin
  if (Scenario = nil) or (Palette = nil) then
    raise EArgumentException.Create('TVideoRenderer : scénario ou palette nil');
  if Scenario.Count = 0 then
    raise EVideoScenarioError.Create('Scénario vide.');
  FPipeLock := TCriticalSection.Create;
  FScenario := TVideoScenario.Create;
  FScenario.Assign(Scenario);
  FPalette := TGradientPalette.Create;
  FPalette.Assign(Palette);
  FMapping := Mapping;
  FKernel := Kernel;
  FFfmpegExe := FfmpegExe;
  FOutputFile := OutputFile;
  FIsPreview := IsPreview;
  FSink := Sink;
  if Divisor <= 0 then
    Divisor := IfThen(IsPreview, kPreviewDivisor, 1);
  VideoFormatSize(FScenario.Format, FWidth, FHeight);
  FWidth := Max(2, FWidth div Divisor);
  FHeight := Max(2, FHeight div Divisor);
  FFramesTotal := FScenario.TotalFrames;
  inherited Create(False);
end;

{------------------------------------------------------------------------------}

destructor TVideoRenderer.Destroy;
begin
  inherited Destroy;  // attend la fin du fil
  FPalette.Free;
  FScenario.Free;
  FPipeLock.Free;
end;

{------------------------------------------------------------------------------}

procedure TVideoRenderer.Cancel;
begin
  Terminate;
  FPipeLock.Enter;
  try
    if FPipe <> nil then
      FPipe.Kill;
  finally
    FPipeLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

function TVideoRenderer.GetSecondsLeft: Double;
var
  Done: Integer;
begin
  Done := FFramesDone;
  if Done = 0 then
    Result := 0
  else if (Length(FCost) > FFramesTotal) and (FCost[Done] > 0) then
    Result := (GetTickCount - FStartTick) / 1000 * (FCost[FFramesTotal] - FCost[Done]) / FCost[Done]
  else
    Result := (GetTickCount - FStartTick) / 1000 / Done * (FFramesTotal - Done);
end;

{------------------------------------------------------------------------------}

// Faux si le rendu a été interrompu
function TVideoRenderer.RenderFrame(const Pose: TCameraPose; Formula: TFractalFormula; Target: TStream;
  Width, Height, Supersample: Integer): Boolean;
var
  V: TViewport;
  Settings: THiResSettings;
  R: THiResRenderer;
begin
  V.Width := Pose.Width;
  V.PixelWidth := Width;
  V.PixelHeight := Height;
  V.SetCenter(Pose.CenterX, Pose.CenterY);
  Formula.MaxIter := AutoMaxIter(V);  // varie avec la profondeur, sans saut d'une image à l'autre
  Settings.Width := Width;
  Settings.Height := Height;
  Settings.Supersample := Supersample;
  Settings.FileName := '';
  Target.Size := 0;
  R := THiResRenderer.Create(Settings, V, Formula, TColorMapper.Create(FPalette, FMapping), '', FKernel,
    kHiResBandRows, Target);
  try
    while WaitForSingleObject(R.Handle, kPollMs) = WAIT_TIMEOUT do
      if Terminated then
        R.Terminate;
    Result := R.IsSucceeded;
    if not Result and not Terminated then
      raise EVideoEncoderError.Create(R.ErrorMessage);
  finally
    R.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Mesure le coût d'une image sur kProbeEvery, en petit, puis remplit FCost en interpolant entre ces mesures ;
// une pause ne coûte rien. Faux si le rendu a été interrompu
function TVideoRenderer.Profile(Formula: TFractalFormula; Target: TStream): Boolean;
var
  Probes: array of Integer;
  Costs: array of Double;
  I, K, LastMove: Integer;
  IsPause: Boolean;
  Pose: TCameraPose;
  Frequency, T0, T1: Int64;
  Cost: Double;
begin
  Result := True;
  LastMove := -1;
  for I := 0 to FFramesTotal - 1 do
  begin
    FScenario.PoseAtFrame(I, IsPause);
    if not IsPause then
    begin
      if (I mod kProbeEvery = 0) or (Length(Probes) = 0) then
      begin
        SetLength(Probes, Length(Probes) + 1);
        Probes[High(Probes)] := I;
      end;
      LastMove := I;
    end;
  end;
  if LastMove < 0 then
    Exit;  // que des pauses : l'estimation au nombre d'images suffit
  if Probes[High(Probes)] <> LastMove then
  begin
    SetLength(Probes, Length(Probes) + 1);
    Probes[High(Probes)] := LastMove;
  end;
  SetLength(Costs, Length(Probes));
  FProbesTotal := Length(Probes);
  FIsProfiling := True;
  try
    QueryPerformanceFrequency(Frequency);
    for K := 0 to High(Probes) do
    begin
      if Terminated then
        Exit(False);
      Pose := FScenario.PoseAtFrame(Probes[K], IsPause);
      QueryPerformanceCounter(T0);
      if not RenderFrame(Pose, Formula, Target, Max(2, FWidth div kProbeDivisor), Max(2, FHeight div kProbeDivisor),
        1) then
        Exit(False);
      QueryPerformanceCounter(T1);
      Costs[K] := (T1 - T0) / Frequency;
      Inc(FProbesDone);
    end;
  finally
    FIsProfiling := False;
  end;
  SetLength(FCost, FFramesTotal + 1);
  FCost[0] := 0;
  K := 0;
  for I := 0 to FFramesTotal - 1 do
  begin
    FScenario.PoseAtFrame(I, IsPause);
    while (K < High(Probes)) and (Probes[K + 1] <= I) do
      Inc(K);
    if IsPause then
      Cost := 0
    else if (K = High(Probes)) or (I <= Probes[K]) then
      Cost := Costs[K]
    else
      Cost := Costs[K] + (Costs[K + 1] - Costs[K]) * (I - Probes[K]) / (Probes[K + 1] - Probes[K]);
    FCost[I + 1] := FCost[I] + Cost;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoRenderer.Execute;
var
  Formula: TFractalFormula;
  Pipe: TFfmpegPipe;
  Frame: TMemoryStream;
  I: Integer;
  Pose: TCameraPose;
  IsPause, HasFrame: Boolean;
begin
  Formula := nil;
  Pipe := nil;
  Frame := TMemoryStream.Create;
  try
    try
      Formula := FScenario.CreateFormula;
      if not Profile(Formula, Frame) then
        Exit;
      FStartTick := GetTickCount;
      if FOutputFile <> '' then
      begin
        Pipe := TFfmpegPipe.Create(FFfmpegExe, FOutputFile, kVideoFps);
        FPipeLock.Enter;
        FPipe := Pipe;
        FPipeLock.Leave;
      end;
      HasFrame := False;
      for I := 0 to FScenario.TotalFrames - 1 do
      begin
        if Terminated then
          Break;
        Pose := FScenario.PoseAtFrame(I, IsPause);
        // une pause montre l'étape, déjà rendue par l'image précédente (fin de trajet ou pause)
        if not (IsPause and HasFrame) then
        begin
          if not RenderFrame(Pose, Formula, Frame, FWidth, FHeight, FScenario.Smoothing) then
            Break;
          Inc(FRenderCount);
          HasFrame := True;
        end;
        if Assigned(FSink) then
          FSink(Frame);
        if Pipe <> nil then
          Pipe.WriteFrame(Frame);
        Inc(FFramesDone);
      end;
      if Terminated then
      begin
        if Pipe <> nil then
          Pipe.Abort;
      end
      else
      begin
        if Pipe <> nil then
          Pipe.Finish;
        FIsSucceeded := True;  // la vidéo est complète, même si une annulation arrive maintenant
      end;
    except
      on E: Exception do
      begin
        if not Terminated then  // FFmpeg tué par Cancel : une annulation, pas une erreur
          FErrorMessage := E.Message;
        if Pipe <> nil then
          Pipe.Abort;
      end;
    end;
  finally
    FPipeLock.Enter;
    FPipe := nil;
    FPipeLock.Leave;
    Pipe.Free;
    Formula.Free;
    Frame.Free;
    FIsDone := True;
  end;
end;

end.
