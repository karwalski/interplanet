# test/parity_test.exs -- LTX parity with the JS reference SDK (issue #27).
# Mirrors the javascript/ltx/tests/run.js sections: golden planId vectors,
# validatePlan + reserved fields, sequence reorder window, reduceDecisions.
# Run with: elixir -r test/test_helper.exs test/parity_test.exs

Code.require_file("../lib/interplanet_ltx/json.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/security.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/segments.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/validate.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/session.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/amend.ex", __DIR__)
Code.require_file("../lib/interplanet_ltx/registers.ex", __DIR__)

import Test

alias InterplanetLtx.Amend
alias InterplanetLtx.Json
alias InterplanetLtx.Registers
alias InterplanetLtx.Security
alias InterplanetLtx.Segments
alias InterplanetLtx.Session
alias InterplanetLtx.Validate

# ── Conformance: golden planId vectors (spec/golden/plan-ids.json) ────────────

golden =
  Path.expand("../../../spec/golden/plan-ids.json", __DIR__)
  |> File.read!()
  |> Json.decode_ordered!()

vectors = Json.get(golden, "vectors")
check length(vectors) >= 9, "golden vectors present"

for gv <- vectors do
  name = Json.get(gv, "name")
  plan = Json.get(gv, "plan")
  check Segments.make_plan_id(plan) == Json.get(gv, "planId"), "golden planId #{name}"

  if Json.get(gv, "planHash") != nil do
    check Amend.plan_hash(Json.to_plain(plan)) == Json.get(gv, "planHash"), "golden planHash #{name}"
  end
end

# ── Conformance: planId prefix vectors (spec/golden/plan-id-prefixes.json) ──
# Unicode upper-casing and UTF-16 slicing of HOSTSTR / NODESTR (issue #37).
# Elixir strings are UTF-8 and cannot hold a lone surrogate, so the expected
# id is planIdUtf8 (a surrogate pair split by the cut becomes U+FFFD).

prefix_vectors =
  Path.expand("../../../spec/golden/plan-id-prefixes.json", __DIR__)
  |> File.read!()
  |> Json.decode_ordered!()
  |> Json.get("vectors")

check length(prefix_vectors) >= 18, "prefix vectors present"

for gv <- prefix_vectors do
  name = Json.get(gv, "name")
  plan = Json.get(gv, "plan")
  want = Json.get(gv, "planIdUtf8")
  got = Segments.make_plan_id(plan)
  check got == want, "prefix planId #{name} (got #{got})"
  check Segments.plan_id_from_json(Json.stringify(plan)) == want, "prefix planId from JSON text #{name}"
  # Typed %LtxPlan{} (v2 model): same prefix.
  typed = InterplanetLtx.make_plan_id(InterplanetLtx.upgrade_config(Json.to_plain(plan)))
  cut = fn id -> binary_part(id, 0, byte_size(id) - 12) end
  check cut.(typed) == cut.(want), "prefix typed planId #{name} (got #{typed})"
end

by_name = Map.new(vectors, fn gv -> {Json.get(gv, "name"), gv} end)
pid_of = fn n -> Json.get(by_name[n], "planId") end
plan_of = fn n -> Json.to_plain(Json.get(by_name[n], "plan")) end

check pid_of.("v2-freeze-check") == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d", "golden v2 freeze anchor"
check pid_of.("v2-unicode-title") == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8", "golden v2 unicode anchor"
check pid_of.("v2-createPlan-default") != pid_of.("v2-key-order-sensitive"), "golden v2 order-sensitive"
check pid_of.("v3-upgrade-delays") == pid_of.("v3-key-order-insensitive"), "golden v3 order-insensitive"
check plan_of.("v3-amendment")["prevPlanHash"] == Json.get(by_name["v3-upgrade-delays"], "planHash"),
      "golden v3 amendment chain hash"
check InterplanetLtx.create_plan([]).quantum == 5 and InterplanetLtx.Constants.default_quantum() == 5,
      "create_plan default quantum is 5"

# create_plan structs serialise nodes before segments, so the default plan
# matches the v2-key-order-sensitive vector (not v2-createPlan-default).
check InterplanetLtx.make_plan_id(
        InterplanetLtx.create_plan(title: "Golden Default", start: "2026-03-15T14:00:00.000Z", delay: 840)
      ) == pid_of.("v2-key-order-sensitive"),
      "create_plan struct planId = golden v2-key-order-sensitive"

# JSON text entry point and Json round trip
check Segments.plan_id_from_json(Json.stringify(Json.get(by_name["v2-relay"], "plan"))) == pid_of.("v2-relay"),
      "plan_id_from_json matches golden v2-relay"
check Json.stringify(Json.decode_ordered!(~s({"b":1,"a":[true,null,"x\\"y"]}))) == ~s({"b":1,"a":[true,null,"x\\"y"]}),
      "Json stringify preserves order and escapes"

# ── Plan validation: reserved streams / branching (§3.5, §7) ─────────────────

codes = fn r -> Enum.map(r.errors, & &1.code) end

for gv <- vectors do
  check Validate.validate_plan(Json.get(gv, "plan")).valid == true,
        "validate_plan accepts golden #{Json.get(gv, "name")}"
end

vp_base = plan_of.("v3-upgrade-delays")
vp_v2 = plan_of.("v2-freeze-check")

check Validate.validate_plan(Map.put(vp_base, "streams", [])).valid == true, "validate_plan v3 empty streams ok"
vp_streams = Validate.validate_plan(Map.put(vp_base, "streams", [%{"id" => "S1"}]))
check vp_streams.valid == false and "reserved_streams" in codes.(vp_streams), "validate_plan non-empty streams"
check Enum.find(vp_streams.errors, &(&1.code == "reserved_streams")).path == "streams",
      "validate_plan streams error path"
check "reserved_streams" in codes.(Validate.validate_plan(Map.put(vp_base, "streams", "S1"))),
      "validate_plan streams non-array"
vp_seg_stream = Validate.validate_plan(Map.put(vp_base, "segments", [%{"type" => "TX", "q" => 1, "stream" => "S1"}]))
check "reserved_streams" in codes.(vp_seg_stream), "validate_plan segment stream"
check "reserved_branching" in codes.(Validate.validate_plan(Map.put(vp_base, "branches", []))),
      "validate_plan branches"
check "reserved_branching" in codes.(Validate.validate_plan(Map.put(vp_base, "branching", %{"mode" => "local"}))),
      "validate_plan branching"
vp_seg_branch = Validate.validate_plan(Map.put(vp_base, "segments", [%{"type" => "CAUCUS", "q" => 1, "branch" => "B1"}]))
check "reserved_branching" in codes.(vp_seg_branch) and hd(vp_seg_branch.errors).path == "segments[0].branch",
      "validate_plan segment branch"
check "v3_field_in_v2" in codes.(Validate.validate_plan(Map.put(vp_v2, "streams", []))),
      "validate_plan v2 streams is v3 field"
check "reserved_branching" in codes.(Validate.validate_plan(Map.put(vp_v2, "branching", true))),
      "validate_plan v2 branching"
check "not_an_object" in codes.(Validate.validate_plan(nil)), "validate_plan non-object"
check "invalid_version" in codes.(Validate.validate_plan(Map.put(vp_v2, "v", 7))), "validate_plan bad version"
check "invalid_host" in codes.(Validate.validate_plan(Map.put(vp_v2, "nodes", Enum.reverse(vp_v2["nodes"])))),
      "validate_plan host not first"
check "invalid_delays" in codes.(Validate.validate_plan(Map.put(vp_base, "delays", %{"N1|N0" => 860}))),
      "validate_plan unsorted delays key"
check "unknown_speaker" in codes.(Validate.validate_plan(Map.put(vp_v2, "segments", [%{"type" => "TX", "q" => 1, "speaker" => "N9"}]))),
      "validate_plan unknown speaker"
check "invalid_quantum" in codes.(Validate.validate_plan(Map.put(vp_v2, "quantum", 0))),
      "validate_plan quantum out of range"
check "missing_field" in codes.(Validate.validate_plan(Map.delete(vp_v2, "title"))), "validate_plan missing title"
check "invalid_mode" in codes.(Validate.validate_plan(Map.put(vp_v2, "mode", "CHAT"))), "validate_plan bad mode"
check "duplicate_node_id" in codes.(Validate.validate_plan(Map.put(vp_v2, "nodes", vp_v2["nodes"] ++ [List.last(vp_v2["nodes"])]))),
      "validate_plan duplicate node id"
check "invalid_field" in codes.(Validate.validate_plan(Map.put(vp_base, "prevPlanHash", "ABC"))),
      "validate_plan bad prevPlanHash"
check Validate.validate_plan(InterplanetLtx.create_plan(start: "2026-03-15T14:00:00.000Z")).valid == true,
      "validate_plan accepts create_plan struct"

# Enforcement paths raise with a code
throws_code = fn f ->
  try do
    f.()
    nil
  rescue
    e in InterplanetLtx.ReservedFieldError -> e.code
  end
end

check throws_code.(fn -> Segments.upgrade_plan_to_v3(vp_v2, %{"streams" => [%{"id" => "S1"}]}) end) == "reserved_streams",
      "upgrade_plan_to_v3 rejects streams"
check throws_code.(fn -> Segments.upgrade_plan_to_v3(vp_v2, %{"streams" => []}) end) == nil,
      "upgrade_plan_to_v3 allows empty"
check throws_code.(fn -> Segments.upgrade_plan_to_v3(vp_v2, %{"branches" => []}) end) == "reserved_branching",
      "upgrade_plan_to_v3 rejects branches"
check throws_code.(fn -> Session.create_session(Map.put(vp_base, "streams", [1]), "id") end) == "reserved_streams",
      "create_session rejects streams"
check throws_code.(fn -> Session.create_session(vp_base, "id") end) == nil, "create_session accepts golden"

vp_nik = Security.generate_nik(node_label: "Earth HQ")
vp_signed = Security.sign_plan(vp_base, vp_nik.private_key_b64, vp_nik.nik["publicKey"])
check throws_code.(fn -> Amend.create_amendment(vp_signed, %{"branching" => %{}}, vp_nik.private_key_b64) end) ==
        "reserved_branching",
      "create_amendment rejects branching"
check throws_code.(fn -> Amend.create_amendment(vp_signed, %{"title" => "x"}, vp_nik.private_key_b64) end) == nil,
      "create_amendment ok without"
up3 = Segments.upgrade_plan_to_v3(vp_v2, %{"delays" => %{"N0|N1" => 900}})
check up3["v"] == 3 and up3["planVersion"] == 1 and up3["delays"]["N0|N1"] == 900, "upgrade_plan_to_v3 result"

# ── Sequence tracker: late arrival vs replay (LTX-SECURITY §11.2) ─────────────

tracker = Security.new_sequence_tracker("plan-parity")
for s <- [1, 2, 5, 6], do: Security.record_seq(tracker, "N0", s)
check Security.missing_seqs(tracker, "N0") == [3, 4], "missing_seqs lists gap"
late4 = Security.record_seq(tracker, "N0", 4)
check late4.accepted == true and late4.late == true, "late seq accepted"
check late4.gap == false and late4.gap_size == 0 and late4.reason == nil, "late seq no gap, no reason"
check Security.last_seen_seq(tracker, "N0") == 6, "late seq keeps high-water mark"
dup4 = Security.record_seq(tracker, "N0", 4)
check dup4.accepted == false and dup4.reason == "replay" and dup4.late == false, "late seq duplicate is replay"
check Security.record_seq(tracker, "N0", 7).late == false, "in-order result late=false"
check Security.record_seq(tracker, "N0", 6).reason == "replay", "duplicate of in-order is replay"
check Security.missing_seqs(tracker, "N0") == [3], "missing_seqs after late"
check Security.record_seq(tracker, "N0", 1.5).reason == "invalid_seq" and
        Security.check_seq(%{seq: 2.5}, tracker, "N0").reason == "invalid_seq",
      "invalid seq rejected"
check Security.check_seq(%{}, tracker, "N0").reason == "missing_seq", "missing seq rejected"
check Security.seq_reorder_window() == 64, "default reorder window"

tw = Security.new_sequence_tracker("plan-window", reorder_window: 4)
Security.record_seq(tw, "N1", 1)
big_gap = Security.record_seq(tw, "N1", 10)
check big_gap.gap == true and big_gap.gap_size == 8, "window gap reported in full"
check Security.missing_seqs(tw, "N1") == [7, 8, 9], "window bounds missing markers"
check Security.record_seq(tw, "N1", 5).reason == "replay", "below window rejected"
check Security.record_seq(tw, "N1", 8).late == true, "inside window accepted late"
Security.record_seq(tw, "N1", 12)
check Security.record_seq(tw, "N1", 7).accepted == false, "slid-out marker rejected"
check Security.record_seq(tw, "N1", 11).late == true, "slid-in gap accepted late"

t0 = Security.new_sequence_tracker("plan-strict", reorder_window: 0)
Security.record_seq(t0, "N0", 1)
Security.record_seq(t0, "N0", 3)
check Security.record_seq(t0, "N0", 2).reason == "replay", "window 0 = strict monotonic"

bad_window =
  try do
    Security.new_sequence_tracker("p", reorder_window: 1.5)
    false
  rescue
    ArgumentError -> true
  end

check bad_window, "non-integer window raises"

{:ok, store} = Agent.start_link(fn -> %{} end)
ta = Security.new_sequence_tracker("plan-persist", storage: store)
Security.record_seq(ta, "N2", 1)
Security.record_seq(ta, "N2", 4)
tb = Security.new_sequence_tracker("plan-persist", storage: store)
check Security.record_seq(tb, "N2", 3).late == true, "persisted late accepted"
check Security.record_seq(tb, "N2", 3).reason == "replay", "persisted late not replayable"
check Security.record_seq(tb, "N2", 4).reason == "replay", "persisted replay rejected"

# ── Decision register (§10.3) ─────────────────────────────────────────────────

dec_host = Security.generate_nik(node_label: "HOST")
dec_mars = Security.generate_nik(node_label: "MARS")
dec_cache = %{"N0" => dec_host.nik, "N1" => dec_mars.nik}

mk_dec = fn type, content, node_id, seq, ts, priv, extra ->
  Registers.create_register_entry(type, content,
    [session_id: "LTX-DEC-TEST", node_id: node_id, seq: seq, timestamp: ts, private_key_b64: priv] ++ extra)
end

dec1 =
  mk_dec.("decision", %{"text" => "Proceed with EVA-3", "rationale" => "Weather window", "originWindow" => "W2"},
          "N0", 1, "2026-08-01T12:00:00.000Z", dec_host.private_key_b64, [])

check dec1["entryId"] == "DEC-N0-1", "decision id prefix DEC"
check Registers.verify_register_entry(dec1, dec_cache).valid == true, "decision entry verifies"
reg1 = Registers.reduce_decisions([dec1])
d1 = reg1.by_id["DEC-N0-1"]
check d1["status"] == "RECORDED" and d1["version"] == 1, "decision RECORDED"
check d1["text"] == "Proceed with EVA-3" and d1["recordedBy"] == "N0" and d1["rationale"] == "Weather window",
      "decision fields"

dec_rev =
  mk_dec.("decision_update", %{"did" => "DEC-N0-1", "text" => "Proceed with EVA-3 at 14:00", "version" => 2},
          "N1", 1, "2026-08-01T12:10:00.000Z", dec_mars.private_key_b64, [])

dec_res =
  mk_dec.("decision_update", %{"did" => "DEC-N0-1", "status" => "RESCINDED", "version" => 3},
          "N0", 2, "2026-08-01T12:20:00.000Z", dec_host.private_key_b64, [])

check dec_rev["entryId"] == "DEC-N1-1", "decision_update id prefix DEC"
reg2 = Registers.reduce_decisions([dec_res, dec1, dec_rev])
d2 = reg2.by_id["DEC-N0-1"]
check d2["text"] == "Proceed with EVA-3 at 14:00", "decision update applied"
check d2["status"] == "RESCINDED" and d2["version"] == 3, "decision RESCINDED v3"
check d2["editor"] == "N0", "decision editor recorded"
check dec_rev["entryId"] in reg2.superseded, "decision older update superseded"

dec_a = mk_dec.("decision_update", %{"did" => "DEC-N0-1", "text" => "From N0", "version" => 5},
                "N0", 7, "2026-08-01T13:00:00.000Z", dec_host.private_key_b64, [])
dec_b = mk_dec.("decision_update", %{"did" => "DEC-N0-1", "text" => "From N1", "version" => 5},
                "N1", 7, "2026-08-01T13:00:00.000Z", dec_mars.private_key_b64, [])
conf1 = Registers.reduce_decisions([dec1, dec_b, dec_a])
conf2 = Registers.reduce_decisions([dec_a, dec1, dec_b])
check conf1.by_id["DEC-N0-1"]["text"] == "From N0", "decision tie lowest nodeId wins"
check dec_b["entryId"] in conf1.superseded and dec_a["entryId"] not in conf1.superseded,
      "decision tie loser superseded"
check conf1 == conf2, "decision reduce order-independent"

dec_hi = mk_dec.("decision_update", %{"did" => "DEC-N0-1", "text" => "N1 v6", "version" => 6},
                 "N1", 8, "2026-08-01T12:30:00.000Z", dec_mars.private_key_b64, [])
check Registers.reduce_decisions([dec1, dec_a, dec_hi]).by_id["DEC-N0-1"]["text"] == "N1 v6",
      "decision higher version wins"

dec_orphan = mk_dec.("decision_update", %{"did" => "DEC-NOPE-1", "version" => 2},
                     "N1", 9, "2026-08-01T12:40:00.000Z", dec_mars.private_key_b64, [])
dec_dup = mk_dec.("decision", %{"text" => "dup"}, "N1", 10, "2026-08-01T12:50:00.000Z",
                  dec_mars.private_key_b64, [entry_id: "DEC-N0-1"])
reg3 = Registers.reduce_decisions([dec1, dec_orphan, dec_dup])
check "DEC-N1-9" in reg3.superseded, "decision orphan update superseded"
check reg3.by_id["DEC-N0-1"]["text"] == "Proceed with EVA-3" and reg3.by_id["DEC-N0-1"]["recordedBy"] == "N0",
      "decision duplicate create ignored"
check map_size(Registers.reduce_decisions([dec1, dec_rev]).by_id) == 1 and
        map_size(Registers.reduce_actions([dec1]).by_id) == 0,
      "decision reducer ignores others"

# ── Summary ───────────────────────────────────────────────────────────────────

passed = Process.get(:passed, 0)
failed = Process.get(:failed, 0)
IO.puts("\n#{passed} passed  #{failed} failed")
if failed > 0, do: System.halt(1)
