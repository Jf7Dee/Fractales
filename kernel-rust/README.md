# Noyau de calcul Rust

DLL appelée par l'application Delphi quand on choisit « Moteur : Rust ». Mêmes formules que
`src\Fractal.Formulas.pas`, en f64 avec SIMD SSE2 (4 pixels à la fois).

## Interface (ABI 2)

- `fk_abi_version() -> u32` : renvoie 2.
- `fk_compute_row(formula, params, param_count, max_iter, x0, dx, y, count, out) -> i32` : palier 1, calcul
  direct d'une suite de pixels, en SIMD.
- `fk_compute_row_perturbed(formula, params, param_count, max_iter, ref_orbit, ref_len, dcx0, ddx, dcy, count,
  out) -> i32` : palier 2 (zoom profond), pixels d'écart `(dcx0 + i·ddx, dcy)` à la référence, en f64 scalaire.
- `ref_orbit` : orbite de référence Z0 = 0, Z1, ... en f64, x et y alternés (`2·ref_len` valeurs), au moins
  deux points. Même algorithme que `IteratePerturbed` dans `src\Fractal.Formulas.pas` (rebasage compris), pour
  Mandelbrot et Tricorn seulement.
- Codes de retour : 0 succès, 1 formule inconnue, 2 nombre de paramètres incorrect, 3 argument invalide
  (pointeur nul, compte négatif, `ref_orbit` nul ou `ref_len < 2`), 4 erreur interne (panique rattrapée),
  5 formule sans perturbation (`fk_compute_row_perturbed` seulement).
- L'application accepte encore une DLL de version 1 (sans `fk_compute_row_perturbed`) : le zoom profond est
  alors calculé par le moteur Delphi, ce que précise l'état du moteur (`RustKernelStatus`).

## Compiler (sur la machine où Rust est installé)

Une seule fois, ajouter la cible 32 bits (Delphi 2010 ne charge que des DLL 32 bits) :

    rustup target add i686-pc-windows-msvc

Puis, dans ce dossier :

    cargo test
    cargo build --release --target i686-pc-windows-msvc

Copier `target\i686-pc-windows-msvc\release\fractal_kernel.dll` dans `bin\`, à côté de `Fractales.exe`.

- `cargo test` tourne en 64 bits (cible par défaut) : il vérifie l'algorithme, dont `perturbed_matches_direct`
  (au moins 98 % de verdicts communs entre la perturbation et le calcul direct) et `perturbed_error_codes`.
- La DLL 32 bits est vérifiée par `./build.sh tests` côté Delphi, une fois copiée dans `bin\` : il la charge et
  compare ses images à celles du moteur Delphi, au palier 1 (`TestRealKernelMatchesDelphi`) et en zoom profond
  (`TestRealKernelPerturbedMatchesDelphi`). Sans la DLL, ces deux tests passent avec un message.
- Sans Rust, `tests\FakeKernel.dpr` (DLL factice calculée par `Fractal.Formulas`) tient lieu de DLL : pour un
  essai complet de l'application, `cp bin/FakeKernel.dll bin/fractal_kernel.dll`, `./build.sh smoke`, puis
  retirer la copie. `bin\FakeKernelAbi1.dll` imite une DLL de version 1.
- N'utilisez **pas** `-C target-cpu=native` : la DLL tourne sur une autre machine. Si `RUSTFLAGS` est encore
  défini dans le terminal (essais du banc), ouvrez-en un nouveau ou tapez `Remove-Item Env:RUSTFLAGS` : la
  variable remplacerait le réglage de `.cargo\config.toml` (runtime C lié statiquement).
- Erreur de liaison `LNK1181` ou `kernel32.lib` introuvable : installer les outils de génération C++ x86
  (Visual Studio Build Tools, « Développement Desktop en C++ »).
- Le dossier `target\` n'est pas suivi par git.
