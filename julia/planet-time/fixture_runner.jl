#!/usr/bin/env julia
"""
fixture_runner.jl — Standalone cross-language fixture validator.

Reads reference.json (54 entries × 9 planets × 6 timestamps) and
validates hour, minute, and light-travel-seconds against InterplanetTime.jl.

Usage:
    julia --project=. fixture_runner.jl [path/to/reference.json]

Exit code: 0 if all assertions pass, 1 if any fail.
"""

# Add this package's src to LOAD_PATH so `using InterplanetTime` works
# without Pkg.instantiate (useful for CI environments without internet access)
push!(LOAD_PATH, joinpath(@__DIR__, "src"))

using Printf

# Load JSON support
try
    using JSON3
catch
    # Fall back to JSON if JSON3 isn't available
    try
        using JSON
        _use_json3 = false
    catch e
        println("ERROR: Neither JSON3 nor JSON package is available.")
        println("Run: julia --project=. -e 'import Pkg; Pkg.instantiate()'")
        exit(1)
    end
end

using InterplanetTime

# ── Determine fixture path ─────────────────────────────────────────────────────

fixture_path = length(ARGS) > 0 ? ARGS[1] :
    joinpath(@__DIR__, "..", "..", "c", "planet-time", "fixtures", "reference.json")

if !isfile(fixture_path)
    println("SKIP: fixture file not found at $fixture_path")
    println("0 passed  0 failed  (fixtures skipped)")
    exit(0)
end

# ── Parse fixture ──────────────────────────────────────────────────────────────

raw = read(fixture_path, String)

# Parse with whichever JSON library loaded
entries = nothing
try
    _data = JSON3.read(raw)
    global entries = _data[:entries]
catch
    # JSON3 not available; try with JSON module (different API)
    _data = JSON.parse(raw)
    global entries = _data["entries"]
end

# ── Validate entries ───────────────────────────────────────────────────────────

function run_fixtures(entries)
passed = 0
failed = 0

for entry in entries
    # Support both JSON3 (symbol keys) and JSON (string keys)
    if isa(entry, AbstractDict)
        # JSON module: string keys
        planet_str  = String(get(entry, "planet",       entry["planet"]))
        utc_ms_raw  = get(entry, "utc_ms",      entry["utc_ms"])
        exp_hour    = get(entry, "hour",         entry["hour"])
        exp_minute  = get(entry, "minute",       entry["minute"])
        lt_s_raw    = get(entry, "light_travel_s", nothing)
    else
        # JSON3: symbol keys
        planet_str  = String(entry[:planet])
        utc_ms_raw  = entry[:utc_ms]
        exp_hour    = entry[:hour]
        exp_minute  = entry[:minute]
        lt_s_raw    = get(entry, :light_travel_s, nothing)
    end

    utc_ms = Int64(utc_ms_raw)
    planet = planet_from_string(planet_str)
    tag    = "$(planet_str)@$(utc_ms)"

    # ── Hour check ─────────────────────────────────────────────────────────────
    pt = get_planet_time(planet, utc_ms)
    if pt.hour == Int(exp_hour)
        passed += 1
    else
        failed += 1
        println("FAIL: $tag  hour=$(exp_hour) (got $(pt.hour))")
    end

    # ── Minute check ───────────────────────────────────────────────────────────
    if pt.minute == Int(exp_minute)
        passed += 1
    else
        failed += 1
        println("FAIL: $tag  minute=$(exp_minute) (got $(pt.minute))")
    end

    # ── Light travel check (Earth→planet, skip earth and moon) ─────────────────
    if lt_s_raw !== nothing && !isnothing(lt_s_raw)
        lt_s = Float64(lt_s_raw)
        if lt_s > 0.0 && planet_str ∉ ["earth", "moon"]
            lt_computed = light_travel_seconds(EARTH, planet, utc_ms)
            if abs(lt_computed - lt_s) <= 2.0
                passed += 1
            else
                failed += 1
                @printf("FAIL: %s  light_travel_s=%.3f (got %.3f)\n", tag, lt_s, lt_computed)
            end
        end
    end
end

# ── Summary ────────────────────────────────────────────────────────────────────

println("Fixture entries checked: $(length(entries))")
println("$passed passed  $failed failed")
return failed
end  # run_fixtures

exit(run_fixtures(entries) > 0 ? 1 : 0)
