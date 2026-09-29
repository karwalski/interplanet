-- interplanet_ltx.lua — LTX (Light-Time eXchange) SDK for Lua
-- Story 61.1 — Lua port of the LTX SDK
--
-- Usage:
--   local LTX = require("interplanet_ltx")
--   local plan = LTX.create_plan({ host_name = "Earth HQ", delay = 800 })

local constants = require("src.constants")

local M = {}
M.VERSION = constants.VERSION

-- ── Internal utilities ───────────────────────────────────────────────────────

local function pad2(n)
  return string.format("%02d", n)
end

-- Base64url encode a string (no padding)
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
  local result = {}
  local len = #data
  local i = 1
  while i <= len do
    local b1 = string.byte(data, i) or 0
    local b2 = string.byte(data, i + 1) or 0
    local b3 = string.byte(data, i + 2) or 0
    local n = b1 * 65536 + b2 * 256 + b3
    result[#result + 1] = string.sub(b64chars, math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
    result[#result + 1] = string.sub(b64chars, math.floor((n % 262144) / 4096) + 1, math.floor((n % 262144) / 4096) + 1)
    result[#result + 1] = string.sub(b64chars, math.floor((n % 4096) / 64) + 1, math.floor((n % 4096) / 64) + 1)
    result[#result + 1] = string.sub(b64chars, (n % 64) + 1, (n % 64) + 1)
    i = i + 3
  end
  local encoded = table.concat(result)
  -- Trim padding
  local rem = len % 3
  if rem == 1 then
    encoded = encoded:sub(1, -3)
  elseif rem == 2 then
    encoded = encoded:sub(1, -2)
  end
  -- Convert to base64url
  encoded = encoded:gsub("%+", "-"):gsub("/", "_")
  return encoded
end

local b64decode_map = {}
for i = 1, #b64chars do
  b64decode_map[string.sub(b64chars, i, i)] = i - 1
end
b64decode_map["-"] = 62
b64decode_map["_"] = 63

local function b64decode(s)
  s = s:gsub("%-", "+"):gsub("_", "/")
  -- Add padding back
  local pad = (4 - (#s % 4)) % 4
  s = s .. string.rep("=", pad)
  local result = {}
  for i = 1, #s, 4 do
    local c1 = b64decode_map[s:sub(i, i)] or 0
    local c2 = b64decode_map[s:sub(i+1, i+1)] or 0
    local c3 = b64decode_map[s:sub(i+2, i+2)] or 0
    local c4 = b64decode_map[s:sub(i+3, i+3)] or 0
    local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
    result[#result + 1] = string.char(math.floor(n / 65536))
    if s:sub(i+2, i+2) ~= "=" then
      result[#result + 1] = string.char(math.floor((n % 65536) / 256))
    end
    if s:sub(i+3, i+3) ~= "=" then
      result[#result + 1] = string.char(n % 256)
    end
  end
  return table.concat(result)
end

-- Minimal JSON serialiser (handles string, number, boolean, nil, table-as-array, table-as-object)
local function json_encode(val, indent, level)
  local t = type(val)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    if val ~= val then return "null" end  -- NaN guard
    return tostring(val)
  elseif t == "string" then
    -- Escape special characters
    local s = val:gsub('\\', '\\\\')
               :gsub('"', '\\"')
               :gsub('\n', '\\n')
               :gsub('\r', '\\r')
               :gsub('\t', '\\t')
    return '"' .. s .. '"'
  elseif t == "table" then
    level = level or 0
    -- Check if array (sequential integer keys from 1)
    local is_array = true
    local max_n = 0
    for k, _ in pairs(val) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      if k > max_n then max_n = k end
    end
    if is_array and max_n == #val then
      local parts = {}
      for _, v in ipairs(val) do
        parts[#parts + 1] = json_encode(v, indent, level + 1)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      -- Object — sort keys for determinism
      local keys = {}
      for k in pairs(val) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = json_encode(tostring(k)) .. ":" .. json_encode(val[k], indent, level + 1)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

-- Minimal JSON parser
local function json_decode(s)
  local pos = 1

  local function skip_ws()
    while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
  end

  local parse_value  -- forward declaration

  local function parse_string()
    pos = pos + 1  -- skip opening "
    local result = {}
    while pos <= #s do
      local c = s:sub(pos, pos)
      if c == '"' then pos = pos + 1; break
      elseif c == '\\' then
        pos = pos + 1
        local esc = s:sub(pos, pos)
        if esc == 'n' then result[#result+1] = '\n'
        elseif esc == 'r' then result[#result+1] = '\r'
        elseif esc == 't' then result[#result+1] = '\t'
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
      elseif c == ',' then pos = pos + 1
      end
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
      elseif c == ',' then pos = pos + 1
      end
    end
    return obj
  end

  parse_value = function()
    skip_ws()
    local c = s:sub(pos, pos)
    if c == '"' then return parse_string()
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

-- Exposed JSON helpers (used by the v1.1 conformance tests and tooling).
M.json_encode = json_encode
M.json_decode = json_decode

-- ── Story 26.3: ICS text escaping ────────────────────────────────────────────

--- Escape a string for RFC 5545 TEXT property values.
-- Escapes backslash → \\, semicolon → \;, comma → \,, newline → \n
-- @param s string
-- @return string
function M.escape_ics_text(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub(";", "\\;")
  s = s:gsub(",", "\\,")
  s = s:gsub("\n", "\\n")
  return s
end

-- ── Story 26.4: Protocol hardening ───────────────────────────────────────────

--- Compute the plan-lock timeout in milliseconds.
-- @param delay_seconds number
-- @return number  milliseconds
function M.plan_lock_timeout_ms(delay_seconds)
  return delay_seconds * constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000
end

--- Check if the measured delay violates the declared delay threshold.
-- @param declared_delay_s number
-- @param measured_delay_s number
-- @return string  "ok" | "violation" | "degraded"
function M.check_delay_violation(declared_delay_s, measured_delay_s)
  local diff = math.abs(measured_delay_s - declared_delay_s)
  if diff > constants.DELAY_VIOLATION_DEGRADED_S then return "degraded" end
  if diff > constants.DELAY_VIOLATION_WARN_S then return "violation" end
  return "ok"
end

-- ── Config management ────────────────────────────────────────────────────────

--- Upgrade a v1 config to v2 schema (v2 configs returned unchanged).
-- @param cfg table  LTX plan config
-- @return table  v2 config
function M.upgrade_config(cfg)
  if cfg.v and cfg.v >= 2 and type(cfg.nodes) == "table" and #cfg.nodes > 0 then
    return cfg
  end
  local rx_name = cfg.rx_name or cfg.rxName or ""
  local remote_loc = "earth"
  if rx_name:lower():find("mars") then remote_loc = "mars"
  elseif rx_name:lower():find("moon") then remote_loc = "moon"
  end
  local result = {}
  for k, v in pairs(cfg) do result[k] = v end
  result.v = 2
  result.nodes = {
    { id = "N0", name = cfg.tx_name or cfg.txName or "Earth HQ",
      role = "HOST", delay = 0, location = "earth" },
    { id = "N1", name = rx_name ~= "" and rx_name or "Mars Hab-01",
      role = "PARTICIPANT", delay = cfg.delay or 0, location = remote_loc },
  }
  return result
end

--- Create a new LTX session plan.
-- @param opts table  Options:
--   title string, start string (ISO 8601), quantum number, mode string,
--   nodes table, host_name string, host_location string,
--   remote_name string, remote_location string, delay number, segments table
-- @return table  LTX plan config (v2)
function M.create_plan(opts)
  opts = opts or {}
  -- Default start: 5 minutes from now (as ISO 8601 string via os.date)
  local start_time = opts.start
  if not start_time then
    local t = os.time() + 300  -- +5 min
    start_time = os.date("!%Y-%m-%dT%H:%M:%SZ", t)
  end

  local nodes = opts.nodes
  if not nodes then
    nodes = {
      { id = "N0",
        name     = opts.host_name or "Earth HQ",
        role     = "HOST",
        delay    = 0,
        location = opts.host_location or "earth" },
      { id = "N1",
        name     = opts.remote_name or "Mars Hab-01",
        role     = "PARTICIPANT",
        delay    = opts.delay or 0,
        location = opts.remote_location or "mars" },
    }
  end

  local segs = opts.segments
  if not segs then
    segs = {}
    for _, s in ipairs(constants.DEFAULT_SEGMENTS) do
      segs[#segs + 1] = { type = s.type, q = s.q }
    end
  end

  return {
    v        = 2,
    title    = opts.title   or "LTX Session",
    start    = start_time,
    quantum  = opts.quantum or constants.DEFAULT_QUANTUM,
    mode     = opts.mode    or "LTX",
    segments = segs,
    nodes    = nodes,
  }
end

-- ── Segment computation ──────────────────────────────────────────────────────

-- Parse ISO 8601 UTC timestamp to Unix seconds (basic implementation)
local function parse_iso8601(s)
  local year, mon, day, h, m, sec =
    s:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not year then
    year, mon, day, h, m, sec =
      s:match("(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)")
  end
  if not year then return 0 end
  -- Use os.time with UTC correction: os.time interprets the table as LOCAL
  -- time, so subtract the local-vs-UTC offset (negative east of Greenwich).
  local now = os.time()
  local utc_offset = os.time(os.date("!*t", now)) - now
  local t = os.time({
    year = tonumber(year), month = tonumber(mon),  day = tonumber(day),
    hour = tonumber(h),    min   = tonumber(m),    sec = tonumber(sec),
    isdst = false,
  })
  return t - utc_offset
end

local function format_iso8601(t)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", t)
end

--- Compute the timed segment array for a plan config.
-- @param cfg table  LTX plan config (v1 or v2)
-- @return table  Array of { type, q, start_iso, end_iso, dur_min }, or nil, string on error
function M.compute_segments(cfg)
  local c = M.upgrade_config(cfg)
  if (c.quantum or 0) < 1 then
    return nil, "quantum must be >= 1, got " .. tostring(c.quantum)
  end
  local q_sec = c.quantum * 60
  local t = parse_iso8601(c.start)
  local result = {}
  for _, s in ipairs(c.segments) do
    local dur = s.q * q_sec
    result[#result + 1] = {
      type      = s.type,
      q         = s.q,
      start_iso = format_iso8601(t),
      end_iso   = format_iso8601(t + dur),
      dur_min   = s.q * c.quantum,
    }
    t = t + dur
  end
  return result
end

--- Total session duration in minutes.
-- @param cfg table
-- @return number
function M.total_min(cfg)
  local total = 0
  for _, s in ipairs(cfg.segments) do
    total = total + s.q * cfg.quantum
  end
  return total
end

-- ── Delay matrix ─────────────────────────────────────────────────────────────

--- Build a flat delay matrix for all ordered node pairs in a plan.
-- Every entry is pair_delay(plan, from, to) (LTX-SPECIFICATION.md §3.7.3):
-- a v3 pair matrix entry (plan.delays) is authoritative where present;
-- HOST to node is that node's declared delay; node to node (neither is HOST)
-- is the SUM of both HOST-relative delays (a conservative upper bound via the
-- HOST vertex), not the max. The matrix is symmetric.
-- @param plan table  LTX plan config (v1, v2 or v3)
-- @return table  Array of { from_id, from_name, to_id, to_name, delay_seconds }
function M.build_delay_matrix(plan)
  local v11 = require("src.v11")
  local c = M.upgrade_config(plan)
  local nodes = c.nodes or {}
  local matrix = {}
  for i = 1, #nodes do
    for j = 1, #nodes do
      if i ~= j then
        local from = nodes[i]
        local to   = nodes[j]
        matrix[#matrix + 1] = {
          from_id      = from.id,
          from_name    = from.name,
          to_id        = to.id,
          to_name      = to.name,
          delay_seconds = assert(v11.pair_delay(c, from.id, to.id)),
        }
      end
    end
  end
  return matrix
end

-- ── Plan ID ──────────────────────────────────────────────────────────────────

-- Serialise a JSON number the way JSON.stringify does (ints without ".0").
local function plan_json_num(v)
  if math.type(v) == "integer" then return tostring(v) end
  if type(v) == "number" and v == math.floor(v) then
    return string.format("%d", v)
  end
  return tostring(v)
end

--- Serialise a plan in the cross-port schema key order:
-- v, title, start, quantum, mode, nodes (id,name,role,delay,location),
-- segments (type,q[,speaker][,label]). This byte sequence is the FROZEN
-- input of the legacy v2 planId polynomial hash (LTX-SPECIFICATION.md §4.3)
-- and matches JSON.stringify of the reference implementation.
function M.plan_schema_json(c)
  local parts = {
    '"v":' .. plan_json_num(c.v or 2),
    '"title":' .. json_encode(tostring(c.title or "")),
    '"start":' .. json_encode(tostring(c.start or "")),
    '"quantum":' .. plan_json_num(c.quantum or 0),
    '"mode":' .. json_encode(tostring(c.mode or "")),
  }
  local nodes = {}
  for _, n in ipairs(c.nodes or {}) do
    nodes[#nodes + 1] = '{"id":' .. json_encode(n.id or "")
      .. ',"name":' .. json_encode(n.name or "")
      .. ',"role":' .. json_encode(n.role or "")
      .. ',"delay":' .. plan_json_num(n.delay or 0)
      .. ',"location":' .. json_encode(n.location or "") .. '}'
  end
  parts[#parts + 1] = '"nodes":[' .. table.concat(nodes, ",") .. ']'
  local segs = {}
  for _, s in ipairs(c.segments or {}) do
    local seg = '{"type":' .. json_encode(s.type or "")
      .. ',"q":' .. plan_json_num(s.q or 0)
    if s.speaker ~= nil then seg = seg .. ',"speaker":' .. json_encode(s.speaker) end
    if s.label ~= nil then seg = seg .. ',"label":' .. json_encode(s.label) end
    segs[#segs + 1] = seg .. '}'
  end
  parts[#parts + 1] = '"segments":[' .. table.concat(segs, ",") .. ']'
  return '{' .. table.concat(parts, ",") .. '}'
end

--- Compute the deterministic plan ID string for a config.
--
-- v2 plans use the FROZEN legacy 32-bit polynomial hash over the fixed
-- schema-order JSON (LTX-SPECIFICATION.md §4.3). v3 plans (v >= 3) hash
-- SHA-256 over the RFC 8785 canonical JSON (§4.5); the "-v3-" infix keeps
-- the two id spaces disjoint.
--
-- @param cfg table
-- @return string  e.g. "LTX-20260101-EARTHHQ-MARSHA-v2-a3b2c1d0"
-- upgradeConfig for an insertion-ordered plan (src/json.lua): v2+ plans with
-- nodes are unchanged; v1 configs gain v = 2 and a two-node list with JS
-- spread semantics (existing keys keep their position, new keys append).
local function upgrade_ordered(cfg)
  local json = require("src.json")
  if type(cfg.v) == "number" and cfg.v >= 2 and type(cfg.nodes) == "table" and #cfg.nodes > 0 then
    return cfg
  end
  local rx_name = cfg.rxName or ""
  local remote_loc = "earth"
  if rx_name:lower():find("mars") then remote_loc = "mars"
  elseif rx_name:lower():find("moon") then remote_loc = "moon"
  end
  local c = json.with(cfg, "v", 2)
  return json.with(c, "nodes", json.array({
    json.object({ { "id", "N0" }, { "name", cfg.txName or "Earth HQ" }, { "role", "HOST" },
                  { "delay", 0 }, { "location", "earth" } }),
    json.object({ { "id", "N1" }, { "name", cfg.rxName or "Mars Hab-01" }, { "role", "PARTICIPANT" },
                  { "delay", cfg.delay or 0 }, { "location", remote_loc } }),
  }))
end

-- ── planId HOSTSTR / NODESTR (LTX-SPECIFICATION.md §4.3) ────────────────────
-- JS name.replace(/\s+/g, '').toUpperCase().slice(0, n) on UTF-8 strings.
-- string.upper / %s / string.sub are byte-wise and ASCII only, so the three
-- steps are done per code point: ECMAScript whitespace, the full Unicode
-- upper-case mapping of JS toUpperCase (generated table below: 1:1 runs and
-- special casings such as 'ß' to "SS"), and a slice in UTF-16 code units.

local function is_js_whitespace(cp)
  return (cp >= 0x09 and cp <= 0x0D) or cp == 0x20 or cp == 0xA0 or cp == 0x1680
    or (cp >= 0x2000 and cp <= 0x200A) or cp == 0x2028 or cp == 0x2029
    or cp == 0x202F or cp == 0x205F or cp == 0x3000 or cp == 0xFEFF
end

-- BEGIN GENERATED UPPER TABLE
-- Generated by scripts/conformance/gen-upper-tables.js from JS toUpperCase, Unicode 17.0 (node 22.22.2).
-- { first, last, stride, delta }
local UPPER_RUNS = {
  {0x61,0x7A,1,-32}, {0xB5,0xB5,1,743}, {0xE0,0xF6,1,-32},
  {0xF8,0xFE,1,-32}, {0xFF,0xFF,1,121}, {0x101,0x12F,2,-1},
  {0x131,0x131,1,-232}, {0x133,0x137,2,-1}, {0x13A,0x148,2,-1},
  {0x14B,0x177,2,-1}, {0x17A,0x17E,2,-1}, {0x17F,0x17F,1,-300},
  {0x180,0x180,1,195}, {0x183,0x185,2,-1}, {0x188,0x188,1,-1},
  {0x18C,0x18C,1,-1}, {0x192,0x192,1,-1}, {0x195,0x195,1,97},
  {0x199,0x199,1,-1}, {0x19A,0x19A,1,163}, {0x19B,0x19B,1,42561},
  {0x19E,0x19E,1,130}, {0x1A1,0x1A5,2,-1}, {0x1A8,0x1A8,1,-1},
  {0x1AD,0x1AD,1,-1}, {0x1B0,0x1B0,1,-1}, {0x1B4,0x1B6,2,-1},
  {0x1B9,0x1B9,1,-1}, {0x1BD,0x1BD,1,-1}, {0x1BF,0x1BF,1,56},
  {0x1C5,0x1C5,1,-1}, {0x1C6,0x1C6,1,-2}, {0x1C8,0x1C8,1,-1},
  {0x1C9,0x1C9,1,-2}, {0x1CB,0x1CB,1,-1}, {0x1CC,0x1CC,1,-2},
  {0x1CE,0x1DC,2,-1}, {0x1DD,0x1DD,1,-79}, {0x1DF,0x1EF,2,-1},
  {0x1F2,0x1F2,1,-1}, {0x1F3,0x1F3,1,-2}, {0x1F5,0x1F5,1,-1},
  {0x1F9,0x21F,2,-1}, {0x223,0x233,2,-1}, {0x23C,0x23C,1,-1},
  {0x23F,0x240,1,10815}, {0x242,0x242,1,-1}, {0x247,0x24F,2,-1},
  {0x250,0x250,1,10783}, {0x251,0x251,1,10780}, {0x252,0x252,1,10782},
  {0x253,0x253,1,-210}, {0x254,0x254,1,-206}, {0x256,0x257,1,-205},
  {0x259,0x259,1,-202}, {0x25B,0x25B,1,-203}, {0x25C,0x25C,1,42319},
  {0x260,0x260,1,-205}, {0x261,0x261,1,42315}, {0x263,0x263,1,-207},
  {0x264,0x264,1,42343}, {0x265,0x265,1,42280}, {0x266,0x266,1,42308},
  {0x268,0x268,1,-209}, {0x269,0x269,1,-211}, {0x26A,0x26A,1,42308},
  {0x26B,0x26B,1,10743}, {0x26C,0x26C,1,42305}, {0x26F,0x26F,1,-211},
  {0x271,0x271,1,10749}, {0x272,0x272,1,-213}, {0x275,0x275,1,-214},
  {0x27D,0x27D,1,10727}, {0x280,0x280,1,-218}, {0x282,0x282,1,42307},
  {0x283,0x283,1,-218}, {0x287,0x287,1,42282}, {0x288,0x288,1,-218},
  {0x289,0x289,1,-69}, {0x28A,0x28B,1,-217}, {0x28C,0x28C,1,-71},
  {0x292,0x292,1,-219}, {0x29D,0x29D,1,42261}, {0x29E,0x29E,1,42258},
  {0x345,0x345,1,84}, {0x371,0x373,2,-1}, {0x377,0x377,1,-1},
  {0x37B,0x37D,1,130}, {0x3AC,0x3AC,1,-38}, {0x3AD,0x3AF,1,-37},
  {0x3B1,0x3C1,1,-32}, {0x3C2,0x3C2,1,-31}, {0x3C3,0x3CB,1,-32},
  {0x3CC,0x3CC,1,-64}, {0x3CD,0x3CE,1,-63}, {0x3D0,0x3D0,1,-62},
  {0x3D1,0x3D1,1,-57}, {0x3D5,0x3D5,1,-47}, {0x3D6,0x3D6,1,-54},
  {0x3D7,0x3D7,1,-8}, {0x3D9,0x3EF,2,-1}, {0x3F0,0x3F0,1,-86},
  {0x3F1,0x3F1,1,-80}, {0x3F2,0x3F2,1,7}, {0x3F3,0x3F3,1,-116},
  {0x3F5,0x3F5,1,-96}, {0x3F8,0x3F8,1,-1}, {0x3FB,0x3FB,1,-1},
  {0x430,0x44F,1,-32}, {0x450,0x45F,1,-80}, {0x461,0x481,2,-1},
  {0x48B,0x4BF,2,-1}, {0x4C2,0x4CE,2,-1}, {0x4CF,0x4CF,1,-15},
  {0x4D1,0x52F,2,-1}, {0x561,0x586,1,-48}, {0x10D0,0x10FA,1,3008},
  {0x10FD,0x10FF,1,3008}, {0x13F8,0x13FD,1,-8}, {0x1C80,0x1C80,1,-6254},
  {0x1C81,0x1C81,1,-6253}, {0x1C82,0x1C82,1,-6244}, {0x1C83,0x1C84,1,-6242},
  {0x1C85,0x1C85,1,-6243}, {0x1C86,0x1C86,1,-6236}, {0x1C87,0x1C87,1,-6181},
  {0x1C88,0x1C88,1,35266}, {0x1C8A,0x1C8A,1,-1}, {0x1D79,0x1D79,1,35332},
  {0x1D7D,0x1D7D,1,3814}, {0x1D8E,0x1D8E,1,35384}, {0x1E01,0x1E95,2,-1},
  {0x1E9B,0x1E9B,1,-59}, {0x1EA1,0x1EFF,2,-1}, {0x1F00,0x1F07,1,8},
  {0x1F10,0x1F15,1,8}, {0x1F20,0x1F27,1,8}, {0x1F30,0x1F37,1,8},
  {0x1F40,0x1F45,1,8}, {0x1F51,0x1F57,2,8}, {0x1F60,0x1F67,1,8},
  {0x1F70,0x1F71,1,74}, {0x1F72,0x1F75,1,86}, {0x1F76,0x1F77,1,100},
  {0x1F78,0x1F79,1,128}, {0x1F7A,0x1F7B,1,112}, {0x1F7C,0x1F7D,1,126},
  {0x1FB0,0x1FB1,1,8}, {0x1FBE,0x1FBE,1,-7205}, {0x1FD0,0x1FD1,1,8},
  {0x1FE0,0x1FE1,1,8}, {0x1FE5,0x1FE5,1,7}, {0x214E,0x214E,1,-28},
  {0x2170,0x217F,1,-16}, {0x2184,0x2184,1,-1}, {0x24D0,0x24E9,1,-26},
  {0x2C30,0x2C5F,1,-48}, {0x2C61,0x2C61,1,-1}, {0x2C65,0x2C65,1,-10795},
  {0x2C66,0x2C66,1,-10792}, {0x2C68,0x2C6C,2,-1}, {0x2C73,0x2C73,1,-1},
  {0x2C76,0x2C76,1,-1}, {0x2C81,0x2CE3,2,-1}, {0x2CEC,0x2CEE,2,-1},
  {0x2CF3,0x2CF3,1,-1}, {0x2D00,0x2D25,1,-7264}, {0x2D27,0x2D27,1,-7264},
  {0x2D2D,0x2D2D,1,-7264}, {0xA641,0xA66D,2,-1}, {0xA681,0xA69B,2,-1},
  {0xA723,0xA72F,2,-1}, {0xA733,0xA76F,2,-1}, {0xA77A,0xA77C,2,-1},
  {0xA77F,0xA787,2,-1}, {0xA78C,0xA78C,1,-1}, {0xA791,0xA793,2,-1},
  {0xA794,0xA794,1,48}, {0xA797,0xA7A9,2,-1}, {0xA7B5,0xA7C3,2,-1},
  {0xA7C8,0xA7CA,2,-1}, {0xA7CD,0xA7DB,2,-1}, {0xA7F6,0xA7F6,1,-1},
  {0xAB53,0xAB53,1,-928}, {0xAB70,0xABBF,1,-38864}, {0xFF41,0xFF5A,1,-32},
  {0x10428,0x1044F,1,-40}, {0x104D8,0x104FB,1,-40}, {0x10597,0x105A1,1,-39},
  {0x105A3,0x105B1,1,-39}, {0x105B3,0x105B9,1,-39}, {0x105BB,0x105BC,1,-39},
  {0x10CC0,0x10CF2,1,-64}, {0x10D70,0x10D85,1,-32}, {0x118C0,0x118DF,1,-32},
  {0x16E60,0x16E7F,1,-32}, {0x16EBB,0x16ED3,1,-27}, {0x1E922,0x1E943,1,-34},
}
-- [code point] = { code points }
local UPPER_SPECIAL = {
  [0xDF]={0x53,0x53}, [0x149]={0x2BC,0x4E}, [0x1F0]={0x4A,0x30C},
  [0x390]={0x399,0x308,0x301}, [0x3B0]={0x3A5,0x308,0x301}, [0x587]={0x535,0x552},
  [0x1E96]={0x48,0x331}, [0x1E97]={0x54,0x308}, [0x1E98]={0x57,0x30A},
  [0x1E99]={0x59,0x30A}, [0x1E9A]={0x41,0x2BE}, [0x1F50]={0x3A5,0x313},
  [0x1F52]={0x3A5,0x313,0x300}, [0x1F54]={0x3A5,0x313,0x301}, [0x1F56]={0x3A5,0x313,0x342},
  [0x1F80]={0x1F08,0x399}, [0x1F81]={0x1F09,0x399}, [0x1F82]={0x1F0A,0x399},
  [0x1F83]={0x1F0B,0x399}, [0x1F84]={0x1F0C,0x399}, [0x1F85]={0x1F0D,0x399},
  [0x1F86]={0x1F0E,0x399}, [0x1F87]={0x1F0F,0x399}, [0x1F88]={0x1F08,0x399},
  [0x1F89]={0x1F09,0x399}, [0x1F8A]={0x1F0A,0x399}, [0x1F8B]={0x1F0B,0x399},
  [0x1F8C]={0x1F0C,0x399}, [0x1F8D]={0x1F0D,0x399}, [0x1F8E]={0x1F0E,0x399},
  [0x1F8F]={0x1F0F,0x399}, [0x1F90]={0x1F28,0x399}, [0x1F91]={0x1F29,0x399},
  [0x1F92]={0x1F2A,0x399}, [0x1F93]={0x1F2B,0x399}, [0x1F94]={0x1F2C,0x399},
  [0x1F95]={0x1F2D,0x399}, [0x1F96]={0x1F2E,0x399}, [0x1F97]={0x1F2F,0x399},
  [0x1F98]={0x1F28,0x399}, [0x1F99]={0x1F29,0x399}, [0x1F9A]={0x1F2A,0x399},
  [0x1F9B]={0x1F2B,0x399}, [0x1F9C]={0x1F2C,0x399}, [0x1F9D]={0x1F2D,0x399},
  [0x1F9E]={0x1F2E,0x399}, [0x1F9F]={0x1F2F,0x399}, [0x1FA0]={0x1F68,0x399},
  [0x1FA1]={0x1F69,0x399}, [0x1FA2]={0x1F6A,0x399}, [0x1FA3]={0x1F6B,0x399},
  [0x1FA4]={0x1F6C,0x399}, [0x1FA5]={0x1F6D,0x399}, [0x1FA6]={0x1F6E,0x399},
  [0x1FA7]={0x1F6F,0x399}, [0x1FA8]={0x1F68,0x399}, [0x1FA9]={0x1F69,0x399},
  [0x1FAA]={0x1F6A,0x399}, [0x1FAB]={0x1F6B,0x399}, [0x1FAC]={0x1F6C,0x399},
  [0x1FAD]={0x1F6D,0x399}, [0x1FAE]={0x1F6E,0x399}, [0x1FAF]={0x1F6F,0x399},
  [0x1FB2]={0x1FBA,0x399}, [0x1FB3]={0x391,0x399}, [0x1FB4]={0x386,0x399},
  [0x1FB6]={0x391,0x342}, [0x1FB7]={0x391,0x342,0x399}, [0x1FBC]={0x391,0x399},
  [0x1FC2]={0x1FCA,0x399}, [0x1FC3]={0x397,0x399}, [0x1FC4]={0x389,0x399},
  [0x1FC6]={0x397,0x342}, [0x1FC7]={0x397,0x342,0x399}, [0x1FCC]={0x397,0x399},
  [0x1FD2]={0x399,0x308,0x300}, [0x1FD3]={0x399,0x308,0x301}, [0x1FD6]={0x399,0x342},
  [0x1FD7]={0x399,0x308,0x342}, [0x1FE2]={0x3A5,0x308,0x300}, [0x1FE3]={0x3A5,0x308,0x301},
  [0x1FE4]={0x3A1,0x313}, [0x1FE6]={0x3A5,0x342}, [0x1FE7]={0x3A5,0x308,0x342},
  [0x1FF2]={0x1FFA,0x399}, [0x1FF3]={0x3A9,0x399}, [0x1FF4]={0x38F,0x399},
  [0x1FF6]={0x3A9,0x342}, [0x1FF7]={0x3A9,0x342,0x399}, [0x1FFC]={0x3A9,0x399},
  [0xFB00]={0x46,0x46}, [0xFB01]={0x46,0x49}, [0xFB02]={0x46,0x4C},
  [0xFB03]={0x46,0x46,0x49}, [0xFB04]={0x46,0x46,0x4C}, [0xFB05]={0x53,0x54},
  [0xFB06]={0x53,0x54}, [0xFB13]={0x544,0x546}, [0xFB14]={0x544,0x535},
  [0xFB15]={0x544,0x53B}, [0xFB16]={0x54E,0x546}, [0xFB17]={0x544,0x53D},
}
-- END GENERATED UPPER TABLE

--- Upper-case one code point as JS does: returns a list of 1 to 3 code points.
local function upper_cp(cp)
  if cp >= 0x61 and cp <= 0x7A then return { cp - 0x20 } end
  if cp < 0xB5 then return { cp } end
  local sp = UPPER_SPECIAL[cp]
  if sp then return sp end
  for _, r in ipairs(UPPER_RUNS) do
    if cp < r[1] then break end
    if cp <= r[2] and (cp - r[1]) % r[3] == 0 then return { cp + r[4] } end
  end
  return { cp }
end

--- s.toUpperCase() with JavaScript semantics (s is UTF-8).
function M.js_upper(s)
  local out = {}
  for _, cp in utf8.codes(s) do
    for _, u in ipairs(upper_cp(cp)) do out[#out + 1] = utf8.char(u) end
  end
  return table.concat(out)
end

--- s.slice(0, n) in UTF-16 code units (s is UTF-8). When the cut splits a
-- surrogate pair JS keeps the lone high surrogate, which a UTF-8 string
-- cannot hold: it becomes U+FFFD, the UTF-8 form of the JS id (planIdUtf8
-- in spec/golden/plan-id-prefixes.json).
local function utf16_slice(s, n)
  local out, units = {}, 0
  for _, cp in utf8.codes(s) do
    local w = cp >= 0x10000 and 2 or 1
    if units + w > n then
      if units < n then out[#out + 1] = "\u{FFFD}" end
      break
    end
    units = units + w
    out[#out + 1] = utf8.char(cp)
  end
  return table.concat(out)
end
M.utf16_slice = utf16_slice

--- name.replace(/\s+/g, '').toUpperCase().slice(0, n)
function M.plan_id_token(name, n)
  local kept = {}
  for _, cp in utf8.codes(name) do
    if not is_js_whitespace(cp) then kept[#kept + 1] = utf8.char(cp) end
  end
  return utf16_slice(M.js_upper(table.concat(kept)), n)
end

function M.make_plan_id(cfg)
  local json  = require("src.json")
  local ordered = json.key_order(cfg) ~= nil
  local c     = ordered and upgrade_ordered(cfg) or M.upgrade_config(cfg)
  local date  = (c.start or ""):sub(1, 10):gsub("-", "")
  local nodes = c.nodes or {}
  local host_name = nodes[1] and nodes[1].name
  if host_name == nil or host_name == "" then host_name = "HOST" end
  local host_str = M.plan_id_token(host_name, 8)
  local node_str
  if #nodes > 1 then
    local parts = {}
    for i = 2, #nodes do
      parts[#parts + 1] = M.plan_id_token(nodes[i].name or "", 4)
    end
    node_str = utf16_slice(table.concat(parts, "-"), 16)
  else
    node_str = "RX"
  end

  if (c.v or 2) >= 3 then
    local security = require("src.security")
    local digest = security.sha256_hex(security.canonical_json(c))
    return string.format("LTX-%s-%s-%s-v3-%s", date, host_str, node_str,
      digest:sub(1, 8))
  end

  -- FROZEN v2 path: imul31 over the UTF-16 code units of the plan JSON. An
  -- insertion-ordered plan (decoded by src/json.lua) is hashed exactly as
  -- JSON.stringify emits it; a plain Lua table uses the schema key order.
  local raw = ordered and json.stringify(c) or M.plan_schema_json(c)
  return string.format("LTX-%s-%s-%s-v2-%s", date, host_str, node_str, json.imul31_hex(raw))
end

--- planId of a plan given as JSON text, preserving its key order (the form in
-- which plans travel; see spec/golden/plan-ids.json).
function M.plan_id_from_json(text)
  return M.make_plan_id(require("src.json").decode_ordered(text))
end

--- Validate a v2 or v3 plan (see src/validate.lua): returns
-- { valid = bool, errors = { { code, path, message }, ... } }.
function M.validate_plan(plan)
  return require("src.validate").validate_plan(plan)
end

-- ── Hash encoding ────────────────────────────────────────────────────────────

--- The JSON a plan travels as, in the key order make_plan_id hashes: an
-- insertion-ordered plan (src/json.lua) as JSON.stringify emits it, a plain
-- v2 table in the schema order of plan_schema_json, and a v3 table with
-- sorted keys (its planId hashes canonical JSON, so order does not matter).
-- Serialising a plain v2 table with sorted keys would transmit a different
-- key order than the frozen v2 hash covers (issue #32).
function M.wire_json(cfg)
  local json = require("src.json")
  if json.key_order(cfg) ~= nil then return json.stringify(cfg) end
  local c = M.upgrade_config(cfg)
  if (c.v or 2) >= 3 then return json_encode(c) end
  return M.plan_schema_json(c)
end

--- Encode a plan config to a URL hash fragment (#l=…).
-- @param cfg table
-- @return string  e.g. "#l=eyJ2IjoyLC4uLn0"
function M.encode_hash(cfg)
  return "#l=" .. b64encode(M.wire_json(cfg))
end

--- Decode a plan config from a URL hash fragment.
-- @param hash string  "#l=…" or "l=…" or raw base64
-- @return table|nil
function M.decode_hash(hash)
  local token = (hash or ""):gsub("^#?l=", "")
  if token == "" then return nil end
  local ok, result = pcall(function()
    return json_decode(b64decode(token))
  end)
  if ok then return result else return nil end
end

--- Build perspective URLs for all nodes in a plan.
-- @param cfg table      LTX plan config
-- @param base_url string  Base page URL
-- @return table  Array of { node_id, name, role, url }
function M.build_node_urls(cfg, base_url)
  local c    = M.upgrade_config(cfg)
  local hash = M.encode_hash(c)
  local base = (base_url or ""):gsub("#.*$", ""):gsub("%?.*$", "")
  local result = {}
  for _, node in ipairs(c.nodes or {}) do
    result[#result + 1] = {
      node_id = node.id,
      name    = node.name,
      role    = node.role,
      url     = base .. "?node=" .. node.id .. hash,
    }
  end
  return result
end

-- ── ICS generation ────────────────────────────────────────────────────────────

local function fmt_dt(iso)
  -- Convert "2026-01-15T10:00:00Z" → "20260115T100000Z"
  return iso:gsub("[%-%:]", ""):gsub("%.%d+", "")
end

local function to_id(name)
  return name:gsub("%s+", "-"):upper()
end

--- Generate LTX-extended iCalendar (.ics) content for a plan.
-- @param cfg table
-- @return string  ICS text (lines joined with CRLF)
function M.generate_ics(cfg)
  local c    = M.upgrade_config(cfg)
  local segs = M.compute_segments(c)
  local plan_id   = M.make_plan_id(c)
  local nodes     = c.nodes or {}
  local host      = nodes[1] or { name = "Earth HQ", role = "HOST", delay = 0, location = "earth" }
  local parts     = {}
  for i = 2, #nodes do parts[#parts + 1] = nodes[i] end

  local seg_tpl = {}
  for _, s in ipairs(c.segments) do seg_tpl[#seg_tpl + 1] = s.type end

  local lines = {
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//InterPlanet//LTX v1.0//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    "UID:" .. plan_id .. "@interplanet.live",
    "DTSTAMP:" .. fmt_dt(format_iso8601(os.time())),
    "DTSTART:" .. fmt_dt(c.start),
    "DTEND:" .. fmt_dt((segs[#segs] or {}).end_iso or c.start),
    "SUMMARY:" .. M.escape_ics_text(c.title),
    "LTX:1",
    "LTX-PLANID:" .. plan_id,
    "LTX-QUANTUM:PT" .. c.quantum .. "M",
    "LTX-SEGMENT-TEMPLATE:" .. table.concat(seg_tpl, ","),
    "LTX-MODE:" .. c.mode,
  }

  for _, node in ipairs(nodes) do
    lines[#lines + 1] = "LTX-NODE:ID=" .. to_id(node.name) .. ";ROLE=" .. node.role
  end
  for _, p in ipairs(parts) do
    local d = p.delay or 0
    lines[#lines + 1] = "LTX-DELAY;NODEID=" .. to_id(p.name) ..
      ":ONEWAY-MIN=" .. d .. ";ONEWAY-MAX=" .. (d + 120) .. ";ONEWAY-ASSUMED=" .. d
  end

  lines[#lines + 1] = "END:VEVENT"
  lines[#lines + 1] = "END:VCALENDAR"

  return table.concat(lines, "\r\n")
end

-- ── Format utilities ─────────────────────────────────────────────────────────

--- Format seconds as HH:MM:SS or MM:SS.
-- @param sec number
-- @return string
function M.format_hms(sec)
  if sec < 0 then sec = 0 end
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  if h > 0 then
    return pad2(h) .. ":" .. pad2(m) .. ":" .. pad2(s)
  end
  return pad2(m) .. ":" .. pad2(s)
end

return M
