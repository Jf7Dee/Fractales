program FractalesTests;

{$APPTYPE CONSOLE}

uses
  TestFramework,
  TextTestRunner,
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas',
  Fractal.Buffer in '..\src\Fractal.Buffer.pas',
  Fractal.Engine in '..\src\Fractal.Engine.pas',
  TestFractalTypes in 'TestFractalTypes.pas',
  TestFractalFormulas in 'TestFractalFormulas.pas',
  TestFractalBuffer in 'TestFractalBuffer.pas',
  TestFractalEngine in 'TestFractalEngine.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
