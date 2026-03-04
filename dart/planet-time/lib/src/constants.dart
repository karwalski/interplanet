// constants.dart — Planet enum, fundamental constants, orbital elements, leap seconds
// Ported verbatim from planet-time.js (Story 18.12)

// ── Planet enum ───────────────────────────────────────────────────────────────

/// All solar-system bodies supported by this library.
enum Planet {
  mercury,
  venus,
  earth,
  mars,
  jupiter,
  saturn,
  uranus,
  neptune,
  moon;

  /// Parse a planet from its lowercase name string.
  static Planet fromString(String s) => Planet.values
      .firstWhere((p) => p.name.toLowerCase() == s.toLowerCase());
}

// ── Fundamental constants ─────────────────────────────────────────────────────

/// J2000.0 epoch as Unix timestamp (ms) — Date.UTC(2000,0,1,12,0,0)
const int j2000Ms = 946728000000;

/// Julian Day number of J2000.0
const double j2000Jd = 2451545.0;

/// Earth solar day in milliseconds
const int earthDayMs = 86400000;

/// 1 AU in kilometres
const double auKm = 149597870.7;

/// Speed of light in km/s
const double cKms = 299792.458;

/// Light travel time for 1 AU in seconds (~499.004)
final double auSeconds = auKm / cKms;

/// Mars epoch (MY0 = 1953-05-24T09:03:58.464Z) in UTC ms
const int marsEpochMs = -524069761536;

/// Mars solar day in milliseconds (24h 39m 35.244s)
const int marsSolMs = 88775244;

// ── Planet data ───────────────────────────────────────────────────────────────

class PlanetData {
  final int solarDayMs;
  final int siderealYrMs;
  final int epochMs;
  final int workStart;
  final int workEnd;
  final double daysPerPeriod;
  final int periodsPerWeek;
  final int workPeriodsPerWeek;
  final bool earthClockSched;

  const PlanetData({
    required this.solarDayMs,
    required this.siderealYrMs,
    required this.epochMs,
    required this.workStart,
    required this.workEnd,
    required this.daysPerPeriod,
    required this.periodsPerWeek,
    required this.workPeriodsPerWeek,
    this.earthClockSched = false,
  });
}

// Rounding helper used to compute solar day ms from float days
int _r(double d) => (d + 0.5).floor();

/// Per-planet calendar constants — mirrors the PLANETS table in planet-time.js.
final Map<Planet, PlanetData> planetDataMap = {
  Planet.mercury: PlanetData(
    solarDayMs: _r(175.9408 * earthDayMs),
    siderealYrMs: _r(87.9691 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 9, workEnd: 17,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    earthClockSched: true,
  ),
  Planet.venus: PlanetData(
    solarDayMs: _r(116.7500 * earthDayMs),
    siderealYrMs: _r(224.701 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 9, workEnd: 17,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    earthClockSched: true,
  ),
  Planet.earth: PlanetData(
    solarDayMs: earthDayMs,
    siderealYrMs: _r(365.25636 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 9, workEnd: 17,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
  Planet.mars: PlanetData(
    solarDayMs: marsSolMs,
    siderealYrMs: _r(686.9957 * earthDayMs),
    epochMs: marsEpochMs,
    workStart: 9, workEnd: 17,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
  Planet.jupiter: PlanetData(
    solarDayMs: _r(9.9250 * 3600000),
    siderealYrMs: _r(4332.589 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 8, workEnd: 16,
    daysPerPeriod: 2.5, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
  Planet.saturn: PlanetData(
    solarDayMs: _r(10.578 * 3600000),
    siderealYrMs: _r(10759.22 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 8, workEnd: 16,
    daysPerPeriod: 2.25, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
  Planet.uranus: PlanetData(
    solarDayMs: _r(17.2479 * 3600000),
    siderealYrMs: _r(30688.5 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 8, workEnd: 16,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
  Planet.neptune: PlanetData(
    solarDayMs: _r(16.1100 * 3600000),
    siderealYrMs: _r(60195.0 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 8, workEnd: 16,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
  Planet.moon: PlanetData(
    solarDayMs: earthDayMs,
    siderealYrMs: _r(365.25636 * earthDayMs),
    epochMs: j2000Ms,
    workStart: 9, workEnd: 17,
    daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
  ),
};

// ── Orbital elements (Meeus Table 31.a) ──────────────────────────────────────

class OrbElem {
  /// Mean longitude at J2000.0 (degrees)
  final double l0;
  /// Rate (degrees per Julian century)
  final double dL;
  /// Longitude of perihelion (degrees)
  final double om0;
  /// Eccentricity at J2000.0
  final double e0;
  /// Semi-major axis (AU)
  final double a;

  const OrbElem({
    required this.l0,
    required this.dL,
    required this.om0,
    required this.e0,
    required this.a,
  });
}

/// Orbital elements table — mirrors ORBITAL_ELEMENTS in planet-time.js exactly.
/// Moon uses Earth's elements for heliocentric position.
final Map<Planet, OrbElem> orbElems = {
  Planet.mercury: const OrbElem(l0: 252.2507, dL: 149474.0722, om0:  77.4561, e0: 0.20564, a: 0.38710),
  Planet.venus:   const OrbElem(l0: 181.9798, dL:  58519.2130, om0: 131.5637, e0: 0.00677, a: 0.72333),
  Planet.earth:   const OrbElem(l0: 100.4664, dL:  36000.7698, om0: 102.9373, e0: 0.01671, a: 1.00000),
  Planet.mars:    const OrbElem(l0: 355.4330, dL:  19141.6964, om0: 336.0600, e0: 0.09341, a: 1.52366),
  Planet.jupiter: const OrbElem(l0:  34.3515, dL:   3036.3027, om0:  14.3320, e0: 0.04849, a: 5.20336),
  Planet.saturn:  const OrbElem(l0:  50.0775, dL:   1223.5093, om0:  93.0572, e0: 0.05551, a: 9.53707),
  Planet.uranus:  const OrbElem(l0: 314.0550, dL:    429.8633, om0: 173.0052, e0: 0.04630, a: 19.1912),
  Planet.neptune: const OrbElem(l0: 304.3480, dL:    219.8997, om0:  48.1234, e0: 0.00899, a: 30.0690),
  // Moon uses Earth's orbital elements for heliocentric position
  Planet.moon:    const OrbElem(l0: 100.4664, dL:  36000.7698, om0: 102.9373, e0: 0.01671, a: 1.00000),
};

// ── IERS leap seconds ─────────────────────────────────────────────────────────
// [taiMinusUtc, utcMs when this offset took effect]
// 28 entries, last updated: 2017-01-01

/// Leap seconds table — (TAI-UTC delta, UTC timestamp ms).
const List<(int, int)> leapSecs = [
  (10,  63072000000),  // 1972-01-01
  (11,  78796800000),  // 1972-07-01
  (12,  94694400000),  // 1973-01-01
  (13, 126230400000),  // 1974-01-01
  (14, 157766400000),  // 1975-01-01
  (15, 189302400000),  // 1976-01-01
  (16, 220924800000),  // 1977-01-01
  (17, 252460800000),  // 1978-01-01
  (18, 283996800000),  // 1979-01-01
  (19, 315532800000),  // 1980-01-01
  (20, 362793600000),  // 1981-07-01
  (21, 394329600000),  // 1982-07-01
  (22, 425865600000),  // 1983-07-01
  (23, 489024000000),  // 1985-07-01
  (24, 567993600000),  // 1988-01-01
  (25, 631152000000),  // 1990-01-01
  (26, 662688000000),  // 1991-01-01
  (27, 709948800000),  // 1992-07-01
  (28, 741484800000),  // 1993-07-01
  (29, 773020800000),  // 1994-07-01
  (30, 820454400000),  // 1996-01-01
  (31, 867715200000),  // 1997-07-01
  (32, 915148800000),  // 1999-01-01
  (33, 1136073600000), // 2006-01-01
  (34, 1230768000000), // 2009-01-01
  (35, 1341100800000), // 2012-07-01
  (36, 1435708800000), // 2015-07-01
  (37, 1483228800000), // 2017-01-01
];
