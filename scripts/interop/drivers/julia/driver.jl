# Interop driver for julia/ltx (see scripts/interop/run.js).
# Usage: julia --project=$ROOT/julia/ltx driver.jl IN OUT
include(joinpath(ENV["ROOT"], "julia", "ltx", "src", "InterplanetLtx.jl"))
using .InterplanetLtx
using Base64

in_dir, out_dir = ARGS[1], ARGS[2]

base = create_plan(title = "Réunion Mars 🚀", start_iso = "2026-03-15T14:00:00.000Z",
                   quantum = 3, mode = "LTX-ASYNC", delay = 840)
plan = LtxPlan(base.v, base.title, base.start, base.quantum, base.mode,
    [LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
     LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
     LtxNode("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")],
    [LtxSegmentSpec("PLAN_CONFIRM", 2),
     LtxSegmentSpec("TX", 3; speaker = "N0", label = "Ouverture: état de la mission"),
     LtxSegmentSpec("RX", 3),
     LtxSegmentSpec("TX", 2; speaker = "N1", label = "Réponse 🔴"),
     LtxSegmentSpec("BUFFER", 1)])
println("NOTE v3 via upgrade_plan_to_v3 (JsonObject)")

function unhash(h)
    t = replace(h[4:end], '-' => '+', '_' => '/')
    t *= repeat("=", mod(-length(t), 4))
    return base64decode(t)
end

write(joinpath(out_dir, "wire-v2.json"), unhash(encode_hash(plan)))
println("ID_V2 ", make_plan_id(plan))

v3 = upgrade_plan_to_v3(plan; extras = ["delays" => parse_json_ordered("{\"N1|N2\":842}")])
write(joinpath(out_dir, "wire-v3.json"), json_stringify(v3))
println("ID_V3 ", make_plan_id(v3))

for v in ("2", "3")
    println("JS_V$v ", plan_id_from_json(read(joinpath(in_dir, "js-v$v.json"), String)))
end
