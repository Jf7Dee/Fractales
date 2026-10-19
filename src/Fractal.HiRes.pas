unit Fractal.HiRes;

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.Png;

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
    FProgress: Integer;
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    function RenderToStream(Stream: TStream): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASettings: THiResSettings; 
                       const AViewport: TViewport; 
                       AFormula: TFractalFormula;
                       AMapper: TColorMapper; 
                       const ALocationText: RawByteString; 
                       AKernel: TEngineKernelType = ekDelphi);
    destructor Destroy; override;
    property Progress: Integer read FProgress;
    property ErrorMessage: string read FErrorMessage;
    property IsSucceeded: Boolean read FIsSucceeded;
    property IsDone: Boolean read FIsDone;
  end;

function EstimateHiResBytes(const Settings: THiResSettings): Int64;

implementation

const
  kWaitSliceMs = 100;
  kBytesPerSample = 5;  // Single + niveau
  kMinSupersample = 1;
  kMaxSupersample = 3;

{------------------------------------------------------------------------------}

function ClampSupersample(Value: Integer): Integer;
begin
  Result := EnsureRange(Value, kMinSupersample, kMaxSupersample);
end;

{------------------------------------------------------------------------------}

function EstimateHiResBytes(const Settings: THiResSettings): Int64;
var
  SS: Integer;
begin
  SS := ClampSupersample(Settings.Supersample);
  Result := Int64(Settings.Width) * SS * kHiResBandRows * SS * kBytesPerSample + Int64(Settings.Width) * 3;
end;

{------------------------------------------------------------------------------}

constructor THiResRenderer.Create(const ASettings: THiResSettings; const AViewport: TViewport;
  AFormula: TFractalFormula; AMapper: TColorMapper; const ALocationText: RawByteString; AKernel: TEngineKernelType);
begin
  FMapper := AMapper;  // en premier : possession toujours transférée, libérée par Destroy même si Clone échoue
  FSettings := ASettings;
  FSettings.Supersample := ClampSupersample(FSettings.Supersample);
  FViewport := AViewport.Resized(ASettings.Width, ASettings.Height);
  FFormula := AFormula.Clone;
  FLocationText := ALocationText;
  FKernel := AKernel;
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
      if EstimateHiResBytes(FSettings) > kMaxHiResBytes then
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

function THiResRenderer.RenderToStream(Stream: TStream): Boolean;
var
  Engine: TRenderEngine;
  Writer: TPngWriter;
  Row: array of Byte;
  Row0, Rows, R, X, SX, SY, SS, Count, SumR, SumG, SumB: Integer;
  C: Cardinal;
  Errors: string;
begin
  Result := False;
  SS := FSettings.Supersample;
  Count := SS * SS;
  SetLength(Row, FSettings.Width * 3);
  Engine := TRenderEngine.Create(CpuCount);
  try
    Engine.Kernel := FKernel;
    Writer := TPngWriter.Create(Stream, FSettings.Width, FSettings.Height);
    try
      if FLocationText <> '' then
        Writer.AddText(kLocationKeyword, FLocationText);
      Row0 := 0;
      while Row0 < FSettings.Height do
      begin
        Rows := Min(kHiResBandRows, FSettings.Height - Row0);
        Engine.Render(FViewport.SubViewport(SS, Row0, Rows), FFormula, False);
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
