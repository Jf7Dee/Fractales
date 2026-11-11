unit Fractal.VideoRender;

// Rendu d'une vidéo : chaque image du scénario est rendue par THiResRenderer dans un flux PNG, puis passée à
// FFmpeg, à un récepteur (aperçu en direct, tests), ou aux deux. Les images d'une pause ne sont rendues qu'une fois.
// Avant le rendu, une image sur kProbeEvery est calculée en petit : ce profil de coût guide l'estimation du temps
// restant, car une image coûte très différemment selon la profondeur et la part d'intérieur à l'écran.
// La vidéo est encodée par morceaux, dans un dossier à côté d'elle, puis assemblée : une génération interrompue
// (mise à jour de Windows, panne, Interrompre) reprend au premier morceau manquant si rien n'a changé depuis.

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.HiRes, Fractal.VideoPath, Fractal.VideoScenario, Fractal.VideoEncoder, Fractal.Persistence, SyncObjs;

const
  kPreviewDivisor = 4;  // l'aperçu est rendu au quart de la taille
  kSegmentFrames = 300;  // un morceau = 10 s de vidéo ; une interruption en perd au plus un
  kPartsSuffix = '.morceaux';

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
    FFrameProgress: Integer;  // avancement de l'image en cours, 0..kProgressMax
    FSegmentFrames: Integer;
    FFirstFrame: Integer;     // première image calculée : les précédentes viennent des morceaux d'une génération interrompue
    FPartsFolder: string;
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
    function PartFile(Index: Integer): string;
    function PendingPartFile: string;
    function StampText(Formula: TFractalFormula): string;
    procedure PrepareParts(Formula: TFractalFormula);
    procedure RemoveParts;
    procedure SetPipe(Pipe: TFfmpegPipe);
    procedure OpenPart(var Pipe: TFfmpegPipe);
    procedure ClosePart(var Pipe: TFfmpegPipe; Index: Integer);
    procedure JoinParts;
    function GetSecondsLeft: Double;
  protected
    procedure Execute; override;
  public
    // Le scénario et la palette sont copiés : le fil travaille sur ses propres instances.
    // OutputFile vide : pas de FFmpeg (le récepteur seul reçoit les images).
    // Divisor : 0 = automatique (kPreviewDivisor en aperçu, 1 sinon). SegmentFrames : 0 = kSegmentFrames
    constructor Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
      Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean;
      Sink: TVideoFrameSink = nil; Divisor: Integer = 0; SegmentFrames: Integer = 0);
    destructor Destroy; override;
    procedure Cancel;  // à préférer à Terminate : arrête aussi FFmpeg, même pendant la finalisation de la vidéo
    property FramesTotal: Integer read FFramesTotal;
    property FramesDone: Integer read FFramesDone;
    property RenderCount: Integer read FRenderCount;  // images réellement calculées (pauses réutilisées)
    property IsProfiling: Boolean read FIsProfiling;   // pré-calcul du profil de coût en cours
    property ProbesDone: Integer read FProbesDone;
    property ProbesTotal: Integer read FProbesTotal;
    property FirstFrame: Integer read FFirstFrame;  // > 0 : génération reprise
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
  kStampName = 'scenario.txt';  // ce qui a produit les morceaux : s'il diffère, ils sont écartés
  kListName = 'liste.txt';
  kPartName = 'morceau%.4d.mp4';
  kPendingPartName = 'morceau-en-cours.mp4';
  kEsContinuous = $80000000;    // SetThreadExecutionState
  kEsSystemRequired = $00000001;

function SetThreadExecutionState(Flags: DWORD): DWORD; stdcall; external kernel32 name 'SetThreadExecutionState';

{------------------------------------------------------------------------------}

constructor TVideoRenderer.Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean; Sink: TVideoFrameSink;
  Divisor, SegmentFrames: Integer);
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
  FSegmentFrames := IfThen(SegmentFrames > 0, SegmentFrames, kSegmentFrames);
  if OutputFile <> '' then
    FPartsFolder := OutputFile + kPartsSuffix + PathDelim;
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

// L'image en cours compte pour sa part déjà calculée : sans elle, l'estimation monte pendant chaque image et
// redescend d'un coup à la suivante. Les images reprises d'une génération interrompue ne comptent pas
function TVideoRenderer.GetSecondsLeft: Double;
var
  Done: Integer;
  Fraction, DoneCost, Elapsed: Double;
begin
  Done := FFramesDone;
  Fraction := Min(1, FFrameProgress / kProgressMax);
  Elapsed := (GetTickCount - FStartTick) / 1000;
  Result := 0;
  if Done < FFirstFrame then
    Exit;
  if Length(FCost) > FFramesTotal then
  begin
    DoneCost := FCost[Done];
    if Done < FFramesTotal then
      DoneCost := DoneCost + (FCost[Done + 1] - FCost[Done]) * Fraction;
    if DoneCost > FCost[FFirstFrame] then
      Result := Elapsed * (FCost[FFramesTotal] - DoneCost) / (DoneCost - FCost[FFirstFrame]);
  end
  else if Done - FFirstFrame + Fraction > 0 then
    Result := Elapsed / (Done - FFirstFrame + Fraction) * (FFramesTotal - Done - Fraction);
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
    begin
      FFrameProgress := R.Progress;
      if Terminated then
        R.Terminate;
    end;
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
  for I := FFirstFrame to FFramesTotal - 1 do
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

function TVideoRenderer.PartFile(Index: Integer): string;
begin
  Result := FPartsFolder + Format(kPartName, [Index]);
end;

{------------------------------------------------------------------------------}

function TVideoRenderer.PendingPartFile: string;
begin
  Result := FPartsFolder + kPendingPartName;
end;

{------------------------------------------------------------------------------}

// Tout ce qui change les images : scénario, palette, coloration, taille, découpage
function TVideoRenderer.StampText(Formula: TFractalFormula): string;
var
  L: TFractalLocation;
  S: TStringList;
begin
  L := TFractalLocation.Create;
  S := TStringList.Create;
  try
    L.CaptureFrom(Formula, MakeViewport(0, 0, kDefaultWidth, 1, 1), False, FPalette, FMapping);
    S.Text := FScenario.SaveToText + L.SaveToText + Format('Taille=%dx%d'#13#10'Morceau=%d'#13#10,
      [FWidth, FHeight, FSegmentFrames]);
    Result := S.Text;  // tel que TStringList le relira
  finally
    S.Free;
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Reprend les morceaux d'une génération interrompue s'ils viennent du même rendu, sinon repart de zéro
procedure TVideoRenderer.PrepareParts(Formula: TFractalFormula);
var
  Stamp: string;
  S: TStringList;
  IsSameRender: Boolean;
  Count: Integer;
begin
  Stamp := StampText(Formula);
  S := TStringList.Create;
  try
    IsSameRender := False;
    if FileExists(FPartsFolder + kStampName) then
    try
      S.LoadFromFile(FPartsFolder + kStampName);
      IsSameRender := S.Text = Stamp;
    except
      on E: EStreamError do
        IsSameRender := False;
    end;
    if IsSameRender then
    begin
      Count := 0;
      while FileExists(PartFile(Count)) do
        Inc(Count);
      FFirstFrame := Min(Count * FSegmentFrames, FFramesTotal);
      FFramesDone := FFirstFrame;
    end
    else
    begin
      RemoveParts;
      if not ForceDirectories(FPartsFolder) then
        raise EVideoEncoderError.CreateFmt('Dossier des morceaux impossible à créer : %s', [FPartsFolder]);
      S.Text := Stamp;
      S.SaveToFile(FPartsFolder + kStampName, TEncoding.UTF8);
    end;
  finally
    S.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoRenderer.RemoveParts;
var
  Found: TSearchRec;
begin
  if FindFirst(FPartsFolder + '*', faAnyFile and not faDirectory, Found) = 0 then
  try
    repeat
      SysUtils.DeleteFile(FPartsFolder + Found.Name);
    until FindNext(Found) <> 0;
  finally
    SysUtils.FindClose(Found);
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(FPartsFolder));
end;

{------------------------------------------------------------------------------}

// Le FFmpeg en cours, que Cancel peut arrêter
procedure TVideoRenderer.SetPipe(Pipe: TFfmpegPipe);
begin
  FPipeLock.Enter;
  try
    FPipe := Pipe;
  finally
    FPipeLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoRenderer.OpenPart(var Pipe: TFfmpegPipe);
begin
  SysUtils.DeleteFile(PendingPartFile);
  Pipe := TFfmpegPipe.Create(FFfmpegExe, PendingPartFile, kVideoFps);
  SetPipe(Pipe);
end;

{------------------------------------------------------------------------------}

// Un morceau ne prend son nom définitif qu'une fois complet : la reprise ne voit jamais un morceau tronqué
procedure TVideoRenderer.ClosePart(var Pipe: TFfmpegPipe; Index: Integer);
begin
  Pipe.Finish;
  SetPipe(nil);
  FreeAndNil(Pipe);
  SysUtils.DeleteFile(PartFile(Index));
  if not RenameFile(PendingPartFile, PartFile(Index)) then
    raise EVideoEncoderError.CreateFmt('Morceau %d impossible à renommer : %s', [Index, SysErrorMessage(GetLastError)]);
end;

{------------------------------------------------------------------------------}

procedure TVideoRenderer.JoinParts;
var
  List: TStringList;
  Pipe: TFfmpegPipe;
  I: Integer;
begin
  List := TStringList.Create;
  try
    for I := 0 to (FFramesTotal - 1) div FSegmentFrames do
      List.Add('file ''' + ExtractFileName(PartFile(I)) + '''');
    List.SaveToFile(FPartsFolder + kListName, TEncoding.ASCII);
  finally
    List.Free;
  end;
  Pipe := TFfmpegPipe.CreateWithArguments(FFfmpegExe, FOutputFile,
    FfmpegConcatArguments(FPartsFolder + kListName, FOutputFile));
  try
    SetPipe(Pipe);
    Pipe.Finish;
  finally
    SetPipe(nil);
    Pipe.Free;
  end;
  RemoveParts;
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
  SetThreadExecutionState(kEsContinuous or kEsSystemRequired);  // pas de mise en veille pendant le rendu
  try
    try
      Formula := FScenario.CreateFormula;
      if FOutputFile <> '' then
        PrepareParts(Formula);
      if not Profile(Formula, Frame) then
        Exit;
      FFrameProgress := 0;  // la dernière image du profil ne compte pas
      FStartTick := GetTickCount;
      HasFrame := False;
      for I := FFirstFrame to FFramesTotal - 1 do
      begin
        if Terminated then
          Break;
        if (FOutputFile <> '') and (I mod FSegmentFrames = 0) then
        begin
          if Pipe <> nil then
            ClosePart(Pipe, I div FSegmentFrames - 1);
          OpenPart(Pipe);
        end;
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
        FFrameProgress := 0;
        Inc(FFramesDone);
      end;
      // interrompu : seul le morceau en cours est perdu, les autres attendent la reprise
      if Terminated then
      begin
        if Pipe <> nil then
          Pipe.Abort;
      end
      else
      begin
        if Pipe <> nil then
          ClosePart(Pipe, (FFramesTotal - 1) div FSegmentFrames);
        if FOutputFile <> '' then
          JoinParts;
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
    SetThreadExecutionState(kEsContinuous);
    SetPipe(nil);
    Pipe.Free;
    Formula.Free;
    Frame.Free;
    FIsDone := True;
  end;
end;

end.
