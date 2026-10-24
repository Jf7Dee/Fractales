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

Hors zoom profond (calcul direct), en Rust, la limite de zoom arrive plus tôt (pixels d'environ 1e-13 contre
1e-16) : c'est la précision du Double. Le moteur choisi n'est pas enregistré dans les lieux.

Compiler la DLL : voir `kernel-rust\README.md`.

## Zoom profond

Le calcul se fait en deux paliers, choisis automatiquement :

1. Calcul direct tant qu'il suffit (Extended en Delphi, Double en Rust).
2. Perturbation au-delà : une orbite de référence en haute précision, puis un petit écart par pixel. Elle prend le
   relais dès que le palier 1 annonce une « limite proche ».

La limite commune aux deux moteurs est une taille de pixel de 1e-300. La barre d'état indique « Delphi ·
perturbation : terminé en … ms », « … : orbite de référence… » pendant le calcul de la référence, et « Limite de
précision proche » près de 1e-300.

- Formules en zoom profond : Mandelbrot, Tricorn et Burning Ship. Julia et Multibrot gardent la limite actuelle
  (prévu plus tard).
- Référence : le centre de la vue ou, si son orbite s'échappe tôt, la plus longue de 9 points de la vue (grille
  3 × 3), calculée avec 25 % d'itérations en plus. Si elle ne s'échappe pas, elle est réutilisée par la vue
  suivante (déplacement ou zoom) de même formule et mêmes paramètres, tant qu'elle reste à moins de deux largeurs
  de vue du centre, que sa précision suffit et que MaxIter ne dépasse pas sa marge. Entre les bandes du rendu HD
  (même largeur de vue), une orbite échappée est elle aussi réutilisée.
- Les rendus profonds sont plus lents : plus d'itérations, plus l'orbite de référence.
- Les lieux (`.frac`, PNG) gardent le centre avec tous ses chiffres utiles ; les anciens fichiers se relisent à
  l'identique.
- Rust : la DLL doit être recompilée (ABI 2, nouvel export `fk_compute_row_perturbed`). Une ancienne DLL (ABI 1)
  fonctionne encore : rendus peu profonds en Rust, rendus profonds repris par Delphi.
