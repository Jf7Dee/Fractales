unit TestFractalHiRes;

interface

uses
  Classes, SysUtils, Types, Graphics, pngimage, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette,
  Fractal.Png, Fractal.HiRes, Fractal.Engine, TestUtils;

type
  TTestHiRes = class(TTestCase)
  private
    FMapping: TColorMapping;
    // dernier RenderPixels
    FRefined: Int64;
    FTotal: Int64;
    FReferenceCount: Integer;
    FBlaCount: Integer;
    function MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
    procedure RenderPng(Size, SS: Integer; const FileName: string; ABandRows: Integer = kHiResBandRows);
    function MeanReliefShift(SS: Integer): Double;
    function RenderPixels(const Settings: THiResSettings; const V: TViewport; F: TFractalFormula;
      ABandRows: Integer = kHiResBandRows): TCardinalDynArray;
    function FileCrc(const FileName: string): Cardinal;
    procedure CompareToFull(const Adaptive, Full: TCardinalDynArray; const Context: string);
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
    procedure TestAdaptiveOffIsIdentical;
    procedure TestAdaptiveSupersampleOneIsIdentical;
    procedure TestAdaptiveFlatViewRefinesNothing;
    procedure TestAdaptiveCloseToFull;
    procedure TestAdaptiveReliefMatchesFull;
    procedure TestAdaptiveBandEdge;
    procedure TestAdaptiveReusesReference;
    procedure TestAdaptiveReferenceAtWordBoundary;
    procedure TestBandsShareBlaTable;
  end;

implementation

uses
  Windows, Math, Fractal.Adaptive, TestFractalPerturbation;

const
  // MultiBroth_1.fscn de JF, première étape (environ 40 000 itérations par pixel)
  kMultiBroth1X = '0.6436032989752984374817305594833887051524012044957825545579532636106783601909397218300741567511592';
  kMultiBroth1Y = '0.3192585403317653763008687900976260312288946415772095488687299432276187153103164694680194451662740';
  kMultiBroth1Width = 2.33279729810509063E-55;
  kMultiBroth1MaxIter = 41477;

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
  Result.IsBla := False;
  Result.IsAdaptive := False;
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

// Rendu HD dans un fichier temporaire, relu en couleurs $RRGGBB ligne par ligne ; garde les compteurs du renderer.
function TTestHiRes.RenderPixels(const Settings: THiResSettings; const V: TViewport; F: TFractalFormula;
  ABandRows: Integer): TCardinalDynArray;
var
  R: THiResRenderer;
  Png: TPngImage;
  X, Y: Integer;
  C: TColor;
begin
  R := RunRenderer(Settings, V, F, ekDelphi, ABandRows);
  try
    R.WaitFor;
    CheckTrue(R.IsSucceeded, R.ErrorMessage);
    FRefined := R.RefinedPixels;
    FTotal := R.TotalPixels;
    FReferenceCount := R.ReferenceComputeCount;
    FBlaCount := R.BlaBuildCount;
  finally
    R.Free;
  end;
  Png := TPngImage.Create;
  try
    Png.LoadFromFile(Settings.FileName);
    SetLength(Result, Settings.Width * Settings.Height);
    for Y := 0 to Settings.Height - 1 do
      for X := 0 to Settings.Width - 1 do
      begin
        C := Png.Pixels[X, Y];
        Result[Y * Settings.Width + X] := Cardinal(GetRValue(C)) shl 16 or Cardinal(GetGValue(C)) shl 8
          or GetBValue(C);
      end;
  finally
    Png.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestHiRes.FileCrc(const FileName: string): Cardinal;
var
  Stream: TFileStream;
  Bytes: array of Byte;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    SetLength(Bytes, Stream.Size);
    Stream.ReadBuffer(Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Result := PngCrc32(@Bytes[0], Length(Bytes));
end;

{------------------------------------------------------------------------------}

// Adaptatif contre lissage complet : au moins 99 % de pixels identiques, au plus un pixel sur mille dont un canal
// s'écarte de plus du seuil + 2.
procedure TTestHiRes.CompareToFull(const Adaptive, Full: TCardinalDynArray; const Context: string);
var
  I, Same, MaxDiff, Shift, Far: Integer;
  Diff: Integer;
begin
  CheckEquals(Length(Full), Length(Adaptive), Context);
  Same := 0;
  MaxDiff := 0;
  Far := 0;
  for I := 0 to High(Full) do
  begin
    if Adaptive[I] = Full[I] then
      Inc(Same);
    Diff := 0;
    Shift := 0;
    while Shift <= 16 do
    begin
      Diff := Max(Diff, Abs(Integer((Adaptive[I] shr Shift) and $FF) - Integer((Full[I] shr Shift) and $FF)));
      Inc(Shift, 8);
    end;
    MaxDiff := Max(MaxDiff, Diff);
    if Diff > kAdaptiveThreshold + 2 then
      Inc(Far);
  end;
  Status(Format('%s : %d %% identiques, écart max %d (%d pixels au-delà de %d), %d pixels lissés sur %d', [Context,
    Same * 100 div Length(Full), MaxDiff, Far, kAdaptiveThreshold + 2, FRefined, FTotal]));
  CheckTrue(Same * 100 >= 99 * Length(Full), Format('%s : %d pixels identiques sur %d', [Context, Same,
    Length(Full)]));
  // un détail plus fin qu'un pixel au milieu d'une zone unie échappe au premier passage (une poussière isolée, que le
  // relief éclaire) : toléré pour un pixel sur mille
  CheckTrue(Far * 1000 <= Length(Full), Format('%s : %d pixels à plus de %d', [Context, Far,
    kAdaptiveThreshold + 2]));
end;

{------------------------------------------------------------------------------}

// Réglage coupé : le PNG est celui du lissage complet actuel, à l'octet près (relief compris).
procedure TTestHiRes.TestAdaptiveOffIsIdentical;
const
  kExpectedCrc = $43326A35;  // PNG produit avant le lissage adaptatif (relief, SS 2)
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
begin
  FMapping.HasRelief := True;
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 200;
    Settings := MakeSettings(40, 40, 2, TestTempFolder + 'hires-adaptive-off.png');
    RenderPixels(Settings, MakeViewport(-0.5, 0, 3, 40, 40), F);
    CheckEquals(IntToHex(kExpectedCrc, 8), IntToHex(FileCrc(Settings.FileName), 8));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// SS 1 : l'adaptatif ne change rien.
procedure TTestHiRes.TestAdaptiveSupersampleOneIsIdentical;
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
  Crc: Cardinal;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 200;
    Settings := MakeSettings(40, 40, 1, TestTempFolder + 'hires-adaptive-ss1.png');
    RenderPixels(Settings, MakeViewport(-0.5, 0, 3, 40, 40), F);
    Crc := FileCrc(Settings.FileName);
    Settings.IsAdaptive := True;
    RenderPixels(Settings, MakeViewport(-0.5, 0, 3, 40, 40), F);
    CheckEquals(IntToHex(Crc, 8), IntToHex(FileCrc(Settings.FileName), 8));
    CheckEquals(0, FRefined);
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue toute intérieure (cardioïde principale) : rien à lisser, image identique au lissage complet.
procedure TTestHiRes.TestAdaptiveFlatViewRefinesNothing;
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
  Full, Adaptive: TCardinalDynArray;
  I: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 200;
    Settings := MakeSettings(40, 30, 2, TestTempFolder + 'hires-adaptive-flat.png');
    Full := RenderPixels(Settings, MakeViewport(0, 0, 0.01, 40, 30), F);
    Settings.IsAdaptive := True;
    Adaptive := RenderPixels(Settings, MakeViewport(0, 0, 0.01, 40, 30), F);
    CheckEquals(0, FRefined, 'pixels lissés');
    CheckEquals(40 * 30, FTotal, 'pixels en tout');
    for I := 0 to High(Full) do
      CheckEquals(Integer(Full[I]), Integer(Adaptive[I]), Format('pixel %d', [I]));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue de bord (vallée des hippocampes), SS 2 et 3, avec et sans relief : proche du lissage complet, moins de
// pixels lissés que l'image n'en compte.
procedure TTestHiRes.TestAdaptiveCloseToFull;
const
  kW = 64;
  kH = 48;
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
  V: TViewport;
  Full: TCardinalDynArray;
  SS, Relief: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 500;
    V := MakeViewport(-0.745, 0.11, 0.05, kW, kH);
    for Relief := 0 to 1 do
      for SS := 2 to 3 do
      begin
        FMapping.HasRelief := Relief = 1;
        Settings := MakeSettings(kW, kH, SS, TestTempFolder + 'hires-adaptive-close.png');
        Full := RenderPixels(Settings, V, F);
        Settings.IsAdaptive := True;
        CompareToFull(RenderPixels(Settings, V, F), Full, Format('SS %d, relief %d', [SS, Relief]));
        CheckTrue(FRefined > 0, 'aucun pixel lissé');
        CheckTrue(FRefined < FTotal, 'tous les pixels lissés');
      end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Relief, bandes de 4 lignes : identique à l'adaptatif d'une seule bande (pas de raccord) et proche du complet.
procedure TTestHiRes.TestAdaptiveReliefMatchesFull;
const
  kW = 64;
  kH = 48;
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
  V: TViewport;
  Full, Whole, Banded: TCardinalDynArray;
  I: Integer;
begin
  FMapping.HasRelief := True;
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 500;
    V := MakeViewport(-0.745, 0.11, 0.05, kW, kH);
    Settings := MakeSettings(kW, kH, 2, TestTempFolder + 'hires-adaptive-relief.png');
    Full := RenderPixels(Settings, V, F, 4);
    Settings.IsAdaptive := True;
    Whole := RenderPixels(Settings, V, F, kH);
    Banded := RenderPixels(Settings, V, F, 4);
    for I := 0 to High(Whole) do
      CheckEquals(Integer(Whole[I]), Integer(Banded[I]), Format('pixel %d, %d', [I mod kW, I div kW]));
    CompareToFull(Banded, Full, 'relief, bandes de 4');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Bandes de 4 lignes sur une vue de bord, sans relief : de part et d'autre de chaque jonction, les pixels sont lissés
// comme en une seule bande (le marquage voit les voisins de la bande voisine).
procedure TTestHiRes.TestAdaptiveBandEdge;
const
  kW = 64;
  kH = 48;
  kBand = 4;
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
  V: TViewport;
  Full, Whole, Banded: TCardinalDynArray;
  I: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 500;
    V := MakeViewport(-0.745, 0.11, 0.05, kW, kH);
    Settings := MakeSettings(kW, kH, 2, TestTempFolder + 'hires-adaptive-edge.png');
    Full := RenderPixels(Settings, V, F, kBand);
    Settings.IsAdaptive := True;
    Whole := RenderPixels(Settings, V, F, kH);
    Banded := RenderPixels(Settings, V, F, kBand);
    CheckTrue(FRefined > 0, 'aucun pixel lissé');
    for I := 0 to High(Whole) do
      CheckEquals(Integer(Whole[I]), Integer(Banded[I]), Format('pixel %d, %d', [I mod kW, I div kW]));
    CompareToFull(Banded, Full, 'jonctions de bandes');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Zoom profond avec BLA (MultiBroth_1 de JF, comme TestFractalBla) : l'adaptatif ne calcule pas plus de références
// ni de tables que le lissage complet.
procedure TTestHiRes.TestAdaptiveReusesReference;
const
  kW = 48;
  kH = 32;
var
  F: TMultibrotFormula;
  Settings: THiResSettings;
  V: TViewport;
  FullReferences, FullTables: Integer;
begin
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 3);
    F.MaxIter := kMultiBroth1MaxIter;
    V := MakeExactViewport(kMultiBroth1X, kMultiBroth1Y, kMultiBroth1Width, kW, kH);
    Settings := MakeSettings(kW, kH, 2, TestTempFolder + 'hires-adaptive-deep.png');
    Settings.IsBla := True;
    RenderPixels(Settings, V, F, 8);
    FullReferences := FReferenceCount;
    FullTables := FBlaCount;
    CheckTrue(FullReferences > 0, 'rendu non perturbé');
    Settings.IsAdaptive := True;
    RenderPixels(Settings, V, F, 8);
    Status(Format('références %d / %d, tables BLA %d / %d, %d pixels lissés sur %d', [FReferenceCount,
      FullReferences, FBlaCount, FullTables, FRefined, FTotal]));
    CheckEquals(FullReferences, FReferenceCount, 'références');
    CheckTrue(FBlaCount <= FullTables, Format('tables BLA : %d contre %d', [FBlaCount, FullTables]));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Pixel juste au-dessus d'une limite de mots (-log2 + 64 = 255,5 : 8 mots) et sous-pixel juste au-dessous (9 mots),
// centre court (Double) : la référence du premier passage doit déjà avoir la précision des bandes suréchantillonnées.
procedure TTestHiRes.TestAdaptiveReferenceAtWordBoundary;
const
  kW = 48;
  kH = 32;
var
  F: TMandelbrotFormula;
  Settings: THiResSettings;
  V: TViewport;
  PixelSize: TFloat;
  FullReferences: Integer;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 2000;
    PixelSize := Power(2, -191.5);
    // c = i : point de Misiurewicz, de la structure à toutes les échelles
    V := MakeViewport(0, 1, kW * PixelSize, kW, kH);
    Settings := MakeSettings(kW, kH, 2, TestTempFolder + 'hires-adaptive-words.png');
    RenderPixels(Settings, V, F, 8);
    FullReferences := FReferenceCount;
    CheckTrue(FullReferences > 0, 'rendu non perturbé');
    Settings.IsAdaptive := True;
    RenderPixels(Settings, V, F, 8);
    CheckEquals(FullReferences, FReferenceCount, 'références');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Bandes d'une même image : la référence est celle de la première bande, l'écart des suivantes à la référence grandit
// peu à peu. Une ou deux tables BLA pour toute l'image, pas une par bande (avant correction : 16 sur 16 bandes)
procedure TTestHiRes.TestBandsShareBlaTable;
const
  kW = 48;
  kH = 64;
  kBandRows = 4;
  kMaxTables = 2;
var
  F: TMultibrotFormula;
  Settings: THiResSettings;
  V: TViewport;
begin
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 3);
    F.MaxIter := kMultiBroth1MaxIter;
    V := MakeExactViewport(kMultiBroth1X, kMultiBroth1Y, kMultiBroth1Width, kW, kH);
    Settings := MakeSettings(kW, kH, 1, TestTempFolder + 'hires-bla-bands.png');
    Settings.IsBla := True;
    RenderPixels(Settings, V, F, kBandRows);
    CheckTrue(FReferenceCount > 0, 'rendu non perturbé');
    CheckTrue(FBlaCount <= kMaxTables, Format('%d tables BLA pour %d bandes', [FBlaCount, kH div kBandRows]));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

initialization
  RegisterTest(TTestHiRes.Suite);

end.
