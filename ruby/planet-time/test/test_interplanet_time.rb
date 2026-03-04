# frozen_string_literal: true

require 'minitest/autorun'
require 'interplanet_time'

REF_MS = InterplanetTime::Constants::J2000_MS

# ── 1. Constants ─────────────────────────────────────────────────────────────

class TestConstants < Minitest::Test
  def test_j2000_ms
    assert_equal 946_728_000_000, InterplanetTime::Constants::J2000_MS
  end

  def test_mars_epoch_ms
    assert_equal(-524_069_761_536, InterplanetTime::Constants::MARS_EPOCH_MS)
  end

  def test_mars_sol_ms
    assert_equal 88_775_244, InterplanetTime::Constants::MARS_SOL_MS
  end

  def test_au_km
    assert_in_delta 149_597_870.7, InterplanetTime::Constants::AU_KM, 0.1
  end

  def test_au_seconds
    expected = 149_597_870.7 / 299_792.458
    assert_in_delta expected, InterplanetTime::Constants::AU_SECONDS, 0.1
  end

  def test_planets_count
    assert_equal 9, InterplanetTime::Constants::PLANETS.size
  end

  def test_orbital_elements_count
    assert_equal 9, InterplanetTime::Constants::ORBITAL_ELEMENTS.size
  end

  def test_leap_seconds_non_empty
    refute_empty InterplanetTime::Constants::LEAP_SECONDS
  end

  def test_leap_seconds_last_delta
    assert_equal 37, InterplanetTime::Constants::LEAP_SECONDS.last[1]
  end
end

# ── 2. JDE / JC ──────────────────────────────────────────────────────────────

class TestJdeJc < Minitest::Test
  def test_jde_at_j2000
    jde = InterplanetTime.jde(REF_MS)
    assert_in_delta 2_451_545.0, jde, 0.01
  end

  def test_jc_at_j2000
    jc = InterplanetTime.jc(REF_MS)
    assert_in_delta 0.0, jc, 0.01
  end

  def test_jde_increases
    a = InterplanetTime.jde(REF_MS)
    b = InterplanetTime.jde(REF_MS + 86_400_000)
    assert b > a
  end

  def test_jc_after_century
    hundred_years = (100 * 365.25 * 86_400_000).to_i
    jc = InterplanetTime.jc(REF_MS + hundred_years)
    assert_in_delta 1.0, jc, 0.01
  end
end

# ── 3. TAI-UTC ────────────────────────────────────────────────────────────────

class TestTaiMinusUtc < Minitest::Test
  def test_at_j2000
    assert_equal 32, InterplanetTime.tai_minus_utc(REF_MS)
  end

  def test_after_last_leap_second
    assert_equal 37, InterplanetTime.tai_minus_utc(1_483_228_800_001)
  end

  def test_before_first_leap_second
    assert_equal 10, InterplanetTime.tai_minus_utc(0)
  end
end

# ── 4. MTC ───────────────────────────────────────────────────────────────────

class TestMTC < Minitest::Test
  def test_mtc_at_j2000
    mtc = InterplanetTime.get_mtc(REF_MS)
    assert_operator mtc.hour, :>=, 0
    assert_operator mtc.hour, :<, 24
    assert_operator mtc.minute, :>=, 0
    assert_operator mtc.minute, :<, 60
  end

  def test_mtc_str_format
    mtc = InterplanetTime.get_mtc(REF_MS)
    assert_match(/\A\d{2}:\d{2}\z/, mtc.mtc_str)
  end

  def test_mtc_sol_at_mars_epoch
    mtc = InterplanetTime.get_mtc(InterplanetTime::Constants::MARS_EPOCH_MS)
    assert_equal 0, mtc.sol
  end

  def test_mtc_sol_non_negative
    mtc = InterplanetTime.get_mtc(REF_MS)
    assert_operator mtc.sol, :>=, 0
  end
end

# ── 5. Light travel ───────────────────────────────────────────────────────────

class TestLightTravel < Minitest::Test
  def test_earth_mars_at_j2000
    lt = InterplanetTime.light_travel_seconds('earth', 'mars', REF_MS)
    assert_operator lt, :>, 100.0
    assert_operator lt, :<, 2000.0
  end

  def test_earth_mars_opposition_aug_2003
    lt = InterplanetTime.light_travel_seconds('earth', 'mars', 1_061_942_400_000)
    assert_in_delta 185.0, lt, 30.0
  end

  def test_earth_jupiter
    lt = InterplanetTime.light_travel_seconds('earth', 'jupiter', REF_MS)
    assert_operator lt, :>, 1000.0
    assert_operator lt, :<, 5000.0
  end

  def test_symmetric
    ab = InterplanetTime.light_travel_seconds('earth', 'mars', REF_MS)
    ba = InterplanetTime.light_travel_seconds('mars', 'earth', REF_MS)
    assert_in_delta ab, ba, 0.001
  end

  def test_format_186_seconds
    assert_equal '3 min 6 s', InterplanetTime.format_light_time(186)
  end

  def test_format_seconds_only
    assert_equal '45 s', InterplanetTime.format_light_time(45)
  end

  def test_format_hours
    assert_equal '1 h 1 min 40 s', InterplanetTime.format_light_time(3700)
  end

  def test_format_zero
    assert_equal '0 s', InterplanetTime.format_light_time(0)
  end

  def test_format_one_minute
    assert_equal '1 min', InterplanetTime.format_light_time(60)
  end
end

# ── 6. getPlanetTime ─────────────────────────────────────────────────────────

class TestPlanetTime < Minitest::Test
  def assert_valid_time(planet)
    pt = InterplanetTime.get_planet_time(planet, REF_MS)
    assert_operator pt.hour, :>=, 0
    assert_operator pt.hour, :<, 24
    assert_operator pt.minute, :>=, 0
    assert_operator pt.minute, :<, 60
    assert_operator pt.second, :>=, 0
    assert_operator pt.second, :<, 60
    assert_match(/\A\d{2}:\d{2}\z/, pt.time_str)
    assert_match(/\A\d{2}:\d{2}:\d{2}\z/, pt.time_str_full)
  end

  %w[mercury venus earth mars jupiter saturn uranus neptune moon].each do |p|
    define_method("test_#{p}") { assert_valid_time(p) }
  end

  def test_tz_offset_shifts_hour
    base   = InterplanetTime.get_planet_time('mars', REF_MS, 0.0)
    offset = InterplanetTime.get_planet_time('mars', REF_MS, 2.0)
    diff   = (offset.hour * 60 + offset.minute) - (base.hour * 60 + base.minute)
    diff -= 24 * 60 if diff > 23 * 60
    diff += 24 * 60 if diff < -23 * 60
    assert_in_delta 120.0, diff.to_f, 1.0
  end

  def test_mars_has_sol_in_year
    pt = InterplanetTime.get_planet_time('mars', REF_MS)
    refute_nil pt.sol_in_year
    assert_equal 669, pt.sols_per_year
  end

  def test_earth_no_sol_in_year
    pt = InterplanetTime.get_planet_time('earth', REF_MS)
    assert_nil pt.sol_in_year
    assert_nil pt.sols_per_year
  end

  def test_day_fraction_in_range
    pt = InterplanetTime.get_planet_time('mars', REF_MS)
    assert_operator pt.day_fraction, :>=, 0.0
    assert_operator pt.day_fraction, :<, 1.0
  end

  def test_earth_epoch_hour_is_zero
    pt = InterplanetTime.get_planet_time('earth', REF_MS)
    assert_equal 0, pt.hour
  end
end

# ── 7. Work-hour logic ────────────────────────────────────────────────────────

class TestWorkHours < Minitest::Test
  def test_work_hour_at_nine
    ms = REF_MS + 9 * 3_600_000
    pt = InterplanetTime.get_planet_time('earth', ms)
    assert_operator pt.hour, :>=, 9
    assert_operator pt.hour, :<, 17
    assert pt.is_work_hour
  end

  def test_rest_hour_at_midnight
    pt = InterplanetTime.get_planet_time('earth', REF_MS)
    assert_equal 0, pt.hour
    refute pt.is_work_hour
  end

  def test_rest_hour_at_twenty_three
    ms = REF_MS + 23 * 3_600_000
    pt = InterplanetTime.get_planet_time('earth', ms)
    assert_equal 23, pt.hour
    refute pt.is_work_hour
  end
end

# ── 8. Line of sight ─────────────────────────────────────────────────────────

class TestLineOfSight < Minitest::Test
  def test_earth_mars_at_j2000
    los = InterplanetTime.check_line_of_sight('earth', 'mars', REF_MS)
    assert [true, false].include?(los.clear)
    assert_operator los.elong_deg, :>, 0.0
  end

  def test_near_superior_conjunction_2021
    # 2021-10-08: Mars near superior conjunction
    los = InterplanetTime.check_line_of_sight('earth', 'mars', 1_633_651_200_000)
    refute los.clear
  end

  def test_near_opposition_2020
    # 2020-10-13: Mars opposition — clear path
    los = InterplanetTime.check_line_of_sight('earth', 'mars', 1_602_547_200_000)
    assert los.clear
  end

  def test_closest_sun_au_present
    los = InterplanetTime.check_line_of_sight('earth', 'jupiter', REF_MS)
    refute_nil los.closest_sun_au
  end
end

# ── 9. Heliocentric position ─────────────────────────────────────────────────

class TestHelioPos < Minitest::Test
  def test_earth_distance_near_one_au
    pos = InterplanetTime.helio_pos('earth', REF_MS)
    assert_in_delta 1.0, pos.r, 0.05
  end

  def test_mars_distance_in_range
    pos = InterplanetTime.helio_pos('mars', REF_MS)
    assert_operator pos.r, :>, 1.3
    assert_operator pos.r, :<, 1.7
  end

  def test_xy_consistent_with_r
    pos = InterplanetTime.helio_pos('earth', REF_MS)
    r   = Math.sqrt(pos.x**2 + pos.y**2)
    assert_in_delta pos.r, r, 0.001
  end
end

# ── 10. Meeting windows ───────────────────────────────────────────────────────

class TestMeetingWindows < Minitest::Test
  def test_earth_earth_always_overlaps
    windows = InterplanetTime.find_meeting_windows('earth', 'earth', REF_MS, earth_days: 1)
    refute_empty windows
  end

  def test_windows_have_positive_duration
    windows = InterplanetTime.find_meeting_windows('earth', 'mars', REF_MS, earth_days: 7)
    windows.each do |w|
      assert_operator w.duration_minutes, :>, 0
      assert_operator w.end_ms, :>, w.start_ms
    end
  end

  def test_windows_return_meeting_window_structs
    windows = InterplanetTime.find_meeting_windows('earth', 'mars', REF_MS, earth_days: 3)
    windows.each do |w|
      assert_instance_of InterplanetTime::MeetingWindow, w
    end
  end
end

# ── 11. Formatting ────────────────────────────────────────────────────────────

class TestFormatting < Minitest::Test
  def test_format_planet_time_iso
    result = InterplanetTime.format_planet_time_iso('mars', 14, 30, 0)
    assert_includes result, '14:30:00'
    assert_includes result, 'mars'
  end
end
