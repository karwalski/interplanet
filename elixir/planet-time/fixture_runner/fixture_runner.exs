#!/usr/bin/env elixir
# fixture_runner.exs — validates 54 cross-language fixture entries
#
# Usage (via mix run — loads the compiled project, Jason available):
#   mix run fixture_runner/fixture_runner.exs ../../c/planet-time/fixtures/reference.json
#
# The script is invoked by `mix run` so all project modules are available.

path = System.argv() |> List.first() || "../../c/planet-time/fixtures/reference.json"

unless File.exists?(path) do
  IO.puts("SKIP: fixture file not found at #{path}")
  IO.puts("0 passed  0 failed  (fixtures skipped)")
  System.halt(0)
end

json_text = File.read!(path)

data =
  try do
    Jason.decode!(json_text)
  rescue
    e ->
      IO.puts(:stderr, "Failed to parse fixture: #{inspect(e)}")
      System.halt(1)
  end

entries = Map.fetch!(data, "entries")

# Ensure all planet atoms are registered in the atom table before
# String.to_existing_atom/1 is called for the first fixture entry.
_ = InterplanetTime.Constants.planets()

passed = 0
failed = 0

{passed, failed} =
  Enum.reduce(entries, {0, 0}, fn entry, {p, f} ->
    utc_ms     = trunc(entry["utc_ms"])
    planet_str = entry["planet"]
    exp_hour   = entry["hour"]
    exp_minute = entry["minute"]
    exp_lt     = entry["light_travel_s"]

    tag = "#{planet_str}@#{utc_ms}"

    planet =
      try do
        String.to_existing_atom(planet_str)
      rescue
        _ ->
          IO.puts("FAIL: #{tag} unknown planet: #{planet_str}")
          nil
      end

    if is_nil(planet) do
      {p, f + 1}
    else
      pt = InterplanetTime.get_planet_time(planet, utc_ms)

      {p1, f1} =
        if pt.hour == exp_hour do
          {p + 1, f}
        else
          IO.puts("FAIL: #{tag} hour=#{exp_hour} (got #{pt.hour})")
          {p, f + 1}
        end

      {p2, f2} =
        if pt.minute == exp_minute do
          {p1 + 1, f1}
        else
          IO.puts("FAIL: #{tag} minute=#{exp_minute} (got #{pt.minute})")
          {p1, f1 + 1}
        end

      {p3, f3} =
        if not is_nil(exp_lt) and exp_lt != 0.0 and
           planet_str not in ["earth", "moon"] do
          lt = InterplanetTime.light_travel_seconds(:earth, planet, utc_ms)
          if abs(lt - exp_lt) <= 2.0 do
            {p2 + 1, f2}
          else
            IO.puts("FAIL: #{tag} lightTravel — expected #{:erlang.float_to_binary(exp_lt, [{:decimals, 3}])}, got #{:erlang.float_to_binary(lt, [{:decimals, 3}])}")
            {p2, f2 + 1}
          end
        else
          {p2, f2}
        end

      {p3, f3}
    end
  end)

IO.puts("Fixture entries checked: #{length(entries)}")
IO.puts("#{passed} passed  #{failed} failed")

if failed > 0, do: System.halt(1)
