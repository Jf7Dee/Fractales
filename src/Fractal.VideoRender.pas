unit Fractal.VideoRender;

// Rendu d'une vidéo : chaque image du scénario est rendue par THiResRenderer dans un flux PNG, puis passée à
// FFmpeg (ou à un récepteur, pour l'aperçu et les tests). Les images d'une pause ne sont rendues qu'une fois.

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.HiRes, Fractal.VideoPath, Fractal.VideoScenario, Fractal.VideoEncoder, SyncObjs;

const
  kPreviewDivisor = 4;  // l'aperçu est rendu au quart de la taille, sans les pauses

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
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    FPipe: TFfmpegPipe;          // visé par Cancel depuis le fil principal, sous FPipeLock
    FPipeLock: TCriticalSection;
    function IsEmitted(Frame: Integer): Boolean;
    function RenderFrame(const Pose: TCameraPose; Formula: TFractalFormula; Target: TStream): Boolean;
    function GetSecondsLeft: Double;
  protected
    procedure Execute; override;
  public
    // Le scénario et la palette sont copiés : le fil travaille sur ses propres instances.
    // Divisor : 0 = automatique (kPreviewDivisor en aperçu, 1 sinon)
    constructor Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
      Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean;
      Sink: TVideoFrameSink = nil; Divisor: Integer = 0);
    destructor Destroy; override;
    procedure Cancel;  // à préférer à Terminate : arrête aussi FFmpeg, même pendant la finalisation de la vidéo
    property FramesTotal: Integer read FFramesTotal;
    property FramesDone: Integer read FFramesDone;
    property RenderCount: Integer read FRenderCount;  // images réellement calculées (pauses réutilisées)
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

{------------------------------------------------------------------------------}

constructor TVideoRenderer.Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean; Sink: TVideoFrameSink;
  Divisor: Integer);
var
  I: Integer;
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
  for I := 0 to FScenario.TotalFrames - 1 do
    if IsEmitted(I) then
      Inc(FFramesTotal);
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

function TVideoRenderer.IsEmitted(Frame: Integer): Boolean;
var
  IsPause: Boolean;
begin
  Result := True;
  if FIsPreview then
  begin
    FScenario.PoseAtFrame(Frame, IsPause);
    Result := not IsPause;
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
  else
    Result := (GetTickCount - FStartTick) / 1000 / Done * (FFramesTotal - Done);
end;

{------------------------------------------------------------------------------}

// Faux si le rendu a été interrompu
function TVideoRenderer.RenderFrame(const Pose: TCameraPose; Formula: TFractalFormula; Target: TStream): Boolean;
var
  V: TViewport;
  Settings: THiResSettings;
  R: THiResRenderer;
begin
  V.Width := Pose.Width;
  V.PixelWidth := FWidth;
  V.PixelHeight := FHeight;
  V.SetCenter(Pose.CenterX, Pose.CenterY);
  Formula.MaxIter := AutoMaxIter(V);  // varie avec la profondeur, sans saut d'une image à l'autre
  Settings.Width := FWidth;
  Settings.Height := FHeight;
  Settings.Supersample := FScenario.Smoothing;
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
      FStartTick := GetTickCount;
      Formula := FScenario.CreateFormula;
      if not Assigned(FSink) then
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
        if IsPause and FIsPreview then
          Continue;
        // une pause montre l'étape, déjà rendue par l'image précédente (fin de trajet ou pause)
        if not (IsPause and HasFrame) then
        begin
          if not RenderFrame(Pose, Formula, Frame) then
            Break;
          Inc(FRenderCount);
          HasFrame := True;
        end;
        if Assigned(FSink) then
          FSink(Frame)
        else
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
