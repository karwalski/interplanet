defmodule InterplanetTime.Constants do
  @moduledoc """
  Fundamental constants, planet data, orbital elements, and leap seconds.
  Ported verbatim from planet-time.js (Story 18.13).

  All solar-day millisecond values are computed as round(float_days * 86_400_000)
  matching planet-time.js exactly.
  """

  # ── Fundamental constants ─────────────────────────────────────────────────

  @j2000_ms       946_728_000_000
  @mars_epoch_ms -524_069_761_536
  @mars_sol_ms    88_775_244
  @au_km          149_597_870.7
  @c_kms          299_792.458
  @j2000_jd       2_451_545.0
  @earth_day_ms   86_400_000

  def j2000_ms,      do: @j2000_ms
  def mars_epoch_ms, do: @mars_epoch_ms
  def mars_sol_ms,   do: @mars_sol_ms
  def au_km,         do: @au_km
  def c_kms,         do: @c_kms
  def j2000_jd,      do: @j2000_jd
  def earth_day_ms,  do: @earth_day_ms
  def au_seconds,    do: @au_km / @c_kms

  # ── Planet data ──────────────────────────────────────────────────────────
  # Mirrors the PLANETS table in planet-time.js.
  # solar_day_ms = round(days * 86_400_000) — computed with Node.js Math.round
  # sidereal_yr_ms = round(yr_days * 86_400_000)

  @planet_data %{
    mercury: %{
      solar_day_ms:         15_201_285_120,   # round(175.9408 * ED)
      sidereal_yr_ms:        7_600_530_240,   # round(87.9691 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           9,  work_end: 17,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5,
      earth_clock_sched:    true
    },
    venus: %{
      solar_day_ms:         10_087_200_000,   # round(116.7500 * ED)
      sidereal_yr_ms:       19_414_166_400,   # round(224.701 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           9,  work_end: 17,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5,
      earth_clock_sched:    true
    },
    earth: %{
      solar_day_ms:         @earth_day_ms,
      sidereal_yr_ms:       31_558_149_504,   # round(365.25636 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           9,  work_end: 17,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5
    },
    mars: %{
      solar_day_ms:         @mars_sol_ms,
      sidereal_yr_ms:       59_356_428_480,   # round(686.9957 * ED)
      epoch_ms:             @mars_epoch_ms,
      work_start:           9,  work_end: 17,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5
    },
    jupiter: %{
      solar_day_ms:             35_730_000,   # round(9.9250 * 3_600_000)
      sidereal_yr_ms:      374_335_689_600,   # round(4332.589 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           8,  work_end: 16,
      days_per_period:      2.5, periods_per_week: 7, work_periods_per_week: 5
    },
    saturn: %{
      solar_day_ms:             38_080_800,   # round(10.578 * 3_600_000) Mankovich et al. 2023
      sidereal_yr_ms:      929_596_608_000,   # round(10759.22 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           8,  work_end: 16,
      days_per_period:      2.25, periods_per_week: 7, work_periods_per_week: 5
    },
    uranus: %{
      solar_day_ms:             62_092_440,   # round(17.2479 * 3_600_000)
      sidereal_yr_ms:    2_651_486_400_000,   # round(30688.5 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           8,  work_end: 16,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5
    },
    neptune: %{
      solar_day_ms:             57_996_000,   # round(16.1100 * 3_600_000)
      sidereal_yr_ms:    5_200_848_000_000,   # round(60195.0 * ED)
      epoch_ms:             @j2000_ms,
      work_start:           8,  work_end: 16,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5
    },
    moon: %{
      solar_day_ms:         @earth_day_ms,
      sidereal_yr_ms:       31_558_149_504,   # round(365.25636 * ED) — same as Earth
      epoch_ms:             @j2000_ms,
      work_start:           9,  work_end: 17,
      days_per_period:      1.0, periods_per_week: 7, work_periods_per_week: 5
    }
  }

  def planet_data, do: @planet_data
  def planet_data(planet), do: @planet_data[planet]

  # ── Orbital elements (Meeus Table 31.a) ─────────────────────────────────
  # l0: mean longitude at J2000.0 (degrees)
  # dl: rate (degrees per Julian century)
  # om0: longitude of perihelion (degrees)
  # e0: eccentricity at J2000.0
  # a: semi-major axis (AU)
  # Moon uses Earth's elements for heliocentric position.

  @orb_elems %{
    mercury: %{l0: 252.2507, dl: 149_474.0722, om0:  77.4561, e0: 0.20564, a: 0.38710},
    venus:   %{l0: 181.9798, dl:  58_519.2130, om0: 131.5637, e0: 0.00677, a: 0.72333},
    earth:   %{l0: 100.4664, dl:  36_000.7698, om0: 102.9373, e0: 0.01671, a: 1.00000},
    mars:    %{l0: 355.4330, dl:  19_141.6964, om0: 336.0600, e0: 0.09341, a: 1.52366},
    jupiter: %{l0:  34.3515, dl:   3_036.3027, om0:  14.3320, e0: 0.04849, a: 5.20336},
    saturn:  %{l0:  50.0775, dl:   1_223.5093, om0:  93.0572, e0: 0.05551, a: 9.53707},
    uranus:  %{l0: 314.0550, dl:     429.8633, om0: 173.0052, e0: 0.04630, a: 19.1912},
    neptune: %{l0: 304.3480, dl:     219.8997, om0:  48.1234, e0: 0.00899, a: 30.0690},
    moon:    %{l0: 100.4664, dl:  36_000.7698, om0: 102.9373, e0: 0.01671, a: 1.00000}
  }

  def orb_elems, do: @orb_elems
  def orb_elems(planet), do: @orb_elems[planet]

  # ── IERS leap seconds ─────────────────────────────────────────────────────
  # Each entry: {tai_minus_utc, utc_ms_when_effective}
  # 28 entries, last updated: 2017-01-01

  @leap_secs [
    {10,    63_072_000_000},   # 1972-01-01
    {11,    78_796_800_000},   # 1972-07-01
    {12,    94_694_400_000},   # 1973-01-01
    {13,   126_230_400_000},   # 1974-01-01
    {14,   157_766_400_000},   # 1975-01-01
    {15,   189_302_400_000},   # 1976-01-01
    {16,   220_924_800_000},   # 1977-01-01
    {17,   252_460_800_000},   # 1978-01-01
    {18,   283_996_800_000},   # 1979-01-01
    {19,   315_532_800_000},   # 1980-01-01
    {20,   362_793_600_000},   # 1981-07-01
    {21,   394_329_600_000},   # 1982-07-01
    {22,   425_865_600_000},   # 1983-07-01
    {23,   489_024_000_000},   # 1985-07-01
    {24,   567_993_600_000},   # 1988-01-01
    {25,   631_152_000_000},   # 1990-01-01
    {26,   662_688_000_000},   # 1991-01-01
    {27,   709_948_800_000},   # 1992-07-01
    {28,   741_484_800_000},   # 1993-07-01
    {29,   773_020_800_000},   # 1994-07-01
    {30,   820_454_400_000},   # 1996-01-01
    {31,   867_715_200_000},   # 1997-07-01
    {32,   915_148_800_000},   # 1999-01-01
    {33, 1_136_073_600_000},   # 2006-01-01
    {34, 1_230_768_000_000},   # 2009-01-01
    {35, 1_341_100_800_000},   # 2012-07-01
    {36, 1_435_708_800_000},   # 2015-07-01
    {37, 1_483_228_800_000}    # 2017-01-01
  ]

  def leap_secs, do: @leap_secs

  # Valid planet atoms
  @planets [:mercury, :venus, :earth, :mars, :jupiter, :saturn, :uranus, :neptune, :moon]
  def planets, do: @planets
end
