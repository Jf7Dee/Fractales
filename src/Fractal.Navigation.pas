unit Fractal.Navigation;

interface

uses
  Types, SysUtils, Classes, Math, Fractal.Types;

const
  kWheelZoomFactor = 1.25;
  kWheelDeltaUnit = 120;
  kMinSelectionPixels = 4;
  kHistoryCapacity = 200;
  kKeyPanDivisor = 10;
  kPinchMaxFactor = 16;     // borne d'un seul pincement, contre les gestes parasites
  kPinchMinChange = 0.02;   // en deçà, le pincement est ignoré (doigts posés sans intention de zoomer)

type
  TNavButton = (nbLeft, nbRight, nbMiddle);
  TViewChangeKind = (vckReset, vckPan);

  TViewChange = record
    Kind: TViewChangeKind;
    DX, DY: Integer;  // vckPan : déplacement du contenu en pixels entiers
  end;

  TViewChangedEvent = procedure(Sender: TObject; const Change: TViewChange) of object;
  TComplexPointEvent = procedure(Sender: TObject; const P: TComplexPoint) of object;
  // Factor = 1 : plus d'aperçu, l'image normale est affichée
  TZoomPreviewEvent = procedure(Sender: TObject; X, Y: Integer; Factor: TFloat) of object;

  TViewHistory = class
  private
    FItems: array of TViewport;
    FCount: Integer;
    FIndex: Integer;
  public
    constructor Create;
    procedure Clear;
    procedure Push(const V: TViewport);
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    function Back: TViewport;
    function Forward: TViewport;
    property Count: Integer read FCount;
  end;

  TNavigator = class;

  TNavigationMode = class
  private
    FNavigator: TNavigator;
  public
    constructor Create(ANavigator: TNavigator); virtual;
    class function DisplayName: string; virtual; abstract;
    procedure MouseDown(Button: TNavButton; X, Y: Integer); virtual;
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean); virtual;
    procedure MouseUp(Button: TNavButton; X, Y: Integer); virtual;
    procedure MouseWheel(WheelDelta, X, Y: Integer); virtual;
    property Navigator: TNavigator read FNavigator;
  end;

  TNavigationModeClass = class of TNavigationMode;

  TFreeNavigationMode = class(TNavigationMode)
  private
    FIsDragging: Boolean;
    FHasMoved: Boolean;
    FLastX: Integer;
    FLastY: Integer;
  public
    class function DisplayName: string; override;
    procedure MouseDown(Button: TNavButton; X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean); override;
    procedure MouseUp(Button: TNavButton; X, Y: Integer); override;
    procedure MouseWheel(WheelDelta, X, Y: Integer); override;
  end;

  TJuliaNavigationMode = class(TFreeNavigationMode)
  public
    class function DisplayName: string; override;
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean); override;
  end;

  TNavigator = class
  private
    FViewport: TViewport;
    FEpsilon: TFloat;
    FHistory: TViewHistory;
    FMode: TNavigationMode;
    FIsSelecting: Boolean;
    FSelStart: TPoint;
    FSelEnd: TPoint;
    FOnViewChanged: TViewChangedEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOnPrecisionLimit: TNotifyEvent;
    FOnJuliaPoint: TComplexPointEvent;
    FOnHistoryChanged: TNotifyEvent;
    FOnZoomPreview: TZoomPreviewEvent;
    FIsGesturePanning: Boolean;
    FHasGestureMoved: Boolean;
    FGestureLast: TPoint;
    FIsPinching: Boolean;
    FPinchCenter: TPoint;
    FPinchStartDistance: Integer;
    procedure DoViewChanged(Kind: TViewChangeKind; DX, DY: Integer);
    procedure DoSelectionChanged;
    procedure DoHistoryChanged;
    procedure DoZoomPreview(Factor: TFloat);
    function TryCommit(const V: TViewport): Boolean;
    function ConstrainedEnd(X, Y: Integer): TPoint;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMode(AModeClass: TNavigationModeClass);
    procedure Reset(const V: TViewport);
    procedure SetPixelSize(AWidth, AHeight: Integer);
    procedure MouseDown(Button: TNavButton; X, Y: Integer);
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean);
    procedure MouseUp(Button: TNavButton; X, Y: Integer);
    procedure MouseWheel(WheelDelta, X, Y: Integer);
    procedure CancelSelection;
    function HasSelection: Boolean;
    function SelectionRect: TRect;
    procedure ZoomAt(X, Y, Factor: TFloat);
    procedure ZoomCenter(Factor: TFloat);
    procedure PanBy(DX, DY: Integer);
    procedure KeyPan(DirX, DirY: Integer);
    procedure GoToView(const V: TViewport);
    procedure PanGesture(X, Y: Integer; IsBegin, IsEnd: Boolean);
    procedure PinchGesture(X, Y, Distance: Integer; IsBegin, IsEnd: Boolean);
    procedure CommitHistory;
    procedure GoBack;
    procedure GoForward;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    procedure NotifyJuliaPoint(X, Y: Integer);
    property Viewport: TViewport read FViewport;
    property Mode: TNavigationMode read FMode;
    // ulp relatif du noyau de calcul courant : fixe la limite de zoom
    property Epsilon: TFloat read FEpsilon write FEpsilon;
    property History: TViewHistory read FHistory;
    property OnViewChanged: TViewChangedEvent read FOnViewChanged write FOnViewChanged;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property OnPrecisionLimit: TNotifyEvent read FOnPrecisionLimit write FOnPrecisionLimit;
    property OnJuliaPoint: TComplexPointEvent read FOnJuliaPoint write FOnJuliaPoint;
    // toute modification de l'historique (ajout, recul, avance, remise à zéro) : état de Précédent / Suivant
    property OnHistoryChanged: TNotifyEvent read FOnHistoryChanged write FOnHistoryChanged;
    // pincement en cours : agrandir l'image affichée autour de (X, Y), sans recalcul
    property OnZoomPreview: TZoomPreviewEvent read FOnZoomPreview write FOnZoomPreview;
  end;

const
  kNavigationModes: array[0..1] of TNavigationModeClass = (TFreeNavigationMode, TJuliaNavigationMode);

function PinchZoomFactor(StartDistance, Distance: Integer): TFloat;
function ZoomPreviewRect(Width, Height, X, Y: Integer; Factor: TFloat): TRect;

implementation

{------------------------------------------------------------------------------}

constructor TViewHistory.Create;
begin
  inherited Create;
  Clear;
end;

{------------------------------------------------------------------------------}

procedure TViewHistory.Clear;
begin
  FCount := 0;
  FIndex := -1;
end;

{------------------------------------------------------------------------------}

procedure TViewHistory.Push(const V: TViewport);
var
  I: Integer;
begin
  FCount := FIndex + 1;  // une nouvelle vue efface l'avenir
  if FCount >= kHistoryCapacity then
  begin
    for I := 0 to FCount - 2 do
      FItems[I] := FItems[I + 1];
    Dec(FCount);
  end;
  if Length(FItems) <= FCount then
    SetLength(FItems, FCount + 16);
  FItems[FCount] := V;
  Inc(FCount);
  FIndex := FCount - 1;
end;

{------------------------------------------------------------------------------}

function TViewHistory.CanGoBack: Boolean;
begin
  Result := FIndex > 0;
end;

{------------------------------------------------------------------------------}

function TViewHistory.CanGoForward: Boolean;
begin
  Result := FIndex < FCount - 1;
end;

{------------------------------------------------------------------------------}

function TViewHistory.Back: TViewport;
begin
  Dec(FIndex);
  Result := FItems[FIndex];
end;

{------------------------------------------------------------------------------}

function TViewHistory.Forward: TViewport;
begin
  Inc(FIndex);
  Result := FItems[FIndex];
end;

{------------------------------------------------------------------------------}

constructor TNavigationMode.Create(ANavigator: TNavigator);
begin
  inherited Create;
  FNavigator := ANavigator;
end;

{------------------------------------------------------------------------------}

procedure TNavigationMode.MouseDown(Button: TNavButton; X, Y: Integer);
begin
end;

{------------------------------------------------------------------------------}

procedure TNavigationMode.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
end;

{------------------------------------------------------------------------------}

procedure TNavigationMode.MouseUp(Button: TNavButton; X, Y: Integer);
begin
end;

{------------------------------------------------------------------------------}

procedure TNavigationMode.MouseWheel(WheelDelta, X, Y: Integer);
begin
end;

{------------------------------------------------------------------------------}

class function TFreeNavigationMode.DisplayName: string;
begin
  Result := 'Libre';
end;

{------------------------------------------------------------------------------}

procedure TFreeNavigationMode.MouseDown(Button: TNavButton; X, Y: Integer);
begin
  if Button <> nbLeft then
    Exit;
  FIsDragging := True;
  FHasMoved := False;
  FLastX := X;
  FLastY := Y;
end;

{------------------------------------------------------------------------------}

procedure TFreeNavigationMode.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
  if not (FIsDragging and IsLeftDown) then
    Exit;
  if (X = FLastX) and (Y = FLastY) then
    Exit;
  Navigator.PanBy(X - FLastX, Y - FLastY);
  FLastX := X;
  FLastY := Y;
  FHasMoved := True;
end;

{------------------------------------------------------------------------------}

procedure TFreeNavigationMode.MouseUp(Button: TNavButton; X, Y: Integer);
begin
  if (Button <> nbLeft) or not FIsDragging then
    Exit;
  FIsDragging := False;
  if FHasMoved then
    Navigator.CommitHistory;
end;

{------------------------------------------------------------------------------}

procedure TFreeNavigationMode.MouseWheel(WheelDelta, X, Y: Integer);
begin
  Navigator.ZoomAt(X, Y, Power(kWheelZoomFactor, WheelDelta / kWheelDeltaUnit));
end;

{------------------------------------------------------------------------------}

class function TJuliaNavigationMode.DisplayName: string;
begin
  Result := 'Aperçu Julia';
end;

{------------------------------------------------------------------------------}

procedure TJuliaNavigationMode.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
  inherited MouseMove(X, Y, IsLeftDown);
  Navigator.NotifyJuliaPoint(X, Y);
end;

{------------------------------------------------------------------------------}

constructor TNavigator.Create;
begin
  inherited Create;
  FHistory := TViewHistory.Create;
  FMode := TFreeNavigationMode.Create(Self);
  FViewport := MakeViewport(0, 0, kDefaultWidth, 1, 1);
  FEpsilon := kExtendedEpsilon;
end;

{------------------------------------------------------------------------------}

destructor TNavigator.Destroy;
begin
  FMode.Free;
  FHistory.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.DoViewChanged(Kind: TViewChangeKind; DX, DY: Integer);
var
  Change: TViewChange;
begin
  Change.Kind := Kind;
  Change.DX := DX;
  Change.DY := DY;
  if Assigned(FOnViewChanged) then
    FOnViewChanged(Self, Change);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.DoSelectionChanged;
begin
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.DoHistoryChanged;
begin
  if Assigned(FOnHistoryChanged) then
    FOnHistoryChanged(Self);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.DoZoomPreview(Factor: TFloat);
begin
  if Assigned(FOnZoomPreview) then
    FOnZoomPreview(Self, FPinchCenter.X, FPinchCenter.Y, Factor);
end;

{------------------------------------------------------------------------------}

function TNavigator.TryCommit(const V: TViewport): Boolean;
begin
  if V.PrecisionState(FEpsilon) = psLimit then
  begin
    if Assigned(FOnPrecisionLimit) then
      FOnPrecisionLimit(Self);
    Exit(False);
  end;
  FViewport := V;
  FHistory.Push(V);
  DoViewChanged(vckReset, 0, 0);
  DoHistoryChanged;
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.SetMode(AModeClass: TNavigationModeClass);
begin
  FMode.Free;
  FMode := AModeClass.Create(Self);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.Reset(const V: TViewport);
begin
  FViewport := V;
  FHistory.Clear;
  FHistory.Push(V);
  DoViewChanged(vckReset, 0, 0);
  DoHistoryChanged;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.SetPixelSize(AWidth, AHeight: Integer);
var
  V: TViewport;
begin
  V := FViewport.Resized(AWidth, AHeight);
  if (V.PixelWidth = FViewport.PixelWidth) and (V.PixelHeight = FViewport.PixelHeight) then
    Exit;
  FViewport := V;
  DoViewChanged(vckReset, 0, 0);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.MouseDown(Button: TNavButton; X, Y: Integer);
begin
  if Button = nbRight then
  begin
    FIsSelecting := True;
    FSelStart := Point(X, Y);
    FSelEnd := FSelStart;
    DoSelectionChanged;
  end
  else
    FMode.MouseDown(Button, X, Y);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
  if FIsSelecting then
  begin
    FSelEnd := ConstrainedEnd(X, Y);
    DoSelectionChanged;
  end
  else
    FMode.MouseMove(X, Y, IsLeftDown);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.MouseUp(Button: TNavButton; X, Y: Integer);
var
  R: TRect;
begin
  if Button = nbRight then
  begin
    if not FIsSelecting then
      Exit;
    FIsSelecting := False;
    DoSelectionChanged;
    R := SelectionRect;
    if R.Right - R.Left >= kMinSelectionPixels then
      TryCommit(FViewport.FittedToRect(R.Left, R.Top, R.Right, R.Bottom));
  end
  else
    FMode.MouseUp(Button, X, Y);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.MouseWheel(WheelDelta, X, Y: Integer);
begin
  FMode.MouseWheel(WheelDelta, X, Y);
end;

{------------------------------------------------------------------------------}

function TNavigator.ConstrainedEnd(X, Y: Integer): TPoint;
var
  DX, DY, W, H: Integer;
  Ratio: Double;
begin
  // rectangle contraint au rapport largeur/hauteur de la vue, pour ne pas déformer l'image
  DX := X - FSelStart.X;
  DY := Y - FSelStart.Y;
  Ratio := FViewport.PixelWidth / FViewport.PixelHeight;
  if Abs(DX) >= Abs(DY) * Ratio then
  begin
    W := Abs(DX);
    H := Round(W / Ratio);
  end
  else
  begin
    H := Abs(DY);
    W := Round(H * Ratio);
  end;
  if DX >= 0 then
    Result.X := FSelStart.X + W
  else
    Result.X := FSelStart.X - W;
  if DY >= 0 then
    Result.Y := FSelStart.Y + H
  else
    Result.Y := FSelStart.Y - H;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.CancelSelection;
begin
  if not FIsSelecting then
    Exit;
  FIsSelecting := False;
  DoSelectionChanged;
end;

{------------------------------------------------------------------------------}

function TNavigator.HasSelection: Boolean;
begin
  Result := FIsSelecting;
end;

{------------------------------------------------------------------------------}

function TNavigator.SelectionRect: TRect;
begin
  Result := Rect(Min(FSelStart.X, FSelEnd.X), Min(FSelStart.Y, FSelEnd.Y), Max(FSelStart.X, FSelEnd.X),
    Max(FSelStart.Y, FSelEnd.Y));
end;

{------------------------------------------------------------------------------}

procedure TNavigator.ZoomAt(X, Y, Factor: TFloat);
begin
  TryCommit(FViewport.ZoomedAt(X, Y, Factor));
end;

{------------------------------------------------------------------------------}

procedure TNavigator.ZoomCenter(Factor: TFloat);
begin
  ZoomAt(FViewport.PixelWidth / 2 - 0.5, FViewport.PixelHeight / 2 - 0.5, Factor);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.PanBy(DX, DY: Integer);
begin
  FViewport := FViewport.Panned(DX, DY);
  DoViewChanged(vckPan, DX, DY);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.KeyPan(DirX, DirY: Integer);
var
  Step: Integer;
begin
  // flèche à droite = regarder à droite = le contenu part vers la gauche
  Step := Max(1, FViewport.PixelWidth div kKeyPanDivisor);
  PanBy(-DirX * Step, -DirY * Step);
  CommitHistory;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.GoToView(const V: TViewport);
begin
  // nouvelle vue ajoutée à l'historique, comme un zoom : Précédent y revient. Taille en pixels conservée.
  // La vue déjà affichée est ignorée : un second clic n'ajoute pas de doublon à l'historique.
  if (V.CenterX = FViewport.CenterX) and (V.CenterY = FViewport.CenterY) and (V.Width = FViewport.Width) then
    Exit;
  TryCommit(V.Resized(FViewport.PixelWidth, FViewport.PixelHeight));
end;

{------------------------------------------------------------------------------}

procedure TNavigator.PanGesture(X, Y: Integer; IsBegin, IsEnd: Boolean);
begin
  // glisser à un doigt : même effet que le glisser à la souris, une entrée d'historique par geste
  if IsBegin then
  begin
    FIsGesturePanning := True;
    FHasGestureMoved := False;
    FGestureLast := Point(X, Y);
  end;
  if not FIsGesturePanning then
    Exit;  // suite d'un geste dont le début n'a pas été reçu
  if (X <> FGestureLast.X) or (Y <> FGestureLast.Y) then
  begin
    PanBy(X - FGestureLast.X, Y - FGestureLast.Y);
    FGestureLast := Point(X, Y);
    FHasGestureMoved := True;
  end;
  if IsEnd then
  begin
    FIsGesturePanning := False;
    if FHasGestureMoved then
      CommitHistory;
  end;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.PinchGesture(X, Y, Distance: Integer; IsBegin, IsEnd: Boolean);
var
  Factor: TFloat;
begin
  // pincement : aperçu étiré pendant le geste, un seul zoom (calcul + historique) à la fin,
  // centré sur le point situé entre les doigts au début du geste
  if IsBegin then
  begin
    FIsPinching := True;
    FPinchCenter := Point(X, Y);
    FPinchStartDistance := Distance;
  end;
  if not FIsPinching then
    Exit;  // suite d'un geste dont le début n'a pas été reçu
  Factor := PinchZoomFactor(FPinchStartDistance, Distance);
  if not IsEnd then
  begin
    DoZoomPreview(Factor);
    Exit;
  end;
  FIsPinching := False;
  DoZoomPreview(1);
  if Abs(Factor - 1) >= kPinchMinChange then
    ZoomAt(FPinchCenter.X, FPinchCenter.Y, Factor);
end;

{------------------------------------------------------------------------------}

procedure TNavigator.CommitHistory;
begin
  FHistory.Push(FViewport);
  DoHistoryChanged;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.GoBack;
begin
  if not FHistory.CanGoBack then
    Exit;
  FViewport := FHistory.Back.Resized(FViewport.PixelWidth, FViewport.PixelHeight);
  DoViewChanged(vckReset, 0, 0);
  DoHistoryChanged;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.GoForward;
begin
  if not FHistory.CanGoForward then
    Exit;
  FViewport := FHistory.Forward.Resized(FViewport.PixelWidth, FViewport.PixelHeight);
  DoViewChanged(vckReset, 0, 0);
  DoHistoryChanged;
end;

{------------------------------------------------------------------------------}

function TNavigator.CanGoBack: Boolean;
begin
  Result := FHistory.CanGoBack;
end;

{------------------------------------------------------------------------------}

function TNavigator.CanGoForward: Boolean;
begin
  Result := FHistory.CanGoForward;
end;

{------------------------------------------------------------------------------}

procedure TNavigator.NotifyJuliaPoint(X, Y: Integer);
begin
  if Assigned(FOnJuliaPoint) then
    FOnJuliaPoint(Self, FViewport.PixelToComplex(X, Y));
end;

{------------------------------------------------------------------------------}

function PinchZoomFactor(StartDistance, Distance: Integer): TFloat;
begin
  // doigts qui s'écartent = grossissement ; distance invalide = aucun zoom
  if (StartDistance <= 0) or (Distance <= 0) then
    Exit(1);
  Result := EnsureRange(Distance / StartDistance, 1 / kPinchMaxFactor, kPinchMaxFactor);
end;

{------------------------------------------------------------------------------}

function ZoomPreviewRect(Width, Height, X, Y: Integer; Factor: TFloat): TRect;
begin
  // image entière étirée de Factor autour de (X, Y), qui reste immobile comme dans TViewport.ZoomedAt
  Result := Rect(Round(X - X * Factor), Round(Y - Y * Factor),
    Round(X + (Width - X) * Factor), Round(Y + (Height - Y) * Factor));
end;

end.
