//! Planetary time calculation — mirrors getPlanetTime / getMTC in planet-time.js.

use crate::constants::{
    EARTH_DAY_MS, MARS_EPOCH_MS, MARS_SOL_MS, Planet,
};

// ── PlanetTime ────────────────────────────────────────────────────────────────

/// All time fields for a single body at a moment in UTC.
#[derive(Debug, Clone)]
pub struct PlanetTime {
    pub hour:          i32,
    pub minute:        i32,
    pub second:        i32,
    pub local_hour:    f64,   // fractional hour (0.0–24.0)
    pub day_fraction:  f64,   // 0.0–1.0 through current solar day
    pub day_number:    i64,   // days since body epoch
    pub day_in_year:   i64,   // 0-based day within the body's "year"
    pub year_number:   i64,
    pub period_in_week: i64,  // which shift within the body's work-week (0-based)
    pub is_work_period: bool,
    pub is_work_hour:   bool,
    pub time_str:       String, // "HH:MM"
    pub time_str_full:  String, // "HH:MM:SS"
    pub sol_in_year:    Option<i64>, // Mars only
    pub sols_per_year:  Option<i64>, // Mars only
    pub zone_id:        Option<String>, // e.g. "AMT+4"; None for Earth
}

/// MTC — Mars Coordinated Time.
#[derive(Debug, Clone)]
pub struct MTC {
    pub sol:     i64,
    pub hour:    i32,
    pub minute:  i32,
    pub second:  i32,
    pub mtc_str: String,
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn pad2(n: i32) -> String { format!("{:02}", n) }

/// Positive modulo — always returns a non-negative result.
fn pos_mod(a: i64, b: i64) -> i64 {
    ((a % b) + b) % b
}

fn pos_mod_f(a: f64, b: f64) -> f64 {
    ((a % b) + b) % b
}

// ── Zone ID helpers ───────────────────────────────────────────────────────────

/// Returns the interplanetary time zone prefix for a body, or `None` for Earth.
fn zone_prefix(planet: Planet) -> Option<&'static str> {
    match planet {
        Planet::Mars    => Some("AMT"),
        Planet::Moon    => Some("LMT"),
        Planet::Mercury => Some("MMT"),
        Planet::Venus   => Some("VMT"),
        Planet::Jupiter => Some("JMT"),
        Planet::Saturn  => Some("SMT"),
        Planet::Uranus  => Some("UMT"),
        Planet::Neptune => Some("NMT"),
        Planet::Earth   => None,
    }
}

/// Builds a zone ID string from a prefix and an integer offset.
/// offset >= 0 → "PREFIX+N"; offset < 0 → "PREFIX-N".
fn build_zone_id(prefix: &str, offset: i64) -> String {
    if offset >= 0 {
        format!("{}+{}", prefix, offset)
    } else {
        format!("{}{}", prefix, offset)
    }
}

// ── get_planet_time ───────────────────────────────────────────────────────────

/// Compute planetary time for `planet` at `utc_ms` with an optional timezone
/// offset in fractional hours (default 0.0).
pub fn get_planet_time(planet: Planet, utc_ms: i64, tz_offset_h: f64) -> PlanetTime {
    // Moon uses Earth's solar day / epoch / scheduling
    let key = if planet == Planet::Moon { Planet::Earth } else { planet };
    let day_ms = key.solar_day_ms();

    // Apply tz offset (fractional hours → ms, using body's own hour length)
    let offset_ms = (tz_offset_h * day_ms as f64 / 24.0).round() as i64;
    // Mars uses its own epoch (MY0 = 1953-05-24); all other bodies use J2000
    let epoch_ms  = key.epoch_ms();
    let adjusted  = utc_ms - epoch_ms + offset_ms;

    // Day number since planet epoch (fractional)
    let day_frac   = adjusted as f64 / day_ms as f64;
    let day_number = day_frac.floor() as i64;
    let frac_day   = pos_mod_f(day_frac, 1.0); // 0–1 within current day

    // HMS — mirrors JS: localHour = dayFraction * 24
    let local_hour = frac_day * 24.0;
    let hour   = local_hour.floor() as i32;
    let minute = ((local_hour - hour as f64) * 60.0).floor() as i32;
    let second = (((local_hour - hour as f64) * 60.0 - minute as f64) * 60.0).floor() as i32;

    // Work-period / work-hour — mirrors JS getPlanetTime logic
    let period_in_week: i64;
    let is_work_period: bool;
    let is_work_hour: bool;

    if key.earth_clock_sched() {
        // Mercury/Venus: solar day >> circadian rhythm — use UTC weekday + UTC hour.
        // UTC day-of-week formula: ((floor(unix_ms / 86400000) % 7) + 3) % 7 → Mon=0..Sun=6
        let utc_day = utc_ms.div_euclid(EARTH_DAY_MS); // proper floor division
        period_in_week = ((utc_day % 7 + 7 + 3) % 7) as i64;
        is_work_period = period_in_week < key.work_periods_per_week();
        let ms_in_day = utc_ms.rem_euclid(EARTH_DAY_MS); // ms since midnight UTC
        let utc_hour = ms_in_day as f64 / 3_600_000.0;
        is_work_hour = is_work_period
            && utc_hour >= key.work_hours_start()
            && utc_hour < key.work_hours_end();
    } else {
        // Standard JS logic: period_in_week = floor(totalDays / daysPerPeriod) % periodsPerWeek
        let total_periods = day_frac / key.days_per_period();
        let raw_period = total_periods.floor() as i64;
        let ppw = key.periods_per_week();
        period_in_week = ((raw_period % ppw) + ppw) % ppw;
        is_work_period = period_in_week < key.work_periods_per_week();
        is_work_hour = is_work_period
            && local_hour >= key.work_hours_start()
            && local_hour < key.work_hours_end();
    }

    // Year / day-in-year — mirrors JS: yearLenDays = siderealYrMs / solarDayMs
    // All sidereal year values below are in Earth days, converted to planet-local days.
    let earth_days_per_yr: f64 = match key {
        Planet::Mercury => 87.9691,
        Planet::Venus   => 224.701,
        Planet::Earth   => 365.25636,
        Planet::Mars    => 686.9957,
        Planet::Jupiter => 4_332.589,
        Planet::Saturn  => 10_759.22,
        Planet::Uranus  => 30_688.5,
        Planet::Neptune => 60_195.0,
        Planet::Moon    => 365.25636,
    };
    let year_len_days = earth_days_per_yr * 86_400_000.0 / day_ms as f64;
    let year_number = (day_frac / year_len_days).floor() as i64;
    let day_in_year = (day_frac - year_number as f64 * year_len_days).floor() as i64;

    // Mars sol-in-year (uses separate Mars epoch and MARS_SOL_MS)
    let (sol_in_year, sols_per_year) = if planet == Planet::Mars {
        let sols_total = (utc_ms - MARS_EPOCH_MS) / MARS_SOL_MS;
        let siy = 669i64; // sols per Mars year
        (Some(pos_mod(sols_total, siy)), Some(siy))
    } else {
        (None, None)
    };

    let time_str      = format!("{}:{}", pad2(hour), pad2(minute));
    let time_str_full = format!("{}:{}:{}", pad2(hour), pad2(minute), pad2(second));

    // Zone ID — None for Earth; Some("PREFIX±N") for all other bodies.
    let zone_id = zone_prefix(planet).map(|prefix| {
        build_zone_id(prefix, tz_offset_h.round() as i64)
    });

    PlanetTime {
        hour, minute, second,
        local_hour, day_fraction: frac_day,
        day_number, day_in_year, year_number,
        period_in_week, is_work_period, is_work_hour,
        time_str, time_str_full,
        sol_in_year, sols_per_year,
        zone_id,
    }
}

// ── get_mtc ───────────────────────────────────────────────────────────────────

/// Mars Coordinated Time (MTC) — sol count + HMS.
pub fn get_mtc(utc_ms: i64) -> MTC {
    let elapsed = utc_ms - MARS_EPOCH_MS;
    let sol     = elapsed / MARS_SOL_MS;
    let rem_ms  = (elapsed % MARS_SOL_MS + MARS_SOL_MS) % MARS_SOL_MS;
    let rem_s   = rem_ms / 1000;
    let hour    = (rem_s / 3600) as i32;
    let minute  = ((rem_s % 3600) / 60) as i32;
    let second  = (rem_s % 60) as i32;
    let mtc_str = format!("{}:{}:{}", pad2(hour), pad2(minute), pad2(second));
    MTC { sol, hour, minute, second, mtc_str }
}

// ── get_mars_time_at_offset ───────────────────────────────────────────────────

/// Convenience wrapper for Mars with a timezone offset.
pub fn get_mars_time_at_offset(utc_ms: i64, offset_h: f64) -> PlanetTime {
    get_planet_time(Planet::Mars, utc_ms, offset_h)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::J2000_MS;

    #[test]
    fn mercury_at_j2000_hour_zero() {
        // J2000 is the epoch; Mercury time should start at 0
        let pt = get_planet_time(Planet::Mercury, J2000_MS, 0.0);
        assert_eq!(pt.hour, 0);
        assert_eq!(pt.minute, 0);
        assert_eq!(pt.second, 0);
    }

    #[test]
    fn mars_at_j2000_has_sol_info() {
        let pt = get_planet_time(Planet::Mars, J2000_MS, 0.0);
        assert!(pt.sol_in_year.is_some());
        assert_eq!(pt.sols_per_year, Some(669));
    }

    #[test]
    fn earth_at_j2000_hour_zero() {
        let pt = get_planet_time(Planet::Earth, J2000_MS, 0.0);
        assert_eq!(pt.hour, 0);
        assert_eq!(pt.minute, 0);
    }

    #[test]
    fn moon_uses_earth_day() {
        let pt_earth = get_planet_time(Planet::Earth, J2000_MS + 43_200_000, 0.0);
        let pt_moon  = get_planet_time(Planet::Moon,  J2000_MS + 43_200_000, 0.0);
        // Moon maps to Earth solar day — noon Earth = hour 12
        assert_eq!(pt_earth.hour, pt_moon.hour);
    }

    #[test]
    fn mtc_at_j2000() {
        let mtc = get_mtc(J2000_MS);
        // Sanity: MTC hour is in [0,23]
        assert!(mtc.hour >= 0 && mtc.hour <= 23);
    }

    #[test]
    fn time_str_format() {
        // Mars uses MARS_EPOCH_MS as its clock epoch → time at epoch is 00:00
        let pt = get_planet_time(Planet::Mars, MARS_EPOCH_MS, 0.0);
        assert_eq!(pt.time_str, "00:00");
        assert_eq!(pt.time_str_full, "00:00:00");
    }

    #[test]
    fn mars_half_sol_hour_12() {
        // Halfway through Mars sol from MARS_EPOCH_MS → hour 12
        let half_sol_ms = MARS_SOL_MS / 2;
        let pt = get_planet_time(Planet::Mars, MARS_EPOCH_MS + half_sol_ms, 0.0);
        assert_eq!(pt.hour, 12);
    }

    #[test]
    fn all_planets_return_valid_hours() {
        for &p in Planet::ALL.iter() {
            let pt = get_planet_time(p, J2000_MS, 0.0);
            assert!(pt.hour >= 0 && pt.hour <= 23, "invalid hour {} for {:?}", pt.hour, p);
        }
    }

    #[test]
    fn tz_offset_shifts_hour() {
        let pt0 = get_planet_time(Planet::Mars, J2000_MS + MARS_SOL_MS / 4, 0.0);
        let pt6 = get_planet_time(Planet::Mars, J2000_MS + MARS_SOL_MS / 4, 6.0);
        // +6h offset should advance hour by 6
        let diff = (pt6.hour - pt0.hour).rem_euclid(24);
        assert_eq!(diff, 6);
    }

    #[test]
    fn day_fraction_range() {
        for off in [0, 1_000_000, 50_000_000, 100_000_000i64] {
            let pt = get_planet_time(Planet::Mars, J2000_MS + off, 0.0);
            assert!(pt.day_fraction >= 0.0 && pt.day_fraction < 1.0);
        }
    }
}
