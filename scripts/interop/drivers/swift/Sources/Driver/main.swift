// Interop driver for swift/ltx (see scripts/interop/run.js).
import Foundation
import InterplanetLTX

let args = CommandLine.arguments
let inDir = args[1], outDir = args[2]
typealias L = InterplanetLTX

var plan = L.createPlan(title: "Réunion Mars 🚀", start: "2026-03-15T14:00:00.000Z", delayS: 840)
plan.quantum = 3
plan.mode = "LTX-ASYNC"
plan.nodes = [
    LtxNode(id: "N0", name: "Earth HQ", role: "HOST", delay: 0, location: "earth"),
    LtxNode(id: "N1", name: "Mars Hab-01", role: "PARTICIPANT", delay: 840, location: "mars"),
    LtxNode(id: "N2", name: "L-1 Gateway", role: "PARTICIPANT", delay: 2, location: "moon"),
]
plan.segments = [
    LtxSegmentTemplate(type: "PLAN_CONFIRM", q: 2),
    LtxSegmentTemplate(type: "TX", q: 3, speaker: "N0", label: "Ouverture: état de la mission"),
    LtxSegmentTemplate(type: "RX", q: 3),
    LtxSegmentTemplate(type: "TX", q: 2, speaker: "N1", label: "Réponse 🔴"),
    LtxSegmentTemplate(type: "BUFFER", q: 1),
]

func unhash(_ h: String) -> Data {
    var s = String(h.dropFirst(3)).replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while s.count % 4 != 0 { s += "=" }
    return Data(base64Encoded: s)!
}

func write(_ name: String, _ data: Data) {
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}

write("wire-v2.json", unhash(L.encodeHash(plan)))
print("ID_V2 \(L.makePlanID(plan))")

// No upgrade function: set the v3 fields on the typed plan.
var v3 = plan
v3.v = 3
v3.planVersion = 1
v3.delays = ["N1|N2": 842]
write("wire-v3.json", unhash(L.encodeHash(v3)))
print("ID_V3 \(L.makePlanID(v3))")
print("NOTE v3 built by setting v/planVersion/delays on LtxPlan (no upgrade function)")

for v in ["2", "3"] {
    let json = try! String(contentsOfFile: "\(inDir)/js-v\(v).json", encoding: .utf8)
    print("JS_V\(v) \(L.makePlanID(json: json) ?? "nil")")
}
