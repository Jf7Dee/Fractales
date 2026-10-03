unit Fractal.Buffer;

interface

uses
  Windows, Math, Fractal.Types;

type
  TIterationValues = array of Single;
  TIterationLevels = array of Byte;

  // Tampon d'itérations partagé par les threads de calcul : chaque thread écrit des pixels disjoints.
  TIterationBuffer = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FValues: TIterationValues;
    FLevels: TIterationLevels;
    FDirty: Integer;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Resize(AWidth, AHeight: Integer);
    procedure Clear;
    procedure Shift(DX, DY: Integer);
    function Value(X, Y: Integer): Single;
    function Level(X, Y: Integer): Byte;
    function IsExact(X, Y: Integer): Boolean;
    procedure WriteAnchor(X, Y, Step: Integer; AValue: Single);
    function RowPtr(Y: Integer): System.PSingle;
    procedure MarkDirty;
    function TakeDirtyFlag: Boolean;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

implementation

{------------------------------------------------------------------------------}

constructor TIterationBuffer.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Resize(AWidth, AHeight);
end;

{------------------------------------------------------------------------------}

procedure TIterationBuffer.Resize(AWidth, AHeight: Integer);
begin
  FWidth := Max(0, AWidth);
  FHeight := Max(0, AHeight);
  SetLength(FValues, FWidth * FHeight);
  SetLength(FLevels, FWidth * FHeight);
  Clear;
end;

{------------------------------------------------------------------------------}

procedure TIterationBuffer.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FValues) do
    FValues[I] := kNotComputed;
  if Length(FLevels) > 0 then
    FillChar(FLevels[0], Length(FLevels), 0);
  MarkDirty;
end;

{------------------------------------------------------------------------------}

procedure TIterationBuffer.Shift(DX, DY: Integer);
var
  NewValues: TIterationValues;
  NewLevels: TIterationLevels;
  X, Y, SX, SY, I: Integer;
begin
  SetLength(NewValues, Length(FValues));
  SetLength(NewLevels, Length(FLevels));
  for Y := 0 to FHeight - 1 do
  begin
    SY := Y - DY;
    for X := 0 to FWidth - 1 do
    begin
      SX := X - DX;
      I := Y * FWidth + X;
      if (SX >= 0) and (SX < FWidth) and (SY >= 0) and (SY < FHeight) then
      begin
        NewValues[I] := FValues[SY * FWidth + SX];
        NewLevels[I] := FLevels[SY * FWidth + SX];
      end
      else
      begin
        NewValues[I] := kNotComputed;
        NewLevels[I] := 0;
      end;
    end;
  end;
  FValues := NewValues;
  FLevels := NewLevels;
  MarkDirty;
end;

{------------------------------------------------------------------------------}

function TIterationBuffer.Value(X, Y: Integer): Single;
begin
  Result := FValues[Y * FWidth + X];
end;

{------------------------------------------------------------------------------}

function TIterationBuffer.Level(X, Y: Integer): Byte;
begin
  Result := FLevels[Y * FWidth + X];
end;

{------------------------------------------------------------------------------}

function TIterationBuffer.IsExact(X, Y: Integer): Boolean;
begin
  Result := FLevels[Y * FWidth + X] = 1;
end;

{------------------------------------------------------------------------------}

procedure TIterationBuffer.WriteAnchor(X, Y, Step: Integer; AValue: Single);
var
  BX, BY, XEnd, YEnd, I: Integer;
begin
  I := Y * FWidth + X;
  FValues[I] := AValue;
  FLevels[I] := 1;
  if Step <= 1 then
    Exit;
  XEnd := Min(X + Step, FWidth);
  YEnd := Min(Y + Step, FHeight);
  for BY := Y to YEnd - 1 do
    for BX := X to XEnd - 1 do
    begin
      I := BY * FWidth + BX;
      if (FLevels[I] = 0) or (FLevels[I] > Step) then
      begin
        FValues[I] := AValue;
        FLevels[I] := Step;
      end;
    end;
end;

{------------------------------------------------------------------------------}

function TIterationBuffer.RowPtr(Y: Integer): System.PSingle;
begin
  Result := @FValues[Y * FWidth];
end;

{------------------------------------------------------------------------------}

procedure TIterationBuffer.MarkDirty;
begin
  InterlockedExchange(FDirty, 1);
end;

{------------------------------------------------------------------------------}

function TIterationBuffer.TakeDirtyFlag: Boolean;
begin
  Result := InterlockedExchange(FDirty, 0) <> 0;
end;

end.
