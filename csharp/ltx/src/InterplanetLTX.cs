// InterplanetLTX.cs — Static API class
// C# port of ltx-sdk.js (Story 33.10)
//
// All algorithms match ltx-sdk.js exactly:
//   - Same polynomial hash (h = 31*h + charCode, uint32)
//   - Same base64url (Convert.ToBase64String → replace +/-  //_  strip =)
//   - Same JSON key order in ToJson(): v,title,start,quantum,mode,segments,nodes
//   - CRLF line endings in ICS

using System.Text;

namespace InterplanetLtx;

public static class InterplanetLTX
{
    public const string VERSION = "1.0.0";

    // ── Polynomial hash ──────────────────────────────────────────────────────
    // Matches JS: h = (Math.imul(31, h) + raw.charCodeAt(i)) >>> 0
    // Note: operate on UTF-16 char values (same as JS charCodeAt)
    private static uint DjbHash(string s)
    {
        uint h = 0;
        foreach (char c in s)
        {
            h = unchecked(h * 31u + (uint)c);
        }
        return h;
    }

    // ── Base64url helpers ────────────────────────────────────────────────────

    private static string B64Enc(string json)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(json);
        return Convert.ToBase64String(bytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }

    private static string? B64Dec(string token)
    {
        try
        {
            string std = token.Replace('-', '+').Replace('_', '/');
            int mod = std.Length % 4;
            if (mod == 2) std += "==";
            else if (mod == 3) std += "=";
            byte[] bytes = Convert.FromBase64String(std);
            return Encoding.UTF8.GetString(bytes);
        }
        catch
        {
            return null;
        }
    }

    // ── CreatePlan ───────────────────────────────────────────────────────────

    /// <summary>Create a new LTX session plan with default Earth HQ → Mars Hab-01 nodes.</summary>
    public static LtxPlan CreatePlan(
        string title = "LTX Session",
        string? start = null,
        int quantum = 3,
        string mode = "LTX",
        List<LtxNode>? nodes = null,
        string hostName = "Earth HQ",
        string hostLocation = "earth",
        string remoteName = "Mars Hab-01",
        string remoteLocation = "mars",
        double delay = 0.0,
        List<LtxSegmentTemplate>? segments = null)
    {
        if (start == null || start.Length == 0)
        {
            // Default: now + 5 min, rounded to the minute (UTC)
            var now = DateTimeOffset.UtcNow.AddMinutes(5);
            now = new DateTimeOffset(now.Year, now.Month, now.Day,
                now.Hour, now.Minute, 0, TimeSpan.Zero);
            start = now.ToString("yyyy-MM-ddTHH:mm:ssZ");
        }

        var planNodes = nodes ?? new List<LtxNode>
        {
            new LtxNode("N0", hostName,   "HOST",        0.0,   hostLocation),
            new LtxNode("N1", remoteName, "PARTICIPANT", delay, remoteLocation),
        };

        var planSegments = segments != null
            ? new List<LtxSegmentTemplate>(segments)
            : new List<LtxSegmentTemplate>(Constants.DEFAULT_SEGMENTS);

        return new LtxPlan
        {
            V        = 2,
            Title    = title,
            Start    = start,
            Quantum  = quantum,
            Mode     = mode,
            Nodes    = planNodes,
            Segments = planSegments,
        };
    }

    // ── UpgradeConfig ────────────────────────────────────────────────────────

    /// <summary>
    /// Upgrade a v1-style config dictionary to a proper LtxPlan (v2 schema).
    /// Accepts string/int values for v, txName, rxName, delay, quantum, mode, title, start.
    /// v2 configs with nodes are returned as-is when possible.
    /// </summary>
    public static LtxPlan UpgradeConfig(Dictionary<string, object> cfg)
    {
        int v = cfg.TryGetValue("v", out var vObj) && vObj != null
            ? Convert.ToInt32(vObj) : 1;
        bool hasNodes = cfg.TryGetValue("nodes", out var nodesObj)
            && nodesObj is List<LtxNode> nl && nl.Count > 0;

        string title   = cfg.TryGetValue("title",   out var t) ? t?.ToString() ?? "LTX Session" : "LTX Session";
        string start   = cfg.TryGetValue("start",   out var s) ? s?.ToString() ?? "" : "";
        int quantum    = cfg.TryGetValue("quantum", out var q) ? Convert.ToInt32(q) : Constants.DEFAULT_QUANTUM;
        string mode    = cfg.TryGetValue("mode",    out var m) ? m?.ToString() ?? "LTX" : "LTX";

        if (v >= 2 && hasNodes)
        {
            return new LtxPlan
            {
                V        = v,
                Title    = title,
                Start    = start,
                Quantum  = quantum,
                Mode     = mode,
                Nodes    = (List<LtxNode>)nodesObj!,
                Segments = cfg.TryGetValue("segments", out var seg) && seg is List<LtxSegmentTemplate> sl
                    ? sl : new List<LtxSegmentTemplate>(Constants.DEFAULT_SEGMENTS),
            };
        }

        // v1 upgrade: synthesise nodes from txName/rxName
        string rxName = cfg.TryGetValue("rxName", out var rx) ? rx?.ToString() ?? "" : "";
        string txName = cfg.TryGetValue("txName", out var tx) ? tx?.ToString() ?? "" : "Earth HQ";
        double delay  = cfg.TryGetValue("delay",  out var d)  ? Convert.ToDouble(d) : 0.0;
        string lrx    = rxName.ToLower();
        string remoteLoc = lrx.Contains("mars") ? "mars" : lrx.Contains("moon") ? "moon" : "earth";

        return new LtxPlan
        {
            V       = 2,
            Title   = title,
            Start   = start,
            Quantum = quantum,
            Mode    = mode,
            Nodes   = new List<LtxNode>
            {
                new LtxNode("N0", txName,                     "HOST",        0.0,   "earth"),
                new LtxNode("N1", rxName.Length > 0 ? rxName : "Mars Hab-01", "PARTICIPANT", delay, remoteLoc),
            },
            Segments = new List<LtxSegmentTemplate>(Constants.DEFAULT_SEGMENTS),
        };
    }

    // ── ICS text escaping ─────────────────────────────────────────────────────

    /// <summary>
    /// Escape a string for use in RFC 5545 TEXT property values.
    /// Escapes: backslash → \\, semicolon → \;, comma → \,, newline → \n
    /// </summary>
    public static string EscapeIcsText(string s)
    {
        return s
            .Replace("\\", "\\\\")
            .Replace(";",  "\\;")
            .Replace(",",  "\\,")
            .Replace("\n", "\\n");
    }

    // ── Plan-lock timeout ─────────────────────────────────────────────────────

    /// <summary>Returns the plan-lock timeout in milliseconds.</summary>
    public static double PlanLockTimeoutMs(double delaySeconds) =>
        delaySeconds * Constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000.0;

    // ── Delay violation check ─────────────────────────────────────────────────

    /// <summary>
    /// Compare declared vs measured one-way delay.
    /// Returns "ok", "violation", or "degraded".
    /// </summary>
    public static string CheckDelayViolation(double declaredDelayS, double measuredDelayS)
    {
        double diff = Math.Abs(measuredDelayS - declaredDelayS);
        if (diff > Constants.DELAY_VIOLATION_DEGRADED_S) return "degraded";
        if (diff > Constants.DELAY_VIOLATION_WARN_S)     return "violation";
        return "ok";
    }

    // ── ComputeSegments ──────────────────────────────────────────────────────

    /// <summary>Compute the timed segment list for a plan.</summary>
    /// <exception cref="ArgumentException">Thrown when quantum is less than 1.</exception>
    public static List<LtxSegment> ComputeSegments(LtxPlan plan)
    {
        if (plan.Quantum < 1)
            throw new ArgumentException($"quantum must be a positive integer, got {plan.Quantum}", nameof(plan));
        long qMs = (long)plan.Quantum * 60 * 1000;
        long t   = ParseIsoToEpochMs(plan.Start);
        var result = new List<LtxSegment>();
        foreach (var seg in plan.Segments)
        {
            long durMs = seg.Q * qMs;
            long endMs = t + durMs;
            result.Add(new LtxSegment(
                Type   : seg.Type,
                Q      : seg.Q,
                Start  : FormatIso(t),
                End    : FormatIso(endMs),
                DurMin : seg.Q * plan.Quantum,
                StartMs: t,
                EndMs  : endMs
            ));
            t = endMs;
        }
        return result;
    }

    // ── TotalMin ─────────────────────────────────────────────────────────────

    /// <summary>Total session duration in minutes.</summary>
    public static int TotalMin(LtxPlan plan)
    {
        int total = 0;
        foreach (var s in plan.Segments)
            total += s.Q * plan.Quantum;
        return total;
    }

    // ── MakePlanId ───────────────────────────────────────────────────────────

    /// <summary>
    /// Compute the deterministic plan ID string.
    /// Matches ltx-sdk.js makePlanId exactly.
    /// Example: "LTX-20240115-EARTHHQ-MARS-v2-d3317d5e"
    /// </summary>
    public static string MakePlanId(LtxPlan plan)
    {
        string date = plan.Start.Substring(0, 10).Replace("-", "");

        var nodes = plan.Nodes;
        string hostStr = nodes.Count > 0
            ? nodes[0].Name.Replace(" ", "").ToUpper()
            : "HOST";
        if (hostStr.Length > 8) hostStr = hostStr.Substring(0, 8);

        string nodeStr;
        if (nodes.Count > 1)
        {
            var parts = new List<string>();
            for (int i = 1; i < nodes.Count; i++)
            {
                string n = nodes[i].Name.Replace(" ", "").ToUpper();
                parts.Add(n.Length > 4 ? n.Substring(0, 4) : n);
            }
            nodeStr = string.Join("-", parts);
            if (nodeStr.Length > 16) nodeStr = nodeStr.Substring(0, 16);
        }
        else
        {
            nodeStr = "RX";
        }

        // Polynomial hash on the JSON string (UTF-16 char values, same as JS charCodeAt)
        string raw = plan.ToJson();
        uint h = DjbHash(raw);
        string hash = h.ToString("x8");

        return $"LTX-{date}-{hostStr}-{nodeStr}-v2-{hash}";
    }

    // ── EncodeHash ───────────────────────────────────────────────────────────

    /// <summary>Encode a plan config to a URL hash fragment (#l=...).</summary>
    public static string EncodeHash(LtxPlan plan)
    {
        return "#l=" + B64Enc(plan.ToJson());
    }

    // ── DecodeHash ───────────────────────────────────────────────────────────

    /// <summary>
    /// Decode a plan from a URL hash fragment.
    /// Accepts "#l=...", "l=...", or raw base64url token.
    /// Returns null if invalid.
    /// </summary>
    public static LtxPlan? DecodeHash(string fragment)
    {
        if (string.IsNullOrEmpty(fragment)) return null;
        string token = fragment;
        if (token.StartsWith("#")) token = token.Substring(1);
        if (token.StartsWith("l=")) token = token.Substring(2);
        string? json = B64Dec(token);
        if (json == null) return null;
        return LtxPlan.FromJson(json);
    }

    // ── BuildNodeUrls ────────────────────────────────────────────────────────

    /// <summary>Build perspective URLs for all nodes in a plan.</summary>
    public static List<LtxNodeUrl> BuildNodeUrls(LtxPlan plan, string baseUrl = "")
    {
        string hash = EncodeHash(plan);
        // strip leading #
        string hashPart = hash.StartsWith("#") ? hash.Substring(1) : hash;
        string cleanBase = baseUrl.Split('#')[0].Split('?')[0];
        var result = new List<LtxNodeUrl>();
        foreach (var node in plan.Nodes)
        {
            string nodeEnc = Uri.EscapeDataString(node.Id);
            string url = $"{cleanBase}?node={nodeEnc}#{hashPart}";
            result.Add(new LtxNodeUrl(node.Id, node.Name, node.Role, url));
        }
        return result;
    }

    // ── GenerateICS ──────────────────────────────────────────────────────────

    /// <summary>
    /// Generate LTX-extended iCalendar (.ics) content for a plan.
    /// Uses CRLF line endings as required by RFC 5545.
    /// </summary>
    public static string GenerateICS(LtxPlan plan)
    {
        var segs   = ComputeSegments(plan);
        long startMs = ParseIsoToEpochMs(plan.Start);
        long endMs   = segs.Count > 0 ? segs[segs.Count - 1].EndMs : startMs;
        string planId = MakePlanId(plan);

        var nodes = plan.Nodes;
        var host  = nodes.Count > 0
            ? nodes[0]
            : new LtxNode("N0", "Earth HQ", "HOST", 0, "earth");
        var parts = nodes.Count > 1 ? nodes.Skip(1).ToList() : new List<LtxNode>();

        string segTpl = string.Join(",", plan.Segments.Select(s => s.Type));

        string partNames = parts.Count > 0
            ? string.Join(", ", parts.Select(p => p.Name))
            : "remote nodes";
        string delayDesc = parts.Count > 0
            ? string.Join(" \u00b7 ", parts.Select(p => $"{p.Name}: {(int)Math.Round(p.Delay / 60)} min one-way"))
            : "no participant delay configured";

        string dtstamp = FmtDT(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());

        var lines = new List<string>
        {
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//InterPlanet//LTX v1.1//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            $"UID:{planId}@interplanet.live",
            $"DTSTAMP:{dtstamp}",
            $"DTSTART:{FmtDT(startMs)}",
            $"DTEND:{FmtDT(endMs)}",
            $"SUMMARY:{EscapeIcsText(plan.Title)}",
            $"DESCRIPTION:LTX session \u2014 {EscapeIcsText(host.Name)} with {EscapeIcsText(partNames)}\\n" +
                $"Signal delays: {EscapeIcsText(delayDesc)}\\n" +
                $"Mode: {EscapeIcsText(plan.Mode)} \u00b7 Segment plan: {segTpl}\\n" +
                "Generated by InterPlanet (https://interplanet.live)",
            "LTX:1",
            $"LTX-PLANID:{planId}",
            $"LTX-QUANTUM:PT{plan.Quantum}M",
            $"LTX-SEGMENT-TEMPLATE:{segTpl}",
            $"LTX-MODE:{plan.Mode}",
        };

        foreach (var n in nodes)
            lines.Add($"LTX-NODE:ID={ToId(n.Name)};ROLE={n.Role}");

        foreach (var p in parts)
        {
            int d = (int)p.Delay;
            lines.Add($"LTX-DELAY;NODEID={ToId(p.Name)}:ONEWAY-MIN={d};ONEWAY-MAX={d + 120};ONEWAY-ASSUMED={d}");
        }

        lines.Add("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY");

        foreach (var n in nodes)
        {
            if (n.Location == "mars")
                lines.Add($"LTX-LOCALTIME:NODE={ToId(n.Name)};SCHEME=LMST;PARAMS=LONGITUDE:0E");
        }

        lines.Add("END:VEVENT");
        lines.Add("END:VCALENDAR");

        return string.Join("\r\n", lines);
    }

    // ── FormatHMS ────────────────────────────────────────────────────────────

    /// <summary>Format seconds as HH:MM:SS (if &ge;1 hour) or MM:SS.</summary>
    public static string FormatHMS(int seconds)
    {
        if (seconds < 0) seconds = 0;
        int h = seconds / 3600;
        int m = (seconds % 3600) / 60;
        int s = seconds % 60;
        return h > 0
            ? $"{h:D2}:{m:D2}:{s:D2}"
            : $"{m:D2}:{s:D2}";
    }

    // ── FormatUTC ────────────────────────────────────────────────────────────

    /// <summary>Format a DateTimeOffset as "HH:MM:SS UTC".</summary>
    public static string FormatUTC(DateTimeOffset dt)
    {
        var utc = dt.ToUniversalTime();
        return $"{utc.Hour:D2}:{utc.Minute:D2}:{utc.Second:D2} UTC";
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static long ParseIsoToEpochMs(string iso)
    {
        try
        {
            return DateTimeOffset.Parse(iso,
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.AssumeUniversal).ToUnixTimeMilliseconds();
        }
        catch
        {
            return 0L;
        }
    }

    private static string FormatIso(long epochMs)
    {
        return DateTimeOffset.FromUnixTimeMilliseconds(epochMs)
            .ToUniversalTime()
            .ToString("yyyy-MM-ddTHH:mm:ssZ");
    }

    private static string FmtDT(long epochMs)
    {
        return DateTimeOffset.FromUnixTimeMilliseconds(epochMs)
            .ToUniversalTime()
            .ToString("yyyyMMdd'T'HHmmss'Z'");
    }

    private static string ToId(string name) =>
        name.Replace(" ", "-").ToUpper();
}
