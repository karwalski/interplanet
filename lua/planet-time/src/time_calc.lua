-- time_calc.lua — Planet time calculations for interplanet_time Lua library
-- Story 18.19 — exact port of planet-time.js / Python _time.py

local M = {}

local C      = require("src.constants")
local Orbital = require("src.orbital")
local math   = math

-- ── Zone prefix table ─────────────────────────────────────────────────────────
-- Maps planet index to interplanetary timezone prefix string.
-- Earth (2) is absent — returns nil.
local ZONE_PREFIXES = {
  [C.MERCURY] = "MMT",
  [C.VENUS]   = "VMT",
  [C.MARS]    = "AMT",
  [C.JUPITER] = "JMT",
  [C.SATURN]  = "SMT",
  [C.URANUS]  = "UMT",
  [C.NEPTUNE] = "NMT",
  [C.MOON]    = "LMT",
}

-- ── Internal helpers ──────────────────────────────────────────────────────────

-- Return the planet data entry (Moon maps to Earth).
local function planet_data(planet_idx)
  if planet_idx == C.MOON then
    return C.PLANETS[C.EARTH]
  end
  return C.PLANETS[planet_idx]
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Solar day length in seconds for a given body.
-- @param body_idx  Planet index (0=Mercury..8=Moon)
-- @return seconds
function M.solar_day_seconds(body_idx)
  local p = planet_data(body_idx)
  return p.solar_day_ms / 1000.0
end

--- Local solar time on a planet (seconds since midnight at given longitude).
-- @param body_idx      Planet index
-- @param utc_ms        UTC milliseconds
-- @param longitude_deg Longitude in degrees (east positive; 0 = prime meridian)
-- @return seconds since midnight (0..solar_day_sec)
function M.local_solar_time(body_idx, utc_ms, longitude_deg)
  longitude_deg = longitude_deg or 0.0
  local p = planet_data(body_idx)
  -- Convert longitude fraction of solar day to ms offset
  local tz_adjust_ms = (longitude_deg / 360.0) * p.solar_day_ms
  local elapsed_ms   = (utc_ms - p.epoch_ms) + tz_adjust_ms
  local solar_day_ms = p.solar_day_ms
  -- Day fraction
  local total_days  = elapsed_ms / solar_day_ms
  local day_frac    = total_days - math.floor(total_days)
  return day_frac * (solar_day_ms / 1000.0)
end

--- Sol number (total solar days since planet epoch) at a given UTC time.
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
-- @return number (fractional)
function M.sol_number(body_idx, utc_ms)
  local p = planet_data(body_idx)
  return (utc_ms - p.epoch_ms) / p.solar_day_ms
end

--- Full planet-time record for a body at a given UTC instant.
-- @param body_idx  Planet index (0=Mercury..8=Moon)
-- @param unix_ms   UTC milliseconds since Unix epoch
-- @return table {
--   body, jd, sol, local_time_sec, day_length_sec,
--   light_travel_from_earth_sec,
--   hour, minute, second, local_hour, day_fraction,
--   day_number, day_in_year, year_number,
--   period_in_week, is_work_period, is_work_hour,
--   time_str, time_str_full,
--   sol_in_year (Mars only), sols_per_year (Mars only),
--   mtc (Mars only)
-- }
function M.planet_time(body_idx, unix_ms)
  -- Moon uses Earth's schedule (tidally locked)
  local key = (body_idx == C.MOON) and C.EARTH or body_idx
  local p   = C.PLANETS[key]

  local elapsed_ms  = unix_ms - p.epoch_ms
  local total_days  = elapsed_ms / p.solar_day_ms
  local day_number  = math.floor(total_days)
  local day_frac    = total_days - day_number

  local local_hour  = day_frac * 24.0
  local h  = math.floor(local_hour)
  local m  = math.floor((local_hour - h) * 60.0)
  local s  = math.floor(((local_hour - h) * 60.0 - m) * 60.0)

  -- Work period / week
  local piw, is_work_period, is_work_hour
  if p.earth_clock_sched then
    -- Mercury and Venus: schedule on UTC Mon–Fri 09:00–17:00
    -- UTC day-of-week: (floor(unix_ms/86400000) % 7 + 3) % 7  →  Mon=0..Sun=6
    piw = ((math.floor(unix_ms / 86400000) % 7) + 3) % 7
    is_work_period = piw < p.work_periods_per_week
    local utc_ms_in_day = unix_ms % 86400000
    local utc_hour = utc_ms_in_day / 3600000.0
    is_work_hour = is_work_period
               and utc_hour >= p.work_hours_start
               and utc_hour < p.work_hours_end
  else
    local total_periods = total_days / p.days_per_period
    local period_int    = math.floor(total_periods)
    piw = ((period_int % p.periods_per_week) + p.periods_per_week) % p.periods_per_week
    is_work_period = piw < p.work_periods_per_week
    is_work_hour   = is_work_period
                  and local_hour >= p.work_hours_start
                  and local_hour < p.work_hours_end
  end

  -- Year / day-in-year
  local year_len_days = p.sidereal_yr_ms / p.solar_day_ms
  local year_number   = math.floor(total_days / year_len_days)
  local day_in_year   = total_days - year_number * year_len_days

  -- Julian Day (TT-based JDE from unix_ms)
  local tai_offset = 10
  for _, entry in ipairs(C.LEAP_SECS) do
    if unix_ms >= entry[2] then tai_offset = entry[1] else break end
  end
  local tt_ms = unix_ms + (tai_offset + 32.184) * 1000.0
  local jd    = C.UNIX_EPOCH_JD + tt_ms / 86400000.0

  -- Light travel time from Earth (skip for Earth/Moon)
  local light_travel = nil
  if body_idx ~= C.EARTH and body_idx ~= C.MOON then
    light_travel = Orbital.light_travel_time(C.EARTH, body_idx, unix_ms)
  end

  -- Mars-specific MTC
  local sol_in_year, sols_per_year, mtc = nil, nil, nil
  if body_idx == C.MARS then
    local sols_per_year_f = C.PLANETS[C.MARS].sidereal_yr_ms / C.PLANETS[C.MARS].solar_day_ms
    sol_in_year  = math.floor(day_in_year)
    sols_per_year = math.floor(sols_per_year_f + 0.5) -- round

    -- MTC (Mars Coordinated Time — sol + time of day from Mars epoch)
    local total_sols_mars = (unix_ms - C.MARS_EPOCH_MS) / C.MARS_SOL_MS
    local mtc_sol  = math.floor(total_sols_mars)
    local mtc_frac = total_sols_mars - mtc_sol
    local mh = math.floor(mtc_frac * 24.0)
    local mm = math.floor((mtc_frac * 24.0 - mh) * 60.0)
    local ms2 = math.floor(((mtc_frac * 24.0 - mh) * 60.0 - mm) * 60.0)
    mtc = { sol = mtc_sol, hour = mh, minute = mm, second = ms2 }
  end

  -- Sol from planet epoch (same as day_number for Mars; total_days for others)
  local sol_total = total_days

  -- Zone ID: PREFIX+0 for non-Earth bodies (no tz_offset_h param in this API)
  local zone_id = nil
  local prefix = ZONE_PREFIXES[body_idx]
  if prefix then
    zone_id = prefix .. "+0"
  end

  return {
    body                      = body_idx,
    jd                        = jd,
    sol                       = sol_total,
    local_time_sec            = day_frac * (p.solar_day_ms / 1000.0),
    day_length_sec            = p.solar_day_ms / 1000.0,
    light_travel_from_earth_sec = light_travel,
    -- time fields
    hour                      = h,
    minute                    = m,
    second                    = s,
    local_hour                = local_hour,
    day_fraction              = day_frac,
    day_number                = day_number,
    day_in_year               = math.floor(day_in_year),
    year_number               = year_number,
    period_in_week            = piw,
    is_work_period            = is_work_period,
    is_work_hour              = is_work_hour,
    time_str                  = string.format("%02d:%02d", h, m),
    time_str_full             = string.format("%02d:%02d:%02d", h, m, s),
    -- Mars only
    sol_in_year               = sol_in_year,
    sols_per_year             = sols_per_year,
    mtc                       = mtc,
    -- Zone ID
    zone_id                   = zone_id,
  }
end

return M
