unit TestFractalFormulas;

interface

uses
  Math, TestFramework, Fractal.Types, Fractal.Formulas;

type
  TTestFormulas = class(TTestCase)
  published
    procedure TestMandelbrotOriginIsInside;
    procedure TestMandelbrotPeriod4BulbIsInside;
    procedure TestMandelbrotFarPointEscapesFast;
    procedure TestSmoothValueIsContinuous;
    procedure TestMultibrotPower2MatchesMandelbrot;
    procedure TestJuliaZeroIsUnitDisk;
    procedure TestTricornIsSymmetric;
    procedure TestBurningShip;
    procedure TestSetParamClampsAndCloneCopies;
    procedure TestRegistry;
    procedure TestKernelIds;
    procedure TestParamToSliderPosition;
    procedure TestSliderPositionToParam;
    procedure TestSliderWithEmptyRange;
    procedure TestResetParamsRestoresDefaults;
  end;

implementation

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestMandelbrotOriginIsInside;
var
  F: TMandelbrotFormula;
begin
  F := TMandelbrotFormula.Create;
  try
    CheckEquals(kInside, F.Iterate(0, 0), 0);
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestMandelbrotPeriod4BulbIsInside;
var
  F: TMandelbrotFormula;
begin
  // hors cardioïde et bulbe principal : aucun raccourci, il faut vraiment itérer
  F := TMandelbrotFormula.Create;
  try
    CheckEquals(kInside, F.Iterate(-1.3107, 0), 0);
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestMandelbrotFarPointEscapesFast;
var
  F: TMandelbrotFormula;
  V: Single;
begin
  F := TMandelbrotFormula.Create;
  try
    V := F.Iterate(10, 10);
    CheckTrue(V >= 0, 'doit s''échapper');
    CheckTrue(V < 3, 'doit s''échapper en peu d''itérations');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestSmoothValueIsContinuous;
var
  F: TMandelbrotFormula;
  A, B: Single;
begin
  F := TMandelbrotFormula.Create;
  try
    A := F.Iterate(0.5, 0.5);
    B := F.Iterate(0.5 + 1e-7, 0.5);
    CheckTrue(A > 0);
    CheckEquals(A, B, 1e-3);
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestMultibrotPower2MatchesMandelbrot;
const
  kPoints: array[0..3, 0..1] of Double = ((0.5, 0.5), (1.0, 1.0), (-2.5, 0.0), (0.0, 1.5));
var
  M: TMandelbrotFormula;
  B: TMultibrotFormula;
  I: Integer;
begin
  M := TMandelbrotFormula.Create;
  B := TMultibrotFormula.Create;
  try
    B.SetParam(B.IndexOfParam('power'), 2);
    for I := 0 to High(kPoints) do
      CheckEquals(M.Iterate(kPoints[I, 0], kPoints[I, 1]), B.Iterate(kPoints[I, 0], kPoints[I, 1]), 1e-3);
    CheckEquals(kInside, B.Iterate(0, 0), 0);
  finally
    B.Free;
    M.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestJuliaZeroIsUnitDisk;
var
  J: TJuliaFormula;
begin
  J := TJuliaFormula.Create;
  try
    J.SetParam(J.IndexOfParam('cx'), 0);
    J.SetParam(J.IndexOfParam('cy'), 0);
    CheckEquals(kInside, J.Iterate(0.5, 0), 0);
    CheckTrue(J.Iterate(1.5, 0) >= 0);
  finally
    J.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestTricornIsSymmetric;
var
  T: TTricornFormula;
begin
  T := TTricornFormula.Create;
  try
    CheckEquals(T.Iterate(0.3, 0.7), T.Iterate(0.3, -0.7), 0);
  finally
    T.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestBurningShip;
var
  B: TBurningShipFormula;
begin
  B := TBurningShipFormula.Create;
  try
    CheckEquals(kInside, B.Iterate(0, 0), 0);
    CheckTrue(B.Iterate(2, 2) >= 0);
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestSetParamClampsAndCloneCopies;
var
  B: TMultibrotFormula;
  C: TFractalFormula;
begin
  B := TMultibrotFormula.Create;
  try
    B.SetParam(0, 99);
    CheckEquals(10.0, B.GetParam(0), 0);
    B.MaxIter := 5;
    CheckEquals(kMinMaxIter, B.MaxIter);
    C := B.Clone;
    try
      CheckTrue(C is TMultibrotFormula);
      CheckEquals(10.0, C.GetParam(0), 0);
      CheckEquals(kMinMaxIter, C.MaxIter);
    finally
      C.Free;
    end;
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestRegistry;
var
  B: TMultibrotFormula;
begin
  CheckTrue(FormulaClassCount >= 5);
  CheckTrue(FindFormulaClass('mandelbrot') = TMandelbrotFormula);
  CheckTrue(FindFormulaClass('xyz') = nil);
  B := TMultibrotFormula.Create;
  try
    CheckEquals(0, B.IndexOfParam('power'));
    CheckEquals(-1, B.IndexOfParam('nope'));
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestKernelIds;
var
  I, J: Integer;
begin
  CheckEquals(kKernelMandelbrot, TMandelbrotFormula.KernelId);
  CheckEquals(kKernelMultibrot, TMultibrotFormula.KernelId);
  CheckEquals(kKernelJulia, TJuliaFormula.KernelId);
  CheckEquals(kKernelBurningShip, TBurningShipFormula.KernelId);
  CheckEquals(kKernelTricorn, TTricornFormula.KernelId);
  for I := 0 to FormulaClassCount - 1 do
    for J := I + 1 to FormulaClassCount - 1 do
      CheckTrue(FormulaClassAt(I).KernelId <> FormulaClassAt(J).KernelId, 'identifiants en double');
end;

{------------------------------------------------------------------------------}

function JuliaCxInfo: TFormulaParam;
var
  F: TJuliaFormula;
begin
  F := TJuliaFormula.Create;
  try
    Result := F.ParamInfo(F.IndexOfParam('cx'));  // de -2 à 2
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestParamToSliderPosition;
var
  Info: TFormulaParam;
begin
  Info := JuliaCxInfo;
  CheckEquals(0, ParamToSliderPosition(Info, -2));
  CheckEquals(kParamSliderSteps, ParamToSliderPosition(Info, 2));
  CheckEquals(kParamSliderSteps div 2, ParamToSliderPosition(Info, 0));
  CheckEquals(539, ParamToSliderPosition(Info, 0.156), 'cran le plus proche');
  CheckEquals(kParamSliderSteps, ParamToSliderPosition(Info, 5), 'au-dessus du maximum');
  CheckEquals(0, ParamToSliderPosition(Info, -5), 'en dessous du minimum');
  CheckEquals(0, ParamToSliderPosition(Info, NaN));
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestSliderPositionToParam;
var
  Info: TFormulaParam;
begin
  Info := JuliaCxInfo;
  CheckEquals(-2, SliderPositionToParam(Info, 0), 0);
  CheckEquals(2, SliderPositionToParam(Info, kParamSliderSteps), 0);
  CheckEquals(0, SliderPositionToParam(Info, kParamSliderSteps div 2), 1e-15);
  CheckEquals(2, SliderPositionToParam(Info, kParamSliderSteps + 500), 0, 'position bornée');
  CheckEquals(-2, SliderPositionToParam(Info, -1), 0, 'position bornée');
  // aller-retour : au plus un demi-cran d'écart
  CheckEquals(0.156, SliderPositionToParam(Info, ParamToSliderPosition(Info, 0.156)), 4 / kParamSliderSteps / 2);
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestSliderWithEmptyRange;
var
  Info: TFormulaParam;
begin
  Info := JuliaCxInfo;
  Info.MinValue := 1;
  Info.MaxValue := 1;
  CheckEquals(0, ParamToSliderPosition(Info, 1));
  CheckEquals(1, SliderPositionToParam(Info, 300), 0);
end;

{------------------------------------------------------------------------------}

procedure TTestFormulas.TestResetParamsRestoresDefaults;
var
  J: TJuliaFormula;
  M, Fresh: TMultibrotFormula;
  Plain: TMandelbrotFormula;
begin
  J := TJuliaFormula.Create;
  M := TMultibrotFormula.Create;
  Fresh := TMultibrotFormula.Create;
  Plain := TMandelbrotFormula.Create;
  try
    J.SetParam(0, 0.3);
    J.SetParam(1, -0.5);
    J.MaxIter := 5000;
    J.ResetParams;
    CheckEquals(J.ParamInfo(0).DefaultValue, J.GetParam(0), 0);
    CheckEquals(J.ParamInfo(1).DefaultValue, J.GetParam(1), 0);
    CheckEquals(5000, J.MaxIter, 'les itérations ne sont pas des paramètres');
    // les valeurs mises en cache par ParamsChanged suivent : même résultat qu'une formule neuve
    M.SetParam(0, 7);
    M.ResetParams;
    CheckEquals(Fresh.Iterate(-0.6, 0.4), M.Iterate(-0.6, 0.4), 0);
    Plain.ResetParams;  // sans paramètre : rien à faire, pas d'erreur
    CheckEquals(0, Plain.ParamCount);
  finally
    Plain.Free;
    Fresh.Free;
    M.Free;
    J.Free;
  end;
end;

initialization
  RegisterTest(TTestFormulas.Suite);

end.
