defmodule InterplanetTime.Formatting do
  @moduledoc """
  format_light_time/1 — human-readable light travel time string.
  Ported verbatim from planet-time.js (Story 18.13).
  """

  @doc """
  Format a light travel time in seconds as a human-readable string.

  Examples:
    iex> format_light_time(0.0)
    "<1ms"
    iex> format_light_time(0.5)
    "500ms"
    iex> format_light_time(30.0)
    "30.0s"
    iex> format_light_time(150.0)
    "2.5min"
    iex> format_light_time(4000.0)
    "1h 7m"
  """
  def format_light_time(seconds) do
    cond do
      seconds < 0.001 -> "<1ms"
      seconds < 1     -> "#{round(seconds * 1000)}ms"
      seconds < 60    -> "#{format_float_1(seconds)}s"
      seconds < 3600  -> "#{format_float_1(seconds / 60)}min"
      true ->
        h = trunc(seconds / 3600)
        m = round(:math.fmod(seconds, 3600) / 60)
        "#{h}h #{m}m"
    end
  end

  # Format a float to 1 decimal place
  defp format_float_1(x) do
    # Round to 1 decimal place
    rounded = Float.round(x, 1)
    # Format without trailing zeros beyond 1dp
    if rounded == trunc(rounded) do
      "#{trunc(rounded)}.0"
    else
      "#{rounded}"
    end
  end
end
