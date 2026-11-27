unit Fractal.VideoRender;

// Rendu d'une vidéo : chaque image du scénario est rendue par THiResRenderer dans un flux PNG, puis passée à
// FFmpeg, à un récepteur (aperçu en direct, tests), ou aux deux. Les images d'une pause ne sont rendues qu'une fois.
// Avant le rendu, une image sur kProbeEvery est calculée en petit : ce profil de coût guide l'estimation du temps
// restant, car une image coûte très différemment selon la profondeur et la part d'intérieur à l'écran.
// La vidéo est encodée par morceaux, dans un dossier à côté d'elle, puis assemblée : une génération interrompue
// (mise à jour de Windows, panne, Interrompre) ne calcule que les morceaux manquants si rien n'a changé depuis. Une
// plage de morceaux peut être calculée seule, sur une autre machine : l'assemblage attend un rendu de toute la vidéo.

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.HiRes, Fractal.VideoPath, Fractal.VideoScenario, Fractal.VideoEncoder, Fractal.Persistence, Fractal.Update,
  Fractal.RustKernel, SyncObjs, Types;

const
  kPreviewDivisor = 4;  // l'aperçu est rendu au quart de la taille
  kSegmentFrames = 50;  // un morceau = 1,7 s de vidéo ; une interruption en perd au plus un
  kPartsSuffix = '.morceaux';
  kStampName = 'scenario.txt';  // dans le dossier des morceaux : ce qui les a produits ; s'il diffère, ils sont écartés

type
  // Appelé dans le fil de rendu, une fois par image
  TVideoFrameSink = procedure(Png: TStream) of object;

  TGenerationOutcome = (goSucceeded, goCancelled, goFailed);

  // Une session de génération, pour le journal écrit à côté de la vidéo
  TGenerationLogEntry = record
    StartTime, EndTime: TDateTime;
    ScenarioFile: string;  // vide : scénario non enregistré
    VideoFormat: TVideoFormat;
    FramesTotal: Integer;
    FramesDone: Integer;
    FirstFrame: Integer;   // > 0 : génération reprise
    RangeFirstFrame, RangeLastFrame: Integer;  // plage d'images rendue ; -1 = toute la vidéo
    Outcome: TGenerationOutcome;
    ErrorMessage: string;
  end;

  TVideoRenderer = class(TThread)
  private
    FScenario: TVideoScenario;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FKernel: TEngineKernelType;
    FIsBla: Boolean;
    FIsAdaptive: Boolean;
    FIsProfileOnly: Boolean;
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
    FFirstSegment, FLastSegment: Integer;  // la plage de morceaux à rendre
    FFramesInRange: Integer;
    FIsWholeVideo: Boolean;
    FPlan: array of Integer;  // les images à calculer dans cette session, dans l'ordre : celles des morceaux absents
    FPlanCount: Integer;      // Length(FPlan), lu par l'estimation
    FPlanDone: Integer;       // images de FPlan faites
    FPartsFolder: string;
    FFingerprint: string;     // l'empreinte du tampon, inscrite dans chaque morceau
    FStartTick: Cardinal;
    FCost: array of Double;  // coût prévu cumulé de FPlan : FCost[J] = images FPlan[0..J-1] ; vide = pas de profil
    FDoneAt: array of Double;  // secondes écoulées depuis FStartTick à la fin de chaque image de FPlan
    FIsProfiling: Boolean;
    FProbesDone: Integer;
    FProbesTotal: Integer;
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    FPipe: TFfmpegPipe;          // visé par Cancel depuis le fil principal, sous FPipeLock
    FPipeLock: TCriticalSection;
    function RenderFrame(const Pose: TCameraPose; Formula: TFractalFormula; Target: TStream;
      Width, Height, Supersample: Integer; TierPixelSize: TFloat = 0): Boolean;
    function Profile(Formula: TFractalFormula; Target: TStream): Boolean;
    function PartFile(Index: Integer): string;
    function PendingPartFile: string;
    procedure PrepareParts;
    function HasPartFiles: Boolean;
    procedure BuildPlan;
    procedure SetPipe(Pipe: TFfmpegPipe);
    procedure OpenPart(var Pipe: TFfmpegPipe);
    procedure ClosePart(var Pipe: TFfmpegPipe; Index: Integer);
    procedure JoinParts;
    function GetSecondsLeft: Double;
    function GetCost: TDoubleDynArray;
  protected
    procedure Execute; override;
  public
    // Le scénario et la palette sont copiés : le fil travaille sur ses propres instances.
    // OutputFile vide : pas de FFmpeg (le récepteur seul reçoit les images).
    // Divisor : 0 = automatique (kPreviewDivisor en aperçu, 1 sinon). SegmentFrames : 0 = kSegmentFrames.
    // FirstSegment..LastSegment : la plage de morceaux à rendre, -1 = jusqu'au dernier ; hors bornes, ramenée aux
    // morceaux de la vidéo. Les morceaux déjà présents sont sautés ; la vidéo n'est assemblée que pour une plage
    // qui la couvre entière
    // IsProfileOnly : ne calcule que le profil de coût de toute la vidéo (plage et OutputFile ignorés, aucun dossier
    // de morceaux touché, aucune image envoyée) puis s'arrête ; le résultat est Cost
    constructor Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
      Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean;
      Sink: TVideoFrameSink = nil; Divisor: Integer = 0; SegmentFrames: Integer = 0; IsBla: Boolean = False;
      IsAdaptive: Boolean = False; FirstSegment: Integer = 0; LastSegment: Integer = -1;
      IsProfileOnly: Boolean = False);
    destructor Destroy; override;
    procedure Cancel;  // à préférer à Terminate : arrête aussi FFmpeg, même pendant la finalisation de la vidéo
    property FramesTotal: Integer read FFramesTotal;
    property FramesDone: Integer read FFramesDone;  // images de la plage faites : morceaux présents, puis calculées
    property FramesInRange: Integer read FFramesInRange;
    property IsWholeVideo: Boolean read FIsWholeVideo;  // la plage couvre toute la vidéo : elle sera assemblée
    property RenderCount: Integer read FRenderCount;  // images réellement calculées (pauses réutilisées)
    property IsProfiling: Boolean read FIsProfiling;   // pré-calcul du profil de coût en cours
    property ProbesDone: Integer read FProbesDone;
    property ProbesTotal: Integer read FProbesTotal;
    property FirstFrame: Integer read FFirstFrame;  // première image calculée dans la session ; > 0 : reprise ou plage
    property SecondsLeft: Double read GetSecondsLeft;
    property FrameWidth: Integer read FWidth;
    property FrameHeight: Integer read FHeight;
    property ErrorMessage: string read FErrorMessage;
    property IsSucceeded: Boolean read FIsSucceeded;
    property IsDone: Boolean read FIsDone;
    // coût prévu cumulé de toute la vidéo (profil seul) : Cost[I] = images 0..I-1, TotalFrames + 1 valeurs ; à lire
    // une fois le fil terminé
    property Cost: TDoubleDynArray read GetCost;
  end;

// Secondes restantes d'après le profil Cost (coûts prévus cumulés : Cost[I] = images 0..I-1) et DoneAt (secondes
// écoulées à la fin de chaque image faite depuis FirstFrame). Le rapport entre durée réelle et coût prévu est pris sur
// les Window dernières images : à l'entrée d'une zone plus chère que prévu, l'estimation suit en quelques images.
// Fraction : part faite de l'image en cours
function RemainingSeconds(const Cost, DoneAt: array of Double; FirstFrame, Done: Integer;
  Fraction, Elapsed: Double; Window: Integer): Double;

// Itérations d'une image : automatiques selon la profondeur, plafonnées par Limit s'il est positif
function VideoMaxIter(const V: TViewport; Limit: Integer): Integer;

// Le noyau de calcul dans le tampon : Delphi, ou la DLL Rust (version de son fichier et ABI) si elle est chargée
function KernelStampText(Kernel: TEngineKernelType): string;

// Le tampon complet d'un rendu : tout ce qui change les images (scénario, palette, coloration, taille, découpage, BLA,
// lissage adaptatif), puis la version de Fractales et le noyau. Une machine de rendu et une autre se comparent par là
function RenderStamp(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Width, Height, SegmentFrames: Integer; IsBla, IsAdaptive: Boolean; Kernel: TEngineKernelType): string;

// L'empreinte d'un tampon : FRACTALES- et 16 chiffres hexadécimaux (FNV-1a 64 bits sur l'UTF-8 du tampon). Inscrite
// dans les métadonnées de chaque morceau : un morceau copié d'une autre machine dit de quel rendu il vient
function StampFingerprint(const Stamp: string): string;

// Vrai si le fichier contient les octets ASCII de Fingerprint ; faux s'il est absent ou illisible
function PartHasFingerprint(const PartFile, Fingerprint: string): Boolean;

// Ce qui sépare deux tampons, en un texte pour l'utilisateur ; vide s'ils sont identiques. Par ordre de priorité : la
// version de Fractales, le noyau, puis le scénario ou les réglages
function StampDifference(const Expected, Found: string): string;

// Ce qui sépare le tampon du dossier des morceaux de OutputFile et Stamp, en un texte pour l'utilisateur ; vide si le
// dossier n'existe pas, n'a pas de tampon, ou a ce tampon
function PartsStampDifference(const OutputFile, Stamp: string): string;

// Efface le dossier des morceaux de OutputFile, avec son contenu. Le rendu ne l'appelle jamais de lui-même : seule la
// jonction réussie, ou un lancement que l'utilisateur a confirmé
procedure RemovePartsFolder(const OutputFile: string);

// Rendu interrompu vers OutputFile : scénario, palette et coloration relus dans le dossier des morceaux, et nombre
// d'images des morceaux présents, où qu'ils soient. Faux si le dossier ou son scénario manque ou est illisible
function ReadInterruptedRender(const OutputFile: string; Scenario: TVideoScenario; Location: TFractalLocation;
  out FramesDone: Integer): Boolean;

// Journal des générations d'une vidéo : même dossier et même nom qu'elle, extension .log ; une entrée par session
function GenerationLogFile(const OutputFile: string): string;
function GenerationLogText(const Entry: TGenerationLogEntry): string;
procedure AppendGenerationLog(const OutputFile: string; const Entry: TGenerationLogEntry);

implementation

const
  kPollMs = 50;
  kProbeEvery = 15;   // une image du profil par demi-seconde de trajet
  kProbeDivisor = 8;  // rapportée à la pleine taille, sans lissage
  kEtaWindowFrames = 150;  // rythme réel mesuré sur les 5 dernières secondes de vidéo
  kListName = 'liste.txt';
  kPartName = 'morceau%.4d.mp4';
  kPendingPartName = 'morceau-en-cours.mp4';
  kEsContinuous = $80000000;    // SetThreadExecutionState
  kEsSystemRequired = $00000001;

function SetThreadExecutionState(Flags: DWORD): DWORD; stdcall; external kernel32 name 'SetThreadExecutionState';

{------------------------------------------------------------------------------}

constructor TVideoRenderer.Create(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Kernel: TEngineKernelType; const FfmpegExe, OutputFile: string; IsPreview: Boolean; Sink: TVideoFrameSink;
  Divisor, SegmentFrames: Integer; IsBla, IsAdaptive: Boolean; FirstSegment, LastSegment: Integer;
  IsProfileOnly: Boolean);
var
  LastOfVideo: Integer;
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
  FIsBla := IsBla;
  FIsAdaptive := IsAdaptive;
  FFfmpegExe := FfmpegExe;
  FIsProfileOnly := IsProfileOnly;
  if not IsProfileOnly then  // le profil seul ne touche à aucun dossier de morceaux
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
  LastOfVideo := Max(0, FFramesTotal - 1) div FSegmentFrames;
  if LastSegment = -1 then
    LastSegment := LastOfVideo;
  FFirstSegment := EnsureRange(FirstSegment, 0, LastOfVideo);
  FLastSegment := EnsureRange(LastSegment, FFirstSegment, LastOfVideo);
  if IsProfileOnly then  // toute la vidéo : la répartition a besoin du coût entier
  begin
    FFirstSegment := 0;
    FLastSegment := LastOfVideo;
  end;
  FIsWholeVideo := (FFirstSegment = 0) and (FLastSegment = LastOfVideo);
  FFramesInRange := Max(0, Min((FLastSegment + 1) * FSegmentFrames, FFramesTotal) - FFirstSegment * FSegmentFrames);
  if FOutputFile <> '' then
    FPartsFolder := FOutputFile + kPartsSuffix + PathDelim;
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

function TVideoRenderer.GetCost: TDoubleDynArray;
var
  I: Integer;
begin
  SetLength(Result, Length(FCost));
  for I := 0 to High(FCost) do
    Result[I] := FCost[I];
end;

{------------------------------------------------------------------------------}

// L'image en cours compte pour sa part déjà calculée : sans elle, l'estimation monte pendant chaque image et
// redescend d'un coup à la suivante. Seules comptent les images à calculer dans la session (FPlan) : les morceaux
// déjà présents n'entrent ni dans le rythme ni dans le reste
function TVideoRenderer.GetSecondsLeft: Double;
var
  Done, Count: Integer;
  Fraction, Elapsed: Double;
begin
  Done := FPlanDone;
  Count := FPlanCount;
  Fraction := Min(1, FFrameProgress / kProgressMax);
  Elapsed := (GetTickCount - FStartTick) / 1000;
  Result := 0;
  if Length(FCost) > Count then
    Result := RemainingSeconds(FCost, FDoneAt, 0, Done, Fraction, Elapsed, kEtaWindowFrames)
  else if Done + Fraction > 0 then
    Result := Elapsed / (Done + Fraction) * (Count - Done - Fraction);
end;

{------------------------------------------------------------------------------}

// Faux si le rendu a été interrompu
function TVideoRenderer.RenderFrame(const Pose: TCameraPose; Formula: TFractalFormula; Target: TStream;
  Width, Height, Supersample: Integer; TierPixelSize: TFloat): Boolean;
var
  V: TViewport;
  Settings: THiResSettings;
  R: THiResRenderer;
begin
  V.Width := Pose.Width;
  V.PixelWidth := Width;
  V.PixelHeight := Height;
  V.SetCenter(Pose.CenterX, Pose.CenterY);
  Formula.MaxIter := VideoMaxIter(V, FScenario.IterLimit);  // varie avec la profondeur, sans saut d'une image à l'autre
  Settings.Width := Width;
  Settings.Height := Height;
  Settings.Supersample := Supersample;
  Settings.FileName := '';
  Settings.IsBla := FIsBla;   // morceaux, aperçu et profil de coût : le profil prédit ainsi le vrai rendu
  Settings.IsAdaptive := FIsAdaptive;   // sans effet au profil de coût (Supersample 1)
  Settings.TierPixelSize := TierPixelSize;
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

// Mesure le coût d'une image sur kProbeEvery parmi celles de FPlan, en petit, puis remplit FCost en interpolant entre
// ces mesures ; une pause ne coûte rien, sauf en tête de morceau où elle est calculée. Faux si le rendu a été
// interrompu
function TVideoRenderer.Profile(Formula: TFractalFormula; Target: TStream): Boolean;
var
  Probes: array of Integer;
  Costs: array of Double;
  I, J, K, LastMove: Integer;
  IsPause: Boolean;
  Pose: TCameraPose;
  Frequency, T0, T1: Int64;
  Cost: Double;
begin
  Result := True;
  LastMove := -1;
  for J := 0 to High(FPlan) do
  begin
    I := FPlan[J];
    FScenario.PoseAtFrame(I, IsPause);
    if not IsPause or (I mod FSegmentFrames = 0) then
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
      // au palier de la vraie image : en petit, les pixels plus gros resteraient au calcul direct alors que la vraie
      // image passe déjà en perturbation, des dizaines de fois plus chère (mesuré : rapport 80 à 116 au lieu de 38)
      if not RenderFrame(Pose, Formula, Target, Max(2, FWidth div kProbeDivisor), Max(2, FHeight div kProbeDivisor),
        1, Pose.Width / (FWidth * FScenario.Smoothing)) then
        Exit(False);
      QueryPerformanceCounter(T1);
      Costs[K] := (T1 - T0) / Frequency;
      Inc(FProbesDone);
    end;
  finally
    FIsProfiling := False;
  end;
  SetLength(FCost, Length(FPlan) + 1);
  FCost[0] := 0;
  K := 0;
  for J := 0 to High(FPlan) do
  begin
    I := FPlan[J];
    FScenario.PoseAtFrame(I, IsPause);
    while (K < High(Probes)) and (Probes[K + 1] <= I) do
      Inc(K);
    if IsPause and (I mod FSegmentFrames <> 0) then
      Cost := 0
    else if (K = High(Probes)) or (I <= Probes[K]) then
      Cost := Costs[K]
    else
      Cost := Costs[K] + (Costs[K + 1] - Costs[K]) * (I - Probes[K]) / (Probes[K + 1] - Probes[K]);
    FCost[J + 1] := FCost[J] + Cost;
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

// Reprend les morceaux d'une génération interrompue s'ils viennent du même rendu ; ceux d'un autre rendu, ou sans
// tampon pour le dire, sont refusés, sans rien effacer
procedure TVideoRenderer.PrepareParts;
var
  Stamp, Difference: string;
  S: TStringList;
begin
  Stamp := RenderStamp(FScenario, FPalette, FMapping, FWidth, FHeight, FSegmentFrames, FIsBla, FIsAdaptive,
    FKernel);
  FFingerprint := StampFingerprint(Stamp);
  Difference := PartsStampDifference(FOutputFile, Stamp);
  if Difference <> '' then
    raise EVideoEncoderError.CreateFmt('Ces morceaux viennent d''un autre rendu (%s) : %s', [Difference, FPartsFolder]);
  S := TStringList.Create;
  try
    if not FileExists(FPartsFolder + kStampName) then
    begin
      if HasPartFiles then
        raise EVideoEncoderError.CreateFmt('Ces morceaux viennent peut-être d''un autre rendu (tampon %s absent) : %s',
          [kStampName, FPartsFolder]);
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

// Un morceau terminé dans le dossier, quel que soit son numéro ; le morceau en cours, tronqué, ne compte pas
function TVideoRenderer.HasPartFiles: Boolean;
var
  Found: TSearchRec;
begin
  Result := False;
  if FindFirst(FPartsFolder + 'morceau*.mp4', faAnyFile and not faDirectory, Found) = 0 then
  try
    repeat
      if not SameText(Found.Name, kPendingPartName) then
        Exit(True);
    until FindNext(Found) <> 0;
  finally
    SysUtils.FindClose(Found);
  end;
end;

{------------------------------------------------------------------------------}

// FPlan : les images des morceaux de la plage absents du dossier, dans l'ordre ; celles des morceaux présents comptent
// déjà comme faites. Sans FFmpeg, toute la plage est à calculer
procedure TVideoRenderer.BuildPlan;
var
  Segment, I, First, Last, Count: Integer;
begin
  SetLength(FPlan, FFramesInRange);
  Count := 0;
  for Segment := FFirstSegment to FLastSegment do
  begin
    First := Segment * FSegmentFrames;
    Last := Min(First + FSegmentFrames, FFramesTotal) - 1;
    if (FOutputFile <> '') and FileExists(PartFile(Segment)) then
      Inc(FFramesDone, Last - First + 1)
    else
      for I := First to Last do
      begin
        FPlan[Count] := I;
        Inc(Count);
      end;
  end;
  SetLength(FPlan, Count);
  if Count > 0 then
    FFirstFrame := FPlan[0]
  else
    FFirstFrame := Min((FLastSegment + 1) * FSegmentFrames, FFramesTotal);  // rien ne manque
  FPlanCount := Count;  // l'estimation ne lit que ce compte, jamais FPlan
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
  Pipe := TFfmpegPipe.Create(FFfmpegExe, PendingPartFile, kVideoFps, FFingerprint);
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
  // tous les morceaux sont vérifiés avant FFmpeg : un morceau d'un autre rendu ne doit pas finir dans la vidéo
  for I := 0 to (FFramesTotal - 1) div FSegmentFrames do
    if not PartHasFingerprint(PartFile(I), FFingerprint) then
      raise EVideoEncoderError.CreateFmt('Le morceau %s vient d''un autre rendu', [ExtractFileName(PartFile(I))]);
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
  RemovePartsFolder(FOutputFile);
end;

{------------------------------------------------------------------------------}

procedure TVideoRenderer.Execute;
var
  Formula: TFractalFormula;
  Pipe: TFfmpegPipe;
  Frame: TMemoryStream;
  I, J, Part: Integer;
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
        PrepareParts;
      BuildPlan;
      if not Profile(Formula, Frame) then
        Exit;
      if FIsProfileOnly then
      begin
        if Length(FCost) = 0 then  // que des pauses : Profile n'a rien mesuré, tout est gratuit
          SetLength(FCost, FFramesTotal + 1);
        FIsSucceeded := True;
        Exit;
      end;
      FFrameProgress := 0;  // la dernière image du profil ne compte pas
      FStartTick := GetTickCount;
      SetLength(FDoneAt, Length(FPlan));
      HasFrame := False;
      Part := -1;
      for J := 0 to High(FPlan) do
      begin
        if Terminated then
          Break;
        I := FPlan[J];
        // chaque morceau recommence : l'image qui le précède n'est peut-être pas calculée dans cette session
        if I mod FSegmentFrames = 0 then
        begin
          HasFrame := False;
          if FOutputFile <> '' then
          begin
            if Pipe <> nil then
              ClosePart(Pipe, Part);
            OpenPart(Pipe);
          end;
          Part := I div FSegmentFrames;
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
        FDoneAt[J] := (GetTickCount - FStartTick) / 1000;  // avant le compte : l'estimation lit les images comptées
        Inc(FPlanDone);
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
          ClosePart(Pipe, Part);
        if (FOutputFile <> '') and FIsWholeVideo then
          JoinParts;
        FIsSucceeded := True;  // la plage est complète, même si une annulation arrive maintenant
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

{------------------------------------------------------------------------------}

function VideoMaxIter(const V: TViewport; Limit: Integer): Integer;
begin
  Result := AutoMaxIter(V);
  if Limit > 0 then
    Result := Min(Result, Limit);  // plafond constant : pas de saut, seules les images profondes sont touchées
end;

{------------------------------------------------------------------------------}

const
  kVersionKey = 'Version=';
  kKernelKey = 'Noyau=';

{------------------------------------------------------------------------------}

function KernelStampText(Kernel: TEngineKernelType): string;
var
  V: TFileVersion;
  Rust: TRustKernel;
begin
  Result := 'Delphi';
  if Kernel <> ekRust then
    Exit;
  Rust := DefaultRustKernel;
  if (Rust = nil) or not Rust.IsAvailable then
    Exit;
  if TryReadFileVersion(Rust.FileName, V) then
    Result := Format('Rust %s ABI %d', [VersionToString(V), Rust.AbiVersion])
  else
    Result := Format('Rust sans version ABI %d', [Rust.AbiVersion]);
end;

{------------------------------------------------------------------------------}

function RenderStamp(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Width, Height, SegmentFrames: Integer; IsBla, IsAdaptive: Boolean; Kernel: TEngineKernelType): string;
const
  kPlatform = {$IFDEF WIN64}'Win64'{$ELSE}'Win32'{$ENDIF};
var
  L: TFractalLocation;
  S: TStringList;
  Formula: TFractalFormula;
  V: TFileVersion;
  VersionText: string;
begin
  if (Scenario = nil) or (Palette = nil) then
    raise EArgumentException.Create('RenderStamp : scénario ou palette nil');
  if TryReadFileVersion(ParamStr(0), V) then
    VersionText := VersionToString(V)
  else
    VersionText := 'inconnue';
  Formula := Scenario.CreateFormula;
  L := TFractalLocation.Create;
  S := TStringList.Create;
  try
    L.CaptureFrom(Formula, MakeViewport(0, 0, kDefaultWidth, 1, 1), False, Palette, Mapping);
    S.Text := Scenario.SaveToText + L.SaveToText + Format('Taille=%dx%d'#13#10'Morceau=%d'#13#10 +
      'BLA=%d'#13#10'LissageAdaptatif=%d'#13#10 + kVersionKey + '%s %s'#13#10 + kKernelKey + '%s'#13#10,
      [Width, Height, SegmentFrames, Ord(IsBla), Ord(IsAdaptive), VersionText, kPlatform, KernelStampText(Kernel)]);
    Result := S.Text;  // tel que TStringList le relira
  finally
    S.Free;
    L.Free;
    Formula.Free;
  end;
end;

{------------------------------------------------------------------------------}

// FNV-1a 64 bits : la multiplication tourne sur 64 bits, sans contrôle de débordement
{$IFOPT Q+}{$DEFINE FINGERPRINT_Q}{$ENDIF}
{$Q-}
function StampFingerprint(const Stamp: string): string;
const
  kOffsetBasis: UInt64 = $CBF29CE484222325;
  kPrime: UInt64 = $100000001B3;
var
  Bytes: UTF8String;
  Hash: UInt64;
  I: Integer;
begin
  Bytes := UTF8Encode(Stamp);
  Hash := kOffsetBasis;
  for I := 1 to Length(Bytes) do
    Hash := (Hash xor Byte(Bytes[I])) * kPrime;
  Result := 'FRACTALES-' + IntToHex(Int64(Hash), 16);
end;
{$IFDEF FINGERPRINT_Q}{$Q+}{$ENDIF}

{------------------------------------------------------------------------------}

function PartHasFingerprint(const PartFile, Fingerprint: string): Boolean;
var
  Needle: AnsiString;
  Data: TFileStream;
  Buffer: AnsiString;
begin
  Result := False;
  Needle := AnsiString(Fingerprint);
  if (Needle = '') or not FileExists(PartFile) then
    Exit;
  try
    Data := TFileStream.Create(PartFile, fmOpenRead or fmShareDenyNone);
    try
      // un morceau fait quelques Mo : lu d'un bloc, aucune empreinte à cheval sur deux lectures n'est manquée
      SetLength(Buffer, Data.Size);
      if Length(Buffer) > 0 then
        Data.ReadBuffer(Buffer[1], Length(Buffer));
    finally
      Data.Free;
    end;
  except
    on EInOutError do
      Exit;
    on EStreamError do
      Exit;
  end;
  Result := Pos(Needle, Buffer) > 0;
end;

{------------------------------------------------------------------------------}

// La valeur de la dernière ligne commençant par Key (le lieu a sa propre ligne Version=) ; vide s'il n'y en a pas
function StampValue(Lines: TStrings; const Key: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Lines.Count - 1 downto 0 do
    if Copy(Lines[I], 1, Length(Key)) = Key then
    begin
      Result := Copy(Lines[I], Length(Key) + 1, MaxInt);
      Exit;
    end;
end;

{------------------------------------------------------------------------------}

function StampDifference(const Expected, Found: string): string;
var
  A, B: TStringList;
begin
  Result := '';
  A := TStringList.Create;
  B := TStringList.Create;
  try
    A.Text := Expected;
    B.Text := Found;
    if A.Text = B.Text then
      Exit;
    if StampValue(A, kVersionKey) <> StampValue(B, kVersionKey) then
      Result := 'différence de version de Fractales'
    else if StampValue(A, kKernelKey) <> StampValue(B, kKernelKey) then
      Result := 'différence de noyau de calcul'
    else
      Result := 'différence de scénario ou réglages';
  finally
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

function PartsStampDifference(const OutputFile, Stamp: string): string;
var
  StampFile: string;
  S: TStringList;
begin
  Result := '';
  StampFile := OutputFile + kPartsSuffix + PathDelim + kStampName;
  if not FileExists(StampFile) then
    Exit;
  S := TStringList.Create;
  try
    try
      S.LoadFromFile(StampFile);
    except
      on E: EStreamError do
      begin
        Result := 'différence de scénario ou réglages';  // tampon illisible : traité comme un autre rendu
        Exit;
      end;
    end;
    Result := StampDifference(Stamp, S.Text);
  finally
    S.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure RemovePartsFolder(const OutputFile: string);
var
  Folder: string;
  Found: TSearchRec;
begin
  Folder := OutputFile + kPartsSuffix + PathDelim;
  if FindFirst(Folder + '*', faAnyFile and not faDirectory, Found) = 0 then
  try
    repeat
      SysUtils.DeleteFile(Folder + Found.Name);
    until FindNext(Found) <> 0;
  finally
    SysUtils.FindClose(Found);
  end;
  RemoveDir(ExcludeTrailingPathDelimiter(Folder));
end;

{------------------------------------------------------------------------------}

// Le scénario des morceaux (RenderStamp) : celui du scénario, puis le lieu à partir de [Fractal], puis la taille et le
// découpage, enfin les réglages BLA et LissageAdaptatif, la version de Fractales et le noyau
function ReadInterruptedRender(const OutputFile: string; Scenario: TVideoScenario; Location: TFractalLocation;
  out FramesDone: Integer): Boolean;
const
  kSizeKey = 'Taille=';
  kSegmentKey = 'Morceau=';
  kBlaKey = 'BLA=';
  kAdaptiveKey = 'LissageAdaptatif=';
  kTrailerLines = 4;  // BLA, LissageAdaptatif, Version, Noyau
var
  Folder: string;
  S, Part: TStringList;
  I, LocationLine, Segment, Last: Integer;
begin
  if (Scenario = nil) or (Location = nil) then
    raise EArgumentException.Create('ReadInterruptedRender : scénario ou lieu nil');
  Result := False;
  FramesDone := 0;
  Folder := OutputFile + kPartsSuffix + PathDelim;
  if (OutputFile = '') or not FileExists(Folder + kStampName) then
    Exit;
  S := TStringList.Create;
  Part := TStringList.Create;
  try
    try
      S.LoadFromFile(Folder + kStampName, TEncoding.UTF8);
      LocationLine := S.IndexOf('[Fractal]');
      // Last : ligne du découpage, avant les réglages
      Last := S.Count - 1;
      while (Last >= 0) and ((Copy(S[Last], 1, Length(kBlaKey)) = kBlaKey)
        or (Copy(S[Last], 1, Length(kAdaptiveKey)) = kAdaptiveKey)
        or (Copy(S[Last], 1, Length(kVersionKey)) = kVersionKey)
        or (Copy(S[Last], 1, Length(kKernelKey)) = kKernelKey)) do
        Dec(Last);
      // tampon d'une version antérieure (sans les quatre lignes finales) : jamais repris (PrepareParts l'écarterait et
      // effacerait ses morceaux), donc pas proposé
      if (Last <> S.Count - 1 - kTrailerLines) or (LocationLine < 1) or (Last < LocationLine + 2) or
        (Copy(S[Last - 1], 1, Length(kSizeKey)) <> kSizeKey) or
        (Copy(S[Last], 1, Length(kSegmentKey)) <> kSegmentKey) then
        Exit;
      Segment := StrToIntDef(Copy(S[Last], Length(kSegmentKey) + 1, MaxInt), 0);
      if Segment <= 0 then
        Exit;
      for I := 0 to LocationLine - 1 do
        Part.Add(S[I]);
      Scenario.LoadFromText(Part.Text);
      Part.Clear;
      for I := LocationLine to Last - 2 do
        Part.Add(S[I]);
      Location.LoadFromText(Part.Text);
      // une palette sans nom est relue « Sans nom » : le rendu rebâti doit redonner le même texte
      I := Part.IndexOf('[Palette]');
      if (I >= 0) and (Part.IndexOf('Name=') > I) then
        Location.Palette.Name := '';
    except
      on E: Exception do
        Exit;  // illisible : rien à reprendre
    end;
    for I := 0 to (Scenario.TotalFrames - 1) div Segment do
      if FileExists(Folder + Format(kPartName, [I])) then
        Inc(FramesDone, Min(Segment, Scenario.TotalFrames - I * Segment));
    Result := True;
  finally
    Part.Free;
    S.Free;
  end;
end;

{------------------------------------------------------------------------------}

function GenerationLogFile(const OutputFile: string): string;
begin
  Result := ChangeFileExt(OutputFile, '.log');
end;

{------------------------------------------------------------------------------}

// 1 h 49 min 36 s, 4 min 05 s, 12 s
function DurationText(Seconds: Integer): string;
begin
  if Seconds >= 3600 then
    Result := Format('%d h %d min %.2d s', [Seconds div 3600, (Seconds div 60) mod 60, Seconds mod 60])
  else if Seconds >= 60 then
    Result := Format('%d min %.2d s', [Seconds div 60, Seconds mod 60])
  else
    Result := Format('%d s', [Seconds]);
end;

{------------------------------------------------------------------------------}

function GenerationLogText(const Entry: TGenerationLogEntry): string;
const
  kStamp = 'yyyy-mm-dd hh:nn:ss';
var
  Outcome, Scenario, Resumed, Range: string;
  Width, Height: Integer;
  IsPartial: Boolean;
begin
  IsPartial := (Entry.RangeFirstFrame >= 0) and (Entry.RangeLastFrame >= 0);
  case Entry.Outcome of
    goSucceeded: if IsPartial then Outcome := 'plage terminée' else Outcome := 'terminée';
    // FramesDone est un compte d'images faites (morceaux déjà présents compris), pas un numéro d'image
    goCancelled: Outcome := Format('interrompue, %d images faites', [Entry.FramesDone]);
  else
    Outcome := 'échec, ' + Entry.ErrorMessage;
  end;
  Scenario := Entry.ScenarioFile;
  if Scenario = '' then
    Scenario := '(non enregistré)';
  Resumed := '';
  if Entry.FirstFrame > 0 then
    Resumed := Format(' (reprise à l''image %d)', [Entry.FirstFrame]);
  Range := '';
  if IsPartial then
    Range := Format('  Plage : images %d à %d', [Entry.RangeFirstFrame, Entry.RangeLastFrame]) + #13#10;
  VideoFormatSize(Entry.VideoFormat, Width, Height);
  Result := Format('%s → %s (%s) : %s', [FormatDateTime(kStamp, Entry.StartTime), FormatDateTime(kStamp, Entry.EndTime),
      DurationText(Round((Entry.EndTime - Entry.StartTime) * SecsPerDay)), Outcome]) + #13#10 +
    '  Scénario : ' + Scenario + #13#10 +
    Format('  Vidéo : %s, %d × %d, %d images%s', [VideoFormatName(Entry.VideoFormat), Width, Height,
      Entry.FramesTotal, Resumed]) + #13#10 + Range;
end;

{------------------------------------------------------------------------------}

procedure AppendGenerationLog(const OutputFile: string; const Entry: TGenerationLogEntry);
var
  T: TStringList;
  FileName: string;
begin
  FileName := GenerationLogFile(OutputFile);
  T := TStringList.Create;
  try
    if FileExists(FileName) then
    begin
      T.LoadFromFile(FileName, TEncoding.UTF8);
      T.Add('');
    end;
    T.Text := T.Text + GenerationLogText(Entry);
    T.SaveToFile(FileName, TEncoding.UTF8);
  finally
    T.Free;
  end;
end;

{------------------------------------------------------------------------------}

{------------------------------------------------------------------------------}

function RemainingSeconds(const Cost, DoneAt: array of Double; FirstFrame, Done: Integer;
  Fraction, Elapsed: Double; Window: Integer): Double;
var
  Total, Start: Integer;
  StartTime, DoneCost: Double;
begin
  Result := 0;
  Total := High(Cost);
  if (Done < FirstFrame) or (Done > Total) then
    Exit;
  Start := Max(FirstFrame, Done - Window);
  StartTime := 0;
  if Start > FirstFrame then
    StartTime := DoneAt[Start - 1];
  DoneCost := Cost[Done];
  if Done < Total then
    DoneCost := DoneCost + (Cost[Done + 1] - Cost[Done]) * Fraction;
  if DoneCost > Cost[Start] then
    Result := (Elapsed - StartTime) * (Cost[Total] - DoneCost) / (DoneCost - Cost[Start]);
end;

{------------------------------------------------------------------------------}

end.
