unit TestFractalHiRes;

interface

uses
  Classes, SysUtils, Graphics, pngimage, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette,
  Fractal.Png, Fractal.HiRes, Fractal.Engine, TestUtils;

type
  TTestHiRes = class(TTestCase)
  private
    function MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
    function RunRenderer(const Settings: THiResSettings; const V: TViewport; F: TFractalFormula;
      AKernel: TEngineKernel = ekDelphi): THiResRenderer;
  published
    procedure TestSmallRenderMatchesDirectColors;
    procedure TestSupersampledRenderHasRequestedSize;
    procedure TestSupersampleAveragesAcrossBands;
    procedure TestCancelDeletesFile;
    procedure TestInvalidPathReportsError;
    procedure TestEstimateRejectsHugeRender;
    procedure TestRustKernelRequestRenders;
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
  F: TFractalFormula; AKernel: TEngineKernel): THiResRenderer;
var
  P: TGradientPalette;
begin
  P := CreateBuiltInPalette(0);
  try
    Result := THiResRenderer.Create(Settings, V, F, TColorMapper.Create(P, DefaultColorMapping), 'abc', AKernel);
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

procedure TTestHiRes.TestSupersampleAveragesAcrossBands;
const
  kPixelX = 5;
  kPixelY = 20;
  kSS = 2;
  kBand = 16;
var
  FileName: string;
  V, Band: TViewport;
  F: TMandelbrotFormula;
  P: TGradientPalette;
  Check: TColorMapper;
  R: THiResRenderer;
  Png: TPngImage;
  C: TComplexPoint;
  SX, SY, Sum, Expected: Integer;
  Channel: Cardinal;
  Shift: Integer;
  Color: Cardinal;
  Sums: array[0..2] of Integer;
begin
  FileName := TestTempFolder + 'hires-bands.png';
  V := MakeViewport(-0.5, 0, 3, 40, 40);
  F := TMandelbrotFormula.Create;
  P := CreateBuiltInPalette(0);
  Check := TColorMapper.Create(P, DefaultColorMapping);
  Png := TPngImage.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(40, 40, kSS, FileName), V, F);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    Band := V.SubViewport(kSS, kBand, kBand);
    FillChar(Sums, SizeOf(Sums), 0);
    for SY := 0 to kSS - 1 do
      for SX := 0 to kSS - 1 do
      begin
        C := Band.PixelToComplex(kPixelX * kSS + SX, (kPixelY - kBand) * kSS + SY);
        Color := Check.MapValue(F.Iterate(C.X, C.Y));
        Inc(Sums[0], (Color shr 16) and $FF);
        Inc(Sums[1], (Color shr 8) and $FF);
        Inc(Sums[2], Color and $FF);
      end;
    Expected := 0;
    for SX := 0 to 2 do
    begin
      Shift := (2 - SX) * 8;  // R, G, B
      Channel := Cardinal((Sums[SX] + (kSS * kSS) div 2) div (kSS * kSS));
      Expected := Expected or Integer(Channel shl Shift);
    end;
    Sum := Integer(SwapRedBlue(Cardinal(Expected)));
    CheckEquals(Sum, Integer(Png.Pixels[kPixelX, kPixelY]));
  finally
    Png.Free;
    Check.Free;
    P.Free;
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

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestRustKernelRequestRenders;
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
  Png: TPngImage;
begin
  // avec ou sans DLL Rust (repli sur Delphi), le rendu HD doit aboutir
  FileName := TestTempFolder + 'hires-rust.png';
  F := TMandelbrotFormula.Create;
  Png := TPngImage.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(64, 48, 2, FileName), MakeViewport(-0.5, 0, 3, 64, 48), F, ekRust);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    CheckEquals(64, Png.Width);
    CheckEquals(48, Png.Height);
  finally
    Png.Free;
    F.Free;
  end;
end;

initialization
  RegisterTest(TTestHiRes.Suite);

end.
