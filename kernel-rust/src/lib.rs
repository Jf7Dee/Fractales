// Noyau de calcul des fractales pour l'application Delphi (src\Fractal.RustKernel.pas).
// Mêmes algorithmes que src\Fractal.Formulas.pas, en f64 (64 bits) au lieu de l'Extended 80 bits de Delphi.
//
// Interface C (convention cdecl en 32 bits) :
//   fk_abi_version() -> u32
//   fk_compute_row(formula, params, param_count, max_iter, x0, dx, y, count, out) -> i32
// Calcule `count` pixels de la ligne d'ordonnée y, d'abscisses x0 + i·dx ; out[i] reçoit la valeur lissée,
// ou -1 pour un point intérieur.
//   fk_compute_row_perturbed(formula, params, param_count, max_iter, ref_orbit, ref_len, dcx0, ddx, dcy, count,
//                            out) -> i32   (version 2)
// Zoom profond par perturbation : `count` pixels d'écart (dcx0 + i·ddx, dcy) au point de référence dont l'orbite
// Z0 = 0, Z1, ... est donnée par ref_orbit = x0, y0, x1, y1, ... (2·ref_len valeurs). Mandelbrot, Tricorn,
// Burning Ship (version 3) et Multibrot à puissance entière (version 4) ; même algorithme que IteratePerturbed dans
// src\Fractal.Formulas.pas. Julia et une puissance non entière : FK_UNSUPPORTED.
//   fk_perturbation_supported(formula) -> i32   (version 3)
// 1 pour les cinq formules (version 4 ; Multibrot : puissances entières seulement), 0 pour un identifiant inconnu.
//   fk_compute_row_perturbed2(formula, params, param_count, max_iter, ref_orbit, ref_len, crit_orbit, crit_len,
//                             dcx0, ddx, dcy, count, out) -> i32   (version 4)
// Comme fk_compute_row_perturbed, plus l'orbite critique W0 = 0, W1, ... (crit_orbit, 2·crit_len valeurs),
// obligatoire pour Julia et ignorée par les autres formules. Pour Julia, ref_orbit part de Z0 = la référence et
// (dcx0 + i·ddx, dcy) est δ0 = pixel - référence ; même algorithme que TJuliaFormula.IteratePerturbedCritical.
//   fk_compute_row_perturbed_bla(formula, params, param_count, max_iter, ref_orbit, ref_len, bla, bla_len, dcx0,
//                                ddx, dcy, count, out) -> i32   (version 5)
//   fk_compute_row_perturbed2_bla(formula, params, param_count, max_iter, ref_orbit, ref_len, bla, bla_len,
//                                 crit_orbit, crit_len, crit_bla, crit_bla_len, dcx0, ddx, dcy, count, out) -> i32
// Comme les deux précédentes, avec la table BLA (approximation bilinéaire) de chaque orbite, construite par
// src\Fractal.Bla.pas (bla_len f64 ; 0 = sans BLA) : sauts de plusieurs itérations, pour les vidéos. Mandelbrot,
// Multibrot entier et Julia ; Burning Ship et Tricorn calculent sans BLA.
//
// Compiler la DLL 32 bits :  cargo build --release --target i686-pc-windows-msvc

use std::f64::consts::LN_2;
use std::panic::{catch_unwind, AssertUnwindSafe};
use wide::*;

pub const ABI_VERSION: u32 = 5;

pub const FK_OK: i32 = 0;
pub const FK_UNKNOWN_FORMULA: i32 = 1;
pub const FK_BAD_PARAM_COUNT: i32 = 2;
pub const FK_INVALID_ARGUMENT: i32 = 3;
pub const FK_INTERNAL_ERROR: i32 = 4;
pub const FK_UNSUPPORTED: i32 = 5; // formule sans perturbation (ou Julia) demandée à fk_compute_row_perturbed

// réponses de fk_perturbation_supported
pub const FK_PERTURBATION_SUPPORTED: i32 = 1;
pub const FK_PERTURBATION_UNSUPPORTED: i32 = 0;

const MIN_ORBIT_LENGTH: i32 = 2; // orbite de référence : Z0 et au moins Z1, lu après le premier pas
// puissance entière de Multibrot : seules 2..MAX_PERTURBED_POWER sont perturbables, à INTEGER_POWER_TOLERANCE près
const MIN_PERTURBED_POWER: f64 = 2.0;
const MAX_PERTURBED_POWER: usize = 10;
const INTEGER_POWER_TOLERANCE: f64 = 1e-9;

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

    // Multibrot à puissance non entière passe par exp, ln, atan2, cos et sin : calcul scalaire seulement.
    fn is_vectorizable(self) -> bool {
        match self {
            Formula::Multibrot { power, .. } => is_integer_power(power),
            _ => true,
        }
    }

    // TFractalFormula.IsPerturbationSupported côté Delphi : toutes, Multibrot pour une puissance entière seulement.
    fn supports_perturbation(self) -> bool {
        match self {
            Formula::Multibrot { power, .. } => is_integer_power(power),
            _ => true,
        }
    }

    // TFractalFormula.HasPixelStart côté Delphi : z0 est le pixel (Julia), la perturbation exige l'orbite critique.
    fn has_pixel_start(self) -> bool {
        matches!(self, Formula::Julia { .. })
    }

    // fk_perturbation_supported : décidé sur l'identifiant seul, sans paramètres (identifiants de from_id).
    // Une nouvelle formule n'est pas prise en charge sans décision explicite : l'intervalle s'arrête à 4.
    fn id_supports_perturbation(id: i32) -> bool {
        matches!(id, 0..=4)
    }
}

// Vrai si `power` est un entier de 2 à MAX_PERTURBED_POWER (tolérance INTEGER_POWER_TOLERANCE), comme
// IsIntegerPower dans src\Fractal.Formulas.pas.
fn is_integer_power(power: f64) -> bool {
    if power.is_nan() || !(0.0..=(MAX_PERTURBED_POWER + 1) as f64).contains(&power) {
        return false;
    }
    let nearest = power.round();
    (power - nearest).abs() < INTEGER_POWER_TOLERANCE
        && (MIN_PERTURBED_POWER..=MAX_PERTURBED_POWER as f64).contains(&nearest)
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
    if is_integer_power(power) {
        return iterate_multibrot_integer(max_iter, power.round() as usize, log_power, cx, cy);
    }
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

// Puissance entière p : z^p par p - 1 multiplications complexes successives, comme TMultibrotFormula.Iterate et
// StepFloat côté Delphi (bien plus rapide que la forme polaire, et vectorisable).
fn iterate_multibrot_integer(max_iter: i32, p: usize, log_power: f64, cx: f64, cy: f64) -> f32 {
    let mut x = 0.0_f64;
    let mut y = 0.0_f64;
    for n in 0..max_iter {
        let m = x * x + y * y;
        if m > ESCAPE_RADIUS2 {
            return smooth_value(n, m, log_power);
        }
        let mut px = x;
        let mut py = y;
        for _ in 2..=p {
            let t = px * x - py * y;
            py = px * y + py * x;
            px = t;
        }
        x = px + cx;
        y = py + cy;
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
        Formula::Multibrot { power, log_power } => {
            if is_integer_power(power) {
                return iterate4_multibrot_integer(max_iter, power.round() as usize, log_power, vx, vy);
            }
            let mut result = [INSIDE; LANES];
            for lane in 0..LANES {
                result[lane] = iterate(formula, max_iter, pxs[lane], py);
            }
            result
        }
    }
}

// iterate_multibrot_integer sur quatre voies, mêmes opérations dans le même ordre
fn iterate4_multibrot_integer(max_iter: i32, p: usize, log_power: f64, cx: f64x4, cy: f64x4) -> [f32; LANES] {
    let mut result = [INSIDE; LANES];
    let mut done: u32 = 0;
    let radius2 = f64x4::splat(ESCAPE_RADIUS2);
    let mut x = f64x4::splat(0.0);
    let mut y = f64x4::splat(0.0);
    for n in 0..max_iter {
        let modulus2 = x * x + y * y;
        let escaped = (modulus2.cmp_gt(radius2).move_mask() as u32) & !done;
        if escaped != 0 {
            let values = modulus2.to_array();
            for lane in 0..LANES {
                if escaped & (1 << lane) != 0 {
                    result[lane] = smooth_value(n, values[lane], log_power);
                }
            }
            done |= escaped;
            if done == ALL_LANES_DONE {
                break;
            }
        }
        let mut px = x;
        let mut py = y;
        for _ in 2..=p {
            let t = px * x - py * y;
            py = px * y + py * x;
            px = t;
        }
        x = px + cx;
        y = py + cy;
    }
    result
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
// Perturbation (zoom profond) : calcul scalaire, mêmes opérations dans le même ordre que les IteratePerturbed de
// TMandelbrotFormula, TTricornFormula, TBurningShipFormula et TMultibrotFormula, et que
// TJuliaFormula.IteratePerturbedCritical.

// |c + d| - |c| sans soustraire deux grands nombres voisins : d garde toute sa précision quand il est minuscule.
// Même tableau que DiffAbs dans src\Fractal.Formulas.pas : (c >= 0, c + d >= 0) donne d ; (c >= 0, c + d < 0)
// donne -(2c + d) ; (c < 0, c + d > 0) donne 2c + d ; (c < 0, c + d <= 0) donne -d.
fn diff_abs(c: f64, d: f64) -> f64 {
    if c >= 0.0 {
        if c + d >= 0.0 {
            d
        } else {
            -(2.0 * c + d)
        }
    } else if c + d > 0.0 {
        2.0 * c + d
    } else {
        -d
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Table BLA (approximation bilinéaire), construite par Fractal.Bla côté Delphi et reçue telle quelle : Steps =
// longueur d'orbite - 1 pas de base ; le pas m (1 <= m <= Steps) mène de l'itération m à m + 1 avec Z = orbit[m]. Le
// niveau k a ceil(Steps / 2^k) entrées ; l'entrée j couvre les pas 1 + j·2^k et suivants. Niveaux concaténés 0, 1,
// 2… jusqu'au premier qui n'a qu'une entrée. Une entrée = BLA_ENTRY f64 : AX, AY, BX, BY, R, Len ; elle donne
// δ(m + Len) ≈ A·δ(m) + B·δc tant que |δ(m)| < R.

const BLA_ENTRY: usize = 6;
const BLA_MAX_LEVELS: usize = 40;

fn bla_level_entries(steps: usize, level: usize) -> usize {
    (steps + (1 << level) - 1) >> level
}

struct Bla<'a> {
    data: &'a [f64],
    steps: usize,
    level_count: usize,
    starts: [usize; BLA_MAX_LEVELS], // première entrée de chaque niveau
}

impl<'a> Bla<'a> {
    // None si `data` n'a pas la taille d'une table pour une orbite de `orbit_len` points
    fn new(data: &'a [f64], orbit_len: usize) -> Option<Self> {
        if orbit_len < 2 {
            return None;
        }
        let steps = orbit_len - 1;
        let mut starts = [0_usize; BLA_MAX_LEVELS];
        let mut level_count = 1;
        while bla_level_entries(steps, level_count - 1) > 1 {
            if level_count >= BLA_MAX_LEVELS {
                return None;
            }
            starts[level_count] = starts[level_count - 1] + bla_level_entries(steps, level_count - 1);
            level_count += 1;
        }
        if data.len() != (starts[level_count - 1] + 1) * BLA_ENTRY {
            return None;
        }
        Some(Bla { data, steps, level_count, starts })
    }

    // Saut au point m (>= 1) à l'itération n, comme BlaJump : l'entrée alignée du plus haut niveau dont le rayon
    // contient δ, sans dépasser max_iter ni la fin de l'orbite ; δ devient A·δ + B·δc. Pas sautés, 0 si aucun.
    #[allow(clippy::too_many_arguments)]
    fn jump(&self, m: usize, n: i32, max_iter: i32, orbit_len: usize, delta: &mut (f64, f64), dcx: f64, dcy: f64) -> usize {
        if m < 1 || m > self.steps {
            return 0;
        }
        let k = m - 1;
        let top = if k == 0 {
            self.level_count - 1
        } else {
            (k.trailing_zeros() as usize).min(self.level_count - 1)
        };
        let (dx, dy) = *delta;
        let d2 = dx * dx + dy * dy;
        for level in (0..=top).rev() {
            let o = (self.starts[level] + (k >> level)) * BLA_ENTRY;
            let e = &self.data[o..o + BLA_ENTRY];
            if d2 >= e[4] * e[4] {
                continue;
            }
            let len = e[5].round() as usize;
            if i64::from(n) + len as i64 > i64::from(max_iter) || m + len > orbit_len - 1 {
                continue;
            }
            *delta = (
                e[0] * dx - e[1] * dy + e[2] * dcx - e[3] * dcy,
                e[0] * dy + e[1] * dx + e[2] * dcy + e[3] * dcx,
            );
            return len;
        }
        0
    }
}

// Table BLA reçue de Delphi : Ok(None) si bla_len = 0 ; FK_INVALID_ARGUMENT si la taille ne va pas avec l'orbite.
///
/// # Safety
/// `bla` désigne `bla_len` f64 lisibles quand `bla_len` > 0.
unsafe fn bla_from_raw<'a>(bla: *const f64, bla_len: i32, orbit_len: i32) -> Result<Option<Bla<'a>>, i32> {
    if bla_len == 0 {
        return Ok(None);
    }
    if bla_len < 0 || bla.is_null() || orbit_len < 2 {
        return Err(FK_INVALID_ARGUMENT);
    }
    let data = std::slice::from_raw_parts(bla, bla_len as usize);
    Bla::new(data, orbit_len as usize).map(Some).ok_or(FK_INVALID_ARGUMENT)
}

// Pixel d'écart (dcx, dcy) à la référence, comme IteratePerturbedCritical : `critical` = orbite critique W de Julia
// (où (dcx, dcy) est δ0), ignorée par les autres formules. Julia et Multibrot à puissance non entière n'arrivent ici
// qu'après les contrôles des exportations.
// `bla`, `crit_bla` : tables BLA de `orbit` et `critical` (None = sans BLA) ; Burning Ship et Tricorn n'en ont pas.
#[allow(clippy::too_many_arguments)]
fn iterate_perturbed(
    formula: Formula,
    max_iter: i32,
    orbit: &[f64],
    critical: &[f64],
    bla: Option<&Bla>,
    crit_bla: Option<&Bla>,
    dcx: f64,
    dcy: f64,
) -> f32 {
    match formula {
        Formula::Julia { .. } => iterate_perturbed_julia(max_iter, orbit, critical, bla, crit_bla, dcx, dcy),
        Formula::Multibrot { power, log_power } => {
            iterate_perturbed_multibrot(max_iter, power.round() as usize, log_power, orbit, bla, dcx, dcy)
        }
        Formula::Mandelbrot => iterate_perturbed_quadratic(formula, max_iter, orbit, bla, dcx, dcy),
        _ => iterate_perturbed_quadratic(formula, max_iter, orbit, None, dcx, dcy),
    }
}

// Mandelbrot, Tricorn et Burning Ship. `orbit` = x0, y0, x1, y1, ... avec Z0 = 0 ; au moins deux points (après le
// premier pas, la boucle lit Z1).
fn iterate_perturbed_quadratic(formula: Formula, max_iter: i32, orbit: &[f64], bla: Option<&Bla>, dcx: f64, dcy: f64) -> f32 {
    let orbit_len = orbit.len() / 2;
    let is_conjugate = matches!(formula, Formula::Tricorn);
    let is_burning_ship = matches!(formula, Formula::BurningShip);
    let mut dx = 0.0_f64;
    let mut dy = 0.0_f64;
    let mut m: usize = 0;
    let mut n: i32 = 0;
    while n < max_iter {
        let zx = orbit[2 * m] + dx;
        let zy = orbit[2 * m + 1] + dy;
        let r2 = zx * zx + zy * zy;
        if r2 > ESCAPE_RADIUS2 {
            return smooth_value(n, r2, LN_2);
        }
        if r2 < dx * dx + dy * dy || m == orbit_len - 1 {
            // rebasage : la référence redevient Z0 = 0
            dx = zx;
            dy = zy;
            m = 0;
        }
        if let Some(table) = bla {
            let mut delta = (dx, dy);
            let len = table.jump(m, n, max_iter, orbit_len, &mut delta, dcx, dcy);
            if len > 0 {
                dx = delta.0;
                dy = delta.1;
                m += len;
                n += len as i32;
                continue;
            }
        }
        let (ox, oy) = (orbit[2 * m], orbit[2 * m + 1]);
        // δ' = 2·Z·δ + δ² + δc ; Tricorn : δ' = conj(2·Z·δ + δ²) + δc
        // Burning Ship : δx' comme Mandelbrot, δy' = 2·diffabs(X·Y, X·δy + Y·δx + δx·δy) - δcy
        let new_dx = 2.0 * (ox * dx - oy * dy) + dx * dx - dy * dy + dcx;
        let new_dy = if is_burning_ship {
            2.0 * diff_abs(ox * oy, ox * dy + oy * dx + dx * dy) - dcy
        } else {
            let cross = 2.0 * (ox * dy + oy * dx) + 2.0 * dx * dy;
            if is_conjugate {
                -cross + dcy
            } else {
                cross + dcy
            }
        };
        dx = new_dx;
        dy = new_dy;
        m += 1;
        n += 1;
    }
    INSIDE
}

// Multibrot à puissance entière `p` (2..MAX_PERTURBED_POWER), Z0 = 0 : δ' = Σ C(p,k)·Z^(p-k)·δ^k + δc, en Horner
// sur δ ; lissage en ln p (`log_power`, de la puissance reçue).
fn iterate_perturbed_multibrot(
    max_iter: i32,
    p: usize,
    log_power: f64,
    orbit: &[f64],
    bla: Option<&Bla>,
    dcx: f64,
    dcy: f64,
) -> f32 {
    let orbit_len = orbit.len() / 2;
    let mut binomial = [0.0_f64; MAX_PERTURBED_POWER + 1]; // C(p, k)
    let mut pow_x = [0.0_f64; MAX_PERTURBED_POWER + 1]; // Z^j
    let mut pow_y = [0.0_f64; MAX_PERTURBED_POWER + 1];
    binomial[0] = 1.0;
    for k in 1..=p {
        binomial[k] = binomial[k - 1] * (p - k + 1) as f64 / k as f64;
    }
    pow_x[0] = 1.0;
    pow_y[0] = 0.0;
    let mut dx = 0.0_f64;
    let mut dy = 0.0_f64;
    let mut m: usize = 0;
    let mut n: i32 = 0;
    while n < max_iter {
        let zx = orbit[2 * m] + dx;
        let zy = orbit[2 * m + 1] + dy;
        let r2 = zx * zx + zy * zy;
        if r2 > ESCAPE_RADIUS2 {
            return smooth_value(n, r2, log_power);
        }
        if r2 < dx * dx + dy * dy || m == orbit_len - 1 {
            // rebasage : la référence redevient Z0 = 0
            dx = zx;
            dy = zy;
            m = 0;
        }
        if let Some(table) = bla {
            let mut delta = (dx, dy);
            let len = table.jump(m, n, max_iter, orbit_len, &mut delta, dcx, dcy);
            if len > 0 {
                dx = delta.0;
                dy = delta.1;
                m += len;
                n += len as i32;
                continue;
            }
        }
        let (ox, oy) = (orbit[2 * m], orbit[2 * m + 1]);
        // puissances de Z : Z^j pour j = 0..p-1
        for k in 1..p {
            pow_x[k] = pow_x[k - 1] * ox - pow_y[k - 1] * oy;
            pow_y[k] = pow_x[k - 1] * oy + pow_y[k - 1] * ox;
        }
        // Horner : S := C(p,p) ; S := S·δ + C(p,k)·Z^(p-k) pour k = p-1..1 ; δ' := S·δ + δc
        let mut sx = 1.0_f64;
        let mut sy = 0.0_f64;
        for k in (1..p).rev() {
            let tx = sx * dx - sy * dy;
            let ty = sx * dy + sy * dx;
            sx = tx + binomial[k] * pow_x[p - k];
            sy = ty + binomial[k] * pow_y[p - k];
        }
        let tx = sx * dx - sy * dy + dcx;
        let ty = sx * dy + sy * dx + dcy;
        dx = tx;
        dy = ty;
        m += 1;
        n += 1;
    }
    INSIDE
}

// Julia : δ0 = (dx0, dy0) = pixel - référence ; δ' = 2·Z·δ + δ² (pas de δc). On itère sur `orbit` (Z0 = la
// référence) ; quand |z|² < |δ|² ou en fin d'orbite, on rebase sur l'orbite critique W (`critical`, W0 = 0) :
// δ := z, m := 0 ; sur W, même règle, toujours vers W0. Les deux orbites ont au moins deux points.
// `bla` sert sur Z, `crit_bla` sur W après le rebasage (B = 0 : pas de δc).
fn iterate_perturbed_julia(
    max_iter: i32,
    orbit: &[f64],
    critical: &[f64],
    bla: Option<&Bla>,
    crit_bla: Option<&Bla>,
    dx0: f64,
    dy0: f64,
) -> f32 {
    let mut reference = orbit;
    let mut reference_bla = bla;
    let mut reference_len = orbit.len() / 2;
    let mut dx = dx0;
    let mut dy = dy0;
    let mut m: usize = 0;
    let mut n: i32 = 0;
    while n < max_iter {
        let zx = reference[2 * m] + dx;
        let zy = reference[2 * m + 1] + dy;
        let r2 = zx * zx + zy * zy;
        if r2 > ESCAPE_RADIUS2 {
            return smooth_value(n, r2, LN_2);
        }
        if r2 < dx * dx + dy * dy || m == reference_len - 1 {
            // rebasage sur W : W0 = 0, donc δ := z
            dx = zx;
            dy = zy;
            m = 0;
            reference = critical;
            reference_bla = crit_bla;
            reference_len = critical.len() / 2;
        }
        if let Some(table) = reference_bla {
            let mut delta = (dx, dy);
            let len = table.jump(m, n, max_iter, reference_len, &mut delta, 0.0, 0.0);
            if len > 0 {
                dx = delta.0;
                dy = delta.1;
                m += len;
                n += len as i32;
                continue;
            }
        }
        let (ox, oy) = (reference[2 * m], reference[2 * m + 1]);
        let new_dx = 2.0 * (ox * dx - oy * dy) + dx * dx - dy * dy;
        let new_dy = 2.0 * (ox * dy + oy * dx) + 2.0 * dx * dy;
        dx = new_dx;
        dy = new_dy;
        m += 1;
        n += 1;
    }
    INSIDE
}

#[allow(clippy::too_many_arguments)]
fn compute_row_perturbed(
    formula: Formula,
    max_iter: i32,
    orbit: &[f64],
    critical: &[f64],
    bla: Option<&Bla>,
    crit_bla: Option<&Bla>,
    dcx0: f64,
    ddx: f64,
    dcy: f64,
    out: &mut [f32],
) {
    for (i, value) in out.iter_mut().enumerate() {
        *value = iterate_perturbed(formula, max_iter, orbit, critical, bla, crit_bla, dcx0 + i as f64 * ddx, dcy);
    }
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
        let formula = match formula_from_raw(formula, params, param_count) {
            Ok(formula) => formula,
            Err(code) => return code,
        };
        let out = std::slice::from_raw_parts_mut(out, count as usize);
        compute_row(formula, max_iter, x0, dx, y, true, out);
        FK_OK
    }));
    result.unwrap_or(FK_INTERNAL_ERROR)
}

/// # Safety
/// `params` désigne `param_count` f64 lisibles (`param_count` >= 0, `params` non nul si `param_count` > 0).
unsafe fn formula_from_raw(id: i32, params: *const f64, param_count: i32) -> Result<Formula, i32> {
    let params: &[f64] = if param_count == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(params, param_count as usize)
    };
    Formula::from_id(id, params)
}

/// # Safety
/// `params` désigne `param_count` f64 lisibles, `ref_orbit` désigne 2·`ref_len` f64 lisibles et `out` désigne
/// `count` f32 modifiables.
#[no_mangle]
pub unsafe extern "C" fn fk_compute_row_perturbed(
    formula: i32,
    params: *const f64,
    param_count: i32,
    max_iter: i32,
    ref_orbit: *const f64,
    ref_len: i32,
    dcx0: f64,
    ddx: f64,
    dcy: f64,
    count: i32,
    out: *mut f32,
) -> i32 {
    // aucune panique ne doit traverser la frontière avec Delphi
    let result = catch_unwind(AssertUnwindSafe(|| {
        if param_count < 0 || max_iter < 0 || count < 0 || out.is_null() || (param_count > 0 && params.is_null()) {
            return FK_INVALID_ARGUMENT;
        }
        if ref_orbit.is_null() || ref_len < MIN_ORBIT_LENGTH {
            return FK_INVALID_ARGUMENT;
        }
        let formula = match formula_from_raw(formula, params, param_count) {
            Ok(formula) => formula,
            Err(code) => return code,
        };
        // Julia exige l'orbite critique : fk_compute_row_perturbed2
        if !formula.supports_perturbation() || formula.has_pixel_start() {
            return FK_UNSUPPORTED;
        }
        let orbit = std::slice::from_raw_parts(ref_orbit, 2 * ref_len as usize);
        let out = std::slice::from_raw_parts_mut(out, count as usize);
        compute_row_perturbed(formula, max_iter, orbit, &[], None, None, dcx0, ddx, dcy, out);
        FK_OK
    }));
    result.unwrap_or(FK_INTERNAL_ERROR)
}

/// # Safety
/// Comme fk_compute_row_perturbed ; de plus, pour Julia, `crit_orbit` désigne 2·`crit_len` f64 lisibles (pour les
/// autres formules, `crit_orbit` n'est pas lu et `crit_len` doit seulement être >= 0).
#[no_mangle]
pub unsafe extern "C" fn fk_compute_row_perturbed2(
    formula: i32,
    params: *const f64,
    param_count: i32,
    max_iter: i32,
    ref_orbit: *const f64,
    ref_len: i32,
    crit_orbit: *const f64,
    crit_len: i32,
    dcx0: f64,
    ddx: f64,
    dcy: f64,
    count: i32,
    out: *mut f32,
) -> i32 {
    // aucune panique ne doit traverser la frontière avec Delphi
    let result = catch_unwind(AssertUnwindSafe(|| {
        if param_count < 0 || max_iter < 0 || count < 0 || out.is_null() || (param_count > 0 && params.is_null()) {
            return FK_INVALID_ARGUMENT;
        }
        if ref_orbit.is_null() || ref_len < MIN_ORBIT_LENGTH || crit_len < 0 {
            return FK_INVALID_ARGUMENT;
        }
        let formula = match formula_from_raw(formula, params, param_count) {
            Ok(formula) => formula,
            Err(code) => return code,
        };
        if !formula.supports_perturbation() {
            return FK_UNSUPPORTED;
        }
        let critical: &[f64] = if formula.has_pixel_start() {
            if crit_orbit.is_null() || crit_len < MIN_ORBIT_LENGTH {
                return FK_INVALID_ARGUMENT;
            }
            std::slice::from_raw_parts(crit_orbit, 2 * crit_len as usize)
        } else {
            &[]
        };
        let orbit = std::slice::from_raw_parts(ref_orbit, 2 * ref_len as usize);
        let out = std::slice::from_raw_parts_mut(out, count as usize);
        compute_row_perturbed(formula, max_iter, orbit, critical, None, None, dcx0, ddx, dcy, out);
        FK_OK
    }));
    result.unwrap_or(FK_INTERNAL_ERROR)
}

/// Comme fk_compute_row_perturbed, avec la table BLA de l'orbite (`bla`, `bla_len` f64, format de Fractal.Bla ;
/// `bla_len` = 0 : sans BLA). Taille de table qui ne correspond pas à `ref_len` : FK_INVALID_ARGUMENT.
///
/// # Safety
/// Comme fk_compute_row_perturbed ; de plus `bla` désigne `bla_len` f64 lisibles quand `bla_len` > 0.
#[no_mangle]
pub unsafe extern "C" fn fk_compute_row_perturbed_bla(
    formula: i32,
    params: *const f64,
    param_count: i32,
    max_iter: i32,
    ref_orbit: *const f64,
    ref_len: i32,
    bla: *const f64,
    bla_len: i32,
    dcx0: f64,
    ddx: f64,
    dcy: f64,
    count: i32,
    out: *mut f32,
) -> i32 {
    // aucune panique ne doit traverser la frontière avec Delphi
    let result = catch_unwind(AssertUnwindSafe(|| {
        if param_count < 0 || max_iter < 0 || count < 0 || out.is_null() || (param_count > 0 && params.is_null()) {
            return FK_INVALID_ARGUMENT;
        }
        if ref_orbit.is_null() || ref_len < MIN_ORBIT_LENGTH {
            return FK_INVALID_ARGUMENT;
        }
        let table = match bla_from_raw(bla, bla_len, ref_len) {
            Ok(table) => table,
            Err(code) => return code,
        };
        let formula = match formula_from_raw(formula, params, param_count) {
            Ok(formula) => formula,
            Err(code) => return code,
        };
        if !formula.supports_perturbation() || formula.has_pixel_start() {
            return FK_UNSUPPORTED;
        }
        let orbit = std::slice::from_raw_parts(ref_orbit, 2 * ref_len as usize);
        let out = std::slice::from_raw_parts_mut(out, count as usize);
        compute_row_perturbed(formula, max_iter, orbit, &[], table.as_ref(), None, dcx0, ddx, dcy, out);
        FK_OK
    }));
    result.unwrap_or(FK_INTERNAL_ERROR)
}

/// Comme fk_compute_row_perturbed2, avec les tables BLA de l'orbite (`bla`) et de l'orbite critique (`crit_bla`) ;
/// longueur 0 = sans BLA pour cette orbite.
///
/// # Safety
/// Comme fk_compute_row_perturbed2 ; de plus `bla` et `crit_bla` désignent `bla_len` et `crit_bla_len` f64 lisibles
/// quand leur longueur est > 0.
#[no_mangle]
pub unsafe extern "C" fn fk_compute_row_perturbed2_bla(
    formula: i32,
    params: *const f64,
    param_count: i32,
    max_iter: i32,
    ref_orbit: *const f64,
    ref_len: i32,
    bla: *const f64,
    bla_len: i32,
    crit_orbit: *const f64,
    crit_len: i32,
    crit_bla: *const f64,
    crit_bla_len: i32,
    dcx0: f64,
    ddx: f64,
    dcy: f64,
    count: i32,
    out: *mut f32,
) -> i32 {
    // aucune panique ne doit traverser la frontière avec Delphi
    let result = catch_unwind(AssertUnwindSafe(|| {
        if param_count < 0 || max_iter < 0 || count < 0 || out.is_null() || (param_count > 0 && params.is_null()) {
            return FK_INVALID_ARGUMENT;
        }
        if ref_orbit.is_null() || ref_len < MIN_ORBIT_LENGTH || crit_len < 0 {
            return FK_INVALID_ARGUMENT;
        }
        let table = match bla_from_raw(bla, bla_len, ref_len) {
            Ok(table) => table,
            Err(code) => return code,
        };
        let crit_table = match bla_from_raw(crit_bla, crit_bla_len, crit_len) {
            Ok(table) => table,
            Err(code) => return code,
        };
        let formula = match formula_from_raw(formula, params, param_count) {
            Ok(formula) => formula,
            Err(code) => return code,
        };
        if !formula.supports_perturbation() {
            return FK_UNSUPPORTED;
        }
        let critical: &[f64] = if formula.has_pixel_start() {
            if crit_orbit.is_null() || crit_len < MIN_ORBIT_LENGTH {
                return FK_INVALID_ARGUMENT;
            }
            std::slice::from_raw_parts(crit_orbit, 2 * crit_len as usize)
        } else {
            &[]
        };
        let orbit = std::slice::from_raw_parts(ref_orbit, 2 * ref_len as usize);
        let out = std::slice::from_raw_parts_mut(out, count as usize);
        compute_row_perturbed(
            formula,
            max_iter,
            orbit,
            critical,
            table.as_ref(),
            crit_table.as_ref(),
            dcx0,
            ddx,
            dcy,
            out,
        );
        FK_OK
    }));
    result.unwrap_or(FK_INTERNAL_ERROR)
}

// 1 si la formule d'identifiant `formula` a sa perturbation (fk_compute_row_perturbed, ou fk_compute_row_perturbed2
// pour Julia ; Multibrot : puissances entières seulement), 0 sinon (identifiant inconnu compris).
#[no_mangle]
pub extern "C" fn fk_perturbation_supported(formula: i32) -> i32 {
    // aucune panique ne doit traverser la frontière avec Delphi ; en cas de panique, la formule reste en Delphi
    let result = catch_unwind(AssertUnwindSafe(|| {
        if Formula::id_supports_perturbation(formula) {
            FK_PERTURBATION_SUPPORTED
        } else {
            FK_PERTURBATION_UNSUPPORTED
        }
    }));
    result.unwrap_or(FK_PERTURBATION_UNSUPPORTED)
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
    fn abi_version_is_5() {
        assert_eq!(fk_abi_version(), 5);
    }

    // Mêmes valeurs que TestDiffAbs (tests\TestFractalPerturbation.pas), égalités strictes.
    #[test]
    fn diff_abs_cases() {
        const TINY: f64 = 1e-300;
        assert_eq!(diff_abs(3.0, 1.0), 1.0, "c >= 0, c + d >= 0 : d");
        assert_eq!(diff_abs(3.0, -5.0), -1.0, "c >= 0, c + d < 0 : -(2c + d)");
        assert_eq!(diff_abs(-3.0, 5.0), -1.0, "c < 0, c + d > 0 : 2c + d");
        assert_eq!(diff_abs(-3.0, 1.0), -1.0, "c < 0, c + d <= 0 : -d");
        assert_eq!(diff_abs(0.0, -2.0), 2.0, "c = 0, d < 0");
        assert_eq!(diff_abs(0.0, 2.0), 2.0, "c = 0, d > 0");
        assert_eq!(diff_abs(2.0, -2.0), -2.0, "c + d = 0, c > 0");
        assert_eq!(diff_abs(-2.0, 2.0), -2.0, "c + d = 0, c < 0");
        assert_eq!(diff_abs(1.0, TINY), TINY, "c ~ 1, d ~ 1e-300 : d exactement");
    }

    #[test]
    fn perturbation_supported() {
        for &id in &[MANDELBROT, MULTIBROT, JULIA, BURNING_SHIP, TRICORN] {
            assert_eq!(fk_perturbation_supported(id), FK_PERTURBATION_SUPPORTED, "formule {}", id);
        }
        for &id in &[99, -1] {
            assert_eq!(fk_perturbation_supported(id), FK_PERTURBATION_UNSUPPORTED, "formule {}", id);
        }
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

    // forme polaire d'origine, gardée ici comme référence pour la puissance entière
    fn polar_multibrot(max_iter: i32, power: f64, cx: f64, cy: f64) -> f32 {
        let (mut x, mut y) = (0.0_f64, 0.0_f64);
        for n in 0..max_iter {
            let m = x * x + y * y;
            if m > ESCAPE_RADIUS2 {
                return smooth_value(n, m, power.ln());
            }
            if m == 0.0 {
                x = cx;
                y = cy;
            } else {
                let r = (0.5 * m.ln() * power).exp();
                let t = y.atan2(x) * power;
                x = r * t.cos() + cx;
                y = r * t.sin() + cy;
            }
        }
        INSIDE
    }

    #[test]
    fn multibrot_integer_matches_polar() {
        // loin du bord, les deux formes donnent le même verdict et presque la même valeur lissée
        for &p in &[3.0, 4.0, 7.0] {
            for &(x, y) in &[(0.0, 0.0), (2.0, 2.0), (0.9, 0.9), (-1.2, 0.4), (0.1, -0.2), (1.5, -0.3)] {
                let a = iterate_multibrot(500, p, f64::ln(p), x, y);
                let b = polar_multibrot(500, p, x, y);
                assert_eq!(a < 0.0, b < 0.0, "p = {} ({}, {})", p, x, y);
                if a >= 0.0 {
                    assert!((a - b).abs() < 1e-3, "p = {} ({}, {}) : {} contre {}", p, x, y, a, b);
                }
            }
        }
    }

    #[test]
    fn multibrot_integer_simd_matches_scalar_exactly() {
        let dx = 3.0 / ROW_LENGTH as f64;
        for &p in &[3.0, 5.0] {
            let formula = Formula::Multibrot { power: p, log_power: f64::ln(p) };
            let mut simd = vec![0.0_f32; ROW_LENGTH];
            let mut scalar = vec![0.0_f32; ROW_LENGTH];
            compute_row(formula, 300, -1.5, dx, 0.35, true, &mut simd);
            compute_row(formula, 300, -1.5, dx, 0.35, false, &mut scalar);
            assert_eq!(simd, scalar, "p = {}", p);
        }
    }

    #[test]
    fn simd_matches_scalar_exactly() {
        let dx = 3.5 / ROW_LENGTH as f64;
        let cases = [
            (Formula::Mandelbrot, -2.0, 0.3),
            (Formula::Julia { cx: -0.8, cy: 0.156 }, -1.75, 0.2),
            (Formula::BurningShip, -2.0, 0.5), // y > 0 : la formule soustrait cy (navire à l'endroit)
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

    // Mandelbrot et Tricorn : points d'intérêt de tests\TestFractalPerturbation.pas ; une ligne de 1 000 pixels de
    // 1e-12 y mêle intérieur et extérieur (mesuré côté Delphi en précision Double : 38 % et 50 % de pixels
    // extérieurs). Burning Ship, Multibrot et Julia : voir perturbed_matches_direct.
    const PERTURBED_MAX_ITER: i32 = 10000;
    const PERTURBED_PIXEL_SIZE: f64 = 1e-12;
    const MIN_AGREEMENT: f64 = 0.98;

    // Orbite de (x, y) par le pas `step`, comme ComputeOrbit (ici en f64) : jusqu'à l'échappement inclus ou
    // max_iter + 1 points ; x et y alternés.
    fn orbit_from(max_iter: i32, mut x: f64, mut y: f64, step: impl Fn(f64, f64) -> (f64, f64)) -> Vec<f64> {
        let mut orbit = Vec::new();
        let mut k = 0;
        loop {
            orbit.push(x);
            orbit.push(y);
            if x * x + y * y > ESCAPE_RADIUS2 || k >= max_iter {
                break;
            }
            let (new_x, new_y) = step(x, y);
            x = new_x;
            y = new_y;
            k += 1;
        }
        orbit
    }

    // Orbite de la référence (cx, cy), comme ComputeReferenceOrbit : Z0 = 0 et c = (cx, cy) ; pour Julia, Z0 = (cx,
    // cy) et c pris dans la formule. Multibrot : z^p par multiplications successives, comme StepFloat.
    fn reference_orbit(formula: Formula, max_iter: i32, cx: f64, cy: f64) -> Vec<f64> {
        match formula {
            Formula::Mandelbrot => orbit_from(max_iter, 0.0, 0.0, |x, y| (x * x - y * y + cx, 2.0 * x * y + cy)),
            Formula::Tricorn => orbit_from(max_iter, 0.0, 0.0, |x, y| (x * x - y * y + cx, -2.0 * x * y + cy)),
            Formula::BurningShip => {
                orbit_from(max_iter, 0.0, 0.0, |x, y| (x * x - y * y + cx, 2.0 * (x * y).abs() - cy))
            }
            Formula::Julia { cx: jx, cy: jy } => julia_orbit(max_iter, cx, cy, jx, jy),
            Formula::Multibrot { power, .. } => {
                let p = power.round() as usize;
                orbit_from(max_iter, 0.0, 0.0, |x, y| {
                    let (mut px, mut py) = (x, y);
                    for _ in 2..=p {
                        let t = px * x - py * y;
                        py = px * y + py * x;
                        px = t;
                    }
                    (px + cx, py + cy)
                })
            }
        }
    }

    // Julia de paramètre (jx, jy) : orbite de z ← z² + c depuis (x0, y0) ; depuis 0, c'est l'orbite critique W,
    // comme ComputeCriticalOrbit.
    fn julia_orbit(max_iter: i32, x0: f64, y0: f64, jx: f64, jy: f64) -> Vec<f64> {
        orbit_from(max_iter, x0, y0, |x, y| (x * x - y * y + jx, 2.0 * x * y + jy))
    }

    #[allow(clippy::too_many_arguments)]
    fn call_perturbed(
        formula: i32,
        params: &[f64],
        max_iter: i32,
        orbit: &[f64],
        dcx0: f64,
        ddx: f64,
        dcy: f64,
        count: usize,
    ) -> (i32, Vec<f32>) {
        let mut out = vec![NOT_WRITTEN; count];
        let code = unsafe {
            fk_compute_row_perturbed(
                formula,
                params.as_ptr(),
                params.len() as i32,
                max_iter,
                orbit.as_ptr(),
                (orbit.len() / 2) as i32,
                dcx0,
                ddx,
                dcy,
                count as i32,
                out.as_mut_ptr(),
            )
        };
        (code, out)
    }

    // Comme call_perturbed, par fk_compute_row_perturbed2 avec l'orbite critique `critical` (W0 = 0, W1, ...).
    #[allow(clippy::too_many_arguments)]
    fn call_perturbed2(
        formula: i32,
        params: &[f64],
        max_iter: i32,
        orbit: &[f64],
        critical: &[f64],
        dcx0: f64,
        ddx: f64,
        dcy: f64,
        count: usize,
    ) -> (i32, Vec<f32>) {
        let mut out = vec![NOT_WRITTEN; count];
        let code = unsafe {
            fk_compute_row_perturbed2(
                formula,
                params.as_ptr(),
                params.len() as i32,
                max_iter,
                orbit.as_ptr(),
                (orbit.len() / 2) as i32,
                critical.as_ptr(),
                (critical.len() / 2) as i32,
                dcx0,
                ddx,
                dcy,
                count as i32,
                out.as_mut_ptr(),
            )
        };
        (code, out)
    }

    // Julia : c par défaut de TJuliaFormula ; écart relatif appliqué aux x de W pour vérifier que la ligne s'en sert.
    const JULIA_PARAMS: [f64; 2] = [-0.8, 0.156];
    const CRITICAL_CORRUPTION: f64 = 1e-3;
    const MULTIBROT_FRACTIONAL_POWER: f64 = 3.5;

    #[test]
    fn perturbed_matches_direct() {
        let cases: [(i32, &[f64], i32, f64, f64); 6] = [
            (MANDELBROT, &[], PERTURBED_MAX_ITER, 0.390797755594254, -0.230650338697738),
            (TRICORN, &[], PERTURBED_MAX_ITER, -0.104560602519813, 0.228469084632435),
            // Burning Ship, hors de l'axe : bord trouvé côté Delphi en Double (bissection, 48 pas, MaxIter 10000,
            // rayon issu de l'origine à 2π/64 radians) ; 49,9 % de pixels extérieurs, échappements jusqu'à 9 999
            // itérations, 100 % de verdicts communs (perturbation f64 comme ici, et IteratePerturbed Delphi sur
            // l'orbite en Double comme la DLL factice)
            (BURNING_SHIP, &[], PERTURBED_MAX_ITER, 0.250151877253826, 0.024637809443158),
            // Multibrot p = 3 et p = 10, Julia : bords kMultibrot3, kMultibrot10 et kJuliaBorder de
            // tests\TestFractalPerturbation.pas arrondis en f64, avec leurs MaxIter. Mesuré côté Delphi en Double
            // (FPU à 53 bits, calcul direct et perturbation de ce test) : p = 3, 10,7 % de pixels extérieurs,
            // échappements jusqu'à 998 itérations ; p = 10, 49,9 %, jusqu'à 499 ; Julia, 60,7 %, jusqu'à 497, dont
            // 789 pixels rebasés sur W (185 valeurs changent avec W faussée de CRITICAL_CORRUPTION). 100 % de
            // verdicts communs pour les trois.
            (MULTIBROT, &[3.0], 1000, 0.6126762793371359, 0.5140964400228588),
            (MULTIBROT, &[10.0], 500, 0.12100571567348044, 0.686257515368839),
            (JULIA, &JULIA_PARAMS, 500, -1.4398988535028006, 0.059997935785771436),
        ];
        let half = (ROW_LENGTH / 2) as f64;
        for &(id, params, max_iter, cx, cy) in &cases {
            let formula = Formula::from_id(id, params).unwrap();
            let orbit = reference_orbit(formula, max_iter, cx, cy);
            let (dcx0, ddx) = (-half * PERTURBED_PIXEL_SIZE, PERTURBED_PIXEL_SIZE);
            let perturbed = if let Formula::Julia { cx: jx, cy: jy } = formula {
                let critical = julia_orbit(max_iter, 0.0, 0.0, jx, jy);
                let (code, perturbed) =
                    call_perturbed2(id, params, max_iter, &orbit, &critical, dcx0, ddx, 0.0, ROW_LENGTH);
                assert_eq!(code, FK_OK);
                let mut corrupted = critical.clone();
                for x in corrupted.iter_mut().step_by(2).skip(1) {
                    *x *= 1.0 + CRITICAL_CORRUPTION;
                }
                let (code, skewed) =
                    call_perturbed2(id, params, max_iter, &orbit, &corrupted, dcx0, ddx, 0.0, ROW_LENGTH);
                assert_eq!(code, FK_OK);
                assert!(
                    skewed.iter().zip(&perturbed).any(|(a, b)| a.to_bits() != b.to_bits()),
                    "{:?} : aucun pixel ne dépend de l'orbite critique",
                    formula
                );
                perturbed
            } else {
                let (code, perturbed) =
                    call_perturbed(id, params, max_iter, &orbit, dcx0, ddx, 0.0, ROW_LENGTH);
                assert_eq!(code, FK_OK);
                // fk_compute_row_perturbed2 ignore l'orbite critique : mêmes valeurs au bit près
                let (code, ignored) =
                    call_perturbed2(id, params, max_iter, &orbit, &[], dcx0, ddx, 0.0, ROW_LENGTH);
                assert_eq!(code, FK_OK);
                assert!(
                    ignored.iter().zip(&perturbed).all(|(a, b)| a.to_bits() == b.to_bits()),
                    "{:?} : fk_compute_row_perturbed2 diffère",
                    formula
                );
                perturbed
            };
            let mut agreeing = 0;
            let mut outside = 0;
            for (i, value) in perturbed.iter().enumerate() {
                let direct = iterate(formula, max_iter, cx + (i as f64 - half) * ddx, cy);
                if (direct < 0.0) == (*value < 0.0) {
                    agreeing += 1;
                }
                if direct >= 0.0 {
                    outside += 1;
                }
            }
            assert!(outside > 0 && outside < ROW_LENGTH, "{:?} : la ligne doit mêler intérieur et extérieur", formula);
            assert!(
                agreeing as f64 >= MIN_AGREEMENT * ROW_LENGTH as f64,
                "{:?} : {} verdicts communs sur {}",
                formula,
                agreeing,
                ROW_LENGTH
            );
        }
    }

    #[test]
    fn perturbed_error_codes() {
        let orbit = reference_orbit(Formula::Mandelbrot, MAX_ITER, -0.75, 0.1);
        let (dcx0, ddx) = (0.0, PERTURBED_PIXEL_SIZE);
        assert_eq!(call_perturbed(99, &[], MAX_ITER, &orbit, dcx0, ddx, 0.0, 4).0, FK_UNKNOWN_FORMULA);
        assert_eq!(call_perturbed(MANDELBROT, &[1.0], MAX_ITER, &orbit, dcx0, ddx, 0.0, 4).0, FK_BAD_PARAM_COUNT);
        assert_eq!(call_perturbed(JULIA, &[0.0, 0.0], MAX_ITER, &orbit, dcx0, ddx, 0.0, 4).0, FK_UNSUPPORTED);
        assert_eq!(call_perturbed(MULTIBROT, &[3.0], MAX_ITER, &orbit, dcx0, ddx, 0.0, 4).0, FK_OK);
        let fractional = [MULTIBROT_FRACTIONAL_POWER];
        assert_eq!(call_perturbed(MULTIBROT, &fractional, MAX_ITER, &orbit, dcx0, ddx, 0.0, 4).0, FK_UNSUPPORTED);
        assert_eq!(call_perturbed(BURNING_SHIP, &[], MAX_ITER, &orbit, dcx0, ddx, 0.0, 4).0, FK_OK);
        assert_eq!(call_perturbed(MANDELBROT, &[], MAX_ITER, &[], dcx0, ddx, 0.0, 4).0, FK_INVALID_ARGUMENT);
        // fk_compute_row_perturbed2 : l'orbite critique est obligatoire pour Julia (au moins deux points), ignorée
        // par les autres formules ; (formule, paramètres, orbite de référence, orbite critique, code attendu)
        let critical = julia_orbit(MAX_ITER, 0.0, 0.0, JULIA_PARAMS[0], JULIA_PARAMS[1]);
        let cases2: [(i32, &[f64], &[f64], &[f64], i32); 8] = [
            (JULIA, &JULIA_PARAMS, &orbit, &critical, FK_OK),
            (JULIA, &JULIA_PARAMS, &orbit, &[], FK_INVALID_ARGUMENT),
            (JULIA, &JULIA_PARAMS, &orbit, &critical[..2], FK_INVALID_ARGUMENT), // un seul point
            (JULIA, &[0.0], &orbit, &critical, FK_BAD_PARAM_COUNT),
            (99, &[], &orbit, &[], FK_UNKNOWN_FORMULA),
            (MULTIBROT, &fractional, &orbit, &[], FK_UNSUPPORTED),
            (MULTIBROT, &[3.0], &orbit, &[], FK_OK),
            (MANDELBROT, &[], &[], &[], FK_INVALID_ARGUMENT),
        ];
        for &(id, params, reference, crit, expected) in &cases2 {
            let code = call_perturbed2(id, params, MAX_ITER, reference, crit, dcx0, ddx, 0.0, 4).0;
            assert_eq!(code, expected, "formule {}, orbite critique de {} points", id, crit.len() / 2);
        }
        let julia_params = JULIA_PARAMS;
        let mut out = [NOT_WRITTEN; 4];
        unsafe {
            let null_orbit: *const f64 = std::ptr::null();
            let null_params: *const f64 = std::ptr::null();
            let null_out: *mut f32 = std::ptr::null_mut();
            let p = out.as_mut_ptr();
            assert_eq!(
                fk_compute_row_perturbed(MANDELBROT, null_params, 0, MAX_ITER, null_orbit, 2, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            let o = orbit.as_ptr();
            assert_eq!(
                fk_compute_row_perturbed(MANDELBROT, null_params, 0, MAX_ITER, o, 0, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed(MANDELBROT, null_params, 0, MAX_ITER, o, 1, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed(MANDELBROT, null_params, 0, -1, o, 2, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed(MANDELBROT, null_params, 0, MAX_ITER, o, 2, dcx0, ddx, 0.0, 4, null_out),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed(MANDELBROT, null_params, 0, MAX_ITER, o, 2, dcx0, ddx, 0.0, 0, p),
                FK_OK
            );
            let j = julia_params.as_ptr();
            let w = critical.as_ptr();
            assert_eq!(
                fk_compute_row_perturbed2(JULIA, j, 2, MAX_ITER, o, 2, null_orbit, 2, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed2(JULIA, j, 2, MAX_ITER, null_orbit, 2, w, 2, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed2(MANDELBROT, null_params, 0, MAX_ITER, o, 2, w, -1, dcx0, ddx, 0.0, 4, p),
                FK_INVALID_ARGUMENT
            );
            assert_eq!(
                fk_compute_row_perturbed2(JULIA, j, 2, MAX_ITER, o, 2, w, 2, dcx0, ddx, 0.0, 4, null_out),
                FK_INVALID_ARGUMENT
            );
            // autres formules : orbite critique nulle acceptée (ignorée)
            assert_eq!(
                fk_compute_row_perturbed2(
                    MANDELBROT, null_params, 0, MAX_ITER, o, 2, null_orbit, 0, dcx0, ddx, 0.0, 0, p
                ),
                FK_OK
            );
        }
        assert!(out.iter().all(|v| *v == NOT_WRITTEN), "aucun pixel ne doit être écrit en cas d'erreur");
    }

    // Table BLA comme BuildBlaTable de Fractal.Bla (ε = 2^-44), pour les tests : un pas au point Z de l'orbite donne
    // A = 2Z (Mandelbrot, Julia) ou p·Z^(p-1) (Multibrot), B = 1 (0 pour Julia).
    fn build_bla(formula: Formula, orbit: &[f64], max_delta_c: f64) -> Vec<f64> {
        let epsilon = 2.0_f64.powi(-44);
        let steps = orbit.len() / 2 - 1;
        let mut starts = vec![0_usize];
        while bla_level_entries(steps, starts.len() - 1) > 1 {
            let level = starts.len() - 1;
            starts.push(starts[level] + bla_level_entries(steps, level));
        }
        let mut data = vec![0.0_f64; (starts[starts.len() - 1] + 1) * BLA_ENTRY];
        for j in 0..steps {
            let (zx, zy) = (orbit[2 * (j + 1)], orbit[2 * (j + 1) + 1]);
            let (mut ax, mut ay, bx, ratio) = match formula {
                Formula::Multibrot { power, .. } => {
                    let p = power.round() as usize;
                    let (mut px, mut py) = (1.0, 0.0);
                    for _ in 2..=p {
                        let t = px * zx - py * zy;
                        py = px * zy + py * zx;
                        px = t;
                    }
                    (px, py, 1.0, 1.0 / f64::max(1.0, (p as f64 - 1.0) / 2.0))
                }
                Formula::Julia { .. } => (zx, zy, 0.0, 1.0),
                _ => (zx, zy, 1.0, 1.0),
            };
            match formula {
                Formula::Multibrot { power, .. } => {
                    ax *= power.round();
                    ay *= power.round();
                }
                _ => {
                    ax *= 2.0;
                    ay *= 2.0;
                }
            }
            let o = j * BLA_ENTRY;
            let r = (epsilon * zx.hypot(zy) * ratio - bx * max_delta_c) / (ax.hypot(ay) + 1.0);
            data[o..o + BLA_ENTRY].copy_from_slice(&[ax, ay, bx, 0.0, r.max(0.0), 1.0]);
        }
        for level in 1..starts.len() {
            let previous = bla_level_entries(steps, level - 1);
            for j in 0..bla_level_entries(steps, level) {
                let x = (starts[level - 1] + 2 * j) * BLA_ENTRY;
                let dst = (starts[level] + j) * BLA_ENTRY;
                let merged = if 2 * j + 1 < previous {
                    let y = x + BLA_ENTRY;
                    let (a, b) = (&data[x..x + BLA_ENTRY], &data[y..y + BLA_ENTRY]);
                    let abs_ax = a[0].hypot(a[1]);
                    let ry = if abs_ax == 0.0 {
                        0.0
                    } else {
                        ((b[4] - a[2].hypot(a[3]) * max_delta_c) / abs_ax).max(0.0)
                    };
                    [
                        b[0] * a[0] - b[1] * a[1],
                        b[0] * a[1] + b[1] * a[0],
                        b[0] * a[2] - b[1] * a[3] + b[2],
                        b[0] * a[3] + b[1] * a[2] + b[3],
                        a[4].min(ry),
                        a[5] + b[5],
                    ]
                } else {
                    let mut copy = [0.0; BLA_ENTRY];
                    copy.copy_from_slice(&data[x..x + BLA_ENTRY]);
                    copy
                };
                data[dst..dst + BLA_ENTRY].copy_from_slice(&merged);
            }
        }
        data
    }

    #[allow(clippy::too_many_arguments)]
    fn call_perturbed_bla(
        formula: i32,
        params: &[f64],
        max_iter: i32,
        orbit: &[f64],
        bla: &[f64],
        critical: &[f64],
        crit_bla: &[f64],
        dcx0: f64,
        ddx: f64,
        dcy: f64,
        count: usize,
    ) -> (i32, Vec<f32>) {
        let mut out = vec![NOT_WRITTEN; count];
        let code = unsafe {
            if critical.is_empty() {
                fk_compute_row_perturbed_bla(
                    formula,
                    params.as_ptr(),
                    params.len() as i32,
                    max_iter,
                    orbit.as_ptr(),
                    (orbit.len() / 2) as i32,
                    bla.as_ptr(),
                    bla.len() as i32,
                    dcx0,
                    ddx,
                    dcy,
                    count as i32,
                    out.as_mut_ptr(),
                )
            } else {
                fk_compute_row_perturbed2_bla(
                    formula,
                    params.as_ptr(),
                    params.len() as i32,
                    max_iter,
                    orbit.as_ptr(),
                    (orbit.len() / 2) as i32,
                    bla.as_ptr(),
                    bla.len() as i32,
                    critical.as_ptr(),
                    (critical.len() / 2) as i32,
                    crit_bla.as_ptr(),
                    crit_bla.len() as i32,
                    dcx0,
                    ddx,
                    dcy,
                    count as i32,
                    out.as_mut_ptr(),
                )
            }
        };
        (code, out)
    }

    const BLA_MAX_ITER: i32 = 3000;
    const BLA_ROWS: usize = 36;
    const BLA_COLUMNS: usize = 64;

    // Avec et sans BLA, sur une grille profonde (largeur 1e-20, sinon ε·|Z| < |δc| et tous les rayons sont nuls)
    // autour d'une référence qui ne s'échappe pas : 99,9 % de verdicts identiques et 99 % des valeurs extérieures à
    // 1e-2 près (seuils de la conception). La table doit permettre des sauts (rayons non nuls aux niveaux élevés).
    #[test]
    fn bla_row_matches_plain() {
        let rabbit = [-0.12, 0.75];
        // (formule, paramètres, référence, largeur de la grille)
        let cases: [(i32, &[f64], f64, f64, f64); 3] = [
            (MANDELBROT, &[], -0.75, 0.0, 1e-20),
            (MULTIBROT, &[3.0], 0.3, 0.3, 1e-20),
            (JULIA, &rabbit, 0.0, 0.0, 1e-20),
        ];
        for &(id, params, rx, ry, width) in &cases {
            let formula = Formula::from_id(id, params).unwrap();
            let orbit = reference_orbit(formula, BLA_MAX_ITER, rx, ry);
            assert!(orbit.len() / 2 > BLA_MAX_ITER as usize, "formule {} : la référence s'échappe", id);
            let critical = if id == JULIA { julia_orbit(BLA_MAX_ITER, 0.0, 0.0, rabbit[0], rabbit[1]) } else { Vec::new() };
            let pixel = width / BLA_COLUMNS as f64;
            let max_delta_c = if id == JULIA { 0.0 } else { width };
            let bla = build_bla(formula, &orbit, max_delta_c);
            let crit_bla = if critical.is_empty() { Vec::new() } else { build_bla(formula, &critical, 0.0) };
            let table = Bla::new(&bla, orbit.len() / 2).unwrap();
            let top = (table.starts[3]..table.starts[4]).any(|j| table.data[j * BLA_ENTRY + 4] > 0.0);
            assert!(top, "formule {} : aucun saut de 8 pas possible", id);
            let (mut same, mut exterior, mut close) = (0, 0, 0);
            for row in 0..BLA_ROWS {
                let dcy = (row as f64 - BLA_ROWS as f64 / 2.0) * pixel;
                let dcx0 = -width / 2.0;
                let (code, plain) = call_perturbed2(id, params, BLA_MAX_ITER, &orbit, &critical, dcx0, pixel, dcy, BLA_COLUMNS);
                assert_eq!(code, FK_OK);
                let (code, fast) = call_perturbed_bla(
                    id, params, BLA_MAX_ITER, &orbit, &bla, &critical, &crit_bla, dcx0, pixel, dcy, BLA_COLUMNS,
                );
                assert_eq!(code, FK_OK);
                for (a, b) in plain.iter().zip(fast.iter()) {
                    if (*a < 0.0) == (*b < 0.0) {
                        same += 1;
                    }
                    if *a >= 0.0 && *b >= 0.0 {
                        exterior += 1;
                        if (a - b).abs() <= 1e-2 {
                            close += 1;
                        }
                    }
                }
            }
            let total = (BLA_ROWS * BLA_COLUMNS) as f64;
            assert!(same as f64 >= 0.999 * total, "formule {} : {} verdicts identiques", id, same);
            assert!(close as f64 >= 0.99 * exterior as f64, "formule {} : {} proches sur {}", id, close, exterior);
        }
    }

    // Un saut donne le même δ, à 1e-6 près en relatif, que les pas perturbés exacts qu'il remplace : vérifie A, B (terme
    // en δc), les signes et les indices de la table, pour les trois formules.
    #[test]
    fn bla_jump_matches_exact_steps() {
        let rabbit = [-0.12, 0.75];
        let cases: [(i32, &[f64], f64, f64); 3] =
            [(MANDELBROT, &[], -0.75, 0.0), (MULTIBROT, &[3.0], 0.3, 0.3), (JULIA, &rabbit, 0.0, 0.0)];
        let (dcx, dcy) = (3e-22, -2e-22);
        for &(id, params, rx, ry) in &cases {
            let formula = Formula::from_id(id, params).unwrap();
            let orbit = reference_orbit(formula, BLA_MAX_ITER, rx, ry);
            let (cx, cy) = if id == JULIA { (0.0, 0.0) } else { (dcx, dcy) };
            let bla = build_bla(formula, &orbit, 1e-21);
            let table = Bla::new(&bla, orbit.len() / 2).unwrap();
            // m = 1 : toutes les entrées de niveau élevé sont alignées
            let start = (1e-22, 5e-23);
            let mut delta = start;
            let len = table.jump(1, 1, BLA_MAX_ITER, orbit.len() / 2, &mut delta, cx, cy);
            assert!(len >= 8, "formule {} : saut de {} pas seulement", id, len);
            let (mut dx, mut dy) = start;
            for m in 1..1 + len {
                let (zx, zy) = (orbit[2 * m], orbit[2 * m + 1]);
                // pas perturbé exact, sans soustraction de grands nombres : (Z + δ)^p - Z^p + δc développé
                let (d2x, d2y) = (dx * dx - dy * dy, 2.0 * dx * dy);
                let (nx, ny) = if id == MULTIBROT {
                    // 3·Z²·δ + 3·Z·δ² + δ³
                    let (z2x, z2y) = (zx * zx - zy * zy, 2.0 * zx * zy);
                    let (d3x, d3y) = (d2x * dx - d2y * dy, d2x * dy + d2y * dx);
                    (
                        3.0 * (z2x * dx - z2y * dy) + 3.0 * (zx * d2x - zy * d2y) + d3x,
                        3.0 * (z2x * dy + z2y * dx) + 3.0 * (zx * d2y + zy * d2x) + d3y,
                    )
                } else {
                    // 2·Z·δ + δ²
                    (2.0 * (zx * dx - zy * dy) + d2x, 2.0 * (zx * dy + zy * dx) + d2y)
                };
                dx = nx + cx;
                dy = ny + cy;
            }
            let error = (delta.0 - dx).hypot(delta.1 - dy);
            assert!(error <= 1e-6 * dx.hypot(dy), "formule {} : écart {} pour |δ| = {}", id, error, dx.hypot(dy));
        }
    }

    // Table vide (longueur 0) : exactement le calcul sans BLA
    #[test]
    fn bla_empty_table_is_exact() {
        let orbit = reference_orbit(Formula::Mandelbrot, BLA_MAX_ITER, -0.75, 0.0);
        let (code, plain) = call_perturbed(MANDELBROT, &[], BLA_MAX_ITER, &orbit, -1e-3, 3e-5, 2e-4, 64);
        assert_eq!(code, FK_OK);
        let (code, fast) = call_perturbed_bla(MANDELBROT, &[], BLA_MAX_ITER, &orbit, &[], &[], &[], -1e-3, 3e-5, 2e-4, 64);
        assert_eq!(code, FK_OK);
        assert_eq!(plain, fast);
    }

    // Taille de table qui ne correspond pas à l'orbite : argument invalide, aucun pixel écrit
    #[test]
    fn bla_table_bad_length_is_error() {
        let orbit = reference_orbit(Formula::Mandelbrot, BLA_MAX_ITER, -0.75, 0.0);
        let bla = build_bla(Formula::Mandelbrot, &orbit, 1e-3);
        let short = &bla[..bla.len() - BLA_ENTRY];
        let (code, out) = call_perturbed_bla(MANDELBROT, &[], BLA_MAX_ITER, &orbit, short, &[], &[], 0.0, 1e-5, 0.0, 4);
        assert_eq!(code, FK_INVALID_ARGUMENT);
        assert!(out.iter().all(|v| *v == NOT_WRITTEN));
        let (code, _) = call_perturbed_bla(MANDELBROT, &[], BLA_MAX_ITER, &orbit, &bla, &[], &[], 0.0, 1e-5, 0.0, 4);
        assert_eq!(code, FK_OK);
    }
}
