package com.interplanet.time;

/**
 * InterplanetTime — Java port of planet-time.js
 * Story 18.2 — Java library (Maven Central)
 *
 * All public methods are static. Timestamps are UTC milliseconds since the Unix epoch.
 *
 * Usage:
 *   PlanetTime mt = InterplanetTime.getPlanetTime(Planet.MARS, System.currentTimeMillis());
 *   MTC mtc = InterplanetTime.getMTC(System.currentTimeMillis());
 *   double lt = InterplanetTime.lightTravelSeconds(Planet.EARTH, Planet.MARS, utcMs);
 */
public final class InterplanetTime {

    private InterplanetTime() {}

    // ── Version ────────────────────────────────────────────────────────────────

    public static final String VERSION = "1.1.0";

    // ── Epoch constants ────────────────────────────────────────────────────────

    public static final long   J2000_MS       = 946728000000L;
    public static final double J2000_JD       = 2451545.0;
    public static final long   EARTH_DAY_MS   = 86400000L;
    public static final long   MARS_EPOCH_MS  = -524069761536L;
    public static final long   MARS_SOL_MS    = 88775244L;
    public static final double AU_KM          = 149597870.7;
    public static final double C_KMS          = 299792.458;
    public static final double AU_SECONDS     = AU_KM / C_KMS;

    private static final double UNIX_EPOCH_JD = 2440587.5;

    // ── Planet data arrays (indexed by Planet.ordinal()) ──────────────────────
    // 0=Mercury,1=Venus,2=Earth,3=Mars,4=Jupiter,5=Saturn,6=Uranus,7=Neptune,8=Moon

    /** Display names. */
    static final String[] PLANETS_NAME = {
        "Mercury","Venus","Earth","Mars","Jupiter","Saturn","Uranus","Neptune","Moon"
    };

    /** Zone prefixes for zoneId (null for Earth at index 2). */
    private static final String[] ZONE_PREFIX = {
        "MMT", "VMT", null, "AMT", "JMT", "SMT", "UMT", "NMT", "LMT"
    };

    /** Solar day in milliseconds. Moon = Earth. */
    private static final double[] SOLAR_DAY_MS = {
        175.9408 * EARTH_DAY_MS,  // Mercury
        116.7500 * EARTH_DAY_MS,  // Venus
        86400000.0,                // Earth
        88775244.0,                // Mars
        9.9250   * 3600000,        // Jupiter
        10.5606  * 3600000,        // Saturn
        17.2479  * 3600000,        // Uranus
        16.1100  * 3600000,        // Neptune
        86400000.0,                // Moon (Earth)
    };

    /** Sidereal year in milliseconds. Moon = Earth. */
    private static final double[] SIDEREAL_YR_MS = {
        87.9691   * EARTH_DAY_MS,  // Mercury
        224.701   * EARTH_DAY_MS,  // Venus
        365.25636 * EARTH_DAY_MS,  // Earth
        686.9957  * EARTH_DAY_MS,  // Mars
        4332.589  * EARTH_DAY_MS,  // Jupiter
        10759.22  * EARTH_DAY_MS,  // Saturn
        30688.5   * EARTH_DAY_MS,  // Uranus
        60195.0   * EARTH_DAY_MS,  // Neptune
        365.25636 * EARTH_DAY_MS,  // Moon (Earth)
    };

    /** Days per work period. */
    private static final double[] DAYS_PER_PERIOD = {
        1, 1, 1, 1, 2.5, 2.25, 1, 1, 1
    };

    /** Work periods per week. All = 5 except outer planets stay 5. */
    private static final int[] WORK_PERIODS_PER_WEEK = { 5, 5, 5, 5, 5, 5, 5, 5, 5 };

    /** Total periods per week. All = 7. */
    private static final int[] PERIODS_PER_WEEK = { 7, 7, 7, 7, 7, 7, 7, 7, 7 };

    /** Work hours start (local hour). */
    private static final int[] WORK_START = { 8, 8, 9, 9, 8, 8, 8, 8, 9 };

    /** Work hours end (local hour). */
    private static final int[] WORK_END = { 16, 16, 17, 17, 16, 16, 16, 16, 17 };

    /** Epoch ms used per planet. Mars uses MARS_EPOCH_MS, others J2000_MS. */
    private static final long[] EPOCH_MS = {
        J2000_MS, J2000_MS, J2000_MS, MARS_EPOCH_MS,
        J2000_MS, J2000_MS, J2000_MS, J2000_MS, J2000_MS,
    };

    // ── Orbital elements (Meeus Table 31.a) ──────────────────────────────────
    // Moon uses Earth's orbital elements.

    private static final double[] ORB_L0 = {
        252.2507, 181.9798, 100.4664, 355.4330,
         34.3515,  50.0775, 314.0550, 304.3480,
        100.4664   // Moon = Earth
    };
    private static final double[] ORB_DL = {
        149474.0722, 58519.2130, 36000.7698, 19141.6964,
          3036.3027,  1223.5093,   429.8633,   219.8997,
         36000.7698   // Moon = Earth
    };
    private static final double[] ORB_OM0 = {
         77.4561, 131.5637, 102.9373, 336.0600,
         14.3320,  93.0572, 173.0052,  48.1234,
        102.9373   // Moon = Earth
    };
    private static final double[] ORB_E0 = {
        0.20564, 0.00677, 0.01671, 0.09341,
        0.04849, 0.05551, 0.04630, 0.00899,
        0.01671  // Moon = Earth
    };
    private static final double[] ORB_A = {
         0.38710, 0.72333, 1.00000, 1.52366,
         5.20336, 9.53707, 19.1912, 30.0690,
         1.00000  // Moon = Earth
    };

    // ── Leap-second table (TAI − UTC, UTC ms when offset took effect) ─────────

    private static final long[][] LEAP_SECS = {
        {10,   63072000000L}, {11,  78796800000L}, {12,  94694400000L},
        {13,  126230400000L}, {14, 157766400000L}, {15, 189302400000L},
        {16,  220924800000L}, {17, 252460800000L}, {18, 283996800000L},
        {19,  315532800000L}, {20, 362793600000L}, {21, 394329600000L},
        {22,  425865600000L}, {23, 489024000000L}, {24, 567993600000L},
        {25,  631152000000L}, {26, 662688000000L}, {27, 709948800000L},
        {28,  741484800000L}, {29, 773020800000L}, {30, 820454400000L},
        {31,  867715200000L}, {32, 915148800000L}, {33,1136073600000L},
        {34, 1230768000000L}, {35,1341100800000L}, {36,1435708800000L},
        {37, 1483228800000L},
    };

    // ── Internal orbital math ─────────────────────────────────────────────────

    private static int taiMinusUtc(long utcMs) {
        int offset = 10;
        for (long[] row : LEAP_SECS) {
            if (utcMs >= row[1]) offset = (int) row[0];
            else break;
        }
        return offset;
    }

    private static double jde(long utcMs) {
        double ttMs = utcMs + (taiMinusUtc(utcMs) + 32.184) * 1000.0;
        return UNIX_EPOCH_JD + ttMs / 86400000.0;
    }

    private static double jc(long utcMs) {
        return (jde(utcMs) - J2000_JD) / 36525.0;
    }

    private static double keplerE(double M, double e) {
        double E = M;
        for (int i = 0; i < 50; i++) {
            double dE = (M - E + e * Math.sin(E)) / (1 - e * Math.cos(E));
            E += dE;
            if (Math.abs(dE) < 1e-12) break;
        }
        return E;
    }

    private static HelioPos helioPos(Planet planet, long utcMs) {
        // Moon uses Earth's orbital data
        int idx = (planet == Planet.MOON) ? Planet.EARTH.ordinal() : planet.ordinal();
        double T   = jc(utcMs);
        double TAU = 2 * Math.PI;
        double D2R = Math.PI / 180.0;

        double L  = ((ORB_L0[idx] + ORB_DL[idx] * T) * D2R % TAU + TAU) % TAU;
        double om = ORB_OM0[idx] * D2R;
        double M  = ((L - om) % TAU + TAU) % TAU;
        double e  = ORB_E0[idx];
        double a  = ORB_A[idx];

        double E   = keplerE(M, e);
        double v   = 2 * Math.atan2(
            Math.sqrt(1 + e) * Math.sin(E / 2),
            Math.sqrt(1 - e) * Math.cos(E / 2)
        );
        double r   = a * (1 - e * Math.cos(E));
        double lon = ((v + om) % TAU + TAU) % TAU;

        return new HelioPos(r * Math.cos(lon), r * Math.sin(lon), r, lon);
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Get the current time on a planet.
     *
     * @param planet  the planet
     * @param utcMs   UTC milliseconds since Unix epoch
     * @return PlanetTime
     */
    public static PlanetTime getPlanetTime(Planet planet, long utcMs) {
        return getPlanetTime(planet, utcMs, 0.0);
    }

    /**
     * Get the local time on a planet at a given zone offset.
     *
     * @param planet     the planet
     * @param utcMs      UTC milliseconds since Unix epoch
     * @param tzOffsetH  local hours from planet prime meridian
     * @return PlanetTime
     */
    public static PlanetTime getPlanetTime(Planet planet, long utcMs, double tzOffsetH) {
        // Moon uses Earth's data
        int idx = (planet == Planet.MOON) ? Planet.EARTH.ordinal() : planet.ordinal();

        double solarDay  = SOLAR_DAY_MS[idx];
        double siderealYr = SIDEREAL_YR_MS[idx];
        long   epochMs   = EPOCH_MS[idx];

        double elapsedMs = (utcMs - epochMs) + tzOffsetH / 24.0 * solarDay;
        double totalDays = elapsedMs / solarDay;
        long   dayNumber = (long) Math.floor(totalDays);
        double dayFrac   = totalDays - dayNumber;

        double localHour = dayFrac * 24.0;
        int    h         = (int) Math.floor(localHour);
        int    m         = (int) Math.floor((localHour - h) * 60);
        int    s         = (int) Math.floor(((localHour - h) * 60 - m) * 60);

        double daysPerPeriod = DAYS_PER_PERIOD[idx];
        int    periodsPerWk  = PERIODS_PER_WEEK[idx];
        int    workPeriodsWk = WORK_PERIODS_PER_WEEK[idx];

        double totalPeriods  = totalDays / daysPerPeriod;
        int    periodInWeek  = (int)(((long) Math.floor(totalPeriods) % periodsPerWk + periodsPerWk) % periodsPerWk);

        boolean isWorkPeriod = periodInWeek < workPeriodsWk;
        boolean isWorkHour   = isWorkPeriod
            && localHour >= WORK_START[idx]
            && localHour <  WORK_END[idx];

        double yearLen    = siderealYr / solarDay;
        long   yearNumber = (long) Math.floor(totalDays / yearLen);
        double dayInYear  = totalDays - yearNumber * yearLen;

        Integer solInYear  = null;
        Integer solsPerYear = null;
        if (planet == Planet.MARS) {
            double spyf    = SIDEREAL_YR_MS[Planet.MARS.ordinal()] / SOLAR_DAY_MS[Planet.MARS.ordinal()];
            solInYear      = (int) Math.floor(dayInYear);
            solsPerYear    = (int) Math.round(spyf);
        }

        String ts  = String.format("%02d:%02d", h, m);
        String tsf = String.format("%02d:%02d:%02d", h, m, s);

        // zoneId: null for Earth; "PREFIX+N" or "PREFIX-N" for all others
        int    planetIdx = planet.ordinal();
        String prefix    = ZONE_PREFIX[planetIdx];
        String zoneId    = null;
        if (prefix != null) {
            int offsetInt = (int) Math.round(tzOffsetH);
            zoneId = prefix + (offsetInt >= 0 ? "+" : "-") + Math.abs(offsetInt);
        }

        return new PlanetTime(
            h, m, s, localHour, dayFrac,
            dayNumber, (int) Math.floor(dayInYear),
            yearNumber, periodInWeek,
            isWorkPeriod, isWorkHour,
            ts, tsf, solInYear, solsPerYear, zoneId
        );
    }

    /**
     * Get Mars Coordinated Time (MTC).
     *
     * @param utcMs UTC milliseconds since Unix epoch
     * @return MTC
     */
    public static MTC getMTC(long utcMs) {
        double totalSols = (double)(utcMs - MARS_EPOCH_MS) / MARS_SOL_MS;
        long   sol       = (long) Math.floor(totalSols);
        double frac      = totalSols - sol;
        int    h         = (int) Math.floor(frac * 24);
        int    m         = (int) Math.floor((frac * 24 - h) * 60);
        int    s         = (int) Math.floor(((frac * 24 - h) * 60 - m) * 60);
        return new MTC(sol, h, m, s, String.format("%02d:%02d", h, m));
    }

    /**
     * Distance in AU between two solar system bodies.
     *
     * @param a     first body
     * @param b     second body
     * @param utcMs UTC milliseconds since Unix epoch
     * @return distance in AU
     */
    public static double bodyDistanceAu(Planet a, Planet b, long utcMs) {
        HelioPos pA = helioPos(a, utcMs);
        HelioPos pB = helioPos(b, utcMs);
        double dx = pA.x() - pB.x();
        double dy = pA.y() - pB.y();
        return Math.sqrt(dx * dx + dy * dy);
    }

    /**
     * One-way light travel time in seconds between two solar system bodies.
     *
     * @param a     source body
     * @param b     destination body
     * @param utcMs UTC milliseconds since Unix epoch
     * @return light travel time in seconds
     */
    public static double lightTravelSeconds(Planet a, Planet b, long utcMs) {
        return bodyDistanceAu(a, b, utcMs) * AU_SECONDS;
    }

    /**
     * Check whether the line of sight between two bodies is clear.
     *
     * @param a     source body
     * @param b     destination body
     * @param utcMs UTC milliseconds since Unix epoch
     * @return LineOfSight describing the visibility state
     */
    public static LineOfSight checkLineOfSight(Planet a, Planet b, long utcMs) {
        HelioPos pA = helioPos(a, utcMs);
        HelioPos pB = helioPos(b, utcMs);

        double dx = pB.x() - pA.x();
        double dy = pB.y() - pA.y();
        double d2 = dx * dx + dy * dy;

        // Guard: co-located bodies (e.g. Earth + Moon)
        if (d2 < 1e-12) {
            return new LineOfSight(true, false, false, null, 0.0);
        }

        double dist = Math.sqrt(d2);
        double t    = Math.max(0.0, Math.min(1.0,
                        -(pA.x() * dx + pA.y() * dy) / d2));
        double cx   = pA.x() + t * dx;
        double cy   = pA.y() + t * dy;
        double closest = Math.sqrt(cx * cx + cy * cy);

        double cosEl = (-pA.x() * dx - pA.y() * dy) / (pA.r() * dist);
        double elong = Math.toDegrees(Math.acos(Math.max(-1.0, Math.min(1.0, cosEl))));

        boolean blocked  = closest < 0.01;
        boolean degraded = !blocked && closest < 0.05;

        return new LineOfSight(
            !blocked && !degraded,
            blocked, degraded,
            closest, elong
        );
    }

    /**
     * Lower-quartile (25th percentile) light travel time over one Earth year.
     * Uses 360 samples; useful for planning long-baseline communication windows.
     *
     * @param a      source body
     * @param b      destination body
     * @param refMs  reference UTC milliseconds (start of sampling period)
     * @return 25th-percentile light travel time in seconds
     */
    public static double lowerQuartileLightTime(Planet a, Planet b, long refMs) {
        int SAMPLES = 360;
        long stepMs = (long)(365.25 * EARTH_DAY_MS / SAMPLES);
        double[] times = new double[SAMPLES];
        for (int i = 0; i < SAMPLES; i++) {
            times[i] = lightTravelSeconds(a, b, refMs + (long) i * stepMs);
        }
        java.util.Arrays.sort(times);
        return times[SAMPLES / 4];
    }

    /**
     * Format light travel seconds as a human-readable string.
     * e.g. 186 → "3 min 6 s", 45 → "45 s"
     *
     * @param seconds light travel time in seconds
     * @return formatted string
     */
    public static String formatLightTime(double seconds) {
        long s = Math.round(seconds);
        if (s < 60) return s + " s";
        long min = s / 60;
        long sec = s % 60;
        if (sec == 0) return min + " min";
        return min + " min " + sec + " s";
    }
}
