# test/security_test.exs — Epic 29 security tests for InterplanetLtx (Elixir)
# Run with: elixir -r test/test_helper.exs test/security_test.exs

Code.require_file("../lib/interplanet_ltx/constants.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/models.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/interplanet_ltx.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/security.ex", __DIR__)

import Test

alias InterplanetLtx.Security

# ── 1. canonical_json_key_order ───────────────────────────────────────────────

a = Security.canonical_json(%{"b" => 1, "a" => 2})
b = Security.canonical_json(%{"a" => 2, "b" => 1})
check a == b,                       "canonical_json: same output regardless of insertion order"
check a == "{\"a\":2,\"b\":1}",     "canonical_json: keys sorted, correct format"

check Security.canonical_json(42)   == "42",    "canonical_json integer"
check Security.canonical_json("hi") == "\"hi\"","canonical_json string"
check Security.canonical_json(true) == "true",  "canonical_json true"
check Security.canonical_json(nil)  == "null",  "canonical_json null"
check Security.canonical_json([1, 2]) == "[1,2]","canonical_json array"

nested = Security.canonical_json(%{"z" => %{"b" => 1, "a" => 2}})
check nested == "{\"z\":{\"a\":2,\"b\":1}}", "canonical_json nested map sorted"

# ── 2. generate_nik_fields ────────────────────────────────────────────────────

result = Security.generate_nik(valid_days: 365, node_label: "test-node")
nik    = result.nik

check is_binary(nik["nodeId"]),               "generate_nik: nodeId is string"
check String.length(nik["nodeId"]) > 0,       "generate_nik: nodeId non-empty"
check is_binary(nik["publicKey"]),            "generate_nik: publicKey is string"
check String.length(nik["publicKey"]) > 0,   "generate_nik: publicKey non-empty"
check nik["algorithm"] == "Ed25519",          "generate_nik: algorithm is Ed25519"
check nik["keyVersion"] == 1,                 "generate_nik: keyVersion is 1"
check nik["label"] == "test-node",            "generate_nik: label stored"
check is_binary(result.private_key_b64),      "generate_nik: private_key_b64 is string"
check String.length(result.private_key_b64) > 0, "generate_nik: private_key_b64 non-empty"

# Two NIKs should have different node IDs
result2 = Security.generate_nik()
check result.nik["nodeId"] != result2.nik["nodeId"], "generate_nik: unique nodeIds"

# ── 3. is_nik_expired_false ───────────────────────────────────────────────────

future_nik = %{"validUntil" => "2099-12-31T23:59:59.000Z"}
check Security.is_nik_expired(future_nik) == false, "is_nik_expired: future date -> false"

fresh_result = Security.generate_nik(valid_days: 365)
check Security.is_nik_expired(fresh_result.nik) == false, "is_nik_expired: fresh NIK not expired"

# ── 4. is_nik_expired_true ────────────────────────────────────────────────────

past_nik = %{"validUntil" => "2000-01-01T00:00:00.000Z"}
check Security.is_nik_expired(past_nik) == true, "is_nik_expired: past date -> true"

expired_nik = %{"validUntil" => "1970-01-01T00:00:00.000Z"}
check Security.is_nik_expired(expired_nik) == true, "is_nik_expired: epoch -> true"

# ── 5. sign_verify_roundtrip ──────────────────────────────────────────────────

nik_result = Security.generate_nik(valid_days: 365)
test_plan  = %{"v" => 2, "title" => "Test Session", "start" => "2099-01-01T00:00:00Z"}

# Pass the pub_key_b64 so kid can be derived correctly
signed = Security.sign_plan(test_plan, nik_result.private_key_b64, nik_result.nik["publicKey"])

check is_map(signed), "sign_plan: returns map"
check is_map(signed.coseSign1), "sign_plan: coseSign1 present"
check is_binary(signed.coseSign1["signature"]), "sign_plan: signature is string"
check is_binary(signed.coseSign1["payload"]),   "sign_plan: payload is string"
check is_binary(signed.coseSign1["protected"]), "sign_plan: protected is string"

# The kid should match the nodeId in the NIK
kid = signed.coseSign1["unprotected"]["kid"]
check kid == nik_result.nik["nodeId"], "sign_plan: kid matches nodeId"

key_cache = %{nik_result.nik["nodeId"] => nik_result.nik}
result_v  = Security.verify_plan(signed, key_cache)

check result_v.valid == true,             "verify_plan: roundtrip valid"
check Map.get(result_v, :reason) == nil,  "verify_plan: no reason on success"

# ── 6. sign_verify_tampered ───────────────────────────────────────────────────

nik_result2 = Security.generate_nik(valid_days: 365)
test_plan2  = %{"v" => 2, "title" => "Original Plan", "start" => "2099-01-01T00:00:00Z"}

signed2  = Security.sign_plan(test_plan2, nik_result2.private_key_b64, nik_result2.nik["publicKey"])
tampered = Map.put(signed2, :plan, %{"v" => 2, "title" => "TAMPERED!", "start" => "2099-01-01T00:00:00Z"})

key_cache2 = %{nik_result2.nik["nodeId"] => nik_result2.nik}
result_t   = Security.verify_plan(tampered, key_cache2)

check result_t.valid == false,              "verify_plan: tampered plan invalid"
check result_t.reason == "payload_mismatch","verify_plan: reason=payload_mismatch"

# ── 7. sign_verify_wrong_key ──────────────────────────────────────────────────

nik_result3 = Security.generate_nik(valid_days: 365)
test_plan3  = %{"v" => 2, "title" => "Plan", "start" => "2099-01-01T00:00:00Z"}
signed3     = Security.sign_plan(test_plan3, nik_result3.private_key_b64, nik_result3.nik["publicKey"])

# Empty key cache
result_wk = Security.verify_plan(signed3, %{})
check result_wk.valid == false,            "verify_plan: empty cache invalid"
check result_wk.reason == "key_not_in_cache","verify_plan: reason=key_not_in_cache"

# Wrong kid in cache (different node's NIK keyed by signer's nodeId)
wrong_nik    = Security.generate_nik(valid_days: 365)
wrong_cache  = %{nik_result3.nik["nodeId"] => wrong_nik.nik}
result_wk2   = Security.verify_plan(signed3, wrong_cache)
check result_wk2.valid == false, "verify_plan: wrong key in cache invalid"

# ── 8. sequence_tracker_replay ────────────────────────────────────────────────

tracker = Security.new_sequence_tracker("plan-001")

b1 = Security.add_seq(%{data: "hello"}, tracker, "N0")
check b1[:seq] == 1, "add_seq: first seq is 1"

b2 = Security.add_seq(%{data: "world"}, tracker, "N0")
check b2[:seq] == 2, "add_seq: second seq is 2"

# Receive b1 (seq=1) — accepted
r1 = Security.check_seq(b1, tracker, "N0")
check r1.accepted == true, "check_seq: first message accepted"
check r1.gap == false,     "check_seq: no gap on seq 1"
check r1.gap_size == 0,    "check_seq: gap_size 0"

# Replay b1 — rejected
r2 = Security.check_seq(b1, tracker, "N0")
check r2.accepted == false,  "check_seq: replay rejected"
check r2.reason == "replay", "check_seq: reason=replay"

# b2 in order
r3 = Security.check_seq(b2, tracker, "N0")
check r3.accepted == true,  "check_seq: seq 2 accepted"
check r3.gap == false,      "check_seq: no gap"

# seq=5 — gap of 2
b5 = %{data: "skip", seq: 5}
r4 = Security.check_seq(b5, tracker, "N0")
check r4.accepted == true, "check_seq: gap accepted"
check r4.gap == true,      "check_seq: gap detected"
check r4.gap_size == 2,    "check_seq: gap_size=2"

# N1 independent counter
b1_n1 = Security.add_seq(%{data: "from N1"}, tracker, "N1")
check b1_n1[:seq] == 1, "add_seq: N1 starts at 1"

# ── 9. key_expired ────────────────────────────────────────────────────────────

nik_r4    = Security.generate_nik(valid_days: 365)
test_p4   = %{"v" => 2, "title" => "P4", "start" => "2099-01-01T00:00:00Z"}
signed4   = Security.sign_plan(test_p4, nik_r4.private_key_b64, nik_r4.nik["publicKey"])

expired2    = Map.put(nik_r4.nik, "validUntil", "2000-01-01T00:00:00.000Z")
exp_cache   = %{nik_r4.nik["nodeId"] => expired2}
result_exp  = Security.verify_plan(signed4, exp_cache)
check result_exp.valid == false,           "verify_plan: expired key invalid"
check result_exp.reason == "key_expired",  "verify_plan: reason=key_expired"

# ── Summary ───────────────────────────────────────────────────────────────────

passed = Process.get(:passed, 0)
failed = Process.get(:failed, 0)
IO.puts("\n#{passed} passed  #{failed} failed")
if failed > 0, do: System.halt(1)
