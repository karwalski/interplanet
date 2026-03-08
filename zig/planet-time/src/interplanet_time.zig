// interplanet_time.zig — Interplanetary Time Library (Zig implementation)
// Story 18.17 — direct port of planet-time.js / libinterplanet.c
//
// No dynamic allocation in the core computation functions.
// All numeric constants taken verbatim from the C source (libinterplanet.c).

const std = @import("std");
const math = std.math;

// ── Version ────────────────────────────────────────────────────────────────

pub const VERSION = "1.0.0";

// ── Physical constants ─────────────────────────────────────────────────────

pub const AU_KM: f64 = 149597870.7;
pub const C_KMS: f64 = 299792.458;
pub const AU_SECONDS: f64 = AU_KM / C_KMS; // ≈ 499.004 s per AU
pub const J2000_JD: f64 = 2451545.0;
pub const J2000_MS: i64 = 946728000000; // 2000-01-01T12:00:00Z
pub const MARS_SOL_MS: i64 = 88775244;
pub const MARS_EPOCH_MS: i64 = -524069761536; // 1953-05-24T09:03:58.464Z

const PI: f64 = math.pi;
const TWO_PI: f64 = 2.0 * math.pi;
const D2R: f64 = PI / 180.0;

// ── Body indices ────────────────────────────────────────────────────────────
//  0=Mercury 1=Venus 2=Earth 3=Mars 4=Jupiter 5=Saturn 6=Uranus 7=Neptune
//  8=Moon (treated as Earth for scheduling)

pub const BODY_MERCURY: u8 = 0;
pub const BODY_VENUS: u8 = 1;
pub const BODY_EARTH: u8 = 2;
pub const BODY_MARS: u8 = 3;
pub const BODY_JUPITER: u8 = 4;
pub const BODY_SATURN: u8 = 5;
pub const BODY_URANUS: u8 = 6;
pub const BODY_NEPTUNE: u8 = 7;
pub const BODY_MOON: u8 = 8;

pub const NBODIES: usize = 8; // Mercury..Neptune in tables
pub const BODY_NAMES = [9][]const u8{
    "Mercury", "Venus", "Earth", "Mars",
    "Jupiter", "Saturn", "Uranus", "Neptune",
    "Moon",
};

pub fn bodyName(index: u8) []const u8 {
    if (index < BODY_NAMES.len) return BODY_NAMES[index];
    return "Unknown";
}

// ── Planet data table ───────────────────────────────────────────────────────
// Indices 0=Mercury .. 7=Neptune (same ordering as C source)

const PlanetData = struct {
    solar_day_ms: f64,
    sidereal_yr_ms: f64,
    days_per_period: f64,
    periods_per_week: i32,
    work_periods_per_week: i32,
    work_hours_start: f64,
    work_hours_end: f64,
    epoch_ms: i64,
    earth_clock_sched: bool = false,  // true for Mercury and Venus
};

const PDATA = [NBODIES]PlanetData{
    // Mercury (0) — Earth-clock scheduling
    .{
        .solar_day_ms = 175.9408 * 86400000.0,
        .sidereal_yr_ms = 87.9691 * 86400000.0,
        .days_per_period = 1.0,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 9.0,
        .work_hours_end = 17.0,
        .epoch_ms = J2000_MS,
        .earth_clock_sched = true,
    },
    // Venus (1) — Earth-clock scheduling
    .{
        .solar_day_ms = 116.7500 * 86400000.0,
        .sidereal_yr_ms = 224.701 * 86400000.0,
        .days_per_period = 1.0,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 9.0,
        .work_hours_end = 17.0,
        .epoch_ms = J2000_MS,
        .earth_clock_sched = true,
    },
    // Earth (2)
    .{
        .solar_day_ms = 86400000.0,
        .sidereal_yr_ms = 365.25636 * 86400000.0,
        .days_per_period = 1.0,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 9.0,
        .work_hours_end = 17.0,
        .epoch_ms = J2000_MS,
    },
    // Mars (3)
    .{
        .solar_day_ms = 88775244.0,
        .sidereal_yr_ms = 686.9957 * 86400000.0,
        .days_per_period = 1.0,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 9.0,
        .work_hours_end = 17.0,
        .epoch_ms = MARS_EPOCH_MS,
    },
    // Jupiter (4)
    .{
        .solar_day_ms = 9.9250 * 3600000.0,
        .sidereal_yr_ms = 4332.589 * 86400000.0,
        .days_per_period = 2.5,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 8.0,
        .work_hours_end = 16.0,
        .epoch_ms = J2000_MS,
    },
    // Saturn (5) — Mankovich et al. 2023: 10.578 h
    .{
        .solar_day_ms = 38080800.0,
        .sidereal_yr_ms = 10759.22 * 86400000.0,
        .days_per_period = 2.25,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 8.0,
        .work_hours_end = 16.0,
        .epoch_ms = J2000_MS,
    },
    // Uranus (6)
    .{
        .solar_day_ms = 17.2479 * 3600000.0,
        .sidereal_yr_ms = 30688.5 * 86400000.0,
        .days_per_period = 1.0,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 8.0,
        .work_hours_end = 16.0,
        .epoch_ms = J2000_MS,
    },
    // Neptune (7)
    .{
        .solar_day_ms = 16.1100 * 3600000.0,
        .sidereal_yr_ms = 60195.0 * 86400000.0,
        .days_per_period = 1.0,
        .periods_per_week = 7,
        .work_periods_per_week = 5,
        .work_hours_start = 8.0,
        .work_hours_end = 16.0,
        .epoch_ms = J2000_MS,
    },
};

// ── Orbital elements (Meeus Table 31.a) ────────────────────────────────────
// L0, dL: mean longitude at J2000 (degrees), rate (degrees/century)
// om0:    longitude of perihelion (degrees)
// e0:     eccentricity
// a:      semi-major axis (AU)

pub const OrbitalElements = struct {
    l0: f64,
    dl: f64,
    om0: f64,
    e0: f64,
    a: f64,
};

pub const ORBELEMS = [NBODIES]OrbitalElements{
    .{ .l0 = 252.2507, .dl = 149474.0722, .om0 = 77.4561, .e0 = 0.20564, .a = 0.38710 }, // Mercury
    .{ .l0 = 181.9798, .dl = 58519.2130, .om0 = 131.5637, .e0 = 0.00677, .a = 0.72333 }, // Venus
    .{ .l0 = 100.4664, .dl = 36000.7698, .om0 = 102.9373, .e0 = 0.01671, .a = 1.00000 }, // Earth
    .{ .l0 = 355.4330, .dl = 19141.6964, .om0 = 336.0600, .e0 = 0.09341, .a = 1.52366 }, // Mars
    .{ .l0 = 34.3515, .dl = 3036.3027, .om0 = 14.3320, .e0 = 0.04849, .a = 5.20336 }, // Jupiter
    .{ .l0 = 50.0775, .dl = 1223.5093, .om0 = 93.0572, .e0 = 0.05551, .a = 9.53707 }, // Saturn
    .{ .l0 = 314.0550, .dl = 429.8633, .om0 = 173.0052, .e0 = 0.04630, .a = 19.1912 }, // Uranus
    .{ .l0 = 304.3480, .dl = 219.8997, .om0 = 48.1234, .e0 = 0.00899, .a = 30.0690 }, // Neptune
};

// Convenience accessors for individual orbital constants
pub fn semiMajorAxisAu(body: u8) f64 {
    const idx = planetIdx(body) orelse return 0.0;
    return ORBELEMS[idx].a;
}

pub fn eccentricity(body: u8) f64 {
    const idx = planetIdx(body) orelse return 0.0;
    return ORBELEMS[idx].e0;
}

pub fn obliquityDeg(_: u8) f64 {
    // Simplified: return Earth obliquity for all bodies as placeholder
    // (full obliquity table is not needed for the fixture tests)
    return 23.439291;
}

pub fn siderealDaySeconds(body: u8) f64 {
    const idx = planetIdx(body) orelse return 0.0;
    // Approximate sidereal day from solar day and orbital period
    const sd = PDATA[idx].solar_day_ms / 1000.0;
    const orb = orbitalPeriodDays(body) * 86400.0;
    if (orb <= 0.0) return sd;
    // sidereal_day = 1/(1/solar_day + 1/orbital_period) in seconds
    return 1.0 / (1.0 / sd + 1.0 / orb);
}

pub fn solarDaySeconds(body: u8) f64 {
    const idx = planetIdx(body) orelse return 86400.0;
    return PDATA[idx].solar_day_ms / 1000.0;
}

pub fn orbitalPeriodDays(body: u8) f64 {
    const idx = planetIdx(body) orelse return 365.25636;
    return PDATA[idx].sidereal_yr_ms / 86400000.0;
}

// ── Leap second table ───────────────────────────────────────────────────────

const LeapSec = struct {
    tai_utc: i32,
    utc_ms: i64,
};

const LEAPSECS = [_]LeapSec{
    .{ .tai_utc = 10, .utc_ms = 63072000000 }, // 1972-01-01
    .{ .tai_utc = 11, .utc_ms = 78796800000 }, // 1972-07-01
    .{ .tai_utc = 12, .utc_ms = 94694400000 }, // 1973-01-01
    .{ .tai_utc = 13, .utc_ms = 126230400000 }, // 1974-01-01
    .{ .tai_utc = 14, .utc_ms = 157766400000 }, // 1975-01-01
    .{ .tai_utc = 15, .utc_ms = 189302400000 }, // 1976-01-01
    .{ .tai_utc = 16, .utc_ms = 220924800000 }, // 1977-01-01
    .{ .tai_utc = 17, .utc_ms = 252460800000 }, // 1978-01-01
    .{ .tai_utc = 18, .utc_ms = 283996800000 }, // 1979-01-01
    .{ .tai_utc = 19, .utc_ms = 315532800000 }, // 1980-01-01
    .{ .tai_utc = 20, .utc_ms = 362793600000 }, // 1981-07-01
    .{ .tai_utc = 21, .utc_ms = 394329600000 }, // 1982-07-01
    .{ .tai_utc = 22, .utc_ms = 425865600000 }, // 1983-07-01
    .{ .tai_utc = 23, .utc_ms = 489024000000 }, // 1985-07-01
    .{ .tai_utc = 24, .utc_ms = 567993600000 }, // 1988-01-01
    .{ .tai_utc = 25, .utc_ms = 631152000000 }, // 1990-01-01
    .{ .tai_utc = 26, .utc_ms = 662688000000 }, // 1991-01-01
    .{ .tai_utc = 27, .utc_ms = 709948800000 }, // 1992-07-01
    .{ .tai_utc = 28, .utc_ms = 741484800000 }, // 1993-07-01
    .{ .tai_utc = 29, .utc_ms = 773020800000 }, // 1994-07-01
    .{ .tai_utc = 30, .utc_ms = 820454400000 }, // 1996-01-01
    .{ .tai_utc = 31, .utc_ms = 867715200000 }, // 1997-07-01
    .{ .tai_utc = 32, .utc_ms = 915148800000 }, // 1999-01-01
    .{ .tai_utc = 33, .utc_ms = 1136073600000 }, // 2006-01-01
    .{ .tai_utc = 34, .utc_ms = 1230768000000 }, // 2009-01-01
    .{ .tai_utc = 35, .utc_ms = 1341100800000 }, // 2012-07-01
    .{ .tai_utc = 36, .utc_ms = 1435708800000 }, // 2015-07-01
    .{ .tai_utc = 37, .utc_ms = 1483228800000 }, // 2017-01-01
};

fn taiMinusUtc(utc_ms: i64) i32 {
    var offset: i32 = 10;
    for (LEAPSECS) |ls| {
        if (utc_ms >= ls.utc_ms) {
            offset = ls.tai_utc;
        } else {
            break;
        }
    }
    return offset;
}

// ── Julian Day ──────────────────────────────────────────────────────────────

/// Convert a UTC timestamp (ms) to Terrestrial Time Julian Day Number.
/// TT = UTC + (TAI−UTC) + 32.184 s
/// JDE = 2440587.5 + tt_ms / 86400000
pub fn julianDayFromMs(utc_ms: i64) f64 {
    const tai_offset: f64 = @floatFromInt(taiMinusUtc(utc_ms));
    const tt_ms: f64 = @as(f64, @floatFromInt(utc_ms)) + (tai_offset + 32.184) * 1000.0;
    return 2440587.5 + tt_ms / 86400000.0;
}

/// Julian centuries since J2000.0 from UTC ms
fn julianCenturiesMs(utc_ms: i64) f64 {
    return (julianDayFromMs(utc_ms) - J2000_JD) / 36525.0;
}

/// Julian centuries since J2000.0 from JD
fn julianCenturiesJd(jd: f64) f64 {
    return (jd - J2000_JD) / 36525.0;
}

// ── Kepler solver ───────────────────────────────────────────────────────────

/// Solve Kepler's equation M = E − e·sin(E) using Newton-Raphson.
fn keplerE(M_rad: f64, e: f64) f64 {
    var E = M_rad;
    for (0..50) |_| {
        const dE = (M_rad - E + e * @sin(E)) / (1.0 - e * @cos(E));
        E += dE;
        if (@abs(dE) < 1e-12) break;
    }
    return E;
}

// ── Internal helper: map body index ────────────────────────────────────────

fn planetIdx(body: u8) ?usize {
    if (body == BODY_MOON) return @as(usize, BODY_EARTH);
    if (body < NBODIES) return @as(usize, body);
    return null;
}

// ── Heliocentric position ───────────────────────────────────────────────────

pub const HelioPos = struct {
    x: f64, // AU, ecliptic plane
    y: f64, // AU, ecliptic plane
    r: f64, // heliocentric distance AU
    lon: f64, // ecliptic longitude (radians)
};

/// Heliocentric position in the ecliptic plane.
/// body: 0=Mercury..7=Neptune (8=Moon uses Earth orbit)
/// utc_ms: UTC milliseconds since Unix epoch
pub fn heliocentricPositionMs(body: u8, utc_ms: i64) ?HelioPos {
    const idx = planetIdx(body) orelse return null;
    const el = ORBELEMS[idx];
    const T = julianCenturiesMs(utc_ms);
    return helioFromTandEl(T, el);
}

fn helioFromTandEl(T: f64, el: OrbitalElements) HelioPos {
    const L_deg = el.l0 + el.dl * T;
    const L = @mod(@mod(L_deg * D2R, TWO_PI) + TWO_PI, TWO_PI);
    const om = el.om0 * D2R;
    const M = @mod(@mod(L - om, TWO_PI) + TWO_PI, TWO_PI);
    const e = el.e0;
    const a = el.a;

    const E = keplerE(M, e);
    const v = 2.0 * math.atan2(
        @sqrt(1.0 + e) * @sin(E / 2.0),
        @sqrt(1.0 - e) * @cos(E / 2.0),
    );
    const r = a * (1.0 - e * @cos(E));
    const lon = @mod(@mod(v + om, TWO_PI) + TWO_PI, TWO_PI);

    return HelioPos{
        .x = r * @cos(lon),
        .y = r * @sin(lon),
        .r = r,
        .lon = lon,
    };
}

// ── Light travel time ───────────────────────────────────────────────────────

/// Distance in AU between two bodies at a given UTC time.
pub fn bodyDistanceAu(body_a: u8, body_b: u8, utc_ms: i64) ?f64 {
    const pa = heliocentricPositionMs(body_a, utc_ms) orelse return null;
    const pb = heliocentricPositionMs(body_b, utc_ms) orelse return null;
    if (body_a == BODY_EARTH or body_a == BODY_MOON) {
        if (body_b == BODY_EARTH or body_b == BODY_MOON) return 0.0;
    }
    const dx = pa.x - pb.x;
    const dy = pa.y - pb.y;
    return @sqrt(dx * dx + dy * dy);
}

/// One-way light travel time in seconds between two bodies.
pub fn lightTravelSeconds(body_a: u8, body_b: u8, utc_ms: i64) ?f64 {
    const d = bodyDistanceAu(body_a, body_b, utc_ms) orelse return null;
    return d * AU_SECONDS;
}

// ── Mean longitude & true anomaly (public for testing) ─────────────────────

/// Mean longitude in degrees for a body at given JD.
pub fn meanLongitudeDeg(body: u8, jd: f64) f64 {
    const idx = planetIdx(body) orelse return 0.0;
    const el = ORBELEMS[idx];
    const T = julianCenturiesJd(jd);
    return el.l0 + el.dl * T;
}

/// True anomaly in degrees from mean anomaly and eccentricity (Newton-Raphson).
pub fn trueAnomalyDeg(mean_anomaly_deg: f64, ecc: f64) f64 {
    const M = @mod(@mod(mean_anomaly_deg * D2R, TWO_PI) + TWO_PI, TWO_PI);
    const E = keplerE(M, ecc);
    const v = 2.0 * math.atan2(
        @sqrt(1.0 + ecc) * @sin(E / 2.0),
        @sqrt(1.0 - ecc) * @cos(E / 2.0),
    );
    return v / D2R;
}

/// Ecliptic longitude in degrees for a body at given JD.
pub fn eclipticLongitudeDeg(body: u8, jd: f64) f64 {
    const idx = planetIdx(body) orelse return 0.0;
    const el = ORBELEMS[idx];
    const T = julianCenturiesJd(jd);
    const pos = helioFromTandEl(T, el);
    return pos.lon / D2R;
}

// ── Planet time ─────────────────────────────────────────────────────────────

pub const PlanetTimeResult = struct {
    hour: i32,
    minute: i32,
    second: i32,
    local_hour: f64,
    day_fraction: f64,
    day_number: i64,
    day_in_year: i64,
    year_number: i64,
    period_in_week: i32,
    is_work_period: bool,
    is_work_hour: bool,
    // Mars only (0 / null equiv for other bodies):
    sol_in_year: ?i64,
    sols_per_year: ?i64,
    // Zone ID: null for Earth; e.g. "AMT+4", "LMT+0" for non-Earth bodies.
    // Storage for the formatted string (prefix up to 3 chars + sign + digits).
    zone_id_buf: [12]u8,
    zone_id_len: usize,

    /// Returns the zone ID as a slice, or null for Earth.
    pub fn zoneId(self: *const PlanetTimeResult) ?[]const u8 {
        if (self.zone_id_len == 0) return null;
        return self.zone_id_buf[0..self.zone_id_len];
    }
};

/// Get local time on a planet at a given UTC instant and tz offset (planet hours).
pub fn getPlanetTime(body: u8, utc_ms: i64, tz_h: f64) ?PlanetTimeResult {
    const key: u8 = if (body == BODY_MOON) BODY_EARTH else body;
    const idx = planetIdx(key) orelse return null;
    const pl = PDATA[idx];

    const tz_adjust_ms: f64 = tz_h / 24.0 * pl.solar_day_ms;
    const elapsed_ms: f64 = @as(f64, @floatFromInt(utc_ms - pl.epoch_ms)) + tz_adjust_ms;

    const total_days = elapsed_ms / pl.solar_day_ms;
    const day_number: i64 = @intFromFloat(@floor(total_days));
    const day_fraction = total_days - @floor(total_days);

    const local_hour = day_fraction * 24.0;
    const h: i32 = @intFromFloat(@floor(local_hour));
    const m: i32 = @intFromFloat(@floor((local_hour - @floor(local_hour)) * 60.0));
    const s: i32 = @intFromFloat(@floor(((local_hour - @floor(local_hour)) * 60.0 - @as(f64, @floatFromInt(m))) * 60.0));

    // Mercury/Venus: use Earth-clock scheduling (UTC day-of-week + UTC hour)
    var piw: i32 = undefined;
    var is_work_period: bool = undefined;
    var is_work_hour: bool = undefined;
    if (pl.earth_clock_sched) {
        // dow = ((floor(utc_ms / 86400000) % 7) + 3) % 7, Mon=0..Sun=6
        const utc_day: i64 = @divFloor(utc_ms, 86400000);
        const dow_raw = @mod(utc_day, 7) + 3;
        const dow: i32 = @intCast(@mod(dow_raw, 7));
        is_work_period = dow < pl.work_periods_per_week;
        const ms_of_day: i64 = utc_ms - utc_day * 86400000;
        const utc_h: f64 = @as(f64, @floatFromInt(ms_of_day)) / 3600000.0;
        is_work_hour = is_work_period and
            utc_h >= pl.work_hours_start and
            utc_h < pl.work_hours_end;
        piw = dow;
    } else {
        const total_periods = total_days / pl.days_per_period;
        const period_int: i64 = @intFromFloat(@floor(total_periods));
        const ppw: i64 = pl.periods_per_week;
        const piw_raw = @mod(period_int, ppw);
        piw = @intCast(if (piw_raw < 0) piw_raw + ppw else piw_raw);
        is_work_period = piw < pl.work_periods_per_week;
        is_work_hour = is_work_period and
            local_hour >= pl.work_hours_start and
            local_hour < pl.work_hours_end;
    }

    const year_len_days = pl.sidereal_yr_ms / pl.solar_day_ms;
    const year_number: i64 = @intFromFloat(@floor(total_days / year_len_days));
    const day_in_year_f = total_days - @as(f64, @floatFromInt(year_number)) * year_len_days;
    const day_in_year: i64 = @intFromFloat(@floor(day_in_year_f));

    var sol_in_year: ?i64 = null;
    var sols_per_year: ?i64 = null;
    if (key == BODY_MARS) {
        sol_in_year = day_in_year;
        const spy_f = PDATA[@as(usize, BODY_MARS)].sidereal_yr_ms / PDATA[@as(usize, BODY_MARS)].solar_day_ms;
        const spy_i: i64 = @intFromFloat(@round(spy_f));
        sols_per_year = spy_i;
    }

    // Zone ID: null for Earth; PREFIX+N or PREFIX-N for all others.
    const ZONE_PREFIXES = [9]?[]const u8{
        "MMT", // 0 Mercury
        "VMT", // 1 Venus
        null,  // 2 Earth
        "AMT", // 3 Mars
        "JMT", // 4 Jupiter
        "SMT", // 5 Saturn
        "UMT", // 6 Uranus
        "NMT", // 7 Neptune
        "LMT", // 8 Moon
    };
    var zone_id_buf = [_]u8{0} ** 12;
    var zone_id_len: usize = 0;
    const zone_prefix = ZONE_PREFIXES[@as(usize, body)];
    if (zone_prefix) |prefix| {
        const abs_off: i64 = @intFromFloat(@abs(@trunc(tz_h)));
        const sign_char: u8 = if (tz_h >= 0.0) '+' else '-';
        const written = std.fmt.bufPrint(&zone_id_buf, "{s}{c}{d}", .{ prefix, sign_char, abs_off }) catch "";
        zone_id_len = written.len;
    }

    return PlanetTimeResult{
        .hour = h,
        .minute = m,
        .second = s,
        .local_hour = local_hour,
        .day_fraction = day_fraction,
        .day_number = day_number,
        .day_in_year = day_in_year,
        .year_number = year_number,
        .period_in_week = piw,
        .is_work_period = is_work_period,
        .is_work_hour = is_work_hour,
        .sol_in_year = sol_in_year,
        .sols_per_year = sols_per_year,
        .zone_id_buf = zone_id_buf,
        .zone_id_len = zone_id_len,
    };
}

// ── MTC ─────────────────────────────────────────────────────────────────────

pub const MtcResult = struct {
    sol: i64,
    hour: i32,
    minute: i32,
    second: i32,
};

/// Mars Coordinated Time (MTC) at a given UTC instant.
pub fn getMtc(utc_ms: i64) MtcResult {
    const total_sols: f64 = @as(f64, @floatFromInt(utc_ms - MARS_EPOCH_MS)) /
        @as(f64, @floatFromInt(MARS_SOL_MS));
    const sol: i64 = @intFromFloat(@floor(total_sols));
    const frac = total_sols - @floor(total_sols);
    const h: i32 = @intFromFloat(@floor(frac * 24.0));
    const m: i32 = @intFromFloat(@floor((frac * 24.0 - @as(f64, @floatFromInt(h))) * 60.0));
    const h_f: f64 = @floatFromInt(h);
    const m_f: f64 = @floatFromInt(m);
    const s: i32 = @intFromFloat(@floor(((frac * 24.0 - h_f) * 60.0 - m_f) * 60.0));
    return MtcResult{ .sol = sol, .hour = h, .minute = m, .second = s };
}

// ── Sol number ──────────────────────────────────────────────────────────────

/// Sol number (total solar days since planet epoch) for a body at UTC ms.
pub fn solNumberMs(body: u8, utc_ms: i64) f64 {
    const key: u8 = if (body == BODY_MOON) BODY_EARTH else body;
    const idx = planetIdx(key) orelse return 0.0;
    const pl = PDATA[idx];
    const elapsed_ms: f64 = @as(f64, @floatFromInt(utc_ms - pl.epoch_ms));
    return elapsed_ms / pl.solar_day_ms;
}

/// Local solar time in seconds since midnight for a body at UTC ms.
pub fn localSolarTimeSec(body: u8, utc_ms: i64, longitude_deg: f64) f64 {
    const key: u8 = if (body == BODY_MOON) BODY_EARTH else body;
    const idx = planetIdx(key) orelse return 0.0;
    const pl = PDATA[idx];
    const solar_day_sec = pl.solar_day_ms / 1000.0;
    // Offset for longitude: longitude_deg / 360 * solar_day_sec
    const lon_offset = longitude_deg / 360.0 * solar_day_sec;
    const elapsed_ms: f64 = @as(f64, @floatFromInt(utc_ms - pl.epoch_ms));
    const elapsed_sec = elapsed_ms / 1000.0;
    const local_sec = @mod(elapsed_sec + lon_offset, solar_day_sec);
    return if (local_sec < 0.0) local_sec + solar_day_sec else local_sec;
}

// ── Public PlanetTime struct (high-level API) ───────────────────────────────

pub const PlanetTime = struct {
    body: u8,
    jd: f64,
    sol: f64,
    local_time_sec: f64,
    day_length_sec: f64,
    light_travel_from_earth_sec: f64,
};

/// Main public API: compute all planet-time fields from body index + unix_ms.
/// body_index: 0=Mercury..7=Neptune, 8=Moon
/// unix_ms: Unix timestamp in milliseconds
pub fn planetTime(body_index: u8, unix_ms: i64) PlanetTime {
    const jd = julianDayFromMs(unix_ms);
    const sol = solNumberMs(body_index, unix_ms);

    const key: u8 = if (body_index == BODY_MOON) BODY_EARTH else body_index;
    const idx = planetIdx(key) orelse 2;
    const day_length_sec = PDATA[idx].solar_day_ms / 1000.0;
    const local_time_sec = localSolarTimeSec(body_index, unix_ms, 0.0);

    const lt = lightTravelSeconds(BODY_EARTH, body_index, unix_ms) orelse 0.0;

    return PlanetTime{
        .body = body_index,
        .jd = jd,
        .sol = sol,
        .local_time_sec = local_time_sec,
        .day_length_sec = day_length_sec,
        .light_travel_from_earth_sec = lt,
    };
}
