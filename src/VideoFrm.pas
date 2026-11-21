unit VideoFrm;

// Fenêtre « Vidéo » : composer un scénario d'étapes (favoris, vue courante), l'enregistrer, en voir un aperçu et
// en tirer une vidéo .mp4 par FFmpeg.

interface

uses
  Windows, Messages, SysUtils, Classes, Math, StrUtils, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, SyncObjs, ShellAPI, Menus, ActnList,
  pngimage, Fractal.Types, Fractal.Palette, Fractal.Engine, Fractal.Persistence, Fractal.VideoPath,
  Fractal.VideoScenario, Fractal.VideoEncoder, Fractal.VideoRender, Fractal.Settings
  {$IFDEF VER210} // Delphi 2010,
  ;
  {$ELSE}         // Delphi XE2 et plus récent (incluant Delphi 13)
    ,UITypes,System.Actions;
  {$ENDIF}

type
  TVideoStepEvent = procedure(Sender: TObject; Index: Integer) of object;

  TVideoForm = class(TForm)
    lblSteps: TLabel;
    lvSteps: TListView;
    cbFavorites: TComboBox;
    btnAddFavorite: TButton;
    btnAddView: TButton;
    btnRemove: TButton;
    btnUp: TButton;
    btnDown: TButton;
    btnShowStep: TButton;
    btnReplaceStep: TButton;
    gbStep: TGroupBox;
    lblMode: TLabel;
    cbMode: TComboBox;
    cbStop: TCheckBox;
    lblTravel: TLabel;
    edTravel: TEdit;
    lblPause: TLabel;
    edPause: TEdit;
    lblSpeed: TLabel;
    gbVideo: TGroupBox;
    lblFormat: TLabel;
    cbFormat: TComboBox;
    lblSmoothing: TLabel;
    cbSmoothing: TComboBox;
    lblIterLimit: TLabel;
    edIterLimit: TEdit;
    lblIterLimitHint: TLabel;
    lblDuration: TLabel;
    lblPreview: TLabel;
    imgPreview: TImage;
    btnPreview: TButton;
    btnRender: TButton;
    btnCancel: TButton;
    pbProgress: TProgressBar;
    lblProgress: TLabel;
    lblFfmpeg: TLabel;
    tmrProgress: TTimer;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    dlgVideo: TSaveDialog;
    btnReplay: TButton;
    btnSplit: TButton;
    btnResumeParts: TButton;
    gbColors: TGroupBox;
    lblColors: TLabel;
    pbPalette: TPaintBox;
    btnReplaceColors: TButton;
    MainMenu1: TMainMenu;
    ActionList1: TActionList;
    Action_Open: TAction;
    Fichier1: TMenuItem;
    Ouvrir1: TMenuItem;
    Action_SaveAs: TAction;
    Enregistrer1: TMenuItem;
    N1: TMenuItem;
    Action_Close: TAction;
    ActionClose1: TMenuItem;
    Action_Save: TAction;
    Enregistrer2: TMenuItem;
    Action_Reset: TAction;
    Nouveau1: TMenuItem;
    N2: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure lvStepsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnAddFavoriteClick(Sender: TObject);
    procedure btnAddViewClick(Sender: TObject);
    procedure btnRemoveClick(Sender: TObject);
    procedure btnUpClick(Sender: TObject);
    procedure btnDownClick(Sender: TObject);
    procedure StepChange(Sender: TObject);
    procedure VideoSettingsChange(Sender: TObject);
    procedure btnPreviewClick(Sender: TObject);
    procedure btnRenderClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure tmrProgressTimer(Sender: TObject);
    procedure btnReplayClick(Sender: TObject);
    procedure btnReplaceColorsClick(Sender: TObject);
    procedure pbPalettePaint(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure Action_OpenExecute(Sender: TObject);
    procedure Action_SaveAsExecute(Sender: TObject);
    procedure Action_CloseExecute(Sender: TObject);
    procedure Action_SaveExecute(Sender: TObject);
    procedure Action_ResetExecute(Sender: TObject);
    procedure btnShowStepClick(Sender: TObject);
    procedure btnReplaceStepClick(Sender: TObject);
    procedure lvStepsDblClick(Sender: TObject);
    procedure btnSplitClick(Sender: TObject);
    procedure btnResumePartsClick(Sender: TObject);
  private
    FScenario: TVideoScenario;
    FFavorites: TFavoriteStore;
    FCurrent: TFractalLocation;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FKernel: TEngineKernelType;
    FIsBla: Boolean;           // [Video] BLA de Fractales.ini
    FIsAdaptive: Boolean;      // [Video] LissageAdaptatif de Fractales.ini
    FFfmpegExe: string;
    FRenderer: TVideoRenderer;
    FIsPreview: Boolean;
    FOutputFile: string;
    FLastError: string;
    FLock: TCriticalSection;
    FPreviewPng: TMemoryStream;  // dernière image de l'aperçu, déposée par le fil de rendu
    FHasNewPreview: Boolean;
    FIsUpdating: Boolean;
    FScenarioFile: string;   // dernier scénario ouvert ou enregistré ; '' = pas encore de fichier
    FRenderedText: string;   // texte du scénario au lancement du rendu en cours
    FRenderStart: TDateTime;     // lancement du rendu en cours, pour le journal de génération
    FRenderScenarioFile: string; // scénario et format du rendu en cours, pour le journal
    FRenderFormat: TVideoFormat;
    FRangeFirstFrame, FRangeLastFrame: Integer;  // plage d'images du rendu en cours, pour l'affichage et le journal
    FLogError: string;           // journal de génération non écrit : affiché avec l'issue
    FSavedText: string;      // texte du scénario au dernier enregistrement ou à l'ouverture ; sert à IsModified
    FOnRequestSnapshot: TNotifyEvent;
    FOnShowStep: TVideoStepEvent;
    FScenarioFolder: string;  // dossiers retenus séparément ; '' = choix de Windows
    FVideoFolder: string;
    FPreviewFolder: string;   // aperçu d'un scénario sans fichier ; '' = dossier temporaire
    FInterruptedFile: string; // Fractales.ini : rendus lancés et pas terminés ; '' = non suivis
    procedure RequestSnapshot;
    procedure PreviewSink(Png: TStream);
    function PreviewFileName: string;
    function PreviewStampFileName: string;
    function IsPreviewCurrent: Boolean;
    procedure WritePreviewStamp;
    procedure AddLocation(const AName: string; Location: TFractalLocation);
    procedure RefreshList(SelectIndex: Integer);
    procedure RefreshStep;
    procedure RefreshSummary;
    procedure RefreshSpeed(Index: Integer);
    procedure RefreshColors;
    function RenderPalette: TGradientPalette;
    function RenderMapping: TColorMapping;
    procedure FixColors;
    function ModeText(Index: Integer): string;
    procedure UpdateControls;
    procedure ShowPreviewFrame;
    procedure FinishRender;
    procedure LogGeneration;
    function SelectedIndex: Integer;
    function IsRendering: Boolean;
    procedure MarkSaved;
    function ConfirmDiscard: Boolean;
    function ConfirmReplaceParts(IsPreview: Boolean; const FileName: string; Divisor: Integer;
      Palette: TGradientPalette; const Mapping: TColorMapping): Boolean;
    procedure LaunchRender(IsPreview: Boolean; const FileName: string; Divisor: Integer; Palette: TGradientPalette;
      const Mapping: TColorMapping; IsBla, IsAdaptive: Boolean; FirstSegment, LastSegment: Integer);
  public
    // Copie le lieu courant et la palette ; Favorites reste à l'appelant. Peut être rappelé : garde les sélections
    procedure Prepare(Favorites: TFavoriteStore; CurrentLocation: TFractalLocation; Palette: TGradientPalette;
      const Mapping: TColorMapping; Kernel: TEngineKernelType; const FfmpegExe: string;
      IsBla, IsAdaptive: Boolean);
    procedure AddCurrentView;
    // « Remplacer les couleurs par celles de la vue » : palette et effets de la fenêtre principale dans le scénario
    procedure ReplaceColors;
    procedure StartRender(IsPreview: Boolean; const FileName: string; Divisor: Integer = 0);
    // Relance un rendu interrompu avec le scénario, la palette, la coloration et les réglages BLA et lissage gardés
    // dans ses morceaux, pour la plage R.FirstSegment..R.LastSegment. Faux si rien n'est repris ; LastError dit
    // pourquoi quand c'est une différence de tampon (version, noyau, réglages)
    function ResumeRender(const R: TInterruptedRender): Boolean;
    function WaitForRender(TimeoutMs: Cardinal): Boolean;  // pour le test de fumée
    // Vrai si le scénario a des étapes et diffère de son dernier enregistrement (ou de son ouverture)
    function IsModified: Boolean;
    property Scenario: TVideoScenario read FScenario;
    property LastError: string read FLastError;
    property PreviewImage: TImage read imgPreview;
    property ScenarioFolder: string read FScenarioFolder write FScenarioFolder;
    property VideoFolder: string read FVideoFolder write FVideoFolder;
    property PreviewFolder: string read FPreviewFolder write FPreviewFolder;  // pour le test de fumée
    property InterruptedFile: string read FInterruptedFile write FInterruptedFile;
    property ReplayButton: TButton read btnReplay;
    property StopCheckBox: TCheckBox read cbStop;  // pour le test de fumée
    property SpeedLabel: TLabel read lblSpeed;
    property ColorsLabel: TLabel read lblColors;
    procedure SelectStep(Index: Integer);
    // Fenêtre non modale : demande à la fenêtre principale d'appeler Prepare avec son état du moment
    // (activation, « Ajouter la vue », lancement d'un rendu)
    property OnRequestSnapshot: TNotifyEvent read FOnRequestSnapshot write FOnRequestSnapshot;
    // « Voir » : montre l'étape Index dans la fenêtre principale
    property OnShowStep: TVideoStepEvent read FOnShowStep write FOnShowStep;
  end;

// Au démarrage : rendus interrompus encore repris possibles (les autres sont oubliés), proposés à l'utilisateur ;
// vrai s'il en choisit un
function ChooseInterruptedRender(const SettingsFile: string; out Chosen: TInterruptedRender): Boolean;

implementation

uses
  VideoSplitDlg;

{$R *.dfm}

const
  kSecondsFormat = '0.0';
  kModeNames: array[TVideoMoveMode] of string = ('Survol', 'Latéral');
  kPassSuffix = ' ▸';  // étape de passage : la caméra ne s'y arrête pas
  kSmoothingNames: array[1..kMaxSmoothing] of string = ('Aucun (rapide)', '2 × 2 (× 4 en temps)',
    '3 × 3 (× 9 en temps)');
  kScenarioFilter = 'Scénarios vidéo (*.fscn)|*.fscn';
  kVideoFilter = 'Vidéos MP4 (*.mp4)|*.mp4';
  kMsgChainedPassing = 'Enchaîné avec les étapes %d à %d : %s en tout, passage ici vers %s';
  kMsgChainedArriving = 'Enchaîné avec les étapes %d à %d : %s en tout, arrivée ici à %s';
  kMsgSpeed = 'Vitesse : %.1f écrans par seconde';
  kMsgTooFast = ' : trop rapide, allongez le trajet ou passez en survol';
  kMsgResumeOne = 'Un rendu a été interrompu à %d %% : %s.'#13#10#13#10'Le reprendre maintenant ?';
  kMsgResumeMany = 'Ces rendus ont été interrompus. Choisissez celui à reprendre maintenant ; les autres seront ' +
    'proposés au prochain démarrage.';
  kMsgRendering = 'Un rendu est en cours : l''interrompre ?';
  kMsgModified = 'Le scénario a été modifié. Enregistrer les modifications ?';
  kMsgDone = 'Vidéo enregistrée :'#13#10'%s';
  kMsgFailed = 'La vidéo n''a pas pu être créée :'#13#10'%s';
  kViewName = 'Vue %d';
  kPreviewSuffix = '.apercu.mp4';
  kPreviewTempName = 'Fractales apercu.mp4';
  kStampExtension = '.scenario';  // scénario au moment de l'aperçu : l'aperçu ne vaut que pour lui
  kMsgReplayFailed = 'Impossible d''ouvrir l''aperçu dans le lecteur vidéo de Windows.';
  kFORM_CAPTION = 'Vidéo';
  kMsgReplaceParts = 'Ces morceaux viennent d''un autre rendu (%s). Les effacer ?';
  kMsgCannotResume = 'Ces morceaux ne peuvent pas être calculés ici : %s.';
  kMsgSameKernelHint = ' Choisissez dans la fenêtre principale le même moteur de calcul que celui des morceaux.';
  kMsgNotResumable = 'Ce dossier ne contient pas de morceaux reprenables (tampon absent, illisible ou d''une ' +
    'ancienne version).';
  kMsgSplitReady = 'Répartition enregistrée dans :'#13#10'%s'#13#10#13#10'Copiez ce dossier sur chaque machine, puis ' +
    '« Reprendre des morceaux » y calcule sa plage.';
  kMsgRangeDone = 'Plage terminée : images %d à %d.'#13#10'Rapatriez les morceaux, puis « Reprendre des morceaux » ' +
    'sans plage assemble la vidéo.';
  kTitleSplitVideo = 'Vidéo à répartir';
  kStampBlaKey = 'BLA=';
  kStampAdaptiveKey = 'LissageAdaptatif=';
  kStampSizeKey = 'Taille=';

{------------------------------------------------------------------------------}

function SecondsText(Seconds: Double): string;
begin
  Result := FormatFloat(kSecondsFormat, Seconds) + ' s';
end;

{------------------------------------------------------------------------------}

function ClockText(Seconds: Double): string;
var
  Total: Integer;
begin
  Total := Round(Seconds);
  if Total >= 3600 then
    Result := Format('%d:%.2d:%.2d', [Total div 3600, (Total div 60) mod 60, Total mod 60])
  else
    Result := Format('%d:%.2d', [Total div 60, Total mod 60]);
end;

{------------------------------------------------------------------------------}

// Accepte la virgule comme le point, quel que soit le réglage de Windows
function TryParseSeconds(const S: string; out Value: Double): Boolean;
begin
  Value := InvariantToFloat(StringReplace(Trim(S), ',', '.', []), NaN);
  Result := not IsNan(Value) and (Value >= 0) and (Value <= kMaxStepSeconds);
end;

{------------------------------------------------------------------------------}

// Les images de la plage de morceaux FirstSegment..LastSegment (-1 = jusqu'au dernier) d'une vidéo de Total images,
// ramenée aux morceaux de la vidéo comme le fait TVideoRenderer
procedure FrameRange(Total, FirstSegment, LastSegment: Integer; out FirstFrame, LastFrame: Integer);
var
  LastOfVideo, First, Last: Integer;
begin
  LastOfVideo := Max(0, Total - 1) div kSegmentFrames;
  if LastSegment = -1 then
    LastSegment := LastOfVideo;
  First := EnsureRange(FirstSegment, 0, LastOfVideo);
  Last := EnsureRange(LastSegment, First, LastOfVideo);
  FirstFrame := First * kSegmentFrames;
  LastFrame := Min((Last + 1) * kSegmentFrames, Total) - 1;
end;

{------------------------------------------------------------------------------}

// Ce que le tampon des morceaux de OutputFile dit des réglages de la machine qui l'a écrit : BLA, lissage adaptatif
// et largeur des images. Faux si le tampon est absent ou illisible
function ReadStampSettings(const OutputFile: string; out IsBla, IsAdaptive: Boolean; out StampWidth: Integer):
  Boolean;
var
  Lines: TStringList;
  I: Integer;
  Size: string;
begin
  Result := False;
  IsBla := False;
  IsAdaptive := False;
  StampWidth := 0;
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(OutputFile + kPartsSuffix + PathDelim + kStampName, TEncoding.UTF8);
    except
      on E: Exception do
        Exit;
    end;
    for I := 0 to Lines.Count - 1 do  // la dernière ligne de chaque clé : le lieu et le scénario ont les leurs
      if Copy(Lines[I], 1, Length(kStampBlaKey)) = kStampBlaKey then
        IsBla := Copy(Lines[I], Length(kStampBlaKey) + 1, MaxInt) = '1'
      else if Copy(Lines[I], 1, Length(kStampAdaptiveKey)) = kStampAdaptiveKey then
        IsAdaptive := Copy(Lines[I], Length(kStampAdaptiveKey) + 1, MaxInt) = '1'
      else if Copy(Lines[I], 1, Length(kStampSizeKey)) = kStampSizeKey then
      begin
        Size := Copy(Lines[I], Length(kStampSizeKey) + 1, MaxInt);
        StampWidth := StrToIntDef(Copy(Size, 1, Pos('x', Size) - 1), 0);
      end;
    Result := True;
  finally
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.FormCreate(Sender: TObject);
var
  M: TVideoMoveMode;
  F: TVideoFormat;
  I: Integer;
begin
  FScenario := TVideoScenario.Create;
  FCurrent := TFractalLocation.Create;
  FPalette := TGradientPalette.Create;
  FLock := TCriticalSection.Create;
  FPreviewPng := TMemoryStream.Create;
  for M := Low(TVideoMoveMode) to High(TVideoMoveMode) do
    cbMode.Items.Add(kModeNames[M]);
  for F := Low(TVideoFormat) to High(TVideoFormat) do
    cbFormat.Items.Add(VideoFormatName(F));
  for I := 1 to kMaxSmoothing do
    cbSmoothing.Items.Add(kSmoothingNames[I]);
  dlgOpen.Filter := kScenarioFilter;
  dlgSave.Filter := kScenarioFilter;
  dlgSave.DefaultExt := Copy(kScenarioExtension, 2, MaxInt);
  dlgVideo.Filter := kVideoFilter;
  dlgVideo.DefaultExt := 'mp4';
  MarkSaved;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.FormDestroy(Sender: TObject);
begin
  if FRenderer <> nil then
  begin
    FRenderer.Cancel;
    FreeAndNil(FRenderer);  // attend la fin du fil
  end;
  FPreviewPng.Free;
  FLock.Free;
  FPalette.Free;
  FCurrent.Free;
  FScenario.Free;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.Prepare(Favorites: TFavoriteStore; CurrentLocation: TFractalLocation; Palette: TGradientPalette;
  const Mapping: TColorMapping; Kernel: TEngineKernelType; const FfmpegExe: string; IsBla, IsAdaptive: Boolean);
var
  Favorite: string;
begin
  if (Favorites = nil) or (CurrentLocation = nil) or (Palette = nil) then
    raise EArgumentException.Create('TVideoForm.Prepare : paramètre nil');
  FFavorites := Favorites;
  FCurrent.LoadFromText(CurrentLocation.SaveToText);
  FPalette.Assign(Palette);
  FMapping := Mapping;
  FKernel := Kernel;
  FFfmpegExe := FfmpegExe;
  FIsBla := IsBla;
  FIsAdaptive := IsAdaptive;
  Favorite := cbFavorites.Text;
  FFavorites.List(cbFavorites.Items);
  cbFavorites.ItemIndex := cbFavorites.Items.IndexOf(Favorite);
  if (cbFavorites.ItemIndex < 0) and (cbFavorites.Items.Count > 0) then
    cbFavorites.ItemIndex := 0;
  if FFfmpegExe = '' then
    lblFfmpeg.Caption := kFfmpegHelp + ' L''aperçu reste possible.'
  else
    lblFfmpeg.Caption := '';
  RefreshList(SelectedIndex);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RequestSnapshot;
begin
  if Assigned(FOnRequestSnapshot) then
    FOnRequestSnapshot(Self);
end;

{------------------------------------------------------------------------------}

// Retour dans la fenêtre : les favoris ont pu changer entre-temps
procedure TVideoForm.FormActivate(Sender: TObject);
begin
  RequestSnapshot;
end;

{------------------------------------------------------------------------------}

function TVideoForm.SelectedIndex: Integer;
begin
  if lvSteps.Selected = nil then
    Result := -1
  else
    Result := lvSteps.Selected.Index;
end;

{------------------------------------------------------------------------------}

function TVideoForm.IsRendering: Boolean;
begin
  Result := FRenderer <> nil;
end;

{------------------------------------------------------------------------------}

function TVideoForm.IsModified: Boolean;
begin
  Result := (FScenario.Count > 0) and (FScenario.SaveToText <> FSavedText);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.MarkSaved;
begin
  FSavedText := FScenario.SaveToText;
end;

{------------------------------------------------------------------------------}

// Avant de remplacer le scénario : propose d'enregistrer ses modifications ; faux = l'utilisateur renonce
function TVideoForm.ConfirmDiscard: Boolean;
begin
  Result := True;
  if not IsModified then
    Exit;
  case MessageDlg(kMsgModified, mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes:
      begin
        if FScenarioFile <> '' then
          Action_SaveExecute(nil)
        else
          Action_SaveAsExecute(nil);
        Result := not IsModified;  // enregistrement annulé ou en échec : on ne perd rien
      end;
    mrNo:
      Result := True;
  else
    Result := False;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.AddLocation(const AName: string; Location: TFractalLocation);
begin
  try
    FScenario.AddLocation(AName, Location);
  except
    on E: EVideoScenarioError do
    begin
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshList(FScenario.Count - 1);
end;

{------------------------------------------------------------------------------}

// Ouvre la boîte sur son propre dossier, sinon Windows reprend le dernier dossier de l'application ;
// retient le dossier choisi dans Folder
function ExecuteInFolder(Dlg: TOpenDialog; var Folder: string): Boolean;
begin
  if (Folder <> '') and DirectoryExists(Folder) then
  begin
    Dlg.InitialDir := Folder;
    Dlg.FileName := ExtractFileName(Dlg.FileName);  // un chemin complet l'emporterait sur InitialDir
  end;
  Result := Dlg.Execute;
  if Result then
    Folder := ExtractFilePath(Dlg.FileName);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.Action_SaveAsExecute(Sender: TObject);
begin
  // nom de la dernière vidéo (pas FOutputFile : l'aperçu y met un fichier temporaire)
  if (fScenarioFile = '') and (dlgVideo.FileName <> '') then
     dlgSave.Filename := ChangeFileExt( ExtractFileName(dlgVideo.FileName), kScenarioExtension );

  if not ExecuteInFolder(dlgSave, FScenarioFolder) then
    Exit;
  FixColors;
  try
    FScenario.SaveToFile(dlgSave.FileName);
    FScenarioFile := dlgSave.FileName;
    MarkSaved;
  except
    on E: EVideoScenarioError do
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
  end;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.Action_SaveExecute(Sender: TObject);
begin
  if FScenarioFile = '' then
    Exit;
  FixColors;
  try
    FScenario.SaveToFile(FScenarioFile);
    MarkSaved;
  except
    on E: EVideoScenarioError do
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
  end;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.Action_CloseExecute(Sender: TObject);
begin
  Close;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.Action_OpenExecute(Sender: TObject);
begin
  if not ConfirmDiscard then
    Exit;
  if not ExecuteInFolder(dlgOpen, FScenarioFolder) then
    Exit;
  try
    FScenario.LoadFromFile(dlgOpen.FileName);
    FScenarioFile := dlgOpen.FileName;
    MarkSaved;
  except
    on E: EVideoScenarioError do
    begin
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshList(0);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.Action_ResetExecute(Sender: TObject);
begin
  if not ConfirmDiscard then
    Exit;
  FScenarioFile := '';
  FScenario.Clear;
  FScenario.Format := vf16x9;  // valeurs d'un scénario neuf (TVideoScenario.Create)
  FScenario.Smoothing := 1;
  FScenario.IterLimit := 0;
  imgPreview.Picture := nil;
  dlgSave.FileName := '';  // un scénario neuf n'hérite pas des noms du précédent
  dlgVideo.FileName := '';
  MarkSaved;
  RefreshList(0);
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.AddCurrentView;
begin
  RequestSnapshot;
  AddLocation(Format(kViewName, [FScenario.Count + 1]), FCurrent);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RefreshList(SelectIndex: Integer);
var
  I: Integer;
  S: TVideoStep;
  Item: TListItem;
begin
  FIsUpdating := True;
  try
    lvSteps.Items.BeginUpdate;
    try
      lvSteps.Items.Clear;
      for I := 0 to FScenario.Count - 1 do
      begin
        S := FScenario[I];
        Item := lvSteps.Items.Add;
        Item.Caption := S.Name;
        if I = 0 then
        begin
          Item.SubItems.Add('départ');
          Item.SubItems.Add('');
        end
        else
        begin
          Item.SubItems.Add(ModeText(I));
          Item.SubItems.Add(SecondsText(S.TravelSeconds));
        end;
        Item.SubItems.Add(SecondsText(S.PauseSeconds));
      end;
    finally
      lvSteps.Items.EndUpdate;
    end;
    if (SelectIndex >= 0) and (SelectIndex < lvSteps.Items.Count) then
    begin
      lvSteps.Items[SelectIndex].Selected := True;
      lvSteps.Items[SelectIndex].MakeVisible(False);
    end;
    cbFormat.ItemIndex := Ord(FScenario.Format);
    cbSmoothing.ItemIndex := FScenario.Smoothing - 1;
    if FScenario.IterLimit > 0 then
      edIterLimit.Text := IntToStr(FScenario.IterLimit)
    else
      edIterLimit.Text := '';
  finally
    FIsUpdating := False;
  end;
  RefreshStep;
  RefreshSummary;
  RefreshColors;
end;

{------------------------------------------------------------------------------}

// Couleurs de l'aperçu et de la vidéo : celles du scénario, sinon celles de la fenêtre principale
function TVideoForm.RenderPalette: TGradientPalette;
begin
  if FScenario.HasColors then
    Result := FScenario.Palette
  else
    Result := FPalette;
end;

{------------------------------------------------------------------------------}

function TVideoForm.RenderMapping: TColorMapping;
begin
  if FScenario.HasColors then
    Result := FScenario.Mapping
  else
    Result := FMapping;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RefreshColors;
begin
  if FScenario.HasColors then
    lblColors.Caption := Format('Couleurs du scénario : palette « %s »', [FScenario.Palette.Name])
  else
    lblColors.Caption := 'Couleurs de la fenêtre principale ; le scénario les gardera à son enregistrement';
  pbPalette.Invalidate;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.pbPalettePaint(Sender: TObject);
var
  P: TGradientPalette;
  X, W: Integer;
begin
  P := RenderPalette;
  W := Max(1, pbPalette.Width);
  for X := 0 to pbPalette.Width - 1 do
  begin
    pbPalette.Canvas.Pen.Color := TColor(SwapRedBlue(P.ColorAt(X / W)));
    pbPalette.Canvas.MoveTo(X, 0);
    pbPalette.Canvas.LineTo(X, pbPalette.Height);
  end;
end;

{------------------------------------------------------------------------------}

// Premier enregistrement d'un scénario sans couleurs : il garde celles de la fenêtre principale du moment
procedure TVideoForm.FixColors;
begin
  if FScenario.HasColors then
    Exit;
  RequestSnapshot;
  FScenario.SetColors(FPalette, FMapping);
  RefreshColors;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.ReplaceColors;
begin
  RequestSnapshot;  // les couleurs affichées en ce moment dans la fenêtre principale
  FScenario.SetColors(FPalette, FMapping);
  RefreshColors;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnReplaceColorsClick(Sender: TObject);
begin
  ReplaceColors;
end;

{------------------------------------------------------------------------------}

// Mode de l'étape dans la liste, avec la marque des passages
function TVideoForm.ModeText(Index: Integer): string;
begin
  Result := kModeNames[FScenario[Index].Mode];
  if not FScenario.IsStopAt(Index) then
    Result := Result + kPassSuffix;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.SelectStep(Index: Integer);
begin
  if (Index >= 0) and (Index < lvSteps.Items.Count) then
  begin
    lvSteps.Items[Index].Selected := True;
    RefreshStep;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RefreshStep;
var
  Index: Integer;
  S: TVideoStep;
begin
  Index := SelectedIndex;
  FIsUpdating := True;
  try
    if Index < 0 then
    begin
      cbMode.ItemIndex := -1;
      cbStop.Checked := False;
      edTravel.Text := '';
      edPause.Text := '';
      lblSpeed.Caption := '';
    end
    else
    begin
      S := FScenario[Index];
      cbMode.ItemIndex := Ord(S.Mode);
      cbStop.Checked := FScenario.IsStopAt(Index);
      edTravel.Text := FormatFloat(kSecondsFormat, S.TravelSeconds);
      edPause.Text := FormatFloat(kSecondsFormat, S.PauseSeconds);
      RefreshSpeed(Index);
    end;
  finally
    FIsUpdating := False;
  end;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RefreshSpeed(Index: Integer);
var
  S: TVideoStep;
  Speed, Seconds, PassAt, Cruise: Double;
  First, Last: Integer;
begin
  lblSpeed.Caption := '';
  if Index <= 0 then
    Exit;
  S := FScenario[Index];
  FScenario.ChainInfo(Index, First, Last, Seconds, PassAt, Cruise);
  if Last - First > 1 then
  begin
    // une étape d'arrêt termine l'enchaînement : on y arrive à la fin, on n'y passe pas
    if Index = Last then
      lblSpeed.Caption := Format(kMsgChainedArriving, [First + 1, Last + 1, SecondsText(Seconds),
        SecondsText(Seconds)])
    else
      lblSpeed.Caption := Format(kMsgChainedPassing, [First + 1, Last + 1, SecondsText(Seconds),
        FormatFloat(kSecondsFormat, PassAt) + ' s']);
    if (S.Mode = vmLateral) and (Cruise > kLateralSpeedWarning) then
      lblSpeed.Caption := lblSpeed.Caption + #13#10 + Format(kMsgSpeed, [Cruise]) + kMsgTooFast;
    Exit;
  end;
  if S.Mode <> vmLateral then
    Exit;
  Speed := LateralScreensPerSecond(FScenario[Index - 1].Pose, S.Pose, S.TravelSeconds);
  lblSpeed.Caption := Format(kMsgSpeed, [Speed]);
  if Speed > kLateralSpeedWarning then
    lblSpeed.Caption := lblSpeed.Caption + kMsgTooFast;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RefreshSummary;
begin
  lblDuration.Caption := Format('Durée : %s '+#13#10+'Nb images : %d ', [ClockText(FScenario.TotalSeconds), FScenario.TotalFrames]);
  UpdateControls;
end;

{------------------------------------------------------------------------------}

// L'aperçu encodé vit à côté du scénario enregistré (il survit à la fermeture), sinon dans le dossier temporaire
// (ou dans PreviewFolder, pour que le test de fumée ne touche pas à l'aperçu d'un Fractales ouvert)
function TVideoForm.PreviewFileName: string;
begin
  if FScenarioFile <> '' then
    Result := ChangeFileExt(FScenarioFile, '') + kPreviewSuffix
  else if FPreviewFolder <> '' then
    Result := IncludeTrailingPathDelimiter(FPreviewFolder) + kPreviewTempName
  else
    Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + kPreviewTempName;
end;

{------------------------------------------------------------------------------}

function TVideoForm.PreviewStampFileName: string;
begin
  Result := PreviewFileName + kStampExtension;
end;

{------------------------------------------------------------------------------}

function TVideoForm.IsPreviewCurrent: Boolean;
var
  L: TStringList;
begin
  Result := False;
  if (FScenario.Count < 2) or not FileExists(PreviewFileName) or not FileExists(PreviewStampFileName) then
    Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(PreviewStampFileName);
      Result := L.Text = FScenario.SaveToText;
    except
      on E: EStreamError do
        Result := False;
    end;
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.UpdateControls;
var
  Index: Integer;
  IsIdle: Boolean;
begin
  Index := SelectedIndex;
  IsIdle := not IsRendering;
  btnAddFavorite.Enabled := IsIdle and (cbFavorites.ItemIndex >= 0);
  btnAddView.Enabled := IsIdle;
  btnRemove.Enabled := IsIdle and (Index >= 0);
  btnUp.Enabled := IsIdle and (Index > 0);
  btnDown.Enabled := IsIdle and (Index >= 0) and (Index < FScenario.Count - 1);
  btnShowStep.Enabled := (Index >= 0) and Assigned(FOnShowStep);  // pendant un rendu aussi : la vue principale est à part
  btnReplaceStep.Enabled := IsIdle and (Index >= 0);
  cbMode.Enabled := IsIdle and (Index > 0);
  cbStop.Enabled := IsIdle and (Index > 0) and (Index < FScenario.Count - 1) and (FScenario[Index].PauseSeconds <= 0);
  edTravel.Enabled := IsIdle and (Index > 0);
  edPause.Enabled := IsIdle and (Index >= 0);
  cbFormat.Enabled := IsIdle;
  cbSmoothing.Enabled := IsIdle;
  edIterLimit.Enabled := IsIdle;
  btnPreview.Enabled := IsIdle and (FScenario.Count >= 2);
  btnRender.Enabled := IsIdle and (FScenario.Count >= 2) and (FFfmpegExe <> '');
  btnCancel.Enabled := not IsIdle;
  btnReplay.Enabled := IsIdle and IsPreviewCurrent;
  btnSplit.Enabled := IsIdle and (FScenario.Count >= 2);
  btnResumeParts.Enabled := IsIdle and (FFfmpegExe <> '');
  btnReplaceColors.Enabled := IsIdle;

  Action_Open.Enabled := IsIdle;
  Action_SaveAs.Enabled := IsIdle and (FScenario.Count > 0);
  Action_Save.Enabled := Action_SaveAs.Enabled and (FScenarioFile <> '');
  Action_Reset.Enabled := IsIdle;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.lvStepsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not FIsUpdating then
    RefreshStep;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnAddFavoriteClick(Sender: TObject);
var
  L: TFractalLocation;
  Name: string;
begin
  if cbFavorites.ItemIndex < 0 then
    Exit;
  Name := cbFavorites.Items[cbFavorites.ItemIndex];
  L := TFractalLocation.Create;
  try
    try
      FFavorites.Load(Name, L);
    except
      on E: EFractalFileError do
      begin
        MessageDlg(E.Message, mtWarning, [mbOK], 0);
        Exit;
      end;
    end;
    AddLocation(Name, L);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnAddViewClick(Sender: TObject);
begin
  AddCurrentView;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnRemoveClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then
    Exit;
  FScenario.Delete(Index);
  RefreshList(Min(Index, FScenario.Count - 1));
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnUpClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index <= 0 then
    Exit;
  FScenario.Move(Index, Index - 1);
  RefreshList(Index - 1);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnDownClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if (Index < 0) or (Index >= FScenario.Count - 1) then
    Exit;
  FScenario.Move(Index, Index + 1);
  RefreshList(Index + 1);
end;

{------------------------------------------------------------------------------}

// Une valeur illisible n'est pas appliquée : le champ garde ce qu'on y tape, l'étape garde l'ancienne valeur
procedure TVideoForm.lvStepsDblClick(Sender: TObject);
begin
  if btnShowStep.Enabled then
    btnShowStepClick(Sender);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnShowStepClick(Sender: TObject);
begin
  if (SelectedIndex >= 0) and Assigned(FOnShowStep) then
    FOnShowStep(Self, SelectedIndex);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnReplaceStepClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := SelectedIndex;
  if Index < 0 then
    Exit;
  RequestSnapshot;  // la vue affichée en ce moment dans la fenêtre principale
  try
    FScenario.ReplaceLocation(Index, FCurrent);
  except
    on E: EVideoScenarioError do
    begin
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  RefreshList(Index);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.StepChange(Sender: TObject);
var
  Index: Integer;
  S: TVideoStep;
  Value: Double;
begin
  Index := SelectedIndex;
  if FIsUpdating or (Index < 0) then
    Exit;
  S := FScenario[Index];
  if (Sender = cbMode) and (cbMode.ItemIndex >= 0) then
    S.Mode := TVideoMoveMode(cbMode.ItemIndex)
  else if Sender = cbStop then
    S.IsStop := cbStop.Checked
  else if (Sender = edTravel) and TryParseSeconds(edTravel.Text, Value) then
    S.TravelSeconds := Value
  else if (Sender = edPause) and TryParseSeconds(edPause.Text, Value) then
    S.PauseSeconds := Value
  else
    Exit;
  FScenario[Index] := S;
  S := FScenario[Index];
  FIsUpdating := True;
  try
    lvSteps.Items[Index].SubItems[0] := IfThen(Index = 0, 'départ', ModeText(Index));
    if Index > 0 then
      lvSteps.Items[Index].SubItems[1] := SecondsText(S.TravelSeconds);
    lvSteps.Items[Index].SubItems[2] := SecondsText(S.PauseSeconds);
    cbStop.Checked := FScenario.IsStopAt(Index);  // une pause non nulle force l'arrêt
  finally
    FIsUpdating := False;
  end;
  UpdateControls;
  if (Sender = cbMode) or (Sender = cbStop) then
    RefreshStep
  else
    RefreshSpeed(Index);
  RefreshSummary;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.VideoSettingsChange(Sender: TObject);
begin
  if FIsUpdating then
    Exit;
  if cbFormat.ItemIndex >= 0 then
    FScenario.Format := TVideoFormat(cbFormat.ItemIndex);
  if cbSmoothing.ItemIndex >= 0 then
    FScenario.Smoothing := cbSmoothing.ItemIndex + 1;
  if Trim(edIterLimit.Text) = '' then
    FScenario.IterLimit := 0
  else if StrToIntDef(Trim(edIterLimit.Text), -1) >= 0 then  // saisie invalide : on garde la valeur
    FScenario.IterLimit := StrToInt(Trim(edIterLimit.Text));
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.PreviewSink(Png: TStream);
begin
  FLock.Enter;
  try
    FPreviewPng.Size := 0;
    Png.Position := 0;
    FPreviewPng.CopyFrom(Png, Png.Size);
    FHasNewPreview := True;
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.ShowPreviewFrame;
var
  Png: TPngImage;
begin
  Png := TPngImage.Create;
  try
    FLock.Enter;
    try
      if not FHasNewPreview then
        Exit;
      FPreviewPng.Position := 0;
      Png.LoadFromStream(FPreviewPng);
      FHasNewPreview := False;
    finally
      FLock.Leave;
    end;
    imgPreview.Picture.Assign(Png);
  finally
    Png.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.StartRender(IsPreview: Boolean; const FileName: string; Divisor: Integer);
begin
  if IsRendering then
    Exit;
  RequestSnapshot;  // moteur du moment ; palette et coloration de la fenêtre principale si le scénario n'en a pas
  if not ConfirmReplaceParts(IsPreview, FileName, Divisor, RenderPalette, RenderMapping) then
    Exit;
  LaunchRender(IsPreview, FileName, Divisor, RenderPalette, RenderMapping, FIsBla, FIsAdaptive, 0, -1);
end;

{------------------------------------------------------------------------------}

// Un dossier de morceaux d'un autre rendu n'est jamais effacé ici : seule une génération lancée normalement le fait,
// après confirmation. BLA et lissage adaptatif viennent du tampon (comme la palette), pas de Fractales.ini
function TVideoForm.ResumeRender(const R: TInterruptedRender): Boolean;
var
  Read: TVideoScenario;
  L: TFractalLocation;
  Done, StampWidth, Width, Height, Divisor: Integer;
  IsBla, IsAdaptive: Boolean;
  Difference: string;
begin
  Result := False;
  FLastError := '';
  if IsRendering then
    Exit;
  RequestSnapshot;  // moteur et FFmpeg du moment
  Read := TVideoScenario.Create;
  L := TFractalLocation.Create;
  try
    if not ReadInterruptedRender(R.OutputFile, Read, L, Done) or
      not ReadStampSettings(R.OutputFile, IsBla, IsAdaptive, StampWidth) then
      Exit;
    // la taille des images est celle des morceaux : un dossier copié ne dit pas de quelle réduction elle vient
    VideoFormatSize(Read.Format, Width, Height);
    Divisor := R.Divisor;
    if StampWidth > 0 then
      Divisor := Max(1, Round(Width / StampWidth));
    Difference := PartsStampDifference(R.OutputFile, RenderStamp(Read, L.Palette, L.Mapping,
      Max(2, Width div Max(1, Divisor)), Max(2, Height div Max(1, Divisor)), kSegmentFrames, IsBla, IsAdaptive,
      FKernel));
    if Difference <> '' then
    begin
      FLastError := Format(kMsgCannotResume, [Difference]);
      if Pos('noyau', Difference) > 0 then
        FLastError := FLastError + kMsgSameKernelHint;
      Exit;
    end;
    FScenario.Assign(Read);
    FScenarioFile := R.ScenarioFile;
    // comparé au fichier tel qu'il est sur le disque ; sans fichier lisible, le scénario repris compte comme modifié
    FSavedText := '';
    if (FScenarioFile <> '') and FileExists(FScenarioFile) then
    try
      Read.LoadFromFile(FScenarioFile);
      FSavedText := Read.SaveToText;
    except
      on EVideoScenarioError do
        FSavedText := '';
    end;
    if R.IsPreview then
      SysUtils.DeleteFile(R.OutputFile + kStampExtension)
    else
      dlgVideo.FileName := R.OutputFile;
    RefreshList(0);
    LaunchRender(R.IsPreview, R.OutputFile, Divisor, L.Palette, L.Mapping, IsBla, IsAdaptive, R.FirstSegment,
      R.LastSegment);
    Result := True;
  finally
    L.Free;
    Read.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Une génération normale vers une vidéo dont le dossier de morceaux a le tampon d'un autre rendu : les anciens morceaux
// ne servent plus, mais ils ont pu coûter des heures ; on ne les efface qu'avec l'accord de l'utilisateur. Faux = il
// renonce au lancement
function TVideoForm.ConfirmReplaceParts(IsPreview: Boolean; const FileName: string; Divisor: Integer;
  Palette: TGradientPalette; const Mapping: TColorMapping): Boolean;
var
  Width, Height: Integer;
  Difference: string;
begin
  Result := True;
  if FileName = '' then
    Exit;
  VideoFormatSize(FScenario.Format, Width, Height);
  if Divisor <= 0 then
    Divisor := IfThen(IsPreview, kPreviewDivisor, 1);
  Difference := PartsStampDifference(FileName, RenderStamp(FScenario, Palette, Mapping, Max(2, Width div Divisor),
    Max(2, Height div Divisor), kSegmentFrames, FIsBla, FIsAdaptive, FKernel));
  if Difference = '' then
    Exit;
  Result := MessageDlg(Format(kMsgReplaceParts, [Difference]), mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if Result then
    RemovePartsFolder(FileName);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.LaunchRender(IsPreview: Boolean; const FileName: string; Divisor: Integer;
  Palette: TGradientPalette; const Mapping: TColorMapping; IsBla, IsAdaptive: Boolean; FirstSegment,
  LastSegment: Integer);
var
  Sink: TVideoFrameSink;
  R: TInterruptedRender;
begin
  FIsPreview := IsPreview;
  FOutputFile := FileName;
  FRenderedText := FScenario.SaveToText;
  FLastError := '';
  FLogError := '';
  FRenderStart := Now;
  FRenderScenarioFile := FScenarioFile;
  FRenderFormat := FScenario.Format;
  Sink := nil;
  if IsPreview then
    Sink := PreviewSink;
  FRenderer := TVideoRenderer.Create(FScenario, Palette, Mapping, FKernel, FFfmpegExe, FileName, IsPreview, Sink,
    Divisor, 0, IsBla, IsAdaptive, FirstSegment, LastSegment);
  FrameRange(FScenario.TotalFrames, FirstSegment, LastSegment, FRangeFirstFrame, FRangeLastFrame);
  if (FileName <> '') and (FInterruptedFile <> '') then
  begin
    R.OutputFile := FileName;
    R.IsPreview := IsPreview;
    R.Divisor := Divisor;
    R.ScenarioFile := FScenarioFile;
    R.FirstSegment := FirstSegment;
    R.LastSegment := LastSegment;
    AddInterruptedRender(FInterruptedFile, R);  // retiré quand le rendu aboutit
  end;
  pbProgress.Max := Max(1, FRenderer.FramesInRange);
  pbProgress.Position := 0;
  lblProgress.Caption := '';
  tmrProgress.Enabled := True;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.FinishRender;
var
  IsSucceeded, IsCancelled, IsPartial: Boolean;
begin
  tmrProgress.Enabled := False;
  ShowPreviewFrame;
  IsSucceeded := FRenderer.IsSucceeded;
  IsPartial := not FRenderer.IsWholeVideo;
  FLastError := FRenderer.ErrorMessage;
  IsCancelled := not IsSucceeded and (FLastError = '');
  LogGeneration;
  FreeAndNil(FRenderer);
  if IsSucceeded and (FOutputFile <> '') and (FInterruptedFile <> '') then
    RemoveInterruptedRender(FInterruptedFile, FOutputFile);
  UpdateControls;
  if IsCancelled and (FOutputFile <> '') then
    lblProgress.Caption := 'Interrompu : relancer la même vidéo reprendra où elle s''est arrêtée.'
  else if IsCancelled then
    lblProgress.Caption := 'Interrompu.'
  else if not IsSucceeded then
  begin
    lblProgress.Caption := 'Échec.';
    MessageDlg(Format(kMsgFailed, [FLastError]), mtError, [mbOK], 0);
  end
  else if FIsPreview then
  begin
    lblProgress.Caption := 'Aperçu terminé.';
    if FOutputFile <> '' then
    begin
      WritePreviewStamp;
      lblProgress.Caption := 'Aperçu terminé : « Revoir l''aperçu » le rejoue.';
      UpdateControls;
    end;
  end
  else if IsPartial then
  begin
    lblProgress.Caption := 'Plage terminée.';
    MessageDlg(Format(kMsgRangeDone, [FRangeFirstFrame, FRangeLastFrame]), mtInformation, [mbOK], 0);
  end
  else
  begin
    lblProgress.Caption := 'Vidéo enregistrée.';
    MessageDlg(Format(kMsgDone, [FOutputFile]), mtInformation, [mbOK], 0);
  end;
  if FLogError <> '' then
    lblProgress.Caption := lblProgress.Caption + ' Journal non écrit : ' + FLogError;

  Caption := kFORM_CAPTION;

end;

{------------------------------------------------------------------------------}

// Une entrée au journal à côté de la vidéo, quelle que soit l'issue ; rien pour l'aperçu. Appelé avant de libérer le
// rendu terminé. Un journal qui ne s'écrit pas ne doit pas faire perdre la vidéo : l'erreur est seulement retenue
procedure TVideoForm.LogGeneration;
var
  Entry: TGenerationLogEntry;
begin
  if FIsPreview or (FOutputFile = '') or (FRenderer = nil) then
    Exit;
  Entry.StartTime := FRenderStart;
  Entry.EndTime := Now;
  Entry.ScenarioFile := FRenderScenarioFile;
  Entry.VideoFormat := FRenderFormat;
  Entry.FramesTotal := FRenderer.FramesTotal;
  Entry.FramesDone := FRenderer.FramesDone;
  Entry.FirstFrame := FRenderer.FirstFrame;
  Entry.RangeFirstFrame := -1;  // toute la vidéo
  Entry.RangeLastFrame := -1;
  if not FRenderer.IsWholeVideo then
  begin
    Entry.RangeFirstFrame := FRangeFirstFrame;
    Entry.RangeLastFrame := FRangeLastFrame;
  end;
  Entry.ErrorMessage := FRenderer.ErrorMessage;
  if FRenderer.IsSucceeded then
    Entry.Outcome := goSucceeded
  else if Entry.ErrorMessage = '' then
    Entry.Outcome := goCancelled
  else
    Entry.Outcome := goFailed;
  try
    AppendGenerationLog(FOutputFile, Entry);
  except
    on E: Exception do
      FLogError := E.Message;
  end;
end;

{------------------------------------------------------------------------------}

function TVideoForm.WaitForRender(TimeoutMs: Cardinal): Boolean;
var
  Deadline: Cardinal;
begin
  tmrProgress.Enabled := False;  // sinon FinishRender libérerait le rendu et ouvrirait une boîte de message
  Deadline := GetTickCount + TimeoutMs;
  while IsRendering and not FRenderer.IsDone and (GetTickCount < Deadline) do
  begin
    Application.ProcessMessages;
    Sleep(20);
  end;
  Result := not IsRendering or FRenderer.IsDone;
  if IsRendering and FRenderer.IsDone then
  begin
    tmrProgress.Enabled := False;
    ShowPreviewFrame;
    FLastError := FRenderer.ErrorMessage;
    Result := FRenderer.IsSucceeded;
    if Result and FIsPreview and (FOutputFile <> '') then
      WritePreviewStamp;
    LogGeneration;
    FreeAndNil(FRenderer);
    UpdateControls;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.tmrProgressTimer(Sender: TObject);
var
  sStatus : string;
begin
  if FRenderer = nil then
  begin
    tmrProgress.Enabled := False;
    Exit;
  end;

  if FIsPreview then
    ShowPreviewFrame;

  if FRenderer.IsProfiling then
  begin
    pbProgress.Max := Max(1, FRenderer.ProbesTotal);
    pbProgress.Position := FRenderer.ProbesDone;
    lblProgress.Caption := Format('Estimation de la durée : %d %%',
      [FRenderer.ProbesDone * 100 div Max(1, FRenderer.ProbesTotal)]);
  end
  else
  begin
    pbProgress.Max := Max(1, FRenderer.FramesInRange);
    pbProgress.Position := FRenderer.FramesDone;
    lblProgress.Caption := Format('Image %d sur %d, reste environ %s', [FRenderer.FramesDone,
      FRenderer.FramesInRange, ClockText(FRenderer.SecondsLeft)]);
    if not FRenderer.IsWholeVideo then  // une plage : l'image de départ est celle de la plage
      lblProgress.Caption := lblProgress.Caption + Format(' (plage : images %d à %d)', [FRangeFirstFrame,
        FRangeLastFrame])
    else if FRenderer.FirstFrame > 0 then
      lblProgress.Caption := lblProgress.Caption + Format(' (reprise à l''image %d)', [FRenderer.FirstFrame]);

    if FIsPreview then
      sStatus := ' : aperçu en cours'
    else
      sStatus := ' : génération de ' + ExtractFileName(FOutputFile);

    Caption := kFORM_CAPTION + sStatus +  Format(' (%d %%)', [FRenderer.FramesDone * 100 div Max(1, FRenderer.FramesInRange)]);
  end;

  if FRenderer.IsDone then
    FinishRender;
end;

{------------------------------------------------------------------------------}

// Avec FFmpeg, l'aperçu est aussi encodé, pour être revu sans être recalculé
procedure TVideoForm.btnPreviewClick(Sender: TObject);
begin
  if FFfmpegExe = '' then
    StartRender(True, '')
  else
  begin
    SysUtils.DeleteFile(PreviewStampFileName);
    StartRender(True, PreviewFileName);
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.WritePreviewStamp;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := FRenderedText;
    L.SaveToFile(PreviewStampFileName, TEncoding.UTF8);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnReplayClick(Sender: TObject);
begin
  if ShellExecute(Handle, 'open', PChar(PreviewFileName), nil, nil, SW_SHOWNORMAL) <= 32 then
    MessageDlg(kMsgReplayFailed, mtWarning, [mbOK], 0);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnRenderClick(Sender: TObject);
begin
  if fScenarioFile <> '' then
    dlgVideo.FileName := ChangeFileExt(ExtractFileName(fScenarioFile), '.mp4');

  if ExecuteInFolder(dlgVideo, FVideoFolder) then
    StartRender(False, dlgVideo.FileName);
end;

{------------------------------------------------------------------------------}

// « Répartir… » : la vidéo se choisit comme pour « Créer la vidéo », puis la fenêtre de répartition prend le relais
procedure TVideoForm.btnSplitClick(Sender: TObject);
begin
  if IsRendering or (FScenario.Count < 2) then
    Exit;
  if FScenarioFile <> '' then
    dlgVideo.FileName := ChangeFileExt(ExtractFileName(FScenarioFile), '.mp4');
  dlgVideo.Title := kTitleSplitVideo;
  try
    if not ExecuteInFolder(dlgVideo, FVideoFolder) then
      Exit;
  finally
    dlgVideo.Title := '';
  end;
  RequestSnapshot;  // moteur du moment ; couleurs de la fenêtre principale si le scénario n'en a pas
  if ShowSplitDialog(FScenario, RenderPalette, RenderMapping, FKernel, FIsBla, FIsAdaptive, FFfmpegExe,
    dlgVideo.FileName) then
    MessageDlg(Format(kMsgSplitReady, [dlgVideo.FileName + kPartsSuffix]), mtInformation, [mbOK], 0);
end;

{------------------------------------------------------------------------------}

// « Reprendre des morceaux… » : le scénario de la fenêtre est remplacé par celui du dossier choisi
procedure TVideoForm.btnResumePartsClick(Sender: TObject);
var
  Folder: string;
  First, Last: Integer;
  R: TInterruptedRender;
begin
  if IsRendering or not ConfirmDiscard then
    Exit;
  if not ShowResumePartsDialog(Folder, First, Last) then
    Exit;
  R.OutputFile := Copy(Folder, 1, Length(Folder) - Length(kPartsSuffix));  // la vidéo : le dossier sans .morceaux
  R.IsPreview := False;
  R.Divisor := 0;  // relu de la taille du tampon
  R.ScenarioFile := '';  // un dossier copié n'a pas son .fscn : scénario non enregistré
  R.FirstSegment := First;
  R.LastSegment := Last;
  if not ResumeRender(R) then
    MessageDlg(IfThen(FLastError <> '', FLastError, kMsgNotResumable), mtWarning, [mbOK], 0);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnCancelClick(Sender: TObject);
begin
  if FRenderer <> nil then
    FRenderer.Cancel;  // le minuteur constate la fin et remet la fenêtre en état
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  // la fenêtre fermée seule est gardée avec son scénario : la question ne vient qu'à la sortie du programme
  if Sender <> Self then
    CanClose := ConfirmDiscard;
  if not CanClose or not IsRendering then
    Exit;
  // minuteur arrêté pendant la question : il ne doit pas libérer le rendu sous nos pieds
  tmrProgress.Enabled := False;
  CanClose := MessageDlg(kMsgRendering, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if CanClose then
  begin
    FRenderer.Cancel;
    FRenderer.WaitFor;  // le fil arrête FFmpeg et supprime la vidéo partielle
    LogGeneration;
    FreeAndNil(FRenderer);
  end
  else
    tmrProgress.Enabled := True;
end;

{------------------------------------------------------------------------------}

// Total : nombre d'images de la vidéo, pour dire la plage d'un rendu partiel
function InterruptedRenderName(const R: TInterruptedRender; Total: Integer): string;
var
  First, Last: Integer;
begin
  if not R.IsPreview then
    Result := 'vidéo ' + ExtractFileName(R.OutputFile)
  else if R.ScenarioFile <> '' then
    Result := 'aperçu de ' + ChangeFileExt(ExtractFileName(R.ScenarioFile), '')
  else
    Result := 'aperçu d''un scénario sans nom';
  FrameRange(Total, R.FirstSegment, R.LastSegment, First, Last);
  if (First > 0) or (Last < Total - 1) then
    Result := Result + Format(' (plage : images %d à %d)', [First, Last]);
end;

{------------------------------------------------------------------------------}

// Liste à choix ; -1 = plus tard
function PickFromList(Items: TStrings): Integer;
var
  Dlg: TForm;
  Prompt: TLabel;
  List: TListBox;
  Ok, Later: TButton;
begin
  Dlg := TForm.Create(nil);
  try
    Dlg.Caption := 'Rendus interrompus';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.Font.Name := 'Segoe UI';
    Dlg.Font.Size := 9;
    Dlg.ClientWidth := 480;
    Dlg.ClientHeight := 260;
    Prompt := TLabel.Create(Dlg);
    Prompt.Parent := Dlg;
    Prompt.SetBounds(12, 12, 456, 36);
    Prompt.AutoSize := False;
    Prompt.WordWrap := True;
    Prompt.Caption := kMsgResumeMany;
    List := TListBox.Create(Dlg);
    List.Parent := Dlg;
    List.SetBounds(12, 52, 456, 160);
    List.Items.Assign(Items);
    List.ItemIndex := 0;
    Ok := TButton.Create(Dlg);
    Ok.Parent := Dlg;
    Ok.SetBounds(292, 222, 85, 27);
    Ok.Caption := 'Reprendre';
    Ok.Default := True;
    Ok.ModalResult := mrOk;
    Later := TButton.Create(Dlg);
    Later.Parent := Dlg;
    Later.SetBounds(383, 222, 85, 27);
    Later.Caption := 'Plus tard';
    Later.Cancel := True;
    Later.ModalResult := mrCancel;
    if Dlg.ShowModal = mrOk then
      Result := List.ItemIndex
    else
      Result := -1;
  finally
    Dlg.Free;
  end;
end;

{------------------------------------------------------------------------------}

function ChooseInterruptedRender(const SettingsFile: string; out Chosen: TInterruptedRender): Boolean;
var
  Renders, Kept: TInterruptedRenders;
  Percents: array of Integer;
  Names: array of string;
  Items: TStringList;
  Read: TVideoScenario;
  L: TFractalLocation;
  I, N, Done, Index: Integer;
begin
  Result := False;
  Renders := LoadInterruptedRenders(SettingsFile);
  SetLength(Kept, 0);
  Read := TVideoScenario.Create;
  L := TFractalLocation.Create;
  try
    for I := 0 to High(Renders) do
      if ReadInterruptedRender(Renders[I].OutputFile, Read, L, Done) then
      begin
        N := Length(Kept);
        SetLength(Kept, N + 1);
        SetLength(Percents, N + 1);
        SetLength(Names, N + 1);
        Kept[N] := Renders[I];
        Percents[N] := Done * 100 div Max(1, Read.TotalFrames);
        Names[N] := InterruptedRenderName(Renders[I], Read.TotalFrames);
      end
      else
        RemoveInterruptedRender(SettingsFile, Renders[I].OutputFile);  // morceaux effacés ou illisibles
  finally
    L.Free;
    Read.Free;
  end;
  if Length(Kept) = 0 then
    Exit;
  if Length(Kept) = 1 then
  begin
    if MessageDlg(Format(kMsgResumeOne, [Percents[0], Names[0]]), mtConfirmation,
      [mbYes, mbNo], 0) <> mrYes then
      Exit;
    Index := 0;
  end
  else
  begin
    Items := TStringList.Create;
    try
      for I := 0 to High(Kept) do
        Items.Add(Format('%d %% : %s', [Percents[I], Names[I]]));
      Index := PickFromList(Items);
    finally
      Items.Free;
    end;
    if Index < 0 then
      Exit;
  end;
  Chosen := Kept[Index];
  Result := True;
end;

end.
