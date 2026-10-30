unit Fractal.Download;

// Téléchargement par HTTP(S) avec WinInet (Windows seul, sans VCL ni bibliothèque tierce). Les opérations sont
// bloquantes : à appeler depuis un fil, jamais depuis le fil principal.

interface

uses
  SysUtils, Classes;

type
  EDownloadError = class(Exception);
  EDownloadCancelled = class(EDownloadError);

  // Total = -1 si la taille est inconnue ; appelé dans le fil qui télécharge
  TDownloadProgress = procedure(Received, Total: Int64) of object;

  TDownloader = class
  private
    FIsCancelled: Boolean;
  public
    function DownloadText(const Url: string): string; virtual; abstract;   // UTF-8 décodé (BOM éventuel conservé)
    procedure DownloadToFile(const Url, FileName: string; OnProgress: TDownloadProgress); virtual; abstract;
    procedure Cancel;                  // lu entre deux blocs ; DownloadToFile lève alors EDownloadCancelled
    property IsCancelled: Boolean read FIsCancelled;
  end;

  TWinInetDownloader = class(TDownloader)
  private
    procedure Fetch(const Url: string; Sink: TStream; OnProgress: TDownloadProgress);
  public
    function DownloadText(const Url: string): string; override;
    procedure DownloadToFile(const Url, FileName: string; OnProgress: TDownloadProgress); override;
  end;

implementation

uses
  Windows, WinInet;

const
  kAgentName = 'Fractales';
  kTimeoutMs = 10000;                  // connexion, envoi et réception
  kBlockSize = 65536;
  kHttpOk = 200;
  kNoTotal = -1;
  kCancelledText = 'Téléchargement annulé.';
  kHttpErrorFormat = 'HTTP %d';
  kNetworkErrorFormat = 'erreur réseau %d';   // codes WinInet (12000 et plus) inconnus de SysErrorMessage

{------------------------------------------------------------------------------}

procedure TDownloader.Cancel;
begin
  FIsCancelled := True;
end;

{------------------------------------------------------------------------------}

// Lève EDownloadError avec le message de la dernière erreur Windows
procedure RaiseLastDownloadError;
var
  Code: DWORD;
  Msg: string;
begin
  Code := GetLastError;
  Msg := Trim(SysErrorMessage(Code));
  if Msg = '' then
    Msg := Format(kNetworkErrorFormat, [Code]);
  raise EDownloadError.Create(Msg);
end;

{------------------------------------------------------------------------------}

procedure SetTimeouts(Session: HINTERNET);
var
  Value: DWORD;
begin
  Value := kTimeoutMs;
  InternetSetOption(Session, INTERNET_OPTION_CONNECT_TIMEOUT, @Value, SizeOf(Value));
  InternetSetOption(Session, INTERNET_OPTION_SEND_TIMEOUT, @Value, SizeOf(Value));
  InternetSetOption(Session, INTERNET_OPTION_RECEIVE_TIMEOUT, @Value, SizeOf(Value));
end;

{------------------------------------------------------------------------------}

// Code HTTP de la réponse
function QueryStatusCode(Request: HINTERNET): DWORD;
var
  Len, Index: DWORD;
begin
  Result := 0;
  Len := SizeOf(Result);
  Index := 0;
  if not HttpQueryInfo(Request, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Result, Len, Index) then
    RaiseLastDownloadError;
end;

{------------------------------------------------------------------------------}

// Taille annoncée par le serveur, ou kNoTotal
function QueryContentLength(Request: HINTERNET): Int64;
var
  Value, Len, Index: DWORD;
begin
  Value := 0;
  Len := SizeOf(Value);
  Index := 0;
  if HttpQueryInfo(Request, HTTP_QUERY_CONTENT_LENGTH or HTTP_QUERY_FLAG_NUMBER, @Value, Len, Index) then
    Result := Value
  else
    Result := kNoTotal;
end;

{------------------------------------------------------------------------------}

procedure TWinInetDownloader.Fetch(const Url: string; Sink: TStream; OnProgress: TDownloadProgress);
var
  Session, Request: HINTERNET;
  Block: array of Byte;
  Got: DWORD;
  Received, Total: Int64;
  Status: DWORD;
begin
  if IsCancelled then
    raise EDownloadCancelled.Create(kCancelledText);
  Session := InternetOpen(kAgentName, INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Session = nil then
    RaiseLastDownloadError;
  try
    SetTimeouts(Session);
    Request := InternetOpenUrl(Session, PChar(Url), nil, 0, INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE, 0);
    if Request = nil then
      RaiseLastDownloadError;
    try
      Status := QueryStatusCode(Request);
      if Status <> kHttpOk then
        raise EDownloadError.Create(Format(kHttpErrorFormat, [Status]));
      Total := QueryContentLength(Request);
      SetLength(Block, kBlockSize);
      Received := 0;
      repeat
        if IsCancelled then
          raise EDownloadCancelled.Create(kCancelledText);
        Got := 0;
        if not InternetReadFile(Request, @Block[0], kBlockSize, Got) then
          RaiseLastDownloadError;
        if Got > 0 then
        begin
          Sink.WriteBuffer(Block[0], Got);
          Inc(Received, Got);
          if Assigned(OnProgress) then
            OnProgress(Received, Total);
        end;
      until Got = 0;
    finally
      InternetCloseHandle(Request);
    end;
  finally
    InternetCloseHandle(Session);
  end;
end;

{------------------------------------------------------------------------------}

function TWinInetDownloader.DownloadText(const Url: string): string;
var
  Stream: TMemoryStream;
  Bytes: TBytes;
begin
  Stream := TMemoryStream.Create;
  try
    Fetch(Url, Stream, nil);
    SetLength(Bytes, Stream.Size);
    if Stream.Size > 0 then
      Move(Stream.Memory^, Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Result := TEncoding.UTF8.GetString(Bytes);   // le BOM éventuel est conservé : TryParseManifest le retire
end;

{------------------------------------------------------------------------------}

procedure TWinInetDownloader.DownloadToFile(const Url, FileName: string; OnProgress: TDownloadProgress);
var
  Stream: TFileStream;
begin
  try
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      Fetch(Url, Stream, OnProgress);
    finally
      Stream.Free;                     // fichier fermé avant toute vérification par l'appelant
    end;
  except
    SysUtils.DeleteFile(FileName);     // pas de fichier partiel
    raise;
  end;
end;

end.
