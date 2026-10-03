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
