unit TestFractalNavigation;

interface

uses
  Types, SysUtils, TestFramework, Fractal.Types, Fractal.Navigation;

type
  TTestNavigator = class(TTestCase)
  private
    FNavigator: TNavigator;
    FChangeCount: Integer;
    FLastChange: TViewChange;
    FIsLimitHit: Boolean;
    FJuliaCount: Integer;
    FJuliaPoint: TComplexPoint;
    FHistoryChangeCount: Integer;
    FIsBackSeen: Boolean;
    FIsForwardSeen: Boolean;
    FPreviewCount: Integer;
    FLastPreviewFactor: TFloat;
    procedure ViewChanged(Sender: TObject; const Change: TViewChange);
    procedure PrecisionLimit(Sender: TObject);
    procedure JuliaPoint(Sender: TObject; const P: TComplexPoint);
    procedure HistoryChanged(Sender: TObject);
    procedure ZoomPreview(Sender: TObject; X, Y: Integer; Factor: TFloat);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestWheelZoomKeepsPointUnderCursor;
    procedure TestLeftDragPansWithOneHistoryEntry;
    procedure TestClickWithoutMoveAddsNoHistory;
    procedure TestRightDragSelectsConstrainedRect;
    procedure TestTinySelectionIsIgnored;
    procedure TestCancelSelection;
    procedure TestBackAndForward;
    procedure TestPrecisionLimitBlocksZoom;
    procedure TestDoubleEpsilonBlocksZoomEarlier;
    procedure TestZoomOutAllowedPastLimit;
    procedure TestResizeKeepsWidthWithoutHistory;
    procedure TestKeyPanMovesByTenthOfWidth;
    procedure TestJuliaModeReportsPoint;
    procedure TestHistoryCapacity;
    procedure TestHistoryChangeReportedAfterDragPan;
    procedure TestHistoryChangeReportedAfterKeyPan;
    procedure TestGoToViewAddsHistory;
    procedure TestGoToSameViewIsIgnored;
    procedure TestPinchZoomFactor;
    procedure TestZoomPreviewRect;
    procedure TestPinchZoomsOnceAtEnd;
    procedure TestTinyPinchIsIgnored;
    procedure TestPinchBlockedByPrecisionLimit;
    procedure TestPanGestureWithOneHistoryEntry;
    procedure TestPanGestureWithoutMoveAddsNoHistory;
    procedure TestGestureWithoutBeginIsIgnored;
  end;

implementation

const
  kEps = 1e-12;

{------------------------------------------------------------------------------}

procedure TTestNavigator.SetUp;
begin
  FNavigator := TNavigator.Create;
  FNavigator.OnViewChanged := ViewChanged;
  FNavigator.OnPrecisionLimit := PrecisionLimit;
  FNavigator.OnJuliaPoint := JuliaPoint;
  FNavigator.OnHistoryChanged := HistoryChanged;
  FNavigator.OnZoomPreview := ZoomPreview;
  FNavigator.Reset(MakeViewport(0, 0, 4, 400, 300));
  FChangeCount := 0;
  FIsLimitHit := False;
  FJuliaCount := 0;
  FHistoryChangeCount := 0;
  FPreviewCount := 0;
  FLastPreviewFactor := 0;
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TearDown;
begin
  FreeAndNil(FNavigator);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.ViewChanged(Sender: TObject; const Change: TViewChange);
begin
  Inc(FChangeCount);
  FLastChange := Change;
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.PrecisionLimit(Sender: TObject);
begin
  FIsLimitHit := True;
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.JuliaPoint(Sender: TObject; const P: TComplexPoint);
begin
  Inc(FJuliaCount);
  FJuliaPoint := P;
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.HistoryChanged(Sender: TObject);
begin
  // état relevé au moment de l'événement, comme le font les boutons Précédent / Suivant
  Inc(FHistoryChangeCount);
  FIsBackSeen := FNavigator.CanGoBack;
  FIsForwardSeen := FNavigator.CanGoForward;
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.ZoomPreview(Sender: TObject; X, Y: Integer; Factor: TFloat);
begin
  Inc(FPreviewCount);
  FLastPreviewFactor := Factor;
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestWheelZoomKeepsPointUnderCursor;
var
  P, Q: TComplexPoint;
begin
  P := FNavigator.Viewport.PixelToComplex(100, 50);
  FNavigator.MouseWheel(120, 100, 50);
  Q := FNavigator.Viewport.PixelToComplex(100, 50);
  CheckEquals(P.X, Q.X, kEps);
  CheckEquals(P.Y, Q.Y, kEps);
  CheckEquals(4 / 1.25, FNavigator.Viewport.Width, kEps);
  CheckTrue(FNavigator.CanGoBack);
  CheckEquals(Ord(vckReset), Ord(FLastChange.Kind));
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestLeftDragPansWithOneHistoryEntry;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.MouseDown(nbLeft, 100, 100);
  FNavigator.MouseMove(110, 95, True);
  CheckEquals(Ord(vckPan), Ord(FLastChange.Kind));
  CheckEquals(10, FLastChange.DX);
  CheckEquals(-5, FLastChange.DY);
  FNavigator.MouseMove(115, 95, True);
  CheckEquals(5, FLastChange.DX);
  CheckEquals(0, FLastChange.DY);
  CheckEquals(Count0, FNavigator.History.Count);
  FNavigator.MouseUp(nbLeft, 115, 95);
  CheckEquals(Count0 + 1, FNavigator.History.Count);
  CheckEquals(-0.15, FNavigator.Viewport.CenterX, kEps);
  CheckEquals(-0.05, FNavigator.Viewport.CenterY, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestClickWithoutMoveAddsNoHistory;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.MouseDown(nbLeft, 100, 100);
  FNavigator.MouseUp(nbLeft, 100, 100);
  CheckEquals(Count0, FNavigator.History.Count);
  CheckEquals(0, FChangeCount);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestRightDragSelectsConstrainedRect;
var
  R: TRect;
begin
  FNavigator.MouseDown(nbRight, 100, 75);
  FNavigator.MouseMove(300, 100, False);
  CheckTrue(FNavigator.HasSelection);
  R := FNavigator.SelectionRect;
  CheckEquals(100, R.Left);
  CheckEquals(75, R.Top);
  CheckEquals(300, R.Right);
  CheckEquals(225, R.Bottom);
  FNavigator.MouseUp(nbRight, 300, 100);
  CheckFalse(FNavigator.HasSelection);
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  CheckEquals(0.0, FNavigator.Viewport.CenterX, kEps);
  CheckEquals(0.0, FNavigator.Viewport.CenterY, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestTinySelectionIsIgnored;
begin
  FNavigator.MouseDown(nbRight, 100, 100);
  FNavigator.MouseMove(102, 101, False);
  FNavigator.MouseUp(nbRight, 102, 101);
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
  CheckFalse(FNavigator.CanGoBack);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestCancelSelection;
begin
  FNavigator.MouseDown(nbRight, 100, 75);
  FNavigator.MouseMove(300, 100, False);
  FNavigator.CancelSelection;
  CheckFalse(FNavigator.HasSelection);
  FNavigator.MouseUp(nbRight, 300, 100);
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestBackAndForward;
begin
  FNavigator.ZoomCenter(2);
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  FNavigator.GoBack;
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
  CheckTrue(FNavigator.CanGoForward);
  FNavigator.GoForward;
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  CheckFalse(FNavigator.CanGoForward);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestPrecisionLimitBlocksZoom;
begin
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-14, 400, 300));
  FNavigator.ZoomCenter(1000);
  CheckTrue(FIsLimitHit);
  CheckEquals(1e-14, FNavigator.Viewport.Width, 1e-28);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestDoubleEpsilonBlocksZoomEarlier;
begin
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-9, 400, 300));
  FNavigator.ZoomCenter(1000);
  CheckFalse(FIsLimitHit, 'Extended : zoom accepté');
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-9, 400, 300));
  FNavigator.Epsilon := kDoubleEpsilon;
  FNavigator.ZoomCenter(1000);
  CheckTrue(FIsLimitHit, 'Double : zoom bloqué');
  CheckEquals(1e-9, FNavigator.Viewport.Width, 1e-21);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestZoomOutAllowedPastLimit;
begin
  // vue déjà au-delà de la limite (passage au moteur Rust, lieu profond chargé) : on doit pouvoir en sortir
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-12, 400, 300));
  FNavigator.Epsilon := kDoubleEpsilon;
  FNavigator.ZoomCenter(0.5);
  CheckFalse(FIsLimitHit, 'zoom arrière accepté');
  CheckEquals(2e-12, FNavigator.Viewport.Width, 1e-24);
  FNavigator.PanBy(10, 0);
  CheckFalse(FIsLimitHit, 'déplacement accepté');
  FNavigator.ZoomCenter(2);
  CheckTrue(FIsLimitHit, 'zoom avant toujours bloqué');
  CheckEquals(2e-12, FNavigator.Viewport.Width, 1e-24);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestResizeKeepsWidthWithoutHistory;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.SetPixelSize(800, 600);
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
  CheckEquals(800, FNavigator.Viewport.PixelWidth);
  CheckEquals(Count0, FNavigator.History.Count);
  CheckEquals(Ord(vckReset), Ord(FLastChange.Kind));
  FNavigator.SetPixelSize(0, 0);
  CheckEquals(1, FNavigator.Viewport.PixelWidth);
  CheckEquals(1, FNavigator.Viewport.PixelHeight);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestKeyPanMovesByTenthOfWidth;
begin
  FNavigator.KeyPan(1, 0);
  CheckEquals(Ord(vckPan), Ord(FLastChange.Kind));
  CheckEquals(-40, FLastChange.DX);
  CheckEquals(0.4, FNavigator.Viewport.CenterX, kEps);
  CheckTrue(FNavigator.CanGoBack);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestJuliaModeReportsPoint;
var
  P: TComplexPoint;
begin
  FNavigator.SetMode(TJuliaNavigationMode);
  FNavigator.MouseMove(200, 150, False);
  CheckEquals(1, FJuliaCount);
  P := FNavigator.Viewport.PixelToComplex(200, 150);
  CheckEquals(P.X, FJuliaPoint.X, kEps);
  CheckEquals(P.Y, FJuliaPoint.Y, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestHistoryCapacity;
var
  I: Integer;
begin
  for I := 1 to kHistoryCapacity + 50 do
    FNavigator.ZoomCenter(1.01);
  CheckEquals(kHistoryCapacity, FNavigator.History.Count);
  CheckTrue(FNavigator.CanGoBack);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestHistoryChangeReportedAfterDragPan;
begin
  FNavigator.ZoomCenter(2);
  FNavigator.GoBack;
  CheckTrue(FIsForwardSeen, 'après Précédent');
  FHistoryChangeCount := 0;
  // le glissement enregistre l'historique après l'événement de vue : il doit être signalé lui aussi
  FNavigator.MouseDown(nbLeft, 10, 10);
  FNavigator.MouseMove(30, 30, True);
  FNavigator.MouseUp(nbLeft, 30, 30);
  CheckEquals(1, FHistoryChangeCount);
  CheckTrue(FIsBackSeen, 'Précédent possible');
  CheckFalse(FIsForwardSeen, 'avenir effacé');
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestHistoryChangeReportedAfterKeyPan;
begin
  CheckFalse(FNavigator.CanGoBack);
  FNavigator.KeyPan(1, 0);
  CheckEquals(1, FHistoryChangeCount);
  CheckTrue(FIsBackSeen);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestGoToViewAddsHistory;
begin
  FNavigator.ZoomCenter(2);
  FHistoryChangeCount := 0;
  FNavigator.GoToView(MakeViewport(-0.5, 0, 3, 1, 1));
  CheckEquals(-0.5, FNavigator.Viewport.CenterX, kEps);
  CheckEquals(3.0, FNavigator.Viewport.Width, kEps);
  CheckEquals(400, FNavigator.Viewport.PixelWidth, 'taille en pixels conservée');
  CheckEquals(300, FNavigator.Viewport.PixelHeight);
  CheckEquals(3, FNavigator.History.Count);
  CheckEquals(1, FHistoryChangeCount);
  CheckTrue(FIsBackSeen);
  CheckEquals(Ord(vckReset), Ord(FLastChange.Kind));
  FNavigator.GoBack;
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestGoToSameViewIsIgnored;
begin
  FNavigator.GoToView(MakeViewport(-0.5, 0, 3, 1, 1));
  FHistoryChangeCount := 0;
  FChangeCount := 0;
  // deuxième clic sur le même bouton : rien ne change, rien n'est ajouté à l'historique
  FNavigator.GoToView(MakeViewport(-0.5, 0, 3, 1, 1));
  CheckEquals(2, FNavigator.History.Count);
  CheckEquals(0, FHistoryChangeCount);
  CheckEquals(0, FChangeCount);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestPinchZoomFactor;
begin
  // doigts qui s'écartent = zoom avant, qui se rapprochent = zoom arrière
  CheckEquals(2.0, PinchZoomFactor(100, 200), kEps);
  CheckEquals(0.5, PinchZoomFactor(200, 100), kEps);
  // distance invalide : aucun zoom
  CheckEquals(1.0, PinchZoomFactor(0, 100), kEps);
  CheckEquals(1.0, PinchZoomFactor(100, 0), kEps);
  // geste parasite : facteur borné
  CheckEquals(kPinchMaxFactor, PinchZoomFactor(10, 1000), kEps);
  CheckEquals(1 / kPinchMaxFactor, PinchZoomFactor(1000, 10), kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestZoomPreviewRect;
var
  R: TRect;
begin
  // grossissement 2 autour de (100, 50) : ce point reste immobile
  R := ZoomPreviewRect(400, 300, 100, 50, 2);
  CheckEquals(-100, R.Left);
  CheckEquals(-50, R.Top);
  CheckEquals(700, R.Right);
  CheckEquals(550, R.Bottom);
  R := ZoomPreviewRect(400, 300, 100, 50, 1);
  CheckEquals(0, R.Left);
  CheckEquals(0, R.Top);
  CheckEquals(400, R.Right);
  CheckEquals(300, R.Bottom);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestPinchZoomsOnceAtEnd;
var
  Count0: Integer;
  P0, P1: TComplexPoint;
begin
  Count0 := FNavigator.History.Count;
  P0 := FNavigator.Viewport.PixelToComplex(100, 80);
  FNavigator.PinchGesture(100, 80, 100, True, False);
  FNavigator.PinchGesture(100, 80, 150, False, False);
  // pendant le geste : aperçu seulement, aucun calcul ni historique
  CheckEquals(1.5, FLastPreviewFactor, kEps);
  CheckEquals(0, FChangeCount);
  CheckEquals(Count0, FNavigator.History.Count);
  FNavigator.PinchGesture(100, 80, 200, False, True);
  // fin du geste : aperçu retiré, un seul zoom, une seule entrée d'historique
  CheckEquals(1.0, FLastPreviewFactor, kEps);
  CheckEquals(1, FChangeCount);
  CheckEquals(Count0 + 1, FNavigator.History.Count);
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  P1 := FNavigator.Viewport.PixelToComplex(100, 80);
  CheckEquals(P0.X, P1.X, kEps);
  CheckEquals(P0.Y, P1.Y, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestTinyPinchIsIgnored;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.PinchGesture(100, 80, 100, True, False);
  FNavigator.PinchGesture(100, 80, 101, False, True);
  CheckEquals(1.0, FLastPreviewFactor, kEps);
  CheckEquals(0, FChangeCount);
  CheckEquals(Count0, FNavigator.History.Count);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestPinchBlockedByPrecisionLimit;
begin
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-14, 400, 300));
  FNavigator.PinchGesture(200, 150, 100, True, False);
  FNavigator.PinchGesture(200, 150, 1000, False, True);
  CheckTrue(FIsLimitHit);
  CheckEquals(1.0, FLastPreviewFactor, kEps);
  CheckEquals(1e-14, FNavigator.Viewport.Width, 1e-28);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestPanGestureWithOneHistoryEntry;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.PanGesture(100, 100, True, False);
  FNavigator.PanGesture(110, 95, False, False);
  CheckEquals(Ord(vckPan), Ord(FLastChange.Kind));
  CheckEquals(10, FLastChange.DX);
  CheckEquals(-5, FLastChange.DY);
  CheckEquals(Count0, FNavigator.History.Count);
  FNavigator.PanGesture(115, 95, False, True);
  CheckEquals(5, FLastChange.DX);
  CheckEquals(0, FLastChange.DY);
  CheckEquals(Count0 + 1, FNavigator.History.Count);
  CheckEquals(-0.15, FNavigator.Viewport.CenterX, kEps);
  CheckEquals(-0.05, FNavigator.Viewport.CenterY, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestPanGestureWithoutMoveAddsNoHistory;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.PanGesture(100, 100, True, False);
  FNavigator.PanGesture(100, 100, False, True);
  CheckEquals(0, FChangeCount);
  CheckEquals(Count0, FNavigator.History.Count);
end;

{------------------------------------------------------------------------------}

procedure TTestNavigator.TestGestureWithoutBeginIsIgnored;
begin
  // message reçu sans son début (geste commencé ailleurs) : rien ne bouge
  FNavigator.PanGesture(120, 100, False, False);
  FNavigator.PanGesture(130, 100, False, True);
  FNavigator.PinchGesture(100, 80, 300, False, True);
  CheckEquals(0, FChangeCount);
  CheckEquals(0, FPreviewCount);
end;

initialization
  RegisterTest(TTestNavigator.Suite);

end.
