-- v11_test.lua -- LTX v1.1 core subset conformance tests (Epic 72.4)
-- Verifies the five cascade features against conformance/vectors.json (.v11).

package.path = package.path .. ';./?.lua;./src/?.lua;../?.lua;../src/?.lua'

local LTX = require('src.interplanet_ltx')
local SEC = require('src.security')
local ED = require('src.ed25519')
local V11 = require('src.v11')

local passed = 0
local failed = 0

local function ok(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print('FAIL: ' .. tostring(msg))
  end
end

local function eq(a, b, msg)
  ok(a == b, (msg or '') .. '  expected=' .. tostring(b) .. '  got=' .. tostring(a))
end

-- ---- Load the golden vectors ----

local function load_vectors()
  local f = io.open('../../../conformance/vectors.json', 'rb')
  if not f then return nil end
  local txt = f:read('a')
  f:close()
  local root = LTX.json_decode(txt)
  return root and root.v11 or nil
end

local v11 = load_vectors()
ok(v11 ~= nil, 'conformance/vectors.json v11 section loaded')
if not v11 then
  print('\n0 passed, 1 failed')
  os.exit(1)
end

local vec_nik = {
  node_id = v11.key.nik.nodeId,
  public_key_b64 = v11.key.nik.publicKey,
  expires_at = v11.key.nik.validUntil,
}

-- ---- Ed25519 primitive (RFC 8032 known-answer + vector key) ----

local sha_abc = SEC.sha256_hex('abc')
eq(sha_abc, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  'sha256_hex known answer')
local sha512_abc = (ED.sha512('abc'):gsub('.', function(c)
  return string.format('%02x', string.byte(c))
end))
eq(sha512_abc,
  'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
    .. '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
  'sha512 known answer')

-- ---- 1. v3 planId + v2 regression ----

ok(SEC.canonical_json(v11.planIdV3.plan) == v11.planIdV3.canonicalJson,
  'v3 plan canonical JSON matches vector')
eq(SEC.sha256_hex(SEC.canonical_json(v11.planIdV3.plan)), v11.planIdV3.sha256,
  'v3 plan canonical sha256 matches vector')
eq(LTX.make_plan_id(v11.planIdV3.plan), v11.planIdV3.expectedPlanId,
  'make_plan_id v3')
eq(LTX.make_plan_id(v11.planIdV2Regression.plan),
  v11.planIdV2Regression.expectedPlanId,
  'FROZEN v2 planId regression')

-- ---- 2. pair_delay + compute_segments_for ----

local pd_plan = v11.pairDelay.plan
for _, case in ipairs(v11.pairDelay.cases) do
  eq(V11.pair_delay(pd_plan, case.a, case.b), case.expected,
    'pair_delay(' .. case.a .. ',' .. case.b .. ')')
end
local fb = v11.pairDelay.fallbackCase
eq(V11.pair_delay(fb.plan, fb.a, fb.b), fb.expected, 'pair_delay fallback')
local unknown_delay, unknown_err = V11.pair_delay(fb.plan, 'N1', 'N9')
ok(unknown_delay == nil and unknown_err ~= nil, 'pair_delay unknown node errors')

local segs_n2 = V11.compute_segments_for(pd_plan, 'N2')
ok(segs_n2 ~= nil and #segs_n2 == 4, 'compute_segments_for 4 segments')
eq(segs_n2[1].perspective, 'neutral', 'PLAN_CONFIRM neutral for N2')
eq(segs_n2[1].arrival_offset_s, 0, 'neutral segment no offset')
eq(segs_n2[2].perspective, 'receive', 'N0 TX received by N2')
eq(segs_n2[2].arrival_offset_s, 2, 'N0->N2 offset 2s (HOST row)')
eq(segs_n2[3].perspective, 'receive', 'N1 TX received by N2')
eq(segs_n2[3].arrival_offset_s, 500, 'N1->N2 offset 500s (pair matrix)')
eq(segs_n2[3].start_iso, '2040-02-01T12:33:20Z',
  'receive segment start shifted by pair delay (12:25:00 + 500s)')
eq(segs_n2[3].speaker, 'N1', 'viewer segment keeps speaker')
eq(segs_n2[3].label, 'Mars Report', 'viewer segment keeps label')
local segs_n1 = V11.compute_segments_for(pd_plan, 'N1')
eq(segs_n1[3].perspective, 'transmit', 'own TX is transmit')
eq(segs_n1[3].arrival_offset_s, 0, 'transmit segment no offset')
eq(segs_n1[3].start_iso, '2040-02-01T12:25:00Z', 'transmit segment unshifted')
local bad_viewer, bad_viewer_err = V11.compute_segments_for(pd_plan, 'N9')
ok(bad_viewer == nil and bad_viewer_err ~= nil,
  'compute_segments_for unknown viewer errors')

-- ---- 3. Amendment-chain verify ----

local key_cache = {}
key_cache[vec_nik.node_id] = vec_nik

local chain = v11.amendmentChain.chain
eq(V11.plan_hash(chain[1].plan), v11.amendmentChain.rootPlanHash,
  'plan_hash(root) matches vector rootPlanHash')
local link_ok, link_reason = V11.verify_plan_envelope(chain[1], key_cache)
ok(link_ok, 'root envelope verifies (' .. tostring(link_reason) .. ')')
local chain_ok, chain_reason = V11.verify_amendment_chain(chain, key_cache)
ok(chain_ok, 'amendment chain verifies (' .. tostring(chain_reason) .. ')')

-- Tampering the amended link's title must break the chain.
local f2 = io.open('../../../conformance/vectors.json', 'rb')
local tampered_root = LTX.json_decode(f2:read('a'))
f2:close()
local tampered_chain = tampered_root.v11.amendmentChain.chain
tampered_chain[2].plan.title = 'Tampered Summit'
local tampered_ok, tampered_reason = V11.verify_amendment_chain(tampered_chain, key_cache)
ok(not tampered_ok, 'tampered amendment chain rejected (' .. tostring(tampered_reason) .. ')')

-- Envelope verification failure modes.
local no_key_ok, no_key_reason = V11.verify_plan_envelope(chain[1], {})
ok(not no_key_ok and no_key_reason == 'key_not_in_cache',
  'envelope with unknown kid rejected')
local expired_cache = {}
expired_cache[vec_nik.node_id] = {
  node_id = vec_nik.node_id,
  public_key_b64 = vec_nik.public_key_b64,
  expires_at = '2000-01-01T00:00:00Z',
}
local expired_ok, expired_reason = V11.verify_plan_envelope(chain[1], expired_cache)
ok(not expired_ok and expired_reason == 'key_expired', 'expired key rejected')

-- ---- 4. Register entries + reducers + entries_root ----

local reg_cache = { N0 = vec_nik, N1 = vec_nik }
for _, entry in ipairs(v11.registerEntries.entries) do
  local e_ok, e_reason = V11.verify_register_entry(entry, reg_cache)
  ok(e_ok, 'register entry ' .. entry.entryId .. ' verifies ('
    .. tostring(e_reason) .. ')')
end

local f3 = io.open('../../../conformance/vectors.json', 'rb')
local tampered_entries = LTX.json_decode(f3:read('a')).v11.registerEntries.entries
f3:close()
tampered_entries[1].content.text = 'Tampered?'
local te_ok, te_reason = V11.verify_register_entry(tampered_entries[1], reg_cache)
ok(not te_ok and te_reason == 'signature_invalid', 'tampered register entry rejected')

local reduced = V11.reduce_questions(v11.registerEntries.entries)
eq(SEC.canonical_json(reduced.by_id),
  SEC.canonical_json(v11.registerEntries.expectedQuestionState),
  'reduce_questions state matches vector')
eq(#reduced.superseded, 0, 'no superseded entries in vector')

-- Order-insensitivity: reversed input produces identical state.
local reversed = {}
for i = #v11.registerEntries.entries, 1, -1 do
  reversed[#reversed + 1] = v11.registerEntries.entries[i]
end
eq(SEC.canonical_json(V11.reduce_questions(reversed).by_id),
  SEC.canonical_json(reduced.by_id),
  'reduce_questions is input-order independent')

eq(V11.entries_root(v11.registerEntries.entries), v11.registerEntries.entriesRoot,
  'entries_root matches vector')
eq(V11.entries_root(reversed), v11.registerEntries.entriesRoot,
  'entries_root input-order independent')

-- reduce_actions basics (no signing in the Lua port; reduce an unsigned
-- envelope shape directly).
local action_entries = {
  {
    entryId = 'ACT-N1-9', sessionId = 'S', nodeId = 'N1', seq = 9,
    type = 'action', content = { description = 'Do the thing', owner = 'N0' },
    timestamp = '2040-02-01T11:20:00.000Z',
  },
  {
    entryId = 'ACT-N0-9', sessionId = 'S', nodeId = 'N0', seq = 9,
    type = 'action_update',
    content = { aid = 'ACT-N1-9', status = 'ACCEPTED', version = 2 },
    timestamp = '2040-02-01T11:25:00.000Z',
  },
}
local actions = V11.reduce_actions(action_entries)
eq(actions.by_id['ACT-N1-9'].status, 'ACCEPTED', 'reduce_actions applies update')
eq(actions.by_id['ACT-N1-9'].version, 2, 'reduce_actions version bump')
eq(actions.by_id['ACT-N1-9'].owner, 'N0', 'reduce_actions keeps owner')

-- §8.2 conflict rule: same version, lowest editor nodeId wins.
local conflict_entries = {
  action_entries[1],
  {
    entryId = 'ACT-N2-1', sessionId = 'S', nodeId = 'N2', seq = 1,
    type = 'action_update',
    content = { aid = 'ACT-N1-9', status = 'REJECTED', version = 2 },
    timestamp = '2040-02-01T11:30:00.000Z',
  },
  action_entries[2],  -- N0, version 2, later timestamp but lower nodeId
}
local conflict = V11.reduce_actions(conflict_entries)
eq(conflict.by_id['ACT-N1-9'].status, 'ACCEPTED',
  'conflict rule: tie resolves to lowest editor nodeId')
eq(#conflict.superseded, 1, 'conflict rule: loser flagged superseded')

-- ---- 5. CBOR decode + COSE_Sign1 verify ----

local cose_envelope = {
  plan = v11.coseSign1.plan,
  coseSign1CborB64 = v11.coseSign1.coseSign1CborB64,
}
local cose_ok, cose_reason = V11.verify_plan_cose(cose_envelope, key_cache)
eq(cose_ok, v11.coseSign1.expectedValid,
  'COSE_Sign1 vector verifies (' .. tostring(cose_reason) .. ')')

local cbor_bytes = SEC.b64u_decode(v11.coseSign1.coseSign1CborB64)
local hex = (cbor_bytes:gsub('.', function(c)
  return string.format('%02x', string.byte(c))
end))
eq(hex, v11.coseSign1.coseSign1CborHex, 'CBOR b64 == hex vector')

local decoded_cose = V11.cbor_decode(cbor_bytes)
ok(decoded_cose ~= nil and decoded_cose.tag == 18, 'CBOR decodes to tag 18')
eq(V11.cbor_encode(decoded_cose), cbor_bytes, 'CBOR deterministic re-encode roundtrip')
eq(V11.cbor_encode({ map = { { 1, -19 } } }), '\161\1\50', 'CBOR {1:-19} == a10132')

local _, trailing_err = V11.cbor_decode('\1\2')
ok(trailing_err == 'cbor: trailing bytes', 'CBOR trailing bytes rejected')
local _, float_err = V11.cbor_decode('\249\60\0')
ok(float_err ~= nil, 'CBOR floats rejected')
local _, indef_err = V11.cbor_decode('\159\1\255')
ok(indef_err ~= nil, 'CBOR indefinite length rejected')

local f4 = io.open('../../../conformance/vectors.json', 'rb')
local tampered_cose_plan = LTX.json_decode(f4:read('a')).v11.coseSign1.plan
f4:close()
tampered_cose_plan.title = 'X'
local ct_ok, ct_reason = V11.verify_plan_cose({
  plan = tampered_cose_plan,
  coseSign1CborB64 = v11.coseSign1.coseSign1CborB64,
}, key_cache)
ok(not ct_ok and ct_reason == 'payload_mismatch', 'COSE tampered plan rejected')
local cnk_ok, cnk_reason = V11.verify_plan_cose(cose_envelope, {})
ok(not cnk_ok and cnk_reason == 'key_not_in_cache', 'COSE unknown key rejected')

-- ---- 6. transition() state machine (golden table) ----

local sm = v11.stateMachine
eq(LTX.make_plan_id(sm.plan), sm.planId, 'state machine planId matches vector')
local ctx = V11.create_session(sm.plan, sm.planId, { quorum = sm.quorum })
eq(ctx.state, 'DRAFT', 'create_session starts DRAFT')
ok(ctx.lock == nil, 'create_session lock nil')
eq(ctx.lock_timeout_ms, 1800000, 'lock timeout 2 x max delay')
local steps_ok = true
for i, step in ipairs(sm.steps) do
  local result = V11.transition(ctx, step.event)
  ctx = result.ctx
  -- step.expectLock is JSON null (absent) for no lock.
  if ctx.state ~= step.expectState or ctx.lock ~= step.expectLock then
    steps_ok = false
    print(string.format('  state machine step %d: got (%s, %s) expected (%s, %s)',
      i, ctx.state, tostring(ctx.lock), tostring(step.expectState),
      tostring(step.expectLock)))
  end
end
ok(steps_ok, 'golden transition table replay (' .. #sm.steps .. ' steps)')
ok(ctx.subset == nil, 'subset cleared after late full-lock recovery')
eq(#ctx.degraded_reasons, 2, 'two degraded reasons logged')
ok(ctx.degraded_reasons[1]:find('[N0,N2]', 1, true) ~= nil,
  'quorum subset [N0,N2] recorded at degrade time')

local after_end = V11.transition(ctx, { type = 'SESSION_START', nowMs = 6000000 })
eq(after_end.ctx.state, 'COMPLETE', 'invalid event ignored in COMPLETE')
ok(after_end.effects[1] and after_end.effects[1].code == 'INVALID_EVENT',
  'invalid event emits INVALID_EVENT')

-- EOK override + resume + amendment path (not covered by the golden table).
local eok = V11.create_session(sm.plan, sm.planId, { quorum = 'all' })
eok = V11.transition(eok, { type = 'START_LOCK', nowMs = 0 }).ctx
for _, nid in ipairs({ 'N1', 'N2' }) do
  eok = V11.transition(eok, {
    type = 'PLAN_CONFIRM', nowMs = 1, nodeId = nid, planId = sm.planId,
  }).ctx
end
eq(eok.state, 'LOCKED', 'full lock with quorum=all')
eq(eok.lock, 'FULL', 'full lock kind FULL')
eok = V11.transition(eok, { type = 'SESSION_START', nowMs = 2 }).ctx
eok = V11.transition(eok, { type = 'EOK_OVERRIDE', nowMs = 3, verified = true }).ctx
eq(eok.state, 'EMERGENCY_HOLD', 'verified EOK holds session')
eok = V11.transition(eok, { type = 'HOST_DECISION', nowMs = 4, decision = 'resume' }).ctx
eq(eok.state, 'ACTIVE', 'HOST resume returns to prior state')
local rejected = V11.transition(eok, { type = 'EOK_OVERRIDE', nowMs = 5, verified = false })
eq(rejected.ctx.state, 'ACTIVE', 'unverified EOK ignored')
ok(rejected.effects[1] and rejected.effects[1].code == 'OVERRIDE_REJECTED',
  'unverified EOK emits OVERRIDE_REJECTED')
eok = V11.transition(eok, {
  type = 'AMENDMENT_PROPOSED', nowMs = 6, planId = 'PLAN-2',
  planVersion = 2, affectedNodeIds = { 'N1' },
}).ctx
eok = V11.transition(eok, {
  type = 'AMENDMENT_CONFIRMED', nowMs = 7, nodeId = 'N1', planId = 'PLAN-2',
}).ctx
eq(eok.plan_id, 'PLAN-2', 'amendment applied: planId swapped')
eq(eok.plan_version, 2, 'amendment applied: planVersion bumped')
eok = V11.transition(eok, { type = 'HOST_DECISION', nowMs = 8, decision = 'abort' }).ctx
eq(eok.state, 'ABORTED', 'HOST abort')

-- ---- Results ----

print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
