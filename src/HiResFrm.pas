unit HiResFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls, ExtCtrls, ShlObj,
  {$IF CompilerVersion >= 23} UITypes,{$IFEND} 
  Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine, Fractal.HiRes, Fractal.Settings;

const
  kPresetCurrentView = 0;
  kPresetCustom = 4;
  kPresetWidths: array[1..3] of Integer = (1920, 3840, 7680);
  kPresetHeights: array[1..3] of Integer = (1080, 2160, 4320);
  kMinHiResSize = 16;
  kMaxHiResSize = 32768;
  kDefaultFileName = 'fractale.png';
  kPngExtension = '.png';

type
  THiResForm = class(TForm)
    lblPreset: TLabel;
    lblSize: TLabel;
    lblSupersample: TLabel;
    lblFile: TLabel;
    lblState: TLabel;
    cbPreset: TComboBox;
    edWidth: TEdit;
    edHeight: TEdit;
    cbSupersample: TComboBox;
    edFile: TEdit;
    btnBrowse: TButton;
    pbProgress: TProgressBar;
    btnStart: TButton;
    btnClose: TButton;
    tmrPoll: TTimer;
    dlgSave: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure cbPresetChange(Sender: TObject);
    procedure btnBrowseClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure tmrPollTimer(Sender: TObject);
  private
    FRenderer: THiResRenderer;
    FViewport: TViewport;
    FFormula: TFractalFormula;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FLocationText: RawByteString;
    FKernel: TEngineKernelType;
    FStartTick: Cardinal;
    FTargetFileName: string;
    FOnRequestSnapshot: TNotifyEvent;
    function ReadSettings(out Settings: THiResSettings): Boolean;
    procedure StopRenderer;
    procedure UpdateButtons;
  public
    procedure Prepare(const V: TViewport; Formula: TFractalFormula; Palette: TGradientPalette;
      const Mapping: TColorMapping; const LocationText: RawByteString; Kernel: TEngineKernelType);
    procedure SuggestFileName;
    procedure ApplySettings(const S: TAppSettings);
    procedure CaptureSettings(var S: TAppSettings);
    procedure StartRender;
    function IsRunning: Boolean;
    property OnRequestSnapshot: TNotifyEvent read FOnRequestSnapshot write FOnRequestSnapshot;
  end;

implementation

uses
  Fractal.Persistence;

{$R *.dfm}

{------------------------------------------------------------------------------}

function PicturesFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, CSIDL_MYPICTURES, 0, 0, Buffer) = S_OK then
    Result := IncludeTrailingPathDelimiter(Buffer)
  else
    Result := ExtractFilePath(ParamStr(0));
end;

{------------------------------------------------------------------------------}

procedure THiResForm.FormCreate(Sender: TObject);
begin
  FPalette := TGradientPalette.Create;
  cbPreset.Items.Add('Vue actuelle');
  cbPreset.Items.Add('1920 x 1080 (Full HD)');
  cbPreset.Items.Add('3840 x 2160 (4K)');
  cbPreset.Items.Add('7680 x 4320 (8K)');
  cbPreset.Items.Add('Personnalisée');
  cbPreset.ItemIndex := 2;
  cbSupersample.Items.Add('1x (aucun)');
  cbSupersample.Items.Add('2x (4 calculs par pixel)');
  cbSupersample.Items.Add('3x (9 calculs par pixel)');
  cbSupersample.ItemIndex := 1;
  edFile.Text := PicturesFolder + kDefaultFileName;
  UpdateButtons;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.FormDestroy(Sender: TObject);
begin
  StopRenderer;
  FFormula.Free;
  FPalette.Free;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not IsRunning then
    Exit;
  CanClose := MessageDlg('Un rendu est en cours. L''annuler ?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if CanClose then
    StopRenderer;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.Prepare(const V: TViewport; Formula: TFractalFormula; Palette: TGradientPalette;
  const Mapping: TColorMapping; const LocationText: RawByteString; Kernel: TEngineKernelType);
begin
  if IsRunning then
    Exit;
  FViewport := V;
  FFormula.Free;
  FFormula := Formula.Clone;
  FPalette.Assign(Palette);
  FMapping := Mapping;
  FLocationText := LocationText;
  FKernel := Kernel;
  cbPresetChange(nil);
end;

{------------------------------------------------------------------------------}

// Nom unique pour la vue préparée, dans le dossier déjà choisi. Appelé à l'ouverture seulement : Prepare est
// aussi rappelé au lancement du rendu et ne doit pas écraser un nom saisi.
procedure THiResForm.SuggestFileName;
var
  Folder: string;
begin
  if IsRunning or (FFormula = nil) then
    Exit;
  Folder := ExtractFilePath(Trim(edFile.Text));
  if Folder = '' then
    Folder := PicturesFolder;
  edFile.Text := Folder + UniqueBaseName(Folder,
    SuggestedName(TFractalFormulaClass(FFormula.ClassType), FViewport, Now), kPngExtension) + kPngExtension;
end;

{------------------------------------------------------------------------------}

// Réglages de la dernière séance : format, taille personnalisée, suréchantillonnage et dossier
procedure THiResForm.ApplySettings(const S: TAppSettings);
begin
  cbPreset.ItemIndex := S.HiResPreset;
  if S.HiResPreset = kPresetCustom then
  begin
    edWidth.Text := IntToStr(S.HiResWidth);
    edHeight.Text := IntToStr(S.HiResHeight);
  end;
  cbPresetChange(nil);
  cbSupersample.ItemIndex := S.HiResSupersample - 1;
  if (S.HiResFolder <> '') and DirectoryExists(S.HiResFolder) then
    edFile.Text := IncludeTrailingPathDelimiter(S.HiResFolder) + kDefaultFileName;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.CaptureSettings(var S: TAppSettings);
var
  Width, Height: Integer;
begin
  S.HiResPreset := cbPreset.ItemIndex;
  if (cbPreset.ItemIndex = kPresetCustom) and TryStrToInt(edWidth.Text, Width)
    and TryStrToInt(edHeight.Text, Height) then
  begin
    S.HiResWidth := Width;
    S.HiResHeight := Height;
  end;
  S.HiResSupersample := cbSupersample.ItemIndex + 1;
  S.HiResFolder := ExtractFilePath(Trim(edFile.Text));
end;

{------------------------------------------------------------------------------}

procedure THiResForm.cbPresetChange(Sender: TObject);
var
  Index: Integer;
begin
  Index := cbPreset.ItemIndex;
  edWidth.ReadOnly := Index <> kPresetCustom;
  edHeight.ReadOnly := Index <> kPresetCustom;
  if Index = kPresetCurrentView then
  begin
    edWidth.Text := IntToStr(FViewport.PixelWidth);
    edHeight.Text := IntToStr(FViewport.PixelHeight);
  end
  else if (Index >= Low(kPresetWidths)) and (Index <= High(kPresetWidths)) then
  begin
    edWidth.Text := IntToStr(kPresetWidths[Index]);
    edHeight.Text := IntToStr(kPresetHeights[Index]);
  end;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.btnBrowseClick(Sender: TObject);
begin
  dlgSave.FileName := edFile.Text;
  if dlgSave.Execute then
    edFile.Text := dlgSave.FileName;
end;

{------------------------------------------------------------------------------}

function THiResForm.ReadSettings(out Settings: THiResSettings): Boolean;
begin
  Result := False;
  if not TryStrToInt(edWidth.Text, Settings.Width) or not TryStrToInt(edHeight.Text, Settings.Height)
    or (Settings.Width < kMinHiResSize) or (Settings.Height < kMinHiResSize)
    or (Settings.Width > kMaxHiResSize) or (Settings.Height > kMaxHiResSize) then
  begin
    MessageDlg(Format('La taille doit être comprise entre %d et %d pixels.', [kMinHiResSize, kMaxHiResSize]),
      mtWarning, [mbOK], 0);
    Exit;
  end;
  Settings.Supersample := cbSupersample.ItemIndex + 1;
  Settings.FileName := Trim(edFile.Text);
  if Settings.FileName = '' then
  begin
    MessageDlg('Indiquez un fichier de destination.', mtWarning, [mbOK], 0);
    Exit;
  end;
  if FileExists(Settings.FileName)
    and (MessageDlg(Format('Le fichier « %s » existe déjà. Le remplacer ?', [ExtractFileName(Settings.FileName)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  if ExtractFilePath(Settings.FileName) <> '' then
    ForceDirectories(ExtractFilePath(Settings.FileName));
  Result := True;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.StartRender;
var
  Settings: THiResSettings;
  Supersampled: TViewport;
  IsAtLimit: Boolean;
begin
  if IsRunning then
    Exit;
  if Assigned(FOnRequestSnapshot) then
    FOnRequestSnapshot(Self);
  if (FFormula = nil) or not ReadSettings(Settings) then
    Exit;
  Supersampled := FViewport.Resized(Settings.Width * Settings.Supersample, Settings.Height * Settings.Supersample);
  // même règle que le navigateur : avec la perturbation, seule la limite du palier 2 compte
  if FFormula.IsPerturbationSupported then
    IsAtLimit := Supersampled.DeepPrecisionState = psLimit
  else
    IsAtLimit := Supersampled.PrecisionState(TRenderEngine.GetEpsilon(FKernel)) = psLimit;
  if IsAtLimit
    and (MessageDlg('Ce rendu dépasse la limite de précision : l''image sera pixelisée. Rendre quand même ?',
      mtWarning, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  FTargetFileName := Settings.FileName;
  FRenderer := THiResRenderer.Create(Settings, FViewport, FFormula, TColorMapper.Create(FPalette, FMapping),
    FLocationText, FKernel);
  FStartTick := GetTickCount;
  pbProgress.Position := 0;
  lblState.Caption := Format('Rendu en cours (moteur %s)...', [TRenderEngine.GetDisplayName(FKernel)]);
  tmrPoll.Enabled := True;
  UpdateButtons;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.btnStartClick(Sender: TObject);
begin
  StartRender;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.btnCloseClick(Sender: TObject);
begin
  if IsRunning then
    FRenderer.Terminate
  else
    Close;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.tmrPollTimer(Sender: TObject);
var
  Seconds: Cardinal;
begin
  if FRenderer = nil then
    Exit;
  pbProgress.Position := FRenderer.Progress;
  Seconds := (GetTickCount - FStartTick) div 1000;
  if not FRenderer.IsDone then
  begin
    lblState.Caption := Format('Rendu en cours... %d %%   (%d s)', [FRenderer.Progress div 10, Seconds]);
    Exit;
  end;
  tmrPoll.Enabled := False;
  FRenderer.WaitFor;
  if FRenderer.IsSucceeded then
    lblState.Caption := Format('Terminé en %d s : %s', [Seconds, ExtractFileName(FTargetFileName)])
  else if FRenderer.ErrorMessage <> '' then
    lblState.Caption := 'Erreur : ' + FRenderer.ErrorMessage
  else
    lblState.Caption := 'Rendu annulé.';
  FreeAndNil(FRenderer);
  UpdateButtons;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.StopRenderer;
begin
  if FRenderer = nil then
    Exit;
  tmrPoll.Enabled := False;
  FRenderer.Terminate;
  FRenderer.WaitFor;
  FreeAndNil(FRenderer);
  lblState.Caption := 'Rendu annulé.';
  UpdateButtons;
end;

{------------------------------------------------------------------------------}

function THiResForm.IsRunning: Boolean;
begin
  Result := FRenderer <> nil;
end;

{------------------------------------------------------------------------------}

procedure THiResForm.UpdateButtons;
begin
  btnStart.Enabled := not IsRunning;
  edWidth.Enabled := not IsRunning;
  edHeight.Enabled := not IsRunning;
  cbPreset.Enabled := not IsRunning;
  cbSupersample.Enabled := not IsRunning;
  edFile.Enabled := not IsRunning;
  btnBrowse.Enabled := not IsRunning;
  if IsRunning then
    btnClose.Caption := 'Annuler'
  else
    btnClose.Caption := 'Fermer';
end;

end.
