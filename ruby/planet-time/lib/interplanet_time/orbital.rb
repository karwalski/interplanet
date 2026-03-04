# frozen_string_literal: true

module InterplanetTime
  # Orbital mechanics — ported from planet-time.js.
  module Orbital
    extend self

    # ── Leap seconds / TT ────────────────────────────────────────────────────

    def tai_minus_utc(utc_ms)
      tai = 10
      Constants::LEAP_SECONDS.each do |(ts, delta)|
        break if utc_ms < ts
        tai = delta
      end
      tai
    end

    # Julian Ephemeris Day (TT) from UTC milliseconds.
    def jde(utc_ms)
      tt_ms = utc_ms + tai_minus_utc(utc_ms) * 1000 + 32_184 # TT = TAI + 32.184 s
      2_440_587.5 + tt_ms / 86_400_000.0
    end

    # Julian centuries from J2000.0 (TT).
    def jc(utc_ms)
      (jde(utc_ms) - Constants::J2000_JD) / 36_525.0
    end

    # ── Kepler solver ────────────────────────────────────────────────────────

    def kepler_e(m_rad, e)
      e_val = m_rad
      50.times do
        d_e = (m_rad - e_val + e * Math.sin(e_val)) / (1.0 - e * Math.cos(e_val))
        e_val += d_e
        break if d_e.abs < 1e-12
      end
      e_val
    end

    # ── Heliocentric position ─────────────────────────────────────────────────

    def helio_pos(planet, utc_ms)
      elems = Constants::ORBITAL_ELEMENTS[planet] ||
              Constants::ORBITAL_ELEMENTS['earth']

      t   = jc(utc_ms)
      l   = (elems[:L0] + elems[:dL] * t) % 360.0
      om  = elems[:om0]
      e   = elems[:e0]
      a   = elems[:a]

      # Mean anomaly (deg → rad)
      m_rad = ((l - om + 360.0) % 360.0) * Math::PI / 180.0
      e_anom = kepler_e(m_rad, e)

      # True anomaly
      nu = 2.0 * Math.atan2(
        Math.sqrt(1.0 + e) * Math.sin(e_anom / 2.0),
        Math.sqrt(1.0 - e) * Math.cos(e_anom / 2.0)
      )

      r   = a * (1.0 - e * Math.cos(e_anom))
      lon = (om * Math::PI / 180.0 + nu + 2.0 * Math::PI) % (2.0 * Math::PI)

      HelioPosResult.new(
        x:   r * Math.cos(lon),
        y:   r * Math.sin(lon),
        r:   r,
        lon: lon
      )
    end

    # ── Distance & light travel ────────────────────────────────────────────────

    def body_distance_au(a, b, utc_ms)
      pa = helio_pos(a, utc_ms)
      pb = helio_pos(b, utc_ms)
      dx = pa.x - pb.x
      dy = pa.y - pb.y
      Math.sqrt(dx * dx + dy * dy)
    end

    def light_travel_seconds(a, b, utc_ms)
      body_distance_au(a, b, utc_ms) * Constants::AU_SECONDS
    end

    # ── Line of sight ─────────────────────────────────────────────────────────

    def check_line_of_sight(a, b, utc_ms)
      pa = helio_pos(a, utc_ms)
      pb = helio_pos(b, utc_ms)

      abx = pb.x - pa.x
      aby = pb.y - pa.y
      d2  = abx * abx + aby * aby

      if d2 < 1e-20
        return LineOfSightResult.new(
          clear: true, blocked: false, degraded: false,
          closest_sun_au: nil, elong_deg: 0.0
        )
      end

      t = [0.0, [(-(pa.x * abx + pa.y * aby) / d2), 1.0].min].max
      cx = pa.x + t * abx
      cy = pa.y + t * aby
      closest = Math.sqrt(cx * cx + cy * cy)

      dot_ab  = abx * pa.x + aby * pa.y
      ab_mag  = Math.sqrt(d2)
      a_mag   = Math.sqrt(pa.x**2 + pa.y**2)
      cos_el  = (a_mag > 1e-10 && ab_mag > 1e-10) ? -dot_ab / (ab_mag * a_mag) : 0.0
      elong   = Math.acos([[-1.0, cos_el].max, 1.0].min) * 180.0 / Math::PI

      blocked  = closest < 0.1
      degraded = !blocked && (closest < 0.25 || elong < 5.0)

      LineOfSightResult.new(
        clear:          !blocked && !degraded,
        blocked:        blocked,
        degraded:       degraded,
        closest_sun_au: closest,
        elong_deg:      elong
      )
    end

    # ── Lower-quartile light time ──────────────────────────────────────────────

    def lower_quartile_light_time(a, b, ref_ms)
      year_ms = 365 * Constants::EARTH_DAY_MS
      step    = year_ms / 360
      samples = (0...360).map { |i| light_travel_seconds(a, b, ref_ms + i * step) }
      samples.sort!
      samples[(samples.size * 0.25).to_i]
    end
  end
end
