# frozen_string_literal: true

module InterplanetTime
  # Planet time calculations — ported from planet-time.js.
  module TimeCalc
    extend self

    EARTH_DAY_MS_I = Constants::EARTH_DAY_MS

    def get_planet_time(planet, utc_ms, tz_offset = 0.0)
      # Moon uses Earth's solar day (tidally locked; schedules run on Earth time)
      effective = planet == 'moon' ? 'earth' : planet

      pd          = Constants::PLANET_DATA[effective]
      solar_day   = pd[:solar_day_ms]
      epoch_ms    = pd[:epoch_ms]
      work_start  = pd[:work_start]
      work_end    = pd[:work_end]
      days_per_p  = pd[:days_per_period]
      per_per_wk  = pd[:periods_per_week]
      work_per_wk = pd[:work_periods_per_week]
      sid_yr_ms   = pd[:sidereal_yr_ms]

      # tz_offset applied the same way as JS: shifts elapsed by a fraction of one day
      elapsed_ms  = (utc_ms - epoch_ms).to_f + tz_offset / 24.0 * solar_day
      total_days  = elapsed_ms / solar_day
      day_number  = total_days.floor
      day_frac    = total_days - day_number

      local_hour  = day_frac * 24.0
      hour        = local_hour.to_i
      min_f       = (local_hour - hour) * 60.0
      minute      = min_f.to_i
      second      = ((min_f - minute) * 60.0).to_i

      if pd[:earth_clock_schedule]
        # Mercury/Venus: Earth-clock week. UTC weekday as 0=Mon..6=Sun
        # (1970-01-01 was a Thursday), work hours on the UTC clock.
        utc_day        = utc_ms.floor.div(EARTH_DAY_MS_I)
        period_in_week = (utc_day + 3) % 7
        is_work_period = period_in_week < work_per_wk
        utc_sec        = (utc_ms.floor - utc_day * EARTH_DAY_MS_I).div(1000)
        utc_hour       = utc_sec / 3600.0
        is_work_hour   = is_work_period && utc_hour >= work_start && utc_hour < work_end
      else
        # Work period: positive modulo so pre-epoch dates give valid 0..(n-1) range
        total_periods  = total_days / days_per_p
        period_in_week = ((total_periods.floor % per_per_wk) + per_per_wk) % per_per_wk
        is_work_period = period_in_week < work_per_wk
        is_work_hour   = is_work_period && local_hour >= work_start && local_hour < work_end
      end

      # Year / day-in-year
      year_len_days = sid_yr_ms.to_f / solar_day
      year_number   = (total_days / year_len_days).floor
      day_in_year   = total_days - year_number * year_len_days

      sol_in_year   = effective == 'mars' ? day_in_year.floor : nil
      sols_per_year = effective == 'mars' ? (sid_yr_ms.to_f / solar_day).round : nil

      zone_prefix = { 'mars' => 'AMT', 'moon' => 'LMT', 'mercury' => 'MMT',
                       'venus' => 'VMT', 'jupiter' => 'JMT', 'saturn' => 'SMT',
                       'uranus' => 'UMT', 'neptune' => 'NMT' }
      zone_id = if planet == 'earth'
                  nil
                else
                  prefix = zone_prefix[planet]
                  offset = tz_offset.to_i
                  sign   = offset >= 0 ? '+' : '-'
                  "#{prefix}#{sign}#{offset.abs}"
                end

      h2 = hour.to_s.rjust(2, '0')
      m2 = minute.to_s.rjust(2, '0')
      s2 = second.to_s.rjust(2, '0')

      PlanetTimeResult.new(
        hour:           hour,
        minute:         minute,
        second:         second,
        local_hour:     local_hour,
        day_fraction:   day_frac,
        day_number:     day_number,
        day_in_year:    day_in_year.floor,
        year_number:    year_number,
        period_in_week: period_in_week,
        is_work_period: is_work_period,
        is_work_hour:   is_work_hour,
        time_str:       "#{h2}:#{m2}",
        time_str_full:  "#{h2}:#{m2}:#{s2}",
        sol_in_year:    sol_in_year,
        sols_per_year:  sols_per_year,
        zone_id:        zone_id
      )
    end

    # Mars Coordinated Time: the Mars clock at the prime meridian (AMT+0), in
    # Mars hours (1/24 sol), matching getMTC in planet-time.js.
    def get_mtc(utc_ms)
      total_sols = (utc_ms - Constants::MARS_EPOCH_MS).to_f / Constants::MARS_SOL_MS
      sol    = total_sols.floor
      frac   = total_sols - sol
      hour   = (frac * 24).floor
      minute = ((frac * 24 - hour) * 60).floor
      second = (((frac * 24 - hour) * 60 - minute) * 60).floor

      h2 = hour.to_s.rjust(2, '0')
      m2 = minute.to_s.rjust(2, '0')

      MTCResult.new(sol: sol, hour: hour, minute: minute, second: second,
                    mtc_str: "#{h2}:#{m2}")
    end

    def get_mars_time_at_offset(utc_ms, offset_hours)
      get_planet_time('mars', utc_ms, offset_hours)
    end
  end
end
