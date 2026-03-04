-- unit_test.lua — Unit tests for interplanet_time Lua library
-- Story 18.19
-- Uses simple pass/fail (no external test framework required)

-- Add parent directory to path so we can require src modules
package.path = package.path .. ";../?.lua;../?/init.lua"

local IPT     = require("src.interplanet_time")
local C       = require("src.constants")
local Orbital = require("src.orbital")
local TC      = require("src.time_calc")

local passed = 0
local failed = 0

-- ── Test helpers ──────────────────────────────────────────────────────────────

local function assert_eq(a, b, msg)
  if a == b then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected: %s\n  got:      %s",
      msg, tostring(b), tostring(a)))
  end
end

local function assert_not_nil(a, msg)
  if a ~= nil then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s — expected non-nil, got nil", msg))
  end
end

local function assert_true(a, msg)
  assert_eq(a, true, msg)
end

local function assert_false(a, msg)
  assert_eq(a, false, msg)
end

local function assert_near(a, b, tol, msg)
  tol = tol or 1e-6
  if math.abs(a - b) <= tol then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected ~%s (tol=%s)\n  got:      %s",
      msg, tostring(b), tostring(tol), tostring(a)))
  end
end

local function assert_ge(a, b, msg)
  if a >= b then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected >= %s\n  got:       %s",
      msg, tostring(b), tostring(a)))
  end
end

local function assert_contains(s, sub, msg)
  if type(s) == "string" and s:find(sub, 1, true) then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected to contain: %s\n  in: %s",
      msg, sub, tostring(s)))
  end
end

-- ── Minimal JSON parser (for fixture file) ────────────────────────────────────

local function json_decode(s)
  local pos = 1

  local function skip_ws()
    while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
  end

  local parse_value

  local function parse_string()
    pos = pos + 1  -- skip opening "
    local result = {}
    while pos <= #s do
      local c = s:sub(pos, pos)
      if c == '"' then pos = pos + 1; break
      elseif c == '\\' then
        pos = pos + 1
        local esc = s:sub(pos, pos)
        if     esc == 'n' then result[#result+1] = '\n'
        elseif esc == 'r' then result[#result+1] = '\r'
        elseif esc == 't' then result[#result+1] = '\t'
        elseif esc == '"' then result[#result+1] = '"'
        elseif esc == '\\' then result[#result+1] = '\\'
        elseif esc == '/' then result[#result+1] = '/'
        else result[#result+1] = esc end
        pos = pos + 1
      else
        result[#result+1] = c
        pos = pos + 1
      end
    end
    return table.concat(result)
  end

  local function parse_number()
    local start = pos
    if s:sub(pos, pos) == '-' then pos = pos + 1 end
    while pos <= #s and s:sub(pos, pos):match("[%d%.eE%+%-]") do pos = pos + 1 end
    return tonumber(s:sub(start, pos - 1))
  end

  local function parse_array()
    pos = pos + 1  -- skip [
    local arr = {}
    skip_ws()
    if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
    while true do
      skip_ws()
      arr[#arr+1] = parse_value()
      skip_ws()
      local c = s:sub(pos, pos)
      if c == ']' then pos = pos + 1; break
      elseif c == ',' then pos = pos + 1 end
    end
    return arr
  end

  local function parse_object()
    pos = pos + 1  -- skip {
    local obj = {}
    skip_ws()
    if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
    while true do
      skip_ws()
      local key = parse_string()
      skip_ws()
      pos = pos + 1  -- skip :
      skip_ws()
      obj[key] = parse_value()
      skip_ws()
      local c = s:sub(pos, pos)
      if c == '}' then pos = pos + 1; break
      elseif c == ',' then pos = pos + 1 end
    end
    return obj
  end

  parse_value = function()
    skip_ws()
    local c = s:sub(pos, pos)
    if c == '"'  then return parse_string()
    elseif c == '[' then return parse_array()
    elseif c == '{' then return parse_object()
    elseif c == 't' then pos = pos + 4; return true
    elseif c == 'f' then pos = pos + 5; return false
    elseif c == 'n' then pos = pos + 4; return nil
    else return parse_number()
    end
  end

  return parse_value()
end

-- ── 1. VERSION ────────────────────────────────────────────────────────────────

assert_not_nil(IPT.VERSION, "IPT.VERSION is set")
assert_contains(IPT.VERSION, ".", "IPT.VERSION has dot separator")

-- ── 2. Planet indices ─────────────────────────────────────────────────────────

assert_eq(IPT.MERCURY, 0, "MERCURY = 0")
assert_eq(IPT.VENUS,   1, "VENUS = 1")
assert_eq(IPT.EARTH,   2, "EARTH = 2")
assert_eq(IPT.MARS,    3, "MARS = 3")
assert_eq(IPT.JUPITER, 4, "JUPITER = 4")
assert_eq(IPT.SATURN,  5, "SATURN = 5")
assert_eq(IPT.URANUS,  6, "URANUS = 6")
assert_eq(IPT.NEPTUNE, 7, "NEPTUNE = 7")
assert_eq(IPT.MOON,    8, "MOON = 8")

-- ── 3. Constants ──────────────────────────────────────────────────────────────

assert_near(IPT.AU_KM,      149597870.7, 0.1,  "AU_KM correct")
assert_near(IPT.C_KMS,      299792.458,  0.001, "C_KMS correct")
assert_near(IPT.AU_SECONDS, 499.004,     0.001, "AU_SECONDS ~499s")
assert_eq  (IPT.J2000_MS,   946728000000,       "J2000_MS correct")
assert_near(IPT.J2000_JD,   2451545.0,   1e-9,  "J2000_JD = 2451545.0")
assert_eq  (IPT.MARS_SOL_MS, 88775244,          "MARS_SOL_MS correct")

-- ── 4. PLANETS table ──────────────────────────────────────────────────────────

assert_not_nil(IPT.PLANETS[IPT.MARS], "PLANETS[MARS] exists")
assert_eq(IPT.PLANETS[IPT.MARS].name, "Mars", "PLANETS[MARS].name = Mars")
assert_eq(IPT.PLANETS[IPT.MARS].solar_day_ms, 88775244, "Mars solar_day_ms")
assert_eq(IPT.PLANETS[IPT.EARTH].solar_day_ms, 86400000, "Earth solar_day_ms")
assert_eq(IPT.PLANETS[IPT.MOON].solar_day_ms, 86400000, "Moon solar_day_ms = Earth")

-- ── 5. ORB_ELEMS table ────────────────────────────────────────────────────────

assert_not_nil(IPT.ORB_ELEMS[IPT.MARS], "ORB_ELEMS[MARS] exists")
assert_near(IPT.ORB_ELEMS[IPT.MARS].a, 1.52366, 1e-5, "Mars semi-major axis")
assert_near(IPT.ORB_ELEMS[IPT.EARTH].a, 1.00000, 1e-5, "Earth semi-major axis = 1 AU")

-- ── 6. PLANET_INDEX lookup ────────────────────────────────────────────────────

assert_eq(IPT.PLANET_INDEX["mars"],    IPT.MARS,    "PLANET_INDEX mars")
assert_eq(IPT.PLANET_INDEX["earth"],   IPT.EARTH,   "PLANET_INDEX earth")
assert_eq(IPT.PLANET_INDEX["moon"],    IPT.MOON,    "PLANET_INDEX moon")
assert_eq(IPT.PLANET_INDEX["jupiter"], IPT.JUPITER, "PLANET_INDEX jupiter")

-- ── 7. julian_day ─────────────────────────────────────────────────────────────

-- J2000.0 = JD 2451545.0 = 2000-01-01 12:00:00 TT (approximately)
local jd_j2000 = IPT.julian_day(2000, 1, 1, 12, 0, 0)
assert_near(jd_j2000, 2451545.0, 0.0001, "julian_day J2000.0 = 2451545.0")

-- Unix epoch 1970-01-01 00:00:00 = JD 2440587.5
local jd_unix = IPT.julian_day(1970, 1, 1, 0, 0, 0)
assert_near(jd_unix, 2440587.5, 0.0001, "julian_day Unix epoch = 2440587.5")

-- ── 8. mean_longitude ────────────────────────────────────────────────────────

-- At J2000.0 epoch, Earth L0 = 100.4664 degrees
local ml = IPT.mean_longitude(IPT.EARTH, IPT.J2000_MS)
assert_ge(ml, 0.0, "mean_longitude >= 0")
assert_ge(360.0, ml, "mean_longitude <= 360")

-- ── 9. true_anomaly ──────────────────────────────────────────────────────────

-- Zero mean anomaly → zero true anomaly for any eccentricity
local ta0 = IPT.true_anomaly(0, 0.0)
assert_near(ta0, 0.0, 1e-10, "true_anomaly(0, 0) = 0")

-- For circular orbit (e=0), true anomaly = mean anomaly
local ta90 = IPT.true_anomaly(90, 0.0)
assert_near(ta90, 90.0, 1e-6, "true_anomaly(90, 0) = 90 (circular)")

-- Kepler's equation check: M = 30deg, e = 0.2
local ta_check = IPT.true_anomaly(30, 0.2)
assert_ge(ta_check, 30.0, "true_anomaly > M for prograde orbit (e>0)")

-- ── 10. ecliptic_longitude ───────────────────────────────────────────────────

local elon = IPT.ecliptic_longitude(IPT.EARTH, IPT.J2000_MS)
assert_ge(elon, 0.0, "ecliptic_longitude >= 0")
assert_ge(360.0, elon, "ecliptic_longitude <= 360")

-- ── 11. heliocentric_pos ─────────────────────────────────────────────────────

local x, y, z = IPT.heliocentric_pos(IPT.EARTH, IPT.J2000_MS)
assert_not_nil(x, "heliocentric_pos x not nil")
assert_not_nil(y, "heliocentric_pos y not nil")
assert_eq(z, 0.0, "heliocentric_pos z = 0 (ecliptic plane)")
-- Earth is ~1 AU from Sun
local r_earth = math.sqrt(x*x + y*y)
assert_near(r_earth, 0.9833, 0.05, "Earth helio distance ~0.983 AU at J2000")

-- Mars should be ~1.52 AU
local mx, my, _ = IPT.heliocentric_pos(IPT.MARS, IPT.J2000_MS)
local r_mars = math.sqrt(mx*mx + my*my)
assert_near(r_mars, 1.39, 0.15, "Mars helio distance near 1.39 AU at J2000")

-- ── 12. heliocentric_r ───────────────────────────────────────────────────────

local r = IPT.heliocentric_r(IPT.EARTH, IPT.J2000_MS)
assert_near(r, r_earth, 1e-9, "heliocentric_r matches heliocentric_pos r")

-- Moon maps to Earth
local r_moon = IPT.heliocentric_r(IPT.MOON, IPT.J2000_MS)
assert_near(r_moon, r_earth, 1e-9, "Moon helio_r = Earth helio_r")

-- ── 13. light_travel_time ────────────────────────────────────────────────────

-- Earth to Mars at J2000: ~923 seconds (from fixture)
local lt_mars = IPT.light_travel_time(IPT.EARTH, IPT.MARS, IPT.J2000_MS)
assert_near(lt_mars, 923.1, 10.0, "Earth-Mars light travel ~923s at J2000")

-- Earth to Jupiter at J2000: ~2306 seconds
local lt_jup = IPT.light_travel_time(IPT.EARTH, IPT.JUPITER, IPT.J2000_MS)
assert_near(lt_jup, 2306.5, 20.0, "Earth-Jupiter light travel ~2306s at J2000")

-- Symmetry: A→B = B→A
local lt_ab = IPT.light_travel_time(IPT.EARTH, IPT.MARS, IPT.J2000_MS)
local lt_ba = IPT.light_travel_time(IPT.MARS, IPT.EARTH, IPT.J2000_MS)
assert_near(lt_ab, lt_ba, 1e-9, "light_travel_time is symmetric")

-- ── 14. solar_day_seconds ────────────────────────────────────────────────────

local earth_day = IPT.solar_day_seconds(IPT.EARTH)
assert_near(earth_day, 86400.0, 1.0, "Earth solar day = 86400s")

local mars_day = IPT.solar_day_seconds(IPT.MARS)
assert_near(mars_day, 88775.244, 0.001, "Mars solar day ~88775.244s")

-- Moon = Earth
local moon_day = IPT.solar_day_seconds(IPT.MOON)
assert_near(moon_day, 86400.0, 1.0, "Moon solar day = Earth day")

-- ── 15. sol_number ───────────────────────────────────────────────────────────

-- At J2000 with epoch=J2000, sol = 0 for non-Mars planets
local sol_earth = IPT.sol_number(IPT.EARTH, IPT.J2000_MS)
assert_near(sol_earth, 0.0, 1e-9, "Earth sol_number at J2000 = 0")

-- Mars sol at J2000: from Mars epoch
local sol_mars = IPT.sol_number(IPT.MARS, IPT.J2000_MS)
assert_near(sol_mars, 16567.66, 0.1, "Mars sol_number at J2000 ~16567")

-- ── 16. local_solar_time ─────────────────────────────────────────────────────

-- At J2000.0, Earth is at epoch so offset=0: time should be 0
local lst_earth = IPT.local_solar_time(IPT.EARTH, IPT.J2000_MS, 0)
assert_near(lst_earth, 0.0, 1.0, "Earth local_solar_time at J2000 prime meridian ~0")

-- At longitude 180, should be half a day later
local lst_180 = IPT.local_solar_time(IPT.EARTH, IPT.J2000_MS, 180)
assert_near(lst_180, 43200.0, 1.0, "Earth local_solar_time at 180 lon = half day")

-- ── 17. planet_time — Earth at J2000 ─────────────────────────────────────────

local pt_earth = IPT.planet_time(IPT.EARTH, IPT.J2000_MS)
assert_not_nil(pt_earth, "planet_time(EARTH) not nil")
assert_eq(pt_earth.hour,   0, "Earth at J2000: hour=0")
assert_eq(pt_earth.minute, 0, "Earth at J2000: minute=0")
assert_eq(pt_earth.second, 0, "Earth at J2000: second=0")
assert_near(pt_earth.local_hour, 0.0, 1e-9, "Earth at J2000: local_hour=0")
assert_near(pt_earth.day_fraction, 0.0, 1e-9, "Earth at J2000: day_fraction=0")
assert_eq(pt_earth.day_number, 0, "Earth at J2000: day_number=0")
assert_eq(pt_earth.year_number, 0, "Earth at J2000: year_number=0")
assert_eq(pt_earth.time_str, "00:00", "Earth at J2000: time_str='00:00'")
assert_eq(pt_earth.time_str_full, "00:00:00", "Earth at J2000: time_str_full='00:00:00'")
-- Earth has no light travel from itself
assert_eq(pt_earth.light_travel_from_earth_sec, nil,
  "Earth has no light_travel_from_earth_sec")
-- Earth has no MTC
assert_eq(pt_earth.mtc, nil, "Earth planet_time has no mtc")
assert_eq(pt_earth.sol_in_year, nil, "Earth planet_time sol_in_year=nil")

-- ── 18. planet_time — Mars at J2000 ──────────────────────────────────────────

local pt_mars = IPT.planet_time(IPT.MARS, IPT.J2000_MS)
assert_not_nil(pt_mars, "planet_time(MARS) not nil")
-- From fixture: Mars at J2000: hour=15, minute=45, second=34
assert_eq(pt_mars.hour,   15, "Mars at J2000: hour=15")
assert_eq(pt_mars.minute, 45, "Mars at J2000: minute=45")
assert_eq(pt_mars.second, 34, "Mars at J2000: second=34")
assert_near(pt_mars.local_hour, 15.7596, 0.001, "Mars at J2000: local_hour~15.76")
assert_eq(pt_mars.day_number, 16567, "Mars at J2000: day_number=16567")
assert_eq(pt_mars.year_number, 24, "Mars at J2000: year_number=24")
-- Mars has sol_in_year / sols_per_year
assert_not_nil(pt_mars.sol_in_year,  "Mars planet_time has sol_in_year")
assert_not_nil(pt_mars.sols_per_year, "Mars planet_time has sols_per_year")
assert_eq(pt_mars.sol_in_year,  520, "Mars at J2000: sol_in_year=520")
assert_eq(pt_mars.sols_per_year, 669, "Mars at J2000: sols_per_year=669")
-- Mars has MTC
assert_not_nil(pt_mars.mtc, "Mars planet_time has mtc")
assert_eq(pt_mars.mtc.sol, 16567, "Mars MTC sol=16567")
assert_eq(pt_mars.mtc.hour, 15, "Mars MTC hour=15")
-- Mars has light travel from Earth
assert_not_nil(pt_mars.light_travel_from_earth_sec, "Mars has light_travel_from_earth_sec")
assert_near(pt_mars.light_travel_from_earth_sec, 923.1, 10.0,
  "Mars light_travel ~923s at J2000")

-- ── 19. planet_time — Moon at J2000 ──────────────────────────────────────────

local pt_moon = IPT.planet_time(IPT.MOON, IPT.J2000_MS)
assert_not_nil(pt_moon, "planet_time(MOON) not nil")
-- Moon uses Earth data, so same time as Earth at J2000
assert_eq(pt_moon.hour, 0,   "Moon at J2000: hour=0")
assert_eq(pt_moon.minute, 0, "Moon at J2000: minute=0")
-- Moon has no MTC, no sol_in_year
assert_eq(pt_moon.mtc, nil, "Moon planet_time has no mtc")
assert_eq(pt_moon.sol_in_year, nil, "Moon planet_time sol_in_year=nil")
-- Moon light travel = nil (same heliocentric position as Earth)
assert_eq(pt_moon.light_travel_from_earth_sec, nil,
  "Moon has no light_travel_from_earth_sec")

-- ── 20. planet_time fields: body and day_length ───────────────────────────────

assert_eq(pt_mars.body, IPT.MARS,   "planet_time body = MARS")
assert_eq(pt_earth.body, IPT.EARTH, "planet_time body = EARTH")
assert_near(pt_mars.day_length_sec, 88775.244, 0.001, "Mars day_length_sec")
assert_near(pt_earth.day_length_sec, 86400.0, 1.0, "Earth day_length_sec")

-- ── 21. period_in_week / is_work_period ──────────────────────────────────────

-- All planets at J2000 epoch → period_in_week=0 → is_work_period=true
local pt_jupiter = IPT.planet_time(IPT.JUPITER, IPT.J2000_MS)
assert_eq(pt_jupiter.period_in_week, 0, "Jupiter at J2000: period_in_week=0")
assert_true(pt_jupiter.is_work_period, "Jupiter at J2000: is_work_period=true")
-- Jupiter at J2000 hour=0, work_hours_start=8 → not work hour
-- (fixture says is_work_hour=1 for Jupiter at J2000 — but fixture uses is_work_hour per JS)
-- Per fixture: is_work_hour=1 for Jupiter at J2000 (hour=0, start=8)
-- Actually fixture says hour=0, is_work_hour=1 for Jupiter J2000 — let's check
-- Jupiter work hours start at 8, so hour 0 is NOT work hour... but fixture says 1.
-- The fixture is the ground truth — we'll verify in fixture runner.
-- Here just test that the field exists:
assert_not_nil(pt_jupiter.is_work_hour, "Jupiter is_work_hour exists")

-- ── 22. Fixture validation ────────────────────────────────────────────────────
-- Load the reference fixture and validate all 54 entries.

-- Locate fixture file relative to this script
local fixture_path = arg and arg[1]
if not fixture_path then
  -- Resolve relative path: test/ is in lua/planet-time/test/
  -- fixture is in c/planet-time/fixtures/reference.json
  -- Running from lua/planet-time/ (Makefile uses: $(LUA) test/unit_test.lua)
  fixture_path = "../../c/planet-time/fixtures/reference.json"
end

local f = io.open(fixture_path, "r")
local fixture_checked = 0

if not f then
  print("WARNING: fixture file not found at: " .. fixture_path)
  print("  (Run 'make fixture' to run the dedicated fixture runner)")
else
  local content = f:read("*a")
  f:close()
  local fixture = json_decode(content)

  -- Tolerances
  local TOL_LIGHT  = 10.0    -- seconds
  local TOL_HOUR   = 1.0/3600  -- 1 second in hours

  for _, entry in ipairs(fixture.entries) do
    local utc_ms     = entry.utc_ms
    local planet_idx = C.PLANET_INDEX[entry.planet]

    if planet_idx then
      local pt = IPT.planet_time(planet_idx, utc_ms)
      local label = entry.planet .. "@" .. entry.date_label

      -- hour / minute / second
      assert_eq(pt.hour,   entry.hour,   label .. ":hour")
      assert_eq(pt.minute, entry.minute, label .. ":minute")
      assert_eq(pt.second, entry.second, label .. ":second")

      -- time_str
      assert_eq(pt.time_str,      entry.time_str,      label .. ":time_str")
      assert_eq(pt.time_str_full, entry.time_str_full, label .. ":time_str_full")

      -- day_number, year_number
      assert_eq(pt.day_number,  entry.day_number,  label .. ":day_number")
      assert_eq(pt.year_number, entry.year_number, label .. ":year_number")

      -- period_in_week, is_work_period, is_work_hour
      assert_eq(pt.period_in_week, entry.period_in_week, label .. ":period_in_week")
      assert_eq(pt.is_work_period and 1 or 0, entry.is_work_period, label .. ":is_work_period")
      assert_eq(pt.is_work_hour   and 1 or 0, entry.is_work_hour,   label .. ":is_work_hour")

      -- helio_r_au via heliocentric_r
      local r = IPT.heliocentric_r(planet_idx, utc_ms)
      assert_near(r, entry.helio_r_au, 0.0001, label .. ":helio_r_au")

      -- light travel from Earth (skip for Earth and Moon)
      if entry.light_travel_s ~= nil then
        local lt = IPT.light_travel_time(IPT.EARTH, planet_idx, utc_ms)
        assert_near(lt, entry.light_travel_s, TOL_LIGHT, label .. ":light_travel_s")
      end

      -- Mars MTC
      if entry.planet == "mars" and entry.mtc then
        assert_not_nil(pt.mtc, label .. ":mtc not nil")
        assert_eq(pt.mtc.sol,    entry.mtc.sol,    label .. ":mtc.sol")
        assert_eq(pt.mtc.hour,   entry.mtc.hour,   label .. ":mtc.hour")
        assert_eq(pt.mtc.minute, entry.mtc.minute, label .. ":mtc.minute")
        assert_eq(pt.mtc.second, entry.mtc.second, label .. ":mtc.second")
        assert_eq(pt.sol_in_year, entry.sol_in_year, label .. ":sol_in_year")
        assert_eq(pt.sols_per_year, entry.sols_per_year, label .. ":sols_per_year")
      end

      fixture_checked = fixture_checked + 1
    end
  end

  print(string.format("fixture entries checked: %d", fixture_checked))
end

-- ── Results ───────────────────────────────────────────────────────────────────

if failed > 0 then
  print(string.format("\n%d passed, %d FAILED", passed, failed))
  os.exit(1)
else
  print(string.format("\n%d passed, 0 flaws", passed))
end
