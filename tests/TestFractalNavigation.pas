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
    procedure ViewChanged(Sender: TObject; const Change: TViewChange);
    procedure PrecisionLimit(Sender: TObject);
    procedure JuliaPoint(Sender: TObject; const P: TComplexPoint);
    procedure HistoryChanged(Sender: TObject);
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
    procedure TestResizeKeepsWidthWithoutHistory;
    procedure TestKeyPanMovesByTenthOfWidth;
    procedure TestJuliaModeReportsPoint;
    procedure TestHistoryCapacity;
    procedure TestHistoryChangeReportedAfterDragPan;
    procedure TestHistoryChangeReportedAfterKeyPan;
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
  FNavigator.Reset(MakeViewport(0, 0, 4, 400, 300));
  FChangeCount := 0;
  FIsLimitHit := False;
  FJuliaCount := 0;
  FHistoryChangeCount := 0;
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

initialization
  RegisterTest(TTestNavigator.Suite);

end.
