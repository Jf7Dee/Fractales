# Fractales — Moteur de calcul Rust dans l'application Delphi

Date : 2026-10-04
Statut : spec à relire

## 1. Objectif

Comparer, dans l'application Delphi existante et sur les mêmes vues, le calcul des pixels fait en Delphi
(Extended 80 bits, x87) et le même calcul fait par une DLL Rust (f64, SIMD SSE2). L'interface, la navigation, les
palettes, les fichiers et le rendu HD restent ceux de l'application Delphi.

Critères de réussite :

- un choix « Moteur : Delphi / Rust » permet de basculer à tout moment ; la vue courante est recalculée aussitôt ;
- la barre d'état affiche le moteur utilisé et le temps du rendu ;
- les deux moteurs donnent la même image (même verdict intérieur/extérieur, valeurs lissées proches) ;
- l'application démarre et fonctionne normalement sans la DLL (moteur Delphi seul) ;
- aucune erreur de la DLL ne fait planter l'application.

Le banc d'essai (`bench`, `bench-rust`) a mesuré environ ×3 en scalaire et ×6 à ×9 en SIMD pour Rust ; ce
projet vérifie ce gain dans l'application réelle.

## 2. Contraintes

- **32 bits** : Delphi 2010 produit un exécutable Win32, qui ne peut charger qu'une DLL 32 bits. La DLL Rust est
  compilée pour la cible `i686-pc-windows-msvc`. SSE2 est disponible en 32 bits.
- **Compilation Rust sur une autre machine** : le code Rust est écrit dans ce dépôt mais compilé et testé
  (`cargo test`) par JF sur la machine où Rust est installé ; la DLL produite est copiée dans `bin\` ici.
- **Delphi** : mêmes contraintes globales que le sous-projet 1 (D2010, VCL seule, UTF-8 BOM + CRLF, séparateurs,
  constantes nommées, zéro avertissement).
- Le moteur choisi n'est **pas** enregistré dans les lieux (`.frac`, PNG) : c'est un outil de comparaison.

## 3. Architecture

### 3.1 DLL Rust (`kernel-rust\`)

Projet Cargo `crate-type = ["cdylib"]`, nom de sortie `fractal_kernel.dll`. Deux fonctions exportées, convention C
(`extern "C"`, `#[no_mangle]`), déclarées `cdecl` côté Delphi :

```
fk_abi_version() -> u32
fk_compute_row(formula: i32, params: *const f64, param_count: i32, max_iter: i32,
               x0: f64, dx: f64, y: f64, count: i32, out: *mut f32) -> i32
```

- `fk_abi_version` renvoie la version d'interface (1). L'application refuse une DLL d'une autre version.
- `fk_compute_row` calcule `count` pixels de la ligne d'ordonnée `y`, d'abscisses `x0 + i·dx` (i = 0…count−1),
  et écrit dans `out[i]` la valeur lissée, ou −1 pour un point intérieur — mêmes conventions que
  `TFractalFormula.Iterate`.
- Codes de retour : 0 = succès ; 1 = formule inconnue ; 2 = nombre de paramètres incorrect ; 3 = argument invalide
  (pointeur nul, `count` ou `max_iter` négatif) ; 4 = erreur interne (panique rattrapée).
- **Aucune panique ne traverse la frontière** : tout le corps est protégé par `std::panic::catch_unwind`.
- Identifiants de formule et paramètres (dans l'ordre déclaré côté Delphi) :

| Id | Formule | Paramètres |
|---|---|---|
| 0 | Mandelbrot | — |
| 1 | Multibrot | power |
| 2 | Julia | cx, cy |
| 3 | Burning Ship | — |
| 4 | Tricorn | — |

- Algorithmes **identiques** à `Fractal.Formulas` : rayon d'échappement 256 (R² = 65 536), test de la cardioïde et du
  bulbe de période 2 pour Mandelbrot, Burning Ship avec `2|xy| − cy`, Tricorn avec `−2xy + cy`, Multibrot en
  polaire (`exp(p·ln r)`, `p·atan2`), lissage `n + 1 − ln(½ ln|z|²)/ln p`, borné à 0.
- Calcul en SIMD 4 pixels (crate `wide`, f64x4) pour les formules polynomiales (0, 2, 3, 4) ; Multibrot en
  scalaire (fonctions transcendantes). Les pixels restants (`count` non multiple de 4) en scalaire.
- Le mode SIMD et le mode scalaire donnent exactement les mêmes valeurs (mêmes opérations dans le même ordre).

### 3.2 Delphi : `Fractal.RustKernel.pas`

Unité sans VCL :

- chargement dynamique au premier usage (`LoadLibrary` du fichier `fractal_kernel.dll` situé à côté de l'exécutable,
  `GetProcAddress`) ; vérification de `fk_abi_version` ;
- `function IsRustKernelAvailable: Boolean`, `function RustKernelStatus: string` (raison si indisponible) ;
- `function RustComputeRow(...): Integer` qui appelle la DLL ;
- sûr entre threads : le chargement est fait une seule fois sous verrou ; ensuite, la DLL est appelée simultanément
  par plusieurs threads (elle n'a aucun état).

### 3.3 Formules

`TFractalFormula` reçoit `class function KernelId: Integer; virtual;` (−1 par défaut = non pris en charge). Les cinq
formules renvoient leur identifiant. Les paramètres envoyés à la DLL sont `GetParam(0…ParamCount−1)`.

### 3.4 Moteur

- `TEngineKernel = (ekDelphi, ekRust)`. `Render` / `RenderShifted` reçoivent le noyau ; il est figé dans
  l'instantané du rendu comme la formule.
- En mode Rust, `ProcessJob` traite chaque ligne d'une tuile ainsi : il regroupe les ancres non exactes consécutives
  (pas = taille de bloc de la passe) en suites, vérifie le numéro de génération avant chaque suite, appelle
  `RustComputeRow` une fois par suite (`dx` = pas × taille de pixel), puis écrit chaque valeur par `WriteAnchor`.
- Une formule sans `KernelId` (≥ 0) ou une DLL indisponible fait retomber le rendu sur le noyau Delphi.
- Un code d'erreur de la DLL lève une exception dans le thread, consignée comme erreur de tuile (comportement
  existant) ; le rendu continue.

### 3.5 Précision

`TViewport.PrecisionState` reçoit l'epsilon du noyau : 2⁻⁶³ (Extended) ou 2⁻⁵² (f64). Mêmes règles qu'aujourd'hui
(limite à 64 ulps par pixel, avertissement à ×8). En mode Rust, le zoom est donc bloqué vers 10⁻¹³ au lieu de 10⁻¹⁶.
Le navigateur reçoit l'epsilon du noyau courant.

## 4. Interface

- Barre d'outils : liste « Moteur : Delphi / Rust ». Si la DLL est indisponible, l'entrée Rust est désactivée
  (le choix reste Delphi) et la raison est affichée dans la barre d'état au démarrage.
- Changer de moteur relance le rendu de la vue courante (et de l'aperçu Julia).
- Barre d'état, panneau du temps : « Delphi : terminé en 812 ms » / « Rust : passe 2/4 … ».
- Rendu HD : utilise le moteur choisi au moment du démarrage.

## 5. Tests

**Rust (`cargo test`, chez JF)** — tests appelant `fk_compute_row` elle-même :

- points connus par formule : (0,0) intérieur pour Mandelbrot, Burning Ship, Tricorn ; point lointain qui s'échappe ;
  Julia c = 0 : (0,5 ; 0) intérieur, (1,5 ; 0) extérieur ; Multibrot puissance 2 ≈ Mandelbrot ;
- SIMD = scalaire exactement sur une ligne de 1 000 pixels pour chaque formule polynomiale ;
- `count` non multiple de 4 ; codes d'erreur 1, 2, 3 ;
- `fk_abi_version() = 1`.

**Delphi (DUnit, ici)** — unité `TestFractalRustKernel`, passée avec un message si la DLL est absente :

- sur une grille de points de chaque formule, Rust et Delphi donnent le même verdict intérieur/extérieur et des
  valeurs lissées à 1e−3 près (hors pixels à la frontière, où l'écart Extended/f64 peut changer l'itération
  d'échappement : on exige ≥ 99 % de pixels concordants) ;
- un rendu complet en mode Rust donne le même nombre de points intérieurs qu'en mode Delphi (± 0,1 %) ;
- le repli : noyau Rust demandé mais DLL indisponible → rendu Delphi, aucune erreur.

**Test de fumée** : étape supplémentaire « Moteur Rust OK » si la DLL est présente (rendu complet en mode Rust,
pixels allumés, pas d'erreur), sinon « Moteur Rust absent (ignoré) ».

## 6. Compilation de la DLL (chez JF)

```
rustup target add i686-pc-windows-msvc
cd kernel-rust
cargo test
cargo build --release --target i686-pc-windows-msvc
```

Le fichier produit est `kernel-rust\target\i686-pc-windows-msvc\release\fractal_kernel.dll`, à copier dans
`bin\` à côté de `Fractales.exe`. Les tests `cargo test` tournent en 64 bits (cible par défaut) : ils vérifient
l'algorithme ; la cible 32 bits est vérifiée par les tests Delphi qui chargent la vraie DLL.

## 7. Hors périmètre

Rendu complet délégué à Rust (rayon), AVX, haute précision, enregistrement du moteur dans les lieux, comparaison
automatique côte à côte dans l'interface.
