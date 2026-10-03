unit PaletteEditorFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, Math,
  Fractal.Palette, Fractal.Persistence;

const
  kGradientHeight = 56;
  kMarkerTop = 60;
  kMarkerSize = 8;
  kHitTolerance = 6;
  kMinStops = 2;

type
  TPaletteEditorForm = class(TForm)
    lblName: TLabel;
    lblHelp: TLabel;
    pbGradient: TPaintBox;
    edName: TEdit;
    btnColor: TButton;
    btnDelete: TButton;
    btnLoad: TButton;
    btnSave: TButton;
    btnImportMap: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    dlgColor: TColorDialog;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pbGradientPaint(Sender: TObject);
    procedure pbGradientMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbGradientMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbGradientMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure edNameChange(Sender: TObject);
    procedure btnColorClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnImportMapClick(Sender: TObject);
  private
    FPalette: TGradientPalette;
    FSelected: Integer;
    FIsDragging: Boolean;
    FOnPaletteChange: TNotifyEvent;
    function StopAtX(X: Integer): Integer;
    function PositionOfX(X: Integer): Double;
    function XOfPosition(Position: Double): Integer;
    procedure EditSelectedColor;
    procedure LoadPaletteFile(const FileName: string; IsMap: Boolean);
    procedure NotifyPaletteChange;
  public
    property Palette: TGradientPalette read FPalette;
    property OnPaletteChange: TNotifyEvent read FOnPaletteChange write FOnPaletteChange;
  end;

implementation

{$R *.dfm}

const
  kPaletteFilter = 'Palette (*.pal)|*.pal';
  kMapFilter = 'Palette Fractint (*.map)|*.map';

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.FormCreate(Sender: TObject);
begin
  FPalette := TGradientPalette.Create;
  dlgOpen.InitialDir := PaletteFolder;
  dlgSave.InitialDir := PaletteFolder;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.FormDestroy(Sender: TObject);
begin
  FPalette.Free;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.FormShow(Sender: TObject);
begin
  edName.Text := FPalette.Name;
  FSelected := 0;
  pbGradient.Invalidate;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (ActiveControl <> edName) then
  begin
    btnDeleteClick(nil);
    Key := 0;
  end;
end;

{------------------------------------------------------------------------------}

function TPaletteEditorForm.XOfPosition(Position: Double): Integer;
begin
  Result := Round(Position * (pbGradient.Width - 1));
end;

{------------------------------------------------------------------------------}

function TPaletteEditorForm.PositionOfX(X: Integer): Double;
begin
  Result := EnsureRange(X / (pbGradient.Width - 1), 0.0, 1.0);
end;

{------------------------------------------------------------------------------}

function TPaletteEditorForm.StopAtX(X: Integer): Integer;
var
  I, Distance, Best: Integer;
begin
  Result := -1;
  Best := kHitTolerance + 1;
  for I := 0 to FPalette.StopCount - 1 do
  begin
    Distance := Abs(XOfPosition(FPalette.Stop(I).Position) - X);
    if Distance < Best then
    begin
      Best := Distance;
      Result := I;
    end;
  end;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.pbGradientPaint(Sender: TObject);
var
  X, I, W: Integer;
  S: TColorStop;
  C: TCanvas;
begin
  C := pbGradient.Canvas;
  W := pbGradient.Width;
  for X := 0 to W - 1 do
  begin
    C.Pen.Color := TColor(SwapRedBlue(FPalette.ColorAt(X / W)));
    C.MoveTo(X, 0);
    C.LineTo(X, kGradientHeight);
  end;
  C.Brush.Color := clBtnFace;
  C.FillRect(Rect(0, kGradientHeight, W, pbGradient.Height));
  for I := 0 to FPalette.StopCount - 1 do
  begin
    S := FPalette.Stop(I);
    X := XOfPosition(S.Position);
    C.Brush.Color := TColor(SwapRedBlue(S.Color));
    if I = FSelected then
    begin
      C.Pen.Color := clHighlight;
      C.Pen.Width := 2;
    end
    else
    begin
      C.Pen.Color := clBlack;
      C.Pen.Width := 1;
    end;
    C.Polygon([Point(X, kMarkerTop), Point(X - kMarkerSize, kMarkerTop + 2 * kMarkerSize),
      Point(X + kMarkerSize, kMarkerTop + 2 * kMarkerSize)]);
  end;
  C.Pen.Width := 1;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.pbGradientMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
begin
  if Button <> mbLeft then
    Exit;
  I := StopAtX(X);
  if ssDouble in Shift then
  begin
    FIsDragging := False;
    if I < 0 then
    begin
      FSelected := FPalette.AddStop(PositionOfX(X), FPalette.ColorAt(PositionOfX(X)));
      NotifyPaletteChange;
    end
    else
      FSelected := I;
    pbGradient.Invalidate;
    EditSelectedColor;
    Exit;
  end;
  if I >= 0 then
  begin
    FSelected := I;
    FIsDragging := True;
    pbGradient.Invalidate;
  end;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.pbGradientMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if not FIsDragging then
    Exit;
  FSelected := FPalette.MoveStop(FSelected, PositionOfX(X));
  pbGradient.Invalidate;
  NotifyPaletteChange;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.pbGradientMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FIsDragging := False;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.edNameChange(Sender: TObject);
begin
  FPalette.Name := edName.Text;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.EditSelectedColor;
begin
  if (FSelected < 0) or (FSelected >= FPalette.StopCount) then
    Exit;
  dlgColor.Color := TColor(SwapRedBlue(FPalette.Stop(FSelected).Color));
  if not dlgColor.Execute then
    Exit;
  FPalette.SetStopColor(FSelected, SwapRedBlue(Cardinal(ColorToRGB(dlgColor.Color))));
  pbGradient.Invalidate;
  NotifyPaletteChange;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.btnColorClick(Sender: TObject);
begin
  EditSelectedColor;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.btnDeleteClick(Sender: TObject);
begin
  if FPalette.StopCount <= kMinStops then
  begin
    MessageDlg('Une palette doit garder au moins deux points.', mtInformation, [mbOK], 0);
    Exit;
  end;
  FPalette.DeleteStop(FSelected);
  FSelected := Min(FSelected, FPalette.StopCount - 1);
  pbGradient.Invalidate;
  NotifyPaletteChange;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.LoadPaletteFile(const FileName: string; IsMap: Boolean);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName);
      if IsMap then
        FPalette.LoadFromMap(Lines)
      else
        FPalette.LoadFromStrings(Lines);
      if IsMap or (FPalette.Name = '') then
        FPalette.Name := ChangeFileExt(ExtractFileName(FileName), '');
      edName.Text := FPalette.Name;
      FSelected := 0;
      pbGradient.Invalidate;
      NotifyPaletteChange;
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.btnLoadClick(Sender: TObject);
begin
  dlgOpen.Filter := kPaletteFilter;
  if dlgOpen.Execute then
    LoadPaletteFile(dlgOpen.FileName, False);
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.btnImportMapClick(Sender: TObject);
begin
  dlgOpen.Filter := kMapFilter;
  if dlgOpen.Execute then
    LoadPaletteFile(dlgOpen.FileName, True);
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.btnSaveClick(Sender: TObject);
var
  Lines: TStringList;
begin
  dlgSave.FileName := SanitizeFileName(FPalette.Name) + '.pal';
  if not dlgSave.Execute then
    Exit;
  Lines := TStringList.Create;
  try
    FPalette.SaveToStrings(Lines);
    try
      Lines.SaveToFile(dlgSave.FileName, TEncoding.UTF8);
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TPaletteEditorForm.NotifyPaletteChange;
begin
  if Assigned(FOnPaletteChange) then
    FOnPaletteChange(Self);
end;

end.
