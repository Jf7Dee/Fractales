program Fractales;

{$SETPEFLAGS $20}  // IMAGE_FILE_LARGE_ADDRESS_AWARE : 4 Go d'adressage sous Windows 64 bits

uses
  Forms,
  SysUtils,
  XPMan,
  Fractal.Types in 'src\Fractal.Types.pas',
  Fractal.HighFloat in 'src\Fractal.HighFloat.pas',
  Fractal.Formulas in 'src\Fractal.Formulas.pas',
  Fractal.Perturbation in 'src\Fractal.Perturbation.pas',
  Fractal.RustKernel in 'src\Fractal.RustKernel.pas',
  Fractal.Buffer in 'src\Fractal.Buffer.pas',
  Fractal.Engine in 'src\Fractal.Engine.pas',
  Fractal.Palette in 'src\Fractal.Palette.pas',
  Fractal.Png in 'src\Fractal.Png.pas',
  Fractal.Persistence in 'src\Fractal.Persistence.pas',
  Fractal.Navigation in 'src\Fractal.Navigation.pas',
  Fractal.HiRes in 'src\Fractal.HiRes.pas',
  Fractal.Settings in 'src\Fractal.Settings.pas',
  Fractal.Update in 'src\Fractal.Update.pas',
  Fractal.View in 'src\Fractal.View.pas',
  MainFrm in 'src\MainFrm.pas' {MainForm},
  PaletteEditorFrm in 'src\PaletteEditorFrm.pas' {PaletteEditorForm},
  HiResFrm in 'src\HiResFrm.pas' {HiResForm},
  HelpFrm in 'src\HelpFrm.pas' {HelpForm};

{$R *.res}
begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Fractales';
  Application.CreateForm(TMainForm, MainForm);
  if FindCmdLineSwitch('smoketest') then
    ExitCode := MainForm.RunSmokeTest(ParamStr(2))
  else
  begin
    MainForm.RestoreSession;
    Application.Run;
  end;
end.
