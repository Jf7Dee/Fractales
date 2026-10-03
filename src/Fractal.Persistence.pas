unit Fractal.Persistence;

interface

uses
  Windows, SysUtils, Classes, IniFiles, Math, ShlObj, Fractal.Types, Fractal.Formulas, Fractal.Palette;

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
function AppDataFolder: string;
function PaletteFolder: string;
function FavoritesFolder: string;

implementation

const
  kSectionFractal = 'Fractal';
  kSectionParams = 'Params';
  kSectionColors = 'Colors';
  kSectionPalette = 'Palette';
  kDefaultFormula = 'Mandelbrot';
  kFormatVersion = 1;
  kInvalidFileChars = '\/:*?"<>|';
  kUnnamed = 'Sans nom';
  kNoLocationMessage = 'Ce fichier ne contient pas de lieu fractal.';

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
        Result.SetParam(Index, InvariantToFloat(FParams.ValueFromIndex[I], Result.GetParam(Index)));
    end;
  except
    Result.Free;
    raise;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFractalLocation.ApplyTo(var V: TViewport);
begin
  V.CenterX := FCenterX;
  V.CenterY := FCenterY;
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

procedure TFractalLocation.LoadFromText(const AText: string);
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
    if not (FWidth > 0) then
      FWidth := FormulaClass.DefaultWidth;
    FMaxIter := EnsureRange(Ini.ReadInteger(kSectionFractal, 'MaxIter', kDefaultMaxIter), kMinMaxIter, kMaxMaxIter);
    FIsAutoIter := Ini.ReadBool(kSectionFractal, 'AutoIter', True);

    FParams.Clear;
    Ini.ReadSectionValues(kSectionParams, FParams);

    FMapping := DefaultColorMapping;
    FMapping.Offset := InvariantToFloat(Ini.ReadString(kSectionColors, 'Offset', ''), FMapping.Offset);
    FMapping.Repeats := InvariantToFloat(Ini.ReadString(kSectionColors, 'Repeats', ''), FMapping.Repeats);
    FMapping.Stretch := InvariantToFloat(Ini.ReadString(kSectionColors, 'Stretch', ''), FMapping.Stretch);
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
  L := TStringList.Create;
  try
    L.Text := SaveToText;
    L.SaveToFile(FileName, TEncoding.UTF8);
  finally
    L.Free;
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
