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
//
// Compiler la DLL 32 bits :  cargo build --release --target i686-pc-windows-msvc

use std::f64::consts::LN_2;
use std::panic::{catch_unwind, AssertUnwindSafe};
use wide::*;

pub const ABI_VERSION: u32 = 4;

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

    // Multibrot passe par exp, ln, atan2, cos et sin : calcul scalaire seulement.
    fn is_vectorizable(self) -> bool {
        !matches!(self, Formula::Multibrot { .. })
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

// Pixel d'écart (dcx, dcy) à la référence, comme IteratePerturbedCritical : `critical` = orbite critique W de Julia
// (où (dcx, dcy) est δ0), ignorée par les autres formules. Julia et Multibrot à puissance non entière n'arrivent ici
// qu'après les contrôles des exportations.
fn iterate_perturbed(formula: Formula, max_iter: i32, orbit: &[f64], critical: &[f64], dcx: f64, dcy: f64) -> f32 {
    match formula {
        Formula::Julia { .. } => iterate_perturbed_julia(max_iter, orbit, critical, dcx, dcy),
        Formula::Multibrot { power, log_power } => {
            iterate_perturbed_multibrot(max_iter, power.round() as usize, log_power, orbit, dcx, dcy)
        }
        _ => iterate_perturbed_quadratic(formula, max_iter, orbit, dcx, dcy),
    }
}

// Mandelbrot, Tricorn et Burning Ship. `orbit` = x0, y0, x1, y1, ... avec Z0 = 0 ; au moins deux points (après le
// premier pas, la boucle lit Z1).
fn iterate_perturbed_quadratic(formula: Formula, max_iter: i32, orbit: &[f64], dcx: f64, dcy: f64) -> f32 {
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
fn iterate_perturbed_multibrot(max_iter: i32, p: usize, log_power: f64, orbit: &[f64], dcx: f64, dcy: f64) -> f32 {
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
fn iterate_perturbed_julia(max_iter: i32, orbit: &[f64], critical: &[f64], dx0: f64, dy0: f64) -> f32 {
    let mut reference = orbit;
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
            reference_len = critical.len() / 2;
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
    dcx0: f64,
    ddx: f64,
    dcy: f64,
    out: &mut [f32],
) {
    for (i, value) in out.iter_mut().enumerate() {
        *value = iterate_perturbed(formula, max_iter, orbit, critical, dcx0 + i as f64 * ddx, dcy);
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
        compute_row_perturbed(formula, max_iter, orbit, &[], dcx0, ddx, dcy, out);
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
        compute_row_perturbed(formula, max_iter, orbit, critical, dcx0, ddx, dcy, out);
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
    fn abi_version_is_4() {
        assert_eq!(fk_abi_version(), 4);
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
}
