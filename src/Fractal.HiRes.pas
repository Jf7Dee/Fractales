unit Fractal.HiRes;

interface

uses
  Windows, SysUtils, Classes, Math, Types, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.Buffer, Fractal.Png;

const
  kHiResBandRows = 16;
  kMaxHiResBytes = 512 * 1024 * 1024;
  kProgressMax = 1000;

type
  THiResSettings = record
    Width: Integer;
    Height: Integer;
    Supersample: Integer;
    FileName: string;
    IsBla: Boolean;    // approximation bilinéaire en zoom profond : vidéos seulement, jamais les images fixes
    // lissage adaptatif (Supersample > 1) : seuls les pixels qui ont du détail sont suréchantillonnés ; vidéos
    // seulement, les images fixes gardent le lissage complet
    IsAdaptive: Boolean;
    // > 0 : taille de pixel (échantillon) qui décide du palier ; profil de coût des vidéos seulement, 0 sinon
    TierPixelSize: TFloat;
  end;

  // Rendu hors écran par bandes de lignes, écrit directement dans le PNG.
  THiResRenderer = class(TThread)
  private
    FSettings: THiResSettings;
    FViewport: TViewport;
    FFormula: TFractalFormula;
    FMapper: TColorMapper;
    FLocationText: RawByteString;
    FKernel: TEngineKernelType;
    FBandRows: Integer;
    FTarget: TStream;  // non nil : le PNG va dans ce flux (vidéo) au lieu du fichier
    FProgress: Integer;
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    FRefinedPixels: Int64;
    FTotalPixels: Int64;
    FReferenceComputeCount: Integer;
    FBlaBuildCount: Integer;
    function ShadedSubPixel(Buffer: TIterationBuffer; X, Y, Distance: Integer): Cardinal;
    function RenderToStream(Stream: TStream): Boolean;
    function WaitForEngine(Engine: TRenderEngine): Boolean;
    function MarkAdaptive(Engine: TRenderEngine; out Colors: TCardinalDynArray; out Marks: TBooleanDynArray): Boolean;
    function BandMask(const Marks: TBooleanDynArray; Row0, Rows, Margin, Bottom: Integer): TBooleanDynArray;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASettings: THiResSettings; 
                       const AViewport: TViewport; 
                       AFormula: TFractalFormula;
                       AMapper: TColorMapper; 
                       const ALocationText: RawByteString; 
                       AKernel: TEngineKernelType = ekDelphi;
                       ABandRows: Integer = kHiResBandRows;
                       ATarget: TStream = nil);
    destructor Destroy; override;
    property Progress: Integer read FProgress;
    property ErrorMessage: string read FErrorMessage;
    property IsSucceeded: Boolean read FIsSucceeded;
    property IsDone: Boolean read FIsDone;
    // après le rendu : pixels suréchantillonnés (tous sans adaptatif, si Supersample > 1) et pixels de l'image ;
    // références et tables BLA calculées par le moteur
    property RefinedPixels: Int64 read FRefinedPixels;
    property TotalPixels: Int64 read FTotalPixels;
    property ReferenceComputeCount: Integer read FReferenceComputeCount;
    property BlaBuildCount: Integer read FBlaBuildCount;
  end;

function EstimateHiResBytes(const Settings: THiResSettings; IsRelief: Boolean = False): Int64;

implementation

uses
  Fractal.Adaptive;

const
  kWaitSliceMs = 100;
  kBytesPerSample = 5;  // Single + niveau
  kMinSupersample = 1;
  kMaxSupersample = 3;
  kReliefOverlapRows = 2;  // une ligne affichée de recouvrement de chaque côté de la bande
  kShadeDistance = 1;      // les voisins du relief sont toujours à un pixel affiché

{------------------------------------------------------------------------------}

function ClampSupersample(Value: Integer): Integer;
begin
  Result := EnsureRange(Value, kMinSupersample, kMaxSupersample);
end;

{------------------------------------------------------------------------------}

function EstimateHiResBytes(const Settings: THiResSettings; IsRelief: Boolean): Int64;
var
  SS, Rows: Integer;
begin
  SS := ClampSupersample(Settings.Supersample);
  Rows := kHiResBandRows;
  if IsRelief then
    Inc(Rows, kReliefOverlapRows);
  Result := Int64(Settings.Width) * SS * Rows * SS * kBytesPerSample + Int64(Settings.Width) * 3;
  // adaptatif : premier passage sur toute l'image (tampon du moteur), puis ses couleurs et ses marques gardées
  if Settings.IsAdaptive and (SS > 1) then
    Inc(Result, Int64(Settings.Width) * Settings.Height * (kBytesPerSample + SizeOf(Cardinal) + SizeOf(Boolean)));
end;

{------------------------------------------------------------------------------}

constructor THiResRenderer.Create(const ASettings: THiResSettings; const AViewport: TViewport;
  AFormula: TFractalFormula; AMapper: TColorMapper; const ALocationText: RawByteString; AKernel: TEngineKernelType;
  ABandRows: Integer; ATarget: TStream);
begin
  FMapper := AMapper;  // en premier : possession toujours transférée, libérée par Destroy même si Clone échoue
  FSettings := ASettings;
  FSettings.Supersample := ClampSupersample(FSettings.Supersample);
  FViewport := AViewport.Resized(ASettings.Width, ASettings.Height);
  FFormula := AFormula.Clone;
  FLocationText := ALocationText;
  FKernel := AKernel;
  FBandRows := Max(1, ABandRows);
  FTarget := ATarget;
  inherited Create(False);
end;

{------------------------------------------------------------------------------}

destructor THiResRenderer.Destroy;
begin
  inherited Destroy;  // attend la fin du thread avant de libérer ce qu'il utilise
  FMapper.Free;
  FFormula.Free;
end;

{------------------------------------------------------------------------------}

procedure THiResRenderer.Execute;
var
  Stream: TFileStream;
  IsFileCreated, IsComplete: Boolean;
begin
  IsFileCreated := False;
  try
    try
      if (FSettings.Width <= 0) or (FSettings.Height <= 0) then
        raise Exception.Create('Dimensions de rendu invalides.');
      if EstimateHiResBytes(FSettings, FMapper.HasRelief) > kMaxHiResBytes then
        raise Exception.Create('Mémoire insuffisante pour ce rendu : réduisez la taille ou le suréchantillonnage.');
      if FTarget <> nil then
        FIsSucceeded := RenderToStream(FTarget)
      else
      begin
        Stream := TFileStream.Create(FSettings.FileName, fmCreate);
        IsFileCreated := True;
        try
          IsComplete := RenderToStream(Stream);
        finally
          Stream.Free;
        end;
        if IsComplete then
          FIsSucceeded := True
        else
          SysUtils.DeleteFile(FSettings.FileName);
      end;
    except
      on E: Exception do
      begin
        FErrorMessage := E.Message;
        if IsFileCreated then
          SysUtils.DeleteFile(FSettings.FileName);
      end;
    end;
  finally
    FIsDone := True;
  end;
end;

{------------------------------------------------------------------------------}

function THiResRenderer.ShadedSubPixel(Buffer: TIterationBuffer; X, Y, Distance: Integer): Cardinal;
var
  Mu, Left, Right, Up, Down: Single;
begin
  if Buffer = nil then
    raise Exception.Create('ShadedSubPixel : tampon absent.');
  Mu := Buffer.Value(X, Y);
  // voisins à Distance sous-pixels (un pixel affiché, d'où kShadeDistance pour la pente) ;
  // hors du tampon (bord de l'image) : le sous-pixel lui-même
  Left := Mu;
  Right := Mu;
  Up := Mu;
  Down := Mu;
  if X - Distance >= 0 then
    Left := Buffer.Value(X - Distance, Y);
  if X + Distance < Buffer.Width then
    Right := Buffer.Value(X + Distance, Y);
  if Y - Distance >= 0 then
    Up := Buffer.Value(X, Y - Distance);
  if Y + Distance < Buffer.Height then
    Down := Buffer.Value(X, Y + Distance);
  Result := FMapper.ShadeValue(Mu, Left, Right, Up, Down, kShadeDistance);
end;

{------------------------------------------------------------------------------}

// Attend la fin du rendu courant ; faux si le thread est arrêté. Les erreurs de calcul lèvent une exception.
function THiResRenderer.WaitForEngine(Engine: TRenderEngine): Boolean;
var
  Errors: string;
begin
  Result := False;
  while not Engine.WaitUntilComplete(kWaitSliceMs) do
    if Terminated then
      Exit;
  if Terminated then
    Exit;
  Errors := Engine.TakeErrors;
  if Errors <> '' then
    raise Exception.Create('Erreur de calcul : ' + Errors);
  Result := True;
end;

{------------------------------------------------------------------------------}

// Premier passage du lissage adaptatif : toute l'image au pas du pixel, en un seul rendu (le marquage voit ainsi les
// voisins de chaque pixel, même au bord d'une bande). Colors : couleur finale de chaque pixel, relief compris (pente
// entre pixels voisins, comme le lissage complet) ; Marks : pixels à suréchantillonner. Faux si le thread est arrêté.
function THiResRenderer.MarkAdaptive(Engine: TRenderEngine; out Colors: TCardinalDynArray;
  out Marks: TBooleanDynArray): Boolean;
var
  X, Y: Integer;
  V, Fine: TViewport;
begin
  Result := False;
  // centre à la précision des sous-pixels (même centre, plus de mots si besoin) : la référence de ce passage sert
  // ensuite à toutes les bandes suréchantillonnées
  V := FViewport.SubViewport(1, 0, FSettings.Height);
  Fine := FViewport.SubViewport(FSettings.Supersample, 0, FSettings.Height);
  V.SetCenter(Fine.ExactCenterX, Fine.ExactCenterY);
  Engine.SampleMask := nil;
  Engine.Render(V, FFormula, False);
  if not WaitForEngine(Engine) then
    Exit;
  SetLength(Colors, FSettings.Width * FSettings.Height);
  for Y := 0 to FSettings.Height - 1 do
    for X := 0 to FSettings.Width - 1 do
      if FMapper.HasRelief then
        Colors[Y * FSettings.Width + X] := ShadedSubPixel(Engine.Buffer, X, Y, 1)
      else
        Colors[Y * FSettings.Width + X] := FMapper.MapValue(Engine.Buffer.Value(X, Y));
  MarkDetail(Colors, FSettings.Width, FSettings.Height, kAdaptiveThreshold, Marks);
  Result := True;
end;

{------------------------------------------------------------------------------}

// Masque des sous-pixels de la bande [Row0, Row0 + Rows), débordements Margin et Bottom compris : ceux des pixels
// marqués de la bande, élargis d'un pixel avec relief (la pente lit les sous-pixels voisins, jusque dans les lignes
// de débordement). nil si la bande n'a aucun pixel marqué.
function THiResRenderer.BandMask(const Marks: TBooleanDynArray; Row0, Rows, Margin, Bottom: Integer): TBooleanDynArray;
var
  Band: TBooleanDynArray;
  X, R, W: Integer;
  IsAny: Boolean;
begin
  W := FSettings.Width;
  SetLength(Band, W * (Rows + Margin + Bottom));
  IsAny := False;
  for R := 0 to Rows - 1 do
    for X := 0 to W - 1 do
      if Marks[(Row0 + R) * W + X] then
      begin
        Band[(R + Margin) * W + X] := True;
        IsAny := True;
      end;
  if IsAny then
    Result := ExpandMask(Band, W, Rows + Margin + Bottom, FSettings.Supersample, Ord(FMapper.HasRelief))
  else
    Result := nil;
end;

{------------------------------------------------------------------------------}

function THiResRenderer.RenderToStream(Stream: TStream): Boolean;
var
  Engine: TRenderEngine;
  Writer: TPngWriter;
  Row: array of Byte;
  Row0, Rows, R, X, SX, SY, SS, Count, SumR, SumG, SumB, Margin, Bottom, Index: Integer;
  IsRelief, IsAdaptive, IsBandRefined: Boolean;
  C: Cardinal;
  Colors: TCardinalDynArray;
  Marks: TBooleanDynArray;
begin
  Result := False;
  SS := FSettings.Supersample;
  Count := SS * SS;
  IsRelief := FMapper.HasRelief;
  IsAdaptive := FSettings.IsAdaptive and (SS > 1);
  FRefinedPixels := 0;
  FTotalPixels := 0;
  SetLength(Row, FSettings.Width * 3);
  Engine := TRenderEngine.Create(CpuCount);
  try
    Engine.Kernel := FKernel;
    Engine.IsBlaEnabled := FSettings.IsBla;
    Engine.TierPixelSize := FSettings.TierPixelSize;
    // les bandes partagent une seule orbite, même échappée : sinon chacune en recalculerait jusqu'à neuf
    Engine.IsEscapedReferenceReusable := True;
    Writer := TPngWriter.Create(Stream, FSettings.Width, FSettings.Height);
    try
      if FLocationText <> '' then
        Writer.AddText(kLocationKeyword, FLocationText);
      if IsAdaptive and not MarkAdaptive(Engine, Colors, Marks) then
        Exit;
      Row0 := 0;
      while Row0 < FSettings.Height do
      begin
        Rows := Min(FBandRows, FSettings.Height - Row0);
        // le relief lit ses voisins à SS sous-pixels : la bande déborde d'une ligne affichée de chaque côté, bornée
        // aux bords de l'image ; sans relief, aucun recouvrement
        if IsRelief then
        begin
          Margin := Min(1, Row0);
          Bottom := Min(1, FSettings.Height - Row0 - Rows);
        end
        else
        begin
          Margin := 0;
          Bottom := 0;
        end;
        // adaptatif : bande calculée seulement aux sous-pixels des pixels marqués (et de leurs voisins avec relief) ;
        // aucune marque : pas de calcul, la bande garde les couleurs du premier passage
        IsBandRefined := True;
        if IsAdaptive then
        begin
          Engine.SampleMask := BandMask(Marks, Row0, Rows, Margin, Bottom);
          IsBandRefined := Engine.SampleMask <> nil;
        end;
        if IsBandRefined then
        begin
          Engine.Render(FViewport.SubViewport(SS, Row0 - Margin, Rows + Margin + Bottom), FFormula, False);
          Engine.SampleMask := nil;
          if not WaitForEngine(Engine) then
            Exit;
        end;
        for R := 0 to Rows - 1 do
        begin
          for X := 0 to FSettings.Width - 1 do
          begin
            Inc(FTotalPixels);
            Index := (Row0 + R) * FSettings.Width + X;
            if IsAdaptive and not Marks[Index] then
            begin
              C := Colors[Index];
              Row[X * 3] := (C shr 16) and $FF;
              Row[X * 3 + 1] := (C shr 8) and $FF;
              Row[X * 3 + 2] := C and $FF;
              Continue;
            end;
            if SS > 1 then
              Inc(FRefinedPixels);
            // anticrénelage : moyenne des couleurs (pas des valeurs) des SS x SS sous-pixels
            SumR := 0;
            SumG := 0;
            SumB := 0;
            for SY := 0 to SS - 1 do
              for SX := 0 to SS - 1 do
              begin
                if IsRelief then
                  C := ShadedSubPixel(Engine.Buffer, X * SS + SX, (R + Margin) * SS + SY, SS)
                else
                  C := FMapper.MapValue(Engine.Buffer.Value(X * SS + SX, R * SS + SY));
                Inc(SumR, (C shr 16) and $FF);
                Inc(SumG, (C shr 8) and $FF);
                Inc(SumB, C and $FF);
              end;
            Row[X * 3] := (SumR + Count div 2) div Count;
            Row[X * 3 + 1] := (SumG + Count div 2) div Count;
            Row[X * 3 + 2] := (SumB + Count div 2) div Count;
          end;
          Writer.WriteRow(@Row[0]);
        end;
        Inc(Row0, Rows);
        FProgress := MulDiv(Row0, kProgressMax, FSettings.Height);
      end;
      Writer.Finish;
      Result := True;
    finally
      Writer.Free;
    end;
  finally
    FReferenceComputeCount := Engine.ReferenceComputeCount;
    FBlaBuildCount := Engine.BlaBuildCount;
    Engine.Free;
  end;
end;

end.
