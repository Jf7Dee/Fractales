unit TestUtils;

interface

function TestTempFolder: string;

implementation

uses
  Windows, SysUtils;

{------------------------------------------------------------------------------}

function TestTempFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  GetTempPath(MAX_PATH, Buffer);
  Result := IncludeTrailingPathDelimiter(Buffer) + 'FractalesTests\';
  ForceDirectories(Result);
end;

end.
