# interplanet_time — Elixir

Elixir port of the [InterPlanet Time](https://interplanet.live) planet-time library
(Story 18.13). Provides solar-day time, work-schedule, orbital mechanics, and
light-speed calculations for every planet in the solar system.

## Usage

```elixir
now = System.os_time(:millisecond)

# Get Mars local time (AMT+0)
mars = InterplanetTime.get_planet_time(:mars, now)
IO.puts("Mars: #{mars.time_str}")

# Light travel time Earth → Mars
lt = InterplanetTime.light_travel_seconds(:earth, :mars, now)
IO.puts("Light travel: #{InterplanetTime.format_light_time(lt)}")

# Mars Coordinated Time
mtc = InterplanetTime.get_mtc(now)
IO.puts("MTC: #{mtc.mtc_str}")
```

## API

- `InterplanetTime.get_planet_time(planet, utc_ms, tz_offset_h \\ 0.0)` → map
- `InterplanetTime.get_mtc(utc_ms)` → map
- `InterplanetTime.helio_pos(planet, utc_ms)` → `{x, y, r, lon}`
- `InterplanetTime.body_distance_au(a, b, utc_ms)` → float
- `InterplanetTime.light_travel_seconds(from, to, utc_ms)` → float
- `InterplanetTime.format_light_time(seconds)` → string
- `InterplanetTime.find_meeting_windows(planet_a, planet_b, opts)` → list

Planet atoms: `:mercury :venus :earth :mars :jupiter :saturn :uranus :neptune :moon`

## Running tests

```
mix deps.get && mix test
```

## Fixture validation

```
mix run fixture_runner/fixture_runner.exs ../../c/planet-time/fixtures/reference.json
```

## License

MIT
