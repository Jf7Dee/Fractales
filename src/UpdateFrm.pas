unit UpdateFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  Fractal.Update;

type
  TUpdateOutcome = (uoLater, uoQuit, uoInstalled);

  TUpdateForm = class(TForm)
    lblMessage: TLabel;
    lblNotes: TLabel;
    pbProgress: TProgressBar;
    btnUpdate: TButton;
    btnLater: TButton;
    btnCancel: TButton;
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDestroy(Sender: TObject);
    procedure btnUpdateClick(Sender: TObject);
    procedure btnLaterClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
  private
    FManifest: TUpdateManifest;
    FManifestUrl: string;
    FFolder: string;
    FIsMandatory: Boolean;
    FIsDownloading: Boolean;
    FIsCancelled: Boolean;
    FOutcome: TUpdateOutcome;
    FThread: TUpdateDownloadThread;
    procedure ShowFailure(const Reason: string);
    procedure DownloadProgress(Received, Total: Int64);
    procedure DownloadDone(Sender: TObject);
  public
    // Remplit la fenêtre ; à appeler avant ShowModal
    procedure Prepare(const Manifest: TUpdateManifest; const Installed: TFileVersion; const ManifestUrl,
      Folder: string);
    property Outcome: TUpdateOutcome read FOutcome;
  end;

implementation

{$R *.dfm}

const
  kMsgAvailable = 'La version %s est disponible (version installée : %s).';
  kMsgFailure = 'Le téléchargement a échoué : %s' + #13#10 + 'La version actuelle reste en place.';
  kCaptionLater = 'Plus tard';
  kCaptionQuit = 'Quitter';
  kCaptionClose = 'Fermer';
  kCaptionUpdate = 'Mettre à jour';
  kCaptionRetry = 'Réessayer';
  kProgressMax = 1000;
  kMessageHeight = 38;
  kMessageGap = 6;

{------------------------------------------------------------------------------}

procedure TUpdateForm.Prepare(const Manifest: TUpdateManifest; const Installed: TFileVersion; const ManifestUrl,
  Folder: string);
begin
  FManifest := Manifest;
  FManifestUrl := ManifestUrl;
  FFolder := Folder;
  FIsMandatory := Manifest.IsMandatory;
  FIsDownloading := False;
  FIsCancelled := False;
  lblMessage.Height := kMessageHeight;
  lblMessage.Caption := Format(kMsgAvailable, [VersionToString(Manifest.Version), VersionToString(Installed)]);
  lblMessage.Visible := True;
  lblNotes.Caption := Manifest.Notes;
  lblNotes.Visible := Manifest.Notes <> '';
  if FIsMandatory then
  begin
    btnLater.Caption := kCaptionQuit;
    FOutcome := uoQuit; // fermer la fenêtre autrement que par « Mettre à jour » revient à quitter
  end
  else
  begin
    btnLater.Caption := kCaptionLater;
    FOutcome := uoLater;
  end;
  btnUpdate.Caption := kCaptionUpdate;
  btnUpdate.Visible := True;
  btnLater.Visible := True;
  btnCancel.Visible := False;
  btnCancel.Enabled := True;
  pbProgress.Position := 0;
  pbProgress.Visible := False;
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.btnUpdateClick(Sender: TObject);
begin
  // Le fil précédent (échec, nouvel essai) ne se libère pas dans son propre OnDone : on le fait ici
  FreeAndNil(FThread);
  lblMessage.Visible := False;
  lblNotes.Visible := False;
  btnUpdate.Visible := False;
  btnLater.Visible := False;
  pbProgress.Position := 0;
  pbProgress.Visible := True;
  btnCancel.Enabled := True;
  btnCancel.Visible := True;
  FIsDownloading := True;
  FIsCancelled := False;
  FThread := TUpdateDownloadThread.Create(FManifestUrl, FFolder, FManifest, DownloadProgress, DownloadDone);
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.btnLaterClick(Sender: TObject);
begin
  if FIsMandatory then
    FOutcome := uoQuit
  else
    FOutcome := uoLater;
  Close;
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.btnCancelClick(Sender: TObject);
begin
  if FThread <> nil then
  begin
    FIsCancelled := True;
    btnCancel.Enabled := False;
    FThread.Cancel;
  end;
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.DownloadProgress(Received, Total: Int64);
begin
  if Total > 0 then
    pbProgress.Position := Integer((Received * kProgressMax) div Total);
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.DownloadDone(Sender: TObject);
var
  ErrorText: string;
begin
  // Appelé dans le fil principal, dans le OnTerminate du fil : ne pas libérer le fil ici
  FIsDownloading := False;
  if (not FThread.IsSuccess) and FIsCancelled and not FIsMandatory then
  begin
    // Annulation voulue : retour au programme, rien n'a changé
    FOutcome := uoLater;
    Close;
    Exit;
  end;
  if FThread.IsSuccess then
  begin
    if TryInstallFiles(FFolder, ErrorText) then
    begin
      FOutcome := uoInstalled;
      Close;
    end
    else
      ShowFailure(ErrorText);
  end
  else
    ShowFailure(FThread.ErrorText);
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.ShowFailure(const Reason: string);
begin
  pbProgress.Visible := False;
  btnCancel.Visible := False;
  lblNotes.Visible := False;
  lblMessage.Height := btnLater.Top - lblMessage.Top - kMessageGap; // les notes sont cachées : toute la place
  lblMessage.Caption := Format(kMsgFailure, [Reason]);
  lblMessage.Visible := True;
  if FIsMandatory then
  begin
    btnLater.Caption := kCaptionQuit;
    btnUpdate.Caption := kCaptionRetry;
    btnUpdate.Visible := True;
  end
  else
  begin
    btnLater.Caption := kCaptionClose;
    btnUpdate.Visible := False;
  end;
  btnLater.Visible := True;
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := not FIsDownloading;
end;

{------------------------------------------------------------------------------}

procedure TUpdateForm.FormDestroy(Sender: TObject);
begin
  if FThread <> nil then
  begin
    // Libérer un fil actif attend sa fin en traitant les Synchronize : OnDone ne doit plus être appelé
    FThread.OnTerminate := nil;
    FreeAndNil(FThread);
  end;
end;

end.
