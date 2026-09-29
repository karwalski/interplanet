// Interop driver for csharp/ltx (see scripts/interop/run.js).
// Usage: Driver <main|v11> <inDir> <outDir>
//   main  InterplanetLTX.CreatePlan / EncodeHash / MakePlanId (LtxPlan)
//   v11   LtxV11 model: PlanV11 / ToJsonV2 / MakePlanId, plus v3
using System.Text;
using InterplanetLtx;

const string Title = "Réunion Mars 🚀";
const string Start = "2026-03-15T14:00:00.000Z";
string mode = args[0], inDir = args[1], outDir = args[2];

if (mode == "main")
{
    var plan = InterplanetLTX.CreatePlan(
        title: Title, start: Start, quantum: 3, mode: "LTX-ASYNC",
        nodes: new List<LtxNode> {
            new("N0", "Earth HQ", "HOST", 0, "earth"),
            new("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
            new("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon"),
        },
        segments: new List<LtxSegmentTemplate> {
            new("PLAN_CONFIRM", 2),
            new("TX", 3, "N0", "Ouverture: état de la mission"),
            new("RX", 3),
            new("TX", 2, "N1", "Réponse 🔴"),
            new("BUFFER", 1),
        });
    Console.WriteLine("NOTE LtxPlan: no v3");
    File.WriteAllBytes(Path.Combine(outDir, "wire-v2.json"), Wire(plan));
    Console.WriteLine("ID_V2 " + InterplanetLTX.MakePlanId(plan));
    CtlCase(outDir);
}
else
{
    var plan = new PlanV11
    {
        V = 2, Title = Title, Start = Start, Quantum = 3, Mode = "LTX-ASYNC",
        Nodes = new List<NodeV11> {
            new("N0", "Earth HQ", "HOST", 0, "earth"),
            new("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
            new("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon"),
        },
        Segments = new List<SegmentTemplateV11> {
            new("PLAN_CONFIRM", 2),
            new("TX", 3, "N0", "Ouverture: état de la mission"),
            new("RX", 3),
            new("TX", 2, "N1", "Réponse 🔴"),
            new("BUFFER", 1),
        },
    };
    File.WriteAllText(Path.Combine(outDir, "wire-v2.json"), LtxV11.ToJsonV2(plan), new UTF8Encoding(false));
    Console.WriteLine("ID_V2 " + LtxV11.MakePlanId(plan));
    // No upgrade function: build the v3 plan with a record `with` expression.
    var v3 = plan with { V = 3, PlanVersion = 1, Delays = new Dictionary<string, long> { ["N1|N2"] = 842 } };
    File.WriteAllText(Path.Combine(outDir, "wire-v3.json"), LtxSecurity.CanonicalJSON(v3.ToDict()), new UTF8Encoding(false));
    Console.WriteLine("ID_V3 " + LtxV11.MakePlanId(v3));
    Console.WriteLine("NOTE PlanV11: v2 wire via ToJsonV2, v3 wire via CanonicalJSON(ToDict()); v3 via `with`");
}

foreach (var v in new[] { "2", "3", "P" })
{
    string json = File.ReadAllText(Path.Combine(inDir, $"js-v{v}.json"), Encoding.UTF8);
    Console.WriteLine($"JS_V{v} " + LtxPlanJson.MakePlanIdFromJson(json));
}

static byte[] Wire(LtxPlan plan)
{
    string token = InterplanetLTX.EncodeHash(plan).Substring(3).Replace('-', '+').Replace('_', '/');
    token = token.PadRight(token.Length + (4 - token.Length % 4) % 4, '=');
    return Convert.FromBase64String(token);
}

// Issue #36 extra case (not a run.js column): control characters, a lone
// surrogate and JS \s whitespace (tab, NBSP, U+3000, U+2028, BOM, LF) in the
// title and node names, plus a speaker-only and a label-only segment. The
// typed wire JSON must be exactly what JSON.stringify writes for it, and the
// typed planId must equal the JSON-based planId of that wire and the JS
// reference id (ltx-sdk.js makePlanId on the same plan object).
static void CtlCase(string outDir)
{
    var ctl = new LtxPlan
    {
        V = 2,
        Title = "Ctl\u0001\b\f\n\r\t\"\\\u001f\u007f\ud800 \ud83d\ude80",
        Start = "2026-03-15T14:00:00.000Z", Quantum = 3, Mode = "LTX-ASYNC",
        Nodes = new List<LtxNode> {
            new("N0", "Earth\tHQ", "HOST", 0, "earth"),
            new("N1", "Ma\u00a0r\u3000s\u2009Hab-01", "PARTICIPANT", 840, "mars"),
            new("N2", "L-1\u2028Gate\ufeffway\n", "PARTICIPANT", 2, "moon"),
        },
        Segments = new List<LtxSegmentTemplate> {
            new("PLAN_CONFIRM", 2),
            new("TX", 3, "N0", "Opening\tremarks"),
            new("RX", 3),
            new("TX", 2, Speaker: "N1"),
            new("TX", 1, Label: "Q&A \ud83d\udd34"),
            new("BUFFER", 1),
        },
    };
    const string reference = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-39d48c2a";
    byte[] wire = Wire(ctl);
    File.WriteAllBytes(Path.Combine(outDir, "wire-ctl.json"), wire);
    string json = Encoding.UTF8.GetString(wire);
    string id = InterplanetLTX.MakePlanId(ctl);
    string jsonId = LtxPlanJson.MakePlanIdFromJson(json);
    bool ok = LtxPlanJson.Stringify(System.Text.Json.JsonDocument.Parse(json).RootElement) == json
              && id == jsonId && id == reference;
    Console.WriteLine($"NOTE ctl/whitespace case: typed {id}, JSON {jsonId}, JS {reference}" + (ok ? " (ok)" : " (MISMATCH)"));
    if (!ok) Environment.Exit(1);
}
