unit Fractal.Persistence;

interface

uses
  Windows, SysUtils, Classes, IniFiles, Math, ShlObj, Fractal.Types, Fractal.HighFloat, Fractal.Formulas,
  Fractal.Palette;

const
  kLocationExtension = '.frac';

type
  EFractalFileError = class(Exception);

  // Un « lieu » : tout ce qu'il faut pour retrouver exactement une vue.
  TFractalLocation = class
  private
    FFormulaName: string;
    FParams: TStringList;
    FCenterX: TFloat;
    FCenterY: TFloat;
    FWidth: TFloat;
    FMaxIter: Integer;
    FIsAutoIter: Boolean;
    FMapping: TColorMapping;
    FPalette: TGradientPalette;
    function DoCreateFormula: TFractalFormula;
    procedure DoLoadFromText(const AText: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure CaptureFrom(Formula: TFractalFormula; const V: TViewport; AIsAutoIter: Boolean;
      APalette: TGradientPalette; const AMapping: TColorMapping);
    function CreateFormula: TFractalFormula;
    procedure ApplyTo(var V: TViewport);
    function SaveToText: string;
    procedure LoadFromText(const AText: string);
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);
    property FormulaName: string read FFormulaName;
    property Params: TStringList read FParams;
    property CenterX: TFloat read FCenterX;
    property CenterY: TFloat read FCenterY;
    property Width: TFloat read FWidth;
    property MaxIter: Integer read FMaxIter;
    property IsAutoIter: Boolean read FIsAutoIter;
    property Mapping: TColorMapping read FMapping;
    property Palette: TGradientPalette read FPalette;
  end;

  // Un favori = un fichier .frac dans un dossier.
  TFavoriteStore = class
  private
    FFolder: string;
  public
    constructor Create(const AFolder: string);
    procedure List(Names: TStrings);
    function Save(const AName: string; Location: TFractalLocation): string;
    procedure Load(const AName: string; Location: TFractalLocation);
    procedure Delete(const AName: string);
    function FileNameOf(const AName: string): string;
    property Folder: string read FFolder;
  end;

function SanitizeFileName(const S: string): string;
function SuggestedName(Formula: TFractalFormulaClass; const V: TViewport; When: TDateTime): string;
function UniqueBaseName(const Folder, Base, Extension: string): string;
function AppDataFolder: string;
function PaletteFolder: string;
function FavoritesFolder: string;

implementation

const
  kCenterWords = 4;   // mots de fraction du centre relu (provisoire : la tâche 3 le lit en haute précision)
  kSectionFractal = 'Fractal';
  kSectionParams = 'Params';
  kSectionColors = 'Colors';
  kSectionPalette = 'Palette';
  kDefaultFormula = 'Mandelbrot';
  kFormatVersion = 1;
  kMinLocationWidth: Double = 1e-300;
  kMaxLocationWidth: Double = 1e300;
  kInvalidFileChars = '\/:*?"<>|';
  kUnnamed = 'Sans nom';
  kNoLocationMessage = 'Ce fichier ne contient pas de lieu fractal.';
  kNameSeparator = '_';
  kNameDateFormat = 'yyyymmdd-hhnn';
  kCentreName = 'centre';
  kCentreRadius = 0.05;      // en largeurs initiales : en deçà, la vue est « au centre »
  kScientificZoom = 1000;    // à partir de ce facteur, le zoom s'écrit 2.4e5
  // secteurs de 45° dans le sens trigonométrique, en partant de l'est
  kCompassPoints: array[0..7] of string = ('E', 'NE', 'N', 'NO', 'O', 'SO', 'S', 'SE');

function CompassDirection(DX, DY: TFloat): string; forward;
function ZoomLabel(Zoom: TFloat): string; forward;
function OneDecimal(Value: TFloat): string; forward;

{------------------------------------------------------------------------------}

// Comme InvariantToFloat, mais refuse ce qui déborde d'un Double (ex. 1e400) : la valeur par défaut est rendue.
function InvariantToDouble(const S: string; Default: Double): Double;
var
  E: TFloat;
begin
  Result := Default;
  try
    E := InvariantToFloat(S, Default);
    if (E <= MaxDouble) and (E >= -MaxDouble) then
      Result := E;
  except
    on EMathError do
      Result := Default;  // le texte déborde même d'un Extended
  end;
end;

{------------------------------------------------------------------------------}

function BoolTo01(Value: Boolean): string;
begin
  if Value then
    Result := '1'
  else
    Result := '0';
end;

{------------------------------------------------------------------------------}

constructor TFractalLocation.Create;
begin
  inherited Create;
  FParams := TStringList.Create;
  FPalette := TGradientPalette.Create;
  FFormulaName := kDefaultFormula;
  FCenterX := TMandelbrotFormula.DefaultCenterX;
  FCenterY := TMandelbrotFormula.DefaultCenterY;
  FWidth := TMandelbrotFormula.DefaultWidth;
  FMaxIter := kDefaultMaxIter;
  FIsAutoIter := True;
  FMapping := DefaultColorMapping;
end;

{------------------------------------------------------------------------------}

destructor TFractalLocation.Destroy;
begin
  FPalette.Free;
  FParams.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.CaptureFrom(Formula: TFractalFormula; const V: TViewport; AIsAutoIter: Boolean;
  APalette: TGradientPalette; const AMapping: TColorMapping);
var
  I: Integer;
begin
  FFormulaName := Formula.FormulaName;
  FParams.Clear;
  for I := 0 to Formula.ParamCount - 1 do
    FParams.Add(Formula.ParamInfo(I).Name + '=' + FloatToInvariant(Formula.GetParam(I)));
  FCenterX := V.CenterX;
  FCenterY := V.CenterY;
  FWidth := V.Width;
  FMaxIter := Formula.MaxIter;
  FIsAutoIter := AIsAutoIter;
  FPalette.Assign(APalette);
  FMapping := AMapping;
end;

{------------------------------------------------------------------------------}

function TFractalLocation.CreateFormula: TFractalFormula;
begin
  try
    Result := DoCreateFormula;
  except
    on E: EFractalFileError do
      raise;
    on E: Exception do
      raise EFractalFileError.CreateFmt('Lieu invalide : %s', [E.Message]);
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.LoadFromText(const AText: string);
begin
  try
    DoLoadFromText(AText);
  except
    on E: EFractalFileError do
      raise;
    on E: Exception do
      raise EFractalFileError.CreateFmt('Lieu invalide : %s', [E.Message]);
  end;
end;

{------------------------------------------------------------------------------}

function TFractalLocation.DoCreateFormula: TFractalFormula;
var
  FormulaClass: TFractalFormulaClass;
  I, Index: Integer;
begin
  FormulaClass := FindFormulaClass(FFormulaName);
  if FormulaClass = nil then
    raise EFractalFileError.CreateFmt('Formule inconnue : %s', [FFormulaName]);
  Result := FormulaClass.Create;
  try
    Result.MaxIter := FMaxIter;
    for I := 0 to FParams.Count - 1 do
    begin
      Index := Result.IndexOfParam(FParams.Names[I]);
      if Index >= 0 then
        Result.SetParam(Index, InvariantToDouble(FParams.ValueFromIndex[I], Result.GetParam(Index)));
    end;
  except
    Result.Free;
    raise;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.ApplyTo(var V: TViewport);
begin
  V.SetCenter(THighFloat.FromFloat(FCenterX, kCenterWords), THighFloat.FromFloat(FCenterY, kCenterWords));
  V.Width := FWidth;
end;

{------------------------------------------------------------------------------}

function TFractalLocation.SaveToText: string;
var
  L, PaletteLines: TStringList;
begin
  L := TStringList.Create;
  PaletteLines := TStringList.Create;
  try
    L.Add('[' + kSectionFractal + ']');
    L.Add('Version=' + IntToStr(kFormatVersion));
    L.Add('Formula=' + FFormulaName);
    L.Add('CenterX=' + FloatToInvariant(FCenterX));
    L.Add('CenterY=' + FloatToInvariant(FCenterY));
    L.Add('Width=' + FloatToInvariant(FWidth));
    L.Add('MaxIter=' + IntToStr(FMaxIter));
    L.Add('AutoIter=' + BoolTo01(FIsAutoIter));
    L.Add('');
    L.Add('[' + kSectionParams + ']');
    L.AddStrings(FParams);
    L.Add('');
    L.Add('[' + kSectionColors + ']');
    L.Add('Offset=' + FloatToInvariant(FMapping.Offset));
    L.Add('Repeats=' + FloatToInvariant(FMapping.Repeats));
    L.Add('Stretch=' + FloatToInvariant(FMapping.Stretch));
    L.Add('Invert=' + BoolTo01(FMapping.IsInverted));
    L.Add('');
    L.Add('[' + kSectionPalette + ']');
    FPalette.SaveToStrings(PaletteLines);
    L.AddStrings(PaletteLines);
    Result := L.Text;
  finally
    PaletteLines.Free;
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.DoLoadFromText(const AText: string);
var
  Ini: TMemIniFile;
  Lines: TStringList;
  FormulaClass: TFractalFormulaClass;
  Name: string;
begin
  Ini := TMemIniFile.Create('');
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    Ini.SetStrings(Lines);
    if not Ini.SectionExists(kSectionFractal) then
      raise EFractalFileError.Create(kNoLocationMessage);
    Name := Ini.ReadString(kSectionFractal, 'Formula', kDefaultFormula);
    FormulaClass := FindFormulaClass(Name);
    if FormulaClass = nil then
      raise EFractalFileError.CreateFmt('Formule inconnue : %s', [Name]);
    FFormulaName := FormulaClass.FormulaName;
    FCenterX := InvariantToFloat(Ini.ReadString(kSectionFractal, 'CenterX', ''), FormulaClass.DefaultCenterX);
    FCenterY := InvariantToFloat(Ini.ReadString(kSectionFractal, 'CenterY', ''), FormulaClass.DefaultCenterY);
    FWidth := InvariantToFloat(Ini.ReadString(kSectionFractal, 'Width', ''), FormulaClass.DefaultWidth);
    if not (FWidth >= kMinLocationWidth) or not (FWidth <= kMaxLocationWidth) then
      FWidth := FormulaClass.DefaultWidth;
    FMaxIter := EnsureRange(Ini.ReadInteger(kSectionFractal, 'MaxIter', kDefaultMaxIter), kMinMaxIter, kMaxMaxIter);
    FIsAutoIter := Ini.ReadBool(kSectionFractal, 'AutoIter', True);

    FParams.Clear;
    Ini.ReadSectionValues(kSectionParams, FParams);

    FMapping := DefaultColorMapping;
    FMapping.Offset := InvariantToDouble(Ini.ReadString(kSectionColors, 'Offset', ''), FMapping.Offset);
    FMapping.Repeats := InvariantToDouble(Ini.ReadString(kSectionColors, 'Repeats', ''), FMapping.Repeats);
    FMapping.Stretch := InvariantToDouble(Ini.ReadString(kSectionColors, 'Stretch', ''), FMapping.Stretch);
    FMapping.IsInverted := Ini.ReadBool(kSectionColors, 'Invert', False);
    FMapping := ClampColorMapping(FMapping);

    Lines.Clear;
    Ini.ReadSectionValues(kSectionPalette, Lines);
    if Lines.Count > 0 then
      FPalette.LoadFromStrings(Lines)
    else
      FPalette.SetDefault;
    if FPalette.Name = '' then
      FPalette.Name := kUnnamed;
  finally
    Lines.Free;
    Ini.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.SaveToFile(const FileName: string);
var
  L: TStringList;
begin
  try
    L := TStringList.Create;
    try
      L.Text := SaveToText;
      L.SaveToFile(FileName, TEncoding.UTF8);
    finally
      L.Free;
    end;
  except
    on E: EFractalFileError do
      raise;
    on E: Exception do
      raise EFractalFileError.CreateFmt('Enregistrement impossible (%s) : %s', [ExtractFileName(FileName), E.Message]);
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.LoadFromFile(const FileName: string);
var
  L: TStringList;
begin
  try
    L := TStringList.Create;
    try
      L.LoadFromFile(FileName);
      LoadFromText(L.Text);
    finally
      L.Free;
    end;
  except
    on E: EFractalFileError do
      raise;
    on E: Exception do
      raise EFractalFileError.CreateFmt('Fichier illisible (%s) : %s', [ExtractFileName(FileName), E.Message]);
  end;
end;

{------------------------------------------------------------------------------}

constructor TFavoriteStore.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := IncludeTrailingPathDelimiter(AFolder);
  ForceDirectories(FFolder);
end;

{------------------------------------------------------------------------------}

procedure TFavoriteStore.List(Names: TStrings);
var
  SR: TSearchRec;
  Sorted: TStringList;
begin
  Sorted := TStringList.Create;
  try
    Sorted.Sorted := True;
    if FindFirst(FFolder + '*' + kLocationExtension, faAnyFile, SR) = 0 then
      try
        repeat
          Sorted.Add(ChangeFileExt(SR.Name, ''));
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    Names.Assign(Sorted);
  finally
    Sorted.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TFavoriteStore.FileNameOf(const AName: string): string;
begin
  Result := FFolder + SanitizeFileName(AName) + kLocationExtension;
end;

{------------------------------------------------------------------------------}

function TFavoriteStore.Save(const AName: string; Location: TFractalLocation): string;
begin
  Result := SanitizeFileName(AName);
  Location.SaveToFile(FileNameOf(Result));
end;

{------------------------------------------------------------------------------}

procedure TFavoriteStore.Load(const AName: string; Location: TFractalLocation);
begin
  Location.LoadFromFile(FileNameOf(AName));
end;

{------------------------------------------------------------------------------}

procedure TFavoriteStore.Delete(const AName: string);
begin
  SysUtils.DeleteFile(FileNameOf(AName));
end;

{------------------------------------------------------------------------------}

function SanitizeFileName(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Pos(Result[I], kInvalidFileChars) > 0 then
      Result[I] := '_';
  Result := Trim(Result);
  if Result = '' then
    Result := kUnnamed;
end;

{------------------------------------------------------------------------------}

// Nom unique et parlant, proposé quand il faut nommer une image, un lieu ou un favori (utile quand le clavier
// virtuel d'une tablette tarde) : formule, direction depuis la vue initiale, zoom, date et heure.
function SuggestedName(Formula: TFractalFormulaClass; const V: TViewport; When: TDateTime): string;
begin
  Result := Formula.FormulaName + kNameSeparator
    + CompassDirection((V.CenterX - Formula.DefaultCenterX) / Formula.DefaultWidth,
      (V.CenterY - Formula.DefaultCenterY) / Formula.DefaultWidth) + kNameSeparator
    + ZoomLabel(Formula.DefaultWidth / V.Width) + kNameSeparator
    + FormatDateTime(kNameDateFormat, When);
end;

{------------------------------------------------------------------------------}

function CompassDirection(DX, DY: TFloat): string;
begin
  if Hypot(DX, DY) < kCentreRadius then
    Result := kCentreName
  else
    Result := kCompassPoints[(Round(RadToDeg(ArcTan2(DY, DX)) / 45) + Length(kCompassPoints))
      mod Length(kCompassPoints)];
end;

{------------------------------------------------------------------------------}

function ZoomLabel(Zoom: TFloat): string;
var
  Exponent: Integer;
  Mantissa: TFloat;
begin
  if Zoom < kScientificZoom then
    Result := 'x' + OneDecimal(Zoom)
  else
  begin
    Exponent := Floor(Log10(Zoom));
    Mantissa := RoundTo(Zoom / Power(10, Exponent), -1);
    if Mantissa >= 10 then
    begin
      Mantissa := Mantissa / 10;
      Inc(Exponent);
    end;
    Result := 'x' + OneDecimal(Mantissa) + 'e' + IntToStr(Exponent);
  end;
end;

{------------------------------------------------------------------------------}

// Une décimale au plus, toujours avec un point : le nom ne dépend pas des réglages régionaux.
function OneDecimal(Value: TFloat): string;
var
  Tenths: Int64;
begin
  Tenths := Round(Value * 10);
  Result := IntToStr(Tenths div 10);
  if Tenths mod 10 <> 0 then
    Result := Result + '.' + IntToStr(Tenths mod 10);
end;

{------------------------------------------------------------------------------}

// Base, ou Base_2, Base_3... : le premier nom absent du dossier pour cette extension.
function UniqueBaseName(const Folder, Base, Extension: string): string;
var
  N: Integer;
begin
  Result := Base;
  N := 1;
  while FileExists(IncludeTrailingPathDelimiter(Folder) + Result + Extension) do
  begin
    Inc(N);
    Result := Base + kNameSeparator + IntToStr(N);
  end;
end;

{------------------------------------------------------------------------------}

function AppDataFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, CSIDL_APPDATA, 0, 0, Buffer) = S_OK then
    Result := IncludeTrailingPathDelimiter(Buffer) + 'Fractales\'
  else
    Result := ExtractFilePath(ParamStr(0));
  ForceDirectories(Result);
end;

{------------------------------------------------------------------------------}

function PaletteFolder: string;
begin
  Result := AppDataFolder + 'Palettes\';
  ForceDirectories(Result);
end;

{------------------------------------------------------------------------------}

function FavoritesFolder: string;
begin
  Result := AppDataFolder + 'Favoris\';
  ForceDirectories(Result);
end;

end.
