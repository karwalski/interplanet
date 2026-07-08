// V11.cs — LTX v1.1 core subset (Epic 72, Story 72.3)
// C# port of the TypeScript reference (segments.ts / session.ts / amend.ts /
// registers.ts / cbor.ts / cose.ts).
//
// Features:
//   1. v3 planId (SHA-256 over RFC 8785 canonical JSON) + pairDelay +
//      ComputeSegmentsFor (frozen v2 polynomial path kept byte-identical)
//   2. Pure transition() session state machine (LTX-SPECIFICATION.md §5)
//   3. Amendment-chain verification (§6.4, LTX-SECURITY.md §7.6)
//   4. Signed register entries + deterministic reducers (§8.2/§9/§10)
//   5. Deterministic CBOR decoder + COSE_Sign1 verification (RFC 8949/9052)

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using NSec.Cryptography;

namespace InterplanetLtx;

// ── v1.1 data model ──────────────────────────────────────────────────────────

public record NodeV11(string Id, string Name, string Role, long Delay, string Location);

public record SegmentTemplateV11(string Type, int Q, string? Speaker = null, string? Label = null);

/// <summary>LTX plan supporting both v2 (frozen) and v3 (§4.4) schemas.</summary>
public record PlanV11
{
    public int V { get; init; } = 2;
    public string Title { get; init; } = "";
    public string Start { get; init; } = "";
    public int Quantum { get; init; } = 5;
    public string Mode { get; init; } = "LTX";
    public List<NodeV11> Nodes { get; init; } = new();
    public List<SegmentTemplateV11> Segments { get; init; } = new();
    /// <summary>v3 pair-delay matrix; key "A|B" with node ids sorted.</summary>
    public Dictionary<string, long>? Delays { get; init; }
    public int? PlanVersion { get; init; }
    public string? PrevPlanHash { get; init; }

    /// <summary>Generic dictionary projection used for canonical JSON hashing.</summary>
    public Dictionary<string, object?> ToDict()
    {
        var d = new Dictionary<string, object?>
        {
            ["v"] = V,
            ["title"] = Title,
            ["start"] = Start,
            ["quantum"] = Quantum,
            ["mode"] = Mode,
            ["nodes"] = Nodes.Select(n => (object?)new Dictionary<string, object?>
            {
                ["id"] = n.Id, ["name"] = n.Name, ["role"] = n.Role,
                ["delay"] = n.Delay, ["location"] = n.Location,
            }).ToList(),
            ["segments"] = Segments.Select(s =>
            {
                var seg = new Dictionary<string, object?> { ["type"] = s.Type, ["q"] = s.Q };
                if (s.Speaker != null) seg["speaker"] = s.Speaker;
                if (s.Label != null) seg["label"] = s.Label;
                return (object?)seg;
            }).ToList(),
        };
        if (Delays != null)
        {
            var delays = new Dictionary<string, object?>();
            foreach (var kv in Delays) delays[kv.Key] = kv.Value;
            d["delays"] = delays;
        }
        if (PlanVersion != null) d["planVersion"] = PlanVersion.Value;
        if (PrevPlanHash != null) d["prevPlanHash"] = PrevPlanHash;
        return d;
    }
}

/// <summary>A computed segment from a specific viewer's perspective (§14.3).</summary>
public record ViewerSegmentV11(
    string Type, int Q, long StartMs, long EndMs, int DurMin,
    string? Speaker, string? Label, string Perspective, long ArrivalOffsetS);

// ── v1.1 security envelope (TRANSITIONAL JSON COSE_Sign1, LTX-SECURITY §7.2) ─

public record NikV11(string NodeId, string PublicKeyB64, string ValidUntil);

public record CoseSign1Json(string Protected, string Kid, string Payload, string Signature);

public record SignedPlanV11(PlanV11 Plan, CoseSign1Json CoseSign1);

// ── Register entries (LTX-SECURITY.md §9.5) ──────────────────────────────────

public record RegisterEntryV11(
    string EntryId, string SessionId, string NodeId, int Seq, string Type,
    Dictionary<string, object?> Content, string Timestamp, string Sig);

public record QuestionStateV11
{
    public string Qid { get; init; } = "";
    public string Text { get; init; } = "";
    public string Submitter { get; init; } = "";
    public string? Urgency { get; init; }
    public string? IntendedWindow { get; init; }
    public string Status { get; init; } = "OPEN";
    public string? Response { get; init; }
    public string? Responder { get; init; }
    public int Version { get; init; } = 1;
}

public record ActionStateV11
{
    public string Aid { get; init; } = "";
    public string Description { get; init; } = "";
    public string? Owner { get; init; }
    public string? DueTimeUTC { get; init; }
    public string? OriginWindow { get; init; }
    public string Status { get; init; } = "PROPOSED";
    public int Version { get; init; } = 1;
}

public record RegisterReductionV11<T>(Dictionary<string, T> ById, List<string> Superseded);

// ── Session state machine (LTX-SPECIFICATION.md §5) ─────────────────────────

public record SessionEventV11(
    string Type, long NowMs,
    string? NodeId = null, string? PlanId = null, long? MeasuredDelayS = null,
    string? Decision = null, bool? Verified = null, int? PlanVersion = null,
    List<string>? AffectedNodeIds = null, string? Reason = null);

public record PendingAmendmentV11(
    string PlanId, int PlanVersion, List<string> AffectedNodeIds,
    List<string> Confirmed, long ProposedAtMs, long TimeoutMs);

public record SessionCtxV11
{
    public string State { get; init; } = "DRAFT";
    public PlanV11 Plan { get; init; } = new();
    public string PlanId { get; init; } = "";
    public string SessionRootPlanId { get; init; } = "";
    public int PlanVersion { get; init; } = 1;
    /// <summary>"FULL", "QUORUM", or null.</summary>
    public string? Lock { get; init; }
    public long? LockStartedAtMs { get; init; }
    public long LockTimeoutMs { get; init; }
    public Dictionary<string, string> Confirmations { get; init; } = new();
    public List<string> Mismatched { get; init; } = new();
    public int QuorumThreshold { get; init; } = 1;
    public List<string>? Subset { get; init; }
    public List<string> DegradedReasons { get; init; } = new();
    public string? ResumeState { get; init; }
    public PendingAmendmentV11? PendingAmendment { get; init; }
}

// ── CBOR (RFC 8949 deterministic subset) ─────────────────────────────────────

/// <summary>Tagged CBOR value (major type 6).</summary>
public sealed class CborTagV11
{
    public long Tag { get; }
    public object? Value { get; }
    public CborTagV11(long tag, object? value) { Tag = tag; Value = value; }
}

public record VerifyResultV11(bool Valid, string? Reason = null);

// ── Static API ───────────────────────────────────────────────────────────────

public static class LtxV11
{
    public const string VERSION = "1.1.0";

    public const int COSE_SIGN1_TAG = 18;
    public const int COSE_ALG_ED25519 = -19;

    private static readonly SignatureAlgorithm Ed = SignatureAlgorithm.Ed25519;

    // ── Canonical JSON / hashing helpers ─────────────────────────────────────

    private static string Sha256Hex(byte[] data) =>
        Convert.ToHexString(SHA256.HashData(data)).ToLower();

    /// <summary>SHA-256 hex of the RFC 8785 canonical JSON of a plan (amend.ts).</summary>
    public static string PlanHash(PlanV11 plan) =>
        Sha256Hex(Encoding.UTF8.GetBytes(LtxSecurity.CanonicalJSON(plan.ToDict())));

    /// <summary>
    /// FROZEN v2 JSON serialisation — insertion-order JSON.stringify equivalent:
    /// v,title,start,quantum,mode,nodes(id,name,role,delay,location),
    /// segments(type,q[,speaker][,label]). Must stay byte-identical (§4.3).
    /// </summary>
    public static string ToJsonV2(PlanV11 p)
    {
        var sb = new StringBuilder();
        sb.Append('{');
        sb.Append("\"v\":").Append(p.V);
        sb.Append(",\"title\":").Append(JsonSerializer.Serialize(p.Title));
        sb.Append(",\"start\":").Append(JsonSerializer.Serialize(p.Start));
        sb.Append(",\"quantum\":").Append(p.Quantum);
        sb.Append(",\"mode\":").Append(JsonSerializer.Serialize(p.Mode));
        sb.Append(",\"nodes\":[");
        for (int i = 0; i < p.Nodes.Count; i++)
        {
            var n = p.Nodes[i];
            if (i > 0) sb.Append(',');
            sb.Append("{\"id\":").Append(JsonSerializer.Serialize(n.Id));
            sb.Append(",\"name\":").Append(JsonSerializer.Serialize(n.Name));
            sb.Append(",\"role\":").Append(JsonSerializer.Serialize(n.Role));
            sb.Append(",\"delay\":").Append(n.Delay);
            sb.Append(",\"location\":").Append(JsonSerializer.Serialize(n.Location));
            sb.Append('}');
        }
        sb.Append("],\"segments\":[");
        for (int i = 0; i < p.Segments.Count; i++)
        {
            var s = p.Segments[i];
            if (i > 0) sb.Append(',');
            sb.Append("{\"type\":").Append(JsonSerializer.Serialize(s.Type));
            sb.Append(",\"q\":").Append(s.Q);
            if (s.Speaker != null) sb.Append(",\"speaker\":").Append(JsonSerializer.Serialize(s.Speaker));
            if (s.Label != null) sb.Append(",\"label\":").Append(JsonSerializer.Serialize(s.Label));
            sb.Append('}');
        }
        sb.Append("]}");
        return sb.ToString();
    }

    // ── 1. Plan ID (v3 + frozen v2) ──────────────────────────────────────────

    /// <summary>
    /// Deterministic plan ID. v3 plans hash SHA-256 over RFC 8785 canonical
    /// JSON (§4.5, "-v3-" infix); the v2 polynomial path is FROZEN (§4.3).
    /// </summary>
    public static string MakePlanId(PlanV11 plan)
    {
        string date = plan.Start.Substring(0, 10).Replace("-", "");
        string hostStr = plan.Nodes.Count > 0
            ? StripWs(plan.Nodes[0].Name).ToUpper() : "HOST";
        if (hostStr.Length > 8) hostStr = hostStr.Substring(0, 8);
        string nodeStr;
        if (plan.Nodes.Count > 1)
        {
            var parts = plan.Nodes.Skip(1).Select(n =>
            {
                string s = StripWs(n.Name).ToUpper();
                return s.Length > 4 ? s.Substring(0, 4) : s;
            });
            nodeStr = string.Join("-", parts);
            if (nodeStr.Length > 16) nodeStr = nodeStr.Substring(0, 16);
        }
        else nodeStr = "RX";

        if (plan.V >= 3)
        {
            string digest = PlanHash(plan);
            return $"LTX-{date}-{hostStr}-{nodeStr}-v3-{digest.Substring(0, 8)}";
        }

        // FROZEN v2 path — 32-bit polynomial hash over the JSON (UTF-16 units).
        string raw = ToJsonV2(plan);
        uint h = 0;
        foreach (char c in raw) h = unchecked(h * 31u + c);
        return $"LTX-{date}-{hostStr}-{nodeStr}-v2-{h:x8}";
    }

    private static string StripWs(string s) =>
        string.Concat(s.Where(c => !char.IsWhiteSpace(c)));

    // ── 1. pairDelay + ComputeSegmentsFor ────────────────────────────────────

    /// <summary>
    /// One-way delay in seconds between two nodes (§3.7). The v3 pair matrix is
    /// authoritative where present; fallback: HOST pairs use the node's declared
    /// delay, non-HOST pairs the sum of both HOST-relative delays.
    /// </summary>
    public static long PairDelay(PlanV11 plan, string nodeIdA, string nodeIdB)
    {
        if (nodeIdA == nodeIdB) return 0;
        var ids = new[] { nodeIdA, nodeIdB }.OrderBy(x => x, StringComparer.Ordinal);
        string key = string.Join("|", ids);
        if (plan.Delays != null && plan.Delays.TryGetValue(key, out long d)) return d;
        var a = plan.Nodes.FirstOrDefault(n => n.Id == nodeIdA);
        var b = plan.Nodes.FirstOrDefault(n => n.Id == nodeIdB);
        if (a == null || b == null)
            throw new ArgumentException($"pairDelay: unknown node {(a == null ? nodeIdA : nodeIdB)}");
        string hostId = plan.Nodes[0].Id;
        if (nodeIdA == hostId) return b.Delay;
        if (nodeIdB == hostId) return a.Delay;
        return a.Delay + b.Delay;
    }

    private static long ParseIsoMs(string iso) =>
        DateTimeOffset.Parse(iso,
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal).ToUnixTimeMilliseconds();

    /// <summary>Base timed segments (epoch ms) for a v1.1 plan.</summary>
    public static List<ViewerSegmentV11> ComputeSegmentsV11(PlanV11 plan)
    {
        long qMs = (long)plan.Quantum * 60 * 1000;
        long t = ParseIsoMs(plan.Start);
        var result = new List<ViewerSegmentV11>();
        foreach (var s in plan.Segments)
        {
            long durMs = s.Q * qMs;
            result.Add(new ViewerSegmentV11(
                s.Type, s.Q, t, t + durMs, s.Q * plan.Quantum,
                s.Speaker, s.Label, "neutral", 0));
            t += durMs;
        }
        return result;
    }

    /// <summary>
    /// Timed segments from viewer V's perspective (§14.3): a segment attributed
    /// to speaker S starts for V at segStart + pairDelay(S, V).
    /// </summary>
    public static List<ViewerSegmentV11> ComputeSegmentsFor(PlanV11 plan, string viewerNodeId)
    {
        if (!plan.Nodes.Any(n => n.Id == viewerNodeId))
            throw new ArgumentException($"computeSegmentsFor: unknown viewer {viewerNodeId}");
        var baseSegs = ComputeSegmentsV11(plan);
        var result = new List<ViewerSegmentV11>();
        for (int i = 0; i < baseSegs.Count; i++)
        {
            var seg = baseSegs[i];
            var tpl = plan.Segments[i];
            if (tpl.Speaker == null || (tpl.Type != "TX" && tpl.Type != "SPEAK"))
            {
                result.Add(seg with { Perspective = "neutral", ArrivalOffsetS = 0 });
            }
            else if (tpl.Speaker == viewerNodeId)
            {
                result.Add(seg with { Perspective = "transmit", ArrivalOffsetS = 0 });
            }
            else
            {
                long shiftS = PairDelay(plan, tpl.Speaker, viewerNodeId);
                result.Add(seg with
                {
                    StartMs = seg.StartMs + shiftS * 1000,
                    EndMs = seg.EndMs + shiftS * 1000,
                    Perspective = "receive",
                    ArrivalOffsetS = shiftS,
                });
            }
        }
        return result;
    }

    // ── Ed25519 / envelope helpers ───────────────────────────────────────────

    private static bool VerifyBytes(byte[] data, string sigB64, NikV11 nik)
    {
        try
        {
            var pub = PublicKey.Import(Ed, LtxSecurity.FromBase64Url(nik.PublicKeyB64),
                KeyBlobFormat.RawPublicKey);
            return Ed.Verify(pub, data, LtxSecurity.FromBase64Url(sigB64));
        }
        catch { return false; }
    }

    private static bool IsExpired(NikV11 nik)
    {
        try
        {
            return DateTimeOffset.UtcNow > DateTimeOffset.Parse(nik.ValidUntil,
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.AssumeUniversal);
        }
        catch { return false; }
    }

    private static NikV11? LookupKid(string kid, Dictionary<string, NikV11> keyCache)
    {
        if (keyCache.TryGetValue(kid, out var direct)) return direct;
        return keyCache.Values.FirstOrDefault(n => n.NodeId.StartsWith(kid));
    }

    /// <summary>Canonical JSON of the Sig_structure array (security.ts).</summary>
    private static string SigStructureJson(string protectedB64, string payloadB64) =>
        "[\"Signature1\"," + JsonSerializer.Serialize(protectedB64) +
        ",\"\"," + JsonSerializer.Serialize(payloadB64) + "]";

    /// <summary>
    /// Verify the TRANSITIONAL JSON COSE_Sign1 plan envelope (LTX-SECURITY §7.2):
    /// Ed25519 over canonicalJSON(["Signature1", protected, "", payload]).
    /// </summary>
    public static VerifyResultV11 VerifyPlanEnvelope(
        SignedPlanV11 sp, Dictionary<string, NikV11> keyCache)
    {
        if (sp.CoseSign1 == null) return new VerifyResultV11(false, "missing_cose_sign1");
        var nik = LookupKid(sp.CoseSign1.Kid, keyCache);
        if (nik == null) return new VerifyResultV11(false, "key_not_in_cache");
        if (IsExpired(nik)) return new VerifyResultV11(false, "key_expired");
        string sigStructure = SigStructureJson(sp.CoseSign1.Protected, sp.CoseSign1.Payload);
        if (!VerifyBytes(Encoding.UTF8.GetBytes(sigStructure), sp.CoseSign1.Signature, nik))
            return new VerifyResultV11(false, "signature_invalid");
        string payloadStr = Encoding.UTF8.GetString(LtxSecurity.FromBase64Url(sp.CoseSign1.Payload));
        if (payloadStr != LtxSecurity.CanonicalJSON(sp.Plan.ToDict()))
            return new VerifyResultV11(false, "payload_mismatch");
        return new VerifyResultV11(true);
    }

    // ── 3. Amendment chains (amend.ts) ───────────────────────────────────────

    /// <summary>
    /// Verify an amendment chain: chain[0] is the root plan, each later element
    /// a successive amendment. Checks per link: signature, planVersion +1 steps,
    /// prevPlanHash equality with the recomputed predecessor hash; the root must
    /// carry no prevPlanHash (LTX-SECURITY.md §7.6).
    /// </summary>
    public static VerifyResultV11 VerifyAmendmentChain(
        List<SignedPlanV11> chain, Dictionary<string, NikV11> keyCache)
    {
        if (chain == null || chain.Count == 0)
            return new VerifyResultV11(false, "empty_chain");
        for (int i = 0; i < chain.Count; i++)
        {
            var sig = VerifyPlanEnvelope(chain[i], keyCache);
            if (!sig.Valid) return new VerifyResultV11(false, $"link_{i}_{sig.Reason}");
        }
        if (chain[0].Plan.PrevPlanHash != null)
            return new VerifyResultV11(false, "root_has_prev_hash");
        var prevPlan = chain[0].Plan;
        int prevVersion = chain[0].Plan.PlanVersion ?? 1;
        for (int i = 1; i < chain.Count; i++)
        {
            var p = chain[i].Plan;
            if (p.V != 3) return new VerifyResultV11(false, $"link_{i}_not_v3");
            if ((p.PlanVersion ?? 0) != prevVersion + 1)
                return new VerifyResultV11(false, $"link_{i}_version_gap");
            if (p.PrevPlanHash != PlanHash(prevPlan))
                return new VerifyResultV11(false, $"link_{i}_prev_hash_mismatch");
            prevPlan = p;
            prevVersion = p.PlanVersion!.Value;
        }
        return new VerifyResultV11(true);
    }

    // ── 4. Register entries + reducers (registers.ts) ────────────────────────

    private static Dictionary<string, object?> UnsignedDict(RegisterEntryV11 e) => new()
    {
        ["entryId"] = e.EntryId,
        ["sessionId"] = e.SessionId,
        ["nodeId"] = e.NodeId,
        ["seq"] = e.Seq,
        ["type"] = e.Type,
        ["content"] = e.Content,
        ["timestamp"] = e.Timestamp,
    };

    private static Dictionary<string, object?> SignedDict(RegisterEntryV11 e)
    {
        var d = UnsignedDict(e);
        d["sig"] = e.Sig;
        return d;
    }

    /// <summary>Verify a register entry signature (Ed25519 over canonical JSON sans sig).</summary>
    public static VerifyResultV11 VerifyRegisterEntry(
        RegisterEntryV11 entry, Dictionary<string, NikV11> keyCache)
    {
        if (entry == null || string.IsNullOrEmpty(entry.Sig))
            return new VerifyResultV11(false, "missing_sig");
        if (!keyCache.TryGetValue(entry.NodeId, out var nik))
            return new VerifyResultV11(false, "key_not_in_cache");
        string canon = LtxSecurity.CanonicalJSON(UnsignedDict(entry));
        bool ok = VerifyBytes(Encoding.UTF8.GetBytes(canon), entry.Sig, nik);
        return ok ? new VerifyResultV11(true) : new VerifyResultV11(false, "signature_invalid");
    }

    /// <summary>Total order (timestamp, nodeId, seq) — §8.2.</summary>
    public static int CompareEntries(RegisterEntryV11 a, RegisterEntryV11 b)
    {
        int c = string.CompareOrdinal(a.Timestamp, b.Timestamp);
        if (c != 0) return c;
        c = string.CompareOrdinal(a.NodeId, b.NodeId);
        if (c != 0) return c;
        return a.Seq.CompareTo(b.Seq);
    }

    /// <summary>De-duplicate by (nodeId, seq) and sort into the §8.2 total order.</summary>
    public static List<RegisterEntryV11> OrderEntries(IEnumerable<RegisterEntryV11> entries)
    {
        var seen = new Dictionary<string, RegisterEntryV11>();
        foreach (var e in entries)
        {
            string key = $"{e.NodeId} {e.Seq}";
            if (!seen.ContainsKey(key)) seen[key] = e;
        }
        var list = seen.Values.ToList();
        list.Sort(CompareEntries);
        return list;
    }

    private static bool Wins(int inVersion, string inEditor, int curVersion, string curEditor)
    {
        if (inVersion != curVersion) return inVersion > curVersion;
        return string.CompareOrdinal(inEditor, curEditor) < 0;
    }

    private static int AsInt(object? v, int fallback) => v switch
    {
        int i => i,
        long l => (int)l,
        double d => (int)d,
        string s when int.TryParse(s, out int p) => p,
        _ => fallback,
    };

    /// <summary>Reduce question register state from log entries (§9.4).</summary>
    public static RegisterReductionV11<QuestionStateV11> ReduceQuestions(
        IEnumerable<RegisterEntryV11> entries)
    {
        var byId = new Dictionary<string, QuestionStateV11>();
        var winners = new Dictionary<string, (int Version, string Editor, string EntryId)>();
        var superseded = new List<string>();

        foreach (var e in OrderEntries(entries))
        {
            if (e.Type == "question")
            {
                string qid = e.EntryId;
                if (byId.ContainsKey(qid)) { superseded.Add(e.EntryId); continue; }
                winners[qid] = (1, e.NodeId, e.EntryId);
                byId[qid] = new QuestionStateV11
                {
                    Qid = qid,
                    Text = e.Content.TryGetValue("text", out var t) ? t?.ToString() ?? "" : "",
                    Submitter = e.NodeId,
                    Urgency = e.Content.TryGetValue("urgency", out var u) ? u?.ToString() : null,
                    IntendedWindow = e.Content.TryGetValue("intendedWindow", out var w) ? w?.ToString() : null,
                    Status = "OPEN",
                    Version = 1,
                };
            }
            else if (e.Type == "question_response")
            {
                string qid = e.Content.TryGetValue("qid", out var q0) ? q0?.ToString() ?? "" : "";
                if (!byId.TryGetValue(qid, out var q)) { superseded.Add(e.EntryId); continue; }
                int version = AsInt(e.Content.TryGetValue("version", out var v) ? v : null, q.Version + 1);
                if (winners.TryGetValue(qid, out var cur))
                {
                    if (!Wins(version, e.NodeId, cur.Version, cur.Editor)) { superseded.Add(e.EntryId); continue; }
                    if (cur.EntryId != q.Qid) superseded.Add(cur.EntryId);
                }
                winners[qid] = (version, e.NodeId, e.EntryId);
                string status = e.Content.TryGetValue("status", out var st) && st?.ToString() == "WITHDRAWN"
                    ? "WITHDRAWN" : "ANSWERED";
                byId[qid] = q with
                {
                    Status = status,
                    Response = e.Content.TryGetValue("response", out var r) ? r?.ToString() : q.Response,
                    Responder = e.NodeId,
                    Version = version,
                };
            }
        }
        return new RegisterReductionV11<QuestionStateV11>(byId, superseded);
    }

    private static readonly string[] ActionStatuses = { "PROPOSED", "ACCEPTED", "REJECTED", "DONE" };

    /// <summary>Reduce action register state from log entries (§10.2).</summary>
    public static RegisterReductionV11<ActionStateV11> ReduceActions(
        IEnumerable<RegisterEntryV11> entries)
    {
        var byId = new Dictionary<string, ActionStateV11>();
        var winners = new Dictionary<string, (int Version, string Editor, string EntryId)>();
        var superseded = new List<string>();

        foreach (var e in OrderEntries(entries))
        {
            if (e.Type == "action")
            {
                string aid = e.EntryId;
                if (byId.ContainsKey(aid)) { superseded.Add(e.EntryId); continue; }
                winners[aid] = (1, e.NodeId, e.EntryId);
                byId[aid] = new ActionStateV11
                {
                    Aid = aid,
                    Description = e.Content.TryGetValue("description", out var d) ? d?.ToString() ?? "" : "",
                    Owner = e.Content.TryGetValue("owner", out var o) ? o?.ToString() : null,
                    DueTimeUTC = e.Content.TryGetValue("dueTimeUTC", out var due) ? due?.ToString() : null,
                    OriginWindow = e.Content.TryGetValue("originWindow", out var ow) ? ow?.ToString() : null,
                    Status = "PROPOSED",
                    Version = 1,
                };
            }
            else if (e.Type == "action_update")
            {
                string aid = e.Content.TryGetValue("aid", out var a0) ? a0?.ToString() ?? "" : "";
                if (!byId.TryGetValue(aid, out var a)) { superseded.Add(e.EntryId); continue; }
                int version = AsInt(e.Content.TryGetValue("version", out var v) ? v : null, a.Version + 1);
                if (winners.TryGetValue(aid, out var cur))
                {
                    if (!Wins(version, e.NodeId, cur.Version, cur.Editor)) { superseded.Add(e.EntryId); continue; }
                    if (cur.EntryId != a.Aid) superseded.Add(cur.EntryId);
                }
                winners[aid] = (version, e.NodeId, e.EntryId);
                string status = e.Content.TryGetValue("status", out var st) &&
                    ActionStatuses.Contains(st?.ToString()) ? st!.ToString()! : a.Status;
                byId[aid] = a with
                {
                    Status = status,
                    Description = e.Content.TryGetValue("description", out var d2) ? d2?.ToString() ?? a.Description : a.Description,
                    Owner = e.Content.TryGetValue("owner", out var o2) ? o2?.ToString() : a.Owner,
                    DueTimeUTC = e.Content.TryGetValue("dueTimeUTC", out var due2) ? due2?.ToString() : a.DueTimeUTC,
                    Version = version,
                };
            }
        }
        return new RegisterReductionV11<ActionStateV11>(byId, superseded);
    }

    // ── Merkle root over ordered entries (merkle.ts / merge.ts) ─────────────

    private static byte[] LeafHash(byte[] entryBytes)
    {
        var buf = new byte[1 + entryBytes.Length];
        buf[0] = 0x00;
        entryBytes.CopyTo(buf, 1);
        return SHA256.HashData(buf);
    }

    private static byte[] NodeHash(byte[] left, byte[] right)
    {
        var buf = new byte[65];
        buf[0] = 0x01;
        left.CopyTo(buf, 1);
        right.CopyTo(buf, 33);
        return SHA256.HashData(buf);
    }

    private static byte[] RootOf(List<byte[]> leaves, int start, int count)
    {
        if (count == 0) return new byte[32];
        if (count == 1) return leaves[start];
        int mid = (int)Math.Pow(2, Math.Floor(Math.Log2(count - 1)));
        return NodeHash(RootOf(leaves, start, mid), RootOf(leaves, start + mid, count - mid));
    }

    /// <summary>
    /// RFC 9162-style Merkle root (hex) over an ordered entry list.
    /// Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01 || L || R).
    /// </summary>
    public static string EntriesRoot(List<RegisterEntryV11> entries)
    {
        var leaves = entries
            .Select(e => LeafHash(Encoding.UTF8.GetBytes(LtxSecurity.CanonicalJSON(SignedDict(e)))))
            .ToList();
        return Convert.ToHexString(RootOf(leaves, 0, leaves.Count)).ToLower();
    }

    // ── 5. CBOR decode (cbor.ts) ─────────────────────────────────────────────

    /// <summary>
    /// Decode deterministic CBOR bytes (RFC 8949 subset): ints, bstr, tstr,
    /// array, map, tag, bool/null. Rejects floats, indefinite lengths, and
    /// trailing bytes. Maps decode to Dictionary&lt;object, object?&gt; with
    /// bstr keys converted to base64url strings.
    /// </summary>
    public static object? DecodeCbor(byte[] bytes)
    {
        int pos = 0;
        object? value = DecodeItem(bytes, ref pos);
        if (pos != bytes.Length) throw new FormatException("cbor: trailing bytes");
        return value;
    }

    private static (int Major, long Arg) ReadHead(byte[] buf, ref int pos)
    {
        if (pos >= buf.Length) throw new FormatException("cbor: truncated");
        byte initial = buf[pos++];
        int major = initial >> 5;
        int info = initial & 0x1f;
        if (info < 24) return (major, info);
        if (info == 24)
        {
            if (pos >= buf.Length) throw new FormatException("cbor: truncated");
            return (major, buf[pos++]);
        }
        if (info == 25)
        {
            if (pos + 2 > buf.Length) throw new FormatException("cbor: truncated");
            long v = (buf[pos] << 8) | buf[pos + 1];
            pos += 2;
            return (major, v);
        }
        if (info == 26)
        {
            if (pos + 4 > buf.Length) throw new FormatException("cbor: truncated");
            long v = ((long)buf[pos] << 24) | ((long)buf[pos + 1] << 16)
                | ((long)buf[pos + 2] << 8) | buf[pos + 3];
            pos += 4;
            return (major, v);
        }
        if (info == 27)
        {
            if (pos + 8 > buf.Length) throw new FormatException("cbor: truncated");
            ulong v = 0;
            for (int i = 0; i < 8; i++) v = (v << 8) | buf[pos + i];
            pos += 8;
            if (v > long.MaxValue) throw new FormatException("cbor: integer too large");
            return (major, (long)v);
        }
        throw new FormatException("cbor: indefinite lengths not supported");
    }

    private static object? DecodeItem(byte[] buf, ref int pos)
    {
        if (pos >= buf.Length) throw new FormatException("cbor: truncated");
        byte first = buf[pos];
        if (first == 0xf6) { pos++; return null; }
        if (first == 0xf5) { pos++; return true; }
        if (first == 0xf4) { pos++; return false; }

        var (major, arg) = ReadHead(buf, ref pos);
        switch (major)
        {
            case 0: return arg;
            case 1: return -arg - 1;
            case 2:
            {
                if (pos + arg > buf.Length) throw new FormatException("cbor: truncated bstr");
                var bytes = new byte[arg];
                Array.Copy(buf, pos, bytes, 0, (int)arg);
                pos += (int)arg;
                return bytes;
            }
            case 3:
            {
                if (pos + arg > buf.Length) throw new FormatException("cbor: truncated tstr");
                string s = Encoding.UTF8.GetString(buf, pos, (int)arg);
                pos += (int)arg;
                return s;
            }
            case 4:
            {
                var list = new List<object?>();
                for (long i = 0; i < arg; i++) list.Add(DecodeItem(buf, ref pos));
                return list;
            }
            case 5:
            {
                var map = new Dictionary<object, object?>();
                for (long i = 0; i < arg; i++)
                {
                    object? k = DecodeItem(buf, ref pos);
                    object key = k is byte[] kb ? LtxSecurity.ToBase64Url(kb) : k!;
                    map[key] = DecodeItem(buf, ref pos);
                }
                return map;
            }
            case 6: return new CborTagV11(arg, DecodeItem(buf, ref pos));
            default: throw new FormatException($"cbor: unsupported major type {major} / simple value");
        }
    }

    // ── 5. COSE_Sign1 verification (cose.ts) ─────────────────────────────────

    private static byte[] EncodeCborHead(int major, long arg)
    {
        if (arg < 24) return new[] { (byte)((major << 5) | arg) };
        if (arg < 0x100) return new[] { (byte)((major << 5) | 24), (byte)arg };
        if (arg < 0x10000)
            return new[] { (byte)((major << 5) | 25), (byte)(arg >> 8), (byte)arg };
        return new[]
        {
            (byte)((major << 5) | 26),
            (byte)(arg >> 24), (byte)(arg >> 16), (byte)(arg >> 8), (byte)arg,
        };
    }

    /// <summary>Sig_structure = CBOR ["Signature1", protected, h'', payload] (RFC 9052).</summary>
    private static byte[] SigStructureBytes(byte[] protectedBytes, byte[] payload)
    {
        var ms = new MemoryStream();
        ms.Write(EncodeCborHead(4, 4));
        ms.Write(EncodeCborHead(3, 10));
        ms.Write(Encoding.UTF8.GetBytes("Signature1"));
        ms.Write(EncodeCborHead(2, protectedBytes.Length));
        ms.Write(protectedBytes);
        ms.Write(EncodeCborHead(2, 0));
        ms.Write(EncodeCborHead(2, payload.Length));
        ms.Write(payload);
        return ms.ToArray();
    }

    /// <summary>
    /// Verify a CBOR COSE_Sign1 plan envelope (tag 18, RFC 9052) against the key
    /// cache. Rejects non-Ed25519 algorithms (protected {1: -19} required) and
    /// payloads that do not match the accompanying plan's canonical JSON.
    /// </summary>
    public static VerifyResultV11 VerifyPlanCose(
        PlanV11? plan, string coseSign1CborB64, Dictionary<string, NikV11> keyCache)
    {
        if (string.IsNullOrEmpty(coseSign1CborB64))
            return new VerifyResultV11(false, "missing_cose_sign1");
        object? decoded;
        try { decoded = DecodeCbor(LtxSecurity.FromBase64Url(coseSign1CborB64)); }
        catch { return new VerifyResultV11(false, "cbor_decode_failed"); }

        if (decoded is not CborTagV11 tag || tag.Tag != COSE_SIGN1_TAG)
            return new VerifyResultV11(false, "not_cose_sign1");
        if (tag.Value is not List<object?> arr || arr.Count != 4)
            return new VerifyResultV11(false, "malformed_cose_sign1");
        if (arr[0] is not byte[] protectedBytes || arr[2] is not byte[] payload ||
            arr[3] is not byte[] signature)
            return new VerifyResultV11(false, "malformed_cose_sign1");

        Dictionary<object, object?>? protectedMap;
        try { protectedMap = DecodeCbor(protectedBytes) as Dictionary<object, object?>; }
        catch { return new VerifyResultV11(false, "protected_decode_failed"); }
        if (protectedMap == null ||
            !protectedMap.TryGetValue(1L, out var alg) ||
            alg is not long algL || algL != COSE_ALG_ED25519)
            return new VerifyResultV11(false, "unsupported_alg");

        string kid = "";
        if (arr[1] is Dictionary<object, object?> unprotected &&
            unprotected.TryGetValue(4L, out var kidRaw))
        {
            kid = kidRaw switch
            {
                byte[] kb => LtxSecurity.ToBase64Url(kb),
                string ks => ks,
                _ => "",
            };
        }
        if (kid.Length == 0) return new VerifyResultV11(false, "missing_kid");

        var nik = LookupKid(kid, keyCache);
        if (nik == null) return new VerifyResultV11(false, "key_not_in_cache");
        if (IsExpired(nik)) return new VerifyResultV11(false, "key_expired");

        byte[] sigStructure = SigStructureBytes(protectedBytes, payload);
        if (!VerifyBytes(sigStructure, LtxSecurity.ToBase64Url(signature), nik))
            return new VerifyResultV11(false, "signature_invalid");

        if (plan != null &&
            Encoding.UTF8.GetString(payload) != LtxSecurity.CanonicalJSON(plan.ToDict()))
            return new VerifyResultV11(false, "payload_mismatch");
        return new VerifyResultV11(true);
    }

    // ── 2. Session state machine (session.ts) ────────────────────────────────

    private static List<NodeV11> Participants(PlanV11 plan) =>
        plan.Nodes.Where(n => n.Role == "PARTICIPANT").ToList();

    /// <summary>2 × one-way delay to the furthest node, in ms (§5.1).</summary>
    public static long LockTimeoutMs(PlanV11 plan)
    {
        long maxDelayS = plan.Nodes.Count > 0 ? plan.Nodes.Max(n => n.Delay) : 0;
        return Constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * maxDelayS * 1000;
    }

    private static int QuorumCount(PlanV11 plan, object? quorum)
    {
        int total = Participants(plan).Count;
        if (quorum is string s && s == "majority") return total / 2 + 1;
        if (quorum is int i) return Math.Min(Math.Max(i, 1), total);
        return total; // "all" (default)
    }

    /// <summary>Create a session context in DRAFT state (§5).</summary>
    public static SessionCtxV11 CreateSession(PlanV11 plan, string planId, object? quorum = null) => new()
    {
        State = "DRAFT",
        Plan = plan,
        PlanId = planId,
        SessionRootPlanId = planId,
        PlanVersion = plan.PlanVersion ?? 1,
        Lock = null,
        LockStartedAtMs = null,
        LockTimeoutMs = LockTimeoutMs(plan),
        Confirmations = new Dictionary<string, string>(),
        Mismatched = new List<string>(),
        QuorumThreshold = QuorumCount(plan, quorum),
        Subset = null,
        DegradedReasons = new List<string>(),
        ResumeState = null,
        PendingAmendment = null,
    };

    private static bool FullLockReached(SessionCtxV11 ctx) =>
        Participants(ctx.Plan).All(n =>
            ctx.Confirmations.TryGetValue(n.Id, out var p) && p == ctx.PlanId);

    private static bool QuorumReached(SessionCtxV11 ctx) =>
        Participants(ctx.Plan).Count(n =>
            ctx.Confirmations.TryGetValue(n.Id, out var p) && p == ctx.PlanId)
        >= ctx.QuorumThreshold;

    /// <summary>Ascending-delay fallback ordering over confirmed participants (§5.3).</summary>
    private static List<string> ConfirmedSubset(SessionCtxV11 ctx)
    {
        var host = ctx.Plan.Nodes[0];
        var confirmed = Participants(ctx.Plan)
            .Where(n => ctx.Confirmations.TryGetValue(n.Id, out var p) && p == ctx.PlanId)
            .OrderBy(n => n.Delay)
            .Select(n => n.Id);
        var subset = new List<string> { host.Id };
        subset.AddRange(confirmed);
        return subset;
    }

    /// <summary>Declared one-way delay: v3 pair matrix HOST row, else node.delay.</summary>
    private static long? DeclaredDelayS(PlanV11 plan, string nodeId)
    {
        var node = plan.Nodes.FirstOrDefault(n => n.Id == nodeId);
        if (node == null) return null;
        if (plan.Delays != null)
        {
            string hostId = plan.Nodes[0].Id;
            var ids = new[] { hostId, nodeId }.OrderBy(x => x, StringComparer.Ordinal);
            string key = string.Join("|", ids);
            if (plan.Delays.TryGetValue(key, out long d)) return d;
        }
        return node.Delay;
    }

    private static SessionCtxV11 Degrade(SessionCtxV11 ctx, string reason)
    {
        var reasons = new List<string>(ctx.DegradedReasons) { reason };
        if (ctx.State == "DEGRADED") return ctx with { DegradedReasons = reasons };
        return ctx with { State = "DEGRADED", DegradedReasons = reasons };
    }

    /// <summary>
    /// Advance the session state machine. Pure: same (ctx, event) always yields
    /// the same result. Side effects of the reference implementation are
    /// simplified away — the state/lock sequence matches the reference exactly.
    /// </summary>
    public static SessionCtxV11 Transition(SessionCtxV11 ctx, SessionEventV11 ev)
    {
        switch (ev.Type)
        {
            case "START_LOCK":
            {
                if (ctx.State != "DRAFT") return ctx;
                string hostId = ctx.Plan.Nodes[0].Id;
                var conf = new Dictionary<string, string>(ctx.Confirmations) { [hostId] = ctx.PlanId };
                return ctx with { State = "LOCKING", LockStartedAtMs = ev.NowMs, Confirmations = conf };
            }

            case "PLAN_CONFIRM":
            {
                if (ctx.State != "LOCKING" && ctx.State != "DEGRADED") return ctx;
                if (ev.NodeId == null || ev.PlanId == null) return ctx;
                var conf = new Dictionary<string, string>(ctx.Confirmations) { [ev.NodeId] = ev.PlanId };
                var next = ctx with { Confirmations = conf };
                if (ev.PlanId != ctx.PlanId)
                {
                    var mm = next.Mismatched.Where(id => id != ev.NodeId).ToList();
                    mm.Add(ev.NodeId);
                    return next with { Mismatched = mm };
                }
                next = next with { Mismatched = next.Mismatched.Where(id => id != ev.NodeId).ToList() };
                if (FullLockReached(next))
                {
                    // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                    return next with { State = "LOCKED", Lock = "FULL", Subset = null };
                }
                return next;
            }

            case "TICK":
            {
                if (ctx.State != "LOCKING" || ctx.LockStartedAtMs == null) return ctx;
                if (ev.NowMs - ctx.LockStartedAtMs.Value < ctx.LockTimeoutMs) return ctx;
                // Lock timeout expired (§5.1).
                if (QuorumReached(ctx))
                {
                    var subset = ConfirmedSubset(ctx);
                    var next = ctx with { Lock = "QUORUM", Subset = subset };
                    return Degrade(next, $"quorum lock with subset [{string.Join(",", subset)}]");
                }
                return Degrade(ctx, "plan-lock timeout without quorum");
            }

            case "SESSION_START":
            {
                if (ctx.State == "LOCKED") return ctx with { State = "ACTIVE" };
                // DEGRADED start requires HOST_DECISION continue (§5.2).
                return ctx;
            }

            case "DELAY_MEASURED":
            {
                if (ctx.State != "ACTIVE" && ctx.State != "LOCKED" && ctx.State != "DEGRADED")
                    return ctx;
                if (ev.NodeId == null || ev.MeasuredDelayS == null) return ctx;
                long? declared = DeclaredDelayS(ctx.Plan, ev.NodeId);
                if (declared == null) return ctx;
                long deviation = Math.Abs(ev.MeasuredDelayS.Value - declared.Value);
                if (deviation > Constants.DELAY_VIOLATION_DEGRADED_S)
                    return Degrade(ctx, $"delay violation {ev.NodeId}: measured {ev.MeasuredDelayS}s vs declared {declared}s");
                return ctx;
            }

            case "EOK_OVERRIDE":
            {
                if (ctx.State == "COMPLETE" || ctx.State == "ABORTED") return ctx;
                if (ev.Verified != true) return ctx;
                if (ctx.State == "EMERGENCY_HOLD") return ctx;
                return ctx with { State = "EMERGENCY_HOLD", ResumeState = ctx.State };
            }

            case "AMENDMENT_PROPOSED":
            {
                if (ctx.State != "ACTIVE" && ctx.State != "LOCKED" && ctx.State != "DEGRADED")
                    return ctx;
                if (ev.PlanId == null || ev.PlanVersion == null || ev.AffectedNodeIds == null)
                    return ctx;
                if (ev.PlanVersion.Value != ctx.PlanVersion + 1) return ctx;
                // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
                var affected = ctx.Plan.Nodes.Where(n => ev.AffectedNodeIds.Contains(n.Id));
                long maxDelayS = affected.Any() ? affected.Max(n => n.Delay) : 0;
                var pending = new PendingAmendmentV11(
                    ev.PlanId, ev.PlanVersion.Value, ev.AffectedNodeIds,
                    new List<string>(), ev.NowMs,
                    Constants.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * maxDelayS * 1000);
                return ctx with { PendingAmendment = pending };
            }

            case "AMENDMENT_CONFIRMED":
            {
                var pa = ctx.PendingAmendment;
                if (pa == null || ev.PlanId != pa.PlanId || ev.NodeId == null) return ctx;
                if (!pa.AffectedNodeIds.Contains(ev.NodeId)) return ctx;
                var confirmed = pa.Confirmed.Where(id => id != ev.NodeId).ToList();
                confirmed.Add(ev.NodeId);
                if (confirmed.Count < pa.AffectedNodeIds.Count)
                    return ctx with { PendingAmendment = pa with { Confirmed = confirmed } };
                // All affected nodes confirmed — the amendment applies.
                return ctx with
                {
                    PlanId = pa.PlanId,
                    PlanVersion = pa.PlanVersion,
                    PendingAmendment = null,
                };
            }

            case "HOST_DECISION":
            {
                if (ev.Decision == "abort")
                {
                    if (ctx.State == "COMPLETE" || ctx.State == "ABORTED") return ctx;
                    return ctx with { State = "ABORTED" };
                }
                if (ev.Decision == "resume" && ctx.State == "EMERGENCY_HOLD")
                    return ctx with { State = ctx.ResumeState ?? "ACTIVE", ResumeState = null };
                if (ev.Decision == "continue" && ctx.State == "DEGRADED")
                    return ctx with { State = "ACTIVE" }; // §5.2: HOST continues with subset.
                return ctx;
            }

            case "SESSION_END":
            {
                if (ctx.State == "ACTIVE" || ctx.State == "DEGRADED")
                    return ctx with { State = "COMPLETE" };
                return ctx;
            }

            default:
                return ctx;
        }
    }
}
