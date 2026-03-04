# frozen_string_literal: true

module InterplanetTime
  # Formatting utilities — ported from planet-time.js.
  module Formatting
    extend self

    # Format a light-travel duration (seconds) to human-readable string.
    # Examples: 45 → "45 s", 186 → "3 min 6 s", 3700 → "1 h 1 min 40 s"
    def format_light_time(seconds)
      s   = seconds.round
      h   = s / 3600
      m   = (s % 3600) / 60
      sec = s % 60

      parts = []
      parts << "#{h} h"   if h > 0
      parts << "#{m} min" if m > 0
      parts << "#{sec} s" if sec > 0 || parts.empty?
      parts.join(' ')
    end

    # Format a planet local time as an ISO-8601-like string.
    def format_planet_time_iso(planet, h, m, s)
      hh = h.to_s.rjust(2, '0')
      mm = m.to_s.rjust(2, '0')
      ss = s.to_s.rjust(2, '0')
      "#{hh}:#{mm}:#{ss}+#{planet}"
    end
  end
end
