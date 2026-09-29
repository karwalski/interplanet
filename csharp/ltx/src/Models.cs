// Models.cs — LTX data model types
// C# port of ltx-sdk.js (Story 33.10)

namespace InterplanetLtx;

/// <summary>Session lifecycle state.</summary>
public enum SessionState
{
    Init,
    Locked,
    Running,
    Degraded,
    Complete
}

/// <summary>String constants for session states.</summary>
public static class SessionStateNames
{
    public static readonly string[] All = { "INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE" };
}

public record LtxNode(string Id, string Name, string Role, double Delay, string Location);
/// <summary>
/// A segment in a plan's segment list. Speaker (a node id) and Label (an
/// agenda title) are the optional attribution fields of LTX-SPECIFICATION.md
/// section 3.4.1; null means absent, and absent fields are not serialised.
/// </summary>
public record LtxSegmentTemplate(string Type, int Q, string? Speaker = null, string? Label = null);
public record LtxSegment(string Type, int Q, string Start, string End, int DurMin, long StartMs, long EndMs);
public record LtxNodeUrl(string NodeId, string Name, string Role, string Url);

/// <summary>
/// LTX session plan — mutable class with manual JSON serialisation
/// to guarantee exact key order: v, title, start, quantum, mode, nodes, segments.
/// </summary>
public class LtxPlan
{
    public int V { get; set; } = 2;
    public string Title { get; set; } = "";
    public string Start { get; set; } = "";
    public int Quantum { get; set; } = 5;
    public string Mode { get; set; } = "LTX";
    public List<LtxNode> Nodes { get; set; } = new();
    public List<LtxSegmentTemplate> Segments { get; set; } = new();

    // ── Manual JSON builder — exact key order matching conformance vectors ──────
    // Order: v, title, start, quantum, mode, nodes, segments
    // (nodes before segments — matches canonical conformance vector key order)
    public string ToJson()
    {
        var sb = new System.Text.StringBuilder();
        sb.Append('{');
        sb.Append($"\"v\":{V},");
        sb.Append($"\"title\":{JsonString(Title)},");
        sb.Append($"\"start\":{JsonString(Start)},");
        sb.Append($"\"quantum\":{Quantum},");
        sb.Append($"\"mode\":{JsonString(Mode)},");

        // nodes array
        sb.Append("\"nodes\":[");
        for (int i = 0; i < Nodes.Count; i++)
        {
            if (i > 0) sb.Append(',');
            var n = Nodes[i];
            sb.Append($"{{\"id\":{JsonString(n.Id)},\"name\":{JsonString(n.Name)},\"role\":{JsonString(n.Role)},\"delay\":{JsonNumber(n.Delay)},\"location\":{JsonString(n.Location)}}}");
        }
        sb.Append("],");

        // segments array
        sb.Append("\"segments\":[");
        for (int i = 0; i < Segments.Count; i++)
        {
            if (i > 0) sb.Append(',');
            // Attributed segments (section 3.4.1): speaker and label follow type
            // and q, only when present, as ltx-sdk.js writes them.
            var s = Segments[i];
            sb.Append($"{{\"type\":{JsonString(s.Type)},\"q\":{s.Q}");
            if (s.Speaker != null) sb.Append($",\"speaker\":{JsonString(s.Speaker)}");
            if (s.Label != null) sb.Append($",\"label\":{JsonString(s.Label)}");
            sb.Append('}');
        }
        sb.Append(']');

        sb.Append('}');
        return sb.ToString();
    }

    // JSON.stringify string quoting (also escapes \b and \f like JS).
    private static string JsonString(string s) => LtxSecurity.JsQuote(s);

    private static string JsonNumber(double d)
    {
        // Output integer if whole number (matches JS behaviour: 0 not 0.0, 1240 not 1240.0)
        if (d == Math.Floor(d) && !double.IsInfinity(d))
            return ((long)d).ToString();
        return d.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }

    // ── JSON parser ──────────────────────────────────────────────────────────
    // Strings go through LtxSecurity.JsonString so every escape (including a
    // lone surrogate, which JSON.stringify writes as \uXXXX) is decoded.
    public static LtxPlan? FromJson(string json)
    {
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind != System.Text.Json.JsonValueKind.Object) return null;
            var plan = new LtxPlan();
            plan.V = Int(root, "v") ?? 2;
            plan.Title = Str(root, "title") ?? "";
            plan.Start = Str(root, "start") ?? "";
            plan.Quantum = Int(root, "quantum") ?? 5;
            plan.Mode = Str(root, "mode") ?? "LTX";
            if (root.TryGetProperty("nodes", out var nodes) && nodes.ValueKind == System.Text.Json.JsonValueKind.Array)
            {
                foreach (var n in nodes.EnumerateArray())
                {
                    string? id = Str(n, "id"), name = Str(n, "name"), role = Str(n, "role"), location = Str(n, "location");
                    if (id != null && name != null && role != null && location != null)
                        plan.Nodes.Add(new LtxNode(id, name, role, Num(n, "delay") ?? 0.0, location));
                }
            }
            if (root.TryGetProperty("segments", out var segs) && segs.ValueKind == System.Text.Json.JsonValueKind.Array)
            {
                foreach (var sg in segs.EnumerateArray())
                {
                    string? type = Str(sg, "type");
                    int? q = Int(sg, "q");
                    if (type != null && q.HasValue)
                        plan.Segments.Add(new LtxSegmentTemplate(type, q.Value, Str(sg, "speaker"), Str(sg, "label")));
                }
            }
            return plan;
        }
        catch
        {
            return null;
        }
    }

    private static System.Text.Json.JsonElement? Prop(System.Text.Json.JsonElement o, string key) =>
        o.ValueKind == System.Text.Json.JsonValueKind.Object && o.TryGetProperty(key, out var v) ? v : null;

    private static string? Str(System.Text.Json.JsonElement o, string key) =>
        Prop(o, key) is { ValueKind: System.Text.Json.JsonValueKind.String } e ? LtxSecurity.JsonString(e) : null;

    private static double? Num(System.Text.Json.JsonElement o, string key) =>
        Prop(o, key) is { ValueKind: System.Text.Json.JsonValueKind.Number } e ? e.GetDouble() : null;

    private static int? Int(System.Text.Json.JsonElement o, string key) =>
        Prop(o, key) is { ValueKind: System.Text.Json.JsonValueKind.Number } e && e.TryGetInt32(out int i) ? i : null;
}
