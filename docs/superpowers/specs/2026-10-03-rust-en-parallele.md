# Fractales : le même projet vu en Rust (notions)

Date : 2026-10-03
Statut : document de familiarisation. Aucun développement Rust n'est prévu pour l'instant.

Le but : pour chaque morceau du sous-projet 1 (Delphi 2010), montrer comment on le ferait en Rust, avec quels
outils, et ce que Rust apporterait ou coûterait **sur ce projet précis**. Les extraits de code servent à donner
la forme du langage ; ils ne sont pas destinés à être compilés tels quels.

## 1. Vue d'ensemble

| Sujet | Delphi 2010 (plan actuel) | Rust (équivalent) |
|---|---|---|
| Projet, compilation | `.dpr` + `dcc32`, `build.sh` | `Cargo.toml` + `cargo build --release` |
| Unités | `Fractal.Engine.pas` | modules : `src/engine.rs` (`mod engine;`) |
| Bibliothèques | VCL, RTL, `ZLib` | « crates » téléchargées par Cargo (voir §3) |
| Tests | DUnit, programme console séparé | intégrés : `#[test]` dans le même fichier, `cargo test` |
| Mémoire | `Create` / `try..finally Free` | automatique : libérée quand la variable sort de portée |
| Erreurs | exceptions (`raise`, `try..except`) | valeurs de retour `Result<T, E>` et opérateur `?` |
| Classes, héritage | `TFractalFormula` + `virtual` | `trait Formula` + `impl Formula for Mandelbrot` |
| Interface graphique | VCL + concepteur de fiches | `egui`/`eframe` (code seulement, pas de concepteur) |
| Plateformes | Windows 32 bits | Windows, Linux, macOS, 64 bits ; même WebAssembly |

L'architecture du plan s'y transpose presque telle quelle : les unités `Fractal.*` sans VCL deviendraient une
bibliothèque (`fractal-core`) et l'interface un second module qui l'utilise. C'est d'ailleurs une bonne
nouvelle pour la version Delphi : ce découpage est sain dans les deux langages.

## 2. Unité par unité

### `Fractal.Types` → structs et `f64`

```rust
pub type Float = f64;   // pas de type 80 bits en Rust : voir §4.1

#[derive(Clone, Copy, Debug)]
pub struct Viewport {
    pub center_x: Float,
    pub center_y: Float,
    pub width: Float,
    pub pixel_width: u32,
    pub pixel_height: u32,
}

impl Viewport {
    pub fn pixel_size(&self) -> Float {
        self.width / self.pixel_width as Float
    }

    pub fn zoomed_at(&self, px: Float, py: Float, factor: Float) -> Viewport {
        let p = self.pixel_to_complex(px, py);
        Viewport {
            width: self.width / factor,
            center_x: p.0 + (self.center_x - p.0) / factor,
            center_y: p.1 + (self.center_y - p.1) / factor,
            ..*self   // les autres champs sont copiés
        }
    }
}
```

À noter : `&self` correspond au `Self` implicite de Delphi ; une variable est non modifiable par défaut
(`let`), et il faut écrire `let mut` pour pouvoir la changer.

### `Fractal.Formulas` → un trait

```rust
pub trait Formula: Send + Sync {          // Send + Sync : utilisable par plusieurs threads
    fn name(&self) -> &'static str;
    fn iterate(&self, cx: f64, cy: f64) -> Option<f32>;   // None = intérieur (remplace kInside)
}

pub struct Mandelbrot { pub max_iter: u32 }

impl Formula for Mandelbrot {
    fn name(&self) -> &'static str { "Mandelbrot" }

    fn iterate(&self, cx: f64, cy: f64) -> Option<f32> {
        let (mut x, mut y) = (0.0, 0.0);
        for n in 0..self.max_iter {
            let (x2, y2) = (x * x, y * y);
            if x2 + y2 > ESCAPE_RADIUS2 {
                return Some(smooth(n, x2 + y2));
            }
            y = 2.0 * x * y + cy;
            x = x2 - y2 + cx;
        }
        None
    }
}
```

`Option<f32>` remplace la valeur sentinelle `-1` : le compilateur oblige à traiter le cas « intérieur ». Le
`Send + Sync` est vérifié à la compilation : une formule qui ne serait pas sûre entre threads serait refusée.

### `Fractal.Engine` → `rayon` et les garanties du compilateur

C'est l'endroit où Rust change le plus de choses. Le moteur Delphi du plan fait environ 300 lignes : pool de
threads, file de tuiles, section critique, événements, numéro de génération. En Rust, la bibliothèque `rayon`
fournit le pool et la répartition du travail :

```rust
use rayon::prelude::*;

// une passe complète : chaque ligne du tampon calculée en parallèle, sur tous les cœurs
buffer
    .par_chunks_mut(width)                 // découpe le tampon en lignes, une par tâche
    .enumerate()
    .for_each(|(y, row)| {
        if cancel.load(Ordering::Relaxed) != generation { return; }   // annulation
        for (x, value) in row.iter_mut().enumerate() {
            let (cx, cy) = view.pixel_to_complex(x as f64, y as f64);
            *value = formula.iterate(cx, cy);
        }
    });
```

Ce que le compilateur garantit ici, et que Delphi laisse à la discipline du développeur :

- **Pas de course de données possible.** `par_chunks_mut` donne à chaque thread une tranche du tampon qui ne
  recoupe aucune autre. Si deux threads pouvaient écrire au même endroit, le programme ne compilerait pas.
  En Delphi, c'est le raisonnement « les tuiles sont disjointes » qui le garantit, sans vérification.
- **Pas d'objet libéré pendant qu'un thread l'utilise.** Le test Delphi `TestNoStaleWritesAfterNewRender`
  existe parce que l'ancien rendu pourrait écrire dans un tampon déjà réutilisé. En Rust, la durée de vie
  d'une référence est vérifiée : on ne peut pas libérer le tampon tant qu'un thread y a accès.
- **Ce qui reste à faire soi-même** : la logique métier de l'annulation (le numéro de génération), l'ordre des
  passes progressives, l'ordre des tuiles du centre vers les bords. Rust supprime une classe de bugs, pas le
  besoin de concevoir.

### `Fractal.Buffer` → `Vec<f32>`

```rust
pub struct IterationBuffer {
    width: usize,
    values: Vec<f32>,   // tableau dynamique, libéré automatiquement
    levels: Vec<u8>,
}
```

Les accès hors limites sont vérifiés (le programme s'arrête net avec un message au lieu d'écrire n'importe où,
contrairement à Delphi avec `{$R-}`). Les vérifications disparaissent quand le compilateur prouve qu'elles sont
inutiles, ce qui est fréquent dans les boucles simples.

### `Fractal.Palette` → structs + `serde`

La palette se transpose directement. La lecture et l'écriture des fichiers se font avec `serde`, qui génère le
code à partir de la déclaration :

```rust
#[derive(Serialize, Deserialize)]
pub struct ColorStop { pub position: f64, pub color: [u8; 3] }

#[derive(Serialize, Deserialize)]
pub struct Palette { pub name: String, pub stops: Vec<ColorStop> }
```

### `Fractal.Png` → crate `png`

Le plan Delphi écrit son propre encodeur PNG en flux (environ 250 lignes), parce que `TPngImage` garde toute
l'image en mémoire. En Rust, la crate `png` fournit déjà une écriture ligne par ligne (`StreamWriter`) et les
blocs texte (`tEXt`/`iTXt`). Cette tâche se réduirait à une vingtaine de lignes.

### `Fractal.Persistence` → `serde` + `toml`

Le fichier `.frac` deviendrait du TOML, un format proche de l'INI. Il n'y a plus de code de lecture ou
d'écriture à écrire : on déclare la structure et `serde` fait le reste. Les nombres y sont toujours écrits avec
un point, quelle que soit la langue de Windows : le piège de la virgule décimale disparaît.

```toml
formula = "Multibrot"
center_x = -0.7436438870371587
center_y = 0.1318259042053119
width = 1.5e-10

[params]
power = 4.5
```

### `Fractal.Navigation` → struct + `enum`

Les modes de navigation deviendraient une énumération avec données, que le compilateur oblige à traiter de
manière exhaustive :

```rust
enum NavMode {
    Free { dragging: Option<(i32, i32)> },
    JuliaPreview { dragging: Option<(i32, i32)> },
}
```

Le `match` sur un `enum` refuse de compiler si on oublie un cas. C'est la version stricte du `case` Delphi.

### `Fractal.HiRes` → un thread + les mêmes briques

Un `std::thread::spawn` pour la coordination, le moteur `rayon` pour chaque bande, et la crate `png` pour
l'écriture. Même structure qu'en Delphi.

### Interface (`MainFrm`, dialogues) → `egui` / `eframe`

C'est le point faible de Rust par rapport à Delphi.

- **Pas de concepteur visuel** comme celui de l'IDE Delphi : toute l'interface s'écrit en code.
- `egui` fonctionne en **mode immédiat** : à chaque image, on redécrit l'interface entière, et l'état vit dans
  vos propres structures. C'est déroutant au début, mais très simple pour ce type d'application (une zone
  d'image, un panneau de réglages, quelques curseurs) :

```rust
egui::SidePanel::right("reglages").show(ctx, |ui| {
    ui.heading("Couleurs");
    if ui.add(egui::Slider::new(&mut self.offset, 0.0..=1.0).text("Décalage")).changed() {
        self.colors_changed = true;
    }
});
```

- L'affichage de l'image passe par une texture GPU (`egui::TextureHandle`), ce qui donne des zooms fluides
  gratuitement. C'est utile pour le futur zoom continu (sous-projet 4).

## 3. Les crates qui remplaceraient les briques du plan

| Besoin | Crate | Remarque |
|---|---|---|
| Parallélisme | `rayon` | standard de fait ; remplace tout le pool de threads |
| Nombres complexes | `num-complex` | optionnel, l'arithmétique à la main reste plus rapide |
| PNG en flux + texte | `png` | remplace `Fractal.Png` |
| Sérialisation | `serde` + `toml` | remplace `Fractal.Persistence` (hors favoris) |
| Interface | `eframe` (`egui`) | fenêtre, panneaux, curseurs, image |
| Dossiers système | `dirs` | `%APPDATA%`, dossier Images |
| Vidéo (sous-projet 4) | appel de `ffmpeg` via `std::process::Command` | identique à l'approche Delphi prévue |
| Haute précision (sous-projet 5) | `rug` (GMP/MPFR) ou `astro-float` | bien plus mûr que ce qui existe pour D2010 |
| Tests de performance | `criterion` | mesures fiables, sans équivalent simple en D2010 |

## 4. Ce que Rust changerait concrètement pour ce projet

### 4.1 Précision : un point pour Delphi, aujourd'hui

Rust n'a pas de type flottant 80 bits. Le `f64` s'arrête vers un zoom de 10⁻¹³, alors que l'`Extended` de
Delphi 32 bits va gratuitement jusqu'à environ 10⁻¹⁶ (tâche 1 du plan). Pour faire mieux en Rust, il faut
passer à de la double-double (crate `twofloat`, environ 10⁻³⁰, mais plus lent) ou directement au zoom profond.

À long terme, le zoom profond (sous-projet 5) se ferait de toute façon avec de la haute précision et de la
perturbation. Rust y est nettement mieux outillé : `rug` repose sur GMP et MPFR, les bibliothèques de référence.

### 4.2 Vitesse : un net avantage pour Rust

- Delphi 2010 génère du code x87 scalaire : un seul calcul flottant à la fois, sans vectorisation.
- Rust (compilateur LLVM, 64 bits) utilise SSE2 et AVX2, et peut calculer 4 pixels `f64` à la fois avec du
  code SIMD explicite (crate `wide`, ou `std::simd`).
- Ordre de grandeur réaliste pour la boucle de Mandelbrot : 2 à 3 fois plus rapide en scalaire, 6 à 10 fois en
  SIMD sur un processeur récent. Ce sont des estimations ; seule une mesure sur ta machine trancherait.

### 4.3 Fiabilité : moins de catégories de bugs

Les bugs les plus coûteux du plan Delphi sont des bugs de concurrence et de durée de vie : écritures périmées,
objet libéré pendant qu'un thread l'utilise, double libération. Le plan les contient par conception et par
des tests. En Rust, la plupart sont **refusés à la compilation**. Le prix est une phase d'apprentissage où le
compilateur refuse souvent ce qui « marcherait » en Delphi.

### 4.4 Productivité de l'interface : un point pour Delphi

Pour une application de bureau Windows avec fiches et boîtes de dialogue, Delphi reste plus rapide à
assembler. `egui` suffit amplement pour cette application, mais sans concepteur, avec un rendu moins
« Windows natif ».

### 4.5 Écosystème et outillage

Cargo (dépendances, compilation, tests, documentation) dans un seul outil, mises à jour faciles, rien à
installer à la main. Delphi 2010 date de 2009 : pas de 64 bits, pas de gestionnaire de paquets, et un code
PNG ou JSON à réécrire soi-même (comme le montre la tâche 6 du plan).

## 5. Comment s'y familiariser sans développer

Une progression courte, en lecture seule, qui suit l'ordre du plan Delphi :

1. **Le livre officiel** (« The Rust Programming Language », gratuit en ligne), chapitres 1 à 10 :
   variables, fonctions, `struct`, `enum`, `match`, `Option`/`Result`, traits. Ce sont exactement les notions
   des extraits ci-dessus.
2. **Chapitre 4 (ownership)** et **chapitre 16 (concurrence)** : ce sont ceux qui expliquent §2 « moteur » et
   §4.3. C'est la vraie nouveauté par rapport à Delphi.
3. **Rust by Example** : pour chaque notion, un petit exemple modifiable dans le navigateur, sans rien installer.
4. **Lire, pas écrire** : le dépôt de la crate `rayon` et un petit explorateur de Mandelbrot en `egui` pour voir
   la forme d'un vrai programme.

Le jour où tu voudras passer à la pratique, l'expérience la plus parlante serait étroite et mesurable :
réécrire **uniquement** la boucle `Iterate` de Mandelbrot et un rendu parallèle 1920×1080 en Rust, puis
comparer le temps avec `Fractal.Engine` sur la même vue. Cela demande quelques heures et répond directement à
la question « Rust est-il un meilleur outil ici ? » sur le critère qui compte le plus pour un explorateur de
fractales.

## 6. Bilan provisoire

| Critère | Avantage |
|---|---|
| Vitesse de calcul | Rust (64 bits, SIMD) |
| Précision sans effort (jusqu'à 10⁻¹⁶) | Delphi (`Extended`) |
| Zoom profond (futur) | Rust (`rug`) |
| Sûreté en multi-thread | Rust (vérifiée à la compilation) |
| Rapidité pour construire l'interface | Delphi (concepteur VCL) |
| Bibliothèques prêtes (PNG, sérialisation) | Rust |
| Courbe d'apprentissage pour toi | Delphi, évidemment |

Le plan Delphi reste un bon choix pour obtenir rapidement une application qui fonctionne. Rust deviendrait
intéressant si la vitesse brute, le 64 bits ou le zoom profond deviennent prioritaires, c'est-à-dire
précisément pour les sous-projets 4 et 5.

## 7. Mesures réelles (2026-10-04)

Programmes : `bench\FractalesBench.dpr` (le vrai `Fractal.Engine`, Delphi 2010, Extended 80 bits x87) et
`bench-rust` (f64, `rayon` avec une tâche par ligne, mode scalaire et mode SIMD `wide` f64x4). Même machine
(4 cœurs logiques, processeur sans AVX, donc SIMD limité à SSE2), 1920×1080, médiane de 5 rendus. Les sommes de
contrôle (points intérieurs) sont identiques partout : les deux programmes font le même travail.

| Scène (4 threads) | Delphi | Rust scalaire | Rust SIMD (SSE2) |
|---|---|---|---|
| Vue d'ensemble (1 000 it.) | 359 ms | 108 ms (×3,3) | 63 ms (×5,7) |
| Vue profonde (5 000 it.) | 8 986 ms | 2 872 ms (×3,1) | 1 003 ms (×9,0) |
| Intérieur lourd (2 000 it.) | 9 596 ms | 3 089 ms (×3,1) | 1 050 ms (×9,1) |

Les rapports sont du même ordre sur 1 thread. Les estimations du §4.2 (2 à 3× en scalaire, 6 à 10× en SIMD) sont
confirmées ; AVX reste à mesurer sur un processeur qui l'a.

**Pièges rencontrés :**
- Un programme Rust lancé depuis l'IDE (« Process finished with exit code 0 ») est compilé en **debug** : la mesure ne
  vaut rien, et le SIMD `wide` y devient 8× plus lent que le scalaire. Toujours mesurer avec `cargo run --release`.
- Dans PowerShell, `set VAR=…` ne définit pas de variable d'environnement : écrire `$env:RUSTFLAGS="-C target-cpu=native"`.
- Une parallélisation par gros blocs de lignes contiguës équilibre mal la charge (×1,7 sur 4 cœurs pour la vue
  profonde) ; une tâche par ligne (`with_max_len(1)`) ou par tuile, comme le moteur Delphi, donne ×3,6 à ×3,9.
