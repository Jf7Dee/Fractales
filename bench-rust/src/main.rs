// Banc d'essai Rust : mêmes scènes, même algorithme et même mise en page que bench\FractalesBench.dpr.
// Différence assumée : f64 (64 bits, SSE2) au lieu de l'Extended 80 bits de Delphi.
//
// Lancer avec :  cargo run --release

use rayon::prelude::*;
use std::time::Instant;

const WIDTH: usize = 1920;
const HEIGHT: usize = 1080;
const RUNS: usize = 5;
const ESCAPE_RADIUS2: f64 = 65536.0; // rayon d'échappement 256, comme Fractal.Formulas
const INSIDE: f32 = -1.0;

#[derive(Clone, Copy)]
enum Kind {
    Mandelbrot,
    Julia { cx: f64, cy: f64 },
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

fn iterate(kind: Kind, max_iter: u32, cx: f64, cy: f64) -> f32 {
    match kind {
        Kind::Mandelbrot => {
            // cardioïde principale et bulbe de période 2 : intérieur garanti
            let q = (cx - 0.25) * (cx - 0.25) + cy * cy;
            if q * (q + (cx - 0.25)) <= 0.25 * cy * cy || (cx + 1.0) * (cx + 1.0) + cy * cy <= 0.0625 {
                return INSIDE;
            }
            let (mut x, mut y) = (0.0_f64, 0.0_f64);
            for n in 0..max_iter {
                let (x2, y2) = (x * x, y * y);
                if x2 + y2 > ESCAPE_RADIUS2 {
                    return smooth_value(n, x2 + y2);
                }
                y = 2.0 * x * y + cy;
                x = x2 - y2 + cx;
            }
            INSIDE
        }
        Kind::Julia { cx: jx, cy: jy } => {
            let (mut x, mut y) = (cx, cy);
            for n in 0..max_iter {
                let (x2, y2) = (x * x, y * y);
                if x2 + y2 > ESCAPE_RADIUS2 {
                    return smooth_value(n, x2 + y2);
                }
                y = 2.0 * x * y + jy;
                x = x2 - y2 + jx;
            }
            INSIDE
        }
    }
}

// Même convention que TViewport.PixelToComplex : centre du pixel en +0,5, axe imaginaire vers le haut.
fn render(scene: &Scene, buffer: &mut [f32], is_parallel: bool) {
    let pixel_size = scene.width / WIDTH as f64;
    let render_row = |(py, row): (usize, &mut [f32])| {
        let y = scene.center_y - (py as f64 + 0.5 - HEIGHT as f64 / 2.0) * pixel_size;
        for (px, value) in row.iter_mut().enumerate() {
            let x = scene.center_x + (px as f64 + 0.5 - WIDTH as f64 / 2.0) * pixel_size;
            *value = iterate(scene.kind, scene.max_iter, x, y);
        }
    };
    if is_parallel {
        buffer.par_chunks_mut(WIDTH).enumerate().for_each(render_row);
    } else {
        buffer.chunks_mut(WIDTH).enumerate().for_each(render_row);
    }
}

fn measure_scene(scene: &Scene, is_parallel: bool) -> Measure {
    let mut buffer = vec![0.0_f32; WIDTH * HEIGHT];
    let mut times: Vec<f64> = Vec::with_capacity(RUNS);
    for _ in 0..RUNS {
        let start = Instant::now();
        render(scene, &mut buffer, is_parallel);
        times.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let inside_count = buffer.iter().filter(|v| **v < 0.0).count();
    let checksum: f64 = buffer.iter().filter(|v| **v >= 0.0).map(|v| *v as f64).sum();
    Measure { median_ms: times[(RUNS - 1) / 2], inside_count, checksum }
}

fn print_line(scene: &Scene, threads: usize, m: &Measure) {
    println!(
        "{:<16} | {:>7} | {:>8} | {:>10.1} | {:>10} | {:>16.1}",
        scene.name, scene.max_iter, threads, m.median_ms, m.inside_count, m.checksum
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
    println!(
        "Rust (f64 64 bits, SSE2) - {} x {}, mediane de {} rendus, {} coeurs logiques",
        WIDTH, HEIGHT, RUNS, threads
    );
    println!("Scene            | MaxIter | Threads  |   ms (med) |  Interieur |   Somme lissee");
    for scene in &scenes {
        print_line(scene, 1, &measure_scene(scene, false));
        print_line(scene, threads, &measure_scene(scene, true));
    }
}
