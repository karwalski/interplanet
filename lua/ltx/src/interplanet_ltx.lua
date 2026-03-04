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
  -- Use os.time with UTC correction
  local utc_offset = os.time() - os.time(os.date("*t", os.time()))
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

--- Build a flat delay matrix for all node pairs in a plan.
-- @param plan table  LTX plan config (v1 or v2)
-- @return table  Array of { from_id, from_name, to_id, to_name, delay_seconds }
function M.build_delay_matrix(plan)
  local c = M.upgrade_config(plan)
  local nodes = c.nodes or {}
  local matrix = {}
  for i = 1, #nodes do
    for j = 1, #nodes do
      if i ~= j then
        local from = nodes[i]
        local to   = nodes[j]
        local delay_sec
        if (from.delay or 0) == 0 or i == 1 then
          delay_sec = to.delay or 0
        elseif (to.delay or 0) == 0 or j == 1 then
          delay_sec = from.delay or 0
        else
          delay_sec = (from.delay or 0) + (to.delay or 0)
        end
        matrix[#matrix + 1] = {
          from_id      = from.id,
          from_name    = from.name,
          to_id        = to.id,
          to_name      = to.name,
          delay_seconds = delay_sec,
        }
      end
    end
  end
  return matrix
end

-- ── Plan ID ──────────────────────────────────────────────────────────────────

--- Compute the deterministic plan ID string for a config.
-- @param cfg table
-- @return string  e.g. "LTX-20260101-EARTHHQ-MARSHA-v2-a3b2c1d0"
function M.make_plan_id(cfg)
  local c     = M.upgrade_config(cfg)
  local date  = (c.start or ""):sub(1, 10):gsub("-", "")
  local nodes = c.nodes or {}
  local host_str = ((nodes[1] and nodes[1].name) or "HOST")
    :gsub("%s+", ""):upper():sub(1, 8)
  local node_str
  if #nodes > 1 then
    local parts = {}
    for i = 2, #nodes do
      parts[#parts + 1] = (nodes[i].name or ""):gsub("%s+", ""):upper():sub(1, 4)
    end
    node_str = table.concat(parts, "-"):sub(1, 16)
  else
    node_str = "RX"
  end

  -- DJB-style polynomial hash of canonical JSON
  local raw = json_encode(c)
  local h = 0
  for k = 1, #raw do
    h = (31 * h + string.byte(raw, k)) % (2^32)
  end
  return string.format("LTX-%s-%s-%s-v2-%08x", date, host_str, node_str, h)
end

-- ── Hash encoding ────────────────────────────────────────────────────────────

--- Encode a plan config to a URL hash fragment (#l=…).
-- @param cfg table
-- @return string  e.g. "#l=eyJ2IjoyLC4uLn0"
function M.encode_hash(cfg)
  return "#l=" .. b64encode(json_encode(cfg))
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
  local hash = "#l=" .. b64encode(json_encode(c))
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
