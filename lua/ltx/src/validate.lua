-- validate.lua -- plan validation (LTX-SPECIFICATION.md §3.5, §4, §7)
--
-- Mirrors validatePlan / _reservedFieldErrors / _assertNoReservedFields in
-- javascript/ltx/ltx-sdk.js. validate_plan(plan) is pure and never raises:
-- it returns { valid = bool, errors = { { code, path, message }, ... } }.
--
-- Error codes: not_an_object, invalid_version, missing_field, invalid_field,
-- invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
-- duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
-- invalid_delays, reserved_streams, reserved_branching.
--
-- Lua note: a key whose value is nil is absent (JS `undefined`); JSON null
-- from src/json.lua is the json.null sentinel, which counts as present.

local json = require("src.json")

local M = {}

local SEG_TYPES = { "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE" }
M.PLAN_SEGMENT_TYPES = { "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
                         "SPEAK", "REST", "PAD", "OPEN", "RELAY" }
M.PLAN_MODES = { "LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC" }
M.V3_ONLY_FIELDS = { "delays", "planVersion", "prevPlanHash", "questions", "actions", "streams" }
local RESERVED_BRANCH_PLAN_FIELDS = { "branches", "branching" }
local RESERVED_BRANCH_SEGMENT_FIELDS = { "branch" }
local RESERVED_STREAM_SEGMENT_FIELDS = { "stream" }
local NODE_ROLES = { "HOST", "PARTICIPANT", "OBSERVER" }
M.SEG_TYPES = SEG_TYPES

local function contains(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function is_object(t)
  return type(t) == "table" and t ~= json.null and not json.is_array(t)
end

-- JS Array.isArray: a table marked as array, or a Lua sequence (an empty
-- unmarked table counts as an empty array).
local function is_array(t)
  if type(t) ~= "table" or t == json.null then return false end
  if json.is_array(t) then return true end
  if json.key_order(t) then return false end
  local n = 0
  for k in pairs(t) do
    if math.type(k) ~= "integer" or k < 1 then return false end
    n = n + 1
  end
  return n == #t
end

-- Number.isInteger
local function is_integer(v)
  return type(v) == "number" and v == math.floor(v) and v == v and v ~= math.huge and v ~= -math.huge
end

local function err(errors, code, path, message)
  errors[#errors + 1] = { code = code, path = path, message = message }
end

--- Reserved-field violations only (§3.5 streams, §7 branching).
function M.reserved_field_errors(plan)
  local errors = {}
  if type(plan) ~= "table" then return errors end
  if plan.streams ~= nil and not (is_array(plan.streams) and #plan.streams == 0) then
    err(errors, "reserved_streams", "streams", "streams[] is reserved (§3.5) and MUST be absent or empty")
  end
  for _, f in ipairs(RESERVED_BRANCH_PLAN_FIELDS) do
    if plan[f] ~= nil then
      err(errors, "reserved_branching", f,
        f .. " is reserved for branching (§7, not yet implemented) and MUST be absent")
    end
  end
  if is_array(plan.segments) then
    for i, s in ipairs(plan.segments) do
      if is_object(s) then
        for _, f in ipairs(RESERVED_STREAM_SEGMENT_FIELDS) do
          if s[f] ~= nil then
            err(errors, "reserved_streams", "segments[" .. (i - 1) .. "]." .. f,
              "segment " .. f .. " is reserved (§3.5) and MUST be absent")
          end
        end
        for _, f in ipairs(RESERVED_BRANCH_SEGMENT_FIELDS) do
          if s[f] ~= nil then
            err(errors, "reserved_branching", "segments[" .. (i - 1) .. "]." .. f,
              "segment " .. f .. " is reserved for branching (§7) and MUST be absent")
          end
        end
      end
    end
  end
  return errors
end

--- Raise if a plan uses reserved stream/branch fields. The error value is a
-- table { code = first code, errors = all errors, message = string } with a
-- __tostring, so pcall callers can read err.code.
function M.assert_no_reserved_fields(plan, fn_name)
  local errors = M.reserved_field_errors(plan)
  if #errors == 0 then return end
  error(setmetatable({
    code = errors[1].code,
    errors = errors,
    message = fn_name .. ": " .. errors[1].message,
  }, { __tostring = function(e) return e.message end }), 2)
end

-- Date.parse(...) is finite: ISO 8601 date or date-time (optional fraction
-- and Z / ±hh:mm offset).
local function valid_timestamp(s)
  if type(s) ~= "string" then return false end
  local y, mo, d, rest = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
  if not y then return false end
  mo, d = tonumber(mo), tonumber(d)
  if mo < 1 or mo > 12 or d < 1 or d > 31 then return false end
  if rest == "" then return true end
  local h, mi, tail = rest:match("^T(%d%d):(%d%d)(.*)$")
  if not h or tonumber(h) > 24 or tonumber(mi) > 59 then return false end
  tail = tail:gsub("^:%d%d", ""):gsub("^%.%d+", "")
  return tail == "" or tail == "Z" or tail:match("^[+-]%d%d:%d%d$") ~= nil
end

--- Validate a v2 or v3 plan. Pure; never raises.
function M.validate_plan(plan)
  local errors = {}
  if not is_object(plan) then
    err(errors, "not_an_object", "", "plan must be an object")
    return { valid = false, errors = errors }
  end
  if plan.v ~= 2 and plan.v ~= 3 then err(errors, "invalid_version", "v", "v must be 2 or 3") end
  for _, f in ipairs({ "title", "start", "quantum", "mode", "nodes", "segments" }) do
    if plan[f] == nil then err(errors, "missing_field", f, f .. " is required") end
  end
  if plan.title ~= nil and type(plan.title) ~= "string" then
    err(errors, "invalid_field", "title", "title must be a string")
  end
  if plan.start ~= nil and not valid_timestamp(plan.start) then
    err(errors, "invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
  end
  if plan.quantum ~= nil and not (is_integer(plan.quantum) and plan.quantum >= 1 and plan.quantum <= 60) then
    err(errors, "invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")
  end
  if plan.mode ~= nil and not contains(M.PLAN_MODES, plan.mode) then
    err(errors, "invalid_mode", "mode", "mode must be one of " .. table.concat(M.PLAN_MODES, ", "))
  end

  local ids, n_ids = {}, 0
  if plan.nodes ~= nil then
    if not is_array(plan.nodes) or #plan.nodes == 0 then
      err(errors, "invalid_nodes", "nodes", "nodes must be a non-empty array")
    else
      local hosts = 0
      for i, n in ipairs(plan.nodes) do
        if not is_object(n) or type(n.id) ~= "string" or n.id == "" or n.id:find("|", 1, true)
            or type(n.name) ~= "string" or not contains(NODE_ROLES, n.role)
            or type(n.delay) ~= "number" or not (n.delay >= 0) then
          err(errors, "invalid_nodes", "nodes[" .. (i - 1) .. "]",
            'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0')
        else
          if ids[n.id] then
            err(errors, "duplicate_node_id", "nodes[" .. (i - 1) .. "].id", "duplicate node id " .. n.id)
          else
            n_ids = n_ids + 1
          end
          ids[n.id] = true
          if n.role == "HOST" then hosts = hosts + 1 end
        end
      end
      local h = plan.nodes[1]
      if hosts ~= 1 or not is_object(h) or h.role ~= "HOST" or h.delay ~= 0 then
        err(errors, "invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")
      end
    end
  end

  if plan.segments ~= nil then
    if not is_array(plan.segments) then
      err(errors, "invalid_segment", "segments", "segments must be an array")
    else
      for i, s in ipairs(plan.segments) do
        if not is_object(s) or not contains(M.PLAN_SEGMENT_TYPES, s.type)
            or not (is_integer(s.q) and s.q >= 1) then
          err(errors, "invalid_segment", "segments[" .. (i - 1) .. "]",
            "segment needs a known type and integer q >= 1")
        elseif s.speaker ~= nil and not ids[s.speaker] then
          err(errors, "unknown_speaker", "segments[" .. (i - 1) .. "].speaker",
            "speaker " .. tostring(s.speaker) .. " is not a node id")
        end
      end
    end
  end

  if plan.v == 2 then
    for _, f in ipairs(M.V3_ONLY_FIELDS) do
      if plan[f] ~= nil then
        err(errors, "v3_field_in_v2", f, f .. " is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
      end
    end
  elseif plan.v == 3 then
    if plan.delays ~= nil then
      local d = plan.delays
      if not is_object(d) or (next(d) ~= nil and is_array(d)) then
        err(errors, "invalid_delays", "delays", "delays must be an object")
      else
        local keys = json.key_order(d)
        if not keys then
          keys = {}
          for k in pairs(d) do keys[#keys + 1] = k end
          table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        end
        for _, k in ipairs(keys) do
          local a, b = tostring(k):match("^([^|]*)|([^|]*)$")
          local val = d[k]
          if not a or not (a < b) or (n_ids > 0 and (not ids[a] or not ids[b]))
              or type(val) ~= "number" or not (val >= 0) then
            err(errors, "invalid_delays", "delays." .. tostring(k),
              'key must be two known node ids joined by "|" in sorted order; value >= 0 (§3.7.2)')
          end
        end
      end
    end
    if plan.planVersion ~= nil and not (is_integer(plan.planVersion) and plan.planVersion >= 1) then
      err(errors, "invalid_field", "planVersion", "planVersion must be an integer >= 1")
    end
    if plan.prevPlanHash ~= nil and not (type(plan.prevPlanHash) == "string"
        and #plan.prevPlanHash == 64 and plan.prevPlanHash:match("^[0-9a-f]+$")) then
      err(errors, "invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")
    end
    for _, f in ipairs({ "questions", "actions" }) do
      if plan[f] ~= nil and not is_array(plan[f]) then
        err(errors, "invalid_field", f, f .. " must be an array")
      end
    end
  end

  for _, e in ipairs(M.reserved_field_errors(plan)) do errors[#errors + 1] = e end
  return { valid = #errors == 0, errors = errors }
end

return M
