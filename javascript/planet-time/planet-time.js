/**
 * planet-time.js — Interplanetary Time Library  v1.1.0
 *
 * Provides time, calendar, work-schedule, orbital mechanics, and light-speed
 * calculations for every planet in our solar system.
 *
 * Design principles
 * ─────────────────
 * • Solar day (not sidereal) is the base unit of "day" — one sunrise to the next.
 * • Each planet gets a 5-day "work week" and an 8-hour "shift", targeting
 *   ~40 work-hours per planet-week. Very long days (Mercury, Venus) use shifts;
 *   very short days (gas giants) group multiple days into one work period.
 * • "Hour" on each planet = 1/24 of its solar day (a "local hour").
 * • Epoch: J2000.0 = 2000-Jan-1 12:00:00 TT ≈ UTC (unless noted).
 *
 * Work-week decisions
 * ───────────────────
 * MERCURY  Solar day = 175.94 Earth days. Work shift = 8 local hours (~58 Earth days).
 *          Week = 7 shifts (5 work + 2 rest).
 * VENUS    Solar day = 116.75 Earth days (retrograde). Same shift approach as Mercury.
 * MARS     Sol ≈ 24h 39m 35.244s. 7-sol week (5 work + 2 rest), mirroring Earth.
 *          Epoch: May 24 1953 per Clancy et al. / interplanet.live.
 * JUPITER  Day ≈ 9.9h. Group 2.5 Jupiter days → one "work period" (~24.8 Earth h).
 *          Week = 7 work periods × 2.5 J-days = 17.5 Jupiter days.
 * SATURN   Day ≈ 10.578h. Group 2.25 Saturn days → one period (~23.8 Earth h).
 * URANUS   Day ≈ 17.2h. Standard 5-day week, 8 local-hour shifts.
 * NEPTUNE  Day ≈ 16.1h. Standard 5-day week, 8 local-hour shifts.
 *
 * Ref data: NASA GSFC Planetary Fact Sheet, Allison & McEwen 2000 (Mars),
 *           Meeus "Astronomical Algorithms" 2nd ed (orbital elements),
 *           IERS Bulletin C (leap seconds).
 */

'use strict';

// ── Version ───────────────────────────────────────────────────────────────────

/** Library version (semver, pre-v1) */
const VERSION = '1.4.0';

// ── Constants ─────────────────────────────────────────────────────────────────

/** J2000.0 epoch as Unix timestamp (ms) */
const J2000_MS = Date.UTC(2000, 0, 1, 12, 0, 0, 0);

/** Julian Day number of J2000.0 */
const J2000_JD = 2451545.0;

/** Earth solar day in milliseconds */
const EARTH_DAY_MS = 86400000;

/** 1 AU in kilometres */
const AU_KM = 149597870.7;

/** Speed of light in km/s */
const C_KMS = 299792.458;

/** Light travel time for 1 AU in seconds */
const AU_SECONDS = AU_KM / C_KMS; // ≈ 499.004 s

// ── Planets ───────────────────────────────────────────────────────────────────

const PLANETS = {

  mercury: {
    name: 'Mercury', symbol: '☿', color: '#b5b5b5',
    solarDayMs: 175.9408 * EARTH_DAY_MS,
    siderealYrMs: 87.9691 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17, shiftHours: 8,
    earthClockSchedule: true,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: 'Solar day ≈ 176 Earth days. Crews use Earth-clock scheduling: Mon–Fri UTC 09:00–17:00. MMT = location reference only.'
  },

  venus: {
    name: 'Venus', symbol: '♀', color: '#e8cda0',
    solarDayMs: 116.7500 * EARTH_DAY_MS,
    // Sidereal rotation: 243.0226 ±0.0013 days (Margot et al. 2021, Nature Astronomy).
    // Venus rotation varies by ~61 ppm (~20 min peak-to-peak) due to atmospheric angular
    // momentum exchange — treat local time as "best-fit at epoch" rather than a fixed clock.
    siderealYrMs: 224.701 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17, shiftHours: 8,
    earthClockSchedule: true,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: 'Solar day ≈ 116.75 Earth days (retrograde). Rotation varies ~61 ppm (Margot 2021). Crews use Earth-clock scheduling: Mon–Fri UTC 09:00–17:00. VMT = location reference only.'
  },

  earth: {
    name: 'Earth', symbol: '♁', color: '#4fa3e0',
    solarDayMs: 86400000,
    siderealYrMs: 365.25636 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17, shiftHours: 8,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: 'Standard 5-day 40-hour week.'
  },

  mars: {
    name: 'Mars', symbol: '♂', color: '#c1440e',
    solarDayMs: 88775244, // 24h 39m 35.244s (Allison & McEwen 2000)
    siderealYrMs: 686.9957 * EARTH_DAY_MS,
    get solsPerYear() { return this.siderealYrMs / this.solarDayMs; },
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 9, workHoursEnd: 17, shiftHours: 8,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: Date.UTC(1953, 4, 24, 9, 3, 58, 464), // May 24 1953 = MY0 (Piqueux backward extension of Clancy et al.)
    // Note: MY1 (Clancy et al. primary convention) begins April 11 1955. This library uses the MY0
    // epoch (May 24 1953) for continuity with interplanet.live v1. Sol counts are internally consistent.
    notes: 'Sol ≈ 24h 40m. 7-sol week (5 work + 2 rest). Epoch: May 24 1953 = MY0 (interplanet.live).'
  },

  jupiter: {
    name: 'Jupiter', symbol: '♃', color: '#c88b3a',
    solarDayMs: 9.9250 * 3600000,
    siderealYrMs: 4332.589 * EARTH_DAY_MS,
    daysPerPeriod: 2.5,   // 2.5 J-days ≈ 24.8 Earth hours per work period
    periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16, shiftHours: 8,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: '1 Jupiter day ≈ 9.9h. Work periods = 2.5 Jupiter days (≈24.8h). Core work hours: 08–16 local. 5 on, 2 off.'
  },

  saturn: {
    name: 'Saturn', symbol: '♄', color: '#e4d191',
    solarDayMs: 10.578 * 3600000, // Mankovich, Marley, Fortney & Mozshovitz (2023): 10h 34m 42s refined ring seismology
    // Note: old System III (Voyager SKR) = 10h 39m 22s is now known to track magnetospheric
    // current periodicity, not core rotation. Ring seismology value is the current scientific consensus.
    siderealYrMs: 10759.22 * EARTH_DAY_MS,
    daysPerPeriod: 2.25,  // 2.25 S-days ≈ 23.8 Earth hours per work period
    periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16, shiftHours: 8,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: '1 Saturn day ≈ 10.578h (Mankovich, Marley, Fortney & Mozshovitz 2023 ring seismology refinement). Work periods = 2.25 Saturn days (≈23.8h). Core work hours: 08–16 local. 5 on, 2 off.'
  },

  uranus: {
    name: 'Uranus', symbol: '⛢', color: '#7de8e8',
    solarDayMs: 17.2479 * 3600000, // Lamy et al. (2025, Nature Astronomy): 17.247864 ±0.000010 h
    siderealYrMs: 30688.5 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16, shiftHours: 8,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: '1 Uranus day ≈ 17.2479h (Lamy et al. 2025). Standard 5-day week, 8 local-hour shifts. Retrograde rotation.'
  },

  neptune: {
    name: 'Neptune', symbol: '♆', color: '#5b73df',
    solarDayMs: 16.1100 * 3600000,
    siderealYrMs: 60195.0 * EARTH_DAY_MS,
    daysPerPeriod: 1, periodsPerWeek: 7, workPeriodsPerWeek: 5,
    workHoursStart: 8, workHoursEnd: 16, shiftHours: 8,
    get localHourMs() { return this.solarDayMs / 24; },
    epochMs: J2000_MS,
    notes: '1 Neptune day ≈ 16.1h. Standard 5-day week, 8 local-hour shifts.'
  },

};

// ── Orbital elements (Meeus Table 31.a) ──────────────────────────────────────
// L0: mean longitude at J2000.0 (degrees)
// dL: rate (degrees per Julian century)
// om0: longitude of perihelion (degrees)
// e0: eccentricity at J2000.0
// a: semi-major axis (AU, constant to this precision)

const ORBITAL_ELEMENTS = {
  mercury: { L0: 252.2507, dL: 149474.0722, om0:  77.4561, e0: 0.20564, a: 0.38710 },
  venus:   { L0: 181.9798, dL:  58519.2130, om0: 131.5637, e0: 0.00677, a: 0.72333 },
  earth:   { L0: 100.4664, dL:  36000.7698, om0: 102.9373, e0: 0.01671, a: 1.00000 },
  mars:    { L0: 355.4330, dL:  19141.6964, om0: 336.0600, e0: 0.09341, a: 1.52366 },
  jupiter: { L0:  34.3515, dL:   3036.3027, om0:  14.3320, e0: 0.04849, a: 5.20336 },
  saturn:  { L0:  50.0775, dL:   1223.5093, om0:  93.0572, e0: 0.05551, a: 9.53707 },
  uranus:  { L0: 314.0550, dL:    429.8633, om0: 173.0052, e0: 0.04630, a: 19.1912 },
  neptune: { L0: 304.3480, dL:    219.8997, om0:  48.1234, e0: 0.00899, a: 30.0690 },
};

// ── IERS leap seconds ─────────────────────────────────────────────────────────
// [TAI−UTC (s), UTC timestamp when this offset took effect]
const LEAP_SECONDS = [
  [10, Date.UTC(1972, 0, 1)], [11, Date.UTC(1972, 6, 1)], [12, Date.UTC(1973, 0, 1)],
  [13, Date.UTC(1974, 0, 1)], [14, Date.UTC(1975, 0, 1)], [15, Date.UTC(1976, 0, 1)],
  [16, Date.UTC(1977, 0, 1)], [17, Date.UTC(1978, 0, 1)], [18, Date.UTC(1979, 0, 1)],
  [19, Date.UTC(1980, 0, 1)], [20, Date.UTC(1981, 6, 1)], [21, Date.UTC(1982, 6, 1)],
  [22, Date.UTC(1983, 6, 1)], [23, Date.UTC(1985, 6, 1)], [24, Date.UTC(1988, 0, 1)],
  [25, Date.UTC(1990, 0, 1)], [26, Date.UTC(1991, 0, 1)], [27, Date.UTC(1992, 6, 1)],
  [28, Date.UTC(1993, 6, 1)], [29, Date.UTC(1994, 6, 1)], [30, Date.UTC(1996, 0, 1)],
  [31, Date.UTC(1997, 6, 1)], [32, Date.UTC(1999, 0, 1)], [33, Date.UTC(2006, 0, 1)],
  [34, Date.UTC(2009, 0, 1)], [35, Date.UTC(2012, 6, 1)], [36, Date.UTC(2015, 6, 1)],
  [37, Date.UTC(2017, 0, 1)], // Current as of 2025 — update if new leap second announced
];

// ── Mars Timezone Zones (AMT = Airy Mean Time, prime meridian = Airy-0 crater) ─
// 24 zones × 1 Mars local hour each (15° longitude)
// Longitudes use IAU 0–360°E east-positive planetocentric convention.
// Zone centre longitudes: AMT+N = N×15°E; AMT-N = 360°−(N×15°)E.
// Feature assignments verified/corrected against USGS Planetary Nomenclature Database 2026.
// NOTE: A previous version of this table had a systematic west-to-east longitude
// label swap in the positive zones; this has been corrected.
const MARS_ZONES = [
  { id: 'AMT+0',  name: 'Sinus Meridiani',                  offsetHours:  0 },
  { id: 'AMT+1',  name: 'Arabia Terra',                     offsetHours:  1 },
  { id: 'AMT+2',  name: 'Arabia Terra (eastern)',           offsetHours:  2 },
  { id: 'AMT+3',  name: 'Hellas Planitia (western rim)',    offsetHours:  3 },
  { id: 'AMT+4',  name: 'Hellas Planitia (centre)',         offsetHours:  4 },
  { id: 'AMT+5',  name: 'Malea Planum',                     offsetHours:  5 },
  { id: 'AMT+6',  name: 'Promethei Terra',                  offsetHours:  6 },
  { id: 'AMT+7',  name: 'Hesperia Planum',                  offsetHours:  7 },
  { id: 'AMT+8',  name: 'Tyrrhena Terra (eastern)',         offsetHours:  8 },
  { id: 'AMT+9',  name: 'Elysium Planitia (western)',       offsetHours:  9 },
  { id: 'AMT+10', name: 'Elysium Mons',                     offsetHours: 10 },
  { id: 'AMT+11', name: 'Elysium Planitia (eastern)',       offsetHours: 11 },
  { id: 'AMT±12', name: 'Elysium–Amazonis antimeridian',   offsetHours: 12 },
  { id: 'AMT-11', name: 'Amazonis Planitia',                offsetHours: -11 },
  { id: 'AMT-10', name: 'Terra Sirenum',                    offsetHours: -10 },
  { id: 'AMT-9',  name: 'Olympus Mons / Daedalia Planum',    offsetHours:  -9 }, // NASA Mars24 convention: Olympus Mons at 226.2°E (133.8°W) = AMT-9
  { id: 'AMT-8',  name: 'Pavonis Mons / Arsia Mons',        offsetHours:  -8 },
  { id: 'AMT-7',  name: 'Ascraeus Mons',                    offsetHours:  -7 },
  { id: 'AMT-6',  name: 'Tharsis Plateau',                  offsetHours:  -6 },
  { id: 'AMT-5',  name: 'Valles Marineris (western)',       offsetHours:  -5 },
  { id: 'AMT-4',  name: 'Valles Marineris (central)',       offsetHours:  -4 },
  { id: 'AMT-3',  name: 'Valles Marineris (eastern)',       offsetHours:  -3 },
  { id: 'AMT-2',  name: 'Margaritifer Terra',               offsetHours:  -2 },
  { id: 'AMT-1',  name: 'Meridiani Planum (western)',       offsetHours:  -1 },
];

// ── Moon timezone zones ───────────────────────────────────────────────────────
// LMT = Lunar Mean Time. Prime meridian = Sinus Medii (IAU, centre of Earth-facing side).
// The Moon is tidally locked; a "local solar day" = 29.53 Earth days (synodic month).
// 24 zones × 15° longitude each. Near side = LMT-6 to LMT+6; far side = LMT±7–±12.
// Feature names from IAU Gazetteer of Planetary Nomenclature (lunar_names.iau.org).
// Key landmarks: Apollo 11 = Mare Tranquillitatis (LMT+2); Apollo 17 = Taurus-Littrow (LMT+2);
// South Pole–Aitken Basin (far side south); Artemis base camp target = South Pole (LMT±6 south).
const MOON_ZONES = _makeZones('LMT', [
  /* +0 */ 'Sinus Medii',           // nearside centre, IAU prime meridian (1°E 2°N)
  /* +1 */ 'Mare Tranquillitatis',  // Sea of Tranquility; Apollo 11 & 17 landing region (~30°E)
  /* +2 */ 'Mare Fecunditatis',     // Sea of Fertility; Luna 16, 20 sample sites (~50°E)
  /* +3 */ 'Mare Crisium',          // Sea of Crises; isolated basin (~60°E)
  /* +4 */ 'Mare Marginis',         // Sea of the Edge; eastern limb (~85°E)
  /* +5 */ 'Smythii Basin',         // limb; partly on near/far border (~90°E)
  /* +6 */ 'Orientale Basin East',  // edge of giant Orientale impact structure
  /* +7 */ 'Korolev Crater',        // large far-side crater; 437 km diameter
  /* +8 */ 'Tsiolkovsky Crater',    // prominent far-side mare-floored crater
  /* +9 */ 'Ingenii Basin',         // far-side south; swirl magnetic anomaly
  /* +10 */ 'South Pole–Aitken S',  // southern far-side; deepest basin in Solar System
  /* +11 */ 'Apollo Basin',         // 537-km far-side crater within SPA Basin
  /* ±12 */ 'Anti-Sinus Medii',     // far-side antipode of prime meridian
  /* -11 */ 'Hertzsprung Crater',   // 591-km far-side basin
  /* -10 */ 'Mendeleev Crater',     // 313-km far-side; first crater photographed (Luna 3)
  /* -9  */ 'Moscoviense Basin',    // far-side mare; landed by Luna 3 in 1959
  /* -8  */ 'Orientale Basin W',    // western limb; largest recent impact structure
  /* -7  */ 'Grimaldi Basin',       // western limb; 430-km dark-floored basin (~68°W)
  /* -6  */ 'Oceanus Procellarum',  // Ocean of Storms; largest lunar mare (~57°W)
  /* -5  */ 'Aristarchus Plateau',  // most reflective point on Moon; volcanic (~47°W)
  /* -4  */ 'Sinus Iridum',         // Bay of Rainbows; future base site (~31°W)
  /* -3  */ 'Mare Imbrium',         // Sea of Rains; Apollo 15 site (~17°W)
  /* -2  */ 'Copernicus Crater',    // spectacular 93-km rayed crater (~20°W)
  /* -1  */ 'Sinus Aestuum',        // Bay of Seething; near lunar centre (~9°W)
]);

// ── Mercury timezone zones ────────────────────────────────────────────────────
// MMT = Mercury Mean Time. Prime meridian: passes through Hun Kal crater (IAU 2009 definition,
// ~20°W in the old Mariner-10 frame; now redefined as 0°). Mercury day = 175.94 Earth days.
// Feature names follow IAU convention: craters named after deceased artists/musicians/authors.
// Sources: MESSENGER mission (NASA, 2011-2015), IAU Planetary Nomenclature.
const MERCURY_ZONES = _makeZones('MMT', [
  /* +0 */ 'Hun Kal Region',        // IAU prime meridian reference crater (1.5-km)
  /* +1 */ 'Tyagaraja Crater',      // 105-km; Carnatic music composer (~148°W → +1)
  /* +2 */ 'Kuiper Crater',         // 62-km; prominent ray crater; Gerard Kuiper
  /* +3 */ 'Mena Crater',           // small feature; transitional region
  /* +4 */ 'Rembrandt Basin',       // 715-km; youngest large basin; Dutch painter (~88°W)
  /* +5 */ 'Vivaldi Crater',        // 213-km; Baroque composer (~85°W)
  /* +6 */ 'Haydn Crater',          // 270-km; Austrian composer (~72°W)
  /* +7 */ 'Bach Basin',            // 225-km; J.S. Bach; southern region (~103°W)
  /* +8 */ 'Tolstoj Basin',         // 500-km; Russian novelist (~163°W)
  /* +9 */ 'Beethoven Basin',       // 625-km; largest named basin; Ludwig van Beethoven
  /* +10 */ 'Degas Crater',         // 52-km rayed; French Impressionist (~126°W)
  /* +11 */ 'Shakespeare Crater',   // 370-km basin; English playwright (~151°W)
  /* ±12 */ 'Caloris Basin',        // 1550-km; largest feature; "hot basin" facing sun at perihelion
  /* -11 */ 'Suisei Planitia',      // northern plains; "Comet" in Japanese
  /* -10 */ 'Sobkou Planitia',      // northern plains; Scythian deity
  /* -9  */ 'Borealis Planitia',    // vast northern lowland plain
  /* -8  */ 'Odin Planitia',        // northern plain; Norse mythology
  /* -7  */ 'Chekhov Crater',       // 199-km; Russian playwright (~61°W)
  /* -6  */ 'Chiang K\'ui Crater',  // 35-km; Chinese lyric poet
  /* -5  */ 'Tir Planitia',         // smooth plains; Zoroastrian messenger deity
  /* -4  */ 'Homer Crater',         // 314-km; ancient Greek poet (~37°W)
  /* -3  */ 'Renoir Crater',        // 246-km; French Impressionist (~51°W)
  /* -2  */ 'Discovery Rupes',      // longest lobate scarp; contraction feature (~38°W)
  /* -1  */ 'Raphael Crater',       // 343-km; Italian Renaissance artist (~76°W)
]);

// ── Venus timezone zones ───────────────────────────────────────────────────────
// VMT = Venus Mean Time. Prime meridian: central peak of Ariadne Crater (IAU standard, ~0°).
// Venus rotates retrograde (east–west), day = 116.75 Earth days. Dense CO₂ atmosphere;
// surface features mapped by Magellan radar (NASA, 1990-1994). IAU convention: features
// named after women (goddesses, historical women) except Maxwell Montes (honoring J.C. Maxwell,
// named before the convention). Sources: Magellan FMAP, USGS Astrogeology, IAU Gazetteer.
// Longitudes use IAU 0–360°E east-positive planetocentric convention (same as all other bodies).
// NOTE: This table was substantially corrected in February 2026 after a full USGS coordinate audit.
// Previous versions contained systematic zone-assignment errors (features placed ~150° from correct zone).
// [†] marks features verified via critical-recommendations research cycle (Feb 2026); USGS gazetteer
//     confirmation pending for zones VMT-11, VMT-10, VMT-9, VMT-8, VMT-6, VMT-4.
const VENUS_ZONES = _makeZones('VMT', [
  /* +0  0°E  */ 'Ariadne Crater region',   // IAU prime meridian; Ariadne crater ~0°E
  /* +1  15°E */ 'Maxwell Montes',           // highest peak on Venus (~11 km); ~3–6°E (USGS); Ishtar Terra western edge
  /* +2  30°E */ 'Ishtar Terra (eastern)',   // highland continent; spans ~0–75°E at high latitudes
  /* +3  45°E */ 'Eistla Regio',             // western highland tessera; ~22–50°E; Norse giantess
  /* +4  60°E */ 'Aphrodite Terra (W edge)', // vast equatorial continent; western edge ~60°E
  /* +5  75°E */ 'Aphrodite Terra / Niobe Planitia', // Niobe Planitia ~83°E; equatorial zone
  /* +6  90°E */ 'Ovda Regio',               // equatorial tessera highland; ~85–100°E
  /* +7  105°E */ 'Aphrodite Terra (central)', // central Aphrodite; ~100–120°E
  /* +8  120°E */ 'Thetis Regio',             // plateau tessera; sea nymph; ~120–140°E
  /* +9  135°E */ 'Artemis Corona',           // largest corona on Venus; ~135°E (USGS confirmed)
  /* +10 150°E */ 'Diana Chasma',             // deep rift valley; Roman moon goddess; ~155°E
  /* +11 165°E */ 'Atalanta Planitia',        // northern lowland basin; Greek huntress; ~165°E (USGS confirmed)
  /* ±12 180°E */ 'Anti-Ariadne',             // far-side antipode; ~180°E
  /* -11 165°W */ 'Navka Planitia',            // ~195°E; lowland volcanic plains (Feb 2026 revision) [†]
  /* -10 150°W */ 'Rusalka Planitia',          // ~210°E; southern lowland plains [†]
  /* -9  135°W */ 'Mugazo Planitia',           // ~220°E; highland–lowland transition zone [†]
  /* -8  120°W */ 'Laimdota Planitia',         // ~240°E; southern lowland plains [†]
  /* -7  105°W */ 'Helen Planitia',            // southern plains; Greek mythological figure; ~255–260°E (USGS)
  /* -6  90°W  */ 'Themis Regio',              // ~270°E; southern highland tessera region [†]
  /* -5  75°W  */ 'Beta Regio',                // volcanic highland; Rhea Mons; ~283°E (USGS confirmed)
  /* -4  60°W  */ 'Aino Planitia',             // ~300–330°E; vast southern lowland; Finnish heroine [†]
  /* -3  45°W  */ 'Guinevere Planitia',       // northern lowland; Arthurian queen; ~317°E (USGS confirmed)
  /* -2  30°W  */ 'Lavinia Planitia',         // large southern plain; Latin princess; ~315–355°E
  /* -1  15°W  */ 'Sedna Planitia',           // lowland; Inuit sea goddess; ~340–350°E
]);

// ── Gas-giant planet timezone zones ──────────────────────────────────────────
// 24 zones per planet, named by notable features where known.

function _makeZones(prefix, names) {
  const out = [];
  for (let h = 0; h <= 12; h++) {
    out.push({ id: h===0?`${prefix}+0`:h===12?`${prefix}±12`:`${prefix}+${h}`, name: names[h]||`${prefix} Zone +${h}`, offsetHours: h });
  }
  for (let h = 11; h >= 1; h--) {
    out.push({ id: `${prefix}-${h}`, name: names[24-h]||`${prefix} Zone -${h}`, offsetHours: -h });
  }
  return out;
}

const JUPITER_ZONES = _makeZones('JMT', [
  'Great Red Spot','South Equatorial Belt','Equatorial Zone','North Equatorial Belt',
  'North Temperate Belt','North Polar Region','Polar Vortex A','Antipodal Zone A',
  'Antipodal Zone B','South Polar Region','South Temperate Belt','South Tropical Zone',
  'Oval BA Region',
  /*-11*/'Oval BA Trailing',/*-10*/'Io Flux Zone',/*-9*/'Europa Trailing',
  /*-8*/'Ganymede Zone',/*-7*/'Callisto Belt',/*-6*/'Inner Ring West',
  /*-5*/'Temperate Rift',/*-4*/'Festoon Belt',/*-3*/'Low Latitude W',/*-2*/'Mid Equatorial W',/*-1*/'GRS Trailing'
]);

const SATURN_ZONES = _makeZones('SMT', [
  'Great White Spot','Equatorial Zone','North Equatorial Belt','North Temperate Belt',
  'North Polar Belt','North Polar Hexagon','Polar Vortex','Antipodal Zone A',
  'Antipodal Zone B','South Polar Region','South Polar Belt','South Temperate Belt',
  'South Equatorial Belt',
  /*-11*/'South Tropical Zone',/*-10*/'Ring Plane Zone',/*-9*/'Inner Ring Belt',
  /*-8*/'Cassini Division Zone',/*-7*/'Encke Gap Zone',/*-6*/'F-Ring Zone',
  /*-5*/'Outer Ring Belt',/*-4*/'Titan Leading',/*-3*/'Titan Trailing',/*-2*/'Rhea Zone',/*-1*/'Tethys Zone'
]);

const URANUS_ZONES = _makeZones('UMT', [
  'Miranda Region','Ariel Zone','Umbriel Belt','Titania Zone','Oberon Region',
  'Caliban Zone','Sycorax Belt','Prospero Zone','Setebos Region','Stephano Zone',
  'Trinculo Belt','Francisco Region','Margaret Zone',
  /*-11*/'Ferdinand Zone',/*-10*/'Perdita Belt',/*-9*/'Mab Zone',/*-8*/'Cupid Region',
  /*-7*/'Puck Zone',/*-6*/'Bianca Belt',/*-5*/'Cressida Zone',/*-4*/'Desdemona Region',
  /*-3*/'Juliet Zone',/*-2*/'Portia Belt',/*-1*/'Rosalind Zone'
]);

const NEPTUNE_ZONES = _makeZones('NMT', [
  'Great Dark Spot','Scooter Zone','Bright Companion A','Small Dark Spot',
  'Equatorial Zone','Northern Band','North Polar Region','Deep Polar Zone',
  'Antipodal Bright A','Antipodal Dark','South Polar Region','South Polar Vortex',
  'Trailing Hemisphere',
  /*-11*/'Triton Leading',/*-10*/'Triton Trailing',/*-9*/'Proteus Zone',
  /*-8*/'Nereid Zone',/*-7*/'Inner Moon Belt',/*-6*/'Equatorial West A',
  /*-5*/'Equatorial West B',/*-4*/'Southern Band',/*-3*/'South Temperate',
  /*-2*/'Dark Belt West',/*-1*/'GDS Trailing'
]);

const PLANET_ZONES = {
  moon: MOON_ZONES,
  mercury: MERCURY_ZONES, venus: VENUS_ZONES,
  mars: MARS_ZONES,
  jupiter: JUPITER_ZONES, saturn: SATURN_ZONES, uranus: URANUS_ZONES, neptune: NEPTUNE_ZONES,
};

// ── Leap second / TT helpers ──────────────────────────────────────────────────

function _getTAIminusUTC(utcMs) {
  let offset = 10;
  for (const [s, tMs] of LEAP_SECONDS) {
    if (utcMs >= tMs) offset = s;
    else break;
  }
  return offset;
}

/**
 * Convert a UTC Date to Terrestrial Time Julian Day Number.
 * TT = UTC + (TAI−UTC) + 32.184 s
 */
function toJDE(date) {
  const utcMs = date.getTime();
  const ttMs  = utcMs + (_getTAIminusUTC(utcMs) + 32.184) * 1000;
  return 2440587.5 + ttMs / 86400000; // Julian Day of Unix epoch + days
}

/** Julian centuries since J2000.0 from a Date. */
function _julianCenturies(date) {
  return (toJDE(date) - J2000_JD) / 36525;
}

// ── Orbital mechanics ─────────────────────────────────────────────────────────

/** Solve Kepler's equation M = E − e·sin(E) using Newton's method. */
function _keplerE(M_rad, e) {
  let E = M_rad;
  for (let i = 0; i < 50; i++) {
    const dE = (M_rad - E + e * Math.sin(E)) / (1 - e * Math.cos(E));
    E += dE;
    if (Math.abs(dE) < 1e-12) break;
  }
  return E;
}

/**
 * Get heliocentric (x, y) position of a planet in AU (ecliptic plane).
 * @param {string} planetKey
 * @param {Date}   date
 * @returns {{x:number, y:number, r:number, lon:number}}
 */
function planetHelioXY(planetKey, date) {
  const key = (planetKey === 'moon') ? 'earth' : planetKey;
  const el  = ORBITAL_ELEMENTS[key];
  if (!el) throw new Error(`No orbital elements for: ${planetKey}`);

  const T   = _julianCenturies(date);
  const D2R = Math.PI / 180;
  const R2D = 180 / Math.PI;
  const TAU = 2 * Math.PI;

  const L   = ((el.L0 + el.dL * T) * D2R % TAU + TAU) % TAU;
  const om  = el.om0 * D2R;
  const M   = ((L - om) % TAU + TAU) % TAU;
  const e   = el.e0;
  const a   = el.a;

  const E   = _keplerE(M, e);
  const v   = 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(E / 2),
                              Math.sqrt(1 - e) * Math.cos(E / 2));
  const r   = a * (1 - e * Math.cos(E));
  const lon = ((v + om) % TAU + TAU) % TAU;

  return { x: r * Math.cos(lon), y: r * Math.sin(lon), r, lon };
}

/**
 * Distance in AU between two solar system bodies.
 * @param {string} keyA  planet key or 'earth'
 * @param {string} keyB  planet key or 'earth'
 * @param {Date}   date
 * @returns {number} AU
 */
function bodyDistance(keyA, keyB, date) {
  const pA = planetHelioXY(keyA, date);
  const pB = planetHelioXY(keyB, date);
  const dx = pA.x - pB.x, dy = pA.y - pB.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * One-way light travel time between two bodies (seconds).
 */
function lightTravelSeconds(keyA, keyB, date) {
  return bodyDistance(keyA, keyB, date) * AU_SECONDS;
}

/**
 * Check whether the line of sight between two bodies is obstructed by the Sun.
 * Buffer zones: < 0.01 AU = blocked; < 0.05 AU = degraded.
 * @returns {{clear, blocked, degraded, closestSunAU, elongDeg, message}}
 */
function checkLineOfSight(keyA, keyB, date) {
  const pA  = planetHelioXY(keyA, date);
  const pB  = planetHelioXY(keyB, date);
  const dx  = pB.x - pA.x, dy = pB.y - pA.y;
  const d2  = dx * dx + dy * dy;
  const dist = Math.sqrt(d2);

  // Closest approach of segment A→B to the Sun (origin)
  const t = Math.max(0, Math.min(1, -(pA.x * dx + pA.y * dy) / d2));
  const cx = pA.x + t * dx, cy = pA.y + t * dy;
  const closestSunAU = Math.sqrt(cx * cx + cy * cy);

  // Solar elongation at A (angle: A–Sun–B direction from A)
  const cosEl = (-pA.x * dx - pA.y * dy) / (pA.r * dist);
  const elongDeg = Math.acos(Math.max(-1, Math.min(1, cosEl))) * 180 / Math.PI;

  const blocked  = closestSunAU < 0.01;
  const degraded = !blocked && closestSunAU < 0.05;

  return {
    clear: !blocked && !degraded, blocked, degraded,
    closestSunAU, elongDeg,
    message: blocked
      ? `Path passes within ${(closestSunAU * AU_KM / 1000).toFixed(0)}k km of Sun — BLOCKED`
      : degraded
      ? `Path passes within ${(closestSunAU * AU_KM / 1e6).toFixed(2)}M km of Sun — degraded`
      : 'Clear line of sight',
  };
}

/**
 * Sample light travel time over one Earth year and return the 25th-percentile value.
 * This is the "lower-quartile light time" — a good target transmission window.
 * @returns {number} seconds
 */
function lowerQuartileLightTime(keyA, keyB, date = new Date()) {
  const SAMPLES = 360;
  const step    = 365.25 * EARTH_DAY_MS / SAMPLES;
  const times   = [];
  for (let i = 0; i < SAMPLES; i++) {
    times.push(lightTravelSeconds(keyA, keyB, new Date(date.getTime() + i * step)));
  }
  times.sort((a, b) => a - b);
  return times[Math.floor(SAMPLES * 0.25)];
}

/**
 * Find the next time (scanning forward in 6-hour steps) when the light travel
 * time from keyA to keyB drops at or below threshold seconds.
 * Searches up to 2 years. Returns a Date or null.
 */
function nextFavourableLightTime(keyA, keyB, thresholdSeconds, fromDate = new Date()) {
  const STEP = 6 * 3600000;
  const MAX  = fromDate.getTime() + 2 * 365.25 * EARTH_DAY_MS;
  for (let t = fromDate.getTime(); t < MAX; t += STEP) {
    if (lightTravelSeconds(keyA, keyB, new Date(t)) <= thresholdSeconds) {
      return new Date(t);
    }
  }
  return null;
}

// ── Mars time ─────────────────────────────────────────────────────────────────

const MARS_EPOCH_MS = Date.UTC(1953, 4, 24, 9, 3, 58, 464); // per Clancy et al.
const MARS_SOL_MS   = 88775244;

/**
 * Get Mars Coordinated Time (MTC) — the Martian equivalent of UTC.
 * @param {Date} [date]
 * @returns {{sol, hour, minute, second, mtcString}}
 */
function getMTC(date = new Date()) {
  const totalSols = (date.getTime() - MARS_EPOCH_MS) / MARS_SOL_MS;
  const sol  = Math.floor(totalSols);
  const frac = totalSols - sol;
  const h = Math.floor(frac * 24);
  const m = Math.floor((frac * 24 - h) * 60);
  const s = Math.floor(((frac * 24 - h) * 60 - m) * 60);
  return { sol, hour: h, minute: m, second: s,
           mtcString: `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}` };
}

/**
 * Get Mars local time at a given zone offset (Mars local hours from AMT).
 */
function getMarsTimeAtOffset(date, offsetHours) {
  const mtc = getMTC(date);
  let h = mtc.hour + offsetHours;
  let solDelta = 0;
  if (h >= 24) { h -= 24; solDelta =  1; }
  if (h <   0) { h += 24; solDelta = -1; }
  return {
    sol: mtc.sol + solDelta,
    hour: Math.floor(h), minute: mtc.minute, second: mtc.second,
    timeString: `${String(Math.floor(h)).padStart(2,'0')}:${String(mtc.minute).padStart(2,'0')}`,
    offsetHours,
  };
}

// ── Core planet time functions ────────────────────────────────────────────────

const _DOW_NAMES  = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const _DOW_SHORT  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

/**
 * Get the current time on a planet.
 * @param {string} planetKey
 * @param {Date}   [date]
 * @param {number} [tzOffsetHours]  optional zone offset (local hours from planet prime meridian)
 * @returns {PlanetTimeResult}
 */
function getPlanetTime(planetKey, date = new Date(), tzOffsetHours = 0) {
  // Moon uses Earth's solar day (tidally locked; work schedules run on Earth time)
  if (planetKey === 'moon') planetKey = 'earth';
  const p = PLANETS[planetKey];
  if (!p) throw new Error(`Unknown planet: ${planetKey}`);

  const elapsedMs   = date.getTime() - p.epochMs + tzOffsetHours / 24 * p.solarDayMs;
  const totalDays   = elapsedMs / p.solarDayMs;
  const dayNumber   = Math.floor(totalDays);
  const dayFraction = totalDays - dayNumber;

  const localHour = dayFraction * 24;
  const h = Math.floor(localHour);
  const m = Math.floor((localHour - h) * 60);
  const s = Math.floor(((localHour - h) * 60 - m) * 60);

  const { daysPerPeriod, periodsPerWeek, workPeriodsPerWeek } = p;

  let periodInWeek, isWorkPeriod, isWorkHour;
  if (p.earthClockSchedule) {
    // Mercury/Venus: solar day >> human circadian rhythm; use Earth-standard work week.
    // getUTCDay() returns 0=Sun..6=Sat; convert to 0=Mon..6=Sun for periodInWeek.
    periodInWeek = (date.getUTCDay() + 6) % 7;
    isWorkPeriod = periodInWeek < workPeriodsPerWeek; // Mon–Fri = periods 0–4
    const utcHour = date.getUTCHours() + date.getUTCMinutes() / 60 + date.getUTCSeconds() / 3600;
    isWorkHour = isWorkPeriod && utcHour >= p.workHoursStart && utcHour < p.workHoursEnd;
  } else {
    const totalPeriods = totalDays / daysPerPeriod;
    // Use positive modulo so pre-epoch dates also return valid 0-(n-1) range
    periodInWeek = ((Math.floor(totalPeriods) % periodsPerWeek) + periodsPerWeek) % periodsPerWeek;
    isWorkPeriod = periodInWeek < workPeriodsPerWeek;
    isWorkHour   = isWorkPeriod && localHour >= p.workHoursStart && localHour < p.workHoursEnd;
  }

  const yearLenDays = p.siderealYrMs / p.solarDayMs;
  const yearNumber  = Math.floor(totalDays / yearLenDays);
  const dayInYear   = totalDays - yearNumber * yearLenDays;

  let solInfo = null;
  if (planetKey === 'mars') {
    solInfo = { solInYear: Math.floor(dayInYear), solsPerYear: Math.round(p.solsPerYear) };
  }

  const dowIndex = periodInWeek % 7;

  return {
    planet: p.name, symbol: p.symbol,
    hour: h, minute: m, second: s, localHour, dayFraction,
    dayNumber, dayInYear: Math.floor(dayInYear), yearNumber, solInfo,
    periodInWeek, isWorkPeriod, isWorkHour,
    dowName: _DOW_NAMES[dowIndex], dowShort: _DOW_SHORT[dowIndex],
    solarDayMs: p.solarDayMs, daysPerPeriod, periodsPerWeek, workPeriodsPerWeek,
    timeString: `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`,
    timeStringFull: `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`,
  };
}

const earthToPlanetTime = getPlanetTime;

/**
 * Find the next Earth Date when a given local planet time occurs.
 */
function nextPlanetTime(planetKey, targetHour, targetMinute = 0, fromDate = new Date()) {
  const p = PLANETS[planetKey];
  const totalDays   = (fromDate.getTime() - p.epochMs) / p.solarDayMs;
  const dayFraction = totalDays - Math.floor(totalDays);
  const targetFrac  = (targetHour + targetMinute / 60) / 24;
  let diff = targetFrac - dayFraction;
  if (diff <= 0) diff += 1;
  return new Date(fromDate.getTime() + diff * p.solarDayMs);
}

/**
 * Get a 24-element array of work/non-work status for each hour of the current planet day.
 */
function getPlanetHourlySchedule(planetKey, now = new Date()) {
  // Moon uses Earth's schedule (tidally locked; crews follow Earth time)
  if (planetKey === 'moon') planetKey = 'earth';
  const p = PLANETS[planetKey];
  const { solarDayMs, workHoursStart, workHoursEnd, daysPerPeriod, periodsPerWeek, workPeriodsPerWeek } = p;

  // Earth-clock planets (Mercury/Venus): schedule is based on UTC hours of the current Earth day.
  if (p.earthClockSchedule) {
    const dayStartMs = Math.floor(now.getTime() / 86400000) * 86400000;
    const dow = (new Date(dayStartMs).getUTCDay() + 6) % 7; // 0=Mon..6=Sun
    const isWorkDay = dow < workPeriodsPerWeek;
    return Array.from({ length: 24 }, (_, i) => {
      const isWork = isWorkDay && i >= workHoursStart && i < workHoursEnd;
      return { localHour: i, isWork, earthTimeMs: dayStartMs + i * 3600000 };
    });
  }

  const elapsedMs    = now.getTime() - p.epochMs;
  const totalDays    = elapsedMs / solarDayMs;
  const dayStartMs   = Math.floor(totalDays) * solarDayMs + p.epochMs;

  return Array.from({ length: 24 }, (_, i) => {
    const earthTimeMs = dayStartMs + (i / 24) * solarDayMs;
    const td          = (earthTimeMs - p.epochMs) / solarDayMs;
    const piw         = Math.floor(td / daysPerPeriod) % periodsPerWeek;
    const isWorkPeriod = piw < workPeriodsPerWeek;
    const isWork       = isWorkPeriod && i >= workHoursStart && i < workHoursEnd;
    return { localHour: i, isWork, earthTimeMs: Math.round(earthTimeMs) };
  });
}

/**
 * Find overlapping work windows between two planets over N Earth days.
 * @returns {Array<{startMs, endMs, durationMinutes}>}
 */
function findMeetingWindows(planetA, planetB, earthDays = 7, start = new Date()) {
  const STEP = 15 * 60000;
  const endMs = start.getTime() + earthDays * EARTH_DAY_MS;
  const windows = [];
  let inWindow = false, windowStart = 0;

  for (let t = start.getTime(); t < endMs; t += STEP) {
    const d   = new Date(t);
    const ta  = getPlanetTime(planetA, d);
    const tb  = getPlanetTime(planetB, d);
    const overlap = ta.isWorkHour && tb.isWorkHour;
    if (overlap && !inWindow)  { inWindow = true; windowStart = t; }
    if (!overlap && inWindow)  { inWindow = false; windows.push({ startMs: windowStart, endMs: t, durationMinutes: (t - windowStart) / 60000 }); }
  }
  if (inWindow) windows.push({ startMs: windowStart, endMs: endMs, durationMinutes: (endMs - windowStart) / 60000 });
  return windows;
}

/**
 * Find the next available meeting slot(s) across N locations.
 *
 * Designed for AI-agent use: pass a list of locations (Earth cities and/or
 * planets), get back a ranked list of overlap windows with per-location
 * local times so the agent can present human-readable options.
 *
 * @param {Array<LocationDescriptor>} locations
 *   Each entry is one of:
 *   - Earth city: { type:'earth', tz:'America/New_York', workWeek?:'mon-fri',
 *                   workStart?:9, workEnd?:17, label?:'New York' }
 *     workWeek accepts: 'mon-fri' | 'sun-thu' | 'sat-thu' | 'mon-sat'
 *   - Planet:     { type:'planet', planet:'mars', tzOffset?:0, label?:'Mars AMT' }
 *     tzOffset is in planet local hours relative to planet prime meridian.
 *
 * @param {object}  [opts]
 * @param {Date}    [opts.from=new Date()]          UTC start of search window
 * @param {number}  [opts.maxDays=14]               max Earth days to scan
 * @param {number}  [opts.stepMinutes=30]           time resolution (minutes)
 * @param {number}  [opts.minDurationMinutes=30]    minimum acceptable overlap
 * @param {number}  [opts.maxOptions=3]             how many slot options to return
 *
 * @returns {{
 *   found: boolean,
 *   message: string,
 *   searchedDays: number,
 *   slots: Array<{
 *     startIso: string,    // UTC ISO-8601 start
 *     endIso: string,      // UTC ISO-8601 end
 *     startMs: number,
 *     endMs: number,
 *     durationMinutes: number,
 *     localTimes: Array<{
 *       label: string,
 *       timeStr: string,   // human-readable local time + weekday at slot midpoint
 *       isWorkHour: boolean
 *     }>
 *   }>
 * }}
 */
function findNextMeetingSlot(locations, opts = {}) {
  const from    = opts.from instanceof Date ? opts.from : new Date();
  const maxDays = opts.maxDays      ?? 14;
  const step    = (opts.stepMinutes ?? 30) * 60000;
  const minDur  = (opts.minDurationMinutes ?? 30) * 60000;
  const maxOpts = opts.maxOptions   ?? 3;

  const _WORK_DAYS = {
    'mon-fri':  ['mon','tue','wed','thu','fri'],
    'sun-thu':  ['sun','mon','tue','wed','thu'],
    'sat-thu':  ['sat','sun','mon','tue','wed','thu'],
    'mon-sat':  ['mon','tue','wed','thu','fri','sat'],
  };

  function _earthIsWork(loc, d) {
    const tz  = loc.tz;
    const ws  = loc.workStart ?? 9;
    const we  = loc.workEnd   ?? 17;
    const ww  = loc.workWeek  ?? 'mon-fri';
    const h   = parseInt(new Intl.DateTimeFormat('en-US',{timeZone:tz,hour:'numeric',hour12:false}).format(d),10);
    const dow = new Intl.DateTimeFormat('en-US',{timeZone:tz,weekday:'short'}).format(d).toLowerCase().slice(0,3);
    const wd  = _WORK_DAYS[ww] ?? _WORK_DAYS['mon-fri'];
    return wd.includes(dow) && h >= ws && h < we;
  }

  const endMs = from.getTime() + maxDays * EARTH_DAY_MS;
  const slots = [];
  let inWindow = false, windowStart = 0;

  for (let t = from.getTime(); t <= endMs; t += step) {
    const d = new Date(t);
    const allWork = locations.every(loc => {
      if (loc.type === 'planet') return getPlanetTime(loc.planet, d, loc.tzOffset ?? 0).isWorkHour;
      return _earthIsWork(loc, d);
    });
    if (allWork  && !inWindow) { inWindow = true;  windowStart = t; }
    if (!allWork && inWindow)  {
      inWindow = false;
      const dur = t - windowStart;
      if (dur >= minDur) {
        slots.push({ startMs: windowStart, endMs: t, durationMinutes: dur / 60000 });
        if (slots.length >= maxOpts) break;
      }
    }
  }
  // Close any window still open at search end
  if (inWindow && slots.length < maxOpts) {
    const dur = endMs - windowStart;
    if (dur >= minDur) slots.push({ startMs: windowStart, endMs, durationMinutes: dur / 60000 });
  }

  // Enrich each slot with ISO timestamps and per-location local times
  const enriched = slots.map(s => {
    const mid = new Date((s.startMs + s.endMs) / 2);
    const localTimes = locations.map(loc => {
      const label = loc.label ?? (loc.type === 'planet' ? (PLANETS[loc.planet]?.name ?? loc.planet) : loc.tz);
      if (loc.type === 'planet') {
        const pt = getPlanetTime(loc.planet, mid, loc.tzOffset ?? 0);
        return {
          label,
          timeStr: `${String(pt.hour).padStart(2,'0')}:${String(pt.minute).padStart(2,'0')} ${pt.dowName} (${PLANETS[loc.planet]?.name ?? loc.planet} local)`,
          isWorkHour: pt.isWorkHour,
        };
      }
      const timeStr = new Intl.DateTimeFormat('en-US', {
        timeZone: loc.tz, weekday:'short', hour:'2-digit', minute:'2-digit', hour12: false,
      }).format(mid);
      return { label, timeStr, isWorkHour: true };
    });
    return {
      startMs: s.startMs, endMs: s.endMs,
      startIso: new Date(s.startMs).toISOString(),
      endIso:   new Date(s.endMs).toISOString(),
      durationMinutes: s.durationMinutes,
      localTimes,
    };
  });

  const message = enriched.length
    ? `Found ${enriched.length} option(s) within ${maxDays} days.`
    : `No overlap of ≥${opts.minDurationMinutes ?? 30} min found within ${maxDays} days.`;

  return { found: enriched.length > 0, message, searchedDays: maxDays, slots: enriched };
}

/**
 * Convert a timezone offset in local hours to milliseconds for a planet.
 */
function planetTimezoneOffsetMs(planetKey, offsetLocalHours) {
  return (offsetLocalHours / 24) * PLANETS[planetKey].solarDayMs;
}

// ── Format utilities ──────────────────────────────────────────────────────────

/**
 * Format a light travel time (seconds) as a human-readable string.
 */
function formatLightTime(seconds) {
  if (seconds < 0.001) return '<1ms';
  if (seconds < 1)     return `${(seconds * 1000).toFixed(0)}ms`;
  if (seconds < 60)    return `${seconds.toFixed(1)}s`;
  if (seconds < 3600)  return `${(seconds / 60).toFixed(1)}min`;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  return `${h}h ${m}m`;
}

// ── Planetary timezone zone prefixes ─────────────────────────────────────────

/** Maps planet key to its 3-letter timezone zone prefix (AMT, LMT, …) */
const ZONE_PREFIXES = {
  mars:    'AMT',
  moon:    'LMT',
  mercury: 'MMT',
  venus:   'VMT',
  jupiter: 'JMT',
  saturn:  'SMT',
  uranus:  'UMT',
  neptune: 'NMT',
};

// ── Astronomical constants with metadata ─────────────────────────────────────
// Per draft-watt-interplanetary-timezones-00 §10 and critical-recommendations §6.2.
// Each entry: { value, unit, source, exact?, revision?, uncertainty?, disputeNote? }

const CONSTANTS = {
  C_KMS: {
    value: 299792.458, unit: 'km/s',
    source: 'SI definition', exact: true,
  },
  AU_KM: {
    value: 149597870.700, unit: 'km',
    source: 'IAU 2012 Resolution B2', exact: true,
  },
  AU_SECONDS: {
    value: AU_KM / C_KMS, unit: 's',
    source: 'Derived: AU_KM / C_KMS', exact: false,
  },
  MARS_SOL_S: {
    value: 88775.244, unit: 's',
    source: 'Allison & McEwen 2000', revision: '2000', uncertainty: null,
  },
  MERCURY_SOLAR_DAY_D: {
    value: 175.9421, unit: 'd',
    source: 'JPL Horizons 2024-Mar', revision: '2024', uncertainty: null,
  },
  VENUS_SOLAR_DAY_D: {
    value: 116.7490, unit: 'd',
    source: 'Margot et al. 2021', revision: '2021', uncertainty: '±0.0002 d',
  },
  JUPITER_ROTATION_H: {
    value: 9.9249, unit: 'h',
    source: 'JPL Horizons (System III) 2025-Jan', revision: '2025', uncertainty: null,
  },
  SATURN_ROTATION_H: {
    value: 10.578, unit: 'h',
    source: 'Mankovich, Marley, Fortney & Mozshovitz 2023 (ring seismology refinement)', revision: '2023',
    uncertainty: null,
    disputeNote: 'System III (Voyager 1980) gives 10.6567 h; NASA Planetary Fact Sheet still lists this value. Implementations MAY use System III for compatibility with historical data products.',
  },
  URANUS_ROTATION_H: {
    value: 17.2479, unit: 'h',
    source: 'Lamy et al. 2025', revision: '2025', uncertainty: null,
  },
  NEPTUNE_ROTATION_H: {
    value: 16.11, unit: 'h',
    source: 'Voyager 2 (1989), JPL Horizons 2021-May', revision: '1989',
    uncertainty: '±0.01 h',
    disputeNote: 'Karkoschka 2011 atmospheric features gives 15.9663 h; NOT RECOMMENDED as default (per draft-watt-interplanetary-timezones-00 §11.3).',
  },
};

/** ISO date when constants were last reviewed. Consumers MAY warn if stale. */
const CONSTANTS_EPOCH = '2025-06-01';

// ── Machine-parseable planetary timestamp format ──────────────────────────────

/**
 * Format a planet time result as a machine-parseable timestamp per
 * draft-watt-interplanetary-timezones-00 §5.
 *
 * @param {object} pt          - PlanetTimeResult from getPlanetTime()
 * @param {string} planetKey   - e.g. 'mars', 'moon', 'jupiter'
 * @param {number} offsetHours - Timezone zone offset (e.g. +4 for AMT+4)
 * @param {Date}   earthDate   - Corresponding Earth UTC instant
 * @returns {string}
 *   Mars:  "MY43-221T14:32:07/2026-02-19T09:15:23Z[Mars/AMT+4]"
 *   Other: "2026-02-19T14:32:07/2026-02-19T14:32:07Z[Moon/LMT+1]"
 *
 * The "/" separator embeds the UTC instant so receivers without planetary
 * time support can extract it directly (minimum interoperability guarantee).
 */
function formatPlanetTimeISO(pt, planetKey, offsetHours, earthDate) {
  const P      = PLANETS[planetKey];
  const prefix = ZONE_PREFIXES[planetKey] || (planetKey.slice(0, 3).toUpperCase() + 'T');
  const offSign = offsetHours > 0 ? '+' : '';
  const tzId    = `${prefix}${offsetHours === 0 ? '0' : offSign + offsetHours}`;
  const bodyName = P ? P.name : (planetKey.charAt(0).toUpperCase() + planetKey.slice(1));

  // Time component: HH:MM:SS from pt fields (getPlanetTime sets hour/minute/second integers)
  const hh = String(pt.hour).padStart(2, '0');
  const mm = String(pt.minute).padStart(2, '0');
  const ss = String(pt.second ?? 0).padStart(2, '0');

  // Date component: Mars uses MY{year}-{sol:3d}, others use Gregorian date
  let dateStr;
  if (planetKey === 'mars' && pt.solInfo) {
    dateStr = `MY${pt.yearNumber}-${String(pt.solInfo.solInYear).padStart(3, '0')}`;
  } else if (earthDate instanceof Date) {
    dateStr = earthDate.toISOString().split('T')[0];
  } else {
    dateStr = '0000-00-00';
  }

  // UTC reference stripped of sub-second precision
  const utcRef = earthDate instanceof Date
    ? '/' + earthDate.toISOString().replace(/\.\d+Z$/, 'Z')
    : '';

  return `${dateStr}T${hh}:${mm}:${ss}${utcRef}[${bodyName}/${tzId}]`;
}

// ── Fairness scoring ──────────────────────────────────────────────────────────

/**
 * Calculate scheduling fairness across a recurring meeting series.
 * @param {Array<Date|number|string>} meetingSeries - UTC meeting instants
 * @param {Array<{tz:string, workWeek?:string}|string>} participants - tz strings or city-like objects
 * @returns {{ overall:number, perParticipant:Array, fairness:'good'|'ok'|'poor' }}
 */
function calculateFairnessScore(meetingSeries, participants) {
  if (!meetingSeries || !meetingSeries.length || !participants || !participants.length) {
    return { overall: 100, perParticipant: [], fairness: 'good' };
  }

  const workWeekDays = {
    'mon-fri': [1, 2, 3, 4, 5],
    'sun-thu': [0, 1, 2, 3, 4],
    'sat-wed': [6, 0, 1, 2, 3],
  };

  const total = meetingSeries.length;
  const perParticipant = participants.map((p, i) => {
    const tz   = (typeof p === 'string') ? p : (p.tz || 'UTC');
    const ww   = (typeof p === 'object' && p.workWeek) ? p.workWeek : 'mon-fri';
    const wDays = workWeekDays[ww] || workWeekDays['mon-fri'];
    let offHourCount = 0;

    meetingSeries.forEach(ts => {
      const d = (ts instanceof Date) ? ts : new Date(ts);
      try {
        const fmt = new Intl.DateTimeFormat('en-US', {
          timeZone: tz, hour: 'numeric', weekday: 'short', hour12: false,
        }).formatToParts(d);
        const get = type => (fmt.find(f => f.type === type) || {}).value || '';
        const h   = parseInt(get('hour'), 10);
        const wdMap = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
        const dow   = wdMap[get('weekday')] ?? 1;
        if (!wDays.includes(dow) || h < 9 || h >= 17) offHourCount++;
      } catch (_) { /* unknown tz — assume in hours */ }
    });

    return { index: i, tz, offHourCount, pct: offHourCount / total };
  });

  // Fairness = how evenly the off-hour burden is distributed (lower stddev = fairer)
  const mean     = perParticipant.reduce((a, p) => a + p.pct, 0) / perParticipant.length;
  const variance = perParticipant.reduce((a, p) => a + (p.pct - mean) ** 2, 0) / perParticipant.length;
  const stddev   = Math.sqrt(variance);
  const overall  = Math.max(0, Math.round(100 * (1 - stddev * 2)));
  const fairness = overall >= 75 ? 'good' : overall >= 40 ? 'ok' : 'poor';

  return { overall, perParticipant, fairness };
}

// ── SDK aliases (PRD §5.5) ────────────────────────────────────────────────────

/** Convert a UTC timestamp to planetary time at a given surface longitude. */
function convertUTCToPlanet(utcTimestamp, planet, longitude) {
  const tzOffsetHours = (longitude !== undefined && longitude !== null)
    ? Math.round(longitude / 15)
    : 0;
  return getPlanetTime(planet, new Date(utcTimestamp), tzOffsetHours);
}

/** Return the UTC millisecond value underlying any Date-like value. */
function convertPlanetToUTC(planetTimestamp) {
  return new Date(planetTimestamp).getTime();
}

/** Light-travel delay in seconds between two named bodies at a given date. */
function calculateLightDelay(bodyA, bodyB, date) {
  return lightTravelSeconds(bodyA, bodyB, date instanceof Date ? date : new Date(date));
}

function formatPlanetTime(pt) {
  const workLabel = pt.isWorkHour ? '🟢 work' : pt.isWorkPeriod ? '🟡 off-shift' : '🔴 rest';
  const dayLabel  = pt.planet === 'Mars' && pt.solInfo
    ? `Sol ${pt.solInfo.solInYear} of Year ${pt.yearNumber}`
    : `Day ${pt.dayInYear} of Year ${pt.yearNumber}`;
  return `${pt.planet} ${pt.symbol}  ${pt.timeString}  ${pt.dowShort}  ${dayLabel}  [${workLabel}]`;
}

// ── Exports ───────────────────────────────────────────────────────────────────

const _exports = {
  // Version
  VERSION,
  // Constants
  J2000_MS, J2000_JD, EARTH_DAY_MS, AU_KM, C_KMS, AU_SECONDS,
  // Data
  PLANETS, ORBITAL_ELEMENTS, LEAP_SECONDS,
  MARS_ZONES, PLANET_ZONES,
  MOON_ZONES, MERCURY_ZONES, VENUS_ZONES,
  JUPITER_ZONES, SATURN_ZONES, URANUS_ZONES, NEPTUNE_ZONES,
  // TT/JDE
  toJDE, _getTAIminusUTC,
  // Orbital mechanics
  planetHelioXY, bodyDistance, lightTravelSeconds,
  checkLineOfSight, lowerQuartileLightTime, nextFavourableLightTime,
  // Mars
  MARS_EPOCH_MS, MARS_SOL_MS, getMTC, getMarsTimeAtOffset,
  // Planet time
  getPlanetTime, earthToPlanetTime, nextPlanetTime,
  getPlanetHourlySchedule, findMeetingWindows, findNextMeetingSlot,
  planetTimezoneOffsetMs,
  // Format
  formatPlanetTime, formatLightTime, formatPlanetTimeISO,
  // Fairness & SDK aliases (PRD §5.5)
  calculateFairnessScore,
  convertUTCToPlanet, convertPlanetToUTC, calculateLightDelay,
  // Metadata
  ZONE_PREFIXES, CONSTANTS, CONSTANTS_EPOCH,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = _exports;
} else if (typeof window !== 'undefined') {
  window.PlanetTime = _exports;
}
