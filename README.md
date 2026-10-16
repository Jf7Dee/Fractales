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

## Moteur Rust

La liste « Moteur » du panneau Navigation choisit qui calcule les pixels : le code Delphi (Extended 80 bits) ou la
DLL Rust `fractal_kernel.dll` (Double 64 bits, SIMD SSE2), placée à côté de `Fractales.exe`. La barre d'état
indique le moteur et le temps de chaque rendu. Sans la DLL, la liste est grisée et l'application calcule en Delphi.

En Rust, la limite de zoom arrive plus tôt (pixels d'environ 1e-13 contre 1e-16) : c'est la précision du Double.
Le moteur choisi n'est pas enregistré dans les lieux.

Compiler la DLL : voir `kernel-rust\README.md`.
