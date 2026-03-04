//! Astronomical constants and planet data — mirrors planet-time.js

pub const J2000_MS: i64     = 946_728_000_000;      // Date.UTC(2000,0,1,12,0,0) — TT noon
pub const MARS_EPOCH_MS: i64 = -524_069_761_536;    // MY 0 sol 0 (Date.UTC(1953,4,24,9,3,58,464))
pub const MARS_SOL_MS: i64   = 88_775_244;          // ms per Mars sol (exact)
pub const AU_KM: f64         = 149_597_870.7;
pub const C_KMS: f64         = 299_792.458;
pub const AU_SECONDS: f64    = AU_KM / C_KMS;
pub const J2000_JD: f64      = 2_451_545.0;
pub const EARTH_DAY_MS: i64  = 86_400_000;
pub const DEG: f64           = std::f64::consts::PI / 180.0;

/// Planet identifier — index doubles as orbital-element table index.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Planet {
    Mercury = 0,
    Venus   = 1,
    Earth   = 2,
    Mars    = 3,
    Jupiter = 4,
    Saturn  = 5,
    Uranus  = 6,
    Neptune = 7,
    Moon    = 8,
}

impl Planet {
    pub fn from_str(s: &str) -> Option<Planet> {
        match s.to_ascii_lowercase().as_str() {
            "mercury" => Some(Planet::Mercury),
            "venus"   => Some(Planet::Venus),
            "earth"   => Some(Planet::Earth),
            "mars"    => Some(Planet::Mars),
            "jupiter" => Some(Planet::Jupiter),
            "saturn"  => Some(Planet::Saturn),
            "uranus"  => Some(Planet::Uranus),
            "neptune" => Some(Planet::Neptune),
            "moon"    => Some(Planet::Moon),
            _ => None,
        }
    }

    pub fn index(self) -> usize { self as usize }

    pub fn name(self) -> &'static str {
        match self {
            Planet::Mercury => "Mercury", Planet::Venus   => "Venus",
            Planet::Earth   => "Earth",   Planet::Mars    => "Mars",
            Planet::Jupiter => "Jupiter", Planet::Saturn  => "Saturn",
            Planet::Uranus  => "Uranus",  Planet::Neptune => "Neptune",
            Planet::Moon    => "Moon",
        }
    }

    pub fn symbol(self) -> &'static str {
        match self {
            Planet::Mercury => "☿", Planet::Venus   => "♀",
            Planet::Earth   => "♁", Planet::Mars    => "♂",
            Planet::Jupiter => "♃", Planet::Saturn  => "♄",
            Planet::Uranus  => "⛢", Planet::Neptune => "♆",
            Planet::Moon    => "☽",
        }
    }

    /// Solar day in milliseconds (mirrors JS PLANET_DATA[key].solarDayMs).
    pub fn solar_day_ms(self) -> i64 {
        match self {
            Planet::Mercury => 15_201_285_120,  // 175.9408 × 86400000 ms
            Planet::Venus   => 10_087_200_000,  // 116.75   × 86400000 ms
            Planet::Earth   => 86_400_000,
            Planet::Mars    => 88_775_244,      // 24h 39m 35.244s (Allison & McEwen 2000)
            Planet::Jupiter => 35_730_000,      // 9.9250h × 3600000 ms
            Planet::Saturn  => 38_080_800,      // 10.578h × 3600000 (Mankovich, Marley, Fortney & Mozshovitz 2023 ring seismology refinement)
            Planet::Uranus  => 62_092_440,      // 17.2479h × 3600000 (Lamy 2025)
            Planet::Neptune => 57_996_000,      // 16.1100h × 3600000 ms
            Planet::Moon    => 2_551_442_976,   // 29.53059 × 86400000 ms
        }
    }

    /// Work shift duration in ms (1/3 of solar day for slow rotators; 1/3 of day else).
    pub fn work_shift_ms(self) -> i64 {
        self.solar_day_ms() * 8 / 24
    }

    /// UTC work-hours start (inclusive). Mercury/Venus use UTC 09:00.
    pub fn work_hours_start(self) -> f64 {
        match self {
            Planet::Mercury | Planet::Venus => 9.0,
            Planet::Earth | Planet::Mars | Planet::Moon => 9.0,
            _ => 8.0,
        }
    }

    /// UTC work-hours end (exclusive). Mercury/Venus use UTC 17:00.
    pub fn work_hours_end(self) -> f64 {
        match self {
            Planet::Mercury | Planet::Venus => 17.0,
            Planet::Earth | Planet::Mars | Planet::Moon => 17.0,
            _ => 16.0,
        }
    }

    /// Number of solar days per scheduling period.
    pub fn days_per_period(self) -> f64 {
        match self {
            Planet::Jupiter => 2.5,
            Planet::Saturn  => 2.25,
            _ => 1.0,
        }
    }

    /// Total scheduling periods per week.
    pub fn periods_per_week(self) -> i64 { 7 }

    /// Number of work periods per week (Mon–Fri = 5).
    pub fn work_periods_per_week(self) -> i64 { 5 }

    /// True for Mercury and Venus — scheduling uses UTC weekday/hour, not planet local time.
    pub fn earth_clock_sched(self) -> bool {
        matches!(self, Planet::Mercury | Planet::Venus)
    }

    /// Epoch (milliseconds since Unix epoch) for this planet.
    pub fn epoch_ms(self) -> i64 {
        if self == Planet::Mars { MARS_EPOCH_MS } else { J2000_MS }
    }

    /// All 9 planets in order.
    pub const ALL: [Planet; 9] = [
        Planet::Mercury, Planet::Venus, Planet::Earth, Planet::Mars,
        Planet::Jupiter, Planet::Saturn, Planet::Uranus, Planet::Neptune,
        Planet::Moon,
    ];
}

/// Keplerian orbital elements (Meeus 2nd ed., Table 33.a / J2000 mean elements).
/// Order matches Planet enum indices 0–8.
#[derive(Debug, Clone, Copy)]
pub struct OrbElems {
    pub l0: f64,   // mean longitude at epoch (deg)
    pub dl: f64,   // rate of change (deg/century)
    pub om: f64,   // longitude of perihelion (deg)
    pub e0: f64,   // eccentricity
    pub a: f64,    // semi-major axis (AU)
}

/// Orbital elements table indexed by Planet::index().
/// Source: Meeus "Astronomical Algorithms" 2nd ed, Table 31.a (low-precision J2000 elements).
/// These match the JS planet-time.js ORBITAL_ELEMENTS table exactly.
pub const ORB_ELEMS: [OrbElems; 9] = [
    // Mercury
    OrbElems { l0: 252.2507, dl: 149_474.0722, om:  77.4561, e0: 0.20564, a: 0.38710 },
    // Venus
    OrbElems { l0: 181.9798, dl:  58_519.2130, om: 131.5637, e0: 0.00677, a: 0.72333 },
    // Earth
    OrbElems { l0: 100.4664, dl:  36_000.7698, om: 102.9373, e0: 0.01671, a: 1.00000 },
    // Mars
    OrbElems { l0: 355.4330, dl:  19_141.6964, om: 336.0600, e0: 0.09341, a: 1.52366 },
    // Jupiter
    OrbElems { l0:  34.3515, dl:   3_036.3027, om:  14.3320, e0: 0.04849, a: 5.20336 },
    // Saturn
    OrbElems { l0:  50.0775, dl:   1_223.5093, om:  93.0572, e0: 0.05551, a: 9.53707 },
    // Uranus
    OrbElems { l0: 314.0550, dl:     429.8633, om: 173.0052, e0: 0.04630, a: 19.1912 },
    // Neptune
    OrbElems { l0: 304.3480, dl:     219.8997, om:  48.1234, e0: 0.00899, a: 30.0690 },
    // Moon — not used for helio_pos (Moon→Earth substitution in orbital.rs); placeholder only
    OrbElems { l0: 218.3165, dl: 481_267.8813, om: 125.0446, e0: 0.0549,  a: 0.00257 },
];

/// TAI − UTC leap-second table (UTC timestamps, seconds added).
/// Source: IERS; last entry 2017-01-01 (37 s).
pub const LEAP_SECS: [(i64, i64); 28] = [
    (63_072_000_000, 10), (78_796_800_000, 11), (94_694_400_000, 12),
    (126_230_400_000, 13), (157_766_400_000, 14), (189_302_400_000, 15),
    (220_924_800_000, 16), (252_460_800_000, 17), (283_996_800_000, 18),
    (315_532_800_000, 19), (362_793_600_000, 20), (394_329_600_000, 21),
    (425_865_600_000, 22), (489_024_000_000, 23), (567_993_600_000, 24),
    (631_152_000_000, 25), (662_688_000_000, 26), (709_948_800_000, 27),
    (741_484_800_000, 28), (773_020_800_000, 29), (820_454_400_000, 30),
    (867_715_200_000, 31), (915_148_800_000, 32), (1_136_073_600_000, 33),
    (1_230_768_000_000, 34), (1_341_100_800_000, 35),
    (1_435_708_800_000, 36), (1_483_228_800_000, 37),
];
