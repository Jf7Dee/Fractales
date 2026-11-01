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
  kNetworkErrorFormat = '%s : erreur réseau %d';   // codes WinInet (12000 et plus) inconnus de SysErrorMessage
  kStepErrorFormat = '%s : %s (%d)';
  kStepOpen = 'InternetOpen';          // étapes nommées dans les messages d'erreur
  kStepOpenUrl = 'InternetOpenUrl';
  kStepQueryStatus = 'HttpQueryInfo';
  kStepRead = 'InternetReadFile';

{------------------------------------------------------------------------------}

procedure TDownloader.Cancel;
begin
  FIsCancelled := True;
end;

{------------------------------------------------------------------------------}

// Lève EDownloadError avec l'étape en cause et le message de l'erreur Windows
procedure RaiseDownloadError(const Step: string; Code: DWORD);
var
  Msg: string;
begin
  Msg := Trim(SysErrorMessage(Code));
  if Msg = '' then
    raise EDownloadError.Create(Format(kNetworkErrorFormat, [Step, Code]));
  raise EDownloadError.Create(Format(kStepErrorFormat, [Step, Msg, Code]));
end;

{------------------------------------------------------------------------------}

procedure RaiseLastDownloadError(const Step: string);
begin
  RaiseDownloadError(Step, GetLastError);
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
    RaiseLastDownloadError(kStepQueryStatus);
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

// Ouvre l'adresse avec les réglages réseau de Windows (proxy compris), puis en connexion directe si l'adresse ne
// s'ouvre pas ainsi : un réglage de proxy défaillant fait échouer WinInet sur certains postes (erreur 1168). Une
// réponse du serveur, même une erreur HTTP, n'est jamais réessayée
procedure OpenUrl(const Url: string; out Session, Request: HINTERNET);
const
  kAccessTypes: array[0..1] of DWORD = (INTERNET_OPEN_TYPE_PRECONFIG, INTERNET_OPEN_TYPE_DIRECT);
var
  I: Integer;
  Code: DWORD;
begin
  Request := nil;
  for I := Low(kAccessTypes) to High(kAccessTypes) do
  begin
    Session := InternetOpen(kAgentName, kAccessTypes[I], nil, nil, 0);
    if Session = nil then
      RaiseLastDownloadError(kStepOpen);
    SetTimeouts(Session);
    // NO_UI : jamais de boîte de dialogue de WinInet (fil sans fenêtre) ; NO_COOKIES : rien n'est conservé
    Request := InternetOpenUrl(Session, PChar(Url), nil, 0, INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE
      or INTERNET_FLAG_NO_UI or INTERNET_FLAG_NO_COOKIES, 0);
    if Request <> nil then
      Exit;
    Code := GetLastError;
    InternetCloseHandle(Session);
  end;
  Session := nil;
  RaiseDownloadError(kStepOpenUrl, Code);   // erreur du dernier essai, en direct
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
  OpenUrl(Url, Session, Request);
  try
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
          RaiseLastDownloadError(kStepRead);
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
