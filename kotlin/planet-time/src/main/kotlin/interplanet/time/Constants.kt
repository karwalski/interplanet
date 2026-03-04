package interplanet.time

/**
 * Constants.kt — Planet enum, J2000 constants, LEAP_SECS, ORB_ELEMS
 * Ported verbatim from planet-time.js v1.1.0
 */

enum class Planet(val idx: Int) {
    MERCURY(0), VENUS(1), EARTH(2), MARS(3),
    JUPITER(4), SATURN(5), URANUS(6), NEPTUNE(7), MOON(8);

    companion object {
        fun fromString(s: String): Planet =
            entries.first { it.name.lowercase() == s.lowercase() }
    }
}

/** J2000.0 epoch as Unix timestamp (ms) = Date.UTC(2000, 0, 1, 12, 0, 0) */
const val J2000_MS: Long = 946728000000L

/** Julian Day number of J2000.0 */
const val J2000_JD: Double = 2451545.0

/** Earth solar day in milliseconds */
const val EARTH_DAY_MS: Long = 86400000L

/** 1 AU in kilometres */
const val AU_KM: Double = 149597870.7

/** Speed of light in km/s */
const val C_KMS: Double = 299792.458

/** Light travel time for 1 AU in seconds (~499.004 s) */
val AU_SECONDS: Double = AU_KM / C_KMS

/** Mars MY0 epoch: Date.UTC(1953, 4, 24, 9, 3, 58, 464) */
const val MARS_EPOCH_MS: Long = -524069761536L

/** Mars solar day in milliseconds (88775244 ms = 24h 39m 35.244s) */
const val MARS_SOL_MS: Long = 88775244L

// ── Planet data ────────────────────────────────────────────────────────────

data class PlanetData(
    val solarDayMs: Long,
    val siderealYrMs: Long,
    val epochMs: Long,
    val workStart: Int,
    val workEnd: Int,
    val daysPerPeriod: Double,
    val periodsPerWeek: Int,
    val workPeriodsPerWeek: Int,
    val earthClockSched: Boolean = false
)

val PLANET_DATA: Map<Planet, PlanetData> = mapOf(
    Planet.MERCURY to PlanetData(
        solarDayMs = (175.9408 * EARTH_DAY_MS).toLong(),
        siderealYrMs = (87.9691 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 9, workEnd = 17,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5,
        earthClockSched = true
    ),
    Planet.VENUS to PlanetData(
        solarDayMs = (116.7500 * EARTH_DAY_MS).toLong(),
        siderealYrMs = (224.701 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 9, workEnd = 17,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5,
        earthClockSched = true
    ),
    Planet.EARTH to PlanetData(
        solarDayMs = EARTH_DAY_MS,
        siderealYrMs = (365.25636 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 9, workEnd = 17,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5
    ),
    Planet.MARS to PlanetData(
        solarDayMs = MARS_SOL_MS,
        siderealYrMs = (686.9957 * EARTH_DAY_MS).toLong(),
        epochMs = MARS_EPOCH_MS,
        workStart = 9, workEnd = 17,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5
    ),
    Planet.JUPITER to PlanetData(
        solarDayMs = (9.9250 * 3600000).toLong(),
        siderealYrMs = (4332.589 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 8, workEnd = 16,
        daysPerPeriod = 2.5, periodsPerWeek = 7, workPeriodsPerWeek = 5
    ),
    Planet.SATURN to PlanetData(
        solarDayMs = (10.578 * 3600000).toLong(),
        siderealYrMs = (10759.22 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 8, workEnd = 16,
        daysPerPeriod = 2.25, periodsPerWeek = 7, workPeriodsPerWeek = 5
    ),
    Planet.URANUS to PlanetData(
        solarDayMs = (17.2479 * 3600000).toLong(),
        siderealYrMs = (30688.5 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 8, workEnd = 16,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5
    ),
    Planet.NEPTUNE to PlanetData(
        solarDayMs = (16.1100 * 3600000).toLong(),
        siderealYrMs = (60195.0 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 8, workEnd = 16,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5
    ),
    Planet.MOON to PlanetData(
        solarDayMs = EARTH_DAY_MS,
        siderealYrMs = (365.25636 * EARTH_DAY_MS).toLong(),
        epochMs = J2000_MS,
        workStart = 9, workEnd = 17,
        daysPerPeriod = 1.0, periodsPerWeek = 7, workPeriodsPerWeek = 5
    )
)

// ── Orbital elements (Meeus Table 31.a) ───────────────────────────────────────
// L0: mean longitude at J2000.0 (degrees)
// dL: rate (degrees per Julian century)
// om0: longitude of perihelion (degrees)
// e0: eccentricity at J2000.0
// a: semi-major axis (AU, constant to this precision)

data class OrbElem(
    val a: Double,
    val e0: Double,
    val om0: Double,
    val l0: Double,
    val dL: Double
)

val ORB_ELEMS: Map<Planet, OrbElem> = mapOf(
    Planet.MERCURY to OrbElem(a = 0.38710,  e0 = 0.20564, om0 =  77.4561, l0 = 252.2507, dL = 149474.0722),
    Planet.VENUS   to OrbElem(a = 0.72333,  e0 = 0.00677, om0 = 131.5637, l0 = 181.9798, dL =  58519.2130),
    Planet.EARTH   to OrbElem(a = 1.00000,  e0 = 0.01671, om0 = 102.9373, l0 = 100.4664, dL =  36000.7698),
    Planet.MARS    to OrbElem(a = 1.52366,  e0 = 0.09341, om0 = 336.0600, l0 = 355.4330, dL =  19141.6964),
    Planet.JUPITER to OrbElem(a = 5.20336,  e0 = 0.04849, om0 =  14.3320, l0 =  34.3515, dL =   3036.3027),
    Planet.SATURN  to OrbElem(a = 9.53707,  e0 = 0.05551, om0 =  93.0572, l0 =  50.0775, dL =   1223.5093),
    Planet.URANUS  to OrbElem(a = 19.19126, e0 = 0.04630, om0 = 173.0052, l0 = 314.0550, dL =    429.8633),
    Planet.NEPTUNE to OrbElem(a = 30.06900, e0 = 0.00899, om0 =  48.1234, l0 = 304.3480, dL =    219.8997),
    // Moon uses Earth's orbital elements for helio position
    Planet.MOON    to OrbElem(a = 1.00000,  e0 = 0.01671, om0 = 102.9373, l0 = 100.4664, dL =  36000.7698)
)

// ── IERS leap seconds ──────────────────────────────────────────────────────────
// [utcMs, taiMinusUtc] — 28-entry array, last entry: 2017-01-01

data class LeapSecond(val utcMs: Long, val delta: Int)

val LEAP_SECONDS: List<LeapSecond> = listOf(
    LeapSecond(63_072_000_000L, 10),   // 1972-01-01
    LeapSecond(78_796_800_000L, 11),   // 1972-07-01
    LeapSecond(94_694_400_000L, 12),   // 1973-01-01
    LeapSecond(126_230_400_000L, 13),  // 1974-01-01
    LeapSecond(157_766_400_000L, 14),  // 1975-01-01
    LeapSecond(189_302_400_000L, 15),  // 1976-01-01
    LeapSecond(220_924_800_000L, 16),  // 1977-01-01
    LeapSecond(252_460_800_000L, 17),  // 1978-01-01
    LeapSecond(283_996_800_000L, 18),  // 1979-01-01
    LeapSecond(315_532_800_000L, 19),  // 1980-01-01
    LeapSecond(362_793_600_000L, 20),  // 1981-07-01
    LeapSecond(394_329_600_000L, 21),  // 1982-07-01
    LeapSecond(425_865_600_000L, 22),  // 1983-07-01
    LeapSecond(489_024_000_000L, 23),  // 1985-07-01
    LeapSecond(567_993_600_000L, 24),  // 1988-01-01
    LeapSecond(631_152_000_000L, 25),  // 1990-01-01
    LeapSecond(662_688_000_000L, 26),  // 1991-01-01
    LeapSecond(709_948_800_000L, 27),  // 1992-07-01
    LeapSecond(741_484_800_000L, 28),  // 1993-07-01
    LeapSecond(773_020_800_000L, 29),  // 1994-07-01
    LeapSecond(820_454_400_000L, 30),  // 1996-01-01
    LeapSecond(867_715_200_000L, 31),  // 1997-07-01
    LeapSecond(915_148_800_000L, 32),  // 1999-01-01
    LeapSecond(1_136_073_600_000L, 33), // 2006-01-01
    LeapSecond(1_230_768_000_000L, 34), // 2009-01-01
    LeapSecond(1_341_100_800_000L, 35), // 2012-07-01
    LeapSecond(1_435_708_800_000L, 36), // 2015-07-01
    LeapSecond(1_483_228_800_000L, 37)  // 2017-01-01
)
