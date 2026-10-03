unit MainFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Buttons,
  AppEvnts, Math, Fractal.Types, Fractal.Formulas, Fractal.Engine, Fractal.Palette, Fractal.Navigation,
  Fractal.View;

const
  kJuliaPreviewWidth = 240;
  kJuliaPreviewHeight = 180;
  kJuliaPreviewMaxIter = 300;
  kJuliaPreviewViewWidth = 3.5;
  kJuliaThreadCount = 2;
  kKeyZoomFactor = 2.0;
  kSmokeTimeoutMs = 30000;
  kRenderPollMs = 20;

type
  TMainForm = class(TForm)
    pnlTop: TPanel;
    lblNavMode: TLabel;
    btnOpen: TButton;
    btnSave: TButton;
    btnExportPng: TButton;
    btnHiRes: TButton;
    cbNavMode: TComboBox;
    btnBack: TButton;
    btnForward: TButton;
    btnAddFavorite: TButton;
    btnTogglePanel: TButton;
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
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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
    procedure NavModeChange(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure ForwardClick(Sender: TObject);
    procedure DisplayTimer(Sender: TObject);
    procedure RenderCurrent;
    procedure RebuildMapper;
    procedure ColorsChanged;
    procedure ColorizeBuffer(Engine: TRenderEngine; Bitmap: TBitmap);
    procedure SetPanelText(Index: Integer; const Text: string);
    procedure UpdateStatus;
    procedure UpdateHistoryButtons;
    function WaitForRender(TimeoutMs: Cardinal): Boolean;
  public
    function RunSmokeTest(const OutputFile: string): Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{------------------------------------------------------------------------------}

function ToNavButton(Button: TMouseButton): TNavButton;
begin
  case Button of
    mbRight:
      Result := nbRight;
    mbMiddle:
      Result := nbMiddle;
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
  FView.OnResize := ViewResize;

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

  FNavigator.Reset(MakeViewport(FFormula.DefaultCenterX, FFormula.DefaultCenterY, FFormula.DefaultWidth,
    Max(1, FView.ClientWidth), Max(1, FView.ClientHeight)));
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  tmrDisplay.Enabled := False;
  FreeAndNil(FEngine);
  FreeAndNil(FJuliaEngine);
  FreeAndNil(FNavigator);
  FreeAndNil(FMapper);
  FreeAndNil(FPalette);
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
  for I := 0 to High(kNavigationModes) do
    cbNavMode.Items.Add(kNavigationModes[I].DisplayName);
  cbNavMode.ItemIndex := 0;
  cbNavMode.OnChange := NavModeChange;
  btnBack.OnClick := BackClick;
  btnForward.OnClick := ForwardClick;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
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
  V := FNavigator.Viewport;
  if FIsAutoIter then
    FFormula.MaxIter := AutoMaxIter(V);
  if Change.Kind = vckPan then
    FEngine.RenderShifted(V, FFormula, Change.DX, Change.DY)
  else
    FEngine.Render(V, FFormula);
  UpdateHistoryButtons;
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
    // Windows.PSingle (retourné par RowPtr) et System.PSingle (attendu par MapRow) sont deux types distincts
    FMapper.MapRow(System.PSingle(Engine.Buffer.RowPtr(Y)), Bitmap.ScanLine[Y], Engine.Buffer.Width);
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
  Digits := EnsureRange(Ceil(-Log10(V.PixelSize)) + 1, 3, 18);
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
      Exit(True);
  until GetTickCount - Start > TimeoutMs;
  Result := False;
end;

{------------------------------------------------------------------------------}

function TMainForm.RunSmokeTest(const OutputFile: string): Integer;
var
  Log: TStringList;
begin
  Result := 1;
  Log := TStringList.Create;
  try
    try
      Show;
      Application.ProcessMessages;
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu initial non terminé');
      DisplayTimer(nil);
      if CountLitPixels(FView.Bitmap) = 0 then
        raise Exception.Create('image entièrement noire');
      Log.Add(Format('Rendu initial OK : %d x %d en %d ms', [FView.Bitmap.Width, FView.Bitmap.Height,
        FEngine.Status.ElapsedMs]));
      FNavigator.ZoomCenter(4);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après zoom non terminé');
      Log.Add('Zoom OK');
      FNavigator.PanBy(25, -10);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après déplacement non terminé');
      Log.Add('Déplacement OK');
      Result := 0;
    except
      on E: Exception do
        Log.Add('ÉCHEC : ' + E.Message);
    end;
  finally
    Log.SaveToFile(OutputFile + '.log', TEncoding.UTF8);
    Log.Free;
  end;
end;

end.
