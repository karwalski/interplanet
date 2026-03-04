"""
runtests.jl — Unit tests for InterplanetTime.jl

100+ assertions covering constants, orbital mechanics, planet time,
MTC, work schedules, formatting, and edge cases.
"""

using Test
using InterplanetTime

@testset "InterplanetTime" begin

# ────────────────────────────────────────────────────────────────
@testset "Constants" begin
    @test J2000_MS == 946_728_000_000
    @test MARS_EPOCH_MS == -524_069_761_536
    @test MARS_SOL_MS == 88_775_244
    @test EARTH_DAY_MS == 86_400_000
    @test J2000_JD == 2_451_545.0
    @test AU_KM ≈ 149_597_870.7 atol=0.001
    @test C_KMS ≈ 299_792.458 atol=0.001
    @test AU_SECONDS ≈ 499.0 atol=1.0
    @test AU_SECONDS ≈ AU_KM / C_KMS atol=1e-6
    @test J2000_MS > 0
    @test MARS_EPOCH_MS < 0
end

# ────────────────────────────────────────────────────────────────
@testset "Planet enum" begin
    @test Int(MERCURY) == 0
    @test Int(VENUS)   == 1
    @test Int(EARTH)   == 2
    @test Int(MARS)    == 3
    @test Int(JUPITER) == 4
    @test Int(SATURN)  == 5
    @test Int(URANUS)  == 6
    @test Int(NEPTUNE) == 7
    @test Int(MOON)    == 8
    # 9 planets total
    @test length(instances(Planet)) == 9
end

# ────────────────────────────────────────────────────────────────
@testset "planet_from_string" begin
    @test planet_from_string("mercury") == MERCURY
    @test planet_from_string("venus")   == VENUS
    @test planet_from_string("earth")   == EARTH
    @test planet_from_string("mars")    == MARS
    @test planet_from_string("jupiter") == JUPITER
    @test planet_from_string("saturn")  == SATURN
    @test planet_from_string("uranus")  == URANUS
    @test planet_from_string("neptune") == NEPTUNE
    @test planet_from_string("moon")    == MOON
    # Case-insensitive
    @test planet_from_string("MARS")    == MARS
    @test planet_from_string("Earth")   == EARTH
    @test planet_from_string("MOON")    == MOON
    @test planet_from_string("Jupiter") == JUPITER
    # Unknown planet raises error
    @test_throws ErrorException planet_from_string("pluto")
    @test_throws ErrorException planet_from_string("")
end

# ────────────────────────────────────────────────────────────────
@testset "Leap seconds (tai_minus_utc)" begin
    # Before first leap second (before 1972-01-01): offset = 10
    @test tai_minus_utc(Int64(0)) == 10
    # At first leap second (1972-01-01): offset = 10
    @test tai_minus_utc(Int64(63_072_000_000)) == 10
    # After first entry: offset = 10
    @test tai_minus_utc(Int64(63_072_000_001)) == 10
    # After 1972-07-01: offset = 11
    @test tai_minus_utc(Int64(78_796_800_001)) == 11
    # Current (after 2017-01-01): 37
    @test tai_minus_utc(Int64(1_483_228_800_001)) == 37
    # At J2000: should be 32
    @test tai_minus_utc(J2000_MS) == 32
end

# ────────────────────────────────────────────────────────────────
@testset "JDE at J2000" begin
    jd = jde(J2000_MS)
    # Should return ≈ 2451545.0 (J2000.0)
    @test jd ≈ 2_451_545.0 atol=0.01
    # Must be greater than J2000_JD (TT > UTC at J2000 due to leap seconds)
    @test jd >= J2000_JD
end

@testset "Julian centuries" begin
    # At J2000: T = 0.0
    @test jc(J2000_MS) ≈ 0.0 atol=1e-4
    # One Julian century = 36525 days later
    t_plus_century = J2000_MS + Int64(36_525) * EARTH_DAY_MS
    @test jc(t_plus_century) ≈ 1.0 atol=0.01
end

# ────────────────────────────────────────────────────────────────
@testset "Kepler equation" begin
    # M=0 → E=0
    @test kepler_e(0.0, 0.0) ≈ 0.0 atol=1e-12
    # Circular orbit (e=0): E=M
    for m in [0.1, 0.5, 1.0, 2.0, 3.0]
        @test kepler_e(m, 0.0) ≈ m atol=1e-10
    end
    # Check M = E - e*sin(E) identity
    for (m_val, e_val) in [(0.3, 0.2), (1.5, 0.09), (2.0, 0.05)]
        E = kepler_e(m_val, e_val)
        @test abs(m_val - (E - e_val * sin(E))) < 1e-11
    end
end

# ────────────────────────────────────────────────────────────────
@testset "helio_pos — basic sanity" begin
    # Earth at J2000: r ≈ 0.983 AU (near perihelion in January)
    pos = helio_pos(EARTH, J2000_MS)
    @test pos.r ≈ 1.0 atol=0.03
    @test pos.r > 0.9 && pos.r < 1.1

    # Mars: semi-major axis = 1.524 AU
    mars_pos = helio_pos(MARS, J2000_MS)
    @test mars_pos.r > 1.0 && mars_pos.r < 1.7

    # Moon uses Earth orbital elements
    moon_pos = helio_pos(MOON, J2000_MS)
    @test moon_pos.r ≈ pos.r atol=0.001

    # All planets: r > 0
    for p in instances(Planet)
        hp = helio_pos(p, J2000_MS)
        @test hp.r > 0.0
    end
end

# ────────────────────────────────────────────────────────────────
@testset "body_distance_au" begin
    # Distance from Earth to itself = 0
    d_self = body_distance_au(EARTH, EARTH, J2000_MS)
    @test d_self ≈ 0.0 atol=1e-10

    # Earth-Mars distance: between 0.37 and 2.67 AU
    d = body_distance_au(EARTH, MARS, J2000_MS)
    @test d > 0.3 && d < 2.8

    # Earth-Jupiter: between ~4.2 and 6.2 AU
    dj = body_distance_au(EARTH, JUPITER, J2000_MS)
    @test dj > 3.9 && dj < 6.4

    # Symmetric
    @test body_distance_au(EARTH, MARS, J2000_MS) ≈ body_distance_au(MARS, EARTH, J2000_MS) atol=1e-10
end

# ────────────────────────────────────────────────────────────────
@testset "light_travel_seconds — known events" begin
    # Earth-Mars at close approach Aug 2003 (~0.37 AU → ~184 s)
    lt_2003 = light_travel_seconds(EARTH, MARS, Int64(1_061_977_860_000))
    @test abs(lt_2003 - 186.0) < 15

    # Earth-Mars farther apart in 2020 (~0.41 AU)
    lt_2020 = light_travel_seconds(EARTH, MARS, Int64(1_602_631_560_000))
    @test abs(lt_2020 - 207.0) < 20

    # Earth-Jupiter Oct 2023 (~5.65 AU → ~2820 s but varies)
    lt_jup = light_travel_seconds(EARTH, JUPITER, Int64(1_698_969_600_000))
    @test abs(lt_jup - 2010.0) < 300

    # Light time > 0
    @test light_travel_seconds(EARTH, SATURN, J2000_MS) > 0.0
    @test light_travel_seconds(EARTH, NEPTUNE, J2000_MS) > 0.0

    # Outer planets take longer
    @test light_travel_seconds(EARTH, SATURN, J2000_MS) > light_travel_seconds(EARTH, MARS, J2000_MS)
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — all planets at J2000" begin
    for p in instances(Planet)
        pt = get_planet_time(p, J2000_MS)
        @test pt.hour   in 0:23
        @test pt.minute in 0:59
        @test pt.second in 0:59
        @test pt.local_hour >= 0.0 && pt.local_hour < 24.0
        @test pt.day_fraction >= 0.0 && pt.day_fraction < 1.0
        @test length(pt.time_str)      == 5   # "HH:MM"
        @test length(pt.time_str_full) == 8   # "HH:MM:SS"
        @test pt.time_str[3] == ':'
        @test pt.time_str_full[3] == ':'
        @test pt.time_str_full[6] == ':'
    end
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — Mars sol fields" begin
    pt = get_planet_time(MARS, J2000_MS)
    @test pt.sol_in_year !== nothing
    @test pt.sols_per_year !== nothing
    @test pt.sol_in_year >= 0
    @test pt.sols_per_year > 0
    # Mars year ≈ 668 sols
    @test pt.sols_per_year ≈ 669 atol=5
end

@testset "get_planet_time — non-Mars no sol fields" begin
    for p in [MERCURY, VENUS, EARTH, JUPITER, SATURN, URANUS, NEPTUNE, MOON]
        pt = get_planet_time(p, J2000_MS)
        @test pt.sol_in_year  === nothing
        @test pt.sols_per_year === nothing
    end
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — work schedule" begin
    # Work period: first 5 of 7 periods are work
    for p in instances(Planet)
        pt = get_planet_time(p, J2000_MS)
        @test pt.period_in_week in 0:6
        if pt.period_in_week < 5
            @test pt.is_work_period == true
        else
            @test pt.is_work_period == false
        end
    end

    # isWorkHour requires isWorkPeriod AND within work hours
    pt_earth = get_planet_time(EARTH, J2000_MS)
    if pt_earth.is_work_period
        if pt_earth.local_hour >= 9.0 && pt_earth.local_hour < 17.0
            @test pt_earth.is_work_hour == true
        else
            @test pt_earth.is_work_hour == false
        end
    else
        @test pt_earth.is_work_hour == false
    end
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — tz offset" begin
    # tz_offset_h shifts the local time
    pt0  = get_planet_time(MARS, J2000_MS, 0.0)
    pt_p1 = get_planet_time(MARS, J2000_MS, 1.0)
    pt_m1 = get_planet_time(MARS, J2000_MS, -1.0)

    # Local hour should differ by approximately 1 hour
    diff_fwd = mod(pt_p1.local_hour - pt0.local_hour + 24.0, 24.0)
    diff_bwd = mod(pt0.local_hour - pt_m1.local_hour + 24.0, 24.0)
    @test diff_fwd ≈ 1.0 atol=0.01
    @test diff_bwd ≈ 1.0 atol=0.01
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — day fractions" begin
    # day_fraction + dayNumber = totalDays
    for p in [EARTH, MARS, JUPITER]
        pt = get_planet_time(p, J2000_MS)
        @test pt.day_fraction >= 0.0
        @test pt.day_fraction < 1.0
        # local_hour = day_fraction * 24
        @test pt.local_hour ≈ pt.day_fraction * 24.0 atol=1e-6
    end
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — year number" begin
    # At J2000 we are several years after each planet epoch
    for p in instances(Planet)
        pt = get_planet_time(p, J2000_MS)
        @test pt.year_number >= 0  # always non-negative (J2000 is epoch)
    end

    # Far future: year number should increase
    future_ms = J2000_MS + Int64(10) * Int64(365) * EARTH_DAY_MS
    for p in [EARTH, MARS]
        pt_now   = get_planet_time(p, J2000_MS)
        pt_future = get_planet_time(p, future_ms)
        @test pt_future.year_number >= pt_now.year_number
    end
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — Moon uses Earth day" begin
    pt_moon  = get_planet_time(MOON, J2000_MS)
    pt_earth = get_planet_time(EARTH, J2000_MS)
    # Moon time should match Earth time exactly (same solar day / epoch)
    @test pt_moon.hour   == pt_earth.hour
    @test pt_moon.minute == pt_earth.minute
    @test pt_moon.second == pt_earth.second
    @test pt_moon.day_fraction ≈ pt_earth.day_fraction atol=1e-10
end

# ────────────────────────────────────────────────────────────────
@testset "get_planet_time — multiple timestamps" begin
    # 6 key timestamps used in fixture
    timestamps = [
        Int64(946_728_000_000),   # J2000 (2000-01-01)
        Int64(1_000_000_000_000), # 2001-09-09
        Int64(1_200_000_000_000), # 2008-01-10
        Int64(1_400_000_000_000), # 2014-05-14
        Int64(1_600_000_000_000), # 2020-09-13
        Int64(1_700_000_000_000), # 2023-11-15
    ]
    for ts in timestamps
        for p in instances(Planet)
            pt = get_planet_time(p, ts)
            @test pt.hour   in 0:23
            @test pt.minute in 0:59
            @test pt.second in 0:59
        end
    end
end

# ────────────────────────────────────────────────────────────────
@testset "get_mtc — basic" begin
    # At Mars epoch: sol=0
    mtc_epoch = get_mtc(MARS_EPOCH_MS)
    @test mtc_epoch.sol == 0
    @test mtc_epoch.hour   in 0:23
    @test mtc_epoch.minute in 0:59

    # At J2000: sol should be very large positive number
    mtc_j2000 = get_mtc(J2000_MS)
    @test mtc_j2000.sol > 0
    @test mtc_j2000.hour   in 0:23
    @test mtc_j2000.minute in 0:59
    @test mtc_j2000.second in 0:59
    # Hour should be ~15 at J2000 (validated against reference)
    @test abs(mtc_j2000.hour - 15) <= 3

    # mtc_str format "HH:MM"
    @test length(mtc_j2000.mtc_str) == 5
    @test mtc_j2000.mtc_str[3] == ':'
end

@testset "get_mtc — sol counting" begin
    # One sol later: sol increments by 1
    mtc_0 = get_mtc(MARS_EPOCH_MS)
    mtc_1 = get_mtc(MARS_EPOCH_MS + MARS_SOL_MS)
    @test mtc_1.sol == mtc_0.sol + 1

    # Half-sol difference: same sol, hour ≈ 12
    mtc_half = get_mtc(MARS_EPOCH_MS + MARS_SOL_MS ÷ 2)
    @test mtc_half.sol == 0
    @test abs(mtc_half.hour - 12) <= 1
end

# ────────────────────────────────────────────────────────────────
@testset "format_light_time" begin
    # Sub-millisecond
    @test format_light_time(0.0) == "<1ms"
    @test format_light_time(0.0005) == "<1ms"

    # Milliseconds
    @test format_light_time(0.5) == "500ms"
    @test format_light_time(0.001) == "1ms"

    # Seconds
    @test contains(format_light_time(30.0), "s")
    @test contains(format_light_time(59.9), "s")

    # Minutes
    @test contains(format_light_time(61.0), "min")
    @test contains(format_light_time(600.0), "min")

    # Hours
    @test contains(format_light_time(3600.0), "h")
    @test contains(format_light_time(7200.0), "h")
    @test format_light_time(3600.0) == "1h 0m"
    @test format_light_time(7320.0) == "2h 2m"

    # Light time for known Earth-Mars 2003 close approach
    lt_s = light_travel_seconds(EARTH, MARS, Int64(1_061_977_860_000))
    fmtd = format_light_time(lt_s)
    @test contains(fmtd, "min") || contains(fmtd, "s")

    # Neptune light time is multi-hour
    lt_nep = light_travel_seconds(EARTH, NEPTUNE, J2000_MS)
    @test contains(format_light_time(lt_nep), "h")
end

# ────────────────────────────────────────────────────────────────
@testset "find_meeting_windows" begin
    # Should return a vector (possibly empty)
    windows = find_meeting_windows(EARTH, MARS, J2000_MS; earth_days=7, step_min=15)
    @test isa(windows, Vector{MeetingWindow})

    # All windows: start < end, duration > 0
    for w in windows
        @test w.start_ms < w.end_ms
        @test w.duration_min > 0
        # Duration should match start/end
        expected_dur = Int((w.end_ms - w.start_ms) ÷ 60_000)
        @test w.duration_min == expected_dur
    end

    # With Earth-Earth: should have many work windows
    windows_ee = find_meeting_windows(EARTH, EARTH, J2000_MS; earth_days=7, step_min=15)
    @test length(windows_ee) > 0

    # 30-day window should have >= as many as 7-day
    windows_30 = find_meeting_windows(EARTH, MARS, J2000_MS; earth_days=30, step_min=15)
    @test length(windows_30) >= length(windows)
end

# ────────────────────────────────────────────────────────────────
@testset "PLANET_TABLE — day lengths" begin
    # Mercury solar day ≈ 175.94 Earth days
    pd_merc = PLANET_TABLE[Int(MERCURY)+1]
    @test abs(pd_merc.solar_day_ms - round(Int64, 175.9408 * EARTH_DAY_MS)) <= 1

    # Earth day = exactly 86400000 ms
    pd_earth = PLANET_TABLE[Int(EARTH)+1]
    @test pd_earth.solar_day_ms == EARTH_DAY_MS

    # Mars sol = exactly 88775244 ms
    pd_mars = PLANET_TABLE[Int(MARS)+1]
    @test pd_mars.solar_day_ms == MARS_SOL_MS

    # Mars epoch
    @test pd_mars.epoch_ms == MARS_EPOCH_MS

    # Jupiter day < Saturn day (≈9.9h vs ≈10.6h)
    pd_jup = PLANET_TABLE[Int(JUPITER)+1]
    pd_sat = PLANET_TABLE[Int(SATURN)+1]
    @test pd_jup.solar_day_ms < pd_sat.solar_day_ms

    # Moon uses Earth's day
    pd_moon = PLANET_TABLE[Int(MOON)+1]
    @test pd_moon.solar_day_ms == EARTH_DAY_MS
end

# ────────────────────────────────────────────────────────────────
@testset "ORB_ELEMS — orbital elements" begin
    # Earth semi-major axis = 1.0 AU
    @test ORB_ELEMS[Int(EARTH)+1].a ≈ 1.0 atol=0.001

    # Mars semi-major axis ≈ 1.524 AU
    @test ORB_ELEMS[Int(MARS)+1].a ≈ 1.52366 atol=0.001

    # Jupiter semi-major axis ≈ 5.203 AU
    @test ORB_ELEMS[Int(JUPITER)+1].a ≈ 5.20336 atol=0.001

    # Neptune: a ≈ 30.07 AU
    @test ORB_ELEMS[Int(NEPTUNE)+1].a ≈ 30.069 atol=0.1

    # Moon has same elements as Earth
    @test ORB_ELEMS[Int(MOON)+1].a ≈ ORB_ELEMS[Int(EARTH)+1].a atol=1e-10
    @test ORB_ELEMS[Int(MOON)+1].e0 ≈ ORB_ELEMS[Int(EARTH)+1].e0 atol=1e-10

    # Eccentricities in valid range [0, 1)
    for i in 1:9
        @test ORB_ELEMS[i].e0 >= 0.0 && ORB_ELEMS[i].e0 < 1.0
    end
end

# ────────────────────────────────────────────────────────────────
@testset "LEAP_SECONDS table" begin
    @test length(LEAP_SECONDS) == 28
    # First entry: 1972-01-01 UTC = 63072000000 ms, TAI-UTC = 10
    @test LEAP_SECONDS[1][1] == Int64(63_072_000_000)
    @test LEAP_SECONDS[1][2] == Int32(10)
    # Last entry: 2017-01-01, TAI-UTC = 37
    @test LEAP_SECONDS[28][2] == Int32(37)
    # Entries are sorted (ascending utc_ms)
    for i in 2:28
        @test LEAP_SECONDS[i][1] > LEAP_SECONDS[i-1][1]
    end
    # TAI-UTC is non-decreasing
    for i in 2:28
        @test LEAP_SECONDS[i][2] >= LEAP_SECONDS[i-1][2]
    end
end

# ────────────────────────────────────────────────────────────────
@testset "helio_pos — x, y, r, lon fields" begin
    pos = helio_pos(EARTH, J2000_MS)
    # r = sqrt(x^2 + y^2)
    @test pos.r ≈ sqrt(pos.x^2 + pos.y^2) atol=1e-10
    # lon = atan(y, x) modulo 2π
    expected_lon = mod(atan(pos.y, pos.x) + 2π, 2π)
    lon_diff = min(abs(pos.lon - expected_lon), abs(pos.lon - expected_lon - 2π), abs(pos.lon - expected_lon + 2π))
    @test lon_diff < 1e-4
end

# ────────────────────────────────────────────────────────────────
@testset "Edge cases — negative timestamps (pre-epoch)" begin
    # Mars epoch is 1953; timestamps before J2000 are negative
    pre_j2000 = J2000_MS - Int64(5) * Int64(365) * EARTH_DAY_MS  # ~1995
    pt = get_planet_time(MARS, pre_j2000)
    @test pt.hour   in 0:23
    @test pt.minute in 0:59
    @test pt.second in 0:59
    @test pt.period_in_week in 0:6
end

@testset "Edge cases — very large timestamps" begin
    # Year 2100
    future_ms = Int64(4_102_444_800_000)
    for p in [EARTH, MARS, JUPITER]
        pt = get_planet_time(p, future_ms)
        @test pt.hour   in 0:23
        @test pt.minute in 0:59
    end
end

end  # @testset "InterplanetTime"
