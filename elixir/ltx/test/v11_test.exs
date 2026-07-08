# test/v11_test.exs — LTX v1.1 core subset tests (Epic 72, Story 72.5)
# Verified against the shared golden vectors: conformance/vectors.json §v11.
# Run with: elixir -r test/test_helper.exs test/v11_test.exs

Code.require_file("../lib/interplanet_ltx/constants.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/models.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/interplanet_ltx.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/security.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/segments.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/session.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/amend.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/registers.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/cbor.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/cose.ex", __DIR__)

import Test

alias InterplanetLtx.Amend
alias InterplanetLtx.Cbor
alias InterplanetLtx.Cose
alias InterplanetLtx.Registers
alias InterplanetLtx.Security
alias InterplanetLtx.Segments
alias InterplanetLtx.Session

# ── Load golden vectors ───────────────────────────────────────────────────────

vectors_path = Path.expand("../../../../conformance/vectors.json", __DIR__)
v11 = File.read!(vectors_path) |> JSON.decode!() |> Map.fetch!("v11")

key = v11["key"]
nik = key["nik"]
seed_b64 = key["privateSeedB64"]

# ── 1. v3 planId + v2 regression ─────────────────────────────────────────────

pid3 = v11["planIdV3"]
plan3 = pid3["plan"]

check Security.canonical_json(plan3) == pid3["canonicalJson"],
      "v11 planIdV3: canonical JSON matches vector"

sha = :crypto.hash(:sha256, Security.canonical_json(plan3)) |> Base.encode16(case: :lower)
check sha == pid3["sha256"], "v11 planIdV3: SHA-256 matches vector"

check Segments.make_plan_id(plan3) == pid3["expectedPlanId"],
      "v11 planIdV3: #{pid3["expectedPlanId"]}"

pid2 = v11["planIdV2Regression"]
check Segments.make_plan_id(pid2["plan"]) == pid2["expectedPlanId"],
      "v11 planIdV2 FROZEN regression: #{pid2["expectedPlanId"]}"
check InterplanetLtx.make_plan_id(pid2["plan"]) == pid2["expectedPlanId"],
      "v11 planIdV2 FROZEN regression via legacy make_plan_id"

# ── 2. pairDelay ─────────────────────────────────────────────────────────────

pd = v11["pairDelay"]

for case_ <- pd["cases"] do
  got = Segments.pair_delay(pd["plan"], case_["a"], case_["b"])
  check got == case_["expected"],
        "v11 pairDelay #{case_["a"]}|#{case_["b"]} = #{case_["expected"]} (got #{got})"
end

fb = pd["fallbackCase"]
check Segments.pair_delay(fb["plan"], fb["a"], fb["b"]) == fb["expected"],
      "v11 pairDelay fallback #{fb["a"]}|#{fb["b"]} = #{fb["expected"]}"

# ── 3. computeSegmentsFor ────────────────────────────────────────────────────

segs_n2 = Segments.compute_segments_for(pd["plan"], "N2")
check length(segs_n2) == 4, "computeSegmentsFor: 4 segments"

seg_n0 = Enum.at(segs_n2, 1)  # TX speaker N0 viewed by N2: receive, shift 2s
check seg_n0.perspective == "receive", "computeSegmentsFor: N0 TX is receive for N2"
check seg_n0.arrival_offset_s == 2, "computeSegmentsFor: HOST pair delay 2s applied"

seg_n1 = Enum.at(segs_n2, 2)  # TX speaker N1 viewed by N2: v3 matrix 500s
check seg_n1.arrival_offset_s == 500, "computeSegmentsFor: v3 delays matrix 500s applied"

seg_tx = Segments.compute_segments_for(pd["plan"], "N1") |> Enum.at(2)
check seg_n1.start_ms - seg_tx.start_ms == 500_000,
      "computeSegmentsFor: receive start shifted by pairDelay ms"
check seg_tx.perspective == "transmit" and seg_tx.arrival_offset_s == 0,
      "computeSegmentsFor: speaker sees own TX as transmit, unshifted"

seg_neutral = Enum.at(segs_n2, 0)
check seg_neutral.perspective == "neutral" and seg_neutral.arrival_offset_s == 0,
      "computeSegmentsFor: unattributed segment neutral"

# ── 4. Amendment chain ───────────────────────────────────────────────────────

am = v11["amendmentChain"]
chain = am["chain"]
key_cache = %{nik["nodeId"] => nik}

check Amend.plan_hash(hd(chain)["plan"]) == am["rootPlanHash"],
      "v11 amend: root planHash matches vector"

res_chain = Amend.verify_amendment_chain(chain, key_cache)
check res_chain.valid == am["expectedValid"], "v11 amend: chain verifies"

# tampering the amended title must break the chain
tampered_chain =
  List.update_at(chain, 1, fn link ->
    Map.put(link, "plan", Map.put(link["plan"], am["tamperField"], "TAMPERED"))
  end)

res_tampered = Amend.verify_amendment_chain(tampered_chain, key_cache)
check res_tampered.valid == false, "v11 amend: tampered #{am["tamperField"]} rejected"

check Amend.verify_amendment_chain([], key_cache).reason == "empty_chain",
      "v11 amend: empty chain rejected"

# ── 5. Register entries + reducers + Merkle root ─────────────────────────────

re = v11["registerEntries"]
entries = re["entries"]
reg_cache = %{"N0" => nik, "N1" => nik, nik["nodeId"] => nik}

for entry <- entries do
  res = Registers.verify_register_entry(entry, reg_cache)
  check res.valid == true, "v11 registers: entry #{entry["entryId"]} signature valid"
end

bad_entry = Map.put(hd(entries), "timestamp", "2041-01-01T00:00:00.000Z")
check Registers.verify_register_entry(bad_entry, reg_cache).valid == false,
      "v11 registers: tampered entry rejected"

reduced = Registers.reduce_questions(entries)
check reduced.by_id == re["expectedQuestionState"],
      "v11 registers: reduced question state matches vector"
check reduced.superseded == [], "v11 registers: nothing superseded"

# order invariance: reversed input produces identical state
check Registers.reduce_questions(Enum.reverse(entries)).by_id == re["expectedQuestionState"],
      "v11 registers: reduction is order-invariant"

check Registers.entries_root(entries) == re["entriesRoot"],
      "v11 registers: Merkle entriesRoot matches vector"

# deterministic re-creation: signing entry 0's fields with the vector seed
e0 = hd(entries)
recreated =
  Registers.create_register_entry("question", e0["content"],
    session_id: e0["sessionId"],
    node_id: e0["nodeId"],
    seq: e0["seq"],
    timestamp: e0["timestamp"],
    private_key_b64: seed_b64
  )
check recreated == e0, "v11 registers: created entry reproduces vector byte-for-byte"

# ── 6. CBOR decode + COSE_Sign1 verify ───────────────────────────────────────

cs = v11["coseSign1"]
cose_env = %{"plan" => cs["plan"], "coseSign1CborB64" => cs["coseSign1CborB64"]}

check Cose.verify_plan_cose(cose_env, key_cache).valid == true,
      "v11 cose: COSE_Sign1 envelope verifies"

check Cose.verify_plan_any(cose_env, key_cache).valid == true,
      "v11 cose: verify_plan_any handles CBOR envelope"

tampered_env = Map.put(cose_env, "plan", Map.put(cs["plan"], "title", "TAMPERED"))
check Cose.verify_plan_cose(tampered_env, key_cache).reason == "payload_mismatch",
      "v11 cose: tampered plan -> payload_mismatch"

check Cose.verify_plan_cose(cose_env, %{}).reason == "key_not_in_cache",
      "v11 cose: empty cache -> key_not_in_cache"

# decoder structure checks
decoded = Cbor.decode(Base.url_decode64!(cs["coseSign1CborB64"], padding: false))
{:tag, 18, [prot, unprot, {:bstr, payload}, {:bstr, sig}]} = decoded
{:bstr, prot_bytes} = prot
check Cbor.decode(prot_bytes) == %{1 => -19}, "v11 cbor: protected header {1: -19}"
{:bstr, kid_bytes} = unprot[4]
check byte_size(kid_bytes) == 16, "v11 cbor: kid is 16 bytes"
check Base.url_encode64(kid_bytes, padding: false) == nik["nodeId"],
      "v11 cbor: kid matches NIK nodeId"
check payload == Security.canonical_json(cs["plan"]), "v11 cbor: payload is canonical plan JSON"
check byte_size(sig) == 64, "v11 cbor: signature is 64 bytes"

# decoder rejections
check (try do Cbor.decode(<<0x00, 0x01>>) && false rescue _ -> true end),
      "v11 cbor: trailing bytes rejected"
check (try do Cbor.decode(<<0xFB, 0::64>>) && false rescue _ -> true end),
      "v11 cbor: floats rejected"
check (try do Cbor.decode(<<0x5F>>) && false rescue _ -> true end),
      "v11 cbor: indefinite lengths rejected"

# sign/verify roundtrip with the fixed seed
roundtrip = Cose.sign_plan_cose(cs["plan"], seed_b64)
check roundtrip["coseSign1CborB64"] == cs["coseSign1CborB64"],
      "v11 cose: deterministic signing reproduces vector envelope"

# ── 7. Session state machine golden transition table ─────────────────────────

sm = v11["stateMachine"]
ctx0 = Session.create_session(sm["plan"], sm["planId"], quorum: sm["quorum"])
check ctx0.state == "DRAFT", "v11 session: starts in DRAFT"
check ctx0.lock_timeout_ms == 1_800_000, "v11 session: lock timeout 2x max delay"

final_ctx =
  sm["steps"]
  |> Enum.with_index()
  |> Enum.reduce(ctx0, fn {step, i}, ctx ->
    %{ctx: next} = Session.transition(ctx, step["event"])
    expect_lock = step["expectLock"]

    check next.state == step["expectState"],
          "v11 session step #{i} (#{step["event"]["type"]}): state #{step["expectState"]} (got #{next.state})"
    check next.lock == expect_lock,
          "v11 session step #{i} (#{step["event"]["type"]}): lock #{inspect(expect_lock)} (got #{inspect(next.lock)})"

    next
  end)

check final_ctx.state == "COMPLETE", "v11 session: ends COMPLETE"

# ── Summary ──────────────────────────────────────────────────────────────────

passed = Process.get(:passed, 0)
failed = Process.get(:failed, 0)
IO.puts("\n#{passed} passed  #{failed} failed")
if failed > 0, do: System.halt(1)
