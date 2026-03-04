"""
_constants.py — Interplanetary Time Library constants.
Mirrors planet-time.js v0.1.0 numeric values verbatim.
"""

import calendar
from enum import IntEnum

__all__ = [
    "Planet", "J2000_MS", "J2000_JD", "EARTH_DAY_MS",
    "AU_KM", "C_KMS", "AU_SECONDS",
    "MARS_EPOCH_MS", "MARS_SOL_MS",
    "LEAP_SECS", "PLANETS", "ORB_ELEMS",
]


class Planet(IntEnum):
    MERCURY = 0
    VENUS   = 1
    EARTH   = 2
    MARS    = 3
    JUPITER = 4
    SATURN  = 5
    URANUS  = 6
    NEPTUNE = 7
    MOON    = 8


# ── Epoch constants ────────────────────────────────────────────────────────────

# J2000.0 as Unix timestamp (ms): Date.UTC(2000, 0, 1, 12, 0, 0) = 946728000000
J2000_MS: int = 946728000000

# Julian Day number of J2000.0
J2000_JD: float = 2451545.0

# Earth solar day in milliseconds
EARTH_DAY_MS: int = 86400000

# Mars epoch (MY0 sol 0): Date.UTC(1953, 4, 24, 9, 3, 58, 464) = -524069761536
MARS_EPOCH_MS: int = -524069761536

# Mars solar day in milliseconds: 24h 39m 35.244s  (Allison & McEwen 2000)
MARS_SOL_MS: int = 88775244

# ── Astronomical constants ─────────────────────────────────────────────────────

AU_KM: float = 149597870.7          # 1 AU in km  (IAU 2012 Resolution B2)
C_KMS: float = 299792.458           # Speed of light in km/s  (SI exact)
AU_SECONDS: float = AU_KM / C_KMS  # Light travel time for 1 AU ≈ 499.004 s

# ── IERS leap seconds ──────────────────────────────────────────────────────────
# (TAI − UTC in seconds, UTC timestamp ms when offset took effect)
# Mirrors LEAP_SECONDS in planet-time.js exactly.

def _utc(year: int, month0: int, day: int,
         h: int = 0, m: int = 0, s: int = 0, ms: int = 0) -> int:
    """UTC milliseconds from (year, JS-style 0-based month, day, ...)."""
    tup = (year, month0 + 1, day, h, m, s, 0, 0, 0)
    return calendar.timegm(tup) * 1000 + ms


LEAP_SECS: list[tuple[int, int]] = [
    (10, _utc(1972, 0, 1)),  (11, _utc(1972, 6, 1)),  (12, _utc(1973, 0, 1)),
    (13, _utc(1974, 0, 1)),  (14, _utc(1975, 0, 1)),  (15, _utc(1976, 0, 1)),
    (16, _utc(1977, 0, 1)),  (17, _utc(1978, 0, 1)),  (18, _utc(1979, 0, 1)),
    (19, _utc(1980, 0, 1)),  (20, _utc(1981, 6, 1)),  (21, _utc(1982, 6, 1)),
    (22, _utc(1983, 6, 1)),  (23, _utc(1985, 6, 1)),  (24, _utc(1988, 0, 1)),
    (25, _utc(1990, 0, 1)),  (26, _utc(1991, 0, 1)),  (27, _utc(1992, 6, 1)),
    (28, _utc(1993, 6, 1)),  (29, _utc(1994, 6, 1)),  (30, _utc(1996, 0, 1)),
    (31, _utc(1997, 6, 1)),  (32, _utc(1999, 0, 1)),  (33, _utc(2006, 0, 1)),
    (34, _utc(2009, 0, 1)),  (35, _utc(2012, 6, 1)),  (36, _utc(2015, 6, 1)),
    (37, _utc(2017, 0, 1)),  # Current as of 2025
]

# ── Planet data ────────────────────────────────────────────────────────────────
# Mirrors the PLANETS dict in planet-time.js.
# Moon maps to Earth's solar-day data (tidally locked; work schedules on Earth time).

PLANETS: dict[int, dict] = {
    Planet.MERCURY: dict(
        name="Mercury",
        solarDayMs=175.9408 * EARTH_DAY_MS,
        siderealYrMs=87.9691 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=9, workHoursEnd=17,
        earthClockSched=True,
        epochMs=J2000_MS,
    ),
    Planet.VENUS: dict(
        name="Venus",
        solarDayMs=116.7500 * EARTH_DAY_MS,
        siderealYrMs=224.701 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=9, workHoursEnd=17,
        earthClockSched=True,
        epochMs=J2000_MS,
    ),
    Planet.EARTH: dict(
        name="Earth",
        solarDayMs=86400000,
        siderealYrMs=365.25636 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=9, workHoursEnd=17,
        epochMs=J2000_MS,
    ),
    Planet.MARS: dict(
        name="Mars",
        solarDayMs=88775244,  # 24h 39m 35.244s
        siderealYrMs=686.9957 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=9, workHoursEnd=17,
        epochMs=MARS_EPOCH_MS,
    ),
    Planet.JUPITER: dict(
        name="Jupiter",
        solarDayMs=9.9250 * 3600000,
        siderealYrMs=4332.589 * EARTH_DAY_MS,
        daysPerPeriod=2.5, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=8, workHoursEnd=16,
        epochMs=J2000_MS,
    ),
    Planet.SATURN: dict(
        name="Saturn",
        solarDayMs=10.578 * 3600000,
        siderealYrMs=10759.22 * EARTH_DAY_MS,
        daysPerPeriod=2.25, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=8, workHoursEnd=16,
        epochMs=J2000_MS,
    ),
    Planet.URANUS: dict(
        name="Uranus",
        solarDayMs=17.2479 * 3600000,
        siderealYrMs=30688.5 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=8, workHoursEnd=16,
        epochMs=J2000_MS,
    ),
    Planet.NEPTUNE: dict(
        name="Neptune",
        solarDayMs=16.1100 * 3600000,
        siderealYrMs=60195.0 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=8, workHoursEnd=16,
        epochMs=J2000_MS,
    ),
    # Moon uses Earth's solar day (tidally locked)
    Planet.MOON: dict(
        name="Moon",
        solarDayMs=86400000,
        siderealYrMs=365.25636 * EARTH_DAY_MS,
        daysPerPeriod=1, periodsPerWeek=7, workPeriodsPerWeek=5,
        workHoursStart=9, workHoursEnd=17,
        epochMs=J2000_MS,
    ),
}

# ── Orbital elements (Meeus Table 31.a) ───────────────────────────────────────
# L0: mean longitude at J2000.0 (degrees)
# dL: rate (degrees per Julian century)
# om0: longitude of perihelion (degrees)
# e0: eccentricity at J2000.0
# a: semi-major axis (AU, constant)
# Moon uses Earth's orbital elements.

ORB_ELEMS: dict[int, dict] = {
    Planet.MERCURY: dict(L0=252.2507, dL=149474.0722, om0= 77.4561, e0=0.20564, a=0.38710),
    Planet.VENUS:   dict(L0=181.9798, dL= 58519.2130, om0=131.5637, e0=0.00677, a=0.72333),
    Planet.EARTH:   dict(L0=100.4664, dL= 36000.7698, om0=102.9373, e0=0.01671, a=1.00000),
    Planet.MARS:    dict(L0=355.4330, dL= 19141.6964, om0=336.0600, e0=0.09341, a=1.52366),
    Planet.JUPITER: dict(L0= 34.3515, dL=  3036.3027, om0= 14.3320, e0=0.04849, a=5.20336),
    Planet.SATURN:  dict(L0= 50.0775, dL=  1223.5093, om0= 93.0572, e0=0.05551, a=9.53707),
    Planet.URANUS:  dict(L0=314.0550, dL=   429.8633, om0=173.0052, e0=0.04630, a=19.1912),
    Planet.NEPTUNE: dict(L0=304.3480, dL=   219.8997, om0= 48.1234, e0=0.00899, a=30.0690),
    Planet.MOON:    dict(L0=100.4664, dL= 36000.7698, om0=102.9373, e0=0.01671, a=1.00000),
}
