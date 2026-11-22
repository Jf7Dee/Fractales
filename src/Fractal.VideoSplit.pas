unit Fractal.VideoSplit;

// Répartition d'une vidéo entre plusieurs machines : chacune rend une plage de morceaux entiers. Le profil de coût de
// toute la vidéo (TVideoRenderer en mode profil seul) propose des plages équilibrées selon la vitesse de chaque
// machine ; l'utilisateur les ajuste, et le fichier repartition.txt les garde pour l'assemblage

interface

uses
  SysUtils, Classes, Math, Fractal.Types;

const
  kSplitFileName = 'repartition.txt';

type
  TSplitMachine = record
    Name: string;
    Speed: Double;  // vitesse relative : 2 = deux fois plus rapide que 1
    FirstSegment, LastSegment: Integer;
  end;

  TSplitMachines = array of TSplitMachine;

  EVideoSplitError = class(Exception);

// Des plages de morceaux entiers, sans chevauchement, qui couvrent tous les morceaux, au moins un par machine.
// Cost : coût cumulé du profil (Cost[I] = images 0..I-1, Length = images + 1). Coupe gloutonne : chaque machine prend
// des morceaux jusqu'à sa part du coût total (sa vitesse sur la somme des vitesses), la borne étant arrondie au
// morceau le plus proche de la cible ; la dernière prend le reste. EArgumentException s'il y a plus de machines que
// de morceaux ou une vitesse nulle
function ProposeSplit(const Cost: array of Double; SegmentFrames: Integer; const Speeds: array of Double):
  TSplitMachines;

// Déplace le début de la machine Index (> 0) et la fin de la précédente ; refuse, sans rien changer, de vider l'une
// des deux
procedure MoveSplitBoundary(var Machines: TSplitMachines; Index, NewFirstSegment: Integer);

// Durée estimée de la plage sur une machine de vitesse Speed : coût × 64 × Smoothing² / Speed. Pessimiste : le profil
// est mesuré au huitième de la taille, sans lissage
function SplitSeconds(const Cost: array of Double; SegmentFrames, FirstSegment, LastSegment: Integer;
  Speed: Double; Smoothing: Integer): Double;

// repartition.txt : UTF-8, une ligne par machine « Nom|Vitesse|PremièreImage|DernièreImage ». Les plages sont en
// morceaux en mémoire et en images dans le fichier : FramesTotal borne la dernière image du dernier morceau
procedure SaveSplitFile(const FileName: string; const Machines: TSplitMachines; SegmentFrames, FramesTotal: Integer);
function LoadSplitFile(const FileName: string; SegmentFrames: Integer): TSplitMachines;

// Vrai si des morceaux d'un autre rendu ne s'effacent qu'après confirmation : jamais pour un aperçu, qui n'est pas réparti
function ShouldConfirmReplaceParts(IsPreview: Boolean): Boolean;

// Texte affiché quand un rendu est interrompu ; IsPartial : une plage, non la vidéo entière
function CancelledCaption(IsPartial: Boolean): string;

// La machine dont le nom est Name (l'ordinateur où l'on reprend), sans tenir compte de la casse ni des espaces autour ;
// -1 si aucune
function MachineIndexByName(const Machines: TSplitMachines; const Name: string): Integer;

implementation

const
  kSeparator = '|';
  kProbeCostFactor = 64;  // le profil est au huitième : 8 × 8 fois moins de pixels

// Le coût cumulé jusqu'à la fin du morceau Segment (inclus)
function SegmentEndCost(const Cost: array of Double; SegmentFrames, Segment: Integer): Double;
begin
  Result := Cost[Min((Segment + 1) * SegmentFrames, High(Cost))];
end;

{------------------------------------------------------------------------------}

function ProposeSplit(const Cost: array of Double; SegmentFrames: Integer; const Speeds: array of Double):
  TSplitMachines;
var
  Frames, Count, Machine, Segment, Current, Best, MaxEnd: Integer;
  Total, Target, SpeedSum, SpeedSoFar, Distance, BestDistance: Double;
  EndCost: array of Double;
begin
  if (Length(Cost) < 2) or (SegmentFrames < 1) then
    raise EArgumentException.Create('ProposeSplit : profil vide ou morceau sans image');
  Frames := High(Cost);
  Count := (Frames - 1) div SegmentFrames + 1;
  if (Length(Speeds) < 1) or (Length(Speeds) > Count) then
    raise EArgumentException.CreateFmt('ProposeSplit : %d machines pour %d morceaux', [Length(Speeds), Count]);
  SpeedSum := 0;
  for Machine := 0 to High(Speeds) do
  begin
    if Speeds[Machine] <= 0 then
      raise EArgumentException.Create('ProposeSplit : vitesse nulle ou négative');
    SpeedSum := SpeedSum + Speeds[Machine];
  end;
  SetLength(EndCost, Count);
  for Segment := 0 to Count - 1 do
    EndCost[Segment] := SegmentEndCost(Cost, SegmentFrames, Segment);
  Total := EndCost[Count - 1];
  if Total <= 0 then  // profil sans coût : les morceaux comptent pour autant
  begin
    Total := Count;
    for Segment := 0 to Count - 1 do
      EndCost[Segment] := Segment + 1;
  end;
  SetLength(Result, Length(Speeds));
  Current := 0;
  SpeedSoFar := 0;
  for Machine := 0 to High(Speeds) do
  begin
    Result[Machine].Name := Format('Machine %d', [Machine + 1]);
    Result[Machine].Speed := Speeds[Machine];
    Result[Machine].FirstSegment := Current;
    SpeedSoFar := SpeedSoFar + Speeds[Machine];
    if Machine = High(Speeds) then
      Best := Count - 1
    else
    begin
      Target := Total * SpeedSoFar / SpeedSum;
      MaxEnd := Count - 1 - (High(Speeds) - Machine);  // un morceau reste pour chacune des suivantes
      Best := Current;
      BestDistance := Abs(EndCost[Current] - Target);
      for Segment := Current + 1 to MaxEnd do
      begin
        Distance := Abs(EndCost[Segment] - Target);
        if Distance < BestDistance then
        begin
          Best := Segment;
          BestDistance := Distance;
        end;
      end;
    end;
    Result[Machine].LastSegment := Best;
    Current := Best + 1;
  end;
end;

{------------------------------------------------------------------------------}

procedure MoveSplitBoundary(var Machines: TSplitMachines; Index, NewFirstSegment: Integer);
begin
  if (Index < 1) or (Index > High(Machines)) then
    Exit;
  if (NewFirstSegment <= Machines[Index - 1].FirstSegment) or (NewFirstSegment > Machines[Index].LastSegment) then
    Exit;  // viderait l'une des deux machines
  Machines[Index].FirstSegment := NewFirstSegment;
  Machines[Index - 1].LastSegment := NewFirstSegment - 1;
end;

{------------------------------------------------------------------------------}

function SplitSeconds(const Cost: array of Double; SegmentFrames, FirstSegment, LastSegment: Integer;
  Speed: Double; Smoothing: Integer): Double;
begin
  if (Length(Cost) < 2) or (SegmentFrames < 1) or (FirstSegment < 0) or (LastSegment < FirstSegment) or
    (Speed <= 0) then
    raise EArgumentException.Create('SplitSeconds : plage ou vitesse invalide');
  Result := SegmentEndCost(Cost, SegmentFrames, LastSegment) - Cost[Min(FirstSegment * SegmentFrames, High(Cost))];
  Result := Result * kProbeCostFactor * Max(1, Smoothing) * Max(1, Smoothing) / Speed;
end;

{------------------------------------------------------------------------------}

procedure SaveSplitFile(const FileName: string; const Machines: TSplitMachines; SegmentFrames, FramesTotal: Integer);
var
  Lines: TStringList;
  I: Integer;
begin
  if SegmentFrames < 1 then
    raise EArgumentException.Create('SaveSplitFile : morceau sans image');
  Lines := TStringList.Create;
  try
    for I := 0 to High(Machines) do
      Lines.Add(Format('%s|%s|%d|%d', [StringReplace(Machines[I].Name, kSeparator, '/', [rfReplaceAll]),
        FloatToInvariant(Machines[I].Speed), Machines[I].FirstSegment * SegmentFrames,
        Min((Machines[I].LastSegment + 1) * SegmentFrames, FramesTotal) - 1]));
    Lines.SaveToFile(FileName, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------}

function LoadSplitFile(const FileName: string; SegmentFrames: Integer): TSplitMachines;
var
  Lines, Fields: TStringList;
  I: Integer;
  First, Last: Integer;
begin
  if SegmentFrames < 1 then
    raise EArgumentException.Create('LoadSplitFile : morceau sans image');
  Result := nil;
  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    Lines.LoadFromFile(FileName, TEncoding.UTF8);
    Fields.Delimiter := kSeparator;
    Fields.StrictDelimiter := True;
    for I := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[I]) = '' then
        Continue;
      Fields.DelimitedText := Lines[I];
      First := -1;
      Last := -1;
      if Fields.Count = 4 then
      begin
        First := StrToIntDef(Trim(Fields[2]), -1);
        Last := StrToIntDef(Trim(Fields[3]), -1);
      end;
      if (First < 0) or (Last < First) then
        raise EVideoSplitError.CreateFmt('%s, ligne %d : « Nom|Vitesse|PremièreImage|DernièreImage » attendu',
          [ExtractFileName(FileName), I + 1]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Name := Fields[0];
      Result[High(Result)].Speed := InvariantToFloat(Trim(Fields[1]), 1);
      Result[High(Result)].FirstSegment := First div SegmentFrames;
      Result[High(Result)].LastSegment := Last div SegmentFrames;
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
end;

{------------------------------------------------------------------------------}

function ShouldConfirmReplaceParts(IsPreview: Boolean): Boolean;
begin
  Result := not IsPreview;
end;

{------------------------------------------------------------------------------}

function CancelledCaption(IsPartial: Boolean): string;
begin
  if IsPartial then
    Result := 'Interrompu : « Reprendre des morceaux… » (ou la proposition au prochain démarrage) reprend cette plage.'
  else
    Result := 'Interrompu : relancer la même vidéo reprendra où elle s''est arrêtée.';
end;

{------------------------------------------------------------------------------}

function MachineIndexByName(const Machines: TSplitMachines; const Name: string): Integer;
begin
  if Trim(Name) <> '' then
    for Result := 0 to High(Machines) do
      if SameText(Trim(Machines[Result].Name), Trim(Name)) then
        Exit;
  Result := -1;
end;

end.
