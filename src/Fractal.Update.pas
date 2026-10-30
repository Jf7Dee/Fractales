unit Fractal.Update;

// Mise à jour du programme : réglages (MiseAJour.ini), versions, manifeste publié avec chaque release, décision,
// empreinte SHA-256, installation, puis vérification et téléchargement (par un TDownloader) et leurs deux fils.

interface

uses
  SysUtils, Classes, Fractal.Download;

const
  kUpdateConfigFileName = 'MiseAJour.ini';
  kManifestFileName = 'manifeste.ini';
  kDefaultManifestUrl = 'https://github.com/Jf7Dee/Fractales/releases/latest/download/manifeste.ini';
  kExeFileName = 'Fractales.exe';      // la DLL : kRustKernelFileName (Fractal.RustKernel)
  kNewSuffix = '.new';
  kOldSuffix = '.old';

type
  TUpdateMode = (umNone, umPropose, umSilent);
  TUpdateConfig = record
    Mode: TUpdateMode;
    ManifestUrl: string;               // kDefaultManifestUrl si absent ou vide
  end;
  TFileVersion = array[0..3] of Word;
  TUpdateManifest = record
    Version: TFileVersion;
    IsMandatory: Boolean;
    Notes: string;
    ExeSha256: string;                 // 64 caractères hexadécimaux, en minuscules après lecture
    DllSha256: string;
  end;
  TUpdateDecision = (udNothing, udPropose, udNotify);
  TUpdateCheckResult = (ucNothing, ucAvailable, ucFailed, ucInvalid);

function LoadUpdateConfig(const FileName: string): TUpdateConfig;
function UpdateConfigFilePath: string;
function TryParseVersion(const S: string; out V: TFileVersion): Boolean;
function CompareVersions(const A, B: TFileVersion): Integer;
function VersionToString(const V: TFileVersion): string;
function TryReadFileVersion(const FileName: string; out V: TFileVersion): Boolean;
function TryParseManifest(const Text: string; out M: TUpdateManifest): Boolean;
function SiblingUrl(const ManifestUrl, FileName: string): string;
function DecideUpdate(Mode: TUpdateMode; const Installed, Available: TFileVersion): TUpdateDecision;
function FileSha256(const FileName: string): string;
function TryInstallFiles(const Folder: string; out ErrorText: string): Boolean;
procedure DeleteNewFiles(const Folder: string);
function CheckForUpdate(Downloader: TDownloader; const ManifestUrl: string; const Installed: TFileVersion;
  out Manifest: TUpdateManifest; out ErrorText: string): TUpdateCheckResult;
function DownloadUpdate(Downloader: TDownloader; const ManifestUrl, Folder: string; const Manifest: TUpdateManifest;
  OnProgress: TDownloadProgress; out ErrorText: string): Boolean;

type
  // Les résultats se lisent dans OnDone (appelé dans le fil principal, via OnTerminate) ; à libérer par l'appelant
  TUpdateCheckThread = class(TThread)
  private
    FManifestUrl: string;
    FInstalled: TFileVersion;
    FCheckResult: TUpdateCheckResult;
    FManifest: TUpdateManifest;
    FErrorText: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const ManifestUrl: string; const Installed: TFileVersion; OnDone: TNotifyEvent);
    property CheckResult: TUpdateCheckResult read FCheckResult;
    property Manifest: TUpdateManifest read FManifest;
    property ErrorText: string read FErrorText;
  end;

  // OnProgress est relayé dans le fil principal (Synchronize) ; ne pas appeler WaitFor depuis ce fil-là pendant le
  // téléchargement
  TUpdateDownloadThread = class(TThread)
  private
    FManifestUrl: string;
    FFolder: string;
    FManifest: TUpdateManifest;
    FOnProgress: TDownloadProgress;
    FDownloader: TDownloader;
    FIsSuccess: Boolean;
    FErrorText: string;
    FReceived: Int64;
    FTotal: Int64;
    procedure HandleProgress(Received, Total: Int64);
    procedure DeliverProgress;
  protected
    procedure Execute; override;
  public
    constructor Create(const ManifestUrl, Folder: string; const Manifest: TUpdateManifest;
      OnProgress: TDownloadProgress; OnDone: TNotifyEvent);
    destructor Destroy; override;
    procedure Cancel;
    property IsSuccess: Boolean read FIsSuccess;
    property ErrorText: string read FErrorText;
  end;

implementation

uses
  Windows, IniFiles, Fractal.RustKernel;

const
  kSectionUpdate = 'MiseAJour';
  kSectionVersion = 'Version';
  kSectionFiles = 'Fichiers';
  kKeyMode = 'Mode';
  kKeyManifest = 'Manifeste';
  kKeyNumber = 'Numero';
  kKeyMandatory = 'Obligatoire';
  kKeyNotes = 'Notes';
  kModePropose = 'Proposer';
  kModeSilent = 'Silencieux';
  kMandatoryYes = '1';
  kMaxVersionPart = 65535;
  kShaHexLength = 64;
  kShaByteCount = 32;
  kReadBlockSize = 65536;
  kHexDigits = '0123456789abcdef';

  // Interface cryptographique de Windows : absente (ou différente) selon la version de Delphi, donc déclarée ici
  kProvRsaAes = 24;
  kCryptVerifyContext = DWORD($F0000000);
  kCalgSha256 = $0000800C;
  kHashVal = 2;                        // HP_HASHVAL
  kMaxRenames = 4;
  kMissingNewFilesText = 'Fichiers téléchargés introuvables.';
  kCorruptFormat = 'Le fichier %s est corrompu (empreinte différente).';
  kVersionMismatchText = 'La version téléchargée ne correspond pas au manifeste.';

type
  TCryptHandle = NativeUInt;

function UpdAcquireContext(out Prov: TCryptHandle; Container, Provider: PWideChar; ProvType, Flags: DWORD): BOOL;
  stdcall; external 'advapi32.dll' name 'CryptAcquireContextW';
function UpdReleaseContext(Prov: TCryptHandle; Flags: DWORD): BOOL; stdcall;
  external 'advapi32.dll' name 'CryptReleaseContext';
function UpdCreateHash(Prov: TCryptHandle; Algid: DWORD; Key: TCryptHandle; Flags: DWORD;
  out Hash: TCryptHandle): BOOL; stdcall; external 'advapi32.dll' name 'CryptCreateHash';
function UpdHashData(Hash: TCryptHandle; Data: Pointer; DataLen, Flags: DWORD): BOOL; stdcall;
  external 'advapi32.dll' name 'CryptHashData';
function UpdGetHashParam(Hash: TCryptHandle; Param: DWORD; Data: Pointer; var DataLen: DWORD; Flags: DWORD): BOOL;
  stdcall; external 'advapi32.dll' name 'CryptGetHashParam';
function UpdDestroyHash(Hash: TCryptHandle): BOOL; stdcall; external 'advapi32.dll' name 'CryptDestroyHash';

{------------------------------------------------------------------------------}

function LoadUpdateConfig(const FileName: string): TUpdateConfig;
var
  Ini: TMemIniFile;
  Text: string;
begin
  Result.Mode := umNone;
  Result.ManifestUrl := kDefaultManifestUrl;
  if not FileExists(FileName) then
    Exit;
  try
    Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
    try
      Text := Trim(Ini.ReadString(kSectionUpdate, kKeyMode, ''));
      if SameText(Text, kModePropose) then
        Result.Mode := umPropose
      else if SameText(Text, kModeSilent) then
        Result.Mode := umSilent;
      Text := Trim(Ini.ReadString(kSectionUpdate, kKeyManifest, ''));
      if Text <> '' then
        Result.ManifestUrl := Text;
    finally
      Ini.Free;
    end;
  except
    Result.Mode := umNone;  // fichier illisible : aucune vérification
    Result.ManifestUrl := kDefaultManifestUrl;
  end;
end;

{------------------------------------------------------------------------------}

function UpdateConfigFilePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + kUpdateConfigFileName;
end;

{------------------------------------------------------------------------------}

function TryParsePart(const S: string; out Part: Word): Boolean;
var
  I, N: Integer;
begin
  Result := False;
  Part := 0;
  if (S = '') or (Length(S) > 5) then
    Exit;
  N := 0;
  for I := 1 to Length(S) do
  begin
    if (S[I] < '0') or (S[I] > '9') then
      Exit;
    N := N * 10 + Ord(S[I]) - Ord('0');
  end;
  if N > kMaxVersionPart then
    Exit;
  Part := N;
  Result := True;
end;

{------------------------------------------------------------------------------}

function TryParseVersion(const S: string; out V: TFileVersion): Boolean;
var
  I, Count, Start: Integer;
  Part: Word;
begin
  Result := False;
  for I := 0 to 3 do
    V[I] := 0;
  Count := 0;
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = '.') then
    begin
      if (Count > 3) or not TryParsePart(Copy(S, Start, I - Start), Part) then
      begin
        for Count := 0 to 3 do
          V[Count] := 0;
        Exit;
      end;
      V[Count] := Part;
      Inc(Count);
      Start := I + 1;
    end;
  Result := True;
end;

{------------------------------------------------------------------------------}

function CompareVersions(const A, B: TFileVersion): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 3 do
    if A[I] <> B[I] then
    begin
      Result := Ord(A[I] > B[I]) - Ord(A[I] < B[I]);
      Exit;
    end;
end;

{------------------------------------------------------------------------------}

function VersionToString(const V: TFileVersion): string;
begin
  Result := Format('%d.%d.%d.%d', [V[0], V[1], V[2], V[3]]);
end;

{------------------------------------------------------------------------------}

function TryReadFileVersion(const FileName: string; out V: TFileVersion): Boolean;
var
  Handle, Size, Len: DWORD;
  I: Integer;
  Data: array of Byte;
  Info: PVSFixedFileInfo;
begin
  Result := False;
  for I := 0 to 3 do
    V[I] := 0;
  Handle := 0;
  Size := GetFileVersionInfoSize(PChar(FileName), Handle);
  if Size = 0 then
    Exit;
  SetLength(Data, Size);
  if not GetFileVersionInfo(PChar(FileName), 0, Size, @Data[0]) then
    Exit;
  Info := nil;
  Len := 0;
  if not VerQueryValue(@Data[0], '\', Pointer(Info), Len) or (Info = nil) or (Len < SizeOf(TVSFixedFileInfo)) then
    Exit;
  V[0] := Info^.dwFileVersionMS shr 16;
  V[1] := Info^.dwFileVersionMS and $FFFF;
  V[2] := Info^.dwFileVersionLS shr 16;
  V[3] := Info^.dwFileVersionLS and $FFFF;
  Result := True;
end;

{------------------------------------------------------------------------------}

function TryNormalizeSha(const S: string; out Hash: string): Boolean;
var
  I: Integer;
begin
  Hash := LowerCase(Trim(S));
  Result := Length(Hash) = kShaHexLength;
  if Result then
    for I := 1 to kShaHexLength do
      if Pos(Hash[I], kHexDigits) = 0 then
      begin
        Result := False;
        Break;
      end;
  if not Result then
    Hash := '';
end;

{------------------------------------------------------------------------------}

function TryParseManifest(const Text: string; out M: TUpdateManifest): Boolean;
var
  Ini: TMemIniFile;
  Lines: TStringList;
  Body: string;
begin
  Result := False;
  M.Version[0] := 0;
  M.Version[1] := 0;
  M.Version[2] := 0;
  M.Version[3] := 0;
  M.IsMandatory := False;
  M.Notes := '';
  M.ExeSha256 := '';
  M.DllSha256 := '';
  Body := Text;
  if (Body <> '') and (Body[1] = #$FEFF) then
    Delete(Body, 1, 1);
  try
    Lines := TStringList.Create;
    try
      Lines.Text := Body;
      Ini := TMemIniFile.Create('');
      try
        Ini.SetStrings(Lines);
        if TryParseVersion(Trim(Ini.ReadString(kSectionVersion, kKeyNumber, '')), M.Version)
          and TryNormalizeSha(Ini.ReadString(kSectionFiles, kExeFileName, ''), M.ExeSha256)
          and TryNormalizeSha(Ini.ReadString(kSectionFiles, kRustKernelFileName, ''), M.DllSha256) then
        begin
          M.IsMandatory := Trim(Ini.ReadString(kSectionVersion, kKeyMandatory, '')) = kMandatoryYes;
          M.Notes := Trim(Ini.ReadString(kSectionVersion, kKeyNotes, ''));
          Result := True;
        end;
      finally
        Ini.Free;
      end;
    finally
      Lines.Free;
    end;
  except
    Result := False;
  end;
  if not Result then
  begin
    M.Version[0] := 0;
    M.Version[1] := 0;
    M.Version[2] := 0;
    M.Version[3] := 0;
    M.IsMandatory := False;
    M.Notes := '';
    M.ExeSha256 := '';
    M.DllSha256 := '';
  end;
end;

{------------------------------------------------------------------------------}

function SiblingUrl(const ManifestUrl, FileName: string): string;
var
  I: Integer;
begin
  I := Length(ManifestUrl);
  while (I > 0) and (ManifestUrl[I] <> '/') do
    Dec(I);
  Result := Copy(ManifestUrl, 1, I) + FileName;
end;

{------------------------------------------------------------------------------}

function DecideUpdate(Mode: TUpdateMode; const Installed, Available: TFileVersion): TUpdateDecision;
begin
  Result := udNothing;
  if (Mode = umNone) or (CompareVersions(Available, Installed) <= 0) then
    Exit;
  if Mode = umPropose then
    Result := udPropose
  else
    Result := udNotify;
end;

{------------------------------------------------------------------------------}

function FileSha256(const FileName: string): string;
var
  Stream: TFileStream;
  Prov, Hash: TCryptHandle;
  Block: array of Byte;
  Digest: array[0..kShaByteCount - 1] of Byte;
  Count, I: Integer;
  Len: DWORD;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if not UpdAcquireContext(Prov, nil, nil, kProvRsaAes, kCryptVerifyContext) then
      RaiseLastOSError;
    try
      if not UpdCreateHash(Prov, kCalgSha256, 0, 0, Hash) then
        RaiseLastOSError;
      try
        SetLength(Block, kReadBlockSize);
        repeat
          Count := Stream.Read(Block[0], kReadBlockSize);
          if (Count > 0) and not UpdHashData(Hash, @Block[0], Count, 0) then
            RaiseLastOSError;
        until Count = 0;
        Len := kShaByteCount;
        if not UpdGetHashParam(Hash, kHashVal, @Digest[0], Len, 0) then
          RaiseLastOSError;
      finally
        UpdDestroyHash(Hash);
      end;
    finally
      UpdReleaseContext(Prov, 0);
    end;
  finally
    Stream.Free;
  end;
  Result := '';
  for I := 0 to kShaByteCount - 1 do
    Result := Result + kHexDigits[(Digest[I] shr 4) + 1] + kHexDigits[(Digest[I] and $F) + 1];
end;

{------------------------------------------------------------------------------}

procedure DeleteNewFiles(const Folder: string);
begin
  SysUtils.DeleteFile(Folder + kExeFileName + kNewSuffix);
  SysUtils.DeleteFile(Folder + kRustKernelFileName + kNewSuffix);
end;

{------------------------------------------------------------------------------}

function TryInstallFiles(const Folder: string; out ErrorText: string): Boolean;
var
  Exe, Dll: string;
  Done: array[0..kMaxRenames - 1] of record
    Source, Target: string;
  end;
  DoneCount, I: Integer;

  // Renomme sans écraser et note le renommage réussi ; en cas d'échec, capture le message système
  function Rename(const Source, Target: string): Boolean;
  begin
    Result := MoveFile(PChar(Source), PChar(Target));
    if Result then
    begin
      Done[DoneCount].Source := Source;
      Done[DoneCount].Target := Target;
      Inc(DoneCount);
    end
    else
      ErrorText := SysErrorMessage(GetLastError);
  end;

  // Efface un ancien fichier s'il existe ; son absence n'est pas une erreur
  function RemoveStale(const FileName: string): Boolean;
  begin
    Result := not FileExists(FileName) or SysUtils.DeleteFile(FileName);
    if not Result then
      ErrorText := SysErrorMessage(GetLastError);
  end;

begin
  ErrorText := '';
  DoneCount := 0;
  Exe := Folder + kExeFileName;
  Dll := Folder + kRustKernelFileName;
  Result := False;
  if not FileExists(Exe + kNewSuffix) or not FileExists(Dll + kNewSuffix) then
  begin
    ErrorText := kMissingNewFilesText;
    Exit;
  end;
  Result := RemoveStale(Exe + kOldSuffix) and RemoveStale(Dll + kOldSuffix)
    and Rename(Exe, Exe + kOldSuffix)
    and (not FileExists(Dll) or Rename(Dll, Dll + kOldSuffix))
    and Rename(Exe + kNewSuffix, Exe)
    and Rename(Dll + kNewSuffix, Dll);
  if Result then
    Exit;
  // Retour arrière : les renommages réussis sont défaits en ordre inverse (le message reste celui de l'échec)
  for I := DoneCount - 1 downto 0 do
    MoveFile(PChar(Done[I].Target), PChar(Done[I].Source));
  DeleteNewFiles(Folder);
end;

{------------------------------------------------------------------------------}

function CheckForUpdate(Downloader: TDownloader; const ManifestUrl: string; const Installed: TFileVersion;
  out Manifest: TUpdateManifest; out ErrorText: string): TUpdateCheckResult;
var
  Text: string;
begin
  TryParseManifest('', Manifest);      // remet le manifeste à zéro
  ErrorText := '';
  try
    Text := Downloader.DownloadText(ManifestUrl);
  except
    on E: EDownloadError do
    begin
      ErrorText := E.Message;
      Result := ucFailed;
      Exit;
    end;
  end;
  if not TryParseManifest(Text, Manifest) then
    Result := ucInvalid
  else if CompareVersions(Manifest.Version, Installed) > 0 then
    Result := ucAvailable
  else
    Result := ucNothing;
end;

{------------------------------------------------------------------------------}

function DownloadUpdate(Downloader: TDownloader; const ManifestUrl, Folder: string; const Manifest: TUpdateManifest;
  OnProgress: TDownloadProgress; out ErrorText: string): Boolean;
var
  ExeNew, DllNew: string;
  Downloaded: TFileVersion;
begin
  Result := False;
  ErrorText := '';
  ExeNew := Folder + kExeFileName + kNewSuffix;
  DllNew := Folder + kRustKernelFileName + kNewSuffix;
  try
    Downloader.DownloadToFile(SiblingUrl(ManifestUrl, kExeFileName), ExeNew, OnProgress);
    Downloader.DownloadToFile(SiblingUrl(ManifestUrl, kRustKernelFileName), DllNew, OnProgress);
    if not SameText(FileSha256(ExeNew), Manifest.ExeSha256) then
      ErrorText := Format(kCorruptFormat, [kExeFileName])
    else if not SameText(FileSha256(DllNew), Manifest.DllSha256) then
      ErrorText := Format(kCorruptFormat, [kRustKernelFileName])
    else if not TryReadFileVersion(ExeNew, Downloaded) or (CompareVersions(Downloaded, Manifest.Version) <> 0) then
      ErrorText := kVersionMismatchText   // anti-boucle : le manifeste annonce autre chose que ce qu'il publie
    else
      Result := True;
  except
    on E: Exception do
      ErrorText := E.Message;
  end;
  if not Result then
    DeleteNewFiles(Folder);
end;

{------------------------------------------------------------------------------}

constructor TUpdateCheckThread.Create(const ManifestUrl: string; const Installed: TFileVersion;
  OnDone: TNotifyEvent);
begin
  inherited Create(True);
  FManifestUrl := ManifestUrl;
  FInstalled := Installed;
  FCheckResult := ucFailed;
  OnTerminate := OnDone;
  Start;
end;

{------------------------------------------------------------------------------}

procedure TUpdateCheckThread.Execute;
var
  Downloader: TWinInetDownloader;
begin
  try
    Downloader := TWinInetDownloader.Create;
    try
      FCheckResult := CheckForUpdate(Downloader, FManifestUrl, FInstalled, FManifest, FErrorText);
    finally
      Downloader.Free;
    end;
  except
    on E: Exception do
    begin
      FCheckResult := ucFailed;
      FErrorText := E.Message;
    end;
  end;
end;

{------------------------------------------------------------------------------}

constructor TUpdateDownloadThread.Create(const ManifestUrl, Folder: string; const Manifest: TUpdateManifest;
  OnProgress: TDownloadProgress; OnDone: TNotifyEvent);
begin
  inherited Create(True);
  FManifestUrl := ManifestUrl;
  FFolder := Folder;
  FManifest := Manifest;
  FOnProgress := OnProgress;
  FDownloader := TWinInetDownloader.Create;
  OnTerminate := OnDone;
  Start;
end;

{------------------------------------------------------------------------------}

destructor TUpdateDownloadThread.Destroy;
begin
  FDownloader.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TUpdateDownloadThread.Cancel;
begin
  FDownloader.Cancel;
end;

{------------------------------------------------------------------------------}

procedure TUpdateDownloadThread.HandleProgress(Received, Total: Int64);
begin
  FReceived := Received;
  FTotal := Total;
  Synchronize(DeliverProgress);
end;

{------------------------------------------------------------------------------}

procedure TUpdateDownloadThread.DeliverProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FReceived, FTotal);
end;

{------------------------------------------------------------------------------}

procedure TUpdateDownloadThread.Execute;
var
  Relay: TDownloadProgress;
begin
  Relay := nil;
  if Assigned(FOnProgress) then
    Relay := HandleProgress;
  try
    FIsSuccess := DownloadUpdate(FDownloader, FManifestUrl, FFolder, FManifest, Relay, FErrorText);
  except
    on E: Exception do
    begin
      FIsSuccess := False;
      FErrorText := E.Message;
    end;
  end;
end;

end.
