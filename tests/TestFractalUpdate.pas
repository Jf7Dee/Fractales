unit TestFractalUpdate;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Update, Fractal.RustKernel, TestUtils;

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
    procedure TestMandatoryFlag;
    procedure TestSiblingUrl;
    procedure TestDecideUpdate;
    procedure TestSha256;
    procedure TestInstallSwapsFiles;
    procedure TestInstallWithoutExistingDll;
    procedure TestInstallReplacesStaleOldFiles;
    procedure TestInstallRollsBackOnFailure;
    procedure TestInstallWithoutNewFiles;
  end;

implementation

const
  kExeHashUpper = 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD';
  kExeHashLower = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  kDllHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  kNotes = 'Effets de couleur et séance conservée';

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
  CheckEquals(0, CompareVersions(R, V(0, 5, 0, 0)));
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

initialization
  RegisterTest(TTestUpdate.Suite);

end.
