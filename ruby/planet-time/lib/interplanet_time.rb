# frozen_string_literal: true

# InterplanetTime — Ruby gem for interplanetary time calculations.
# Ported from planet-time.js (JavaScript reference implementation).
#
# @example
#   require 'interplanet_time'
#   pt = InterplanetTime.get_planet_time('mars', 946_728_000_000)
#   puts pt.time_str   # => "HH:MM"
#
#   lt = InterplanetTime.light_travel_seconds('earth', 'mars', Time.now.to_i * 1000)
#   puts InterplanetTime.format_light_time(lt)   # => e.g. "3 min 22 s"
#
module InterplanetTime
  require_relative 'interplanet_time/constants'
  require_relative 'interplanet_time/models'
  require_relative 'interplanet_time/orbital'
  require_relative 'interplanet_time/time_calc'
  require_relative 'interplanet_time/scheduling'
  require_relative 'interplanet_time/formatting'

  VERSION = Constants::VERSION

  # ── Planet time ──────────────────────────────────────────────────────────

  def self.get_planet_time(planet, utc_ms, tz_offset = 0.0)
    TimeCalc.get_planet_time(planet, utc_ms, tz_offset)
  end

  def self.get_mtc(utc_ms)
    TimeCalc.get_mtc(utc_ms)
  end

  def self.get_mars_time_at_offset(utc_ms, offset_hours)
    TimeCalc.get_mars_time_at_offset(utc_ms, offset_hours)
  end

  # ── Orbital mechanics ────────────────────────────────────────────────────

  def self.helio_pos(planet, utc_ms)
    Orbital.helio_pos(planet, utc_ms)
  end

  def self.body_distance_au(a, b, utc_ms)
    Orbital.body_distance_au(a, b, utc_ms)
  end

  def self.light_travel_seconds(a, b, utc_ms)
    Orbital.light_travel_seconds(a, b, utc_ms)
  end

  def self.check_line_of_sight(a, b, utc_ms)
    Orbital.check_line_of_sight(a, b, utc_ms)
  end

  def self.lower_quartile_light_time(a, b, ref_ms)
    Orbital.lower_quartile_light_time(a, b, ref_ms)
  end

  # ── TAI / JDE ────────────────────────────────────────────────────────────

  def self.tai_minus_utc(utc_ms)
    Orbital.tai_minus_utc(utc_ms)
  end

  def self.jde(utc_ms)
    Orbital.jde(utc_ms)
  end

  def self.jc(utc_ms)
    Orbital.jc(utc_ms)
  end

  # ── Scheduling ───────────────────────────────────────────────────────────

  def self.find_meeting_windows(planet_a, planet_b, from_ms, earth_days: 7)
    Scheduling.find_meeting_windows(planet_a, planet_b, from_ms, earth_days: earth_days)
  end

  # ── Formatting ───────────────────────────────────────────────────────────

  def self.format_light_time(seconds)
    Formatting.format_light_time(seconds)
  end

  def self.format_planet_time_iso(planet, h, m, s)
    Formatting.format_planet_time_iso(planet, h, m, s)
  end
end
