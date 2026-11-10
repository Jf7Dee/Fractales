unit Fractal.VideoEncoder;

// Encodage d'une vidéo par FFmpeg (programme externe) : les images PNG lui arrivent par un tube sur son entrée
// standard, ses messages vont dans un journal à côté de la vidéo.

interface

uses
  Windows, SysUtils, Classes, Math, SyncObjs;

const
  kFfmpegExe = 'ffmpeg.exe';
  kFfmpegHelp = 'FFmpeg est introuvable : téléchargez ffmpeg.exe (ffmpeg.org) et placez-le à côté de Fractales.exe.';

type
  EVideoEncoderError = class(Exception);

  TFfmpegPipe = class
  private
    FOutputFile: string;
    FLogFile: string;
    FProcess: TProcessInformation;
    FInput: THandle;  // extrémité d'écriture du tube vers l'entrée de FFmpeg
    FLock: TCriticalSection;  // FProcess, que Kill peut viser depuis un autre fil
    procedure CloseProcess;
    procedure StopProcess;
    function LogTail: string;
    procedure Fail(const Text: string);
  public
    constructor Create(const FfmpegExe, OutputFile: string; Fps: Integer);
    destructor Destroy; override;
    procedure WriteFrame(Png: TStream);
    procedure Finish;
    procedure Abort;   // abandon voulu : vidéo partielle et journal supprimés
    procedure Kill;    // depuis un autre fil : arrête FFmpeg, ce qui débloque WriteFrame et Finish
  end;

function FindFfmpeg(const ExeFolder, ConfiguredPath: string): string;
function FfmpegArguments(const OutputFile: string; Fps: Integer): string;

implementation

const
  kLogExtension = '.log';
  kPipeBufferBytes = 1024 * 1024;
  kWriteChunkBytes = 64 * 1024;
  kLogTailChars = 800;
  kBelowNormalPriority = $00004000;  // BELOW_NORMAL_PRIORITY_CLASS, absent de Windows.pas en D2010

{------------------------------------------------------------------------------}

function FindFfmpeg(const ExeFolder, ConfiguredPath: string): string;
begin
  if (ConfiguredPath <> '') and FileExists(ConfiguredPath) then
    Result := ConfiguredPath
  else if FileExists(IncludeTrailingPathDelimiter(ExeFolder) + kFfmpegExe) then
    Result := IncludeTrailingPathDelimiter(ExeFolder) + kFfmpegExe
  else
    Result := '';
end;

{------------------------------------------------------------------------------}

// H.264 en yuv420p : lisible partout (téléphones, Facebook, Instagram) ; débit élevé, les fractales compressent mal.
// yuv420p exige des dimensions paires : une ligne ou une colonne impaire est retirée (aperçu réduit)
function FfmpegArguments(const OutputFile: string; Fps: Integer): string;
begin
  Result := Format('-y -hide_banner -loglevel error -f image2pipe -framerate %d -c:v png -i - ' +
    '-vf "crop=trunc(iw/2)*2:trunc(ih/2)*2" ' +
    '-c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart "%s"', [Fps, OutputFile]);
end;

{------------------------------------------------------------------------------}

constructor TFfmpegPipe.Create(const FfmpegExe, OutputFile: string; Fps: Integer);
var
  Security: TSecurityAttributes;
  StdInRead, Log: THandle;
  Startup: TStartupInfo;
  CommandLine: string;
  IsStarted: Boolean;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FOutputFile := OutputFile;
  FLogFile := OutputFile + kLogExtension;
  if (FfmpegExe = '') or not FileExists(FfmpegExe) then
    raise EVideoEncoderError.Create(kFfmpegHelp);
  Security.nLength := SizeOf(Security);
  Security.lpSecurityDescriptor := nil;
  Security.bInheritHandle := True;
  if not CreatePipe(StdInRead, FInput, @Security, kPipeBufferBytes) then
    RaiseLastOSError;
  // seule l'extrémité de lecture passe à FFmpeg : sinon il ne verrait jamais la fin des images
  SetHandleInformation(FInput, HANDLE_FLAG_INHERIT, 0);
  Log := CreateFile(PChar(FLogFile), GENERIC_WRITE, FILE_SHARE_READ, @Security, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  try
    if Log = INVALID_HANDLE_VALUE then
      raise EVideoEncoderError.CreateFmt('Journal de FFmpeg impossible à créer (%s) : %s',
        [FLogFile, SysErrorMessage(GetLastError)]);
    FillChar(Startup, SizeOf(Startup), 0);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    Startup.hStdInput := StdInRead;
    Startup.hStdOutput := Log;
    Startup.hStdError := Log;
    CommandLine := '"' + FfmpegExe + '" ' + FfmpegArguments(OutputFile, Fps);
    UniqueString(CommandLine);  // CreateProcess peut écrire dans la ligne de commande
    // priorité réduite : l'encodage prend tous les cœurs, Windows doit rester utilisable
    IsStarted := CreateProcess(nil, PChar(CommandLine), nil, nil, True,
      CREATE_NO_WINDOW or kBelowNormalPriority, nil, nil, Startup, FProcess);
    if not IsStarted then
      raise EVideoEncoderError.CreateFmt('FFmpeg n''a pas pu démarrer : %s', [SysErrorMessage(GetLastError)]);
  except
    CloseHandle(FInput);
    FInput := 0;
    CloseHandle(StdInRead);
    if Log <> INVALID_HANDLE_VALUE then
      CloseHandle(Log);
    SysUtils.DeleteFile(FLogFile);
    raise;
  end;
  CloseHandle(StdInRead);
  CloseHandle(Log);
end;

{------------------------------------------------------------------------------}

destructor TFfmpegPipe.Destroy;
begin
  if FInput <> 0 then
    Abort;
  CloseProcess;
  FLock.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TFfmpegPipe.CloseProcess;
begin
  FLock.Enter;
  try
    if FProcess.hProcess <> 0 then
    begin
      CloseHandle(FProcess.hThread);
      CloseHandle(FProcess.hProcess);
      FProcess.hProcess := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFfmpegPipe.Kill;
begin
  FLock.Enter;
  try
    if FProcess.hProcess <> 0 then
      TerminateProcess(FProcess.hProcess, 1);
  finally
    FLock.Leave;
  end;
end;

{------------------------------------------------------------------------------}

// Fin du journal de FFmpeg : ce qu'il a dit avant d'échouer
function TFfmpegPipe.LogTail: string;
var
  Stream: TFileStream;
  Bytes: RawByteString;
begin
  Result := '';
  try
    Stream := TFileStream.Create(FLogFile, fmOpenRead or fmShareDenyNone);
    try
      Stream.Position := Max(0, Stream.Size - kLogTailChars);
      SetLength(Bytes, Stream.Size - Stream.Position);
      if Length(Bytes) > 0 then
        Stream.ReadBuffer(Bytes[1], Length(Bytes));
    finally
      Stream.Free;
    end;
    Result := Trim(StringReplace(string(Bytes), #13, #10, [rfReplaceAll]));
  except
    on E: EStreamError do
      Result := '';
  end;
end;

{------------------------------------------------------------------------------}

procedure TFfmpegPipe.Fail(const Text: string);
var
  Tail: string;
begin
  Tail := LogTail;
  StopProcess;  // le journal reste, pour comprendre l'échec
  if Tail <> '' then
    raise EVideoEncoderError.Create(Text + #13#10 + Tail)
  else
    raise EVideoEncoderError.Create(Text);
end;

{------------------------------------------------------------------------------}

procedure TFfmpegPipe.WriteFrame(Png: TStream);
var
  Buffer: array[0..kWriteChunkBytes - 1] of Byte;
  Count: Integer;
  Written: DWORD;
begin
  if Png = nil then
    raise EArgumentException.Create('WriteFrame : Png nil');
  if FInput = 0 then
    raise EVideoEncoderError.Create('Encodage déjà terminé.');
  Png.Position := 0;
  repeat
    Count := Png.Read(Buffer, SizeOf(Buffer));
    if (Count > 0) and not (WriteFile(FInput, Buffer, Count, Written, nil) and (Integer(Written) = Count)) then
      Fail('FFmpeg a cessé de recevoir les images.');
  until Count = 0;
end;

{------------------------------------------------------------------------------}

procedure TFfmpegPipe.Finish;
var
  ExitCode: DWORD;
begin
  if FInput = 0 then
    raise EVideoEncoderError.Create('Encodage déjà terminé.');
  CloseHandle(FInput);  // fin des images : FFmpeg termine la vidéo et s'arrête
  FInput := 0;
  WaitForSingleObject(FProcess.hProcess, INFINITE);
  if not GetExitCodeProcess(FProcess.hProcess, ExitCode) then
    ExitCode := 1;
  CloseProcess;
  if ExitCode <> 0 then
    Fail(Format('FFmpeg a échoué (code %d).', [ExitCode]));
  SysUtils.DeleteFile(FLogFile);
end;

{------------------------------------------------------------------------------}

// Arrête FFmpeg et attend sa fin (un processus tué meurt toujours), puis supprime la vidéo partielle
procedure TFfmpegPipe.StopProcess;
begin
  if FInput <> 0 then
  begin
    CloseHandle(FInput);
    FInput := 0;
  end;
  if FProcess.hProcess <> 0 then
  begin
    if WaitForSingleObject(FProcess.hProcess, 0) = WAIT_TIMEOUT then
      TerminateProcess(FProcess.hProcess, 1);
    WaitForSingleObject(FProcess.hProcess, INFINITE);
    CloseProcess;
  end;
  SysUtils.DeleteFile(FOutputFile);
end;

{------------------------------------------------------------------------------}

procedure TFfmpegPipe.Abort;
begin
  StopProcess;
  SysUtils.DeleteFile(FLogFile);
end;

end.
