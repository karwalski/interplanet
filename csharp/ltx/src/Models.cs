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
public record LtxSegmentTemplate(string Type, int Q);
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
    public int Quantum { get; set; } = 3;
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
            sb.Append($"{{\"type\":{JsonString(Segments[i].Type)},\"q\":{Segments[i].Q}}}");
        }
        sb.Append(']');

        sb.Append('}');
        return sb.ToString();
    }

    private static string JsonString(string s)
    {
        // Escape special characters
        var sb = new System.Text.StringBuilder("\"");
        foreach (char c in s)
        {
            switch (c)
            {
                case '"':  sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20)
                        sb.Append($"\\u{(int)c:x4}");
                    else
                        sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
        return sb.ToString();
    }

    private static string JsonNumber(double d)
    {
        // Output integer if whole number (matches JS behaviour: 0 not 0.0, 1240 not 1240.0)
        if (d == Math.Floor(d) && !double.IsInfinity(d))
            return ((long)d).ToString();
        return d.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }

    // ── Manual JSON parser ────────────────────────────────────────────────────
    public static LtxPlan? FromJson(string json)
    {
        try
        {
            var plan = new LtxPlan();
            plan.V = ParseIntField(json, "v") ?? 2;
            plan.Title = ParseStringField(json, "title") ?? "";
            plan.Start = ParseStringField(json, "start") ?? "";
            plan.Quantum = ParseIntField(json, "quantum") ?? 3;
            plan.Mode = ParseStringField(json, "mode") ?? "LTX";
            plan.Segments = ParseSegments(json);
            plan.Nodes = ParseNodes(json);
            return plan;
        }
        catch
        {
            return null;
        }
    }

    private static string? ParseStringField(string json, string key)
    {
        string pattern = $"\"{key}\":\"";
        int idx = json.IndexOf(pattern);
        if (idx < 0) return null;
        idx += pattern.Length;
        var sb = new System.Text.StringBuilder();
        bool escaped = false;
        for (int i = idx; i < json.Length; i++)
        {
            char c = json[i];
            if (escaped)
            {
                switch (c)
                {
                    case '"':  sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case 'n':  sb.Append('\n'); break;
                    case 'r':  sb.Append('\r'); break;
                    case 't':  sb.Append('\t'); break;
                    default:   sb.Append(c); break;
                }
                escaped = false;
            }
            else if (c == '\\') escaped = true;
            else if (c == '"') break;
            else sb.Append(c);
        }
        return sb.ToString();
    }

    private static int? ParseIntField(string json, string key)
    {
        string pattern = $"\"{key}\":";
        int idx = json.IndexOf(pattern);
        if (idx < 0) return null;
        idx += pattern.Length;
        // skip whitespace
        while (idx < json.Length && json[idx] == ' ') idx++;
        int start = idx;
        while (idx < json.Length && (char.IsDigit(json[idx]) || json[idx] == '-')) idx++;
        if (idx == start) return null;
        return int.TryParse(json.AsSpan(start, idx - start), out int val) ? val : null;
    }

    private static List<LtxSegmentTemplate> ParseSegments(string json)
    {
        var result = new List<LtxSegmentTemplate>();
        int idx = json.IndexOf("\"segments\":[");
        if (idx < 0) return result;
        idx += "\"segments\":[".Length;
        int depth = 1;
        var sb = new System.Text.StringBuilder("[");
        while (idx < json.Length && depth > 0)
        {
            char c = json[idx];
            sb.Append(c);
            if (c == '[') depth++;
            else if (c == ']') depth--;
            idx++;
        }
        string arr = sb.ToString().TrimEnd(']').TrimStart('[');
        // Split by },{ pattern
        var items = SplitObjects(arr);
        foreach (var item in items)
        {
            string? type = ParseStringField("{" + item + "}", "type");
            int? q = ParseIntField("{" + item + "}", "q");
            if (type != null && q.HasValue)
                result.Add(new LtxSegmentTemplate(type, q.Value));
        }
        return result;
    }

    private static List<LtxNode> ParseNodes(string json)
    {
        var result = new List<LtxNode>();
        int idx = json.IndexOf("\"nodes\":[");
        if (idx < 0) return result;
        idx += "\"nodes\":[".Length;
        int depth = 1;
        var sb = new System.Text.StringBuilder("[");
        while (idx < json.Length && depth > 0)
        {
            char c = json[idx];
            sb.Append(c);
            if (c == '[') depth++;
            else if (c == ']') depth--;
            idx++;
        }
        string arr = sb.ToString().TrimEnd(']').TrimStart('[');
        var items = SplitObjects(arr);
        foreach (var item in items)
        {
            string wrapped = "{" + item + "}";
            string? id = ParseStringField(wrapped, "id");
            string? name = ParseStringField(wrapped, "name");
            string? role = ParseStringField(wrapped, "role");
            double delay = ParseDoubleField(wrapped, "delay") ?? 0.0;
            string? location = ParseStringField(wrapped, "location");
            if (id != null && name != null && role != null && location != null)
                result.Add(new LtxNode(id, name, role, delay, location));
        }
        return result;
    }

    private static double? ParseDoubleField(string json, string key)
    {
        string pattern = $"\"{key}\":";
        int idx = json.IndexOf(pattern);
        if (idx < 0) return null;
        idx += pattern.Length;
        while (idx < json.Length && json[idx] == ' ') idx++;
        int start = idx;
        while (idx < json.Length && (char.IsDigit(json[idx]) || json[idx] == '-' || json[idx] == '.')) idx++;
        if (idx == start) return null;
        return double.TryParse(json.AsSpan(start, idx - start),
            System.Globalization.NumberStyles.Any,
            System.Globalization.CultureInfo.InvariantCulture,
            out double val) ? val : null;
    }

    private static List<string> SplitObjects(string arr)
    {
        var result = new List<string>();
        int depth = 0, start = 0;
        bool inStr = false;
        bool escaped = false;
        for (int i = 0; i < arr.Length; i++)
        {
            char c = arr[i];
            if (escaped) { escaped = false; continue; }
            if (c == '\\' && inStr) { escaped = true; continue; }
            if (c == '"') inStr = !inStr;
            if (inStr) continue;
            if (c == '{') { if (depth == 0) start = i + 1; depth++; }
            else if (c == '}') { depth--; if (depth == 0) result.Add(arr.Substring(start, i - start)); }
        }
        return result;
    }
}
