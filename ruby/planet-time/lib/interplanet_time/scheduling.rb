# frozen_string_literal: true

module InterplanetTime
  # Meeting window finder — ported from planet-time.js findMeetingWindows().
  module Scheduling
    extend self

    STEP_MS = 15 * 60 * 1000  # 15-minute step

    def find_meeting_windows(planet_a, planet_b, from_ms, earth_days: 7)
      end_ms      = from_ms + earth_days * Constants::EARTH_DAY_MS
      windows     = []
      in_window   = false
      window_start = 0

      t = from_ms
      while t < end_ms
        ta = TimeCalc.get_planet_time(planet_a, t)
        tb = TimeCalc.get_planet_time(planet_b, t)
        overlap = ta.is_work_hour && tb.is_work_hour

        if overlap && !in_window
          in_window    = true
          window_start = t
        elsif !overlap && in_window
          in_window = false
          dur = ((t - window_start) / 60_000).to_i
          windows << MeetingWindow.new(start_ms: window_start, end_ms: t,
                                       duration_minutes: dur)
        end
        t += STEP_MS
      end

      if in_window
        dur = ((end_ms - window_start) / 60_000).to_i
        windows << MeetingWindow.new(start_ms: window_start, end_ms: end_ms,
                                     duration_minutes: dur)
      end

      windows
    end
  end
end
