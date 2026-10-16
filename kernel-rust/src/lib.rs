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
