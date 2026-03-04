//! Utility formatters — human-readable light-travel time and ISO-style planet time.

use crate::time_calc::PlanetTime;

/// Format a light-travel duration in seconds as a human-readable string.
///
/// Examples:
/// - 0.3  s  → "0.3 s"
/// - 186  s  → "3 min 6 s"
/// - 2010 s  → "33 min 30 s"
/// - 5400 s  → "1 hr 30 min"
pub fn format_light_time(seconds: f64) -> String {
    let s = seconds.round() as i64;
    if s < 60 {
        format!("{} s", s)
    } else if s < 3_600 {
        let m = s / 60;
        let rem = s % 60;
        if rem == 0 {
            format!("{} min", m)
        } else {
            format!("{} min {} s", m, rem)
        }
    } else {
        let h   = s / 3_600;
        let m   = (s % 3_600) / 60;
        if m == 0 {
            format!("{} hr", h)
        } else {
            format!("{} hr {} min", h, m)
        }
    }
}

/// Format a `PlanetTime` as an ISO-8601-style string:
/// `"DDD+NNNNN HH:MM:SS"` where DDD is day_number and NNNNN is day_in_year.
///
/// Intended for logging / debugging; not part of the wire protocol.
pub fn format_planet_time_iso(pt: &PlanetTime) -> String {
    format!(
        "day{}+{} {}",
        pt.day_number, pt.day_in_year, pt.time_str_full
    )
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn light_time_seconds() {
        assert_eq!(format_light_time(0.3),  "0 s");
        assert_eq!(format_light_time(45.0), "45 s");
        assert_eq!(format_light_time(59.4), "59 s");
    }

    #[test]
    fn light_time_minutes() {
        assert_eq!(format_light_time(60.0),  "1 min");
        assert_eq!(format_light_time(186.0), "3 min 6 s");
        assert_eq!(format_light_time(120.0), "2 min");
    }

    #[test]
    fn light_time_hours() {
        assert_eq!(format_light_time(3600.0),  "1 hr");
        assert_eq!(format_light_time(5400.0),  "1 hr 30 min");
        assert_eq!(format_light_time(7200.0),  "2 hr");
        assert_eq!(format_light_time(2010.0),  "33 min 30 s");
    }

    #[test]
    fn planet_time_iso_format() {
        use crate::time_calc::get_planet_time;
        use crate::constants::{Planet, J2000_MS};
        let pt = get_planet_time(Planet::Earth, J2000_MS, 0.0);
        let s  = format_planet_time_iso(&pt);
        // Should contain "day0+0 00:00:00"
        assert!(s.contains("00:00:00"), "got: {}", s);
    }
}
