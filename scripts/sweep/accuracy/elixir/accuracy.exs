# Accuracy harness for elixir/planet-time (see ../gen-cases-group2.js).
# Run from elixir/planet-time:
#   mix run ../../scripts/sweep/accuracy/elixir/accuracy.exs ../../scripts/sweep/accuracy/instants-group2.txt
bodies = [:mercury, :venus, :earth, :mars, :jupiter, :saturn, :uranus, :neptune, :moon]
b = fn v -> if v, do: 1, else: 0 end

[path | _] = System.argv()

path
|> File.read!()
|> String.split("\n", trim: true)
|> Enum.each(fn line ->
  ms = line |> String.trim() |> String.to_integer()

  Enum.each(bodies, fn body ->
    try do
      pt = InterplanetTime.get_planet_time(body, ms)
      lt = InterplanetTime.light_travel_seconds(body, :earth, ms)

      IO.puts(
        Enum.join(
          [ms, body, pt.hour, pt.minute, pt.second, pt.day_number, pt.day_in_year,
           pt.year_number, pt.period_in_week, b.(pt.is_work_period), b.(pt.is_work_hour),
           :erlang.float_to_binary(lt * 1.0, decimals: 6)],
          "\t"
        )
      )
    rescue
      e -> IO.puts(:stderr, "#{ms} #{body}: #{Exception.message(e)}")
    end
  end)

  m = InterplanetTime.get_mtc(ms)
  IO.puts(Enum.join([ms, "mtc", m.sol, m.hour, m.minute, m.second], "\t"))
end)
