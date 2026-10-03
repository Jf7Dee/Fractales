program FractalesTests;

{$APPTYPE CONSOLE}

uses
  TestFramework,
  TextTestRunner,
  Fractal.Types in '..\src\Fractal.Types.pas',
  TestFractalTypes in 'TestFractalTypes.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
