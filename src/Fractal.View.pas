unit Fractal.View;

interface

uses
  Windows, Messages, Classes, Types, Controls, Graphics, Fractal.Types, Fractal.Navigation;

const
  kJuliaMargin = 12;

type
  // Zone d'affichage : dessine le bitmap calculé, l'aperçu Julia et le rectangle de sélection.
  // Reçoit aussi les gestes tactiles (pincement, glisser à un doigt) et l'aperçu étiré du pincement.
  TFractalView = class(TCustomControl)
  private
    FBitmap: TBitmap;
    FJuliaBitmap: TBitmap;
    FIsJuliaVisible: Boolean;
    FSelection: TRect;
    FHasSelection: Boolean;
    FPreviewCenter: TPoint;
    FPreviewFactor: TFloat;
    procedure SetJuliaVisible(Value: Boolean);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure PaintZoomPreview;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetSelection(const R: TRect; IsVisible: Boolean);
    procedure SetZoomPreview(X, Y: Integer; Factor: TFloat);
    function JuliaRect: TRect;
    property Bitmap: TBitmap read FBitmap;
    property JuliaBitmap: TBitmap read FJuliaBitmap;
    property IsJuliaVisible: Boolean read FIsJuliaVisible write SetJuliaVisible;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
    property OnGesture;
  end;

implementation

{------------------------------------------------------------------------------}

constructor TFractalView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  Color := clBlack;
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf32bit;
  FJuliaBitmap := TBitmap.Create;
  FJuliaBitmap.PixelFormat := pf32bit;
  FPreviewFactor := 1;
  // gestes interactifs de Windows 7+ à deux doigts seulement : un doigt seul reste une souris pour Windows
  // (glisser = glisser gauche, appui long puis glisser = glisser droit, donc sélection)
  Touch.InteractiveGestures := [igZoom, igPan];
  Touch.InteractiveGestureOptions := [];
end;

{------------------------------------------------------------------------------}

destructor TFractalView.Destroy;
begin
  FJuliaBitmap.Free;
  FBitmap.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TFractalView.SetJuliaVisible(Value: Boolean);
begin
  if FIsJuliaVisible = Value then
    Exit;
  FIsJuliaVisible := Value;
  Invalidate;
end;

{------------------------------------------------------------------------------}

procedure TFractalView.SetSelection(const R: TRect; IsVisible: Boolean);
begin
  FSelection := R;
  FHasSelection := IsVisible;
  Invalidate;
end;

{------------------------------------------------------------------------------}

procedure TFractalView.SetZoomPreview(X, Y: Integer; Factor: TFloat);
begin
  // Factor = 1 : retour à l'affichage normal
  FPreviewCenter := Point(X, Y);
  FPreviewFactor := Factor;
  Invalidate;
end;

{------------------------------------------------------------------------------}

function TFractalView.JuliaRect: TRect;
begin
  Result := Rect(ClientWidth - FJuliaBitmap.Width - kJuliaMargin, ClientHeight - FJuliaBitmap.Height - kJuliaMargin,
    ClientWidth - kJuliaMargin, ClientHeight - kJuliaMargin);
end;

{------------------------------------------------------------------------------}

procedure TFractalView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;  // tout est repeint dans Paint : pas d'effacement, pas de scintillement
end;

{------------------------------------------------------------------------------}

procedure TFractalView.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  Message.Result := DLGC_WANTARROWS;
end;

{------------------------------------------------------------------------------}

procedure TFractalView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if CanFocus and not Focused then
    SetFocus;
  inherited MouseDown(Button, Shift, X, Y);
end;

{------------------------------------------------------------------------------}

procedure TFractalView.Paint;
var
  R: TRect;
begin
  if FPreviewFactor <> 1 then
    PaintZoomPreview
  else
  begin
    Canvas.Draw(0, 0, FBitmap);
    Canvas.Brush.Color := clBlack;
    if FBitmap.Width < ClientWidth then
      Canvas.FillRect(Rect(FBitmap.Width, 0, ClientWidth, ClientHeight));
    if FBitmap.Height < ClientHeight then
      Canvas.FillRect(Rect(0, FBitmap.Height, ClientWidth, ClientHeight));
  end;
  if FIsJuliaVisible and (FJuliaBitmap.Width > 0) then
  begin
    R := JuliaRect;
    Canvas.Draw(R.Left, R.Top, FJuliaBitmap);
    Canvas.Brush.Color := clWhite;
    Canvas.FrameRect(Rect(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1));
  end;
  if FHasSelection then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := clWhite;
    Canvas.Rectangle(FSelection);
    Canvas.Pen.Color := clBlack;
    Canvas.Rectangle(FSelection.Left + 1, FSelection.Top + 1, FSelection.Right - 1, FSelection.Bottom - 1);
    Canvas.Brush.Style := bsSolid;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalView.PaintZoomPreview;
var
  R: TRect;
begin
  // image courante étirée pendant un pincement ; le calcul n'a lieu qu'à la fin du geste
  R := ZoomPreviewRect(FBitmap.Width, FBitmap.Height, FPreviewCenter.X, FPreviewCenter.Y, FPreviewFactor);
  SetStretchBltMode(Canvas.Handle, COLORONCOLOR);  // le plus rapide : l'aperçu est redessiné à chaque mouvement
  Canvas.StretchDraw(R, FBitmap);
  // le reste en noir, sans repeindre l'image : pas de scintillement
  ExcludeClipRect(Canvas.Handle, R.Left, R.Top, R.Right, R.Bottom);
  Canvas.Brush.Color := clBlack;
  Canvas.FillRect(ClientRect);
  SelectClipRgn(Canvas.Handle, 0);
end;

end.
