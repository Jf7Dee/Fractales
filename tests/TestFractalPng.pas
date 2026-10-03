unit TestFractalPng;

interface

uses
  Classes, SysUtils, Graphics, pngimage, TestFramework, Fractal.Palette, Fractal.Png, TestUtils;

type
  TTestPng = class(TTestCase)
  private
    function PixelColor(X, Y: Integer): Cardinal;
    procedure WritePng(const FileName: string; W, H: Integer; const Text: RawByteString);
    procedure CheckPixels(const FileName: string; W, H, Stride: Integer);
  published
    procedure TestCrcOfIend;
    procedure TestSmallImageDecodes;
    procedure TestLargeImageDecodes;
    procedure TestTextRoundTrip;
    procedure TestMissingKeywordReturnsFalse;
    procedure TestNonPngReturnsFalse;
    procedure TestIncompleteImageRaises;
  end;

implementation

{------------------------------------------------------------------------------}

function TTestPng.PixelColor(X, Y: Integer): Cardinal;
begin
  // valeurs pseudo-aléatoires peu compressibles : force plusieurs blocs IDAT
  Result := (Cardinal(X) * 73856093) xor (Cardinal(Y) * 19349663);
  Result := (Result * 2654435761) and $FFFFFF;
end;

{------------------------------------------------------------------------------}

procedure TTestPng.WritePng(const FileName: string; W, H: Integer; const Text: RawByteString);
var
  Stream: TFileStream;
  Writer: TPngWriter;
  Row: array of Byte;
  X, Y: Integer;
  C: Cardinal;
begin
  SetLength(Row, W * 3);
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Writer := TPngWriter.Create(Stream, W, H);
    try
      if Text <> '' then
        Writer.AddText(kLocationKeyword, Text);
      for Y := 0 to H - 1 do
      begin
        for X := 0 to W - 1 do
        begin
          C := PixelColor(X, Y);
          Row[X * 3] := (C shr 16) and $FF;
          Row[X * 3 + 1] := (C shr 8) and $FF;
          Row[X * 3 + 2] := C and $FF;
        end;
        Writer.WriteRow(@Row[0]);
      end;
      Writer.Finish;
    finally
      Writer.Free;
    end;
  finally
    Stream.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPng.CheckPixels(const FileName: string; W, H, Stride: Integer);
var
  Png: TPngImage;
  X, Y: Integer;
begin
  Png := TPngImage.Create;
  try
    Png.LoadFromFile(FileName);
    CheckEquals(W, Png.Width);
    CheckEquals(H, Png.Height);
    Y := 0;
    while Y < H do
    begin
      X := 0;
      while X < W do
      begin
        CheckEquals(Integer(SwapRedBlue(PixelColor(X, Y))), Integer(Png.Pixels[X, Y]), Format('(%d, %d)', [X, Y]));
        Inc(X, Stride);
      end;
      Inc(Y, Stride);
    end;
  finally
    Png.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestCrcOfIend;
var
  S: AnsiString;
begin
  S := 'IEND';
  CheckEquals(Integer($AE426082), Integer(PngCrc32(@S[1], 4)));
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestSmallImageDecodes;
var
  FileName: string;
begin
  FileName := TestTempFolder + 'small.png';
  WritePng(FileName, 4, 3, 'abc');
  CheckPixels(FileName, 4, 3, 1);
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestLargeImageDecodes;
var
  FileName: string;
begin
  FileName := TestTempFolder + 'large.png';
  WritePng(FileName, 300, 400, '');
  CheckPixels(FileName, 300, 400, 37);
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestTextRoundTrip;
var
  FileName: string;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'text.png';
  WritePng(FileName, 4, 3, UTF8Encode('Précédent=1'));
  CheckTrue(ReadPngText(FileName, kLocationKeyword, Text));
  CheckEquals('Précédent=1', UTF8ToString(Text));
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestMissingKeywordReturnsFalse;
var
  FileName: string;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'text.png';
  WritePng(FileName, 4, 3, 'abc');
  CheckFalse(ReadPngText(FileName, 'Autre', Text));
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestNonPngReturnsFalse;
var
  FileName: string;
  L: TStringList;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'pas-un-png.png';
  L := TStringList.Create;
  try
    L.Add('bonjour');
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
  CheckFalse(ReadPngText(FileName, kLocationKeyword, Text));
  CheckFalse(ReadPngText(TestTempFolder + 'inexistant.png', kLocationKeyword, Text));
end;

{------------------------------------------------------------------------------}

procedure TTestPng.TestIncompleteImageRaises;
var
  Stream: TMemoryStream;
  Writer: TPngWriter;
  Row: array[0..11] of Byte;
  IsRaised: Boolean;
begin
  FillChar(Row, SizeOf(Row), 0);
  Stream := TMemoryStream.Create;
  Writer := TPngWriter.Create(Stream, 4, 3);
  try
    Writer.WriteRow(@Row[0]);
    IsRaised := False;
    try
      Writer.Finish;
    except
      on EPngError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    Writer.Free;
    Stream.Free;
  end;
end;

initialization
  RegisterTest(TTestPng.Suite);

end.
