# Noyau de calcul Rust

DLL appelée par l'application Delphi quand on choisit « Moteur : Rust ». Mêmes formules que
`src\Fractal.Formulas.pas`, en f64 avec SIMD SSE2 (4 pixels à la fois).

## Interface (ABI 4)

- `fk_abi_version() -> u32` : renvoie 4.
- `fk_compute_row(formula, params, param_count, max_iter, x0, dx, y, count, out) -> i32` : palier 1, calcul
  direct d'une suite de pixels, en SIMD.
- `fk_compute_row_perturbed(formula, params, param_count, max_iter, ref_orbit, ref_len, dcx0, ddx, dcy, count,
  out) -> i32` : palier 2 (zoom profond), pixels d'écart `(dcx0 + i·ddx, dcy)` à la référence, en f64 scalaire.
- `ref_orbit` : orbite de référence Z0 = 0, Z1, ... en f64, x et y alternés (`2·ref_len` valeurs), au moins
  deux points. Même algorithme que `IteratePerturbed` dans `src\Fractal.Formulas.pas` (rebasage compris), pour
  Mandelbrot, Tricorn, Burning Ship et Multibrot à puissance entière (2 à 10, à 1e-9 près). Le Burning Ship passe
  par `diff_abs(c, d) = |c + d| - |c|`, calculée sans soustraire deux grands nombres voisins, avec le même tableau
  de cas que `DiffAbs` côté Delphi. Multibrot : δ' = Σ C(p, k)·Zᵖ⁻ᵏ·δᵏ + δc, en Horner sur δ, lissage en ln p.
  Julia et une puissance non entière de Multibrot : code 5.
- `fk_compute_row_perturbed2(formula, params, param_count, max_iter, ref_orbit, ref_len, crit_orbit, crit_len,
  dcx0, ddx, dcy, count, out) -> i32` (version 4) : comme `fk_compute_row_perturbed`, plus l'orbite critique
  W0 = 0, W1, ... (`crit_orbit`, `2·crit_len` valeurs), obligatoire pour Julia (code 3 si `crit_orbit` est nul ou
  `crit_len < 2`) et ignorée par les autres formules. Pour Julia, `ref_orbit` part de Z0 = la référence et
  `(dcx0 + i·ddx, dcy)` est δ0 = pixel − référence ; on rebase de Z vers W (δ := z), puis toujours vers W0, comme
  `TJuliaFormula.IteratePerturbedCritical`.
- `fk_perturbation_supported(formula) -> i32` (version 3) : décidé sur l'identifiant seul, sans paramètres ;
  en version 4, 1 pour les cinq formules (Multibrot : puissances entières seulement, la DLL répond 5 aux autres),
  0 pour un identifiant inconnu. L'application la consulte avant de confier un rendu profond au moteur Rust.
- Codes de retour : 0 succès, 1 formule inconnue, 2 nombre de paramètres incorrect, 3 argument invalide
  (pointeur nul, compte négatif, `ref_orbit` nul ou `ref_len < 2`, orbite critique absente pour Julia), 4 erreur
  interne (panique rattrapée), 5 formule sans perturbation (fonctions perturbées seulement).
- L'application accepte encore une DLL de version 3 : Julia et Multibrot profonds repris par le moteur Delphi (elle
  répond 0 pour eux). Une DLL de version 2 (sans `fk_perturbation_supported`) : Mandelbrot et Tricorn profonds en
  Rust, Burning Ship profond repris par le moteur Delphi. Et une DLL de version 1 (sans
  `fk_compute_row_perturbed`) : tout le zoom profond est alors calculé par le moteur Delphi. L'état du moteur
  (`RustKernelStatus`) le précise.

## Compiler (sur la machine où Rust est installé)

Une seule fois, ajouter la cible 32 bits (Delphi 2010 ne charge que des DLL 32 bits) :

    rustup target add i686-pc-windows-msvc

Puis, dans ce dossier :

    cargo test
    cargo build --release --target i686-pc-windows-msvc

Copier `target\i686-pc-windows-msvc\release\fractal_kernel.dll` dans `bin\`, à côté de `Fractales.exe`.

- `cargo test` tourne en 64 bits (cible par défaut) : il vérifie l'algorithme, dont `perturbed_matches_direct`
  (au moins 98 % de verdicts communs entre la perturbation et le calcul direct, pour Mandelbrot, Tricorn, Burning
  Ship, Multibrot p = 3 et p = 10, et Julia par `fk_compute_row_perturbed2`), `abi_version_is_4`, `diff_abs_cases`,
  `perturbation_supported` et `perturbed_error_codes`.
- La DLL 32 bits est vérifiée par `./build.sh tests` côté Delphi, une fois copiée dans `bin\` : il la charge et
  compare ses images à celles du moteur Delphi, au palier 1 (`TestRealKernelMatchesDelphi`) et en zoom profond
  (`TestRealKernelPerturbedMatchesDelphi`). Sans la DLL, ces deux tests passent avec un message.
- Sans Rust, `tests\FakeKernel.dpr` (DLL factice calculée par `Fractal.Formulas`) tient lieu de DLL : pour un
  essai complet de l'application, `cp bin/FakeKernel.dll bin/fractal_kernel.dll`, `./build.sh smoke`, puis
  retirer la copie. `bin\FakeKernelAbi1.dll` imite une DLL de version 1, `bin\FakeKernelAbi2.dll` une DLL de
  version 2, `bin\FakeKernelAbi3.dll` une DLL de version 3.
- N'utilisez **pas** `-C target-cpu=native` : la DLL tourne sur une autre machine. Si `RUSTFLAGS` est encore
  défini dans le terminal (essais du banc), ouvrez-en un nouveau ou tapez `Remove-Item Env:RUSTFLAGS` : la
  variable remplacerait le réglage de `.cargo\config.toml` (runtime C lié statiquement).
- Erreur de liaison `LNK1181` ou `kernel32.lib` introuvable : installer les outils de génération C++ x86
  (Visual Studio Build Tools, « Développement Desktop en C++ »).
- Le dossier `target\` n'est pas suivi par git.
