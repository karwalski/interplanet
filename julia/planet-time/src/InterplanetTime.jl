"""
    InterplanetTime

Julia port of planet-time.js — Interplanetary Time Library v1.1.0.

Provides time, calendar, work-schedule, orbital mechanics, and light-speed
calculations for every planet in the solar system.
"""
module InterplanetTime

using Printf

export Planet, PlanetTime, MtcResult, HelioPos, MeetingWindow
export get_planet_time, get_mtc, light_travel_seconds, body_distance_au,
       helio_pos, format_light_time, find_meeting_windows, planet_from_string,
       tai_minus_utc, jde, jc, kepler_e
export J2000_MS, MARS_EPOCH_MS, MARS_SOL_MS, EARTH_DAY_MS, J2000_JD,
       AU_KM, C_KMS, AU_SECONDS
export MERCURY, VENUS, EARTH, MARS, JUPITER, SATURN, URANUS, NEPTUNE, MOON
export LEAP_SECONDS, ORB_ELEMS, PLANET_TABLE

# ── Planet enum ────────────────────────────────────────────────────────────────

@enum Planet begin
    MERCURY = 0
    VENUS   = 1
    EARTH   = 2
    MARS    = 3
    JUPITER = 4
    SATURN  = 5
    URANUS  = 6
    NEPTUNE = 7
    MOON    = 8
end

"""Convert a string to a Planet enum value (case-insensitive)."""
function planet_from_string(s::AbstractString)::Planet
    d = Dict(
        "mercury" => MERCURY,
        "venus"   => VENUS,
        "earth"   => EARTH,
        "mars"    => MARS,
        "jupiter" => JUPITER,
        "saturn"  => SATURN,
        "uranus"  => URANUS,
        "neptune" => NEPTUNE,
        "moon"    => MOON,
    )
    key = lowercase(strip(s))
    if haskey(d, key)
        return d[key]
    else
        error("Unknown planet: $s")
    end
end

# ── Constants ──────────────────────────────────────────────────────────────────

"""J2000.0 epoch as Unix timestamp (ms): Date.UTC(2000,0,1,12,0,0)"""
const J2000_MS = Int64(946_728_000_000)

"""Julian Day number of J2000.0"""
const J2000_JD = 2_451_545.0

"""Earth solar day in milliseconds"""
const EARTH_DAY_MS = Int64(86_400_000)

"""1 AU in kilometres (IAU 2012)"""
const AU_KM = 149_597_870.7

"""Speed of light in km/s"""
const C_KMS = 299_792.458

"""Light travel time for 1 AU in seconds (~499.004 s)"""
const AU_SECONDS = AU_KM / C_KMS

"""Mars MY0 epoch: Date.UTC(1953,4,24,9,3,58,464) — May 24 1953 (Clancy/Piqueux)"""
const MARS_EPOCH_MS = Int64(-524_069_761_536)

"""Mars solar day (sol) in milliseconds: 24h 39m 35.244s (Allison & McEwen 2000)"""
const MARS_SOL_MS = Int64(88_775_244)

# ── IERS leap seconds ─────────────────────────────────────────────────────────
# Each entry: (utc_ms, tai_minus_utc)
# 28 entries — last: 2017-01-01 (current as of 2025)

const LEAP_SECONDS = Tuple{Int64,Int32}[
    (Int64(63_072_000_000),   Int32(10)),
    (Int64(78_796_800_000),   Int32(11)),
    (Int64(94_694_400_000),   Int32(12)),
    (Int64(126_230_400_000),  Int32(13)),
    (Int64(157_766_400_000),  Int32(14)),
    (Int64(189_302_400_000),  Int32(15)),
    (Int64(220_924_800_000),  Int32(16)),
    (Int64(252_460_800_000),  Int32(17)),
    (Int64(283_996_800_000),  Int32(18)),
    (Int64(315_532_800_000),  Int32(19)),
    (Int64(362_793_600_000),  Int32(20)),
    (Int64(394_329_600_000),  Int32(21)),
    (Int64(425_865_600_000),  Int32(22)),
    (Int64(489_024_000_000),  Int32(23)),
    (Int64(567_993_600_000),  Int32(24)),
    (Int64(631_152_000_000),  Int32(25)),
    (Int64(662_688_000_000),  Int32(26)),
    (Int64(709_948_800_000),  Int32(27)),
    (Int64(741_484_800_000),  Int32(28)),
    (Int64(773_020_800_000),  Int32(29)),
    (Int64(820_454_400_000),  Int32(30)),
    (Int64(867_715_200_000),  Int32(31)),
    (Int64(915_148_800_000),  Int32(32)),
    (Int64(1_136_073_600_000),Int32(33)),
    (Int64(1_230_768_000_000),Int32(34)),
    (Int64(1_341_100_800_000),Int32(35)),
    (Int64(1_435_708_800_000),Int32(36)),
    (Int64(1_483_228_800_000),Int32(37)),
]

# ── Orbital elements ──────────────────────────────────────────────────────────
# Keplerian elements at J2000.0 (Meeus Table 31.a)
# Fields: (a, e0, om0_deg, l0_deg, dL_deg_per_century)
# om0 and l0 stored in degrees here; converted to radians in helio_pos

struct OrbElem
    a   ::Float64   # semi-major axis (AU)
    e0  ::Float64   # eccentricity at J2000
    om0 ::Float64   # longitude of perihelion (degrees)
    l0  ::Float64   # mean longitude at J2000 (degrees)
    dL  ::Float64   # mean motion (degrees/Julian century)
end

# Indexed by Int(planet)+1 (1-indexed, planets 0-8)
# Index 9 = MOON uses Earth orbital elements (index 3 = EARTH)
const ORB_ELEMS = OrbElem[
    # 1: MERCURY (index 0)
    OrbElem(0.38710, 0.20564,  77.4561, 252.2507, 149_474.0722),
    # 2: VENUS (index 1)
    OrbElem(0.72333, 0.00677, 131.5637, 181.9798,  58_519.2130),
    # 3: EARTH (index 2)
    OrbElem(1.00000, 0.01671, 102.9373, 100.4664,  36_000.7698),
    # 4: MARS (index 3)
    OrbElem(1.52366, 0.09341, 336.0600, 355.4330,  19_141.6964),
    # 5: JUPITER (index 4)
    OrbElem(5.20336, 0.04849,  14.3320,  34.3515,   3_036.3027),
    # 6: SATURN (index 5)
    OrbElem(9.53707, 0.05551,  93.0572,  50.0775,   1_223.5093),
    # 7: URANUS (index 6)
    OrbElem(19.19126, 0.04630, 173.0052, 314.0550,    429.8633),
    # 8: NEPTUNE (index 7)
    OrbElem(30.06900, 0.00899,  48.1234, 304.3480,    219.8997),
    # 9: MOON (index 8) — uses Earth's orbital elements
    OrbElem(1.00000, 0.01671, 102.9373, 100.4664,  36_000.7698),
]

# ── Planet data table ──────────────────────────────────────────────────────────

struct PlanetData
    solar_day_ms        ::Int64
    sidereal_yr_ms      ::Int64
    epoch_ms            ::Int64
    work_start          ::Int
    work_end            ::Int
    days_per_period     ::Float64
    periods_per_week    ::Int
    work_periods_per_week::Int
end

# Note: Moon uses Earth's solar day (tidally locked)
const PLANET_TABLE = PlanetData[
    # 1: MERCURY — Earth-clock scheduling
    PlanetData(round(Int64, 175.9408 * EARTH_DAY_MS), round(Int64, 87.9691 * EARTH_DAY_MS),
               J2000_MS, 9, 17, 1.0, 7, 5),
    # 2: VENUS — Earth-clock scheduling
    PlanetData(round(Int64, 116.7500 * EARTH_DAY_MS), round(Int64, 224.701 * EARTH_DAY_MS),
               J2000_MS, 9, 17, 1.0, 7, 5),
    # 3: EARTH
    PlanetData(EARTH_DAY_MS, round(Int64, 365.25636 * EARTH_DAY_MS),
               J2000_MS, 9, 17, 1.0, 7, 5),
    # 4: MARS
    PlanetData(MARS_SOL_MS, round(Int64, 686.9957 * EARTH_DAY_MS),
               MARS_EPOCH_MS, 9, 17, 1.0, 7, 5),
    # 5: JUPITER
    PlanetData(round(Int64, 9.9250 * 3_600_000), round(Int64, 4332.589 * EARTH_DAY_MS),
               J2000_MS, 8, 16, 2.5, 7, 5),
    # 6: SATURN — Mankovich et al. 2023: 10.578 h
    PlanetData(Int64(38_080_800), round(Int64, 10_759.22 * EARTH_DAY_MS),
               J2000_MS, 8, 16, 2.25, 7, 5),
    # 7: URANUS
    PlanetData(round(Int64, 17.2479 * 3_600_000), round(Int64, 30_688.5 * EARTH_DAY_MS),
               J2000_MS, 8, 16, 1.0, 7, 5),
    # 8: NEPTUNE
    PlanetData(round(Int64, 16.1100 * 3_600_000), round(Int64, 60_195.0 * EARTH_DAY_MS),
               J2000_MS, 8, 16, 1.0, 7, 5),
    # 9: MOON (uses Earth's solar day)
    PlanetData(EARTH_DAY_MS, round(Int64, 365.25636 * EARTH_DAY_MS),
               J2000_MS, 9, 17, 1.0, 7, 5),
]

# ── Result structs ─────────────────────────────────────────────────────────────

"""Planet time result."""
struct PlanetTime
    hour            ::Int
    minute          ::Int
    second          ::Int
    local_hour      ::Float64
    day_fraction    ::Float64
    day_number      ::Int64
    day_in_year     ::Int64
    year_number     ::Int64
    period_in_week  ::Int
    is_work_period  ::Bool
    is_work_hour    ::Bool
    time_str        ::String   # "HH:MM"
    time_str_full   ::String   # "HH:MM:SS"
    sol_in_year     ::Union{Int64,Nothing}
    sols_per_year   ::Union{Int64,Nothing}
    zone_id         ::Union{String,Nothing}
end

"""Mars Coordinated Time result."""
struct MtcResult
    sol     ::Int64
    hour    ::Int
    minute  ::Int
    second  ::Int
    mtc_str ::String   # "HH:MM"
end

"""Heliocentric position (ecliptic plane)."""
struct HelioPos
    x   ::Float64   # AU
    y   ::Float64   # AU
    r   ::Float64   # distance (AU)
    lon ::Float64   # ecliptic longitude (radians)
end

"""A meeting window where both parties have isWorkHour=true."""
struct MeetingWindow
    start_ms        ::Int64
    end_ms          ::Int64
    duration_min    ::Int
end

# ── Orbital mechanics ──────────────────────────────────────────────────────────

"""Return TAI-UTC leap second offset for the given UTC milliseconds."""
function tai_minus_utc(utc_ms::Int64)::Int
    offset = 10
    for (t_ms, delta) in LEAP_SECONDS
        if utc_ms >= t_ms
            offset = Int(delta)
        else
            break
        end
    end
    return offset
end

"""
    jde(utc_ms) -> Float64

Return the Julian Ephemeris Day (TT) for the given UTC milliseconds.
TT = UTC + (TAI-UTC) + 32.184 s
"""
function jde(utc_ms::Int64)::Float64
    tai = tai_minus_utc(utc_ms)
    tt_ms = Float64(utc_ms) + Float64(tai) * 1000.0 + 32_184.0
    return 2_440_587.5 + tt_ms / 86_400_000.0
end

"""Return Julian centuries since J2000.0 (TT)."""
function jc(utc_ms::Int64)::Float64
    return (jde(utc_ms) - J2000_JD) / 36_525.0
end

"""
    kepler_e(M, e) -> Float64

Solve Kepler's equation M = E − e·sin(E) via Newton-Raphson.
Tolerance: 1e-12, maximum 50 iterations.
"""
function kepler_e(M::Float64, e::Float64)::Float64
    E = M
    for _ in 1:50
        dE = (M - E + e * sin(E)) / (1.0 - e * cos(E))
        E += dE
        abs(dE) < 1e-12 && break
    end
    return E
end

"""
    helio_pos(planet, utc_ms) -> HelioPos

Compute heliocentric ecliptic position of a planet at utc_ms.
Moon maps to Earth's orbital elements.
"""
function helio_pos(planet::Planet, utc_ms::Int64)::HelioPos
    idx = Int(planet) + 1   # Julia is 1-indexed; Moon = index 9
    oe = ORB_ELEMS[idx]

    T = jc(utc_ms)
    D2R = π / 180.0
    TAU = 2.0 * π

    L   = mod(oe.l0 + oe.dL * T, 360.0)
    om  = oe.om0 * D2R
    M   = mod((L - oe.om0 + 360.0), 360.0) * D2R
    e   = oe.e0
    a   = oe.a

    E   = kepler_e(M, e)
    nu  = 2.0 * atan(sqrt(1.0 + e) * sin(E / 2.0),
                     sqrt(1.0 - e) * cos(E / 2.0))
    r   = a * (1.0 - e * cos(E))
    lon = mod(om + nu + TAU, TAU)

    return HelioPos(r * cos(lon), r * sin(lon), r, lon)
end

"""
    body_distance_au(a, b, utc_ms) -> Float64

Return the distance in AU between two solar system bodies.
"""
function body_distance_au(a::Planet, b::Planet, utc_ms::Int64)::Float64
    pa = helio_pos(a, utc_ms)
    pb = helio_pos(b, utc_ms)
    dx = pa.x - pb.x
    dy = pa.y - pb.y
    return sqrt(dx^2 + dy^2)
end

"""
    light_travel_seconds(from_planet, to_planet, utc_ms) -> Float64

Return one-way light travel time between two bodies in seconds.
"""
function light_travel_seconds(from_planet::Planet, to_planet::Planet, utc_ms::Int64)::Float64
    return body_distance_au(from_planet, to_planet, utc_ms) * AU_SECONDS
end

# ── Zone prefix map ────────────────────────────────────────────────────────────

const ZONE_PREFIXES = Dict{Planet,String}(
    MERCURY => "MMT",
    VENUS   => "VMT",
    MARS    => "AMT",
    JUPITER => "JMT",
    SATURN  => "SMT",
    URANUS  => "UMT",
    NEPTUNE => "NMT",
    MOON    => "LMT",
)

# ── Planet time calculation ────────────────────────────────────────────────────

"""
    get_planet_time(planet, utc_ms, tz_offset_h=0.0) -> PlanetTime

Return the local time on a planet at the given UTC milliseconds.
`tz_offset_h` is the optional zone offset in local hours from the planet's prime meridian.
Moon uses Earth's solar day (tidally locked; work schedules run on Earth time).
"""
function get_planet_time(planet::Planet, utc_ms::Int64, tz_offset_h::Float64=0.0)::PlanetTime
    # PLANET_TABLE is indexed 1-based: planet index 0 → table row 1, ..., MOON (8) → row 9
    # PLANET_TABLE[MOON+1] already stores Earth's solar day (same values), so no remapping needed
    pd = PLANET_TABLE[Int(planet) + 1]

    solar_day = Float64(pd.solar_day_ms)

    # tz offset applied as a fraction of one solar day (same as JS)
    elapsed_ms   = Float64(utc_ms - pd.epoch_ms) + tz_offset_h / 24.0 * solar_day
    total_days   = elapsed_ms / solar_day
    day_number   = Int64(floor(total_days))
    day_frac     = total_days - Float64(day_number)

    local_hour = day_frac * 24.0
    h  = Int(floor(local_hour))
    mf = (local_hour - Float64(h)) * 60.0
    m  = Int(floor(mf))
    s  = Int(floor((mf - Float64(m)) * 60.0))

    # Work period — Mercury/Venus use Earth-clock scheduling (UTC day-of-week + UTC hour)
    earth_clock = (planet == MERCURY || planet == VENUS)
    piw::Int = 0
    is_work_period::Bool = false
    is_work_hour::Bool = false
    if earth_clock
        # dow = ((floor(utc_ms / 86400000) % 7) + 3) % 7, Mon=0..Sun=6
        # fld gives floor division (correct for negative values)
        utc_day = fld(utc_ms, Int64(86_400_000))
        dow = mod(mod(utc_day, 7) + 3, 7)
        is_work_period = dow < pd.work_periods_per_week
        ms_of_day = utc_ms - utc_day * Int64(86_400_000)
        utc_h = Int(div(ms_of_day, Int64(3_600_000)))
        is_work_hour = is_work_period && utc_h >= pd.work_start && utc_h < pd.work_end
        piw = Int(dow)
    else
        total_periods = total_days / pd.days_per_period
        piw = ((Int(floor(total_periods)) % pd.periods_per_week) + pd.periods_per_week) % pd.periods_per_week
        is_work_period = piw < pd.work_periods_per_week
        is_work_hour   = is_work_period && local_hour >= Float64(pd.work_start) && local_hour < Float64(pd.work_end)
    end

    # Year / day-in-year
    year_len_days = Float64(pd.sidereal_yr_ms) / solar_day
    year_number   = Int64(floor(total_days / year_len_days))
    day_in_year   = Int64(floor(total_days - Float64(year_number) * year_len_days))

    sol_in_year  = nothing
    sols_per_year = nothing
    if planet == MARS
        sol_in_year  = day_in_year
        sols_per_year = Int64(round(Float64(pd.sidereal_yr_ms) / solar_day))
    end

    zone_id::Union{String,Nothing} = nothing
    if haskey(ZONE_PREFIXES, planet)
        prefix = ZONE_PREFIXES[planet]
        n = Int(floor(tz_offset_h))
        zone_id = n >= 0 ? "$(prefix)+$(n)" : "$(prefix)-$(abs(n))"
    end

    time_str      = @sprintf("%02d:%02d", h, m)
    time_str_full = @sprintf("%02d:%02d:%02d", h, m, s)

    return PlanetTime(
        h, m, s,
        local_hour, day_frac,
        day_number, day_in_year, year_number,
        piw, is_work_period, is_work_hour,
        time_str, time_str_full,
        sol_in_year, sols_per_year,
        zone_id,
    )
end

"""
    get_mtc(utc_ms) -> MtcResult

Return Mars Coordinated Time (MTC) for the given UTC milliseconds.
"""
function get_mtc(utc_ms::Int64)::MtcResult
    ms       = Float64(utc_ms - MARS_EPOCH_MS)
    sol_f    = ms / Float64(MARS_SOL_MS)
    sol      = Int64(floor(sol_f))
    frac     = sol_f - Float64(sol)

    total_sec = frac * Float64(MARS_SOL_MS) / 1000.0
    h  = Int(floor(total_sec / 3600.0))
    mf = mod(total_sec, 3600.0) / 60.0
    m  = Int(floor(mf))
    sc = Int(floor(mod(total_sec, 60.0)))

    mtc_str = @sprintf("%02d:%02d", h, m)
    return MtcResult(sol, h, m, sc, mtc_str)
end

# ── Formatting ─────────────────────────────────────────────────────────────────

"""
    format_light_time(seconds) -> String

Format a light travel time (seconds) as a human-readable string.
"""
function format_light_time(seconds::Float64)::String
    if seconds < 0.001
        return "<1ms"
    elseif seconds < 1.0
        return "$(round(Int, seconds * 1000))ms"
    elseif seconds < 60.0
        return "$(round(seconds; digits=1))s"
    elseif seconds < 3600.0
        return "$(round(seconds / 60.0; digits=1))min"
    else
        h = floor(Int, seconds / 3600.0)
        m = round(Int, mod(seconds, 3600.0) / 60.0)
        return "$(h)h $(m)m"
    end
end

# ── Scheduling ─────────────────────────────────────────────────────────────────

"""
    find_meeting_windows(a, b, from_ms; earth_days=30, step_min=15) -> Vector{MeetingWindow}

Find overlapping work windows between two planets over N Earth days.
Scans in `step_min`-minute steps; both parties must have `is_work_hour=true`.
"""
function find_meeting_windows(
        a::Planet, b::Planet, from_ms::Int64;
        earth_days::Int=30, step_min::Int=15)::Vector{MeetingWindow}
    step_ms = Int64(step_min * 60_000)
    to_ms   = from_ms + Int64(earth_days) * EARTH_DAY_MS
    windows = MeetingWindow[]
    in_window    = false
    window_start = Int64(0)

    t = from_ms
    while t < to_ms
        ta = get_planet_time(a, t)
        tb = get_planet_time(b, t)
        overlap = ta.is_work_hour && tb.is_work_hour
        if overlap && !in_window
            in_window    = true
            window_start = t
        elseif !overlap && in_window
            in_window = false
            dur = Int((t - window_start) ÷ 60_000)
            push!(windows, MeetingWindow(window_start, t, dur))
        end
        t += step_ms
    end
    if in_window
        dur = Int((to_ms - window_start) ÷ 60_000)
        push!(windows, MeetingWindow(window_start, to_ms, dur))
    end
    return windows
end

end  # module InterplanetTime
