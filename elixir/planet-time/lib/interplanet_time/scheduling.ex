defmodule InterplanetTime.Scheduling do
  @moduledoc """
  find_meeting_windows/3 — find overlapping work windows between two planets.
  Ported verbatim from planet-time.js (Story 18.13).
  """

  alias InterplanetTime.TimeCalc
  alias InterplanetTime.Constants

  @step_ms 15 * 60_000  # 15-minute steps

  @doc """
  Find overlapping work windows between `planet_a` and `planet_b`
  over `earth_days` Earth days, starting from `start_ms` (UTC ms).

  Returns a list of maps: `%{start_ms, end_ms, duration_min}`.
  """
  def find_meeting_windows(planet_a, planet_b, opts \\ []) do
    earth_days = Keyword.get(opts, :earth_days, 7)
    start_ms   = Keyword.get(opts, :start_ms, System.os_time(:millisecond))
    end_ms     = start_ms + earth_days * Constants.earth_day_ms()

    scan(planet_a, planet_b, start_ms, end_ms, false, 0, [])
    |> Enum.reverse()
  end

  defp scan(_a, _b, t, end_ms, false, _ws, acc) when t >= end_ms, do: acc
  defp scan(_a, _b, t, end_ms, true,  ws, acc) when t >= end_ms do
    win = %{start_ms: ws, end_ms: end_ms, duration_min: div(end_ms - ws, 60_000)}
    [win | acc]
  end

  defp scan(planet_a, planet_b, t, end_ms, in_window, window_start, acc) do
    ta = TimeCalc.get_planet_time(planet_a, t)
    tb = TimeCalc.get_planet_time(planet_b, t)
    overlap = ta.is_work_hour and tb.is_work_hour

    {new_in, new_ws, new_acc} =
      cond do
        overlap and not in_window ->
          {true, t, acc}
        not overlap and in_window ->
          win = %{start_ms: window_start, end_ms: t, duration_min: div(t - window_start, 60_000)}
          {false, 0, [win | acc]}
        true ->
          {in_window, window_start, acc}
      end

    scan(planet_a, planet_b, t + @step_ms, end_ms, new_in, new_ws, new_acc)
  end
end
