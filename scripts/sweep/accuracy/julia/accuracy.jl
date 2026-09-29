# Accuracy harness for julia/planet-time (see ../gen-cases-group2.js).
# Run from julia/planet-time:
#   julia --project=. ../../scripts/sweep/accuracy/julia/accuracy.jl ../../scripts/sweep/accuracy/instants-group2.txt
using InterplanetTime
using Printf

const BODIES = [("mercury", MERCURY), ("venus", VENUS), ("earth", EARTH), ("mars", MARS),
                ("jupiter", JUPITER), ("saturn", SATURN), ("uranus", URANUS),
                ("neptune", NEPTUNE), ("moon", MOON)]
b(v) = v ? 1 : 0

for raw in eachline(ARGS[1])
    line = strip(raw)
    isempty(line) && continue
    ms = parse(Int64, line)
    for (name, body) in BODIES
        pt = get_planet_time(body, ms)
        lt = light_travel_seconds(body, EARTH, ms)
        @printf("%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%.6f\n", ms, name, pt.hour, pt.minute,
                pt.second, pt.day_number, pt.day_in_year, pt.year_number, pt.period_in_week,
                b(pt.is_work_period), b(pt.is_work_hour), lt)
    end
    m = get_mtc(ms)
    @printf("%d\tmtc\t%d\t%d\t%d\t%d\n", ms, m.sol, m.hour, m.minute, m.second)
end
