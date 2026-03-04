-- security_test.lua -- Epic 29, Stories 29.1 / 29.4 / 29.5

package.path = package.path .. ';../?.lua;../src/?.lua;./src/?.lua;./?.lua'
local SEC = require('security')

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

-- ---- Story 29.1: canonical_json ----

eq(SEC.canonical_json({}), '{}', 'empty object')
eq(SEC.canonical_json({z=1, a=2}), '{"a":2,"z":1}', 'sorted keys')
eq(SEC.canonical_json({1,2,3}), '[1,2,3]', 'array')
eq(SEC.canonical_json(42), '42', 'number')
eq(SEC.canonical_json(true), 'true', 'boolean')
eq(SEC.canonical_json('hi'), '"hi"', 'string')
eq(SEC.canonical_json(nil), 'null', 'nil->null')

-- nested object
local nested = SEC.canonical_json({b={y=9,x=1}, a=3})
ok(nested == '{"a":3,"b":{"x":1,"y":9}}', 'nested sorted keys: ' .. nested)

-- ---- Story 29.1: generate_nik ----

local nik = SEC.generate_nik()
ok(nik ~= nil, 'generate_nik returns table')
eq(nik.key_type, 'ltx-nik-v1', 'key_type')
ok(nik.node_id ~= nil and #nik.node_id > 0, 'node_id non-empty')
ok(nik.kid ~= nil and #nik.kid > 0, 'kid non-empty')
ok(nik.public_key_b64 ~= nil and #nik.public_key_b64 > 0, 'pub key non-empty')
ok(nik.private_key_b64 ~= nil and #nik.private_key_b64 > 0, 'priv key non-empty')
ok(nik.issued_at ~= nil, 'issued_at set')
ok(nik.expires_at ~= nil, 'expires_at set')

-- node_id length: 16 raw bytes -> 22 base64url chars
ok(#nik.node_id == 22, 'node_id is 22 chars (16 bytes b64u): ' .. #nik.node_id)

-- custom label and validity
local nik2 = SEC.generate_nik({valid_days=30, node_label='TestNode'})
eq(nik2.node_label, 'TestNode', 'node_label preserved')
ok(nik2.expires_at > nik2.issued_at, 'expires_at after issued_at')

-- two NIKs must have different node_ids
local nik3 = SEC.generate_nik()
ok(nik.node_id ~= nik3.node_id, 'unique node_ids')

-- ---- Story 29.1: is_nik_expired ----

ok(not SEC.is_nik_expired(nik), 'fresh nik not expired')

local expired_nik = {expires_at = '2000-01-01T00:00:00Z'}
ok(SEC.is_nik_expired(expired_nik), 'old nik is expired')

ok(SEC.is_nik_expired(nil), 'nil nik is expired')
ok(SEC.is_nik_expired({}), 'nik with no expires_at is expired')

-- ---- Story 29.4: sign_plan / verify_plan ----

local plan = {planId='p1', startAt='2026-05-01T00:00:00Z', quantum=60}
local sp = SEC.sign_plan(plan, nik.private_key_b64, nik.public_key_b64, nik.kid)
ok(sp ~= nil, 'sign_plan returns table')
ok(sp.coseSign1 ~= nil, 'coseSign1 present')
ok(sp.coseSign1.protected ~= nil, 'protected header present')
ok(sp.coseSign1.signature ~= nil, 'signature present')
eq(sp.coseSign1.unprotected.kid, nik.kid, 'kid in unprotected header')

-- verify with matching key cache
local cache = {}
cache[nik.kid] = nik
local ok1, reason1 = SEC.verify_plan(sp, cache)
eq(ok1, true, 'verify ok')
eq(reason1, 'ok', 'reason is ok')

-- verify fails: key not in cache
local ok2, reason2 = SEC.verify_plan(sp, {})
eq(ok2, false, 'verify fails empty cache')
eq(reason2, 'key_not_in_cache', 'reason key_not_in_cache')

-- verify fails: key expired
local old_cache = {}
old_cache[nik.kid] = {expires_at = '2000-01-01T00:00:00Z', private_key_b64 = nik.private_key_b64}
local ok3, reason3 = SEC.verify_plan(sp, old_cache)
eq(ok3, false, 'verify fails expired key')
eq(reason3, 'key_expired', 'reason key_expired')

-- verify fails: payload mismatch
local tampered = {
  plan = {planId='TAMPERED', startAt='2026-05-01T00:00:00Z', quantum=60},
  coseSign1 = sp.coseSign1,
}
local ok4, reason4 = SEC.verify_plan(tampered, cache)
eq(ok4, false, 'verify fails tampered plan')
eq(reason4, 'payload_mismatch', 'reason payload_mismatch')

-- sign_plan with missing args returns nil
local sp_nil, err_nil = SEC.sign_plan(nil, nik.private_key_b64)
eq(sp_nil, nil, 'sign_plan nil plan returns nil')

-- ---- Story 29.5: SequenceTracker ----

local st = SEC.new_sequence_tracker('plan-x')
ok(st ~= nil, 'tracker created')
eq(st.plan_id, 'plan-x', 'plan_id stored')

-- first seq is always accepted
local r1, m1 = SEC.add_seq(st, 'alice', 1)
eq(r1, true, 'first seq accepted')
eq(m1, 'ok', 'first seq message ok')

-- next seq accepted
local r2, m2 = SEC.add_seq(st, 'alice', 2)
eq(r2, true, 'seq 2 accepted')
eq(m2, 'ok', 'seq 2 message ok')

-- replay (same seq)
local r3, m3 = SEC.add_seq(st, 'alice', 2)
eq(r3, false, 'replay rejected')
eq(m3, 'replay', 'replay reason')

-- gap
local r4, m4 = SEC.add_seq(st, 'alice', 10)
eq(r4, true, 'gap accepted')
eq(m4, 'gap', 'gap reason')

-- check_seq (read-only)
local c1, _ = SEC.check_seq(st, 'alice', 10)
eq(c1, false, 'check_seq replay same')
local c2, _ = SEC.check_seq(st, 'alice', 11)
eq(c2, true, 'check_seq next ok')
local c3, m = SEC.check_seq(st, 'alice', 20)
eq(c3, true, 'check_seq gap')
eq(m, 'gap', 'check_seq gap reason')

-- independent peers
local rb, mb = SEC.add_seq(st, 'bob', 5)
eq(rb, true, 'bob first seq ok')
eq(mb, 'ok', 'bob first seq message')

-- ---- Results ----

print(string.format('\n%d passed, %d failed', passed, failed))
if failed > 0 then os.exit(1) end
