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
    procedure CheckExactAcceptanceDepths(F: TFractalFormula; const TextX, TextY, FormulaLabel: string;
      Kernel: TEngineKernelType = ekDelphi; RustKernel: TRustKernel = nil);
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
    procedure TestCriticalOrbitReusedWhenPanning;
    procedure TestJuliaDeepRenderRunsInRustWithAbi4;
    procedure TestCriticalOrbitCoversReusedReference;
    procedure TestJuliaFarOutsideUsesCriticalOrbit;
    procedure TestCriticalOrbitSharedByBands;
    procedure TestCriticalOrbitReusedWhenZoomingOut;
    procedure TestJuliaDeepRenderAtAcceptanceDepths;
    procedure TestMultibrotDeepRenderAtAcceptanceDepths;
    procedure TestRustJuliaAndMultibrotAtAcceptanceDepths;
    procedure TestMultibrotPowerChangeAtDepth;
    procedure TestJuliaParamChangeAtDepth;
    procedure TestJuliaDustDeepRender;
    procedure TestJuliaShallowStaysDirect;
    procedure TestMultibrotShallowStaysDirect;
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
  kJuliaDeepPixelSize = 1e-30;
  kBeyondReuseWidths = 3;           // au-delà des deux largeurs de réutilisation de Z
  kJuliaParamStep = 1e-3;           // déplacement de c (partie réelle)
  // c dans l'ensemble de Mandelbrot (lapin de Douady) : W ne s'échappe pas, sa longueur dépend de MaxIter
  kRabbitCX = -0.12;
  kRabbitCY = 0.75;
  kRabbitMaxIters: array[0..2] of Integer = (1000, 1200, 1400);
  kFarOutsideX = 300;               // |Z0|² > rayon d'échappement : toutes les candidates s'échappent d'emblée
  kJuliaZoomOutPixelSize = 1e-60;   // plus de mots qu'au pixel kJuliaDeepPixelSize
  kBeyondJuliaHeadroomMaxIter = 700;   // au-delà de la marge de Z (500 x 1,25)
  kPowerChangePixelSize = 1e-30;       // vue profonde (palier 2) des changements de puissance et de c
  kMultibrotFractionalPower = 3.5;     // non entière : palier 1
  kMultibrotNextIntegerPower = 4;
  // c hors de l'ensemble de Mandelbrot (W s'échappe en 14 itérations ; 0,3 + 0,5i y reste borné) : Julia est une
  // poussière. Centre : le point fixe répulsif z² + c = z, donc un point de l'ensemble de Julia, à la précision Double.
  kDustCX = 0.3;
  kDustCY = 0.6;
  kDustCenterX = -0.0253949604533787;
  kDustCenterY = 0.5709990056644647;
  kDustMaxIter = 500;
  kEscapeRadiusSquared = 4;
  // Les centres du bord des tâches 2 et 3 (kMultibrot3X/Y, kJuliaBorderX/Y) ne valent que jusqu'à environ 1e-36 (120
  // bissections) : aux pixels 1e-200 et 2e-300 la vue tient dans un seul intervalle et l'image est uniforme. Centres
  // exacts à 320 chiffres (calculés en décimal, résidus nuls) dont le voisinage montre de la structure à toute échelle.
  // Multibrot 3 : point de Misiurewicz c = 3^(1/4) e^(i 7 pi / 12) ; 0 -> c -> w, w point fixe répulsif de z^3 + c
  // (|3 w^2| = 3 racine de 3).
  // Julia (c par défaut) : point fixe répulsif z = (1 + racine(1 - 4c)) / 2 de l'ensemble de Julia, multiplicateur ~ 3.
  // c est celui des paramètres, des Double : -0,8 et 0,156 pris à leur valeur binaire exacte, non décimale
  // (l'écart de 1e-17 sur c déplacerait le point fixe de 1e-17 et l'image serait uniforme à toute profondeur).
  // Le temps d'échappement y croît comme -ln(distance) / ln 3 (~620 itérations à 2e-300) : d'où kJuliaDeepFixedMaxIter.
  kMultibrot3DeepX = '-0.340625019316606640194394244037830888977210102549125303119702632614517377348795234363098' +
    '894929139975317759460130571319972102258985648516678785020987543232005137724559654474662298' +
    '990842181784879059644210903965592602443811239238719727078554421131207823193140792225506761' +
    '14876128181435452752857530367056555141991023326475371';
  kMultibrot3DeepY = '1.2712298784187062391356129910210649767284143282267776782136791436934807913447441969146767' +
    '160282631933396985181626638437283262450381644243328982863195606645889473223966573714015302' +
    '679689506918934527700571712003809231292205368581525859863376676655240443359592661903330133' +
    '2456881521588968918879500702011143388281769347849655';
  kJuliaDeepFixedX = '1.5275031186435346322746079313519161694753124175117324939057282566585686365256957860204218' +
    '797313351184801444002570910951865534481777051308796130172927856717641520997246593777747333' +
    '554733692653533497725634901756289430561671972800422120905766803724335507079262252218970227' +
    '8566557803248497561650426605619668972033739355370098';
  kJuliaDeepFixedY = '-0.075912178352287865376456865868742942799734402525730952654506243139459159550421806597174' +
    '420588911813206756769732574586094721158660828801112776142780444448191604413522810973643723' +
    '335613907471955114540964164395977029874058280091167396580640821604934534492290629684390547' +
    '75447222062943355991678937308701938184779390934026945';
  kJuliaDeepFixedMaxIter = 1500;

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
    CheckTrue(HasDistinctValues, Format('image uniforme au pixel %g', [V.PixelSize]));
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
begin
  Result := MakeExactViewport(kBurningShipFavouriteCenterX, kBurningShipFavouriteCenterY, Width, kDeepPixelWidth,
    kDeepPixelHeight);
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

{------------------------------------------------------------------------------}

// Vue Julia profonde au bord kJuliaBorder (MaxIter kJuliaBorderMaxIter), au pixel PixelSize.
function JuliaDeepViewport(PixelSize: TFloat = kJuliaDeepPixelSize): TViewport;
begin
  Result := MakeExactViewport(kJuliaBorderX, kJuliaBorderY, kDeepPixelWidth * PixelSize, kDeepPixelWidth,
    kDeepPixelHeight);
end;

{------------------------------------------------------------------------------}

// Julia profond : un déplacement au-delà de deux largeurs recalcule Z mais garde W (même c, même précision) ; un
// changement de c recalcule les deux.
procedure TTestEngine.TestCriticalOrbitReusedWhenPanning;
var
  E: TRenderEngine;
  F: TJuliaFormula;
  V: TViewport;
  Index: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kJuliaBorderMaxIter;
    V := JuliaDeepViewport;
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals('', E.TakeErrors);
    CheckEquals(1, E.ReferenceComputeCount);
    CheckEquals(1, E.CriticalComputeCount);
    E.Render(V.Panned(kBeyondReuseWidths * kDeepPixelWidth, 0), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals('', E.TakeErrors);
    CheckEquals(2, E.ReferenceComputeCount, 'Z non recalculée après le déplacement');
    CheckEquals(1, E.CriticalComputeCount, 'W recalculée alors que c n''a pas changé');
    Index := F.IndexOfParam('cx');
    F.SetParam(Index, F.GetParam(Index) + kJuliaParamStep);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals('', E.TakeErrors);
    CheckEquals(3, E.ReferenceComputeCount, 'Z non recalculée après le changement de c');
    CheckEquals(2, E.CriticalComputeCount, 'W non recalculée après le changement de c');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// ABI 4 (fk_compute_row_perturbed2) : la DLL reçoit l'orbite critique, un rendu Julia profond demandé en Rust est
// calculé par la DLL, sans erreur ; le palier 1 aussi.
procedure TTestEngine.TestJuliaDeepRenderRunsInRustWithAbi4;
var
  Fake: TRustKernel;
  E: TRenderEngine;
  F: TJuliaFormula;
begin
  Fake := TRustKernel.Create(FakeKernelFileName);
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    CheckTrue(Fake.IsAvailable, Fake.Status);
    E.Kernel := ekRust;
    E.RustKernel := Fake;
    F.MaxIter := kJuliaBorderMaxIter;
    CheckEquals(Ord(ekRust), Ord(E.ResolveKernel(F)), 'palier 1 de Julia en Rust');
    CheckEquals(Ord(ekRust), Ord(E.ResolveKernel(F, True)), 'palier 2 de Julia en Rust');
    E.Render(JuliaDeepViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals(Ord(ekRust), Ord(E.Status.Kernel), 'noyau du rendu Julia profond');
    CheckEquals('', E.TakeErrors);
  finally
    F.Free;
    E.Free;
    Fake.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Z réutilisée n'emporte W que si W couvre le MaxIter du rendu. c dans l'ensemble de Mandelbrot, vue intérieure
// autour de 0 : MaxIter 1000 (W et Z jusqu'à 1250) ; déplacement de trois largeurs à MaxIter 1200 (Z refaite jusqu'à
// 1500, W gardée : 1250 >= 1200) ; MaxIter 1400 sans déplacement : Z suffirait (1500), mais W (1250) non : refaite.
procedure TTestEngine.TestCriticalOrbitCoversReusedReference;
var
  E: TRenderEngine;
  F: TJuliaFormula;
  V: TViewport;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.SetParam(F.IndexOfParam('cx'), kRabbitCX);
    F.SetParam(F.IndexOfParam('cy'), kRabbitCY);
    F.MaxIter := kRabbitMaxIters[0];
    V := DeepViewport(0, 0, kJuliaDeepPixelSize);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals(1, E.CriticalComputeCount);
    F.MaxIter := kRabbitMaxIters[1];
    V := V.Panned(kBeyondReuseWidths * kDeepPixelWidth, 0);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(2, E.ReferenceComputeCount, 'Z non recalculée après le déplacement');
    CheckEquals(1, E.CriticalComputeCount, 'W recalculée alors qu''elle couvre MaxIter');
    F.MaxIter := kRabbitMaxIters[2];
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals('', E.TakeErrors);
    CheckEquals(2, E.CriticalComputeCount, 'W trop courte gardée avec Z');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue profonde loin de l'ensemble : toutes les candidates Z0 s'échappent d'emblée ; W (point de départ 0) sert de
// référence, et le rendu, tout extérieur, se termine sans erreur.
procedure TTestEngine.TestJuliaFarOutsideUsesCriticalOrbit;
var
  E: TRenderEngine;
  F: TJuliaFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kJuliaBorderMaxIter;
    E.Render(DeepViewport(kFarOutsideX, 0, kJuliaDeepPixelSize), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals('', E.TakeErrors);
    CheckEquals(0, CountNegativeValues(E), 'pixels intérieurs loin de l''ensemble');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Bandes d'un rendu HD (IsEscapedReferenceReusable) : une seule orbite critique pour toutes.
procedure TTestEngine.TestCriticalOrbitSharedByBands;
var
  E: TRenderEngine;
  F: TJuliaFormula;
  V: TViewport;
  Band: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kJuliaBorderMaxIter;
    V := JuliaDeepViewport;
    E.IsEscapedReferenceReusable := True;
    for Band := 0 to 2 do
    begin
      E.Render(V.SubViewport(1, Band * kBandRows, kBandRows), F, False);
      CheckTrue(E.WaitUntilComplete(kWaitMs));
      CheckTrue(E.Status.IsComplete);
      CheckTrue(E.Status.IsPerturbation);
      CheckEquals('', E.TakeErrors);
    end;
    CheckEquals(1, E.CriticalComputeCount, 'W recalculée entre les bandes');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Dézoom : W calculée avec plus de mots que la nouvelle vue n'en demande reste valable ; Z est refaite (MaxIter
// au-delà de sa marge), W (échappée, c par défaut) gardée.
procedure TTestEngine.TestCriticalOrbitReusedWhenZoomingOut;
var
  E: TRenderEngine;
  F: TJuliaFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kJuliaBorderMaxIter;
    E.Render(JuliaDeepViewport(kJuliaZoomOutPixelSize), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckEquals(1, E.CriticalComputeCount);
    F.MaxIter := kBeyondJuliaHeadroomMaxIter;
    E.Render(JuliaDeepViewport, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckEquals('', E.TakeErrors);
    CheckEquals(2, E.ReferenceComputeCount, 'Z non recalculée');
    CheckEquals(1, E.CriticalComputeCount, 'W plus précise recalculée au dézoom');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Rendu profond de F au centre exact (TextX ; TextY) aux profondeurs d'acceptation, par le noyau Kernel ; durée notée
// dans le journal.
// F porte déjà son MaxIter et ses paramètres.
procedure TTestEngine.CheckExactAcceptanceDepths(F: TFractalFormula; const TextX, TextY, FormulaLabel: string;
  Kernel: TEngineKernelType; RustKernel: TRustKernel);
var
  I: Integer;
  T: Cardinal;
begin
  for I := Low(kAcceptancePixelSizes) to High(kAcceptancePixelSizes) do
  begin
    T := GetTickCount;
    CheckDeepRender(F, MakeExactViewport(TextX, TextY, kDeepPixelWidth * kAcceptancePixelSizes[I], kDeepPixelWidth,
      kDeepPixelHeight), Kernel, RustKernel);
    Status(Format('%s, %s, pixel %g : %d ms', [FormulaLabel, TRenderEngine.GetDisplayName(Kernel),
      kAcceptancePixelSizes[I], GetTickCount - T]));
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestJuliaDeepRenderAtAcceptanceDepths;
var
  F: TJuliaFormula;
begin
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kJuliaDeepFixedMaxIter;
    CheckExactAcceptanceDepths(F, kJuliaDeepFixedX, kJuliaDeepFixedY, 'Julia');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestEngine.TestMultibrotDeepRenderAtAcceptanceDepths;
var
  F: TMultibrotFormula;
begin
  F := TMultibrotFormula.Create;
  try
    F.SetParam(0, 3);
    F.MaxIter := kMultibrot3MaxIter;
    CheckExactAcceptanceDepths(F, kMultibrot3DeepX, kMultibrot3DeepY, 'Multibrot 3');
  finally
    F.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Julia (c par défaut) et Multibrot p = 3 aux profondeurs d'acceptation, calculés par la DLL factice v4.
procedure TTestEngine.TestRustJuliaAndMultibrotAtAcceptanceDepths;
var
  Fake: TRustKernel;
  J: TJuliaFormula;
  M: TMultibrotFormula;
begin
  Fake := TRustKernel.Create(FakeKernelFileName);
  J := TJuliaFormula.Create;
  M := TMultibrotFormula.Create;
  try
    CheckTrue(Fake.IsAvailable, Fake.Status);
    J.MaxIter := kJuliaDeepFixedMaxIter;
    CheckExactAcceptanceDepths(J, kJuliaDeepFixedX, kJuliaDeepFixedY, 'Julia', ekRust, Fake);
    M.SetParam(0, 3);
    M.MaxIter := kMultibrot3MaxIter;
    CheckExactAcceptanceDepths(M, kMultibrot3DeepX, kMultibrot3DeepY, 'Multibrot 3', ekRust, Fake);
  finally
    M.Free;
    J.Free;
    Fake.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Multibrot : vue profonde p = 3 (palier 2) ; p = 3,5 reste sur la même vue, en palier 1, sans erreur ; p = 4
// retrouve le palier 2 avec une référence recalculée.
procedure TTestEngine.TestMultibrotPowerChangeAtDepth;
var
  E: TRenderEngine;
  F: TMultibrotFormula;
  V: TViewport;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMultibrotFormula.Create;
  try
    F.MaxIter := kMultibrot3MaxIter;
    F.SetParam(0, 3);
    V := MakeExactViewport(kMultibrot3X, kMultibrot3Y, kDeepPixelWidth * kPowerChangePixelSize, kDeepPixelWidth,
      kDeepPixelHeight);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation, 'p = 3 : palier 1');
    CheckEquals('', E.TakeErrors);
    CheckEquals(1, E.ReferenceComputeCount);
    F.SetParam(0, kMultibrotFractionalPower);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete, 'rendu p = 3,5 incomplet');
    CheckFalse(E.Status.IsPerturbation, 'p = 3,5 : perturbation');
    CheckEquals('', E.TakeErrors);
    CheckEquals(1, E.ReferenceComputeCount, 'référence calculée pour une puissance non entière');
    F.SetParam(0, kMultibrotNextIntegerPower);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete, 'rendu p = 4 incomplet');
    CheckTrue(E.Status.IsPerturbation, 'p = 4 : palier 1');
    CheckEquals('', E.TakeErrors);
    CheckEquals(2, E.ReferenceComputeCount, 'référence non recalculée pour p = 4');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Julia : vue profonde, c modifié ; rendu complet en palier 2, Z et W recalculées.
procedure TTestEngine.TestJuliaParamChangeAtDepth;
var
  E: TRenderEngine;
  F: TJuliaFormula;
  V: TViewport;
  Index: Integer;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.MaxIter := kJuliaBorderMaxIter;
    V := JuliaDeepViewport(kPowerChangePixelSize);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckEquals(1, E.ReferenceComputeCount);
    CheckEquals(1, E.CriticalComputeCount);
    Index := F.IndexOfParam('cy');
    F.SetParam(Index, F.GetParam(Index) + kJuliaParamStep);
    E.Render(V, F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete, 'rendu incomplet après le changement de c');
    CheckTrue(E.Status.IsPerturbation, 'palier 1 après le changement de c');
    CheckEquals('', E.TakeErrors);
    CheckEquals(2, E.ReferenceComputeCount, 'Z non recalculée');
    CheckEquals(2, E.CriticalComputeCount, 'W non recalculée');
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// c hors de l'ensemble de Mandelbrot : W s'échappe (vérifié ici par itération directe) et l'ensemble de Julia est une
// poussière ; le rendu profond au point fixe répulsif se termine sans erreur.
procedure TTestEngine.TestJuliaDustDeepRender;
var
  E: TRenderEngine;
  F: TJuliaFormula;
  X, Y, T: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while (N < kDustMaxIter) and (X * X + Y * Y <= kEscapeRadiusSquared) do
  begin
    T := X * X - Y * Y + kDustCX;
    Y := 2 * X * Y + kDustCY;
    X := T;
    Inc(N);
  end;
  Check(N < kDustMaxIter, 'l''orbite critique de c ne s''échappe pas');
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    F.SetParam(F.IndexOfParam('cx'), kDustCX);
    F.SetParam(F.IndexOfParam('cy'), kDustCY);
    F.MaxIter := kDustMaxIter;
    E.Render(DeepViewport(kDustCenterX, kDustCenterY, kJuliaDeepPixelSize), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckTrue(E.Status.IsPerturbation);
    CheckFalse(E.Status.IsReferencePending);
    CheckEquals('', E.TakeErrors);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue par défaut de Julia : calcul direct, ni orbite de référence ni orbite critique.
procedure TTestEngine.TestJuliaShallowStaysDirect;
var
  E: TRenderEngine;
  F: TJuliaFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TJuliaFormula.Create;
  try
    E.Render(MakeViewport(0, 0, F.DefaultWidth, kDeepPixelWidth, kDeepPixelHeight), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckFalse(E.Status.IsPerturbation);
    CheckEquals(0, E.ReferenceComputeCount);
    CheckEquals(0, E.CriticalComputeCount);
    CheckEquals('', E.TakeErrors);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

// Vue par défaut de Multibrot : calcul direct, aucune orbite de référence.
procedure TTestEngine.TestMultibrotShallowStaysDirect;
var
  E: TRenderEngine;
  F: TMultibrotFormula;
begin
  E := TRenderEngine.Create(CpuCount);
  F := TMultibrotFormula.Create;
  try
    E.Render(MakeViewport(0, 0, F.DefaultWidth, kDeepPixelWidth, kDeepPixelHeight), F);
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
    CheckFalse(E.Status.IsPerturbation);
    CheckEquals(0, E.ReferenceComputeCount);
    CheckEquals('', E.TakeErrors);
  finally
    F.Free;
    E.Free;
  end;
end;

{------------------------------------------------------------------------------}

initialization
  RegisterTest(TTestEngine.Suite);

end.
