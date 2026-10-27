unit Fractal.Palette;

interface

uses
  SysUtils, Classes, Math, Fractal.Types, Fractal.Buffer;

const
  kLutSize = 4096;
  kRefIter = 1000.0;  // u = mu / kRefIter : les couleurs ne dépendent pas du nombre max d'itérations
  kSliderMax = 1000;
  kStretchSliderMid = 500;  // position du curseur d'étirement qui vaut exactement 1 (chemin rapide)
  kMinRepeats = 1.0;
  kMaxRepeats = 1000.0;
  kRepeatsDecades = 3;  // 10^0 .. 10^3
  kMinStretch = 0.2;
  kMaxStretch = 2.0;
  // effets : bandes, contours et relief (valeurs par défaut = premier essai agréable)
  kMinBandWidth = 1 / 64;  // largeur d'une bande, en fraction du cycle de la palette
  kMaxBandWidth = 0.25;
  kDefaultBandWidth = 1 / 16;
  kMinShading = 0.0;  // amplitude du modelé : 0 = bande plate, 1 = du noir à la couleur pleine
  kMaxShading = 1.0;
  kDefaultShading = 0.5;
  kMinContourWidth = 0.02;  // épaisseur du contour, en fraction de la bande
  kMaxContourWidth = 0.5;
  kDefaultContourWidth = 0.1;
  kFullTurnDegrees = 360.0;
  kDefaultLightAngle = 135.0;  // lumière venant du haut à gauche (0 = droite, 90 = haut)
  kMinReliefIntensity = 0.0;
  kMaxReliefIntensity = 1.0;
  kDefaultReliefIntensity = 0.6;
  kMinReliefHeight = 0.0;  // multiplicateur de la pente (altitude = position dans la palette)
  kMaxReliefHeight = 100.0;
  kDefaultReliefHeight = 8.0;
  // curseurs du panneau Effets
  kEffectSliderMax = 100;
  kMinBandCount = 4;  // une bande vaut 1/N du cycle de la palette, avec N entier : les bandes divisent le cycle
  kMaxBandCount = 64;
  kBandSliderMax = kMaxBandCount - kMinBandCount;  // à droite : N petit, donc bandes larges
  kLightAngleSliderMax = 359;  // pas de 1 degré ; 360 degrés = 0
  kInsideColor = $000000;
  kMaxStops = 1024;
  kMaxMapColors = 256;
  kMaxColorValue = $FFFFFF;  // masque d'une couleur $00RRGGBB
  kKeyName = 'Name';
  kKeyCount = 'Count';
  kKeyStop = 'Stop';

type
  EPaletteError = class(Exception);

  TColorStop = record
    Position: Double;
    Color: Cardinal;  // $00RRGGBB
  end;

  TGradientPalette = class
  private
    FName: string;
    FStops: array of TColorStop;
    function InsertStop(const S: TColorStop): Integer;
  public
    constructor Create;
    procedure Assign(Source: TGradientPalette);
    procedure Clear;
    procedure SetDefault;
    function AddStop(APosition: Double; AColor: Cardinal): Integer;
    procedure DeleteStop(Index: Integer);
    function MoveStop(Index: Integer; APosition: Double): Integer;
    procedure SetStopColor(Index: Integer; AColor: Cardinal);
    function StopCount: Integer;
    function Stop(Index: Integer): TColorStop;
    function ColorAt(T: Double): Cardinal;
    procedure SaveToStrings(Lines: TStrings);
    procedure LoadFromStrings(Lines: TStrings);
    procedure LoadFromMap(Lines: TStrings);
    property Name: string read FName write FName;
  end;

  TColoringMode = (cmSmooth, cmBands);

  TColorMapping = record
    Offset: Double;
    Repeats: Double;
    Stretch: Double;
    IsInverted: Boolean;
    Mode: TColoringMode;
    BandWidth: Double;  // cmBands : largeur d'une bande, en fraction du cycle de la palette
    Shading: Double;  // cmBands : amplitude du modelé dans la bande (0 à 1)
    HasContours: Boolean;  // cmBands : assombrit le bord haut de chaque bande
    ContourWidth: Double;  // fraction de la bande
    HasRelief: Boolean;
    LightAngle: Double;  // degrés, 0 = lumière venant de la droite, sens trigonométrique
    ReliefIntensity: Double;
    ReliefHeight: Double;
  end;

  TColorMapper = class
  private
    FLut: array[0..kLutSize - 1] of Cardinal;
    FMapping: TColorMapping;
    FLightX: Double;  // vecteur vers la lumière, précalculé au Create
    FLightY: Double;
    FLightZ: Double;
    function BandColor(T: Double): Cardinal;
    function NeighbourPosition(Mu: Single; Fallback: Double): Double;
  public
    constructor Create(APalette: TGradientPalette; const AMapping: TColorMapping);
    function PalettePosition(Mu: Single): Double;
    function HasRelief: Boolean;
    function MapValue(Mu: Single): Cardinal;
    function ShadeValue(Mu, Left, Right, Up, Down: Single): Cardinal; overload;
    function ShadeValue(Mu, Left, Right, Up, Down: Single; Distance: Integer): Cardinal; overload;
    procedure MapRow(Src: PSingle; Dest: PCardinal; Count: Integer);
    procedure MapBufferRow(Buffer: TIterationBuffer; Y: Integer; Dest: PCardinal);
  end;

function DefaultColorMapping: TColorMapping;
function ClampColorMapping(const M: TColorMapping): TColorMapping;
function MappingFromSliders(Offset, Repeats, Stretch: Integer; IsInverted: Boolean): TColorMapping;
procedure MappingToSliders(const M: TColorMapping; out Offset, Repeats, Stretch: Integer);
procedure CopyEffects(const Source: TColorMapping; var Dest: TColorMapping);
function WithDefaultColors(const M: TColorMapping): TColorMapping;
function WithDefaultEffects(const M: TColorMapping): TColorMapping;
function BandWidthFromSlider(Position: Integer): Double;
function BandWidthToSlider(Width: Double): Integer;
function ShadingFromSlider(Position: Integer): Double;
function ShadingToSlider(Shading: Double): Integer;
function ContourWidthFromSlider(Position: Integer): Double;
function ContourWidthToSlider(Width: Double): Integer;
function LightAngleFromSlider(Position: Integer): Double;
function LightAngleToSlider(Angle: Double): Integer;
function ReliefIntensityFromSlider(Position: Integer): Double;
function ReliefIntensityToSlider(Intensity: Double): Integer;
function ReliefHeightFromSlider(Position: Integer): Double;
function ReliefHeightToSlider(Height: Double): Integer;
function SwapRedBlue(C: Cardinal): Cardinal;
function BuiltInPaletteCount: Integer;
function CreateBuiltInPalette(Index: Integer): TGradientPalette;

implementation

const
  kDefaultRepeats = 25.0;
  kBuiltInCount = 5;
  kContourDarkness = 0.35;  // facteur de luminosité appliqué sur le contour
  kLightElevationDegrees = 45.0;  // hauteur de la lumière au-dessus du plan de l'image
  kDegreesToRadians = Pi / 180;
  kMaxChannel = 255;

{------------------------------------------------------------------------------}

function LerpColor(A, B: Cardinal; F: Double): Cardinal;
var
  R, G, Bl: Integer;
begin
  R := Round(((A shr 16) and $FF) * (1 - F) + ((B shr 16) and $FF) * F);
  G := Round(((A shr 8) and $FF) * (1 - F) + ((B shr 8) and $FF) * F);
  Bl := Round((A and $FF) * (1 - F) + (B and $FF) * F);
  Result := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(Bl);
end;

{------------------------------------------------------------------------------}

function MakeStop(APosition: Double; AColor: Cardinal): TColorStop;
begin
  Result.Position := EnsureRange(APosition, 0.0, 1.0);
  Result.Color := AColor and kMaxColorValue;
end;

{------------------------------------------------------------------------------}

constructor TGradientPalette.Create;
begin
  inherited Create;
  SetDefault;
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.Assign(Source: TGradientPalette);
begin
  FName := Source.FName;
  FStops := Copy(Source.FStops);
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.Clear;
begin
  SetLength(FStops, 0);
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.SetDefault;
begin
  Clear;
  AddStop(0, $000000);
  AddStop(0.5, $FFFFFF);
end;

{------------------------------------------------------------------------------}

function TGradientPalette.InsertStop(const S: TColorStop): Integer;
var
  I: Integer;
begin
  Result := Length(FStops);
  for I := 0 to High(FStops) do
    if FStops[I].Position > S.Position then
    begin
      Result := I;
      Break;
    end;
  SetLength(FStops, Length(FStops) + 1);
  for I := High(FStops) downto Result + 1 do
    FStops[I] := FStops[I - 1];
  FStops[Result] := S;
end;

{------------------------------------------------------------------------------}

function TGradientPalette.AddStop(APosition: Double; AColor: Cardinal): Integer;
begin
  Result := InsertStop(MakeStop(APosition, AColor));
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.DeleteStop(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index > High(FStops)) then
    Exit;
  for I := Index to High(FStops) - 1 do
    FStops[I] := FStops[I + 1];
  SetLength(FStops, Length(FStops) - 1);
end;

{------------------------------------------------------------------------------}

function TGradientPalette.MoveStop(Index: Integer; APosition: Double): Integer;
var
  S: TColorStop;
begin
  S := FStops[Index];
  DeleteStop(Index);
  Result := InsertStop(MakeStop(APosition, S.Color));
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.SetStopColor(Index: Integer; AColor: Cardinal);
begin
  FStops[Index].Color := AColor and kMaxColorValue;
end;

{------------------------------------------------------------------------------}

function TGradientPalette.StopCount: Integer;
begin
  Result := Length(FStops);
end;

{------------------------------------------------------------------------------}

function TGradientPalette.Stop(Index: Integer): TColorStop;
begin
  Result := FStops[Index];
end;

{------------------------------------------------------------------------------}

function TGradientPalette.ColorAt(T: Double): Cardinal;
var
  N, I: Integer;
  First, Last: TColorStop;
  Span, Local: Double;
begin
  N := Length(FStops);
  if N = 0 then
    Exit(0);
  if N = 1 then
    Exit(FStops[0].Color);
  T := T - Floor(T);
  First := FStops[0];
  Last := FStops[N - 1];
  if (T < First.Position) or (T >= Last.Position) then
  begin
    // segment qui reboucle du dernier point vers le premier
    Span := 1 - Last.Position + First.Position;
    if T >= Last.Position then
      Local := T - Last.Position
    else
      Local := T + 1 - Last.Position;
    if Span <= 0 then
      Exit(First.Color);
    Exit(LerpColor(Last.Color, First.Color, Local / Span));
  end;
  for I := 0 to N - 2 do
    if (T >= FStops[I].Position) and (T < FStops[I + 1].Position) then
    begin
      Span := FStops[I + 1].Position - FStops[I].Position;
      if Span <= 0 then
        Exit(FStops[I].Color);
      Exit(LerpColor(FStops[I].Color, FStops[I + 1].Color, (T - FStops[I].Position) / Span));
    end;
  Result := Last.Color;
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.SaveToStrings(Lines: TStrings);
var
  I: Integer;
begin
  Lines.Add(kKeyName + '=' + FName);
  Lines.Add(kKeyCount + '=' + IntToStr(Length(FStops)));
  for I := 0 to High(FStops) do
    Lines.Add(Format('%s%d=%s,%s', [kKeyStop, I, FloatToInvariant(FStops[I].Position), IntToHex(FStops[I].Color, 6)]));
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.LoadFromStrings(Lines: TStrings);
var
  I, Count, P: Integer;
  S: string;
  Position: TFloat;
  Color: Integer;
begin
  FName := Lines.Values[kKeyName];
  Count := StrToIntDef(Lines.Values[kKeyCount], kMaxStops);
  Clear;
  for I := 0 to Min(Count, kMaxStops) - 1 do
  begin
    S := Lines.Values[kKeyStop + IntToStr(I)];
    if S = '' then
      Break;
    P := Pos(',', S);
    if P = 0 then
      Continue;
    Position := InvariantToFloat(Copy(S, 1, P - 1), -1);
    Color := StrToIntDef('$' + Trim(Copy(S, P + 1, MaxInt)), -1);
    if (Position >= 0) and (Position <= 1) and (Color >= 0) and (Color <= kMaxColorValue) then
      AddStop(Position, Cardinal(Color));
  end;
  if Length(FStops) = 0 then
    SetDefault;
end;

{------------------------------------------------------------------------------}

function ReadInteger(const S: string; var P: Integer; out Value: Integer): Boolean;
var
  Start: Integer;
begin
  while (P <= Length(S)) and ((S[P] = ' ') or (S[P] = #9)) do
    Inc(P);
  Start := P;
  while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') do
    Inc(P);
  Result := (P > Start) and TryStrToInt(Copy(S, Start, P - Start), Value);
end;

{------------------------------------------------------------------------------}

procedure TGradientPalette.LoadFromMap(Lines: TStrings);
var
  Colors: array of Cardinal;
  I, P, R, G, B, N: Integer;
begin
  SetLength(Colors, 0);
  for I := 0 to Lines.Count - 1 do
  begin
    if Length(Colors) >= kMaxMapColors then
      Break;
    P := 1;
    if ReadInteger(Lines[I], P, R) and ReadInteger(Lines[I], P, G) and ReadInteger(Lines[I], P, B)
      and (R <= 255) and (G <= 255) and (B <= 255) then
    begin
      N := Length(Colors);
      SetLength(Colors, N + 1);
      Colors[N] := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
    end;
  end;
  if Length(Colors) < 2 then
    raise EPaletteError.Create('Fichier .map invalide : moins de deux couleurs lisibles.');
  Clear;
  for I := 0 to High(Colors) do
    AddStop(I / Length(Colors), Colors[I]);
end;

{------------------------------------------------------------------------------}

function ScaleColor(C: Cardinal; F: Double): Cardinal;
var
  R, G, B: Integer;
begin
  if F = 1 then
    Exit(C);
  R := Min(kMaxChannel, Round(((C shr 16) and $FF) * F));
  G := Min(kMaxChannel, Round(((C shr 8) and $FF) * F));
  B := Min(kMaxChannel, Round((C and $FF) * F));
  Result := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
end;

{------------------------------------------------------------------------------}

constructor TColorMapper.Create(APalette: TGradientPalette; const AMapping: TColorMapping);
var
  I: Integer;
  Azimuth, Elevation: Double;
begin
  inherited Create;
  FMapping := ClampColorMapping(AMapping);
  Azimuth := FMapping.LightAngle * kDegreesToRadians;
  Elevation := kLightElevationDegrees * kDegreesToRadians;
  FLightX := Cos(Azimuth) * Cos(Elevation);
  FLightY := -Sin(Azimuth) * Cos(Elevation);  // l'axe vertical de l'image descend
  FLightZ := Sin(Elevation);
  for I := 0 to kLutSize - 1 do
    FLut[I] := APalette.ColorAt(I / kLutSize);
end;

{------------------------------------------------------------------------------}

function TColorMapper.MapValue(Mu: Single): Cardinal;
var
  U, T: Double;
  I: Integer;
begin
  // IsNan d'abord : une comparaison ordonnée avec un NaN lève EInvalidOp quand les exceptions FPU sont actives
  if IsNan(Mu) or IsInfinite(Mu) or (Mu < 0) then
    Exit(kInsideColor);
  U := Mu / kRefIter;
  if FMapping.Stretch <> 1 then
    U := Power(U, FMapping.Stretch);
  T := Frac(FMapping.Offset + FMapping.Repeats * U);
  if FMapping.IsInverted then
    T := 1 - T;
  if FMapping.Mode = cmBands then
    Exit(BandColor(T));
  I := EnsureRange(Trunc(T * kLutSize), 0, kLutSize - 1);
  Result := FLut[I];
end;

{------------------------------------------------------------------------------}

function TColorMapper.BandColor(T: Double): Cardinal;
var
  Scaled, Rel, Factor: Double;
  BandIndex, I: Integer;
begin
  Scaled := T / FMapping.BandWidth;
  BandIndex := Floor(Scaled);
  Rel := Scaled - BandIndex;  // position dans la bande, de 0 (début) à 1 (bord)
  I := EnsureRange(Trunc(BandIndex * FMapping.BandWidth * kLutSize), 0, kLutSize - 1);
  Factor := 1 - FMapping.Shading * (1 - Rel);
  if FMapping.HasContours and (Rel >= 1 - FMapping.ContourWidth) then
    Factor := Factor * kContourDarkness;
  Result := ScaleColor(FLut[I], Factor);
end;

{------------------------------------------------------------------------------}

function TColorMapper.PalettePosition(Mu: Single): Double;
var
  U: Double;
begin
  if IsNan(Mu) or IsInfinite(Mu) or (Mu < 0) then
    Exit(NaN);
  U := Mu / kRefIter;
  if FMapping.Stretch <> 1 then
    U := Power(U, FMapping.Stretch);
  Result := FMapping.Offset + FMapping.Repeats * U;
end;

{------------------------------------------------------------------------------}

function TColorMapper.NeighbourPosition(Mu: Single; Fallback: Double): Double;
begin
  Result := PalettePosition(Mu);
  if IsNan(Result) then
    Result := Fallback;  // voisin absent : le pixel lui-même, pour une pente d'un seul côté
end;

{------------------------------------------------------------------------------}

function TColorMapper.HasRelief: Boolean;
begin
  Result := FMapping.HasRelief;
end;

{------------------------------------------------------------------------------}

function TColorMapper.ShadeValue(Mu, Left, Right, Up, Down: Single): Cardinal;
begin
  Result := ShadeValue(Mu, Left, Right, Up, Down, 1);
end;

{------------------------------------------------------------------------------}

function TColorMapper.ShadeValue(Mu, Left, Right, Up, Down: Single; Distance: Integer): Cardinal;
var
  Z, SlopeX, SlopeY, Lit, Scale: Double;
begin
  Result := MapValue(Mu);
  if not FMapping.HasRelief then
    Exit;
  Z := PalettePosition(Mu);
  if IsNan(Z) then
    Exit(kInsideColor);
  // pente par pixel affiché : les voisins sont à Distance pixels de chaque côté
  Scale := FMapping.ReliefHeight / (2 * Max(1, Distance));
  SlopeX := Scale * (NeighbourPosition(Right, Z) - NeighbourPosition(Left, Z));
  SlopeY := Scale * (NeighbourPosition(Down, Z) - NeighbourPosition(Up, Z));
  // normale (-SlopeX, -SlopeY, 1) normalisée, produit scalaire avec la lumière, rapporté à celui du plan plat
  Lit := (FLightZ - SlopeX * FLightX - SlopeY * FLightY) / Sqrt(SlopeX * SlopeX + SlopeY * SlopeY + 1) / FLightZ;
  Result := ScaleColor(Result, Max(0.0, 1 + FMapping.ReliefIntensity * (Lit - 1)));
end;

{------------------------------------------------------------------------------}

procedure TColorMapper.MapRow(Src: PSingle; Dest: PCardinal; Count: Integer);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    Dest^ := MapValue(Src^);
    Inc(Src);
    Inc(Dest);
  end;
end;

{------------------------------------------------------------------------------}

function ValueOrSelf(Buffer: TIterationBuffer; X, Y: Integer; Fallback: Single): Single;
begin
  if (X < 0) or (X >= Buffer.Width) or (Y < 0) or (Y >= Buffer.Height) then
    Result := Fallback  // voisin hors de l'image : le pixel lui-même, pour une pente d'un seul côté
  else
    Result := Buffer.Value(X, Y);
end;

{------------------------------------------------------------------------------}

function BlockStep(Buffer: TIterationBuffer; X, Y: Integer): Integer;
begin
  // WriteAnchor marque l'ancre du bloc au niveau 1 et le reste du bloc à la taille du bloc : l'ancre prend donc le
  // niveau de ses voisins de droite et du dessous (de gauche et du dessus au bord), sinon elle se teinterait à part
  Result := Max(1, Buffer.Level(X, Y));
  if X + 1 < Buffer.Width then
    Result := Max(Result, Buffer.Level(X + 1, Y))
  else if X > 0 then
    Result := Max(Result, Buffer.Level(X - 1, Y));
  if Y + 1 < Buffer.Height then
    Result := Max(Result, Buffer.Level(X, Y + 1))
  else if Y > 0 then
    Result := Max(Result, Buffer.Level(X, Y - 1));
end;

{------------------------------------------------------------------------------}

procedure TColorMapper.MapBufferRow(Buffer: TIterationBuffer; Y: Integer; Dest: PCardinal);
var
  X, Step, Width, Height, XLeft, XRight, YUp, YDown: Integer;
  Mu: Single;
begin
  if Buffer = nil then
    raise EPaletteError.Create('MapBufferRow : tampon absent.');
  Width := Buffer.Width;
  Height := Buffer.Height;
  if (Y < 0) or (Y >= Height) then
    Exit;
  if not FMapping.HasRelief then
  begin
    MapRow(Buffer.RowPtr(Y), Dest, Width);
    Exit;
  end;
  for X := 0 to Width - 1 do
  begin
    Mu := Buffer.Value(X, Y);
    // pendant les passes grossières, les voisins sont à la distance du bloc du pixel ; 1 quand il est exact
    Step := BlockStep(Buffer, X, Y);
    XLeft := X - Step;
    XRight := X + Step;
    YUp := Y - Step;
    YDown := Y + Step;
    Dest^ := ShadeValue(Mu,
      ValueOrSelf(Buffer, XLeft, Y, Mu), ValueOrSelf(Buffer, XRight, Y, Mu),
      ValueOrSelf(Buffer, X, YUp, Mu), ValueOrSelf(Buffer, X, YDown, Mu), Step);
    Inc(Dest);
  end;
end;

{------------------------------------------------------------------------------}

function DefaultColorMapping: TColorMapping;
begin
  Result.Offset := 0;
  Result.Repeats := kDefaultRepeats;
  Result.Stretch := 1;
  Result.IsInverted := False;
  Result.Mode := cmSmooth;
  Result.BandWidth := kDefaultBandWidth;
  Result.Shading := kDefaultShading;
  Result.HasContours := False;
  Result.ContourWidth := kDefaultContourWidth;
  Result.HasRelief := False;
  Result.LightAngle := kDefaultLightAngle;
  Result.ReliefIntensity := kDefaultReliefIntensity;
  Result.ReliefHeight := kDefaultReliefHeight;
end;

{------------------------------------------------------------------------------}

function ClampOrDefault(Value, Default, Lowest, Highest: Double): Double;
begin
  if IsNan(Value) then
    Exit(Default);
  Result := EnsureRange(Value, Lowest, Highest);
end;

{------------------------------------------------------------------------------}

function ClampColorMapping(const M: TColorMapping): TColorMapping;
begin
  Result := M;
  if IsNan(Result.Offset) or IsInfinite(Result.Offset) then
    Result.Offset := 0;
  Result.Offset := Result.Offset - Floor(Result.Offset);
  if IsNan(Result.Repeats) then
    Result.Repeats := kDefaultRepeats;
  Result.Repeats := EnsureRange(Result.Repeats, kMinRepeats, kMaxRepeats);
  if IsNan(Result.Stretch) then
    Result.Stretch := 1;
  Result.Stretch := EnsureRange(Result.Stretch, kMinStretch, kMaxStretch);
  Result.BandWidth := ClampOrDefault(Result.BandWidth, kDefaultBandWidth, kMinBandWidth, kMaxBandWidth);
  Result.Shading := ClampOrDefault(Result.Shading, kDefaultShading, kMinShading, kMaxShading);
  Result.ContourWidth := ClampOrDefault(Result.ContourWidth, kDefaultContourWidth, kMinContourWidth,
    kMaxContourWidth);
  if IsNan(Result.LightAngle) or IsInfinite(Result.LightAngle) then
    Result.LightAngle := kDefaultLightAngle;
  Result.LightAngle := Result.LightAngle - kFullTurnDegrees * Floor(Result.LightAngle / kFullTurnDegrees);
  Result.ReliefIntensity := ClampOrDefault(Result.ReliefIntensity, kDefaultReliefIntensity, kMinReliefIntensity,
    kMaxReliefIntensity);
  Result.ReliefHeight := ClampOrDefault(Result.ReliefHeight, kDefaultReliefHeight, kMinReliefHeight,
    kMaxReliefHeight);
end;

{------------------------------------------------------------------------------}

function MappingFromSliders(Offset, Repeats, Stretch: Integer; IsInverted: Boolean): TColorMapping;
begin
  Result.Offset := Offset / kSliderMax;
  Result.Repeats := Power(10, kRepeatsDecades * Repeats / kSliderMax);
  if Stretch <= kStretchSliderMid then
    Result.Stretch := kMinStretch + (1 - kMinStretch) * Stretch / kStretchSliderMid
  else
    Result.Stretch := 1 + (kMaxStretch - 1) * (Stretch - kStretchSliderMid) / (kSliderMax - kStretchSliderMid);
  Result.IsInverted := IsInverted;
  Result := ClampColorMapping(Result);
end;

{------------------------------------------------------------------------------}

procedure MappingToSliders(const M: TColorMapping; out Offset, Repeats, Stretch: Integer);
var
  C: TColorMapping;
begin
  C := ClampColorMapping(M);
  Offset := Round(C.Offset * kSliderMax);
  Repeats := Round(Log10(C.Repeats) / kRepeatsDecades * kSliderMax);
  if C.Stretch <= 1 then
    Stretch := Round((C.Stretch - kMinStretch) / (1 - kMinStretch) * kStretchSliderMid)
  else
    Stretch := kStretchSliderMid
      + Round((C.Stretch - 1) / (kMaxStretch - 1) * (kSliderMax - kStretchSliderMid));
  Stretch := EnsureRange(Stretch, 0, kSliderMax);
end;

{------------------------------------------------------------------------------}

procedure CopyEffects(const Source: TColorMapping; var Dest: TColorMapping);
begin
  Dest.Mode := Source.Mode;
  Dest.BandWidth := Source.BandWidth;
  Dest.Shading := Source.Shading;
  Dest.HasContours := Source.HasContours;
  Dest.ContourWidth := Source.ContourWidth;
  Dest.HasRelief := Source.HasRelief;
  Dest.LightAngle := Source.LightAngle;
  Dest.ReliefIntensity := Source.ReliefIntensity;
  Dest.ReliefHeight := Source.ReliefHeight;
end;

{------------------------------------------------------------------------------}

// Bouton de réinitialisation des couleurs : décalage, répétitions, étirement et inversion par défaut, effets gardés
function WithDefaultColors(const M: TColorMapping): TColorMapping;
begin
  Result := DefaultColorMapping;
  CopyEffects(M, Result);
end;

{------------------------------------------------------------------------------}

// Bouton de réinitialisation des effets : effets par défaut, couleurs gardées
function WithDefaultEffects(const M: TColorMapping): TColorMapping;
begin
  Result := M;
  CopyEffects(DefaultColorMapping, Result);
end;

{------------------------------------------------------------------------------}

function ToSliderRange(Value, Lowest, Highest: Double; Steps: Integer): Integer;
begin
  Result := EnsureRange(Round((Value - Lowest) / (Highest - Lowest) * Steps), 0, Steps);
end;

{------------------------------------------------------------------------------}

function FromSliderRange(Position: Integer; Lowest, Highest: Double; Steps: Integer): Double;
begin
  Result := Lowest + (Highest - Lowest) * EnsureRange(Position, 0, Steps) / Steps;
end;

{------------------------------------------------------------------------------}

function BandWidthFromSlider(Position: Integer): Double;
begin
  // la largeur est 1/N avec N entier : les bandes divisent exactement le cycle de la palette
  Result := 1 / (kMaxBandCount - EnsureRange(Position, 0, kBandSliderMax));
end;

{------------------------------------------------------------------------------}

function BandWidthToSlider(Width: Double): Integer;
var
  Count: Integer;
begin
  if IsNan(Width) or (Width <= 0) then
    Exit(0);
  Count := EnsureRange(Round(1 / Width), kMinBandCount, kMaxBandCount);
  Result := kMaxBandCount - Count;
end;

{------------------------------------------------------------------------------}

function ShadingFromSlider(Position: Integer): Double;
begin
  Result := FromSliderRange(Position, kMinShading, kMaxShading, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function ShadingToSlider(Shading: Double): Integer;
begin
  if IsNan(Shading) then
    Shading := kDefaultShading;
  Result := ToSliderRange(Shading, kMinShading, kMaxShading, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function ContourWidthFromSlider(Position: Integer): Double;
begin
  Result := FromSliderRange(Position, kMinContourWidth, kMaxContourWidth, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function ContourWidthToSlider(Width: Double): Integer;
begin
  if IsNan(Width) then
    Width := kDefaultContourWidth;
  Result := ToSliderRange(Width, kMinContourWidth, kMaxContourWidth, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function LightAngleFromSlider(Position: Integer): Double;
begin
  Result := EnsureRange(Position, 0, kLightAngleSliderMax);
end;

{------------------------------------------------------------------------------}

function LightAngleToSlider(Angle: Double): Integer;
begin
  if IsNan(Angle) or IsInfinite(Angle) then
    Exit(Round(kDefaultLightAngle));
  Angle := Angle - kFullTurnDegrees * Floor(Angle / kFullTurnDegrees);
  Result := Round(Angle) mod Round(kFullTurnDegrees);
end;

{------------------------------------------------------------------------------}

function ReliefIntensityFromSlider(Position: Integer): Double;
begin
  Result := FromSliderRange(Position, kMinReliefIntensity, kMaxReliefIntensity, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function ReliefIntensityToSlider(Intensity: Double): Integer;
begin
  if IsNan(Intensity) then
    Intensity := kDefaultReliefIntensity;
  Result := ToSliderRange(Intensity, kMinReliefIntensity, kMaxReliefIntensity, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function ReliefHeightFromSlider(Position: Integer): Double;
var
  F: Double;
begin
  // échelle quadratique : de la finesse près de zéro, où se trouve la valeur par défaut
  F := EnsureRange(Position, 0, kEffectSliderMax) / kEffectSliderMax;
  Result := kMinReliefHeight + (kMaxReliefHeight - kMinReliefHeight) * F * F;
end;

{------------------------------------------------------------------------------}

function ReliefHeightToSlider(Height: Double): Integer;
var
  F: Double;
begin
  if IsNan(Height) then
    Height := kDefaultReliefHeight;
  F := EnsureRange((Height - kMinReliefHeight) / (kMaxReliefHeight - kMinReliefHeight), 0.0, 1.0);
  Result := EnsureRange(Round(Sqrt(F) * kEffectSliderMax), 0, kEffectSliderMax);
end;

{------------------------------------------------------------------------------}

function SwapRedBlue(C: Cardinal): Cardinal;
begin
  Result := ((C and $FF) shl 16) or (C and $FF00) or ((C shr 16) and $FF);
end;

{------------------------------------------------------------------------------}

function BuiltInPaletteCount: Integer;
begin
  Result := kBuiltInCount;
end;

{------------------------------------------------------------------------------}

function CreateBuiltInPalette(Index: Integer): TGradientPalette;
begin
  Result := TGradientPalette.Create;
  Result.Clear;
  case Index of
    0:
      begin
        Result.Name := 'Classique';
        Result.AddStop(0, $000764);
        Result.AddStop(0.16, $206BCB);
        Result.AddStop(0.42, $EDFFFF);
        Result.AddStop(0.6425, $FFAA00);
        Result.AddStop(0.8575, $000200);
      end;
    1:
      begin
        Result.Name := 'Feu';
        Result.AddStop(0, $000000);
        Result.AddStop(0.25, $800000);
        Result.AddStop(0.5, $FF4000);
        Result.AddStop(0.75, $FFC000);
        Result.AddStop(0.9, $FFFFA0);
      end;
    2:
      begin
        Result.Name := 'Océan';
        Result.AddStop(0, $000020);
        Result.AddStop(0.3, $0050A0);
        Result.AddStop(0.6, $40C0E0);
        Result.AddStop(0.8, $E0FFFF);
      end;
    3:
      begin
        Result.Name := 'Arc-en-ciel';
        Result.AddStop(0, $FF0000);
        Result.AddStop(1 / 6, $FFFF00);
        Result.AddStop(2 / 6, $00FF00);
        Result.AddStop(3 / 6, $00FFFF);
        Result.AddStop(4 / 6, $0000FF);
        Result.AddStop(5 / 6, $FF00FF);
      end;
  else
    Result.Name := 'Gris';
    Result.AddStop(0, $000000);
    Result.AddStop(0.5, $FFFFFF);
  end;
end;

end.
