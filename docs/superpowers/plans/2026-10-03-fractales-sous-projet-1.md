# Fractales — Sous-projet 1 (moteur et exploration) : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** une application VCL Delphi 2010 qui calcule et explore en temps réel des fractales de type Mandelbrot
(pool de threads, tuiles, rendu progressif), avec palettes, sauvegarde de lieux, export PNG et rendu haute
résolution.

**Architecture :** des unités sans VCL (`Fractal.*`) portent tout le calcul : vue et précision, formules, tampon
d'itérations, moteur multi-thread, palettes, écriture PNG en flux, sérialisation des lieux, navigation, rendu HD.
Elles sont couvertes par DUnit en console. La couche VCL (`Fractal.View`, `MainFrm`, `PaletteEditorFrm`,
`HiResFrm`) ne fait qu'assembler ces unités ; elle est vérifiée par un test de fumée (`-smoketest`) qui lance
l'application, rend, zoome, exporte et quitte avec un code de sortie.

**Tech Stack :** Delphi 2010 (dcc32 21.0, Win32), VCL, DUnit (livré avec D2010), `ZLib` (RTL), `pngimage`
(uniquement dans les tests, pour relire les PNG produits), Git Bash pour les commandes.

**Spec :** `docs/superpowers/specs/2026-10-03-fractales-moteur-exploration-design.md`

## Global Constraints

- Compilateur : Delphi 2010, Win32 uniquement. Pas de syntaxe postérieure à 2010 : pas de `var` en ligne, pas
  d'opérateurs sur records managés, pas de chaînes multi-lignes, pas de `$I %DATE%`.
- `TFloat = Extended`, défini uniquement dans `Fractal.Types`.
- VCL standard uniquement, aucun composant tiers.
- Racine du projet : `D:\Etudes\Dev\Perso\Fractales` (dépôt git local, commits autorisés).
- Encodage des sources `.pas`/`.dpr` : **UTF-8 avec BOM**, fins de ligne **CRLF** (vérifié : D2010 compile
  correctement ce format). Après chaque création de fichier avec l'outil Write, lancer
  `tools/normalize.sh <fichiers>`. Les `.dfm` restent en ASCII pur : les accents s'écrivent `#233` etc.
- Largeur de ligne : 120 caractères.
- Commentaires et textes d'interface en français ; identifiants en anglais.
- Fonctions booléennes et champs booléens préfixés `Is`/`Has`/`Should` (ou forme verbale qui ne peut pas se lire
  comme une propriété : `TryTakeJob`, `WaitForRender`).
- Entre deux routines : une ligne vide, le séparateur `{` + 78 tirets + `}`, une ligne vide. Dans les blocs de
  code de ce plan, ce séparateur est écrit `//SEP` pour rester lisible. **À chaque création de fichier**, avant
  `tools/normalize.sh`, lancer :
  `sed -i 's#^//SEP$#{------------------------------------------------------------------------------}#' <fichier>`.
  Pour les insertions dans un fichier existant (tâches 11 à 15), écrire directement le vrai séparateur.
- Unités nouvelles déclarées explicitement dans les `.dpr` (`uses X in 'chemin'`), jamais via le chemin de
  recherche.
- Constantes nommées pour tout littéral utilisé deux fois ou plus.
- Les threads de calcul n'appellent **jamais** la VCL (ni `Synchronize`, ni `Queue`).
- Commits : messages courts en français, se terminant par la ligne
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Écarts assumés par rapport à la spec

Ces écarts sont des précisions d'implémentation ; ils ne changent aucun comportement visible :

1. **PNG** : on n'utilise pas `TPngImage` pour écrire, mais un petit écrivain PNG en flux (`Fractal.Png`, sur
   `ZLib` de la RTL). C'est la seule façon de tenir l'exigence « rendu HD par bandes, sans tampon complet en
   mémoire » (`TPngImage` garde toute l'image, 100 Mo contigus pour un 8K). `pngimage` sert seulement dans
   les tests, à relire les fichiers produits.
2. **Annulation** : la génération est vérifiée **à chaque pixel**, pas à chaque ligne. `Render` attend la fin
   du pixel en cours de chaque thread, ce qui garantit qu'aucune écriture d'un ancien rendu n'arrive après.
3. **Favoris** : un fichier `.frac` par favori dans `%APPDATA%\Fractales\Favoris\` au lieu d'un fichier unique.
   Supprimer, renommer ou partager un favori devient une simple opération sur un fichier.
4. **Réglages de couleur** : définitions précises retenues. Avec `u = mu / 1000` (mu = valeur lissée) :
   `t = frac(Décalage + Répétition × u^Étirement)`, puis inversion éventuelle `t = 1 − t`. Répétition 1–1000
   (échelle logarithmique sur le curseur), Étirement 0,2–2 (1 = linéaire).
5. **Interface principale** : la fiche `MainFrm.dfm` contient toute la mise en page, mais les événements des
   contrôles sont branchés dans le code (`Init…`), tâche par tâche. Les deux dialogues, écrits en une seule
   tâche chacun, branchent leurs événements dans le `.dfm` comme d'habitude.

## Review Focus

1. **Mouvements de souris rapides pendant un rendu lourd** : aucun gel, aucun pixel d'un ancien rendu dans le
   nouveau. Couvert par `TestNoStaleWritesAfterNewRender` et `TestCancelIsQuick` (tâche 4).
2. **Fenêtre minimisée ou redimensionnée à 0 pixel** : la vue reste valide (1×1 minimum), aucune exception.
   Couvert par `TestResizeKeepsWidthWithoutHistory` (tâche 8).
3. **Zoom jusqu'à la limite de précision** : avertissement puis blocage, jamais d'image en blocs. Couvert par
   `TestPrecisionState` (tâche 1) et `TestPrecisionLimitBlocksZoom` (tâche 8).
4. **Fichiers écrits ou relus sous un Windows en français (virgule décimale), édités à la main ou corrompus** :
   format numérique invariant, lecture tolérante, `EFractalFileError` uniquement. Couvert par
   `TestNumbersAreInvariant`, `TestOutOfRangeValuesAreClamped`, `TestBinaryFileRaisesFileError` (tâche 7).
5. **Fermeture ou annulation pendant un rendu HD** : pas de blocage, fichier partiel supprimé. Couvert par
   `TestCancelDeletesFile` (tâche 9) et `TestDestroyWhileRendering` (tâche 4).

## Structure des fichiers

```
D:\Etudes\Dev\Perso\Fractales\
  .gitignore, .gitattributes, build.sh
  tools\normalize.sh             encodage UTF-8 BOM + CRLF
  Fractales.dpr                  application
  src\Fractal.Types.pas          TFloat, TViewport, précision, itérations auto, format invariant
  src\Fractal.Formulas.pas       TFractalFormula + 5 formules + registre
  src\Fractal.Buffer.pas         TIterationBuffer (valeurs + niveau de précision par pixel)
  src\Fractal.Engine.pas         TRenderEngine (pool de threads, tuiles, passes, générations)
  src\Fractal.Palette.pas        TGradientPalette, TColorMapping, TColorMapper, palettes livrées
  src\Fractal.Png.pas            TPngWriter (flux), ReadPngText, CRC32
  src\Fractal.Persistence.pas    TFractalLocation, TFavoriteStore, dossiers APPDATA
  src\Fractal.Navigation.pas     TNavigator, modes, historique, sélection
  src\Fractal.HiRes.pas          THiResRenderer (thread, bandes, suréchantillonnage)
  src\Fractal.View.pas           TFractalView (contrôle d'affichage)
  src\MainFrm.pas/.dfm           fenêtre principale
  src\PaletteEditorFrm.pas/.dfm  éditeur de palette
  src\HiResFrm.pas/.dfm          dialogue de rendu HD
  tests\FractalesTests.dpr       programme DUnit console
  tests\TestUtils.pas            dossier temporaire des tests
  tests\TestFractal*.pas         une unité de test par unité Fractal.*
```

Commandes (depuis Git Bash, à la racine du projet) :

- `./build.sh tests` : compile et lance les tests ; code de sortie ≠ 0 en cas d'échec.
- `./build.sh app` : compile `bin/Fractales.exe`.
- `./build.sh smoke` : compile l'application puis lance le test de fumée.

---

### Task 1 : échafaudage et `Fractal.Types`

**Files :**
- Create : `.gitignore`, `.gitattributes`, `build.sh`, `tools/normalize.sh`
- Create : `src/Fractal.Types.pas`
- Create : `tests/FractalesTests.dpr`, `tests/TestFractalTypes.pas`

**Interfaces :**
- Produces : `TFloat`, `TComplexPoint`, `TPrecisionState (psOk, psWarning, psLimit)`, `TViewport` (champs
  `CenterX, CenterY, Width: TFloat; PixelWidth, PixelHeight: Integer`, méthodes `PixelSize`, `Height`, `Zoom`,
  `PixelToComplex(PX, PY: TFloat): TComplexPoint`, `ComplexToPixel`, `ZoomedAt(PX, PY, Factor: TFloat)`,
  `Panned(DX, DY: Integer)`, `FittedToRect(X1, Y1, X2, Y2: Integer)`, `Resized(W, H: Integer)`,
  `SubViewport(Supersample, Row0, Rows: Integer)`, `PrecisionState`), constantes `kInside = -1.0`,
  `kNotComputed = -2.0`, `kDefaultWidth = 4.0`, fonctions `MakeViewport`, `AutoMaxIter`, `FloatToInvariant`,
  `InvariantToFloat`.

- [ ] **Step 1 : fichiers d'outillage**

`.gitignore` :

```
bin/
dcu/
*.dcu
*.exe
*.~*
__history/
*.local
*.identcache
*.dsk
*.stat
```

`.gitattributes` (les fichiers sont stockés tels quels, CRLF compris) :

```
* -text
```

`tools/normalize.sh` :

```sh
#!/bin/sh
# Normalise les sources Delphi 2010 : UTF-8 avec BOM pour .pas/.dpr, fins de ligne CRLF pour tout.
for f in "$@"; do
  case "$f" in
    *.pas|*.dpr)
      if [ "$(head -c3 "$f" | od -An -tx1 | tr -d ' \n')" != "efbbbf" ]; then
        printf '\357\273\277' | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      fi ;;
  esac
  unix2dos -q "$f"
done
```

`build.sh` :

```sh
#!/bin/sh
# Compilation en ligne de commande (Delphi 2010).  Usage : ./build.sh tests | app | smoke
set -e
cd "$(dirname "$0")"
DCC="/c/Program Files (x86)/Embarcadero/RAD Studio/7.0/bin/dcc32.exe"
BDS='C:\Program Files (x86)\Embarcadero\RAD Studio\7.0'
mkdir -p bin dcu
case "$1" in
  tests)
    "$DCC" -B -Q -N0dcu -Ebin -U"$BDS\source\dUnit\src" tests/FractalesTests.dpr
    ./bin/FractalesTests.exe ;;
  app)
    "$DCC" -B -Q -N0dcu -Ebin Fractales.dpr ;;
  smoke)
    "$DCC" -B -Q -N0dcu -Ebin Fractales.dpr
    rm -f bin/smoke.png bin/smoke.png.log
    set +e
    ./bin/Fractales.exe -smoketest bin/smoke.png
    code=$?
    cat bin/smoke.png.log
    exit $code ;;
  *)
    echo "Usage : $0 tests|app|smoke"
    exit 2 ;;
esac
```

Note : l'option est `-smoketest` et non `/smoketest`, parce que Git Bash réécrirait un argument commençant par
`/` en chemin Windows.

Run : `cd /d/Etudes/Dev/Perso/Fractales && chmod +x build.sh tools/normalize.sh && unix2dos -q .gitignore .gitattributes`

- [ ] **Step 2 : écrire les tests de `Fractal.Types`**

`tests/TestFractalTypes.pas` :

```pascal
unit TestFractalTypes;

interface

uses
  TestFramework, Fractal.Types;

type
  TTestViewport = class(TTestCase)
  private
    function StandardViewport: TViewport;
  published
    procedure TestPixelToComplexCenterAndCorner;
    procedure TestComplexToPixelRoundTrip;
    procedure TestZoomedAtKeepsPointFixed;
    procedure TestPannedMovesContent;
    procedure TestFittedToRect;
    procedure TestSubViewportMatchesFullPixels;
    procedure TestPrecisionState;
    procedure TestAutoMaxIter;
    procedure TestInvariantFloatRoundTrip;
  end;

implementation

uses
  SysUtils;

const
  kEps = 1e-12;

//SEP

function TTestViewport.StandardViewport: TViewport;
begin
  Result := MakeViewport(0, 0, 4, 400, 300);
end;

//SEP

procedure TTestViewport.TestPixelToComplexCenterAndCorner;
var
  V: TViewport;
  P: TComplexPoint;
begin
  V := StandardViewport;
  P := V.PixelToComplex(199.5, 149.5);
  CheckEquals(0.0, P.X, kEps);
  CheckEquals(0.0, P.Y, kEps);
  P := V.PixelToComplex(0, 0);
  CheckEquals(-1.995, P.X, kEps);
  CheckEquals(1.495, P.Y, kEps);
end;

//SEP

procedure TTestViewport.TestComplexToPixelRoundTrip;
var
  V: TViewport;
  Q: TComplexPoint;
begin
  V := StandardViewport;
  Q := V.ComplexToPixel(V.PixelToComplex(123, 45));
  CheckEquals(123.0, Q.X, 1e-9);
  CheckEquals(45.0, Q.Y, 1e-9);
end;

//SEP

procedure TTestViewport.TestZoomedAtKeepsPointFixed;
var
  V, W: TViewport;
  P, Q: TComplexPoint;
begin
  V := StandardViewport;
  P := V.PixelToComplex(50, 70);
  W := V.ZoomedAt(50, 70, 3);
  Q := W.PixelToComplex(50, 70);
  CheckEquals(P.X, Q.X, kEps);
  CheckEquals(P.Y, Q.Y, kEps);
  CheckEquals(4 / 3, W.Width, kEps);
end;

//SEP

procedure TTestViewport.TestPannedMovesContent;
var
  V, W: TViewport;
  P, Q: TComplexPoint;
begin
  V := StandardViewport;
  W := V.Panned(10, -5);
  P := V.PixelToComplex(100, 100);
  Q := W.PixelToComplex(110, 95);
  CheckEquals(P.X, Q.X, kEps);
  CheckEquals(P.Y, Q.Y, kEps);
end;

//SEP

procedure TTestViewport.TestFittedToRect;
var
  W: TViewport;
begin
  W := StandardViewport.FittedToRect(100, 75, 300, 225);
  CheckEquals(0.0, W.CenterX, kEps);
  CheckEquals(0.0, W.CenterY, kEps);
  CheckEquals(2.0, W.Width, kEps);
  W := StandardViewport.FittedToRect(300, 225, 100, 75);
  CheckEquals(0.0, W.CenterX, kEps);
  CheckEquals(2.0, W.Width, kEps);
end;

//SEP

procedure TTestViewport.TestSubViewportMatchesFullPixels;
var
  V, S: TViewport;
  A, B, C, D, Full: TComplexPoint;
begin
  V := StandardViewport;
  S := V.SubViewport(2, 10, 4);
  CheckEquals(800, S.PixelWidth);
  CheckEquals(8, S.PixelHeight);
  // le pixel (7, 11) de l'image finale = sous-pixels colonnes 14-15, lignes 2-3 de la bande
  A := S.PixelToComplex(14, 2);
  B := S.PixelToComplex(15, 2);
  C := S.PixelToComplex(14, 3);
  D := S.PixelToComplex(15, 3);
  Full := V.PixelToComplex(7, 11);
  CheckEquals(Full.X, (A.X + B.X + C.X + D.X) / 4, kEps);
  CheckEquals(Full.Y, (A.Y + B.Y + C.Y + D.Y) / 4, kEps);
end;

//SEP

procedure TTestViewport.TestPrecisionState;
begin
  CheckEquals(Ord(psOk), Ord(StandardViewport.PrecisionState));
  CheckEquals(Ord(psWarning), Ord(MakeViewport(0.5, 0, 1e-14, 400, 300).PrecisionState));
  CheckEquals(Ord(psLimit), Ord(MakeViewport(0.5, 0, 1e-17, 400, 300).PrecisionState));
end;

//SEP

procedure TTestViewport.TestAutoMaxIter;
begin
  CheckEquals(250, AutoMaxIter(StandardViewport));
  CheckTrue(AutoMaxIter(MakeViewport(0, 0, 4e-8, 400, 300)) > AutoMaxIter(MakeViewport(0, 0, 4e-4, 400, 300)));
end;

//SEP

procedure TTestViewport.TestInvariantFloatRoundTrip;
const
  kSampleX = -0.7436438870371587;
begin
  CheckEquals(kSampleX, InvariantToFloat(FloatToInvariant(kSampleX), 0), 1e-17);
  CheckEquals(1.5e-10, InvariantToFloat(FloatToInvariant(1.5e-10), 0), 1e-27);
  CheckEquals(7.0, InvariantToFloat('abc', 7), 0);
  CheckEquals(0, Pos(',', FloatToInvariant(0.5)));
end;

initialization
  RegisterTest(TTestViewport.Suite);

end.
```

`tests/FractalesTests.dpr` :

```pascal
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
```

- [ ] **Step 3 : vérifier que la compilation échoue**

Run : `tools/normalize.sh tests/*.pas tests/*.dpr && ./build.sh tests`
Expected : échec de compilation, `File not found: 'Fractal.Types.pas'` (ou `F1026`).

- [ ] **Step 4 : écrire `src/Fractal.Types.pas`**

```pascal
unit Fractal.Types;

interface

uses
  SysUtils;

type
  TFloat = Extended;

  TComplexPoint = record
    X, Y: TFloat;
  end;

  TPrecisionState = (psOk, psWarning, psLimit);

  // Fenêtre sur le plan complexe. Le pixel (PX, PY) a son centre en PX + 0,5 ; l'axe imaginaire monte.
  TViewport = record
    CenterX, CenterY: TFloat;
    Width: TFloat;
    PixelWidth, PixelHeight: Integer;
    function PixelSize: TFloat;
    function Height: TFloat;
    function Zoom: TFloat;
    function PixelToComplex(PX, PY: TFloat): TComplexPoint;
    function ComplexToPixel(const P: TComplexPoint): TComplexPoint;
    function ZoomedAt(PX, PY, Factor: TFloat): TViewport;
    function Panned(DX, DY: Integer): TViewport;
    function FittedToRect(X1, Y1, X2, Y2: Integer): TViewport;
    function Resized(APixelWidth, APixelHeight: Integer): TViewport;
    function SubViewport(Supersample, Row0, Rows: Integer): TViewport;
    function PrecisionState: TPrecisionState;
  end;

const
  kInside = -1.0;
  kNotComputed = -2.0;
  kDefaultWidth = 4.0;

function MakeViewport(ACenterX, ACenterY, AWidth: TFloat; APixelWidth, APixelHeight: Integer): TViewport;
function AutoMaxIter(const V: TViewport): Integer;
function FloatToInvariant(Value: TFloat): string;
function InvariantToFloat(const S: string; Default: TFloat): TFloat;

implementation

uses
  Math;

const
  kExtendedEpsilon = 1.0842021724855044e-19;  // 2^-63 : un ulp relatif en Extended
  kLimitUlps = 64;                            // en dessous de 64 ulps par pixel, l'image se pixelise
  kWarningFactor = 8;
  kInvariantPrecision = 18;
  kAutoIterBase = 250;
  kAutoIterScale = 150;
  kAutoIterExponent = 1.4;
  kAutoIterMax = 1000000;
  kEnglishLocale = 1033;

var
  InvariantSettings: TFormatSettings;

//SEP

function TViewport.PixelSize: TFloat;
begin
  Result := Width / PixelWidth;
end;

//SEP

function TViewport.Height: TFloat;
begin
  Result := PixelSize * PixelHeight;
end;

//SEP

function TViewport.Zoom: TFloat;
begin
  Result := kDefaultWidth / Width;
end;

//SEP

function TViewport.PixelToComplex(PX, PY: TFloat): TComplexPoint;
var
  S: TFloat;
begin
  S := PixelSize;
  Result.X := CenterX + (PX + 0.5 - PixelWidth / 2) * S;
  Result.Y := CenterY - (PY + 0.5 - PixelHeight / 2) * S;
end;

//SEP

function TViewport.ComplexToPixel(const P: TComplexPoint): TComplexPoint;
var
  S: TFloat;
begin
  S := PixelSize;
  Result.X := (P.X - CenterX) / S + PixelWidth / 2 - 0.5;
  Result.Y := (CenterY - P.Y) / S + PixelHeight / 2 - 0.5;
end;

//SEP

function TViewport.ZoomedAt(PX, PY, Factor: TFloat): TViewport;
var
  P: TComplexPoint;
begin
  // le point sous (PX, PY) reste immobile
  P := PixelToComplex(PX, PY);
  Result := Self;
  Result.Width := Width / Factor;
  Result.CenterX := P.X + (CenterX - P.X) / Factor;
  Result.CenterY := P.Y + (CenterY - P.Y) / Factor;
end;

//SEP

function TViewport.Panned(DX, DY: Integer): TViewport;
begin
  // le contenu se déplace de (DX, DY) pixels
  Result := Self;
  Result.CenterX := CenterX - DX * PixelSize;
  Result.CenterY := CenterY + DY * PixelSize;
end;

//SEP

function TViewport.FittedToRect(X1, Y1, X2, Y2: Integer): TViewport;
var
  T: Integer;
  C: TComplexPoint;
begin
  if X1 > X2 then
  begin
    T := X1;
    X1 := X2;
    X2 := T;
  end;
  if Y1 > Y2 then
  begin
    T := Y1;
    Y1 := Y2;
    Y2 := T;
  end;
  if X2 - X1 < 1 then
    Exit(Self);
  C := PixelToComplex((X1 + X2) / 2 - 0.5, (Y1 + Y2) / 2 - 0.5);
  Result := Self;
  Result.CenterX := C.X;
  Result.CenterY := C.Y;
  Result.Width := (X2 - X1) * PixelSize;
end;

//SEP

function TViewport.Resized(APixelWidth, APixelHeight: Integer): TViewport;
begin
  Result := Self;
  Result.PixelWidth := Max(1, APixelWidth);
  Result.PixelHeight := Max(1, APixelHeight);
end;

//SEP

function TViewport.SubViewport(Supersample, Row0, Rows: Integer): TViewport;
begin
  // bande de lignes [Row0, Row0 + Rows) de l'image, suréchantillonnée Supersample x Supersample
  Result := Self;
  Result.PixelWidth := PixelWidth * Supersample;
  Result.PixelHeight := Rows * Supersample;
  Result.CenterY := CenterY - (Row0 + Rows / 2 - PixelHeight / 2) * PixelSize;
end;

//SEP

function TViewport.PrecisionState: TPrecisionState;
var
  MinSize: TFloat;
begin
  MinSize := kLimitUlps * kExtendedEpsilon * Max(1.0, Max(Abs(CenterX), Abs(CenterY)));
  if PixelSize < MinSize then
    Result := psLimit
  else if PixelSize < MinSize * kWarningFactor then
    Result := psWarning
  else
    Result := psOk;
end;

//SEP

function MakeViewport(ACenterX, ACenterY, AWidth: TFloat; APixelWidth, APixelHeight: Integer): TViewport;
begin
  Result.CenterX := ACenterX;
  Result.CenterY := ACenterY;
  Result.Width := AWidth;
  Result.PixelWidth := Max(1, APixelWidth);
  Result.PixelHeight := Max(1, APixelHeight);
end;

//SEP

function AutoMaxIter(const V: TViewport): Integer;
begin
  Result := kAutoIterBase + Round(kAutoIterScale * Power(Log10(Max(1.0, V.Zoom)), kAutoIterExponent));
  Result := Min(Result, kAutoIterMax);
end;

//SEP

function FloatToInvariant(Value: TFloat): string;
begin
  Result := FloatToStrF(Value, ffGeneral, kInvariantPrecision, 0, InvariantSettings);
end;

//SEP

function InvariantToFloat(const S: string; Default: TFloat): TFloat;
var
  E: Extended;
begin
  if TryStrToFloat(Trim(S), E, InvariantSettings) and not IsNan(E) and not IsInfinite(E) then
    Result := E
  else
    Result := Default;
end;

initialization
  GetLocaleFormatSettings(kEnglishLocale, InvariantSettings);
  InvariantSettings.DecimalSeparator := '.';
  InvariantSettings.ThousandSeparator := ',';

end.
```

Run : `tools/normalize.sh src/Fractal.Types.pas`

- [ ] **Step 5 : lancer les tests**

Run : `./build.sh tests`
Expected : la dernière ligne commence par `OK:` (9 tests), code de sortie 0.

- [ ] **Step 6 : commit**

```bash
git add .gitignore .gitattributes build.sh tools src tests
git commit -m "Échafaudage, tests DUnit et Fractal.Types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2 : `Fractal.Formulas`

**Files :**
- Create : `src/Fractal.Formulas.pas`, `tests/TestFractalFormulas.pas`
- Modify : `tests/FractalesTests.dpr` (clause `uses`)

**Interfaces :**
- Consumes : `TFloat`, `kInside`, `kDefaultWidth` (tâche 1).
- Produces : `TFormulaParam = record Name, Caption: string; DefaultValue, MinValue, MaxValue: Double; end`,
  `TFractalFormula` (`constructor Create; virtual`, classes `FormulaName`, `DisplayName`, `DefaultCenterX`,
  `DefaultCenterY`, `DefaultWidth`, `Clone: TFractalFormula`, `Iterate(const CX, CY: TFloat): Single`,
  `ParamCount`, `ParamInfo(Index)`, `GetParam(Index): Double`, `SetParam(Index; Value: Double)` (bornée),
  `IndexOfParam(const AName): Integer` (−1 si absent), propriété `MaxIter` bornée à [16, 1 000 000]),
  `TFractalFormulaClass`, `TMandelbrotFormula`, `TMultibrotFormula` (param. `power`), `TJuliaFormula`
  (param. `cx`, `cy`), `TBurningShipFormula`, `TTricornFormula`, `RegisterFormula`, `FormulaClassCount`,
  `FormulaClassAt(Index)`, `FindFormulaClass(const AName): TFractalFormulaClass` (nil si inconnue, sans
  distinction de casse), constantes `kEscapeRadius2`, `kMinMaxIter = 16`, `kMaxMaxIter = 1000000`,
  `kDefaultMaxIter = 1000`.
- `Iterate` renvoie `kInside` (−1) pour un point de l'ensemble, sinon une valeur lissée ≥ 0. Elle ne modifie
  jamais l'objet : plusieurs threads l'appellent en même temps sur la même instance.

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalFormulas.pas` :

```pascal
unit TestFractalFormulas;

interface

uses
  TestFramework, Fractal.Types, Fractal.Formulas;

type
  TTestFormulas = class(TTestCase)
  published
    procedure TestMandelbrotOriginIsInside;
    procedure TestMandelbrotPeriod4BulbIsInside;
    procedure TestMandelbrotFarPointEscapesFast;
    procedure TestSmoothValueIsContinuous;
    procedure TestMultibrotPower2MatchesMandelbrot;
    procedure TestJuliaZeroIsUnitDisk;
    procedure TestTricornIsSymmetric;
    procedure TestBurningShip;
    procedure TestSetParamClampsAndCloneCopies;
    procedure TestRegistry;
  end;

implementation

//SEP

procedure TTestFormulas.TestMandelbrotOriginIsInside;
var
  F: TMandelbrotFormula;
begin
  F := TMandelbrotFormula.Create;
  try
    CheckEquals(kInside, F.Iterate(0, 0), 0);
  finally
    F.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestMandelbrotPeriod4BulbIsInside;
var
  F: TMandelbrotFormula;
begin
  // hors cardioïde et bulbe principal : aucun raccourci, il faut vraiment itérer
  F := TMandelbrotFormula.Create;
  try
    CheckEquals(kInside, F.Iterate(-1.3107, 0), 0);
  finally
    F.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestMandelbrotFarPointEscapesFast;
var
  F: TMandelbrotFormula;
  V: Single;
begin
  F := TMandelbrotFormula.Create;
  try
    V := F.Iterate(10, 10);
    CheckTrue(V >= 0, 'doit s''échapper');
    CheckTrue(V < 3, 'doit s''échapper en peu d''itérations');
  finally
    F.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestSmoothValueIsContinuous;
var
  F: TMandelbrotFormula;
  A, B: Single;
begin
  F := TMandelbrotFormula.Create;
  try
    A := F.Iterate(0.5, 0.5);
    B := F.Iterate(0.5 + 1e-7, 0.5);
    CheckTrue(A > 0);
    CheckEquals(A, B, 1e-3);
  finally
    F.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestMultibrotPower2MatchesMandelbrot;
const
  kPoints: array[0..3, 0..1] of Double = ((0.5, 0.5), (1.0, 1.0), (-2.5, 0.0), (0.0, 1.5));
var
  M: TMandelbrotFormula;
  B: TMultibrotFormula;
  I: Integer;
begin
  M := TMandelbrotFormula.Create;
  B := TMultibrotFormula.Create;
  try
    B.SetParam(B.IndexOfParam('power'), 2);
    for I := 0 to High(kPoints) do
      CheckEquals(M.Iterate(kPoints[I, 0], kPoints[I, 1]), B.Iterate(kPoints[I, 0], kPoints[I, 1]), 1e-3);
    CheckEquals(kInside, B.Iterate(0, 0), 0);
  finally
    B.Free;
    M.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestJuliaZeroIsUnitDisk;
var
  J: TJuliaFormula;
begin
  J := TJuliaFormula.Create;
  try
    J.SetParam(J.IndexOfParam('cx'), 0);
    J.SetParam(J.IndexOfParam('cy'), 0);
    CheckEquals(kInside, J.Iterate(0.5, 0), 0);
    CheckTrue(J.Iterate(1.5, 0) >= 0);
  finally
    J.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestTricornIsSymmetric;
var
  T: TTricornFormula;
begin
  T := TTricornFormula.Create;
  try
    CheckEquals(T.Iterate(0.3, 0.7), T.Iterate(0.3, -0.7), 0);
  finally
    T.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestBurningShip;
var
  B: TBurningShipFormula;
begin
  B := TBurningShipFormula.Create;
  try
    CheckEquals(kInside, B.Iterate(0, 0), 0);
    CheckTrue(B.Iterate(2, 2) >= 0);
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestSetParamClampsAndCloneCopies;
var
  B: TMultibrotFormula;
  C: TFractalFormula;
begin
  B := TMultibrotFormula.Create;
  try
    B.SetParam(0, 99);
    CheckEquals(10.0, B.GetParam(0), 0);
    B.MaxIter := 5;
    CheckEquals(kMinMaxIter, B.MaxIter);
    C := B.Clone;
    try
      CheckTrue(C is TMultibrotFormula);
      CheckEquals(10.0, C.GetParam(0), 0);
      CheckEquals(kMinMaxIter, C.MaxIter);
    finally
      C.Free;
    end;
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestFormulas.TestRegistry;
var
  B: TMultibrotFormula;
begin
  CheckTrue(FormulaClassCount >= 5);
  CheckTrue(FindFormulaClass('mandelbrot') = TMandelbrotFormula);
  CheckTrue(FindFormulaClass('xyz') = nil);
  B := TMultibrotFormula.Create;
  try
    CheckEquals(0, B.IndexOfParam('power'));
    CheckEquals(-1, B.IndexOfParam('nope'));
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TTestFormulas.Suite);

end.
```

Ajouter dans `tests/FractalesTests.dpr`, après la ligne `Fractal.Types in ...` :

```pascal
  Fractal.Formulas in '..\src\Fractal.Formulas.pas',
```

et après `TestFractalTypes in 'TestFractalTypes.pas'` (remplacer le `;` final par `,`) :

```pascal
  TestFractalFormulas in 'TestFractalFormulas.pas';
```

Règle valable pour toutes les tâches suivantes : les unités `Fractal.*` se suivent dans la clause `uses`, puis les
unités de test ; seule la dernière ligne se termine par `;`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalFormulas.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Formulas.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Formulas.pas`**

```pascal
unit Fractal.Formulas;

interface

uses
  SysUtils, Math, Fractal.Types;

const
  kEscapeRadius2 = 65536.0;  // rayon d'échappement 256 : lissage précis
  kMinMaxIter = 16;
  kMaxMaxIter = 1000000;
  kDefaultMaxIter = 1000;

type
  TFormulaParam = record
    Name: string;
    Caption: string;
    DefaultValue: Double;
    MinValue: Double;
    MaxValue: Double;
  end;

  TFractalFormula = class;
  TFractalFormulaClass = class of TFractalFormula;

  TFractalFormula = class
  private
    FParamInfos: array of TFormulaParam;
    FParamValues: array of Double;
    FMaxIter: Integer;
    procedure SetMaxIter(Value: Integer);
  protected
    procedure DeclareParam(const AName, ACaption: string; ADefault, AMin, AMax: Double);
    procedure ParamsChanged; virtual;
    function SmoothValue(N: Integer; Modulus2, LogPower: TFloat): Single;
  public
    constructor Create; virtual;
    class function FormulaName: string; virtual; abstract;
    class function DisplayName: string; virtual; abstract;
    class function DefaultCenterX: TFloat; virtual;
    class function DefaultCenterY: TFloat; virtual;
    class function DefaultWidth: TFloat; virtual;
    function Clone: TFractalFormula;
    function Iterate(const CX, CY: TFloat): Single; virtual; abstract;
    function ParamCount: Integer;
    function ParamInfo(Index: Integer): TFormulaParam;
    function GetParam(Index: Integer): Double;
    procedure SetParam(Index: Integer; Value: Double);
    function IndexOfParam(const AName: string): Integer;
    property MaxIter: Integer read FMaxIter write SetMaxIter;
  end;

  TMandelbrotFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TMultibrotFormula = class(TFractalFormula)
  private
    FPower: TFloat;
    FLogPower: TFloat;
  protected
    procedure ParamsChanged; override;
  public
    constructor Create; override;
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultWidth: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TJuliaFormula = class(TFractalFormula)
  private
    FCX: TFloat;
    FCY: TFloat;
  protected
    procedure ParamsChanged; override;
  public
    constructor Create; override;
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultWidth: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TBurningShipFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    class function DefaultCenterY: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

  TTricornFormula = class(TFractalFormula)
  public
    class function FormulaName: string; override;
    class function DisplayName: string; override;
    class function DefaultCenterX: TFloat; override;
    function Iterate(const CX, CY: TFloat): Single; override;
  end;

procedure RegisterFormula(AClass: TFractalFormulaClass);
function FormulaClassCount: Integer;
function FormulaClassAt(Index: Integer): TFractalFormulaClass;
function FindFormulaClass(const AName: string): TFractalFormulaClass;

implementation

const
  kLn2 = 0.69314718055994530942;

var
  FormulaRegistry: array of TFractalFormulaClass;

//SEP

constructor TFractalFormula.Create;
begin
  inherited Create;
  FMaxIter := kDefaultMaxIter;
end;

//SEP

class function TFractalFormula.DefaultCenterX: TFloat;
begin
  Result := 0;
end;

//SEP

class function TFractalFormula.DefaultCenterY: TFloat;
begin
  Result := 0;
end;

//SEP

class function TFractalFormula.DefaultWidth: TFloat;
begin
  Result := kDefaultWidth;
end;

//SEP

procedure TFractalFormula.SetMaxIter(Value: Integer);
begin
  FMaxIter := EnsureRange(Value, kMinMaxIter, kMaxMaxIter);
end;

//SEP

procedure TFractalFormula.DeclareParam(const AName, ACaption: string; ADefault, AMin, AMax: Double);
var
  I: Integer;
begin
  I := Length(FParamInfos);
  SetLength(FParamInfos, I + 1);
  SetLength(FParamValues, I + 1);
  FParamInfos[I].Name := AName;
  FParamInfos[I].Caption := ACaption;
  FParamInfos[I].DefaultValue := ADefault;
  FParamInfos[I].MinValue := AMin;
  FParamInfos[I].MaxValue := AMax;
  FParamValues[I] := ADefault;
end;

//SEP

procedure TFractalFormula.ParamsChanged;
begin
  // rien par défaut : les formules qui mettent des valeurs en cache le redéfinissent
end;

//SEP

function TFractalFormula.SmoothValue(N: Integer; Modulus2, LogPower: TFloat): Single;
var
  Mu: TFloat;
begin
  Mu := N + 1 - Ln(0.5 * Ln(Modulus2)) / LogPower;
  if Mu < 0 then
    Mu := 0;
  Result := Mu;
end;

//SEP

function TFractalFormula.Clone: TFractalFormula;
var
  I: Integer;
begin
  Result := TFractalFormulaClass(ClassType).Create;
  Result.MaxIter := FMaxIter;
  for I := 0 to High(FParamValues) do
    Result.SetParam(I, FParamValues[I]);
end;

//SEP

function TFractalFormula.ParamCount: Integer;
begin
  Result := Length(FParamInfos);
end;

//SEP

function TFractalFormula.ParamInfo(Index: Integer): TFormulaParam;
begin
  Result := FParamInfos[Index];
end;

//SEP

function TFractalFormula.GetParam(Index: Integer): Double;
begin
  Result := FParamValues[Index];
end;

//SEP

procedure TFractalFormula.SetParam(Index: Integer; Value: Double);
begin
  if (Index < 0) or (Index >= Length(FParamValues)) then
    raise Exception.CreateFmt('Paramètre %d inexistant pour %s', [Index, FormulaName]);
  if IsNan(Value) then
    Value := FParamInfos[Index].DefaultValue;
  FParamValues[Index] := EnsureRange(Value, FParamInfos[Index].MinValue, FParamInfos[Index].MaxValue);
  ParamsChanged;
end;

//SEP

function TFractalFormula.IndexOfParam(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FParamInfos) do
    if SameText(FParamInfos[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

//SEP

class function TMandelbrotFormula.FormulaName: string;
begin
  Result := 'Mandelbrot';
end;

//SEP

class function TMandelbrotFormula.DisplayName: string;
begin
  Result := 'Mandelbrot';
end;

//SEP

class function TMandelbrotFormula.DefaultCenterX: TFloat;
begin
  Result := -0.5;
end;

//SEP

function TMandelbrotFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2, Q: TFloat;
  N: Integer;
begin
  // cardioïde principale et bulbe de période 2 : intérieur garanti, inutile d'itérer
  Q := (CX - 0.25) * (CX - 0.25) + CY * CY;
  if (Q * (Q + (CX - 0.25)) <= 0.25 * CY * CY) or ((CX + 1) * (CX + 1) + CY * CY <= 0.0625) then
    Exit(kInside);
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    Y := 2 * X * Y + CY;
    X := X2 - Y2 + CX;
    Inc(N);
  end;
  Result := kInside;
end;

//SEP

constructor TMultibrotFormula.Create;
begin
  inherited Create;
  DeclareParam('power', 'Puissance n', 3, 1.5, 10);
  ParamsChanged;
end;

//SEP

class function TMultibrotFormula.FormulaName: string;
begin
  Result := 'Multibrot';
end;

//SEP

class function TMultibrotFormula.DisplayName: string;
begin
  Result := 'Multibrot (z^n)';
end;

//SEP

class function TMultibrotFormula.DefaultWidth: TFloat;
begin
  Result := 3.0;
end;

//SEP

procedure TMultibrotFormula.ParamsChanged;
begin
  FPower := GetParam(0);
  FLogPower := Ln(FPower);
end;

//SEP

function TMultibrotFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, M, R, T: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    M := X * X + Y * Y;
    if M > kEscapeRadius2 then
      Exit(SmoothValue(N, M, FLogPower));
    if M = 0 then
    begin
      X := CX;
      Y := CY;
    end
    else
    begin
      // z^n en polaire : accepte une puissance non entière
      R := Exp(0.5 * Ln(M) * FPower);
      T := ArcTan2(Y, X) * FPower;
      X := R * Cos(T) + CX;
      Y := R * Sin(T) + CY;
    end;
    Inc(N);
  end;
  Result := kInside;
end;

//SEP

constructor TJuliaFormula.Create;
begin
  inherited Create;
  DeclareParam('cx', 'c (réel)', -0.8, -2, 2);
  DeclareParam('cy', 'c (imaginaire)', 0.156, -2, 2);
  ParamsChanged;
end;

//SEP

class function TJuliaFormula.FormulaName: string;
begin
  Result := 'Julia';
end;

//SEP

class function TJuliaFormula.DisplayName: string;
begin
  Result := 'Julia';
end;

//SEP

class function TJuliaFormula.DefaultWidth: TFloat;
begin
  Result := 3.5;
end;

//SEP

procedure TJuliaFormula.ParamsChanged;
begin
  FCX := GetParam(0);
  FCY := GetParam(1);
end;

//SEP

function TJuliaFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2: TFloat;
  N: Integer;
begin
  X := CX;
  Y := CY;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    Y := 2 * X * Y + FCY;
    X := X2 - Y2 + FCX;
    Inc(N);
  end;
  Result := kInside;
end;

//SEP

class function TBurningShipFormula.FormulaName: string;
begin
  Result := 'BurningShip';
end;

//SEP

class function TBurningShipFormula.DisplayName: string;
begin
  Result := 'Burning Ship';
end;

//SEP

class function TBurningShipFormula.DefaultCenterX: TFloat;
begin
  Result := -0.45;
end;

//SEP

class function TBurningShipFormula.DefaultCenterY: TFloat;
begin
  Result := 0.5;
end;

//SEP

function TBurningShipFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    // - CY : le navire apparaît à l'endroit avec un axe imaginaire qui monte
    Y := 2 * Abs(X * Y) - CY;
    X := X2 - Y2 + CX;
    Inc(N);
  end;
  Result := kInside;
end;

//SEP

class function TTricornFormula.FormulaName: string;
begin
  Result := 'Tricorn';
end;

//SEP

class function TTricornFormula.DisplayName: string;
begin
  Result := 'Tricorn';
end;

//SEP

class function TTricornFormula.DefaultCenterX: TFloat;
begin
  Result := -0.3;
end;

//SEP

function TTricornFormula.Iterate(const CX, CY: TFloat): Single;
var
  X, Y, X2, Y2: TFloat;
  N: Integer;
begin
  X := 0;
  Y := 0;
  N := 0;
  while N < FMaxIter do
  begin
    X2 := X * X;
    Y2 := Y * Y;
    if X2 + Y2 > kEscapeRadius2 then
      Exit(SmoothValue(N, X2 + Y2, kLn2));
    Y := -2 * X * Y + CY;
    X := X2 - Y2 + CX;
    Inc(N);
  end;
  Result := kInside;
end;

//SEP

procedure RegisterFormula(AClass: TFractalFormulaClass);
begin
  SetLength(FormulaRegistry, Length(FormulaRegistry) + 1);
  FormulaRegistry[High(FormulaRegistry)] := AClass;
end;

//SEP

function FormulaClassCount: Integer;
begin
  Result := Length(FormulaRegistry);
end;

//SEP

function FormulaClassAt(Index: Integer): TFractalFormulaClass;
begin
  Result := FormulaRegistry[Index];
end;

//SEP

function FindFormulaClass(const AName: string): TFractalFormulaClass;
var
  I: Integer;
begin
  for I := 0 to High(FormulaRegistry) do
    if SameText(FormulaRegistry[I].FormulaName, AName) then
      Exit(FormulaRegistry[I]);
  Result := nil;
end;

initialization
  RegisterFormula(TMandelbrotFormula);
  RegisterFormula(TMultibrotFormula);
  RegisterFormula(TJuliaFormula);
  RegisterFormula(TBurningShipFormula);
  RegisterFormula(TTricornFormula);

end.
```

Run : `tools/normalize.sh src/Fractal.Formulas.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (19 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Formulas.pas tests
git commit -m "Formules : Mandelbrot, Multibrot, Julia, Burning Ship, Tricorn

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3 : `Fractal.Buffer`

**Files :**
- Create : `src/Fractal.Buffer.pas`, `tests/TestFractalBuffer.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `kNotComputed` (tâche 1).
- Produces : `TIterationBuffer` : `Create(AWidth, AHeight)`, `Resize(AWidth, AHeight)` (vide le tampon),
  `Clear`, `Shift(DX, DY: Integer)` (le contenu se déplace de DX, DY ; les zones découvertes sont vidées),
  `Value(X, Y): Single`, `Level(X, Y): Byte`, `IsExact(X, Y): Boolean`, `WriteAnchor(X, Y, Step: Integer;
  AValue: Single)`, `RowPtr(Y): PSingle`, `MarkDirty`, `TakeDirtyFlag: Boolean`, propriétés `Width`, `Height`.
- Niveau d'un pixel : 0 = non calculé, 1 = exact, S > 1 = approximation venant d'un bloc S×S. `WriteAnchor`
  écrit l'ancre (niveau 1) et remplit le reste du bloc S×S, sauf les pixels déjà plus précis (niveau ≠ 0 et ≤ S).

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalBuffer.pas` :

```pascal
unit TestFractalBuffer;

interface

uses
  TestFramework, Fractal.Types, Fractal.Buffer;

type
  TTestBuffer = class(TTestCase)
  published
    procedure TestNewBufferIsNotComputed;
    procedure TestWriteAnchorFillsBlock;
    procedure TestCoarseBlockKeepsFinerPixels;
    procedure TestBlockIsClippedAtEdges;
    procedure TestShiftMovesContent;
    procedure TestDirtyFlag;
  end;

implementation

//SEP

procedure TTestBuffer.TestNewBufferIsNotComputed;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(10, 8);
  try
    CheckEquals(10, B.Width);
    CheckEquals(8, B.Height);
    CheckEquals(kNotComputed, B.Value(9, 7), 0);
    CheckEquals(0, B.Level(9, 7));
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestBuffer.TestWriteAnchorFillsBlock;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(16, 16);
  try
    B.WriteAnchor(0, 0, 4, 5);
    CheckTrue(B.IsExact(0, 0));
    CheckEquals(4, B.Level(3, 3));
    CheckEquals(5.0, B.Value(3, 3), 0);
    CheckEquals(0, B.Level(4, 0));
    B.WriteAnchor(2, 0, 2, 9);
    CheckTrue(B.IsExact(2, 0));
    CheckEquals(2, B.Level(3, 1));
    CheckEquals(9.0, B.Value(3, 1), 0);
    CheckEquals(4, B.Level(0, 1));
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestBuffer.TestCoarseBlockKeepsFinerPixels;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(16, 16);
  try
    B.WriteAnchor(1, 1, 1, 7);
    B.WriteAnchor(0, 0, 4, 3);
    CheckEquals(7.0, B.Value(1, 1), 0);
    CheckTrue(B.IsExact(1, 1));
    CheckEquals(3.0, B.Value(2, 2), 0);
    CheckEquals(4, B.Level(2, 2));
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestBuffer.TestBlockIsClippedAtEdges;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(5, 5);
  try
    B.WriteAnchor(0, 0, 8, 2);
    CheckEquals(2.0, B.Value(4, 4), 0);
    CheckEquals(8, B.Level(4, 4));
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestBuffer.TestShiftMovesContent;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(8, 8);
  try
    B.WriteAnchor(1, 1, 1, 5);
    B.Shift(2, 1);
    CheckEquals(5.0, B.Value(3, 2), 0);
    CheckTrue(B.IsExact(3, 2));
    CheckEquals(kNotComputed, B.Value(0, 0), 0);
    CheckEquals(0, B.Level(0, 0));
  finally
    B.Free;
  end;
end;

//SEP

procedure TTestBuffer.TestDirtyFlag;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(2, 2);
  try
    B.TakeDirtyFlag;
    CheckFalse(B.TakeDirtyFlag);
    B.MarkDirty;
    CheckTrue(B.TakeDirtyFlag);
    CheckFalse(B.TakeDirtyFlag);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TTestBuffer.Suite);

end.
```

Ajouter `Fractal.Buffer in '..\src\Fractal.Buffer.pas'` et `TestFractalBuffer in 'TestFractalBuffer.pas'` au `.dpr`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalBuffer.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Buffer.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Buffer.pas`**

```pascal
unit Fractal.Buffer;

interface

uses
  Windows, Math, Fractal.Types;

type
  // Tampon d'itérations partagé par les threads de calcul : chaque thread écrit des pixels disjoints.
  TIterationBuffer = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FValues: array of Single;
    FLevels: array of Byte;
    FDirty: Integer;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Resize(AWidth, AHeight: Integer);
    procedure Clear;
    procedure Shift(DX, DY: Integer);
    function Value(X, Y: Integer): Single;
    function Level(X, Y: Integer): Byte;
    function IsExact(X, Y: Integer): Boolean;
    procedure WriteAnchor(X, Y, Step: Integer; AValue: Single);
    function RowPtr(Y: Integer): PSingle;
    procedure MarkDirty;
    function TakeDirtyFlag: Boolean;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

implementation

//SEP

constructor TIterationBuffer.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Resize(AWidth, AHeight);
end;

//SEP

procedure TIterationBuffer.Resize(AWidth, AHeight: Integer);
begin
  FWidth := Max(0, AWidth);
  FHeight := Max(0, AHeight);
  SetLength(FValues, FWidth * FHeight);
  SetLength(FLevels, FWidth * FHeight);
  Clear;
end;

//SEP

procedure TIterationBuffer.Clear;
var
  I: Integer;
begin
  for I := 0 to High(FValues) do
    FValues[I] := kNotComputed;
  if Length(FLevels) > 0 then
    FillChar(FLevels[0], Length(FLevels), 0);
  MarkDirty;
end;

//SEP

procedure TIterationBuffer.Shift(DX, DY: Integer);
var
  NewValues: array of Single;
  NewLevels: array of Byte;
  X, Y, SX, SY, I: Integer;
begin
  SetLength(NewValues, Length(FValues));
  SetLength(NewLevels, Length(FLevels));
  for Y := 0 to FHeight - 1 do
  begin
    SY := Y - DY;
    for X := 0 to FWidth - 1 do
    begin
      SX := X - DX;
      I := Y * FWidth + X;
      if (SX >= 0) and (SX < FWidth) and (SY >= 0) and (SY < FHeight) then
      begin
        NewValues[I] := FValues[SY * FWidth + SX];
        NewLevels[I] := FLevels[SY * FWidth + SX];
      end
      else
      begin
        NewValues[I] := kNotComputed;
        NewLevels[I] := 0;
      end;
    end;
  end;
  FValues := NewValues;
  FLevels := NewLevels;
  MarkDirty;
end;

//SEP

function TIterationBuffer.Value(X, Y: Integer): Single;
begin
  Result := FValues[Y * FWidth + X];
end;

//SEP

function TIterationBuffer.Level(X, Y: Integer): Byte;
begin
  Result := FLevels[Y * FWidth + X];
end;

//SEP

function TIterationBuffer.IsExact(X, Y: Integer): Boolean;
begin
  Result := FLevels[Y * FWidth + X] = 1;
end;

//SEP

procedure TIterationBuffer.WriteAnchor(X, Y, Step: Integer; AValue: Single);
var
  BX, BY, XEnd, YEnd, I: Integer;
begin
  I := Y * FWidth + X;
  FValues[I] := AValue;
  FLevels[I] := 1;
  if Step <= 1 then
    Exit;
  XEnd := Min(X + Step, FWidth);
  YEnd := Min(Y + Step, FHeight);
  for BY := Y to YEnd - 1 do
    for BX := X to XEnd - 1 do
    begin
      I := BY * FWidth + BX;
      if (FLevels[I] = 0) or (FLevels[I] > Step) then
      begin
        FValues[I] := AValue;
        FLevels[I] := Step;
      end;
    end;
end;

//SEP

function TIterationBuffer.RowPtr(Y: Integer): PSingle;
begin
  Result := @FValues[Y * FWidth];
end;

//SEP

procedure TIterationBuffer.MarkDirty;
begin
  InterlockedExchange(FDirty, 1);
end;

//SEP

function TIterationBuffer.TakeDirtyFlag: Boolean;
begin
  Result := InterlockedExchange(FDirty, 0) <> 0;
end;

end.
```

Run : `tools/normalize.sh src/Fractal.Buffer.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (25 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Buffer.pas tests
git commit -m "Tampon d'itérations avec niveau de précision par pixel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4 : `Fractal.Engine`

**Files :**
- Create : `src/Fractal.Engine.pas`, `tests/TestFractalEngine.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `TViewport`, `MakeViewport` (1) ; `TFractalFormula.Clone/Iterate`, `TMandelbrotFormula`,
  `TJuliaFormula` (2) ; `TIterationBuffer` (3).
- Produces : `TRenderEngine` : `Create(AThreadCount)`, `Render(const V; Formula; IsProgressive: Boolean = True)`,
  `RenderShifted(const V; Formula; DX, DY: Integer)`, `Cancel`, `WaitUntilComplete(TimeoutMs: Cardinal): Boolean`,
  `Status: TRenderStatus`, `TakeErrors: string`, propriété `Buffer: TIterationBuffer`.
  `TRenderStatus` : `Generation, DoneJobs, TotalJobs, PassCount: Integer; ElapsedMs: Cardinal;
  function IsComplete: Boolean; function CurrentPass: Integer`. Fonction `CpuCount: Integer`.
- Garanties : `Render` et `RenderShifted` clonent la formule (l'appelant peut la modifier ou la libérer
  ensuite) ; au retour de `Render`, plus aucun thread n'écrit de pixel de l'ancien rendu ; à la fin, tous les
  pixels sont exacts (niveau 1).
- Passes progressives : blocs 8, 4, 2, 1. Les passes d'une même tuile sont traitées dans l'ordre (une tuile
  n'est jamais traitée par deux threads à la fois) ; les tuiles proches du centre partent en premier.

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalEngine.pas` :

```pascal
unit TestFractalEngine;

interface

uses
  Windows, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Engine;

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
    function CountNegativeValues(E: TRenderEngine): Integer;
  published
    procedure TestRenderCompletesWithExactPixels;
    procedure TestValuesMatchDirectIteration;
    procedure TestMultiThreadMatchesSingleThread;
    procedure TestNoStaleWritesAfterNewRender;
    procedure TestShiftedRenderMatchesFreshRender;
    procedure TestErrorsAreReported;
    procedure TestCancelIsQuick;
    procedure TestDestroyWhileRendering;
  end;

implementation

const
  kWaitMs = 10000;

//SEP

class function TRaisingFormula.FormulaName: string;
begin
  Result := 'Raising';
end;

//SEP

class function TRaisingFormula.DisplayName: string;
begin
  Result := 'Raising';
end;

//SEP

function TRaisingFormula.Iterate(const CX, CY: TFloat): Single;
begin
  if CX > 0 then
    raise Exception.Create('boom');
  Result := 0;
end;

//SEP

function TTestEngine.SmallViewport: TViewport;
begin
  Result := MakeViewport(-0.5, 0, 3, 200, 150);
end;

//SEP

function TTestEngine.CreateHeavyFormula: TFractalFormula;
begin
  // Julia c = 0 : le disque unité est intérieur, chaque pixel coûte MaxIter itérations
  Result := TJuliaFormula.Create;
  Result.SetParam(0, 0);
  Result.SetParam(1, 0);
  Result.MaxIter := 1000000;
end;

//SEP

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

//SEP

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

//SEP

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

//SEP

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

//SEP

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
      E.Render(MakeViewport(0, 0, 1, 160, 120), Heavy);
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

//SEP

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

//SEP

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

//SEP

procedure TTestEngine.TestCancelIsQuick;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  T: Cardinal;
begin
  E := TRenderEngine.Create(CpuCount);
  Heavy := CreateHeavyFormula;
  try
    E.Render(MakeViewport(0, 0, 1, 160, 120), Heavy);
    Sleep(30);
    T := GetTickCount;
    E.Cancel;
    CheckTrue(GetTickCount - T < 500, Format('%d ms', [GetTickCount - T]));
  finally
    Heavy.Free;
    E.Free;
  end;
end;

//SEP

procedure TTestEngine.TestDestroyWhileRendering;
var
  E: TRenderEngine;
  Heavy: TFractalFormula;
  T: Cardinal;
begin
  Heavy := CreateHeavyFormula;
  try
    E := TRenderEngine.Create(CpuCount);
    E.Render(MakeViewport(0, 0, 1, 160, 120), Heavy);
    Sleep(30);
    T := GetTickCount;
    E.Free;
    CheckTrue(GetTickCount - T < 1000, Format('%d ms', [GetTickCount - T]));
  finally
    Heavy.Free;
  end;
end;

initialization
  RegisterTest(TTestEngine.Suite);

end.
```

Ajouter `Fractal.Engine in '..\src\Fractal.Engine.pas'` et `TestFractalEngine in 'TestFractalEngine.pas'` au `.dpr`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalEngine.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Engine.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Engine.pas`**

```pascal
unit Fractal.Engine;

interface

uses
  Windows, SysUtils, Classes, SyncObjs, Math, Fractal.Types, Fractal.Formulas, Fractal.Buffer;

const
  kTileSize = 64;
  kMaxErrorLines = 20;
  kIdleWaitMs = 250;

type
  TTileJob = record
    Generation: Integer;
    TileIndex: Integer;
    PassIndex: Integer;
    X0, Y0, X1, Y1: Integer;  // X1, Y1 exclus
    Step: Integer;            // taille des blocs de la passe : 8, 4, 2 ou 1
    IsTaken: Boolean;
  end;

  TRenderStatus = record
    Generation: Integer;
    DoneJobs: Integer;
    TotalJobs: Integer;
    PassCount: Integer;
    ElapsedMs: Cardinal;
    function IsComplete: Boolean;
    function CurrentPass: Integer;
  end;

  TRenderEngine = class;

  TRenderWorker = class(TThread)
  private
    FEngine: TRenderEngine;
  protected
    procedure Execute; override;
  public
    constructor Create(AEngine: TRenderEngine);
  end;

  TRenderEngine = class
  private
    FLock: TCriticalSection;
    FWorkEvent: TEvent;
    FCompleteEvent: TEvent;
    FWorkers: array of TRenderWorker;
    FJobs: array of TTileJob;
    FTileDone: array of Integer;
    FNextJob: Integer;
    FGeneration: Integer;
    FActiveJobs: Integer;
    FDoneJobs: Integer;
    FTotalJobs: Integer;
    FPassCount: Integer;
    FStartTick: Cardinal;
    FElapsedMs: Cardinal;
    FIsShuttingDown: Boolean;
    FViewport: TViewport;
    FFormula: TFractalFormula;
    FBuffer: TIterationBuffer;
    FErrors: TStringList;
    function TryTakeJob(out Job: TTileJob): Boolean;
    function ProcessJob(const Job: TTileJob): Boolean;
    procedure FinishJob(const Job: TTileJob; IsCompleted: Boolean);
    procedure AddError(const Msg: string);
    procedure StopCurrent;
    procedure StartRender(const V: TViewport; Formula: TFractalFormula; IsProgressive, IsShift: Boolean;
      DX, DY: Integer);
    procedure QueueJobs(IsProgressive: Boolean);
  public
    constructor Create(AThreadCount: Integer);
    destructor Destroy; override;
    procedure Render(const V: TViewport; Formula: TFractalFormula; IsProgressive: Boolean = True);
    procedure RenderShifted(const V: TViewport; Formula: TFractalFormula; DX, DY: Integer);
    procedure Cancel;
    function WaitUntilComplete(TimeoutMs: Cardinal): Boolean;
    function Status: TRenderStatus;
    function TakeErrors: string;
    property Buffer: TIterationBuffer read FBuffer;
  end;

function CpuCount: Integer;

implementation

const
  kProgressiveSteps: array[0..3] of Integer = (8, 4, 2, 1);

//SEP

function CpuCount: Integer;
var
  Info: TSystemInfo;
begin
  GetSystemInfo(Info);
  Result := Max(1, Info.dwNumberOfProcessors);
end;

//SEP

function TRenderStatus.IsComplete: Boolean;
begin
  Result := DoneJobs >= TotalJobs;
end;

//SEP

function TRenderStatus.CurrentPass: Integer;
var
  JobsPerPass: Integer;
begin
  if (PassCount = 0) or (TotalJobs = 0) then
    Exit(PassCount);
  JobsPerPass := Max(1, TotalJobs div PassCount);
  Result := Min(PassCount, DoneJobs div JobsPerPass + 1);
end;

//SEP

constructor TRenderWorker.Create(AEngine: TRenderEngine);
begin
  FEngine := AEngine;
  inherited Create(False);
end;

//SEP

procedure TRenderWorker.Execute;
var
  Job: TTileJob;
  IsCompleted: Boolean;
begin
  while not Terminated do
    if FEngine.TryTakeJob(Job) then
    begin
      IsCompleted := False;
      try
        try
          IsCompleted := FEngine.ProcessJob(Job);
        except
          on E: Exception do
          begin
            FEngine.AddError(Format('Tuile (%d, %d) : %s', [Job.X0, Job.Y0, E.Message]));
            IsCompleted := True;
          end;
        end;
      finally
        FEngine.FinishJob(Job, IsCompleted);
      end;
    end
    else
      FEngine.FWorkEvent.WaitFor(kIdleWaitMs);
end;

//SEP

constructor TRenderEngine.Create(AThreadCount: Integer);
var
  I: Integer;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FWorkEvent := TEvent.Create(nil, True, False, '');
  FCompleteEvent := TEvent.Create(nil, True, True, '');
  FErrors := TStringList.Create;
  FBuffer := TIterationBuffer.Create(0, 0);
  FViewport := MakeViewport(0, 0, kDefaultWidth, 1, 1);
  SetLength(FWorkers, Max(1, AThreadCount));
  for I := 0 to High(FWorkers) do
    FWorkers[I] := TRenderWorker.Create(Self);
end;

//SEP

destructor TRenderEngine.Destroy;
var
  I: Integer;
begin
  StopCurrent;
  FIsShuttingDown := True;
  for I := 0 to High(FWorkers) do
    FWorkers[I].Terminate;
  FWorkEvent.SetEvent;
  for I := 0 to High(FWorkers) do
  begin
    FWorkers[I].WaitFor;
    FWorkers[I].Free;
  end;
  FFormula.Free;
  FBuffer.Free;
  FErrors.Free;
  FCompleteEvent.Free;
  FWorkEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

//SEP

procedure TRenderEngine.Render(const V: TViewport; Formula: TFractalFormula; IsProgressive: Boolean);
begin
  StartRender(V, Formula, IsProgressive, False, 0, 0);
end;

//SEP

procedure TRenderEngine.RenderShifted(const V: TViewport; Formula: TFractalFormula; DX, DY: Integer);
begin
  StartRender(V, Formula, True, True, DX, DY);
end;

//SEP

procedure TRenderEngine.StartRender(const V: TViewport; Formula: TFractalFormula; IsProgressive, IsShift: Boolean;
  DX, DY: Integer);
var
  NewFormula: TFractalFormula;
begin
  // clonée avant l'arrêt : si le clonage échoue, le rendu courant reste intact
  NewFormula := Formula.Clone;
  StopCurrent;
  FFormula.Free;
  FFormula := NewFormula;
  FViewport := V;
  if (FBuffer.Width <> V.PixelWidth) or (FBuffer.Height <> V.PixelHeight) then
    FBuffer.Resize(V.PixelWidth, V.PixelHeight)
  else if IsShift then
    FBuffer.Shift(DX, DY)
  else
    FBuffer.Clear;
  QueueJobs(IsProgressive);
end;

//SEP

procedure TRenderEngine.StopCurrent;
begin
  FLock.Enter;
  try
    Inc(FGeneration);
    SetLength(FJobs, 0);
    FNextJob := 0;
    FTotalJobs := 0;
    FDoneJobs := 0;
    FCompleteEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
  // chaque thread actif s'arrête au pixel suivant : on l'attend pour qu'il n'écrive plus rien ensuite
  while FActiveJobs > 0 do
    SwitchToThread;
end;

//SEP

procedure TRenderEngine.QueueJobs(IsProgressive: Boolean);
var
  TilesX, TilesY, TileCount, StepCount, T, P, I, J, Tmp: Integer;
  Order: array of Integer;
  Dist: array of Double;
  DX, DY: Double;
begin
  TilesX := (FBuffer.Width + kTileSize - 1) div kTileSize;
  TilesY := (FBuffer.Height + kTileSize - 1) div kTileSize;
  TileCount := TilesX * TilesY;
  SetLength(Order, TileCount);
  SetLength(Dist, TileCount);
  for T := 0 to TileCount - 1 do
  begin
    Order[T] := T;
    DX := (T mod TilesX + 0.5) * kTileSize - FBuffer.Width / 2;
    DY := (T div TilesX + 0.5) * kTileSize - FBuffer.Height / 2;
    Dist[T] := DX * DX + DY * DY;
  end;
  // tri par insertion du centre vers les bords : quelques milliers de tuiles au plus
  for I := 1 to TileCount - 1 do
  begin
    Tmp := Order[I];
    J := I - 1;
    while (J >= 0) and (Dist[Order[J]] > Dist[Tmp]) do
    begin
      Order[J + 1] := Order[J];
      Dec(J);
    end;
    Order[J + 1] := Tmp;
  end;
  if IsProgressive then
    StepCount := Length(kProgressiveSteps)
  else
    StepCount := 1;

  FLock.Enter;
  try
    SetLength(FJobs, TileCount * StepCount);
    SetLength(FTileDone, TileCount);
    for T := 0 to TileCount - 1 do
      FTileDone[T] := 0;
    I := 0;
    for P := 0 to StepCount - 1 do
      for J := 0 to TileCount - 1 do
      begin
        T := Order[J];
        FJobs[I].Generation := FGeneration;
        FJobs[I].TileIndex := T;
        FJobs[I].PassIndex := P;
        FJobs[I].X0 := (T mod TilesX) * kTileSize;
        FJobs[I].Y0 := (T div TilesX) * kTileSize;
        FJobs[I].X1 := Min(FJobs[I].X0 + kTileSize, FBuffer.Width);
        FJobs[I].Y1 := Min(FJobs[I].Y0 + kTileSize, FBuffer.Height);
        if IsProgressive then
          FJobs[I].Step := kProgressiveSteps[P]
        else
          FJobs[I].Step := 1;
        FJobs[I].IsTaken := False;
        Inc(I);
      end;
    FNextJob := 0;
    FTotalJobs := Length(FJobs);
    FDoneJobs := 0;
    FPassCount := StepCount;
    FStartTick := GetTickCount;
    FElapsedMs := 0;
    if FTotalJobs = 0 then
      FCompleteEvent.SetEvent
    else
      FWorkEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

//SEP

function TRenderEngine.TryTakeJob(out Job: TTileJob): Boolean;
var
  I: Integer;
begin
  Result := False;
  FLock.Enter;
  try
    while (FNextJob < Length(FJobs)) and FJobs[FNextJob].IsTaken do
      Inc(FNextJob);
    // une passe d'une tuile n'est éligible qu'une fois les passes précédentes de cette tuile terminées
    for I := FNextJob to High(FJobs) do
      if not FJobs[I].IsTaken and (FTileDone[FJobs[I].TileIndex] = FJobs[I].PassIndex) then
      begin
        FJobs[I].IsTaken := True;
        Job := FJobs[I];
        InterlockedIncrement(FActiveJobs);
        Exit(True);
      end;
    if not FIsShuttingDown then
      FWorkEvent.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

//SEP

function TRenderEngine.ProcessJob(const Job: TTileJob): Boolean;
var
  X, Y: Integer;
  P: TComplexPoint;
begin
  Result := False;
  Y := Job.Y0;
  while Y < Job.Y1 do
  begin
    X := Job.X0;
    while X < Job.X1 do
    begin
      if Job.Generation <> FGeneration then
        Exit;
      if not FBuffer.IsExact(X, Y) then
      begin
        P := FViewport.PixelToComplex(X, Y);
        FBuffer.WriteAnchor(X, Y, Job.Step, FFormula.Iterate(P.X, P.Y));
      end;
      Inc(X, Job.Step);
    end;
    FBuffer.MarkDirty;
    Inc(Y, Job.Step);
  end;
  Result := True;
end;

//SEP

procedure TRenderEngine.FinishJob(const Job: TTileJob; IsCompleted: Boolean);
begin
  FLock.Enter;
  try
    if IsCompleted and (Job.Generation = FGeneration) then
    begin
      Inc(FTileDone[Job.TileIndex]);
      Inc(FDoneJobs);
      if FDoneJobs = FTotalJobs then
      begin
        FElapsedMs := GetTickCount - FStartTick;
        FCompleteEvent.SetEvent;
      end
      else
        FWorkEvent.SetEvent;
    end;
    InterlockedDecrement(FActiveJobs);
  finally
    FLock.Leave;
  end;
end;

//SEP

procedure TRenderEngine.AddError(const Msg: string);
begin
  FLock.Enter;
  try
    if FErrors.Count < kMaxErrorLines then
      FErrors.Add(Msg);
  finally
    FLock.Leave;
  end;
end;

//SEP

procedure TRenderEngine.Cancel;
begin
  StopCurrent;
  FCompleteEvent.SetEvent;
end;

//SEP

function TRenderEngine.WaitUntilComplete(TimeoutMs: Cardinal): Boolean;
begin
  Result := FCompleteEvent.WaitFor(TimeoutMs) = wrSignaled;
end;

//SEP

function TRenderEngine.Status: TRenderStatus;
begin
  FLock.Enter;
  try
    Result.Generation := FGeneration;
    Result.DoneJobs := FDoneJobs;
    Result.TotalJobs := FTotalJobs;
    Result.PassCount := FPassCount;
    if FDoneJobs < FTotalJobs then
      Result.ElapsedMs := GetTickCount - FStartTick
    else
      Result.ElapsedMs := FElapsedMs;
  finally
    FLock.Leave;
  end;
end;

//SEP

function TRenderEngine.TakeErrors: string;
begin
  FLock.Enter;
  try
    Result := TrimRight(FErrors.Text);
    FErrors.Clear;
  finally
    FLock.Leave;
  end;
end;

end.
```

Run : `tools/normalize.sh src/Fractal.Engine.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (33 tests). `TestNoStaleWritesAfterNewRender` doit passer à chaque exécution : lancer
`./build.sh tests` trois fois de suite pour s'en assurer.

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Engine.pas tests
git commit -m "Moteur de rendu : pool de threads, tuiles, passes progressives

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5 : `Fractal.Palette`

**Files :**
- Create : `src/Fractal.Palette.pas`, `tests/TestFractalPalette.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `FloatToInvariant`, `InvariantToFloat` (1).
- Produces : `TColorStop = record Position: Double; Color: Cardinal; end` (couleur `$00RRGGBB`) ;
  `TGradientPalette` (`Assign`, `Clear`, `SetDefault`, `AddStop(Pos; Color): Integer`, `DeleteStop(Index)`,
  `MoveStop(Index; Pos): Integer` (renvoie le nouvel indice), `SetStopColor(Index; Color)`, `StopCount`,
  `Stop(Index)`, `ColorAt(T: Double): Cardinal` (cyclique), `SaveToStrings(Lines)`, `LoadFromStrings(Lines)`,
  `LoadFromMap(Lines)`, propriété `Name`) ; `EPaletteError` ; `TColorMapping = record Offset, Repeats, Stretch:
  Double; IsInverted: Boolean; end` ; `DefaultColorMapping`, `ClampColorMapping`, `MappingFromSliders(Offset,
  Repeats, Stretch: Integer; IsInverted: Boolean): TColorMapping`, `MappingToSliders(const M; out Offset,
  Repeats, Stretch: Integer)` ; `TColorMapper` (`Create(Palette; const Mapping)`, `MapValue(Mu: Single):
  Cardinal`, `MapRow(Src: PSingle; Dest: PCardinal; Count: Integer)`) ; `SwapRedBlue(C: Cardinal): Cardinal` ;
  `BuiltInPaletteCount`, `CreateBuiltInPalette(Index): TGradientPalette` (0 = Classique, 1 = Feu) ;
  constantes `kSliderMax = 1000`, `kMinRepeats`, `kMaxRepeats`, `kMinStretch`, `kMaxStretch`.
- `MapValue` renvoie du `$00RRGGBB`, c'est-à-dire l'ordre mémoire B, G, R, 0 d'un `TBitmap` `pf32bit`.
- Un `TColorMapper` ne change plus après sa création : on peut le lire depuis plusieurs threads.

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalPalette.pas` :

```pascal
unit TestFractalPalette;

interface

uses
  Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Palette;

type
  TTestPalette = class(TTestCase)
  private
    function CreateTwoStops(P1: Double; C1: Cardinal; P2: Double; C2: Cardinal): TGradientPalette;
  published
    procedure TestColorAtStopsAndMidpoint;
    procedure TestColorAtWrapsAround;
    procedure TestMoveStopKeepsOrder;
    procedure TestStringsRoundTrip;
    procedure TestEmptyStringsGiveDefault;
    procedure TestLoadFromMap;
    procedure TestInvalidMapRaises;
    procedure TestMapperInsideIsBlack;
    procedure TestMapperRepeatsAndOffset;
    procedure TestMapperInvert;
    procedure TestMapRowMatchesMapValue;
    procedure TestSliderRoundTrip;
    procedure TestSwapRedBlue;
    procedure TestBuiltInPalettes;
  end;

implementation

//SEP

function TTestPalette.CreateTwoStops(P1: Double; C1: Cardinal; P2: Double; C2: Cardinal): TGradientPalette;
begin
  Result := TGradientPalette.Create;
  Result.Clear;
  Result.AddStop(P1, C1);
  Result.AddStop(P2, C2);
end;

//SEP

procedure TTestPalette.TestColorAtStopsAndMidpoint;
var
  P: TGradientPalette;
  R: Cardinal;
begin
  P := CreateTwoStops(0, $000000, 0.5, $FF0000);
  try
    CheckEquals(Integer($000000), Integer(P.ColorAt(0)));
    CheckEquals(Integer($FF0000), Integer(P.ColorAt(0.5)));
    R := (P.ColorAt(0.25) shr 16) and $FF;
    CheckTrue((R >= 127) and (R <= 128), IntToStr(R));
  finally
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestColorAtWrapsAround;
var
  P: TGradientPalette;
  G: Cardinal;
begin
  P := CreateTwoStops(0.25, $000000, 0.75, $FFFFFF);
  try
    // 0 est à mi-chemin entre le blanc (0,75) et le noir suivant (1,25)
    G := (P.ColorAt(0) shr 8) and $FF;
    CheckTrue((G >= 127) and (G <= 128), IntToStr(G));
    CheckEquals(Integer(P.ColorAt(0)), Integer(P.ColorAt(1.0)));
  finally
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestMoveStopKeepsOrder;
var
  P: TGradientPalette;
  I: Integer;
begin
  P := CreateTwoStops(0.2, $111111, 0.6, $222222);
  try
    I := P.AddStop(0.4, $333333);
    CheckEquals(1, I);
    I := P.MoveStop(0, 0.9);
    CheckEquals(2, I);
    CheckEquals(Integer($111111), Integer(P.Stop(2).Color));
    CheckEquals(0.4, P.Stop(0).Position, 1e-12);
  finally
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestStringsRoundTrip;
var
  A, B: TGradientPalette;
  L: TStringList;
  I: Integer;
begin
  A := CreateBuiltInPalette(1);
  B := TGradientPalette.Create;
  L := TStringList.Create;
  try
    A.SaveToStrings(L);
    B.LoadFromStrings(L);
    CheckEquals(A.Name, B.Name);
    CheckEquals(A.StopCount, B.StopCount);
    for I := 0 to A.StopCount - 1 do
    begin
      CheckEquals(A.Stop(I).Position, B.Stop(I).Position, 1e-6);
      CheckEquals(Integer(A.Stop(I).Color), Integer(B.Stop(I).Color));
    end;
  finally
    L.Free;
    B.Free;
    A.Free;
  end;
end;

//SEP

procedure TTestPalette.TestEmptyStringsGiveDefault;
var
  P: TGradientPalette;
  L: TStringList;
begin
  P := TGradientPalette.Create;
  L := TStringList.Create;
  try
    L.Add('Stop0=pas un nombre');
    P.LoadFromStrings(L);
    CheckEquals(2, P.StopCount);
  finally
    L.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestLoadFromMap;
var
  P: TGradientPalette;
  L: TStringList;
begin
  P := TGradientPalette.Create;
  L := TStringList.Create;
  try
    L.Add('255 0 0 rouge');
    L.Add('');
    L.Add('  0 255   0');
    L.Add('0'#9'0'#9'255');
    P.LoadFromMap(L);
    CheckEquals(3, P.StopCount);
    CheckEquals(Integer($FF0000), Integer(P.Stop(0).Color));
    CheckEquals(Integer($00FF00), Integer(P.Stop(1).Color));
    CheckEquals(Integer($0000FF), Integer(P.Stop(2).Color));
    CheckEquals(1 / 3, P.Stop(1).Position, 1e-12);
  finally
    L.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestInvalidMapRaises;
var
  P: TGradientPalette;
  L: TStringList;
  IsRaised: Boolean;
begin
  P := TGradientPalette.Create;
  L := TStringList.Create;
  try
    L.Add('12 34 56');
    L.Add('bonjour');
    IsRaised := False;
    try
      P.LoadFromMap(L);
    except
      on EPaletteError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    L.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestMapperInsideIsBlack;
var
  P: TGradientPalette;
  M: TColorMapper;
begin
  P := CreateTwoStops(0, $FFFFFF, 0.5, $FF0000);
  M := TColorMapper.Create(P, DefaultColorMapping);
  try
    CheckEquals(0, Integer(M.MapValue(kInside)));
    CheckEquals(0, Integer(M.MapValue(kNotComputed)));
  finally
    M.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestMapperRepeatsAndOffset;
var
  P: TGradientPalette;
  A, B, C: TColorMapper;
  MA, MB, MC: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  MA := DefaultColorMapping;
  MA.Repeats := 10;
  MB := MA;
  MB.Repeats := 20;
  MC := MA;
  MC.Offset := 0.5;
  A := TColorMapper.Create(P, MA);
  B := TColorMapper.Create(P, MB);
  C := TColorMapper.Create(P, MC);
  try
    CheckEquals(Integer(A.MapValue(50)), Integer(B.MapValue(25)));
    // 50 itérations avec Répétition 10 donnent t = 0,5 ; un décalage de 0,5 le ramène à 0
    CheckEquals(Integer(A.MapValue(0)), Integer(C.MapValue(50)));
  finally
    C.Free;
    B.Free;
    A.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestMapperInvert;
var
  P: TGradientPalette;
  A, B: TColorMapper;
  M: TColorMapping;
begin
  P := CreateBuiltInPalette(0);
  M := DefaultColorMapping;
  M.Repeats := 10;
  A := TColorMapper.Create(P, M);
  M.IsInverted := True;
  B := TColorMapper.Create(P, M);
  try
    // t = 0,25 inversé = 0,75
    CheckEquals(Integer(A.MapValue(75)), Integer(B.MapValue(25)));
  finally
    B.Free;
    A.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestMapRowMatchesMapValue;
const
  kCount = 5;
var
  P: TGradientPalette;
  M: TColorMapper;
  Src: array[0..kCount - 1] of Single;
  Dest: array[0..kCount - 1] of Cardinal;
  I: Integer;
begin
  P := CreateBuiltInPalette(2);
  M := TColorMapper.Create(P, DefaultColorMapping);
  try
    Src[0] := kInside;
    Src[1] := 0;
    Src[2] := 3.7;
    Src[3] := 120.25;
    Src[4] := 999;
    M.MapRow(@Src[0], @Dest[0], kCount);
    for I := 0 to kCount - 1 do
      CheckEquals(Integer(M.MapValue(Src[I])), Integer(Dest[I]));
  finally
    M.Free;
    P.Free;
  end;
end;

//SEP

procedure TTestPalette.TestSliderRoundTrip;
var
  M: TColorMapping;
  O, R, S: Integer;
begin
  M := MappingFromSliders(250, 500, 444, True);
  CheckEquals(0.25, M.Offset, 1e-9);
  CheckTrue(M.IsInverted);
  MappingToSliders(M, O, R, S);
  CheckEquals(250, O);
  CheckEquals(500, R);
  CheckEquals(444, S);
end;

//SEP

procedure TTestPalette.TestSwapRedBlue;
begin
  CheckEquals(Integer($332211), Integer(SwapRedBlue($112233)));
end;

//SEP

procedure TTestPalette.TestBuiltInPalettes;
var
  I: Integer;
  P: TGradientPalette;
begin
  CheckTrue(BuiltInPaletteCount >= 5);
  for I := 0 to BuiltInPaletteCount - 1 do
  begin
    P := CreateBuiltInPalette(I);
    try
      CheckTrue(P.StopCount >= 2, P.Name);
      CheckTrue(P.Name <> '');
    finally
      P.Free;
    end;
  end;
end;

initialization
  RegisterTest(TTestPalette.Suite);

end.
```

Ajouter `Fractal.Palette in '..\src\Fractal.Palette.pas'` et `TestFractalPalette in 'TestFractalPalette.pas'` au
`.dpr`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalPalette.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Palette.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Palette.pas`**

```pascal
unit Fractal.Palette;

interface

uses
  SysUtils, Classes, Math, Fractal.Types;

const
  kLutSize = 4096;
  kRefIter = 1000.0;  // u = mu / kRefIter : les couleurs ne dépendent pas du nombre max d'itérations
  kSliderMax = 1000;
  kMinRepeats = 1.0;
  kMaxRepeats = 1000.0;
  kRepeatsDecades = 3;  // 10^0 .. 10^3
  kMinStretch = 0.2;
  kMaxStretch = 2.0;
  kInsideColor = $000000;
  kMaxStops = 1024;
  kMaxMapColors = 256;

type
  EPaletteError = class(Exception);

  TColorStop = record
    Position: Double;
    Color: Cardinal;  // $00RRGGBB
  end;

  TGradientPalette = class
  private
    FName: string;
    FStops: array of TColorStop;
    function InsertStop(const S: TColorStop): Integer;
  public
    constructor Create;
    procedure Assign(Source: TGradientPalette);
    procedure Clear;
    procedure SetDefault;
    function AddStop(APosition: Double; AColor: Cardinal): Integer;
    procedure DeleteStop(Index: Integer);
    function MoveStop(Index: Integer; APosition: Double): Integer;
    procedure SetStopColor(Index: Integer; AColor: Cardinal);
    function StopCount: Integer;
    function Stop(Index: Integer): TColorStop;
    function ColorAt(T: Double): Cardinal;
    procedure SaveToStrings(Lines: TStrings);
    procedure LoadFromStrings(Lines: TStrings);
    procedure LoadFromMap(Lines: TStrings);
    property Name: string read FName write FName;
  end;

  TColorMapping = record
    Offset: Double;
    Repeats: Double;
    Stretch: Double;
    IsInverted: Boolean;
  end;

  TColorMapper = class
  private
    FLut: array[0..kLutSize - 1] of Cardinal;
    FMapping: TColorMapping;
  public
    constructor Create(APalette: TGradientPalette; const AMapping: TColorMapping);
    function MapValue(Mu: Single): Cardinal;
    procedure MapRow(Src: PSingle; Dest: PCardinal; Count: Integer);
  end;

function DefaultColorMapping: TColorMapping;
function ClampColorMapping(const M: TColorMapping): TColorMapping;
function MappingFromSliders(Offset, Repeats, Stretch: Integer; IsInverted: Boolean): TColorMapping;
procedure MappingToSliders(const M: TColorMapping; out Offset, Repeats, Stretch: Integer);
function SwapRedBlue(C: Cardinal): Cardinal;
function BuiltInPaletteCount: Integer;
function CreateBuiltInPalette(Index: Integer): TGradientPalette;

implementation

const
  kDefaultRepeats = 25.0;
  kBuiltInCount = 5;
  kDefaultName = 'Sans nom';

//SEP

function LerpColor(A, B: Cardinal; F: Double): Cardinal;
var
  R, G, Bl: Integer;
begin
  R := Round(((A shr 16) and $FF) * (1 - F) + ((B shr 16) and $FF) * F);
  G := Round(((A shr 8) and $FF) * (1 - F) + ((B shr 8) and $FF) * F);
  Bl := Round((A and $FF) * (1 - F) + (B and $FF) * F);
  Result := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(Bl);
end;

//SEP

function MakeStop(APosition: Double; AColor: Cardinal): TColorStop;
begin
  Result.Position := EnsureRange(APosition, 0.0, 1.0);
  Result.Color := AColor and $FFFFFF;
end;

//SEP

constructor TGradientPalette.Create;
begin
  inherited Create;
  SetDefault;
end;

//SEP

procedure TGradientPalette.Assign(Source: TGradientPalette);
begin
  FName := Source.FName;
  FStops := Copy(Source.FStops);
end;

//SEP

procedure TGradientPalette.Clear;
begin
  SetLength(FStops, 0);
end;

//SEP

procedure TGradientPalette.SetDefault;
begin
  Clear;
  AddStop(0, $000000);
  AddStop(0.5, $FFFFFF);
end;

//SEP

function TGradientPalette.InsertStop(const S: TColorStop): Integer;
var
  I: Integer;
begin
  Result := Length(FStops);
  for I := 0 to High(FStops) do
    if FStops[I].Position > S.Position then
    begin
      Result := I;
      Break;
    end;
  SetLength(FStops, Length(FStops) + 1);
  for I := High(FStops) downto Result + 1 do
    FStops[I] := FStops[I - 1];
  FStops[Result] := S;
end;

//SEP

function TGradientPalette.AddStop(APosition: Double; AColor: Cardinal): Integer;
begin
  Result := InsertStop(MakeStop(APosition, AColor));
end;

//SEP

procedure TGradientPalette.DeleteStop(Index: Integer);
var
  I: Integer;
begin
  if (Index < 0) or (Index > High(FStops)) then
    Exit;
  for I := Index to High(FStops) - 1 do
    FStops[I] := FStops[I + 1];
  SetLength(FStops, Length(FStops) - 1);
end;

//SEP

function TGradientPalette.MoveStop(Index: Integer; APosition: Double): Integer;
var
  S: TColorStop;
begin
  S := FStops[Index];
  DeleteStop(Index);
  Result := InsertStop(MakeStop(APosition, S.Color));
end;

//SEP

procedure TGradientPalette.SetStopColor(Index: Integer; AColor: Cardinal);
begin
  FStops[Index].Color := AColor and $FFFFFF;
end;

//SEP

function TGradientPalette.StopCount: Integer;
begin
  Result := Length(FStops);
end;

//SEP

function TGradientPalette.Stop(Index: Integer): TColorStop;
begin
  Result := FStops[Index];
end;

//SEP

function TGradientPalette.ColorAt(T: Double): Cardinal;
var
  N, I: Integer;
  First, Last: TColorStop;
  Span, Local: Double;
begin
  N := Length(FStops);
  if N = 0 then
    Exit(0);
  if N = 1 then
    Exit(FStops[0].Color);
  T := T - Floor(T);
  First := FStops[0];
  Last := FStops[N - 1];
  if (T < First.Position) or (T >= Last.Position) then
  begin
    // segment qui reboucle du dernier point vers le premier
    Span := 1 - Last.Position + First.Position;
    if T >= Last.Position then
      Local := T - Last.Position
    else
      Local := T + 1 - Last.Position;
    if Span <= 0 then
      Exit(First.Color);
    Exit(LerpColor(Last.Color, First.Color, Local / Span));
  end;
  for I := 0 to N - 2 do
    if (T >= FStops[I].Position) and (T < FStops[I + 1].Position) then
    begin
      Span := FStops[I + 1].Position - FStops[I].Position;
      if Span <= 0 then
        Exit(FStops[I].Color);
      Exit(LerpColor(FStops[I].Color, FStops[I + 1].Color, (T - FStops[I].Position) / Span));
    end;
  Result := Last.Color;
end;

//SEP

procedure TGradientPalette.SaveToStrings(Lines: TStrings);
var
  I: Integer;
begin
  Lines.Add('Name=' + FName);
  Lines.Add('Count=' + IntToStr(Length(FStops)));
  for I := 0 to High(FStops) do
    Lines.Add(Format('Stop%d=%s,%s', [I, FloatToInvariant(FStops[I].Position), IntToHex(FStops[I].Color, 6)]));
end;

//SEP

procedure TGradientPalette.LoadFromStrings(Lines: TStrings);
var
  I, Count, P: Integer;
  S: string;
  Position: TFloat;
  Color: Integer;
begin
  FName := Lines.Values['Name'];
  Count := StrToIntDef(Lines.Values['Count'], kMaxStops);
  Clear;
  for I := 0 to Min(Count, kMaxStops) - 1 do
  begin
    S := Lines.Values['Stop' + IntToStr(I)];
    if S = '' then
      Break;
    P := Pos(',', S);
    if P = 0 then
      Continue;
    Position := InvariantToFloat(Copy(S, 1, P - 1), -1);
    Color := StrToIntDef('$' + Trim(Copy(S, P + 1, MaxInt)), -1);
    if (Position >= 0) and (Position <= 1) and (Color >= 0) and (Color <= $FFFFFF) then
      AddStop(Position, Cardinal(Color));
  end;
  if Length(FStops) = 0 then
    SetDefault;
end;

//SEP

function ReadInteger(const S: string; var P: Integer; out Value: Integer): Boolean;
var
  Start: Integer;
begin
  while (P <= Length(S)) and ((S[P] = ' ') or (S[P] = #9)) do
    Inc(P);
  Start := P;
  while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') do
    Inc(P);
  Result := (P > Start) and TryStrToInt(Copy(S, Start, P - Start), Value);
end;

//SEP

procedure TGradientPalette.LoadFromMap(Lines: TStrings);
var
  Colors: array of Cardinal;
  I, P, R, G, B, N: Integer;
begin
  SetLength(Colors, 0);
  for I := 0 to Lines.Count - 1 do
  begin
    if Length(Colors) >= kMaxMapColors then
      Break;
    P := 1;
    if ReadInteger(Lines[I], P, R) and ReadInteger(Lines[I], P, G) and ReadInteger(Lines[I], P, B)
      and (R <= 255) and (G <= 255) and (B <= 255) then
    begin
      N := Length(Colors);
      SetLength(Colors, N + 1);
      Colors[N] := (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);
    end;
  end;
  if Length(Colors) < 2 then
    raise EPaletteError.Create('Fichier .map invalide : moins de deux couleurs lisibles.');
  Clear;
  for I := 0 to High(Colors) do
    AddStop(I / Length(Colors), Colors[I]);
end;

//SEP

constructor TColorMapper.Create(APalette: TGradientPalette; const AMapping: TColorMapping);
var
  I: Integer;
begin
  inherited Create;
  FMapping := ClampColorMapping(AMapping);
  for I := 0 to kLutSize - 1 do
    FLut[I] := APalette.ColorAt(I / kLutSize);
end;

//SEP

function TColorMapper.MapValue(Mu: Single): Cardinal;
var
  U, T: Double;
  I: Integer;
begin
  if Mu < 0 then
    Exit(kInsideColor);
  U := Mu / kRefIter;
  if FMapping.Stretch <> 1 then
    U := Power(U, FMapping.Stretch);
  T := Frac(FMapping.Offset + FMapping.Repeats * U);
  if FMapping.IsInverted then
    T := 1 - T;
  I := EnsureRange(Trunc(T * kLutSize), 0, kLutSize - 1);
  Result := FLut[I];
end;

//SEP

procedure TColorMapper.MapRow(Src: PSingle; Dest: PCardinal; Count: Integer);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    Dest^ := MapValue(Src^);
    Inc(Src);
    Inc(Dest);
  end;
end;

//SEP

function DefaultColorMapping: TColorMapping;
begin
  Result.Offset := 0;
  Result.Repeats := kDefaultRepeats;
  Result.Stretch := 1;
  Result.IsInverted := False;
end;

//SEP

function ClampColorMapping(const M: TColorMapping): TColorMapping;
begin
  Result := M;
  if IsNan(Result.Offset) or IsInfinite(Result.Offset) then
    Result.Offset := 0;
  Result.Offset := Result.Offset - Floor(Result.Offset);
  if IsNan(Result.Repeats) then
    Result.Repeats := kDefaultRepeats;
  Result.Repeats := EnsureRange(Result.Repeats, kMinRepeats, kMaxRepeats);
  if IsNan(Result.Stretch) then
    Result.Stretch := 1;
  Result.Stretch := EnsureRange(Result.Stretch, kMinStretch, kMaxStretch);
end;

//SEP

function MappingFromSliders(Offset, Repeats, Stretch: Integer; IsInverted: Boolean): TColorMapping;
begin
  Result.Offset := Offset / kSliderMax;
  Result.Repeats := Power(10, kRepeatsDecades * Repeats / kSliderMax);
  Result.Stretch := kMinStretch + (kMaxStretch - kMinStretch) * Stretch / kSliderMax;
  Result.IsInverted := IsInverted;
  Result := ClampColorMapping(Result);
end;

//SEP

procedure MappingToSliders(const M: TColorMapping; out Offset, Repeats, Stretch: Integer);
begin
  Offset := Round(M.Offset * kSliderMax);
  Repeats := Round(Log10(M.Repeats) / kRepeatsDecades * kSliderMax);
  Stretch := Round((M.Stretch - kMinStretch) / (kMaxStretch - kMinStretch) * kSliderMax);
end;

//SEP

function SwapRedBlue(C: Cardinal): Cardinal;
begin
  Result := ((C and $FF) shl 16) or (C and $FF00) or ((C shr 16) and $FF);
end;

//SEP

function BuiltInPaletteCount: Integer;
begin
  Result := kBuiltInCount;
end;

//SEP

function CreateBuiltInPalette(Index: Integer): TGradientPalette;
begin
  Result := TGradientPalette.Create;
  Result.Clear;
  case Index of
    0:
      begin
        Result.Name := 'Classique';
        Result.AddStop(0, $000764);
        Result.AddStop(0.16, $206BCB);
        Result.AddStop(0.42, $EDFFFF);
        Result.AddStop(0.6425, $FFAA00);
        Result.AddStop(0.8575, $000200);
      end;
    1:
      begin
        Result.Name := 'Feu';
        Result.AddStop(0, $000000);
        Result.AddStop(0.25, $800000);
        Result.AddStop(0.5, $FF4000);
        Result.AddStop(0.75, $FFC000);
        Result.AddStop(0.9, $FFFFA0);
      end;
    2:
      begin
        Result.Name := 'Océan';
        Result.AddStop(0, $000020);
        Result.AddStop(0.3, $0050A0);
        Result.AddStop(0.6, $40C0E0);
        Result.AddStop(0.8, $E0FFFF);
      end;
    3:
      begin
        Result.Name := 'Arc-en-ciel';
        Result.AddStop(0, $FF0000);
        Result.AddStop(1 / 6, $FFFF00);
        Result.AddStop(2 / 6, $00FF00);
        Result.AddStop(3 / 6, $00FFFF);
        Result.AddStop(4 / 6, $0000FF);
        Result.AddStop(5 / 6, $FF00FF);
      end;
  else
    Result.Name := 'Gris';
    Result.AddStop(0, $000000);
    Result.AddStop(0.5, $FFFFFF);
  end;
end;

end.
```

Run : `tools/normalize.sh src/Fractal.Palette.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (47 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Palette.pas tests
git commit -m "Palettes en dégradés, import .map, conversion valeurs-couleurs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6 : `Fractal.Png`

**Files :**
- Create : `src/Fractal.Png.pas`, `tests/TestUtils.pas`, `tests/TestFractalPng.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `SwapRedBlue` (5, dans les tests seulement).
- Produces : `TPngWriter` (`Create(AStream: TStream; AWidth, AHeight: Integer)`, `AddText(const Keyword:
  AnsiString; const Text: RawByteString)` (avant la première ligne), `WriteRow(Rgb: PByte)` (Width × 3 octets
  R, G, B), `Finish` (lève `EPngError` s'il manque des lignes)), `EPngError`, `PngCrc32(Data: PByte; Size:
  Integer): Cardinal`, `ReadPngText(const FileName: string; const Keyword: AnsiString; out Text:
  RawByteString): Boolean`, constante `kLocationKeyword = 'FractalLocation'`. `TestTempFolder` dans
  `tests/TestUtils.pas` : `function TestTempFolder: string` (se termine par `\`, créé si besoin).
- Le texte d'un lieu est stocké en UTF-8 dans un bloc `tEXt` : on l'encode avec `UTF8Encode` et on le relit
  avec `UTF8ToString`.

- [ ] **Step 1 : écrire les tests**

`tests/TestUtils.pas` :

```pascal
unit TestUtils;

interface

function TestTempFolder: string;

implementation

uses
  Windows, SysUtils;

//SEP

function TestTempFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  GetTempPath(MAX_PATH, Buffer);
  Result := IncludeTrailingPathDelimiter(Buffer) + 'FractalesTests\';
  ForceDirectories(Result);
end;

end.
```

`tests/TestFractalPng.pas` :

```pascal
unit TestFractalPng;

interface

uses
  Classes, SysUtils, Graphics, pngimage, TestFramework, Fractal.Palette, Fractal.Png, TestUtils;

type
  TTestPng = class(TTestCase)
  private
    function PixelColor(X, Y: Integer): Cardinal;
    procedure WritePng(const FileName: string; W, H: Integer; const Text: RawByteString);
    procedure CheckPixels(const FileName: string; W, H, Stride: Integer);
  published
    procedure TestCrcOfIend;
    procedure TestSmallImageDecodes;
    procedure TestLargeImageDecodes;
    procedure TestTextRoundTrip;
    procedure TestMissingKeywordReturnsFalse;
    procedure TestNonPngReturnsFalse;
    procedure TestIncompleteImageRaises;
  end;

implementation

//SEP

function TTestPng.PixelColor(X, Y: Integer): Cardinal;
begin
  // valeurs pseudo-aléatoires peu compressibles : force plusieurs blocs IDAT
  Result := (Cardinal(X) * 73856093) xor (Cardinal(Y) * 19349663);
  Result := (Result * 2654435761) and $FFFFFF;
end;

//SEP

procedure TTestPng.WritePng(const FileName: string; W, H: Integer; const Text: RawByteString);
var
  Stream: TFileStream;
  Writer: TPngWriter;
  Row: array of Byte;
  X, Y: Integer;
  C: Cardinal;
begin
  SetLength(Row, W * 3);
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Writer := TPngWriter.Create(Stream, W, H);
    try
      if Text <> '' then
        Writer.AddText(kLocationKeyword, Text);
      for Y := 0 to H - 1 do
      begin
        for X := 0 to W - 1 do
        begin
          C := PixelColor(X, Y);
          Row[X * 3] := (C shr 16) and $FF;
          Row[X * 3 + 1] := (C shr 8) and $FF;
          Row[X * 3 + 2] := C and $FF;
        end;
        Writer.WriteRow(@Row[0]);
      end;
      Writer.Finish;
    finally
      Writer.Free;
    end;
  finally
    Stream.Free;
  end;
end;

//SEP

procedure TTestPng.CheckPixels(const FileName: string; W, H, Stride: Integer);
var
  Png: TPngImage;
  X, Y: Integer;
begin
  Png := TPngImage.Create;
  try
    Png.LoadFromFile(FileName);
    CheckEquals(W, Png.Width);
    CheckEquals(H, Png.Height);
    Y := 0;
    while Y < H do
    begin
      X := 0;
      while X < W do
      begin
        CheckEquals(Integer(SwapRedBlue(PixelColor(X, Y))), Integer(Png.Pixels[X, Y]), Format('(%d, %d)', [X, Y]));
        Inc(X, Stride);
      end;
      Inc(Y, Stride);
    end;
  finally
    Png.Free;
  end;
end;

//SEP

procedure TTestPng.TestCrcOfIend;
var
  S: AnsiString;
begin
  S := 'IEND';
  CheckEquals(Integer($AE426082), Integer(PngCrc32(@S[1], 4)));
end;

//SEP

procedure TTestPng.TestSmallImageDecodes;
var
  FileName: string;
begin
  FileName := TestTempFolder + 'small.png';
  WritePng(FileName, 4, 3, 'abc');
  CheckPixels(FileName, 4, 3, 1);
end;

//SEP

procedure TTestPng.TestLargeImageDecodes;
var
  FileName: string;
begin
  FileName := TestTempFolder + 'large.png';
  WritePng(FileName, 300, 400, '');
  CheckPixels(FileName, 300, 400, 37);
end;

//SEP

procedure TTestPng.TestTextRoundTrip;
var
  FileName: string;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'text.png';
  WritePng(FileName, 4, 3, UTF8Encode('Précédent=1'));
  CheckTrue(ReadPngText(FileName, kLocationKeyword, Text));
  CheckEquals('Précédent=1', UTF8ToString(Text));
end;

//SEP

procedure TTestPng.TestMissingKeywordReturnsFalse;
var
  FileName: string;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'text.png';
  WritePng(FileName, 4, 3, 'abc');
  CheckFalse(ReadPngText(FileName, 'Autre', Text));
end;

//SEP

procedure TTestPng.TestNonPngReturnsFalse;
var
  FileName: string;
  L: TStringList;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'pas-un-png.png';
  L := TStringList.Create;
  try
    L.Add('bonjour');
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
  CheckFalse(ReadPngText(FileName, kLocationKeyword, Text));
  CheckFalse(ReadPngText(TestTempFolder + 'inexistant.png', kLocationKeyword, Text));
end;

//SEP

procedure TTestPng.TestIncompleteImageRaises;
var
  Stream: TMemoryStream;
  Writer: TPngWriter;
  Row: array[0..11] of Byte;
  IsRaised: Boolean;
begin
  FillChar(Row, SizeOf(Row), 0);
  Stream := TMemoryStream.Create;
  Writer := TPngWriter.Create(Stream, 4, 3);
  try
    Writer.WriteRow(@Row[0]);
    IsRaised := False;
    try
      Writer.Finish;
    except
      on EPngError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    Writer.Free;
    Stream.Free;
  end;
end;

initialization
  RegisterTest(TTestPng.Suite);

end.
```

Ajouter au `.dpr` : `Fractal.Png in '..\src\Fractal.Png.pas'`, `TestUtils in 'TestUtils.pas'`,
`TestFractalPng in 'TestFractalPng.pas'`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestUtils.pas tests/TestFractalPng.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Png.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Png.pas`**

```pascal
unit Fractal.Png;

interface

uses
  SysUtils, Classes, ZLib;

const
  kLocationKeyword = 'FractalLocation';

type
  EPngError = class(Exception);

  // Écrivain PNG en flux (RVB 8 bits, sans entrelacement) : les lignes compressées partent dans des blocs
  // IDAT au fur et à mesure, l'image complète n'est jamais en mémoire.
  TPngWriter = class
  private
    FStream: TStream;
    FWidth: Integer;
    FHeight: Integer;
    FRowsWritten: Integer;
    FPending: TMemoryStream;
    FSink: TStream;
    FZip: TZCompressionStream;
    FIsFinished: Boolean;
    procedure WriteChunk(const ChunkType: AnsiString; Data: Pointer; Size: Integer);
    procedure FlushPending(IsForced: Boolean);
  public
    constructor Create(AStream: TStream; AWidth, AHeight: Integer);
    destructor Destroy; override;
    procedure AddText(const Keyword: AnsiString; const Text: RawByteString);
    procedure WriteRow(Rgb: PByte);
    procedure Finish;
  end;

function PngCrc32(Data: PByte; Size: Integer): Cardinal;
function ReadPngText(const FileName: string; const Keyword: AnsiString; out Text: RawByteString): Boolean;

implementation

const
  kPngSignature: array[0..7] of Byte = (137, 80, 78, 71, 13, 10, 26, 10);
  kIdatFlushSize = 65536;
  kCrcPolynomial = $EDB88320;
  kCrcInit = $FFFFFFFF;

type
  // Puits pour TZCompressionStream : il exige un flux dont la position avance en même temps que les
  // écritures. Les octets réels vont dans le tampon FTarget, vidé à chaque bloc IDAT.
  TPendingSink = class(TStream)
  private
    FTarget: TMemoryStream;
    FPosition: Int64;
  public
    constructor Create(ATarget: TMemoryStream);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

var
  CrcTable: array[0..255] of Cardinal;

//SEP

procedure BuildCrcTable;
var
  N, K: Integer;
  C: Cardinal;
begin
  for N := 0 to 255 do
  begin
    C := N;
    for K := 0 to 7 do
      if C and 1 <> 0 then
        C := kCrcPolynomial xor (C shr 1)
      else
        C := C shr 1;
    CrcTable[N] := C;
  end;
end;

//SEP

function UpdateCrc(Crc: Cardinal; Data: PByte; Size: Integer): Cardinal;
var
  I: Integer;
begin
  Result := Crc;
  for I := 0 to Size - 1 do
  begin
    Result := CrcTable[(Result xor Data^) and $FF] xor (Result shr 8);
    Inc(Data);
  end;
end;

//SEP

function PngCrc32(Data: PByte; Size: Integer): Cardinal;
begin
  Result := UpdateCrc(kCrcInit, Data, Size) xor kCrcInit;
end;

//SEP

procedure WriteBigEndian(Stream: TStream; Value: Cardinal);
var
  B: array[0..3] of Byte;
begin
  B[0] := Byte(Value shr 24);
  B[1] := Byte(Value shr 16);
  B[2] := Byte(Value shr 8);
  B[3] := Byte(Value);
  Stream.WriteBuffer(B, 4);
end;

//SEP

function ReadBigEndian(Stream: TStream): Cardinal;
var
  B: array[0..3] of Byte;
begin
  Stream.ReadBuffer(B, 4);
  Result := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or (Cardinal(B[2]) shl 8) or B[3];
end;

//SEP

constructor TPendingSink.Create(ATarget: TMemoryStream);
begin
  inherited Create;
  FTarget := ATarget;
end;

//SEP

function TPendingSink.Read(var Buffer; Count: Longint): Longint;
begin
  raise EPngError.Create('Flux PNG en écriture seule');
end;

//SEP

function TPendingSink.Write(const Buffer; Count: Longint): Longint;
begin
  FTarget.Seek(0, soFromEnd);
  FTarget.WriteBuffer(Buffer, Count);
  Inc(FPosition, Count);
  Result := Count;
end;

//SEP

function TPendingSink.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  NewPosition: Int64;
begin
  case Origin of
    soBeginning:
      NewPosition := Offset;
  else
    NewPosition := FPosition + Offset;
  end;
  if NewPosition <> FPosition then
    raise EPngError.Create('Flux PNG non positionnable');
  Result := FPosition;
end;

//SEP

constructor TPngWriter.Create(AStream: TStream; AWidth, AHeight: Integer);
var
  Header: array[0..12] of Byte;
begin
  inherited Create;
  if (AWidth <= 0) or (AHeight <= 0) then
    raise EPngError.CreateFmt('Dimensions PNG invalides : %d x %d', [AWidth, AHeight]);
  FStream := AStream;
  FWidth := AWidth;
  FHeight := AHeight;
  FStream.WriteBuffer(kPngSignature, SizeOf(kPngSignature));
  Header[0] := Byte(AWidth shr 24);
  Header[1] := Byte(AWidth shr 16);
  Header[2] := Byte(AWidth shr 8);
  Header[3] := Byte(AWidth);
  Header[4] := Byte(AHeight shr 24);
  Header[5] := Byte(AHeight shr 16);
  Header[6] := Byte(AHeight shr 8);
  Header[7] := Byte(AHeight);
  Header[8] := 8;   // 8 bits par canal
  Header[9] := 2;   // RVB
  Header[10] := 0;  // compression deflate
  Header[11] := 0;  // filtrage standard
  Header[12] := 0;  // sans entrelacement
  WriteChunk('IHDR', @Header, SizeOf(Header));
  FPending := TMemoryStream.Create;
  FSink := TPendingSink.Create(FPending);
  FZip := TZCompressionStream.Create(FSink, zcDefault);
end;

//SEP

destructor TPngWriter.Destroy;
begin
  FZip.Free;
  FSink.Free;
  FPending.Free;
  inherited Destroy;
end;

//SEP

procedure TPngWriter.WriteChunk(const ChunkType: AnsiString; Data: Pointer; Size: Integer);
var
  Crc: Cardinal;
begin
  WriteBigEndian(FStream, Size);
  FStream.WriteBuffer(ChunkType[1], 4);
  if Size > 0 then
    FStream.WriteBuffer(Data^, Size);
  Crc := UpdateCrc(kCrcInit, @ChunkType[1], 4);
  if Size > 0 then
    Crc := UpdateCrc(Crc, Data, Size);
  WriteBigEndian(FStream, Crc xor kCrcInit);
end;

//SEP

procedure TPngWriter.FlushPending(IsForced: Boolean);
begin
  if (FPending.Size >= kIdatFlushSize) or (IsForced and (FPending.Size > 0)) then
  begin
    WriteChunk('IDAT', FPending.Memory, FPending.Size);
    FPending.Clear;
  end;
end;

//SEP

procedure TPngWriter.AddText(const Keyword: AnsiString; const Text: RawByteString);
var
  Data: TMemoryStream;
  Zero: Byte;
begin
  if FRowsWritten > 0 then
    raise EPngError.Create('Le texte PNG doit précéder les lignes de l''image');
  Data := TMemoryStream.Create;
  try
    Data.WriteBuffer(Keyword[1], Length(Keyword));
    Zero := 0;
    Data.WriteBuffer(Zero, 1);
    if Length(Text) > 0 then
      Data.WriteBuffer(Text[1], Length(Text));
    WriteChunk('tEXt', Data.Memory, Data.Size);
  finally
    Data.Free;
  end;
end;

//SEP

procedure TPngWriter.WriteRow(Rgb: PByte);
var
  Filter: Byte;
begin
  if FIsFinished or (FRowsWritten >= FHeight) then
    raise EPngError.Create('Trop de lignes pour l''image PNG');
  Filter := 0;
  FZip.WriteBuffer(Filter, 1);
  FZip.WriteBuffer(Rgb^, FWidth * 3);
  Inc(FRowsWritten);
  FlushPending(False);
end;

//SEP

procedure TPngWriter.Finish;
begin
  if FRowsWritten <> FHeight then
    raise EPngError.CreateFmt('Image PNG incomplète : %d lignes sur %d', [FRowsWritten, FHeight]);
  FreeAndNil(FZip);  // termine le flux deflate dans FPending
  FlushPending(True);
  WriteChunk('IEND', nil, 0);
  FIsFinished := True;
end;

//SEP

function ReadPngText(const FileName: string; const Keyword: AnsiString; out Text: RawByteString): Boolean;
var
  Stream: TFileStream;
  Signature: array[0..7] of Byte;
  ChunkType: array[0..3] of AnsiChar;
  Len: Cardinal;
  Data: RawByteString;
  I, Separator: Integer;
begin
  Result := False;
  Text := '';
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  except
    on EFOpenError do
      Exit;
  end;
  try
    if (Stream.Read(Signature, 8) <> 8) or not CompareMem(@Signature, @kPngSignature, 8) then
      Exit;
    while Stream.Position + 8 <= Stream.Size do
    begin
      Len := ReadBigEndian(Stream);
      Stream.ReadBuffer(ChunkType, 4);
      if Int64(Len) + 4 > Stream.Size - Stream.Position then
        Exit;
      if CompareMem(@ChunkType, PAnsiChar('IEND'), 4) then
        Exit;
      if CompareMem(@ChunkType, PAnsiChar('tEXt'), 4) then
      begin
        SetLength(Data, Len);
        if Len > 0 then
          Stream.ReadBuffer(Data[1], Len);
        Stream.Seek(4, soCurrent);
        Separator := 0;
        for I := 1 to Length(Data) do
          if Data[I] = #0 then
          begin
            Separator := I;
            Break;
          end;
        if (Separator - 1 = Length(Keyword)) and (Length(Keyword) > 0)
          and CompareMem(@Data[1], @Keyword[1], Length(Keyword)) then
        begin
          Text := Copy(Data, Separator + 1, MaxInt);
          Exit(True);
        end;
      end
      else
        Stream.Seek(Int64(Len) + 4, soCurrent);
    end;
  finally
    Stream.Free;
  end;
end;

initialization
  BuildCrcTable;

end.
```

Run : `tools/normalize.sh src/Fractal.Png.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (54 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Png.pas tests
git commit -m "Écriture PNG en flux avec bloc texte

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7 : `Fractal.Persistence`

**Files :**
- Create : `src/Fractal.Persistence.pas`, `tests/TestFractalPersistence.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `TViewport`, `FloatToInvariant`, `InvariantToFloat` (1) ; `TFractalFormula`, `FindFormulaClass`,
  `kMinMaxIter`, `kMaxMaxIter`, `kDefaultMaxIter` (2) ; `TGradientPalette`, `TColorMapping`,
  `DefaultColorMapping`, `ClampColorMapping` (5).
- Produces : `EFractalFileError` ; `TFractalLocation` (`CaptureFrom(Formula; const V; AIsAutoIter; APalette;
  const AMapping)`, `CreateFormula: TFractalFormula` (lève `EFractalFileError` si inconnue), `ApplyTo(var V:
  TViewport)` (centre et largeur, garde la taille en pixels), `SaveToText: string`, `LoadFromText(const S)`,
  `SaveToFile`, `LoadFromFile` (toute erreur devient `EFractalFileError`), propriétés en lecture `FormulaName`,
  `Params` (TStringList nom=valeur), `CenterX`, `CenterY`, `Width`, `MaxIter`, `IsAutoIter`, `Mapping`,
  `Palette`) ; `TFavoriteStore` (`Create(const AFolder)`, `List(Names: TStrings)`, `Save(const AName; Location):
  string` (renvoie le nom réellement stocké), `Load(const AName; Location)`, `Delete(const AName)`,
  `FileNameOf(const AName): string`, propriété `Folder`) ; `SanitizeFileName`, `AppDataFolder`,
  `PaletteFolder`, `FavoritesFolder` (chemins terminés par `\`, créés si besoin).

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalPersistence.pas` :

```pascal
unit TestFractalPersistence;

interface

uses
  Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Persistence,
  TestUtils;

type
  TTestPersistence = class(TTestCase)
  private
    function SampleLocation: TFractalLocation;
    procedure CheckRaisesFileError(const Text: string);
  published
    procedure TestTextRoundTrip;
    procedure TestCreateFormulaRestoresParams;
    procedure TestUnknownFormulaRaises;
    procedure TestMissingValuesUseDefaults;
    procedure TestOutOfRangeValuesAreClamped;
    procedure TestTextWithoutSectionRaises;
    procedure TestBinaryFileRaisesFileError;
    procedure TestNumbersAreInvariant;
    procedure TestFavoriteStore;
    procedure TestSanitizeFileName;
  end;

implementation

const
  kSampleX = -0.7436438870371587;
  kSampleY = 0.1318259042053119;

//SEP

function TTestPersistence.SampleLocation: TFractalLocation;
var
  F: TMultibrotFormula;
  P: TGradientPalette;
  M: TColorMapping;
begin
  F := TMultibrotFormula.Create;
  P := CreateBuiltInPalette(1);
  try
    F.SetParam(0, 4.5);
    F.MaxIter := 3000;
    M := DefaultColorMapping;
    M.Offset := 0.3;
    M.Repeats := 40;
    M.Stretch := 0.8;
    M.IsInverted := True;
    Result := TFractalLocation.Create;
    Result.CaptureFrom(F, MakeViewport(kSampleX, kSampleY, 1.5e-10, 800, 600), False, P, M);
  finally
    P.Free;
    F.Free;
  end;
end;

//SEP

procedure TTestPersistence.CheckRaisesFileError(const Text: string);
var
  L: TFractalLocation;
  IsRaised: Boolean;
begin
  L := TFractalLocation.Create;
  try
    IsRaised := False;
    try
      L.LoadFromText(Text);
    except
      on EFractalFileError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised, Text);
  finally
    L.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestTextRoundTrip;
var
  A, B: TFractalLocation;
begin
  A := SampleLocation;
  B := TFractalLocation.Create;
  try
    B.LoadFromText(A.SaveToText);
    CheckEquals('Multibrot', B.FormulaName);
    CheckEquals(kSampleX, B.CenterX, 1e-17);
    CheckEquals(kSampleY, B.CenterY, 1e-17);
    CheckEquals(1.5e-10, B.Width, 1e-26);
    CheckEquals(3000, B.MaxIter);
    CheckFalse(B.IsAutoIter);
    CheckEquals(0.3, B.Mapping.Offset, 1e-9);
    CheckEquals(40.0, B.Mapping.Repeats, 1e-9);
    CheckEquals(0.8, B.Mapping.Stretch, 1e-9);
    CheckTrue(B.Mapping.IsInverted);
    CheckEquals('Feu', B.Palette.Name);
    CheckEquals(A.Palette.StopCount, B.Palette.StopCount);
    CheckEquals(Integer(A.Palette.Stop(2).Color), Integer(B.Palette.Stop(2).Color));
  finally
    B.Free;
    A.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestCreateFormulaRestoresParams;
var
  A: TFractalLocation;
  F: TFractalFormula;
begin
  A := SampleLocation;
  try
    F := A.CreateFormula;
    try
      CheckTrue(F is TMultibrotFormula);
      CheckEquals(4.5, F.GetParam(0), 1e-12);
      CheckEquals(3000, F.MaxIter);
    finally
      F.Free;
    end;
  finally
    A.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestUnknownFormulaRaises;
begin
  CheckRaisesFileError('[Fractal]'#13#10'Formula=Inexistante');
end;

//SEP

procedure TTestPersistence.TestMissingValuesUseDefaults;
var
  L: TFractalLocation;
  F: TFractalFormula;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Julia');
    CheckEquals(TJuliaFormula.DefaultCenterX, L.CenterX, 0);
    CheckEquals(TJuliaFormula.DefaultWidth, L.Width, 0);
    CheckEquals(kDefaultMaxIter, L.MaxIter);
    CheckTrue(L.IsAutoIter);
    CheckTrue(L.Palette.StopCount >= 2);
    F := L.CreateFormula;
    try
      CheckEquals(-0.8, F.GetParam(0), 1e-12);
    finally
      F.Free;
    end;
  finally
    L.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestOutOfRangeValuesAreClamped;
var
  L: TFractalLocation;
begin
  L := TFractalLocation.Create;
  try
    L.LoadFromText('[Fractal]'#13#10'Formula=Mandelbrot'#13#10'MaxIter=5'#13#10'Width=-3'#13#10 +
      '[Colors]'#13#10'Repeats=99999'#13#10'Stretch=0');
    CheckEquals(kMinMaxIter, L.MaxIter);
    CheckEquals(TMandelbrotFormula.DefaultWidth, L.Width, 0);
    CheckEquals(kMaxRepeats, L.Mapping.Repeats, 0);
    CheckEquals(kMinStretch, L.Mapping.Stretch, 0);
  finally
    L.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestTextWithoutSectionRaises;
begin
  CheckRaisesFileError('bonjour');
end;

//SEP

procedure TTestPersistence.TestBinaryFileRaisesFileError;
var
  FileName: string;
  Stream: TFileStream;
  Bytes: array[0..1023] of Byte;
  I: Integer;
  L: TFractalLocation;
  IsRaised: Boolean;
begin
  FileName := TestTempFolder + 'binaire.frac';
  for I := 0 to High(Bytes) do
    Bytes[I] := Byte(I * 7 + 3);
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Bytes, SizeOf(Bytes));
  finally
    Stream.Free;
  end;
  L := TFractalLocation.Create;
  try
    IsRaised := False;
    try
      L.LoadFromFile(FileName);
    except
      on EFractalFileError do
        IsRaised := True;
    end;
    CheckTrue(IsRaised);
  finally
    L.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestNumbersAreInvariant;
var
  A: TFractalLocation;
begin
  A := SampleLocation;
  try
    CheckTrue(Pos('CenterX=-0.7436438870', A.SaveToText) > 0);
  finally
    A.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestFavoriteStore;
var
  Folder, Stored: string;
  Store: TFavoriteStore;
  A, B: TFractalLocation;
  Names: TStringList;
begin
  Folder := TestTempFolder + 'Favoris\';
  if FileExists(Folder + 'Spirale_ double.frac') then
    DeleteFile(Folder + 'Spirale_ double.frac');
  Store := TFavoriteStore.Create(Folder);
  A := SampleLocation;
  B := TFractalLocation.Create;
  Names := TStringList.Create;
  try
    Stored := Store.Save('Spirale: double', A);
    CheckEquals('Spirale_ double', Stored);
    Store.List(Names);
    CheckTrue(Names.IndexOf(Stored) >= 0);
    Store.Load(Stored, B);
    CheckEquals(kSampleX, B.CenterX, 1e-17);
    Store.Delete(Stored);
    Store.List(Names);
    CheckEquals(-1, Names.IndexOf(Stored));
  finally
    Names.Free;
    B.Free;
    A.Free;
    Store.Free;
  end;
end;

//SEP

procedure TTestPersistence.TestSanitizeFileName;
begin
  CheckEquals('a_b_c_d_e_f_g_h_i_j', SanitizeFileName('a/b\c:d*e?f"g<h>i|j'));
  CheckEquals('Sans nom', SanitizeFileName('   '));
end;

initialization
  RegisterTest(TTestPersistence.Suite);

end.
```

Ajouter `Fractal.Persistence in '..\src\Fractal.Persistence.pas'` et
`TestFractalPersistence in 'TestFractalPersistence.pas'` au `.dpr`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalPersistence.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Persistence.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Persistence.pas`**

```pascal
unit Fractal.Persistence;

interface

uses
  Windows, SysUtils, Classes, IniFiles, Math, ShlObj, Fractal.Types, Fractal.Formulas, Fractal.Palette;

const
  kLocationExtension = '.frac';

type
  EFractalFileError = class(Exception);

  // Un « lieu » : tout ce qu'il faut pour retrouver exactement une vue.
  TFractalLocation = class
  private
    FFormulaName: string;
    FParams: TStringList;
    FCenterX: TFloat;
    FCenterY: TFloat;
    FWidth: TFloat;
    FMaxIter: Integer;
    FIsAutoIter: Boolean;
    FMapping: TColorMapping;
    FPalette: TGradientPalette;
  public
    constructor Create;
    destructor Destroy; override;
    procedure CaptureFrom(Formula: TFractalFormula; const V: TViewport; AIsAutoIter: Boolean;
      APalette: TGradientPalette; const AMapping: TColorMapping);
    function CreateFormula: TFractalFormula;
    procedure ApplyTo(var V: TViewport);
    function SaveToText: string;
    procedure LoadFromText(const AText: string);
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);
    property FormulaName: string read FFormulaName;
    property Params: TStringList read FParams;
    property CenterX: TFloat read FCenterX;
    property CenterY: TFloat read FCenterY;
    property Width: TFloat read FWidth;
    property MaxIter: Integer read FMaxIter;
    property IsAutoIter: Boolean read FIsAutoIter;
    property Mapping: TColorMapping read FMapping;
    property Palette: TGradientPalette read FPalette;
  end;

  // Un favori = un fichier .frac dans un dossier.
  TFavoriteStore = class
  private
    FFolder: string;
  public
    constructor Create(const AFolder: string);
    procedure List(Names: TStrings);
    function Save(const AName: string; Location: TFractalLocation): string;
    procedure Load(const AName: string; Location: TFractalLocation);
    procedure Delete(const AName: string);
    function FileNameOf(const AName: string): string;
    property Folder: string read FFolder;
  end;

function SanitizeFileName(const S: string): string;
function AppDataFolder: string;
function PaletteFolder: string;
function FavoritesFolder: string;

implementation

const
  kSectionFractal = 'Fractal';
  kSectionParams = 'Params';
  kSectionColors = 'Colors';
  kSectionPalette = 'Palette';
  kDefaultFormula = 'Mandelbrot';
  kFormatVersion = 1;
  kInvalidFileChars = '\/:*?"<>|';
  kUnnamed = 'Sans nom';
  kNoLocationMessage = 'Ce fichier ne contient pas de lieu fractal.';

//SEP

function BoolTo01(Value: Boolean): string;
begin
  if Value then
    Result := '1'
  else
    Result := '0';
end;

//SEP

constructor TFractalLocation.Create;
begin
  inherited Create;
  FParams := TStringList.Create;
  FPalette := TGradientPalette.Create;
  FFormulaName := kDefaultFormula;
  FCenterX := TMandelbrotFormula.DefaultCenterX;
  FCenterY := TMandelbrotFormula.DefaultCenterY;
  FWidth := TMandelbrotFormula.DefaultWidth;
  FMaxIter := kDefaultMaxIter;
  FIsAutoIter := True;
  FMapping := DefaultColorMapping;
end;

//SEP

destructor TFractalLocation.Destroy;
begin
  FPalette.Free;
  FParams.Free;
  inherited Destroy;
end;

//SEP

procedure TFractalLocation.CaptureFrom(Formula: TFractalFormula; const V: TViewport; AIsAutoIter: Boolean;
  APalette: TGradientPalette; const AMapping: TColorMapping);
var
  I: Integer;
begin
  FFormulaName := Formula.FormulaName;
  FParams.Clear;
  for I := 0 to Formula.ParamCount - 1 do
    FParams.Add(Formula.ParamInfo(I).Name + '=' + FloatToInvariant(Formula.GetParam(I)));
  FCenterX := V.CenterX;
  FCenterY := V.CenterY;
  FWidth := V.Width;
  FMaxIter := Formula.MaxIter;
  FIsAutoIter := AIsAutoIter;
  FPalette.Assign(APalette);
  FMapping := AMapping;
end;

//SEP

function TFractalLocation.CreateFormula: TFractalFormula;
var
  FormulaClass: TFractalFormulaClass;
  I, Index: Integer;
begin
  FormulaClass := FindFormulaClass(FFormulaName);
  if FormulaClass = nil then
    raise EFractalFileError.CreateFmt('Formule inconnue : %s', [FFormulaName]);
  Result := FormulaClass.Create;
  try
    Result.MaxIter := FMaxIter;
    for I := 0 to FParams.Count - 1 do
    begin
      Index := Result.IndexOfParam(FParams.Names[I]);
      if Index >= 0 then
        Result.SetParam(Index, InvariantToFloat(FParams.ValueFromIndex[I], Result.GetParam(Index)));
    end;
  except
    Result.Free;
    raise;
  end;
end;

//SEP

procedure TFractalLocation.ApplyTo(var V: TViewport);
begin
  V.CenterX := FCenterX;
  V.CenterY := FCenterY;
  V.Width := FWidth;
end;

//SEP

function TFractalLocation.SaveToText: string;
var
  L, PaletteLines: TStringList;
begin
  L := TStringList.Create;
  PaletteLines := TStringList.Create;
  try
    L.Add('[' + kSectionFractal + ']');
    L.Add('Version=' + IntToStr(kFormatVersion));
    L.Add('Formula=' + FFormulaName);
    L.Add('CenterX=' + FloatToInvariant(FCenterX));
    L.Add('CenterY=' + FloatToInvariant(FCenterY));
    L.Add('Width=' + FloatToInvariant(FWidth));
    L.Add('MaxIter=' + IntToStr(FMaxIter));
    L.Add('AutoIter=' + BoolTo01(FIsAutoIter));
    L.Add('');
    L.Add('[' + kSectionParams + ']');
    L.AddStrings(FParams);
    L.Add('');
    L.Add('[' + kSectionColors + ']');
    L.Add('Offset=' + FloatToInvariant(FMapping.Offset));
    L.Add('Repeats=' + FloatToInvariant(FMapping.Repeats));
    L.Add('Stretch=' + FloatToInvariant(FMapping.Stretch));
    L.Add('Invert=' + BoolTo01(FMapping.IsInverted));
    L.Add('');
    L.Add('[' + kSectionPalette + ']');
    FPalette.SaveToStrings(PaletteLines);
    L.AddStrings(PaletteLines);
    Result := L.Text;
  finally
    PaletteLines.Free;
    L.Free;
  end;
end;

//SEP

procedure TFractalLocation.LoadFromText(const AText: string);
var
  Ini: TMemIniFile;
  Lines: TStringList;
  FormulaClass: TFractalFormulaClass;
  Name: string;
begin
  Ini := TMemIniFile.Create('');
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    Ini.SetStrings(Lines);
    if not Ini.SectionExists(kSectionFractal) then
      raise EFractalFileError.Create(kNoLocationMessage);
    Name := Ini.ReadString(kSectionFractal, 'Formula', kDefaultFormula);
    FormulaClass := FindFormulaClass(Name);
    if FormulaClass = nil then
      raise EFractalFileError.CreateFmt('Formule inconnue : %s', [Name]);
    FFormulaName := FormulaClass.FormulaName;
    FCenterX := InvariantToFloat(Ini.ReadString(kSectionFractal, 'CenterX', ''), FormulaClass.DefaultCenterX);
    FCenterY := InvariantToFloat(Ini.ReadString(kSectionFractal, 'CenterY', ''), FormulaClass.DefaultCenterY);
    FWidth := InvariantToFloat(Ini.ReadString(kSectionFractal, 'Width', ''), FormulaClass.DefaultWidth);
    if not (FWidth > 0) then
      FWidth := FormulaClass.DefaultWidth;
    FMaxIter := EnsureRange(Ini.ReadInteger(kSectionFractal, 'MaxIter', kDefaultMaxIter), kMinMaxIter, kMaxMaxIter);
    FIsAutoIter := Ini.ReadBool(kSectionFractal, 'AutoIter', True);

    FParams.Clear;
    Ini.ReadSectionValues(kSectionParams, FParams);

    FMapping := DefaultColorMapping;
    FMapping.Offset := InvariantToFloat(Ini.ReadString(kSectionColors, 'Offset', ''), FMapping.Offset);
    FMapping.Repeats := InvariantToFloat(Ini.ReadString(kSectionColors, 'Repeats', ''), FMapping.Repeats);
    FMapping.Stretch := InvariantToFloat(Ini.ReadString(kSectionColors, 'Stretch', ''), FMapping.Stretch);
    FMapping.IsInverted := Ini.ReadBool(kSectionColors, 'Invert', False);
    FMapping := ClampColorMapping(FMapping);

    Lines.Clear;
    Ini.ReadSectionValues(kSectionPalette, Lines);
    if Lines.Count > 0 then
      FPalette.LoadFromStrings(Lines)
    else
      FPalette.SetDefault;
    if FPalette.Name = '' then
      FPalette.Name := kUnnamed;
  finally
    Lines.Free;
    Ini.Free;
  end;
end;

//SEP

procedure TFractalLocation.SaveToFile(const FileName: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := SaveToText;
    L.SaveToFile(FileName, TEncoding.UTF8);
  finally
    L.Free;
  end;
end;

//SEP

procedure TFractalLocation.LoadFromFile(const FileName: string);
var
  L: TStringList;
begin
  try
    L := TStringList.Create;
    try
      L.LoadFromFile(FileName);
      LoadFromText(L.Text);
    finally
      L.Free;
    end;
  except
    on E: EFractalFileError do
      raise;
    on E: Exception do
      raise EFractalFileError.CreateFmt('Fichier illisible (%s) : %s', [ExtractFileName(FileName), E.Message]);
  end;
end;

//SEP

constructor TFavoriteStore.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := IncludeTrailingPathDelimiter(AFolder);
  ForceDirectories(FFolder);
end;

//SEP

procedure TFavoriteStore.List(Names: TStrings);
var
  SR: TSearchRec;
  Sorted: TStringList;
begin
  Sorted := TStringList.Create;
  try
    Sorted.Sorted := True;
    if FindFirst(FFolder + '*' + kLocationExtension, faAnyFile, SR) = 0 then
      try
        repeat
          Sorted.Add(ChangeFileExt(SR.Name, ''));
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    Names.Assign(Sorted);
  finally
    Sorted.Free;
  end;
end;

//SEP

function TFavoriteStore.FileNameOf(const AName: string): string;
begin
  Result := FFolder + SanitizeFileName(AName) + kLocationExtension;
end;

//SEP

function TFavoriteStore.Save(const AName: string; Location: TFractalLocation): string;
begin
  Result := SanitizeFileName(AName);
  Location.SaveToFile(FileNameOf(Result));
end;

//SEP

procedure TFavoriteStore.Load(const AName: string; Location: TFractalLocation);
begin
  Location.LoadFromFile(FileNameOf(AName));
end;

//SEP

procedure TFavoriteStore.Delete(const AName: string);
begin
  SysUtils.DeleteFile(FileNameOf(AName));
end;

//SEP

function SanitizeFileName(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if Pos(Result[I], kInvalidFileChars) > 0 then
      Result[I] := '_';
  Result := Trim(Result);
  if Result = '' then
    Result := kUnnamed;
end;

//SEP

function AppDataFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, CSIDL_APPDATA, 0, 0, Buffer) = S_OK then
    Result := IncludeTrailingPathDelimiter(Buffer) + 'Fractales\'
  else
    Result := ExtractFilePath(ParamStr(0));
  ForceDirectories(Result);
end;

//SEP

function PaletteFolder: string;
begin
  Result := AppDataFolder + 'Palettes\';
  ForceDirectories(Result);
end;

//SEP

function FavoritesFolder: string;
begin
  Result := AppDataFolder + 'Favoris\';
  ForceDirectories(Result);
end;

end.
```

Run : `tools/normalize.sh src/Fractal.Persistence.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (64 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Persistence.pas tests
git commit -m "Lieux sérialisés (.frac) et favoris

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8 : `Fractal.Navigation`

**Files :**
- Create : `src/Fractal.Navigation.pas`, `tests/TestFractalNavigation.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `TViewport` et ses méthodes, `TComplexPoint`, `TPrecisionState`, `MakeViewport` (1).
- Produces : `TNavButton = (nbLeft, nbRight, nbMiddle)` ; `TViewChangeKind = (vckReset, vckPan)` ;
  `TViewChange = record Kind; DX, DY: Integer; end` ; `TViewChangedEvent = procedure(Sender: TObject; const
  Change: TViewChange) of object` ; `TComplexPointEvent = procedure(Sender: TObject; const P: TComplexPoint) of
  object` ; `TViewHistory` (`Clear`, `Push`, `CanGoBack`, `CanGoForward`, `Back`, `Forward`, `Count`) ;
  `TNavigationMode` (`Create(ANavigator); virtual`, classe `DisplayName`, `MouseDown`, `MouseMove(X, Y;
  IsLeftDown)`, `MouseUp`, `MouseWheel(WheelDelta, X, Y)`) ; `TFreeNavigationMode`, `TJuliaNavigationMode` ;
  `kNavigationModes: array[0..1] of TNavigationModeClass` ; `TNavigator` (`SetMode`, `Reset(V)`,
  `SetPixelSize(W, H)`, `MouseDown/MouseMove/MouseUp/MouseWheel`, `CancelSelection`, `HasSelection`,
  `SelectionRect: TRect`, `ZoomAt(X, Y, Factor: TFloat)`, `ZoomCenter(Factor)`, `PanBy(DX, DY)`,
  `KeyPan(DirX, DirY)`, `CommitHistory`, `GoBack`, `GoForward`, `CanGoBack`, `CanGoForward`,
  `NotifyJuliaPoint(X, Y)`, propriétés `Viewport`, `Mode`, `History`, événements `OnViewChanged`,
  `OnSelectionChanged`, `OnPrecisionLimit`, `OnJuliaPoint`) ; constante `kHistoryCapacity = 200`.
- Règles : le bouton droit sélectionne une zone dans tous les modes ; un glisser au bouton gauche émet des
  `vckPan` sans historique et ajoute une seule entrée au relâchement ; tout zoom passe par un contrôle de
  précision (`psLimit` → `OnPrecisionLimit`, vue inchangée) ; un redimensionnement n'ajoute rien à
  l'historique.

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalNavigation.pas` :

```pascal
unit TestFractalNavigation;

interface

uses
  Types, SysUtils, TestFramework, Fractal.Types, Fractal.Navigation;

type
  TTestNavigator = class(TTestCase)
  private
    FNavigator: TNavigator;
    FChangeCount: Integer;
    FLastChange: TViewChange;
    FIsLimitHit: Boolean;
    FJuliaCount: Integer;
    FJuliaPoint: TComplexPoint;
    procedure ViewChanged(Sender: TObject; const Change: TViewChange);
    procedure PrecisionLimit(Sender: TObject);
    procedure JuliaPoint(Sender: TObject; const P: TComplexPoint);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestWheelZoomKeepsPointUnderCursor;
    procedure TestLeftDragPansWithOneHistoryEntry;
    procedure TestClickWithoutMoveAddsNoHistory;
    procedure TestRightDragSelectsConstrainedRect;
    procedure TestTinySelectionIsIgnored;
    procedure TestCancelSelection;
    procedure TestBackAndForward;
    procedure TestPrecisionLimitBlocksZoom;
    procedure TestResizeKeepsWidthWithoutHistory;
    procedure TestKeyPanMovesByTenthOfWidth;
    procedure TestJuliaModeReportsPoint;
    procedure TestHistoryCapacity;
  end;

implementation

const
  kEps = 1e-12;

//SEP

procedure TTestNavigator.SetUp;
begin
  FNavigator := TNavigator.Create;
  FNavigator.OnViewChanged := ViewChanged;
  FNavigator.OnPrecisionLimit := PrecisionLimit;
  FNavigator.OnJuliaPoint := JuliaPoint;
  FNavigator.Reset(MakeViewport(0, 0, 4, 400, 300));
  FChangeCount := 0;
  FIsLimitHit := False;
  FJuliaCount := 0;
end;

//SEP

procedure TTestNavigator.TearDown;
begin
  FreeAndNil(FNavigator);
end;

//SEP

procedure TTestNavigator.ViewChanged(Sender: TObject; const Change: TViewChange);
begin
  Inc(FChangeCount);
  FLastChange := Change;
end;

//SEP

procedure TTestNavigator.PrecisionLimit(Sender: TObject);
begin
  FIsLimitHit := True;
end;

//SEP

procedure TTestNavigator.JuliaPoint(Sender: TObject; const P: TComplexPoint);
begin
  Inc(FJuliaCount);
  FJuliaPoint := P;
end;

//SEP

procedure TTestNavigator.TestWheelZoomKeepsPointUnderCursor;
var
  P, Q: TComplexPoint;
begin
  P := FNavigator.Viewport.PixelToComplex(100, 50);
  FNavigator.MouseWheel(120, 100, 50);
  Q := FNavigator.Viewport.PixelToComplex(100, 50);
  CheckEquals(P.X, Q.X, kEps);
  CheckEquals(P.Y, Q.Y, kEps);
  CheckEquals(4 / 1.25, FNavigator.Viewport.Width, kEps);
  CheckTrue(FNavigator.CanGoBack);
  CheckEquals(Ord(vckReset), Ord(FLastChange.Kind));
end;

//SEP

procedure TTestNavigator.TestLeftDragPansWithOneHistoryEntry;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.MouseDown(nbLeft, 100, 100);
  FNavigator.MouseMove(110, 95, True);
  CheckEquals(Ord(vckPan), Ord(FLastChange.Kind));
  CheckEquals(10, FLastChange.DX);
  CheckEquals(-5, FLastChange.DY);
  FNavigator.MouseMove(115, 95, True);
  CheckEquals(5, FLastChange.DX);
  CheckEquals(0, FLastChange.DY);
  CheckEquals(Count0, FNavigator.History.Count);
  FNavigator.MouseUp(nbLeft, 115, 95);
  CheckEquals(Count0 + 1, FNavigator.History.Count);
  CheckEquals(-0.15, FNavigator.Viewport.CenterX, kEps);
  CheckEquals(-0.05, FNavigator.Viewport.CenterY, kEps);
end;

//SEP

procedure TTestNavigator.TestClickWithoutMoveAddsNoHistory;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.MouseDown(nbLeft, 100, 100);
  FNavigator.MouseUp(nbLeft, 100, 100);
  CheckEquals(Count0, FNavigator.History.Count);
  CheckEquals(0, FChangeCount);
end;

//SEP

procedure TTestNavigator.TestRightDragSelectsConstrainedRect;
var
  R: TRect;
begin
  FNavigator.MouseDown(nbRight, 100, 75);
  FNavigator.MouseMove(300, 100, False);
  CheckTrue(FNavigator.HasSelection);
  R := FNavigator.SelectionRect;
  CheckEquals(100, R.Left);
  CheckEquals(75, R.Top);
  CheckEquals(300, R.Right);
  CheckEquals(225, R.Bottom);
  FNavigator.MouseUp(nbRight, 300, 100);
  CheckFalse(FNavigator.HasSelection);
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  CheckEquals(0.0, FNavigator.Viewport.CenterX, kEps);
  CheckEquals(0.0, FNavigator.Viewport.CenterY, kEps);
end;

//SEP

procedure TTestNavigator.TestTinySelectionIsIgnored;
begin
  FNavigator.MouseDown(nbRight, 100, 100);
  FNavigator.MouseMove(102, 101, False);
  FNavigator.MouseUp(nbRight, 102, 101);
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
  CheckFalse(FNavigator.CanGoBack);
end;

//SEP

procedure TTestNavigator.TestCancelSelection;
begin
  FNavigator.MouseDown(nbRight, 100, 75);
  FNavigator.MouseMove(300, 100, False);
  FNavigator.CancelSelection;
  CheckFalse(FNavigator.HasSelection);
  FNavigator.MouseUp(nbRight, 300, 100);
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
end;

//SEP

procedure TTestNavigator.TestBackAndForward;
begin
  FNavigator.ZoomCenter(2);
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  FNavigator.GoBack;
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
  CheckTrue(FNavigator.CanGoForward);
  FNavigator.GoForward;
  CheckEquals(2.0, FNavigator.Viewport.Width, kEps);
  CheckFalse(FNavigator.CanGoForward);
end;

//SEP

procedure TTestNavigator.TestPrecisionLimitBlocksZoom;
begin
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-14, 400, 300));
  FNavigator.ZoomCenter(1000);
  CheckTrue(FIsLimitHit);
  CheckEquals(1e-14, FNavigator.Viewport.Width, 1e-28);
end;

//SEP

procedure TTestNavigator.TestResizeKeepsWidthWithoutHistory;
var
  Count0: Integer;
begin
  Count0 := FNavigator.History.Count;
  FNavigator.SetPixelSize(800, 600);
  CheckEquals(4.0, FNavigator.Viewport.Width, kEps);
  CheckEquals(800, FNavigator.Viewport.PixelWidth);
  CheckEquals(Count0, FNavigator.History.Count);
  CheckEquals(Ord(vckReset), Ord(FLastChange.Kind));
  FNavigator.SetPixelSize(0, 0);
  CheckEquals(1, FNavigator.Viewport.PixelWidth);
  CheckEquals(1, FNavigator.Viewport.PixelHeight);
end;

//SEP

procedure TTestNavigator.TestKeyPanMovesByTenthOfWidth;
begin
  FNavigator.KeyPan(1, 0);
  CheckEquals(Ord(vckPan), Ord(FLastChange.Kind));
  CheckEquals(-40, FLastChange.DX);
  CheckEquals(0.4, FNavigator.Viewport.CenterX, kEps);
  CheckTrue(FNavigator.CanGoBack);
end;

//SEP

procedure TTestNavigator.TestJuliaModeReportsPoint;
var
  P: TComplexPoint;
begin
  FNavigator.SetMode(TJuliaNavigationMode);
  FNavigator.MouseMove(200, 150, False);
  CheckEquals(1, FJuliaCount);
  P := FNavigator.Viewport.PixelToComplex(200, 150);
  CheckEquals(P.X, FJuliaPoint.X, kEps);
  CheckEquals(P.Y, FJuliaPoint.Y, kEps);
end;

//SEP

procedure TTestNavigator.TestHistoryCapacity;
var
  I: Integer;
begin
  for I := 1 to kHistoryCapacity + 50 do
    FNavigator.ZoomCenter(1.01);
  CheckEquals(kHistoryCapacity, FNavigator.History.Count);
  CheckTrue(FNavigator.CanGoBack);
end;

initialization
  RegisterTest(TTestNavigator.Suite);

end.
```

Ajouter `Fractal.Navigation in '..\src\Fractal.Navigation.pas'` et
`TestFractalNavigation in 'TestFractalNavigation.pas'` au `.dpr`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalNavigation.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.Navigation.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.Navigation.pas`**

```pascal
unit Fractal.Navigation;

interface

uses
  Types, SysUtils, Classes, Math, Fractal.Types;

const
  kWheelZoomFactor = 1.25;
  kWheelDeltaUnit = 120;
  kMinSelectionPixels = 4;
  kHistoryCapacity = 200;
  kKeyPanDivisor = 10;

type
  TNavButton = (nbLeft, nbRight, nbMiddle);
  TViewChangeKind = (vckReset, vckPan);

  TViewChange = record
    Kind: TViewChangeKind;
    DX, DY: Integer;  // vckPan : déplacement du contenu en pixels entiers
  end;

  TViewChangedEvent = procedure(Sender: TObject; const Change: TViewChange) of object;
  TComplexPointEvent = procedure(Sender: TObject; const P: TComplexPoint) of object;

  TViewHistory = class
  private
    FItems: array of TViewport;
    FCount: Integer;
    FIndex: Integer;
  public
    constructor Create;
    procedure Clear;
    procedure Push(const V: TViewport);
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    function Back: TViewport;
    function Forward: TViewport;
    property Count: Integer read FCount;
  end;

  TNavigator = class;

  TNavigationMode = class
  private
    FNavigator: TNavigator;
  public
    constructor Create(ANavigator: TNavigator); virtual;
    class function DisplayName: string; virtual; abstract;
    procedure MouseDown(Button: TNavButton; X, Y: Integer); virtual;
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean); virtual;
    procedure MouseUp(Button: TNavButton; X, Y: Integer); virtual;
    procedure MouseWheel(WheelDelta, X, Y: Integer); virtual;
    property Navigator: TNavigator read FNavigator;
  end;

  TNavigationModeClass = class of TNavigationMode;

  TFreeNavigationMode = class(TNavigationMode)
  private
    FIsDragging: Boolean;
    FHasMoved: Boolean;
    FLastX: Integer;
    FLastY: Integer;
  public
    class function DisplayName: string; override;
    procedure MouseDown(Button: TNavButton; X, Y: Integer); override;
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean); override;
    procedure MouseUp(Button: TNavButton; X, Y: Integer); override;
    procedure MouseWheel(WheelDelta, X, Y: Integer); override;
  end;

  TJuliaNavigationMode = class(TFreeNavigationMode)
  public
    class function DisplayName: string; override;
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean); override;
  end;

  TNavigator = class
  private
    FViewport: TViewport;
    FHistory: TViewHistory;
    FMode: TNavigationMode;
    FIsSelecting: Boolean;
    FSelStart: TPoint;
    FSelEnd: TPoint;
    FOnViewChanged: TViewChangedEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOnPrecisionLimit: TNotifyEvent;
    FOnJuliaPoint: TComplexPointEvent;
    procedure DoViewChanged(Kind: TViewChangeKind; DX, DY: Integer);
    procedure DoSelectionChanged;
    function TryCommit(const V: TViewport): Boolean;
    function ConstrainedEnd(X, Y: Integer): TPoint;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetMode(AModeClass: TNavigationModeClass);
    procedure Reset(const V: TViewport);
    procedure SetPixelSize(AWidth, AHeight: Integer);
    procedure MouseDown(Button: TNavButton; X, Y: Integer);
    procedure MouseMove(X, Y: Integer; IsLeftDown: Boolean);
    procedure MouseUp(Button: TNavButton; X, Y: Integer);
    procedure MouseWheel(WheelDelta, X, Y: Integer);
    procedure CancelSelection;
    function HasSelection: Boolean;
    function SelectionRect: TRect;
    procedure ZoomAt(X, Y, Factor: TFloat);
    procedure ZoomCenter(Factor: TFloat);
    procedure PanBy(DX, DY: Integer);
    procedure KeyPan(DirX, DirY: Integer);
    procedure CommitHistory;
    procedure GoBack;
    procedure GoForward;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    procedure NotifyJuliaPoint(X, Y: Integer);
    property Viewport: TViewport read FViewport;
    property Mode: TNavigationMode read FMode;
    property History: TViewHistory read FHistory;
    property OnViewChanged: TViewChangedEvent read FOnViewChanged write FOnViewChanged;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property OnPrecisionLimit: TNotifyEvent read FOnPrecisionLimit write FOnPrecisionLimit;
    property OnJuliaPoint: TComplexPointEvent read FOnJuliaPoint write FOnJuliaPoint;
  end;

const
  kNavigationModes: array[0..1] of TNavigationModeClass = (TFreeNavigationMode, TJuliaNavigationMode);

implementation

//SEP

constructor TViewHistory.Create;
begin
  inherited Create;
  Clear;
end;

//SEP

procedure TViewHistory.Clear;
begin
  FCount := 0;
  FIndex := -1;
end;

//SEP

procedure TViewHistory.Push(const V: TViewport);
var
  I: Integer;
begin
  FCount := FIndex + 1;  // une nouvelle vue efface l'avenir
  if FCount >= kHistoryCapacity then
  begin
    for I := 0 to FCount - 2 do
      FItems[I] := FItems[I + 1];
    Dec(FCount);
  end;
  if Length(FItems) <= FCount then
    SetLength(FItems, FCount + 16);
  FItems[FCount] := V;
  Inc(FCount);
  FIndex := FCount - 1;
end;

//SEP

function TViewHistory.CanGoBack: Boolean;
begin
  Result := FIndex > 0;
end;

//SEP

function TViewHistory.CanGoForward: Boolean;
begin
  Result := FIndex < FCount - 1;
end;

//SEP

function TViewHistory.Back: TViewport;
begin
  Dec(FIndex);
  Result := FItems[FIndex];
end;

//SEP

function TViewHistory.Forward: TViewport;
begin
  Inc(FIndex);
  Result := FItems[FIndex];
end;

//SEP

constructor TNavigationMode.Create(ANavigator: TNavigator);
begin
  inherited Create;
  FNavigator := ANavigator;
end;

//SEP

procedure TNavigationMode.MouseDown(Button: TNavButton; X, Y: Integer);
begin
end;

//SEP

procedure TNavigationMode.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
end;

//SEP

procedure TNavigationMode.MouseUp(Button: TNavButton; X, Y: Integer);
begin
end;

//SEP

procedure TNavigationMode.MouseWheel(WheelDelta, X, Y: Integer);
begin
end;

//SEP

class function TFreeNavigationMode.DisplayName: string;
begin
  Result := 'Libre';
end;

//SEP

procedure TFreeNavigationMode.MouseDown(Button: TNavButton; X, Y: Integer);
begin
  if Button <> nbLeft then
    Exit;
  FIsDragging := True;
  FHasMoved := False;
  FLastX := X;
  FLastY := Y;
end;

//SEP

procedure TFreeNavigationMode.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
  if not (FIsDragging and IsLeftDown) then
    Exit;
  if (X = FLastX) and (Y = FLastY) then
    Exit;
  Navigator.PanBy(X - FLastX, Y - FLastY);
  FLastX := X;
  FLastY := Y;
  FHasMoved := True;
end;

//SEP

procedure TFreeNavigationMode.MouseUp(Button: TNavButton; X, Y: Integer);
begin
  if (Button <> nbLeft) or not FIsDragging then
    Exit;
  FIsDragging := False;
  if FHasMoved then
    Navigator.CommitHistory;
end;

//SEP

procedure TFreeNavigationMode.MouseWheel(WheelDelta, X, Y: Integer);
begin
  Navigator.ZoomAt(X, Y, Power(kWheelZoomFactor, WheelDelta / kWheelDeltaUnit));
end;

//SEP

class function TJuliaNavigationMode.DisplayName: string;
begin
  Result := 'Aperçu Julia';
end;

//SEP

procedure TJuliaNavigationMode.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
  inherited MouseMove(X, Y, IsLeftDown);
  Navigator.NotifyJuliaPoint(X, Y);
end;

//SEP

constructor TNavigator.Create;
begin
  inherited Create;
  FHistory := TViewHistory.Create;
  FMode := TFreeNavigationMode.Create(Self);
  FViewport := MakeViewport(0, 0, kDefaultWidth, 1, 1);
end;

//SEP

destructor TNavigator.Destroy;
begin
  FMode.Free;
  FHistory.Free;
  inherited Destroy;
end;

//SEP

procedure TNavigator.DoViewChanged(Kind: TViewChangeKind; DX, DY: Integer);
var
  Change: TViewChange;
begin
  Change.Kind := Kind;
  Change.DX := DX;
  Change.DY := DY;
  if Assigned(FOnViewChanged) then
    FOnViewChanged(Self, Change);
end;

//SEP

procedure TNavigator.DoSelectionChanged;
begin
  if Assigned(FOnSelectionChanged) then
    FOnSelectionChanged(Self);
end;

//SEP

function TNavigator.TryCommit(const V: TViewport): Boolean;
begin
  if V.PrecisionState = psLimit then
  begin
    if Assigned(FOnPrecisionLimit) then
      FOnPrecisionLimit(Self);
    Exit(False);
  end;
  FViewport := V;
  FHistory.Push(V);
  DoViewChanged(vckReset, 0, 0);
  Result := True;
end;

//SEP

procedure TNavigator.SetMode(AModeClass: TNavigationModeClass);
begin
  FMode.Free;
  FMode := AModeClass.Create(Self);
end;

//SEP

procedure TNavigator.Reset(const V: TViewport);
begin
  FViewport := V;
  FHistory.Clear;
  FHistory.Push(V);
  DoViewChanged(vckReset, 0, 0);
end;

//SEP

procedure TNavigator.SetPixelSize(AWidth, AHeight: Integer);
var
  V: TViewport;
begin
  V := FViewport.Resized(AWidth, AHeight);
  if (V.PixelWidth = FViewport.PixelWidth) and (V.PixelHeight = FViewport.PixelHeight) then
    Exit;
  FViewport := V;
  DoViewChanged(vckReset, 0, 0);
end;

//SEP

procedure TNavigator.MouseDown(Button: TNavButton; X, Y: Integer);
begin
  if Button = nbRight then
  begin
    FIsSelecting := True;
    FSelStart := Point(X, Y);
    FSelEnd := FSelStart;
    DoSelectionChanged;
  end
  else
    FMode.MouseDown(Button, X, Y);
end;

//SEP

procedure TNavigator.MouseMove(X, Y: Integer; IsLeftDown: Boolean);
begin
  if FIsSelecting then
  begin
    FSelEnd := ConstrainedEnd(X, Y);
    DoSelectionChanged;
  end
  else
    FMode.MouseMove(X, Y, IsLeftDown);
end;

//SEP

procedure TNavigator.MouseUp(Button: TNavButton; X, Y: Integer);
var
  R: TRect;
begin
  if Button = nbRight then
  begin
    if not FIsSelecting then
      Exit;
    FIsSelecting := False;
    DoSelectionChanged;
    R := SelectionRect;
    if R.Right - R.Left >= kMinSelectionPixels then
      TryCommit(FViewport.FittedToRect(R.Left, R.Top, R.Right, R.Bottom));
  end
  else
    FMode.MouseUp(Button, X, Y);
end;

//SEP

procedure TNavigator.MouseWheel(WheelDelta, X, Y: Integer);
begin
  FMode.MouseWheel(WheelDelta, X, Y);
end;

//SEP

function TNavigator.ConstrainedEnd(X, Y: Integer): TPoint;
var
  DX, DY, W, H: Integer;
  Ratio: Double;
begin
  // rectangle contraint au rapport largeur/hauteur de la vue, pour ne pas déformer l'image
  DX := X - FSelStart.X;
  DY := Y - FSelStart.Y;
  Ratio := FViewport.PixelWidth / FViewport.PixelHeight;
  if Abs(DX) >= Abs(DY) * Ratio then
  begin
    W := Abs(DX);
    H := Round(W / Ratio);
  end
  else
  begin
    H := Abs(DY);
    W := Round(H * Ratio);
  end;
  if DX >= 0 then
    Result.X := FSelStart.X + W
  else
    Result.X := FSelStart.X - W;
  if DY >= 0 then
    Result.Y := FSelStart.Y + H
  else
    Result.Y := FSelStart.Y - H;
end;

//SEP

procedure TNavigator.CancelSelection;
begin
  if not FIsSelecting then
    Exit;
  FIsSelecting := False;
  DoSelectionChanged;
end;

//SEP

function TNavigator.HasSelection: Boolean;
begin
  Result := FIsSelecting;
end;

//SEP

function TNavigator.SelectionRect: TRect;
begin
  Result := Rect(Min(FSelStart.X, FSelEnd.X), Min(FSelStart.Y, FSelEnd.Y), Max(FSelStart.X, FSelEnd.X),
    Max(FSelStart.Y, FSelEnd.Y));
end;

//SEP

procedure TNavigator.ZoomAt(X, Y, Factor: TFloat);
begin
  TryCommit(FViewport.ZoomedAt(X, Y, Factor));
end;

//SEP

procedure TNavigator.ZoomCenter(Factor: TFloat);
begin
  ZoomAt(FViewport.PixelWidth / 2 - 0.5, FViewport.PixelHeight / 2 - 0.5, Factor);
end;

//SEP

procedure TNavigator.PanBy(DX, DY: Integer);
begin
  FViewport := FViewport.Panned(DX, DY);
  DoViewChanged(vckPan, DX, DY);
end;

//SEP

procedure TNavigator.KeyPan(DirX, DirY: Integer);
var
  Step: Integer;
begin
  // flèche à droite = regarder à droite = le contenu part vers la gauche
  Step := Max(1, FViewport.PixelWidth div kKeyPanDivisor);
  PanBy(-DirX * Step, -DirY * Step);
  CommitHistory;
end;

//SEP

procedure TNavigator.CommitHistory;
begin
  FHistory.Push(FViewport);
end;

//SEP

procedure TNavigator.GoBack;
begin
  if not FHistory.CanGoBack then
    Exit;
  FViewport := FHistory.Back.Resized(FViewport.PixelWidth, FViewport.PixelHeight);
  DoViewChanged(vckReset, 0, 0);
end;

//SEP

procedure TNavigator.GoForward;
begin
  if not FHistory.CanGoForward then
    Exit;
  FViewport := FHistory.Forward.Resized(FViewport.PixelWidth, FViewport.PixelHeight);
  DoViewChanged(vckReset, 0, 0);
end;

//SEP

function TNavigator.CanGoBack: Boolean;
begin
  Result := FHistory.CanGoBack;
end;

//SEP

function TNavigator.CanGoForward: Boolean;
begin
  Result := FHistory.CanGoForward;
end;

//SEP

procedure TNavigator.NotifyJuliaPoint(X, Y: Integer);
begin
  if Assigned(FOnJuliaPoint) then
    FOnJuliaPoint(Self, FViewport.PixelToComplex(X, Y));
end;

end.
```

Run : `tools/normalize.sh src/Fractal.Navigation.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (76 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.Navigation.pas tests
git commit -m "Navigation : modes, sélection de zone, historique

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9 : `Fractal.HiRes`

**Files :**
- Create : `src/Fractal.HiRes.pas`, `tests/TestFractalHiRes.pas`
- Modify : `tests/FractalesTests.dpr`

**Interfaces :**
- Consumes : `TViewport.Resized/SubViewport` (1) ; `TFractalFormula.Clone` (2) ; `TRenderEngine`, `CpuCount` (4) ;
  `TColorMapper.MapValue` (5) ; `TPngWriter`, `kLocationKeyword` (6).
- Produces : `THiResSettings = record Width, Height, Supersample: Integer; FileName: string; end` ;
  `THiResRenderer = class(TThread)` (`Create(const ASettings; const AViewport; AFormula; AMapper: TColorMapper;
  const ALocationText: RawByteString)` — démarre aussitôt, clone la formule, **prend possession** de `AMapper` ;
  propriétés `Progress` (0–1000), `ErrorMessage`, `IsSucceeded`, `IsDone`) ; `EstimateHiResBytes(const S):
  Int64` ; constantes `kHiResBandRows = 16`, `kMaxHiResBytes`.
- La vue est redimensionnée à `Width × Height` en gardant sa largeur dans le plan complexe.
- Annulation : `Terminate`. Le fichier partiel est supprimé en cas d'annulation ou d'erreur.

- [ ] **Step 1 : écrire les tests**

`tests/TestFractalHiRes.pas` :

```pascal
unit TestFractalHiRes;

interface

uses
  Classes, SysUtils, Graphics, pngimage, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.Palette,
  Fractal.Png, Fractal.HiRes, TestUtils;

type
  TTestHiRes = class(TTestCase)
  private
    function MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
    function RunRenderer(const Settings: THiResSettings; const V: TViewport; F: TFractalFormula): THiResRenderer;
  published
    procedure TestSmallRenderMatchesDirectColors;
    procedure TestSupersampledRenderHasRequestedSize;
    procedure TestCancelDeletesFile;
    procedure TestInvalidPathReportsError;
    procedure TestEstimateRejectsHugeRender;
  end;

implementation

//SEP

function TTestHiRes.MakeSettings(W, H, SS: Integer; const FileName: string): THiResSettings;
begin
  Result.Width := W;
  Result.Height := H;
  Result.Supersample := SS;
  Result.FileName := FileName;
end;

//SEP

function TTestHiRes.RunRenderer(const Settings: THiResSettings; const V: TViewport;
  F: TFractalFormula): THiResRenderer;
var
  P: TGradientPalette;
begin
  P := CreateBuiltInPalette(0);
  try
    Result := THiResRenderer.Create(Settings, V, F, TColorMapper.Create(P, DefaultColorMapping), 'abc');
  finally
    P.Free;
  end;
end;

//SEP

procedure TTestHiRes.TestSmallRenderMatchesDirectColors;
const
  kSamples: array[0..3, 0..1] of Integer = ((0, 0), (10, 20), (63, 47), (32, 24));
var
  FileName: string;
  V: TViewport;
  F: TMandelbrotFormula;
  P: TGradientPalette;
  Check: TColorMapper;
  R: THiResRenderer;
  Png: TPngImage;
  C: TComplexPoint;
  I: Integer;
  Text: RawByteString;
begin
  FileName := TestTempFolder + 'hires.png';
  V := MakeViewport(-0.5, 0, 3, 64, 48);
  F := TMandelbrotFormula.Create;
  P := CreateBuiltInPalette(0);
  Check := TColorMapper.Create(P, DefaultColorMapping);
  Png := TPngImage.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(64, 48, 1, FileName), V, F);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
      CheckTrue(R.IsDone);
      CheckEquals(1000, R.Progress);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    for I := 0 to High(kSamples) do
    begin
      C := V.PixelToComplex(kSamples[I, 0], kSamples[I, 1]);
      CheckEquals(Integer(SwapRedBlue(Check.MapValue(F.Iterate(C.X, C.Y)))),
        Integer(Png.Pixels[kSamples[I, 0], kSamples[I, 1]]));
    end;
    CheckTrue(ReadPngText(FileName, kLocationKeyword, Text));
    CheckEquals('abc', UTF8ToString(Text));
  finally
    Png.Free;
    Check.Free;
    P.Free;
    F.Free;
  end;
end;

//SEP

procedure TTestHiRes.TestSupersampledRenderHasRequestedSize;
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
  Png: TPngImage;
begin
  FileName := TestTempFolder + 'hires-ss.png';
  F := TMandelbrotFormula.Create;
  Png := TPngImage.Create;
  try
    R := RunRenderer(MakeSettings(80, 50, 2, FileName), MakeViewport(-0.5, 0, 3, 400, 300), F);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    CheckEquals(80, Png.Width);
    CheckEquals(50, Png.Height);
  finally
    Png.Free;
    F.Free;
  end;
end;

//SEP

procedure TTestHiRes.TestCancelDeletesFile;
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
begin
  FileName := TestTempFolder + 'hires-cancel.png';
  F := TMandelbrotFormula.Create;
  try
    F.MaxIter := 5000;
    R := RunRenderer(MakeSettings(3000, 2000, 3, FileName), MakeViewport(-0.5, 0, 3, 400, 300), F);
    try
      Sleep(300);
      R.Terminate;
      R.WaitFor;
      CheckFalse(R.IsSucceeded);
      CheckEquals('', R.ErrorMessage);
    finally
      R.Free;
    end;
    CheckFalse(FileExists(FileName));
  finally
    F.Free;
  end;
end;

//SEP

procedure TTestHiRes.TestInvalidPathReportsError;
var
  F: TMandelbrotFormula;
  R: THiResRenderer;
begin
  F := TMandelbrotFormula.Create;
  try
    R := RunRenderer(MakeSettings(16, 16, 1, TestTempFolder + 'absent\sous\x.png'),
      MakeViewport(-0.5, 0, 3, 400, 300), F);
    try
      R.WaitFor;
      CheckFalse(R.IsSucceeded);
      CheckTrue(R.ErrorMessage <> '');
    finally
      R.Free;
    end;
  finally
    F.Free;
  end;
end;

//SEP

procedure TTestHiRes.TestEstimateRejectsHugeRender;
begin
  CheckTrue(EstimateHiResBytes(MakeSettings(7680, 4320, 3, '')) < kMaxHiResBytes);
  CheckTrue(EstimateHiResBytes(MakeSettings(1000000, 100, 3, '')) > kMaxHiResBytes);
end;

initialization
  RegisterTest(TTestHiRes.Suite);

end.
```

Ajouter `Fractal.HiRes in '..\src\Fractal.HiRes.pas'` et `TestFractalHiRes in 'TestFractalHiRes.pas'` au `.dpr`.

- [ ] **Step 2 : vérifier l'échec**

Run : `tools/normalize.sh tests/TestFractalHiRes.pas tests/FractalesTests.dpr && ./build.sh tests`
Expected : échec de compilation, `Fractal.HiRes.pas` introuvable.

- [ ] **Step 3 : écrire `src/Fractal.HiRes.pas`**

```pascal
unit Fractal.HiRes;

interface

uses
  Windows, SysUtils, Classes, Math, Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.Engine,
  Fractal.Png;

const
  kHiResBandRows = 16;
  kMaxHiResBytes = 512 * 1024 * 1024;
  kProgressMax = 1000;

type
  THiResSettings = record
    Width: Integer;
    Height: Integer;
    Supersample: Integer;
    FileName: string;
  end;

  // Rendu hors écran par bandes de lignes, écrit directement dans le PNG.
  THiResRenderer = class(TThread)
  private
    FSettings: THiResSettings;
    FViewport: TViewport;
    FFormula: TFractalFormula;
    FMapper: TColorMapper;
    FLocationText: RawByteString;
    FProgress: Integer;
    FErrorMessage: string;
    FIsSucceeded: Boolean;
    FIsDone: Boolean;
    function RenderToStream(Stream: TStream): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASettings: THiResSettings; const AViewport: TViewport; AFormula: TFractalFormula;
      AMapper: TColorMapper; const ALocationText: RawByteString);
    destructor Destroy; override;
    property Progress: Integer read FProgress;
    property ErrorMessage: string read FErrorMessage;
    property IsSucceeded: Boolean read FIsSucceeded;
    property IsDone: Boolean read FIsDone;
  end;

function EstimateHiResBytes(const Settings: THiResSettings): Int64;

implementation

const
  kWaitSliceMs = 100;
  kBytesPerSample = 5;  // Single + niveau

//SEP

function EstimateHiResBytes(const Settings: THiResSettings): Int64;
begin
  Result := Int64(Settings.Width) * Settings.Supersample * kHiResBandRows * Settings.Supersample * kBytesPerSample
    + Int64(Settings.Width) * 3;
end;

//SEP

constructor THiResRenderer.Create(const ASettings: THiResSettings; const AViewport: TViewport;
  AFormula: TFractalFormula; AMapper: TColorMapper; const ALocationText: RawByteString);
begin
  FSettings := ASettings;
  FSettings.Supersample := EnsureRange(FSettings.Supersample, 1, 3);
  FViewport := AViewport.Resized(ASettings.Width, ASettings.Height);
  FFormula := AFormula.Clone;
  FMapper := AMapper;
  FLocationText := ALocationText;
  inherited Create(False);
end;

//SEP

destructor THiResRenderer.Destroy;
begin
  inherited Destroy;  // attend la fin du thread avant de libérer ce qu'il utilise
  FMapper.Free;
  FFormula.Free;
end;

//SEP

procedure THiResRenderer.Execute;
var
  Stream: TFileStream;
  IsFileCreated, IsComplete: Boolean;
begin
  IsFileCreated := False;
  try
    try
      if (FSettings.Width <= 0) or (FSettings.Height <= 0) then
        raise Exception.Create('Dimensions de rendu invalides.');
      if EstimateHiResBytes(FSettings) > kMaxHiResBytes then
        raise Exception.Create('Mémoire insuffisante pour ce rendu : réduisez la taille ou le suréchantillonnage.');
      Stream := TFileStream.Create(FSettings.FileName, fmCreate);
      IsFileCreated := True;
      try
        IsComplete := RenderToStream(Stream);
      finally
        Stream.Free;
      end;
      if IsComplete then
        FIsSucceeded := True
      else
        SysUtils.DeleteFile(FSettings.FileName);
    except
      on E: Exception do
      begin
        FErrorMessage := E.Message;
        if IsFileCreated then
          SysUtils.DeleteFile(FSettings.FileName);
      end;
    end;
  finally
    FIsDone := True;
  end;
end;

//SEP

function THiResRenderer.RenderToStream(Stream: TStream): Boolean;
var
  Engine: TRenderEngine;
  Writer: TPngWriter;
  Row: array of Byte;
  Row0, Rows, R, X, SX, SY, SS, Count, SumR, SumG, SumB: Integer;
  C: Cardinal;
  Errors: string;
begin
  Result := False;
  SS := FSettings.Supersample;
  Count := SS * SS;
  SetLength(Row, FSettings.Width * 3);
  Engine := TRenderEngine.Create(CpuCount);
  try
    Writer := TPngWriter.Create(Stream, FSettings.Width, FSettings.Height);
    try
      if FLocationText <> '' then
        Writer.AddText(kLocationKeyword, FLocationText);
      Row0 := 0;
      while Row0 < FSettings.Height do
      begin
        Rows := Min(kHiResBandRows, FSettings.Height - Row0);
        Engine.Render(FViewport.SubViewport(SS, Row0, Rows), FFormula, False);
        while not Engine.WaitUntilComplete(kWaitSliceMs) do
          if Terminated then
            Exit;
        if Terminated then
          Exit;
        Errors := Engine.TakeErrors;
        if Errors <> '' then
          raise Exception.Create('Erreur de calcul : ' + Errors);
        for R := 0 to Rows - 1 do
        begin
          for X := 0 to FSettings.Width - 1 do
          begin
            // anticrénelage : moyenne des couleurs (pas des valeurs) des SS x SS sous-pixels
            SumR := 0;
            SumG := 0;
            SumB := 0;
            for SY := 0 to SS - 1 do
              for SX := 0 to SS - 1 do
              begin
                C := FMapper.MapValue(Engine.Buffer.Value(X * SS + SX, R * SS + SY));
                Inc(SumR, (C shr 16) and $FF);
                Inc(SumG, (C shr 8) and $FF);
                Inc(SumB, C and $FF);
              end;
            Row[X * 3] := (SumR + Count div 2) div Count;
            Row[X * 3 + 1] := (SumG + Count div 2) div Count;
            Row[X * 3 + 2] := (SumB + Count div 2) div Count;
          end;
          Writer.WriteRow(@Row[0]);
        end;
        Inc(Row0, Rows);
        FProgress := MulDiv(Row0, kProgressMax, FSettings.Height);
      end;
      Writer.Finish;
      Result := True;
    finally
      Writer.Free;
    end;
  finally
    Engine.Free;
  end;
end;

end.
```

Run : `tools/normalize.sh src/Fractal.HiRes.pas`

- [ ] **Step 4 : lancer les tests**

Run : `./build.sh tests`
Expected : `OK:` (81 tests).

- [ ] **Step 5 : commit**

```bash
git add src/Fractal.HiRes.pas tests
git commit -m "Rendu haute résolution par bandes avec suréchantillonnage

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10 : vue, fenêtre principale et test de fumée

**Files :**
- Create : `src/Fractal.View.pas`, `src/MainFrm.pas`, `src/MainFrm.dfm`, `Fractales.dpr`

**Interfaces :**
- Consumes : tout ce qui précède, sauf `Fractal.HiRes` et `Fractal.Persistence`.
- Produces : `TFractalView = class(TCustomControl)` (`Bitmap`, `JuliaBitmap`, `IsJuliaVisible`,
  `SetSelection(const R: TRect; IsVisible: Boolean)`, `JuliaRect`, événements souris publics) ;
  `TMainForm` avec les champs `FView, FEngine, FJuliaEngine, FJuliaFormula, FNavigator, FFormula, FPalette,
  FMapping, FMapper, FAppEvents, FIsAutoIter, FAreColorsChanged, FIsUpdating, FMouseX, FMouseY,
  FStatusMessage`, et les méthodes `RenderCurrent`, `RebuildMapper`, `ColorsChanged`, `ColorizeBuffer(Engine;
  Bitmap)`, `UpdateStatus`, `WaitForRender(TimeoutMs): Boolean`, `RunSmokeTest(const OutputFile): Integer`
  (publique). Les tâches 11 à 15 ajoutent leurs méthodes à cette classe.
- La fiche `.dfm` contient **toute** la mise en page, y compris les contrôles que les tâches suivantes
  rendront actifs. Seuls `OnCreate`, `OnDestroy` et `OnKeyDown` du formulaire sont branchés dans le `.dfm`.

- [ ] **Step 1 : écrire `src/Fractal.View.pas`**

```pascal
unit Fractal.View;

interface

uses
  Windows, Messages, Classes, Controls, Graphics;

const
  kJuliaMargin = 12;

type
  // Zone d'affichage : dessine le bitmap calculé, l'aperçu Julia et le rectangle de sélection.
  TFractalView = class(TCustomControl)
  private
    FBitmap: TBitmap;
    FJuliaBitmap: TBitmap;
    FIsJuliaVisible: Boolean;
    FSelection: TRect;
    FHasSelection: Boolean;
    procedure SetJuliaVisible(Value: Boolean);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetSelection(const R: TRect; IsVisible: Boolean);
    function JuliaRect: TRect;
    property Bitmap: TBitmap read FBitmap;
    property JuliaBitmap: TBitmap read FJuliaBitmap;
    property IsJuliaVisible: Boolean read FIsJuliaVisible write SetJuliaVisible;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnResize;
  end;

implementation

//SEP

constructor TFractalView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  Color := clBlack;
  FBitmap := TBitmap.Create;
  FBitmap.PixelFormat := pf32bit;
  FJuliaBitmap := TBitmap.Create;
  FJuliaBitmap.PixelFormat := pf32bit;
end;

//SEP

destructor TFractalView.Destroy;
begin
  FJuliaBitmap.Free;
  FBitmap.Free;
  inherited Destroy;
end;

//SEP

procedure TFractalView.SetJuliaVisible(Value: Boolean);
begin
  if FIsJuliaVisible = Value then
    Exit;
  FIsJuliaVisible := Value;
  Invalidate;
end;

//SEP

procedure TFractalView.SetSelection(const R: TRect; IsVisible: Boolean);
begin
  FSelection := R;
  FHasSelection := IsVisible;
  Invalidate;
end;

//SEP

function TFractalView.JuliaRect: TRect;
begin
  Result := Rect(ClientWidth - FJuliaBitmap.Width - kJuliaMargin, ClientHeight - FJuliaBitmap.Height - kJuliaMargin,
    ClientWidth - kJuliaMargin, ClientHeight - kJuliaMargin);
end;

//SEP

procedure TFractalView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;  // tout est repeint dans Paint : pas d'effacement, pas de scintillement
end;

//SEP

procedure TFractalView.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  Message.Result := DLGC_WANTARROWS;
end;

//SEP

procedure TFractalView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if CanFocus and not Focused then
    SetFocus;
  inherited MouseDown(Button, Shift, X, Y);
end;

//SEP

procedure TFractalView.Paint;
var
  R: TRect;
begin
  Canvas.Draw(0, 0, FBitmap);
  Canvas.Brush.Color := clBlack;
  if FBitmap.Width < ClientWidth then
    Canvas.FillRect(Rect(FBitmap.Width, 0, ClientWidth, ClientHeight));
  if FBitmap.Height < ClientHeight then
    Canvas.FillRect(Rect(0, FBitmap.Height, ClientWidth, ClientHeight));
  if FIsJuliaVisible and (FJuliaBitmap.Width > 0) then
  begin
    R := JuliaRect;
    Canvas.Draw(R.Left, R.Top, FJuliaBitmap);
    Canvas.Brush.Color := clWhite;
    Canvas.FrameRect(Rect(R.Left - 1, R.Top - 1, R.Right + 1, R.Bottom + 1));
  end;
  if FHasSelection then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := clWhite;
    Canvas.Rectangle(FSelection);
    Canvas.Pen.Color := clBlack;
    Canvas.Rectangle(FSelection.Left + 1, FSelection.Top + 1, FSelection.Right - 1, FSelection.Bottom - 1);
    Canvas.Brush.Style := bsSolid;
  end;
end;

end.
```

- [ ] **Step 2 : écrire `src/MainFrm.dfm`** (ASCII pur : `#233` = é, `#201` = É, `#9668` = ◄, `#9658` = ►,
  `#9733` = ★, `#9656` = ▸)

```
object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Fractales'
  ClientHeight = 720
  ClientWidth = 1200
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1200
    Height = 34
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblNavMode: TLabel
      Left = 376
      Top = 9
      Caption = 'Navigation :'
    end
    object btnOpen: TButton
      Left = 4
      Top = 4
      Width = 80
      Height = 26
      Caption = 'Ouvrir...'
      TabOrder = 0
    end
    object btnSave: TButton
      Left = 88
      Top = 4
      Width = 90
      Height = 26
      Caption = 'Enregistrer...'
      TabOrder = 1
    end
    object btnExportPng: TButton
      Left = 182
      Top = 4
      Width = 70
      Height = 26
      Caption = 'PNG...'
      TabOrder = 2
    end
    object btnHiRes: TButton
      Left = 256
      Top = 4
      Width = 100
      Height = 26
      Caption = 'Rendu HD...'
      TabOrder = 3
    end
    object cbNavMode: TComboBox
      Left = 452
      Top = 5
      Width = 130
      Height = 23
      Style = csDropDownList
      TabOrder = 4
    end
    object btnBack: TButton
      Left = 592
      Top = 4
      Width = 34
      Height = 26
      Hint = 'Pr'#233'c'#233'dent (Retour arri'#232're)'
      Caption = #9668
      ParentShowHint = False
      ShowHint = True
      TabOrder = 5
    end
    object btnForward: TButton
      Left = 628
      Top = 4
      Width = 34
      Height = 26
      Hint = 'Suivant'
      Caption = #9658
      ParentShowHint = False
      ShowHint = True
      TabOrder = 6
    end
    object btnAddFavorite: TButton
      Left = 672
      Top = 4
      Width = 90
      Height = 26
      Caption = #9733' Favori'
      TabOrder = 7
    end
    object btnTogglePanel: TButton
      Left = 766
      Top = 4
      Width = 100
      Height = 26
      Caption = 'Panneau (F4)'
      TabOrder = 8
    end
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 701
    Width = 1200
    Height = 19
    Panels = <
      item
        Width = 320
      end
      item
        Width = 130
      end
      item
        Width = 100
      end
      item
        Width = 170
      end
      item
        Width = 50
      end>
  end
  object pnlSide: TPanel
    Left = 920
    Top = 34
    Width = 280
    Height = 667
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 1
    object grpFormula: TGroupBox
      Left = 0
      Top = 0
      Width = 280
      Height = 210
      Align = alTop
      Caption = 'Formule'
      TabOrder = 0
      object lblMaxIter: TLabel
        Left = 8
        Top = 180
        Caption = 'It'#233'rations max'
      end
      object cbFormula: TComboBox
        Left = 8
        Top = 20
        Width = 262
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object pnlParams: TPanel
        Left = 8
        Top = 50
        Width = 262
        Height = 120
        BevelOuter = bvNone
        TabOrder = 1
      end
      object edMaxIter: TEdit
        Left = 100
        Top = 176
        Width = 80
        Height = 23
        TabOrder = 2
      end
      object chkAutoIter: TCheckBox
        Left = 190
        Top = 179
        Width = 70
        Height = 17
        Caption = 'auto'
        TabOrder = 3
      end
    end
    object grpColors: TGroupBox
      Left = 0
      Top = 210
      Width = 280
      Height = 185
      Align = alTop
      Caption = 'Couleurs'
      TabOrder = 1
      object lblOffset: TLabel
        Left = 8
        Top = 56
        Caption = 'D'#233'calage'
      end
      object lblRepeats: TLabel
        Left = 8
        Top = 88
        Caption = 'R'#233'p'#233'tition'
      end
      object lblStretch: TLabel
        Left = 8
        Top = 120
        Caption = #201'tirement'
      end
      object cbPalette: TComboBox
        Left = 8
        Top = 20
        Width = 180
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object btnEditPalette: TButton
        Left = 194
        Top = 19
        Width = 76
        Height = 25
        Caption = #201'diter...'
        TabOrder = 1
      end
      object tbOffset: TTrackBar
        Left = 80
        Top = 50
        Width = 190
        Height = 26
        Max = 1000
        TabOrder = 2
        TickStyle = tsNone
      end
      object tbRepeats: TTrackBar
        Left = 80
        Top = 82
        Width = 190
        Height = 26
        Max = 1000
        TabOrder = 3
        TickStyle = tsNone
      end
      object tbStretch: TTrackBar
        Left = 80
        Top = 114
        Width = 190
        Height = 26
        Max = 1000
        TabOrder = 4
        TickStyle = tsNone
      end
      object chkInvert: TCheckBox
        Left = 8
        Top = 152
        Width = 120
        Height = 17
        Caption = 'Inverser'
        TabOrder = 5
      end
    end
    object grpFavorites: TGroupBox
      Left = 0
      Top = 395
      Width = 280
      Height = 272
      Align = alClient
      Caption = 'Favoris'
      TabOrder = 2
      object lbFavorites: TListBox
        AlignWithMargins = True
        Left = 5
        Top = 20
        Width = 270
        Height = 247
        Align = alClient
        ItemHeight = 15
        TabOrder = 0
      end
    end
  end
  object splSide: TSplitter
    Left = 915
    Top = 34
    Width = 5
    Height = 667
    Align = alRight
    MinSize = 200
  end
  object pnlCollapse: TPanel
    Left = 899
    Top = 34
    Width = 16
    Height = 667
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 2
    object btnCollapse: TSpeedButton
      Left = 0
      Top = 0
      Width = 16
      Height = 667
      Hint = 'Masquer / afficher le panneau (F4)'
      Align = alClient
      Caption = #9656
      Flat = True
      ParentShowHint = False
      ShowHint = True
    end
  end
  object tmrDisplay: TTimer
    Interval = 33
    Left = 40
    Top = 80
  end
end
```

- [ ] **Step 3 : écrire `src/MainFrm.pas`**

```pascal
unit MainFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, ComCtrls, Buttons,
  AppEvnts, Math, Fractal.Types, Fractal.Formulas, Fractal.Engine, Fractal.Palette, Fractal.Navigation,
  Fractal.View;

const
  kJuliaPreviewWidth = 240;
  kJuliaPreviewHeight = 180;
  kJuliaPreviewMaxIter = 300;
  kJuliaPreviewViewWidth = 3.5;
  kJuliaThreadCount = 2;
  kKeyZoomFactor = 2.0;
  kSmokeTimeoutMs = 30000;
  kRenderPollMs = 20;

type
  TMainForm = class(TForm)
    pnlTop: TPanel;
    lblNavMode: TLabel;
    btnOpen: TButton;
    btnSave: TButton;
    btnExportPng: TButton;
    btnHiRes: TButton;
    cbNavMode: TComboBox;
    btnBack: TButton;
    btnForward: TButton;
    btnAddFavorite: TButton;
    btnTogglePanel: TButton;
    sbStatus: TStatusBar;
    pnlSide: TPanel;
    grpFormula: TGroupBox;
    lblMaxIter: TLabel;
    cbFormula: TComboBox;
    pnlParams: TPanel;
    edMaxIter: TEdit;
    chkAutoIter: TCheckBox;
    grpColors: TGroupBox;
    lblOffset: TLabel;
    lblRepeats: TLabel;
    lblStretch: TLabel;
    cbPalette: TComboBox;
    btnEditPalette: TButton;
    tbOffset: TTrackBar;
    tbRepeats: TTrackBar;
    tbStretch: TTrackBar;
    chkInvert: TCheckBox;
    grpFavorites: TGroupBox;
    lbFavorites: TListBox;
    splSide: TSplitter;
    pnlCollapse: TPanel;
    btnCollapse: TSpeedButton;
    tmrDisplay: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FView: TFractalView;
    FEngine: TRenderEngine;
    FJuliaEngine: TRenderEngine;
    FJuliaFormula: TJuliaFormula;
    FNavigator: TNavigator;
    FFormula: TFractalFormula;
    FPalette: TGradientPalette;
    FMapping: TColorMapping;
    FMapper: TColorMapper;
    FAppEvents: TApplicationEvents;
    FIsAutoIter: Boolean;
    FAreColorsChanged: Boolean;
    FIsUpdating: Boolean;
    FMouseX: Integer;
    FMouseY: Integer;
    FStatusMessage: string;
    procedure InitNavigation;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ViewResize(Sender: TObject);
    procedure NavigatorViewChanged(Sender: TObject; const Change: TViewChange);
    procedure NavigatorSelectionChanged(Sender: TObject);
    procedure NavigatorPrecisionLimit(Sender: TObject);
    procedure NavigatorJuliaPoint(Sender: TObject; const P: TComplexPoint);
    procedure NavModeChange(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure ForwardClick(Sender: TObject);
    procedure DisplayTimer(Sender: TObject);
    procedure RenderCurrent;
    procedure RebuildMapper;
    procedure ColorsChanged;
    procedure ColorizeBuffer(Engine: TRenderEngine; Bitmap: TBitmap);
    procedure SetPanelText(Index: Integer; const Text: string);
    procedure UpdateStatus;
    procedure UpdateHistoryButtons;
    function WaitForRender(TimeoutMs: Cardinal): Boolean;
  public
    function RunSmokeTest(const OutputFile: string): Integer;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

//SEP

function ToNavButton(Button: TMouseButton): TNavButton;
begin
  case Button of
    mbRight:
      Result := nbRight;
    mbMiddle:
      Result := nbMiddle;
  else
    Result := nbLeft;
  end;
end;

//SEP

function CountLitPixels(Bitmap: TBitmap): Integer;
var
  X, Y: Integer;
  P: PCardinal;
begin
  Result := 0;
  for Y := 0 to Bitmap.Height - 1 do
  begin
    P := Bitmap.ScanLine[Y];
    for X := 0 to Bitmap.Width - 1 do
    begin
      if P^ and $FFFFFF <> 0 then
        Inc(Result);
      Inc(P);
    end;
  end;
end;

//SEP

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FView := TFractalView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.OnMouseDown := ViewMouseDown;
  FView.OnMouseMove := ViewMouseMove;
  FView.OnMouseUp := ViewMouseUp;
  FView.OnResize := ViewResize;

  FEngine := TRenderEngine.Create(CpuCount);
  FJuliaEngine := TRenderEngine.Create(kJuliaThreadCount);
  FJuliaFormula := TJuliaFormula.Create;
  FJuliaFormula.MaxIter := kJuliaPreviewMaxIter;
  FFormula := TMandelbrotFormula.Create;
  FIsAutoIter := True;
  FPalette := CreateBuiltInPalette(0);
  FMapping := DefaultColorMapping;
  RebuildMapper;

  FAppEvents := TApplicationEvents.Create(Self);
  FAppEvents.OnMessage := AppMessage;
  tmrDisplay.OnTimer := DisplayTimer;
  InitNavigation;

  FNavigator.Reset(MakeViewport(FFormula.DefaultCenterX, FFormula.DefaultCenterY, FFormula.DefaultWidth,
    Max(1, FView.ClientWidth), Max(1, FView.ClientHeight)));
end;

//SEP

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  tmrDisplay.Enabled := False;
  FreeAndNil(FEngine);
  FreeAndNil(FJuliaEngine);
  FreeAndNil(FNavigator);
  FreeAndNil(FMapper);
  FreeAndNil(FPalette);
  FreeAndNil(FJuliaFormula);
  FreeAndNil(FFormula);
end;

//SEP

procedure TMainForm.InitNavigation;
var
  I: Integer;
begin
  FNavigator := TNavigator.Create;
  FNavigator.OnViewChanged := NavigatorViewChanged;
  FNavigator.OnSelectionChanged := NavigatorSelectionChanged;
  FNavigator.OnPrecisionLimit := NavigatorPrecisionLimit;
  FNavigator.OnJuliaPoint := NavigatorJuliaPoint;
  for I := 0 to High(kNavigationModes) do
    cbNavMode.Items.Add(kNavigationModes[I].DisplayName);
  cbNavMode.ItemIndex := 0;
  cbNavMode.OnChange := NavModeChange;
  btnBack.OnClick := BackClick;
  btnForward.OnClick := ForwardClick;
end;

//SEP

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    FNavigator.CancelSelection;
    Key := 0;
    Exit;
  end;
  // les touches de navigation ne doivent pas voler la saisie dans les champs du panneau
  if (ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox) or (ActiveControl is TCustomListBox)
    or (ActiveControl is TTrackBar) then
    Exit;
  case Key of
    VK_ADD, VK_OEM_PLUS:
      FNavigator.ZoomCenter(kKeyZoomFactor);
    VK_SUBTRACT, VK_OEM_MINUS:
      FNavigator.ZoomCenter(1 / kKeyZoomFactor);
    VK_LEFT:
      FNavigator.KeyPan(-1, 0);
    VK_RIGHT:
      FNavigator.KeyPan(1, 0);
    VK_UP:
      FNavigator.KeyPan(0, -1);
    VK_DOWN:
      FNavigator.KeyPan(0, 1);
    VK_BACK:
      FNavigator.GoBack;
  else
    Exit;
  end;
  Key := 0;
end;

//SEP

procedure TMainForm.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  P: TPoint;
begin
  // la molette va au contrôle sous le curseur, pas à celui qui a le focus
  if (Msg.message <> WM_MOUSEWHEEL) or not FView.HandleAllocated then
    Exit;
  P := Point(SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)));
  if WindowFromPoint(P) <> FView.Handle then
    Exit;
  P := FView.ScreenToClient(P);
  FNavigator.MouseWheel(SmallInt(HiWord(Msg.wParam)), P.X, P.Y);
  Handled := True;
end;

//SEP

procedure TMainForm.ViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FNavigator.MouseDown(ToNavButton(Button), X, Y);
end;

//SEP

procedure TMainForm.ViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FMouseX := X;
  FMouseY := Y;
  FNavigator.MouseMove(X, Y, ssLeft in Shift);
end;

//SEP

procedure TMainForm.ViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FNavigator.MouseUp(ToNavButton(Button), X, Y);
end;

//SEP

procedure TMainForm.ViewResize(Sender: TObject);
begin
  FNavigator.SetPixelSize(Max(1, FView.ClientWidth), Max(1, FView.ClientHeight));
end;

//SEP

procedure TMainForm.NavigatorViewChanged(Sender: TObject; const Change: TViewChange);
var
  V: TViewport;
begin
  V := FNavigator.Viewport;
  if FIsAutoIter then
    FFormula.MaxIter := AutoMaxIter(V);
  if Change.Kind = vckPan then
    FEngine.RenderShifted(V, FFormula, Change.DX, Change.DY)
  else
    FEngine.Render(V, FFormula);
  UpdateHistoryButtons;
end;

//SEP

procedure TMainForm.NavigatorSelectionChanged(Sender: TObject);
begin
  FView.SetSelection(FNavigator.SelectionRect, FNavigator.HasSelection);
end;

//SEP

procedure TMainForm.NavigatorPrecisionLimit(Sender: TObject);
begin
  FStatusMessage := 'Limite de précision atteinte : zoom bloqué.';
end;

//SEP

procedure TMainForm.NavigatorJuliaPoint(Sender: TObject; const P: TComplexPoint);
begin
  FJuliaFormula.SetParam(FJuliaFormula.IndexOfParam('cx'), P.X);
  FJuliaFormula.SetParam(FJuliaFormula.IndexOfParam('cy'), P.Y);
  FJuliaEngine.Render(MakeViewport(0, 0, kJuliaPreviewViewWidth, kJuliaPreviewWidth, kJuliaPreviewHeight),
    FJuliaFormula);
end;

//SEP

procedure TMainForm.NavModeChange(Sender: TObject);
begin
  FNavigator.SetMode(kNavigationModes[cbNavMode.ItemIndex]);
  FView.IsJuliaVisible := FNavigator.Mode is TJuliaNavigationMode;
  FView.SetFocus;
end;

//SEP

procedure TMainForm.BackClick(Sender: TObject);
begin
  FNavigator.GoBack;
end;

//SEP

procedure TMainForm.ForwardClick(Sender: TObject);
begin
  FNavigator.GoForward;
end;

//SEP

procedure TMainForm.UpdateHistoryButtons;
begin
  btnBack.Enabled := FNavigator.CanGoBack;
  btnForward.Enabled := FNavigator.CanGoForward;
end;

//SEP

procedure TMainForm.RenderCurrent;
begin
  FEngine.Render(FNavigator.Viewport, FFormula);
end;

//SEP

procedure TMainForm.RebuildMapper;
begin
  FreeAndNil(FMapper);
  FMapper := TColorMapper.Create(FPalette, FMapping);
end;

//SEP

procedure TMainForm.ColorsChanged;
begin
  RebuildMapper;
  FAreColorsChanged := True;
end;

//SEP

procedure TMainForm.ColorizeBuffer(Engine: TRenderEngine; Bitmap: TBitmap);
var
  Y: Integer;
begin
  if (Engine.Buffer.Width = 0) or (Engine.Buffer.Height = 0) then
    Exit;
  if (Bitmap.Width <> Engine.Buffer.Width) or (Bitmap.Height <> Engine.Buffer.Height) then
  begin
    Bitmap.PixelFormat := pf32bit;
    Bitmap.SetSize(Engine.Buffer.Width, Engine.Buffer.Height);
  end;
  for Y := 0 to Engine.Buffer.Height - 1 do
    FMapper.MapRow(Engine.Buffer.RowPtr(Y), Bitmap.ScanLine[Y], Engine.Buffer.Width);
end;

//SEP

procedure TMainForm.DisplayTimer(Sender: TObject);
var
  IsChanged: Boolean;
  Errors: string;
begin
  IsChanged := False;
  if FEngine.Buffer.TakeDirtyFlag or FAreColorsChanged then
  begin
    ColorizeBuffer(FEngine, FView.Bitmap);
    IsChanged := True;
  end;
  if FView.IsJuliaVisible and (FJuliaEngine.Buffer.TakeDirtyFlag or FAreColorsChanged) then
  begin
    ColorizeBuffer(FJuliaEngine, FView.JuliaBitmap);
    IsChanged := True;
  end;
  FAreColorsChanged := False;
  if IsChanged then
    FView.Invalidate;
  Errors := FEngine.TakeErrors;
  if Errors <> '' then
    FStatusMessage := 'Erreur de calcul : ' + Copy(Errors, 1, Pos(#13, Errors + #13) - 1);
  UpdateStatus;
end;

//SEP

procedure TMainForm.SetPanelText(Index: Integer; const Text: string);
begin
  if sbStatus.Panels[Index].Text <> Text then
    sbStatus.Panels[Index].Text := Text;
end;

//SEP

procedure TMainForm.UpdateStatus;
var
  V: TViewport;
  P: TComplexPoint;
  Digits: Integer;
  S: TRenderStatus;
  Msg: string;
begin
  V := FNavigator.Viewport;
  P := V.PixelToComplex(FMouseX, FMouseY);
  Digits := EnsureRange(Ceil(-Log10(V.PixelSize)) + 1, 3, 18);
  SetPanelText(0, 'x = ' + FloatToStrF(P.X, ffFixed, 18, Digits) + '   y = ' + FloatToStrF(P.Y, ffFixed, 18, Digits));
  SetPanelText(1, 'zoom ' + FormatFloat('0.00e+0', V.Zoom));
  SetPanelText(2, IntToStr(FFormula.MaxIter) + ' it.');
  S := FEngine.Status;
  if S.IsComplete then
    SetPanelText(3, Format('terminé en %d ms', [S.ElapsedMs]))
  else
    SetPanelText(3, Format('passe %d/%d   %d ms', [S.CurrentPass, S.PassCount, S.ElapsedMs]));
  Msg := FStatusMessage;
  if V.PrecisionState <> psOk then
    Msg := 'Limite de précision proche. ' + Msg;
  SetPanelText(4, Msg);
end;

//SEP

function TMainForm.WaitForRender(TimeoutMs: Cardinal): Boolean;
var
  Start: Cardinal;
begin
  Start := GetTickCount;
  repeat
    Application.ProcessMessages;
    if FEngine.WaitUntilComplete(kRenderPollMs) then
      Exit(True);
  until GetTickCount - Start > TimeoutMs;
  Result := False;
end;

//SEP

function TMainForm.RunSmokeTest(const OutputFile: string): Integer;
var
  Log: TStringList;
begin
  Result := 1;
  Log := TStringList.Create;
  try
    try
      Show;
      Application.ProcessMessages;
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu initial non terminé');
      DisplayTimer(nil);
      if CountLitPixels(FView.Bitmap) = 0 then
        raise Exception.Create('image entièrement noire');
      Log.Add(Format('Rendu initial OK : %d x %d en %d ms', [FView.Bitmap.Width, FView.Bitmap.Height,
        FEngine.Status.ElapsedMs]));
      FNavigator.ZoomCenter(4);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après zoom non terminé');
      Log.Add('Zoom OK');
      FNavigator.PanBy(25, -10);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après déplacement non terminé');
      Log.Add('Déplacement OK');
      Result := 0;
    except
      on E: Exception do
        Log.Add('ÉCHEC : ' + E.Message);
    end;
  finally
    Log.SaveToFile(OutputFile + '.log', TEncoding.UTF8);
    Log.Free;
  end;
end;

end.
```

- [ ] **Step 4 : écrire `Fractales.dpr`**

```pascal
program Fractales;

{$SETPEFLAGS $20}  // IMAGE_FILE_LARGE_ADDRESS_AWARE : 4 Go d'adressage sous Windows 64 bits

uses
  Forms,
  SysUtils,
  XPMan,
  Fractal.Types in 'src\Fractal.Types.pas',
  Fractal.Formulas in 'src\Fractal.Formulas.pas',
  Fractal.Buffer in 'src\Fractal.Buffer.pas',
  Fractal.Engine in 'src\Fractal.Engine.pas',
  Fractal.Palette in 'src\Fractal.Palette.pas',
  Fractal.Png in 'src\Fractal.Png.pas',
  Fractal.Persistence in 'src\Fractal.Persistence.pas',
  Fractal.Navigation in 'src\Fractal.Navigation.pas',
  Fractal.HiRes in 'src\Fractal.HiRes.pas',
  Fractal.View in 'src\Fractal.View.pas',
  MainFrm in 'src\MainFrm.pas' {MainForm};

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Fractales';
  Application.CreateForm(TMainForm, MainForm);
  if FindCmdLineSwitch('smoketest') then
    ExitCode := MainForm.RunSmokeTest(ParamStr(2))
  else
    Application.Run;
end.
```

Run : `tools/normalize.sh src/Fractal.View.pas src/MainFrm.pas src/MainFrm.dfm Fractales.dpr`

- [ ] **Step 5 : compiler et lancer le test de fumée**

Run : `./build.sh smoke`
Expected : code de sortie 0 et le journal affiche :

```
Rendu initial OK : <largeur> x <hauteur> en <n> ms
Zoom OK
Déplacement OK
```

Si un message « Property … does not exist » ou « Error reading … » apparaît, une propriété du `.dfm` est mal
orthographiée : la corriger à partir de l'aide de la classe concernée, puis relancer.

- [ ] **Step 6 : relancer les tests unitaires**

Run : `./build.sh tests`
Expected : `OK:` (81 tests).

- [ ] **Step 7 : commit**

```bash
git add src/Fractal.View.pas src/MainFrm.pas src/MainFrm.dfm Fractales.dpr
git commit -m "Fenêtre principale : affichage, navigation, aperçu Julia, test de fumée

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11 : panneau latéral — formule, paramètres, itérations, repli, plein écran

**Files :**
- Modify : `src/MainFrm.pas`

**Interfaces :**
- Consumes : `FormulaClassCount`, `FormulaClassAt`, `TFractalFormula.ParamCount/ParamInfo/GetParam/SetParam`,
  `AutoMaxIter`.
- Produces (méthodes privées de `TMainForm`) : `InitFormulaPanel`, `SetFormula(AFormula: TFractalFormula;
  IsResetView: Boolean)` (prend possession de `AFormula`), `BuildParamEditors`, `UpdateMaxIterControls`,
  `SetSidePanelVisible(IsVisible: Boolean)`, `ToggleFullScreen`. Utilisées par les tâches 14 et 15.

- [ ] **Step 1 : déclarations**

Dans la section `private` de `TMainForm`, après `FStatusMessage: string;`, ajouter :

```pascal
    FIsFullScreen: Boolean;
    FSavedBounds: TRect;
    FWasSidePanelVisible: Boolean;
```

et après `function WaitForRender(TimeoutMs: Cardinal): Boolean;` :

```pascal
    procedure InitFormulaPanel;
    procedure FormulaComboChange(Sender: TObject);
    procedure SetFormula(AFormula: TFractalFormula; IsResetView: Boolean);
    procedure BuildParamEditors;
    procedure ParamEditExit(Sender: TObject);
    procedure ParamEditKeyPress(Sender: TObject; var Key: Char);
    procedure ApplyParamEdit(Edit: TEdit);
    procedure MaxIterEditExit(Sender: TObject);
    procedure MaxIterEditKeyPress(Sender: TObject; var Key: Char);
    procedure ApplyMaxIterEdit;
    procedure AutoIterClick(Sender: TObject);
    procedure UpdateMaxIterControls;
    procedure TogglePanelClick(Sender: TObject);
    procedure SetSidePanelVisible(IsVisible: Boolean);
    procedure ToggleFullScreen;
```

Constantes à ajouter dans le bloc `const` de l'interface, après `kRenderPollMs = 20;` :

```pascal
  kParamRowHeight = 28;
  kParamLabelWidth = 120;
  kParamEditLeft = 130;
  kParamEditWidth = 120;
```

- [ ] **Step 2 : branchements**

Dans `FormCreate`, remplacer la ligne `  InitNavigation;` par :

```pascal
  InitNavigation;
  InitFormulaPanel;
```

Dans `NavigatorViewChanged`, remplacer :

```pascal
  if FIsAutoIter then
    FFormula.MaxIter := AutoMaxIter(V);
```

par :

```pascal
  if FIsAutoIter then
  begin
    FFormula.MaxIter := AutoMaxIter(V);
    UpdateMaxIterControls;
  end;
```

Dans `FormKeyDown`, au tout début du corps (avant `if Key = VK_ESCAPE then`), ajouter :

```pascal
  if Key = VK_F4 then
  begin
    SetSidePanelVisible(not pnlSide.Visible);
    Key := 0;
    Exit;
  end;
  if Key = VK_F11 then
  begin
    ToggleFullScreen;
    Key := 0;
    Exit;
  end;
```

- [ ] **Step 3 : implémentations**

Ajouter à la fin de l'unité, juste avant le `end.` final (chaque routine précédée d'une ligne vide, du
séparateur et d'une ligne vide) :

```pascal
//SEP

procedure TMainForm.InitFormulaPanel;
var
  I: Integer;
begin
  for I := 0 to FormulaClassCount - 1 do
    cbFormula.Items.Add(FormulaClassAt(I).DisplayName);
  cbFormula.OnChange := FormulaComboChange;
  edMaxIter.OnExit := MaxIterEditExit;
  edMaxIter.OnKeyPress := MaxIterEditKeyPress;
  chkAutoIter.OnClick := AutoIterClick;
  btnTogglePanel.OnClick := TogglePanelClick;
  btnCollapse.OnClick := TogglePanelClick;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I) = FFormula.ClassType then
      cbFormula.ItemIndex := I;
  BuildParamEditors;
  UpdateMaxIterControls;
end;

//SEP

procedure TMainForm.FormulaComboChange(Sender: TObject);
begin
  SetFormula(FormulaClassAt(cbFormula.ItemIndex).Create, True);
end;

//SEP

procedure TMainForm.SetFormula(AFormula: TFractalFormula; IsResetView: Boolean);
var
  I: Integer;
begin
  FFormula.Free;
  FFormula := AFormula;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I) = FFormula.ClassType then
      cbFormula.ItemIndex := I;
  BuildParamEditors;
  UpdateMaxIterControls;
  if IsResetView then
    FNavigator.Reset(MakeViewport(FFormula.DefaultCenterX, FFormula.DefaultCenterY, FFormula.DefaultWidth,
      Max(1, FView.ClientWidth), Max(1, FView.ClientHeight)))
  else
    RenderCurrent;
end;

//SEP

procedure TMainForm.BuildParamEditors;
var
  I: Integer;
  L: TLabel;
  E: TEdit;
begin
  // détacher OnExit avant de libérer : un champ qui perd le focus en mourant ne doit rien appliquer
  for I := 0 to pnlParams.ControlCount - 1 do
    if pnlParams.Controls[I] is TEdit then
      TEdit(pnlParams.Controls[I]).OnExit := nil;
  while pnlParams.ControlCount > 0 do
    pnlParams.Controls[0].Free;
  for I := 0 to FFormula.ParamCount - 1 do
  begin
    L := TLabel.Create(Self);
    L.Parent := pnlParams;
    L.Caption := FFormula.ParamInfo(I).Caption;
    L.SetBounds(0, I * kParamRowHeight + 4, kParamLabelWidth, 20);
    E := TEdit.Create(Self);
    E.Parent := pnlParams;
    E.SetBounds(kParamEditLeft, I * kParamRowHeight, kParamEditWidth, 22);
    E.Text := FloatToStr(FFormula.GetParam(I));
    E.Tag := I;
    E.OnExit := ParamEditExit;
    E.OnKeyPress := ParamEditKeyPress;
  end;
end;

//SEP

procedure TMainForm.ParamEditExit(Sender: TObject);
begin
  ApplyParamEdit(TEdit(Sender));
end;

//SEP

procedure TMainForm.ParamEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    ApplyParamEdit(TEdit(Sender));
    Key := #0;
  end;
end;

//SEP

procedure TMainForm.ApplyParamEdit(Edit: TEdit);
var
  Value: Double;
  Index: Integer;
begin
  Index := Edit.Tag;
  if TryStrToFloat(Edit.Text, Value) then
  begin
    if Value <> FFormula.GetParam(Index) then
    begin
      FFormula.SetParam(Index, Value);
      RenderCurrent;
    end;
  end
  else
    FStatusMessage := Format('Valeur invalide pour « %s ».', [FFormula.ParamInfo(Index).Caption]);
  Edit.Text := FloatToStr(FFormula.GetParam(Index));
end;

//SEP

procedure TMainForm.MaxIterEditExit(Sender: TObject);
begin
  ApplyMaxIterEdit;
end;

//SEP

procedure TMainForm.MaxIterEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    ApplyMaxIterEdit;
    Key := #0;
  end;
end;

//SEP

procedure TMainForm.ApplyMaxIterEdit;
var
  Value: Integer;
begin
  if TryStrToInt(edMaxIter.Text, Value) and (Value <> FFormula.MaxIter) then
  begin
    FFormula.MaxIter := Value;
    FIsAutoIter := False;
    RenderCurrent;
  end;
  UpdateMaxIterControls;
end;

//SEP

procedure TMainForm.AutoIterClick(Sender: TObject);
begin
  if FIsUpdating then
    Exit;
  FIsAutoIter := chkAutoIter.Checked;
  if FIsAutoIter then
  begin
    FFormula.MaxIter := AutoMaxIter(FNavigator.Viewport);
    RenderCurrent;
  end;
  UpdateMaxIterControls;
end;

//SEP

procedure TMainForm.UpdateMaxIterControls;
begin
  FIsUpdating := True;
  try
    edMaxIter.Text := IntToStr(FFormula.MaxIter);
    chkAutoIter.Checked := FIsAutoIter;
  finally
    FIsUpdating := False;
  end;
end;

//SEP

procedure TMainForm.TogglePanelClick(Sender: TObject);
begin
  SetSidePanelVisible(not pnlSide.Visible);
end;

//SEP

procedure TMainForm.SetSidePanelVisible(IsVisible: Boolean);
begin
  if IsVisible then
  begin
    // ordre des contrôles alignés à droite : bande de repli, séparateur, panneau
    pnlSide.Left := ClientWidth;
    pnlSide.Visible := True;
    splSide.Left := pnlSide.Left - 1;
    splSide.Visible := True;
    btnCollapse.Caption := #9656;
  end
  else
  begin
    splSide.Visible := False;
    pnlSide.Visible := False;
    btnCollapse.Caption := #9666;
  end;
end;

//SEP

procedure TMainForm.ToggleFullScreen;
begin
  FIsFullScreen := not FIsFullScreen;
  if FIsFullScreen then
  begin
    FSavedBounds := BoundsRect;
    FWasSidePanelVisible := pnlSide.Visible;
    pnlTop.Visible := False;
    sbStatus.Visible := False;
    SetSidePanelVisible(False);
    pnlCollapse.Visible := False;
    BorderStyle := bsNone;
    BoundsRect := Monitor.BoundsRect;
  end
  else
  begin
    BorderStyle := bsSizeable;
    BoundsRect := FSavedBounds;
    pnlTop.Visible := True;
    sbStatus.Visible := True;
    pnlCollapse.Visible := True;
    SetSidePanelVisible(FWasSidePanelVisible);
  end;
end;
```

Ajouter à `RunSmokeTest`, juste avant `Result := 0;` :

```pascal
      SetFormula(TMultibrotFormula.Create, True);
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu Multibrot non terminé');
      if pnlParams.ControlCount <> 2 then
        raise Exception.Create('éditeur de paramètres Multibrot absent');
      SetSidePanelVisible(False);
      SetSidePanelVisible(True);
      if not pnlSide.Visible then
        raise Exception.Create('panneau latéral non restauré');
      Log.Add('Formules et panneau OK');
```

Run : `tools/normalize.sh src/MainFrm.pas`

- [ ] **Step 4 : test de fumée**

Run : `./build.sh smoke`
Expected : code 0, journal terminé par `Formules et panneau OK`.

- [ ] **Step 5 : commit**

```bash
git add src/MainFrm.pas
git commit -m "Panneau latéral : formule, paramètres, itérations, repli et plein écran

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12 : couleurs — palettes et réglages en direct

**Files :**
- Modify : `src/MainFrm.pas`

**Interfaces :**
- Consumes : `BuiltInPaletteCount`, `CreateBuiltInPalette`, `TGradientPalette.LoadFromStrings/LoadFromMap`,
  `MappingFromSliders`, `MappingToSliders` (5) ; `PaletteFolder` (7).
- Produces : `FPalettes: TObjectList` (palettes proposées), `FillPaletteCombo`, `UpdateColorControls` (utilisées
  par les tâches 13 et 14).

- [ ] **Step 1 : déclarations**

Dans la clause `uses` de l'interface, ajouter `Contnrs` après `Math,` et `Fractal.Persistence` après
`Fractal.Navigation,`.

Champs privés, après `FWasSidePanelVisible: Boolean;` :

```pascal
    FPalettes: TObjectList;
```

Méthodes privées, après `procedure ToggleFullScreen;` :

```pascal
    procedure InitColorPanel;
    procedure FillPaletteCombo;
    procedure PaletteComboChange(Sender: TObject);
    procedure ColorSliderChange(Sender: TObject);
    procedure UpdateColorControls;
```

- [ ] **Step 2 : branchements**

Dans `FormCreate`, remplacer `  InitFormulaPanel;` par :

```pascal
  InitFormulaPanel;
  InitColorPanel;
```

Dans `FormDestroy`, après `FreeAndNil(FPalette);`, ajouter :

```pascal
  FreeAndNil(FPalettes);
```

- [ ] **Step 3 : implémentations** (à la fin de l'unité, avant `end.`)

```pascal
//SEP

procedure TMainForm.InitColorPanel;
begin
  FPalettes := TObjectList.Create(True);
  FillPaletteCombo;
  cbPalette.ItemIndex := 0;
  cbPalette.OnChange := PaletteComboChange;
  tbOffset.OnChange := ColorSliderChange;
  tbRepeats.OnChange := ColorSliderChange;
  tbStretch.OnChange := ColorSliderChange;
  chkInvert.OnClick := ColorSliderChange;
  UpdateColorControls;
end;

//SEP

procedure TMainForm.FillPaletteCombo;
var
  I: Integer;
  Folder, Ext: string;
  SR: TSearchRec;
  P: TGradientPalette;
  Lines: TStringList;
begin
  FPalettes.Clear;
  cbPalette.Items.Clear;
  for I := 0 to BuiltInPaletteCount - 1 do
    FPalettes.Add(CreateBuiltInPalette(I));
  Folder := PaletteFolder;
  if FindFirst(Folder + '*.*', faAnyFile, SR) = 0 then
    try
      repeat
        Ext := LowerCase(ExtractFileExt(SR.Name));
        if (Ext <> '.pal') and (Ext <> '.map') then
          Continue;
        P := TGradientPalette.Create;
        Lines := TStringList.Create;
        try
          try
            Lines.LoadFromFile(Folder + SR.Name);
            if Ext = '.map' then
              P.LoadFromMap(Lines)
            else
              P.LoadFromStrings(Lines);
            if (Ext = '.map') or (P.Name = '') then
              P.Name := ChangeFileExt(SR.Name, '');
            FPalettes.Add(P);
            P := nil;
          except
            on E: Exception do
              FStatusMessage := Format('Palette ignorée (%s) : %s', [SR.Name, E.Message]);
          end;
        finally
          Lines.Free;
          P.Free;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  for I := 0 to FPalettes.Count - 1 do
    cbPalette.Items.Add(TGradientPalette(FPalettes[I]).Name);
end;

//SEP

procedure TMainForm.PaletteComboChange(Sender: TObject);
begin
  if cbPalette.ItemIndex < 0 then
    Exit;
  FPalette.Assign(TGradientPalette(FPalettes[cbPalette.ItemIndex]));
  ColorsChanged;
end;

//SEP

procedure TMainForm.ColorSliderChange(Sender: TObject);
begin
  if FIsUpdating then
    Exit;
  FMapping := MappingFromSliders(tbOffset.Position, tbRepeats.Position, tbStretch.Position, chkInvert.Checked);
  ColorsChanged;
end;

//SEP

procedure TMainForm.UpdateColorControls;
var
  Offset, Repeats, Stretch: Integer;
begin
  FIsUpdating := True;
  try
    MappingToSliders(FMapping, Offset, Repeats, Stretch);
    tbOffset.Position := Offset;
    tbRepeats.Position := Repeats;
    tbStretch.Position := Stretch;
    chkInvert.Checked := FMapping.IsInverted;
  finally
    FIsUpdating := False;
  end;
end;
```

Note : `Continue` dans un `repeat … until FindNext(SR) <> 0` saute bien à la condition, donc au fichier
suivant.

Ajouter à `RunSmokeTest`, avant `Result := 0;` :

```pascal
      tbOffset.Position := 500;
      chkInvert.Checked := True;
      if not FMapping.IsInverted or (Abs(FMapping.Offset - 0.5) > 1e-9) then
        raise Exception.Create('réglages de couleur non appliqués');
      cbPalette.ItemIndex := 1;
      PaletteComboChange(nil);
      DisplayTimer(nil);
      Log.Add('Couleurs OK');
```

Run : `tools/normalize.sh src/MainFrm.pas`

- [ ] **Step 4 : test de fumée**

Run : `./build.sh smoke`
Expected : code 0, journal terminé par `Couleurs OK`.

- [ ] **Step 5 : commit**

```bash
git add src/MainFrm.pas
git commit -m "Palettes et réglages de couleur sans recalcul

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13 : éditeur de palette

**Files :**
- Create : `src/PaletteEditorFrm.pas`, `src/PaletteEditorFrm.dfm`
- Modify : `src/MainFrm.pas`, `Fractales.dpr`

**Interfaces :**
- Consumes : `TGradientPalette` (toutes ses méthodes), `SwapRedBlue` (5) ; `PaletteFolder`, `SanitizeFileName`
  (7) ; `FillPaletteCombo`, `ColorsChanged` (10, 12).
- Produces : `TPaletteEditorForm` (propriétés `Palette: TGradientPalette` (copie de travail, appartient au
  dialogue) et `OnPaletteChange: TNotifyEvent`, appelé à chaque modification pour l'aperçu en direct).
- Cycle de vie : l'appelant crée le dialogue, `ShowModal`, puis le libère (try/finally). En cas d'annulation,
  l'appelant restaure sa palette d'origine.

- [ ] **Step 1 : écrire `src/PaletteEditorFrm.dfm`**

```
object PaletteEditorForm: TPaletteEditorForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = #201'diteur de palette'
  ClientHeight = 232
  ClientWidth = 620
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  Position = poOwnerFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 15
  object lblName: TLabel
    Left = 12
    Top = 15
    Caption = 'Nom :'
  end
  object lblHelp: TLabel
    Left = 12
    Top = 128
    Caption = 
      'Glisser un point pour le d'#233'placer ; double-clic pour ajouter un point ou ' +
      'changer sa couleur ; Suppr pour l'#39'effacer.'
  end
  object pbGradient: TPaintBox
    Left = 12
    Top = 44
    Width = 596
    Height = 78
    OnMouseDown = pbGradientMouseDown
    OnMouseMove = pbGradientMouseMove
    OnMouseUp = pbGradientMouseUp
    OnPaint = pbGradientPaint
  end
  object edName: TEdit
    Left = 60
    Top = 11
    Width = 250
    Height = 23
    TabOrder = 0
    OnChange = edNameChange
  end
  object btnColor: TButton
    Left = 12
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Couleur...'
    TabOrder = 1
    OnClick = btnColorClick
  end
  object btnDelete: TButton
    Left = 118
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Supprimer'
    TabOrder = 2
    OnClick = btnDeleteClick
  end
  object btnLoad: TButton
    Left = 224
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Charger...'
    TabOrder = 3
    OnClick = btnLoadClick
  end
  object btnSave: TButton
    Left = 330
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Enregistrer...'
    TabOrder = 4
    OnClick = btnSaveClick
  end
  object btnImportMap: TButton
    Left = 436
    Top = 156
    Width = 120
    Height = 26
    Caption = 'Importer .map...'
    TabOrder = 5
    OnClick = btnImportMapClick
  end
  object btnOK: TButton
    Left = 452
    Top = 196
    Width = 75
    Height = 26
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 6
  end
  object btnCancel: TButton
    Left = 533
    Top = 196
    Width = 75
    Height = 26
    Cancel = True
    Caption = 'Annuler'
    ModalResult = 2
    TabOrder = 7
  end
  object dlgColor: TColorDialog
    Options = [cdFullOpen]
    Left = 560
    Top = 4
  end
  object dlgOpen: TOpenDialog
    Options = [ofHideReadOnly, ofFileMustExist, ofEnableSizing]
    Left = 520
    Top = 4
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'pal'
    Filter = 'Palette (*.pal)|*.pal'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Left = 480
    Top = 4
  end
end
```

- [ ] **Step 2 : écrire `src/PaletteEditorFrm.pas`**

```pascal
unit PaletteEditorFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ExtCtrls, Math,
  Fractal.Palette, Fractal.Persistence;

const
  kGradientHeight = 56;
  kMarkerTop = 60;
  kMarkerSize = 8;
  kHitTolerance = 6;
  kMinStops = 2;

type
  TPaletteEditorForm = class(TForm)
    lblName: TLabel;
    lblHelp: TLabel;
    pbGradient: TPaintBox;
    edName: TEdit;
    btnColor: TButton;
    btnDelete: TButton;
    btnLoad: TButton;
    btnSave: TButton;
    btnImportMap: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    dlgColor: TColorDialog;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure pbGradientPaint(Sender: TObject);
    procedure pbGradientMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbGradientMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbGradientMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure edNameChange(Sender: TObject);
    procedure btnColorClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnImportMapClick(Sender: TObject);
  private
    FPalette: TGradientPalette;
    FSelected: Integer;
    FIsDragging: Boolean;
    FOnPaletteChange: TNotifyEvent;
    function StopAtX(X: Integer): Integer;
    function PositionOfX(X: Integer): Double;
    function XOfPosition(Position: Double): Integer;
    procedure EditSelectedColor;
    procedure LoadPaletteFile(const FileName: string; IsMap: Boolean);
    procedure PaletteChanged;
  public
    property Palette: TGradientPalette read FPalette;
    property OnPaletteChange: TNotifyEvent read FOnPaletteChange write FOnPaletteChange;
  end;

implementation

{$R *.dfm}

const
  kPaletteFilter = 'Palette (*.pal)|*.pal';
  kMapFilter = 'Palette Fractint (*.map)|*.map';

//SEP

procedure TPaletteEditorForm.FormCreate(Sender: TObject);
begin
  FPalette := TGradientPalette.Create;
  dlgOpen.InitialDir := PaletteFolder;
  dlgSave.InitialDir := PaletteFolder;
end;

//SEP

procedure TPaletteEditorForm.FormDestroy(Sender: TObject);
begin
  FPalette.Free;
end;

//SEP

procedure TPaletteEditorForm.FormShow(Sender: TObject);
begin
  edName.Text := FPalette.Name;
  FSelected := 0;
  pbGradient.Invalidate;
end;

//SEP

procedure TPaletteEditorForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (ActiveControl <> edName) then
  begin
    btnDeleteClick(nil);
    Key := 0;
  end;
end;

//SEP

function TPaletteEditorForm.XOfPosition(Position: Double): Integer;
begin
  Result := Round(Position * (pbGradient.Width - 1));
end;

//SEP

function TPaletteEditorForm.PositionOfX(X: Integer): Double;
begin
  Result := EnsureRange(X / (pbGradient.Width - 1), 0.0, 1.0);
end;

//SEP

function TPaletteEditorForm.StopAtX(X: Integer): Integer;
var
  I, Distance, Best: Integer;
begin
  Result := -1;
  Best := kHitTolerance + 1;
  for I := 0 to FPalette.StopCount - 1 do
  begin
    Distance := Abs(XOfPosition(FPalette.Stop(I).Position) - X);
    if Distance < Best then
    begin
      Best := Distance;
      Result := I;
    end;
  end;
end;

//SEP

procedure TPaletteEditorForm.pbGradientPaint(Sender: TObject);
var
  X, I, W: Integer;
  S: TColorStop;
  C: TCanvas;
begin
  C := pbGradient.Canvas;
  W := pbGradient.Width;
  for X := 0 to W - 1 do
  begin
    C.Pen.Color := TColor(SwapRedBlue(FPalette.ColorAt(X / W)));
    C.MoveTo(X, 0);
    C.LineTo(X, kGradientHeight);
  end;
  C.Brush.Color := clBtnFace;
  C.FillRect(Rect(0, kGradientHeight, W, pbGradient.Height));
  for I := 0 to FPalette.StopCount - 1 do
  begin
    S := FPalette.Stop(I);
    X := XOfPosition(S.Position);
    C.Brush.Color := TColor(SwapRedBlue(S.Color));
    if I = FSelected then
    begin
      C.Pen.Color := clHighlight;
      C.Pen.Width := 2;
    end
    else
    begin
      C.Pen.Color := clBlack;
      C.Pen.Width := 1;
    end;
    C.Polygon([Point(X, kMarkerTop), Point(X - kMarkerSize, kMarkerTop + 2 * kMarkerSize),
      Point(X + kMarkerSize, kMarkerTop + 2 * kMarkerSize)]);
  end;
  C.Pen.Width := 1;
end;

//SEP

procedure TPaletteEditorForm.pbGradientMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  I: Integer;
begin
  if Button <> mbLeft then
    Exit;
  I := StopAtX(X);
  if ssDouble in Shift then
  begin
    FIsDragging := False;
    if I < 0 then
    begin
      FSelected := FPalette.AddStop(PositionOfX(X), FPalette.ColorAt(PositionOfX(X)));
      PaletteChanged;
    end
    else
      FSelected := I;
    pbGradient.Invalidate;
    EditSelectedColor;
    Exit;
  end;
  if I >= 0 then
  begin
    FSelected := I;
    FIsDragging := True;
    pbGradient.Invalidate;
  end;
end;

//SEP

procedure TPaletteEditorForm.pbGradientMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if not FIsDragging then
    Exit;
  FSelected := FPalette.MoveStop(FSelected, PositionOfX(X));
  pbGradient.Invalidate;
  PaletteChanged;
end;

//SEP

procedure TPaletteEditorForm.pbGradientMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FIsDragging := False;
end;

//SEP

procedure TPaletteEditorForm.edNameChange(Sender: TObject);
begin
  FPalette.Name := edName.Text;
end;

//SEP

procedure TPaletteEditorForm.EditSelectedColor;
begin
  if (FSelected < 0) or (FSelected >= FPalette.StopCount) then
    Exit;
  dlgColor.Color := TColor(SwapRedBlue(FPalette.Stop(FSelected).Color));
  if not dlgColor.Execute then
    Exit;
  FPalette.SetStopColor(FSelected, SwapRedBlue(Cardinal(ColorToRGB(dlgColor.Color))));
  pbGradient.Invalidate;
  PaletteChanged;
end;

//SEP

procedure TPaletteEditorForm.btnColorClick(Sender: TObject);
begin
  EditSelectedColor;
end;

//SEP

procedure TPaletteEditorForm.btnDeleteClick(Sender: TObject);
begin
  if FPalette.StopCount <= kMinStops then
  begin
    MessageDlg('Une palette doit garder au moins deux points.', mtInformation, [mbOK], 0);
    Exit;
  end;
  FPalette.DeleteStop(FSelected);
  FSelected := Min(FSelected, FPalette.StopCount - 1);
  pbGradient.Invalidate;
  PaletteChanged;
end;

//SEP

procedure TPaletteEditorForm.LoadPaletteFile(const FileName: string; IsMap: Boolean);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName);
      if IsMap then
        FPalette.LoadFromMap(Lines)
      else
        FPalette.LoadFromStrings(Lines);
      if IsMap or (FPalette.Name = '') then
        FPalette.Name := ChangeFileExt(ExtractFileName(FileName), '');
      edName.Text := FPalette.Name;
      FSelected := 0;
      pbGradient.Invalidate;
      PaletteChanged;
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
  end;
end;

//SEP

procedure TPaletteEditorForm.btnLoadClick(Sender: TObject);
begin
  dlgOpen.Filter := kPaletteFilter;
  if dlgOpen.Execute then
    LoadPaletteFile(dlgOpen.FileName, False);
end;

//SEP

procedure TPaletteEditorForm.btnImportMapClick(Sender: TObject);
begin
  dlgOpen.Filter := kMapFilter;
  if dlgOpen.Execute then
    LoadPaletteFile(dlgOpen.FileName, True);
end;

//SEP

procedure TPaletteEditorForm.btnSaveClick(Sender: TObject);
var
  Lines: TStringList;
begin
  dlgSave.FileName := SanitizeFileName(FPalette.Name) + '.pal';
  if not dlgSave.Execute then
    Exit;
  Lines := TStringList.Create;
  try
    FPalette.SaveToStrings(Lines);
    try
      Lines.SaveToFile(dlgSave.FileName, TEncoding.UTF8);
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Lines.Free;
  end;
end;

//SEP

procedure TPaletteEditorForm.PaletteChanged;
begin
  if Assigned(FOnPaletteChange) then
    FOnPaletteChange(Self);
end;

end.
```

- [ ] **Step 3 : brancher l'éditeur dans `MainFrm.pas`**

Clause `uses` de l'implémentation : juste après `{$R *.dfm}`, ajouter :

```pascal
uses
  PaletteEditorFrm;
```

Méthodes privées, après `procedure UpdateColorControls;` :

```pascal
    procedure EditPaletteClick(Sender: TObject);
    procedure PaletteEditorChange(Sender: TObject);
```

Dans `InitColorPanel`, après `chkInvert.OnClick := ColorSliderChange;`, ajouter :

```pascal
  btnEditPalette.OnClick := EditPaletteClick;
```

À la fin de l'unité, avant `end.` :

```pascal
//SEP

procedure TMainForm.EditPaletteClick(Sender: TObject);
var
  Dlg: TPaletteEditorForm;
  Saved: TGradientPalette;
begin
  Saved := TGradientPalette.Create;
  Dlg := TPaletteEditorForm.Create(Self);
  try
    Saved.Assign(FPalette);
    Dlg.Palette.Assign(FPalette);
    Dlg.OnPaletteChange := PaletteEditorChange;
    if Dlg.ShowModal = mrOk then
    begin
      // la palette modifiée n'est pas forcément enregistrée : on recharge la liste sans la sélectionner
      FillPaletteCombo;
      cbPalette.ItemIndex := -1;
    end
    else
      FPalette.Assign(Saved);
    ColorsChanged;
  finally
    Dlg.Free;
    Saved.Free;
  end;
end;

//SEP

procedure TMainForm.PaletteEditorChange(Sender: TObject);
begin
  FPalette.Assign(TPaletteEditorForm(Sender).Palette);
  ColorsChanged;
end;
```

Ajouter à `RunSmokeTest`, avant `Result := 0;` :

```pascal
      with TPaletteEditorForm.Create(Self) do
        try
          Palette.Assign(FPalette);
          Show;
          Application.ProcessMessages;
          Close;
        finally
          Free;
        end;
      Log.Add('Éditeur de palette OK');
```

Dans `Fractales.dpr`, remplacer `MainFrm in 'src\MainFrm.pas' {MainForm};` par :

```pascal
  MainFrm in 'src\MainFrm.pas' {MainForm},
  PaletteEditorFrm in 'src\PaletteEditorFrm.pas' {PaletteEditorForm};
```

Run : `tools/normalize.sh src/PaletteEditorFrm.pas src/PaletteEditorFrm.dfm src/MainFrm.pas Fractales.dpr`

- [ ] **Step 4 : test de fumée**

Run : `./build.sh smoke`
Expected : code 0, journal terminé par `Éditeur de palette OK`.

- [ ] **Step 5 : commit**

```bash
git add src/PaletteEditorFrm.pas src/PaletteEditorFrm.dfm src/MainFrm.pas Fractales.dpr
git commit -m "Éditeur de palette avec aperçu en direct

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14 : fichiers — ouvrir, enregistrer, exporter en PNG, favoris

**Files :**
- Modify : `src/MainFrm.pas`

**Interfaces :**
- Consumes : `TFractalLocation`, `TFavoriteStore`, `FavoritesFolder`, `EFractalFileError` (7) ; `TPngWriter`,
  `ReadPngText`, `kLocationKeyword` (6) ; `SetFormula`, `UpdateColorControls`, `FillPaletteCombo` (11, 12).
- Produces : `CaptureLocation: TFractalLocation` (l'appelant libère), `ApplyLocation(Location)`,
  `LocationAsPngText(Location): RawByteString`, `ExportViewPng(const FileName)` (utilisées par la tâche 15).

- [ ] **Step 1 : déclarations**

Clause `uses` de l'interface : ajouter `Fractal.Png` après `Fractal.Palette,`.

Champs privés, après `FPalettes: TObjectList;` :

```pascal
    FFavorites: TFavoriteStore;
```

Méthodes privées, après `procedure PaletteEditorChange(Sender: TObject);` :

```pascal
    procedure InitFilePanel;
    function CaptureLocation: TFractalLocation;
    procedure ApplyLocation(Location: TFractalLocation);
    function LocationAsPngText(Location: TFractalLocation): RawByteString;
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ExportPngClick(Sender: TObject);
    procedure ExportViewPng(const FileName: string);
    procedure AddFavoriteClick(Sender: TObject);
    procedure FavoritesDblClick(Sender: TObject);
    procedure FavoritesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RefreshFavorites;
```

Constantes, après `kParamEditWidth = 120;` :

```pascal
  kExportWaitMs = 60000;
  kFracFilter = 'Lieu fractal (*.frac)|*.frac';
  kPngFilter = 'Image PNG (*.png)|*.png';
```

- [ ] **Step 2 : branchements**

Dans `FormCreate`, remplacer `  InitColorPanel;` par :

```pascal
  InitColorPanel;
  InitFilePanel;
```

Dans `FormDestroy`, après `FreeAndNil(FPalettes);` :

```pascal
  FreeAndNil(FFavorites);
```

- [ ] **Step 3 : implémentations** (à la fin de l'unité, avant `end.`)

```pascal
//SEP

procedure TMainForm.InitFilePanel;
begin
  FFavorites := TFavoriteStore.Create(FavoritesFolder);
  btnOpen.OnClick := OpenClick;
  btnSave.OnClick := SaveClick;
  btnExportPng.OnClick := ExportPngClick;
  btnAddFavorite.OnClick := AddFavoriteClick;
  lbFavorites.OnDblClick := FavoritesDblClick;
  lbFavorites.OnKeyDown := FavoritesKeyDown;
  RefreshFavorites;
end;

//SEP

function TMainForm.CaptureLocation: TFractalLocation;
begin
  Result := TFractalLocation.Create;
  Result.CaptureFrom(FFormula, FNavigator.Viewport, FIsAutoIter, FPalette, FMapping);
end;

//SEP

procedure TMainForm.ApplyLocation(Location: TFractalLocation);
var
  V: TViewport;
  Formula: TFractalFormula;
begin
  Formula := Location.CreateFormula;
  FIsAutoIter := Location.IsAutoIter;
  FPalette.Assign(Location.Palette);
  FMapping := Location.Mapping;
  cbPalette.ItemIndex := -1;
  UpdateColorControls;
  ColorsChanged;
  SetFormula(Formula, False);
  V := FNavigator.Viewport;
  Location.ApplyTo(V);
  FNavigator.Reset(V);
end;

//SEP

function TMainForm.LocationAsPngText(Location: TFractalLocation): RawByteString;
begin
  Result := UTF8Encode(Location.SaveToText);
end;

//SEP

procedure TMainForm.OpenClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  Location: TFractalLocation;
  Text: RawByteString;
begin
  Dlg := TOpenDialog.Create(nil);
  Location := TFractalLocation.Create;
  try
    Dlg.Filter := 'Lieux et images (*.frac;*.png)|*.frac;*.png|' + kFracFilter + '|' + kPngFilter;
    Dlg.Options := Dlg.Options + [ofFileMustExist];
    if not Dlg.Execute then
      Exit;
    try
      if SameText(ExtractFileExt(Dlg.FileName), '.png') then
      begin
        if not ReadPngText(Dlg.FileName, kLocationKeyword, Text) then
        begin
          MessageDlg('Ce PNG ne contient pas de lieu fractal : il ne peut pas être rouvert dans l''application.',
            mtInformation, [mbOK], 0);
          Exit;
        end;
        Location.LoadFromText(UTF8ToString(Text));
      end
      else
        Location.LoadFromFile(Dlg.FileName);
      ApplyLocation(Location);
    except
      on E: EFractalFileError do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Location.Free;
    Dlg.Free;
  end;
end;

//SEP

procedure TMainForm.SaveClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  Location: TFractalLocation;
begin
  Dlg := TSaveDialog.Create(nil);
  Location := CaptureLocation;
  try
    Dlg.Filter := kFracFilter;
    Dlg.DefaultExt := 'frac';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    try
      Location.SaveToFile(Dlg.FileName);
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Location.Free;
    Dlg.Free;
  end;
end;

//SEP

procedure TMainForm.ExportPngClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Filter := kPngFilter;
    Dlg.DefaultExt := 'png';
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    try
      ExportViewPng(Dlg.FileName);
    except
      on E: Exception do
        MessageDlg('Export impossible : ' + E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

//SEP

procedure TMainForm.ExportViewPng(const FileName: string);
var
  Stream: TFileStream;
  Writer: TPngWriter;
  Location: TFractalLocation;
  Row: array of Byte;
  X, Y: Integer;
  Src: PCardinal;
  Bmp: TBitmap;
  IsFileCreated: Boolean;
begin
  Screen.Cursor := crHourGlass;
  try
    WaitForRender(kExportWaitMs);
    ColorizeBuffer(FEngine, FView.Bitmap);
  finally
    Screen.Cursor := crDefault;
  end;
  Bmp := FView.Bitmap;
  SetLength(Row, Bmp.Width * 3);
  IsFileCreated := False;
  Location := CaptureLocation;
  try
    try
      Stream := TFileStream.Create(FileName, fmCreate);
      IsFileCreated := True;
      try
        Writer := TPngWriter.Create(Stream, Bmp.Width, Bmp.Height);
        try
          Writer.AddText(kLocationKeyword, LocationAsPngText(Location));
          for Y := 0 to Bmp.Height - 1 do
          begin
            Src := Bmp.ScanLine[Y];
            for X := 0 to Bmp.Width - 1 do
            begin
              Row[X * 3] := (Src^ shr 16) and $FF;
              Row[X * 3 + 1] := (Src^ shr 8) and $FF;
              Row[X * 3 + 2] := Src^ and $FF;
              Inc(Src);
            end;
            Writer.WriteRow(@Row[0]);
          end;
          Writer.Finish;
        finally
          Writer.Free;
        end;
      finally
        Stream.Free;
      end;
    except
      if IsFileCreated then
        SysUtils.DeleteFile(FileName);
      raise;
    end;
  finally
    Location.Free;
  end;
end;

//SEP

procedure TMainForm.RefreshFavorites;
begin
  FFavorites.List(lbFavorites.Items);
end;

//SEP

procedure TMainForm.AddFavoriteClick(Sender: TObject);
var
  Name, Stored: string;
  Location: TFractalLocation;
begin
  Name := '';
  if not InputQuery('Ajouter aux favoris', 'Nom du favori :', Name) or (Trim(Name) = '') then
    Exit;
  if FileExists(FFavorites.FileNameOf(Name))
    and (MessageDlg(Format('Le favori « %s » existe déjà. Le remplacer ?', [SanitizeFileName(Name)]),
      mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  Location := CaptureLocation;
  try
    try
      Stored := FFavorites.Save(Name, Location);
    except
      on E: Exception do
      begin
        MessageDlg(E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  finally
    Location.Free;
  end;
  RefreshFavorites;
  lbFavorites.ItemIndex := lbFavorites.Items.IndexOf(Stored);
end;

//SEP

procedure TMainForm.FavoritesDblClick(Sender: TObject);
var
  Location: TFractalLocation;
begin
  if lbFavorites.ItemIndex < 0 then
    Exit;
  Location := TFractalLocation.Create;
  try
    try
      FFavorites.Load(lbFavorites.Items[lbFavorites.ItemIndex], Location);
      ApplyLocation(Location);
    except
      on E: EFractalFileError do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  finally
    Location.Free;
  end;
end;

//SEP

procedure TMainForm.FavoritesKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Name: string;
begin
  if (Key <> VK_DELETE) or (lbFavorites.ItemIndex < 0) then
    Exit;
  Name := lbFavorites.Items[lbFavorites.ItemIndex];
  if MessageDlg(Format('Supprimer le favori « %s » ?', [Name]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FFavorites.Delete(Name);
    RefreshFavorites;
  end;
  Key := 0;
end;
```

Ajouter à `RunSmokeTest`, avant `Result := 0;` (déclarer aussi `Text: RawByteString;` et
`Location: TFractalLocation;` dans la section `var` de `RunSmokeTest`) :

```pascal
      ExportViewPng(OutputFile);
      if not ReadPngText(OutputFile, kLocationKeyword, Text) then
        raise Exception.Create('lieu absent du PNG exporté');
      Location := TFractalLocation.Create;
      try
        Location.LoadFromText(UTF8ToString(Text));
        if Location.FormulaName <> FFormula.FormulaName then
          raise Exception.Create('lieu du PNG incohérent');
        ApplyLocation(Location);
      finally
        Location.Free;
      end;
      if not WaitForRender(kSmokeTimeoutMs) then
        raise Exception.Create('rendu après réouverture non terminé');
      Log.Add('Export PNG et réouverture OK');
```

Run : `tools/normalize.sh src/MainFrm.pas`

- [ ] **Step 4 : test de fumée**

Run : `./build.sh smoke`
Expected : code 0, journal terminé par `Export PNG et réouverture OK`, et `bin/smoke.png` existe.

- [ ] **Step 5 : commit**

```bash
git add src/MainFrm.pas
git commit -m "Ouvrir, enregistrer, exporter en PNG, favoris

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15 : dialogue de rendu haute résolution

**Files :**
- Create : `src/HiResFrm.pas`, `src/HiResFrm.dfm`
- Modify : `src/MainFrm.pas`, `Fractales.dpr`

**Interfaces :**
- Consumes : `THiResRenderer`, `THiResSettings` (9) ; `TColorMapper`, `TGradientPalette` (5) ;
  `CaptureLocation`, `LocationAsPngText` (14).
- Produces : `THiResForm` (non modal ; `Prepare(const V; Formula; Palette; const Mapping; const LocationText:
  RawByteString)` — sans effet pendant un rendu ; `StartRender` ; `IsRunning: Boolean`). Une seule instance,
  possédée par la fenêtre principale, qui la libère à sa fermeture (le rendu en cours est alors annulé).

- [ ] **Step 1 : écrire `src/HiResFrm.dfm`**

```
object HiResForm: THiResForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Rendu haute r'#233'solution'
  ClientHeight = 250
  ClientWidth = 470
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = False
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object lblPreset: TLabel
    Left = 12
    Top = 15
    Caption = 'Taille :'
  end
  object lblSize: TLabel
    Left = 12
    Top = 47
    Caption = 'Largeur x hauteur :'
  end
  object lblSupersample: TLabel
    Left = 12
    Top = 79
    Caption = 'Sur'#233'chantillonnage :'
  end
  object lblFile: TLabel
    Left = 12
    Top = 111
    Caption = 'Fichier :'
  end
  object lblState: TLabel
    Left = 12
    Top = 180
    Width = 446
    Height = 15
    AutoSize = False
  end
  object cbPreset: TComboBox
    Left = 150
    Top = 11
    Width = 308
    Height = 23
    Style = csDropDownList
    TabOrder = 0
    OnChange = cbPresetChange
  end
  object edWidth: TEdit
    Left = 150
    Top = 43
    Width = 80
    Height = 23
    TabOrder = 1
  end
  object edHeight: TEdit
    Left = 240
    Top = 43
    Width = 80
    Height = 23
    TabOrder = 2
  end
  object cbSupersample: TComboBox
    Left = 150
    Top = 75
    Width = 200
    Height = 23
    Style = csDropDownList
    TabOrder = 3
  end
  object edFile: TEdit
    Left = 150
    Top = 107
    Width = 270
    Height = 23
    TabOrder = 4
  end
  object btnBrowse: TButton
    Left = 426
    Top = 106
    Width = 32
    Height = 25
    Caption = '...'
    TabOrder = 5
    OnClick = btnBrowseClick
  end
  object pbProgress: TProgressBar
    Left = 12
    Top = 150
    Width = 446
    Height = 20
    Max = 1000
    TabOrder = 6
  end
  object btnStart: TButton
    Left = 302
    Top = 212
    Width = 75
    Height = 26
    Caption = 'D'#233'marrer'
    Default = True
    TabOrder = 7
    OnClick = btnStartClick
  end
  object btnClose: TButton
    Left = 383
    Top = 212
    Width = 75
    Height = 26
    Caption = 'Fermer'
    TabOrder = 8
    OnClick = btnCloseClick
  end
  object tmrPoll: TTimer
    Enabled = False
    Interval = 200
    OnTimer = tmrPollTimer
    Left = 12
    Top = 208
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'png'
    Filter = 'Image PNG (*.png)|*.png'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Left = 50
    Top = 208
  end
end
```

- [ ] **Step 2 : écrire `src/HiResFrm.pas`**

```pascal
unit HiResFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs, StdCtrls, ComCtrls, ExtCtrls, ShlObj,
  Fractal.Types, Fractal.Formulas, Fractal.Palette, Fractal.HiRes;

const
  kPresetCurrentView = 0;
  kPresetCustom = 4;
  kPresetWidths: array[1..3] of Integer = (1920, 3840, 7680);
  kPresetHeights: array[1..3] of Integer = (1080, 2160, 4320);
  kMinHiResSize = 16;
  kMaxHiResSize = 32768;
  kDefaultFileName = 'fractale.png';

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
    FStartTick: Cardinal;
    function ReadSettings(out Settings: THiResSettings): Boolean;
    procedure StopRenderer;
    procedure UpdateButtons;
  public
    procedure Prepare(const V: TViewport; Formula: TFractalFormula; Palette: TGradientPalette;
      const Mapping: TColorMapping; const LocationText: RawByteString);
    procedure StartRender;
    function IsRunning: Boolean;
  end;

implementation

{$R *.dfm}

//SEP

function PicturesFolder: string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, CSIDL_MYPICTURES, 0, 0, Buffer) = S_OK then
    Result := IncludeTrailingPathDelimiter(Buffer)
  else
    Result := ExtractFilePath(ParamStr(0));
end;

//SEP

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

//SEP

procedure THiResForm.FormDestroy(Sender: TObject);
begin
  StopRenderer;
  FFormula.Free;
  FPalette.Free;
end;

//SEP

procedure THiResForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not IsRunning then
    Exit;
  CanClose := MessageDlg('Un rendu est en cours. L''annuler ?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if CanClose then
    StopRenderer;
end;

//SEP

procedure THiResForm.Prepare(const V: TViewport; Formula: TFractalFormula; Palette: TGradientPalette;
  const Mapping: TColorMapping; const LocationText: RawByteString);
begin
  if IsRunning then
    Exit;
  FViewport := V;
  FFormula.Free;
  FFormula := Formula.Clone;
  FPalette.Assign(Palette);
  FMapping := Mapping;
  FLocationText := LocationText;
  cbPresetChange(nil);
end;

//SEP

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

//SEP

procedure THiResForm.btnBrowseClick(Sender: TObject);
begin
  dlgSave.FileName := edFile.Text;
  if dlgSave.Execute then
    edFile.Text := dlgSave.FileName;
end;

//SEP

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
  if ExtractFilePath(Settings.FileName) <> '' then
    ForceDirectories(ExtractFilePath(Settings.FileName));
  Result := True;
end;

//SEP

procedure THiResForm.StartRender;
var
  Settings: THiResSettings;
begin
  if IsRunning or (FFormula = nil) or not ReadSettings(Settings) then
    Exit;
  FRenderer := THiResRenderer.Create(Settings, FViewport, FFormula, TColorMapper.Create(FPalette, FMapping),
    FLocationText);
  FStartTick := GetTickCount;
  pbProgress.Position := 0;
  lblState.Caption := 'Rendu en cours...';
  tmrPoll.Enabled := True;
  UpdateButtons;
end;

//SEP

procedure THiResForm.btnStartClick(Sender: TObject);
begin
  StartRender;
end;

//SEP

procedure THiResForm.btnCloseClick(Sender: TObject);
begin
  if IsRunning then
    FRenderer.Terminate
  else
    Close;
end;

//SEP

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
    lblState.Caption := Format('Terminé en %d s : %s', [Seconds, ExtractFileName(edFile.Text)])
  else if FRenderer.ErrorMessage <> '' then
    lblState.Caption := 'Erreur : ' + FRenderer.ErrorMessage
  else
    lblState.Caption := 'Rendu annulé.';
  FreeAndNil(FRenderer);
  UpdateButtons;
end;

//SEP

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

//SEP

function THiResForm.IsRunning: Boolean;
begin
  Result := FRenderer <> nil;
end;

//SEP

procedure THiResForm.UpdateButtons;
begin
  btnStart.Enabled := not IsRunning;
  if IsRunning then
    btnClose.Caption := 'Annuler'
  else
    btnClose.Caption := 'Fermer';
end;

end.
```

- [ ] **Step 3 : brancher le dialogue dans `MainFrm.pas`**

Clause `uses` de l'implémentation : remplacer `  PaletteEditorFrm;` par :

```pascal
  PaletteEditorFrm, HiResFrm;
```

Le champ doit être typé avant la clause d'implémentation : déclarer dans la section `private`, après
`FFavorites: TFavoriteStore;` :

```pascal
    FHiResForm: TForm;  // THiResForm, déclaré dans l'implémentation pour éviter une dépendance d'interface
```

Méthode privée, après `procedure RefreshFavorites;` :

```pascal
    procedure HiResClick(Sender: TObject);
```

Dans `InitFilePanel`, après `btnAddFavorite.OnClick := AddFavoriteClick;` :

```pascal
  btnHiRes.OnClick := HiResClick;
```

À la fin de l'unité, avant `end.` :

```pascal
//SEP

procedure TMainForm.HiResClick(Sender: TObject);
var
  Location: TFractalLocation;
begin
  if FHiResForm = nil then
    FHiResForm := THiResForm.Create(Self);
  Location := CaptureLocation;
  try
    THiResForm(FHiResForm).Prepare(FNavigator.Viewport, FFormula, FPalette, FMapping, LocationAsPngText(Location));
  finally
    Location.Free;
  end;
  FHiResForm.Show;
end;
```

Ajouter à `RunSmokeTest`, avant `Result := 0;` (déclarer aussi `HiResFile: string;` et `Start: Cardinal;`) :

```pascal
      HiResClick(nil);
      HiResFile := ChangeFileExt(OutputFile, '') + '_hd.png';
      SysUtils.DeleteFile(HiResFile);
      with THiResForm(FHiResForm) do
      begin
        cbPreset.ItemIndex := kPresetCustom;
        cbPresetChange(nil);
        edWidth.Text := '160';
        edHeight.Text := '120';
        cbSupersample.ItemIndex := 1;
        edFile.Text := ExpandFileName(HiResFile);
        StartRender;
        Start := GetTickCount;
        while IsRunning and (GetTickCount - Start < kSmokeTimeoutMs) do
        begin
          Application.ProcessMessages;
          Sleep(kRenderPollMs);
        end;
        if IsRunning then
          raise Exception.Create('rendu HD non terminé');
      end;
      if not FileExists(HiResFile) then
        raise Exception.Create('fichier du rendu HD absent');
      Log.Add('Rendu HD OK');
```

Dans `Fractales.dpr`, remplacer `PaletteEditorFrm in 'src\PaletteEditorFrm.pas' {PaletteEditorForm};` par :

```pascal
  PaletteEditorFrm in 'src\PaletteEditorFrm.pas' {PaletteEditorForm},
  HiResFrm in 'src\HiResFrm.pas' {HiResForm};
```

Run : `tools/normalize.sh src/HiResFrm.pas src/HiResFrm.dfm src/MainFrm.pas Fractales.dpr`

- [ ] **Step 4 : test de fumée**

Run : `./build.sh smoke`
Expected : code 0, journal terminé par `Rendu HD OK`, `bin/smoke_hd.png` existe.

- [ ] **Step 5 : commit**

```bash
git add src/HiResFrm.pas src/HiResFrm.dfm src/MainFrm.pas Fractales.dpr
git commit -m "Dialogue de rendu haute résolution

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16 : vérification finale et liste de contrôle manuelle

**Files :**
- Create : `README.md`

- [ ] **Step 1 : tout reconstruire et tout vérifier**

Run : `./build.sh tests && ./build.sh smoke`
Expected : `OK:` (81 tests), puis le journal complet du test de fumée et un code de sortie 0 :

```
Rendu initial OK : ...
Zoom OK
Déplacement OK
Formules et panneau OK
Couleurs OK
Éditeur de palette OK
Export PNG et réouverture OK
Rendu HD OK
```

- [ ] **Step 2 : vérifier l'encodage et les fins de ligne**

Run : `git ls-files --eol | grep -v "w/crlf" ; for f in src/*.pas tests/*.pas *.dpr tests/*.dpr; do head -c3 "$f" | od -An -tx1 | grep -q "ef bb bf" || echo "SANS BOM : $f"; done`
Expected : aucune ligne pour les fichiers sources (seuls des fichiers binaires éventuels peuvent apparaître
dans la première commande), aucun « SANS BOM ».

- [ ] **Step 3 : écrire `README.md`**

```markdown
# Fractales

Explorateur de fractales (Mandelbrot, Multibrot, Julia, Burning Ship, Tricorn) en Delphi 2010.

## Compiler

Depuis Git Bash, à la racine :

- `./build.sh tests` : tests unitaires DUnit
- `./build.sh app` : `bin/Fractales.exe`
- `./build.sh smoke` : test de fumée de l'application

On peut aussi ouvrir `Fractales.dpr` dans l'IDE Delphi 2010.

## Utilisation

- Molette : zoom sur le curseur. Glisser (bouton gauche) : déplacer. Glisser (bouton droit) : zoomer sur une zone.
- `+` / `-` : zoom ; flèches : déplacement ; `Retour arrière` : vue précédente ; `Échap` : annuler la sélection.
- `F4` : panneau latéral ; `F11` : plein écran.
- Un PNG exporté contient son « lieu » : on le rouvre avec Ouvrir.
- Palettes et favoris : `%APPDATA%\Fractales\Palettes` et `%APPDATA%\Fractales\Favoris`.
```

Run : `unix2dos -q README.md`

- [ ] **Step 4 : commit**

```bash
git add README.md
git commit -m "README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5 : liste de contrôle manuelle pour JF** (à transmettre telle quelle ; ces points demandent un
  œil humain)

1. Lancer `bin/Fractales.exe` : l'ensemble de Mandelbrot apparaît en blocs puis s'affine en moins d'une seconde.
2. Molette rapide sur un bord de l'ensemble : l'image suit sans geler.
3. Glisser au bouton gauche : l'image suit la souris ; seules les bandes découvertes se recalculent.
4. Glisser au bouton droit : rectangle blanc aux proportions de la fenêtre ; au relâchement, la vue se recadre.
5. Mode « Aperçu Julia » : la vignette en bas à droite change avec la souris.
6. Changer de formule, modifier « Puissance n » (Multibrot) puis Entrée : nouveau rendu.
7. Curseurs Décalage / Répétition / Étirement / Inverser : les couleurs changent instantanément, sans passe.
8. Éditeur de palette : glisser un point, double-cliquer pour en ajouter, OK et Annuler.
9. `F4`, puis le bouton ▸ / ◂ : le panneau se ferme et se rouvre à la même largeur. `F11` : plein écran.
10. Exporter un PNG, le rouvrir avec Ouvrir : même vue, mêmes couleurs.
11. Rendu HD 4K en 2× : progression, puis fichier correct ; un second rendu annulé ne laisse pas de fichier.
12. Zoomer jusqu'à l'avertissement « Limite de précision proche » puis « zoom bloqué ».

- [ ] **Step 6 : remplacer les marqueurs de séparateur**

Les blocs de code de ce plan utilisent la ligne `//SEP` à la place du séparateur de routines. Chaque `//SEP`
écrit dans un fichier source doit devenir le séparateur réel. Cette substitution se fait **à chaque création
de fichier**, juste avant `tools/normalize.sh` ; cette étape finale vérifie qu'il n'en reste aucun :

Run : `grep -rn "//SEP" src tests ; echo "fin"`
Expected : seulement `fin`.
