-- Interop driver for lua/ltx (see scripts/interop/run.js).
-- Run from lua/ltx so that require("src.*") resolves: lua driver.lua IN OUT
local in_dir, out_dir = arg[1], arg[2]
local LTX = require("src.interplanet_ltx")
local V11 = require("src.v11")

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local function b64url_decode(s)
  local out, acc, bits = {}, 0, 0
  for i = 1, #s do
    local v = B64:find(s:sub(i, i), 1, true)
    if not v then break end
    acc = (acc << 6) | (v - 1)
    bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      out[#out + 1] = string.char((acc >> bits) & 0xFF)
    end
  end
  return table.concat(out)
end

local function write(name, data)
  local f = assert(io.open(out_dir .. "/" .. name, "wb"))
  f:write(data)
  f:close()
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local plan = LTX.create_plan({
  title = "Réunion Mars 🚀",
  start = "2026-03-15T14:00:00.000Z",
  quantum = 3,
  mode = "LTX-ASYNC",
  nodes = {
    { id = "N0", name = "Earth HQ", role = "HOST", delay = 0, location = "earth" },
    { id = "N1", name = "Mars Hab-01", role = "PARTICIPANT", delay = 840, location = "mars" },
    { id = "N2", name = "L-1 Gateway", role = "PARTICIPANT", delay = 2, location = "moon" },
  },
  segments = {
    { type = "PLAN_CONFIRM", q = 2 },
    { type = "TX", q = 3, speaker = "N0", label = "Ouverture: état de la mission" },
    { type = "RX", q = 3 },
    { type = "TX", q = 2, speaker = "N1", label = "Réponse 🔴" },
    { type = "BUFFER", q = 1 },
  },
})

write("wire-v2.json", b64url_decode(LTX.encode_hash(plan):sub(4)))
print("ID_V2 " .. LTX.make_plan_id(plan))

local v3 = V11.upgrade_plan_to_v3(plan, { delays = { ["N1|N2"] = 842 } })
write("wire-v3.json", b64url_decode(LTX.encode_hash(v3):sub(4)))
print("ID_V3 " .. LTX.make_plan_id(v3))
print("NOTE v3 via v11.upgrade_plan_to_v3; wire via encode_hash")

for _, v in ipairs({ "2", "3", "P" }) do
  print("JS_V" .. v .. " " .. LTX.plan_id_from_json(read(in_dir .. "/js-v" .. v .. ".json")))
end
