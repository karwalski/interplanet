// ParityTests.cs — LTX parity cascade (issue #27): golden planId vectors
// (spec/golden/plan-ids.json), validatePlan reserved streams/branching, and
// the decision register + merge snapshot. Mirrors javascript/ltx/tests/run.js.

using System.Text.Json;
using InterplanetLtx;

public static class ParityTests
{
    private static string? FindGolden()
    {
        var dir = new DirectoryInfo(Directory.GetCurrentDirectory());
        for (var d = dir; d != null; d = d.Parent)
        {
            string p = Path.Combine(d.FullName, "spec", "golden", "plan-ids.json");
            if (File.Exists(p)) return p;
        }
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d != null; d = d.Parent)
        {
            string p = Path.Combine(d.FullName, "spec", "golden", "plan-ids.json");
            if (File.Exists(p)) return p;
        }
        return null;
    }

    private static string? S(JsonElement o, string k) =>
        o.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>Typed v1.1 plan from the wire form (fields PlanV11 models).</summary>
    private static PlanV11 ToPlanV11(JsonElement p)
    {
        Dictionary<string, long>? delays = null;
        if (p.TryGetProperty("delays", out var d) && d.ValueKind == JsonValueKind.Object)
            delays = d.EnumerateObject().ToDictionary(x => x.Name, x => x.Value.GetInt64());
        return new PlanV11
        {
            V = p.GetProperty("v").GetInt32(),
            Title = S(p, "title") ?? "",
            Start = S(p, "start") ?? "",
            Quantum = p.GetProperty("quantum").GetInt32(),
            Mode = S(p, "mode") ?? "LTX",
            Nodes = p.GetProperty("nodes").EnumerateArray().Select(n => new NodeV11(
                S(n, "id")!, S(n, "name")!, S(n, "role")!, n.GetProperty("delay").GetInt64(), S(n, "location")!)).ToList(),
            Segments = p.GetProperty("segments").EnumerateArray().Select(s => new SegmentTemplateV11(
                S(s, "type")!, s.GetProperty("q").GetInt32(), S(s, "speaker"), S(s, "label"))).ToList(),
            Delays = delays,
            PlanVersion = p.TryGetProperty("planVersion", out var pv) ? pv.GetInt32() : null,
            PrevPlanHash = S(p, "prevPlanHash"),
        };
    }

    /// <summary>Shallow copy of a plan object with fields replaced/added.</summary>
    private static string With(JsonElement plan, Dictionary<string, string> extraJson)
    {
        var parts = new List<string>();
        foreach (var p in plan.EnumerateObject())
            if (!extraJson.ContainsKey(p.Name))
                parts.Add(LtxSecurity.JsQuote(p.Name) + ":" + LtxPlanJson.Stringify(p.Value));
        foreach (var kv in extraJson) parts.Add(LtxSecurity.JsQuote(kv.Key) + ":" + kv.Value);
        return "{" + string.Join(",", parts) + "}";
    }

    private static List<string> Codes(string json) => LtxPlanJson.ValidatePlan(json).Codes;

    public static void Run(Action<bool, string> Check)
    {
        // ── Golden planId vectors ────────────────────────────────────────────
        string? path = FindGolden();
        Check(path != null, "golden: spec/golden/plan-ids.json found");
        if (path == null) return;
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        var vectors = doc.RootElement.GetProperty("vectors").EnumerateArray().ToList();
        Check(vectors.Count >= 9, "golden: vectors present");
        var byName = vectors.ToDictionary(v => S(v, "name")!, v => v);
        int typedCovered = 0, legacyCovered = 0;
        foreach (var gv in vectors)
        {
            string name = S(gv, "name")!;
            var plan = gv.GetProperty("plan");
            string json = LtxPlanJson.Stringify(plan);
            string planId = S(gv, "planId")!;
            Check(LtxPlanJson.MakePlanIdFromJson(json) == planId, $"golden planId {name}");
            if (S(gv, "planHash") is string ph)
                Check(LtxPlanJson.PlanHashFromJson(json) == ph, $"golden planHash {name}");
            // Typed models serialise v2 plans in the fixed order v, title,
            // start, quantum, mode, nodes, segments and drop unmodelled fields,
            // so their planId is only comparable when that projection is lossless.
            var typed = ToPlanV11(plan);
            bool lossless = typed.V >= 3
                ? LtxSecurity.CanonicalJSON(typed.ToDict()) == LtxSecurity.CanonicalJSON(plan)
                : LtxV11.ToJsonV2(typed) == json;
            if (lossless)
            {
                typedCovered++;
                Check(LtxV11.MakePlanId(typed) == planId, $"golden typed PlanV11 planId {name}");
            }
            if (typed.V == 2 && typed.Segments.All(s => s.Speaker == null && s.Label == null))
            {
                var legacy = new LtxPlan
                {
                    V = typed.V, Title = typed.Title, Start = typed.Start, Quantum = typed.Quantum, Mode = typed.Mode,
                    Nodes = typed.Nodes.Select(n => new LtxNode(n.Id, n.Name, n.Role, n.Delay, n.Location)).ToList(),
                    Segments = typed.Segments.Select(s => new LtxSegmentTemplate(s.Type, s.Q)).ToList(),
                };
                if (legacy.ToJson() == json)
                {
                    legacyCovered++;
                    Check(InterplanetLTX.MakePlanId(legacy) == planId, $"golden typed LtxPlan planId {name}");
                }
            }
        }
        Check(typedCovered >= 3, $"golden: typed PlanV11 MakePlanId covers {typedCovered} vectors");
        Check(legacyCovered >= 1, $"golden: typed LtxPlan MakePlanId covers {legacyCovered} vectors");
        Check(S(byName["v2-freeze-check"], "planId") == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d", "golden v2 freeze anchor");
        Check(S(byName["v2-unicode-title"], "planId") == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8", "golden v2 unicode anchor");
        Check(S(byName["v2-createPlan-default"], "planId") != S(byName["v2-key-order-sensitive"], "planId"),
            "golden v2 order-sensitive");
        Check(S(byName["v3-upgrade-delays"], "planId") == S(byName["v3-key-order-insensitive"], "planId"),
            "golden v3 order-insensitive");
        Check(S(byName["v3-amendment"].GetProperty("plan"), "prevPlanHash") == S(byName["v3-upgrade-delays"], "planHash"),
            "golden v3 amendment chain hash");
        Check(InterplanetLTX.CreatePlan().Quantum == 5 && Constants.DEFAULT_QUANTUM == 5 && new PlanV11().Quantum == 5,
            "createPlan default quantum is 5");
        Check(LtxSecurity.CanonicalJSON(new Dictionary<string, object?> { ["t"] = "Q&A <é>" }) == "{\"t\":\"Q&A <é>\"}",
            "canonical JSON keeps &, <, > and non-ASCII raw (JSON.stringify)");

        // ── validatePlan: reserved streams / branching (§3.5, §7) ─────────────
        foreach (var gv in vectors)
            Check(LtxPlanJson.ValidatePlan(gv.GetProperty("plan")).Valid, $"validatePlan accepts golden {S(gv, "name")}");
        var vpBase = byName["v3-upgrade-delays"].GetProperty("plan");
        var vpV2 = byName["v2-freeze-check"].GetProperty("plan");
        Check(LtxPlanJson.ValidatePlan(With(vpBase, new() { ["streams"] = "[]" })).Valid, "validatePlan v3 empty streams ok");
        var vpStreams = LtxPlanJson.ValidatePlan(With(vpBase, new() { ["streams"] = "[{\"id\":\"S1\"}]" }));
        Check(!vpStreams.Valid && vpStreams.Codes.Contains("reserved_streams"), "validatePlan non-empty streams");
        Check(vpStreams.Errors.First(e => e.Code == "reserved_streams").Path == "streams", "validatePlan streams error path");
        Check(Codes(With(vpBase, new() { ["streams"] = "\"S1\"" })).Contains("reserved_streams"), "validatePlan streams non-array");
        Check(Codes(With(vpBase, new() { ["segments"] = "[{\"type\":\"TX\",\"q\":1,\"stream\":\"S1\"}]" }))
            .Contains("reserved_streams"), "validatePlan segment stream");
        Check(Codes(With(vpBase, new() { ["branches"] = "[]" })).Contains("reserved_branching"), "validatePlan branches");
        Check(Codes(With(vpBase, new() { ["branching"] = "{\"mode\":\"local\"}" })).Contains("reserved_branching"),
            "validatePlan branching");
        var vpSegBranch = LtxPlanJson.ValidatePlan(With(vpBase, new() { ["segments"] = "[{\"type\":\"CAUCUS\",\"q\":1,\"branch\":\"B1\"}]" }));
        Check(vpSegBranch.Codes.Contains("reserved_branching") && vpSegBranch.Errors[0].Path == "segments[0].branch",
            "validatePlan segment branch");
        Check(Codes(With(vpV2, new() { ["streams"] = "[]" })).Contains("v3_field_in_v2"), "validatePlan v2 streams is v3 field");
        Check(Codes(With(vpV2, new() { ["branching"] = "true" })).Contains("reserved_branching"), "validatePlan v2 branching");
        Check(Codes("null").Contains("not_an_object"), "validatePlan non-object");
        Check(Codes(With(vpV2, new() { ["v"] = "7" })).Contains("invalid_version"), "validatePlan bad version");
        Check(Codes(With(vpV2, new() { ["nodes"] = "[" + string.Join(",",
                vpV2.GetProperty("nodes").EnumerateArray().Reverse().Select(LtxPlanJson.Stringify)) + "]" }))
            .Contains("invalid_host"), "validatePlan host not first");
        Check(Codes(With(vpBase, new() { ["delays"] = "{\"N1|N0\":860}" })).Contains("invalid_delays"),
            "validatePlan unsorted delays key");
        Check(Codes(With(vpV2, new() { ["segments"] = "[{\"type\":\"TX\",\"q\":1,\"speaker\":\"N9\"}]" }))
            .Contains("unknown_speaker"), "validatePlan unknown speaker");
        Check(Codes(With(vpV2, new() { ["quantum"] = "0" })).Contains("invalid_quantum"), "validatePlan quantum out of range");
        var typedBase = ToPlanV11(vpBase);
        Check(LtxPlanJson.ValidatePlan(typedBase).Valid, "validatePlan typed PlanV11 projection valid");
        string? sessionCode = null;
        try { LtxV11.CreateSession(typedBase, "id"); } catch (ReservedFieldException e) { sessionCode = e.Code; }
        Check(sessionCode == null, "createSession accepts typed plan");
        ReservedFieldException? rfe = null;
        try
        {
            using var bad = JsonDocument.Parse(With(vpBase, new() { ["streams"] = "[1]" }));
            LtxPlanJson.AssertNoReservedFields(bad.RootElement, "createSession");
        }
        catch (ReservedFieldException e) { rfe = e; }
        Check(rfe != null && rfe.Code == "reserved_streams" && rfe.Message.StartsWith("createSession:") && rfe.Errors.Count == 1,
            "AssertNoReservedFields throws with code and errors");

        // ── Decision register (§10.3) + merge snapshot ───────────────────────
        var host = LtxSecurity.GenerateNIK(nodeLabel: "HOST");
        var mars = LtxSecurity.GenerateNIK(nodeLabel: "MARS");
        var cache = new Dictionary<string, NikV11>
        {
            ["N0"] = new NikV11("N0", host.Nik.PublicKeyB64, host.Nik.ValidUntil),
            ["N1"] = new NikV11("N1", mars.Nik.PublicKeyB64, mars.Nik.ValidUntil),
        };
        RegisterEntryV11 Mk(string type, Dictionary<string, object?> content, string nodeId, int seq, string ts,
            string priv, string? entryId = null) =>
            LtxV11.CreateRegisterEntry(type, content, "LTX-DEC-TEST", nodeId, seq, ts, priv, entryId);
        var dec1 = Mk("decision", new() { ["text"] = "Proceed with EVA-3", ["rationale"] = "Weather window", ["originWindow"] = "W2" },
            "N0", 1, "2026-08-01T12:00:00.000Z", host.PrivateKeyB64);
        Check(dec1.EntryId == "DEC-N0-1", "decision id prefix DEC");
        Check(LtxV11.VerifyRegisterEntry(dec1, cache).Valid, "decision entry verifies");
        var r1 = LtxV11.ReduceDecisions(new[] { dec1 });
        Check(r1.ById["DEC-N0-1"].Status == "RECORDED" && r1.ById["DEC-N0-1"].Version == 1, "decision RECORDED");
        Check(r1.ById["DEC-N0-1"].Text == "Proceed with EVA-3" && r1.ById["DEC-N0-1"].RecordedBy == "N0" &&
              r1.ById["DEC-N0-1"].Rationale == "Weather window", "decision fields");
        var decRev = Mk("decision_update", new() { ["did"] = "DEC-N0-1", ["text"] = "Proceed with EVA-3 at 14:00", ["version"] = 2 },
            "N1", 1, "2026-08-01T12:10:00.000Z", mars.PrivateKeyB64);
        Check(decRev.EntryId == "DEC-N1-1", "decision_update id prefix DEC");
        var decRes = Mk("decision_update", new() { ["did"] = "DEC-N0-1", ["status"] = "RESCINDED", ["version"] = 3 },
            "N0", 2, "2026-08-01T12:20:00.000Z", host.PrivateKeyB64);
        var r2 = LtxV11.ReduceDecisions(new[] { decRes, dec1, decRev });
        Check(r2.ById["DEC-N0-1"].Text == "Proceed with EVA-3 at 14:00", "decision update applied");
        Check(r2.ById["DEC-N0-1"].Status == "RESCINDED" && r2.ById["DEC-N0-1"].Version == 3, "decision RESCINDED v3");
        Check(r2.ById["DEC-N0-1"].Editor == "N0", "decision editor recorded");
        Check(r2.Superseded.Contains(decRev.EntryId), "decision older update superseded");
        var decA = Mk("decision_update", new() { ["did"] = "DEC-N0-1", ["text"] = "From N0", ["version"] = 5 },
            "N0", 7, "2026-08-01T13:00:00.000Z", host.PrivateKeyB64);
        var decB = Mk("decision_update", new() { ["did"] = "DEC-N0-1", ["text"] = "From N1", ["version"] = 5 },
            "N1", 7, "2026-08-01T13:00:00.000Z", mars.PrivateKeyB64);
        var c1 = LtxV11.ReduceDecisions(new[] { dec1, decB, decA });
        var c2 = LtxV11.ReduceDecisions(new[] { decA, dec1, decB });
        Check(c1.ById["DEC-N0-1"].Text == "From N0", "decision tie lowest nodeId wins");
        Check(c1.Superseded.Contains(decB.EntryId) && !c1.Superseded.Contains(decA.EntryId), "decision tie loser superseded");
        Check(c1.ById["DEC-N0-1"] == c2.ById["DEC-N0-1"] && c1.Superseded.SequenceEqual(c2.Superseded),
            "decision reduce order-independent");
        var decHi = Mk("decision_update", new() { ["did"] = "DEC-N0-1", ["text"] = "N1 v6", ["version"] = 6 },
            "N1", 8, "2026-08-01T12:30:00.000Z", mars.PrivateKeyB64);
        Check(LtxV11.ReduceDecisions(new[] { dec1, decA, decHi }).ById["DEC-N0-1"].Text == "N1 v6", "decision higher version wins");
        var decOrphan = Mk("decision_update", new() { ["did"] = "DEC-NOPE-1", ["version"] = 2 },
            "N1", 9, "2026-08-01T12:40:00.000Z", mars.PrivateKeyB64);
        var decDup = Mk("decision", new() { ["text"] = "dup" }, "N1", 10, "2026-08-01T12:50:00.000Z",
            mars.PrivateKeyB64, entryId: "DEC-N0-1");
        var r3 = LtxV11.ReduceDecisions(new[] { dec1, decOrphan, decDup });
        Check(r3.Superseded.Contains("DEC-N1-9"), "decision orphan update superseded");
        Check(r3.ById["DEC-N0-1"].Text == "Proceed with EVA-3" && r3.ById["DEC-N0-1"].RecordedBy == "N0",
            "decision duplicate create ignored");
        Check(LtxV11.ReduceDecisions(new[] { dec1, decRev }).ById.Count == 1 &&
              LtxV11.ReduceActions(new[] { dec1 }).ById.Count == 0, "decision reducer ignores others");
        var (merged, snap) = LtxV11.RunMergeSegment(new[] { dec1 }, new[] { decRev }, cache,
            "LTX-DEC-TEST", "N0", 99, "2026-08-01T15:00:00.000Z", host.PrivateKeyB64);
        var decReg = (Dictionary<string, object?>)snap.Content["decisionRegister"]!;
        Check((int)((Dictionary<string, object?>)decReg["DEC-N0-1"]!)["version"]! == 2, "snapshot decisionRegister");
        Check(snap.EntryId == "MRG-N0-99" && (int)snap.Content["entryCount"]! == 2 &&
              (int)snap.Content["rejectedCount"]! == 0 && merged.Entries.Count == 2, "snapshot entry id and counts");
        Check(LtxV11.VerifyRegisterEntry(snap, cache).Valid, "snapshot signature verifies");
        var rej = LtxV11.MergeLogs(new[] { dec1 }, new[] { decRev },
            new Dictionary<string, NikV11> { ["N0"] = cache["N0"] });
        Check(rej.Entries.Count == 1 && rej.Rejected.Count == 1 && rej.Rejected[0].Reason == "key_not_in_cache",
            "mergeLogs rejects unverifiable entries");
    }

    /// <summary>
    /// Issue #36: the typed LtxPlan wire JSON is exactly JSON.stringify
    /// (control characters, lone surrogates), MakePlanId strips JS \s
    /// whitespace (not only spaces), and segments carry optional speaker/label.
    /// </summary>
    public static void RunIssue36(Action<bool, string> Check)
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
        // JSON.stringify of the same plan object and its makePlanId, from ltx-sdk.js (node 22).
        const string ctlJs = "{\"v\":2,\"title\":\"Ctl\\u0001\\b\\f\\n\\r\\t\\\"\\\\\\u001f\u007f\\ud800 \ud83d\ude80\",\"start\":\"2026-03-15T14:00:00.000Z\",\"quantum\":3,\"mode\":\"LTX-ASYNC\",\"nodes\":[{\"id\":\"N0\",\"name\":\"Earth\\tHQ\",\"role\":\"HOST\",\"delay\":0,\"location\":\"earth\"},{\"id\":\"N1\",\"name\":\"Ma\u00a0r\u3000s\u2009Hab-01\",\"role\":\"PARTICIPANT\",\"delay\":840,\"location\":\"mars\"},{\"id\":\"N2\",\"name\":\"L-1\u2028Gate\ufeffway\\n\",\"role\":\"PARTICIPANT\",\"delay\":2,\"location\":\"moon\"}],\"segments\":[{\"type\":\"PLAN_CONFIRM\",\"q\":2},{\"type\":\"TX\",\"q\":3,\"speaker\":\"N0\",\"label\":\"Opening\\tremarks\"},{\"type\":\"RX\",\"q\":3},{\"type\":\"TX\",\"q\":2,\"speaker\":\"N1\"},{\"type\":\"TX\",\"q\":1,\"label\":\"Q&A \ud83d\udd34\"},{\"type\":\"BUFFER\",\"q\":1}]}";
        const string ctlJsId = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-39d48c2a";
        string json = ctl.ToJson();
        Check(json == ctlJs, "issue36: ToJson == JSON.stringify (control chars, lone surrogate, speaker/label)");
        Check(!json.Any(c => c < ' '), "issue36: ToJson has no raw control characters");
        Check(json.Contains("{\"type\":\"RX\",\"q\":3}"), "issue36: unattributed segment has no speaker/label");
        Check(LtxPlanJson.Stringify(JsonDocument.Parse(json).RootElement) == json,
            "issue36: ToJson re-stringifies identically (lone surrogate kept)");
        string id = InterplanetLTX.MakePlanId(ctl);
        Check(id == ctlJsId, "issue36: MakePlanId == JS makePlanId");
        Check(LtxPlanJson.MakePlanIdFromJson(json) == id, "issue36: MakePlanId == MakePlanIdFromJson(wire JSON)");
        var back = InterplanetLTX.DecodeHash(InterplanetLTX.EncodeHash(ctl));
        Check(back != null && back.Title == ctl.Title && back.Nodes.SequenceEqual(ctl.Nodes)
              && back.Segments.SequenceEqual(ctl.Segments), "issue36: DecodeHash round-trips title, names, speaker/label");
        Check(back != null && InterplanetLTX.MakePlanId(back) == id, "issue36: decoded plan has the same planId");

        // JS \s is not char.IsWhiteSpace: U+FEFF is stripped, U+0085 is kept.
        var ws = new LtxPlan
        {
            V = 2, Title = "t", Start = "2026-03-15T14:00:00.000Z", Quantum = 3, Mode = "LTX",
            Nodes = new List<LtxNode> {
                new("N0", "\u00a0Ea\u1680rth\u205fHQ\u202f", "HOST", 0, "earth"),
                new("N1", "\ufeffM\va\fr\u3000s", "PARTICIPANT", 0, "mars"),
                new("N2", "X\u0085Y", "PARTICIPANT", 0, "moon"),
            },
            Segments = new List<LtxSegmentTemplate> { new("TX", 1) },
        };
        const string wsJsId = "LTX-20260315-EARTHHQ-MARS-X\u0085Y-v2-aa92073b";
        Check(InterplanetLTX.MakePlanId(ws) == wsJsId, "issue36: MakePlanId strips JS \\s whitespace only");
        Check(LtxPlanJson.MakePlanIdFromJson(ws.ToJson()) == wsJsId, "issue36: MakePlanIdFromJson strips JS \\s whitespace only");
        var wsV11 = new PlanV11
        {
            V = 2, Title = "t", Start = "2026-03-15T14:00:00.000Z", Quantum = 3, Mode = "LTX",
            Nodes = ws.Nodes.Select(n => new NodeV11(n.Id, n.Name, n.Role, (long)n.Delay, n.Location)).ToList(),
            Segments = new List<SegmentTemplateV11> { new("TX", 1) },
        };
        Check(LtxV11.MakePlanId(wsV11) == wsJsId, "issue36: PlanV11 MakePlanId strips JS \\s whitespace only");
    }
}
