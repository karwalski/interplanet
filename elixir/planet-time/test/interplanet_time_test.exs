defmodule InterplanetTimeTest do
  use ExUnit.Case, async: true

  alias InterplanetTime
  alias InterplanetTime.Constants
  alias InterplanetTime.Orbital

  # Reference timestamps (UTC ms)
  @j2000      946_728_000_000
  @mars_2003 1_061_977_860_000
  @jup_2023  1_698_969_600_000
  @y2025     1_735_689_600_000

  # ── Constants ─────────────────────────────────────────────────────────────

  describe "Constants" do
    test "j2000_ms" do
      assert Constants.j2000_ms() == 946_728_000_000
    end

    test "mars_epoch_ms" do
      assert Constants.mars_epoch_ms() == -524_069_761_536
    end

    test "mars_sol_ms" do
      assert Constants.mars_sol_ms() == 88_775_244
    end

    test "au_km" do
      assert_in_delta Constants.au_km(), 149_597_870.7, 0.1
    end

    test "c_kms" do
      assert_in_delta Constants.c_kms(), 299_792.458, 0.001
    end

    test "au_seconds ~ 499" do
      assert_in_delta Constants.au_seconds(), 499.004, 0.01
    end

    test "earth_day_ms" do
      assert Constants.earth_day_ms() == 86_400_000
    end

    test "leap_secs has 28 entries" do
      assert length(Constants.leap_secs()) == 28
    end

    test "first leap second delta is 10" do
      {delta, _} = hd(Constants.leap_secs())
      assert delta == 10
    end

    test "last leap second delta is 37" do
      {delta, _} = List.last(Constants.leap_secs())
      assert delta == 37
    end

    test "orb_elems has 9 entries" do
      assert map_size(Constants.orb_elems()) == 9
    end

    test "moon orbital elements match earth L0" do
      assert Constants.orb_elems(:moon).l0 == Constants.orb_elems(:earth).l0
    end

    test "mars a ~ 1.52 AU" do
      assert_in_delta Constants.orb_elems(:mars).a, 1.52366, 0.0001
    end

    test "planet_data has 9 entries" do
      assert map_size(Constants.planet_data()) == 9
    end

    test "Jupiter days_per_period = 2.5" do
      assert Constants.planet_data(:jupiter).days_per_period == 2.5
    end

    test "Saturn days_per_period = 2.25" do
      assert Constants.planet_data(:saturn).days_per_period == 2.25
    end
  end

  # ── tai_minus_utc ─────────────────────────────────────────────────────────

  describe "tai_minus_utc" do
    test "before 1972 returns 10" do
      assert Orbital.tai_minus_utc(0) == 10
    end

    test "at j2000 returns 32" do
      assert Orbital.tai_minus_utc(@j2000) == 32
    end

    test "after 2017 returns 37" do
      assert Orbital.tai_minus_utc(@y2025) == 37
    end
  end

  # ── jde / jc ─────────────────────────────────────────────────────────────

  describe "jde and jc" do
    test "jde at J2000 ~ 2451545" do
      assert_in_delta Orbital.jde(@j2000), 2_451_545.0, 0.01
    end

    test "jc at J2000 ~ 0.0" do
      assert abs(Orbital.jc(@j2000)) < 0.0001
    end

    test "jc is monotonically increasing" do
      assert Orbital.jc(@y2025) > Orbital.jc(@j2000)
    end
  end

  # ── kepler_e ──────────────────────────────────────────────────────────────

  describe "kepler_e" do
    test "e=0 returns M" do
      assert_in_delta Orbital.kepler_e(1.2, 0.0), 1.2, 1.0e-10
    end

    test "converges for Mars eccentricity" do
      e_val = Orbital.kepler_e(1.0, 0.09341)
      assert is_float(e_val)
      assert e_val > 0.9 and e_val < 1.2
    end
  end

  # ── helio_pos ────────────────────────────────────────────────────────────

  describe "helio_pos" do
    test "Earth r ~ 1 AU at J2000" do
      {_, _, r, _} = Orbital.helio_pos(:earth, @j2000)
      assert_in_delta r, 1.0, 0.03
    end

    test "Mars r ~ 1.52 AU mean" do
      {_, _, r, _} = Orbital.helio_pos(:mars, @j2000)
      assert_in_delta r, 1.52, 0.15
    end

    test "Moon uses Earth orbit (same r)" do
      {_, _, r_moon, _} = Orbital.helio_pos(:moon, @j2000)
      {_, _, r_earth, _} = Orbital.helio_pos(:earth, @j2000)
      assert_in_delta r_moon, r_earth, 1.0e-10
    end

    test "Jupiter r ~ 5.2 AU" do
      {_, _, r, _} = Orbital.helio_pos(:jupiter, @j2000)
      assert_in_delta r, 5.2, 0.3
    end

    test "Neptune r ~ 30 AU" do
      {_, _, r, _} = Orbital.helio_pos(:neptune, @j2000)
      assert_in_delta r, 30.0, 1.0
    end
  end

  # ── body_distance_au ──────────────────────────────────────────────────────

  describe "body_distance_au" do
    test "Earth to Earth = 0" do
      d = InterplanetTime.body_distance_au(:earth, :earth, @j2000)
      assert_in_delta d, 0.0, 1.0e-10
    end

    test "Earth-Mars in valid range" do
      d = InterplanetTime.body_distance_au(:earth, :mars, @j2000)
      assert d > 0.3 and d < 2.7
    end

    test "Earth-Neptune > 28 AU" do
      d = InterplanetTime.body_distance_au(:earth, :neptune, @j2000)
      assert d > 28.0
    end

    test "symmetry: A->B == B->A" do
      ab = InterplanetTime.body_distance_au(:earth, :mars, @mars_2003)
      ba = InterplanetTime.body_distance_au(:mars, :earth, @mars_2003)
      assert_in_delta ab, ba, 1.0e-10
    end
  end

  # ── light_travel_seconds ──────────────────────────────────────────────────

  describe "light_travel_seconds" do
    test "Earth to Earth = 0" do
      lt = InterplanetTime.light_travel_seconds(:earth, :earth, @j2000)
      assert_in_delta lt, 0.0, 1.0e-6
    end

    test "Earth-Mars close approach 2003 < 250 s" do
      lt = InterplanetTime.light_travel_seconds(:earth, :mars, @mars_2003)
      assert lt < 250.0
    end

    test "Earth-Jupiter > 2000 s at j2000" do
      lt = InterplanetTime.light_travel_seconds(:earth, :jupiter, @j2000)
      assert lt > 2000.0
    end

    test "Earth-Neptune > 14000 s" do
      lt = InterplanetTime.light_travel_seconds(:earth, :neptune, @j2000)
      assert lt > 14_000.0
    end

    test "Earth-Mercury > 0" do
      lt = InterplanetTime.light_travel_seconds(:earth, :mercury, @j2000)
      assert lt > 0.0
    end
  end

  # ── format_light_time ─────────────────────────────────────────────────────

  describe "format_light_time" do
    test "<1ms for near-zero" do
      assert InterplanetTime.format_light_time(0.0) == "<1ms"
    end

    test "ms format" do
      assert InterplanetTime.format_light_time(0.5) == "500ms"
    end

    test "seconds format" do
      assert InterplanetTime.format_light_time(30.0) == "30.0s"
    end

    test "minutes format" do
      assert InterplanetTime.format_light_time(150.0) == "2.5min"
    end

    test "hours format contains h" do
      s = InterplanetTime.format_light_time(4000.0)
      assert String.contains?(s, "h")
      assert String.contains?(s, "m")
    end
  end

  # ── get_mtc ───────────────────────────────────────────────────────────────

  describe "get_mtc" do
    test "at Mars epoch sol=0" do
      mtc = InterplanetTime.get_mtc(Constants.mars_epoch_ms())
      assert mtc.sol == 0
      assert mtc.hour == 0
      assert mtc.minute == 0
    end

    test "sol increases by 1 over one Mars sol" do
      a = InterplanetTime.get_mtc(@j2000)
      b = InterplanetTime.get_mtc(@j2000 + Constants.mars_sol_ms())
      assert b.sol - a.sol == 1
    end

    test "hour in range 0-23" do
      mtc = InterplanetTime.get_mtc(@y2025)
      assert mtc.hour >= 0 and mtc.hour < 24
    end

    test "minute in range 0-59" do
      mtc = InterplanetTime.get_mtc(@y2025)
      assert mtc.minute >= 0 and mtc.minute < 60
    end

    test "second in range 0-59" do
      mtc = InterplanetTime.get_mtc(@y2025)
      assert mtc.second >= 0 and mtc.second < 60
    end

    test "mtc_str matches HH:MM pattern" do
      mtc = InterplanetTime.get_mtc(@y2025)
      assert Regex.match?(~r/^\d{2}:\d{2}$/, mtc.mtc_str)
    end
  end

  # ── get_planet_time ───────────────────────────────────────────────────────

  describe "get_planet_time — Earth" do
    test "hour in range 0-23" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert pt.hour >= 0 and pt.hour < 24
    end

    test "minute in range 0-59" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert pt.minute >= 0 and pt.minute < 60
    end

    test "second in range 0-59" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert pt.second >= 0 and pt.second < 60
    end

    test "time_str matches HH:MM" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert Regex.match?(~r/^\d{2}:\d{2}$/, pt.time_str)
    end

    test "time_str_full matches HH:MM:SS" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert Regex.match?(~r/^\d{2}:\d{2}:\d{2}$/, pt.time_str_full)
    end

    test "sol_in_year is nil for Earth" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert is_nil(pt.sol_in_year)
    end

    test "sols_per_year is nil for Earth" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert is_nil(pt.sols_per_year)
    end

    test "day_fraction in 0.0-1.0" do
      pt = InterplanetTime.get_planet_time(:earth, @j2000)
      assert pt.day_fraction >= 0.0 and pt.day_fraction < 1.0
    end

    test "local_hour = day_fraction * 24" do
      pt = InterplanetTime.get_planet_time(:earth, @y2025)
      assert_in_delta pt.local_hour, pt.day_fraction * 24.0, 1.0e-10
    end
  end

  describe "get_planet_time — Mars" do
    test "sol_in_year not nil" do
      pt = InterplanetTime.get_planet_time(:mars, @j2000)
      assert not is_nil(pt.sol_in_year)
    end

    test "sols_per_year ~ 669" do
      pt = InterplanetTime.get_planet_time(:mars, @j2000)
      assert abs(pt.sols_per_year - 669) <= 2
    end

    test "sol_in_year in 0-669" do
      pt = InterplanetTime.get_planet_time(:mars, @j2000)
      assert pt.sol_in_year >= 0 and pt.sol_in_year < 670
    end

    test "period_in_week in 0-6" do
      pt = InterplanetTime.get_planet_time(:mars, @j2000)
      assert pt.period_in_week >= 0 and pt.period_in_week < 7
    end
  end

  describe "get_planet_time — Moon" do
    test "Moon matches Earth time (same solar day)" do
      moon  = InterplanetTime.get_planet_time(:moon, @j2000)
      earth = InterplanetTime.get_planet_time(:earth, @j2000)
      assert moon.hour   == earth.hour
      assert moon.minute == earth.minute
    end

    test "Moon sol_in_year is nil" do
      pt = InterplanetTime.get_planet_time(:moon, @j2000)
      assert is_nil(pt.sol_in_year)
    end
  end

  describe "get_planet_time — tz_offset_h" do
    test "positive offset increases hour" do
      base   = InterplanetTime.get_planet_time(:earth, @j2000)
      offset = InterplanetTime.get_planet_time(:earth, @j2000, 4.0)
      assert offset.hour == rem(base.hour + 4, 24)
    end

    test "negative offset decreases hour" do
      base   = InterplanetTime.get_planet_time(:earth, @j2000)
      offset = InterplanetTime.get_planet_time(:earth, @j2000, -3.0)
      assert offset.hour == Integer.mod(base.hour - 3, 24)
    end
  end

  describe "get_planet_time — all planets smoke test" do
    for planet <- [:mercury, :venus, :earth, :mars, :jupiter, :saturn, :uranus, :neptune, :moon] do
      test "#{planet} returns valid result" do
        pt = InterplanetTime.get_planet_time(unquote(planet), @y2025)
        assert pt.hour >= 0 and pt.hour < 24
        assert pt.minute >= 0 and pt.minute < 60
        assert String.length(pt.time_str) == 5
      end
    end
  end

  # ── find_meeting_windows ──────────────────────────────────────────────────

  describe "find_meeting_windows" do
    test "returns a list" do
      w = InterplanetTime.find_meeting_windows(:earth, :earth, start_ms: @j2000)
      assert is_list(w)
    end

    test "Earth-Earth produces windows" do
      w = InterplanetTime.find_meeting_windows(:earth, :earth, earth_days: 7, start_ms: @j2000)
      assert length(w) > 0
    end

    test "window start_ms < end_ms" do
      w = InterplanetTime.find_meeting_windows(:earth, :mars, earth_days: 14, start_ms: @j2000)
      for win <- w do
        assert win.start_ms < win.end_ms
      end
    end

    test "window duration_min > 0" do
      w = InterplanetTime.find_meeting_windows(:earth, :mars, earth_days: 14, start_ms: @j2000)
      for win <- w do
        assert win.duration_min > 0
      end
    end
  end
end
