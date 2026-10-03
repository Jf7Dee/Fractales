unit TestFractalHiRes;

interface

uses
  Classes, SysUtils, Graphics, pngimage, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette,
  Fractal.Png, Fractal.HiRes, TestUtils;

type
  TTestHiRes = class(TTestCase)
  private
    function MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
    function RunRenderer(const Settings: THiResSettings; const V: TViewport; F: TFractalFormula): THiResRenderer;
  published
    procedure TestSmallRenderMatchesDirectColors;
    procedure TestSupersampledRenderHasRequestedSize;
    procedure TestCancelDeletesFile;
    procedure TestInvalidPathReportsError;
    procedure TestEstimateRejectsHugeRender;
  end;

implementation

{------------------------------------------------------------------------------}

function TTestHiRes.MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
begin
  Result.Width := W;
  Result.Height := H;
  Result.Supersample := SS;
  Result.FileName := FileName;
end;

{------------------------------------------------------------------------------}

function TTestHiRes.RunRenderer(const Settings: THiResSettings; const V: TViewport;
  F: TFractalFormula): THiResRenderer;
var
  P: TGradientPalette;
begin
  P := CreateBuiltInPalette(0);
  try
    Result := THiResRenderer.Create(Settings, V, F, TColorMapper.Create(P, DefaultColorMapping), 'abc');
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestSmallRenderMatchesDirectColors;
const
  kSamples: array[0..3, 0..1] of Integer = ((0, 0), (10, 20), (63, 47), (32, 24));
var
  FileName: string;
  V: TViewport;
  F: TMandelbrotFormula;
  P: TGradientPalette;
  Check: TColorMapper;
  R: THiResRenderer;
  Png: TPngImage;
  C: TComplexPoint;
  I: Integer;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'hires.png';
  V := MakeViewport(-0.5, 0, 3, 64, 48);
  F := TMandelbrotFormula.Create;
  P := CreateBuiltInPalette(0);
  Check := TColorMapper.Create(P, DefaultColorMapping);
  Png := TPngImage.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(64, 48, 1, FileName), V, F);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
      CheckTrue(R.IsDone);
      CheckEquals(1000, R.Progress);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    for I := 0 to High(kSamples) do
    begin
      C := V.PixelToComplex(kSamples[I, 0], kSamples[I, 1]);
      CheckEquals(Integer(SwapRedBlue(Check.MapValue(F.Iterate(C.X, C.Y)))),
        Integer(Png.Pixels[kSamples[I, 0], kSamples[I, 1]]));
    end;
    CheckTrue(ReadPngText(FileName, kLocationKeyword, Text));
    CheckEquals('abc', UTF8ToString(Text));
  finally
    Png.Free;
    Check.Free;
    P.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestSupersampledRenderHasRequestedSize;
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
  Png: TPngImage;
begin
  FileName := TestTempFolder + 'hires-ss.png';
  F := TMandelbrotFormula.Create;
  Png := TPngImage.Create;
  try
    R := RunRenderer(MakeSettings(80, 50, 2, FileName), MakeViewport(-0.5, 0, 3, 400, 300), F);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    CheckEquals(80, Png.Width);
    CheckEquals(50, Png.Height);
  finally
    Png.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestCancelDeletesFile;
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
begin
  FileName := TestTempFolder + 'hires-cancel.png';
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 5000;
    R := RunRenderer(MakeSettings(3000, 2000, 3, FileName), MakeViewport(-0.5, 0, 3, 400, 300), F);
    try
      Sleep(300);
      R.Terminate;
      R.WaitFor;
      CheckFalse(R.IsSucceeded);
      CheckEquals('', R.ErrorMessage);
    finally
      R.Free;
    end;
    CheckFalse(FileExists(FileName));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestInvalidPathReportsError;
var
  F: TMandelbrotFormula;
  R: THiResRenderer;
begin
  F := TMandelbrotFormula.Create;
  try
    R := RunRenderer(MakeSettings(16, 16, 1, TestTempFolder + 'absent\sous\x.png'),
      MakeViewport(-0.5, 0, 3, 400, 300), F);
    try
      R.WaitFor;
      CheckFalse(R.IsSucceeded);
      CheckTrue(R.ErrorMessage <> '');
    finally
      R.Free;
    end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestEstimateRejectsHugeRender;
begin
  CheckTrue(EstimateHiResBytes(MakeSettings(7680, 4320, 3, '')) < kMaxHiResBytes);
  CheckTrue(EstimateHiResBytes(MakeSettings(1000000, 100, 3, '')) > kMaxHiResBytes);
end;

initialization
  RegisterTest(TTestHiRes.Suite);

end.
