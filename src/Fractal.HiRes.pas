unit Fractal.HiRes;

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
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
    FProgress: Integer;
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    function ShadedSubPixel(Buffer: TIterationBuffer; X, Y, Distance: Integer): Cardinal;
    function RenderToStream(Stream: TStream): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASettings: THiResSettings; 
                       const AViewport: TViewport; 
                       AFormula: TFractalFormula;
                       AMapper: TColorMapper; 
                       const ALocationText: RawByteString; 
                       AKernel: TEngineKernelType = ekDelphi;
                       ABandRows: Integer = kHiResBandRows);
    destructor Destroy; override;
    property Progress: Integer read FProgress;
    property ErrorMessage: string read FErrorMessage;
    property IsSucceeded: Boolean read FIsSucceeded;
    property IsDone: Boolean read FIsDone;
  end;

function EstimateHiResBytes(const Settings: THiResSettings; IsRelief: Boolean = False): Int64;

implementation

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
end;

{------------------------------------------------------------------------------}

constructor THiResRenderer.Create(const ASettings: THiResSettings; const AViewport: TViewport;
  AFormula: TFractalFormula; AMapper: TColorMapper; const ALocationText: RawByteString; AKernel: TEngineKernelType;
  ABandRows: Integer);
begin
  FMapper := AMapper;  // en premier : possession toujours transférée, libérée par Destroy même si Clone échoue
  FSettings := ASettings;
  FSettings.Supersample := ClampSupersample(FSettings.Supersample);
  FViewport := AViewport.Resized(ASettings.Width, ASettings.Height);
  FFormula := AFormula.Clone;
  FLocationText := ALocationText;
  FKernel := AKernel;
  FBandRows := Max(1, ABandRows);
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

function THiResRenderer.RenderToStream(Stream: TStream): Boolean;
var
  Engine: TRenderEngine;
  Writer: TPngWriter;
  Row: array of Byte;
  Row0, Rows, R, X, SX, SY, SS, Count, SumR, SumG, SumB, Margin, Bottom: Integer;
  IsRelief: Boolean;
  C: Cardinal;
  Errors: string;
begin
  Result := False;
  SS := FSettings.Supersample;
  Count := SS * SS;
  IsRelief := FMapper.HasRelief;
  SetLength(Row, FSettings.Width * 3);
  Engine := TRenderEngine.Create(CpuCount);
  try
    Engine.Kernel := FKernel;
    // les bandes partagent une seule orbite, même échappée : sinon chacune en recalculerait jusqu'à neuf
    Engine.IsEscapedReferenceReusable := True;
    Writer := TPngWriter.Create(Stream, FSettings.Width, FSettings.Height);
    try
      if FLocationText <> '' then
        Writer.AddText(kLocationKeyword, FLocationText);
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
        Engine.Render(FViewport.SubViewport(SS, Row0 - Margin, Rows + Margin + Bottom), FFormula, False);
        while not Engine.WaitUntilComplete(kWaitSliceMs) do
          if Terminated then
            Exit;
        if Terminated then
          Exit;
        Errors := Engine.TakeErrors;
        if Errors <> '' then
          raise Exception.Create('Erreur de calcul : ' + Errors);
        for R := 0 to Rows - 1 do
        begin
          for X := 0 to FSettings.Width - 1 do
          begin
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
    Engine.Free;
  end;
end;

end.
