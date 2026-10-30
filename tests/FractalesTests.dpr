program FractalesTests;

{$APPTYPE CONSOLE}

uses
  TestFramework,
  TextTestRunner,
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.HighFloat in '..\src\Fractal.HighFloat.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas',
  Fractal.Perturbation in '..\src\Fractal.Perturbation.pas',
  Fractal.RustKernel in '..\src\Fractal.RustKernel.pas',
  Fractal.Buffer in '..\src\Fractal.Buffer.pas',
  Fractal.Engine in '..\src\Fractal.Engine.pas',
  Fractal.Palette in '..\src\Fractal.Palette.pas',
  Fractal.Png in '..\src\Fractal.Png.pas',
  Fractal.Persistence in '..\src\Fractal.Persistence.pas',
  Fractal.Navigation in '..\src\Fractal.Navigation.pas',
  Fractal.HiRes in '..\src\Fractal.HiRes.pas',
  Fractal.Settings in '..\src\Fractal.Settings.pas',
  Fractal.Download in '..\src\Fractal.Download.pas',
  Fractal.Update in '..\src\Fractal.Update.pas',
  TestFractalTypes in 'TestFractalTypes.pas',
  TestFractalHighFloat in 'TestFractalHighFloat.pas',
  TestFractalPerturbation in 'TestFractalPerturbation.pas',
  TestFractalFormulas in 'TestFractalFormulas.pas',
  TestFractalBuffer in 'TestFractalBuffer.pas',
  TestFractalEngine in 'TestFractalEngine.pas',
  TestFractalPalette in 'TestFractalPalette.pas',
  TestUtils in 'TestUtils.pas',
  TestFractalPng in 'TestFractalPng.pas',
  TestFractalPersistence in 'TestFractalPersistence.pas',
  TestFractalNavigation in 'TestFractalNavigation.pas',
  TestFractalHiRes in 'TestFractalHiRes.pas',
  TestFractalRustKernel in 'TestFractalRustKernel.pas',
  TestFractalSettings in 'TestFractalSettings.pas',
  TestFractalUpdate in 'TestFractalUpdate.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
