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
  TestFractalTypes in 'TestFractalTypes.pas',
  TestFractalFormulas in 'TestFractalFormulas.pas',
  TestFractalBuffer in 'TestFractalBuffer.pas',
  TestFractalEngine in 'TestFractalEngine.pas',
  TestFractalPalette in 'TestFractalPalette.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
