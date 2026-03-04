defmodule InterplanetTime do
  @moduledoc """
  InterPlanet Time — Elixir port (Story 18.13).

  Facade module re-exporting the public API from sub-modules.

  Planet atoms: :mercury :venus :earth :mars :jupiter :saturn :uranus :neptune :moon

  ## Examples

      iex> now = System.os_time(:millisecond)
      iex> mars = InterplanetTime.get_planet_time(:mars, now)
      iex> is_map(mars)
      true

      iex> lt = InterplanetTime.light_travel_seconds(:earth, :mars, 946728000000)
      iex> lt > 0
      true
  """

  alias InterplanetTime.TimeCalc
  alias InterplanetTime.Orbital
  alias InterplanetTime.Formatting
  alias InterplanetTime.Scheduling

  @doc """
  Get the local time on `planet` at `utc_ms`.

  `tz_offset_h` is the optional zone offset in planet local hours from the
  planet's prime meridian (e.g. +4.0 for AMT+4 on Mars).
  """
  defdelegate get_planet_time(planet, utc_ms, tz_offset_h \\ 0.0), to: TimeCalc

  @doc "Get Mars Coordinated Time (MTC) for the given UTC milliseconds."
  defdelegate get_mtc(utc_ms), to: TimeCalc

  @doc "Returns the heliocentric ecliptic position of `planet` at `utc_ms` as `{x, y, r, lon}`."
  defdelegate helio_pos(planet, utc_ms), to: Orbital

  @doc "Returns the distance between two solar system bodies in AU."
  defdelegate body_distance_au(a, b, utc_ms), to: Orbital

  @doc "Returns one-way light travel time between two bodies in seconds."
  defdelegate light_travel_seconds(from, to, utc_ms), to: Orbital

  @doc "Format a light travel time in seconds as a human-readable string."
  defdelegate format_light_time(seconds), to: Formatting

  @doc "Find overlapping work windows between two planets."
  defdelegate find_meeting_windows(planet_a, planet_b, opts \\ []), to: Scheduling
end
