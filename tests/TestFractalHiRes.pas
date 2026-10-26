unit TestFractalHiRes;

interface

uses
  Classes, SysUtils, Graphics, pngimage, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette,
  Fractal.Png, Fractal.HiRes, Fractal.Engine, TestUtils;

type
  TTestHiRes = class(TTestCase)
  private
    FMapping: TColorMapping;
    function MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
    procedure RenderPng(Size, SS: Integer; const FileName: string; ABandRows: Integer = kHiResBandRows);
    function MeanReliefShift(SS: Integer): Double;
    function RunRenderer(const Settings: THiResSettings; const V: TViewport; F: TFractalFormula;
      AKernel: TEngineKernelType = ekDelphi; ABandRows: Integer = kHiResBandRows): THiResRenderer;
  protected
    procedure SetUp; override;
  published
    procedure TestSmallRenderMatchesDirectColors;
    procedure TestSupersampledRenderHasRequestedSize;
    procedure TestSupersampleAveragesAcrossBands;
    procedure TestCancelDeletesFile;
    procedure TestInvalidPathReportsError;
    procedure TestEstimateRejectsHugeRender;
    procedure TestRustKernelRequestRenders;
    procedure TestHiResWithoutEffectsUnchanged;
    procedure TestHiResReliefHasNoSeam;
    procedure TestHiResReliefStrengthIndependentOfSupersample;
  end;

implementation

{------------------------------------------------------------------------------}

procedure TTestHiRes.SetUp;
begin
  inherited SetUp;
  FMapping := DefaultColorMapping;
end;

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
  F: TFractalFormula; AKernel: TEngineKernelType; ABandRows: Integer): THiResRenderer;
var
  P: TGradientPalette;
begin
  P := CreateBuiltInPalette(0);
  try
    Result := THiResRenderer.Create(Settings, V, F, TColorMapper.Create(P, FMapping), 'abc', AKernel, ABandRows);
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
  // le relief ajoute deux lignes de recouvrement à la bande ; sans relief, l'estimation est inchangée
  CheckEquals(Int64(100) * 2 * kHiResBandRows * 2 * 5 + 300, EstimateHiResBytes(MakeSettings(100, 10, 2, '')));
  CheckEquals(Int64(100) * 2 * (kHiResBandRows + 2) * 2 * 5 + 300,
    EstimateHiResBytes(MakeSettings(100, 10, 2, ''), True));
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

procedure TTestHiRes.TestHiResWithoutEffectsUnchanged;
const
  kExpectedCrc = $95E81BBF;  // PNG produit avant l'ajout du relief en HD (commit d4abc22)
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
  Stream: TFileStream;
  Bytes: array of Byte;
begin
  FileName := TestTempFolder + 'hires-frozen.png';
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(40, 40, 2, FileName), MakeViewport(-0.5, 0, 3, 40, 40), F);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Stream := TFileStream.Create(FileName, fmOpenRead);
    try
      SetLength(Bytes, Stream.Size);
      Stream.ReadBuffer(Bytes[0], Stream.Size);
    finally
      Stream.Free;
    end;
    CheckEquals(IntToHex(kExpectedCrc, 8), IntToHex(PngCrc32(@Bytes[0], Length(Bytes)), 8));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestHiResReliefHasNoSeam;
const
  kSize = 40;
  kSS = 2;
  kManyBandRows = 7;  // ne divise pas 40 : bandes de 7 lignes puis une dernière de 5
var
  F: TMandelbrotFormula;
  R: THiResRenderer;
  Whole, Banded, Plain: TPngImage;
  X, Y: Integer;
  IsDifferent: Boolean;
begin
  // référence sans relief, pour vérifier que le relief agit réellement
  RenderPng(kSize, kSS, TestTempFolder + 'hires-relief-plain.png');
  FMapping.HasRelief := True;
  F := TMandelbrotFormula.Create;
  Whole := TPngImage.Create;
  Banded := TPngImage.Create;
  Plain := TPngImage.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(kSize, kSize, kSS, TestTempFolder + 'hires-relief-whole.png'),
      MakeViewport(-0.5, 0, 3, kSize, kSize), F, ekDelphi, kSize);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    R := RunRenderer(MakeSettings(kSize, kSize, kSS, TestTempFolder + 'hires-relief-bands.png'),
      MakeViewport(-0.5, 0, 3, kSize, kSize), F, ekDelphi, kManyBandRows);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Whole.LoadFromFile(TestTempFolder + 'hires-relief-whole.png');
    Banded.LoadFromFile(TestTempFolder + 'hires-relief-bands.png');
    Plain.LoadFromFile(TestTempFolder + 'hires-relief-plain.png');
    IsDifferent := False;
    for Y := 0 to kSize - 1 do
      for X := 0 to kSize - 1 do
      begin
        CheckEquals(Integer(Whole.Pixels[X, Y]), Integer(Banded.Pixels[X, Y]),
          Format('pixel (%d, %d)', [X, Y]));
        if Whole.Pixels[X, Y] <> Plain.Pixels[X, Y] then
          IsDifferent := True;
      end;
    CheckTrue(IsDifferent, 'le relief ne change aucun pixel');
  finally
    Plain.Free;
    Banded.Free;
    Whole.Free;
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.RenderPng(Size, SS: Integer; const FileName: string; ABandRows: Integer);
var
  F: TMandelbrotFormula;
  R: THiResRenderer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(Size, Size, SS, FileName), MakeViewport(-0.5, 0, 3, Size, Size), F,
      ekDelphi, ABandRows);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestHiRes.MeanReliefShift(SS: Integer): Double;
const
  kSize = 40;
var
  Plain, Shaded: TPngImage;
  X, Y: Integer;
  C1, C2: Integer;
  Total: Int64;
  PlainName, ShadedName: string;
begin
  PlainName := TestTempFolder + Format('hires-strength-plain-%d.png', [SS]);
  ShadedName := TestTempFolder + Format('hires-strength-relief-%d.png', [SS]);
  FMapping.HasRelief := False;
  RenderPng(kSize, SS, PlainName);
  FMapping.HasRelief := True;
  RenderPng(kSize, SS, ShadedName);
  Plain := TPngImage.Create;
  Shaded := TPngImage.Create;
  try
    Plain.LoadFromFile(PlainName);
    Shaded.LoadFromFile(ShadedName);
    Total := 0;
    for Y := 0 to kSize - 1 do
      for X := 0 to kSize - 1 do
      begin
        C1 := Plain.Pixels[X, Y];
        C2 := Shaded.Pixels[X, Y];
        Inc(Total, Abs((C1 and $FF) - (C2 and $FF)) + Abs(((C1 shr 8) and $FF) - ((C2 shr 8) and $FF)) +
          Abs(((C1 shr 16) and $FF) - ((C2 shr 16) and $FF)));
      end;
    Result := Total / (kSize * kSize);
  finally
    Shaded.Free;
    Plain.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestHiRes.TestHiResReliefStrengthIndependentOfSupersample;
const
  kMinRatio = 0.7;  // le HD doit rendre le relief de l'écran ; avant correction (pente SS fois trop plate) : 0,64
  kMaxRatio = 1.3;  // l'anticrénelage lisse un peu les écarts : on tolère 30 % de part et d'autre
var
  Screen, Doubled: Double;
begin
  Screen := MeanReliefShift(1);
  Doubled := MeanReliefShift(2);
  CheckTrue(Screen > 0, 'le relief ne change aucun pixel');
  CheckTrue((Doubled >= kMinRatio * Screen) and (Doubled <= kMaxRatio * Screen),
    Format('force du relief : SS=1 %.3f, SS=2 %.3f', [Screen, Doubled]));
end;

{------------------------------------------------------------------------------}

initialization
  RegisterTest(TTestHiRes.Suite);

end.
