# frozen_string_literal: true

module InterplanetTime
  # Immutable result objects (Struct-based for simplicity on Ruby 2.6+).

  PlanetTimeResult = Struct.new(
    :hour, :minute, :second,
    :local_hour, :day_fraction, :day_number, :day_in_year, :year_number,
    :period_in_week, :is_work_period, :is_work_hour,
    :time_str, :time_str_full,
    :sol_in_year, :sols_per_year,
    keyword_init: true
  )

  MTCResult = Struct.new(
    :sol, :hour, :minute, :second, :mtc_str,
    keyword_init: true
  )

  HelioPosResult = Struct.new(:x, :y, :r, :lon, keyword_init: true)

  LineOfSightResult = Struct.new(
    :clear, :blocked, :degraded, :closest_sun_au, :elong_deg,
    keyword_init: true
  )

  MeetingWindow = Struct.new(:start_ms, :end_ms, :duration_minutes, keyword_init: true)
end
