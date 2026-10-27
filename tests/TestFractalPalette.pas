unit TestFractalPalette;

interface

uses
  Classes, SysUtils, Math, TestFramework, Fractal.Types, Fractal.Buffer, Fractal.Palette;

type
  TTestPalette = class(TTestCase)
  private
    function CreateTwoStops(P1: Double; C1: Cardinal; P2: Double; C2: Cardinal): TGradientPalette;
    function CreateFlatPalette(C: Cardinal): TGradientPalette;
    function EffectMapping(AMode: TColoringMode; ABandWidth: Double): TColorMapping;
    function Red(C: Cardinal): Integer;
  published
    procedure TestColorAtStopsAndMidpoint;
    procedure TestColorAtWrapsAround;
    procedure TestMoveStopKeepsOrder;
    procedure TestStringsRoundTrip;
    procedure TestEmptyStringsGiveDefault;
    procedure TestLoadFromMap;
    procedure TestInvalidMapRaises;
    procedure TestMapperInsideIsBlack;
    procedure TestMapperRepeatsAndOffset;
    procedure TestMapperInvert;
    procedure TestMapRowMatchesMapValue;
    procedure TestSliderRoundTrip;
    procedure TestSwapRedBlue;
    procedure TestBuiltInPalettes;
    procedure TestMapperNanAndInfinityAreInside;
    procedure TestMapperStretch;
    procedure TestClampColorMapping;
    procedure TestColorAtWrapsPastLastStop;
    procedure TestDefaultsUnchanged;
    procedure TestBandsAreFlat;
    procedure TestBandsDiffer;
    procedure TestBandWidth;
    procedure TestShadingRisesInBand;
    procedure TestContoursDarkenEdge;
    procedure TestReliefLitSideBrighter;
    procedure TestReliefFlatUnchanged;
    procedure TestReliefMissingNeighbourHasNoSpike;
    procedure TestReliefIgnoresPaletteWrap;
    procedure TestInsideUnaffected;
    procedure TestClampEffectSettings;
    procedure TestEffectSliderRoundTrip;
    procedure TestBandWidthSliderIsIntegerFraction;
    procedure TestMapBufferRowWithoutReliefMatchesMapRow;
    procedure TestReliefUsesBlockLevel;
    procedure TestCopyEffects;
    procedure TestWithDefaultColorsKeepsEffects;
    procedure TestWithDefaultEffectsKeepsColors;
  end;

implementation

{------------------------------------------------------------------------------}

function TTestPalette.CreateTwoStops(P1: Double; C1: Cardinal; P2: Double; C2: Cardinal): TGradientPalette;
begin
  Result := TGradientPalette.Create;
  Result.Clear;
  Result.AddStop(P1, C1);
  Result.AddStop(P2, C2);
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestColorAtStopsAndMidpoint;
var
  P: TGradientPalette;
  R: Cardinal;
begin
  P := CreateTwoStops(0, $000000, 0.5, $FF0000);
  try
    CheckEquals(Integer($000000), Integer(P.ColorAt(0)));
    CheckEquals(Integer($FF0000), Integer(P.ColorAt(0.5)));
    R := (P.ColorAt(0.25) shr 16) and $FF;
    CheckTrue((R >= 127) and (R <= 128), IntToStr(R));
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestColorAtWrapsAround;
var
  P: TGradientPalette;
  G: Cardinal;
begin
  P := CreateTwoStops(0.25, $000000, 0.75, $FFFFFF);
  try
    // 0 est à mi-chemin entre le blanc (0,75) et le noir suivant (1,25)
    G := (P.ColorAt(0) shr 8) and $FF;
    CheckTrue((G >= 127) and (G <= 128), IntToStr(G));
    CheckEquals(Integer(P.ColorAt(0)), Integer(P.ColorAt(1.0)));
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMoveStopKeepsOrder;
var
  P: TGradientPalette;
  I: Integer;
begin
  P := CreateTwoStops(0.2, $111111, 0.6, $222222);
  try
    I := P.AddStop(0.4, $333333);
    CheckEquals(1, I);
    I := P.MoveStop(0, 0.9);
    CheckEquals(2, I);
    CheckEquals(Integer($111111), Integer(P.Stop(2).Color));
    CheckEquals(0.4, P.Stop(0).Position, 1e-12);
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestStringsRoundTrip;
var
  A, B: TGradientPalette;
  L: TStringList;
  I: Integer;
begin
  A := CreateBuiltInPalette(1);
  B := TGradientPalette.Create;
  L := TStringList.Create;
  try
    A.SaveToStrings(L);
    B.LoadFromStrings(L);
    CheckEquals(A.Name, B.Name);
    CheckEquals(A.StopCount, B.StopCount);
    for I := 0 to A.StopCount - 1 do
    begin
      CheckEquals(A.Stop(I).Position, B.Stop(I).Position, 1e-6);
      CheckEquals(Integer(A.Stop(I).Color), Integer(B.Stop(I).Color));
    end;
  finally
    L.Free;
    B.Free;
    A.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestEmptyStringsGiveDefault;
var
  P: TGradientPalette;
  L: TStringList;
begin
  P := TGradientPalette.Create;
  L := TStringList.Create;
  try
    L.Add('Stop0=pas un nombre');
    P.LoadFromStrings(L);
    CheckEquals(2, P.StopCount);
  finally
    L.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestLoadFromMap;
var
  P: TGradientPalette;
  L: TStringList;
begin
  P := TGradientPalette.Create;
  L := TStringList.Create;
  try
    L.Add('255 0 0 rouge');
    L.Add('');
    L.Add('  0 255   0');
    L.Add('0'#9'0'#9'255');
    P.LoadFromMap(L);
    CheckEquals(3, P.StopCount);
    CheckEquals(Integer($FF0000), Integer(P.Stop(0).Color));
    CheckEquals(Integer($00FF00), Integer(P.Stop(1).Color));
    CheckEquals(Integer($0000FF), Integer(P.Stop(2).Color));
    CheckEquals(1 / 3, P.Stop(1).Position, 1e-12);
  finally
    L.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestInvalidMapRaises;
var
  P: TGradientPalette;
  L: TStringList;
  IsRaised: Boolean;
begin
  P := TGradientPalette.Create;
  L := TStringList.Create;
  try
    L.Add('12 34 56');
    L.Add('bonjour');
    IsRaised := False;
    try
      P.LoadFromMap(L);
    except
      on EPaletteError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    L.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapperInsideIsBlack;
var
  P: TGradientPalette;
  M: TColorMapper;
begin
  P := CreateTwoStops(0, $FFFFFF, 0.5, $FF0000);
  M := TColorMapper.Create(P, DefaultColorMapping);
  try
    CheckEquals(0, Integer(M.MapValue(kInside)));
    CheckEquals(0, Integer(M.MapValue(kNotComputed)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapperRepeatsAndOffset;
var
  P: TGradientPalette;
  A, B, C: TColorMapper;
  MA, MB, MC: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  MA := DefaultColorMapping;
  MA.Repeats := 10;
  MB := MA;
  MB.Repeats := 20;
  MC := MA;
  MC.Offset := 0.5;
  A := TColorMapper.Create(P, MA);
  B := TColorMapper.Create(P, MB);
  C := TColorMapper.Create(P, MC);
  try
    CheckEquals(Integer(A.MapValue(50)), Integer(B.MapValue(25)));
    // 50 itérations avec Répétition 10 donnent t = 0,5 ; un décalage de 0,5 le ramène à 0
    CheckEquals(Integer(A.MapValue(0)), Integer(C.MapValue(50)));
  finally
    C.Free;
    B.Free;
    A.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapperInvert;
var
  P: TGradientPalette;
  A, B: TColorMapper;
  M: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  M := DefaultColorMapping;
  M.Repeats := 10;
  A := TColorMapper.Create(P, M);
  M.IsInverted := True;
  B := TColorMapper.Create(P, M);
  try
    // t = 0,25 inversé = 0,75
    CheckEquals(Integer(A.MapValue(75)), Integer(B.MapValue(25)));
  finally
    B.Free;
    A.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapRowMatchesMapValue;
const
  kCount = 5;
var
  P: TGradientPalette;
  M: TColorMapper;
  Src: array[0..kCount - 1] of Single;
  Dest: array[0..kCount - 1] of Cardinal;
  I: Integer;
begin
  P := CreateBuiltInPalette(2);
  M := TColorMapper.Create(P, DefaultColorMapping);
  try
    Src[0] := kInside;
    Src[1] := 0;
    Src[2] := 3.7;
    Src[3] := 120.25;
    Src[4] := 999;
    M.MapRow(@Src[0], @Dest[0], kCount);
    for I := 0 to kCount - 1 do
      CheckEquals(Integer(M.MapValue(Src[I])), Integer(Dest[I]));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestSliderRoundTrip;
var
  M: TColorMapping;
  O, R, S: Integer;
begin
  M := MappingFromSliders(250, 500, 500, True);
  CheckEquals(0.25, M.Offset, 1e-9);
  CheckTrue(M.IsInverted);
  CheckTrue(M.Stretch = 1, 'Stretch exactement 1');
  MappingToSliders(M, O, R, S);
  CheckEquals(250, O);
  CheckEquals(500, R);
  CheckEquals(500, S);
  M := MappingFromSliders(0, 0, 200, False);
  CheckTrue(M.Stretch < 1);
  MappingToSliders(M, O, R, S);
  CheckEquals(200, S);
  M := MappingFromSliders(0, 0, 800, False);
  CheckTrue(M.Stretch > 1);
  MappingToSliders(M, O, R, S);
  CheckEquals(800, S);
  MappingToSliders(DefaultColorMapping, O, R, S);
  CheckEquals(500, S);
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestSwapRedBlue;
begin
  CheckEquals(Integer($332211), Integer(SwapRedBlue($112233)));
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestBuiltInPalettes;
var
  I: Integer;
  P: TGradientPalette;
begin
  CheckTrue(BuiltInPaletteCount >= 5);
  for I := 0 to BuiltInPaletteCount - 1 do
  begin
    P := CreateBuiltInPalette(I);
    try
      CheckTrue(P.StopCount >= 2, P.Name);
      CheckTrue(P.Name <> '');
    finally
      P.Free;
    end;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapperNanAndInfinityAreInside;
var
  P: TGradientPalette;
  M: TColorMapper;
  V: Single;
begin
  P := CreateBuiltInPalette(0);
  M := TColorMapper.Create(P, DefaultColorMapping);
  try
    V := NaN;
    CheckEquals(0, Integer(M.MapValue(V)));
    V := Infinity;
    CheckEquals(0, Integer(M.MapValue(V)));
    V := NegInfinity;
    CheckEquals(0, Integer(M.MapValue(V)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapperStretch;
var
  P: TGradientPalette;
  A, B: TColorMapper;
  MA, MB: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  MA := DefaultColorMapping;
  MA.Repeats := 10;
  MA.Stretch := 0.5;
  MB := MA;
  MB.Stretch := 1;
  A := TColorMapper.Create(P, MA);
  B := TColorMapper.Create(P, MB);
  try
    // mu = 250 : u = 0,25 ; u^0,5 = 0,5 ; équivaut à u = 0,5 (mu = 500) sans étirement
    CheckEquals(Integer(B.MapValue(500)), Integer(A.MapValue(250)));
  finally
    B.Free;
    A.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestClampColorMapping;
var
  M, R: TColorMapping;
begin
  M := DefaultColorMapping;
  M.Repeats := 0;
  CheckEquals(kMinRepeats, ClampColorMapping(M).Repeats, 1e-12);
  M.Repeats := 1e6;
  CheckEquals(kMaxRepeats, ClampColorMapping(M).Repeats, 1e-12);
  M := DefaultColorMapping;
  M.Stretch := 0;
  CheckEquals(kMinStretch, ClampColorMapping(M).Stretch, 1e-12);
  M.Stretch := 9;
  CheckEquals(kMaxStretch, ClampColorMapping(M).Stretch, 1e-12);
  M := DefaultColorMapping;
  M.Offset := 1.25;
  CheckEquals(0.25, ClampColorMapping(M).Offset, 1e-12);
  M.Offset := NaN;
  R := ClampColorMapping(M);
  CheckEquals(0, R.Offset, 1e-12);
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestColorAtWrapsPastLastStop;
var
  P: TGradientPalette;
  G: Cardinal;
begin
  P := CreateTwoStops(0.25, $000000, 0.75, $FFFFFF);
  try
    // 0,9 est après le dernier point : entre le blanc (0,75) et le noir qui reboucle (1,25)
    G := (P.ColorAt(0.9) shr 8) and $FF;
    CheckTrue((G > 0) and (G < 255), IntToStr(G));
    CheckTrue(P.ColorAt(0.9) <> P.ColorAt(0.75));
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestPalette.CreateFlatPalette(C: Cardinal): TGradientPalette;
begin
  Result := CreateTwoStops(0, C, 0.5, C);
end;

{------------------------------------------------------------------------------}

function TTestPalette.EffectMapping(AMode: TColoringMode; ABandWidth: Double): TColorMapping;
begin
  Result := DefaultColorMapping;
  Result.Repeats := 1;
  Result.Mode := AMode;
  Result.BandWidth := ABandWidth;
  Result.Shading := 0;
  Result.HasContours := False;
  Result.HasRelief := False;
end;

{------------------------------------------------------------------------------}

function TTestPalette.Red(C: Cardinal): Integer;
begin
  Result := (C shr 16) and $FF;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestDefaultsUnchanged;
const
  kSamples = 1000;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
  Pass, I: Integer;
  Mu: Single;
  U, T: Double;
  Expected: Cardinal;
begin
  P := CreateBuiltInPalette(0);
  try
    CheckTrue(DefaultColorMapping.Mode = cmSmooth);
    CheckFalse(DefaultColorMapping.HasContours);
    CheckFalse(DefaultColorMapping.HasRelief);
    for Pass := 0 to 2 do
    begin
      Map := DefaultColorMapping;
      if Pass = 1 then
      begin
        Map.Offset := 0.3;
        Map.Stretch := 0.6;
        Map.IsInverted := True;
      end;
      if Pass = 2 then
        Map.Repeats := 333;
      M := TColorMapper.Create(P, Map);
      try
        for I := -20 to kSamples do
        begin
          Mu := I * 1.37;
          // implémentation d'origine recopiée
          if Mu < 0 then
            Expected := kInsideColor
          else
          begin
            U := Mu / kRefIter;
            if Map.Stretch <> 1 then
              U := Power(U, Map.Stretch);
            T := Frac(Map.Offset + Map.Repeats * U);
            if Map.IsInverted then
              T := 1 - T;
            Expected := P.ColorAt(EnsureRange(Trunc(T * kLutSize), 0, kLutSize - 1) / kLutSize);
          end;
          CheckEquals(Integer(Expected), Integer(M.MapValue(Mu)), Format('pass %d mu %g', [Pass, Mu]));
        end;
      finally
        M.Free;
      end;
    end;
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestBandsAreFlat;
var
  P: TGradientPalette;
  M: TColorMapper;
begin
  P := CreateBuiltInPalette(4);
  M := TColorMapper.Create(P, EffectMapping(cmBands, 0.125));
  try
    // la bande 0 couvre mu de 0 à 125
    CheckEquals(Integer(M.MapValue(5)), Integer(M.MapValue(60)));
    CheckEquals(Integer(M.MapValue(5)), Integer(M.MapValue(120)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestBandsDiffer;
var
  P: TGradientPalette;
  M: TColorMapper;
begin
  P := CreateBuiltInPalette(4);
  M := TColorMapper.Create(P, EffectMapping(cmBands, 0.125));
  try
    CheckTrue(M.MapValue(60) <> M.MapValue(190));
    CheckTrue(M.MapValue(190) <> M.MapValue(310));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestBandWidth;
var
  P: TGradientPalette;
  Narrow, Wide: TColorMapper;
begin
  P := CreateBuiltInPalette(4);
  Narrow := TColorMapper.Create(P, EffectMapping(cmBands, 0.0625));
  Wide := TColorMapper.Create(P, EffectMapping(cmBands, 0.25));
  try
    // bandes étroites : 30 et 90 sont dans deux bandes (0-62,5 et 62,5-125) ; bandes larges : dans la même (0-250)
    CheckTrue(Narrow.MapValue(30) <> Narrow.MapValue(90));
    CheckEquals(Integer(Wide.MapValue(30)), Integer(Wide.MapValue(90)));
    CheckTrue(Wide.MapValue(30) <> Wide.MapValue(290));
  finally
    Wide.Free;
    Narrow.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestShadingRisesInBand;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
begin
  P := CreateFlatPalette($808080);
  Map := EffectMapping(cmBands, 0.125);
  Map.Shading := 0.6;
  M := TColorMapper.Create(P, Map);
  try
    CheckTrue(Red(M.MapValue(10)) < Red(M.MapValue(60)));
    CheckTrue(Red(M.MapValue(60)) < Red(M.MapValue(120)));
    // la bande suivante recommence au même niveau sombre
    CheckEquals(Red(M.MapValue(10)), Red(M.MapValue(135)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestContoursDarkenEdge;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
begin
  P := CreateFlatPalette($808080);
  try
    Map := EffectMapping(cmBands, 0.125);
    Map.HasContours := True;
    Map.ContourWidth := 0.2;
    M := TColorMapper.Create(P, Map);
    try
      // bande 0 : 0-125 ; le contour occupe les 20 % du bord haut (mu 100 à 125)
      CheckEquals(Red(M.MapValue(10)), Red(M.MapValue(90)));
      CheckTrue(Red(M.MapValue(110)) < Red(M.MapValue(90)));
      CheckTrue(Red(M.MapValue(124)) < Red(M.MapValue(90)));
      // la bande suivante repart sans contour
      CheckEquals(Red(M.MapValue(10)), Red(M.MapValue(135)));
    finally
      M.Free;
    end;
    Map.HasContours := False;
    M := TColorMapper.Create(P, Map);
    try
      CheckEquals(Red(M.MapValue(10)), Red(M.MapValue(124)));
    finally
      M.Free;
    end;
  finally
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestReliefLitSideBrighter;
var
  P: TGradientPalette;
  Lit, Shadow: TColorMapper;
  Map: TColorMapping;
  LitColor, ShadowColor: Cardinal;
begin
  P := CreateFlatPalette($808080);
  Map := EffectMapping(cmSmooth, 0.125);
  Map.HasRelief := True;
  Map.ReliefIntensity := 1;
  Map.ReliefHeight := 20;
  Map.LightAngle := 180;
  Lit := TColorMapper.Create(P, Map);
  Map.LightAngle := 0;
  Shadow := TColorMapper.Create(P, Map);
  try
    // plan montant vers la droite : éclairé par la gauche (180 degrés) il est clair, par la droite il est sombre
    LitColor := Lit.ShadeValue(500, 400, 600, 500, 500);
    ShadowColor := Shadow.ShadeValue(500, 400, 600, 500, 500);
    CheckTrue(Red(LitColor) > Red(ShadowColor), Format('%x %x', [LitColor, ShadowColor]));
    CheckTrue(Red(LitColor) > $80);
    CheckTrue(Red(ShadowColor) < $80);
    // même chose dans l'axe vertical : lumière du haut (90) sur un plan montant vers le bas
    Map.LightAngle := 90;
    Lit.Free;
    Lit := TColorMapper.Create(P, Map);
    Map.LightAngle := 270;
    Shadow.Free;
    Shadow := TColorMapper.Create(P, Map);
    CheckTrue(Red(Lit.ShadeValue(500, 500, 500, 400, 600)) > Red(Shadow.ShadeValue(500, 500, 500, 400, 600)));
  finally
    Shadow.Free;
    Lit.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestReliefFlatUnchanged;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  Map := DefaultColorMapping;
  Map.HasRelief := True;
  M := TColorMapper.Create(P, Map);
  try
    CheckEquals(Integer(M.MapValue(321)), Integer(M.ShadeValue(321, 321, 321, 321, 321)));
    CheckEquals(Integer(M.MapValue(7)), Integer(M.ShadeValue(7, 7, 7, 7, 7)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestReliefMissingNeighbourHasNoSpike;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
begin
  P := CreateFlatPalette($808080);
  Map := EffectMapping(cmSmooth, 0.125);
  Map.HasRelief := True;
  Map.ReliefIntensity := 1;
  Map.ReliefHeight := 20;
  M := TColorMapper.Create(P, Map);
  try
    // voisin absent (non calculé, intérieur, NaN) = le pixel lui-même
    CheckEquals(Integer(M.ShadeValue(500, 500, 510, 500, 500)),
      Integer(M.ShadeValue(500, kNotComputed, 510, 500, 500)));
    CheckEquals(Integer(M.ShadeValue(500, 500, 510, 500, 500)),
      Integer(M.ShadeValue(500, kInside, 510, 500, 500)));
    CheckEquals(Integer(M.ShadeValue(500, 500, 500, 500, 505)),
      Integer(M.ShadeValue(500, NaN, 500, NaN, 505)));
    CheckEquals(Integer(M.MapValue(500)), Integer(M.ShadeValue(500, kInside, kInside, kNotComputed, NaN)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestReliefIgnoresPaletteWrap;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
begin
  P := CreateFlatPalette($808080);
  Map := DefaultColorMapping;
  Map.Repeats := 100;
  Map.HasRelief := True;
  Map.ReliefIntensity := 1;
  Map.ReliefHeight := 1;
  M := TColorMapper.Create(P, Map);
  try
    // mu 9,9 et 10,1 : positions 0,99 et 1,01 de part et d'autre du repli ; la pente reste de 0,01 par pixel
    CheckTrue(Abs(Red(M.ShadeValue(10, 9.9, 10.1, 10, 10)) - Red(M.MapValue(10))) <= 2);
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestInsideUnaffected;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  Map := DefaultColorMapping;
  Map.Mode := cmBands;
  Map.HasContours := True;
  Map.HasRelief := True;
  Map.Shading := 1;
  M := TColorMapper.Create(P, Map);
  try
    CheckEquals(Integer(kInsideColor), Integer(M.MapValue(kInside)));
    CheckEquals(Integer(kInsideColor), Integer(M.MapValue(NaN)));
    CheckEquals(Integer(kInsideColor), Integer(M.ShadeValue(kInside, 100, 200, 300, 400)));
    CheckTrue(IsNan(M.PalettePosition(kInside)));
    CheckTrue(IsNan(M.PalettePosition(kNotComputed)));
  finally
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestClampEffectSettings;
var
  M, R: TColorMapping;
begin
  M := DefaultColorMapping;
  M.BandWidth := 0;
  M.Shading := 9;
  M.ContourWidth := -1;
  M.ReliefIntensity := 9;
  M.ReliefHeight := 1e9;
  M.LightAngle := 725;
  R := ClampColorMapping(M);
  CheckEquals(kMinBandWidth, R.BandWidth, 1e-12);
  CheckEquals(kMaxShading, R.Shading, 1e-12);
  CheckEquals(kMinContourWidth, R.ContourWidth, 1e-12);
  CheckEquals(kMaxReliefIntensity, R.ReliefIntensity, 1e-12);
  CheckEquals(kMaxReliefHeight, R.ReliefHeight, 1e-12);
  CheckEquals(5, R.LightAngle, 1e-9);
  M.BandWidth := NaN;
  M.LightAngle := NaN;
  R := ClampColorMapping(M);
  CheckEquals(kDefaultBandWidth, R.BandWidth, 1e-12);
  CheckEquals(kDefaultLightAngle, R.LightAngle, 1e-12);
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestEffectSliderRoundTrip;
var
  Pos: Integer;
begin
  for Pos := 0 to kEffectSliderMax do
  begin
    CheckEquals(Pos, ShadingToSlider(ShadingFromSlider(Pos)), 'modelé');
    CheckEquals(Pos, ContourWidthToSlider(ContourWidthFromSlider(Pos)), 'contour');
    CheckEquals(Pos, ReliefIntensityToSlider(ReliefIntensityFromSlider(Pos)), 'intensité');
    CheckEquals(Pos, ReliefHeightToSlider(ReliefHeightFromSlider(Pos)), 'hauteur');
  end;
  for Pos := 0 to kLightAngleSliderMax do
    CheckEquals(Pos, LightAngleToSlider(LightAngleFromSlider(Pos)), 'lumière');
  CheckEquals(kMinShading, ShadingFromSlider(0), 1e-12);
  CheckEquals(kMaxShading, ShadingFromSlider(kEffectSliderMax), 1e-12);
  CheckEquals(kMaxReliefHeight, ReliefHeightFromSlider(kEffectSliderMax), 1e-9);
  CheckEquals(kDefaultReliefHeight, ReliefHeightFromSlider(ReliefHeightToSlider(kDefaultReliefHeight)), 0.5);
  CheckEquals(kDefaultLightAngle, LightAngleFromSlider(LightAngleToSlider(kDefaultLightAngle)), 1e-9);
  // NaN : ni exception ni position hors plage
  CheckEquals(ShadingToSlider(kDefaultShading), ShadingToSlider(NaN));
  CheckEquals(ContourWidthToSlider(kDefaultContourWidth), ContourWidthToSlider(NaN));
  CheckEquals(ReliefIntensityToSlider(kDefaultReliefIntensity), ReliefIntensityToSlider(NaN));
  CheckEquals(ReliefHeightToSlider(kDefaultReliefHeight), ReliefHeightToSlider(NaN));
  CheckEquals(LightAngleToSlider(kDefaultLightAngle), LightAngleToSlider(NaN));
  // hors bornes : ramené dans la plage du curseur
  CheckEquals(0, ShadingToSlider(-5));
  CheckEquals(kEffectSliderMax, ContourWidthToSlider(99));
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestBandWidthSliderIsIntegerFraction;
var
  Pos, N: Integer;
  W: Double;
begin
  for Pos := 0 to kBandSliderMax do
  begin
    W := BandWidthFromSlider(Pos);
    N := Round(1 / W);
    CheckEquals(N, 1 / W, 1e-9, 'la bande divise exactement le cycle');
    CheckTrue((N >= kMinBandCount) and (N <= kMaxBandCount));
    CheckEquals(Pos, BandWidthToSlider(W), 'aller-retour');
  end;
  // curseur à droite = bandes larges
  CheckEquals(kMaxBandWidth, BandWidthFromSlider(kBandSliderMax), 1e-12);
  CheckEquals(kMinBandWidth, BandWidthFromSlider(0), 1e-12);
  // une largeur qui n'est pas 1/N (ancien fichier) se range sur le N le plus proche
  CheckEquals(BandWidthToSlider(1 / 16), BandWidthToSlider(0.0627));
  CheckEquals(kBandSliderMax, BandWidthToSlider(0.9));
  CheckEquals(0, BandWidthToSlider(0.0001));
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestMapBufferRowWithoutReliefMatchesMapRow;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
  Buf: TIterationBuffer;
  X, Y: Integer;
  Expected, Actual: array of Cardinal;
begin
  P := CreateBuiltInPalette(0);
  Map := DefaultColorMapping;
  Map.Mode := cmBands;
  Map.HasContours := True;
  M := TColorMapper.Create(P, Map);
  Buf := TIterationBuffer.Create(9, 3);
  try
    for Y := 0 to 2 do
      for X := 0 to 8 do
        Buf.WriteAnchor(X, Y, 1, 17.5 * (X + 3 * Y));
    Buf.WriteAnchor(4, 1, 1, kInside);
    SetLength(Expected, 9);
    SetLength(Actual, 9);
    for Y := 0 to 2 do
    begin
      M.MapRow(Buf.RowPtr(Y), @Expected[0], 9);
      M.MapBufferRow(Buf, Y, @Actual[0]);
      for X := 0 to 8 do
        CheckEquals(Integer(Expected[X]), Integer(Actual[X]), Format('pixel %d,%d', [X, Y]));
    end;
  finally
    Buf.Free;
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestReliefUsesBlockLevel;
const
  kStep = 4;
  kWidth = 16;
  kHeight = 8;
  kFlat = $808080;
var
  P: TGradientPalette;
  M: TColorMapper;
  Map: TColorMapping;
  Buf: TIterationBuffer;
  X, Y, BX: Integer;
  Row: array of Cardinal;
  BlockRows: array[0..kStep - 1] of array of Cardinal;
  Expected: Cardinal;
begin
  P := CreateFlatPalette(kFlat);
  Map := DefaultColorMapping;
  Map.HasRelief := True;
  Map.ReliefIntensity := 1;
  Map.ReliefHeight := 1;
  M := TColorMapper.Create(P, Map);
  Buf := TIterationBuffer.Create(kWidth, kHeight);
  try
    // passe grossière : une ancre tous les 4 pixels, valeur linéaire en X
    for Y := 0 to kHeight div kStep - 1 do
      for X := 0 to kWidth div kStep - 1 do
        Buf.WriteAnchor(X * kStep, Y * kStep, kStep, 200 + 8 * X * kStep);
    SetLength(Row, kWidth);
    M.MapBufferRow(Buf, 1, @Row[0]);
    // bloc du milieu (colonnes 4 à 7) : voisins pris à 4 pixels, donc pente non nulle
    Expected := M.ShadeValue(Buf.Value(5, 1), Buf.Value(1, 1), Buf.Value(9, 1), Buf.Value(5, 1), Buf.Value(5, 1),
      kStep);
    CheckEquals(Integer(Expected), Integer(Row[5]));
    CheckTrue(Row[5] <> kFlat, 'relief au milieu d''un bloc non plat');
    // aucun pixel ne sature, et un bloc reste d'une seule teinte
    for X := 0 to kWidth - 1 do
      CheckTrue(((Row[X] shr 16) and $FF) < 255, 'pas de saturation en colonne ' + IntToStr(X));
    for BX := 1 to 2 do
      for X := BX * kStep to BX * kStep + kStep - 1 do
        CheckEquals(Integer(Row[BX * kStep]), Integer(Row[X]), 'bloc uniforme');
    // le pixel ancre (premier pixel du bloc, niveau 1) doit se teinter comme le reste de son bloc : lignes 0 à 3
    for Y := 0 to kStep - 1 do
    begin
      SetLength(BlockRows[Y], kWidth);
      M.MapBufferRow(Buf, Y, @BlockRows[Y][0]);
    end;
    for BX := 1 to 2 do
      for Y := 0 to kStep - 1 do
        for X := BX * kStep to BX * kStep + kStep - 1 do
        begin
          CheckEquals(Integer(BlockRows[0][BX * kStep]), Integer(BlockRows[Y][X]),
            Format('bloc uniforme, pixel %d,%d', [X, Y]));
          CheckTrue(((BlockRows[Y][X] shr 16) and $FF) < 255, 'pas de saturation sur le bloc');
        end;
  finally
    Buf.Free;
    M.Free;
    P.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestCopyEffects;
var
  Src, Dest: TColorMapping;
begin
  Src := DefaultColorMapping;
  Src.Offset := 0.3;
  Src.Mode := cmBands;
  Src.BandWidth := 0.125;
  Src.Shading := 0.9;
  Src.HasContours := True;
  Src.ContourWidth := 0.3;
  Src.HasRelief := True;
  Src.LightAngle := 77;
  Src.ReliefIntensity := 0.2;
  Src.ReliefHeight := 33;
  Dest := DefaultColorMapping;
  Dest.Repeats := 7;
  Dest.IsInverted := True;
  CopyEffects(Src, Dest);
  CheckTrue(Dest.Mode = cmBands);
  CheckEquals(0.125, Dest.BandWidth, 1e-12);
  CheckEquals(0.9, Dest.Shading, 1e-12);
  CheckTrue(Dest.HasContours);
  CheckEquals(0.3, Dest.ContourWidth, 1e-12);
  CheckTrue(Dest.HasRelief);
  CheckEquals(77, Dest.LightAngle, 1e-12);
  CheckEquals(0.2, Dest.ReliefIntensity, 1e-12);
  CheckEquals(33, Dest.ReliefHeight, 1e-12);
  // les champs de couleur ne bougent pas
  CheckEquals(0, Dest.Offset, 1e-12);
  CheckEquals(7, Dest.Repeats, 1e-12);
  CheckTrue(Dest.IsInverted);
end;

{------------------------------------------------------------------------------}

function CustomizedMapping: TColorMapping;
begin
  Result := DefaultColorMapping;
  Result.Offset := 0.3;
  Result.Repeats := 7;
  Result.Stretch := 2;
  Result.IsInverted := True;
  Result.Mode := cmBands;
  Result.Shading := 0.9;
  Result.HasContours := True;
  Result.HasRelief := True;
  Result.ReliefHeight := 33;
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestWithDefaultColorsKeepsEffects;
var
  M, Default: TColorMapping;
begin
  M := WithDefaultColors(CustomizedMapping);
  Default := DefaultColorMapping;
  CheckEquals(Default.Offset, M.Offset, 1e-12);
  CheckEquals(Default.Repeats, M.Repeats, 1e-12);
  CheckEquals(Default.Stretch, M.Stretch, 1e-12);
  CheckFalse(M.IsInverted);
  // les effets ne bougent pas
  CheckTrue(M.Mode = cmBands);
  CheckEquals(0.9, M.Shading, 1e-12);
  CheckTrue(M.HasContours);
  CheckTrue(M.HasRelief);
  CheckEquals(33, M.ReliefHeight, 1e-12);
end;

{------------------------------------------------------------------------------}

procedure TTestPalette.TestWithDefaultEffectsKeepsColors;
var
  M, Default: TColorMapping;
begin
  M := WithDefaultEffects(CustomizedMapping);
  Default := DefaultColorMapping;
  CheckTrue(M.Mode = cmSmooth);
  CheckEquals(Default.Shading, M.Shading, 1e-12);
  CheckFalse(M.HasContours);
  CheckFalse(M.HasRelief);
  CheckEquals(Default.ReliefHeight, M.ReliefHeight, 1e-12);
  // les couleurs ne bougent pas
  CheckEquals(0.3, M.Offset, 1e-12);
  CheckEquals(7, M.Repeats, 1e-12);
  CheckEquals(2, M.Stretch, 1e-12);
  CheckTrue(M.IsInverted);
end;

initialization
  RegisterTest(TTestPalette.Suite);

end.
