# frozen_string_literal: true

module InterplanetTime
  # Numerical constants — ported verbatim from planet-time.js.
  # All times in UTC milliseconds since Unix epoch.
  module Constants
    VERSION = '0.1.0'

    J2000_MS         = 946_728_000_000   # Date.UTC(2000,0,1,12,0,0) — TT noon
    J2000_JD         = 2_451_545.0
    EARTH_DAY_MS     = 86_400_000
    MARS_EPOCH_MS    = -524_069_761_536  # MY 0 sol 0 — Date.UTC(1953,4,24,9,3,58,464)
    MARS_SOL_MS      = 88_775_244        # ms per Mars solar day
    AU_KM            = 149_597_870.7
    C_KMS            = 299_792.458
    AU_SECONDS       = AU_KM / C_KMS    # ~499.0 s

    PLANETS = %w[mercury venus earth mars jupiter saturn uranus neptune moon].freeze

    # Per-planet calendar constants — sourced verbatim from PLANETS table in planet-time.js.
    # daysPerPeriod, periodsPerWeek, workPeriodsPerWeek: planet week structure.
    PLANET_DATA = {
      'mercury' => {
        solar_day_ms:           (175.9408 * EARTH_DAY_MS).round,
        sidereal_yr_ms:         ( 87.9691 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             8,  work_end: 16,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
      'venus'   => {
        solar_day_ms:           (116.7500 * EARTH_DAY_MS).round,
        sidereal_yr_ms:         (224.701  * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             8,  work_end: 16,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
      'earth'   => {
        solar_day_ms:           EARTH_DAY_MS,
        sidereal_yr_ms:         (365.25636 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             9,  work_end: 17,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
      'mars'    => {
        solar_day_ms:           MARS_SOL_MS,
        sidereal_yr_ms:         (686.9957 * EARTH_DAY_MS).round,
        epoch_ms:               MARS_EPOCH_MS,
        work_start:             9,  work_end: 17,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
      'jupiter' => {
        solar_day_ms:           (9.9250  * 3_600_000).round,
        sidereal_yr_ms:         (4332.589 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             8,  work_end: 16,
        days_per_period:        2.5, periods_per_week: 7, work_periods_per_week: 5,
      },
      'saturn'  => {
        solar_day_ms:           (10.5606 * 3_600_000).round,
        sidereal_yr_ms:         (10_759.22 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             8,  work_end: 16,
        days_per_period:        2.25, periods_per_week: 7, work_periods_per_week: 5,
      },
      'uranus'  => {
        solar_day_ms:           (17.2479 * 3_600_000).round,
        sidereal_yr_ms:         (30_688.5 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             8,  work_end: 16,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
      'neptune' => {
        solar_day_ms:           (16.1100 * 3_600_000).round,
        sidereal_yr_ms:         (60_195.0 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             8,  work_end: 16,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
      'moon'    => {
        # Moon uses Earth's solar day (tidally locked; schedules run on Earth time)
        solar_day_ms:           EARTH_DAY_MS,
        sidereal_yr_ms:         (365.25636 * EARTH_DAY_MS).round,
        epoch_ms:               J2000_MS,
        work_start:             9,  work_end: 17,
        days_per_period:        1.0, periods_per_week: 7, work_periods_per_week: 5,
      },
    }.freeze

    # Keplerian orbital elements at J2000.0 — verbatim from planet-time.js (Meeus Table 31.a).
    # L0 (deg), dL (deg/Julian century), om0 (deg), e0, a (AU).
    # Moon uses Earth's values for orbital mechanics.
    ORBITAL_ELEMENTS = {
      'mercury' => { L0: 252.2507, dL: 149_474.0722, om0:  77.4561, e0: 0.20564, a:  0.38710 },
      'venus'   => { L0: 181.9798, dL:  58_519.2130, om0: 131.5637, e0: 0.00677, a:  0.72333 },
      'earth'   => { L0: 100.4664, dL:  36_000.7698, om0: 102.9373, e0: 0.01671, a:  1.00000 },
      'mars'    => { L0: 355.4330, dL:  19_141.6964, om0: 336.0600, e0: 0.09341, a:  1.52366 },
      'jupiter' => { L0:  34.3515, dL:   3_036.3027, om0:  14.3320, e0: 0.04849, a:  5.20336 },
      'saturn'  => { L0:  50.0775, dL:   1_223.5093, om0:  93.0572, e0: 0.05551, a:  9.53707 },
      'uranus'  => { L0: 314.0550, dL:     429.8633, om0: 173.0052, e0: 0.04630, a: 19.19126 },
      'neptune' => { L0: 304.3480, dL:     219.8997, om0:  48.1234, e0: 0.00899, a: 30.06900 },
      'moon'    => { L0: 100.4664, dL:  36_000.7698, om0: 102.9373, e0: 0.01671, a:  1.00000 },
    }.freeze

    # Leap-second table: [UTC_ms, TAI-UTC], ascending order.
    # Verbatim from planet-time.js LEAP_SECONDS.
    LEAP_SECONDS = [
      [  63_072_000_000,  10], [  78_796_800_000,  11], [  94_694_400_000,  12],
      [ 126_230_400_000,  13], [ 157_766_400_000,  14], [ 189_302_400_000,  15],
      [ 220_924_800_000,  16], [ 252_460_800_000,  17], [ 283_996_800_000,  18],
      [ 315_532_800_000,  19], [ 362_793_600_000,  20], [ 394_329_600_000,  21],
      [ 425_865_600_000,  22], [ 489_024_000_000,  23], [ 567_993_600_000,  24],
      [ 631_152_000_000,  25], [ 662_688_000_000,  26], [ 709_948_800_000,  27],
      [ 741_484_800_000,  28], [ 773_020_800_000,  29], [ 820_454_400_000,  30],
      [ 867_715_200_000,  31], [ 915_148_800_000,  32], [1_136_073_600_000, 33],
      [1_230_768_000_000, 34], [1_341_100_800_000, 35], [1_435_708_800_000, 36],
      [1_483_228_800_000, 37],
    ].freeze
  end
end
