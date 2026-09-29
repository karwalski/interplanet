# Interop driver for elixir/ltx (see scripts/interop/run.js).
# Run with the port compiled onto the code path: elixir -pa build driver.exs IN OUT
alias InterplanetLtx.Models.{LtxNode, LtxSegmentTemplate}

[in_dir, out_dir] = System.argv()

plan =
  InterplanetLtx.create_plan(
    title: "Réunion Mars 🚀",
    start: "2026-03-15T14:00:00.000Z",
    quantum: 3,
    mode: "LTX-ASYNC",
    nodes: [
      %LtxNode{id: "N0", name: "Earth HQ", role: "HOST", delay: 0, location: "earth"},
      %LtxNode{id: "N1", name: "Mars Hab-01", role: "PARTICIPANT", delay: 840, location: "mars"},
      %LtxNode{id: "N2", name: "L-1 Gateway", role: "PARTICIPANT", delay: 2, location: "moon"}
    ],
    segments: [
      %LtxSegmentTemplate{type: "PLAN_CONFIRM", q: 2},
      %LtxSegmentTemplate{type: "TX", q: 3, speaker: "N0", label: "Ouverture: état de la mission"},
      %LtxSegmentTemplate{type: "RX", q: 3},
      %LtxSegmentTemplate{type: "TX", q: 2, speaker: "N1", label: "Réponse 🔴"},
      %LtxSegmentTemplate{type: "BUFFER", q: 1}
    ]
  )

"#l=" <> token = InterplanetLtx.encode_hash(plan)
File.write!(Path.join(out_dir, "wire-v2.json"), Base.url_decode64!(token, padding: false))
IO.puts("ID_V2 " <> InterplanetLtx.make_plan_id(plan))

v3 = InterplanetLtx.Segments.upgrade_plan_to_v3(plan, %{"delays" => %{"N1|N2" => 842}})
File.write!(Path.join(out_dir, "wire-v3.json"), InterplanetLtx.Security.canonical_json(v3))
IO.puts("ID_V3 " <> InterplanetLtx.Segments.make_plan_id(v3))
IO.puts("NOTE v3 via Segments.upgrade_plan_to_v3 (plain map); wire via Security.canonical_json")

for v <- ["2", "3"] do
  json = File.read!(Path.join(in_dir, "js-v#{v}.json"))
  IO.puts("JS_V#{v} " <> InterplanetLtx.Segments.plan_id_from_json(json))
end
