# Vidéos : étapes de passage — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** une case « Arrêt » par étape ; les trajets entre deux arrêts forment un mouvement unique à vitesse perçue
constante, arrondi autour des étapes de passage.

**Architecture:** `Fractal.VideoPath` gagne une mesure de longueur perçue commune (survol et latéral), la pose à une
longueur donnée, le profil de vitesse d'un enchaînement et l'arrondi d'un coin. `TVideoScenario.PoseAtFrame` découpe
la vidéo en enchaînements (d'un arrêt au suivant) au lieu de trajets ; un enchaînement d'un seul trajet garde
exactement le code actuel. `VideoFrm` ajoute la case et la ligne d'information.

**Tech Stack:** Delphi (D2010 ici via `./build.sh tests|app|smoke`, CE 13 chez JF), DUnit.

**Spec:** `docs/superpowers/specs/2026-11-12-videos-passage-design.md`

## Global Constraints

- Tous arrêts (case cochée partout, ou fichier sans clé `Arret`) : `PoseAtFrame` rend **exactement** les mêmes poses
  qu'avant (même code : `PoseBetween(..., (Frame + 1) / N)`).
- Fichier : clé `Arret=0` dans `[StepN]`, écrite seulement si la case est décochée ; absente = arrêt ; `Version=1`.
- Arrêts forcés (case cochée et grisée) : première étape, dernière, étape à pause non nulle ; `Arret=0` y est lu
  puis ignoré.
- Le trajet qui arrive à une étape suit le mode de cette étape.
- Zoom profond : jamais de soustraction de deux centres en `TFloat` ; un décalage se mesure en `THighFloat`
  (`Sub(...).ToFloat`) par rapport à une étape voisine et s'applique avec le motif de `CenterFrom`.
- Durée totale (`TotalFrames`) inchangée par les cases.
- `.pas` UTF-8 avec BOM, CRLF ; `.dfm` ASCII CRLF, accents en `#nnn` ; éditer par script Python (`utf-8-sig`,
  `newline=''`). Compiler sous D2010 : pas d'unités préfixées (`Vcl.`, `System.`).
- Commits : branche `videos`, message français court, accord de JF avant chaque commit de code, trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Enchaînement contenant un trajet « zoom pur » (même centre) ou deux étapes identiques (longueur nulle) : pas de
   division par zéro, pas de NaN — test dans la tâche 2 et la tâche 4.
2. Arrondi d'un coin entre deux trajets très inégaux (1 s puis 30 s, ou largeurs 1e-13 et 1) : la fenêtre se règle
   sur le plus court, la pose reste dans le cadre des deux étapes — test dans la tâche 3.
3. Case décochée puis pause portée à une valeur non nulle : l'étape redevient un arrêt sans toucher la case
   enregistrée — test dans la tâche 1.
4. Enchaînement dont un trajet latéral est très long : l'avertissement de vitesse utilise la vitesse de croisière —
   test dans la tâche 4 (`ChainInfo`).
5. Reprise d'une génération : décocher une case change `SaveToText`, donc l'estampille — test dans la tâche 1.

---

### Task 1: Case « Arrêt » dans le scénario

**Files:**
- Modify: `src/Fractal.VideoScenario.pas` (`TVideoStep`, `AddLocation`, `SaveToText`, `LoadFromFile`)
- Test: `tests/TestFractalVideo.pas` (`TTestVideoScenario`)

**Interfaces:**
- Produces: champ `TVideoStep.IsStop: Boolean` (vrai par défaut) ; `function TVideoScenario.IsStopAt(Index: Integer):
  Boolean` — arrêt effectif (forcé pour 0, `Count - 1`, `PauseSeconds > 0`, sinon `IsStop`).

- [ ] **Step 1: tests** `TestStopFlagRoundTrip` : scénario de 4 étapes, `IsStop := False` sur l'étape 1 ;
  `Pos('Arret=0', SaveToText) > 0` et une seule occurrence ; après `SaveToFile`/`LoadFromFile`,
  `CheckFalse(S[1].IsStop)`, `CheckTrue(S[2].IsStop)`. `TestStopIsForced` : `IsStop := False` sur 0, 1 et 3, pause
  2 s sur 1 ; `IsStopAt(0)`, `IsStopAt(1)`, `IsStopAt(3)` vrais ; `IsStopAt(2)` vrai (case cochée) ; puis
  `IsStop := False` sur 2 → `IsStopAt(2)` faux ; `S[1].IsStop` reste faux. Un fichier écrit avant la tâche (sans
  `Arret`) se relit avec tous les `IsStop` vrais (réutiliser `TestSaveLoadRoundTrip`, ajouter la vérification).
- [ ] **Step 2:** `./build.sh tests` → échec de compilation (`IsStop` inconnu).
- [ ] **Step 3: implémenter.** Lecture : `Ini.ReadString(Section, 'Arret', '1') <> '0'`.
- [ ] **Step 4:** `./build.sh tests` → `OK: 328 tests` (ou plus).
- [ ] **Step 5: commit** (accord de JF) : « Vidéo : case Arrêt dans le scénario ».

### Task 2: Longueur perçue et pose à une longueur donnée

**Files:**
- Modify: `src/Fractal.VideoPath.pas`
- Test: `tests/TestFractalVideo.pas` (`TTestVideoPath`)

**Interfaces:**
- Produces:
  - `function PathLength(const A, B: TCameraPose; Mode: TVideoMoveMode): TFloat;`
  - `function PoseAtLength(const A, B: TCameraPose; Mode: TVideoMoveMode; S: TFloat): TCameraPose;` — sans
    adoucissement ; `S` borné à `[0, PathLength]` ; 0 → `A`, longueur → `B` exactement.

Métrique commune (celle de van Wijk et Nuij, dont `FlyoverLength` est l'intégrale) :
`ds² = (du / w)² + (d ln w)² / ρ²`, `u` = déplacement du centre, `w` = largeur, `ρ = kRho`.
- Survol : `PathLength = FlyoverLength(A.Width, B.Width, D)` ; `PoseAtLength` = branche survol de `PoseBetween`
  avec `S` au lieu de `E * Total`.
- Latéral (et point identique) : le chemin est celui de `PoseBetween` paramétré par `E` (centre linéaire, largeur
  `LogLerp`). Longueur par intégration numérique de la métrique sur `kLengthSamples = 64` pas (Simpson ou trapèzes) ;
  `PoseAtLength` inverse la table cumulée (interpolation linéaire) pour retrouver `E`, puis applique la branche
  latérale de `PoseBetween`.
- Factoriser : `PoseBetween` appelle les mêmes branches ; son comportement ne change pas (tests existants verts).

- [ ] **Step 1: tests** `TestPathLength` : survol entre deux poses éloignées = `FlyoverLength` (à 1e-12 près en
  relatif) ; latéral pur à largeur constante `w`, distance `3 * w` → `3` (à 1e-3) ; zoom pur `w` → `w / 100` →
  `Ln(100) / kRho` pour les deux modes ; deux poses identiques → 0. `TestPoseAtLength` : pour chaque mode, `S = 0`
  → `A`, `S = PathLength` → `B` (centres égaux en `THighFloat`) ; `S` à mi-longueur sur un latéral pur → centre au
  milieu (1e-6 en largeurs) ; longueur nulle → `A` sans NaN.
- [ ] **Step 2:** `./build.sh tests` → échec de compilation.
- [ ] **Step 3: implémenter** dans `Fractal.VideoPath.pas`.
- [ ] **Step 4:** `./build.sh tests` → tous OK, anciens tests de trajet compris.
- [ ] **Step 5: commit** : « Vidéo : longueur perçue des trajets ».

### Task 3: Profil de vitesse et arrondi des coins

**Files:**
- Modify: `src/Fractal.VideoPath.pas`
- Test: `tests/TestFractalVideo.pas` (`TTestVideoPath`)

**Interfaces:**
- Produces:
  - `function ChainDistance(T, Total, RampIn, RampOut: Double): Double;` — `T` = fraction de temps (0..1) de
    l'enchaînement ; `RampIn`, `RampOut` = fractions de temps des rampes (`RampIn + RampOut <= 1`) ; résultat =
    longueur parcourue (0..`Total`).
  - `function RoundedCorner(const P0, Corner, P2: TCameraPose; U: Double): TCameraPose;` — Bézier quadratique de
    `P0` (U = 0) à `P2` (U = 1), point de contrôle `Corner`, calculée en décalages `THighFloat` relatifs à
    `Corner` pour le centre et en `Ln(Width)` pour la largeur.

Profil (fixé par le plan) : vitesse `v(t)` = `V * Smooth(t / RampIn)` en montée, `V` en palier,
`V * Smooth((1 - t) / RampOut)` en descente, `Smooth(x) = 3x² - 2x³` ; la surface sous `v` vaut `Total`, d'où
`V = Total / (1 - RampIn / 2 - RampOut / 2)` ; `ChainDistance` intègre `v` analytiquement
(`∫Smooth = x³ - x⁴/2`).

- [ ] **Step 1: tests** `TestChainDistance` : bornes 0 → 0 et 1 → `Total` ; monotone sur 101 points ; avec
  `RampIn = RampOut = 0.2`, les écarts entre points successifs dans `[0.3, 0.7]` sont égaux (1e-9) ; vitesse nulle aux
  bouts (écart des deux premiers points < 1e-4 · `Total`). `TestRoundedCorner` : U = 0 → `P0`, U = 1 → `P2`
  (THighFloat égaux) ; U = 0.5 ne tombe pas sur `Corner` mais à moins de la moitié de la distance `P0`–`Corner` ;
  largeurs 1e-13 et 1 : la largeur reste entre les deux, pas de NaN.
- [ ] **Step 2:** `./build.sh tests` → échec de compilation.
- [ ] **Step 3: implémenter.**
- [ ] **Step 4:** `./build.sh tests` → tous OK.
- [ ] **Step 5: commit** : « Vidéo : profil de vitesse et arrondi des passages ».

### Task 4: Enchaînements dans `PoseAtFrame`

**Files:**
- Modify: `src/Fractal.VideoScenario.pas`
- Test: `tests/TestFractalVideo.pas` (`TTestVideoScenario`)

**Interfaces:**
- Consumes: `IsStopAt` (tâche 1) ; `PathLength`, `PoseAtLength` (tâche 2) ; `ChainDistance`, `RoundedCorner`
  (tâche 3).
- Produces: `procedure TVideoScenario.ChainInfo(Index: Integer; out First, Last: Integer; out Seconds, PassAt,
  CruiseSpeed: Double);` — pour l'étape `Index` : premier et dernier arrêt de l'enchaînement qui la contient
  (`First < Index <= Last`), durée totale, instant de passage le plus proche de l'étape depuis `First`, vitesse de
  croisière en unités de la métrique par seconde (= largeurs d'écran par seconde pour un glissement pur).

Règles (fixées par le plan) :
- Un enchaînement va d'un arrêt `F` au suivant `L`. Si `L = F + 1` : code actuel inchangé
  (`PoseBetween(..., (k + 1) / N)`).
- Sinon : `N = Σ TravelFrames(F+1..L)` ; `T = (k + 1) / N` ; `RampIn = TravelFrames(F+1) / (2N)`,
  `RampOut = TravelFrames(L) / (2N)` ; `s = ChainDistance(T, ΣL_i, RampIn, RampOut)` ; on trouve le trajet `i` par
  longueurs cumulées et on prend `PoseAtLength(P[i-1], P[i], Mode[i], s - cumul)`.
- Arrondi : autour de chaque étape de passage `J` (`F < J < L`), fenêtre `h = kCornerRatio * Min(L_J, L_{J+1})`,
  `kCornerRatio = 0.25`. Si `s` est dans `[cumul_J - h, cumul_J + h]` : `RoundedCorner(pose à cumul_J - h,
  P[J], pose à cumul_J + h, (s - cumul_J + h) / (2h))`. Si `h = 0`, pas d'arrondi.
- Les pauses ne bougent pas (un arrêt peut avoir une pause, qui suit l'arrivée comme aujourd'hui).
- `PassAt` = instant où `s` atteint `cumul_Index`, trouvé par dichotomie sur `ChainDistance`.

- [ ] **Step 1: tests** `TestAllStopsUnchanged` : scénario de 4 étapes (modes mêlés, pauses) ; pour chaque image,
  `PoseAtFrame` égale `PoseBetween(...)` calculé à la main comme avant (centres et largeur identiques).
  `TestChainKeepsSpeed` : 3 étapes en ligne, survols, étape 1 en passage, durées 4 s et 4 s ; mesurer la longueur
  perçue entre images consécutives (`PathLength` en latéral entre les deux poses, approximation locale) ; sur le
  tiers central de la vidéo, min/max des écarts dans un rapport > 0,8 ; aucune image du tiers central n'est égale
  à la pose de l'étape 1. `TestChainTotalFrames` : `TotalFrames` identique avec et sans la case. `TestChainZeroLength`
  : deux étapes identiques au milieu d'un enchaînement → pas de NaN, dernière image = dernière étape.
  `TestChainInfo` : pour l'exemple 3 étapes, `First = 0`, `Last = 2`, `Seconds = 8`, `PassAt` entre 3 s et 5 s,
  `CruiseSpeed > 0`.
- [ ] **Step 2:** `./build.sh tests` → échecs attendus (`ChainInfo` inconnu).
- [ ] **Step 3: implémenter.** Calculer les longueurs une fois par appel (pas de cache nécessaire ;
  `PoseAtFrame` reste en O(nombre d'étapes)).
- [ ] **Step 4:** `./build.sh tests` → tous OK ; `./build.sh smoke` → OK.
- [ ] **Step 5: commit** : « Vidéo : trajets enchaînés aux étapes de passage ».

### Task 5: Fenêtre Vidéo

**Files:**
- Modify: `src/VideoFrm.pas`, `src/VideoFrm.dfm` (groupe `gbStep`), `src/MainFrm.pas` (test de fumée)

**Interfaces:**
- Consumes: `TVideoStep.IsStop`, `IsStopAt`, `ChainInfo`.

- Case `cbStop: TCheckBox`, libellé « Arrêt », dans `gbStep` à droite de `cbMode` (`Left = 210`, `Top = 22`),
  `OnClick = StepChange`. `RefreshStep` : `Checked := IsStopAt(Index)`, `Enabled := IsIdle` et étape ni première,
  ni dernière, ni à pause non nulle. `StepChange` écrit `IsStop := cbStop.Checked`.
- `RefreshSpeed(Index)` : si `ChainInfo(Index, ...)` donne `Last - First > 1` (le trajet appartient à un
  enchaînement de plus d'un trajet), afficher
  `Format('Enchaîné avec les étapes %d à %d : %s en tout, passage ici vers %s', [First + 1, Last + 1, …])`
  (secondes avec `SecondsText`, une décimale pour le passage) ; puis, si `CruiseSpeed > kLateralSpeedWarning` et que
  le trajet est latéral, l'avertissement actuel sur une seconde ligne. Sinon, comportement actuel.
- Liste des étapes : colonne Mode, suffixe ` ▸` quand l'étape est un passage (`not IsStopAt(I)`).
- Test de fumée (`MainFrm.pas`, bloc « Fenêtre Vidéo ») : décocher la case d'une étape intermédiaire d'un scénario
  de 3 étapes, vérifier `Scenario[1].IsStop = False` et que `lblSpeed.Caption` commence par `Enchaîné`.

- [ ] **Step 1:** écrire la vérification du test de fumée.
- [ ] **Step 2:** `./build.sh smoke` → échec.
- [ ] **Step 3: implémenter** (`.dfm` en ASCII, `Caption = 'Arr'#234't'`).
- [ ] **Step 4:** `./build.sh app`, `./build.sh smoke`, `./build.sh tests` → OK. Faire générer à JF un court
  aperçu (3 étapes, passage au milieu) et extraire quelques images autour du passage dans `examples/` pour juger
  l'arrondi ; ajuster `kCornerRatio` si besoin.
- [ ] **Step 5: commit** : « Vidéo : case Arrêt et enchaînements dans la fenêtre ».
