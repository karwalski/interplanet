# constants.R — Interplanet Time R package constants
# Ported from planet-time.js v1.1.0

# ── Core constants ─────────────────────────────────────────────────────────

#' J2000.0 epoch as Unix timestamp (ms)
J2000_MS <- 946728000000

#' Julian Day number of J2000.0
J2000_JD <- 2451545.0

#' Earth solar day in milliseconds
EARTH_DAY_MS <- 86400000

#' 1 AU in kilometres
AU_KM <- 149597870.7

#' Speed of light in km/s
C_KMS <- 299792.458

#' Light travel time for 1 AU in seconds
AU_SECONDS <- AU_KM / C_KMS

#' Mars epoch: MY0 Sol 0 = 1953-05-24T09:03:58.464Z
MARS_EPOCH_MS <- -524069761536

#' Mars sol in milliseconds (Allison & McEwen 2000)
MARS_SOL_MS <- 88775244

# ── Planet enum ───────────────────────────────────────────────────────────

#' Planet indices (named integer vector)
Planet <- c(
  MERCURY = 0L, VENUS = 1L, EARTH = 2L, MARS = 3L,
  JUPITER = 4L, SATURN = 5L, URANUS = 6L, NEPTUNE = 7L, MOON = 8L
)

# ── Planet data ───────────────────────────────────────────────────────────
# Index order matches Planet enum: 0=Mercury, 1=Venus, 2=Earth, 3=Mars,
# 4=Jupiter, 5=Saturn, 6=Uranus, 7=Neptune, 8=Moon

PLANET_DATA <- list(
  list(
    key = "mercury", name = "Mercury", symbol = "Mercury",
    solarDayMs = 175.9408 * EARTH_DAY_MS,
    siderealYrMs = 87.9691 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 9, workHoursEnd = 17, shiftHours = 8,
    epochMs = J2000_MS, earthClockSched = TRUE
  ),
  list(
    key = "venus", name = "Venus", symbol = "Venus",
    solarDayMs = 116.7500 * EARTH_DAY_MS,
    siderealYrMs = 224.701 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 9, workHoursEnd = 17, shiftHours = 8,
    epochMs = J2000_MS, earthClockSched = TRUE
  ),
  list(
    key = "earth", name = "Earth", symbol = "Earth",
    solarDayMs = 86400000,
    siderealYrMs = 365.25636 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 9, workHoursEnd = 17, shiftHours = 8,
    epochMs = J2000_MS
  ),
  list(
    key = "mars", name = "Mars", symbol = "Mars",
    solarDayMs = 88775244,
    siderealYrMs = 686.9957 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 9, workHoursEnd = 17, shiftHours = 8,
    epochMs = MARS_EPOCH_MS
  ),
  list(
    key = "jupiter", name = "Jupiter", symbol = "Jupiter",
    solarDayMs = 9.9250 * 3600000,
    siderealYrMs = 4332.589 * EARTH_DAY_MS,
    daysPerPeriod = 2.5, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 8, workHoursEnd = 16, shiftHours = 8,
    epochMs = J2000_MS
  ),
  list(
    key = "saturn", name = "Saturn", symbol = "Saturn",
    solarDayMs = 38080800,  # Mankovich et al. 2023: 10.578 h
    siderealYrMs = 10759.22 * EARTH_DAY_MS,
    daysPerPeriod = 2.25, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 8, workHoursEnd = 16, shiftHours = 8,
    epochMs = J2000_MS
  ),
  list(
    key = "uranus", name = "Uranus", symbol = "Uranus",
    solarDayMs = 17.2479 * 3600000,
    siderealYrMs = 30688.5 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 8, workHoursEnd = 16, shiftHours = 8,
    epochMs = J2000_MS
  ),
  list(
    key = "neptune", name = "Neptune", symbol = "Neptune",
    solarDayMs = 16.1100 * 3600000,
    siderealYrMs = 60195.0 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 8, workHoursEnd = 16, shiftHours = 8,
    epochMs = J2000_MS
  ),
  list(
    key = "moon", name = "Moon", symbol = "Moon",
    solarDayMs = 86400000,
    siderealYrMs = 365.25636 * EARTH_DAY_MS,
    daysPerPeriod = 1, periodsPerWeek = 7, workPeriodsPerWeek = 5,
    workHoursStart = 9, workHoursEnd = 17, shiftHours = 8,
    epochMs = J2000_MS
  )
)

# ── Orbital elements (Meeus Table 31.a) ────────────────────────────────────
# Index order matches Planet enum (0-8). Moon uses Earth's orbital elements.
# L0: mean longitude at J2000.0 (degrees)
# dL: rate (degrees per Julian century)
# om0: longitude of perihelion (degrees)
# e0: eccentricity at J2000.0
# a: semi-major axis (AU)

ORB_ELEMS <- list(
  list(L0 = 252.2507, dL = 149474.0722, om0 =  77.4561, e0 = 0.20564, a = 0.38710),  # mercury
  list(L0 = 181.9798, dL =  58519.2130, om0 = 131.5637, e0 = 0.00677, a = 0.72333),  # venus
  list(L0 = 100.4664, dL =  36000.7698, om0 = 102.9373, e0 = 0.01671, a = 1.00000),  # earth
  list(L0 = 355.4330, dL =  19141.6964, om0 = 336.0600, e0 = 0.09341, a = 1.52366),  # mars
  list(L0 =  34.3515, dL =   3036.3027, om0 =  14.3320, e0 = 0.04849, a = 5.20336),  # jupiter
  list(L0 =  50.0775, dL =   1223.5093, om0 =  93.0572, e0 = 0.05551, a = 9.53707),  # saturn
  list(L0 = 314.0550, dL =    429.8633, om0 = 173.0052, e0 = 0.04630, a = 19.1912),  # uranus
  list(L0 = 304.3480, dL =    219.8997, om0 =  48.1234, e0 = 0.00899, a = 30.0690),  # neptune
  list(L0 = 100.4664, dL =  36000.7698, om0 = 102.9373, e0 = 0.01671, a = 1.00000)   # moon (earth)
)

# ── IERS Leap seconds ──────────────────────────────────────────────────────
# Each entry: list(tai_utc, utc_ms)
# UTC ms values match Date.UTC() calls in planet-time.js

LEAP_SECS <- list(
  list(tai_utc = 10, utc_ms =   63072000000),  # 1972-01-01
  list(tai_utc = 11, utc_ms =   78796800000),  # 1972-07-01
  list(tai_utc = 12, utc_ms =   94694400000),  # 1973-01-01
  list(tai_utc = 13, utc_ms =  126230400000),  # 1974-01-01
  list(tai_utc = 14, utc_ms =  157766400000),  # 1975-01-01
  list(tai_utc = 15, utc_ms =  189302400000),  # 1976-01-01
  list(tai_utc = 16, utc_ms =  220924800000),  # 1977-01-01
  list(tai_utc = 17, utc_ms =  252460800000),  # 1978-01-01
  list(tai_utc = 18, utc_ms =  283996800000),  # 1979-01-01
  list(tai_utc = 19, utc_ms =  315532800000),  # 1980-01-01
  list(tai_utc = 20, utc_ms =  362793600000),  # 1981-07-01
  list(tai_utc = 21, utc_ms =  394329600000),  # 1982-07-01
  list(tai_utc = 22, utc_ms =  425865600000),  # 1983-07-01
  list(tai_utc = 23, utc_ms =  489024000000),  # 1985-07-01
  list(tai_utc = 24, utc_ms =  567993600000),  # 1988-01-01
  list(tai_utc = 25, utc_ms =  631152000000),  # 1990-01-01
  list(tai_utc = 26, utc_ms =  662688000000),  # 1991-01-01
  list(tai_utc = 27, utc_ms =  709948800000),  # 1992-07-01
  list(tai_utc = 28, utc_ms =  741484800000),  # 1993-07-01
  list(tai_utc = 29, utc_ms =  773020800000),  # 1994-07-01
  list(tai_utc = 30, utc_ms =  820454400000),  # 1996-01-01
  list(tai_utc = 31, utc_ms =  867715200000),  # 1997-07-01
  list(tai_utc = 32, utc_ms =  915148800000),  # 1999-01-01
  list(tai_utc = 33, utc_ms = 1136073600000),  # 2006-01-01
  list(tai_utc = 34, utc_ms = 1230768000000),  # 2009-01-01
  list(tai_utc = 35, utc_ms = 1341100800000),  # 2012-07-01
  list(tai_utc = 36, utc_ms = 1435708800000),  # 2015-07-01
  list(tai_utc = 37, utc_ms = 1483228800000)   # 2017-01-01
)
