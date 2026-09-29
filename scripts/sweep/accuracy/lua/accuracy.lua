-- Accuracy harness for lua/planet-time (see ../gen-cases-group2.js).
-- Run from lua/planet-time:
--   lua ../../scripts/sweep/accuracy/lua/accuracy.lua ../../scripts/sweep/accuracy/instants-group2.txt
package.path = package.path .. ";./?.lua"
local IPT = require("src.interplanet_time")

local bodies = {
  { "mercury", IPT.MERCURY }, { "venus", IPT.VENUS }, { "earth", IPT.EARTH },
  { "mars", IPT.MARS }, { "jupiter", IPT.JUPITER }, { "saturn", IPT.SATURN },
  { "uranus", IPT.URANUS }, { "neptune", IPT.NEPTUNE }, { "moon", IPT.MOON },
}
local function b(v) return v and 1 or 0 end
local function i(v) return string.format("%d", v) end

local out = {}
for line in io.lines(arg[1]) do
  local ms = math.tointeger(tonumber(line))
  if ms then
    for _, pair in ipairs(bodies) do
      local name, idx = pair[1], pair[2]
      local pt = IPT.planet_time(idx, ms)
      local lt = IPT.light_travel_time(idx, IPT.EARTH, ms)
      out[#out + 1] = table.concat({ i(ms), name, i(pt.hour), i(pt.minute), i(pt.second),
        i(pt.day_number), i(pt.day_in_year), i(pt.year_number), i(pt.period_in_week),
        b(pt.is_work_period), b(pt.is_work_hour), string.format("%.6f", lt) }, "\t")
      if idx == IPT.MARS then
        local m = pt.mtc
        out[#out + 1] = table.concat({ i(ms), "mtc", i(m.sol), i(m.hour), i(m.minute), i(m.second) }, "\t")
      end
    end
  end
end
io.write(table.concat(out, "\n"), "\n")
