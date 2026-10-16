# Noyau de calcul Rust

DLL appelée par l'application Delphi quand on choisit « Moteur : Rust ». Mêmes formules que
`src\Fractal.Formulas.pas`, en f64 avec SIMD SSE2 (4 pixels à la fois).

## Compiler (sur la machine où Rust est installé)

Une seule fois, ajouter la cible 32 bits (Delphi 2010 ne charge que des DLL 32 bits) :

    rustup target add i686-pc-windows-msvc

Puis, dans ce dossier :

    cargo test
    cargo build --release --target i686-pc-windows-msvc

Copier `target\i686-pc-windows-msvc\release\fractal_kernel.dll` dans `bin\`, à côté de `Fractales.exe`.

- `cargo test` tourne en 64 bits (cible par défaut) : il vérifie l'algorithme. La DLL 32 bits est vérifiée par
  `./build.sh tests` côté Delphi, qui la charge et compare ses images à celles du moteur Delphi.
- N'utilisez **pas** `-C target-cpu=native` : la DLL tourne sur une autre machine. Si `RUSTFLAGS` est encore
  défini dans le terminal (essais du banc), ouvrez-en un nouveau ou tapez `Remove-Item Env:RUSTFLAGS` : la
  variable remplacerait le réglage de `.cargo\config.toml` (runtime C lié statiquement).
- Erreur de liaison `LNK1181` ou `kernel32.lib` introuvable : installer les outils de génération C++ x86
  (Visual Studio Build Tools, « Développement Desktop en C++ »).
- Le dossier `target\` n'est pas suivi par git.
