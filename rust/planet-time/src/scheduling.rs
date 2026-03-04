//! Meeting window scheduling — mirrors findMeetingWindows in planet-time.js.

use crate::constants::{Planet, EARTH_DAY_MS};
use crate::time_calc::get_planet_time;

/// A contiguous window in which both parties have `is_work_hour = true`.
#[derive(Debug, Clone)]
pub struct MeetingWindow {
    pub start_ms:     i64,
    pub end_ms:       i64,
    pub duration_min: i64,
}

/// Find all overlapping work-hour windows for two bodies over `earth_days` days,
/// scanning at `step_min` minute intervals (default 15).
pub fn find_meeting_windows(
    a: Planet,
    b: Planet,
    from_ms: i64,
    earth_days: i32,
    step_min: i32,
) -> Vec<MeetingWindow> {
    let step_ms  = step_min as i64 * 60_000;
    let end_ms   = from_ms + earth_days as i64 * EARTH_DAY_MS;
    let mut wins = Vec::new();
    let mut in_window    = false;
    let mut window_start = 0i64;

    let mut t = from_ms;
    while t < end_ms {
        let ta = get_planet_time(a, t, 0.0);
        let tb = get_planet_time(b, t, 0.0);
        let overlap = ta.is_work_hour && tb.is_work_hour;

        if overlap && !in_window {
            in_window    = true;
            window_start = t;
        }
        if !overlap && in_window {
            in_window = false;
            let dur = (t - window_start) / 60_000;
            wins.push(MeetingWindow { start_ms: window_start, end_ms: t, duration_min: dur });
        }
        t += step_ms;
    }
    if in_window {
        let dur = (end_ms - window_start) / 60_000;
        wins.push(MeetingWindow { start_ms: window_start, end_ms, duration_min: dur });
    }
    wins
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::J2000_MS;

    #[test]
    fn earth_earth_has_windows() {
        // Earth ↔ Earth same timezone should always overlap during work hours
        let wins = find_meeting_windows(Planet::Earth, Planet::Earth, J2000_MS, 1, 15);
        // At J2000 (midnight) scanning one day there should be at least one window
        // (the work shift window for both at UTC)
        assert!(!wins.is_empty(), "Earth↔Earth should find at least one window");
    }

    #[test]
    fn windows_have_positive_duration() {
        let wins = find_meeting_windows(Planet::Earth, Planet::Earth, J2000_MS, 1, 15);
        for w in &wins {
            assert!(w.duration_min > 0);
            assert!(w.end_ms > w.start_ms);
        }
    }

    #[test]
    fn windows_do_not_overlap() {
        let wins = find_meeting_windows(Planet::Earth, Planet::Earth, J2000_MS, 3, 15);
        for i in 1..wins.len() {
            assert!(wins[i].start_ms >= wins[i - 1].end_ms,
                "windows overlap: {:?} and {:?}", wins[i-1], wins[i]);
        }
    }

    #[test]
    fn earth_mars_windows_7_days() {
        let wins = find_meeting_windows(Planet::Earth, Planet::Mars, J2000_MS, 7, 15);
        // May or may not find windows depending on orbital position; just verify no panic
        for w in &wins {
            assert!(w.duration_min > 0);
        }
    }

    #[test]
    fn step_15_min_resolution() {
        let wins = find_meeting_windows(Planet::Earth, Planet::Earth, J2000_MS, 1, 15);
        for w in &wins {
            // Duration should be a multiple of 15 min
            assert_eq!(w.duration_min % 15, 0, "duration {} is not a 15-min multiple", w.duration_min);
        }
    }
}
