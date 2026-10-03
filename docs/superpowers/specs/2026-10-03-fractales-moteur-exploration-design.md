# Fractales — Sous-projet 1 : moteur et exploration

Date : 2026-10-03
Statut : spec à relire

## 1. Objectif

Application personnelle Windows (VCL, Delphi 2010, 32 bits) pour générer et explorer en temps réel des fractales
de type Mandelbrot, avec contrôle de la formule, des couleurs (palettes) et sauvegarde des résultats.

Critères de réussite du sous-projet 1 :

- l'exploration à la souris est fluide : retour visuel immédiat, image affinée progressivement en quelques
  dixièmes de seconde sur une vue standard ;
- tous les cœurs du processeur sont utilisés pendant un rendu ;
- changer les réglages de couleur ne relance aucun calcul ;
- un PNG exporté peut être rouvert dans l'application et redonne exactement la même vue ;
- un rendu haute résolution (jusqu'à 8K, suréchantillonné) aboutit sans épuiser la mémoire.

## 2. Découpage global du projet

| # | Sous-projet | Statut |
|---|---|---|
| 1 | Moteur et exploration (ce document) | à concevoir / implémenter |
| 2 | Formules : formule libre (parseur), méthodes de coloration de l'intérieur | futur |
| 3 | Éditeur de palettes avancé | futur (version de base incluse dans le 1) |
| 4 | Vidéo : zoom continu, animation de palette (color cycling), export via `ffmpeg.exe` | futur |
| 5 | Zoom profond (> 10⁻¹⁶ : haute précision + perturbation) | futur |

## 3. Contraintes et choix techniques

- **Compilateur** : Delphi 2010, Win32 uniquement (pas de Win64 en D2010 ; en Win64, `Extended` = `Double`).
- **Composants** : VCL standard uniquement, aucune dépendance tierce. Graphics32 pourra être réévalué si le zoom
  continu (sous-projet 4) manque de fluidité.
- **Précision** : `TFloat = Extended` (80 bits, FPU x87), défini en un seul endroit. Zoom utile jusqu'à ~10⁻¹⁶.
- **PNG** : unité `pngimage` livrée avec D2010 (`TPNGObject`, blocs `tEXt`).
- **Emplacement** : `D:\Etudes\Dev\Perso\Fractales`, dépôt git propre, hors Multidev.
- **Tests** : DUnit (livré avec D2010), sur les unités sans VCL.

## 4. Architecture

Une unité par responsabilité. Dépendances à sens unique ; l'interface est au sommet, rien ne dépend d'elle.

```
Fractal.Types ← Fractal.Formulas ┐
              ← Fractal.Buffer  ─┴← Fractal.Engine ← Fractal.HiRes
Fractal.Palette (indépendante)
Fractal.Persistence (Types, Formulas, Palette)
Fractal.Navigation (Types)
MainForm + fiches (tout le reste)
```

| Unité | Rôle | VCL ? |
|---|---|---|
| `Fractal.Types` | `TFloat`, `TViewport` (centre X/Y, largeur visible, ratio), conversions pixel ↔ complexe, recadrage d'une sélection en conservant le ratio | non |
| `Fractal.Formulas` | `TFractalFormula` abstraite : `Iterate(cx, cy): Single` (valeur lissée, ou valeur « intérieur »), `Clone`, liste déclarative de paramètres (nom, type, défaut, min, max). Registre des formules. Formules livrées : Mandelbrot, Multibrot zⁿ (n réel), Julia (c réglable), Burning Ship, Tricorn | non |
| `Fractal.Buffer` | `TIterationBuffer` : tableau de `Single` (1 valeur/pixel) + état par tuile et indicateur « modifié » | non |
| `Fractal.Engine` | Pool de threads, file de tuiles, numéro de génération, passes progressives, collecte des erreurs | non |
| `Fractal.Palette` | `TGradientPalette` (points de couleur interpolés), lecture/écriture, import `.map` Fractint. `TColorMapper` : décalage, étirement, répétition, inversion → table de 4096 couleurs précalculée | non |
| `Fractal.Navigation` | `TNavigationMode` abstrait (réception des événements souris/clavier) ; modes Libre et Aperçu Julia ; sélection de zone au bouton droit commune à tous les modes ; historique Précédent/Suivant | non (événements abstraits) |
| `Fractal.Persistence` | Sérialisation d'un « lieu » (formule + paramètres, vue, itérations, palette, réglages couleur) en texte de type INI. Même texte pour `.frac` et pour le bloc `tEXt` du PNG. Gestion des favoris | non (PNG via `pngimage`) |
| `Fractal.HiRes` | Rendu hors écran à taille choisie, suréchantillonnage 1×/2×/3×, par bandes, écriture PNG, progression, annulation | `Graphics` + `pngimage` seulement (pas de fiche) |
| `MainForm`, `PaletteEditorForm`, `HiResDialog` | Interface ; assemblage des unités ci-dessus | oui |

## 5. Moteur de rendu (pool de threads et tuiles)

### 5.1 Requête de rendu

1. Le mode de navigation produit un nouveau `TViewport` et appelle `Engine.Render(viewport, formule, maxIter)`.
2. Le moteur incrémente le numéro de génération (`InterlockedIncrement`), vide la file, et construit un
   **instantané figé** : copie de la vue, `formule.Clone`, nombre d'itérations. Les threads ne lisent que cet
   instantané : aucun verrou dans la boucle de calcul.
3. La file est remplie en **4 passes** : blocs 8×8, puis 4×4, 2×2, 1×1. Dans une passe, tuiles (64×64) triées du
   centre vers les bords. Une passe ne recalcule pas les pixels déjà calculés par la passe précédente.

### 5.2 Threads de travail

- N threads permanents, N = nombre de processeurs logiques (`GetSystemInfo`), créés au démarrage.
- Boucle : retirer une tuile sous `TCriticalSection` (section critique limitée au retrait), la calculer, écrire
  dans le tampon, marquer le tampon « modifié ».
- Après **chaque ligne** de la tuile : si sa génération ≠ génération courante, abandon immédiat.
- File vide : attente sur un `TEvent` (aucune consommation CPU).
- Tout le traitement d'une tuile est dans un `try/except` : l'exception est consignée (message + génération) et le
  thread continue. Un thread ne meurt jamais en silence.

### 5.3 Affichage

- `TTimer` à ~30 i/s sur le thread principal : si le tampon est « modifié », conversion tampon → `TBitmap`
  `pf32bit` via `ScanLine` et la table du `TColorMapper`, puis `BitBlt` à l'écran. Les erreurs consignées par les
  threads sont affichées dans la barre d'état.
- Un changement de réglage de couleur relance uniquement cette conversion.
- Les threads n'appellent **jamais** la VCL (ni `Synchronize`, ni `Queue`).
- Pendant un glisser, l'image précédente est décalée immédiatement à l'écran, le nouveau rendu démarre en parallèle.

### 5.4 Itérations

- Maximum réglable ; option « auto » qui l'augmente avec la profondeur de zoom.

### 5.5 Arrêt

- Indicateur d'arrêt, réveil de tous les threads (`TEvent`), `WaitFor` sur chacun, puis libération du tampon.

## 6. Couleurs

- **Coloration lissée** (smooth coloring) systématique : valeur continue `n + 1 - log2(log|z|)` (adaptée à la
  puissance pour Multibrot).
- **Palettes** : liste de points (position 0..1, couleur), interpolation linéaire RVB. Quelques palettes livrées.
  Import des fichiers `.map` de Fractint (256 lignes `R G B`).
- **Réglages instantanés** : décalage, étirement, répétition, inversion. Intérieur de l'ensemble : noir
  (méthodes de coloration de l'intérieur → sous-projet 2).
- **Éditeur de palette (version de base)** : fiche séparée, barre de dégradé, points déplaçables, ajout/suppression,
  `TColorDialog`, aperçu en direct sur la vue principale.

## 7. Navigation

- Le mode est choisi dans la barre d'outils (liste déroulante). Chaque mode est une classe dérivée de
  `TNavigationMode`.
- **Libre** : molette = zoom centré sur le curseur ; glisser bouton gauche = déplacement.
- **Aperçu Julia** : comme Libre, plus une incrustation en coin affichant l'ensemble de Julia correspondant au
  point sous le curseur (basse résolution, même moteur, génération distincte).
- **Sélection de zone (tous les modes)** : rectangle tracé bouton droit enfoncé, contraint au ratio de la fenêtre ;
  la vue est recadrée au relâchement ; `Échap` annule.
- **Historique** : pile de vues Précédent/Suivant (`Retour arrière` / boutons).
- **Clavier** : `+`/`-` zoom, flèches déplacement, `F11` plein écran, `F4` panneau latéral.
- **Limite de précision** : avertissement dans la barre d'état à l'approche de 10⁻¹⁶ ; le zoom est bloqué au-delà.

## 8. Interface

```
┌──────────────────────────────────────────────────────────────────────┐
│ [Ouvrir][Enregistrer][PNG][Rendu HD] | Nav: [Libre ▼] | [◄][►] [★][▸]│
├──────────────────────────────────────────┬─┬─────────────────────────┤
│                                          │▸│ Formule: [Mandelbrot ▼] │
│                                          │ │  ─ paramètres (auto) ─  │
│            zone d'affichage              │ │  Puissance n  [ 2.0 ]   │
│                                          │ │  Itér. max [1000] ☑auto │
│                           ┌────────┐     │ │ Palette: [Feu ▼][Éditer]│
│                           │ Julia  │     │ │  Décalage / Étirement / │
│                           └────────┘     │ │  Répétition, ☐ Inverser │
│                                          │ │ Favoris                 │
├──────────────────────────────────────────┴─┴─────────────────────────┤
│ x=… y=… | zoom 1.2e8 | 1000 it | passe 3/4 | 82 ms | messages        │
└──────────────────────────────────────────────────────────────────────┘
```

- **Panneau latéral** redimensionnable par `TSplitter`, avec un bouton ▸/◂ contre le splitter pour le fermer ou
  le rouvrir en un clic (même action : bouton de barre d'outils et `F4`). La largeur précédente est restaurée à la
  réouverture.
- Contrôles de paramètres générés à partir de la déclaration de la formule.
- Barre d'état : coordonnées sous le curseur, profondeur de zoom, itérations, passe, temps de rendu, messages.

## 9. Sauvegarde

- **Export PNG** de la vue affichée, avec le « lieu » sérialisé dans un bloc `tEXt` (mot-clé `FractalLocation`).
- **Ouverture d'un PNG** : si le bloc est présent, la vue est restaurée ; sinon, message « ce PNG ne contient pas de
  lieu ».
- **Fichiers `.frac`** : même sérialisation, texte de type INI.
- **Favoris** : liste nommée de lieux, même format texte, stockée dans `%APPDATA%\Fractales\favoris.frac`.
- **Rendu HD** : boîte de dialogue (taille : préréglages 1080p, 4K, 8K ou personnalisée ; suréchantillonnage 1×,
  2×, 3× ; fichier de destination). Calcul **par bandes** écrites au fur et à mesure (pas de tampon complet en
  mémoire), barre de progression, annulation. L'exploration reste possible pendant le rendu.

## 10. Gestion des erreurs

- **Threads** : voir 5.2 (consignation + affichage, jamais de mort silencieuse).
- **Lecture de fichiers** (`.frac`, PNG, `.map`, palettes) : tolérante — clé inconnue ignorée, valeur absente →
  défaut, valeur hors plage → bornée. Fichier illisible → message clair, la vue courante est conservée.
- **Rendu HD** : vérification de la mémoire disponible avant le départ ; échec d'écriture (disque plein, etc.) →
  message et suppression du fichier partiel.

## 11. Tests (DUnit)

- **Formules** : points connus — (0,0) dans l'ensemble ; (2,2) s'échappe à la 1re itération ; continuité de la
  valeur lissée entre pixels voisins ; Julia avec c = 0 ↔ disque unité.
- **`TViewport`** : aller-retour pixel → complexe → pixel ; recadrage d'une sélection avec respect du ratio.
- **Palette** : interpolation, décalage, répétition, inversion ; import d'un vrai fichier `.map`.
- **Persistance** : sauvegarde puis relecture → lieu identique ; fichier corrompu → aucune exception non gérée.
- **Moteur** : rendu multi-thread identique, pixel pour pixel, à un rendu mono-thread ; après changement de
  génération, aucune écriture de l'ancien rendu dans le tampon.

## 12. Hors périmètre (sous-projet 1)

Formule libre, coloration de l'intérieur, animation de palette, zoom continu, vidéo, zoom profond, TIFF 16 bits,
composants tiers.
