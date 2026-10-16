unit Fractal.Png;

interface

uses
  SysUtils, Classes, ZLib;

const
  kLocationKeyword = 'FractalLocation';

type
  EPngError = class(Exception);

  // Écrivain PNG en flux (RVB 8 bits, sans entrelacement) : les lignes compressées partent dans des blocs
  // IDAT au fur et à mesure, l'image complète n'est jamais en mémoire.
  TPngWriter = class
  private
    FStream: TStream;
    FWidth: Integer;
    FHeight: Integer;
    FRowsWritten: Integer;
    FPending: TMemoryStream;
    FSink: TStream;
    FZip: TZCompressionStream;
    FIsFinished: Boolean;
    procedure WriteChunk(const ChunkType: AnsiString; Data: Pointer; Size: Integer);
    procedure FlushPending(IsForced: Boolean);
  public
    constructor Create(AStream: TStream; AWidth, AHeight: Integer);
    destructor Destroy; override;
    procedure AddText(const Keyword: AnsiString; const Text: RawByteString);
    procedure WriteRow(Rgb: PByte);
    procedure Finish;
  end;

function PngCrc32(Data: PByte; Size: Integer): Cardinal;
function ReadPngText(const FileName: string; const Keyword: AnsiString; out Text: RawByteString): Boolean;

implementation

const
  kPngSignature: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
  kIdatFlushSize = 65536;
  kMaxTextChunkSize = 1024 * 1024;
  kCrcPolynomial = $EDB88320;
  kCrcInit = $FFFFFFFF;
  kZlibWindowBits = 15;  // en-tête zlib + fenêtre de 32 Ko, le format exigé par PNG (0 est refusé en compression)

type
  // Puits pour TZCompressionStream : il exige un flux dont la position avance en même temps que les
  // écritures. Les octets réels vont dans le tampon FTarget, vidé à chaque bloc IDAT.
  TPendingSink = class(TStream)
  private
    FTarget: TMemoryStream;
    FPosition: Int64;
  public
    constructor Create(ATarget: TMemoryStream);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

var
  CrcTable: array[0..255] of Cardinal;

{------------------------------------------------------------------------------}

procedure BuildCrcTable;
var
  N, K: Integer;
  C: Cardinal;
begin
  for N := 0 to 255 do
  begin
    C := N;
    for K := 0 to 7 do
      if C and 1 <> 0 then
        C := kCrcPolynomial xor (C shr 1)
      else
        C := C shr 1;
    CrcTable[N] := C;
  end;
end;

{------------------------------------------------------------------------------}

function UpdateCrc(Crc: Cardinal; Data: PByte; Size: Integer): Cardinal;
var
  I: Integer;
begin
  Result := Crc;
  for I := 0 to Size - 1 do
  begin
    Result := CrcTable[(Result xor Data^) and $FF] xor (Result shr 8);
    Inc(Data);
  end;
end;

{------------------------------------------------------------------------------}

function PngCrc32(Data: PByte; Size: Integer): Cardinal;
begin
  Result := UpdateCrc(kCrcInit, Data, Size) xor kCrcInit;
end;

{------------------------------------------------------------------------------}

procedure WriteBigEndian(Stream: TStream; Value: Cardinal);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(Value shr 24);
  B[1] := Byte(Value shr 16);
  B[2] := Byte(Value shr 8);
  B[3] := Byte(Value);
  Stream.WriteBuffer(B, 4);
end;

{------------------------------------------------------------------------------}

function ReadBigEndian(Stream: TStream): Cardinal;
var
  B: array[0..3] of Byte;
begin
  Stream.ReadBuffer(B, 4);
  Result := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or (Cardinal(B[2]) shl 8) or B[3];
end;

{------------------------------------------------------------------------------}

constructor TPendingSink.Create(ATarget: TMemoryStream);
begin
  inherited Create;
  FTarget := ATarget;
end;

{------------------------------------------------------------------------------}

function TPendingSink.Read(var Buffer; Count: Longint): Longint;
begin
  raise EPngError.Create('Flux PNG en écriture seule');
end;

{------------------------------------------------------------------------------}

function TPendingSink.Write(const Buffer; Count: Longint): Longint;
begin
  FTarget.Seek(0, soFromEnd);
  FTarget.WriteBuffer(Buffer, Count);
  Inc(FPosition, Count);
  Result := Count;
end;

{------------------------------------------------------------------------------}

function TPendingSink.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  NewPosition: Int64;
begin
  case Origin of
    soBeginning:
      NewPosition := Offset;
    soCurrent:
      NewPosition := FPosition + Offset;
  else
    raise EPngError.Create('Flux PNG non positionnable');
  end;
  if NewPosition <> FPosition then
    raise EPngError.Create('Flux PNG non positionnable');
  Result := FPosition;
end;

{------------------------------------------------------------------------------}

constructor TPngWriter.Create(AStream: TStream; AWidth, AHeight: Integer);
var
  Header: array[0..12] of Byte;
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPngError.CreateFmt('Dimensions PNG invalides : %d x %d', [AWidth, AHeight]);
  FStream := AStream;
  FWidth := AWidth;
  FHeight := AHeight;
  FStream.WriteBuffer(kPngSignature, SizeOf(kPngSignature));
  Header[0] := Byte(AWidth shr 24);
  Header[1] := Byte(AWidth shr 16);
  Header[2] := Byte(AWidth shr 8);
  Header[3] := Byte(AWidth);
  Header[4] := Byte(AHeight shr 24);
  Header[5] := Byte(AHeight shr 16);
  Header[6] := Byte(AHeight shr 8);
  Header[7] := Byte(AHeight);
  Header[8] := 8;   // 8 bits par canal
  Header[9] := 2;   // RVB
  Header[10] := 0;  // compression deflate
  Header[11] := 0;  // filtrage standard
  Header[12] := 0;  // sans entrelacement
  WriteChunk('IHDR', @Header, SizeOf(Header));
  FPending := TMemoryStream.Create;
  FSink := TPendingSink.Create(FPending);
  // le paramètre windowBits n'existe qu'après D2010 ; D2010 utilise implicitement la même valeur
  {$IF CompilerVersion >= 22}
  FZip := TZCompressionStream.Create(FSink, zcDefault, kZlibWindowBits);
  {$ELSE}
  FZip := TZCompressionStream.Create(FSink, zcDefault);
  {$IFEND}
end;

{------------------------------------------------------------------------------}

destructor TPngWriter.Destroy;
begin
  FZip.Free;
  FSink.Free;
  FPending.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TPngWriter.WriteChunk(const ChunkType: AnsiString; Data: Pointer; Size: Integer);
var
  Crc: Cardinal;
begin
  WriteBigEndian(FStream, Size);
  FStream.WriteBuffer(ChunkType[1], 4);
  if Size > 0 then
    FStream.WriteBuffer(Data^, Size);
  Crc := UpdateCrc(kCrcInit, @ChunkType[1], 4);
  if Size > 0 then
    Crc := UpdateCrc(Crc, Data, Size);
  WriteBigEndian(FStream, Crc xor kCrcInit);
end;

{------------------------------------------------------------------------------}

procedure TPngWriter.FlushPending(IsForced: Boolean);
begin
  if (FPending.Size >= kIdatFlushSize) or (IsForced and (FPending.Size > 0)) then
  begin
    WriteChunk('IDAT', FPending.Memory, FPending.Size);
    FPending.Clear;
  end;
end;

{------------------------------------------------------------------------------}

procedure TPngWriter.AddText(const Keyword: AnsiString; const Text: RawByteString);
var
  Data: TMemoryStream;
  Zero: Byte;
begin
  if FRowsWritten > 0 then
    raise EPngError.Create('Le texte PNG doit précéder les lignes de l''image');
  Data := TMemoryStream.Create;
  try
    Data.WriteBuffer(Keyword[1], Length(Keyword));
    Zero := 0;
    Data.WriteBuffer(Zero, 1);
    if Length(Text) > 0 then
      Data.WriteBuffer(Text[1], Length(Text));
    WriteChunk('tEXt', Data.Memory, Data.Size);
  finally
    Data.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TPngWriter.WriteRow(Rgb: PByte);
var
  Filter: Byte;
begin
  if FIsFinished or (FRowsWritten >= FHeight) then
    raise EPngError.Create('Trop de lignes pour l''image PNG');
  Filter := 0;
  FZip.WriteBuffer(Filter, 1);
  FZip.WriteBuffer(Rgb^, FWidth * 3);
  Inc(FRowsWritten);
  FlushPending(False);
end;

{------------------------------------------------------------------------------}

procedure TPngWriter.Finish;
begin
  if FIsFinished then
    raise EPngError.Create('Image PNG déjà terminée');
  if FRowsWritten <> FHeight then
    raise EPngError.CreateFmt('Image PNG incomplète : %d lignes sur %d', [FRowsWritten, FHeight]);
  FreeAndNil(FZip);  // termine le flux deflate dans FPending
  FlushPending(True);
  WriteChunk('IEND', nil, 0);
  FIsFinished := True;
end;

{------------------------------------------------------------------------------}

function DoReadPngText(const FileName: string; const Keyword: AnsiString; out Text: RawByteString): Boolean;
var
  Stream: TFileStream;
  Signature: array[0..7] of Byte;
  ChunkType: array[0..3] of AnsiChar;
  Len: Cardinal;
  Data: RawByteString;
  I, Separator: Integer;
begin
  Result := False;
  Text := '';
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    on EFOpenError do
      Exit;
  end;
  try
    if (Stream.Read(Signature, 8) <> 8) or not CompareMem(@Signature, @kPngSignature, 8) then
      Exit;
    while Stream.Position + 8 <= Stream.Size do
    begin
      Len := ReadBigEndian(Stream);
      Stream.ReadBuffer(ChunkType, 4);
      if Int64(Len) + 4 > Stream.Size - Stream.Position then
        Exit;
      if CompareMem(@ChunkType, PAnsiChar('IEND'), 4) then
        Exit;
      if CompareMem(@ChunkType, PAnsiChar('tEXt'), 4) and (Len <= kMaxTextChunkSize) then
      begin
        SetLength(Data, Len);
        if Len > 0 then
          Stream.ReadBuffer(Data[1], Len);
        Stream.Seek(4, soCurrent);
        Separator := 0;
        for I := 1 to Length(Data) do
          if Data[I] = #0 then
          begin
            Separator := I;
            Break;
          end;
        if (Separator - 1 = Length(Keyword)) and (Length(Keyword) > 0)
          and CompareMem(@Data[1], @Keyword[1], Length(Keyword)) then
        begin
          Text := Copy(Data, Separator + 1, MaxInt);
          Exit(True);
        end;
      end
      else
        Stream.Seek(Int64(Len) + 4, soCurrent);
    end;
  finally
    Stream.Free;
  end;
end;

{------------------------------------------------------------------------------}

function ReadPngText(const FileName: string; const Keyword: AnsiString; out Text: RawByteString): Boolean;
begin
  try
    Result := DoReadPngText(FileName, Keyword, Text);
  except
    Result := False;
    Text := '';
  end;
end;

{------------------------------------------------------------------------------}

initialization
  BuildCrcTable;

end.
