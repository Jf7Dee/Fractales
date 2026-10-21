unit TestFractalTypes;

interface

uses
  TestFramework, Fractal.Types, Fractal.HighFloat;

type
  TTestViewport = class(TTestCase)
  private
    function StandardViewport: TViewport;
  published
    procedure TestPixelToComplexCenterAndCorner;
    procedure TestComplexToPixelRoundTrip;
    procedure TestZoomedAtKeepsPointFixed;
    procedure TestPannedMovesContent;
    procedure TestFittedToRect;
    procedure TestSubViewportMatchesFullPixels;
    procedure TestDeepZoomKeepsPointFixed;
    procedure TestViewportCopiesAreIndependent;
    procedure TestHugeWidthKeepsCenterBounded;
    procedure TestMakeViewportClampsBadCenters;
    procedure TestOnePixelViewportKeepsDefaultCenter;
    procedure TestPrecisionState;
    procedure TestPrecisionStateWithDoubleEpsilon;
    procedure TestDeepPrecisionState;
    procedure TestAutoMaxIter;
    procedure TestInvariantFloatRoundTrip;
  end;

implementation

uses
  SysUtils, Math;

const
  kEps = 1e-12;

{------------------------------------------------------------------------------}

function TTestViewport.StandardViewport: TViewport;
begin
  Result := MakeViewport(0, 0, 4, 400, 300);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestPixelToComplexCenterAndCorner;
var
  V: TViewport;
  P: TComplexPoint;
begin
  V := StandardViewport;
  P := V.PixelToComplex(199.5, 149.5);
  CheckEquals(0.0, P.X, kEps);
  CheckEquals(0.0, P.Y, kEps);
  P := V.PixelToComplex(0, 0);
  CheckEquals(-1.995, P.X, kEps);
  CheckEquals(1.495, P.Y, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestComplexToPixelRoundTrip;
var
  V: TViewport;
  Q: TComplexPoint;
begin
  V := StandardViewport;
  Q := V.ComplexToPixel(V.PixelToComplex(123, 45));
  CheckEquals(123.0, Q.X, 1e-9);
  CheckEquals(45.0, Q.Y, 1e-9);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestZoomedAtKeepsPointFixed;
var
  V, W: TViewport;
  P, Q: TComplexPoint;
begin
  V := StandardViewport;
  P := V.PixelToComplex(50, 70);
  W := V.ZoomedAt(50, 70, 3);
  Q := W.PixelToComplex(50, 70);
  CheckEquals(P.X, Q.X, kEps);
  CheckEquals(P.Y, Q.Y, kEps);
  CheckEquals(4 / 3, W.Width, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestPannedMovesContent;
var
  V, W: TViewport;
  P, Q: TComplexPoint;
begin
  V := StandardViewport;
  W := V.Panned(10, -5);
  P := V.PixelToComplex(100, 100);
  Q := W.PixelToComplex(110, 95);
  CheckEquals(P.X, Q.X, kEps);
  CheckEquals(P.Y, Q.Y, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestFittedToRect;
var
  W: TViewport;
begin
  W := StandardViewport.FittedToRect(100, 75, 300, 225);
  CheckEquals(0.0, W.CenterX, kEps);
  CheckEquals(0.0, W.CenterY, kEps);
  CheckEquals(2.0, W.Width, kEps);
  W := StandardViewport.FittedToRect(300, 225, 100, 75);
  CheckEquals(0.0, W.CenterX, kEps);
  CheckEquals(2.0, W.Width, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestSubViewportMatchesFullPixels;
var
  V, S: TViewport;
  A, B, C, D, Full: TComplexPoint;
begin
  V := StandardViewport;
  S := V.SubViewport(2, 10, 4);
  CheckEquals(800, S.PixelWidth);
  CheckEquals(8, S.PixelHeight);
  // le pixel (7, 11) de l'image finale = sous-pixels colonnes 14-15, lignes 2-3 de la bande
  A := S.PixelToComplex(14, 2);
  B := S.PixelToComplex(15, 2);
  C := S.PixelToComplex(14, 3);
  D := S.PixelToComplex(15, 3);
  Full := V.PixelToComplex(7, 11);
  CheckEquals(Full.X, (A.X + B.X + C.X + D.X) / 4, kEps);
  CheckEquals(Full.Y, (A.Y + B.Y + C.Y + D.Y) / 4, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestDeepZoomKeepsPointFixed;
const
  kPX = 613;
  kPY = 211;
  kZoomCount = 70;
  kWords = 8;
var
  V: TViewport;
  I: Integer;
  O: TComplexPoint;
  PX, PY, QX, QY: THighFloat;
begin
  V := MakeViewport(-0.75, 0.1, 4, 800, 600);
  O := V.PixelOffset(kPX, kPY);
  PX := V.ExactCenterX.AddFloat(O.X, kWords);
  PY := V.ExactCenterY.AddFloat(O.Y, kWords);
  for I := 1 to kZoomCount do
    V := V.ZoomedAt(kPX, kPY, 2);
  O := V.PixelOffset(kPX, kPY);
  QX := V.ExactCenterX.AddFloat(O.X, kWords);
  QY := V.ExactCenterY.AddFloat(O.Y, kWords);
  CheckTrue(Abs(QX.Sub(PX).ToFloat) < V.PixelSize, 'X');
  CheckTrue(Abs(QY.Sub(PY).ToFloat) < V.PixelSize, 'Y');
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestViewportCopiesAreIndependent;
var
  A, B: TViewport;
  X0: THighFloat;
begin
  A := MakeViewport(-0.75, 0.1, 4, 800, 600);
  B := A;
  X0 := B.ExactCenterX;
  A := A.Panned(5, 0);
  CheckTrue(B.ExactCenterX.IsEqual(X0), 'B garde son centre exact');
  CheckFalse(A.ExactCenterX.IsEqual(X0), 'A a bougé');
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestHugeWidthKeepsCenterBounded;
var
  V: TViewport;
begin
  V := MakeViewport(0.5, 0.1, 1e12, 800, 600);
  V := V.Panned(500, -300);
  CheckTrue(Abs(V.CenterX) <= kMaxCenterCoordinate, 'Panned X');
  CheckTrue(Abs(V.CenterY) <= kMaxCenterCoordinate, 'Panned Y');
  V := V.ZoomedAt(10, 20, 0.5);
  CheckTrue(Abs(V.CenterX) <= kMaxCenterCoordinate, 'ZoomedAt X');
  CheckTrue(Abs(V.CenterY) <= kMaxCenterCoordinate, 'ZoomedAt Y');
  V := V.FittedToRect(0, 0, 100, 100);
  CheckTrue(Abs(V.CenterX) <= kMaxCenterCoordinate, 'FittedToRect X');
  V := V.SubViewport(1, 100, 50);
  CheckTrue(Abs(V.CenterY) <= kMaxCenterCoordinate, 'SubViewport Y');
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestMakeViewportClampsBadCenters;
var
  V: TViewport;
begin
  V := MakeViewport(NaN, 1e300, 4, 100, 100);
  CheckEquals(0.0, V.CenterX, kEps);
  CheckEquals(kMaxCenterCoordinate, V.CenterY, kEps);
  V := MakeViewport(-Infinity, 0, 4, 100, 100);
  CheckEquals(-kMaxCenterCoordinate, V.CenterX, kEps);
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestOnePixelViewportKeepsDefaultCenter;
const
  kCx = -0.7436438870371587;
  kCy = 0.1318259042053119;
var
  A, B: TViewport;
begin
  A := MakeViewport(kCx, kCy, 4, 1, 1).Resized(800, 600);
  B := MakeViewport(kCx, kCy, 4, 800, 600);
  CheckTrue(A.IsSameView(B));
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestPrecisionState;
begin
  CheckEquals(Ord(psOk), Ord(StandardViewport.PrecisionState));
  CheckEquals(Ord(psWarning), Ord(MakeViewport(0.5, 0, 1e-14, 400, 300).PrecisionState));
  CheckEquals(Ord(psLimit), Ord(MakeViewport(0.5, 0, 1e-17, 400, 300).PrecisionState));
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestDeepPrecisionState;
begin
  // palier 2 : limite à 1e-300 par pixel, avertissement sous 8e-300, quel que soit le centre
  CheckEquals(Ord(psOk), Ord(MakeViewport(0.5, 0, 400e-30, 400, 300).DeepPrecisionState));
  CheckEquals(Ord(psWarning), Ord(MakeViewport(0.5, 0, 400 * 4e-300, 400, 300).DeepPrecisionState));
  CheckEquals(Ord(psLimit), Ord(MakeViewport(0.5, 0, 400e-301, 400, 300).DeepPrecisionState));
  CheckEquals(Ord(psOk), Ord(MakeViewport(2, 3, 400e-30, 400, 300).DeepPrecisionState));
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestPrecisionStateWithDoubleEpsilon;
begin
  // moteur Rust (Double) : limite par pixel 64 × 2^-52 ≈ 1,4e-14, avertissement en dessous de 1,1e-13
  CheckEquals(Ord(psOk), Ord(MakeViewport(0.5, 0, 1e-10, 400, 300).PrecisionState(kDoubleEpsilon)));
  CheckEquals(Ord(psWarning), Ord(MakeViewport(0.5, 0, 4e-11, 400, 300).PrecisionState(kDoubleEpsilon)));
  CheckEquals(Ord(psLimit), Ord(MakeViewport(0.5, 0, 1e-12, 400, 300).PrecisionState(kDoubleEpsilon)));
  CheckEquals(Ord(psOk), Ord(MakeViewport(0.5, 0, 1e-12, 400, 300).PrecisionState));
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestAutoMaxIter;
begin
  CheckEquals(250, AutoMaxIter(StandardViewport));
  CheckTrue(AutoMaxIter(MakeViewport(0, 0, 4e-8, 400, 300)) > AutoMaxIter(MakeViewport(0, 0, 4e-4, 400, 300)));
end;

{------------------------------------------------------------------------------}

procedure TTestViewport.TestInvariantFloatRoundTrip;
const
  kSampleX = -0.7436438870371587;
begin
  CheckEquals(kSampleX, InvariantToFloat(FloatToInvariant(kSampleX), 0), 1e-17);
  CheckEquals(1.5e-10, InvariantToFloat(FloatToInvariant(1.5e-10), 0), 1e-27);
  CheckEquals(7.0, InvariantToFloat('abc', 7), 0);
  CheckEquals(0, Pos(',', FloatToInvariant(0.5)));
end;

initialization
  RegisterTest(TTestViewport.Suite);

end.
