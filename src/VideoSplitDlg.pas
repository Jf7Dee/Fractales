unit VideoSplitDlg;

// Fenêtres de la répartition d'une vidéo entre plusieurs machines : « Répartir » (profil de coût, plages par machine,
// dossier des morceaux préparé) et « Reprendre des morceaux » (choix du dossier copié, puis de la plage à calculer).
// Fenêtres construites en code, comme la liste des rendus interrompus de VideoFrm.

interface

uses
  Windows, SysUtils, Classes, Math, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Types,
  Fractal.Types, Fractal.Palette, Fractal.Engine, Fractal.VideoScenario, Fractal.VideoRender, Fractal.VideoSplit
  {$IFDEF VER210} // Delphi 2010,
  ;
  {$ELSE}         // Delphi XE2 et plus récent (incluant Delphi 13)
    ,UITypes;
  {$ENDIF}

// Calcule le profil de coût de la vidéo (progression et bouton Annuler), montre les plages proposées par machine, et
// à la validation crée le dossier des morceaux de OutputFile avec son tampon et repartition.txt. Aucune image n'est
// calculée. Faux si l'utilisateur annule, si le profil échoue, ou si le dossier existe avec le tampon d'un autre rendu
function ShowSplitDialog(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Kernel: TEngineKernelType; IsBla, IsAdaptive: Boolean; const FfmpegExe, OutputFile: string): Boolean;

// Choisit le dossier des morceaux (*.morceaux, par son scenario.txt), puis la plage à calculer : une machine de
// repartition.txt s'il existe, une plage d'images saisie, ou toute la vidéo (LastSegment = -1 : jusqu'au dernier).
// Folder sans séparateur final. Faux si l'utilisateur renonce
function ShowResumePartsDialog(out Folder: string; out FirstSegment, LastSegment: Integer): Boolean;

implementation

const
  kMaxMachines = 8;
  kDefaultMachines = 3;
  kMsgTooShort = 'La vidéo est trop courte pour être répartie : il faut au moins deux morceaux de %d images.';
  kMsgProfileFailed = 'Le profil de coût n''a pas pu être calculé :'#13#10'%s';
  kMsgOtherRender = 'Ces morceaux viennent d''un autre rendu (%s) : %s'#13#10#13#10'Rien n''est modifié. ' +
    'Choisissez une autre vidéo, ou effacez ce dossier.';
  kMsgNoStamp = 'Ce dossier contient des morceaux sans tampon (%s) : ils viennent peut-être d''un autre rendu.';
  kMsgSplitFailed = 'La répartition n''a pas pu être enregistrée :'#13#10'%s';
  kMsgNotParts = 'Ce n''est pas un dossier de morceaux : son nom doit se terminer par %s.';
  kMsgBadSplitFile = '%s est illisible (%s) : une plage est à saisir.';
  kMsgBadRange = 'La plage est invalide : la première image doit être un nombre, la dernière un nombre au moins égal ' +
    '(ou vide pour aller jusqu''à la fin).';
  kFontName = 'Segoe UI';
  kFontSize = 9;
  kProfileTimerMs = 200;

{------------------------------------------------------------------------------}

// Heures:minutes, comme l'estimation d'une plage de plusieurs heures
function HoursText(Seconds: Double): string;
var
  Minutes: Int64;
begin
  Minutes := Round(Seconds / 60);
  Result := Format('%d:%.2d', [Minutes div 60, Minutes mod 60]);
end;

{------------------------------------------------------------------------------}

procedure SetupDialog(Dlg: TForm; const ACaption: string; AWidth, AHeight: Integer);
begin
  Dlg.Caption := ACaption;
  Dlg.BorderStyle := bsDialog;
  Dlg.Position := poMainFormCenter;
  Dlg.Font.Name := kFontName;
  Dlg.Font.Size := kFontSize;
  Dlg.ClientWidth := AWidth;
  Dlg.ClientHeight := AHeight;
end;

{------------------------------------------------------------------------------}

function NewLabel(Dlg: TForm; X, Y, W, H: Integer; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Dlg);
  Result.Parent := Dlg;
  Result.SetBounds(X, Y, W, H);
  Result.AutoSize := False;
  Result.Caption := ACaption;
end;

{------------------------------------------------------------------------------}

function NewEdit(Dlg: TForm; X, Y, W: Integer; const AText: string): TEdit;
begin
  Result := TEdit.Create(Dlg);
  Result.Parent := Dlg;
  Result.SetBounds(X, Y, W, 23);
  Result.Text := AText;
end;

{------------------------------------------------------------------------------}

function NewButton(Dlg: TForm; X, Y, W: Integer; const ACaption: string; AResult: TModalResult): TButton;
begin
  Result := TButton.Create(Dlg);
  Result.Parent := Dlg;
  Result.SetBounds(X, Y, W, 27);
  Result.Caption := ACaption;
  Result.ModalResult := AResult;
end;

{------------------------------------------------------------------------------}

type
  // Attente du profil de coût : une fenêtre avec une barre de progression, et Annuler
  TProfileWaiter = class
  private
    FRenderer: TVideoRenderer;
    FDialog: TForm;
    FBar: TProgressBar;
    FStatus: TLabel;
    procedure Tick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    // Faux si annulé ou en échec ; ErrorText vide = annulé
    function Run(Renderer: TVideoRenderer; out ErrorText: string): Boolean;
  end;

{------------------------------------------------------------------------------}

procedure TProfileWaiter.Tick(Sender: TObject);
begin
  FBar.Max := Max(1, FRenderer.ProbesTotal);
  FBar.Position := FRenderer.ProbesDone;
  FStatus.Caption := Format('Estimation de la durée : %d %%', [FRenderer.ProbesDone * 100 div Max(1,
    FRenderer.ProbesTotal)]);
  if FRenderer.IsDone then
    FDialog.ModalResult := mrOk;
end;

{------------------------------------------------------------------------------}

procedure TProfileWaiter.CancelClick(Sender: TObject);
begin
  FRenderer.Cancel;  // le fil s'arrête, et le minuteur ferme la fenêtre
end;

{------------------------------------------------------------------------------}

function TProfileWaiter.Run(Renderer: TVideoRenderer; out ErrorText: string): Boolean;
var
  Timer: TTimer;
  Cancel: TButton;
begin
  if Renderer = nil then
    raise EArgumentException.Create('TProfileWaiter.Run : rendu nil');
  ErrorText := '';
  FRenderer := Renderer;
  FDialog := TForm.Create(nil);
  try
    SetupDialog(FDialog, 'Répartir : estimation du coût', 420, 110);
    FStatus := NewLabel(FDialog, 12, 12, 396, 18, 'Estimation de la durée : 0 %');
    FBar := TProgressBar.Create(FDialog);
    FBar.Parent := FDialog;
    FBar.SetBounds(12, 36, 396, 18);
    Cancel := NewButton(FDialog, 323, 70, 85, 'Annuler', mrNone);
    Cancel.Cancel := True;
    Cancel.OnClick := CancelClick;
    Timer := TTimer.Create(FDialog);
    Timer.Interval := kProfileTimerMs;
    Timer.OnTimer := Tick;
    FDialog.ShowModal;
  finally
    FDialog.Free;
  end;
  // fenêtre fermée par la croix avant la fin du fil : on l'arrête
  if not Renderer.IsDone then
    Renderer.Cancel;
  Renderer.WaitFor;
  Result := Renderer.IsSucceeded;
  if not Result then
    ErrorText := Renderer.ErrorMessage;
end;

{------------------------------------------------------------------------------}

type
  TMachineRow = record
    NameEdit, SpeedEdit, FirstEdit: TEdit;
    LastLabel, TimeLabel: TLabel;
  end;

  // La fenêtre des machines : nombre, nom, vitesse, plage (en images) et temps estimé de chacune
  TSplitDialog = class
  private
    FCost: TDoubleDynArray;
    FFramesTotal: Integer;
    FSegmentCount: Integer;
    FSmoothing: Integer;
    FDialog: TForm;
    FCount: TComboBox;
    FRows: array[0..kMaxMachines - 1] of TMachineRow;
    FSpeeds: array[0..kMaxMachines - 1] of Double;
    FSummary: TLabel;
    FMachines: TSplitMachines;
    FIsUpdating: Boolean;
    FOutputFile: string;
    FStampText: string;
    function MachineCount: Integer;
    procedure Repropose;
    procedure RefreshRows;
    procedure CountChange(Sender: TObject);
    procedure SpeedExit(Sender: TObject);
    procedure FirstExit(Sender: TObject);
    procedure OkClick(Sender: TObject);
    function PrepareFolder: Boolean;
  public
    function Run(Scenario: TVideoScenario; const Cost: TDoubleDynArray; const OutputFile, StampText: string):
      Boolean;
  end;

{------------------------------------------------------------------------------}

function TSplitDialog.MachineCount: Integer;
begin
  Result := StrToIntDef(FCount.Text, kDefaultMachines);
end;

{------------------------------------------------------------------------------}

// Nouvelles plages d'après le nombre de machines et leurs vitesses
procedure TSplitDialog.Repropose;
var
  Speeds: array of Double;
  I: Integer;
begin
  SetLength(Speeds, MachineCount);
  for I := 0 to High(Speeds) do
    Speeds[I] := FSpeeds[I];
  FMachines := ProposeSplit(FCost, kSegmentFrames, Speeds);
  RefreshRows;
end;

{------------------------------------------------------------------------------}

procedure TSplitDialog.RefreshRows;
var
  I, N: Integer;
  Longest, Seconds: Double;
begin
  N := Length(FMachines);
  Longest := 0;
  FIsUpdating := True;
  try
    for I := 0 to kMaxMachines - 1 do
    begin
      FRows[I].NameEdit.Visible := I < N;
      FRows[I].SpeedEdit.Visible := I < N;
      FRows[I].FirstEdit.Visible := I < N;
      FRows[I].LastLabel.Visible := I < N;
      FRows[I].TimeLabel.Visible := I < N;
      if I >= N then
        Continue;
      FRows[I].SpeedEdit.Text := FloatToInvariant(FSpeeds[I]);
      FRows[I].FirstEdit.Text := IntToStr(FMachines[I].FirstSegment * kSegmentFrames);
      FRows[I].FirstEdit.Enabled := I > 0;  // la première plage commence à l'image 0
      FRows[I].LastLabel.Caption := IntToStr(Min((FMachines[I].LastSegment + 1) * kSegmentFrames, FFramesTotal) - 1);
      Seconds := SplitSeconds(FCost, kSegmentFrames, FMachines[I].FirstSegment, FMachines[I].LastSegment,
        FSpeeds[I], FSmoothing);
      FRows[I].TimeLabel.Caption := HoursText(Seconds);
      Longest := Max(Longest, Seconds);
    end;
  finally
    FIsUpdating := False;
  end;
  FSummary.Caption := Format('Vidéo : %d images en %d morceaux de %d. Temps estimé le plus long : %s (h:mm, prudent).',
    [FFramesTotal, FSegmentCount, kSegmentFrames, HoursText(Longest)]);
end;

{------------------------------------------------------------------------------}

procedure TSplitDialog.CountChange(Sender: TObject);
begin
  if not FIsUpdating then
    Repropose;
end;

{------------------------------------------------------------------------------}

// Une vitesse modifiée redistribue toutes les plages ; une vitesse illisible est remise à sa valeur
procedure TSplitDialog.SpeedExit(Sender: TObject);
var
  Row: Integer;
  Value: Double;
begin
  Row := TComponent(Sender).Tag;
  if Row >= Length(FMachines) then
    Exit;
  Value := InvariantToFloat(StringReplace(Trim(TEdit(Sender).Text), ',', '.', []), NaN);
  if IsNan(Value) or (Value <= 0) or (SameValue(Value, FSpeeds[Row])) then
  begin
    RefreshRows;
    Exit;
  end;
  FSpeeds[Row] := Value;
  Repropose;
end;

{------------------------------------------------------------------------------}

// Une première image modifiée déplace la limite avec la plage précédente, arrondie au morceau le plus proche ; une
// limite qui viderait une plage est refusée
procedure TSplitDialog.FirstExit(Sender: TObject);
var
  Row, Frame: Integer;
begin
  Row := TComponent(Sender).Tag;
  Frame := StrToIntDef(Trim(TEdit(Sender).Text), -1);
  if (Row > 0) and (Row < Length(FMachines)) and (Frame >= 0) then
    MoveSplitBoundary(FMachines, Row, Round(Frame / kSegmentFrames));
  RefreshRows;
end;

{------------------------------------------------------------------------------}

// Le dossier des morceaux avec son tampon, sauf s'il porte déjà celui de ce rendu ; refus si c'est celui d'un autre
function TSplitDialog.PrepareFolder: Boolean;
var
  Folder, Difference: string;
  Stamp: TStringList;
  Found: TSearchRec;
  HasParts: Boolean;
begin
  Result := False;
  Folder := FOutputFile + kPartsSuffix + PathDelim;
  Difference := PartsStampDifference(FOutputFile, FStampText);
  if Difference <> '' then
  begin
    MessageDlg(Format(kMsgOtherRender, [Difference, Folder]), mtWarning, [mbOK], 0);
    Exit;
  end;
  if not FileExists(Folder + kStampName) then
  begin
    HasParts := False;
    if FindFirst(Folder + 'morceau*.mp4', faAnyFile and not faDirectory, Found) = 0 then
    begin
      HasParts := True;
      SysUtils.FindClose(Found);
    end;
    if HasParts then
    begin
      MessageDlg(Format(kMsgNoStamp, [Folder]), mtWarning, [mbOK], 0);
      Exit;
    end;
    if not ForceDirectories(Folder) then
      raise EInOutError.CreateFmt('dossier impossible à créer : %s', [Folder]);
    Stamp := TStringList.Create;
    try
      Stamp.Text := FStampText;
      Stamp.SaveToFile(Folder + kStampName, TEncoding.UTF8);
    finally
      Stamp.Free;
    end;
  end;
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TSplitDialog.OkClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to High(FMachines) do
  begin
    FMachines[I].Name := Trim(FRows[I].NameEdit.Text);
    if FMachines[I].Name = '' then
      FMachines[I].Name := Format('Machine %d', [I + 1]);
    FMachines[I].Speed := FSpeeds[I];
  end;
  try
    if not PrepareFolder then
      Exit;
    SaveSplitFile(FOutputFile + kPartsSuffix + PathDelim + kSplitFileName, FMachines, kSegmentFrames, FFramesTotal);
  except
    on E: Exception do
    begin
      MessageDlg(Format(kMsgSplitFailed, [E.Message]), mtError, [mbOK], 0);
      Exit;
    end;
  end;
  FDialog.ModalResult := mrOk;
end;

{------------------------------------------------------------------------------}

function TSplitDialog.Run(Scenario: TVideoScenario; const Cost: TDoubleDynArray; const OutputFile, StampText: string):
  Boolean;
var
  I, MaxCount: Integer;
  Ok, Cancel: TButton;
begin
  FCost := Cost;
  FOutputFile := OutputFile;
  FStampText := StampText;
  FFramesTotal := Scenario.TotalFrames;
  FSegmentCount := (FFramesTotal - 1) div kSegmentFrames + 1;
  FSmoothing := Scenario.Smoothing;
  MaxCount := Min(kMaxMachines, FSegmentCount);
  for I := 0 to kMaxMachines - 1 do
    FSpeeds[I] := 1;
  FDialog := TForm.Create(nil);
  try
    SetupDialog(FDialog, 'Répartir la vidéo entre des machines', 560, 432);
    NewLabel(FDialog, 12, 15, 150, 18, 'Nombre de machines');
    FCount := TComboBox.Create(FDialog);
    FCount.Parent := FDialog;
    FCount.SetBounds(160, 12, 60, 23);
    FCount.Style := csDropDownList;
    for I := 2 to MaxCount do
      FCount.Items.Add(IntToStr(I));
    FCount.ItemIndex := Min(kDefaultMachines, MaxCount) - 2;
    FCount.OnChange := CountChange;
    NewLabel(FDialog, 12, 50, 150, 18, 'Nom');
    NewLabel(FDialog, 172, 50, 60, 18, 'Vitesse');
    NewLabel(FDialog, 242, 50, 90, 18, 'Première image');
    NewLabel(FDialog, 342, 50, 90, 18, 'Dernière image');
    NewLabel(FDialog, 442, 50, 100, 18, 'Temps estimé');
    for I := 0 to kMaxMachines - 1 do
    begin
      FRows[I].NameEdit := NewEdit(FDialog, 12, 72 + I * 30, 150, Format('Machine %d', [I + 1]));
      FRows[I].SpeedEdit := NewEdit(FDialog, 172, 72 + I * 30, 60, '1');
      FRows[I].SpeedEdit.Tag := I;
      FRows[I].SpeedEdit.OnExit := SpeedExit;
      FRows[I].FirstEdit := NewEdit(FDialog, 242, 72 + I * 30, 90, '0');
      FRows[I].FirstEdit.Tag := I;
      FRows[I].FirstEdit.OnExit := FirstExit;
      FRows[I].LastLabel := NewLabel(FDialog, 342, 76 + I * 30, 90, 18, '');
      FRows[I].TimeLabel := NewLabel(FDialog, 442, 76 + I * 30, 100, 18, '');
    end;
    FSummary := NewLabel(FDialog, 12, 318, 536, 36, '');
    FSummary.WordWrap := True;
    NewLabel(FDialog, 12, 358, 536, 36, 'Les plages sont en morceaux entiers de ' + IntToStr(kSegmentFrames) +
      ' images. OK crée le dossier des morceaux et son repartition.txt ; aucune image n''est calculée ici.').WordWrap
      := True;
    Ok := NewButton(FDialog, 383, 398, 80, 'OK', mrNone);
    Ok.OnClick := OkClick;
    Cancel := NewButton(FDialog, 469, 398, 80, 'Annuler', mrCancel);
    Cancel.Cancel := True;
    Repropose;
    Result := FDialog.ShowModal = mrOk;
  finally
    FDialog.Free;
  end;
end;

{------------------------------------------------------------------------------}

function ShowSplitDialog(Scenario: TVideoScenario; Palette: TGradientPalette; const Mapping: TColorMapping;
  Kernel: TEngineKernelType; IsBla, IsAdaptive: Boolean; const FfmpegExe, OutputFile: string): Boolean;
var
  Renderer: TVideoRenderer;
  Waiter: TProfileWaiter;
  Dialog: TSplitDialog;
  Cost: TDoubleDynArray;
  ErrorText, StampText: string;
  Width, Height: Integer;
begin
  Result := False;
  if (Scenario = nil) or (Palette = nil) then
    raise EArgumentException.Create('ShowSplitDialog : scénario ou palette nil');
  if (OutputFile = '') or (Scenario.TotalFrames <= kSegmentFrames) then
  begin
    MessageDlg(Format(kMsgTooShort, [kSegmentFrames]), mtWarning, [mbOK], 0);
    Exit;
  end;
  Renderer := TVideoRenderer.Create(Scenario, Palette, Mapping, Kernel, FfmpegExe, '', False, nil, 0, 0, IsBla,
    IsAdaptive, 0, -1, True);
  try
    Waiter := TProfileWaiter.Create;
    try
      if not Waiter.Run(Renderer, ErrorText) then
      begin
        if ErrorText <> '' then
          MessageDlg(Format(kMsgProfileFailed, [ErrorText]), mtError, [mbOK], 0);
        Exit;
      end;
    finally
      Waiter.Free;
    end;
    Cost := Renderer.Cost;
  finally
    Renderer.Free;
  end;
  VideoFormatSize(Scenario.Format, Width, Height);  // vidéo entière : pas de réduction
  StampText := RenderStamp(Scenario, Palette, Mapping, Width, Height, kSegmentFrames, IsBla, IsAdaptive, Kernel);
  Dialog := TSplitDialog.Create;
  try
    Result := Dialog.Run(Scenario, Cost, OutputFile, StampText);
  finally
    Dialog.Free;
  end;
end;

{------------------------------------------------------------------------------}

type
  // Le choix de la plage à calculer dans un dossier de morceaux
  TResumeDialog = class
  private
    FDialog: TForm;
    FMachines: TSplitMachines;
    FByMachine, FByRange, FWhole: TRadioButton;
    FMachineList: TComboBox;
    FFirstEdit, FLastEdit: TEdit;
    FFirst, FLast: Integer;
    procedure ModeChange(Sender: TObject);
    procedure OkClick(Sender: TObject);
  public
    function Run(const Machines: TSplitMachines; out FirstSegment, LastSegment: Integer): Boolean;
  end;

{------------------------------------------------------------------------------}

procedure TResumeDialog.ModeChange(Sender: TObject);
begin
  FMachineList.Enabled := FByMachine.Checked;
  FFirstEdit.Enabled := FByRange.Checked;
  FLastEdit.Enabled := FByRange.Checked;
end;

{------------------------------------------------------------------------------}

procedure TResumeDialog.OkClick(Sender: TObject);
var
  First, Last: Integer;
begin
  if FByMachine.Checked then
  begin
    if FMachineList.ItemIndex < 0 then
      Exit;
    FFirst := FMachines[FMachineList.ItemIndex].FirstSegment;
    FLast := FMachines[FMachineList.ItemIndex].LastSegment;
  end
  else if FByRange.Checked then
  begin
    First := StrToIntDef(Trim(FFirstEdit.Text), -1);
    if Trim(FLastEdit.Text) = '' then
      Last := MaxInt
    else
      Last := StrToIntDef(Trim(FLastEdit.Text), -1);
    if (First < 0) or (Last < First) then
    begin
      MessageDlg(kMsgBadRange, mtWarning, [mbOK], 0);
      Exit;
    end;
    FFirst := First div kSegmentFrames;
    if Last = MaxInt then
      FLast := -1
    else
      FLast := Last div kSegmentFrames;
  end
  else
  begin
    FFirst := 0;
    FLast := -1;
  end;
  FDialog.ModalResult := mrOk;
end;

{------------------------------------------------------------------------------}

function TResumeDialog.Run(const Machines: TSplitMachines; out FirstSegment, LastSegment: Integer): Boolean;
var
  I: Integer;
  Ok, Cancel: TButton;
begin
  FMachines := Machines;
  FDialog := TForm.Create(nil);
  try
    SetupDialog(FDialog, 'Reprendre des morceaux : plage à calculer', 480, 250);
    FByMachine := TRadioButton.Create(FDialog);
    FByMachine.Parent := FDialog;
    FByMachine.SetBounds(12, 14, 100, 20);
    FByMachine.Caption := 'Machine';
    FByMachine.OnClick := ModeChange;
    FMachineList := TComboBox.Create(FDialog);
    FMachineList.Parent := FDialog;
    FMachineList.SetBounds(120, 12, 348, 23);
    FMachineList.Style := csDropDownList;
    for I := 0 to High(Machines) do
      FMachineList.Items.Add(Format('%s : images %d à %d', [Machines[I].Name, Machines[I].FirstSegment *
        kSegmentFrames, (Machines[I].LastSegment + 1) * kSegmentFrames - 1]));
    if FMachineList.Items.Count > 0 then
      FMachineList.ItemIndex := 0;
    FByRange := TRadioButton.Create(FDialog);
    FByRange.Parent := FDialog;
    FByRange.SetBounds(12, 56, 100, 20);
    FByRange.Caption := 'Plage';
    FByRange.OnClick := ModeChange;
    NewLabel(FDialog, 120, 59, 90, 18, 'première image');
    FFirstEdit := NewEdit(FDialog, 210, 56, 70, '0');
    NewLabel(FDialog, 290, 59, 90, 18, 'dernière image');
    FLastEdit := NewEdit(FDialog, 380, 56, 70, '');
    NewLabel(FDialog, 120, 84, 348, 18, 'Dernière vide : jusqu''à la fin. Arrondi aux morceaux de ' +
      IntToStr(kSegmentFrames) + ' images.');
    FWhole := TRadioButton.Create(FDialog);
    FWhole.Parent := FDialog;
    FWhole.SetBounds(12, 118, 456, 20);
    FWhole.Caption := 'Toute la vidéo : calculer ce qui manque, puis assembler';
    FWhole.OnClick := ModeChange;
    FByMachine.Enabled := Length(Machines) > 0;
    FByMachine.Checked := Length(Machines) > 0;
    FWhole.Checked := Length(Machines) = 0;
    NewLabel(FDialog, 12, 150, 456, 36, 'Les morceaux déjà présents dans le dossier ne sont pas recalculés. ' +
      'La vidéo n''est assemblée que si la plage couvre toute la vidéo.').WordWrap := True;
    Ok := NewButton(FDialog, 303, 210, 80, 'OK', mrNone);
    Ok.OnClick := OkClick;
    Cancel := NewButton(FDialog, 389, 210, 80, 'Annuler', mrCancel);
    Cancel.Cancel := True;
    ModeChange(nil);
    Result := FDialog.ShowModal = mrOk;
  finally
    FDialog.Free;
  end;
  FirstSegment := FFirst;
  LastSegment := FLast;
end;

{------------------------------------------------------------------------------}

function ShowResumePartsDialog(out Folder: string; out FirstSegment, LastSegment: Integer): Boolean;
var
  Open: TOpenDialog;
  Machines: TSplitMachines;
  Dialog: TResumeDialog;
  SplitFile: string;
begin
  Result := False;
  Folder := '';
  FirstSegment := 0;
  LastSegment := -1;
  Open := TOpenDialog.Create(nil);
  try
    Open.Title := 'Dossier des morceaux : choisir son scenario.txt';
    Open.Filter := 'Tampon des morceaux (' + kStampName + ')|' + kStampName;
    Open.Options := [ofHideReadOnly, ofFileMustExist, ofEnableSizing];
    if not Open.Execute then
      Exit;
    Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(Open.FileName));
  finally
    Open.Free;
  end;
  if not SameText(Copy(Folder, Length(Folder) - Length(kPartsSuffix) + 1, MaxInt), kPartsSuffix) then
  begin
    MessageDlg(Format(kMsgNotParts, [kPartsSuffix]), mtWarning, [mbOK], 0);
    Exit;
  end;
  Machines := nil;
  SplitFile := Folder + PathDelim + kSplitFileName;
  if FileExists(SplitFile) then
  try
    Machines := LoadSplitFile(SplitFile, kSegmentFrames);
  except
    on E: Exception do
    begin
      MessageDlg(Format(kMsgBadSplitFile, [kSplitFileName, E.Message]), mtWarning, [mbOK], 0);
      Machines := nil;
    end;
  end;
  Dialog := TResumeDialog.Create;
  try
    Result := Dialog.Run(Machines, FirstSegment, LastSegment);
  finally
    Dialog.Free;
  end;
end;

end.
