unit TestFractalVideo;

interface

uses
  SysUtils, Math, TestFramework, Fractal.HighFloat, Fractal.Types, Fractal.VideoPath;

type
  TTestVideoPath = class(TTestCase)
  private
    function Pose(const X, Y: string; Width: TFloat): TCameraPose;
    function Shifted(const P: TCameraPose; DX, DY, Width: TFloat): TCameraPose;
    procedure CheckSamePose(const Expected, Actual: TCameraPose; const Msg: string);
  published
    procedure TestPoseEndsAreExact;
    procedure TestFlyoverZoomsOutBetweenFarSteps;
    procedure TestFlyoverIsContinuous;
    procedure TestLateralKeepsDepth;
    procedure TestSameStepIsStill;
    procedure TestPureZoom;
    procedure TestEaseInOut;
    procedure TestLateralSpeed;
    procedure TestSuggestedTravelBounds;
  end;

implementation

const
  kDeepX = '-1.7497219321511873028716437163845234092736412895523871602987456123450123';
  kDeepY = '0.0359184017366402873318741290014429910282311173400051209836671520390411';
  kWords = 10;

{------------------------------------------------------------------------------}

function TTestVideoPath.Pose(const X, Y: string; Width: TFloat): TCameraPose;
begin
  CheckTrue(THighFloat.TryParse(X, kWords, Result.CenterX), X);
  CheckTrue(THighFloat.TryParse(Y, kWords, Result.CenterY), Y);
  Result.Width := Width;
end;

{------------------------------------------------------------------------------}

function TTestVideoPath.Shifted(const P: TCameraPose; DX, DY, Width: TFloat): TCameraPose;
begin
  Result.CenterX := P.CenterX.AddFloat(DX, kWords);
  Result.CenterY := P.CenterY.AddFloat(DY, kWords);
  Result.Width := Width;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.CheckSamePose(const Expected, Actual: TCameraPose; const Msg: string);
begin
  CheckTrue(Expected.CenterX.IsEqual(Actual.CenterX), Msg + ' : X');
  CheckTrue(Expected.CenterY.IsEqual(Actual.CenterY), Msg + ' : Y');
  CheckEquals(Expected.Width, Actual.Width, 0, Msg + ' : largeur');
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestPoseEndsAreExact;
var
  A, B: TCameraPose;
  M: TVideoMoveMode;
begin
  A := Pose(kDeepX, kDeepY, 1e-13);
  B := Shifted(A, 0.3, 0, 1e-12);
  for M := Low(TVideoMoveMode) to High(TVideoMoveMode) do
  begin
    CheckSamePose(A, PoseBetween(A, B, M, 0), 'début');
    CheckSamePose(B, PoseBetween(A, B, M, 1), 'fin');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestFlyoverZoomsOutBetweenFarSteps;
var
  A, B: TCameraPose;
begin
  A := Pose('0', '0', 1e-6);
  B := Shifted(A, 1, 0, 1e-6);
  CheckTrue(PoseBetween(A, B, vmFlyover, 0.5).Width > 1);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestFlyoverIsContinuous;
var
  A, B, P, Q: TCameraPose;
  I: Integer;
  Step: TFloat;
begin
  // en zoom profond, deux images voisines ne s'écartent jamais de plus d'une fraction de leur largeur,
  // y compris au passage de la moitié du trajet (où le calcul change de bout)
  A := Pose(kDeepX, kDeepY, 1e-13);
  B := Shifted(A, 0.3, 0.1, 1e-12);
  P := A;
  for I := 1 to 3000 do
  begin
    Q := PoseBetween(A, B, vmFlyover, I / 3000);
    Step := Hypot(Q.CenterX.Sub(P.CenterX).ToFloat, Q.CenterY.Sub(P.CenterY).ToFloat);
    CheckTrue(Step < 0.5 * Max(P.Width, Q.Width), Format('image %d : pas %g, largeur %g', [I, Step, Q.Width]));
    CheckTrue(Abs(Ln(Q.Width / P.Width)) < 0.5, Format('image %d : saut de largeur', [I]));
    P := Q;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestLateralKeepsDepth;
var
  A, B, P: TCameraPose;
begin
  A := Pose('0', '0', 0.004);
  B := Shifted(A, 0.01, 0, 0.004);
  CheckEquals(0.004, PoseBetween(A, B, vmLateral, 0.25).Width, 1e-12);
  CheckEquals(0.004, PoseBetween(A, B, vmLateral, 0.75).Width, 1e-12);
  P := PoseBetween(A, B, vmLateral, 0.5);
  CheckEquals(0.004, P.Width, 1e-12);
  CheckEquals(0.005, P.CenterX.ToFloat, 1e-12);
  CheckEquals(0, P.CenterY.ToFloat, 1e-12);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestSameStepIsStill;
var
  A: TCameraPose;
  M: TVideoMoveMode;
begin
  A := Pose(kDeepX, kDeepY, 1e-13);
  for M := Low(TVideoMoveMode) to High(TVideoMoveMode) do
  begin
    CheckSamePose(A, PoseBetween(A, A, M, 0), 'début');
    CheckEquals(A.Width, PoseBetween(A, A, M, 0.5).Width, 1e-25);
    CheckEquals(0, PoseBetween(A, A, M, 0.5).CenterX.Sub(A.CenterX).ToFloat, 1e-25);
    CheckSamePose(A, PoseBetween(A, A, M, 1), 'fin');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestPureZoom;
var
  A, B, P: TCameraPose;
begin
  A := Pose('-0.75', '0.1', 1);
  B := Pose('-0.75', '0.1', 1e-10);
  P := PoseBetween(A, B, vmFlyover, 0.5);
  CheckEquals(1e-5, P.Width, 1e-7);
  CheckEquals(0, P.CenterX.Sub(A.CenterX).ToFloat, 1e-20);
  CheckEquals(0, P.CenterY.Sub(A.CenterY).ToFloat, 1e-20);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestEaseInOut;
var
  I: Integer;
begin
  CheckEquals(0, EaseInOut(0), 0);
  CheckEquals(1, EaseInOut(1), 1e-15);
  CheckEquals(0.5, EaseInOut(0.5), 1e-15);
  for I := 1 to 10 do
    CheckTrue(EaseInOut(I / 10) > EaseInOut((I - 1) / 10));
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestLateralSpeed;
var
  A, B: TCameraPose;
begin
  A := Pose('0', '0', 0.01);
  B := Shifted(A, 0.04, 0, 0.01);
  CheckEquals(2.0, LateralScreensPerSecond(A, B, 2), 1e-12);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestSuggestedTravelBounds;
var
  A, B: TCameraPose;
begin
  A := Pose('0', '0', 1e-6);
  B := Shifted(A, 1, 0, 1e-6);
  CheckEquals(kMaxTravelSeconds, SuggestedTravelSeconds(A, B, vmLateral), 0);
  CheckTrue(SuggestedTravelSeconds(A, B, vmFlyover) > kMinTravelSeconds);
  CheckEquals(kMinTravelSeconds, SuggestedTravelSeconds(A, A, vmFlyover), 0);
end;

initialization
  RegisterTest(TTestVideoPath.Suite);

end.
