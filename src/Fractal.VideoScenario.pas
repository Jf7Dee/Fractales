unit Fractal.VideoScenario;

// Scénario d'une vidéo : étapes (positions copiées des favoris), trajets et pauses, format ; fichier .fscn.

interface

uses
  SysUtils, Classes, IniFiles, Math, Fractal.Types, Fractal.HighFloat, Fractal.Formulas, Fractal.Persistence,
  Fractal.VideoPath;

const
  kScenarioExtension = '.fscn';
  kVideoFps = 30;
  kMinTravelFrames = kVideoFps div 2;  // un trajet dure au moins une demi-seconde
  kMaxSmoothing = 3;                   // lissage : chaque pixel calculé en N × N points
  kMaxStepSeconds = 3600.0;            // trajet ou pause : une heure au plus

type
  TVideoFormat = (vf1x1, vf4x5, vf9x16, vf16x9);

  EVideoScenarioError = class(Exception);

  TVideoStep = record
    Name: string;
    Pose: TCameraPose;
    Mode: TVideoMoveMode;     // trajet qui arrive à cette étape (ignoré pour la première)
    TravelSeconds: Double;    // idem
    PauseSeconds: Double;     // arrêt sur cette étape ; pour la première, durée avant le départ
  end;

  TVideoScenario = class
  private
    FSteps: array of TVideoStep;
    FTemplate: TFractalLocation;  // formule et paramètres communs à toutes les étapes
    FHasFormula: Boolean;
    FFormat: TVideoFormat;
    FSmoothing: Integer;
    procedure SetSmoothing(Value: Integer);
    function GetStep(Index: Integer): TVideoStep;
    procedure SetStep(Index: Integer; const Value: TVideoStep);
    function GetFormulaName: string;
    function GetParams: TStrings;
    procedure CheckIndex(Index: Integer);
    procedure SetFormula(const AFormulaName: string; AParams: TStrings);
    function TravelFrames(Index: Integer): Integer;
    function PauseFrames(Index: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Assign(Source: TVideoScenario);
    procedure Clear;
    procedure AddLocation(const AName: string; Location: TFractalLocation);
    procedure Delete(Index: Integer);
    procedure Move(FromIndex, ToIndex: Integer);
    function Count: Integer;
    function TotalFrames: Integer;
    function TotalSeconds: Double;
    function PoseAtFrame(Frame: Integer; out IsPause: Boolean): TCameraPose;
    function CreateFormula: TFractalFormula;
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);
    property Steps[Index: Integer]: TVideoStep read GetStep write SetStep; default;
    property FormulaName: string read GetFormulaName;
    property Params: TStrings read GetParams;
    property Format: TVideoFormat read FFormat write FFormat;
    property Smoothing: Integer read FSmoothing write SetSmoothing;  // 1 = aucun, 2 = 2×2, 3 = 3×3
  end;

procedure VideoFormatSize(Format: TVideoFormat; out Width, Height: Integer);
function VideoFormatName(Format: TVideoFormat): string;
function ClampTravelSeconds(Seconds: Double): Double;
function ClampPauseSeconds(Seconds: Double): Double;

implementation

const
  kFormatVersion = 1;
  kSectionVideo = 'Video';
  kSectionParams = 'Params';
  kStepSectionPrefix = 'Step';
  kModeNames: array[TVideoMoveMode] of string = ('Survol', 'Lateral');
  kFormatKeys: array[TVideoFormat] of string = ('1x1', '4x5', '9x16', '16x9');
  kFormatNames: array[TVideoFormat] of string = ('Carré 1:1', 'Vertical 4:5', 'Reel 9:16', 'Horizontal 16:9');
  kFormatWidths: array[TVideoFormat] of Integer = (1080, 1080, 1080, 1920);
  kFormatHeights: array[TVideoFormat] of Integer = (1080, 1350, 1920, 1080);
  kNoScenarioMessage = 'Ce fichier n''est pas un scénario vidéo de Fractales.';

{------------------------------------------------------------------------------}

procedure VideoFormatSize(Format: TVideoFormat; out Width, Height: Integer);
begin
  Width := kFormatWidths[Format];
  Height := kFormatHeights[Format];
end;

{------------------------------------------------------------------------------}

function VideoFormatName(Format: TVideoFormat): string;
begin
  Result := kFormatNames[Format];
end;

{------------------------------------------------------------------------------}

// Un trajet dure au moins kMinTravelFrames images : la durée affichée est celle de la vidéo
function ClampTravelSeconds(Seconds: Double): Double;
begin
  if IsNan(Seconds) then
    Seconds := 0;
  Result := EnsureRange(Seconds, kMinTravelFrames / kVideoFps, kMaxStepSeconds);
end;

{------------------------------------------------------------------------------}

function ClampPauseSeconds(Seconds: Double): Double;
begin
  if IsNan(Seconds) then
    Seconds := 0;
  Result := EnsureRange(Seconds, 0, kMaxStepSeconds);
end;

{------------------------------------------------------------------------------}

constructor TVideoScenario.Create;
begin
  inherited Create;
  FTemplate := TFractalLocation.Create;
  FFormat := vf16x9;
  FSmoothing := 1;
end;

{------------------------------------------------------------------------------}

destructor TVideoScenario.Destroy;
begin
  FTemplate.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.Assign(Source: TVideoScenario);
begin
  FSteps := Copy(Source.FSteps);
  FTemplate.LoadFromText(Source.FTemplate.SaveToText);
  FHasFormula := Source.FHasFormula;
  FFormat := Source.FFormat;
  FSmoothing := Source.FSmoothing;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.SetSmoothing(Value: Integer);
begin
  FSmoothing := EnsureRange(Value, 1, kMaxSmoothing);
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.Clear;
begin
  SetLength(FSteps, 0);
  FHasFormula := False;
end;

{------------------------------------------------------------------------------}

function TVideoScenario.GetFormulaName: string;
begin
  if FHasFormula then
    Result := FTemplate.FormulaName
  else
    Result := '';
end;

{------------------------------------------------------------------------------}

function TVideoScenario.GetParams: TStrings;
begin
  Result := FTemplate.Params;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.SetFormula(const AFormulaName: string; AParams: TStrings);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('[Fractal]');
    L.Add('Formula=' + AFormulaName);
    L.Add('[' + kSectionParams + ']');
    L.AddStrings(AParams);
    FTemplate.LoadFromText(L.Text);  // EFractalFileError si la formule est inconnue
  finally
    L.Free;
  end;
  FHasFormula := True;
end;

{------------------------------------------------------------------------------}

function TVideoScenario.CreateFormula: TFractalFormula;
begin
  if not FHasFormula then
    raise EVideoScenarioError.Create('Scénario vide : aucune formule.');
  Result := FTemplate.CreateFormula;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.AddLocation(const AName: string; Location: TFractalLocation);
var
  Step: TVideoStep;
begin
  if Location = nil then
    raise EArgumentException.Create('AddLocation : Location nil');
  if FHasFormula and (not SameText(Location.FormulaName, FTemplate.FormulaName)
    or (Location.Params.Text <> FTemplate.Params.Text)) then
    raise EVideoScenarioError.CreateFmt('« %s » n''est pas une vue de la même fractale que les autres étapes.',
      [AName]);
  if not FHasFormula then
    SetFormula(Location.FormulaName, Location.Params);
  Step.Name := AName;
  Step.Pose.CenterX := Location.CenterX;
  Step.Pose.CenterY := Location.CenterY;
  Step.Pose.Width := Location.Width;
  Step.Mode := vmFlyover;
  Step.PauseSeconds := 0;
  Step.TravelSeconds := kMinTravelSeconds;
  if Count > 0 then
    Step.TravelSeconds := SuggestedTravelSeconds(FSteps[Count - 1].Pose, Step.Pose, vmFlyover);
  SetLength(FSteps, Count + 1);
  FSteps[Count - 1] := Step;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.CheckIndex(Index: Integer);
begin
  if (Index < 0) or (Index >= Count) then
    raise EArgumentOutOfRangeException.CreateFmt('Étape %d hors du scénario', [Index]);
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.Delete(Index: Integer);
var
  I: Integer;
begin
  CheckIndex(Index);
  for I := Index to Count - 2 do
    FSteps[I] := FSteps[I + 1];
  SetLength(FSteps, Count - 1);
  if Count = 0 then
    FHasFormula := False;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.Move(FromIndex, ToIndex: Integer);
var
  Step: TVideoStep;
  I: Integer;
begin
  CheckIndex(FromIndex);
  CheckIndex(ToIndex);
  Step := FSteps[FromIndex];
  if FromIndex < ToIndex then
    for I := FromIndex to ToIndex - 1 do
      FSteps[I] := FSteps[I + 1]
  else
    for I := FromIndex downto ToIndex + 1 do
      FSteps[I] := FSteps[I - 1];
  FSteps[ToIndex] := Step;
end;

{------------------------------------------------------------------------------}

function TVideoScenario.Count: Integer;
begin
  Result := Length(FSteps);
end;

{------------------------------------------------------------------------------}

function TVideoScenario.GetStep(Index: Integer): TVideoStep;
begin
  CheckIndex(Index);
  Result := FSteps[Index];
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.SetStep(Index: Integer; const Value: TVideoStep);
begin
  CheckIndex(Index);
  if not (Value.Pose.Width > 0) then
    raise EVideoScenarioError.Create('Largeur d''étape invalide.');
  FSteps[Index] := Value;
  FSteps[Index].TravelSeconds := ClampTravelSeconds(Value.TravelSeconds);
  FSteps[Index].PauseSeconds := ClampPauseSeconds(Value.PauseSeconds);
end;

{------------------------------------------------------------------------------}

function TVideoScenario.TravelFrames(Index: Integer): Integer;
begin
  if Index = 0 then
    Result := 0
  else
    Result := Max(kMinTravelFrames, Round(FSteps[Index].TravelSeconds * kVideoFps));
end;

{------------------------------------------------------------------------------}

function TVideoScenario.PauseFrames(Index: Integer): Integer;
begin
  Result := Round(FSteps[Index].PauseSeconds * kVideoFps);
end;

{------------------------------------------------------------------------------}

function TVideoScenario.TotalFrames: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    Inc(Result, TravelFrames(I) + PauseFrames(I));
end;

{------------------------------------------------------------------------------}

function TVideoScenario.TotalSeconds: Double;
begin
  Result := TotalFrames / kVideoFps;
end;

{------------------------------------------------------------------------------}

// Image d'un trajet de N images : fraction (k + 1) / N, la dernière tombe exactement sur l'étape d'arrivée
function TVideoScenario.PoseAtFrame(Frame: Integer; out IsPause: Boolean): TCameraPose;
var
  I, N: Integer;
begin
  if Count = 0 then
    raise EVideoScenarioError.Create('Scénario vide.');
  Frame := Max(0, Frame);
  for I := 0 to Count - 1 do
  begin
    N := TravelFrames(I);
    if Frame < N then
    begin
      IsPause := False;
      Exit(PoseBetween(FSteps[I - 1].Pose, FSteps[I].Pose, FSteps[I].Mode, (Frame + 1) / N));
    end;
    Dec(Frame, N);
    N := PauseFrames(I);
    if Frame < N then
    begin
      IsPause := True;
      Exit(FSteps[I].Pose);
    end;
    Dec(Frame, N);
  end;
  IsPause := True;  // au-delà de la fin : la dernière étape
  Result := FSteps[Count - 1].Pose;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.SaveToFile(const FileName: string);
var
  L: TStringList;
  I: Integer;
  S: TVideoStep;
begin
  L := TStringList.Create;
  try
    L.Add('[' + kSectionVideo + ']');
    L.Add('Version=' + IntToStr(kFormatVersion));
    L.Add('Formula=' + FormulaName);
    L.Add('Format=' + kFormatKeys[FFormat]);
    L.Add('Smoothing=' + IntToStr(FSmoothing));
    L.Add('Steps=' + IntToStr(Count));
    L.Add('');
    L.Add('[' + kSectionParams + ']');
    L.AddStrings(FTemplate.Params);
    for I := 0 to Count - 1 do
    begin
      S := FSteps[I];
      L.Add('');
      L.Add('[' + kStepSectionPrefix + IntToStr(I + 1) + ']');
      L.Add('Name=' + S.Name);
      L.Add('CenterX=' + S.Pose.CenterX.ToString(CenterDigits(S.Pose.Width, S.Pose.CenterX)));
      L.Add('CenterY=' + S.Pose.CenterY.ToString(CenterDigits(S.Pose.Width, S.Pose.CenterY)));
      L.Add('Width=' + FloatToInvariant(S.Pose.Width));
      L.Add('Mode=' + kModeNames[S.Mode]);
      L.Add('Travel=' + FloatToInvariant(S.TravelSeconds));
      L.Add('Pause=' + FloatToInvariant(S.PauseSeconds));
    end;
    try
      L.SaveToFile(FileName, TEncoding.UTF8);
    except
      on E: Exception do
        raise EVideoScenarioError.CreateFmt('Enregistrement impossible (%s) : %s',
          [ExtractFileName(FileName), E.Message]);
    end;
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TVideoScenario.LoadFromFile(const FileName: string);
var
  L, P: TStringList;
  Ini: TMemIniFile;
  I, N: Integer;
  Section, Key: string;
  S: TVideoStep;
  M: TVideoMoveMode;
  F: TVideoFormat;
  Loaded: TVideoScenario;
begin
  L := TStringList.Create;
  P := TStringList.Create;
  Ini := TMemIniFile.Create('');
  Loaded := TVideoScenario.Create;
  try
    try
      L.LoadFromFile(FileName);
      Ini.SetStrings(L);
      if not Ini.SectionExists(kSectionVideo) then
        raise EVideoScenarioError.Create(kNoScenarioMessage);
      Ini.ReadSectionValues(kSectionParams, P);
      N := Ini.ReadInteger(kSectionVideo, 'Steps', 0);
      if N > 0 then
        Loaded.SetFormula(Ini.ReadString(kSectionVideo, 'Formula', ''), P);
      Key := Ini.ReadString(kSectionVideo, 'Format', '');
      for F := Low(TVideoFormat) to High(TVideoFormat) do
        if SameText(Key, kFormatKeys[F]) then
          Loaded.FFormat := F;
      Loaded.Smoothing := Ini.ReadInteger(kSectionVideo, 'Smoothing', 1);
      SetLength(Loaded.FSteps, N);
      for I := 0 to N - 1 do
      begin
        Section := kStepSectionPrefix + IntToStr(I + 1);
        if not Ini.SectionExists(Section) then
          raise EVideoScenarioError.CreateFmt('Étape %d absente.', [I + 1]);
        S.Name := Ini.ReadString(Section, 'Name', '');
        S.Pose.Width := InvariantToFloat(Ini.ReadString(Section, 'Width', ''), 0);
        if not (S.Pose.Width > 0) or not (S.Pose.Width < 1e10) then
          raise EVideoScenarioError.CreateFmt('Étape %d : largeur invalide.', [I + 1]);
        S.Pose.CenterX := ParseCenter(Ini.ReadString(Section, 'CenterX', ''), S.Pose.Width, 0);
        S.Pose.CenterY := ParseCenter(Ini.ReadString(Section, 'CenterY', ''), S.Pose.Width, 0);
        S.Mode := vmFlyover;
        Key := Ini.ReadString(Section, 'Mode', '');
        for M := Low(TVideoMoveMode) to High(TVideoMoveMode) do
          if SameText(Key, kModeNames[M]) then
            S.Mode := M;
        S.TravelSeconds := ClampTravelSeconds(InvariantToFloat(Ini.ReadString(Section, 'Travel', ''),
          kMinTravelSeconds));
        S.PauseSeconds := ClampPauseSeconds(InvariantToFloat(Ini.ReadString(Section, 'Pause', ''), 0));
        Loaded.FSteps[I] := S;
      end;
    except
      on E: EVideoScenarioError do
        raise;
      on E: Exception do
        raise EVideoScenarioError.CreateFmt('Fichier illisible (%s) : %s', [ExtractFileName(FileName), E.Message]);
    end;
    Assign(Loaded);
  finally
    Loaded.Free;
    Ini.Free;
    P.Free;
    L.Free;
  end;
end;

end.
