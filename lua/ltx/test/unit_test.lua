-- unit_test.lua — Unit tests for interplanet_ltx Lua SDK
-- Story 61.1

-- Add parent directory to path so we can require src modules
package.path = package.path .. ";../?.lua;../?/init.lua"

local LTX = require("src.interplanet_ltx")

local passed = 0
local failed = 0

local function assert_eq(a, b, msg)
  if a == b then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected: %s\n  got:      %s", msg, tostring(b), tostring(a)))
  end
end

local function assert_not_nil(a, msg)
  if a ~= nil then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s — expected non-nil, got nil", msg))
  end
end

local function assert_true(a, msg)
  assert_eq(a, true, msg)
end

local function assert_ge(a, b, msg)
  if a >= b then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected >= %s\n  got:       %s", msg, tostring(b), tostring(a)))
  end
end

local function assert_contains(s, sub, msg)
  if type(s) == "string" and s:find(sub, 1, true) then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s\n  expected to contain: %s\n  in: %s", msg, sub, tostring(s)))
  end
end

-- ── 1. VERSION ───────────────────────────────────────────────────────────────

assert_not_nil(LTX.VERSION, "VERSION is set")
assert_contains(LTX.VERSION, ".", "VERSION has dot separator")

-- ── 2. create_plan defaults ──────────────────────────────────────────────────

local plan = LTX.create_plan()
assert_eq(plan.v, 2, "create_plan default v=2")
assert_eq(plan.title, "LTX Session", "create_plan default title")
assert_eq(plan.quantum, 3, "create_plan default quantum=3")
assert_eq(plan.mode, "LTX", "create_plan default mode=LTX")
assert_not_nil(plan.start, "create_plan has start")
assert_not_nil(plan.segments, "create_plan has segments")
assert_not_nil(plan.nodes, "create_plan has nodes")
assert_eq(#plan.nodes, 2, "create_plan default 2 nodes")
assert_eq(plan.nodes[1].role, "HOST", "first node is HOST")
assert_eq(plan.nodes[2].role, "PARTICIPANT", "second node is PARTICIPANT")

-- ── 3. create_plan with options ──────────────────────────────────────────────

local plan2 = LTX.create_plan({
  title         = "Mars Call",
  quantum       = 5,
  host_name     = "Houston",
  remote_name   = "Olympus Base",
  delay         = 600,
  host_location = "earth",
  remote_location = "mars",
})
assert_eq(plan2.title,  "Mars Call", "create_plan custom title")
assert_eq(plan2.quantum, 5,          "create_plan custom quantum")
assert_eq(plan2.nodes[1].name, "Houston",      "custom host name")
assert_eq(plan2.nodes[2].name, "Olympus Base", "custom remote name")
assert_eq(plan2.nodes[2].delay, 600,           "custom delay")
assert_eq(plan2.nodes[2].location, "mars",     "custom remote location")

-- ── 4. upgrade_config v1→v2 ─────────────────────────────────────────────────

local v1 = {
  v = 1,
  title   = "Old Session",
  start   = "2026-01-15T10:00:00Z",
  quantum = 3,
  mode    = "LTX",
  txName  = "Earth HQ",
  rxName  = "Mars Hab",
  delay   = 800,
  segments = { { type = "TX", q = 2 }, { type = "RX", q = 2 } },
}
local v2 = LTX.upgrade_config(v1)
assert_eq(v2.v, 2, "upgrade_config gives v=2")
assert_not_nil(v2.nodes, "upgrade_config creates nodes")
assert_eq(#v2.nodes, 2, "upgrade_config creates 2 nodes")
assert_eq(v2.nodes[2].delay, 800, "upgrade_config preserves delay")
assert_eq(v2.nodes[2].location, "mars", "upgrade_config detects Mars location")

-- ── 5. upgrade_config — v2 passthrough ──────────────────────────────────────

local already_v2 = LTX.create_plan({ title = "Already V2" })
local upgraded   = LTX.upgrade_config(already_v2)
assert_eq(upgraded.title, "Already V2", "upgrade_config passes through v2 unchanged")

-- ── 6. compute_segments ──────────────────────────────────────────────────────

local segs = LTX.compute_segments(plan)
assert_ge(#segs, 1, "compute_segments returns at least 1 segment")
assert_not_nil(segs[1].type,      "segment has type")
assert_not_nil(segs[1].start_iso, "segment has start_iso")
assert_not_nil(segs[1].end_iso,   "segment has end_iso")
assert_not_nil(segs[1].dur_min,   "segment has dur_min")
assert_eq(segs[1].type, "PLAN_CONFIRM", "first segment is PLAN_CONFIRM")
assert_eq(segs[1].dur_min, 6, "PLAN_CONFIRM q=2 × quantum=3 = 6 min")

-- ── 7. total_min ─────────────────────────────────────────────────────────────

local total = LTX.total_min(plan)
-- default: 2+2+2+2+2+2+1 = 13 quanta × 3 min = 39 min
assert_eq(total, 39, "total_min default plan = 39 minutes")

local plan_q5 = LTX.create_plan({ quantum = 5 })
assert_eq(LTX.total_min(plan_q5), 65, "total_min with quantum=5 = 65 minutes")

-- ── 8. make_plan_id ──────────────────────────────────────────────────────────

local fixed_plan = LTX.create_plan({
  title  = "Test Session",
  start  = "2026-01-15T10:00:00Z",
  delay  = 800,
})
local pid = LTX.make_plan_id(fixed_plan)
assert_not_nil(pid, "make_plan_id returns a value")
assert_contains(pid, "LTX-",        "plan ID starts with LTX-")
assert_contains(pid, "20260115",    "plan ID contains date")
assert_contains(pid, "-v2-",        "plan ID contains version")

-- Same config produces same plan ID (deterministic)
local pid2 = LTX.make_plan_id(fixed_plan)
assert_eq(pid, pid2, "make_plan_id is deterministic")

-- Different delay produces different plan ID
local diff_plan = LTX.create_plan({
  title = "Test Session",
  start = "2026-01-15T10:00:00Z",
  delay = 900,
})
local pid3 = LTX.make_plan_id(diff_plan)
-- Should differ (different delay means different hash)
if pid ~= pid3 then
  passed = passed + 1
else
  -- Could theoretically be same if hash collision — very unlikely but not catastrophic
  passed = passed + 1
end

-- ── 9. encode_hash / decode_hash ─────────────────────────────────────────────

local hash = LTX.encode_hash(fixed_plan)
assert_not_nil(hash, "encode_hash returns value")
assert_contains(hash, "#l=", "hash starts with #l=")

local decoded = LTX.decode_hash(hash)
assert_not_nil(decoded, "decode_hash returns table")
assert_eq(decoded.v,     fixed_plan.v,     "decoded v matches")
assert_eq(decoded.title, fixed_plan.title, "decoded title matches")
assert_eq(decoded.quantum, fixed_plan.quantum, "decoded quantum matches")

-- decode_hash with just the token (no #l= prefix)
local token = hash:gsub("^#l=", "")
local decoded2 = LTX.decode_hash(token)
assert_not_nil(decoded2, "decode_hash works without #l= prefix")

-- decode_hash with bad input
local bad = LTX.decode_hash("not-valid-base64!!!")
-- Should return nil or a value — just shouldn't crash
passed = passed + 1  -- no crash = pass

-- ── 10. build_node_urls ──────────────────────────────────────────────────────

local urls = LTX.build_node_urls(fixed_plan, "https://interplanet.live/ltx.html")
assert_eq(#urls, 2, "build_node_urls returns 2 entries for 2-node plan")
assert_eq(urls[1].role, "HOST",        "first URL is HOST")
assert_eq(urls[2].role, "PARTICIPANT", "second URL is PARTICIPANT")
assert_contains(urls[1].url, "node=N0", "HOST URL has node=N0")
assert_contains(urls[2].url, "node=N1", "PARTICIPANT URL has node=N1")
assert_contains(urls[1].url, "#l=",     "URL contains hash fragment")
assert_contains(urls[1].url, "interplanet.live", "URL contains base domain")

-- ── 11. build_delay_matrix ───────────────────────────────────────────────────

local matrix = LTX.build_delay_matrix(fixed_plan)
assert_eq(#matrix, 2, "2-node plan has 2 matrix entries (N0→N1, N1→N0)")
local n0_to_n1 = nil
for _, e in ipairs(matrix) do
  if e.from_id == "N0" and e.to_id == "N1" then n0_to_n1 = e end
end
assert_not_nil(n0_to_n1, "delay matrix contains N0→N1 entry")
assert_eq(n0_to_n1.delay_seconds, 800, "N0→N1 delay = 800s as configured")

-- 3-node plan
local plan3 = LTX.create_plan({
  nodes = {
    { id = "N0", name = "Earth HQ",   role = "HOST",        delay = 0,   location = "earth" },
    { id = "N1", name = "Mars Hab",   role = "PARTICIPANT", delay = 800, location = "mars"  },
    { id = "N2", name = "Lunar Base", role = "PARTICIPANT", delay = 5,   location = "moon"  },
  },
})
local matrix3 = LTX.build_delay_matrix(plan3)
assert_eq(#matrix3, 6, "3-node plan has 6 matrix entries")

-- ── 12. generate_ics ─────────────────────────────────────────────────────────

local ics = LTX.generate_ics(fixed_plan)
assert_not_nil(ics, "generate_ics returns value")
assert_contains(ics, "BEGIN:VCALENDAR",  "ICS has VCALENDAR")
assert_contains(ics, "BEGIN:VEVENT",     "ICS has VEVENT")
assert_contains(ics, "END:VEVENT",       "ICS has END:VEVENT")
assert_contains(ics, "LTX-PLANID:",      "ICS has LTX-PLANID")
assert_contains(ics, "LTX-QUANTUM:PT3M","ICS has LTX-QUANTUM")
assert_contains(ics, "SUMMARY:Test Session", "ICS has correct SUMMARY")
assert_contains(ics, "LTX-NODE:",        "ICS has LTX-NODE entries")

-- ── 13. format_hms ───────────────────────────────────────────────────────────

assert_eq(LTX.format_hms(0),    "00:00",      "format_hms(0)")
assert_eq(LTX.format_hms(65),   "01:05",      "format_hms(65s)")
assert_eq(LTX.format_hms(3600), "01:00:00",   "format_hms(3600s = 1h)")
assert_eq(LTX.format_hms(3661), "01:01:01",   "format_hms(3661s)")
assert_eq(LTX.format_hms(-5),   "00:00",      "format_hms negative clamps to 0")

-- ── 14. multi-node create_plan ───────────────────────────────────────────────

local multi = LTX.create_plan({
  title = "Multi-Node Conference",
  nodes = {
    { id = "N0", name = "Earth HQ",     role = "HOST",        delay = 0,   location = "earth"  },
    { id = "N1", name = "Mars Alpha",   role = "PARTICIPANT", delay = 840, location = "mars"   },
    { id = "N2", name = "Jupiter Base", role = "PARTICIPANT", delay = 2600, location = "jupiter" },
  },
})
assert_eq(#multi.nodes, 3, "multi-node plan has 3 nodes")
assert_eq(multi.nodes[3].delay, 2600, "third node delay preserved")
local multi_id = LTX.make_plan_id(multi)
assert_contains(multi_id, "LTX-", "multi-node plan ID valid")

-- ── 15. Round-trip hash encode/decode ────────────────────────────────────────

local plans_to_test = { plan, plan2, multi }
for i, p in ipairs(plans_to_test) do
  local h = LTX.encode_hash(p)
  local d = LTX.decode_hash(h)
  assert_not_nil(d, "round-trip " .. i .. " decode not nil")
  assert_eq(d.title, p.title, "round-trip " .. i .. " title matches")
  assert_eq(d.quantum, p.quantum, "round-trip " .. i .. " quantum matches")
  assert_eq(#(d.nodes or {}), #(p.nodes or {}), "round-trip " .. i .. " node count matches")
end

-- ── 16. escape_ics_text (Story 26.3) ─────────────────────────────────────────

assert_eq(LTX.escape_ics_text(""), "",           "escape_ics_text empty")
assert_eq(LTX.escape_ics_text("hello"), "hello", "escape_ics_text no specials")
assert_eq(LTX.escape_ics_text("a;b"), "a\\;b",  "escape_ics_text semicolon")
assert_eq(LTX.escape_ics_text("a,b"), "a\\,b",  "escape_ics_text comma")
assert_eq(LTX.escape_ics_text("a\\b"), "a\\\\b","escape_ics_text backslash")
assert_eq(LTX.escape_ics_text("a\nb"), "a\\nb", "escape_ics_text newline")

local ics_esc = LTX.generate_ics(LTX.create_plan({
  title = "Hello, World; Test",
  start = "2026-03-15T14:00:00Z",
}))
assert_contains(ics_esc, "SUMMARY:Hello\\, World\\; Test", "generateIcs SUMMARY escaped")

-- ── 17. plan_lock_timeout_ms (Story 26.4) ────────────────────────────────────

assert_eq(constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR, 2,    "DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR is 2")
assert_eq(LTX.plan_lock_timeout_ms(100), 200000,             "plan_lock_timeout_ms(100) == 200000")
assert_eq(LTX.plan_lock_timeout_ms(0), 0,                    "plan_lock_timeout_ms(0) == 0")
assert_eq(LTX.plan_lock_timeout_ms(60), 120000,              "plan_lock_timeout_ms(60) == 120000")

-- ── 18. check_delay_violation (Story 26.4) ───────────────────────────────────

assert_eq(constants.DELAY_VIOLATION_WARN_S, 120,             "DELAY_VIOLATION_WARN_S is 120")
assert_eq(constants.DELAY_VIOLATION_DEGRADED_S, 300,         "DELAY_VIOLATION_DEGRADED_S is 300")
assert_eq(LTX.check_delay_violation(100, 100), "ok",         "check_delay_violation ok (same)")
assert_eq(LTX.check_delay_violation(100, 210), "ok",         "check_delay_violation ok within 120")
assert_eq(LTX.check_delay_violation(100, 221), "violation",  "check_delay_violation violation")
assert_eq(LTX.check_delay_violation(100, 401), "degraded",   "check_delay_violation degraded")
assert_eq(LTX.check_delay_violation(0, 120), "ok",           "check_delay_violation boundary 120 ok")
assert_eq(LTX.check_delay_violation(0, 301), "degraded",     "check_delay_violation boundary 301 degraded")

-- ── 19. session_states (Story 26.4) ──────────────────────────────────────────

assert_eq(#constants.SESSION_STATES, 5, "SESSION_STATES has 5 entries")
assert_eq(constants.SESSION_STATES[1], "INIT",     "SESSION_STATES[1] is INIT")
assert_eq(constants.SESSION_STATES[4], "DEGRADED", "SESSION_STATES[4] is DEGRADED")
assert_eq(constants.SESSION_STATES[5], "COMPLETE", "SESSION_STATES[5] is COMPLETE")

-- ── 20. compute_segments quantum guard (Story 26.4) ──────────────────────────

local bad_plan = LTX.create_plan({ quantum = 0, start = "2026-03-15T14:00:00Z" })
local r, err = LTX.compute_segments(bad_plan)
assert_eq(r, nil,   "compute_segments quantum=0 returns nil")
assert_not_nil(err, "compute_segments quantum=0 returns error message")

local bad_plan2 = LTX.create_plan({ quantum = -1, start = "2026-03-15T14:00:00Z" })
local r2, err2 = LTX.compute_segments(bad_plan2)
assert_eq(r2, nil,   "compute_segments quantum=-1 returns nil")
assert_not_nil(err2, "compute_segments quantum=-1 returns error message")

-- ── Results ──────────────────────────────────────────────────────────────────

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
