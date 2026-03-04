-- constants.lua — LTX protocol constants
-- Interplanet LTX SDK for Lua

local M = {}

M.VERSION = "1.0.0"

M.SEG_TYPES = {
  "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
  "SPEAK", "RELAY", "REST", "PAD",
}

M.DEFAULT_QUANTUM = 3  -- minutes per quantum

M.DEFAULT_SEGMENTS = {
  { type = "PLAN_CONFIRM", q = 2 },
  { type = "TX",           q = 2 },
  { type = "RX",           q = 2 },
  { type = "CAUCUS",       q = 2 },
  { type = "TX",           q = 2 },
  { type = "RX",           q = 2 },
  { type = "BUFFER",       q = 1 },
}

M.DEFAULT_API_BASE = "https://interplanet.live/api/ltx.php"

-- Story 26.4 constants
M.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2
M.DELAY_VIOLATION_WARN_S = 120
M.DELAY_VIOLATION_DEGRADED_S = 300
M.SESSION_STATES = { "INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE" }

return M
