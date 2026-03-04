-- fixture_runner.lua — Validates all 54 reference.json fixture entries
-- Story 18.19
--
-- Usage:
--   lua test/fixture_runner.lua ../../c/planet-time/fixtures/reference.json
--   (or via Makefile: make fixture)

package.path = package.path .. ";../?.lua;../?/init.lua"

local IPT = require("src.interplanet_time")
local C   = require("src.constants")

-- ── Minimal JSON parser ───────────────────────────────────────────────────────

local function json_decode(s)
  local pos = 1

  local function skip_ws()
    while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
  end

  local parse_value

  local function parse_string()
    pos = pos + 1
    local result = {}
    while pos <= #s do
      local c = s:sub(pos, pos)
      if c == '"' then pos = pos + 1; break
      elseif c == '\\' then
        pos = pos + 1
        local esc = s:sub(pos, pos)
        if     esc == 'n'  then result[#result+1] = '\n'
        elseif esc == 'r'  then result[#result+1] = '\r'
        elseif esc == 't'  then result[#result+1] = '\t'
        elseif esc == '"'  then result[#result+1] = '"'
        elseif esc == '\\' then result[#result+1] = '\\'
        elseif esc == '/'  then result[#result+1] = '/'
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
    pos = pos + 1
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
    pos = pos + 1
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

-- ── Main ─────────────────────────────────────────────────────────────────────

local fixture_path = arg and arg[1]
if not fixture_path then
  fixture_path = "../../c/planet-time/fixtures/reference.json"
end

local f = io.open(fixture_path, "r")
if not f then
  print("ERROR: cannot open fixture file: " .. tostring(fixture_path))
  os.exit(1)
end
local content = f:read("*a")
f:close()

local fixture = json_decode(content)
if not fixture or not fixture.entries then
  print("ERROR: could not parse fixture JSON")
  os.exit(1)
end

-- Tolerances
local TOL_LIGHT   = 10.0   -- seconds for light travel time
local TOL_HELIO_R = 0.0001 -- AU for heliocentric distance

local passed  = 0
local failed  = 0
local checked = 0

local function check(cond, label, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL [%s]: %s", label, detail or ""))
  end
end

for _, entry in ipairs(fixture.entries) do
  local utc_ms     = entry.utc_ms
  local planet_idx = C.PLANET_INDEX[entry.planet]
  local label      = entry.planet .. "@" .. entry.date_label

  if not planet_idx then
    print("WARN: unknown planet: " .. tostring(entry.planet))
    goto continue
  end

  local pt = IPT.planet_time(planet_idx, utc_ms)

  -- Time fields
  check(pt.hour   == entry.hour,   label, "hour: got "..pt.hour.." expected "..entry.hour)
  check(pt.minute == entry.minute, label, "minute: got "..pt.minute.." expected "..entry.minute)
  check(pt.second == entry.second, label, "second: got "..pt.second.." expected "..entry.second)
  check(pt.time_str      == entry.time_str,      label, "time_str")
  check(pt.time_str_full == entry.time_str_full, label, "time_str_full")

  -- Day fields
  check(pt.day_number  == entry.day_number,  label, "day_number: got "..pt.day_number.." expected "..entry.day_number)
  check(pt.year_number == entry.year_number, label, "year_number")

  -- Work period fields
  check(pt.period_in_week == entry.period_in_week, label, "period_in_week")
  check((pt.is_work_period and 1 or 0) == entry.is_work_period, label, "is_work_period")
  check((pt.is_work_hour   and 1 or 0) == entry.is_work_hour,   label, "is_work_hour")

  -- Heliocentric distance
  local r = IPT.heliocentric_r(planet_idx, utc_ms)
  check(math.abs(r - entry.helio_r_au) <= TOL_HELIO_R, label,
    string.format("helio_r_au: got %.6f expected %.6f (diff %.6f)",
      r, entry.helio_r_au, math.abs(r - entry.helio_r_au)))

  -- Light travel time
  if entry.light_travel_s ~= nil then
    local lt = IPT.light_travel_time(IPT.EARTH, planet_idx, utc_ms)
    check(math.abs(lt - entry.light_travel_s) <= TOL_LIGHT, label,
      string.format("light_travel_s: got %.2f expected %.2f (diff %.2f)",
        lt, entry.light_travel_s, math.abs(lt - entry.light_travel_s)))
  end

  -- Mars MTC
  if entry.planet == "mars" then
    if entry.mtc then
      check(pt.mtc ~= nil, label, "mtc should exist")
      if pt.mtc then
        check(pt.mtc.sol    == entry.mtc.sol,    label, "mtc.sol")
        check(pt.mtc.hour   == entry.mtc.hour,   label, "mtc.hour")
        check(pt.mtc.minute == entry.mtc.minute, label, "mtc.minute")
        check(pt.mtc.second == entry.mtc.second, label, "mtc.second")
      end
    end
    if entry.sol_in_year ~= nil then
      check(pt.sol_in_year == entry.sol_in_year, label,
        "sol_in_year: got "..tostring(pt.sol_in_year).." expected "..tostring(entry.sol_in_year))
    end
    if entry.sols_per_year ~= nil then
      check(pt.sols_per_year == entry.sols_per_year, label,
        "sols_per_year: got "..tostring(pt.sols_per_year).." expected "..tostring(entry.sols_per_year))
    end
  end

  checked = checked + 1

  ::continue::
end

print(string.format("\nfixture entries checked: %d / %d", checked, #fixture.entries))
if failed > 0 then
  print(string.format("%d passed, %d FAILED", passed, failed))
  os.exit(1)
else
  print(string.format("%d passed, 0 flaws", passed))
end
