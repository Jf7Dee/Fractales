unit TestFractalVideo;

interface

uses
  Windows, SysUtils, Classes, Math, TestFramework, Fractal.HighFloat, Fractal.Types, Fractal.Persistence,
  Fractal.VideoPath, Fractal.VideoScenario, Fractal.VideoEncoder, TestUtils;

type
  TTestVideoPath = class(TTestCase)
  private
    function Pose(const X, Y: string; Width: TFloat): TCameraPose;
    function Shifted(const P: TCameraPose; DX, DY, Width: TFloat): TCameraPose;
    procedure CheckSamePose(const Expected, Actual: TCameraPose; const Msg: string);
    procedure CheckContinuous(const A, B: TCameraPose; Frames: Integer);
  published
    procedure TestPoseEndsAreExact;
    procedure TestFlyoverZoomsOutBetweenFarSteps;
    procedure TestFlyoverIsContinuous;
    procedure TestDeepBurningShipDescent;
    procedure TestLateralKeepsDepth;
    procedure TestSameStepIsStill;
    procedure TestPureZoom;
    procedure TestEaseInOut;
    procedure TestLateralSpeed;
    procedure TestSuggestedTravelBounds;
  end;

  TTestVideoScenario = class(TTestCase)
  private
    function Location(const Formula, X, Y, Width: string): TFractalLocation;
    procedure Add(Scenario: TVideoScenario; const Name, Formula, X, Y, Width: string);
    function TempFile(const Name: string): string;
  published
    procedure TestFormatSizes;
    procedure TestTimeline;
    procedure TestRefusesOtherFormula;
    procedure TestSaveLoadRoundTrip;
    procedure TestLoadGarbage;
    procedure TestMoveAndDelete;
  end;

  TTestVideoEncoder = class(TTestCase)
  private
    function SystemTool(const Name: string): string;
  published
    procedure TestArguments;
    procedure TestFindFfmpeg;
    procedure TestMissingExe;
    procedure TestFailingEncoderReportsError;
  end;

implementation

const
  kDeepX = '-1.7497219321511873028716437163845234092736412895523871602987456123450123';
  kDeepY = '0.0359184017366402873318741290014429910282311173400051209836671520390411';
  kWords = 10;
  // favoris Burning Ship de JF : bord gauche en gros plan (5e-11) et « oursin » (3e-29)
  kEdgeX = '-1.99712240306470985';
  kEdgeY = '0.000000000010345977442981882';
  kEdgeWidth = 5.02824617434859796E-11;
  kUrchinX = '-1.997122403065318324623916505722918186185975901327638166826268558098248425659525415';
  kUrchinY = '0.000000000002272801529681104851361137388945192918711481697520836942869180331919921';
  kUrchinWidth = '3.07321407518908409E-29';
  kInnerX = '-1.47428203549613083';
  kInnerY = '-1.94990625370902929E-5';

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

// Deux images voisines ne s'écartent jamais de plus d'une fraction de leur largeur, y compris au passage de la
// moitié du trajet (où le calcul change de bout)
procedure TTestVideoPath.CheckContinuous(const A, B: TCameraPose; Frames: Integer);
var
  P, Q: TCameraPose;
  I: Integer;
  Step: TFloat;
begin
  P := A;
  for I := 1 to Frames do
  begin
    Q := PoseBetween(A, B, vmFlyover, I / Frames);
    Step := Hypot(Q.CenterX.Sub(P.CenterX).ToFloat, Q.CenterY.Sub(P.CenterY).ToFloat);
    CheckTrue(Step < 0.5 * Max(P.Width, Q.Width), Format('image %d : pas %g, largeur %g', [I, Step, Q.Width]));
    CheckTrue(Abs(Ln(Q.Width / P.Width)) < 0.5, Format('image %d : saut de largeur', [I]));
    P := Q;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestFlyoverIsContinuous;
var
  A: TCameraPose;
begin
  A := Pose(kDeepX, kDeepY, 1e-13);
  CheckContinuous(A, Shifted(A, 0.3, 0.1, 1e-12), 3000);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoPath.TestDeepBurningShipDescent;
var
  Edge, Urchin: TCameraPose;
begin
  // 18 ordres de grandeur de descente, avec un léger décalage : vraie descente vers l'oursin, et retour
  Edge := Pose(kEdgeX, kEdgeY, kEdgeWidth);
  Urchin := Pose(kUrchinX, kUrchinY, InvariantToFloat(kUrchinWidth, 0));
  CheckContinuous(Edge, Urchin, 3000);
  CheckContinuous(Urchin, Edge, 3000);
  CheckSamePose(Urchin, PoseBetween(Edge, Urchin, vmFlyover, 1), 'arrivée');
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

{------------------------------------------------------------------------------}

function TTestVideoScenario.Location(const Formula, X, Y, Width: string): TFractalLocation;
begin
  Result := TFractalLocation.Create;
  Result.LoadFromText('[Fractal]'#13#10'Formula=' + Formula + #13#10'CenterX=' + X + #13#10'CenterY=' + Y +
    #13#10'Width=' + Width + #13#10);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.Add(Scenario: TVideoScenario; const Name, Formula, X, Y, Width: string);
var
  L: TFractalLocation;
begin
  L := Location(Formula, X, Y, Width);
  try
    Scenario.AddLocation(Name, L);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestVideoScenario.TempFile(const Name: string): string;
begin
  Result := TestTempFolder + Name;
  SysUtils.DeleteFile(Result);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.TestFormatSizes;
var
  W, H: Integer;
begin
  VideoFormatSize(vf1x1, W, H);
  CheckEquals(1080, W);
  CheckEquals(1080, H);
  VideoFormatSize(vf4x5, W, H);
  CheckEquals(1080, W);
  CheckEquals(1350, H);
  VideoFormatSize(vf9x16, W, H);
  CheckEquals(1080, W);
  CheckEquals(1920, H);
  VideoFormatSize(vf16x9, W, H);
  CheckEquals(1920, W);
  CheckEquals(1080, H);
  CheckEquals('Reel 9:16', VideoFormatName(vf9x16));
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.TestTimeline;
var
  Sc: TVideoScenario;
  S: TVideoStep;
  P: TCameraPose;
  IsPause: Boolean;
begin
  Sc := TVideoScenario.Create;
  try
    Add(Sc, 'intérieur', 'BurningShip', kInnerX, kInnerY, '2.8e-6');
    Add(Sc, 'bord', 'BurningShip', kEdgeX, kEdgeY, '5.02824617434859796E-11');
    Add(Sc, 'oursin', 'BurningShip', kUrchinX, kUrchinY, kUrchinWidth);
    S := Sc[0];
    S.PauseSeconds := 1;
    Sc[0] := S;
    S := Sc[1];
    S.TravelSeconds := 2;
    S.PauseSeconds := 0;
    Sc[1] := S;
    S := Sc[2];
    S.TravelSeconds := 3;
    S.PauseSeconds := 1.5;
    Sc[2] := S;
    CheckEquals(225, Sc.TotalFrames);
    CheckEquals(7.5, Sc.TotalSeconds, 1e-12);
    P := Sc.PoseAtFrame(0, IsPause);
    CheckTrue(IsPause, 'image 0');
    CheckTrue(P.CenterX.IsEqual(Sc[0].Pose.CenterX));
    Sc.PoseAtFrame(30, IsPause);
    CheckFalse(IsPause, 'image 30 : début du trajet');
    P := Sc.PoseAtFrame(89, IsPause);
    CheckFalse(IsPause, 'image 89 : fin du premier trajet');
    CheckTrue(P.CenterX.IsEqual(Sc[1].Pose.CenterX), 'image 89 : sur l''étape 2');
    P := Sc.PoseAtFrame(224, IsPause);
    CheckTrue(IsPause, 'dernière image');
    CheckTrue(P.CenterX.IsEqual(Sc[2].Pose.CenterX));
    CheckEquals(Sc[2].Pose.Width, P.Width, 0);
  finally
    Sc.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.TestRefusesOtherFormula;
var
  Sc: TVideoScenario;
begin
  Sc := TVideoScenario.Create;
  try
    Add(Sc, 'm', 'Mandelbrot', '-0.75', '0.1', '0.01');
    try
      Add(Sc, 'b', 'BurningShip', kEdgeX, kEdgeY, '1e-10');
      Fail('autre formule acceptée');
    except
      on E: EVideoScenarioError do
        CheckTrue(Pos('« b »', E.Message) > 0, E.Message);
    end;
    CheckEquals(1, Sc.Count);
    CheckEquals('Mandelbrot', Sc.FormulaName);
  finally
    Sc.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.TestSaveLoadRoundTrip;
var
  A, B: TVideoScenario;
  S: TVideoStep;
  FileName: string;
  I: Integer;
begin
  FileName := TempFile('scenario' + kScenarioExtension);
  A := TVideoScenario.Create;
  B := TVideoScenario.Create;
  try
    Add(A, 'bord gauche', 'BurningShip', kEdgeX, kEdgeY, '5.02824617434859796E-11');
    Add(A, 'oursin', 'BurningShip', kUrchinX, kUrchinY, kUrchinWidth);
    S := A[1];
    S.Mode := vmLateral;
    S.TravelSeconds := 4.25;
    S.PauseSeconds := 1.5;
    A[1] := S;
    A.Format := vf9x16;
    A.SaveToFile(FileName);
    // relu par un autre scénario, sans aucun favori : le fichier se suffit à lui-même
    B.LoadFromFile(FileName);
    CheckEquals(2, B.Count);
    CheckEquals('BurningShip', B.FormulaName);
    CheckTrue(B.Format = vf9x16);
    for I := 0 to 1 do
    begin
      CheckEquals(A[I].Name, B[I].Name);
      CheckTrue(A[I].Pose.CenterX.IsEqual(B[I].Pose.CenterX), Format('étape %d : X', [I]));
      CheckTrue(A[I].Pose.CenterY.IsEqual(B[I].Pose.CenterY), Format('étape %d : Y', [I]));
      CheckEquals(A[I].Pose.Width, B[I].Pose.Width, A[I].Pose.Width * 1e-15);
      CheckTrue(A[I].Mode = B[I].Mode);
      CheckEquals(A[I].TravelSeconds, B[I].TravelSeconds, 1e-12);
      CheckEquals(A[I].PauseSeconds, B[I].PauseSeconds, 1e-12);
    end;
    CheckEquals(A.TotalFrames, B.TotalFrames);
  finally
    B.Free;
    A.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.TestLoadGarbage;
const
  kTexts: array[0..3] of string = ('', 'n''importe quoi', '[Video]'#13#10'Steps=2'#13#10'Formula=BurningShip',
    '[Video]'#13#10'Steps=1'#13#10'Formula=Inconnue'#13#10'[Step1]'#13#10'Width=1');
var
  Sc: TVideoScenario;
  L: TStringList;
  FileName: string;
  I: Integer;
begin
  FileName := TempFile('mauvais' + kScenarioExtension);
  Sc := TVideoScenario.Create;
  L := TStringList.Create;
  try
    for I := Low(kTexts) to High(kTexts) do
    begin
      L.Text := kTexts[I];
      L.SaveToFile(FileName);
      try
        Sc.LoadFromFile(FileName);
        Fail(Format('texte %d accepté', [I]));
      except
        on E: EVideoScenarioError do
          ;
      end;
      CheckEquals(0, Sc.Count, Format('texte %d : scénario modifié', [I]));
    end;
  finally
    L.Free;
    Sc.Free;
    SysUtils.DeleteFile(FileName);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoScenario.TestMoveAndDelete;
var
  Sc: TVideoScenario;
begin
  Sc := TVideoScenario.Create;
  try
    Add(Sc, 'a', 'BurningShip', kInnerX, kInnerY, '2.8e-6');
    Add(Sc, 'b', 'BurningShip', kEdgeX, kEdgeY, '5e-11');
    Add(Sc, 'c', 'BurningShip', kUrchinX, kUrchinY, kUrchinWidth);
    Sc.Move(2, 0);
    CheckEquals('c', Sc[0].Name);
    CheckEquals('a', Sc[1].Name);
    CheckEquals('b', Sc[2].Name);
    Sc.Delete(1);
    CheckEquals(2, Sc.Count);
    CheckEquals('b', Sc[1].Name);
    Sc.Delete(0);
    Sc.Delete(0);
    CheckEquals('', Sc.FormulaName, 'scénario vide : plus de formule');
  finally
    Sc.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestVideoEncoder.SystemTool(const Name: string): string;
begin
  Result := GetEnvironmentVariable('SystemRoot') + '\System32\' + Name;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoEncoder.TestArguments;
const
  kParts: array[0..8] of string = ('-y ', '-f image2pipe', '-framerate 30', '-c:v png -i -', '-c:v libx264',
    '-pix_fmt yuv420p', '-crf 16', '-movflags +faststart', '"C:\Vidéos\voyage.mp4"');
var
  Args: string;
  I: Integer;
begin
  Args := FfmpegArguments('C:\Vidéos\voyage.mp4', 30);
  for I := Low(kParts) to High(kParts) do
    CheckTrue(Pos(kParts[I], Args) > 0, kParts[I] + ' absent de : ' + Args);
end;

{------------------------------------------------------------------------------}

procedure TTestVideoEncoder.TestFindFfmpeg;
var
  Folder, Fake, Configured: string;
  L: TStringList;
begin
  Folder := TestTempFolder + 'ffmpeg-test\';
  ForceDirectories(Folder);
  Fake := Folder + kFfmpegExe;
  Configured := TestTempFolder + 'ffmpeg-ailleurs.exe';
  L := TStringList.Create;
  try
    SysUtils.DeleteFile(Fake);
    SysUtils.DeleteFile(Configured);
    CheckEquals('', FindFfmpeg(Folder, ''), 'rien nulle part');
    L.SaveToFile(Fake);
    CheckEquals(Fake, FindFfmpeg(Folder, ''), 'à côté de l''exe');
    CheckEquals(Fake, FindFfmpeg(Folder, Configured), 'chemin configuré absent : repli');
    L.SaveToFile(Configured);
    CheckEquals(Configured, FindFfmpeg(Folder, Configured), 'chemin configuré');
  finally
    L.Free;
    SysUtils.DeleteFile(Fake);
    SysUtils.DeleteFile(Configured);
    RemoveDir(Folder);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoEncoder.TestMissingExe;
begin
  try
    TFfmpegPipe.Create('X:\absent\ffmpeg.exe', TestTempFolder + 'absent.mp4', 30).Free;
    Fail('exe absent accepté');
  except
    on E: EVideoEncoderError do
      CheckEquals(kFfmpegHelp, E.Message);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestVideoEncoder.TestFailingEncoderReportsError;
var
  Pipe: TFfmpegPipe;
  OutFile: string;
  Png: TMemoryStream;
begin
  // where.exe refuse les arguments de FFmpeg et s'arrête en erreur : même chemin qu'un FFmpeg qui échoue
  OutFile := TestTempFolder + 'echec.mp4';
  SysUtils.DeleteFile(OutFile);
  Png := TMemoryStream.Create;
  Pipe := TFfmpegPipe.Create(SystemTool('where.exe'), OutFile, 30);
  try
    Png.SetSize(16);
    try
      Pipe.WriteFrame(Png);  // peut déjà échouer si where.exe est parti
      Pipe.Finish;
      Fail('échec non signalé');
    except
      on E: EVideoEncoderError do
        CheckTrue(Pos('FFmpeg', E.Message) > 0, E.Message);
    end;
    CheckFalse(FileExists(OutFile), 'vidéo partielle laissée');
  finally
    Pipe.Free;
    Png.Free;
    SysUtils.DeleteFile(OutFile + '.log');
  end;
end;

initialization
  RegisterTest(TTestVideoPath.Suite);
  RegisterTest(TTestVideoScenario.Suite);
  RegisterTest(TTestVideoEncoder.Suite);

end.
