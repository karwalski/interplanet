-- constants.lua — Interplanetary Time Library constants
-- Story 18.19 — Lua port of planet-time
--
-- BODIES table indexed 0..8 (Sun=0, Mercury=1, ..., Neptune=8, Moon=9)
-- Note: the fixture/API uses planet indices matching the JS/Python:
--   Mercury=0, Venus=1, Earth=2, Mars=3, Jupiter=4, Saturn=5,
--   Uranus=6, Neptune=7, Moon=8

local M = {}

M.VERSION = "1.0.0"

-- ── Epoch constants ───────────────────────────────────────────────────────────

-- J2000.0 as Unix timestamp (ms): Date.UTC(2000, 0, 1, 12, 0, 0) = 946728000000
M.J2000_MS = 946728000000

-- Julian Day number of J2000.0
M.J2000_JD = 2451545.0

-- Julian Day of the Unix epoch (1970-01-01 00:00:00 UTC)
M.UNIX_EPOCH_JD = 2440587.5

-- Earth solar day in milliseconds
M.EARTH_DAY_MS = 86400000

-- Mars epoch (MY0 sol 0): 1953-05-24T09:03:58.464Z
M.MARS_EPOCH_MS = -524069761536

-- Mars solar day in milliseconds: 24h 39m 35.244s
M.MARS_SOL_MS = 88775244

-- ── Astronomical constants ────────────────────────────────────────────────────

M.AU_KM     = 149597870.7       -- 1 AU in km (IAU 2012 exact)
M.C_KMS     = 299792.458        -- speed of light km/s (SI exact)
M.AU_SECONDS = 149597870.7 / 299792.458  -- light travel time for 1 AU ≈ 499.004 s

-- ── Planet indices ────────────────────────────────────────────────────────────

M.MERCURY = 0
M.VENUS   = 1
M.EARTH   = 2
M.MARS    = 3
M.JUPITER = 4
M.SATURN  = 5
M.URANUS  = 6
M.NEPTUNE = 7
M.MOON    = 8

-- ── Leap-second table ─────────────────────────────────────────────────────────
-- { tai_minus_utc, utc_onset_ms }

M.LEAP_SECS = {
  { 10,  63072000000   }, -- 1972-01-01
  { 11,  78796800000   }, -- 1972-07-01
  { 12,  94694400000   }, -- 1973-01-01
  { 13,  126230400000  }, -- 1974-01-01
  { 14,  157766400000  }, -- 1975-01-01
  { 15,  189302400000  }, -- 1976-01-01
  { 16,  220924800000  }, -- 1977-01-01
  { 17,  252460800000  }, -- 1978-01-01
  { 18,  283996800000  }, -- 1979-01-01
  { 19,  315532800000  }, -- 1980-01-01
  { 20,  362793600000  }, -- 1981-07-01
  { 21,  394329600000  }, -- 1982-07-01
  { 22,  425865600000  }, -- 1983-07-01
  { 23,  489024000000  }, -- 1985-07-01
  { 24,  567993600000  }, -- 1988-01-01
  { 25,  631152000000  }, -- 1990-01-01
  { 26,  662688000000  }, -- 1991-01-01
  { 27,  709948800000  }, -- 1992-07-01
  { 28,  741484800000  }, -- 1993-07-01
  { 29,  773020800000  }, -- 1994-07-01
  { 30,  820454400000  }, -- 1996-01-01
  { 31,  867715200000  }, -- 1997-07-01
  { 32,  915148800000  }, -- 1999-01-01
  { 33,  1136073600000 }, -- 2006-01-01
  { 34,  1230768000000 }, -- 2009-01-01
  { 35,  1341100800000 }, -- 2012-07-01
  { 36,  1435708800000 }, -- 2015-07-01
  { 37,  1483228800000 }, -- 2017-01-01 — current as of 2025
}

-- ── Planet data table ─────────────────────────────────────────────────────────
-- Indexed 0..8 (Mercury..Moon)
-- Fields: name, solar_day_ms, sidereal_yr_ms, days_per_period,
--         periods_per_week, work_periods_per_week,
--         work_hours_start, work_hours_end, epoch_ms

M.PLANETS = {
  [M.MERCURY] = {
    name                  = "Mercury",
    solar_day_ms          = 175.9408 * 86400000,
    sidereal_yr_ms        = 87.9691  * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 9,
    work_hours_end        = 17,
    earth_clock_sched     = true,
    epoch_ms              = 946728000000,
  },
  [M.VENUS] = {
    name                  = "Venus",
    solar_day_ms          = 116.7500 * 86400000,
    sidereal_yr_ms        = 224.701  * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 9,
    work_hours_end        = 17,
    earth_clock_sched     = true,
    epoch_ms              = 946728000000,
  },
  [M.EARTH] = {
    name                  = "Earth",
    solar_day_ms          = 86400000,
    sidereal_yr_ms        = 365.25636 * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 9,
    work_hours_end        = 17,
    epoch_ms              = 946728000000,
  },
  [M.MARS] = {
    name                  = "Mars",
    solar_day_ms          = 88775244,
    sidereal_yr_ms        = 686.9957 * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 9,
    work_hours_end        = 17,
    epoch_ms              = -524069761536,
  },
  [M.JUPITER] = {
    name                  = "Jupiter",
    solar_day_ms          = 9.9250 * 3600000,
    sidereal_yr_ms        = 4332.589 * 86400000,
    days_per_period       = 2.5,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 8,
    work_hours_end        = 16,
    epoch_ms              = 946728000000,
  },
  [M.SATURN] = {
    name                  = "Saturn",
    solar_day_ms          = 10.578 * 3600000,
    sidereal_yr_ms        = 10759.22 * 86400000,
    days_per_period       = 2.25,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 8,
    work_hours_end        = 16,
    epoch_ms              = 946728000000,
  },
  [M.URANUS] = {
    name                  = "Uranus",
    solar_day_ms          = 17.2479 * 3600000,
    sidereal_yr_ms        = 30688.5 * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 8,
    work_hours_end        = 16,
    epoch_ms              = 946728000000,
  },
  [M.NEPTUNE] = {
    name                  = "Neptune",
    solar_day_ms          = 16.1100 * 3600000,
    sidereal_yr_ms        = 60195.0 * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 8,
    work_hours_end        = 16,
    epoch_ms              = 946728000000,
  },
  -- Moon uses Earth's solar day (tidally locked)
  [M.MOON] = {
    name                  = "Moon",
    solar_day_ms          = 86400000,
    sidereal_yr_ms        = 365.25636 * 86400000,
    days_per_period       = 1.0,
    periods_per_week      = 7,
    work_periods_per_week = 5,
    work_hours_start      = 9,
    work_hours_end        = 17,
    epoch_ms              = 946728000000,
  },
}

-- ── Orbital elements (Meeus Table 31.a) ──────────────────────────────────────
-- L0:  mean longitude at J2000.0 (degrees)
-- dL:  rate (degrees per Julian century)
-- om0: longitude of perihelion (degrees)
-- e0:  eccentricity at J2000.0
-- a:   semi-major axis (AU, constant)
-- Moon uses Earth's orbital elements.

M.ORB_ELEMS = {
  [M.MERCURY] = { L0=252.2507, dL=149474.0722, om0= 77.4561, e0=0.20564, a=0.38710 },
  [M.VENUS]   = { L0=181.9798, dL= 58519.2130, om0=131.5637, e0=0.00677, a=0.72333 },
  [M.EARTH]   = { L0=100.4664, dL= 36000.7698, om0=102.9373, e0=0.01671, a=1.00000 },
  [M.MARS]    = { L0=355.4330, dL= 19141.6964, om0=336.0600, e0=0.09341, a=1.52366 },
  [M.JUPITER] = { L0= 34.3515, dL=  3036.3027, om0= 14.3320, e0=0.04849, a=5.20336 },
  [M.SATURN]  = { L0= 50.0775, dL=  1223.5093, om0= 93.0572, e0=0.05551, a=9.53707 },
  [M.URANUS]  = { L0=314.0550, dL=   429.8633, om0=173.0052, e0=0.04630, a=19.1912 },
  [M.NEPTUNE] = { L0=304.3480, dL=   219.8997, om0= 48.1234, e0=0.00899, a=30.0690 },
  [M.MOON]    = { L0=100.4664, dL= 36000.7698, om0=102.9373, e0=0.01671, a=1.00000 },
}

-- Planet name → index lookup
M.PLANET_INDEX = {
  mercury = M.MERCURY,
  venus   = M.VENUS,
  earth   = M.EARTH,
  mars    = M.MARS,
  jupiter = M.JUPITER,
  saturn  = M.SATURN,
  uranus  = M.URANUS,
  neptune = M.NEPTUNE,
  moon    = M.MOON,
}

return M
