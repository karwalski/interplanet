# parity_tests.jl — LTX parity with the JS reference SDK (issue #27).
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

end  # @testset "JS reference parity"
