unit TestFractalEngine;

interface

uses
  Windows, SysUtils, Math, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Engine, Fractal.RustKernel;

type
  TRaisingFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TTestEngine = class(TTestCase)
  private
    function SmallViewport: TViewport;
    function CreateHeavyFormula: TFractalFormula;
    function HeavyViewport: TViewport;
    function CountNegativeValues(E: TRenderEngine): Integer;
    function DeepViewport(CX, CY, PixelSize: TFloat): TViewport;
    function FavouriteViewport(Width: TFloat): TViewport;
    procedure CheckDeepRender(F: TFractalFormula; const V: TViewport; Kernel: TEngineKernelType = ekDelphi;
      RustKernel: TRustKernel = nil);
    procedure CheckAcceptanceDepths(Kernel: TEngineKernelType; RustKernel: TRustKernel);
    procedure CheckBurningShipAcceptanceDepths(Kernel: TEngineKernelType; RustKernel: TRustKernel);
  published
    procedure TestRenderCompletesWithExactPixels;
    procedure TestValuesMatchDirectIteration;
    procedure TestMultiThreadMatchesSingleThread;
    procedure TestNoStaleWritesAfterNewRender;
    procedure TestShiftedRenderMatchesFreshRender;
    procedure TestErrorsAreReported;
    procedure TestCancelIsQuick;
    procedure TestCancelIsNotComplete;
    procedure TestDestroyWhileRendering;
    procedure TestShallowRenderStaysDirect;
    procedure TestDeepRenderUsesPerturbation;
    procedure TestTricornDeepRender;
    procedure TestBurningShipDeepRenderAtAcceptanceDepths;
    procedure TestBurningShipShallowStaysDirect;
    procedure TestBurningShipFavouriteDeepRender;
    procedure TestReferenceIsReused;
    procedure TestReferenceCandidateWhenCentreEscapes;
    procedure TestNewRenderCancelsReference;
    procedure TestDelphiRenderAtAcceptanceDepths;
    procedure TestRustRenderAtAcceptanceDepths;
    procedure TestRustBurningShipAtAcceptanceDepths;
    procedure TestReferenceReusedWithinIterHeadroom;
    procedure TestEscapedReferenceReusedForBands;
  end;

implementation

uses
  Fractal.HighFloat, TestFractalRustKernel, TestFractalPerturbation;

const
  kWaitMs = 10000;
  kRaisingName = 'Raising';
  kDeepPixelWidth = 160;
  kDeepPixelHeight = 120;
  kDeepMaxIter = 2000;
  kCancelledReferenceMaxIter = 1000000;
  kShallowAfterDeepMaxMs = 2000;
  kShiftPixels = 10;
  // profondeurs d'acceptation de la spec : 1e-200 (§7) et la limite 1e-300 du palier 2 (§2), sans la franchir
  kAcceptancePixelSizes: array[0..1] of TFloat = (1e-200, 2e-300);
  kHeadroomPixelSize = 1e-50;
  kFavouriteDeepFactor = 1e-6;   // vue du favori de JF 10^6 fois plus étroite
  kZoomFactor = 2;
  kBeyondHeadroomFactor = 1.3;      // au-delà de kReferenceIterHeadroom
  kEscapingCenterX = 0.5;           // hors de l'ensemble : le centre et les 8 autres candidates s'échappent vite
  kEscapingPixelSize = 1e-30;
  kBandRows = 16;

{------------------------------------------------------------------------------}

class function TRaisingFormula.FormulaName: string;
begin
  Result := kRaisingName;
end;

{------------------------------------------------------------------------------}

class function TRaisingFormula.DisplayName: string;
begin
  Result := kRaisingName;
end;

{------------------------------------------------------------------------------}

function TRaisingFormula.Iterate(const CX, CY: TFloat): Single;
begin
  if CX > 0 then
    raise Exception.Create('boom');
  Result := 0;
end;

{------------------------------------------------------------------------------}

function TTestEngine.SmallViewport: TViewport;
begin
  Result := MakeViewport(-0.5, 0, 3, 200, 150);
end;

{------------------------------------------------------------------------------}

function TTestEngine.HeavyViewport: TViewport;
begin
  Result := MakeViewport(0, 0, 1, 160, 120);
end;

{------------------------------------------------------------------------------}

function TTestEngine.CreateHeavyFormula: TFractalFormula;
begin
  // Julia c = 0 : le disque unité est intérieur, chaque pixel coûte MaxIter itérations
  Result := TJuliaFormula.Create;
  Result.SetParam(0, 0);
  Result.SetParam(1, 0);
  Result.MaxIter := 1000000;
end;

{------------------------------------------------------------------------------}

function TTestEngine.CountNegativeValues(E: TRenderEngine): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 0 to E.Buffer.Height - 1 do
    for X := 0 to E.Buffer.Width - 1 do
      if E.Buffer.Value(X, Y) < 0 then
        Inc(Result);
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestRenderCompletesWithExactPixels;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  X, Y, N: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals(4, E.Status.PassCount);
    N := 0;
    for Y := 0 to E.Buffer.Height - 1 do
      for X := 0 to E.Buffer.Width - 1 do
        if not E.Buffer.IsExact(X, Y) then
          Inc(N);
    CheckEquals(0, N);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestValuesMatchDirectIteration;
const
  kSamples: array[0..3, 0..1] of Integer = ((0, 0), (17, 33), (199, 149), (100, 75));
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  P: TComplexPoint;
  I: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    for I := 0 to High(kSamples) do
    begin
      P := SmallViewport.PixelToComplex(kSamples[I, 0], kSamples[I, 1]);
      CheckEquals(F.Iterate(P.X, P.Y), E.Buffer.Value(kSamples[I, 0], kSamples[I, 1]), 0);
    end;
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestMultiThreadMatchesSingleThread;
var
  E1, E8: TRenderEngine;
  F: TMandelbrotFormula;
  X, Y, N: Integer;
begin
  E1 := TRenderEngine.Create(1);
  E8 := TRenderEngine.Create(8);
  F := TMandelbrotFormula.Create;
  try
    E1.Render(SmallViewport, F);
    E8.Render(SmallViewport, F);
    CheckTrue(E1.WaitUntilComplete(kWaitMs));
    CheckTrue(E8.WaitUntilComplete(kWaitMs));
    N := 0;
    for Y := 0 to E1.Buffer.Height - 1 do
      for X := 0 to E1.Buffer.Width - 1 do
        if E1.Buffer.Value(X, Y) <> E8.Buffer.Value(X, Y) then
          Inc(N);
    CheckEquals(0, N);
  finally
    F.Free;
    E8.Free;
    E1.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestNoStaleWritesAfterNewRender;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  Light: TMandelbrotFormula;
  Round: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  Heavy := CreateHeavyFormula;
  Light := TMandelbrotFormula.Create;
  try
    for Round := 1 to 5 do
    begin
      E.Render(HeavyViewport, Heavy);
      Sleep(30);
      // tout s'échappe autour de (5, 5) : une valeur négative ne peut venir que du rendu précédent
      E.Render(MakeViewport(5, 5, 1, 160, 120), Light);
      CheckTrue(E.WaitUntilComplete(kWaitMs));
      CheckEquals(0, CountNegativeValues(E), Format('tour %d', [Round]));
    end;
  finally
    Light.Free;
    Heavy.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestShiftedRenderMatchesFreshRender;
var
  E, Fresh: TRenderEngine;
  F: TMandelbrotFormula;
  V2: TViewport;
  X, Y, N: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  Fresh := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    V2 := SmallViewport.Panned(17, -9);
    E.RenderShifted(V2, F, 17, -9);
    Fresh.Render(V2, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(Fresh.WaitUntilComplete(kWaitMs));
    N := 0;
    for Y := 0 to E.Buffer.Height - 1 do
      for X := 0 to E.Buffer.Width - 1 do
        if Abs(E.Buffer.Value(X, Y) - Fresh.Buffer.Value(X, Y)) > 1e-3 then
          Inc(N);
    CheckTrue(N <= E.Buffer.Width * E.Buffer.Height div 100, Format('%d pixels différents', [N]));
  finally
    F.Free;
    Fresh.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestErrorsAreReported;
var
  E: TRenderEngine;
  R: TRaisingFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  R := TRaisingFormula.Create;
  try
    E.Render(SmallViewport, R);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(Pos('boom', E.TakeErrors) > 0);
    CheckEquals('', E.TakeErrors);
  finally
    R.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestCancelIsQuick;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  T: Cardinal;
begin
  E := TRenderEngine.Create(CpuCount);
  Heavy := CreateHeavyFormula;
  try
    E.Render(HeavyViewport, Heavy);
    Sleep(30);
    T := GetTickCount;
    E.Cancel;
    CheckTrue(GetTickCount - T < 500, Format('%d ms', [GetTickCount - T]));
  finally
    Heavy.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestCancelIsNotComplete;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  F: TMandelbrotFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  Heavy := CreateHeavyFormula;
  F := TMandelbrotFormula.Create;
  try
    E.Render(HeavyViewport, Heavy);
    Sleep(30);
    E.Cancel;
    CheckFalse(E.Status.IsComplete);
    CheckTrue(E.WaitUntilComplete(0));
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
  finally
    F.Free;
    Heavy.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestDestroyWhileRendering;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  T: Cardinal;
begin
  Heavy := CreateHeavyFormula;
  try
    E := TRenderEngine.Create(CpuCount);
    E.Render(HeavyViewport, Heavy);
    Sleep(30);
    T := GetTickCount;
    E.Free;
    CheckTrue(GetTickCount - T < 1000, Format('%d ms', [GetTickCount - T]));
  finally
    Heavy.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestShallowRenderStaysDirect;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  P: TComplexPoint;
  X, Y, N: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    E.Render(SmallViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckFalse(E.Status.IsPerturbation);
    CheckEquals(0, E.ReferenceComputeCount);
    N := 0;
    for Y := 0 to E.Buffer.Height - 1 do
      for X := 0 to E.Buffer.Width - 1 do
      begin
        P := SmallViewport.PixelToComplex(X, Y);
        if E.Buffer.Value(X, Y) <> F.Iterate(P.X, P.Y) then
          Inc(N);
      end;
    CheckEquals(0, N);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestDeepRenderUsesPerturbation;
var
  F: TMandelbrotFormula;
begin
  // c = i : point de Misiurewicz, de la structure à toutes les échelles
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    CheckDeepRender(F, DeepViewport(0, 1, 1e-50));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

function TTestEngine.DeepViewport(CX, CY, PixelSize: TFloat): TViewport;
begin
  Result := MakeViewport(CX, CY, kDeepPixelWidth * PixelSize, kDeepPixelWidth, kDeepPixelHeight);
end;

{------------------------------------------------------------------------------}

// Rendu profond complet, en perturbation, sans erreur, et dont les valeurs lissées ne sont pas toutes égales.
procedure TTestEngine.CheckDeepRender(F: TFractalFormula; const V: TViewport; Kernel: TEngineKernelType;
  RustKernel: TRustKernel);
var
  E: TRenderEngine;
  X, Y: Integer;
  HasDistinctValues: Boolean;
begin
  E := TRenderEngine.Create(CpuCount);
  try
    E.Kernel := Kernel;
    E.RustKernel := RustKernel;
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs), 'délai dépassé');
    CheckTrue(E.Status.IsComplete, 'rendu incomplet');
    CheckTrue(E.Status.IsPerturbation, 'palier 1 au lieu de la perturbation');
    CheckEquals(Ord(Kernel), Ord(E.Status.Kernel), 'noyau du rendu');
    CheckFalse(E.Status.IsReferencePending);
    CheckEquals('', E.TakeErrors);
    CheckEquals(1, E.ReferenceComputeCount);
    HasDistinctValues := False;
    for Y := 0 to E.Buffer.Height - 1 do
      for X := 0 to E.Buffer.Width - 1 do
        if E.Buffer.Value(X, Y) <> E.Buffer.Value(0, 0) then
          HasDistinctValues := True;
    CheckTrue(HasDistinctValues, 'image uniforme');
  finally
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestTricornDeepRender;
var
  F: TTricornFormula;
begin
  F := TTricornFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    CheckDeepRender(F, DeepViewport(-2, 0, 1e-40));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestBurningShipDeepRenderAtAcceptanceDepths;
begin
  CheckBurningShipAcceptanceDepths(ekDelphi, nil);
end;

{------------------------------------------------------------------------------}

// Burning Ship sur la pointe de l'antenne (cx = kBurningShipDeepTipX, cy = 0) aux profondeurs d'acceptation ; durée
// notée dans le journal.
procedure TTestEngine.CheckBurningShipAcceptanceDepths(Kernel: TEngineKernelType; RustKernel: TRustKernel);
var
  F: TBurningShipFormula;
  I: Integer;
  T: Cardinal;
begin
  F := TBurningShipFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    for I := Low(kAcceptancePixelSizes) to High(kAcceptancePixelSizes) do
    begin
      T := GetTickCount;
      CheckDeepRender(F, DeepViewport(kBurningShipDeepTipX, 0, kAcceptancePixelSizes[I]), Kernel, RustKernel);
      Status(Format('Burning Ship, %s, pixel %g : %d ms', [TRenderEngine.GetDisplayName(Kernel),
        kAcceptancePixelSizes[I], GetTickCount - T]));
    end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue par défaut du Burning Ship : calcul direct, aucune orbite de référence.
procedure TTestEngine.TestBurningShipShallowStaysDirect;
var
  E: TRenderEngine;
  F: TBurningShipFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TBurningShipFormula.Create;
  try
    E.Render(MakeViewport(F.DefaultCenterX, F.DefaultCenterY, F.DefaultWidth, kDeepPixelWidth, kDeepPixelHeight), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs), 'délai dépassé');
    CheckFalse(E.Status.IsPerturbation);
    CheckEquals(0, E.ReferenceComputeCount);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue du favori de JF, centre exact (THighFloat) et largeur donnée.
function TTestEngine.FavouriteViewport(Width: TFloat): TViewport;
var
  X, Y: THighFloat;
  Words: Integer;
begin
  Result := MakeViewport(0, 0, Width, kDeepPixelWidth, kDeepPixelHeight);
  Words := FracWordsForPixelSize(Result.PixelSize);
  Check(THighFloat.TryParse(kBurningShipFavouriteCenterX, Words, X), 'centre X lisible');
  Check(THighFloat.TryParse(kBurningShipFavouriteCenterY, Words, Y), 'centre Y lisible');
  Result.SetCenter(X, Y);
end;

{------------------------------------------------------------------------------}

// Favori de JF à sa largeur, puis 10^6 fois plus étroit : cette dernière vue est rendue en perturbation.
procedure TTestEngine.TestBurningShipFavouriteDeepRender;
var
  F: TBurningShipFormula;
  E: TRenderEngine;
begin
  F := TBurningShipFormula.Create;
  try
    F.MaxIter := kBurningShipFavouriteMaxIter;
    // à sa propre largeur (pixel d'environ 1e-16) le favori reste au palier 1 : seule la vue 10^6 fois plus étroite
    // passe par CheckDeepRender, qui exige la perturbation
    E := TRenderEngine.Create(CpuCount);
    try
      E.Render(FavouriteViewport(kBurningShipFavouriteWidth), F);
      CheckTrue(E.WaitUntilComplete(kWaitMs), 'délai dépassé');
      CheckFalse(E.Status.IsPerturbation, 'le favori à sa largeur doit rester au palier 1');
    finally
      E.Free;
    end;
    CheckDeepRender(F, FavouriteViewport(kBurningShipFavouriteWidth * kFavouriteDeepFactor));
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestReferenceIsReused;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  V: TViewport;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    V := DeepViewport(0, 1, 1e-50);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(1, E.ReferenceComputeCount);
    E.RenderShifted(V.Panned(kShiftPixels, 0), F, kShiftPixels, 0);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals(1, E.ReferenceComputeCount, 'orbite recalculée');
    // un MaxIter au-delà de la marge de l'orbite interdit la réutilisation
    F.MaxIter := Ceil(kDeepMaxIter * kReferenceIterHeadroom) + 1;
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(2, E.ReferenceComputeCount, 'orbite réutilisée malgré un MaxIter hors marge');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestReferenceCandidateWhenCentreEscapes;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  W: TFloat;
begin
  // centre en i + W/3 : son orbite s'échappe vite ; le candidat à -1/3 de la largeur tombe exactement sur c = i,
  // dont l'orbite ne s'échappe jamais
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    W := kDeepPixelWidth * 1e-30;
    E.Render(MakeViewport(W / 3, 1, W, kDeepPixelWidth, kDeepPixelHeight), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals('', E.TakeErrors);
    // orbite calculée avec la marge d'itérations
    CheckEquals(Ceil(kDeepMaxIter * kReferenceIterHeadroom) + 1, E.ReferenceLength, 'référence échappée gardée');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestNewRenderCancelsReference;
var
  E: TRenderEngine;
  Deep, Shallow: TMandelbrotFormula;
  T, Elapsed: Cardinal;
begin
  E := TRenderEngine.Create(CpuCount);
  Deep := TMandelbrotFormula.Create;
  Shallow := TMandelbrotFormula.Create;
  try
    Deep.MaxIter := kCancelledReferenceMaxIter;
    T := GetTickCount;
    E.Render(DeepViewport(0, 1, 1e-200), Deep);
    CheckTrue(E.Status.IsReferencePending);
    E.Render(SmallViewport, Shallow);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    Elapsed := GetTickCount - T;
    CheckTrue(E.Status.IsComplete);
    CheckFalse(E.Status.IsPerturbation);
    CheckTrue(Elapsed < Cardinal(kShallowAfterDeepMaxMs), Format('%d ms', [Elapsed]));
    // l'orbite abandonnée n'est jamais installée
    CheckEquals(0, E.ReferenceComputeCount);
    CheckEquals(0, E.ReferenceLength);
  finally
    Shallow.Free;
    Deep.Free;
    E.Free;
  end;
end;


{------------------------------------------------------------------------------}

procedure TTestEngine.TestDelphiRenderAtAcceptanceDepths;
begin
  CheckAcceptanceDepths(ekDelphi, nil);
end;

{------------------------------------------------------------------------------}

// Rendu complet de c = i aux profondeurs d'acceptation, MaxIter 2000, petite vue ; durée notée dans le journal.
procedure TTestEngine.CheckAcceptanceDepths(Kernel: TEngineKernelType; RustKernel: TRustKernel);
var
  F: TMandelbrotFormula;
  I: Integer;
  T: Cardinal;
begin
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    for I := Low(kAcceptancePixelSizes) to High(kAcceptancePixelSizes) do
    begin
      T := GetTickCount;
      CheckDeepRender(F, DeepViewport(0, 1, kAcceptancePixelSizes[I]), Kernel, RustKernel);
      Status(Format('%s, pixel %g : %d ms', [TRenderEngine.GetDisplayName(Kernel), kAcceptancePixelSizes[I],
        GetTickCount - T]));
    end;
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestRustRenderAtAcceptanceDepths;
var
  Fake: TRustKernel;
begin
  // DLL factice : mêmes calculs en Double que fk_compute_row_perturbed
  Fake := TRustKernel.Create(FakeKernelFileName);
  try
    CheckTrue(Fake.IsAvailable, Fake.Status);
    CheckAcceptanceDepths(ekRust, Fake);
  finally
    Fake.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Burning Ship : la DLL factice v3 calcule aussi ses rangées perturbées.
procedure TTestEngine.TestRustBurningShipAtAcceptanceDepths;
var
  Fake: TRustKernel;
begin
  Fake := TRustKernel.Create(FakeKernelFileName);
  try
    CheckTrue(Fake.IsAvailable, Fake.Status);
    CheckBurningShipAcceptanceDepths(ekRust, Fake);
  finally
    Fake.Free;
  end;
end;


{------------------------------------------------------------------------------}

procedure TTestEngine.TestReferenceReusedWithinIterHeadroom;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  V: TViewport;
  PreviousMaxIter: Integer;
begin
  // zoom x2 au centre avec l'auto-itération : MaxIter augmente de moins de 25 %, l'orbite sert encore
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    V := DeepViewport(0, 1, kHeadroomPixelSize);
    F.MaxIter := AutoMaxIter(V);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(1, E.ReferenceComputeCount);
    PreviousMaxIter := F.MaxIter;
    V := V.ZoomedAt(V.PixelWidth / 2 - 0.5, V.PixelHeight / 2 - 0.5, kZoomFactor);
    F.MaxIter := AutoMaxIter(V);
    CheckTrue(F.MaxIter > PreviousMaxIter, 'MaxIter inchangé');
    CheckTrue(F.MaxIter < PreviousMaxIter * kReferenceIterHeadroom, 'MaxIter hors marge');
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals('', E.TakeErrors);
    CheckEquals(1, E.ReferenceComputeCount, 'orbite recalculée malgré la marge');
    // au-delà de la marge, l'orbite est recalculée
    F.MaxIter := Round(F.MaxIter * kBeyondHeadroomFactor);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(2, E.ReferenceComputeCount, 'orbite réutilisée hors marge');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestEscapedReferenceReusedForBands;
var
  E: TRenderEngine;
  F: TMandelbrotFormula;
  V: TViewport;
begin
  // deux bandes d'un rendu HD : le centre et toutes les candidates s'échappent, une seule orbite pour les deux
  E := TRenderEngine.Create(CpuCount);
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := kDeepMaxIter;
    V := DeepViewport(kEscapingCenterX, 0, kEscapingPixelSize);
    E.IsEscapedReferenceReusable := True;
    E.Render(V.SubViewport(1, 0, kBandRows), F, False);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsPerturbation);
    CheckTrue(E.ReferenceLength <= kDeepMaxIter, 'référence non échappée');
    E.Render(V.SubViewport(1, kBandRows, kBandRows), F, False);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals('', E.TakeErrors);
    CheckEquals(1, E.ReferenceComputeCount, 'orbite échappée recalculée');
    // sans l'option, une référence échappée est recalculée pour la vue suivante
    E.IsEscapedReferenceReusable := False;
    E.Render(V.SubViewport(1, 2 * kBandRows, kBandRows), F, False);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(2, E.ReferenceComputeCount, 'orbite échappée réutilisée sans l''option');
  finally
    F.Free;
    E.Free;
  end;
end;

initialization
  RegisterTest(TTestEngine.Suite);

end.
