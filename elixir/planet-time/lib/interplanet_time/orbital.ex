defmodule InterplanetTime.Orbital do
  @moduledoc """
  Heliocentric position, distance, and light-travel calculations.
  Ported verbatim from planet-time.js (Story 18.13).
  """

  import :math, except: [fmod: 2]
  alias InterplanetTime.Constants

  # ── Leap seconds / TT ───────────────────────────────────────────────────────

  @doc "Returns TAI - UTC (leap seconds) for the given UTC milliseconds."
  def tai_minus_utc(utc_ms) do
    Constants.leap_secs()
    |> Enum.reduce_while(10, fn {delta, t_ms}, acc ->
      if utc_ms >= t_ms do
        {:cont, delta}
      else
        {:halt, acc}
      end
    end)
  end

  @doc "Returns the Julian Ephemeris Day (TT) from UTC milliseconds."
  def jde(utc_ms) do
    tt_ms = utc_ms + (tai_minus_utc(utc_ms) + 32.184) * 1000
    2_440_587.5 + tt_ms / 86_400_000.0
  end

  @doc "Returns Julian centuries from J2000.0 (TT)."
  def jc(utc_ms) do
    (jde(utc_ms) - Constants.j2000_jd()) / 36_525.0
  end

  # ── Kepler solver ────────────────────────────────────────────────────────────

  @doc "Solve Kepler's equation M = E - e·sin(E) via Newton-Raphson (tol 1e-12)."
  def kepler_e(m, e), do: kepler_iter(m, e, m, 0)

  defp kepler_iter(_m, _e, big_e, 50), do: big_e
  defp kepler_iter(m, e, big_e, i) do
    d_e = (m - big_e + e * sin(big_e)) / (1.0 - e * cos(big_e))
    new_e = big_e + d_e
    if Kernel.abs(d_e) < 1.0e-12 do
      new_e
    else
      kepler_iter(m, e, new_e, i + 1)
    end
  end

  # ── Heliocentric position ────────────────────────────────────────────────────

  @doc """
  Compute the heliocentric ecliptic position of `planet` at `utc_ms`.
  Returns `{x, y, r, lon}` in AU and radians.
  Moon uses Earth's orbital elements.
  """
  def helio_pos(planet, utc_ms) do
    el = Constants.orb_elems(planet) || Constants.orb_elems(:earth)

    t   = jc(utc_ms)
    tau = 2.0 * pi()
    d2r = pi() / 180.0

    l   = fmod((el.l0 + el.dl * t) * d2r, tau)
    l   = fmod(l + tau, tau)
    om  = el.om0 * d2r
    big_m = fmod(fmod(l - om, tau) + tau, tau)

    e    = el.e0
    a    = el.a
    big_e = kepler_e(big_m, e)

    v = 2.0 * atan2(
      sqrt(1.0 + e) * sin(big_e / 2.0),
      sqrt(1.0 - e) * cos(big_e / 2.0)
    )

    r   = a * (1.0 - e * cos(big_e))
    lon = fmod(fmod(v + om, tau) + tau, tau)

    {r * cos(lon), r * sin(lon), r, lon}
  end

  # ── Distance & light travel ──────────────────────────────────────────────────

  @doc "Returns the distance between two solar system bodies in AU."
  def body_distance_au(a, b, utc_ms) do
    {ax, ay, _, _} = helio_pos(a, utc_ms)
    {bx, by, _, _} = helio_pos(b, utc_ms)
    dx = ax - bx
    dy = ay - by
    sqrt(dx * dx + dy * dy)
  end

  @doc "Returns one-way light travel time between two bodies in seconds."
  def light_travel_seconds(from, to, utc_ms) do
    body_distance_au(from, to, utc_ms) * Constants.au_seconds()
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Floating-point modulo matching Dart/JS behaviour
  defp fmod(a, b) do
    result = :math.fmod(a, b)
    if result < 0, do: result + b, else: result
  end
end
