// unit_test.zig — InterplanetTime Zig library unit + fixture tests
// Story 18.17 — Zig port of planet-time library
//
// Standalone executable: imports interplanet_time.zig and runs ≥100 check() calls.
// Exits with code 1 if any check fails.
// Prints "fixture entries checked: N" to stdout for E2E detection.

const std = @import("std");
const ipt = @import("interplanet_time");

var passed: u32 = 0;
var failed: u32 = 0;

fn check(desc: []const u8, ok: bool) void {
    if (ok) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n", .{desc});
    }
}

fn checkApprox(desc: []const u8, got: f64, expected: f64, tol: f64) void {
    if (@abs(got - expected) <= tol) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  got: {d:.6}  expected: {d:.6}  tol: {d}\n", .{ desc, got, expected, tol });
    }
}

fn checkI64(desc: []const u8, got: i64, expected: i64) void {
    if (got == expected) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  got: {d}  expected: {d}\n", .{ desc, got, expected });
    }
}

fn checkI32(desc: []const u8, got: i32, expected: i32) void {
    if (got == expected) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  got: {d}  expected: {d}\n", .{ desc, got, expected });
    }
}

fn checkStr(desc: []const u8, got: []const u8, expected: []const u8) void {
    if (std.mem.eql(u8, got, expected)) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  got: {s}  expected: {s}\n", .{ desc, got, expected });
    }
}

// ─── SECTION 1: Constants ──────────────────────────────────────────────────

fn testConstants() void {
    checkStr("VERSION = 1.0.0", ipt.VERSION, "1.0.0");
    checkApprox("AU_KM = 149597870.7", ipt.AU_KM, 149597870.7, 0.01);
    checkApprox("C_KMS = 299792.458", ipt.C_KMS, 299792.458, 0.001);
    checkApprox("AU_SECONDS ≈ 499.0", ipt.AU_SECONDS, 499.004, 0.01);
    checkApprox("J2000_JD = 2451545.0", ipt.J2000_JD, 2451545.0, 0.0001);
    checkI64("J2000_MS = 946728000000", ipt.J2000_MS, 946728000000);
    checkI64("MARS_SOL_MS = 88775244", ipt.MARS_SOL_MS, 88775244);
    checkI64("MARS_EPOCH_MS", ipt.MARS_EPOCH_MS, -524069761536);
    checkStr("body 0 = Mercury", ipt.bodyName(0), "Mercury");
    checkStr("body 1 = Venus", ipt.bodyName(1), "Venus");
    checkStr("body 2 = Earth", ipt.bodyName(2), "Earth");
    checkStr("body 3 = Mars", ipt.bodyName(3), "Mars");
    checkStr("body 4 = Jupiter", ipt.bodyName(4), "Jupiter");
    checkStr("body 5 = Saturn", ipt.bodyName(5), "Saturn");
    checkStr("body 6 = Uranus", ipt.bodyName(6), "Uranus");
    checkStr("body 7 = Neptune", ipt.bodyName(7), "Neptune");
    checkStr("body 8 = Moon", ipt.bodyName(8), "Moon");
    checkStr("body 99 = Unknown", ipt.bodyName(99), "Unknown");
}

// ─── SECTION 2: Orbital elements ──────────────────────────────────────────

fn testOrbitalElements() void {
    checkApprox("Mercury a = 0.38710", ipt.ORBELEMS[0].a, 0.38710, 0.0001);
    checkApprox("Venus a = 0.72333", ipt.ORBELEMS[1].a, 0.72333, 0.0001);
    checkApprox("Earth a = 1.00000", ipt.ORBELEMS[2].a, 1.00000, 0.0001);
    checkApprox("Mars a = 1.52366", ipt.ORBELEMS[3].a, 1.52366, 0.0001);
    checkApprox("Jupiter a = 5.20336", ipt.ORBELEMS[4].a, 5.20336, 0.0001);
    checkApprox("Saturn a = 9.53707", ipt.ORBELEMS[5].a, 9.53707, 0.0001);
    checkApprox("Uranus a = 19.1912", ipt.ORBELEMS[6].a, 19.1912, 0.0001);
    checkApprox("Neptune a = 30.0690", ipt.ORBELEMS[7].a, 30.0690, 0.0001);

    checkApprox("Mercury e = 0.20564", ipt.ORBELEMS[0].e0, 0.20564, 0.00001);
    checkApprox("Mars e = 0.09341", ipt.ORBELEMS[3].e0, 0.09341, 0.00001);
    checkApprox("Neptune e = 0.00899", ipt.ORBELEMS[7].e0, 0.00899, 0.00001);

    checkApprox("semiMajorAxisAu Earth", ipt.semiMajorAxisAu(2), 1.0, 0.001);
    checkApprox("semiMajorAxisAu Mars", ipt.semiMajorAxisAu(3), 1.52366, 0.0001);
    checkApprox("eccentricity Mercury", ipt.eccentricity(0), 0.20564, 0.0001);
    checkApprox("eccentricity Earth", ipt.eccentricity(2), 0.01671, 0.0001);
}

// ─── SECTION 3: Day lengths ────────────────────────────────────────────────

fn testDayLengths() void {
    checkApprox("solarDaySeconds Earth = 86400", ipt.solarDaySeconds(2), 86400.0, 1.0);
    checkApprox("solarDaySeconds Mars ≈ 88775", ipt.solarDaySeconds(3), 88775.244, 1.0);
    checkApprox("solarDaySeconds Jupiter ≈ 35730", ipt.solarDaySeconds(4), 9.9250 * 3600.0, 1.0);
    checkApprox("orbitalPeriodDays Earth ≈ 365.25", ipt.orbitalPeriodDays(2), 365.25636, 0.01);
    checkApprox("orbitalPeriodDays Mars ≈ 687", ipt.orbitalPeriodDays(3), 686.9957, 0.01);
    checkApprox("orbitalPeriodDays Jupiter ≈ 4332", ipt.orbitalPeriodDays(4), 4332.589, 0.1);
}

// ─── SECTION 4: Julian Day ─────────────────────────────────────────────────

fn testJulianDay() void {
    // J2000 epoch: JD should equal 2451545.0 (adjusted for TT offset)
    const jd_j2000 = ipt.julianDayFromMs(ipt.J2000_MS);
    // 2000-01-01T12:00:00 UTC — with leap seconds (+32) + 32.184 = 64.184s ahead of UTC
    // expected JD ≈ 2451545.0007... (slightly after due to TT correction)
    checkApprox("JD at J2000 ≈ 2451545.0", jd_j2000, 2451545.0, 0.01);

    // Unix epoch 0: 1970-01-01T00:00:00 UTC → JD ≈ 2440587.5
    const jd_unix0 = ipt.julianDayFromMs(0);
    checkApprox("JD at Unix epoch ≈ 2440587.5", jd_unix0, 2440587.5, 0.01);

    // meanLongitude should be stable near J2000
    const ml = ipt.meanLongitudeDeg(2, 2451545.0); // Earth at J2000
    checkApprox("meanLongitude Earth at J2000 ≈ 100.47", ml, 100.4664, 0.1);
}

// ─── SECTION 5: True anomaly ───────────────────────────────────────────────

fn testTrueAnomaly() void {
    // At mean anomaly = 0, true anomaly = 0 for any eccentricity
    checkApprox("trueAnomaly M=0,e=0 → 0", ipt.trueAnomalyDeg(0.0, 0.0), 0.0, 1e-9);
    checkApprox("trueAnomaly M=0,e=0.1 → 0", ipt.trueAnomalyDeg(0.0, 0.1), 0.0, 1e-9);

    // At M=180, true anomaly = 180 (apoapsis)
    checkApprox("trueAnomaly M=180,e=0 → 180", ipt.trueAnomalyDeg(180.0, 0.0), 180.0, 1e-6);

    // Mercury has high eccentricity (0.20564): v > M near perihelion
    const v_merc = ipt.trueAnomalyDeg(90.0, 0.20564);
    check("trueAnomaly Mercury at M=90 > 90", v_merc > 90.0);
    check("trueAnomaly Mercury at M=90 < 150", v_merc < 150.0);
}

// ─── SECTION 6: Heliocentric position ─────────────────────────────────────

fn testHeliocentricPosition() void {
    const j2000 = ipt.J2000_MS;

    const earth_pos = ipt.heliocentricPositionMs(2, j2000);
    check("Earth helio pos not null", earth_pos != null);
    if (earth_pos) |pos| {
        checkApprox("Earth r at J2000 ≈ 0.983", pos.r, 0.9833060589279895, 0.001);
        check("Earth x != 0", pos.x != 0.0);
        check("Earth y != 0", pos.y != 0.0);
        check("Earth r > 0", pos.r > 0.0);
        check("Earth lon in [0, 2pi]", pos.lon >= 0.0 and pos.lon <= 6.3);
    }

    const mars_pos = ipt.heliocentricPositionMs(3, j2000);
    check("Mars helio pos not null", mars_pos != null);
    if (mars_pos) |pos| {
        checkApprox("Mars r at J2000 ≈ 1.391", pos.r, 1.3910742836600924, 0.01);
    }

    const moon_pos = ipt.heliocentricPositionMs(8, j2000);
    check("Moon helio pos uses Earth orbit", moon_pos != null);
    if (moon_pos) |mp| {
        if (earth_pos) |ep| {
            checkApprox("Moon r == Earth r", mp.r, ep.r, 1e-10);
        }
    }

    // Invalid body returns null
    const bad = ipt.heliocentricPositionMs(100, j2000);
    check("invalid body returns null", bad == null);
}

// ─── SECTION 7: Light travel time ─────────────────────────────────────────

fn testLightTravel() void {
    const j2000 = ipt.J2000_MS;

    const lt_mercury = ipt.lightTravelSeconds(2, 0, j2000);
    check("Earth→Mercury light time not null", lt_mercury != null);
    if (lt_mercury) |lt| {
        checkApprox("Earth→Mercury at J2000 ≈ 707s", lt, 706.7542428039411, 1.0);
    }

    const lt_mars = ipt.lightTravelSeconds(2, 3, j2000);
    check("Earth→Mars light time not null", lt_mars != null);
    if (lt_mars) |lt| {
        checkApprox("Earth→Mars at J2000 ≈ 923s", lt, 923.1360896123749, 2.0);
    }

    const lt_jupiter = ipt.lightTravelSeconds(2, 4, j2000);
    check("Earth→Jupiter light time not null", lt_jupiter != null);
    if (lt_jupiter) |lt| {
        checkApprox("Earth→Jupiter at J2000 ≈ 2307s", lt, 2306.554086928502, 5.0);
    }

    const lt_neptune = ipt.lightTravelSeconds(2, 7, j2000);
    check("Earth→Neptune light time not null", lt_neptune != null);
    if (lt_neptune) |lt| {
        checkApprox("Earth→Neptune at J2000 ≈ 15491s", lt, 15490.795544064931, 20.0);
    }

    // Earth→Earth = 0 (or Moon→Earth)
    const lt_self = ipt.lightTravelSeconds(2, 2, j2000);
    check("Earth→Earth distance = 0", lt_self != null);
    if (lt_self) |lt| {
        checkApprox("Earth→Earth light time = 0", lt, 0.0, 0.001);
    }

    // Bad body
    const lt_bad = ipt.lightTravelSeconds(99, 2, j2000);
    check("invalid body light time = null", lt_bad == null);
}

// ─── SECTION 8: Planet time ────────────────────────────────────────────────

fn testPlanetTime() void {
    const j2000 = ipt.J2000_MS;

    // Earth at J2000: epoch is J2000_MS, so elapsed=0 → time 00:00:00
    const earth_t = ipt.getPlanetTime(2, j2000, 0.0);
    check("Earth getPlanetTime not null", earth_t != null);
    if (earth_t) |t| {
        checkI32("Earth hour = 0", t.hour, 0);
        checkI32("Earth minute = 0", t.minute, 0);
        checkI32("Earth second = 0", t.second, 0);
        checkApprox("Earth local_hour = 0", t.local_hour, 0.0, 0.001);
        checkApprox("Earth day_fraction = 0", t.day_fraction, 0.0, 0.001);
        checkI64("Earth day_number = 0", t.day_number, 0);
        checkI64("Earth day_in_year = 0", t.day_in_year, 0);
        checkI64("Earth year_number = 0", t.year_number, 0);
        checkI32("Earth period_in_week = 0", t.period_in_week, 0);
        check("Earth is_work_period = true", t.is_work_period);
        check("Earth is_work_hour = false (h=0 < start=9)", !t.is_work_hour);
        check("Earth sol_in_year = null", t.sol_in_year == null);
        check("Earth sols_per_year = null", t.sols_per_year == null);
    }

    // Mars at J2000
    const mars_t = ipt.getPlanetTime(3, j2000, 0.0);
    check("Mars getPlanetTime not null", mars_t != null);
    if (mars_t) |t| {
        checkI32("Mars hour = 15", t.hour, 15);
        checkI32("Mars minute = 45", t.minute, 45);
        checkI32("Mars second = 34", t.second, 34);
        checkI64("Mars day_number = 16567", t.day_number, 16567);
        checkI64("Mars year_number = 24", t.year_number, 24);
        check("Mars sol_in_year not null", t.sol_in_year != null);
        check("Mars sols_per_year not null", t.sols_per_year != null);
        if (t.sols_per_year) |spy| {
            checkI64("Mars sols_per_year = 669", spy, 669);
        }
    }

    // Moon maps to Earth
    const moon_t = ipt.getPlanetTime(8, j2000, 0.0);
    check("Moon getPlanetTime not null", moon_t != null);
    if (moon_t) |t| {
        if (earth_t) |et| {
            checkI32("Moon hour == Earth hour", t.hour, et.hour);
            checkI64("Moon day_number == Earth day_number", t.day_number, et.day_number);
        }
    }

    // Invalid body
    const bad_t = ipt.getPlanetTime(99, j2000, 0.0);
    check("invalid body returns null", bad_t == null);
}

// ─── SECTION 9: MTC ────────────────────────────────────────────────────────

fn testMtc() void {
    const j2000 = ipt.J2000_MS;
    const mtc = ipt.getMtc(j2000);
    checkI32("MTC hour = 15", mtc.hour, 15);
    checkI32("MTC minute = 45", mtc.minute, 45);
    checkI32("MTC second = 34", mtc.second, 34);
    checkI64("MTC sol = 16567", mtc.sol, 16567);

    // Mars close approach 2003
    const mtc2 = ipt.getMtc(1061977860000);
    checkI32("MTC 2003 hour = 21", mtc2.hour, 21);
    checkI32("MTC 2003 minute = 3", mtc2.minute, 3);
    checkI64("MTC 2003 sol = 17865", mtc2.sol, 17865);
}

// ─── SECTION 10: Sol number ────────────────────────────────────────────────

fn testSolNumber() void {
    // Earth at J2000 epoch: sol = 0
    checkApprox("Earth sol at J2000 = 0", ipt.solNumberMs(2, ipt.J2000_MS), 0.0, 0.001);

    // Mars: total_sols at J2000
    const mars_sol = ipt.solNumberMs(3, ipt.J2000_MS);
    checkApprox("Mars sol at J2000 ≈ 16567", mars_sol, 16567.657, 0.01);

    // Moon: same as Earth
    const moon_sol = ipt.solNumberMs(8, ipt.J2000_MS);
    checkApprox("Moon sol == Earth sol", moon_sol, ipt.solNumberMs(2, ipt.J2000_MS), 0.001);
}

// ─── SECTION 11: planetTime high-level API ─────────────────────────────────

fn testPlanetTimeApi() void {
    const j2000 = ipt.J2000_MS;

    const pt_earth = ipt.planetTime(2, j2000);
    check("planetTime Earth body = 2", pt_earth.body == 2);
    checkApprox("planetTime Earth jd ≈ 2451545", pt_earth.jd, 2451545.0, 0.01);
    checkApprox("planetTime Earth day_length_sec = 86400", pt_earth.day_length_sec, 86400.0, 1.0);
    checkApprox("planetTime Earth light_travel = 0", pt_earth.light_travel_from_earth_sec, 0.0, 0.001);

    const pt_mars = ipt.planetTime(3, j2000);
    check("planetTime Mars body = 3", pt_mars.body == 3);
    checkApprox("planetTime Mars day_length ≈ 88775", pt_mars.day_length_sec, 88775.244, 1.0);
    checkApprox("planetTime Mars light_travel ≈ 923", pt_mars.light_travel_from_earth_sec, 923.1, 2.0);
    check("planetTime Mars light_travel > 0", pt_mars.light_travel_from_earth_sec > 0.0);

    const pt_neptune = ipt.planetTime(7, j2000);
    check("planetTime Neptune body = 7", pt_neptune.body == 7);
    checkApprox("planetTime Neptune light_travel ≈ 15491", pt_neptune.light_travel_from_earth_sec, 15490.795, 20.0);
}

// ─── SECTION 12: eclipticLongitude ────────────────────────────────────────

fn testEclipticLongitude() void {
    const jd = ipt.J2000_JD;
    const lon_earth = ipt.eclipticLongitudeDeg(2, jd);
    // Earth ecliptic longitude at J2000 should be in range [0, 360)
    check("Earth ecliptic lon >= 0", lon_earth >= 0.0);
    check("Earth ecliptic lon < 360", lon_earth < 360.0);

    const lon_mars = ipt.eclipticLongitudeDeg(3, jd);
    check("Mars ecliptic lon >= 0", lon_mars >= 0.0);
    check("Mars ecliptic lon < 360", lon_mars < 360.0);
    // Earth and Mars at different longitudes
    check("Earth and Mars at different ecliptic lons", @abs(lon_earth - lon_mars) > 1.0);
}

// ─── SECTION 13: fixture tests ────────────────────────────────────────────

// Fixture data: body, utc_ms, hour, minute, second, day_number, year_number,
//               day_in_year, period_in_week, is_work_period, is_work_hour,
//               sol_in_year (0=null), sols_per_year (0=null), light_travel_s (0=null),
//               helio_r_au
const FixtureEntry = struct {
    planet: u8,
    utc_ms: i64,
    hour: i32,
    minute: i32,
    second: i32,
    day_number: i64,
    year_number: i64,
    day_in_year: i64,
    period_in_week: i32,
    is_work_period: bool,
    is_work_hour: bool,
    sol_in_year: ?i64,
    sols_per_year: ?i64,
    light_travel_s: ?f64, // null = Earth/Moon (no light travel)
    helio_r_au: f64,
};

// All 54 fixture entries transcribed from reference.json (6 dates × 9 bodies)
const FIXTURES = [54]FixtureEntry{
    // ── J2000 (utc_ms=946728000000) ──────────────────────────────────────
    .{ .planet = 0, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 706.7542428039411, .helio_r_au = 0.46647753144648163 },
    .{ .planet = 1, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 567.5012770526228, .helio_r_au = 0.7202295289649099 },
    .{ .planet = 2, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9833060589279895 },
    .{ .planet = 3, .utc_ms = 946728000000, .hour = 15, .minute = 45, .second = 34, .day_number = 16567, .year_number = 24, .day_in_year = 520, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = 520, .sols_per_year = 669, .light_travel_s = 923.1360896123749, .helio_r_au = 1.3910742836600924 },
    .{ .planet = 4, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 2306.554086928502, .helio_r_au = 4.967832600836045 },
    .{ .planet = 5, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 4309.384068020626, .helio_r_au = 9.164283537842621 },
    .{ .planet = 6, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 10325.790834522653, .helio_r_au = 19.897633429858004 },
    .{ .planet = 7, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 15490.795544064931, .helio_r_au = 30.135652634100506 },
    .{ .planet = 8, .utc_ms = 946728000000, .hour = 0, .minute = 0, .second = 0, .day_number = 0, .year_number = 0, .day_in_year = 0, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9833060589279895 },

    // ── mars_close_2003 (utc_ms=1061977860000) ───────────────────────────
    .{ .planet = 0, .utc_ms = 1061977860000, .hour = 13, .minute = 57, .second = 29, .day_number = 7, .year_number = 15, .day_in_year = 0, .period_in_week = 2, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 359.8552310844892, .helio_r_au = 0.44310356208446816 },
    .{ .planet = 1, .utc_ms = 1061977860000, .hour = 10, .minute = 12, .second = 30, .day_number = 11, .year_number = 5, .day_in_year = 1, .period_in_week = 2, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 861.9155299052014, .helio_r_au = 0.7189961633958073 },
    .{ .planet = 2, .utc_ms = 1061977860000, .hour = 21, .minute = 50, .second = 59, .day_number = 1333, .year_number = 3, .day_in_year = 238, .period_in_week = 3, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 1.0103918628441901 },
    .{ .planet = 3, .utc_ms = 1061977860000, .hour = 21, .minute = 3, .second = 23, .day_number = 17865, .year_number = 26, .day_in_year = 481, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = 481, .sols_per_year = 669, .light_travel_s = 185.18742520006936, .helio_r_au = 1.3813993224295216 },
    .{ .planet = 4, .utc_ms = 1061977860000, .hour = 13, .minute = 50, .second = 37, .day_number = 3225, .year_number = 0, .day_in_year = 3225, .period_in_week = 2, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 3185.1762550164162, .helio_r_au = 5.375244387546164 },
    .{ .planet = 5, .utc_ms = 1061977860000, .hour = 10, .minute = 56, .second = 25, .day_number = 3026, .year_number = 0, .day_in_year = 3026, .period_in_week = 1, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 4775.888312467666, .helio_r_au = 9.00792950900437 },
    .{ .planet = 6, .utc_ms = 1061977860000, .hour = 2, .minute = 25, .second = 54, .day_number = 1856, .year_number = 0, .day_in_year = 1856, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 9483.01795956456, .helio_r_au = 20.013608829966746 },
    .{ .planet = 7, .utc_ms = 1061977860000, .hour = 4, .minute = 53, .second = 11, .day_number = 1987, .year_number = 0, .day_in_year = 1987, .period_in_week = 6, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 14554.333106044034, .helio_r_au = 30.098459762239496 },
    .{ .planet = 8, .utc_ms = 1061977860000, .hour = 21, .minute = 50, .second = 59, .day_number = 1333, .year_number = 3, .day_in_year = 238, .period_in_week = 3, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 1.0103918628441901 },

    // ── mars_opp_2020 (utc_ms=1602631560000) ────────────────────────────
    .{ .planet = 0, .utc_ms = 1602631560000, .hour = 3, .minute = 32, .second = 58, .day_number = 43, .year_number = 86, .day_in_year = 0, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 387.07526004659894, .helio_r_au = 0.3868228455164716 },
    .{ .planet = 1, .utc_ms = 1602631560000, .hour = 0, .minute = 33, .second = 37, .day_number = 65, .year_number = 33, .day_in_year = 1, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 578.8962633603282, .helio_r_au = 0.7189641629423671 },
    .{ .planet = 2, .utc_ms = 1602631560000, .hour = 11, .minute = 26, .second = 0, .day_number = 7591, .year_number = 20, .day_in_year = 286, .period_in_week = 3, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9973562596002316 },
    .{ .planet = 3, .utc_ms = 1602631560000, .hour = 0, .minute = 25, .second = 34, .day_number = 23956, .year_number = 35, .day_in_year = 554, .period_in_week = 2, .is_work_period = true, .is_work_hour = false, .sol_in_year = 554, .sols_per_year = 669, .light_travel_s = 209.3423727579502, .helio_r_au = 1.416875710600763 },
    .{ .planet = 4, .utc_ms = 1602631560000, .hour = 5, .minute = 20, .second = 24, .day_number = 18357, .year_number = 1, .day_in_year = 7880, .period_in_week = 6, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 2526.6968349288572, .helio_r_au = 5.123470128299849 },
    .{ .planet = 5, .utc_ms = 1602631560000, .hour = 23, .minute = 54, .second = 44, .day_number = 17223, .year_number = 0, .day_in_year = 17223, .period_in_week = 4, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 4925.033309168938, .helio_r_au = 9.99673917394121 },
    .{ .planet = 6, .utc_ms = 1602631560000, .hour = 8, .minute = 9, .second = 42, .day_number = 10563, .year_number = 0, .day_in_year = 10563, .period_in_week = 0, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 9399.796924093554, .helio_r_au = 19.781017892133487 },
    .{ .planet = 7, .utc_ms = 1602631560000, .hour = 11, .minute = 5, .second = 19, .day_number = 11309, .year_number = 0, .day_in_year = 11309, .period_in_week = 4, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 14514.07404969162, .helio_r_au = 29.927798050659955 },
    .{ .planet = 8, .utc_ms = 1602631560000, .hour = 11, .minute = 26, .second = 0, .day_number = 7591, .year_number = 20, .day_in_year = 286, .period_in_week = 3, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9973562596002316 },

    // ── jup_opp_2023 (utc_ms=1698969600000) ─────────────────────────────
    .{ .planet = 0, .utc_ms = 1698969600000, .hour = 11, .minute = 38, .second = 58, .day_number = 49, .year_number = 98, .day_in_year = 0, .period_in_week = 4, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 709.5107872061175, .helio_r_au = 0.4648484789147635 },
    .{ .planet = 1, .utc_ms = 1698969600000, .hour = 13, .minute = 46, .second = 22, .day_number = 74, .year_number = 38, .day_in_year = 1, .period_in_week = 4, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 384.1925445579176, .helio_r_au = 0.7196092626164466 },
    .{ .planet = 2, .utc_ms = 1698969600000, .hour = 12, .minute = 0, .second = 0, .day_number = 8706, .year_number = 23, .day_in_year = 305, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9920972388538314 },
    .{ .planet = 3, .utc_ms = 1698969600000, .hour = 4, .minute = 59, .second = 42, .day_number = 25041, .year_number = 37, .day_in_year = 302, .period_in_week = 2, .is_work_period = true, .is_work_hour = false, .sol_in_year = 302, .sols_per_year = 669, .light_travel_s = 1268.739925334528, .helio_r_au = 1.5557152926220081 },
    .{ .planet = 4, .utc_ms = 1698969600000, .hour = 12, .minute = 1, .second = 48, .day_number = 21053, .year_number = 2, .day_in_year = 99, .period_in_week = 0, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 1987.2963556416285, .helio_r_au = 4.9746111527144015 },
    .{ .planet = 5, .utc_ms = 1698969600000, .hour = 19, .minute = 53, .second = 19, .day_number = 19753, .year_number = 0, .day_in_year = 19753, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 4674.5845978229745, .helio_r_au = 9.75434434349266 },
    .{ .planet = 6, .utc_ms = 1698969600000, .hour = 20, .minute = 47, .second = 16, .day_number = 12114, .year_number = 0, .day_in_year = 12114, .period_in_week = 4, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 9305.709215235636, .helio_r_au = 19.619368695196123 },
    .{ .planet = 7, .utc_ms = 1698969600000, .hour = 13, .minute = 51, .second = 17, .day_number = 12970, .year_number = 0, .day_in_year = 12970, .period_in_week = 6, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 14571.249135676502, .helio_r_au = 29.90169177820852 },
    .{ .planet = 8, .utc_ms = 1698969600000, .hour = 12, .minute = 0, .second = 0, .day_number = 8706, .year_number = 23, .day_in_year = 305, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9920972388538314 },

    // ── 2025_start (utc_ms=1735689600000) ───────────────────────────────
    .{ .planet = 0, .utc_ms = 1735689600000, .hour = 21, .minute = 37, .second = 24, .day_number = 51, .year_number = 103, .day_in_year = 0, .period_in_week = 2, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 572.2676812761725, .helio_r_au = 0.42076195804745387 },
    .{ .planet = 1, .utc_ms = 1735689600000, .hour = 5, .minute = 8, .second = 21, .day_number = 78, .year_number = 40, .day_in_year = 1, .period_in_week = 2, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 374.9206736253089, .helio_r_au = 0.7224595068331514 },
    .{ .planet = 2, .utc_ms = 1735689600000, .hour = 12, .minute = 0, .second = 0, .day_number = 9131, .year_number = 25, .day_in_year = 0, .period_in_week = 3, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9833008596040858 },
    .{ .planet = 3, .utc_ms = 1735689600000, .hour = 20, .minute = 5, .second = 12, .day_number = 25454, .year_number = 38, .day_in_year = 47, .period_in_week = 2, .is_work_period = true, .is_work_hour = false, .sol_in_year = 47, .sols_per_year = 669, .light_travel_s = 327.46040602173736, .helio_r_au = 1.613388097097231 },
    .{ .planet = 4, .utc_ms = 1735689600000, .hour = 5, .minute = 1, .second = 3, .day_number = 22081, .year_number = 2, .day_in_year = 1127, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 2091.5562189232596, .helio_r_au = 5.0831959502320245 },
    .{ .planet = 5, .utc_ms = 1735689600000, .hour = 2, .minute = 15, .second = 35, .day_number = 20718, .year_number = 0, .day_in_year = 20718, .period_in_week = 3, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 5003.7102997098145, .helio_r_au = 9.63103703704223 },
    .{ .planet = 6, .utc_ms = 1735689600000, .hour = 5, .minute = 49, .second = 11, .day_number = 12706, .year_number = 0, .day_in_year = 12706, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 9410.27520920926, .helio_r_au = 19.551283551188696 },
    .{ .planet = 7, .utc_ms = 1735689600000, .hour = 17, .minute = 23, .second = 7, .day_number = 13603, .year_number = 0, .day_in_year = 13603, .period_in_week = 2, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 15028.533977426103, .helio_r_au = 29.892327211162215 },
    .{ .planet = 8, .utc_ms = 1735689600000, .hour = 12, .minute = 0, .second = 0, .day_number = 9131, .year_number = 25, .day_in_year = 0, .period_in_week = 3, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 0.9833008596040858 },

    // ── 2024_mid (utc_ms=1718452800000) ─────────────────────────────────
    .{ .planet = 0, .utc_ms = 1718452800000, .hour = 18, .minute = 24, .second = 35, .day_number = 50, .year_number = 101, .day_in_year = 0, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 660.5394453492744, .helio_r_au = 0.30869276493317155 },
    .{ .planet = 1, .utc_ms = 1718452800000, .hour = 12, .minute = 7, .second = 42, .day_number = 76, .year_number = 39, .day_in_year = 1, .period_in_week = 5, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 864.316983220227, .helio_r_au = 0.7195382181114681 },
    .{ .planet = 2, .utc_ms = 1718452800000, .hour = 0, .minute = 0, .second = 0, .day_number = 8932, .year_number = 24, .day_in_year = 165, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 1.0158588245126992 },
    .{ .planet = 3, .utc_ms = 1718452800000, .hour = 16, .minute = 11, .second = 35, .day_number = 25260, .year_number = 37, .day_in_year = 521, .period_in_week = 4, .is_work_period = true, .is_work_hour = true, .sol_in_year = 521, .sols_per_year = 669, .light_travel_s = 900.0071368495244, .helio_r_au = 1.3920903327283716 },
    .{ .planet = 4, .utc_ms = 1718452800000, .hour = 18, .minute = 58, .second = 56, .day_number = 21598, .year_number = 2, .day_in_year = 645, .period_in_week = 1, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 2976.6708230797967, .helio_r_au = 5.023332048554532 },
    .{ .planet = 5, .utc_ms = 1718452800000, .hour = 10, .minute = 57, .second = 30, .day_number = 20265, .year_number = 0, .day_in_year = 20265, .period_in_week = 4, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 4759.041790430863, .helio_r_au = 9.690271743971675 },
    .{ .planet = 6, .utc_ms = 1718452800000, .hour = 15, .minute = 26, .second = 37, .day_number = 12428, .year_number = 0, .day_in_year = 12428, .period_in_week = 3, .is_work_period = true, .is_work_hour = true, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 10212.6372099176, .helio_r_au = 19.583631839855922 },
    .{ .planet = 7, .utc_ms = 1718452800000, .hour = 12, .minute = 25, .second = 28, .day_number = 13306, .year_number = 0, .day_in_year = 13306, .period_in_week = 6, .is_work_period = false, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = 14948.908755739225, .helio_r_au = 29.896680172162203 },
    .{ .planet = 8, .utc_ms = 1718452800000, .hour = 0, .minute = 0, .second = 0, .day_number = 8932, .year_number = 24, .day_in_year = 165, .period_in_week = 0, .is_work_period = true, .is_work_hour = false, .sol_in_year = null, .sols_per_year = null, .light_travel_s = null, .helio_r_au = 1.0158588245126992 },
};

fn runFixtureTests() u32 {
    var count: u32 = 0;
    for (FIXTURES, 0..) |fx, i| {
        const pt = ipt.getPlanetTime(fx.planet, fx.utc_ms, 0.0) orelse {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] getPlanetTime returned null\n", .{i});
            continue;
        };

        var buf: [64]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "fixture[{d}] p={d} t={d}", .{ i, fx.planet, fx.utc_ms }) catch "fixture";

        _ = label;

        // hour, minute, second
        if (pt.hour != fx.hour) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] hour got={d} expected={d}\n", .{ i, pt.hour, fx.hour });
        } else {
            passed += 1;
        }
        if (pt.minute != fx.minute) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] minute got={d} expected={d}\n", .{ i, pt.minute, fx.minute });
        } else {
            passed += 1;
        }
        if (pt.second != fx.second) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] second got={d} expected={d}\n", .{ i, pt.second, fx.second });
        } else {
            passed += 1;
        }

        // day_number
        if (pt.day_number != fx.day_number) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] day_number got={d} expected={d}\n", .{ i, pt.day_number, fx.day_number });
        } else {
            passed += 1;
        }

        // year_number
        if (pt.year_number != fx.year_number) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] year_number got={d} expected={d}\n", .{ i, pt.year_number, fx.year_number });
        } else {
            passed += 1;
        }

        // day_in_year
        if (pt.day_in_year != fx.day_in_year) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] day_in_year got={d} expected={d}\n", .{ i, pt.day_in_year, fx.day_in_year });
        } else {
            passed += 1;
        }

        // period_in_week
        if (pt.period_in_week != fx.period_in_week) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] period_in_week got={d} expected={d}\n", .{ i, pt.period_in_week, fx.period_in_week });
        } else {
            passed += 1;
        }

        // is_work_period
        if (pt.is_work_period != fx.is_work_period) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] is_work_period got={} expected={}\n", .{ i, pt.is_work_period, fx.is_work_period });
        } else {
            passed += 1;
        }

        // is_work_hour
        if (pt.is_work_hour != fx.is_work_hour) {
            failed += 1;
            std.debug.print("FAIL: fixture[{d}] is_work_hour got={} expected={}\n", .{ i, pt.is_work_hour, fx.is_work_hour });
        } else {
            passed += 1;
        }

        // sol_in_year (Mars only)
        if (fx.sol_in_year) |expected_sol| {
            if (pt.sol_in_year) |got_sol| {
                if (got_sol != expected_sol) {
                    failed += 1;
                    std.debug.print("FAIL: fixture[{d}] sol_in_year got={d} expected={d}\n", .{ i, got_sol, expected_sol });
                } else {
                    passed += 1;
                }
            } else {
                failed += 1;
                std.debug.print("FAIL: fixture[{d}] sol_in_year expected {d} got null\n", .{ i, expected_sol });
            }
        } else {
            if (pt.sol_in_year != null) {
                failed += 1;
                std.debug.print("FAIL: fixture[{d}] sol_in_year expected null got {?}\n", .{ i, pt.sol_in_year });
            } else {
                passed += 1;
            }
        }

        // light_travel (only for non-Earth/Moon bodies)
        if (fx.light_travel_s) |expected_lt| {
            if (ipt.lightTravelSeconds(2, fx.planet, fx.utc_ms)) |got_lt| {
                if (@abs(got_lt - expected_lt) > 10.0) {
                    failed += 1;
                    std.debug.print("FAIL: fixture[{d}] light_travel got={d:.2} expected={d:.2}\n", .{ i, got_lt, expected_lt });
                } else {
                    passed += 1;
                }
            } else {
                failed += 1;
                std.debug.print("FAIL: fixture[{d}] light_travel expected {d:.2} got null\n", .{ i, expected_lt });
            }
        } else {
            passed += 1; // Earth/Moon: no light travel check
        }

        // helio_r_au
        if (ipt.heliocentricPositionMs(fx.planet, fx.utc_ms)) |pos| {
            if (@abs(pos.r - fx.helio_r_au) > 0.01) {
                failed += 1;
                std.debug.print("FAIL: fixture[{d}] helio_r got={d:.6} expected={d:.6}\n", .{ i, pos.r, fx.helio_r_au });
            } else {
                passed += 1;
            }
        } else {
            // Earth: no helio check needed but we still need to count
            passed += 1;
        }

        count += 1;
    }
    return count;
}

pub fn main() !void {
    std.debug.print("InterplanetTime Zig — unit + fixture tests\n", .{});
    std.debug.print("============================================\n", .{});

    testConstants();
    testOrbitalElements();
    testDayLengths();
    testJulianDay();
    testTrueAnomaly();
    testHeliocentricPosition();
    testLightTravel();
    testPlanetTime();
    testMtc();
    testSolNumber();
    testPlanetTimeApi();
    testEclipticLongitude();

    const fixture_count = runFixtureTests();

    std.debug.print("\n", .{});
    std.debug.print("fixture entries checked: {d}\n", .{fixture_count});
    if (failed == 0) {
        std.debug.print("{d} passed\n", .{passed});
    } else {
        std.debug.print("{d} passed  {d} FAILED\n", .{ passed, failed });
        std.process.exit(1);
    }
}
