# Fractales — Moteur de calcul Rust dans l'application Delphi : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** une liste « Moteur : Delphi / Rust » dans l'application ; en mode Rust, les pixels sont calculés par une
DLL Rust 32 bits (`fractal_kernel.dll`, f64 + SIMD SSE2) au lieu du code Delphi (Extended x87), sur les mêmes vues.

**Architecture :** la DLL exporte deux fonctions C (`fk_abi_version`, `fk_compute_row`). Côté Delphi, une unité
sans VCL (`Fractal.RustKernel`) charge la DLL et l'appelle ; le moteur (`Fractal.Engine`) reçoit un noyau
(`ekDelphi` / `ekRust`) figé à chaque rendu et, en mode Rust, envoie à la DLL des suites de pixels consécutifs.
Une DLL **factice écrite en Delphi** (`tests\FakeKernel.dpr`, mêmes exports, calcul par `Fractal.Formulas`)
permet de tester tout le chemin Rust ici, où Rust n'est pas installé. La vraie DLL est compilée chez JF.

**Tech Stack :** Delphi 2010 (dcc32 21.0, Win32), VCL, DUnit ; Rust (édition 2021, crate `wide` 0.7) compilé pour
`i686-pc-windows-msvc` sur la machine de JF.

**Spec :** `docs/superpowers/specs/2026-10-04-moteur-rust-design.md`

## Global Constraints

- Delphi 2010, Win32 uniquement. Pas de syntaxe postérieure à 2010 (pas de `var` en ligne, pas de chaînes
  multi-lignes).
- Racine : `D:\Etudes\Dev\Perso\Fractales` (dépôt git local, commits autorisés). Commandes en Git Bash.
- `.pas`/`.dpr`/`.md` : **UTF-8 avec BOM** pour `.pas`/`.dpr`, fins de ligne **CRLF** pour tous. Après chaque
  écriture d'un fichier avec l'outil Write, lancer `tools/normalize.sh <fichiers>`. Les `.dfm` restent en ASCII
  pur (accents en `#233`). Les fichiers Rust (`.rs`, `.toml`) restent en UTF-8 **sans** BOM, fins de ligne LF.
- Entre deux routines Pascal : une ligne vide, le séparateur `{` + 78 tirets + `}`, une ligne vide. Dans ce plan,
  le séparateur est écrit `//SEP` dans les fichiers **créés** ; avant `tools/normalize.sh`, lancer
  `sed -i 's#^//SEP$#{------------------------------------------------------------------------------}#' <fichier>`.
  Dans les fichiers **existants**, écrire directement le vrai séparateur ; une routine nouvelle s'insère
  **sous** sa routine appelante ou à l'endroit indiqué, jamais en s'ancrant sur le mot-clé `function` d'une
  routine existante (on placerait le texte entre son séparateur et elle).
- Largeur de ligne : 120 caractères. Commentaires et textes d'interface en français ; identifiants en anglais.
- Booléens préfixés `Is`/`Has`/`Should`. Constantes nommées pour tout littéral utilisé deux fois ou plus.
- Unités nouvelles déclarées dans **chaque** `.dpr` qui les compile (`uses X in 'chemin'`) : `Fractales.dpr`,
  `tests\FractalesTests.dpr`, `bench\FractalesBench.dpr` (le banc compile `Fractal.Engine`, qui utilisera
  `Fractal.RustKernel`).
- Les threads de calcul n'appellent jamais la VCL.
- Zéro avertissement et zéro conseil du compilateur sur les unités touchées.
- Nom de la DLL : `fractal_kernel.dll`, cherchée dans le dossier de l'exécutable. Version d'interface : `1`.
- Codes de retour de `fk_compute_row` : 0 succès, 1 formule inconnue, 2 nombre de paramètres incorrect,
  3 argument invalide, 4 erreur interne.
- Identifiants de formule : 0 Mandelbrot, 1 Multibrot (power), 2 Julia (cx, cy), 3 Burning Ship, 4 Tricorn.
- Le moteur choisi n'est **pas** enregistré dans les lieux (`.frac`, PNG).
- Commits : messages courts en français, terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Commandes de vérification : `./build.sh tests` (tests DUnit, sortie « OK »), `./build.sh app`,
  `./build.sh smoke`, `./build.sh bench` (doit seulement compiler et tourner).

## Écarts assumés par rapport à la spec

1. **Choix du noyau** : `TRenderEngine.Kernel` est une propriété lue (et figée) au début de chaque
   `Render`/`RenderShifted`, au lieu d'un paramètre supplémentaire de ces méthodes. Même comportement, aucun
   appelant existant à modifier.
2. **`RustComputeRow`** devient la méthode `TRustKernel.ComputeRow`, qui **lève** `ERustKernelError` (message
   « Moteur Rust : … (code N). ») au lieu de renvoyer le code. Le moteur n'a ainsi rien à traduire. Une classe
   plutôt que des fonctions globales : les tests chargent une DLL factice ou absente sans toucher à la DLL par
   défaut (`DefaultRustKernel`), que l'application utilise.
3. **Liste « Moteur »** : la VCL ne sait pas griser une seule entrée d'une liste déroulante ; sans DLL, toute la
   liste est désactivée (elle reste sur Delphi) et son info-bulle donne la raison.
4. **DLL factice** `tests\FakeKernel.dpr` : ajoutée pour tester ici le chargement et le moteur en mode Rust.
5. **Runtime C lié statiquement** dans la DLL Rust (`kernel-rust\.cargo\config.toml`) : la DLL ne dépend pas
   du redistribuable Visual C++ sur la machine Delphi.

## Review Focus

1. **DLL 64 bits copiée par erreur** (compilée sans `--target i686-pc-windows-msvc`) : `LoadLibrary` échoue avec
   l'erreur 193 ; l'application doit rester en Delphi et dire pourquoi, en citant la bonne cible. Test : tâche 3,
   `TestBadFormatFileIsUnavailable` (un fichier texte nommé `.dll` produit la même erreur 193).
2. **Mauvaise DLL** (autre DLL portant ce nom, ou ancienne version sans les exports) : indisponible, raison
   affichée, aucun appel. Test : tâche 3, `TestDllWithoutExportsIsUnavailable` (charge `version.dll` du système).
3. **Tuiles de bord et suites courtes** : une image dont la taille n'est pas un multiple de 64, des suites de
   1 à 3 pixels, des comptes non multiples de 4 côté SIMD. Tests : tâche 4 (vue 203 × 149) ; tâche 1
   (`count = 7`).
4. **Réactivité en mode Rust** : une suite peut contenir 64 pixels, calculés d'un seul appel non interruptible ;
   un nouveau rendu doit tout de même partir vite. Test : tâche 4, `TestNewRenderIsQuickInRustMode`.
5. **Voies SIMD déjà échappées** qui continuent de calculer jusqu'à l'infini ou NaN : elles ne doivent jamais
   modifier le résultat. Test : tâche 1, `simd_matches_scalar_exactly` (lignes mêlant intérieur et extérieur).

---

### Task 1: DLL Rust `kernel-rust`

Écrite ici, **compilée et testée chez JF** (Rust n'est pas installé sur cette machine). L'implémenteur écrit les
fichiers, vérifie la syntaxe à la lecture, et commite ; la vérification `cargo test` / `cargo build` est faite
par JF et consignée au ledger quand il la renvoie.

**Files:**
- Create: `kernel-rust/Cargo.toml`
- Create: `kernel-rust/.cargo/config.toml`
- Create: `kernel-rust/src/lib.rs`
- Create: `kernel-rust/README.md`
- Modify: `.gitignore` (ajouter `kernel-rust/target/`)

**Interfaces:**
- Produces: `fractal_kernel.dll` exportant
  `fk_abi_version() -> u32` et
  `fk_compute_row(formula: i32, params: *const f64, param_count: i32, max_iter: i32, x0: f64, dx: f64, y: f64,
  count: i32, out: *mut f32) -> i32` (convention C = cdecl en 32 bits).

- [ ] **Step 1: Écrire `kernel-rust/Cargo.toml`**

```toml
[package]
name = "fractal_kernel"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wide = "0.7"

# pas de panic = "abort" : fk_compute_row rattrape les paniques avec catch_unwind
[profile.release]
opt-level = 3
codegen-units = 1
lto = true
```

- [ ] **Step 2: Écrire `kernel-rust/.cargo/config.toml`**

```toml
# DLL autonome : le runtime C est lié statiquement, inutile d'installer le redistribuable Visual C++
# sur la machine où tourne l'application Delphi.
[target.i686-pc-windows-msvc]
rustflags = ["-C", "target-feature=+crt-static"]
```

- [ ] **Step 3: Écrire `kernel-rust/src/lib.rs` (code et tests)**

```rust
// Noyau de calcul des fractales pour l'application Delphi (src\Fractal.RustKernel.pas).
// Mêmes algorithmes que src\Fractal.Formulas.pas, en f64 (64 bits) au lieu de l'Extended 80 bits de Delphi.
//
// Interface C (convention cdecl en 32 bits) :
//   fk_abi_version() -> u32
//   fk_compute_row(formula, params, param_count, max_iter, x0, dx, y, count, out) -> i32
// Calcule `count` pixels de la ligne d'ordonnée y, d'abscisses x0 + i·dx ; out[i] reçoit la valeur lissée,
// ou -1 pour un point intérieur.
//
// Compiler la DLL 32 bits :  cargo build --release --target i686-pc-windows-msvc

use std::f64::consts::LN_2;
use std::panic::{catch_unwind, AssertUnwindSafe};
use wide::*;

pub const ABI_VERSION: u32 = 1;

pub const FK_OK: i32 = 0;
pub const FK_UNKNOWN_FORMULA: i32 = 1;
pub const FK_BAD_PARAM_COUNT: i32 = 2;
pub const FK_INVALID_ARGUMENT: i32 = 3;
pub const FK_INTERNAL_ERROR: i32 = 4;

const ESCAPE_RADIUS2: f64 = 65536.0; // rayon d'échappement 256, comme Fractal.Formulas
const INSIDE: f32 = -1.0;
const LANES: usize = 4;
const ALL_LANES_DONE: u32 = 0b1111;

#[derive(Clone, Copy, PartialEq, Debug)]
enum Formula {
    Mandelbrot,
    Multibrot { power: f64, log_power: f64 },
    Julia { cx: f64, cy: f64 },
    BurningShip,
    Tricorn,
}

impl Formula {
    // Identifiants et paramètres : TFractalFormula.KernelId et GetParam côté Delphi.
    fn from_id(id: i32, params: &[f64]) -> Result<Formula, i32> {
        let expected_params = match id {
            0 | 3 | 4 => 0,
            1 => 1,
            2 => 2,
            _ => return Err(FK_UNKNOWN_FORMULA),
        };
        if params.len() != expected_params {
            return Err(FK_BAD_PARAM_COUNT);
        }
        match id {
            0 => Ok(Formula::Mandelbrot),
            1 => {
                let power = params[0];
                if !power.is_finite() || power <= 0.0 {
                    return Err(FK_INVALID_ARGUMENT);
                }
                Ok(Formula::Multibrot { power, log_power: power.ln() })
            }
            2 => Ok(Formula::Julia { cx: params[0], cy: params[1] }),
            3 => Ok(Formula::BurningShip),
            _ => Ok(Formula::Tricorn),
        }
    }

    // Multibrot passe par exp, ln, atan2, cos et sin : calcul scalaire seulement.
    fn is_vectorizable(self) -> bool {
        !matches!(self, Formula::Multibrot { .. })
    }
}

// Valeur lissée, identique à TFractalFormula.SmoothValue.
fn smooth_value(n: i32, modulus2: f64, log_power: f64) -> f32 {
    let mu = n as f64 + 1.0 - (0.5 * modulus2.ln()).ln() / log_power;
    if mu < 0.0 {
        0.0
    } else {
        mu as f32
    }
}

// Cardioïde principale et bulbe de période 2 : intérieur garanti, inutile d'itérer.
fn is_in_main_bulbs(cx: f64, cy: f64) -> bool {
    let q = (cx - 0.25) * (cx - 0.25) + cy * cy;
    q * (q + (cx - 0.25)) <= 0.25 * cy * cy || (cx + 1.0) * (cx + 1.0) + cy * cy <= 0.0625
}

// ---------------------------------------------------------------------------------------------------------------
// Calcul scalaire : un pixel à la fois.

fn iterate(formula: Formula, max_iter: i32, px: f64, py: f64) -> f32 {
    match formula {
        Formula::Mandelbrot => {
            if is_in_main_bulbs(px, py) {
                return INSIDE;
            }
            iterate_quadratic(max_iter, 0.0, 0.0, px, py, |x, y, k| 2.0 * x * y + k)
        }
        Formula::Julia { cx, cy } => iterate_quadratic(max_iter, px, py, cx, cy, |x, y, k| 2.0 * x * y + k),
        // - k : le navire apparaît à l'endroit avec un axe imaginaire qui monte
        Formula::BurningShip => iterate_quadratic(max_iter, 0.0, 0.0, px, py, |x, y, k| 2.0 * (x * y).abs() - k),
        Formula::Tricorn => iterate_quadratic(max_iter, 0.0, 0.0, px, py, |x, y, k| -2.0 * x * y + k),
        Formula::Multibrot { power, log_power } => iterate_multibrot(max_iter, power, log_power, px, py),
    }
}

// z ← (x² − y² + kx) + i·next_y(x, y, ky), en partant de (x, y).
fn iterate_quadratic(
    max_iter: i32,
    mut x: f64,
    mut y: f64,
    kx: f64,
    ky: f64,
    next_y: impl Fn(f64, f64, f64) -> f64,
) -> f32 {
    for n in 0..max_iter {
        let x2 = x * x;
        let y2 = y * y;
        if x2 + y2 > ESCAPE_RADIUS2 {
            return smooth_value(n, x2 + y2, LN_2);
        }
        y = next_y(x, y, ky);
        x = x2 - y2 + kx;
    }
    INSIDE
}

fn iterate_multibrot(max_iter: i32, power: f64, log_power: f64, cx: f64, cy: f64) -> f32 {
    let mut x = 0.0_f64;
    let mut y = 0.0_f64;
    for n in 0..max_iter {
        let m = x * x + y * y;
        if m > ESCAPE_RADIUS2 {
            return smooth_value(n, m, log_power);
        }
        if m == 0.0 {
            x = cx;
            y = cy;
        } else {
            // z^n en polaire : accepte une puissance non entière
            let r = (0.5 * m.ln() * power).exp();
            let t = y.atan2(x) * power;
            x = r * t.cos() + cx;
            y = r * t.sin() + cy;
        }
    }
    INSIDE
}

// ---------------------------------------------------------------------------------------------------------------
// Calcul SIMD : quatre pixels voisins à la fois, mêmes opérations dans le même ordre que le scalaire.

fn iterate4(formula: Formula, max_iter: i32, pxs: [f64; LANES], py: f64) -> [f32; LANES] {
    let two = f64x4::splat(2.0);
    let minus_two = f64x4::splat(-2.0);
    let zero = f64x4::splat(0.0);
    let vx = f64x4::new(pxs);
    let vy = f64x4::splat(py);
    match formula {
        Formula::Mandelbrot => {
            let mut done: u32 = 0;
            for (lane, &px) in pxs.iter().enumerate() {
                if is_in_main_bulbs(px, py) {
                    done |= 1 << lane;
                }
            }
            iterate4_quadratic(max_iter, done, zero, zero, vx, vy, |x, y, k| two * x * y + k)
        }
        Formula::Julia { cx, cy } => {
            iterate4_quadratic(max_iter, 0, vx, vy, f64x4::splat(cx), f64x4::splat(cy), |x, y, k| two * x * y + k)
        }
        Formula::BurningShip => {
            iterate4_quadratic(max_iter, 0, zero, zero, vx, vy, |x, y, k| two * (x * y).abs() - k)
        }
        Formula::Tricorn => iterate4_quadratic(max_iter, 0, zero, zero, vx, vy, |x, y, k| minus_two * x * y + k),
        Formula::Multibrot { .. } => {
            let mut result = [INSIDE; LANES];
            for lane in 0..LANES {
                result[lane] = iterate(formula, max_iter, pxs[lane], py);
            }
            result
        }
    }
}

// Chaque voie s'arrête à son propre échappement ; les voies déjà échappées (ou intérieures d'office, `done`)
// continuent de calculer pour rien, éventuellement jusqu'à l'infini, mais ne sont plus jamais lues.
fn iterate4_quadratic(
    max_iter: i32,
    mut done: u32,
    mut x: f64x4,
    mut y: f64x4,
    kx: f64x4,
    ky: f64x4,
    next_y: impl Fn(f64x4, f64x4, f64x4) -> f64x4,
) -> [f32; LANES] {
    let mut result = [INSIDE; LANES];
    if done == ALL_LANES_DONE {
        return result;
    }
    let radius2 = f64x4::splat(ESCAPE_RADIUS2);
    for n in 0..max_iter {
        let x2 = x * x;
        let y2 = y * y;
        let modulus2 = x2 + y2;
        let escaped = (modulus2.cmp_gt(radius2).move_mask() as u32) & !done;
        if escaped != 0 {
            let values = modulus2.to_array();
            for lane in 0..LANES {
                if escaped & (1 << lane) != 0 {
                    result[lane] = smooth_value(n, values[lane], LN_2);
                }
            }
            done |= escaped;
            if done == ALL_LANES_DONE {
                break;
            }
        }
        y = next_y(x, y, ky);
        x = x2 - y2 + kx;
    }
    result
}

// ---------------------------------------------------------------------------------------------------------------

fn compute_row(formula: Formula, max_iter: i32, x0: f64, dx: f64, y: f64, is_simd: bool, out: &mut [f32]) {
    let pixel_x = |i: usize| x0 + i as f64 * dx;
    let mut i = 0;
    if is_simd && formula.is_vectorizable() {
        while i + LANES <= out.len() {
            let pxs = [pixel_x(i), pixel_x(i + 1), pixel_x(i + 2), pixel_x(i + 3)];
            out[i..i + LANES].copy_from_slice(&iterate4(formula, max_iter, pxs, y));
            i += LANES;
        }
    }
    // reste de la ligne (count non multiple de 4) et formules non vectorisables
    while i < out.len() {
        out[i] = iterate(formula, max_iter, pixel_x(i), y);
        i += 1;
    }
}

#[no_mangle]
pub extern "C" fn fk_abi_version() -> u32 {
    ABI_VERSION
}

/// # Safety
/// `params` désigne `param_count` f64 lisibles et `out` désigne `count` f32 modifiables.
#[no_mangle]
pub unsafe extern "C" fn fk_compute_row(
    formula: i32,
    params: *const f64,
    param_count: i32,
    max_iter: i32,
    x0: f64,
    dx: f64,
    y: f64,
    count: i32,
    out: *mut f32,
) -> i32 {
    // aucune panique ne doit traverser la frontière avec Delphi
    let result = catch_unwind(AssertUnwindSafe(|| {
        if param_count < 0 || max_iter < 0 || count < 0 || out.is_null() || (param_count > 0 && params.is_null()) {
            return FK_INVALID_ARGUMENT;
        }
        let params: &[f64] = if param_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(params, param_count as usize)
        };
        let formula = match Formula::from_id(formula, params) {
            Ok(formula) => formula,
            Err(code) => return code,
        };
        let out = std::slice::from_raw_parts_mut(out, count as usize);
        compute_row(formula, max_iter, x0, dx, y, true, out);
        FK_OK
    }));
    result.unwrap_or(FK_INTERNAL_ERROR)
}

#[cfg(test)]
mod tests {
    use super::*;

    const MANDELBROT: i32 = 0;
    const MULTIBROT: i32 = 1;
    const JULIA: i32 = 2;
    const BURNING_SHIP: i32 = 3;
    const TRICORN: i32 = 4;
    const MAX_ITER: i32 = 500;
    const NOT_WRITTEN: f32 = -2.0;
    const ROW_LENGTH: usize = 1000;

    fn call(formula: i32, params: &[f64], x0: f64, dx: f64, y: f64, count: usize) -> (i32, Vec<f32>) {
        let mut out = vec![NOT_WRITTEN; count];
        let code = unsafe {
            fk_compute_row(
                formula,
                params.as_ptr(),
                params.len() as i32,
                MAX_ITER,
                x0,
                dx,
                y,
                count as i32,
                out.as_mut_ptr(),
            )
        };
        (code, out)
    }

    fn point(formula: i32, params: &[f64], x: f64, y: f64) -> f32 {
        let (code, out) = call(formula, params, x, 0.0, y, 1);
        assert_eq!(code, FK_OK);
        out[0]
    }

    #[test]
    fn abi_version_is_1() {
        assert_eq!(fk_abi_version(), 1);
    }

    #[test]
    fn known_points() {
        assert_eq!(point(MANDELBROT, &[], 0.0, 0.0), INSIDE);
        assert_eq!(point(MANDELBROT, &[], -1.3107, 0.0), INSIDE); // bulbe de période 4 : aucun raccourci
        assert!(point(MANDELBROT, &[], 2.0, 2.0) >= 0.0);
        assert_eq!(point(BURNING_SHIP, &[], 0.0, 0.0), INSIDE);
        assert!(point(BURNING_SHIP, &[], 2.0, 2.0) >= 0.0);
        assert_eq!(point(TRICORN, &[], 0.0, 0.0), INSIDE);
        assert!(point(TRICORN, &[], 2.0, 2.0) >= 0.0);
        assert_eq!(point(JULIA, &[0.0, 0.0], 0.5, 0.0), INSIDE);
        assert!(point(JULIA, &[0.0, 0.0], 1.5, 0.0) >= 0.0);
        assert_eq!(point(MULTIBROT, &[3.0], 0.0, 0.0), INSIDE);
        assert!(point(MULTIBROT, &[3.0], 2.0, 2.0) >= 0.0);
    }

    #[test]
    fn multibrot_power_2_matches_mandelbrot() {
        let samples = [(0.0, 0.0), (-0.1, 0.1), (-1.3107, 0.0), (2.0, 2.0), (0.5, 0.5), (-2.5, 0.3)];
        for &(x, y) in &samples {
            let m = point(MANDELBROT, &[], x, y);
            let b = point(MULTIBROT, &[2.0], x, y);
            assert_eq!(m < 0.0, b < 0.0, "verdict différent en ({}, {})", x, y);
            if m >= 0.0 {
                assert!((m - b).abs() < 1e-3, "({}, {}) : {} contre {}", x, y, m, b);
            }
        }
    }

    #[test]
    fn simd_matches_scalar_exactly() {
        let dx = 3.5 / ROW_LENGTH as f64;
        let cases = [
            (Formula::Mandelbrot, -2.0, 0.3),
            (Formula::Julia { cx: -0.8, cy: 0.156 }, -1.75, 0.2),
            (Formula::BurningShip, -2.0, -0.5),
            (Formula::Tricorn, -2.0, 0.4),
        ];
        for &(formula, x0, y) in &cases {
            let mut simd = vec![NOT_WRITTEN; ROW_LENGTH];
            let mut scalar = vec![NOT_WRITTEN; ROW_LENGTH];
            compute_row(formula, MAX_ITER, x0, dx, y, true, &mut simd);
            compute_row(formula, MAX_ITER, x0, dx, y, false, &mut scalar);
            let inside = scalar.iter().filter(|v| **v < 0.0).count();
            assert!(inside > 0 && inside < ROW_LENGTH, "{:?} : la ligne doit mêler intérieur et extérieur", formula);
            for i in 0..ROW_LENGTH {
                assert_eq!(simd[i].to_bits(), scalar[i].to_bits(), "{:?}, pixel {}", formula, i);
            }
        }
    }

    #[test]
    fn count_not_multiple_of_4() {
        let (x0, dx, y) = (-2.0, 0.5, 0.0);
        let (code, out) = call(MANDELBROT, &[], x0, dx, y, 7);
        assert_eq!(code, FK_OK);
        for (i, value) in out.iter().enumerate() {
            let expected = iterate(Formula::Mandelbrot, MAX_ITER, x0 + i as f64 * dx, y);
            assert_eq!(value.to_bits(), expected.to_bits(), "pixel {}", i);
        }
    }

    #[test]
    fn error_codes() {
        assert_eq!(call(99, &[], 0.0, 0.01, 0.0, 4).0, FK_UNKNOWN_FORMULA);
        assert_eq!(call(MANDELBROT, &[1.0], 0.0, 0.01, 0.0, 4).0, FK_BAD_PARAM_COUNT);
        assert_eq!(call(JULIA, &[0.0], 0.0, 0.01, 0.0, 4).0, FK_BAD_PARAM_COUNT);
        assert_eq!(call(MULTIBROT, &[-1.0], 0.0, 0.01, 0.0, 4).0, FK_INVALID_ARGUMENT);
        let mut out = [NOT_WRITTEN; 4];
        unsafe {
            let null_out = std::ptr::null_mut();
            assert_eq!(fk_compute_row(MANDELBROT, std::ptr::null(), 0, MAX_ITER, 0.0, 0.01, 0.0, 4, null_out), 3);
            assert_eq!(fk_compute_row(MANDELBROT, std::ptr::null(), 0, -1, 0.0, 0.01, 0.0, 4, out.as_mut_ptr()), 3);
            assert_eq!(fk_compute_row(MANDELBROT, std::ptr::null(), 0, MAX_ITER, 0.0, 0.01, 0.0, -1, out.as_mut_ptr()), 3);
            assert_eq!(fk_compute_row(JULIA, std::ptr::null(), 2, MAX_ITER, 0.0, 0.01, 0.0, 4, out.as_mut_ptr()), 3);
            assert_eq!(fk_compute_row(MANDELBROT, std::ptr::null(), 0, MAX_ITER, 0.0, 0.01, 0.0, 0, out.as_mut_ptr()), 0);
        }
        assert!(out.iter().all(|v| *v == NOT_WRITTEN), "aucun pixel ne doit être écrit en cas d'erreur");
    }
}
```

Note : les quelques lignes de `error_codes` qui dépassent 120 caractères sont acceptées telles quelles
(`rustfmt` n'est pas imposé) ; si l'implémenteur préfère, il peut introduire une variable `p = out.as_mut_ptr()`.

- [ ] **Step 4: Écrire `kernel-rust/README.md`**

```markdown
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
```

- [ ] **Step 5: `.gitignore`** — ajouter la ligne `kernel-rust/target/` sous `bench-rust/target/`, puis
  `unix2dos -q .gitignore` seulement si le fichier était déjà en CRLF (`git ls-files --eol .gitignore`).

- [ ] **Step 6: Commit**

```bash
git add kernel-rust .gitignore
git commit -m "DLL Rust du moteur de calcul (kernel-rust)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7 (chez JF) : vérification** — JF lance `cargo test` (attendu : 6 tests réussis) puis
  `cargo build --release --target i686-pc-windows-msvc`, et copie la DLL dans `bin\`. Le résultat est consigné
  au ledger ; un échec de compilation est corrigé dans une tâche de correction, sans bloquer les tâches 2 à 7
  (elles s'appuient sur la DLL factice).

---

### Task 2: Epsilon de précision par noyau (vue et navigateur)

**Files:**
- Modify: `src/Fractal.Types.pas`
- Modify: `src/Fractal.Navigation.pas`
- Test: `tests/TestFractalTypes.pas`, `tests/TestFractalNavigation.pas`

**Interfaces:**
- Produces: constantes `kExtendedEpsilon`, `kDoubleEpsilon` (interface de `Fractal.Types`) ;
  `function TViewport.PrecisionState(Epsilon: TFloat = kExtendedEpsilon): TPrecisionState;` ;
  `property TNavigator.Epsilon: TFloat` (défaut `kExtendedEpsilon`).

- [ ] **Step 1: Tests qui échouent**

Dans `tests/TestFractalTypes.pas`, déclarer `procedure TestPrecisionStateWithDoubleEpsilon;` sous
`TestPrecisionState` et ajouter, sous la routine `TestPrecisionState` :

```pascal
procedure TTestViewport.TestPrecisionStateWithDoubleEpsilon;
begin
  // moteur Rust (Double) : limite par pixel 64 × 2^-52 ≈ 1,4e-14, avertissement en dessous de 1,1e-13
  CheckEquals(Ord(psOk), Ord(MakeViewport(0.5, 0, 1e-10, 400, 300).PrecisionState(kDoubleEpsilon)));
  CheckEquals(Ord(psWarning), Ord(MakeViewport(0.5, 0, 4e-11, 400, 300).PrecisionState(kDoubleEpsilon)));
  CheckEquals(Ord(psLimit), Ord(MakeViewport(0.5, 0, 1e-12, 400, 300).PrecisionState(kDoubleEpsilon)));
  CheckEquals(Ord(psOk), Ord(MakeViewport(0.5, 0, 1e-12, 400, 300).PrecisionState));
end;
```

Dans `tests/TestFractalNavigation.pas`, déclarer `procedure TestDoubleEpsilonBlocksZoomEarlier;` sous
`TestPrecisionLimitBlocksZoom`, et ajouter sous la routine `TestPrecisionLimitBlocksZoom` :

```pascal
procedure TTestNavigator.TestDoubleEpsilonBlocksZoomEarlier;
begin
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-9, 400, 300));
  FNavigator.ZoomCenter(1000);
  CheckFalse(FIsLimitHit, 'Extended : zoom accepté');
  FNavigator.Reset(MakeViewport(0.5, 0, 1e-9, 400, 300));
  FNavigator.Epsilon := kDoubleEpsilon;
  FNavigator.ZoomCenter(1000);
  CheckTrue(FIsLimitHit, 'Double : zoom bloqué');
  CheckEquals(1e-9, FNavigator.Viewport.Width, 1e-21);
end;
```

- [ ] **Step 2: Vérifier l'échec** — `./build.sh tests` : erreur de compilation (`kDoubleEpsilon` inconnu).

- [ ] **Step 3: `Fractal.Types`**

Dans l'interface, **avant** le bloc `type`, ajouter :

```pascal
const
  kExtendedEpsilon = 1.0842021724855044e-19;  // 2^-63 : un ulp relatif en Extended (moteur Delphi)
  kDoubleEpsilon = 2.2204460492503131e-16;    // 2^-52 : un ulp relatif en Double (moteur Rust)

```

Supprimer la ligne `kExtendedEpsilon = …` du bloc `const` de l'implémentation. Remplacer la déclaration
`function PrecisionState: TPrecisionState;` par :

```pascal
    function PrecisionState(Epsilon: TFloat = kExtendedEpsilon): TPrecisionState;
```

et l'implémentation par :

```pascal
function TViewport.PrecisionState(Epsilon: TFloat): TPrecisionState;
var
  MinSize: TFloat;
begin
  MinSize := kLimitUlps * Epsilon * Max(1.0, Max(Abs(CenterX), Abs(CenterY)));
  if PixelSize < MinSize then
    Result := psLimit
  else if PixelSize < MinSize * kWarningFactor then
    Result := psWarning
  else
    Result := psOk;
end;
```

- [ ] **Step 4: `Fractal.Navigation`**

Dans `TNavigator` : champ privé `FEpsilon: TFloat;` (sous `FViewport`), propriété publique
`property Epsilon: TFloat read FEpsilon write FEpsilon;` (sous `property Mode`), avec le commentaire
`// ulp relatif du noyau de calcul courant : fixe la limite de zoom` au-dessus. Dans `TNavigator.Create`, ajouter
`FEpsilon := kExtendedEpsilon;` après `FViewport := …`. Dans `TryCommit`, remplacer `V.PrecisionState` par
`V.PrecisionState(FEpsilon)`.

- [ ] **Step 5: Vérifier** — `./build.sh tests` : OK, nouveaux tests compris.

- [ ] **Step 6: Commit**

```bash
git add src/Fractal.Types.pas src/Fractal.Navigation.pas tests/TestFractalTypes.pas tests/TestFractalNavigation.pas
git commit -m "Limite de précision selon le noyau (Extended ou Double)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Identifiants de formule, chargeur de DLL et DLL factice

**Files:**
- Modify: `src/Fractal.Formulas.pas`
- Create: `src/Fractal.RustKernel.pas`
- Create: `tests/FakeKernel.dpr`
- Create: `tests/TestFractalRustKernel.pas`
- Modify: `tests/TestFractalFormulas.pas`, `tests/FractalesTests.dpr`, `build.sh`, `Fractales.dpr`,
  `bench/FractalesBench.dpr`

**Interfaces:**
- Consumes: rien des tâches précédentes.
- Produces :
  - `Fractal.Formulas` : constantes `kKernelNone = -1`, `kKernelMandelbrot = 0`, `kKernelMultibrot = 1`,
    `kKernelJulia = 2`, `kKernelBurningShip = 3`, `kKernelTricorn = 4` ;
    `class function TFractalFormula.KernelId: Integer; virtual;`.
  - `Fractal.RustKernel` : `ERustKernelError = class(Exception)` ;
    `TRustKernel.Create(const AFileName: string)` (ne lève jamais) ; `function IsAvailable: Boolean` ;
    `property Status: string` ;
    `procedure ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer; Output: System.PSingle)`
    (lève `ERustKernelError`) ; `function DefaultRustKernel: TRustKernel` ;
    `function IsRustKernelAvailable: Boolean` ; `function RustKernelStatus: string` ;
    constante `kRustKernelFileName = 'fractal_kernel.dll'`.
  - Tests : `bin\FakeKernel.dll` ; dans `TestFractalRustKernel`, la classe `TUnknownKernelFormula` et les
    fonctions `FakeKernelFileName`, `TestBinFolder` (réutilisées en tâche 4).

- [ ] **Step 1: Tests qui échouent**

Dans `tests/TestFractalFormulas.pas`, déclarer `procedure TestKernelIds;` sous `TestRegistry` et ajouter sous la
routine `TestRegistry` :

```pascal
procedure TTestFormulas.TestKernelIds;
var
  I, J: Integer;
begin
  CheckEquals(kKernelMandelbrot, TMandelbrotFormula.KernelId);
  CheckEquals(kKernelMultibrot, TMultibrotFormula.KernelId);
  CheckEquals(kKernelJulia, TJuliaFormula.KernelId);
  CheckEquals(kKernelBurningShip, TBurningShipFormula.KernelId);
  CheckEquals(kKernelTricorn, TTricornFormula.KernelId);
  for I := 0 to FormulaClassCount - 1 do
    for J := I + 1 to FormulaClassCount - 1 do
      CheckTrue(FormulaClassAt(I).KernelId <> FormulaClassAt(J).KernelId, 'identifiants en double');
end;
```

Créer `tests/TestFractalRustKernel.pas` :

```pascal
unit TestFractalRustKernel;

interface

uses
  Windows, Classes, SysUtils, TestFramework, Fractal.Types, Fractal.Formulas, Fractal.RustKernel, TestUtils;

type
  // formule sans équivalent dans la DLL : la DLL doit répondre « formule inconnue »
  TUnknownKernelFormula = class(TMandelbrotFormula)
  public
    class function KernelId: Integer; override;
  end;

  TTestRustKernel = class(TTestCase)
  published
    procedure TestMissingFileIsUnavailable;
    procedure TestBadFormatFileIsUnavailable;
    procedure TestDllWithoutExportsIsUnavailable;
    procedure TestFakeKernelComputesRow;
    procedure TestKernelErrorRaises;
    procedure TestUnavailableKernelRaises;
    procedure TestDefaultKernelIsShared;
  end;

function TestBinFolder: string;
function FakeKernelFileName: string;

implementation

const
  kFakeKernelFile = 'FakeKernel.dll';
  kUnknownKernelId = 42;
  kRowCount = 5;
  kRowX0 = -2.5;
  kRowDX = 0.5;

//SEP

function TestBinFolder: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

//SEP

function FakeKernelFileName: string;
begin
  Result := TestBinFolder + kFakeKernelFile;
end;

//SEP

class function TUnknownKernelFormula.KernelId: Integer;
begin
  Result := kUnknownKernelId;
end;

//SEP

procedure TTestRustKernel.TestMissingFileIsUnavailable;
var
  K: TRustKernel;
begin
  K := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('introuvable', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

//SEP

procedure TTestRustKernel.TestBadFormatFileIsUnavailable;
var
  FileName: string;
  Lines: TStringList;
  K: TRustKernel;
begin
  // même erreur 193 qu'une DLL 64 bits : le message doit citer la bonne cible de compilation
  FileName := TestTempFolder + 'not_a_dll.dll';
  Lines := TStringList.Create;
  try
    Lines.Add('pas une DLL');
    Lines.SaveToFile(FileName);
  finally
    Lines.Free;
  end;
  K := TRustKernel.Create(FileName);
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('i686-pc-windows-msvc', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

//SEP

procedure TTestRustKernel.TestDllWithoutExportsIsUnavailable;
var
  SystemDir: array[0..MAX_PATH] of Char;
  K: TRustKernel;
begin
  GetSystemDirectory(SystemDir, MAX_PATH);
  K := TRustKernel.Create(IncludeTrailingPathDelimiter(SystemDir) + 'version.dll');
  try
    CheckFalse(K.IsAvailable);
    CheckTrue(Pos('fk_', K.Status) > 0, K.Status);
  finally
    K.Free;
  end;
end;

//SEP

procedure TTestRustKernel.TestFakeKernelComputesRow;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..kRowCount - 1] of Single;
  I: Integer;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TMandelbrotFormula.Create;
  try
    CheckTrue(K.IsAvailable, K.Status);
    K.ComputeRow(F, kRowX0, kRowDX, 0, kRowCount, @Values[0]);
    for I := 0 to kRowCount - 1 do
      CheckEquals(F.Iterate(kRowX0 + I * kRowDX, 0), Values[I], 0, Format('pixel %d', [I]));
    CheckEquals(kInside, Values[kRowCount - 1], 0);  // x = -0,5 : cardioïde
  finally
    F.Free;
    K.Free;
  end;
end;

//SEP

procedure TTestRustKernel.TestKernelErrorRaises;
var
  K: TRustKernel;
  F: TUnknownKernelFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(FakeKernelFileName);
  F := TUnknownKernelFormula.Create;
  try
    try
      K.ComputeRow(F, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckTrue(Pos('(code 1)', E.Message) > 0, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

//SEP

procedure TTestRustKernel.TestUnavailableKernelRaises;
var
  K: TRustKernel;
  F: TMandelbrotFormula;
  Values: array[0..0] of Single;
begin
  K := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
  F := TMandelbrotFormula.Create;
  try
    try
      K.ComputeRow(F, 0, kRowDX, 0, 1, @Values[0]);
      Fail('ERustKernelError attendue');
    except
      on E: ERustKernelError do
        CheckEquals(K.Status, E.Message);
    end;
  finally
    F.Free;
    K.Free;
  end;
end;

//SEP

procedure TTestRustKernel.TestDefaultKernelIsShared;
begin
  CheckSame(DefaultRustKernel, DefaultRustKernel);
  CheckEquals(DefaultRustKernel.IsAvailable, IsRustKernelAvailable);
  CheckEquals(DefaultRustKernel.Status, RustKernelStatus);
end;

initialization
  RegisterTest(TTestRustKernel.Suite);

end.
```

Dans `tests/FractalesTests.dpr`, ajouter `Fractal.RustKernel in '..\src\Fractal.RustKernel.pas',` après la ligne
`Fractal.Formulas` et `TestFractalRustKernel in 'TestFractalRustKernel.pas'` en dernier (remplacer le `;` de
`TestFractalHiRes` par `,`).

- [ ] **Step 2: Vérifier l'échec** — `./build.sh tests` : erreur de compilation (`KernelId`, unité
  `Fractal.RustKernel` introuvable).

- [ ] **Step 3: `Fractal.Formulas`**

Dans l'interface, à la fin du bloc `const` (après `kDefaultMaxIter`), ajouter :

```pascal
  // identifiants des formules dans la DLL Rust (fk_compute_row)
  kKernelNone = -1;
  kKernelMandelbrot = 0;
  kKernelMultibrot = 1;
  kKernelJulia = 2;
  kKernelBurningShip = 3;
  kKernelTricorn = 4;
```

Déclarer `class function KernelId: Integer; virtual;` dans `TFractalFormula` sous `DefaultWidth`, et
`class function KernelId: Integer; override;` dans chacune des cinq formules, sous `DisplayName` (ou sous la
dernière méthode `Default…` déclarée). Implémentations, chacune insérée **après** la dernière routine `class
function` existante de la classe concernée (avec son séparateur) :

```pascal
class function TFractalFormula.KernelId: Integer;
begin
  Result := kKernelNone;  // pas d'équivalent dans la DLL Rust : le moteur Delphi calcule
end;
```

```pascal
class function TMandelbrotFormula.KernelId: Integer;
begin
  Result := kKernelMandelbrot;
end;
```

```pascal
class function TMultibrotFormula.KernelId: Integer;
begin
  Result := kKernelMultibrot;
end;
```

```pascal
class function TJuliaFormula.KernelId: Integer;
begin
  Result := kKernelJulia;
end;
```

```pascal
class function TBurningShipFormula.KernelId: Integer;
begin
  Result := kKernelBurningShip;
end;
```

```pascal
class function TTricornFormula.KernelId: Integer;
begin
  Result := kKernelTricorn;
end;
```

- [ ] **Step 4: Créer `src/Fractal.RustKernel.pas`**

```pascal
unit Fractal.RustKernel;

// Chargement et appel de la DLL de calcul Rust (kernel-rust\, fractal_kernel.dll). Unité sans VCL.

interface

uses
  Windows, SysUtils, SyncObjs, Fractal.Formulas;

const
  kRustKernelFileName = 'fractal_kernel.dll';
  kRustAbiVersion = 1;
  kMaxKernelParams = 8;
  // codes de retour de fk_compute_row
  kRustOk = 0;
  kRustUnknownFormula = 1;
  kRustBadParamCount = 2;
  kRustInvalidArgument = 3;
  kRustInternalError = 4;

type
  ERustKernelError = class(Exception);

  TRustAbiVersionFunc = function: Cardinal; cdecl;
  TRustComputeRowFunc = function(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer;
    X0, DX, Y: Double; Count: Integer; Output: System.PSingle): Integer; cdecl;

  // Une DLL de calcul chargée. Elle n'a aucun état : plusieurs threads peuvent appeler ComputeRow à la fois.
  TRustKernel = class
  private
    FHandle: HMODULE;
    FComputeRow: TRustComputeRowFunc;
    FStatus: string;
    function FindExport(const Name: AnsiString): Pointer;
    procedure Unload(const Reason: string);
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function IsAvailable: Boolean;
    procedure ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer; Output: System.PSingle);
    property Status: string read FStatus;
  end;

function DefaultRustKernel: TRustKernel;
function IsRustKernelAvailable: Boolean;
function RustKernelStatus: string;

implementation

var
  KernelLock: TCriticalSection;
  DefaultKernel: TRustKernel;

//SEP

function RustErrorText(Code: Integer): string;
begin
  case Code of
    kRustUnknownFormula:
      Result := 'formule inconnue';
    kRustBadParamCount:
      Result := 'nombre de paramètres incorrect';
    kRustInvalidArgument:
      Result := 'argument invalide';
    kRustInternalError:
      Result := 'erreur interne';
  else
    Result := 'erreur inattendue';
  end;
  Result := Format('Moteur Rust : %s (code %d).', [Result, Code]);
end;

//SEP

constructor TRustKernel.Create(const AFileName: string);
var
  AbiVersion: TRustAbiVersionFunc;
  Version: Cardinal;
  ErrorCode: Cardinal;
begin
  inherited Create;
  if not FileExists(AFileName) then
  begin
    FStatus := Format('Moteur Rust absent : %s introuvable.', [ExtractFileName(AFileName)]);
    Exit;
  end;
  FHandle := LoadLibrary(PChar(AFileName));
  if FHandle = 0 then
  begin
    ErrorCode := GetLastError;
    FStatus := Format('Moteur Rust : chargement de %s impossible (%s).',
      [ExtractFileName(AFileName), SysErrorMessage(ErrorCode)]);
    if ErrorCode = ERROR_BAD_EXE_FORMAT then
      FStatus := FStatus + ' DLL 64 bits ? Compilez-la avec --target i686-pc-windows-msvc.';
    Exit;
  end;
  AbiVersion := FindExport('fk_abi_version');
  FComputeRow := FindExport('fk_compute_row');
  if not Assigned(AbiVersion) or not Assigned(FComputeRow) then
  begin
    Unload(Format('Moteur Rust : %s ne contient pas fk_abi_version et fk_compute_row.',
      [ExtractFileName(AFileName)]));
    Exit;
  end;
  Version := AbiVersion;
  if Version <> kRustAbiVersion then
  begin
    Unload(Format('Moteur Rust : %s est en version %d, version %d attendue.',
      [ExtractFileName(AFileName), Version, kRustAbiVersion]));
    Exit;
  end;
  FStatus := 'Moteur Rust disponible.';
end;

//SEP

destructor TRustKernel.Destroy;
begin
  if FHandle <> 0 then
    FreeLibrary(FHandle);
  inherited Destroy;
end;

//SEP

function TRustKernel.FindExport(const Name: AnsiString): Pointer;
begin
  // cdecl 32 bits : le nom peut être exporté avec ou sans le préfixe « _ » selon l'éditeur de liens
  Result := GetProcAddress(FHandle, PAnsiChar(Name));
  if Result = nil then
    Result := GetProcAddress(FHandle, PAnsiChar('_' + Name));
end;

//SEP

procedure TRustKernel.Unload(const Reason: string);
begin
  FreeLibrary(FHandle);
  FHandle := 0;
  FComputeRow := nil;
  FStatus := Reason;
end;

//SEP

function TRustKernel.IsAvailable: Boolean;
begin
  Result := FHandle <> 0;
end;

//SEP

procedure TRustKernel.ComputeRow(Formula: TFractalFormula; X0, DX, Y: Double; Count: Integer;
  Output: System.PSingle);
var
  Params: array[0..kMaxKernelParams - 1] of Double;
  I, Code: Integer;
begin
  if not IsAvailable then
    raise ERustKernelError.Create(FStatus);
  if Formula.ParamCount > kMaxKernelParams then
    raise ERustKernelError.CreateFmt('Moteur Rust : trop de paramètres pour %s.', [Formula.FormulaName]);
  for I := 0 to Formula.ParamCount - 1 do
    Params[I] := Formula.GetParam(I);
  Code := FComputeRow(Formula.KernelId, @Params[0], Formula.ParamCount, Formula.MaxIter, X0, DX, Y, Count, Output);
  if Code <> kRustOk then
    raise ERustKernelError.Create(RustErrorText(Code));
end;

//SEP

function DefaultRustKernel: TRustKernel;
begin
  // chargée au premier usage, une seule fois, à côté de l'exécutable
  KernelLock.Enter;
  try
    if DefaultKernel = nil then
      DefaultKernel := TRustKernel.Create(ExtractFilePath(ParamStr(0)) + kRustKernelFileName);
    Result := DefaultKernel;
  finally
    KernelLock.Leave;
  end;
end;

//SEP

function IsRustKernelAvailable: Boolean;
begin
  Result := DefaultRustKernel.IsAvailable;
end;

//SEP

function RustKernelStatus: string;
begin
  Result := DefaultRustKernel.Status;
end;

initialization
  KernelLock := TCriticalSection.Create;

finalization
  FreeAndNil(DefaultKernel);
  FreeAndNil(KernelLock);

end.
```

Note D2010 : affecter un `Pointer` à une variable de type procédural (`AbiVersion := FindExport(...)`) compile
sans transtypage. Si le compilateur le refuse, écrire `@AbiVersion := FindExport(...)` (idem `@FComputeRow`).
`Version := AbiVersion;` appelle la fonction (pas de `()` nécessaire en Pascal, mais `AbiVersion()` est accepté).

- [ ] **Step 5: Créer `tests/FakeKernel.dpr`**

```pascal
library FakeKernel;

// DLL de substitution pour les tests : mêmes exports que la DLL Rust (kernel-rust), mais calculée par
// Fractal.Formulas. Elle permet de vérifier le chargement et le moteur en mode Rust sur une machine sans Rust.

uses
  SysUtils,
  Fractal.Types in '..\src\Fractal.Types.pas',
  Fractal.Formulas in '..\src\Fractal.Formulas.pas';

const
  kAbiVersion = 1;
  kOk = 0;
  kUnknownFormula = 1;
  kBadParamCount = 2;
  kInvalidArgument = 3;
  kInternalError = 4;

//SEP

function fk_abi_version: Cardinal; cdecl;
begin
  Result := kAbiVersion;
end;

//SEP

function fk_compute_row(Formula: Integer; Params: PDouble; ParamCount, MaxIter: Integer; X0, DX, Y: Double;
  Count: Integer; Output: PSingle): Integer; cdecl;
var
  FormulaClass: TFractalFormulaClass;
  F: TFractalFormula;
  I: Integer;
begin
  if (ParamCount < 0) or (MaxIter < 0) or (Count < 0) or (Output = nil) or ((ParamCount > 0) and (Params = nil)) then
    Exit(kInvalidArgument);
  FormulaClass := nil;
  for I := 0 to FormulaClassCount - 1 do
    if FormulaClassAt(I).KernelId = Formula then
      FormulaClass := FormulaClassAt(I);
  if FormulaClass = nil then
    Exit(kUnknownFormula);
  try
    F := FormulaClass.Create;
    try
      if ParamCount <> F.ParamCount then
        Exit(kBadParamCount);
      for I := 0 to ParamCount - 1 do
      begin
        F.SetParam(I, Params^);
        Inc(Params);
      end;
      F.MaxIter := MaxIter;
      for I := 0 to Count - 1 do
      begin
        Output^ := F.Iterate(X0 + I * DX, Y);
        Inc(Output);
      end;
      Result := kOk;
    finally
      F.Free;
    end;
  except
    Result := kInternalError;
  end;
end;

exports
  fk_abi_version,
  fk_compute_row;

begin
end.
```

- [ ] **Step 6: `build.sh`** — dans la branche `tests)`, compiler la DLL factice avant les tests :

```sh
  tests)
    (cd tests && "$DCC" -B -Q -N0../dcu -E../bin FakeKernel.dpr)
    (cd tests && "$DCC" -B -Q -N0../dcu -E../bin -U"$BDS\source\dUnit\src" FractalesTests.dpr)
    ./bin/FractalesTests.exe ;;
```

- [ ] **Step 7: `.dpr` de l'application et du banc** — ajouter `Fractal.RustKernel in 'src\Fractal.RustKernel.pas',`
  après la ligne `Fractal.Formulas` dans `Fractales.dpr`, et
  `Fractal.RustKernel in '..\src\Fractal.RustKernel.pas',` après `Fractal.Formulas` dans
  `bench/FractalesBench.dpr`.

- [ ] **Step 8: Normaliser** — séparateurs (`sed`) puis `tools/normalize.sh` sur les trois fichiers créés ;
  `tools/normalize.sh` sur les fichiers modifiés (sans effet s'ils sont déjà conformes).

- [ ] **Step 9: Vérifier** — `./build.sh tests` : OK (la DLL factice est produite dans `bin\FakeKernel.dll`) ;
  `./build.sh app` et `./build.sh bench` compilent sans avertissement.

- [ ] **Step 10: Commit**

```bash
git add src/Fractal.Formulas.pas src/Fractal.RustKernel.pas tests/FakeKernel.dpr tests/TestFractalRustKernel.pas \
  tests/TestFractalFormulas.pas tests/FractalesTests.dpr build.sh Fractales.dpr bench/FractalesBench.dpr
git commit -m "Chargeur de la DLL Rust, identifiants de formule et DLL factice de test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Moteur — noyau Delphi ou Rust

**Files:**
- Modify: `src/Fractal.Engine.pas`
- Modify: `tests/TestFractalRustKernel.pas`

**Interfaces:**
- Consumes: `TRustKernel`, `DefaultRustKernel`, `TUnknownKernelFormula`, `FakeKernelFileName`, `TestBinFolder`
  (tâche 3) ; `kExtendedEpsilon`, `kDoubleEpsilon` (tâche 2) ; `kKernelNone` (tâche 3).
- Produces :
  - `TEngineKernel = (ekDelphi, ekRust);`
  - `TRenderStatus.Kernel: TEngineKernel` (noyau réellement utilisé par le rendu courant) ;
  - `property TRenderEngine.Kernel: TEngineKernel` (noyau demandé, lu au début de chaque rendu) ;
  - `property TRenderEngine.RustKernel: TRustKernel` (non possédée ; `nil` = `DefaultRustKernel`) ;
  - `function TRenderEngine.ResolveKernel(Formula: TFractalFormula): TEngineKernel;` (noyau qui serait utilisé) ;
  - `function KernelEpsilon(Kernel: TEngineKernel): TFloat;` ;
    `function KernelDisplayName(Kernel: TEngineKernel): string;` ('Delphi' / 'Rust').

- [ ] **Step 1: Tests qui échouent** — dans `tests/TestFractalRustKernel.pas` :

Ajouter `Fractal.Buffer, Fractal.Engine` à la clause `uses` de l'interface. Déclarer, sous `TUnknownKernelFormula` :

```pascal
  // formule que la DLL ne sait pas calculer : le moteur doit retomber sur Delphi
  TNoKernelFormula = class(TMandelbrotFormula)
  public
    class function KernelId: Integer; override;
  end;

  TTestRustEngine = class(TTestCase)
  private
    FFake: TRustKernel;
    FMissing: TRustKernel;
    function RenderWith(Kernel: TEngineKernel; RustKernel: TRustKernel; Formula: TFractalFormula;
      const V: TViewport; IsProgressive: Boolean): TRenderEngine;
    procedure CheckBuffersAgree(A, B: TIterationBuffer; MinRatio: Double; const Context: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRustModeMatchesDelphiWithFakeKernel;
    procedure TestFallsBackWhenDllMissing;
    procedure TestFallsBackForFormulaWithoutKernelId;
    procedure TestKernelErrorBecomesTileError;
    procedure TestNewRenderIsQuickInRustMode;
    procedure TestKernelEpsilonAndName;
    procedure TestRealKernelMatchesDelphi;
  end;
```

Constantes à ajouter au bloc `const` de l'implémentation :

```pascal
  kWaitMs = 20000;
  kValueTolerance = 1e-3;
  kInsideTolerance = 0.001;   // ± 0,1 % de points intérieurs
  kFakeMinRatio = 0.999;      // DLL factice : seules les coordonnées arrondies en Double diffèrent
  kRealMinRatio = 0.99;       // vraie DLL : Double contre Extended, écarts possibles à la frontière
  kOddWidth = 203;            // ni multiple de 64 ni de 4 : tuiles de bord et suites courtes
  kOddHeight = 149;
  kCompareWidth = 200;
  kCompareHeight = 150;
  kHeavyMaxIter = 100000;
  kQuickRenderMs = 1000;
```

Routines à ajouter **avant** `initialization` (dans cet ordre), et `RegisterTest(TTestRustEngine.Suite);` sous
l'enregistrement existant :

```pascal
class function TNoKernelFormula.KernelId: Integer;
begin
  Result := kKernelNone;
end;

//SEP

procedure TTestRustEngine.SetUp;
begin
  FFake := TRustKernel.Create(FakeKernelFileName);
  FMissing := TRustKernel.Create(TestBinFolder + 'absent_kernel.dll');
end;

//SEP

procedure TTestRustEngine.TearDown;
begin
  FreeAndNil(FMissing);
  FreeAndNil(FFake);
end;

//SEP

function TTestRustEngine.RenderWith(Kernel: TEngineKernel; RustKernel: TRustKernel; Formula: TFractalFormula;
  const V: TViewport; IsProgressive: Boolean): TRenderEngine;
begin
  Result := TRenderEngine.Create(CpuCount);
  try
    Result.Kernel := Kernel;
    Result.RustKernel := RustKernel;
    Result.Render(V, Formula, IsProgressive);
    CheckTrue(Result.WaitUntilComplete(kWaitMs), 'rendu non terminé');
    CheckTrue(Result.Status.IsComplete, 'rendu incomplet');
  except
    Result.Free;
    raise;
  end;
end;

//SEP

procedure TTestRustEngine.CheckBuffersAgree(A, B: TIterationBuffer; MinRatio: Double; const Context: string);
var
  X, Y, Matching, InsideA, InsideB, Total: Integer;
  VA, VB: Single;
begin
  CheckEquals(A.Width, B.Width, Context);
  CheckEquals(A.Height, B.Height, Context);
  Matching := 0;
  InsideA := 0;
  InsideB := 0;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
    begin
      CheckTrue(B.IsExact(X, Y), Format('%s : pixel (%d, %d) non calculé', [Context, X, Y]));
      VA := A.Value(X, Y);
      VB := B.Value(X, Y);
      if VA < 0 then
        Inc(InsideA);
      if VB < 0 then
        Inc(InsideB);
      if ((VA < 0) and (VB < 0)) or ((VA >= 0) and (VB >= 0) and (Abs(VA - VB) <= kValueTolerance)) then
        Inc(Matching);
    end;
  Total := A.Width * A.Height;
  CheckTrue(Matching >= MinRatio * Total, Format('%s : %d pixels concordants sur %d', [Context, Matching, Total]));
  CheckTrue(Abs(InsideA - InsideB) <= kInsideTolerance * Total,
    Format('%s : %d points intérieurs contre %d', [Context, InsideA, InsideB]));
end;

//SEP

procedure TTestRustEngine.TestRustModeMatchesDelphiWithFakeKernel;
var
  F: TFractalFormula;
  V: TViewport;
  ED, ER: TRenderEngine;
  I: Integer;
begin
  for I := 0 to FormulaClassCount - 1 do
  begin
    F := FormulaClassAt(I).Create;
    ED := nil;
    ER := nil;
    try
      V := MakeViewport(F.DefaultCenterX, F.DefaultCenterY, F.DefaultWidth, kOddWidth, kOddHeight);
      ED := RenderWith(ekDelphi, nil, F, V, True);
      ER := RenderWith(ekRust, FFake, F, V, True);
      CheckEquals(Ord(ekRust), Ord(ER.Status.Kernel), F.FormulaName);
      CheckEquals('', ER.TakeErrors, F.FormulaName);
      CheckBuffersAgree(ED.Buffer, ER.Buffer, kFakeMinRatio, F.FormulaName);
    finally
      ER.Free;
      ED.Free;
      F.Free;
    end;
  end;
end;

//SEP

procedure TTestRustEngine.TestFallsBackWhenDllMissing;
var
  F: TMandelbrotFormula;
  E: TRenderEngine;
begin
  F := TMandelbrotFormula.Create;
  E := nil;
  try
    E := RenderWith(ekRust, FMissing, F, MakeViewport(-0.5, 0, 3, kOddWidth, kOddHeight), True);
    CheckEquals(Ord(ekDelphi), Ord(E.Status.Kernel));
    CheckEquals(Ord(ekDelphi), Ord(E.ResolveKernel(F)));
    CheckEquals('', E.TakeErrors);
  finally
    E.Free;
    F.Free;
  end;
end;

//SEP

procedure TTestRustEngine.TestFallsBackForFormulaWithoutKernelId;
var
  F: TNoKernelFormula;
  E: TRenderEngine;
begin
  F := TNoKernelFormula.Create;
  E := nil;
  try
    E := RenderWith(ekRust, FFake, F, MakeViewport(-0.5, 0, 3, kOddWidth, kOddHeight), True);
    CheckEquals(Ord(ekDelphi), Ord(E.Status.Kernel));
    CheckEquals('', E.TakeErrors);
  finally
    E.Free;
    F.Free;
  end;
end;

//SEP

procedure TTestRustEngine.TestKernelErrorBecomesTileError;
var
  F: TUnknownKernelFormula;
  E: TRenderEngine;
begin
  F := TUnknownKernelFormula.Create;
  E := nil;
  try
    E := RenderWith(ekRust, FFake, F, MakeViewport(-0.5, 0, 3, kOddWidth, kOddHeight), True);
    CheckEquals(Ord(ekRust), Ord(E.Status.Kernel));
    CheckTrue(Pos('Moteur Rust', E.TakeErrors) > 0);
  finally
    E.Free;
    F.Free;
  end;
end;

//SEP

procedure TTestRustEngine.TestNewRenderIsQuickInRustMode;
var
  Heavy: TJuliaFormula;
  Light: TMandelbrotFormula;
  E: TRenderEngine;
  Start: Cardinal;
begin
  // Julia c = 0 : chaque pixel du disque unité coûte MaxIter itérations ; une suite en coûte jusqu'à 64 fois plus
  Heavy := TJuliaFormula.Create;
  Light := TMandelbrotFormula.Create;
  E := TRenderEngine.Create(CpuCount);
  try
    Heavy.SetParam(0, 0);
    Heavy.SetParam(1, 0);
    Heavy.MaxIter := kHeavyMaxIter;
    E.Kernel := ekRust;
    E.RustKernel := FFake;
    E.Render(MakeViewport(0, 0, 1, kCompareWidth, kCompareHeight), Heavy);
    Sleep(50);
    Start := GetTickCount;
    E.Render(MakeViewport(5, 5, 1, kCompareWidth, kCompareHeight), Light);
    CheckTrue(GetTickCount - Start < kQuickRenderMs, Format('nouveau rendu après %d ms', [GetTickCount - Start]));
    CheckTrue(E.WaitUntilComplete(kWaitMs));
    CheckTrue(E.Status.IsComplete);
  finally
    E.Free;
    Light.Free;
    Heavy.Free;
  end;
end;

//SEP

procedure TTestRustEngine.TestKernelEpsilonAndName;
begin
  CheckEquals(kExtendedEpsilon, KernelEpsilon(ekDelphi), 0);
  CheckEquals(kDoubleEpsilon, KernelEpsilon(ekRust), 0);
  CheckEquals('Delphi', KernelDisplayName(ekDelphi));
  CheckEquals('Rust', KernelDisplayName(ekRust));
end;

//SEP

procedure TTestRustEngine.TestRealKernelMatchesDelphi;
var
  RealKernel: TRustKernel;
  F: TFractalFormula;
  V: TViewport;
  ED, ER: TRenderEngine;
  I: Integer;
begin
  if not FileExists(TestBinFolder + kRustKernelFileName) then
  begin
    Status('fractal_kernel.dll absente de bin\ : comparaison avec le vrai moteur Rust ignorée.');
    Exit;
  end;
  RealKernel := TRustKernel.Create(TestBinFolder + kRustKernelFileName);
  try
    CheckTrue(RealKernel.IsAvailable, RealKernel.Status);
    for I := 0 to FormulaClassCount - 1 do
    begin
      F := FormulaClassAt(I).Create;
      ED := nil;
      ER := nil;
      try
        V := MakeViewport(F.DefaultCenterX, F.DefaultCenterY, F.DefaultWidth, kCompareWidth, kCompareHeight);
        ED := RenderWith(ekDelphi, nil, F, V, False);
        ER := RenderWith(ekRust, RealKernel, F, V, False);
        CheckEquals(Ord(ekRust), Ord(ER.Status.Kernel), F.FormulaName);
        CheckEquals('', ER.TakeErrors, F.FormulaName);
        CheckBuffersAgree(ED.Buffer, ER.Buffer, kRealMinRatio, F.FormulaName);
      finally
        ER.Free;
        ED.Free;
        F.Free;
      end;
    end;
  finally
    RealKernel.Free;
  end;
end;
```

Note : `TestKernelEpsilonAndName` compare des constantes réelles à zéro près ; si `CheckEquals` échoue à cause de
l'arrondi Extended/Double des constantes non typées (piège connu D2010), comparer avec une tolérance de
`1e-30` plutôt que de toucher aux constantes.

- [ ] **Step 2: Vérifier l'échec** — `./build.sh tests` : erreur de compilation (`TEngineKernel` inconnu).

- [ ] **Step 3: `Fractal.Engine` — interface**

`uses` : ajouter `Fractal.RustKernel` en fin de liste. Avant `TTileJob`, ajouter :

```pascal
  // noyau de calcul des pixels : Delphi (Extended, x87) ou DLL Rust (Double, SIMD)
  TEngineKernel = (ekDelphi, ekRust);

```

Dans `TRenderStatus`, ajouter le champ `Kernel: TEngineKernel;` après `IsCancelled`. Dans `TRenderEngine`, champs
privés (sous `FErrors`) :

```pascal
    FKernel: TEngineKernel;
    FActiveKernel: TEngineKernel;          // figé au début du rendu courant
    FRustKernel: TRustKernel;              // non possédé ; nil = DefaultRustKernel
    FActiveRustKernel: TRustKernel;        // figé au début du rendu courant (nil en mode Delphi)
```

Méthodes privées (sous `ProcessJob`) : `function ProcessRustJob(const Job: TTileJob): Boolean;` et
`function CurrentRustKernel: TRustKernel;`. Publiques (sous `TakeErrors`) :
`function ResolveKernel(Formula: TFractalFormula): TEngineKernel;`. Propriétés (sous `Buffer`) :

```pascal
    property Kernel: TEngineKernel read FKernel write FKernel;
    property RustKernel: TRustKernel read FRustKernel write FRustKernel;
```

Fonctions globales, sous `function CpuCount: Integer;` :

```pascal
function KernelEpsilon(Kernel: TEngineKernel): TFloat;
function KernelDisplayName(Kernel: TEngineKernel): string;
```

- [ ] **Step 4: `Fractal.Engine` — implémentation**

Sous la routine `CpuCount` (avec séparateurs) :

```pascal
function KernelEpsilon(Kernel: TEngineKernel): TFloat;
begin
  if Kernel = ekRust then
    Result := kDoubleEpsilon
  else
    Result := kExtendedEpsilon;
end;

{------------------------------------------------------------------------------}

function KernelDisplayName(Kernel: TEngineKernel): string;
begin
  if Kernel = ekRust then
    Result := 'Rust'
  else
    Result := 'Delphi';
end;
```

`StartRender` devient :

```pascal
procedure TRenderEngine.StartRender(const V: TViewport; Formula: TFractalFormula; IsProgressive, IsShift: Boolean;
  DX, DY: Integer);
var
  NewFormula: TFractalFormula;
  NewKernel: TEngineKernel;
begin
  // clonée avant l'arrêt : si le clonage échoue, le rendu courant reste intact
  NewFormula := Formula.Clone;
  NewKernel := ResolveKernel(NewFormula);
  StopCurrent;
  FLock.Enter;
  try
    FErrors.Clear;
  finally
    FLock.Leave;
  end;
  FFormula.Free;
  FFormula := NewFormula;
  FActiveKernel := NewKernel;
  if NewKernel = ekRust then
    FActiveRustKernel := CurrentRustKernel
  else
    FActiveRustKernel := nil;
  FViewport := V;
  if (FBuffer.Width <> V.PixelWidth) or (FBuffer.Height <> V.PixelHeight) then
    FBuffer.Resize(V.PixelWidth, V.PixelHeight)
  else if IsShift then
    FBuffer.Shift(DX, DY)
  else
    FBuffer.Clear;
  QueueJobs(IsProgressive);
end;
```

Dans `ProcessJob`, insérer en tête du corps (après `begin`, avant `Result := False;`) :

```pascal
  if FActiveKernel = ekRust then
    Exit(ProcessRustJob(Job));
```

Sous la routine `ProcessJob` (avec séparateurs) :

```pascal
function TRenderEngine.ProcessRustJob(const Job: TTileJob): Boolean;
var
  Values: array[0..kTileSize - 1] of Single;
  X, Y, RunStart, Count, I: Integer;
  P: TComplexPoint;
  DX: Double;
begin
  // ancres consécutives à calculer regroupées en suites : un seul appel à la DLL par suite
  Result := False;
  DX := Job.Step * FViewport.PixelSize;
  Y := Job.Y0;
  while Y < Job.Y1 do
  begin
    X := Job.X0;
    while X < Job.X1 do
    begin
      if FBuffer.IsExact(X, Y) then
      begin
        Inc(X, Job.Step);
        Continue;
      end;
      RunStart := X;
      Count := 0;
      while (X < Job.X1) and not FBuffer.IsExact(X, Y) do
      begin
        Inc(Count);
        Inc(X, Job.Step);
      end;
      if Job.Generation <> FGeneration then
        Exit;
      P := FViewport.PixelToComplex(RunStart, Y);
      FActiveRustKernel.ComputeRow(FFormula, P.X, DX, P.Y, Count, @Values[0]);
      for I := 0 to Count - 1 do
        FBuffer.WriteAnchor(RunStart + I * Job.Step, Y, Job.Step, Values[I]);
    end;
    FBuffer.MarkDirty;
    Inc(Y, Job.Step);
  end;
  Result := True;
end;
```

Sous la routine `TakeErrors` (fin de l'unité, avec séparateurs) :

```pascal
function TRenderEngine.CurrentRustKernel: TRustKernel;
begin
  if FRustKernel <> nil then
    Result := FRustKernel
  else
    Result := DefaultRustKernel;
end;

{------------------------------------------------------------------------------}

function TRenderEngine.ResolveKernel(Formula: TFractalFormula): TEngineKernel;
begin
  // la DLL par défaut n'est chargée que si le noyau Rust est demandé
  if (FKernel = ekRust) and (Formula.KernelId <> kKernelNone) and CurrentRustKernel.IsAvailable then
    Result := ekRust
  else
    Result := ekDelphi;
end;
```

Dans `TRenderEngine.Status`, ajouter `Result.Kernel := FActiveKernel;` après `Result.IsCancelled := …`.

- [ ] **Step 5: Vérifier** — `./build.sh tests` : OK. Sans `bin\fractal_kernel.dll`, la sortie console mentionne
  la comparaison ignorée. `./build.sh bench` compile et tourne.

- [ ] **Step 6: Commit**

```bash
git add src/Fractal.Engine.pas tests/TestFractalRustKernel.pas
git commit -m "Moteur : noyau Delphi ou Rust, suites de pixels envoyées à la DLL

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Rendu HD avec le noyau choisi

**Files:**
- Modify: `src/Fractal.HiRes.pas`
- Test: `tests/TestFractalHiRes.pas`

**Interfaces:**
- Consumes: `TEngineKernel`, `TRenderEngine.Kernel` (tâche 4).
- Produces: `THiResRenderer.Create(..., const ALocationText: RawByteString; AKernel: TEngineKernel = ekDelphi)`.

- [ ] **Step 1: Test qui échoue** — dans `tests/TestFractalHiRes.pas` : ajouter `Fractal.Engine` à `uses` ;
  ajouter le paramètre `AKernel: TEngineKernel = ekDelphi` à `RunRenderer` (déclaration et implémentation) et le
  transmettre : `THiResRenderer.Create(Settings, V, F, TColorMapper.Create(P, DefaultColorMapping), 'abc', AKernel)` ;
  déclarer `procedure TestRustKernelRequestRenders;` sous `TestEstimateRejectsHugeRender` et l'ajouter sous la
  routine correspondante :

```pascal
procedure TTestHiRes.TestRustKernelRequestRenders;
var
  FileName: string;
  F: TMandelbrotFormula;
  R: THiResRenderer;
  Png: TPngImage;
begin
  // avec ou sans DLL Rust (repli sur Delphi), le rendu HD doit aboutir
  FileName := TestTempFolder + 'hires-rust.png';
  F := TMandelbrotFormula.Create;
  Png := TPngImage.Create;
  try
    F.MaxIter := 200;
    R := RunRenderer(MakeSettings(64, 48, 2, FileName), MakeViewport(-0.5, 0, 3, 64, 48), F, ekRust);
    try
      R.WaitFor;
      CheckTrue(R.IsSucceeded, R.ErrorMessage);
    finally
      R.Free;
    end;
    Png.LoadFromFile(FileName);
    CheckEquals(64, Png.Width);
    CheckEquals(48, Png.Height);
  finally
    Png.Free;
    F.Free;
  end;
end;
```

- [ ] **Step 2: Vérifier l'échec** — `./build.sh tests` : erreur de compilation (trop de paramètres).

- [ ] **Step 3: `Fractal.HiRes`** — champ privé `FKernel: TEngineKernel;` sous `FLocationText` ; constructeur :

```pascal
    constructor Create(const ASettings: THiResSettings; const AViewport: TViewport; AFormula: TFractalFormula;
      AMapper: TColorMapper; const ALocationText: RawByteString; AKernel: TEngineKernel = ekDelphi);
```

(même signature, sans la valeur par défaut, dans l'implémentation), avec `FKernel := AKernel;` après
`FLocationText := ALocationText;`. Dans `RenderToStream`, après `Engine := TRenderEngine.Create(CpuCount);`,
insérer à l'intérieur du `try` (première ligne) `Engine.Kernel := FKernel;`.

- [ ] **Step 4: Vérifier** — `./build.sh tests` : OK.

- [ ] **Step 5: Commit**

```bash
git add src/Fractal.HiRes.pas tests/TestFractalHiRes.pas
git commit -m "Rendu HD : noyau de calcul transmis au moteur

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Interface — liste « Moteur », barre d'état, rendu HD, test de fumée

**Files:**
- Modify: `src/MainFrm.pas`, `src/MainFrm.dfm`, `src/HiResFrm.pas`

**Interfaces:**
- Consumes: `TEngineKernel`, `KernelEpsilon`, `KernelDisplayName`, `TRenderEngine.Kernel`, `ResolveKernel`,
  `TRenderStatus.Kernel` (tâche 4) ; `IsRustKernelAvailable`, `RustKernelStatus` (tâche 3) ;
  `TNavigator.Epsilon` (tâche 2) ; `THiResRenderer.Create(..., AKernel)` (tâche 5).
- Produces: `THiResForm.Prepare(const V: TViewport; Formula: TFractalFormula; Palette: TGradientPalette;
  const Mapping: TColorMapping; const LocationText: RawByteString; Kernel: TEngineKernel)`.

- [ ] **Step 1: `MainFrm.dfm`** — dans `pnlTop`, après l'objet `btnTogglePanel` (avant le `end` du panneau) :

```
    object lblKernel: TLabel
      Left = 880
      Top = 9
      Caption = 'Moteur :'
    end
    object cbKernel: TComboBox
      Left = 934
      Top = 5
      Width = 90
      Height = 23
      Style = csDropDownList
      ParentShowHint = False
      ShowHint = True
      TabOrder = 9
    end
```

Dans `sbStatus`, passer le quatrième panneau (`Width = 170`) à `Width = 220`.

- [ ] **Step 2: `MainFrm.pas` — déclarations**

`uses` de l'interface : ajouter `Fractal.RustKernel` après `Fractal.View`. Champs publiés : `lblKernel: TLabel;`
sous `lblNavMode`, `cbKernel: TComboBox;` sous `cbNavMode`. Méthodes privées, sous `NavigatorJuliaPoint` :

```pascal
    procedure RenderJuliaPreview;
    procedure InitKernelPanel;
    procedure KernelComboChange(Sender: TObject);
    procedure UpdateKernelEpsilon;
```

- [ ] **Step 3: `FormCreate`** — appeler `InitKernelPanel;` après `InitFilePanel;`, et après l'appel final
  `FNavigator.Reset(...)` ajouter :

```pascal
  // après Reset, qui efface le message d'état
  if not IsRustKernelAvailable then
    FStatusMessage := RustKernelStatus;
```

- [ ] **Step 4: Aperçu Julia** — `NavigatorJuliaPoint` devient :

```pascal
procedure TMainForm.NavigatorJuliaPoint(Sender: TObject; const P: TComplexPoint);
begin
  FJuliaFormula.SetParam(FJuliaFormula.IndexOfParam('cx'), P.X);
  FJuliaFormula.SetParam(FJuliaFormula.IndexOfParam('cy'), P.Y);
  RenderJuliaPreview;
end;
```

et, sous cette routine (avec séparateurs) :

```pascal
procedure TMainForm.RenderJuliaPreview;
begin
  FJuliaEngine.Render(MakeViewport(0, 0, kJuliaPreviewViewWidth, kJuliaPreviewWidth, kJuliaPreviewHeight),
    FJuliaFormula);
end;
```

- [ ] **Step 5: Liste « Moteur »** — sous la routine `NavModeChange` (avec séparateurs) :

```pascal
procedure TMainForm.InitKernelPanel;
begin
  cbKernel.Items.Add(KernelDisplayName(ekDelphi));
  cbKernel.Items.Add(KernelDisplayName(ekRust));
  cbKernel.ItemIndex := Ord(ekDelphi);
  cbKernel.OnChange := KernelComboChange;
  // la VCL ne sait pas griser une seule entrée : sans DLL, toute la liste est désactivée et reste sur Delphi
  cbKernel.Enabled := IsRustKernelAvailable;
  cbKernel.Hint := RustKernelStatus;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.KernelComboChange(Sender: TObject);
begin
  FEngine.Kernel := TEngineKernel(cbKernel.ItemIndex);
  FJuliaEngine.Kernel := FEngine.Kernel;
  UpdateKernelEpsilon;
  RenderCurrent;
  if FView.IsJuliaVisible then
    RenderJuliaPreview;
  FView.SetFocus;
end;

{------------------------------------------------------------------------------}

procedure TMainForm.UpdateKernelEpsilon;
begin
  // la limite de zoom suit le noyau réellement utilisé (une formule sans équivalent Rust reste en Delphi)
  FNavigator.Epsilon := KernelEpsilon(FEngine.ResolveKernel(FFormula));
end;
```

- [ ] **Step 6: Changement de formule** — dans `SetFormula`, après `FFormula := AFormula;`, ajouter
  `UpdateKernelEpsilon;`.

- [ ] **Step 7: Barre d'état** — dans `UpdateStatus`, remplacer les deux `SetPanelText(3, …)` et le test de
  précision par :

```pascal
  if S.IsComplete then
    SetPanelText(3, Format('%s : terminé en %d ms', [KernelDisplayName(S.Kernel), S.ElapsedMs]))
  else
    SetPanelText(3, Format('%s : passe %d/%d   %d ms', [KernelDisplayName(S.Kernel), S.CurrentPass, S.PassCount,
      S.ElapsedMs]));
  Msg := FStatusMessage;
  if V.PrecisionState(FNavigator.Epsilon) <> psOk then
    Msg := 'Limite de précision proche. ' + Msg;
```

- [ ] **Step 8: Rendu HD** — dans `PrepareHiResForm`, passer le noyau :

```pascal
    THiResForm(FHiResForm).Prepare(FNavigator.Viewport, FFormula, FPalette, FMapping, LocationAsPngText(Location),
      FEngine.ResolveKernel(FFormula));
```

Dans `HiResFrm.pas` : ajouter `Fractal.Engine` à `uses` de l'interface ; champ privé `FKernel: TEngineKernel;`
sous `FLocationText` ; ajouter le paramètre `Kernel: TEngineKernel` à `Prepare` (déclaration et implémentation)
avec `FKernel := Kernel;` après `FLocationText := LocationText;`. Dans `StartRender` :
remplacer `.PrecisionState = psLimit)` par `.PrecisionState(KernelEpsilon(FKernel)) = psLimit)` ; passer
`FLocationText, FKernel` au constructeur de `THiResRenderer` ; remplacer
`lblState.Caption := 'Rendu en cours...';` par
`lblState.Caption := Format('Rendu en cours (moteur %s)...', [KernelDisplayName(FKernel)]);`.

- [ ] **Step 9: Test de fumée** — dans `RunSmokeTest`, après `FSmokeLog.Add('Déplacement OK');` :

```pascal
      if IsRustKernelAvailable then
      begin
        cbKernel.ItemIndex := Ord(ekRust);
        KernelComboChange(nil);
        if not WaitForRender(kSmokeTimeoutMs) then
          raise Exception.Create('rendu en mode Rust non terminé');
        CheckSmokeStep('moteur Rust');
        if FEngine.Status.Kernel <> ekRust then
          raise Exception.Create('le moteur Rust n''a pas été utilisé');
        FSmokeLog.Add(Format('Moteur Rust OK : %d ms', [FEngine.Status.ElapsedMs]));
        cbKernel.ItemIndex := Ord(ekDelphi);
        KernelComboChange(nil);
      end
      else
        FSmokeLog.Add('Moteur Rust absent (ignoré) : ' + RustKernelStatus);
```

- [ ] **Step 10: Vérifier** — `./build.sh tests` : OK ; `./build.sh smoke` : code 0, journal contenant
  « Moteur Rust absent (ignoré) » (ou « Moteur Rust OK » si `bin\fractal_kernel.dll` est présente) et toutes les
  étapes existantes. Lancer `bin\Fractales.exe` : la liste « Moteur » est grisée, son info-bulle et la barre
  d'état donnent la raison ; le quatrième panneau affiche « Delphi : terminé en N ms ».

- [ ] **Step 11: Commit**

```bash
git add src/MainFrm.pas src/MainFrm.dfm src/HiResFrm.pas
git commit -m "Interface : choix du moteur Delphi ou Rust

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-10-04-moteur-rust-design.md`
- Modify: `docs/superpowers/specs/2026-10-03-rust-en-parallele.md`

- [ ] **Step 1: `README.md`** — ajouter, après la section « Utilisation », une section :

```markdown
## Moteur Rust

La liste « Moteur » de la barre d'outils choisit qui calcule les pixels : le code Delphi (Extended 80 bits) ou la
DLL Rust `fractal_kernel.dll` (Double 64 bits, SIMD SSE2), placée à côté de `Fractales.exe`. La barre d'état
indique le moteur et le temps de chaque rendu. Sans la DLL, la liste est grisée et l'application calcule en Delphi.

En Rust, la limite de zoom arrive plus tôt (pixels d'environ 1e-13 contre 1e-16) : c'est la précision du Double.
Le moteur choisi n'est pas enregistré dans les lieux.

Compiler la DLL : voir `kernel-rust\README.md`.
```

- [ ] **Step 2: Spec** — passer `Statut : spec à relire` à `Statut : approuvée` ; dans §3.2, remplacer
  `function RustComputeRow(...): Integer` par la classe `TRustKernel` (`ComputeRow` lève `ERustKernelError`) ;
  dans §3.4, préciser que le noyau est la propriété `Kernel` lue au début de chaque rendu ; dans §4, remplacer
  « l'entrée Rust est désactivée » par « la liste est désactivée (la VCL ne grise pas une entrée seule) » ;
  dans §5, ajouter la DLL factice `tests\FakeKernel.dpr`.

- [ ] **Step 3: Note Rust** — dans `2026-10-03-rust-en-parallele.md`, §7, ajouter sous le tableau existant une
  seconde mesure en mode release, même machine (2026-10-04) :

| Scène | Rust scalaire 1T | Rust SIMD 1T | Rust scalaire 4T | Rust SIMD 4T |
|---|---|---|---|---|
| Vue d'ensemble | 410,8 ms | 221,9 ms | 104,6 ms | 57,3 ms |
| Vue profonde | 10 748,4 ms | 4 196,5 ms | 2 936,0 ms | 1 243,3 ms |

  avec une phrase : les écarts avec la première mesure (≈ 10 à 20 %) donnent l'ordre de grandeur du bruit de
  mesure sur cette machine ; les rapports Delphi/Rust restent les mêmes.

- [ ] **Step 4: Normaliser et commit**

```bash
tools/normalize.sh README.md docs/superpowers/specs/2026-10-04-moteur-rust-design.md \
  docs/superpowers/specs/2026-10-03-rust-en-parallele.md
git add README.md docs/superpowers/specs
git commit -m "Documentation du moteur Rust

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Après l'exécution (chez JF)

1. Compiler la DLL (`kernel-rust\README.md`) et la copier dans `bin\`.
2. Ici : `./build.sh tests` — `TestRealKernelMatchesDelphi` compare alors vraiment les deux moteurs ;
   `./build.sh smoke` — le journal doit dire « Moteur Rust OK ».
3. Dans l'application : basculer Delphi / Rust sur les mêmes vues et comparer les temps de la barre d'état.
