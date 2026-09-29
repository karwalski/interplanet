# parity_tests.jl -- LTX parity with the JS reference SDK (issue #27).
# Mirrors javascript/ltx/tests/run.js: golden planId vectors and validatePlan
# with the reserved streams / branching fields. Included from runtests.jl.

using Test

const GOLDEN_PATH = joinpath(@__DIR__, "..", "..", "..", "spec", "golden", "plan-ids.json")

codes(r) = [e.code for e in r.errors]
throws_code(f) = try
    f(); nothing
catch e
    e isa ReservedFieldError ? e.code : rethrow()
end

@testset "JS reference parity (issue #27)" begin

golden  = parse_json_ordered(read(GOLDEN_PATH, String))
vectors = golden["vectors"]
by_name = Dict(gv["name"] => gv for gv in vectors)

@testset "golden planId vectors" begin
    @test length(vectors) >= 9
    for gv in vectors
        @test make_plan_id(gv["plan"]) == gv["planId"]
        if haskey(gv, "planHash")
            @test plan_hash(gv["plan"]) == gv["planHash"]
        end
    end
    @test by_name["v2-freeze-check"]["planId"] == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d"
    @test by_name["v2-unicode-title"]["planId"] == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8"
    @test by_name["v2-createPlan-default"]["planId"] != by_name["v2-key-order-sensitive"]["planId"]
    @test by_name["v3-upgrade-delays"]["planId"] == by_name["v3-key-order-insensitive"]["planId"]
    @test by_name["v3-amendment"]["plan"]["prevPlanHash"] == by_name["v3-upgrade-delays"]["planHash"]
    @test create_plan().quantum == 5 && DEFAULT_QUANTUM == 5
    # LtxPlan serialises nodes before segments, so the default plan matches
    # the v2-key-order-sensitive vector (JS createPlan emits segments first).
    @test make_plan_id(create_plan(title = "Golden Default", start_iso = "2026-03-15T14:00:00.000Z",
                                   delay = 840)) == by_name["v2-key-order-sensitive"]["planId"]
    @test plan_id_from_json(json_stringify(by_name["v2-relay"]["plan"])) == by_name["v2-relay"]["planId"]
    @test json_stringify(parse_json_ordered("{\"b\":1,\"a\":[true,null,\"x\\\"y\"],\"e\":[],\"o\":{}}")) ==
          "{\"b\":1,\"a\":[true,null,\"x\\\"y\"],\"e\":[],\"o\":{}}"
    @test parse_json_ordered("\"\\ud83d\\ude80\"") == "\U1F680"
end

# spec/golden/plan-id-prefixes.json (issue #37): Unicode upper-casing and
# UTF-16 slicing of HOSTSTR / NODESTR. A Julia String holds a lone surrogate
# as WTF-8, so the expected id is the planIdWtf8Hex bytes.
@testset "golden planId prefix vectors" begin
    pv = parse_json_ordered(read(joinpath(@__DIR__, "..", "..", "..", "spec", "golden",
                                          "plan-id-prefixes.json"), String))["vectors"]
    @test length(pv) >= 18
    for gv in pv
        want = String(hex2bytes(gv["planIdWtf8Hex"]))
        plan = gv["plan"]
        @test make_plan_id(plan) == want
        @test plan_id_from_json(json_stringify(plan)) == want
        # Typed LtxPlan (v2 model, nodes first): same prefix.
        typed = LtxPlan(2, plan["title"], plan["start"], plan["quantum"], plan["mode"],
                        [LtxNode(n["id"], n["name"], n["role"], n["delay"], n["location"]) for n in plan["nodes"]],
                        [LtxSegmentSpec(sg["type"], sg["q"]) for sg in plan["segments"]])
        tid = make_plan_id(typed)
        @test codeunits(tid)[1:end-12] == codeunits(want)[1:end-12]
        @test occursin("\\ud8", json_stringify(make_plan_id(plan))) == gv["loneSurrogate"]
    end
    @test InterplanetLtx.js_uppercase("stra\u00dfe \ufb01 \u0149 \u0390 \u1fb3 \u0587") ==
          "STRASSE FI \u02bcN \u0399\u0308\u0301 \u0391\u0399 \u0535\u0552"
end

@testset "validate_plan and reserved fields" begin
    for gv in vectors
        @test validate_plan(gv["plan"]).valid
    end
    vp_base = by_name["v3-upgrade-delays"]["plan"]
    vp_v2   = by_name["v2-freeze-check"]["plan"]
    w = InterplanetLtx.json_with
    obj(ps...) = JsonObject(Pair{String,Any}[ps...])
    @test validate_plan(w(vp_base, "streams", Any[])).valid
    vs = validate_plan(w(vp_base, "streams", Any[obj("id" => "S1")]))
    @test !vs.valid && "reserved_streams" in codes(vs)
    @test first(filter(e -> e.code == "reserved_streams", vs.errors)).path == "streams"
    @test "reserved_streams" in codes(validate_plan(w(vp_base, "streams", "S1")))
    @test "reserved_streams" in codes(validate_plan(w(vp_base, "segments", Any[obj("type" => "TX", "q" => 1, "stream" => "S1")])))
    @test "reserved_branching" in codes(validate_plan(w(vp_base, "branches", Any[])))
    @test "reserved_branching" in codes(validate_plan(w(vp_base, "branching", obj("mode" => "local"))))
    vb = validate_plan(w(vp_base, "segments", Any[obj("type" => "CAUCUS", "q" => 1, "branch" => "B1")]))
    @test "reserved_branching" in codes(vb) && vb.errors[1].path == "segments[0].branch"
    @test "v3_field_in_v2" in codes(validate_plan(w(vp_v2, "streams", Any[])))
    @test "reserved_branching" in codes(validate_plan(w(vp_v2, "branching", true)))
    @test "not_an_object" in codes(validate_plan(nothing))
    @test "invalid_version" in codes(validate_plan(w(vp_v2, "v", 7)))
    @test "invalid_host" in codes(validate_plan(w(vp_v2, "nodes", reverse(vp_v2["nodes"]))))
    @test "invalid_delays" in codes(validate_plan(w(vp_base, "delays", obj("N1|N0" => 860))))
    @test "unknown_speaker" in codes(validate_plan(w(vp_v2, "segments", Any[obj("type" => "TX", "q" => 1, "speaker" => "N9")])))
    @test "invalid_quantum" in codes(validate_plan(w(vp_v2, "quantum", 0)))
    @test "missing_field" in codes(validate_plan(InterplanetLtx.json_without(vp_v2, "title")))
    @test "invalid_mode" in codes(validate_plan(w(vp_v2, "mode", "CHAT")))
    @test "duplicate_node_id" in codes(validate_plan(w(vp_v2, "nodes", vcat(vp_v2["nodes"], vp_v2["nodes"][2:2]))))
    @test "invalid_field" in codes(validate_plan(w(vp_base, "prevPlanHash", "ABC")))
    @test validate_plan(create_plan(start_iso = "2026-03-15T14:00:00Z")).valid

    @test throws_code(() -> upgrade_plan_to_v3(vp_v2; extras = ["streams" => Any[obj("id" => "S1")]])) == "reserved_streams"
    @test throws_code(() -> upgrade_plan_to_v3(vp_v2; extras = ["streams" => Any[]])) === nothing
    @test throws_code(() -> upgrade_plan_to_v3(vp_v2; extras = ["branches" => Any[]])) == "reserved_branching"
    up3 = upgrade_plan_to_v3(vp_v2; extras = ["delays" => obj("N0|N1" => 900)])
    @test up3["v"] == 3 && up3["planVersion"] == 1 && up3["delays"]["N0|N1"] == 900 && vp_v2["v"] == 2
    @test validate_plan(up3).valid
    @test startswith(make_plan_id(up3), "LTX-20260801-EARTHHQ-MARS-v3-")
end

@testset "attributed segments and JS string rules (#36)" begin
    IL = InterplanetLtx
    unhash(h) = IL._b64dec(h[4:end])
    rep_nodes = [LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
                 LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
                 LtxNode("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")]
    att = LtxPlan(2, "Réunion Mars 🚀", "2026-03-15T14:00:00.000Z", 3, "LTX-ASYNC", rep_nodes,
        [LtxSegmentSpec("PLAN_CONFIRM", 2),
         LtxSegmentSpec("TX", 3; speaker = "N0", label = "Ouverture: état de la mission"),
         LtxSegmentSpec("RX", 3),
         LtxSegmentSpec("TX", 2; speaker = "N1", label = "Réponse 🔴"),
         LtxSegmentSpec("BUFFER", 1)])
    aw = unhash(encode_hash(att))
    # {type, q, speaker?, label?}: JS key order, absent fields omitted
    @test endswith(aw, "\"segments\":[{\"type\":\"PLAN_CONFIRM\",\"q\":2},{\"type\":\"TX\",\"q\":3,\"speaker\":\"N0\"," *
                       "\"label\":\"Ouverture: état de la mission\"},{\"type\":\"RX\",\"q\":3}," *
                       "{\"type\":\"TX\",\"q\":2,\"speaker\":\"N1\",\"label\":\"Réponse 🔴\"},{\"type\":\"BUFFER\",\"q\":1}]}")
    # JS makePlanId of the same object (nodes before segments)
    @test make_plan_id(att) == "LTX-20260315-EARTHHQ-MARS-L-1G-v2-1e382346"
    @test make_plan_id(att) == plan_id_from_json(aw)
    back = decode_hash(encode_hash(att))
    @test back !== nothing
    @test back.title == att.title
    @test back.segments[2].speaker == "N0" && back.segments[4].label == "Réponse 🔴"
    @test back.segments[1].speaker === nothing && back.segments[1].label === nothing
    @test make_plan_id(back) == make_plan_id(att)
    lp = LtxPlan(att.v, att.title, att.start, att.quantum, att.mode, att.nodes,
                 [LtxSegmentSpec("RX", 2; label = "Q&A {\"x\"}\n")])
    @test endswith(unhash(encode_hash(lp)), "\"segments\":[{\"type\":\"RX\",\"q\":2,\"label\":\"Q&A {\\\"x\\\"}\\n\"}]}")
    @test decode_hash(encode_hash(lp)).segments[1].label == "Q&A {\"x\"}\n"

    # Control characters, JS whitespace (/\s/ is Unicode-aware in JS) and
    # non-whitespace look-alikes (U+0085, U+200B) in node names.
    wp = LtxPlan(2, "C\u0001\b\t\n\v\f\r\u001f\"\\/\u007f\u2028\u2029é🚀", "2026-03-15T14:00:00.000Z", 3, "LTX",
        [LtxNode("N0", "Earth\u00a0\tHQ", "HOST", 0, "earth"),
         LtxNode("N1", "\u3000M\u2003a\u2028rs", "PARTICIPANT", 840, "mars"),
         LtxNode("N2", "\ufeffL\u0085u\u200bna", "PARTICIPANT", 2, "moon")],
        [LtxSegmentSpec("TX", 2; speaker = "N1"), LtxSegmentSpec("RX", 2; label = "Q\0&A")])
    @test make_plan_id(wp) == "LTX-20260315-EARTHHQ-MARS-L\u0085U\u200b-v2-4bd132bb"
    ww = unhash(encode_hash(wp))
    @test plan_id_from_json(ww) == "LTX-20260315-EARTHHQ-MARS-L\u0085U\u200b-v2-4bd132bb"
    @test startswith(ww, "{\"v\":2,\"title\":\"C\\u0001\\b\\t\\n\\u000b\\f\\r\\u001f\\\"\\\\/\u007f\u2028\u2029é🚀\",")
    @test occursin("LTX-NODE:ID=EARTH-HQ;ROLE=HOST", generate_ics(wp))

    # Lone UTF-16 surrogates (a Julia String holds them as WTF-8)
    segs = copy(att.segments)
    segs[2] = LtxSegmentSpec("TX", 3; speaker = "N0", label = "\udbff")
    sp = LtxPlan(att.v, "x\ud800y\udc00z", att.start, att.quantum, att.mode, att.nodes, segs)
    sw = unhash(encode_hash(sp))
    @test occursin("\"title\":\"x\\ud800y\\udc00z\"", sw) && occursin("\"label\":\"\\udbff\"", sw)
    @test make_plan_id(sp) == "LTX-20260315-EARTHHQ-MARS-L-1G-v2-35164df8"
    @test plan_id_from_json(sw) == "LTX-20260315-EARTHHQ-MARS-L-1G-v2-35164df8"
    @test IL._js_quote("\ud83d\ude80") == "\"🚀\""
    @test json_stringify(parse_json_ordered("\"\\ud800\\u0041\"")) == "\"\\ud800A\""
end

end  # @testset "JS reference parity"
