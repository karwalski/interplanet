-- orbital.lua — Orbital mechanics for interplanet_time Lua library
-- Story 18.19 — exact port of planet-time.js / Python _orbital.py
--
-- All functions accept utc_ms (number, milliseconds since Unix epoch).

local M = {}

local C   = require("src.constants")
local math = math

local PI     = math.pi
local TWO_PI = 2.0 * PI
local D2R    = PI / 180.0

-- ── Internal: leap-second / Julian Day helpers ────────────────────────────────

-- Return TAI − UTC in seconds for a given UTC timestamp (ms).
local function tai_minus_utc(utc_ms)
  local offset = 10
  for _, entry in ipairs(C.LEAP_SECS) do
    if utc_ms >= entry[2] then
      offset = entry[1]
    else
      break
    end
  end
  return offset
end

-- Convert UTC milliseconds to Terrestrial Time Julian Ephemeris Day.
-- TT = UTC + (TAI−UTC) + 32.184 s
local function jde(utc_ms)
  local tt_ms = utc_ms + (tai_minus_utc(utc_ms) + 32.184) * 1000.0
  return C.UNIX_EPOCH_JD + tt_ms / 86400000.0
end

-- Julian centuries from J2000.0 for the given UTC millisecond timestamp.
local function jc(utc_ms)
  return (jde(utc_ms) - C.J2000_JD) / 36525.0
end

-- Expose julian_day as public (simple JDE from UTC ms)
function M.julian_day(year, month, day, hour, minute, second)
  -- Standard Julian Day formula (valid for all dates after -4716)
  hour    = hour    or 0
  minute  = minute  or 0
  second  = second  or 0
  local a = math.floor((14 - month) / 12)
  local y = year + 4800 - a
  local m = month + 12 * a - 3
  local jdn = day
    + math.floor((153 * m + 2) / 5)
    + 365 * y
    + math.floor(y / 4)
    - math.floor(y / 100)
    + math.floor(y / 400)
    - 32045
  return jdn - 0.5 + (hour + minute / 60.0 + second / 3600.0) / 24.0
end

-- ── Internal: Kepler solver ──────────────────────────────────────────────────

-- Solve Kepler's equation M = E − e·sin(E) using Newton-Raphson.
-- 50 iterations; tolerance 1e-12 radians.
local function kepler_E(M_anom, e)
  local E = M_anom
  for _ = 1, 50 do
    local dE = (M_anom - E + e * math.sin(E)) / (1.0 - e * math.cos(E))
    E = E + dE
    if math.abs(dE) < 1e-12 then break end
  end
  return E
end

-- ── Internal: planet index helper ────────────────────────────────────────────

-- Return orbital-elements key (Moon maps to Earth).
local function orb_key(planet_idx)
  if planet_idx == C.MOON then return C.EARTH end
  return planet_idx
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Mean longitude of a body at a given UTC millisecond timestamp.
-- @param body_idx  Planet index (0=Mercury..8=Moon)
-- @param utc_ms   UTC milliseconds
-- @return degrees (0..360)
function M.mean_longitude(body_idx, utc_ms)
  local el = C.ORB_ELEMS[orb_key(body_idx)]
  local T  = jc(utc_ms)
  local L_rad = math.fmod(math.fmod((el.L0 + el.dL * T) * D2R, TWO_PI) + TWO_PI, TWO_PI)
  return L_rad / D2R
end

--- True anomaly from mean anomaly (degrees) and eccentricity.
-- Uses Kepler equation (Newton-Raphson, 50 iters).
-- @param mean_anomaly_deg  degrees
-- @param eccentricity      dimensionless
-- @return true anomaly in degrees
function M.true_anomaly(mean_anomaly_deg, eccentricity)
  local M_rad = mean_anomaly_deg * D2R
  local E = kepler_E(M_rad, eccentricity)
  local v = 2.0 * math.atan2(
    math.sqrt(1.0 + eccentricity) * math.sin(E / 2.0),
    math.sqrt(1.0 - eccentricity) * math.cos(E / 2.0)
  )
  return v / D2R
end

--- Ecliptic longitude of a body (degrees, 0..360).
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
-- @return degrees
function M.ecliptic_longitude(body_idx, utc_ms)
  local key = orb_key(body_idx)
  local el  = C.ORB_ELEMS[key]
  local T   = jc(utc_ms)

  local L   = math.fmod(math.fmod((el.L0 + el.dL * T) * D2R, TWO_PI) + TWO_PI, TWO_PI)
  local om  = el.om0 * D2R
  local M_r = math.fmod(math.fmod(L - om, TWO_PI) + TWO_PI, TWO_PI)
  local E   = kepler_E(M_r, el.e0)
  local v   = 2.0 * math.atan2(
    math.sqrt(1.0 + el.e0) * math.sin(E / 2.0),
    math.sqrt(1.0 - el.e0) * math.cos(E / 2.0)
  )
  local lon = math.fmod(math.fmod(v + om, TWO_PI) + TWO_PI, TWO_PI)
  return lon / D2R
end

--- Heliocentric (x, y, z) position of a body in AU (ecliptic plane; z=0).
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
-- @return x, y, z (AU)
function M.heliocentric_pos(body_idx, utc_ms)
  local key = orb_key(body_idx)
  local el  = C.ORB_ELEMS[key]
  local T   = jc(utc_ms)

  local L   = math.fmod(math.fmod((el.L0 + el.dL * T) * D2R, TWO_PI) + TWO_PI, TWO_PI)
  local om  = el.om0 * D2R
  local M_r = math.fmod(math.fmod(L - om, TWO_PI) + TWO_PI, TWO_PI)
  local E   = kepler_E(M_r, el.e0)
  local v   = 2.0 * math.atan2(
    math.sqrt(1.0 + el.e0) * math.sin(E / 2.0),
    math.sqrt(1.0 - el.e0) * math.cos(E / 2.0)
  )
  local r   = el.a * (1.0 - el.e0 * math.cos(E))
  local lon = math.fmod(math.fmod(v + om, TWO_PI) + TWO_PI, TWO_PI)

  local x = r * math.cos(lon)
  local y = r * math.sin(lon)
  return x, y, 0.0
end

--- One-way light travel time between two solar-system bodies.
-- @param body1_idx  Planet index of first body
-- @param body2_idx  Planet index of second body
-- @param utc_ms     UTC milliseconds
-- @return seconds
function M.light_travel_time(body1_idx, body2_idx, utc_ms)
  local x1, y1 = M.heliocentric_pos(body1_idx, utc_ms)
  local x2, y2 = M.heliocentric_pos(body2_idx, utc_ms)
  local dx = x1 - x2
  local dy = y1 - y2
  local dist_au = math.sqrt(dx * dx + dy * dy)
  return dist_au * C.AU_SECONDS
end

--- Heliocentric distance (r) of a body in AU.
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
-- @return AU
function M.heliocentric_r(body_idx, utc_ms)
  local key = orb_key(body_idx)
  local el  = C.ORB_ELEMS[key]
  local T   = jc(utc_ms)

  local L   = math.fmod(math.fmod((el.L0 + el.dL * T) * D2R, TWO_PI) + TWO_PI, TWO_PI)
  local om  = el.om0 * D2R
  local M_r = math.fmod(math.fmod(L - om, TWO_PI) + TWO_PI, TWO_PI)
  local E   = kepler_E(M_r, el.e0)
  return el.a * (1.0 - el.e0 * math.cos(E))
end

return M
