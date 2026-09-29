-- parity_test.lua -- LTX parity with the JS reference SDK (issue #27).
-- Mirrors javascript/ltx/tests/run.js: golden planId vectors, validatePlan +
-- reserved fields, reduceDecisions, buildDelayMatrix via pairDelay.
-- Run from lua/ltx: lua test/parity_test.lua

package.path = package.path .. ';./?.lua;./src/?.lua;../?.lua;../src/?.lua'

local LTX = require('src.interplanet_ltx')
local SEC = require('src.security')
local V11 = require('src.v11')
local JSON = require('src.json')
local VAL = require('src.validate')

local passed, failed = 0, 0
local function ok(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print('FAIL: ' .. tostring(msg)) end
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return setmetatable(out, getmetatable(t))
end
local function with(t, k, v) local c = copy(t); c[k] = v; return c end
local function codes(r)
  local set = {}
  for _, e in ipairs(r.errors) do set[e.code] = true end
  return set
end

-- ── Conformance: golden planId vectors (spec/golden/plan-ids.json) ────────

local f = assert(io.open('../../spec/golden/plan-ids.json', 'rb'))
local golden = JSON.decode_ordered(f:read('a'))
f:close()

ok(#golden.vectors >= 9, 'golden vectors present')
local by_name = {}
for _, gv in ipairs(golden.vectors) do
  by_name[gv.name] = gv
  ok(LTX.make_plan_id(gv.plan) == gv.planId, 'golden planId ' .. gv.name .. ' got ' .. LTX.make_plan_id(gv.plan))
  if gv.planHash ~= nil then
    ok(V11.plan_hash(gv.plan) == gv.planHash, 'golden planHash ' .. gv.name)
  end
end
ok(by_name['v2-freeze-check'].planId == 'LTX-20260801-EARTHHQ-MARS-v2-d132e85d', 'golden v2 freeze anchor')
ok(by_name['v2-unicode-title'].planId == 'LTX-20261231-EARTHHQ-MARS-v2-7bc93af8', 'golden v2 unicode anchor')
ok(by_name['v2-createPlan-default'].planId ~= by_name['v2-key-order-sensitive'].planId, 'golden v2 order-sensitive')
ok(by_name['v3-upgrade-delays'].planId == by_name['v3-key-order-insensitive'].planId, 'golden v3 order-insensitive')
ok(by_name['v3-amendment'].plan.prevPlanHash == by_name['v3-upgrade-delays'].planHash, 'golden v3 amendment chain hash')
ok(LTX.create_plan({}).quantum == 5, 'create_plan default quantum is 5')
-- Plain create_plan tables hash in schema order (nodes before segments), so the
-- default plan matches the v2-key-order-sensitive vector.
local sp = LTX.make_plan_id(LTX.create_plan({ title = 'Golden Default', start = '2026-03-15T14:00:00.000Z', delay = 840 }))
ok(sp == by_name['v2-key-order-sensitive'].planId, 'create_plan planId = golden v2-key-order-sensitive, got ' .. sp)
ok(LTX.plan_id_from_json(JSON.stringify(by_name['v2-relay'].plan)) == by_name['v2-relay'].planId,
  'plan_id_from_json matches golden v2-relay')
ok(JSON.stringify(JSON.decode_ordered('{"b":1,"a":[true,null,"x\\"y"],"e":[]}')) == '{"b":1,"a":[true,null,"x\\"y"],"e":[]}',
  'json stringify preserves order, null, escapes, empty array')

-- ── Plan validation: reserved streams / branching (§3.5, §7) ──────────────

for _, gv in ipairs(golden.vectors) do
  ok(VAL.validate_plan(gv.plan).valid == true, 'validate_plan accepts golden ' .. gv.name)
end
local vp_base = by_name['v3-upgrade-delays'].plan
local vp_v2 = by_name['v2-freeze-check'].plan
ok(VAL.validate_plan(with(vp_base, 'streams', JSON.array({}))).valid == true, 'validate_plan v3 empty streams ok')
local vp_streams = VAL.validate_plan(with(vp_base, 'streams', { { id = 'S1' } }))
ok(vp_streams.valid == false and codes(vp_streams).reserved_streams, 'validate_plan non-empty streams')
local sp
for _, e in ipairs(vp_streams.errors) do if e.code == 'reserved_streams' then sp = e.path; break end end
ok(sp == 'streams', 'validate_plan streams error path')
ok(codes(VAL.validate_plan(with(vp_base, 'streams', 'S1'))).reserved_streams, 'validate_plan streams non-array')
ok(codes(VAL.validate_plan(with(vp_base, 'segments', { { type = 'TX', q = 1, stream = 'S1' } }))).reserved_streams,
  'validate_plan segment stream')
ok(codes(VAL.validate_plan(with(vp_base, 'branches', {}))).reserved_branching, 'validate_plan branches')
ok(codes(VAL.validate_plan(with(vp_base, 'branching', { mode = 'local' }))).reserved_branching, 'validate_plan branching')
local vp_seg_branch = VAL.validate_plan(with(vp_base, 'segments', { { type = 'CAUCUS', q = 1, branch = 'B1' } }))
ok(codes(vp_seg_branch).reserved_branching and vp_seg_branch.errors[1].path == 'segments[0].branch',
  'validate_plan segment branch')
ok(codes(VAL.validate_plan(with(vp_v2, 'streams', {}))).v3_field_in_v2, 'validate_plan v2 streams is v3 field')
ok(codes(VAL.validate_plan(with(vp_v2, 'branching', true))).reserved_branching, 'validate_plan v2 branching')
ok(codes(VAL.validate_plan(nil)).not_an_object, 'validate_plan non-object')
ok(codes(VAL.validate_plan(with(vp_v2, 'v', 7))).invalid_version, 'validate_plan bad version')
ok(codes(VAL.validate_plan(with(vp_v2, 'nodes', { vp_v2.nodes[2], vp_v2.nodes[1] }))).invalid_host,
  'validate_plan host not first')
ok(codes(VAL.validate_plan(with(vp_base, 'delays', { ['N1|N0'] = 860 }))).invalid_delays,
  'validate_plan unsorted delays key')
ok(codes(VAL.validate_plan(with(vp_v2, 'segments', { { type = 'TX', q = 1, speaker = 'N9' } }))).unknown_speaker,
  'validate_plan unknown speaker')
ok(codes(VAL.validate_plan(with(vp_v2, 'quantum', 0))).invalid_quantum, 'validate_plan quantum out of range')
ok(codes(VAL.validate_plan(with(vp_v2, 'title', nil))).missing_field, 'validate_plan missing title')
ok(codes(VAL.validate_plan(with(vp_v2, 'mode', 'CHAT'))).invalid_mode, 'validate_plan bad mode')
ok(codes(VAL.validate_plan(with(vp_v2, 'nodes', { vp_v2.nodes[1], vp_v2.nodes[2], vp_v2.nodes[2] }))).duplicate_node_id,
  'validate_plan duplicate node id')
ok(codes(VAL.validate_plan(with(vp_base, 'prevPlanHash', 'ABC'))).invalid_field, 'validate_plan bad prevPlanHash')
ok(LTX.validate_plan(LTX.create_plan({ start = '2026-03-15T14:00:00.000Z' })).valid == true,
  'validate_plan accepts create_plan output')

-- Enforcement paths raise with a code
local function throws_code(fn, ...)
  local good, e = pcall(fn, ...)
  if good then return nil end
  return type(e) == 'table' and e.code or tostring(e)
end
ok(throws_code(V11.upgrade_plan_to_v3, vp_v2, { streams = { { id = 'S1' } } }) == 'reserved_streams',
  'upgrade_plan_to_v3 rejects streams')
ok(throws_code(V11.upgrade_plan_to_v3, vp_v2, { streams = JSON.array({}) }) == nil, 'upgrade_plan_to_v3 allows empty')
ok(throws_code(V11.upgrade_plan_to_v3, vp_v2, { branches = {} }) == 'reserved_branching',
  'upgrade_plan_to_v3 rejects branches')
ok(throws_code(V11.create_session, with(vp_base, 'streams', { 1 }), 'id') == 'reserved_streams',
  'create_session rejects streams')
ok(throws_code(V11.create_session, vp_base, 'id') == nil, 'create_session accepts golden')
local up3 = V11.upgrade_plan_to_v3(vp_v2, { delays = { ['N0|N1'] = 900 } })
ok(up3.v == 3 and up3.planVersion == 1 and up3.delays['N0|N1'] == 900 and vp_v2.v == 2,
  'upgrade_plan_to_v3 result, input not mutated')

-- ── Decision register (§10.3) ─────────────────────────────────────────────
-- Lua has no signing, so entries are built unsigned; reducers do not verify.

local function mk(type_, content, node_id, seq, ts, entry_id)
  return { entryId = entry_id or ('DEC-' .. node_id .. '-' .. seq), sessionId = 'LTX-DEC-TEST',
           nodeId = node_id, seq = seq, type = type_, content = content, timestamp = ts }
end
local dec1 = mk('decision', { text = 'Proceed with EVA-3', rationale = 'Weather window', originWindow = 'W2' },
  'N0', 1, '2026-08-01T12:00:00.000Z')
local d1 = V11.reduce_decisions({ dec1 }).by_id['DEC-N0-1']
ok(d1.status == 'RECORDED' and d1.version == 1, 'decision RECORDED')
ok(d1.text == 'Proceed with EVA-3' and d1.recordedBy == 'N0' and d1.rationale == 'Weather window', 'decision fields')
local dec_rev = mk('decision_update', { did = 'DEC-N0-1', text = 'Proceed with EVA-3 at 14:00', version = 2 },
  'N1', 1, '2026-08-01T12:10:00.000Z')
local dec_res = mk('decision_update', { did = 'DEC-N0-1', status = 'RESCINDED', version = 3 },
  'N0', 2, '2026-08-01T12:20:00.000Z')
local reg2 = V11.reduce_decisions({ dec_res, dec1, dec_rev })
local d2 = reg2.by_id['DEC-N0-1']
ok(d2.text == 'Proceed with EVA-3 at 14:00', 'decision update applied')
ok(d2.status == 'RESCINDED' and d2.version == 3, 'decision RESCINDED v3')
ok(d2.editor == 'N0', 'decision editor recorded')
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
ok(has(reg2.superseded, dec_rev.entryId), 'decision older update superseded')
local dec_a = mk('decision_update', { did = 'DEC-N0-1', text = 'From N0', version = 5 }, 'N0', 7, '2026-08-01T13:00:00.000Z')
local dec_b = mk('decision_update', { did = 'DEC-N0-1', text = 'From N1', version = 5 }, 'N1', 7, '2026-08-01T13:00:00.000Z')
local conf1 = V11.reduce_decisions({ dec1, dec_b, dec_a })
local conf2 = V11.reduce_decisions({ dec_a, dec1, dec_b })
ok(conf1.by_id['DEC-N0-1'].text == 'From N0', 'decision tie lowest nodeId wins')
ok(has(conf1.superseded, dec_b.entryId) and not has(conf1.superseded, dec_a.entryId), 'decision tie loser superseded')
ok(SEC.canonical_json(conf1) == SEC.canonical_json(conf2), 'decision reduce order-independent')
local dec_hi = mk('decision_update', { did = 'DEC-N0-1', text = 'N1 v6', version = 6 }, 'N1', 8, '2026-08-01T12:30:00.000Z')
ok(V11.reduce_decisions({ dec1, dec_a, dec_hi }).by_id['DEC-N0-1'].text == 'N1 v6', 'decision higher version wins')
local dec_orphan = mk('decision_update', { did = 'DEC-NOPE-1', version = 2 }, 'N1', 9, '2026-08-01T12:40:00.000Z')
local dec_dup = mk('decision', { text = 'dup' }, 'N1', 10, '2026-08-01T12:50:00.000Z', 'DEC-N0-1')
local reg3 = V11.reduce_decisions({ dec1, dec_orphan, dec_dup })
ok(has(reg3.superseded, 'DEC-N1-9'), 'decision orphan update superseded')
ok(reg3.by_id['DEC-N0-1'].text == 'Proceed with EVA-3' and reg3.by_id['DEC-N0-1'].recordedBy == 'N0',
  'decision duplicate create ignored')
local n_dec = 0
for _ in pairs(V11.reduce_decisions({ dec1, dec_rev }).by_id) do n_dec = n_dec + 1 end
ok(n_dec == 1 and next(V11.reduce_actions({ dec1 }).by_id) == nil, 'decision reducer ignores others')

-- ── buildDelayMatrix (§3.7): sum via HOST for non-HOST pairs ──────────────

local dm_plan = {
  v = 2, title = 'Delay Matrix', start = '2026-06-01T12:00:00.000Z', quantum = 5, mode = 'LTX-ASYNC',
  segments = { { type = 'TX', q = 1 } },
  nodes = {
    { id = 'N0', name = 'Earth HQ',    role = 'HOST',        delay = 0,    location = 'earth' },
    { id = 'N1', name = 'Mars Hab-01', role = 'PARTICIPANT', delay = 1240, location = 'mars' },
    { id = 'N2', name = 'Jupiter Obs', role = 'PARTICIPANT', delay = 3240, location = 'jupiter' },
    { id = 'N3', name = 'Earth Annex', role = 'PARTICIPANT', delay = 0,    location = 'earth' },
  },
}
local function dm_get(m, a, b)
  for _, p in ipairs(m) do if p.from_id == a and p.to_id == b then return p.delay_seconds end end
end
local dm = LTX.build_delay_matrix(dm_plan)
ok(#dm == 12, 'delay matrix n*(n-1) pairs')
ok(dm_get(dm, 'N0', 'N1') == 1240 and dm_get(dm, 'N1', 'N0') == 1240, 'delay matrix HOST to node')
ok(dm_get(dm, 'N1', 'N2') == 1240 + 3240, 'delay matrix non-HOST pair = sum')
ok(dm_get(dm, 'N1', 'N2') ~= math.max(1240, 3240), 'delay matrix not max')
local sym, eq_pd = true, true
for _, p in ipairs(dm) do
  if p.delay_seconds ~= dm_get(dm, p.to_id, p.from_id) then sym = false end
  if p.delay_seconds ~= V11.pair_delay(dm_plan, p.from_id, p.to_id) then eq_pd = false end
end
ok(sym, 'delay matrix symmetric')
ok(dm_get(dm, 'N3', 'N2') == 3240 and dm_get(dm, 'N3', 'N0') == 0, 'delay matrix zero-delay non-HOST')
ok(eq_pd, 'delay matrix equals pair_delay')
local dm3 = LTX.build_delay_matrix(V11.upgrade_plan_to_v3(dm_plan, { delays = { ['N1|N2'] = 2900 } }))
ok(dm_get(dm3, 'N1', 'N2') == 2900 and dm_get(dm3, 'N2', 'N1') == 2900, 'delay matrix v3 entry authoritative')
ok(dm_get(dm3, 'N1', 'N3') == 1240, 'delay matrix v3 fallback sum')

-- ── Wire order = hash order (issue #32) ─────────────────────────────────────
-- encode_hash must transmit a plain v2 table in the key order make_plan_id
-- hashes, so a receiver hashing the wire JSON derives the same planId.
local wp = LTX.create_plan({
  title = 'Réunion Mars 🚀', start = '2026-03-15T14:00:00Z',
  nodes = {
    { id = 'N0', name = 'Earth HQ', role = 'HOST', delay = 0, location = 'earth' },
    { id = 'N1', name = 'Mars Hab-01', role = 'PARTICIPANT', delay = 840, location = 'mars' },
  },
  segments = { { type = 'TX', q = 2, speaker = 'N0', label = 'Ouverture' }, { type = 'RX', q = 2 } },
})
local wire = LTX.wire_json(wp)
ok(wire:sub(1, 12) == '{"v":2,"titl', 'wire JSON in schema key order')
ok(LTX.make_plan_id(wp) == 'LTX-20260315-EARTHHQ-MARS-v2-4987df52', 'typed v2 planId matches JS')
ok(LTX.plan_id_from_json(wire) == LTX.make_plan_id(wp), 'planId of wire JSON equals make_plan_id')
local decoded = LTX.decode_hash(LTX.encode_hash(wp))
ok(decoded and decoded.segments[1].label == 'Ouverture', 'encode_hash round-trips')
local wv3 = V11.upgrade_plan_to_v3(wp, { delays = { ['N0|N1'] = 842 } })
ok(LTX.plan_id_from_json(LTX.wire_json(wv3)) == LTX.make_plan_id(wv3), 'v3 planId of wire JSON equals make_plan_id')

print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
