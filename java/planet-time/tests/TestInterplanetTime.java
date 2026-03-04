import com.interplanet.time.*;

/**
 * TestInterplanetTime — standalone unit tests for the InterplanetTime Java library.
 * Story 18.2 — Java library
 *
 * Runs without JUnit. Exit code 0 = all pass, 1 = at least one failure.
 */
public class TestInterplanetTime {

    static int passed = 0;
    static int failed = 0;

    static void check(String name, boolean cond) {
        if (cond) {
            passed++;
            System.out.println("PASS: " + name);
        } else {
            failed++;
            System.out.println("FAIL: " + name);
        }
    }

    static void checkApprox(String name, double actual, double expected, double delta) {
        check(name + " (" + actual + " ≈ " + expected + ")",
              Math.abs(actual - expected) <= delta);
    }

    // ── Constants ─────────────────────────────────────────────────────────────

    static void testConstants() {
        System.out.println("\n── Constants ────────────────────────────────");
        check("J2000_MS", InterplanetTime.J2000_MS == 946728000000L);
        check("J2000_JD", InterplanetTime.J2000_JD == 2451545.0);
        check("EARTH_DAY_MS", InterplanetTime.EARTH_DAY_MS == 86400000L);
        check("MARS_SOL_MS", InterplanetTime.MARS_SOL_MS == 88775244L);
        check("MARS_EPOCH_MS < 0", InterplanetTime.MARS_EPOCH_MS < 0);
        checkApprox("AU_SECONDS ≈ 499", InterplanetTime.AU_SECONDS, 499.004, 0.01);
    }

    // ── getPlanetTime ─────────────────────────────────────────────────────────

    static void testGetPlanetTime() {
        System.out.println("\n── getPlanetTime ────────────────────────────");

        // J2000.0 reference: 946728000000L ms
        long j2000 = InterplanetTime.J2000_MS;

        // Earth at J2000.0 — epoch is J2000_MS so elapsedMs=0, dayFrac=0, hour=0
        PlanetTime earth = InterplanetTime.getPlanetTime(Planet.EARTH, j2000);
        check("Earth hour at J2000 == 0", earth.hour() == 0);
        check("Earth minute valid", earth.minute() >= 0 && earth.minute() < 60);
        check("Earth second valid", earth.second() >= 0 && earth.second() < 60);
        check("Earth no sol fields", earth.solInYear() == null && earth.solsPerYear() == null);
        check("Earth timeStr format", earth.timeStr().matches("\\d{2}:\\d{2}"));
        check("Earth timeStrFull format", earth.timeStrFull().matches("\\d{2}:\\d{2}:\\d{2}"));

        // Mars at J2000.0
        PlanetTime mars = InterplanetTime.getPlanetTime(Planet.MARS, j2000);
        check("Mars hour valid", mars.hour() >= 0 && mars.hour() < 24);
        check("Mars minute valid", mars.minute() >= 0 && mars.minute() < 60);
        check("Mars sol fields not null", mars.solInYear() != null && mars.solsPerYear() != null);
        check("Mars solsPerYear ≈ 668", mars.solsPerYear() >= 660 && mars.solsPerYear() <= 675);

        // Moon uses Earth data (same result as Earth at same time)
        PlanetTime moon = InterplanetTime.getPlanetTime(Planet.MOON, j2000);
        check("Moon hour same as Earth", moon.hour() == earth.hour());

        // All planets
        for (Planet p : Planet.values()) {
            PlanetTime pt = InterplanetTime.getPlanetTime(p, j2000);
            check("Planet " + p.displayName() + " hour ∈ [0,23]",
                  pt.hour() >= 0 && pt.hour() < 24);
        }

        // Known test date: 2003-08-27T00:00:00Z (closest Mars approach)
        long aug2003 = 1061942400000L;
        PlanetTime marsAug = InterplanetTime.getPlanetTime(Planet.MARS, aug2003);
        check("Mars Aug 2003 hour valid", marsAug.hour() >= 0 && marsAug.hour() < 24);
    }

    // ── getMTC ────────────────────────────────────────────────────────────────

    static void testGetMTC() {
        System.out.println("\n── getMTC ───────────────────────────────────");
        long j2000 = InterplanetTime.J2000_MS;
        MTC mtc = InterplanetTime.getMTC(j2000);
        check("MTC sol ≥ 0", mtc.sol() >= 0);
        check("MTC hour ∈ [0,23]", mtc.hour() >= 0 && mtc.hour() < 24);
        check("MTC minute ∈ [0,59]", mtc.minute() >= 0 && mtc.minute() < 60);
        // J2000.0 MTC ≈ 15:39 (from JS/Python reference)
        check("MTC hour at J2000 ∈ [14,17]", mtc.hour() >= 14 && mtc.hour() <= 17);
        check("MTC string format", mtc.mtcStr().matches("\\d{2}:\\d{2}"));
    }

    // ── lightTravelSeconds ────────────────────────────────────────────────────

    static void testLightTravel() {
        System.out.println("\n── lightTravelSeconds ───────────────────────");

        // Earth–Mars at closest approach 2003-08-27: ~186 s
        long aug2003 = 1061942400000L;
        double lt1 = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.MARS, aug2003);
        checkApprox("Earth-Mars Aug 2003 ≈ 186 s", lt1, 186.0, 20.0);

        // Earth–Mars at far opposition 2020-10-13: ~207 s
        long oct2020 = 1602547200000L;
        double lt2 = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.MARS, oct2020);
        checkApprox("Earth-Mars Oct 2020 ≈ 207 s", lt2, 207.0, 25.0);

        // Earth–Jupiter 2023-11-03: ~2010 s
        long nov2023 = 1699056000000L;
        double lt3 = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.JUPITER, nov2023);
        checkApprox("Earth-Jupiter Nov 2023 ≈ 2010 s", lt3, 2010.0, 150.0);

        // Earth–Moon: bodies co-located in our model → 0
        double lt4 = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.MOON, aug2003);
        check("Earth-Moon ≥ 0", lt4 >= 0.0);

        // Symmetry: a→b = b→a
        double fwd = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.MARS, aug2003);
        double rev = InterplanetTime.lightTravelSeconds(Planet.MARS, Planet.EARTH, aug2003);
        checkApprox("Light time symmetric", fwd, rev, 0.001);
    }

    // ── checkLineOfSight ──────────────────────────────────────────────────────

    static void testLineOfSight() {
        System.out.println("\n── checkLineOfSight ─────────────────────────");

        // Earth–Mars at closest approach (opposition): should be clear
        long aug2003 = 1061942400000L;
        LineOfSight los1 = InterplanetTime.checkLineOfSight(Planet.EARTH, Planet.MARS, aug2003);
        check("Earth-Mars opposition: not blocked", !los1.blocked());
        check("Earth-Mars opposition: elong > 120°", los1.elongDeg() > 120.0);

        // Earth–Moon: co-located → always clear
        LineOfSight los2 = InterplanetTime.checkLineOfSight(Planet.EARTH, Planet.MOON, aug2003);
        check("Earth-Moon: always clear", los2.clear());
        check("Earth-Moon: not blocked", !los2.blocked());

        // Any pair: result flags are consistent
        LineOfSight los3 = InterplanetTime.checkLineOfSight(Planet.EARTH, Planet.MARS, aug2003);
        check("LOS flags consistent", (los3.clear() || los3.degraded() || los3.blocked())
              && !(los3.clear() && los3.blocked()));
    }

    // ── formatLightTime ───────────────────────────────────────────────────────

    static void testFormatLightTime() {
        System.out.println("\n── formatLightTime ──────────────────────────");
        check("45 s", InterplanetTime.formatLightTime(45.0).contains("s"));
        check("186 s = 3 min", InterplanetTime.formatLightTime(186.0).contains("min"));
        check("60 s = 1 min", InterplanetTime.formatLightTime(60.0).equals("1 min"));
    }

    // ── Work hour logic ───────────────────────────────────────────────────────

    static void testWorkHour() {
        System.out.println("\n── isWorkHour logic ─────────────────────────");
        // Scan 24 Earth hours and verify work hours fall in 09:00–17:00
        long baseMs = 1700000000000L; // arbitrary Monday
        boolean anyWork = false;
        for (int delta = 0; delta < 24; delta++) {
            long t = baseMs + (long) delta * 3600_000;
            PlanetTime pt = InterplanetTime.getPlanetTime(Planet.EARTH, t);
            if (pt.isWorkHour()) {
                anyWork = true;
                check("Work hour h ∈ [9,16]", pt.hour() >= 9 && pt.hour() < 17);
            }
        }
        check("Some work hours exist over 24h scan", anyWork);
    }

    // ── Planet enum ───────────────────────────────────────────────────────────

    static void testPlanetEnum() {
        System.out.println("\n── Planet enum ──────────────────────────────");
        check("Planet.fromString MARS", Planet.fromString("mars") == Planet.MARS);
        check("Planet.fromString EARTH", Planet.fromString("Earth") == Planet.EARTH);
        check("Planet.fromString unknown", Planet.fromString("XYZZY") == null);
        check("Planet.MARS.displayName()", Planet.MARS.displayName().equals("Mars"));
        check("Planet count = 9", Planet.values().length == 9);
    }

    // ── lowerQuartileLightTime ────────────────────────────────────────────────

    static void testLowerQuartile() {
        System.out.println("\n── lowerQuartileLightTime ───────────────────");
        long refMs = InterplanetTime.J2000_MS;
        double q25 = InterplanetTime.lowerQuartileLightTime(Planet.EARTH, Planet.MARS, refMs);
        // Earth-Mars range: ~183 s (min) to ~1248 s (max); q25 can vary by epoch
        check("Earth-Mars q25 > 100 s", q25 > 100.0);
        check("Earth-Mars q25 < 1250 s", q25 < 1250.0);
    }

    // ── Main ──────────────────────────────────────────────────────────────────

    public static void main(String[] args) {
        System.out.println("InterplanetTime Java library — unit tests");
        System.out.println("==========================================");

        testConstants();
        testGetPlanetTime();
        testGetMTC();
        testLightTravel();
        testLineOfSight();
        testFormatLightTime();
        testWorkHour();
        testPlanetEnum();
        testLowerQuartile();

        System.out.printf("%n══════════════════════════════════════════%n");
        System.out.printf("%d passed  %d failed%n", passed, failed);

        if (failed > 0) {
            System.exit(1);
        }
    }
}
