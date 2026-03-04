//! # interplanet-time
//!
//! Pure-Rust port of `planet-time.js` — planetary time calculation, orbital
//! mechanics, meeting-window scheduling, and light-travel formatting.
//!
//! All functions accept `utc_ms: i64` (milliseconds since the Unix epoch,
//! identical convention to the JavaScript and C siblings).
//!
//! ## Quick start
//!
//! ```rust
//! use interplanet_time::{get_planet_time, Planet};
//!
//! let pt = get_planet_time(Planet::Mars, 946_728_000_000, 0.0);
//! println!("Mars time at J2000: {}", pt.time_str);
//! ```

pub mod constants;
pub mod orbital;
pub mod time_calc;
pub mod scheduling;
pub mod formatting;

// ── Convenience re-exports ────────────────────────────────────────────────────

pub use constants::Planet;

pub use orbital::{
    helio_pos, body_distance_au, light_travel_seconds,
    check_line_of_sight, lower_quartile_light_time,
    LineOfSight, HelioPos,
};

pub use time_calc::{
    get_planet_time, get_mtc, get_mars_time_at_offset,
    PlanetTime, MTC,
};

pub use scheduling::{find_meeting_windows, MeetingWindow};

pub use formatting::{format_light_time, format_planet_time_iso};
