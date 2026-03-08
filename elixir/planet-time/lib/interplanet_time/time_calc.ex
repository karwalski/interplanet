defmodule InterplanetTime.TimeCalc do
  @moduledoc """
  get_planet_time/3 and get_mtc/1.
  Ported verbatim from planet-time.js (Story 18.13).
  """

  import Kernel, except: [floor: 1]
  alias InterplanetTime.Constants

  # ── Planet time ──────────────────────────────────────────────────────────────

  @zone_prefixes %{
    mercury: "MMT",
    venus:   "VMT",
    mars:    "AMT",
    jupiter: "JMT",
    saturn:  "SMT",
    uranus:  "UMT",
    neptune: "NMT",
    moon:    "LMT"
  }

  @doc """
  Get the local time on `planet` at `utc_ms`.

  `tz_offset_h` is the optional zone offset in planet local hours from the
  planet's prime meridian (e.g. +4.0 for AMT+4 on Mars).

  Returns a map with keys:
    :hour, :minute, :second, :local_hour, :day_fraction,
    :day_number, :day_in_year, :year_number, :period_in_week,
    :is_work_period, :is_work_hour, :time_str, :time_str_full,
    :sol_in_year (nil unless :mars), :sols_per_year (nil unless :mars),
    :zone_id (nil for Earth; e.g. "AMT+4" for Mars with tz_offset_h=4)
  """
  def get_planet_time(planet, utc_ms, tz_offset_h \\ 0.0) do
    # Moon uses Earth's solar day
    effective = if planet == :moon, do: :earth, else: planet
    pd = Constants.planet_data(effective)

    solar_day = pd.solar_day_ms * 1.0
    elapsed_ms = (utc_ms - pd.epoch_ms) * 1.0 + tz_offset_h / 24.0 * solar_day
    total_days = elapsed_ms / solar_day

    day_number = floor(total_days)
    day_frac   = total_days - day_number

    local_hour = day_frac * 24.0
    h          = trunc(local_hour)
    min_f      = (local_hour - h) * 60.0
    m          = trunc(min_f)
    s          = trunc((min_f - m) * 60.0)

    # Work period — Mercury/Venus use Earth-clock scheduling (UTC day-of-week + UTC hour)
    earth_clock = Map.get(pd, :earth_clock_sched, false)
    {piw, is_work_period, is_work_hour} =
      if earth_clock do
        # dow = ((floor(utc_ms / 86400000) % 7) + 3) % 7 — Mon=0..Sun=6
        utc_day_int = trunc(:math.floor(utc_ms / 86_400_000.0))
        dow = Integer.mod(Integer.mod(utc_day_int, 7) + 3, 7)
        is_wp = dow < 5
        utc_ms_of_day = trunc(utc_ms) - utc_day_int * 86_400_000
        utc_h = div(utc_ms_of_day, 3_600_000)
        is_wh = is_wp and utc_h >= pd.work_start and utc_h < pd.work_end
        {dow, is_wp, is_wh}
      else
        total_periods = total_days / pd.days_per_period
        p = Integer.mod(floor(total_periods), pd.periods_per_week)
        is_wp = p < pd.work_periods_per_week
        is_wh = is_wp and local_hour >= pd.work_start and local_hour < pd.work_end
        {p, is_wp, is_wh}
      end

    year_len_days = pd.sidereal_yr_ms / solar_day
    year_number   = floor(total_days / year_len_days)
    day_in_year   = floor(total_days - year_number * year_len_days)

    {sol_in_year, sols_per_year} =
      if effective == :mars do
        syear = trunc(pd.sidereal_yr_ms / solar_day + 0.5)
        {trunc(day_in_year), syear}
      else
        {nil, nil}
      end

    zone_id =
      case Map.get(@zone_prefixes, planet) do
        nil    -> nil
        prefix ->
          n = trunc(tz_offset_h)
          if n >= 0, do: "#{prefix}+#{n}", else: "#{prefix}-#{abs(n)}"
      end

    %{
      hour:           h,
      minute:         m,
      second:         s,
      local_hour:     local_hour,
      day_fraction:   day_frac,
      day_number:     trunc(day_number),
      day_in_year:    trunc(day_in_year),
      year_number:    trunc(year_number),
      period_in_week: piw,
      is_work_period: is_work_period,
      is_work_hour:   is_work_hour,
      time_str:       "#{pad2(h)}:#{pad2(m)}",
      time_str_full:  "#{pad2(h)}:#{pad2(m)}:#{pad2(s)}",
      sol_in_year:    sol_in_year,
      sols_per_year:  sols_per_year,
      zone_id:        zone_id
    }
  end

  # ── Mars Coordinated Time ────────────────────────────────────────────────────

  @doc """
  Get Mars Coordinated Time (MTC) — the Martian equivalent of UTC.

  Returns a map with keys: :sol, :hour, :minute, :second, :mtc_str
  """
  def get_mtc(utc_ms) do
    mars_epoch = Constants.mars_epoch_ms()
    mars_sol   = Constants.mars_sol_ms()

    total_sols = (utc_ms - mars_epoch) / (mars_sol * 1.0)
    sol        = floor(total_sols)
    frac       = total_sols - sol

    h = trunc(frac * 24)
    m = trunc((frac * 24 - h) * 60)
    s = trunc(((frac * 24 - h) * 60 - m) * 60)

    %{
      sol:     trunc(sol),
      hour:    h,
      minute:  m,
      second:  s,
      mtc_str: "#{pad2(h)}:#{pad2(m)}"
    }
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp pad2(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp floor(x), do: trunc(:math.floor(x))
end
