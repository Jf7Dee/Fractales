unit TestFractalUpdate;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Update, Fractal.Download, Fractal.RustKernel,
  TestUtils;

type
  TTestUpdate = class(TTestCase)
  private
    function V(A, B, C, D: Word): TFileVersion;
    function ManifestText(const Mandatory, ExeHash, Eol: string): string;
    procedure WriteText(const FileName, Text: string);
    procedure WriteBytes(const FileName: string; const Bytes: AnsiString);
    function FreshFolder(const Name: string): string;
    function ReadAll(const FileName: string): string;
    procedure RemoveFolder(const Folder: string);
    procedure Stage(const Folder: string; WithDll, WithNew: Boolean);
    function ExeSource: string;
    function NewManifest(const Version, ExeHash, DllHash: string): string;
    procedure PrepareDownload(const Name: string; out Folder, ExeHash, DllHash: string);
    function RunDownload(Fake: TObject; const Folder, Version, ExeHash, DllHash: string; out Err: string): Boolean;
  published
    procedure TestMissingConfigIsNone;
    procedure TestConfigModes;
    procedure TestParseVersion;
    procedure TestCompareVersions;
    procedure TestVersionToString;
    procedure TestReadFileVersion;
    procedure TestParseManifest;
    procedure TestManifestWithBomAndLf;
    procedure TestInvalidManifests;
    procedure TestScriptManifestFormat;
    procedure TestMandatoryFlag;
    procedure TestSiblingUrl;
    procedure TestDecideUpdate;
    procedure TestSha256;
    procedure TestInstallSwapsFiles;
    procedure TestInstallWithoutExistingDll;
    procedure TestInstallReplacesStaleOldFiles;
    procedure TestInstallRollsBackOnFailure;
    procedure TestInstallWaitsForTransientLock;
    procedure TestInstallWithoutNewFiles;
    procedure TestCheckFindsNewerVersion;
    procedure TestCheckSameVersionIsNothing;
    procedure TestCheckNetworkFailure;
    procedure TestCheckInvalidManifest;
    procedure TestDownloadUpdateSucceeds;
    procedure TestDownloadRejectsBadHash;
    procedure TestDownloadRejectsVersionMismatch;
    procedure TestDownloadFailureLeavesNoNewFiles;
    procedure TestDownloadCancelled;
  end;

implementation

const
  kExeHashUpper = 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD';
  kExeHashLower = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  kDllHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  kNotes = 'Effets de couleur et séance conservée';
  kFakeManifestUrl = 'http://fake/manifeste.ini';
  kFakeExeUrl = 'http://fake/Fractales.exe';
  kFakeDllUrl = 'http://fake/fractal_kernel.dll';
  kTransientLockMs = 300;              // plus court que les essais de renommage (5 essais, 200 ms entre deux)

type
  // Téléchargeur sans réseau : adresse -> fichier local ; une adresse inconnue répond « HTTP 404 »
  TFakeDownloader = class(TDownloader)
  private
    FMap: TStringList;
    FCalls: Integer;
  public
    FailAtFile: Integer;               // numéro (à partir de 1) du DownloadToFile qui échoue ; 0 = aucun
    constructor Create;
    destructor Destroy; override;
    procedure Add(const Url, LocalFile: string);
    function DownloadText(const Url: string): string; override;
    procedure DownloadToFile(const Url, FileName: string; OnProgress: TDownloadProgress); override;
  end;

  // Verrou passager (antivirus, indexation) : libère le fichier ouvert après un court délai
  TDelayedRelease = class(TThread)
  private
    FLocked: TFileStream;
  protected
    procedure Execute; override;
  public
    constructor Create(Locked: TFileStream);
    destructor Destroy; override;
  end;

{------------------------------------------------------------------------------}

constructor TFakeDownloader.Create;
begin
  inherited Create;
  FMap := TStringList.Create;
end;

{------------------------------------------------------------------------------}

destructor TFakeDownloader.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

{------------------------------------------------------------------------------}

procedure TFakeDownloader.Add(const Url, LocalFile: string);
begin
  FMap.Values[Url] := LocalFile;
end;

{------------------------------------------------------------------------------}

function TFakeDownloader.DownloadText(const Url: string): string;
var
  L: TStringList;
begin
  if FMap.Values[Url] = '' then
    raise EDownloadError.Create('HTTP 404');
  L := TStringList.Create;
  try
    L.LoadFromFile(FMap.Values[Url], TEncoding.UTF8);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TFakeDownloader.DownloadToFile(const Url, FileName: string; OnProgress: TDownloadProgress);
begin
  if IsCancelled then
    raise EDownloadCancelled.Create('Téléchargement annulé.');
  Inc(FCalls);
  if FCalls = FailAtFile then
    raise EDownloadError.Create('connexion interrompue');
  if FMap.Values[Url] = '' then
    raise EDownloadError.Create('HTTP 404');
  if not CopyFile(PChar(FMap.Values[Url]), PChar(FileName), False) then
    raise EDownloadError.Create(SysErrorMessage(GetLastError));
  if Assigned(OnProgress) then
    OnProgress(1, 1);
end;

{------------------------------------------------------------------------------}

constructor TDelayedRelease.Create(Locked: TFileStream);
begin
  FLocked := Locked;
  inherited Create(False);
end;

{------------------------------------------------------------------------------}

destructor TDelayedRelease.Destroy;
begin
  inherited Destroy;                   // attend la fin de Execute
  FreeAndNil(FLocked);                 // si le fil n'a jamais tourné
end;

{------------------------------------------------------------------------------}

procedure TDelayedRelease.Execute;
begin
  Sleep(kTransientLockMs);
  FreeAndNil(FLocked);
end;

{------------------------------------------------------------------------------}

function TTestUpdate.V(A, B, C, D: Word): TFileVersion;
begin
  Result[0] := A;
  Result[1] := B;
  Result[2] := C;
  Result[3] := D;
end;

{------------------------------------------------------------------------------}

function TTestUpdate.ManifestText(const Mandatory, ExeHash, Eol: string): string;
begin
  Result := '[Version]' + Eol + 'Numero=0.5.0.0' + Eol + 'Obligatoire=' + Mandatory + Eol + 'Notes=' + kNotes + Eol +
    Eol + '[Fichiers]' + Eol + 'Fractales.exe=' + ExeHash + Eol + 'fractal_kernel.dll=' + kDllHash + Eol;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.WriteText(const FileName, Text: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(FileName, TEncoding.UTF8);
  finally
    L.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.WriteBytes(const FileName: string; const Bytes: AnsiString);
var
  S: TFileStream;
begin
  S := TFileStream.Create(FileName, fmCreate);
  try
    if Length(Bytes) > 0 then
      S.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    S.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.RemoveFolder(const Folder: string);
var
  SR: TSearchRec;
begin
  if FindFirst(Folder + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        DeleteFile(Folder + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(Folder);
end;

{------------------------------------------------------------------------------}

function TTestUpdate.FreshFolder(const Name: string): string;
begin
  Result := TestTempFolder + Name + '\';
  RemoveFolder(Result);
  ForceDirectories(Result);
end;

{------------------------------------------------------------------------------}

function TTestUpdate.ReadAll(const FileName: string): string;
var
  S: TFileStream;
  A: AnsiString;
begin
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(A, S.Size);
    if S.Size > 0 then
      S.ReadBuffer(A[1], S.Size);
    Result := string(A);
  finally
    S.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Contenus distincts : exe/dll d'origine, puis exe.new/dll.new
procedure TTestUpdate.Stage(const Folder: string; WithDll, WithNew: Boolean);
begin
  WriteBytes(Folder + kExeFileName, 'exe-ancien');
  if WithDll then
    WriteBytes(Folder + kRustKernelFileName, 'dll-ancienne');
  if WithNew then
  begin
    WriteBytes(Folder + kExeFileName + kNewSuffix, 'exe-nouveau');
    WriteBytes(Folder + kRustKernelFileName + kNewSuffix, 'dll-nouvelle');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestMissingConfigIsNone;
var
  C: TUpdateConfig;
begin
  C := LoadUpdateConfig(TestTempFolder + 'MiseAJour-absent.ini');
  CheckTrue(C.Mode = umNone);
  CheckEquals(kDefaultManifestUrl, C.ManifestUrl);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestConfigModes;
var
  FileName: string;
  C: TUpdateConfig;
begin
  FileName := TestTempFolder + 'MiseAJour-modes.ini';
  WriteText(FileName, '[MiseAJour]'#13#10'Mode=proposer');
  C := LoadUpdateConfig(FileName);
  CheckTrue(C.Mode = umPropose);
  CheckEquals(kDefaultManifestUrl, C.ManifestUrl);
  WriteText(FileName, '[MiseAJour]'#13#10'Mode=Silencieux'#13#10'Manifeste=http://localhost:8000/manifeste.ini');
  C := LoadUpdateConfig(FileName);
  CheckTrue(C.Mode = umSilent);
  CheckEquals('http://localhost:8000/manifeste.ini', C.ManifestUrl);
  WriteText(FileName, '[MiseAJour]'#13#10'Mode=Toujours');
  CheckTrue(LoadUpdateConfig(FileName).Mode = umNone);
  WriteText(FileName, '[MiseAJour]'#13#10'Mode=Aucune'#13#10'Manifeste=');
  C := LoadUpdateConfig(FileName);
  CheckTrue(C.Mode = umNone);
  CheckEquals(kDefaultManifestUrl, C.ManifestUrl);
  DeleteFile(FileName);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestParseVersion;
var
  R: TFileVersion;
begin
  CheckTrue(TryParseVersion('0.5', R));
  CheckEquals(0, CompareVersions(R, V(0, 5, 0, 0)));
  CheckTrue(TryParseVersion('1.0.10.0', R));
  CheckEquals(0, CompareVersions(R, V(1, 0, 10, 0)));
  CheckTrue(TryParseVersion('65535', R));
  CheckFalse(TryParseVersion('', R));
  CheckFalse(TryParseVersion('1..2', R));
  CheckFalse(TryParseVersion('1.2.3.4.5', R));
  CheckFalse(TryParseVersion('1.a', R));
  CheckFalse(TryParseVersion('70000', R));
  CheckFalse(TryParseVersion('1.-2', R));
  CheckFalse(TryParseVersion('1.2.', R));
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestCompareVersions;
begin
  CheckTrue(CompareVersions(V(1, 0, 10, 0), V(1, 0, 9, 0)) > 0);
  CheckEquals(0, CompareVersions(V(0, 5, 0, 0), V(0, 5, 0, 0)));
  CheckTrue(CompareVersions(V(0, 5, 0, 0), V(1, 0, 0, 0)) < 0);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestVersionToString;
begin
  CheckEquals('0.5.0.0', VersionToString(V(0, 5, 0, 0)));
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestReadFileVersion;
var
  ExeName, IniName: string;
  R: TFileVersion;
begin
  IniName := TestTempFolder + 'sans-version.ini';
  WriteText(IniName, '[A]'#13#10'B=1');
  CheckFalse(TryReadFileVersion(IniName, R));
  DeleteFile(IniName);
  CheckFalse(TryReadFileVersion(TestTempFolder + 'absent.exe', R));
  ExeName := ExtractFilePath(ParamStr(0)) + kExeFileName;
  if not FileExists(ExeName) then
  begin
    Status('Fractales.exe absent à côté des tests (./build.sh app) : version de l''exe non vérifiée');
    Exit;
  end;
  CheckTrue(TryReadFileVersion(ExeName, R));
  // le numéro change à chaque version : on vérifie seulement qu'il est lu
  CheckTrue(CompareVersions(R, V(0, 0, 0, 0)) <> 0, 'version de l''exe à 0.0.0.0');
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestParseManifest;
var
  M: TUpdateManifest;
begin
  CheckTrue(TryParseManifest(ManifestText('0', kExeHashUpper, #13#10), M));
  CheckEquals(0, CompareVersions(M.Version, V(0, 5, 0, 0)));
  CheckFalse(M.IsMandatory);
  CheckEquals(kNotes, M.Notes);
  CheckEquals(kExeHashLower, M.ExeSha256);
  CheckEquals(kDllHash, M.DllSha256);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestManifestWithBomAndLf;
var
  M: TUpdateManifest;
begin
  CheckTrue(TryParseManifest(#$FEFF + ManifestText('0', kExeHashLower, #10), M));
  CheckEquals(0, CompareVersions(M.Version, V(0, 5, 0, 0)));
  CheckEquals(kNotes, M.Notes);
  CheckEquals(kDllHash, M.DllSha256);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestInvalidManifests;
var
  M: TUpdateManifest;
  Good: string;
begin
  Good := ManifestText('0', kExeHashLower, #13#10);
  CheckTrue(TryParseManifest(Good, M));
  CheckFalse(TryParseManifest(StringReplace(Good, 'Numero=0.5.0.0', 'Autre=1', []), M), 'numéro absent');
  CheckFalse(TryParseManifest(StringReplace(Good, 'Numero=0.5.0.0', 'Numero=0.x', []), M), 'numéro invalide');
  CheckFalse(TryParseManifest(ManifestText('0', Copy(kExeHashLower, 1, 63), #13#10), M), '63 caractères');
  CheckFalse(TryParseManifest(ManifestText('0', Copy(kExeHashLower, 1, 63) + 'g', #13#10), M), 'empreinte avec g');
  CheckFalse(TryParseManifest(Copy(Good, 1, Pos('[Fichiers]', Good) - 1), M), 'section Fichiers absente');
  CheckFalse(TryParseManifest('', M), 'texte vide');
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestScriptManifestFormat;
// Texte tel que l'écrit tools/preparer-version.sh : CRLF, ligne vide entre les sections, notes accentuées
const
  kScriptManifest = '[Version]'#13#10 +
    'Numero=0.5.0.0'#13#10 +
    'Obligatoire=1'#13#10 +
    'Notes=Séance conservée'#13#10 +
    #13#10 +
    '[Fichiers]'#13#10 +
    'Fractales.exe=d2c07da0061e39c403c1ec41a1a8a4ce2a305d55d18d169bb11450102892f873'#13#10 +
    'fractal_kernel.dll=ed95d1fd8a1e666ac5004a2e4b23e53fbe799b48e890473d052b6d7d5c55163c'#13#10;
var
  M: TUpdateManifest;
begin
  CheckTrue(TryParseManifest(kScriptManifest, M));
  CheckEquals(0, CompareVersions(M.Version, V(0, 5, 0, 0)));
  CheckTrue(M.IsMandatory);
  CheckEquals('Séance conservée', M.Notes);
  CheckEquals('d2c07da0061e39c403c1ec41a1a8a4ce2a305d55d18d169bb11450102892f873', M.ExeSha256);
  CheckEquals('ed95d1fd8a1e666ac5004a2e4b23e53fbe799b48e890473d052b6d7d5c55163c', M.DllSha256);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestMandatoryFlag;
var
  M: TUpdateManifest;
begin
  CheckTrue(TryParseManifest(ManifestText('1', kExeHashLower, #13#10), M));
  CheckTrue(M.IsMandatory);
  CheckTrue(TryParseManifest(ManifestText('oui', kExeHashLower, #13#10), M));
  CheckFalse(M.IsMandatory);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestSiblingUrl;
begin
  CheckEquals('https://github.com/Jf7Dee/Fractales/releases/latest/download/Fractales.exe',
    SiblingUrl(kDefaultManifestUrl, 'Fractales.exe'));
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestDecideUpdate;
begin
  CheckTrue(DecideUpdate(umNone, V(0, 5, 0, 0), V(0, 6, 0, 0)) = udNothing);
  CheckTrue(DecideUpdate(umPropose, V(0, 5, 0, 0), V(0, 5, 0, 0)) = udNothing);
  CheckTrue(DecideUpdate(umPropose, V(0, 5, 0, 0), V(0, 4, 0, 0)) = udNothing);
  CheckTrue(DecideUpdate(umPropose, V(0, 5, 0, 0), V(0, 6, 0, 0)) = udPropose);
  CheckTrue(DecideUpdate(umSilent, V(0, 5, 0, 0), V(0, 6, 0, 0)) = udNotify);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestSha256;
var
  FileName: string;
begin
  FileName := TestTempFolder + 'sha256.bin';
  WriteBytes(FileName, 'abc');
  CheckEquals(kExeHashLower, FileSha256(FileName));
  WriteBytes(FileName, '');
  CheckEquals(kDllHash, FileSha256(FileName));
  DeleteFile(FileName);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestInstallSwapsFiles;
var
  F, Err: string;
begin
  F := FreshFolder('install-swap');
  try
    Stage(F, True, True);
    CheckTrue(TryInstallFiles(F, Err), Err);
    CheckEquals('exe-nouveau', ReadAll(F + kExeFileName));
    CheckEquals('dll-nouvelle', ReadAll(F + kRustKernelFileName));
    CheckEquals('exe-ancien', ReadAll(F + kExeFileName + kOldSuffix));
    CheckEquals('dll-ancienne', ReadAll(F + kRustKernelFileName + kOldSuffix));
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix));
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix));
  finally
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestInstallWithoutExistingDll;
var
  F, Err: string;
begin
  F := FreshFolder('install-nodll');
  try
    Stage(F, False, True);
    CheckTrue(TryInstallFiles(F, Err), Err);
    CheckEquals('exe-nouveau', ReadAll(F + kExeFileName));
    CheckEquals('dll-nouvelle', ReadAll(F + kRustKernelFileName));
    CheckEquals('exe-ancien', ReadAll(F + kExeFileName + kOldSuffix));
    CheckFalse(FileExists(F + kRustKernelFileName + kOldSuffix));
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix));
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix));
  finally
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestInstallReplacesStaleOldFiles;
var
  F, Err: string;
begin
  F := FreshFolder('install-stale');
  try
    Stage(F, True, True);
    WriteBytes(F + kExeFileName + kOldSuffix, 'exe-perime');
    WriteBytes(F + kRustKernelFileName + kOldSuffix, 'dll-perimee');
    CheckTrue(TryInstallFiles(F, Err), Err);
    CheckEquals('exe-ancien', ReadAll(F + kExeFileName + kOldSuffix));
    CheckEquals('dll-ancienne', ReadAll(F + kRustKernelFileName + kOldSuffix));
    CheckEquals('exe-nouveau', ReadAll(F + kExeFileName));
    CheckEquals('dll-nouvelle', ReadAll(F + kRustKernelFileName));
  finally
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestInstallRollsBackOnFailure;
var
  F, Err: string;
  Locked: TFileStream;
  Ok: Boolean;
begin
  F := FreshFolder('install-rollback');
  try
    Stage(F, True, True);
    Locked := TFileStream.Create(F + kRustKernelFileName, fmOpenRead or fmShareExclusive);
    try
      Ok := TryInstallFiles(F, Err);
    finally
      Locked.Free;
    end;
    CheckFalse(Ok);
    CheckTrue(Err <> '', 'message d''erreur');
    CheckEquals('exe-ancien', ReadAll(F + kExeFileName));
    CheckEquals('dll-ancienne', ReadAll(F + kRustKernelFileName));
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix));
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix));
    CheckFalse(FileExists(F + kExeFileName + kOldSuffix));
    CheckFalse(FileExists(F + kRustKernelFileName + kOldSuffix));
  finally
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

// Un retour arrière qui échoue ne se provoque pas de façon fiable (il défait un renommage qui vient de réussir) :
// on vérifie à la place que les renommages réessaient tant qu'un verrou passager tient le fichier
procedure TTestUpdate.TestInstallWaitsForTransientLock;
var
  F, Err: string;
  Release: TDelayedRelease;
  Ok: Boolean;
begin
  F := FreshFolder('install-transient');
  try
    Stage(F, True, True);
    Release := TDelayedRelease.Create(TFileStream.Create(F + kRustKernelFileName, fmOpenRead or fmShareExclusive));
    try
      Ok := TryInstallFiles(F, Err);
    finally
      Release.Free;
    end;
    CheckTrue(Ok, Err);
    CheckEquals('exe-nouveau', ReadAll(F + kExeFileName));
    CheckEquals('dll-nouvelle', ReadAll(F + kRustKernelFileName));
    CheckEquals('dll-ancienne', ReadAll(F + kRustKernelFileName + kOldSuffix));
  finally
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestInstallWithoutNewFiles;
var
  F, Err: string;
begin
  F := FreshFolder('install-nonew');
  try
    Stage(F, True, False);
    WriteBytes(F + kExeFileName + kNewSuffix, 'exe-nouveau');
    CheckFalse(TryInstallFiles(F, Err));
    CheckEquals('exe-ancien', ReadAll(F + kExeFileName));
    CheckEquals('dll-ancienne', ReadAll(F + kRustKernelFileName));
    CheckEquals('exe-nouveau', ReadAll(F + kExeFileName + kNewSuffix));
    CheckFalse(FileExists(F + kExeFileName + kOldSuffix));
    CheckFalse(FileExists(F + kRustKernelFileName + kOldSuffix));
  finally
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

function TTestUpdate.ExeSource: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + kExeFileName;   // bin\Fractales.exe, produit par « build.sh app »
end;

{------------------------------------------------------------------------------}

function TTestUpdate.NewManifest(const Version, ExeHash, DllHash: string): string;
begin
  Result := '[Version]'#13#10'Numero=' + Version + #13#10'Obligatoire=0'#13#10#13#10'[Fichiers]'#13#10 +
    'Fractales.exe=' + ExeHash + #13#10'fractal_kernel.dll=' + DllHash + #13#10;
end;

{------------------------------------------------------------------------------}

// Dossier de travail + faux exe (copie de bin\Fractales.exe) et fausse DLL, avec leurs empreintes
procedure TTestUpdate.PrepareDownload(const Name: string; out Folder, ExeHash, DllHash: string);
begin
  Folder := FreshFolder(Name);
  CopyFile(PChar(ExeSource), PChar(Folder + 'src-exe.bin'), False);
  WriteBytes(Folder + 'src-dll.bin', 'fausse-dll');
  ExeHash := FileSha256(Folder + 'src-exe.bin');
  DllHash := FileSha256(Folder + 'src-dll.bin');
end;

{------------------------------------------------------------------------------}

function TTestUpdate.RunDownload(Fake: TObject; const Folder, Version, ExeHash, DllHash: string;
  out Err: string): Boolean;
var
  D: TFakeDownloader;
  M: TUpdateManifest;
begin
  D := TFakeDownloader(Fake);
  D.Add(kFakeExeUrl, Folder + 'src-exe.bin');
  D.Add(kFakeDllUrl, Folder + 'src-dll.bin');
  CheckTrue(TryParseManifest(NewManifest(Version, ExeHash, DllHash), M), 'manifeste du test');
  Result := DownloadUpdate(D, kFakeManifestUrl, Folder, M, nil, Err);
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestCheckFindsNewerVersion;
var
  D: TFakeDownloader;
  M: TUpdateManifest;
  Err: string;
begin
  WriteText(TestTempFolder + 'check-new.ini', NewManifest('0.6.0.0', kExeHashLower, kDllHash));
  D := TFakeDownloader.Create;
  try
    D.Add(kFakeManifestUrl, TestTempFolder + 'check-new.ini');
    CheckTrue(CheckForUpdate(D, kFakeManifestUrl, V(0, 5, 0, 0), M, Err) = ucAvailable, 'ucAvailable');
    CheckEquals('0.6.0.0', VersionToString(M.Version));
    CheckEquals(kExeHashLower, M.ExeSha256);
  finally
    D.Free;
    DeleteFile(TestTempFolder + 'check-new.ini');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestCheckSameVersionIsNothing;
var
  D: TFakeDownloader;
  M: TUpdateManifest;
  Err: string;
begin
  WriteText(TestTempFolder + 'check-same.ini', NewManifest('0.5.0.0', kExeHashLower, kDllHash));
  D := TFakeDownloader.Create;
  try
    D.Add(kFakeManifestUrl, TestTempFolder + 'check-same.ini');
    CheckTrue(CheckForUpdate(D, kFakeManifestUrl, V(0, 5, 0, 0), M, Err) = ucNothing, 'ucNothing');
  finally
    D.Free;
    DeleteFile(TestTempFolder + 'check-same.ini');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestCheckNetworkFailure;
var
  D: TFakeDownloader;
  M: TUpdateManifest;
  Err: string;
begin
  D := TFakeDownloader.Create;
  try
    CheckTrue(CheckForUpdate(D, kFakeManifestUrl, V(0, 5, 0, 0), M, Err) = ucFailed, 'ucFailed');
    CheckTrue(Pos('404', Err) > 0, 'ErrorText : ' + Err);
  finally
    D.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestCheckInvalidManifest;
var
  D: TFakeDownloader;
  M: TUpdateManifest;
  Err: string;
begin
  WriteText(TestTempFolder + 'check-bad.ini', 'ceci n''est pas un manifeste');
  D := TFakeDownloader.Create;
  try
    D.Add(kFakeManifestUrl, TestTempFolder + 'check-bad.ini');
    CheckTrue(CheckForUpdate(D, kFakeManifestUrl, V(0, 5, 0, 0), M, Err) = ucInvalid, 'ucInvalid');
  finally
    D.Free;
    DeleteFile(TestTempFolder + 'check-bad.ini');
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestDownloadUpdateSucceeds;
var
  D: TFakeDownloader;
  F, ExeHash, DllHash, Err: string;
begin
  if not FileExists(ExeSource) then
  begin
    Status('bin\Fractales.exe absent : test sauté');
    Exit;
  end;
  PrepareDownload('dl-ok', F, ExeHash, DllHash);
  D := TFakeDownloader.Create;
  try
    CheckTrue(RunDownload(D, F, '0.5.0.0', ExeHash, DllHash, Err), Err);
    CheckTrue(FileExists(F + kExeFileName + kNewSuffix), 'exe.new');
    CheckTrue(FileExists(F + kRustKernelFileName + kNewSuffix), 'dll.new');
  finally
    D.Free;
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestDownloadRejectsBadHash;
var
  D: TFakeDownloader;
  F, ExeHash, DllHash, Err: string;
begin
  if not FileExists(ExeSource) then
  begin
    Status('bin\Fractales.exe absent : test sauté');
    Exit;
  end;
  PrepareDownload('dl-badhash', F, ExeHash, DllHash);
  D := TFakeDownloader.Create;
  try
    CheckFalse(RunDownload(D, F, '0.5.0.0', ExeHash, kDllHash, Err), 'doit échouer');
    CheckEquals(Format('Le fichier %s est corrompu (empreinte différente).', [kRustKernelFileName]), Err);
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix), 'exe.new');
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix), 'dll.new');
  finally
    D.Free;
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestDownloadRejectsVersionMismatch;
var
  D: TFakeDownloader;
  F, ExeHash, DllHash, Err: string;
begin
  if not FileExists(ExeSource) then
  begin
    Status('bin\Fractales.exe absent : test sauté');
    Exit;
  end;
  PrepareDownload('dl-version', F, ExeHash, DllHash);
  D := TFakeDownloader.Create;
  try
    CheckFalse(RunDownload(D, F, '0.6.0.0', ExeHash, DllHash, Err), 'doit échouer');
    CheckEquals('La version téléchargée ne correspond pas au manifeste.', Err);
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix), 'exe.new');
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix), 'dll.new');
  finally
    D.Free;
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestDownloadFailureLeavesNoNewFiles;
var
  D: TFakeDownloader;
  F, ExeHash, DllHash, Err: string;
begin
  if not FileExists(ExeSource) then
  begin
    Status('bin\Fractales.exe absent : test sauté');
    Exit;
  end;
  PrepareDownload('dl-fail', F, ExeHash, DllHash);
  D := TFakeDownloader.Create;
  try
    D.FailAtFile := 2;
    CheckFalse(RunDownload(D, F, '0.5.0.0', ExeHash, DllHash, Err), 'doit échouer');
    CheckTrue(Err <> '', 'ErrorText');
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix), 'exe.new');
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix), 'dll.new');
  finally
    D.Free;
    RemoveFolder(F);
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestUpdate.TestDownloadCancelled;
var
  D: TFakeDownloader;
  F, ExeHash, DllHash, Err: string;
begin
  if not FileExists(ExeSource) then
  begin
    Status('bin\Fractales.exe absent : test sauté');
    Exit;
  end;
  PrepareDownload('dl-cancel', F, ExeHash, DllHash);
  D := TFakeDownloader.Create;
  try
    D.Cancel;
    CheckFalse(RunDownload(D, F, '0.5.0.0', ExeHash, DllHash, Err), 'doit échouer');
    CheckFalse(FileExists(F + kExeFileName + kNewSuffix), 'exe.new');
    CheckFalse(FileExists(F + kRustKernelFileName + kNewSuffix), 'dll.new');
  finally
    D.Free;
    RemoveFolder(F);
  end;
end;

initialization
  RegisterTest(TTestUpdate.Suite);

end.
