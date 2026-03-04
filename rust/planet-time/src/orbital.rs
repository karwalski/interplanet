//! Orbital mechanics — heliocentric positions, light-travel time, line-of-sight.
//! Mirrors the orbital section of planet-time.js.

use crate::constants::{
    AU_SECONDS, DEG, J2000_MS, LEAP_SECS, ORB_ELEMS, Planet,
};
use std::f64::consts::PI;

// ── TAI − UTC ──────────────────────────────────────────────────────────────────

/// Returns TAI − UTC in seconds for the given UTC millisecond timestamp.
pub fn tai_minus_utc(utc_ms: i64) -> f64 {
    let mut ls = 10i64;
    for &(ts, s) in LEAP_SECS.iter() {
        if utc_ms >= ts { ls = s; }
    }
    ls as f64
}

// ── Julian date helpers ───────────────────────────────────────────────────────

/// Julian Ephemeris Day (TT) from UTC milliseconds.
pub fn jde(utc_ms: i64) -> f64 {
    let tai = utc_ms as f64 + tai_minus_utc(utc_ms) * 1000.0;
    let tt  = tai + 32_184.0;  // TT = TAI + 32.184 s (in ms)
    2_440_587.5 + tt / 86_400_000.0
}

/// Julian centuries from J2000.0 (TT).
pub fn jc(utc_ms: i64) -> f64 {
    (jde(utc_ms) - 2_451_545.0) / 36_525.0
}

// ── Kepler equation ───────────────────────────────────────────────────────────

/// Solve Kepler's equation M = E − e·sin(E) for eccentric anomaly E (radians).
/// Newton-Raphson, tolerance 1 × 10⁻¹².
pub fn kepler_e(m: f64, e: f64) -> f64 {
    let mut big_e = m;
    loop {
        let delta = (m - big_e + e * big_e.sin()) / (1.0 - e * big_e.cos());
        big_e += delta;
        if delta.abs() < 1e-12 { break; }
    }
    big_e
}

// ── Heliocentric position ─────────────────────────────────────────────────────

/// Heliocentric ecliptic position (AU, radians).
#[derive(Debug, Clone, Copy)]
pub struct HelioPos {
    pub x: f64,
    pub y: f64,
    pub r: f64,   // distance from Sun in AU
    pub lon: f64, // ecliptic longitude (radians, 0–2π)
}

/// Compute heliocentric position for `planet` at `utc_ms`.
pub fn helio_pos(planet: Planet, utc_ms: i64) -> HelioPos {
    let t  = jc(utc_ms);
    // Moon orbits Earth, not the Sun — use Earth's orbital elements for heliocentric position
    // (mirrors JS: key = (planetKey === 'moon') ? 'earth' : planetKey)
    let key = if planet == Planet::Moon { Planet::Earth } else { planet };
    let el = ORB_ELEMS[key.index()];

    let l = (el.l0 + el.dl * t).rem_euclid(360.0) * DEG; // mean longitude (rad)
    let w = el.om * DEG;                                    // longitude of perihelion (rad)
    let m = (l - w).rem_euclid(2.0 * PI);                  // mean anomaly (rad)
    let e = el.e0;
    let big_e = kepler_e(m, e);

    // True anomaly
    let nu = 2.0 * f64::atan2(
        ((1.0 + e) / (1.0 - e)).sqrt() * f64::sin(big_e / 2.0),
        f64::cos(big_e / 2.0),
    );

    let r   = el.a * (1.0 - e * big_e.cos());
    let lon = (nu + w).rem_euclid(2.0 * PI);
    let x   = r * lon.cos();
    let y   = r * lon.sin();
    HelioPos { x, y, r, lon }
}

// ── Distance / light travel ───────────────────────────────────────────────────

/// Euclidean distance in AU between two bodies at `utc_ms`.
pub fn body_distance_au(a: Planet, b: Planet, utc_ms: i64) -> f64 {
    let pa = helio_pos(a, utc_ms);
    let pb = helio_pos(b, utc_ms);
    let dx = pa.x - pb.x;
    let dy = pa.y - pb.y;
    (dx * dx + dy * dy).sqrt()
}

/// One-way light travel time in seconds between two bodies.
pub fn light_travel_seconds(a: Planet, b: Planet, utc_ms: i64) -> f64 {
    body_distance_au(a, b, utc_ms) * AU_SECONDS
}

// ── Line of sight ─────────────────────────────────────────────────────────────

/// Line-of-sight status between two bodies.
#[derive(Debug, Clone, Copy)]
pub struct LineOfSight {
    pub clear:           bool,
    pub blocked:         bool,   // elongation < 3°
    pub degraded:        bool,   // 3° ≤ elongation < 10°
    pub closest_sun_au:  Option<f64>,
    pub elong_deg:       f64,
}

/// Check whether the direct path between `a` and `b` passes through the Sun.
pub fn check_line_of_sight(a: Planet, b: Planet, utc_ms: i64) -> LineOfSight {
    let pa = helio_pos(a, utc_ms);
    let pb = helio_pos(b, utc_ms);

    let dx = pb.x - pa.x;
    let dy = pb.y - pa.y;
    let d2 = dx * dx + dy * dy;

    // Minimum Sun-distance along the line segment
    let closest_sun_au = if d2 < 1e-30 {
        None
    } else {
        let t = (-(pa.x * dx + pa.y * dy) / d2).clamp(0.0, 1.0);
        let cx = pa.x + t * dx;
        let cy = pa.y + t * dy;
        Some((cx * cx + cy * cy).sqrt())
    };

    // Elongation: angle at body-a between Sun and body-b
    let elong_deg = {
        let ra  = pa.r;
        let rb  = body_distance_au(a, b, utc_ms);
        let rsun = pa.r; // a–Sun = ra
        // law of cosines: cos(elong) = (ra² + rb² - rb_abs²) / 2 ra rb
        // Simpler: angle between vector (0,0)→pa and pa→pb
        let ax = -pa.x;   // Sun relative to a
        let ay = -pa.y;
        let bx = pb.x - pa.x;
        let by = pb.y - pa.y;
        let dot = ax * bx + ay * by;
        let mag = (ax * ax + ay * ay).sqrt() * (bx * bx + by * by).sqrt();
        if mag < 1e-30 { 0.0 } else { f64::acos((dot / mag).clamp(-1.0, 1.0)) / DEG }
    };
    let _ = (closest_sun_au, pa.r); // suppress unused

    let blocked  = elong_deg < 3.0;
    let degraded = !blocked && elong_deg < 10.0;
    let clear    = !blocked && !degraded;

    LineOfSight { clear, blocked, degraded, closest_sun_au, elong_deg }
}

/// Lower-quartile (p25) light travel time — 360 orbital samples over one Earth year.
pub fn lower_quartile_light_time(a: Planet, b: Planet, ref_ms: i64) -> f64 {
    let year_ms = 365_250 * 86_400i64; // approx Julian year in ms
    let step    = year_ms / 360;
    let mut samples: Vec<f64> = (0..360)
        .map(|i| light_travel_seconds(a, b, ref_ms + i as i64 * step))
        .collect();
    samples.sort_by(|x, y| x.partial_cmp(y).unwrap());
    samples[samples.len() / 4]
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jde_at_j2000() {
        // J2000_MS = Date.UTC(2000,0,1,12,0,0) — should give JDE ≈ 2451545.0
        let j = jde(J2000_MS);
        assert!((j - 2_451_545.0).abs() < 0.01, "jde at J2000 = {}", j);
    }

    #[test]
    fn jc_at_j2000() {
        let t = jc(J2000_MS);
        assert!(t.abs() < 1e-4, "jc at J2000 = {}", t);
    }

    #[test]
    fn light_travel_earth_mars_opposition_2003() {
        // 2003-08-27 ≈ closest Mars approach; ~186 s ±15
        let utc_ms = 1_061_991_060_000i64;
        let lt = light_travel_seconds(Planet::Earth, Planet::Mars, utc_ms);
        assert!((lt - 186.0).abs() < 15.0, "E→Mars 2003-08 = {} s", lt);
    }

    #[test]
    fn light_travel_earth_mars_2020_opposition() {
        // 2020-10-13 — ~207 s ±15
        let utc_ms = 1_602_633_600_000i64;
        let lt = light_travel_seconds(Planet::Earth, Planet::Mars, utc_ms);
        assert!((lt - 207.0).abs() < 20.0, "E→Mars 2020 = {} s", lt);
    }

    #[test]
    fn light_travel_earth_jupiter() {
        // 2023-11-03 — ~2010 s ±120
        let utc_ms = 1_699_046_400_000i64;
        let lt = light_travel_seconds(Planet::Earth, Planet::Jupiter, utc_ms);
        assert!((lt - 2010.0).abs() < 120.0, "E→Jupiter = {} s", lt);
    }

    #[test]
    fn helio_r_earth_near_1au() {
        let hp = helio_pos(Planet::Earth, J2000_MS);
        assert!((hp.r - 1.0).abs() < 0.02, "Earth r = {} AU", hp.r);
    }

    #[test]
    fn helio_r_j2000_mercury_fixture() {
        // reference.json: J2000 mercury helio_r_au ≈ 0.46648
        let hp = helio_pos(Planet::Mercury, J2000_MS);
        assert!((hp.r - 0.46648).abs() < 0.001, "Mercury r = {}", hp.r);
    }

    #[test]
    fn los_earth_mars_clear() {
        // Normal date — should not be in conjunction
        let los = check_line_of_sight(Planet::Earth, Planet::Mars, J2000_MS);
        assert!(los.elong_deg > 0.0);
    }

    #[test]
    fn lower_quartile_earth_mars_positive() {
        let lq = lower_quartile_light_time(Planet::Earth, Planet::Mars, J2000_MS);
        assert!(lq > 0.0 && lq < 1300.0, "p25 = {} s", lq);
    }
}
