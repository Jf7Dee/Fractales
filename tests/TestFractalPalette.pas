unit TestFractalPalette;

interface

uses
  Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Palette;

type
  TTestPalette = class(TTestCase)
  private
    function CreateTwoStops(P1: Double; C1: Cardinal; P2: Double; C2: Cardinal): TGradientPalette;
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
  M := MappingFromSliders(250, 500, 444, True);
  CheckEquals(0.25, M.Offset, 1e-9);
  CheckTrue(M.IsInverted);
  MappingToSliders(M, O, R, S);
  CheckEquals(250, O);
  CheckEquals(500, R);
  CheckEquals(444, S);
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

initialization
  RegisterTest(TTestPalette.Suite);

end.
