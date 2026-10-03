program FractalesTests;

{$APPTYPE CONSOLE}

uses
  TestFramework,
  TextTestRunner,
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas',
  Fractal.Buffer in '..\src\Fractal.Buffer.pas',
  Fractal.Engine in '..\src\Fractal.Engine.pas',
  Fractal.Palette in '..\src\Fractal.Palette.pas',
  Fractal.Png in '..\src\Fractal.Png.pas',
  Fractal.Persistence in '..\src\Fractal.Persistence.pas',
  TestFractalTypes in 'TestFractalTypes.pas',
  TestFractalFormulas in 'TestFractalFormulas.pas',
  TestFractalBuffer in 'TestFractalBuffer.pas',
  TestFractalEngine in 'TestFractalEngine.pas',
  TestFractalPalette in 'TestFractalPalette.pas',
  TestUtils in 'TestUtils.pas',
  TestFractalPng in 'TestFractalPng.pas',
  TestFractalPersistence in 'TestFractalPersistence.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
