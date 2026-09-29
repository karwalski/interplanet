// PrefixTests.cs: spec/golden/plan-id-prefixes.json (issue #37, spec §4.3).
// HOSTSTR / NODESTR use JS whitespace, JS toUpperCase (full Unicode mapping
// with special casing, JsUpper) and UTF-16 slicing. A C# string is UTF-16, so
// the exact JS id (planId, lone surrogates included) is expected on every
// path: LtxPlanJson.MakePlanIdFromJson (JSON text), LtxV11.MakePlanId (typed
// PlanV11) and InterplanetLTX.MakePlanId (typed LtxPlan, v2 only).

using System.Text.Json;
using InterplanetLtx;

public static class PrefixTests
{
    private static string? FindGolden()
    {
        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
            for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
            {
                string p = Path.Combine(d.FullName, "spec", "golden", "plan-id-prefixes.json");
                if (File.Exists(p)) return p;
            }
        return null;
    }

    private static string? S(JsonElement o, string k) =>
        o.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? LtxSecurity.JsonString(v) : null;

    private static string Prefix(string id) => id.Substring(0, id.Length - 12);

    public static void Run(Action<bool, string> Check)
    {
        string? path = FindGolden();
        Check(path != null, "prefix: spec/golden/plan-id-prefixes.json found");
        if (path == null) return;
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        var vectors = doc.RootElement.GetProperty("vectors").EnumerateArray().ToList();
        Check(vectors.Count >= 18, "prefix: vectors present");
        foreach (var gv in vectors)
        {
            string name = S(gv, "name")!;
            string want = S(gv, "planId")!;
            var plan = gv.GetProperty("plan");
            void Id(string got, string exp, string label)
            {
                Check(got == exp, $"prefix {label} {name}");
                if (got != exp) Console.WriteLine($"  got  {LtxSecurity.JsQuote(got)}\n  want {LtxSecurity.JsQuote(exp)}");
            }
            // JSON path: the raw text of the vector and its re-serialisation.
            Id(LtxPlanJson.MakePlanIdFromJson(plan.GetRawText()), want, "json");
            Id(LtxPlanJson.MakePlanIdFromJson(LtxPlanJson.Stringify(plan)), want, "json text");

            // Typed models write nodes before segments: the v2 hash matches only
            // for nodes-first vectors; v3 (canonical JSON) always.
            var keys = plan.EnumerateObject().Select(p => p.Name).ToList();
            bool nodesFirst = keys.IndexOf("nodes") < keys.IndexOf("segments");
            int v = plan.GetProperty("v").GetInt32();
            Dictionary<string, long>? delays = plan.TryGetProperty("delays", out var d) && d.ValueKind == JsonValueKind.Object
                ? d.EnumerateObject().ToDictionary(x => x.Name, x => x.Value.GetInt64()) : null;
            var nodes = plan.GetProperty("nodes").EnumerateArray().ToList();
            var segs = plan.GetProperty("segments").EnumerateArray().ToList();
            var typed = new PlanV11
            {
                V = v, Title = S(plan, "title")!, Start = S(plan, "start")!,
                Quantum = plan.GetProperty("quantum").GetInt32(), Mode = S(plan, "mode")!,
                Nodes = nodes.Select(n => new NodeV11(S(n, "id")!, S(n, "name")!, S(n, "role")!,
                    n.GetProperty("delay").GetInt64(), S(n, "location")!)).ToList(),
                Segments = segs.Select(s => new SegmentTemplateV11(S(s, "type")!, s.GetProperty("q").GetInt32(),
                    S(s, "speaker"), S(s, "label"))).ToList(),
                Delays = delays,
                PlanVersion = plan.TryGetProperty("planVersion", out var pv) ? pv.GetInt32() : null,
                PrevPlanHash = S(plan, "prevPlanHash"),
            };
            string v11 = LtxV11.MakePlanId(typed);
            Id(Prefix(v11), Prefix(want), "typed PlanV11 prefix");
            if (nodesFirst || v >= 3) Id(v11, want, "typed PlanV11");
            if (v != 2) continue;
            var legacy = new LtxPlan
            {
                V = 2, Title = typed.Title, Start = typed.Start, Quantum = typed.Quantum, Mode = typed.Mode,
                Nodes = typed.Nodes.Select(n => new LtxNode(n.Id, n.Name, n.Role, n.Delay, n.Location)).ToList(),
                Segments = typed.Segments.Select(s => new LtxSegmentTemplate(s.Type, s.Q, s.Speaker, s.Label)).ToList(),
            };
            string tid = InterplanetLTX.MakePlanId(legacy);
            Id(Prefix(tid), Prefix(want), "typed LtxPlan prefix");
            if (nodesFirst) Id(tid, want, "typed LtxPlan");
        }
        // JsUpper spot checks (special casing ToUpperInvariant lacks).
        Check(JsUpper.ToUpper("stra\u00dfe \ufb01x \u0390 \u1fb3 \u0149") == "STRASSE FIX \u0399\u0308\u0301 \u0391\u0399 \u02bcN", "JsUpper special casing");
        Check(JsUpper.ToUpper("a\ud83dz𐐨") == "A\ud83dZ𐐀", "JsUpper lone surrogate kept, astral mapped");
    }
}
