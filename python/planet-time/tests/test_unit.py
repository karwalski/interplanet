"""
test_unit.py — Unit tests for interplanet_time Python library.
12 sections, ≥200 assertions. stdlib unittest only.
"""

import math
import unittest

import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parents[1] / 'src'))

from interplanet_time import (
    Planet,
    get_planet_time, get_mtc, get_mars_time_at_offset,
    helio_pos, body_distance_au, light_travel_seconds,
    check_line_of_sight, lower_quartile_light_time,
    find_meeting_windows,
    PlanetTimezone, PlanetDateTime,
    format_light_time, format_planet_time_iso,
    MeetingWindow,
)
from interplanet_time._constants import (
    J2000_MS, J2000_JD, MARS_EPOCH_MS, MARS_SOL_MS,
    EARTH_DAY_MS, AU_KM, C_KMS, AU_SECONDS, LEAP_SECS, PLANETS,
)
from interplanet_time._orbital import _jde, _jc, _kepler_E, _tai_minus_utc

# Reference timestamps
J2000       = 946728000000    # 2000-01-01T12:00:00Z
MARS_2003   = 1061977860000   # 2003-08-27 — Mars closest approach
MARS_2020   = 1602631560000   # 2020-10-13 — Mars opposition
JUP_2023    = 1698969600000   # 2023-11-03 — Jupiter opposition
START_2025  = 1735689600000   # 2025-01-01T00:00:00Z
MID_2024    = 1718452800000   # 2024-06-15T12:00:00Z


# ── 1. Constants ───────────────────────────────────────────────────────────────

class TestConstants(unittest.TestCase):

    def test_j2000_jd(self):
        self.assertAlmostEqual(J2000_JD, 2451545.0, places=6)

    def test_j2000_ms(self):
        self.assertEqual(J2000_MS, 946728000000)

    def test_mars_epoch_ms(self):
        self.assertEqual(MARS_EPOCH_MS, -524069761536)

    def test_mars_sol_ms(self):
        self.assertEqual(MARS_SOL_MS, 88775244)

    def test_earth_day_ms(self):
        self.assertEqual(EARTH_DAY_MS, 86400000)

    def test_au_km(self):
        self.assertAlmostEqual(AU_KM, 149597870.7, places=1)

    def test_c_kms(self):
        self.assertAlmostEqual(C_KMS, 299792.458, places=3)

    def test_au_seconds(self):
        self.assertAlmostEqual(AU_SECONDS, 499.004, delta=0.001)

    def test_leap_secs_count(self):
        self.assertEqual(len(LEAP_SECS), 28)

    def test_leap_secs_first(self):
        tai, ms = LEAP_SECS[0]
        self.assertEqual(tai, 10)
        # 1972-01-01T00:00:00Z
        self.assertEqual(ms, 63072000000)

    def test_leap_secs_last(self):
        tai, _ = LEAP_SECS[-1]
        self.assertEqual(tai, 37)

    def test_planet_enum_values(self):
        self.assertEqual(Planet.MERCURY, 0)
        self.assertEqual(Planet.VENUS,   1)
        self.assertEqual(Planet.EARTH,   2)
        self.assertEqual(Planet.MARS,    3)
        self.assertEqual(Planet.JUPITER, 4)
        self.assertEqual(Planet.SATURN,  5)
        self.assertEqual(Planet.URANUS,  6)
        self.assertEqual(Planet.NEPTUNE, 7)
        self.assertEqual(Planet.MOON,    8)

    def test_planets_dict_has_all(self):
        for p in Planet:
            self.assertIn(p, PLANETS)

    def test_mars_epoch_before_j2000(self):
        self.assertLess(MARS_EPOCH_MS, J2000_MS)

    def test_au_seconds_formula(self):
        self.assertAlmostEqual(AU_SECONDS, AU_KM / C_KMS, places=6)


# ── 2. JDE / Julian centuries ─────────────────────────────────────────────────

class TestJDE(unittest.TestCase):

    def test_jde_at_j2000(self):
        # At J2000, TT ≈ UTC + 63.184 s → JDE very close to 2451545.0
        jde = _jde(J2000_MS)
        self.assertAlmostEqual(jde, 2451545.0, delta=0.001)

    def test_jc_at_j2000(self):
        # Julian centuries at J2000 ≈ 0 (by definition)
        jc = _jc(J2000_MS)
        self.assertAlmostEqual(jc, 0.0, delta=0.001)

    def test_jde_unix_epoch(self):
        # Unix epoch 1970-01-01T00:00:00Z = JD 2440587.5
        jde = _jde(0)
        self.assertAlmostEqual(jde, 2440587.5, delta=0.001)

    def test_jde_increases(self):
        self.assertGreater(_jde(J2000_MS + 86400000), _jde(J2000_MS))

    def test_jc_2025(self):
        # 2025 is ~25.04 years after J2000 → jc ≈ 0.25
        jc = _jc(START_2025)
        self.assertAlmostEqual(jc, 0.25, delta=0.01)

    def test_tai_minus_utc_before_1972(self):
        # Before first entry → 10s
        self.assertEqual(_tai_minus_utc(0), 10)

    def test_tai_minus_utc_2017(self):
        # After 2017-01-01 → 37s
        self.assertEqual(_tai_minus_utc(START_2025), 37)

    def test_tai_minus_utc_1972(self):
        self.assertEqual(_tai_minus_utc(63072000000), 10)

    def test_tai_minus_utc_after_1999(self):
        # 1999-01-01 → 32s
        self.assertEqual(_tai_minus_utc(915148800000), 32)


# ── 3. MTC at J2000 ───────────────────────────────────────────────────────────

class TestMTC(unittest.TestCase):

    def test_mtc_j2000_hour(self):
        mtc = get_mtc(J2000_MS)
        self.assertEqual(mtc.hour, 15)

    def test_mtc_j2000_minute(self):
        mtc = get_mtc(J2000_MS)
        self.assertAlmostEqual(mtc.minute, 45, delta=3)

    def test_mtc_j2000_sol(self):
        mtc = get_mtc(J2000_MS)
        self.assertEqual(mtc.sol, 16567)

    def test_mtc_j2000_second(self):
        mtc = get_mtc(J2000_MS)
        self.assertEqual(mtc.second, 34)

    def test_mtc_str_format(self):
        mtc = get_mtc(J2000_MS)
        self.assertEqual(mtc.mtc_str, "15:45")

    def test_mtc_sol_increases(self):
        sol_now  = get_mtc(J2000_MS).sol
        sol_later = get_mtc(J2000_MS + MARS_SOL_MS).sol
        self.assertEqual(sol_later, sol_now + 1)

    def test_mtc_2003_sol(self):
        mtc = get_mtc(MARS_2003)
        self.assertEqual(mtc.sol, 17865)

    def test_mtc_2003_hour(self):
        mtc = get_mtc(MARS_2003)
        self.assertEqual(mtc.hour, 21)

    def test_mtc_2003_minute(self):
        mtc = get_mtc(MARS_2003)
        self.assertEqual(mtc.minute, 3)


# ── 4. Light travel Earth → Mars 2003-08-27 (closest approach) ───────────────

class TestLightTravelMars2003(unittest.TestCase):

    def test_lt_earth_mars_2003(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2003)
        self.assertAlmostEqual(lt, 185.2, delta=15)

    def test_lt_direction_symmetric(self):
        ltAB = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2003)
        ltBA = light_travel_seconds(Planet.MARS, Planet.EARTH, MARS_2003)
        self.assertAlmostEqual(ltAB, ltBA, delta=0.001)

    def test_body_distance_mars_2003(self):
        d = body_distance_au(Planet.EARTH, Planet.MARS, MARS_2003)
        # ~0.37 AU at closest approach
        self.assertAlmostEqual(d, 0.37, delta=0.05)

    def test_helio_r_earth_2003(self):
        hp = helio_pos(Planet.EARTH, MARS_2003)
        self.assertAlmostEqual(hp.r, 1.010, delta=0.01)

    def test_helio_r_mars_2003(self):
        hp = helio_pos(Planet.MARS, MARS_2003)
        self.assertAlmostEqual(hp.r, 1.381, delta=0.01)


# ── 5. Light travel Earth → Mars 2020-10-13 (opposition) ─────────────────────

class TestLightTravelMars2020(unittest.TestCase):

    def test_lt_earth_mars_2020(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2020)
        self.assertAlmostEqual(lt, 209.3, delta=15)

    def test_lt_greater_than_2003(self):
        lt_2020 = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2020)
        lt_2003 = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2003)
        self.assertGreater(lt_2020, lt_2003)

    def test_format_lt_mars_2020(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2020)
        s  = format_light_time(lt)
        self.assertIn("min", s)


# ── 6. Light travel Earth → Jupiter 2023-11-03 ───────────────────────────────

class TestLightTravelJupiter(unittest.TestCase):

    def test_lt_earth_jupiter_2023(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.JUPITER, JUP_2023)
        self.assertAlmostEqual(lt, 1987.3, delta=120)

    def test_format_lt_jupiter(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.JUPITER, JUP_2023)
        s  = format_light_time(lt)
        self.assertIn("min", s)

    def test_lt_uranus_large(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.URANUS, JUP_2023)
        self.assertGreater(lt, 9000)

    def test_lt_neptune_larger(self):
        lt_u = light_travel_seconds(Planet.EARTH, Planet.URANUS, JUP_2023)
        lt_n = light_travel_seconds(Planet.EARTH, Planet.NEPTUNE, JUP_2023)
        self.assertGreater(lt_n, lt_u)


# ── 7. get_planet_time — all 9 planets at 3 reference dates ──────────────────

class TestGetPlanetTime(unittest.TestCase):

    # --- J2000 ---

    def test_pt_mercury_j2000(self):
        pt = get_planet_time(Planet.MERCURY, J2000_MS)
        self.assertEqual(pt.hour, 0)
        self.assertEqual(pt.minute, 0)
        self.assertEqual(pt.day_number, 0)
        self.assertFalse(pt.is_work_hour)

    def test_pt_venus_j2000(self):
        pt = get_planet_time(Planet.VENUS, J2000_MS)
        self.assertEqual(pt.hour, 0)
        self.assertEqual(pt.day_number, 0)

    def test_pt_earth_j2000(self):
        pt = get_planet_time(Planet.EARTH, J2000_MS)
        self.assertEqual(pt.hour, 0)
        self.assertEqual(pt.day_number, 0)
        self.assertIsNone(pt.sol_in_year)
        self.assertIsNone(pt.sols_per_year)

    def test_pt_mars_j2000(self):
        pt = get_planet_time(Planet.MARS, J2000_MS)
        self.assertEqual(pt.hour, 15)
        self.assertEqual(pt.minute, 45)
        self.assertEqual(pt.second, 34)
        self.assertEqual(pt.day_number, 16567)
        self.assertEqual(pt.sol_in_year, 520)
        self.assertEqual(pt.sols_per_year, 669)
        self.assertFalse(pt.is_work_hour)

    def test_pt_jupiter_j2000(self):
        pt = get_planet_time(Planet.JUPITER, J2000_MS)
        self.assertEqual(pt.hour, 0)
        self.assertIsNone(pt.sol_in_year)

    def test_pt_saturn_j2000(self):
        pt = get_planet_time(Planet.SATURN, J2000_MS)
        self.assertEqual(pt.hour, 0)

    def test_pt_uranus_j2000(self):
        pt = get_planet_time(Planet.URANUS, J2000_MS)
        self.assertEqual(pt.hour, 0)

    def test_pt_neptune_j2000(self):
        pt = get_planet_time(Planet.NEPTUNE, J2000_MS)
        self.assertEqual(pt.hour, 0)

    def test_pt_moon_j2000(self):
        # Moon maps to Earth
        pt_moon  = get_planet_time(Planet.MOON, J2000_MS)
        pt_earth = get_planet_time(Planet.EARTH, J2000_MS)
        self.assertEqual(pt_moon.hour,       pt_earth.hour)
        self.assertEqual(pt_moon.day_number, pt_earth.day_number)
        self.assertIsNone(pt_moon.sol_in_year)

    # --- mars_close_2003 ---

    def test_pt_mercury_2003(self):
        pt = get_planet_time(Planet.MERCURY, MARS_2003)
        self.assertEqual(pt.hour, 13)
        self.assertEqual(pt.minute, 57)
        self.assertTrue(pt.is_work_hour)

    def test_pt_mars_2003(self):
        pt = get_planet_time(Planet.MARS, MARS_2003)
        self.assertEqual(pt.hour, 21)
        self.assertEqual(pt.minute, 3)
        self.assertEqual(pt.day_number, 17865)

    def test_pt_earth_2003(self):
        pt = get_planet_time(Planet.EARTH, MARS_2003)
        self.assertEqual(pt.hour, 21)
        self.assertEqual(pt.minute, 50)

    # --- 2025_start ---

    def test_pt_earth_2025(self):
        pt = get_planet_time(Planet.EARTH, START_2025)
        self.assertEqual(pt.hour, 12)
        self.assertEqual(pt.day_number, 9131)

    def test_pt_mars_2025(self):
        pt = get_planet_time(Planet.MARS, START_2025)
        self.assertEqual(pt.hour, 20)
        self.assertEqual(pt.sol_in_year, 47)

    def test_pt_jupiter_2025(self):
        pt = get_planet_time(Planet.JUPITER, START_2025)
        self.assertEqual(pt.hour, 5)

    def test_pt_saturn_2025(self):
        pt = get_planet_time(Planet.SATURN, START_2025)
        self.assertEqual(pt.hour, 2)  # Mankovich et al. 2023: 10.578 h/day

    def test_pt_neptune_2025(self):
        pt = get_planet_time(Planet.NEPTUNE, START_2025)
        self.assertEqual(pt.hour, 17)

    def test_pt_time_str(self):
        pt = get_planet_time(Planet.EARTH, J2000_MS)
        self.assertEqual(pt.time_str, "00:00")
        self.assertEqual(pt.time_str_full, "00:00:00")

    def test_pt_mars_time_str_2003(self):
        pt = get_planet_time(Planet.MARS, MARS_2003)
        self.assertEqual(pt.time_str, "21:03")

    def test_pt_tz_offset_mars(self):
        pt0 = get_planet_time(Planet.MARS, MARS_2003, tz_offset_h=0)
        pt3 = get_planet_time(Planet.MARS, MARS_2003, tz_offset_h=3)
        diff = (pt3.local_hour - pt0.local_hour) % 24
        self.assertAlmostEqual(diff, 3.0, delta=0.01)


# ── 8. Work hour logic ────────────────────────────────────────────────────────

class TestWorkHourLogic(unittest.TestCase):

    def test_earth_work_period_0_is_work(self):
        # Earth: periods 0-4 are work, 5-6 are rest
        pt = get_planet_time(Planet.EARTH, J2000_MS)
        self.assertEqual(pt.period_in_week, 0)
        self.assertTrue(pt.is_work_period)

    def test_earth_work_hour_9to17(self):
        # Add hours to reach 9:30 on day 0 from J2000
        p = PLANETS[Planet.EARTH]
        offset_ms = int(9.5 / 24 * p['solarDayMs'])
        pt = get_planet_time(Planet.EARTH, J2000_MS + offset_ms)
        self.assertTrue(pt.is_work_hour)

    def test_earth_off_hour_before_9(self):
        p = PLANETS[Planet.EARTH]
        offset_ms = int(8.5 / 24 * p['solarDayMs'])
        pt = get_planet_time(Planet.EARTH, J2000_MS + offset_ms)
        self.assertFalse(pt.is_work_hour)

    def test_earth_off_hour_after_17(self):
        p = PLANETS[Planet.EARTH]
        offset_ms = int(17.5 / 24 * p['solarDayMs'])
        pt = get_planet_time(Planet.EARTH, J2000_MS + offset_ms)
        self.assertFalse(pt.is_work_hour)

    def test_earth_rest_period(self):
        # Period 5 and 6 are rest days
        p = PLANETS[Planet.EARTH]
        offset_ms = int(5 * p['solarDayMs'])  # day 5 = period 5
        pt = get_planet_time(Planet.EARTH, J2000_MS + offset_ms)
        self.assertEqual(pt.period_in_week, 5)
        self.assertFalse(pt.is_work_period)
        self.assertFalse(pt.is_work_hour)

    def test_earth_rest_period_6(self):
        p = PLANETS[Planet.EARTH]
        offset_ms = int(6 * p['solarDayMs'])
        pt = get_planet_time(Planet.EARTH, J2000_MS + offset_ms)
        self.assertEqual(pt.period_in_week, 6)
        self.assertFalse(pt.is_work_period)

    def test_mercury_work_utc_09_17(self):
        # Mercury uses Earth-clock scheduling: UTC Mon–Fri 09:00–17:00
        # Jan 3, 2000 10:00 UTC is a Monday → work hour
        monday_10am_utc = 946893600000
        pt = get_planet_time(Planet.MERCURY, monday_10am_utc)
        self.assertTrue(pt.is_work_hour)

    def test_mercury_off_hours_utc(self):
        # Mercury: Mon Jan 3, 2000 17:30 UTC → after 17:00, not work hour
        monday_1730_utc = 946920600000
        pt = get_planet_time(Planet.MERCURY, monday_1730_utc)
        self.assertFalse(pt.is_work_hour)

    def test_jupiter_period_grouping(self):
        # Jupiter daysPerPeriod=2.5 — period changes every 2.5 Jupiter days
        pt = get_planet_time(Planet.JUPITER, J2000_MS)
        self.assertGreaterEqual(pt.period_in_week, 0)
        self.assertLess(pt.period_in_week, 7)

    def test_mars_work_hour_range(self):
        p = PLANETS[Planet.MARS]
        # At epoch, add 10 local hours (inside 9-17 window)
        offset_ms = 10 * PLANETS[Planet.MARS]['solarDayMs'] // 24
        pt = get_planet_time(Planet.MARS, MARS_EPOCH_MS + offset_ms)
        if pt.is_work_period:
            self.assertTrue(pt.is_work_hour)

    def test_period_in_week_range(self):
        for planet in Planet:
            pt = get_planet_time(planet, J2000_MS)
            self.assertGreaterEqual(pt.period_in_week, 0)
            self.assertLess(pt.period_in_week, 7)

    def test_is_work_period_bool(self):
        for planet in Planet:
            pt = get_planet_time(planet, J2000_MS)
            self.assertIsInstance(pt.is_work_period, bool)
            self.assertIsInstance(pt.is_work_hour, bool)


# ── 9. Line of sight ──────────────────────────────────────────────────────────

class TestLineOfSight(unittest.TestCase):

    def test_los_earth_mars_2003_clear(self):
        # Mars closest approach 2003 — should be near opposition → clear
        los = check_line_of_sight(Planet.EARTH, Planet.MARS, MARS_2003)
        self.assertIsInstance(los.clear, bool)
        self.assertFalse(los.blocked)

    def test_los_earth_mars_2020_clear(self):
        los = check_line_of_sight(Planet.EARTH, Planet.MARS, MARS_2020)
        self.assertFalse(los.blocked)

    def test_los_fields_present(self):
        los = check_line_of_sight(Planet.EARTH, Planet.MARS, J2000_MS)
        self.assertIsNotNone(los.elong_deg)
        self.assertIsInstance(los.clear, bool)
        self.assertIsInstance(los.blocked, bool)
        self.assertIsInstance(los.degraded, bool)

    def test_los_earth_moon_guard(self):
        # Earth and Moon share orbital position — guard returns clear
        los = check_line_of_sight(Planet.EARTH, Planet.MOON, J2000_MS)
        self.assertTrue(los.clear)
        self.assertFalse(los.blocked)
        self.assertIsNone(los.closest_sun_au)

    def test_los_clear_blocked_exclusive(self):
        los = check_line_of_sight(Planet.EARTH, Planet.JUPITER, J2000_MS)
        self.assertFalse(los.clear and los.blocked)

    def test_los_elong_range(self):
        los = check_line_of_sight(Planet.EARTH, Planet.MARS, MARS_2003)
        self.assertGreaterEqual(los.elong_deg, 0)
        self.assertLessEqual(los.elong_deg, 180)

    def test_los_closest_sun_positive(self):
        los = check_line_of_sight(Planet.EARTH, Planet.MARS, MARS_2003)
        if los.closest_sun_au is not None:
            self.assertGreater(los.closest_sun_au, 0)


# ── 10. find_meeting_windows ──────────────────────────────────────────────────

class TestFindMeetingWindows(unittest.TestCase):

    def test_earth_earth_overlap(self):
        # Two Earth parties with same work schedule should have many overlaps
        windows = find_meeting_windows(
            Planet.EARTH, Planet.EARTH, J2000_MS, earth_days=7
        )
        self.assertGreater(len(windows), 0)

    def test_windows_type(self):
        windows = find_meeting_windows(
            Planet.EARTH, Planet.MARS, START_2025, earth_days=7
        )
        for w in windows:
            self.assertIsInstance(w, MeetingWindow)
            self.assertGreater(w.end_ms, w.start_ms)
            self.assertGreater(w.duration_min, 0)

    def test_windows_no_overlap(self):
        # Confirm no window starts after end
        windows = find_meeting_windows(
            Planet.EARTH, Planet.MARS, START_2025, earth_days=30
        )
        end = START_2025 + 30 * EARTH_DAY_MS
        for w in windows:
            self.assertGreaterEqual(w.start_ms, START_2025)
            self.assertLessEqual(w.end_ms, end + 1)

    def test_duration_consistent(self):
        windows = find_meeting_windows(
            Planet.EARTH, Planet.EARTH, START_2025, earth_days=7
        )
        for w in windows:
            expected = (w.end_ms - w.start_ms) // 60_000
            self.assertEqual(w.duration_min, expected)

    def test_step_min_parameter(self):
        w15 = find_meeting_windows(Planet.EARTH, Planet.EARTH, START_2025, earth_days=3, step_min=15)
        w30 = find_meeting_windows(Planet.EARTH, Planet.EARTH, START_2025, earth_days=3, step_min=30)
        self.assertGreater(len(w15), 0)
        self.assertGreater(len(w30), 0)

    def test_mars_earth_windows(self):
        windows = find_meeting_windows(
            Planet.EARTH, Planet.MARS, START_2025, earth_days=30
        )
        # We should find at least one overlap window over 30 days
        self.assertGreater(len(windows), 0)


# ── 11. PlanetTimezone / PlanetDateTime ───────────────────────────────────────

class TestPlanetTimezone(unittest.TestCase):

    def test_utcoffset_zero(self):
        import datetime
        tz = PlanetTimezone(Planet.MARS, 0)
        self.assertEqual(tz.utcoffset(None), datetime.timedelta(0))

    def test_tzname_mars(self):
        tz = PlanetTimezone(Planet.MARS, 0)
        name = tz.tzname(None)
        self.assertIn("MARS", name.upper())

    def test_dst_zero(self):
        import datetime
        tz = PlanetTimezone(Planet.EARTH, 0)
        self.assertEqual(tz.dst(None), datetime.timedelta(0))

    def test_planet_timezone_planet(self):
        tz = PlanetTimezone(Planet.JUPITER, 3)
        self.assertEqual(tz.planet, Planet.JUPITER)
        self.assertEqual(tz.offset_h, 3)

    def test_planet_datetime_from_utc_ms(self):
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.MARS, 0)
        self.assertIsNotNone(pdt.planet_time)

    def test_planet_datetime_planet_time(self):
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.MARS, 0)
        pt  = pdt.planet_time
        self.assertEqual(pt.hour, 15)
        self.assertEqual(pt.minute, 45)

    def test_planet_datetime_earth(self):
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.EARTH, 0)
        pt  = pdt.planet_time
        self.assertEqual(pt.hour, 0)

    def test_planet_datetime_strftime_T(self):
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.EARTH, 0)
        self.assertEqual(pdt.strftime('%T'), '00:00')

    def test_planet_datetime_strftime_J(self):
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.EARTH, 0)
        result = pdt.strftime('%J')
        self.assertEqual(result, '0')

    def test_planet_datetime_strftime_standard(self):
        import datetime
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.EARTH, 0)
        # Standard strftime should still work
        result = pdt.strftime('%Y')
        self.assertEqual(result, '2000')

    def test_repr_planet_timezone(self):
        tz = PlanetTimezone(Planet.MARS, 3)
        self.assertIn("MARS", repr(tz).upper())

    def test_planet_datetime_is_datetime(self):
        import datetime
        pdt = PlanetDateTime.from_utc_ms(J2000_MS, Planet.MARS, 0)
        self.assertIsInstance(pdt, datetime.datetime)


# ── 12. Formatting ────────────────────────────────────────────────────────────

class TestFormatting(unittest.TestCase):

    def test_format_lt_sub_ms(self):
        self.assertEqual(format_light_time(0.0), "<1ms")

    def test_format_lt_ms_range(self):
        self.assertIn("ms", format_light_time(0.5))

    def test_format_lt_seconds(self):
        s = format_light_time(30)
        self.assertIn("s", s)
        self.assertNotIn("min", s)

    def test_format_lt_minutes(self):
        s = format_light_time(120)
        self.assertIn("min", s)

    def test_format_lt_hours(self):
        s = format_light_time(7200)
        self.assertIn("h", s)

    def test_format_lt_mars_close(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.MARS, MARS_2003)
        s  = format_light_time(lt)
        self.assertIn("min", s)

    def test_format_planet_time_iso_earth(self):
        pt = get_planet_time(Planet.EARTH, J2000_MS)
        s  = format_planet_time_iso(pt, Planet.EARTH, 0, J2000_MS)
        self.assertIn("T", s)
        self.assertIn("/", s)
        self.assertIn("[", s)
        self.assertIn("Earth", s)

    def test_format_planet_time_iso_mars(self):
        pt = get_planet_time(Planet.MARS, J2000_MS)
        s  = format_planet_time_iso(pt, Planet.MARS, 0, J2000_MS)
        self.assertTrue(s.startswith("MY"))
        self.assertIn("AMT", s)

    def test_format_planet_time_iso_utc_ref(self):
        pt = get_planet_time(Planet.EARTH, START_2025)
        s  = format_planet_time_iso(pt, Planet.EARTH, 0, START_2025)
        self.assertIn("Z", s)

    def test_format_planet_time_iso_offset(self):
        pt = get_planet_time(Planet.MARS, J2000_MS, tz_offset_h=4)
        s  = format_planet_time_iso(pt, Planet.MARS, 4, J2000_MS)
        self.assertIn("AMT+4", s)

    def test_format_lt_moon(self):
        # Moon LT is effectively 0 (same as Earth); should not crash
        lt = light_travel_seconds(Planet.EARTH, Planet.MOON, J2000_MS)
        s  = format_light_time(lt)
        self.assertIsInstance(s, str)

    def test_format_lt_neptune(self):
        lt = light_travel_seconds(Planet.EARTH, Planet.NEPTUNE, START_2025)
        s  = format_light_time(lt)
        self.assertIn("h", s)

    def test_format_planet_time_iso_moon(self):
        pt = get_planet_time(Planet.MOON, J2000_MS)
        s  = format_planet_time_iso(pt, Planet.MOON, 0, J2000_MS)
        self.assertIn("LMT", s)


# ── Orbital / helio_pos sanity ─────────────────────────────────────────────────

class TestHelioPosExtra(unittest.TestCase):
    """Additional orbital mechanics checks (counted across sections above)."""

    def test_helio_pos_earth_r_approx_1au(self):
        hp = helio_pos(Planet.EARTH, J2000_MS)
        self.assertAlmostEqual(hp.r, 1.0, delta=0.02)

    def test_helio_pos_moon_same_as_earth(self):
        hpe = helio_pos(Planet.EARTH, J2000_MS)
        hpm = helio_pos(Planet.MOON, J2000_MS)
        self.assertAlmostEqual(hpe.r, hpm.r, places=6)

    def test_helio_pos_mercury_r(self):
        hp = helio_pos(Planet.MERCURY, J2000_MS)
        self.assertAlmostEqual(hp.r, 0.466, delta=0.05)

    def test_helio_pos_neptune_r(self):
        hp = helio_pos(Planet.NEPTUNE, J2000_MS)
        self.assertAlmostEqual(hp.r, 30.0, delta=1.0)

    def test_kepler_E_circular(self):
        # Circular orbit: e=0, E = M
        for M in [0, 1.0, 2.5, 5.0]:
            self.assertAlmostEqual(_kepler_E(M, 0.0), M, places=10)

    def test_kepler_E_eccentric(self):
        # Known: M=π/2, e=0.5 → E ≈ 1.7628
        E = _kepler_E(math.pi / 2, 0.5)
        self.assertAlmostEqual(E - 0.5 * math.sin(E), math.pi / 2, delta=1e-10)

    def test_lower_quartile_light_time_mars(self):
        lq = lower_quartile_light_time(Planet.EARTH, Planet.MARS, J2000_MS)
        # Lower quartile of E→Mars light time is always < max (~1350 s) and > min (~180 s)
        self.assertGreater(lq, 100)
        self.assertLess(lq, 1350)

    def test_all_planets_helio_pos(self):
        for planet in Planet:
            hp = helio_pos(planet, J2000_MS)
            self.assertGreater(hp.r, 0)
            self.assertFalse(math.isnan(hp.x))
            self.assertFalse(math.isnan(hp.y))


if __name__ == '__main__':
    unittest.main()
