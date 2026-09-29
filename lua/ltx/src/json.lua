-- json.lua -- insertion-ordered JSON for the frozen v2 planId (LTX-SPECIFICATION.md §4.3)
--
-- Lua tables do not keep key order, but the v2 planId hash is computed over
-- JSON.stringify of the plan in insertion order. decode_ordered() records the
-- key order of every object in its metatable (__jsonorder) and marks arrays
-- (__jsonarray, so an empty [] stays an array); stringify() replays that order
-- byte-for-byte like JSON.stringify; imul31_hex() is the frozen hash over
-- UTF-16 code units. Decoded tables are ordinary Lua tables otherwise.

local M = {}

--- Sentinel for JSON null inside decoded objects and arrays.
M.null = setmetatable({}, { __jsonnull = true, __tostring = function() return "null" end })

local ARRAY_MT = { __jsonarray = true }

--- Mark a Lua sequence as a JSON array (so an empty table encodes as []).
function M.array(t)
  return setmetatable(t or {}, ARRAY_MT)
end

--- True if t was decoded from (or marked as) a JSON array.
function M.is_array(t)
  local mt = type(t) == "table" and getmetatable(t)
  return mt ~= nil and mt ~= false and mt.__jsonarray == true
end

--- Key order of a decoded object, or nil for plain tables.
function M.key_order(t)
  local mt = type(t) == "table" and getmetatable(t)
  return mt and mt.__jsonorder or nil
end

--- Build an ordered object from a list of { key, value } pairs.
function M.object(pairs_list)
  local obj, order = {}, {}
  for _, kv in ipairs(pairs_list) do
    obj[kv[1]] = kv[2]
    order[#order + 1] = kv[1]
  end
  return setmetatable(obj, { __jsonorder = order })
end

--- Copy an ordered object and set key k (JS spread semantics: an existing key
-- keeps its position, a new key is appended).
function M.with(obj, k, v)
  local order = {}
  local src = M.key_order(obj) or {}
  local seen = false
  for i, key in ipairs(src) do
    order[i] = key
    if key == k then seen = true end
  end
  if not seen then order[#order + 1] = k end
  local out = {}
  for key, val in pairs(obj) do out[key] = val end
  out[k] = v
  return setmetatable(out, { __jsonorder = order })
end

-- ── Decoding ────────────────────────────────────────────────────────────────

local function utf8_char(cp)
  return utf8.char(cp)
end

--- Decode JSON text, keeping object key order and array-ness in metatables.
function M.decode_ordered(s)
  local pos = 1

  local function fail(msg)
    error("json: " .. msg .. " at " .. pos, 0)
  end

  local function skip_ws()
    pos = s:find("[^ \t\r\n]", pos) or (#s + 1)
  end

  local parse_value

  local function parse_string()
    pos = pos + 1
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unterminated string") end
      if c == '"' then pos = pos + 1; break end
      if c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        if e == "u" then
          local cp = tonumber(s:sub(pos + 2, pos + 5), 16)
          pos = pos + 6
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(s:sub(pos + 2, pos + 5), 16)
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
            pos = pos + 6
          end
          out[#out + 1] = utf8_char(cp)
        else
          local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
          if not map[e] then fail("bad escape") end
          out[#out + 1] = map[e]
          pos = pos + 2
        end
      else
        local j = s:find('["\\]', pos) or (#s + 1)
        out[#out + 1] = s:sub(pos, j - 1)
        pos = j
      end
    end
    return table.concat(out)
  end

  local function parse_number()
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not num or num == "" then fail("unexpected input") end
    pos = pos + #num
    if num:find("[.eE]") then return tonumber(num) end
    return math.tointeger(tonumber(num)) or tonumber(num)
  end

  local function parse_array()
    pos = pos + 1
    local arr = M.array({})
    skip_ws()
    if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
    while true do
      local v = parse_value()
      arr[#arr + 1] = v
      skip_ws()
      local c = s:sub(pos, pos)
      pos = pos + 1
      if c == "]" then break elseif c ~= "," then fail("expected , or ]") end
    end
    return arr
  end

  local function parse_object()
    pos = pos + 1
    local obj, order = {}, {}
    skip_ws()
    if s:sub(pos, pos) == "}" then
      pos = pos + 1
      return setmetatable(obj, { __jsonorder = order })
    end
    while true do
      skip_ws()
      if s:sub(pos, pos) ~= '"' then fail("expected key") end
      local key = parse_string()
      skip_ws()
      if s:sub(pos, pos) ~= ":" then fail("expected :") end
      pos = pos + 1
      local v = parse_value()
      if obj[key] == nil then order[#order + 1] = key end
      obj[key] = v
      skip_ws()
      local c = s:sub(pos, pos)
      pos = pos + 1
      if c == "}" then break elseif c ~= "," then fail("expected , or }") end
    end
    return setmetatable(obj, { __jsonorder = order })
  end

  parse_value = function()
    skip_ws()
    local c = s:sub(pos, pos)
    if c == '"' then return parse_string()
    elseif c == "[" then return parse_array()
    elseif c == "{" then return parse_object()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return M.null
    else return parse_number()
    end
  end

  local v = parse_value()
  skip_ws()
  if pos <= #s then fail("trailing data") end
  return v
end

-- ── Encoding (JSON.stringify semantics) ─────────────────────────────────────

local function quote(str)
  return '"' .. str:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\b" then return "\\b" end
    if c == "\f" then return "\\f" end
    if c == "\n" then return "\\n" end
    if c == "\r" then return "\\r" end
    if c == "\t" then return "\\t" end
    local b = c:byte()
    if b < 0x20 then return string.format("\\u%04x", b) end
    return c  -- DEL (0x7f) is not escaped by JSON.stringify
  end):gsub('\xED[\xA0-\xBF][\x80-\xBF]', function(w)
    -- A lone UTF-16 surrogate held as WTF-8 (as decode_ordered keeps one):
    -- JSON.stringify writes it as a lowercase \udxxx escape.
    local b1, b2 = w:byte(2, 3)
    return string.format("\\u%04x", 0xD000 | ((b1 & 0x3F) << 6) | (b2 & 0x3F))
  end) .. '"'
end

local function is_sequence(t)
  local n = 0
  for k in pairs(t) do
    if math.type(k) ~= "integer" or k < 1 then return false end
    n = n + 1
  end
  return n > 0 and n == #t
end

--- Serialise like JavaScript JSON.stringify (no whitespace). Ordered objects
-- use their decoded key order; plain tables use sorted keys.
function M.stringify(v)
  local t = type(v)
  if v == nil or v == M.null then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if math.type(v) == "integer" then return tostring(v) end
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v == math.floor(v) and math.abs(v) < 1e21 then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if t == "string" then return quote(v) end
  if t == "table" then
    if M.is_array(v) or is_sequence(v) then
      local parts = {}
      for i = 1, #v do parts[i] = M.stringify(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local order = M.key_order(v)
    if not order then
      order = {}
      for k in pairs(v) do order[#order + 1] = tostring(k) end
      table.sort(order)
    end
    local parts = {}
    for _, k in ipairs(order) do
      if v[k] ~= nil then parts[#parts + 1] = quote(k) .. ":" .. M.stringify(v[k]) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "null"
end

-- ── Frozen v2 hash ──────────────────────────────────────────────────────────

--- h = (Math.imul(31, h) + charCodeAt(i)) >>> 0 over the UTF-16 code units
-- of s (UTF-8 input), as 8 lowercase hex digits (LTX-SPECIFICATION.md §4.3).
function M.imul31_hex(s)
  local h = 0
  local function add(unit) h = (h * 31 + unit) & 0xFFFFFFFF end
  for _, cp in utf8.codes(s, true) do  -- lax: a WTF-8 lone surrogate is one unit
    if cp >= 0x10000 then
      local x = cp - 0x10000
      add(0xD800 + (x >> 10))
      add(0xDC00 + (x & 0x3FF))
    else
      add(cp)
    end
  end
  return string.format("%08x", h)
end

return M
