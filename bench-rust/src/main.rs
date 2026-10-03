// Banc d'essai Rust : mêmes scènes, même algorithme et même mise en page que bench\FractalesBench.dpr.
// Différence assumée : f64 (64 bits) au lieu de l'Extended 80 bits de Delphi.
//
// Deux façons de calculer :
//   - scalaire : un pixel à la fois, comme Delphi ;
//   - SIMD f64x4 : quatre pixels voisins à la fois (crate `wide`). Les instructions réellement utilisées
//     dépendent de la compilation : SSE2 par défaut (2 × 2 pixels), AVX/AVX2 avec RUSTFLAGS=-C target-cpu=native.
// En parallèle, chaque ligne est une tâche séparée : rayon les distribue aux cœurs libres, comme la file de
// tuiles du moteur Delphi.
//
// Lancer avec :  cargo run --release

use rayon::prelude::*;
use std::time::Instant;
use wide::*;

const WIDTH: usize = 1920;
const HEIGHT: usize = 1080;
const RUNS: usize = 5;
const ESCAPE_RADIUS2: f64 = 65536.0; // rayon d'échappement 256, comme Fractal.Formulas
const INSIDE: f32 = -1.0;
const LANES: usize = 4;
const ALL_LANES_DONE: u32 = 0b1111;

#[derive(Clone, Copy)]
enum Kind {
    Mandelbrot,
    Julia { cx: f64, cy: f64 },
}

#[derive(Clone, Copy)]
enum Mode {
    Scalar,
    Simd,
}

struct Scene {
    name: &'static str,
    kind: Kind,
    center_x: f64,
    center_y: f64,
    width: f64,
    max_iter: u32,
}

struct Measure {
    median_ms: f64,
    inside_count: usize,
    checksum: f64,
}

// Valeur lissée, identique à TFractalFormula.SmoothValue (puissance 2).
fn smooth_value(n: u32, modulus2: f64) -> f32 {
    let mu = n as f64 + 1.0 - (0.5 * modulus2.ln()).ln() / std::f64::consts::LN_2;
    if mu < 0.0 { 0.0 } else { mu as f32 }
}

// Cardioïde principale et bulbe de période 2 : intérieur garanti, inutile d'itérer.
fn is_in_main_bulbs(cx: f64, cy: f64) -> bool {
    let q = (cx - 0.25) * (cx - 0.25) + cy * cy;
    q * (q + (cx - 0.25)) <= 0.25 * cy * cy || (cx + 1.0) * (cx + 1.0) + cy * cy <= 0.0625
}

fn iterate(kind: Kind, max_iter: u32, cx: f64, cy: f64) -> f32 {
    let (mut x, mut y, kx, ky) = match kind {
        Kind::Mandelbrot => {
            if is_in_main_bulbs(cx, cy) {
                return INSIDE;
            }
            (0.0, 0.0, cx, cy)
        }
        Kind::Julia { cx: jx, cy: jy } => (cx, cy, jx, jy),
    };
    for n in 0..max_iter {
        let (x2, y2) = (x * x, y * y);
        if x2 + y2 > ESCAPE_RADIUS2 {
            return smooth_value(n, x2 + y2);
        }
        y = 2.0 * x * y + ky;
        x = x2 - y2 + kx;
    }
    INSIDE
}

// Quatre pixels d'une même ligne à la fois. Chaque voie s'arrête à son propre échappement ;
// les voies déjà échappées continuent de calculer pour rien (le coût du SIMD) mais ne sont plus lues.
fn iterate4(kind: Kind, max_iter: u32, cxs: [f64; LANES], cy: f64) -> [f32; LANES] {
    let mut result = [INSIDE; LANES];
    let mut done: u32 = 0;
    let (mut x, mut y, kx, ky) = match kind {
        Kind::Mandelbrot => {
            for (lane, &cx) in cxs.iter().enumerate() {
                if is_in_main_bulbs(cx, cy) {
                    done |= 1 << lane;
                }
            }
            (f64x4::splat(0.0), f64x4::splat(0.0), f64x4::new(cxs), f64x4::splat(cy))
        }
        Kind::Julia { cx: jx, cy: jy } => (f64x4::new(cxs), f64x4::splat(cy), f64x4::splat(jx), f64x4::splat(jy)),
    };
    if done == ALL_LANES_DONE {
        return result;
    }
    let radius2 = f64x4::splat(ESCAPE_RADIUS2);
    let two = f64x4::splat(2.0);
    for n in 0..max_iter {
        let x2 = x * x;
        let y2 = y * y;
        let modulus2 = x2 + y2;
        let escaped = (modulus2.cmp_gt(radius2).move_mask() as u32) & !done;
        if escaped != 0 {
            let values = modulus2.to_array();
            for lane in 0..LANES {
                if escaped & (1 << lane) != 0 {
                    result[lane] = smooth_value(n, values[lane]);
                }
            }
            done |= escaped;
            if done == ALL_LANES_DONE {
                break;
            }
        }
        y = two * x * y + ky;
        x = x2 - y2 + kx;
    }
    result
}

// Même convention que TViewport.PixelToComplex : centre du pixel en +0,5, axe imaginaire vers le haut.
fn pixel_x(scene: &Scene, px: usize, pixel_size: f64) -> f64 {
    scene.center_x + (px as f64 + 0.5 - WIDTH as f64 / 2.0) * pixel_size
}

fn render_row(scene: &Scene, mode: Mode, py: usize, row: &mut [f32]) {
    let pixel_size = scene.width / WIDTH as f64;
    let y = scene.center_y - (py as f64 + 0.5 - HEIGHT as f64 / 2.0) * pixel_size;
    match mode {
        Mode::Scalar => {
            for (px, value) in row.iter_mut().enumerate() {
                *value = iterate(scene.kind, scene.max_iter, pixel_x(scene, px, pixel_size), y);
            }
        }
        Mode::Simd => {
            for (chunk, values) in row.chunks_exact_mut(LANES).enumerate() {
                let base = chunk * LANES;
                let cxs = [
                    pixel_x(scene, base, pixel_size),
                    pixel_x(scene, base + 1, pixel_size),
                    pixel_x(scene, base + 2, pixel_size),
                    pixel_x(scene, base + 3, pixel_size),
                ];
                values.copy_from_slice(&iterate4(scene.kind, scene.max_iter, cxs, y));
            }
        }
    }
}

fn render(scene: &Scene, buffer: &mut [f32], mode: Mode, is_parallel: bool) {
    if is_parallel {
        // with_max_len(1) : une tâche par ligne, distribuée aux cœurs libres (équilibrage de charge)
        buffer
            .par_chunks_mut(WIDTH)
            .with_max_len(1)
            .enumerate()
            .for_each(|(py, row)| render_row(scene, mode, py, row));
    } else {
        buffer
            .chunks_mut(WIDTH)
            .enumerate()
            .for_each(|(py, row)| render_row(scene, mode, py, row));
    }
}

fn measure_scene(scene: &Scene, mode: Mode, is_parallel: bool) -> Measure {
    let mut buffer = vec![0.0_f32; WIDTH * HEIGHT];
    let mut times: Vec<f64> = Vec::with_capacity(RUNS);
    for _ in 0..RUNS {
        let start = Instant::now();
        render(scene, &mut buffer, mode, is_parallel);
        times.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let inside_count = buffer.iter().filter(|v| **v < 0.0).count();
    let checksum: f64 = buffer.iter().filter(|v| **v >= 0.0).map(|v| *v as f64).sum();
    Measure { median_ms: times[(RUNS - 1) / 2], inside_count, checksum }
}

fn print_line(scene: &Scene, mode_name: &str, threads: usize, m: &Measure) {
    println!(
        "{:<16} | {:<9} | {:>7} | {:>7} | {:>10.1} | {:>10} | {:>16.1}",
        scene.name, mode_name, scene.max_iter, threads, m.median_ms, m.inside_count, m.checksum
    );
}

fn main() {
    let scenes = [
        Scene { name: "Vue d'ensemble", kind: Kind::Mandelbrot, center_x: -0.5, center_y: 0.0, width: 3.0, max_iter: 1000 },
        Scene {
            name: "Vue profonde",
            kind: Kind::Mandelbrot,
            center_x: -0.743643887037151,
            center_y: 0.131825904205330,
            width: 1e-9,
            max_iter: 5000,
        },
        Scene {
            name: "Interieur lourd",
            kind: Kind::Julia { cx: 0.0, cy: 0.0 },
            center_x: 0.0,
            center_y: 0.0,
            width: 3.0,
            max_iter: 2000,
        },
    ];
    let threads = rayon::current_num_threads();
    let avx = if cfg!(target_feature = "avx") { "AVX actif" } else { "sans AVX (SSE2)" };
    println!(
        "Rust (f64 64 bits, {}) - {} x {}, mediane de {} rendus, {} coeurs logiques",
        avx, WIDTH, HEIGHT, RUNS, threads
    );
    println!("Scene            | Mode      | MaxIter | Threads |   ms (med) |  Interieur |   Somme lissee");
    for scene in &scenes {
        print_line(scene, "scalaire", 1, &measure_scene(scene, Mode::Scalar, false));
        print_line(scene, "SIMD x4", 1, &measure_scene(scene, Mode::Simd, false));
        print_line(scene, "scalaire", threads, &measure_scene(scene, Mode::Scalar, true));
        print_line(scene, "SIMD x4", threads, &measure_scene(scene, Mode::Simd, true));
    }
}
