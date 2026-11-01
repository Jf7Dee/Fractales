unit AboutFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls,
  pngimage,  // TPngImage : le bandeau (vallée des hippocampes) est un PNG rangé dans le .dfm
  Fractal.Update;

type
  TAboutForm = class(TForm)
    imgBanner: TImage;
    lblTitle: TLabel;
    lblVersion: TLabel;
    lblStatus: TLabel;
    btnCheck: TButton;
    btnClose: TButton;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDestroy(Sender: TObject);
    procedure btnCheckClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
  private
    FManifestUrl: string;
    FInstalled: TFileVersion;
    FIsChecking: Boolean;
    FIsUpdateAvailable: Boolean;
    FManifest: TUpdateManifest;
    FThread: TUpdateCheckThread;
    procedure CheckDone(Sender: TObject);
  public
    // Remplit la fenêtre ; à appeler avant ShowModal. Sans version lisible, la recherche est impossible
    procedure Prepare(HasVersion: Boolean; const Installed: TFileVersion; const ManifestUrl: string);
    // Vrai si la fenêtre s'est fermée sur une version plus récente : l'appelant propose alors de l'installer
    property IsUpdateAvailable: Boolean read FIsUpdateAvailable;
    property Manifest: TUpdateManifest read FManifest;
  end;

function CheckResultText(CheckResult: TUpdateCheckResult; const ErrorText: string): string;

implementation

{$R *.dfm}

const
  kVersionFormat = 'Version %s';
  kVersionUnknown = 'Version inconnue';
  kMsgChecking = 'Recherche en cours...';
  kMsgUpToDate = 'Version déjà à jour.';

{------------------------------------------------------------------------------}

function CheckResultText(CheckResult: TUpdateCheckResult; const ErrorText: string): string;
begin
  case CheckResult of
    ucNothing:
      Result := kMsgUpToDate;
    ucAvailable:
      Result := '';                    // la fenêtre se ferme : la fenêtre de mise à jour prend le relais
    ucInvalid:
      Result := kUpdateInvalidText;
  else
    Result := Format(kUpdateFailedFormat, [ErrorText]);
  end;
end;

{------------------------------------------------------------------------------}

procedure TAboutForm.Prepare(HasVersion: Boolean; const Installed: TFileVersion; const ManifestUrl: string);
begin
  FInstalled := Installed;
  FManifestUrl := ManifestUrl;
  FIsUpdateAvailable := False;
  if HasVersion then
    lblVersion.Caption := Format(kVersionFormat, [VersionToString(Installed)])
  else
    lblVersion.Caption := kVersionUnknown;
  lblStatus.Caption := '';
  btnCheck.Enabled := HasVersion;
end;

{------------------------------------------------------------------------------}

procedure TAboutForm.btnCheckClick(Sender: TObject);
begin
  // Le fil précédent (nouvel essai) ne se libère pas dans son propre OnDone : on le fait ici
  FreeAndNil(FThread);
  btnCheck.Enabled := False;
  btnClose.Enabled := False;
  lblStatus.Caption := kMsgChecking;
  Screen.Cursor := crAppStart;
  FIsChecking := True;
  FThread := TUpdateCheckThread.Create(FManifestUrl, FInstalled, CheckDone);
end;

{------------------------------------------------------------------------------}

procedure TAboutForm.btnCloseClick(Sender: TObject);
begin
  Close;
end;

{------------------------------------------------------------------------------}

procedure TAboutForm.CheckDone(Sender: TObject);
begin
  // Appelé dans le fil principal, dans le OnTerminate du fil : ne pas libérer le fil ici. Une exception ne doit
  // pas en sortir (elle remonterait dans le fil et tuerait le programme) : elle s'affiche comme un échec
  FIsChecking := False;
  Screen.Cursor := crDefault;
  btnClose.Enabled := True;
  try
    if FThread.CheckResult = ucAvailable then
    begin
      FManifest := FThread.Manifest;
      FIsUpdateAvailable := True;
      Close;
      Exit;
    end;
    lblStatus.Caption := CheckResultText(FThread.CheckResult, FThread.ErrorText);
  except
    on E: Exception do
      lblStatus.Caption := CheckResultText(ucFailed, E.Message);
  end;
  btnCheck.Enabled := True;
end;

{------------------------------------------------------------------------------}

procedure TAboutForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FIsChecking;         // la recherche se termine d'elle-même (délais de 10 s)
end;

{------------------------------------------------------------------------------}

procedure TAboutForm.FormDestroy(Sender: TObject);
begin
  if FThread <> nil then
  begin
    // Libérer un fil actif attend sa fin en traitant les Synchronize : OnDone ne doit plus être appelé
    FThread.OnTerminate := nil;
    FreeAndNil(FThread);
  end;
  if FIsChecking then
    Screen.Cursor := crDefault;
end;

end.
