unit VideoFrm;

// Fenêtre « Vidéo » : composer un scénario d'étapes (favoris, vue courante), l'enregistrer, en voir un aperçu et
// en tirer une vidéo .mp4 par FFmpeg.

interface

uses
  Windows, Messages, SysUtils, Classes, Math, StrUtils, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, SyncObjs, ShellAPI, {$IF CompilerVersion >= 23} UITypes,{$IFEND}
  pngimage, Fractal.Types, Fractal.Palette, Fractal.Engine, Fractal.Persistence, Fractal.VideoPath,
  Fractal.VideoScenario, Fractal.VideoEncoder, Fractal.VideoRender;

type
  TVideoForm = class(TForm)
    lblSteps: TLabel;
    lvSteps: TListView;
    cbFavorites: TComboBox;
    btnAddFavorite: TButton;
    btnAddView: TButton;
    btnRemove: TButton;
    btnUp: TButton;
    btnDown: TButton;
    gbStep: TGroupBox;
    lblMode: TLabel;
    cbMode: TComboBox;
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
    lblDuration: TLabel;
    lblPreview: TLabel;
    imgPreview: TImage;
    btnPreview: TButton;
    btnRender: TButton;
    btnCancel: TButton;
    pbProgress: TProgressBar;
    lblProgress: TLabel;
    lblFfmpeg: TLabel;
    btnOpen: TButton;
    btnSave: TButton;
    btnClose: TButton;
    tmrProgress: TTimer;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    dlgVideo: TSaveDialog;
    btnReplay: TButton;
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
    procedure btnOpenClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure tmrProgressTimer(Sender: TObject);
    procedure btnReplayClick(Sender: TObject);
    procedure FormActivate(Sender: TObject);
  private
    FScenario: TVideoScenario;
    FFavorites: TFavoriteStore;
    FCurrent: TFractalLocation;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FKernel: TEngineKernelType;
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
    FOnRequestSnapshot: TNotifyEvent;
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
    procedure UpdateControls;
    procedure ShowPreviewFrame;
    procedure FinishRender;
    function SelectedIndex: Integer;
    function IsRendering: Boolean;
  public
    // Copie le lieu courant et la palette ; Favorites reste à l'appelant. Peut être rappelé : garde les sélections
    procedure Prepare(Favorites: TFavoriteStore; CurrentLocation: TFractalLocation; Palette: TGradientPalette;
      const Mapping: TColorMapping; Kernel: TEngineKernelType; const FfmpegExe: string);
    procedure AddCurrentView;
    procedure StartRender(IsPreview: Boolean; const FileName: string; Divisor: Integer = 0);
    function WaitForRender(TimeoutMs: Cardinal): Boolean;  // pour le test de fumée
    property Scenario: TVideoScenario read FScenario;
    property LastError: string read FLastError;
    property PreviewImage: TImage read imgPreview;
    property ReplayButton: TButton read btnReplay;
    // Fenêtre non modale : demande à la fenêtre principale d'appeler Prepare avec son état du moment
    // (activation, « Ajouter la vue », lancement d'un rendu)
    property OnRequestSnapshot: TNotifyEvent read FOnRequestSnapshot write FOnRequestSnapshot;
  end;

implementation

{$R *.dfm}

const
  kSecondsFormat = '0.0';
  kModeNames: array[TVideoMoveMode] of string = ('Survol', 'Latéral');
  kSmoothingNames: array[1..kMaxSmoothing] of string = ('Aucun (rapide)', '2 × 2 (× 4 en temps)',
    '3 × 3 (× 9 en temps)');
  kScenarioFilter = 'Scénarios vidéo (*.fscn)|*.fscn';
  kVideoFilter = 'Vidéos MP4 (*.mp4)|*.mp4';
  kMsgRendering = 'Un rendu est en cours : l''interrompre ?';
  kMsgDone = 'Vidéo enregistrée :'#13#10'%s';
  kMsgFailed = 'La vidéo n''a pas pu être créée :'#13#10'%s';
  kViewName = 'Vue %d';
  kPreviewSuffix = '.apercu.mp4';
  kPreviewTempName = 'Fractales apercu.mp4';
  kStampExtension = '.scenario';  // scénario au moment de l'aperçu : l'aperçu ne vaut que pour lui
  kMsgReplayFailed = 'Impossible d''ouvrir l''aperçu dans le lecteur vidéo de Windows.';

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
  const Mapping: TColorMapping; Kernel: TEngineKernelType; const FfmpegExe: string);
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
          Item.SubItems.Add(kModeNames[S.Mode]);
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
  finally
    FIsUpdating := False;
  end;
  RefreshStep;
  RefreshSummary;
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
      edTravel.Text := '';
      edPause.Text := '';
      lblSpeed.Caption := '';
    end
    else
    begin
      S := FScenario[Index];
      cbMode.ItemIndex := Ord(S.Mode);
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
  Speed: Double;
begin
  lblSpeed.Caption := '';
  if Index <= 0 then
    Exit;
  S := FScenario[Index];
  if S.Mode <> vmLateral then
    Exit;
  Speed := LateralScreensPerSecond(FScenario[Index - 1].Pose, S.Pose, S.TravelSeconds);
  lblSpeed.Caption := Format('Vitesse : %.1f écrans par seconde', [Speed]);
  if Speed > kLateralSpeedWarning then
    lblSpeed.Caption := lblSpeed.Caption + ' : trop rapide, allongez le trajet ou passez en survol';
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.RefreshSummary;
begin
  lblDuration.Caption := Format('Durée : %s '+#13#10+'Nb images : %d ', [ClockText(FScenario.TotalSeconds), FScenario.TotalFrames]);
  UpdateControls;
end;

{------------------------------------------------------------------------------}

// L'aperçu encodé vit à côté du scénario enregistré (il survit à la fermeture), sinon dans le dossier temporaire
function TVideoForm.PreviewFileName: string;
begin
  if FScenarioFile <> '' then
    Result := ChangeFileExt(FScenarioFile, '') + kPreviewSuffix
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
  cbMode.Enabled := IsIdle and (Index > 0);
  edTravel.Enabled := IsIdle and (Index > 0);
  edPause.Enabled := IsIdle and (Index >= 0);
  cbFormat.Enabled := IsIdle;
  cbSmoothing.Enabled := IsIdle;
  btnPreview.Enabled := IsIdle and (FScenario.Count >= 2);
  btnRender.Enabled := IsIdle and (FScenario.Count >= 2) and (FFfmpegExe <> '');
  btnCancel.Enabled := not IsIdle;
  btnOpen.Enabled := IsIdle;
  btnSave.Enabled := IsIdle and (FScenario.Count > 0);
  btnReplay.Enabled := IsIdle and IsPreviewCurrent;
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
    lvSteps.Items[Index].SubItems[0] := IfThen(Index = 0, 'départ', kModeNames[S.Mode]);
    if Index > 0 then
      lvSteps.Items[Index].SubItems[1] := SecondsText(S.TravelSeconds);
    lvSteps.Items[Index].SubItems[2] := SecondsText(S.PauseSeconds);
  finally
    FIsUpdating := False;
  end;
  if Sender = cbMode then
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
var
  Sink: TVideoFrameSink;
begin
  if IsRendering then
    Exit;
  RequestSnapshot;  // palette, coloration et moteur du moment
  FIsPreview := IsPreview;
  FOutputFile := FileName;
  FRenderedText := FScenario.SaveToText;
  FLastError := '';
  Sink := nil;
  if IsPreview then
    Sink := PreviewSink;
  FRenderer := TVideoRenderer.Create(FScenario, FPalette, FMapping, FKernel, FFfmpegExe, FileName, IsPreview, Sink,
    Divisor);
  pbProgress.Max := Max(1, FRenderer.FramesTotal);
  pbProgress.Position := 0;
  lblProgress.Caption := '';
  tmrProgress.Enabled := True;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.FinishRender;
var
  IsSucceeded, IsCancelled: Boolean;
begin
  tmrProgress.Enabled := False;
  ShowPreviewFrame;
  IsSucceeded := FRenderer.IsSucceeded;
  FLastError := FRenderer.ErrorMessage;
  IsCancelled := not IsSucceeded and (FLastError = '');
  FreeAndNil(FRenderer);
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
  else
  begin
    lblProgress.Caption := 'Vidéo enregistrée.';
    MessageDlg(Format(kMsgDone, [FOutputFile]), mtInformation, [mbOK], 0);
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
    FreeAndNil(FRenderer);
    UpdateControls;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.tmrProgressTimer(Sender: TObject);
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
    pbProgress.Max := Max(1, FRenderer.FramesTotal);
    pbProgress.Position := FRenderer.FramesDone;
    lblProgress.Caption := Format('Image %d sur %d, reste environ %s', [FRenderer.FramesDone, FRenderer.FramesTotal,
      ClockText(FRenderer.SecondsLeft)]);
    if FRenderer.FirstFrame > 0 then
      lblProgress.Caption := lblProgress.Caption + Format(' (reprise à l''image %d)', [FRenderer.FirstFrame]);
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
  if dlgVideo.Execute then
    StartRender(False, dlgVideo.FileName);
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnCancelClick(Sender: TObject);
begin
  if FRenderer <> nil then
    FRenderer.Cancel;  // le minuteur constate la fin et remet la fenêtre en état
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnOpenClick(Sender: TObject);
begin
  if not dlgOpen.Execute then
    Exit;
  try
    FScenario.LoadFromFile(dlgOpen.FileName);
    FScenarioFile := dlgOpen.FileName;
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

procedure TVideoForm.btnSaveClick(Sender: TObject);
begin
  if not dlgSave.Execute then
    Exit;
  try
    FScenario.SaveToFile(dlgSave.FileName);
    FScenarioFile := dlgSave.FileName;
  except
    on E: EVideoScenarioError do
      MessageDlg(E.Message, mtWarning, [mbOK], 0);
  end;
  UpdateControls;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

{------------------------------------------------------------------------------}

procedure TVideoForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if not IsRendering then
    Exit;
  // minuteur arrêté pendant la question : il ne doit pas libérer le rendu sous nos pieds
  tmrProgress.Enabled := False;
  CanClose := MessageDlg(kMsgRendering, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if CanClose then
  begin
    FRenderer.Cancel;
    FreeAndNil(FRenderer);  // attend la fin du fil, qui arrête FFmpeg et supprime la vidéo partielle
  end
  else
    tmrProgress.Enabled := True;
end;

end.
