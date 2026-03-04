-- interplanet_time.lua — Public facade for the Interplanetary Time Lua library
-- Story 18.19
--
-- Usage:
--   local IPT = require("src.interplanet_time")
--   local result = IPT.planet_time(IPT.MARS, unix_ms)
--   local lt = IPT.light_travel_time(IPT.EARTH, IPT.MARS, unix_ms)

local C       = require("src.constants")
local Orbital = require("src.orbital")
local TimeCalc = require("src.time_calc")

local M = {}

M.VERSION = C.VERSION

-- ── Planet index constants ────────────────────────────────────────────────────

M.MERCURY = C.MERCURY
M.VENUS   = C.VENUS
M.EARTH   = C.EARTH
M.MARS    = C.MARS
M.JUPITER = C.JUPITER
M.SATURN  = C.SATURN
M.URANUS  = C.URANUS
M.NEPTUNE = C.NEPTUNE
M.MOON    = C.MOON

-- ── Re-export constants module ────────────────────────────────────────────────

M.PLANETS      = C.PLANETS
M.ORB_ELEMS    = C.ORB_ELEMS
M.PLANET_INDEX = C.PLANET_INDEX
M.AU_KM        = C.AU_KM
M.C_KMS        = C.C_KMS
M.AU_SECONDS   = C.AU_SECONDS
M.J2000_MS     = C.J2000_MS
M.J2000_JD     = C.J2000_JD
M.MARS_EPOCH_MS = C.MARS_EPOCH_MS
M.MARS_SOL_MS  = C.MARS_SOL_MS

-- ── Re-export orbital functions ───────────────────────────────────────────────

--- Julian Day from calendar components.
-- @param year, month, day, hour, minute, second
-- @return JD number
M.julian_day = Orbital.julian_day

--- Mean longitude of a body (degrees).
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
M.mean_longitude = Orbital.mean_longitude

--- True anomaly from mean anomaly and eccentricity (degrees).
-- @param mean_anomaly_deg  degrees
-- @param eccentricity      dimensionless
M.true_anomaly = Orbital.true_anomaly

--- Ecliptic longitude of a body (degrees, 0..360).
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
M.ecliptic_longitude = Orbital.ecliptic_longitude

--- Heliocentric (x, y, z) position in AU (ecliptic plane; z=0).
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
-- @return x, y, z (AU)
M.heliocentric_pos = Orbital.heliocentric_pos

--- Heliocentric distance (r) of a body in AU.
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
M.heliocentric_r = Orbital.heliocentric_r

--- One-way light travel time between two bodies (seconds).
-- @param body1_idx, body2_idx  Planet indices
-- @param utc_ms               UTC milliseconds
M.light_travel_time = Orbital.light_travel_time

-- ── Re-export time calculation functions ─────────────────────────────────────

--- Solar day length in seconds.
-- @param body_idx  Planet index
M.solar_day_seconds = TimeCalc.solar_day_seconds

--- Local solar time on a planet (seconds since midnight).
-- @param body_idx      Planet index
-- @param utc_ms        UTC milliseconds
-- @param longitude_deg Longitude in degrees (east positive)
M.local_solar_time = TimeCalc.local_solar_time

--- Sol number (total solar days since planet epoch).
-- @param body_idx  Planet index
-- @param utc_ms   UTC milliseconds
M.sol_number = TimeCalc.sol_number

--- Full planet-time record for a body at a UTC instant.
-- @param body_idx  Planet index
-- @param unix_ms   UTC milliseconds
-- @return table with all time fields
M.planet_time = TimeCalc.planet_time

return M
