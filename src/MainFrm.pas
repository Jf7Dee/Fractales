unit MainFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Buttons,
  AppEvnts, Math, Contnrs, Fractal.Types, Fractal.Formulas, Fractal.Engine, Fractal.Palette, Fractal.Navigation,
  Fractal.Persistence, Fractal.Png, Fractal.View, ImgList;

const
  kJuliaPreviewWidth = 240;
  kJuliaPreviewHeight = 180;
  kJuliaPreviewMaxIter = 300;
  kJuliaPreviewViewWidth = 3.5;
  kJuliaThreadCount = 2;
  kKeyZoomFactor = 2.0;
  kSmokeTimeoutMs = 30000;
  kRenderPollMs = 20;
  kParamRowHeight = 28;
  kParamLabelWidth = 120;
  kParamEditLeft = 130;
  kParamEditWidth = 120;
  kExportWaitMs = 60000;
  kFracFilter = 'Lieu fractal (*.frac)|*.frac';
  kPngFilter = 'Image PNG (*.png)|*.png';
  kMinCoordDigits = 3;
  kMaxCoordDigits = 18;

type
  TMainForm = class(TForm)
    pnlTop: TPanel;
    lblNavMode: TLabel;
    btnOpen: TButton;
    btnSave: TButton;
    btnExportPng: TButton;
    btnHiRes: TButton;
    cbNavMode: TComboBox;
    btnBack: TBitBtn;
    btnForward: TBitBtn;
    btnAddFavorite: TBitBtn;
    sbStatus: TStatusBar;
    pnlSide: TPanel;
    grpFormula: TGroupBox;
    lblMaxIter: TLabel;
    cbFormula: TComboBox;
    pnlParams: TPanel;
    edMaxIter: TEdit;
    chkAutoIter: TCheckBox;
    grpColors: TGroupBox;
    lblOffset: TLabel;
    lblRepeats: TLabel;
    lblStretch: TLabel;
    cbPalette: TComboBox;
    btnEditPalette: TButton;
    tbOffset: TTrackBar;
    tbRepeats: TTrackBar;
    tbStretch: TTrackBar;
    chkInvert: TCheckBox;
    grpFavorites: TGroupBox;
    lbFavorites: TListBox;
    splSide: TSplitter;
    pnlCollapse: TPanel;
    btnCollapse: TSpeedButton;
    tmrDisplay: TTimer;
    ImageList1: TImageList;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);

    procedure BackClick(Sender: TObject);
    procedure ForwardClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ExportPngClick(Sender: TObject);
    procedure HiResClick(Sender: TObject);
    procedure AddFavoriteClick(Sender: TObject);
    procedure FavoritesDblClick(Sender: TObject);
    procedure FavoritesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TogglePanelClick(Sender: TObject);
    procedure EditPaletteClick(Sender: TObject);
    procedure ColorSliderChange(Sender: TObject);
    procedure MaxIterEditExit(Sender: TObject);
    procedure MaxIterEditKeyPress(Sender: TObject; var Key: Char);
    procedure AutoIterClick(Sender: TObject);
  private
    FView: TFractalView;
    FEngine: TRenderEngine;
    FJuliaEngine: TRenderEngine;
    FJuliaFormula: TJuliaFormula;
    FNavigator: TNavigator;
    FFormula: TFractalFormula;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FMapper: TColorMapper;
    FAppEvents: TApplicationEvents;
    FIsAutoIter: Boolean;
    FAreColorsChanged: Boolean;
    FIsUpdating: Boolean;
    FMouseX: Integer;
    FMouseY: Integer;
    FStatusMessage: string;
    FIsFullScreen: Boolean;
    FSavedBounds: TRect;
    FSavedWindowState: TWindowState;
    FWasSidePanelVisible: Boolean;
    FPalettes: TObjectList;
    FFavorites: TFavoriteStore;
    FHiResForm: TForm;  // THiResForm, déclaré dans l'implémentation pour éviter une dépendance d'interface
    FSmokeLog: TStringList;
    FHasSmokeFailure: Boolean;
    procedure InitNavigation;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewResize(Sender: TObject);
    procedure NavigatorViewChanged(Sender: TObject; const Change: TViewChange);
    procedure NavigatorSelectionChanged(Sender: TObject);
    procedure NavigatorPrecisionLimit(Sender: TObject);
    procedure NavigatorJuliaPoint(Sender: TObject; const P: TComplexPoint);
    procedure NavigatorHistoryChanged(Sender: TObject);
    procedure NavModeChange(Sender: TObject);
    procedure DisplayTimer(Sender: TObject);
    procedure RenderCurrent;
    procedure RebuildMapper;
    procedure ColorsChanged;
    procedure ColorizeBuffer(Engine: TRenderEngine; Bitmap: TBitmap);
    procedure SetPanelText(Index: Integer; const Text: string);
    procedure UpdateStatus;
    procedure UpdateHistoryButtons;
    function WaitForRender(TimeoutMs: Cardinal): Boolean;
    procedure InitFormulaPanel;
    procedure FormulaComboChange(Sender: TObject);
    procedure SetFormula(AFormula: TFractalFormula; IsResetView: Boolean);
    procedure BuildParamEditors;

    procedure ParamEditExit(Sender: TObject);
    procedure ParamEditKeyPress(Sender: TObject; var Key: Char);
    procedure ApplyParamEdit(Edit: TEdit);
    procedure ApplyMaxIterEdit;
    procedure UpdateMaxIterControls;

    procedure SetSidePanelVisible(IsVisible: Boolean);
    procedure ToggleFullScreen;
    procedure InitColorPanel;
    procedure FillPaletteCombo;
    procedure PaletteComboChange(Sender: TObject);

    procedure UpdateColorControls;
    procedure PaletteEditorChange(Sender: TObject);
    procedure InitFilePanel;
    function CaptureLocation: TFractalLocation;
    procedure ApplyLocation(Location: TFractalLocation);
    function LocationAsPngText(Location: TFractalLocation): RawByteString;
    procedure ExportViewPng(const FileName: string);
    procedure RefreshFavorites;
    procedure PrepareHiResForm(Sender: TObject);

    procedure CheckSmokeStep(const StepName: string);
    procedure SmokeException(Sender: TObject; E: Exception);
  public
    function RunSmokeTest(const OutputFile: string): Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

uses
  PaletteEditorFrm, HiResFrm;

{------------------------------------------------------------------------------}

function ToNavButton(Button: TMouseButton): TNavButton;
begin
  case Button of
    mbRight: Result := nbRight;
    mbMiddle: Result := nbMiddle;
  else
    Result := nbLeft;
  end;
end;

{------------------------------------------------------------------------------}

function CountLitPixels(Bitmap: TBitmap): Integer;
var
  X, Y: Integer;
  P: PCardinal;
begin
  Result := 0;
  for Y := 0 to Bitmap.Height - 1 do
  begin
    P := Bitmap.ScanLine[Y];
    for X := 0 to Bitmap.Width - 1 do
    begin
      if P^ and $FFFFFF <> 0 then
        Inc(Result);
      Inc(P);
    end;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FView := TFractalView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnMouseDown := ViewMouseDown;
  FView.OnMouseMove := ViewMouseMove;
  FView.OnMouseUp := ViewMouseUp;

  FEngine := TRenderEngine.Create(CpuCount);
  FJuliaEngine := TRenderEngine.Create(kJuliaThreadCount);
  FJuliaFormula := TJuliaFormula.Create;
  FJuliaFormula.MaxIter := kJuliaPreviewMaxIter;
  FFormula := TMandelbrotFormula.Create;
  FIsAutoIter := True;
  FPalette := CreateBuiltInPalette(0);
  FMapping := DefaultColorMapping;
  RebuildMapper;

  FAppEvents := TApplicationEvents.Create(Self);
  FAppEvents.OnMessage := AppMessage;
  tmrDisplay.OnTimer := DisplayTimer;
  InitNavigation;
  InitFormulaPanel;
  InitColorPanel;
  InitFilePanel;
  FView.OnResize := ViewResize;

  FNavigator.Reset(MakeViewport(FFormula.DefaultCenterX, FFormula.DefaultCenterY, FFormula.DefaultWidth,
    Max(1, FView.ClientWidth), Max(1, FView.ClientHeight)));
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  tmrDisplay.Enabled := False;
  FView.OnResize := nil;
  FView.OnMouseDown := nil;
  FView.OnMouseMove := nil;
  FView.OnMouseUp := nil;
  FAppEvents.OnMessage := nil;
  FreeAndNil(FEngine);
  FreeAndNil(FJuliaEngine);
  FreeAndNil(FNavigator);
  FreeAndNil(FMapper);
  FreeAndNil(FPalette);
  FreeAndNil(FPalettes);
  FreeAndNil(FFavorites);
  FreeAndNil(FJuliaFormula);
  FreeAndNil(FFormula);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.InitNavigation;
var
  I: Integer;
begin
  FNavigator := TNavigator.Create;
  FNavigator.OnViewChanged := NavigatorViewChanged;
  FNavigator.OnSelectionChanged := NavigatorSelectionChanged;
  FNavigator.OnPrecisionLimit := NavigatorPrecisionLimit;
  FNavigator.OnJuliaPoint := NavigatorJuliaPoint;
  FNavigator.OnHistoryChanged := NavigatorHistoryChanged;
  for I := 0 to High(kNavigationModes) do
    cbNavMode.Items.Add(kNavigationModes[I].DisplayName);
  cbNavMode.ItemIndex := 0;
  cbNavMode.OnChange := NavModeChange;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_F11 then
  begin
    ToggleFullScreen;
    Key := 0;
    Exit;
  end;

  if Key = VK_ESCAPE then
  begin
    FNavigator.CancelSelection;
    Key := 0;
    Exit;
  end;

  // les touches de navigation ne doivent pas voler la saisie dans les champs du panneau
  if (ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox) or (ActiveControl is TCustomListBox)
    or (ActiveControl is TTrackBar) then
    Exit;

  case Key of
    VK_ADD, VK_OEM_PLUS:
      FNavigator.ZoomCenter(kKeyZoomFactor);
    VK_SUBTRACT, VK_OEM_MINUS:
      FNavigator.ZoomCenter(1 / kKeyZoomFactor);
    VK_LEFT:
      FNavigator.KeyPan(-1, 0);
    VK_RIGHT:
      FNavigator.KeyPan(1, 0);
    VK_UP:
      FNavigator.KeyPan(0, -1);
    VK_DOWN:
      FNavigator.KeyPan(0, 1);
    VK_BACK:
      FNavigator.GoBack;
  else
    Exit;
  end;
  Key := 0;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  P: TPoint;
begin
  // la molette va au contrôle sous le curseur, pas à celui qui a le focus
  if (Msg.message <> WM_MOUSEWHEEL) or not FView.HandleAllocated then
    Exit;
  P := Point(SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)));
  if WindowFromPoint(P) <> FView.Handle then
    Exit;
  P := FView.ScreenToClient(P);
  FNavigator.MouseWheel(SmallInt(HiWord(Msg.wParam)), P.X, P.Y);
  Handled := True;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FNavigator.MouseDown(ToNavButton(Button), X, Y);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FMouseX := X;
  FMouseY := Y;
  FNavigator.MouseMove(X, Y, ssLeft in Shift);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FNavigator.MouseUp(ToNavButton(Button), X, Y);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ViewResize(Sender: TObject);
begin
  FNavigator.SetPixelSize(Max(1, FView.ClientWidth), Max(1, FView.ClientHeight));
end;

{------------------------------------------------------------------------------}

procedure TMainForm.NavigatorViewChanged(Sender: TObject; const Change: TViewChange);
var
  V: TViewport;
begin
  FStatusMessage := '';
  V := FNavigator.Viewport;
  if FIsAutoIter then
  begin
    FFormula.MaxIter := AutoMaxIter(V);
    UpdateMaxIterControls;
  end;
  if Change.Kind = vckPan then
    FEngine.RenderShifted(V, FFormula, Change.DX, Change.DY)
  else
    FEngine.Render(V, FFormula);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.NavigatorSelectionChanged(Sender: TObject);
begin
  FView.SetSelection(FNavigator.SelectionRect, FNavigator.HasSelection);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.NavigatorPrecisionLimit(Sender: TObject);
begin
  FStatusMessage := 'Limite de précision atteinte : zoom bloqué.';
end;

{------------------------------------------------------------------------------}

procedure TMainForm.NavigatorJuliaPoint(Sender: TObject; const P: TComplexPoint);
begin
  FJuliaFormula.SetParam(FJuliaFormula.IndexOfParam('cx'), P.X);
  FJuliaFormula.SetParam(FJuliaFormula.IndexOfParam('cy'), P.Y);
  FJuliaEngine.Render(MakeViewport(0, 0, kJuliaPreviewViewWidth, kJuliaPreviewWidth, kJuliaPreviewHeight),
                      FJuliaFormula);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.NavigatorHistoryChanged(Sender: TObject);
begin
  UpdateHistoryButtons;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.NavModeChange(Sender: TObject);
begin
  FNavigator.SetMode(kNavigationModes[cbNavMode.ItemIndex]);
  FView.IsJuliaVisible := FNavigator.Mode is TJuliaNavigationMode;
  FView.SetFocus;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.BackClick(Sender: TObject);
begin
  FNavigator.GoBack;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ForwardClick(Sender: TObject);
begin
  FNavigator.GoForward;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.UpdateHistoryButtons;
begin
  btnBack.Enabled := FNavigator.CanGoBack;
  btnForward.Enabled := FNavigator.CanGoForward;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.RenderCurrent;
begin
  FEngine.Render(FNavigator.Viewport, FFormula);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.RebuildMapper;
begin
  FreeAndNil(FMapper);
  FMapper := TColorMapper.Create(FPalette, FMapping);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ColorsChanged;
begin
  RebuildMapper;
  FAreColorsChanged := True;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ColorizeBuffer(Engine: TRenderEngine; Bitmap: TBitmap);
var
  Y: Integer;
begin
  if (Engine.Buffer.Width = 0) or (Engine.Buffer.Height = 0) then
    Exit;

  if (Bitmap.Width <> Engine.Buffer.Width) or (Bitmap.Height <> Engine.Buffer.Height) then
  begin
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Engine.Buffer.Width, Engine.Buffer.Height);
  end;

  for Y := 0 to Engine.Buffer.Height - 1 do
    FMapper.MapRow(Engine.Buffer.RowPtr(Y), Bitmap.ScanLine[Y], Engine.Buffer.Width);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.DisplayTimer(Sender: TObject);
var
  IsChanged: Boolean;
  Errors: string;
begin
  IsChanged := False;
  if FEngine.Buffer.TakeDirtyFlag or FAreColorsChanged then
  begin
    ColorizeBuffer(FEngine, FView.Bitmap);
    IsChanged := True;
  end;

  if FView.IsJuliaVisible and (FJuliaEngine.Buffer.TakeDirtyFlag or FAreColorsChanged) then
  begin
    ColorizeBuffer(FJuliaEngine, FView.JuliaBitmap);
    IsChanged := True;
  end;

  FAreColorsChanged := False;
  if IsChanged then
    FView.Invalidate;
  Errors := FEngine.TakeErrors;
  if Errors <> '' then
    FStatusMessage := 'Erreur de calcul : ' + Copy(Errors, 1, Pos(#13, Errors + #13) - 1);
  UpdateStatus;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.SetPanelText(Index: Integer; const Text: string);
begin
  if sbStatus.Panels[Index].Text <> Text then
    sbStatus.Panels[Index].Text := Text;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.UpdateStatus;
var
  V: TViewport;
  P: TComplexPoint;
  Digits: Integer;
  S: TRenderStatus;
  Msg: string;
begin
  V := FNavigator.Viewport;
  P := V.PixelToComplex(FMouseX, FMouseY);
  if IsNan(V.PixelSize) or IsInfinite(V.PixelSize) or not (V.PixelSize > 0) then
    Digits := kMinCoordDigits
  else
    Digits := EnsureRange(Ceil(-Log10(V.PixelSize)) + 1, kMinCoordDigits, kMaxCoordDigits);
  SetPanelText(0, 'x = ' + FloatToStrF(P.X, ffFixed, 18, Digits) + '   y = ' + FloatToStrF(P.Y, ffFixed, 18, Digits));
  SetPanelText(1, 'zoom ' + FormatFloat('0.00e+0', V.Zoom));
  SetPanelText(2, IntToStr(FFormula.MaxIter) + ' it.');
  S := FEngine.Status;
  if S.IsComplete then
    SetPanelText(3, Format('terminé en %d ms', [S.ElapsedMs]))
  else
    SetPanelText(3, Format('passe %d/%d   %d ms', [S.CurrentPass, S.PassCount, S.ElapsedMs]));
  Msg := FStatusMessage;
  if V.PrecisionState <> psOk then
    Msg := 'Limite de précision proche. ' + Msg;
  SetPanelText(4, Msg);
end;

{------------------------------------------------------------------------------}

function TMainForm.WaitForRender(TimeoutMs: Cardinal): Boolean;
var
  Start: Cardinal;
begin
  Start := GetTickCount;
  repeat
    Application.ProcessMessages;
    if FEngine.WaitUntilComplete(kRenderPollMs) then
    begin
      if FEngine.Status.IsComplete then
        Exit(True);
      Sleep(1);  // rendu annulé et non relancé : ne pas tourner à vide
    end;
  until GetTickCount - Start > TimeoutMs;
  Result := False;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.CheckSmokeStep(const StepName: string);
var
  Errors: string;
begin
  Errors := FEngine.TakeErrors;  // avant DisplayTimer, qui les consommerait aussi
  if Errors <> '' then
    raise Exception.Create(StepName + ' : erreur de calcul : ' + Errors);
  DisplayTimer(nil);
  if CountLitPixels(FView.Bitmap) = 0 then
    raise Exception.Create(StepName + ' : image entièrement noire');
end;

{------------------------------------------------------------------------------}

procedure TMainForm.SmokeException(Sender: TObject; E: Exception);
begin
  FSmokeLog.Add('ÉCHEC : exception non gérée : ' + E.Message);
  FHasSmokeFailure := True;
end;

{------------------------------------------------------------------------------}

function TMainForm.RunSmokeTest(const OutputFile: string): Integer;
var
  Dlg: TPaletteEditorForm;
  Text: RawByteString;
  Location: TFractalLocation;
  HiRes: THiResForm;
  HiResFile: string;
  Start: Cardinal;
begin
  Result := 1;

  FSmokeLog := TStringList.Create;
  try
    Application.OnException := SmokeException;
    try
      Show;
      Application.ProcessMessages;
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu initial non terminé');
      CheckSmokeStep('rendu initial');
      FSmokeLog.Add(Format('Rendu initial OK : %d x %d en %d ms', [FView.Bitmap.Width, FView.Bitmap.Height,
        FEngine.Status.ElapsedMs]));
      FNavigator.ZoomCenter(4);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après zoom non terminé');
      CheckSmokeStep('zoom');
      FSmokeLog.Add('Zoom OK');
      FNavigator.PanBy(25, -10);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après déplacement non terminé');
      CheckSmokeStep('déplacement');
      FSmokeLog.Add('Déplacement OK');
      SetFormula(TMultibrotFormula.Create, True);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu Multibrot non terminé');
      CheckSmokeStep('Multibrot');
      if pnlParams.ControlCount <> 2 then
        raise Exception.Create('éditeur de paramètres Multibrot absent');

      SetSidePanelVisible(False);
      SetSidePanelVisible(True);
      if not pnlSide.Visible then
        raise Exception.Create('panneau latéral non restauré');
      FSmokeLog.Add('Formules et panneau OK');
      tbOffset.Position := 500;
      chkInvert.Checked := True;

      if not FMapping.IsInverted or (Abs(FMapping.Offset - 0.5) > 1e-9) then
        raise Exception.Create('réglages de couleur non appliqués');
      cbPalette.ItemIndex := 1;
      PaletteComboChange(nil);
      DisplayTimer(nil);
      FSmokeLog.Add('Couleurs OK');

      Dlg := TPaletteEditorForm.Create(Self);
      try
        Dlg.Palette.Assign(FPalette);
        Dlg.Show;
        Application.ProcessMessages;
        Dlg.Close;
      finally
        Dlg.Free;
      end;
      FSmokeLog.Add('Éditeur de palette OK');
      ExportViewPng(OutputFile);
      if not ReadPngText(OutputFile, kLocationKeyword, Text) then
        raise Exception.Create('lieu absent du PNG exporté');

      Location := TFractalLocation.Create;
      try
        Location.LoadFromText(UTF8ToString(Text));
        if Location.FormulaName <> FFormula.FormulaName then
          raise Exception.Create('lieu du PNG incohérent');
        ApplyLocation(Location);
      finally
        Location.Free;
      end;

      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après réouverture non terminé');
      CheckSmokeStep('réouverture');
      FSmokeLog.Add('Export PNG et réouverture OK');
      HiResClick(nil);
      HiRes := THiResForm(FHiResForm);
      HiResFile := ChangeFileExt(OutputFile, '') + '_hd.png';
      SysUtils.DeleteFile(HiResFile);
      HiRes.cbPreset.ItemIndex := kPresetCustom;
      HiRes.cbPresetChange(nil);
      HiRes.edWidth.Text := '160';
      HiRes.edHeight.Text := '120';
      HiRes.cbSupersample.ItemIndex := 1;
      HiRes.edFile.Text := ExpandFileName(HiResFile);
      HiRes.StartRender;
      Start := GetTickCount;

      while HiRes.IsRunning and (GetTickCount - Start < kSmokeTimeoutMs) do
      begin
        Application.ProcessMessages;
        Sleep(kRenderPollMs);
      end;

      if HiRes.IsRunning then
        raise Exception.Create('rendu HD non terminé');
      if not FileExists(HiResFile) then
        raise Exception.Create('fichier du rendu HD absent');
      FSmokeLog.Add('Rendu HD OK');
      if not FHasSmokeFailure then
        Result := 0;
    except
      on E: Exception do
        FSmokeLog.Add('ÉCHEC : ' + E.Message);
    end;
  finally
    Application.OnException := nil;
    FSmokeLog.SaveToFile(OutputFile + '.log', TEncoding.UTF8);
    FreeAndNil(FSmokeLog);
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.InitFormulaPanel;
var
  I: Integer;
begin
  for I := 0 to FormulaClassCount - 1 do
    cbFormula.Items.Add(FormulaClassAt(I).DisplayName);
  cbFormula.OnChange := FormulaComboChange;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I) = FFormula.ClassType then
      cbFormula.ItemIndex := I;
  BuildParamEditors;
  UpdateMaxIterControls;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormulaComboChange(Sender: TObject);
begin
  SetFormula(FormulaClassAt(cbFormula.ItemIndex).Create, True);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.SetFormula(AFormula: TFractalFormula; IsResetView: Boolean);
var
  I: Integer;
begin
  FFormula.Free;
  FFormula := AFormula;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I) = FFormula.ClassType then
      cbFormula.ItemIndex := I;
  BuildParamEditors;
  UpdateMaxIterControls;
  if IsResetView then
    FNavigator.Reset(MakeViewport(FFormula.DefaultCenterX, FFormula.DefaultCenterY, FFormula.DefaultWidth,
      Max(1, FView.ClientWidth), Max(1, FView.ClientHeight)))
  else
    RenderCurrent;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.BuildParamEditors;
var
  I: Integer;
  L: TLabel;
  E: TEdit;
begin
  // détacher OnExit avant de libérer : un champ qui perd le focus en mourant ne doit rien appliquer
  for I := 0 to pnlParams.ControlCount - 1 do
    if pnlParams.Controls[I] is TEdit then
      TEdit(pnlParams.Controls[I]).OnExit := nil;
  while pnlParams.ControlCount > 0 do
    pnlParams.Controls[0].Free;

  for I := 0 to FFormula.ParamCount - 1 do
  begin
    L := TLabel.Create(Self);
    L.Parent := pnlParams;
    L.Caption := FFormula.ParamInfo(I).Caption;
    L.SetBounds(0, I * kParamRowHeight + 4, kParamLabelWidth, 20);
    E := TEdit.Create(Self);
    E.Parent := pnlParams;
    E.SetBounds(kParamEditLeft, I * kParamRowHeight, kParamEditWidth, 22);
    E.Text := FloatToStr(FFormula.GetParam(I));
    E.Tag := I;
    E.OnExit := ParamEditExit;
    E.OnKeyPress := ParamEditKeyPress;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ParamEditExit(Sender: TObject);
begin
  ApplyParamEdit(TEdit(Sender));
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ParamEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    ApplyParamEdit(TEdit(Sender));
    Key := #0;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ApplyParamEdit(Edit: TEdit);
var
  Value: Double;
  Index: Integer;
begin
  Index := Edit.Tag;
  if TryStrToFloat(Edit.Text, Value) then
  begin
    if Value <> FFormula.GetParam(Index) then
    begin
      FFormula.SetParam(Index, Value);
      RenderCurrent;
    end;
    FStatusMessage := '';
  end
  else
    FStatusMessage := Format('Valeur invalide pour « %s ».', [FFormula.ParamInfo(Index).Caption]);
  Edit.Text := FloatToStr(FFormula.GetParam(Index));
end;

{------------------------------------------------------------------------------}

procedure TMainForm.MaxIterEditExit(Sender: TObject);
begin
  ApplyMaxIterEdit;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.MaxIterEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    ApplyMaxIterEdit;
    Key := #0;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ApplyMaxIterEdit;
var
  Value: Integer;
begin
  if edMaxIter.Modified and TryStrToInt(edMaxIter.Text, Value) then
  begin
    FIsAutoIter := False;
    if Value <> FFormula.MaxIter then
    begin
      FFormula.MaxIter := Value;
      RenderCurrent;
    end;
  end;
  UpdateMaxIterControls;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.AutoIterClick(Sender: TObject);
begin
  if FIsUpdating then
    Exit;
  FIsAutoIter := chkAutoIter.Checked;
  if FIsAutoIter then
  begin
    FFormula.MaxIter := AutoMaxIter(FNavigator.Viewport);
    RenderCurrent;
  end;
  UpdateMaxIterControls;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.UpdateMaxIterControls;
begin
  FIsUpdating := True;
  try
    edMaxIter.Text := IntToStr(FFormula.MaxIter);
    edMaxIter.Modified := False;
    chkAutoIter.Checked := FIsAutoIter;
  finally
    FIsUpdating := False;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.TogglePanelClick(Sender: TObject);
begin
  if FIsFullScreen then
    Exit;
  SetSidePanelVisible(not pnlSide.Visible);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.SetSidePanelVisible(IsVisible: Boolean);
begin
  btnCollapse.Glyph := nil;
  btnCollapse.NumGlyphs := 1;
  if IsVisible then
  begin
    // ordre des contrôles alignés à droite : bande de repli, séparateur, panneau
    pnlSide.Left := ClientWidth;
    pnlSide.Visible := True;
    splSide.Left := pnlSide.Left - 1;
    splSide.Visible := True;
    ImageList1.GetBitmap(0, btnCollapse.Glyph);
  end
  else
  begin
    splSide.Visible := False;
    pnlSide.Visible := False;
    ImageList1.GetBitmap(1, btnCollapse.Glyph);
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ToggleFullScreen;
begin
  FIsFullScreen := not FIsFullScreen;
  if FIsFullScreen then
  begin
    FSavedWindowState := WindowState;
    WindowState := wsNormal;
    FSavedBounds := BoundsRect;
    FWasSidePanelVisible := pnlSide.Visible;
    pnlTop.Visible := False;
    sbStatus.Visible := False;
    SetSidePanelVisible(False);
    pnlCollapse.Visible := False;
    BorderStyle := bsNone;
    BoundsRect := Monitor.BoundsRect;
  end
  else
  begin
    BorderStyle := bsSizeable;
    BoundsRect := FSavedBounds;
    WindowState := FSavedWindowState;
    pnlTop.Visible := True;
    sbStatus.Visible := True;
    pnlCollapse.Visible := True;
    SetSidePanelVisible(FWasSidePanelVisible);
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.InitColorPanel;
begin
  FPalettes := TObjectList.Create(True);
  FillPaletteCombo;
  cbPalette.ItemIndex := 0;
  cbPalette.OnChange := PaletteComboChange;
  UpdateColorControls;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FillPaletteCombo;
var
  I: Integer;
  Folder, Ext: string;
  SR: TSearchRec;
  P: TGradientPalette;
  Lines: TStringList;
begin
  FPalettes.Clear;
  cbPalette.Items.Clear;

  for I := 0 to BuiltInPaletteCount - 1 do
    FPalettes.Add(CreateBuiltInPalette(I));

  Folder := PaletteFolder;

  if FindFirst(Folder + '*.*', faAnyFile, SR) = 0 then
    try
      repeat
        Ext := LowerCase(ExtractFileExt(SR.Name));
        if (Ext <> '.pal') and (Ext <> '.map') then
          Continue;
        P := TGradientPalette.Create;
        Lines := TStringList.Create;
        try
          try
            Lines.LoadFromFile(Folder + SR.Name);
            if Ext = '.map' then
              P.LoadFromMap(Lines)
            else
              P.LoadFromStrings(Lines);
            if (Ext = '.map') or (P.Name = '') then
              P.Name := ChangeFileExt(SR.Name, '');
            FPalettes.Add(P);
            P := nil;
          except
            on E: Exception do
              FStatusMessage := Format('Palette ignorée (%s) : %s', [SR.Name, E.Message]);
          end;
        finally
          Lines.Free;
          P.Free;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;

  for I := 0 to FPalettes.Count - 1 do
    cbPalette.Items.Add(TGradientPalette(FPalettes[I]).Name);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.PaletteComboChange(Sender: TObject);
begin
  if cbPalette.ItemIndex < 0 then
    Exit;
  FPalette.Assign(TGradientPalette(FPalettes[cbPalette.ItemIndex]));
  ColorsChanged;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ColorSliderChange(Sender: TObject);
begin
  if FIsUpdating then
    Exit;
  FMapping := MappingFromSliders(tbOffset.Position, tbRepeats.Position, tbStretch.Position, chkInvert.Checked);
  ColorsChanged;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.UpdateColorControls;
var
  Offset, Repeats, Stretch: Integer;
begin
  FIsUpdating := True;
  try
    MappingToSliders(FMapping, Offset, Repeats, Stretch);
    tbOffset.Position := Offset;
    tbRepeats.Position := Repeats;
    tbStretch.Position := Stretch;
    chkInvert.Checked := FMapping.IsInverted;
  finally
    FIsUpdating := False;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.EditPaletteClick(Sender: TObject);
var
  Dlg: TPaletteEditorForm;
  Saved: TGradientPalette;
begin
  Saved := TGradientPalette.Create;
  Dlg := TPaletteEditorForm.Create(Self);

  try
    Saved.Assign(FPalette);
    Dlg.Palette.Assign(FPalette);
    Dlg.OnPaletteChange := PaletteEditorChange;
    if Dlg.ShowModal = mrOk then
    begin
      // la palette modifiée n'est pas forcément enregistrée : on recharge la liste sans la sélectionner
      FillPaletteCombo;
      cbPalette.ItemIndex := -1;
    end
    else
      FPalette.Assign(Saved);
    ColorsChanged;
  finally
    Dlg.Free;
    Saved.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.PaletteEditorChange(Sender: TObject);
begin
  FPalette.Assign(TPaletteEditorForm(Sender).Palette);
  ColorsChanged;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.InitFilePanel;
begin
  FFavorites := TFavoriteStore.Create(FavoritesFolder);
  RefreshFavorites;
end;

{------------------------------------------------------------------------------}

function TMainForm.CaptureLocation: TFractalLocation;
begin
  Result := TFractalLocation.Create;
  Result.CaptureFrom(FFormula, FNavigator.Viewport, FIsAutoIter, FPalette, FMapping);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ApplyLocation(Location: TFractalLocation);
var
  V: TViewport;
  Formula: TFractalFormula;
begin
  Formula := Location.CreateFormula;
  FIsAutoIter := Location.IsAutoIter;
  FPalette.Assign(Location.Palette);
  FMapping := Location.Mapping;
  cbPalette.ItemIndex := -1;
  UpdateColorControls;
  ColorsChanged;
  SetFormula(Formula, False);
  V := FNavigator.Viewport;
  Location.ApplyTo(V);
  FNavigator.Reset(V);
end;

{------------------------------------------------------------------------------}

function TMainForm.LocationAsPngText(Location: TFractalLocation): RawByteString;
begin
  Result := UTF8Encode(Location.SaveToText);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.OpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  Location: TFractalLocation;
  Text: RawByteString;
begin
  Dlg := TOpenDialog.Create(nil);
  Location := TFractalLocation.Create;
  try
    Dlg.Filter := 'Lieux et images (*.frac;*.png)|*.frac;*.png|' + kFracFilter + '|' + kPngFilter;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then
      Exit;
    try
      if SameText(ExtractFileExt(Dlg.FileName), '.png') then
      begin
        if not ReadPngText(Dlg.FileName, kLocationKeyword, Text) then
        begin
          MessageDlg('Ce PNG ne contient pas de lieu fractal : il ne peut pas être rouvert dans l''application.',
            mtInformation, [mbOK], 0);
          Exit;
        end;
        Location.LoadFromText(UTF8ToString(Text));
      end
      else
        Location.LoadFromFile(Dlg.FileName);
      ApplyLocation(Location);
    except
      on E: EFractalFileError do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Location.Free;
    Dlg.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.SaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Location: TFractalLocation;
begin
  Dlg := TSaveDialog.Create(nil);
  Location := CaptureLocation;
  try
    Dlg.Filter := kFracFilter;
    Dlg.DefaultExt := 'frac';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    try
      Location.SaveToFile(Dlg.FileName);
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Location.Free;
    Dlg.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ExportPngClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := kPngFilter;
    Dlg.DefaultExt := 'png';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    try
      ExportViewPng(Dlg.FileName);
    except
      on E: Exception do
        MessageDlg('Export impossible : ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.ExportViewPng(const FileName: string);
var
  Stream: TFileStream;
  Writer: TPngWriter;
  Location: TFractalLocation;
  Row: array of Byte;
  X, Y: Integer;
  Src: PCardinal;
  Bmp: TBitmap;
  IsFileCreated: Boolean;
begin
  Screen.Cursor := crHourGlass;
  try
    WaitForRender(kExportWaitMs);
    ColorizeBuffer(FEngine, FView.Bitmap);
  finally
    Screen.Cursor := crDefault;
  end;
  Bmp := FView.Bitmap;
  SetLength(Row, Bmp.Width * 3);
  IsFileCreated := False;
  Location := CaptureLocation;
  try
    try
      Stream := TFileStream.Create(FileName, fmCreate);
      IsFileCreated := True;
      try
        Writer := TPngWriter.Create(Stream, Bmp.Width, Bmp.Height);
        try
          Writer.AddText(kLocationKeyword, LocationAsPngText(Location));
          for Y := 0 to Bmp.Height - 1 do
          begin
            Src := Bmp.ScanLine[Y];
            for X := 0 to Bmp.Width - 1 do
            begin
              Row[X * 3] := (Src^ shr 16) and $FF;
              Row[X * 3 + 1] := (Src^ shr 8) and $FF;
              Row[X * 3 + 2] := Src^ and $FF;
              Inc(Src);
            end;
            Writer.WriteRow(@Row[0]);
          end;
          Writer.Finish;
        finally
          Writer.Free;
        end;
      finally
        Stream.Free;
      end;
    except
      if IsFileCreated then
        SysUtils.DeleteFile(FileName);
      raise;
    end;
  finally
    Location.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.RefreshFavorites;
begin
  FFavorites.List(lbFavorites.Items);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.AddFavoriteClick(Sender: TObject);
var
  Name, Stored: string;
  Location: TFractalLocation;
begin
  Name := '';
  if not InputQuery('Ajouter aux favoris', 'Nom du favori :', Name) or (Trim(Name) = '') then
    Exit;
  if FileExists(FFavorites.FileNameOf(Name))
    and (MessageDlg(Format('Le favori « %s » existe déjà. Le remplacer ?', [SanitizeFileName(Name)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  Location := CaptureLocation;
  try
    try
      Stored := FFavorites.Save(Name, Location);
    except
      on E: Exception do
      begin
        MessageDlg(E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Location.Free;
  end;
  RefreshFavorites;
  lbFavorites.ItemIndex := lbFavorites.Items.IndexOf(Stored);
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FavoritesDblClick(Sender: TObject);
var
  Location: TFractalLocation;
begin
  if lbFavorites.ItemIndex < 0 then
    Exit;
  Location := TFractalLocation.Create;
  try
    try
      FFavorites.Load(lbFavorites.Items[lbFavorites.ItemIndex], Location);
      ApplyLocation(Location);
    except
      on E: EFractalFileError do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Location.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FavoritesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Name: string;
begin
  if (Key <> VK_DELETE) or (lbFavorites.ItemIndex < 0) then
    Exit;
  Name := lbFavorites.Items[lbFavorites.ItemIndex];
  if MessageDlg(Format('Supprimer le favori « %s » ?', [Name]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FFavorites.Delete(Name);
    RefreshFavorites;
  end;
  Key := 0;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.HiResClick(Sender: TObject);
begin
  if FHiResForm = nil then
  begin
    FHiResForm := THiResForm.Create(Self);
    THiResForm(FHiResForm).OnRequestSnapshot := PrepareHiResForm;
  end;
  PrepareHiResForm(nil);
  FHiResForm.Show;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.PrepareHiResForm(Sender: TObject);
var
  Location: TFractalLocation;
begin
  Location := CaptureLocation;
  try
    THiResForm(FHiResForm).Prepare(FNavigator.Viewport, FFormula, FPalette, FMapping, LocationAsPngText(Location));
  finally
    Location.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if (FHiResForm <> nil) and THiResForm(FHiResForm).IsRunning then
    THiResForm(FHiResForm).FormCloseQuery(Self, CanClose);
end;

end.
