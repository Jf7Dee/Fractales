# Banc d'essai Delphi / Rust

Mêmes trois scènes en 1920×1080, même algorithme (rayon d'échappement 256, test de la cardioïde, valeur lissée),
médiane de 5 rendus, sur 1 thread puis sur tous les cœurs logiques.

| Scène | Formule | Centre | Largeur | MaxIter |
|---|---|---|---|---|
| Vue d'ensemble | Mandelbrot | (−0,5 ; 0) | 3 | 1 000 |
| Vue profonde | Mandelbrot | (−0,743643887037151 ; 0,131825904205330) | 1e−9 | 5 000 |
| Intérieur lourd | Julia c = 0 | (0 ; 0) | 3 | 2 000 |

## Lancer, sur la même machine

Delphi (exécutable déjà compilé, aucune installation nécessaire) :

```
bin\FractalesBench.exe
```

Rust :

```
cd bench-rust
cargo run --release
```

Variante Rust optimisée pour le processeur exact de la machine (AVX2, FMA…) :

```
set RUSTFLAGS=-C target-cpu=native
cargo run --release
```

Chaque programme dure quelques minutes ; le gros du temps passe dans les rendus sur 1 thread.

Le programme Rust mesure deux modes : **scalaire** (un pixel à la fois, comme Delphi) et **SIMD x4** (quatre pixels
voisins à la fois avec la crate `wide`). Sans `target-cpu=native`, le SIMD se limite à SSE2 (2 × 2 pixels) ; avec,
il utilise AVX si le processeur l'a. La première ligne affichée indique lequel est actif.

En parallèle, Rust crée une tâche par ligne (`with_max_len(1)`) : les cœurs libres prennent la ligne suivante, ce qui
équilibre la charge comme la file de tuiles du moteur Delphi.

## Lire les résultats

- **ms (méd)** : temps médian d'un rendu complet.
- **Intérieur** et **Somme lissée** : sommes de contrôle. Le nombre de points intérieurs doit être identique ou presque ;
  la somme lissée peut différer légèrement, car Delphi calcule en Extended 80 bits et Rust en f64.
- Le rendu Delphi passe par le vrai moteur (`Fractal.Engine` : tuiles, file de travail, générations) ; le rendu Rust
  est une boucle directe avec `rayon`. L'écart mesure donc le langage **et** le surcoût du moteur.
