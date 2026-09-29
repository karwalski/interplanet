// Validate.cs — plan validation (LTX-SPECIFICATION.md §3.5, §4, §7) and planId
// over the wire form of a plan (spec/golden/plan-ids.json).
//
// C# port of validatePlan / _reservedFieldErrors / _assertNoReservedFields and
// makePlanId(JSON.parse(json)) in javascript/ltx/ltx-sdk.js. Works on
// System.Text.Json elements, which keep object key order; the typed plan
// models have no slot for the reserved fields validation has to detect.

using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace InterplanetLtx;

/// <summary>One validation failure: a stable code, the JSON path and a message.</summary>
public record PlanValidationError(string Code, string Path, string Message);

/// <summary>Result of <see cref="LtxPlanJson.ValidatePlan(JsonElement)"/>.</summary>
public record PlanValidation(bool Valid, List<PlanValidationError> Errors)
{
    public List<string> Codes => Errors.Select(e => e.Code).ToList();
}

/// <summary>
/// Thrown by session creation (and any future upgrade or amendment helper)
/// when a plan uses the reserved streams (§3.5) or branching (§7) fields.
/// <see cref="Code"/> is the first violation's code; <see cref="Errors"/> lists all.
/// </summary>
public class ReservedFieldException : Exception
{
    public string Code { get; }
    public List<PlanValidationError> Errors { get; }
    public ReservedFieldException(string code, string message, List<PlanValidationError> errors)
        : base(message) { Code = code; Errors = errors; }
}

public static class LtxPlanJson
{
    /// <summary>Core segment types (§3.4) plus the auxiliary types the SDKs handle.</summary>
    public static readonly string[] PlanSegmentTypes =
        { "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE", "SPEAK", "REST", "PAD", "OPEN", "RELAY" };
    public static readonly string[] PlanModes = { "LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC" };
    /// <summary>Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3).</summary>
    public static readonly string[] V3OnlyFields =
        { "delays", "planVersion", "prevPlanHash", "questions", "actions", "streams" };
    private static readonly string[] ReservedBranchPlanFields = { "branches", "branching" };
    private static readonly string[] ReservedBranchSegmentFields = { "branch" };
    private static readonly string[] ReservedStreamSegmentFields = { "stream" };
    private static readonly string[] Roles = { "HOST", "PARTICIPANT", "OBSERVER" };

    // ── JSON helpers ─────────────────────────────────────────────────────────

    private static bool Has(JsonElement o, string key) => o.TryGetProperty(key, out _);

    private static JsonElement? Get(JsonElement o, string key) =>
        o.ValueKind == JsonValueKind.Object && o.TryGetProperty(key, out var v) ? v : null;

    private static double? Num(JsonElement? v) =>
        v is { ValueKind: JsonValueKind.Number } e ? e.GetDouble() : null;

    private static bool IsInteger(JsonElement? v) =>
        Num(v) is double d && !double.IsInfinity(d) && Math.Floor(d) == d;

    private static string? Str(JsonElement? v) =>
        v is { ValueKind: JsonValueKind.String } e ? LtxSecurity.JsonString(e) : null;

    /// <summary>JavaScript Number-to-String for a JSON number element.</summary>
    public static string JsNumber(JsonElement e)
    {
        if (e.TryGetInt64(out long l)) return l.ToString(CultureInfo.InvariantCulture);
        double d = e.GetDouble();
        if (Math.Floor(d) == d && Math.Abs(d) < 1e21) return d.ToString("F0", CultureInfo.InvariantCulture);
        return d.ToString("R", CultureInfo.InvariantCulture);
    }

    /// <summary>Compact serialisation identical to JavaScript JSON.stringify (key order kept).</summary>
    public static string Stringify(JsonElement e)
    {
        switch (e.ValueKind)
        {
            case JsonValueKind.Object:
                return "{" + string.Join(",", e.EnumerateObject()
                    .Select(p => LtxSecurity.JsQuote(p.Name) + ":" + Stringify(p.Value))) + "}";
            case JsonValueKind.Array:
                return "[" + string.Join(",", e.EnumerateArray().Select(Stringify)) + "]";
            case JsonValueKind.String: return LtxSecurity.JsQuote(LtxSecurity.JsonString(e));
            case JsonValueKind.Number: return JsNumber(e);
            case JsonValueKind.True: return "true";
            case JsonValueKind.False: return "false";
            default: return "null";
        }
    }

    private static JsonElement Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }

    // ── Reserved fields ──────────────────────────────────────────────────────

    /// <summary>Reserved-field violations only (§3.5 streams, §7 branching).</summary>
    public static List<PlanValidationError> ReservedFieldErrors(JsonElement plan)
    {
        var errors = new List<PlanValidationError>();
        if (plan.ValueKind != JsonValueKind.Object) return errors;
        if (Get(plan, "streams") is JsonElement st &&
            !(st.ValueKind == JsonValueKind.Array && st.GetArrayLength() == 0))
        {
            errors.Add(new("reserved_streams", "streams",
                "streams[] is reserved (§3.5) and MUST be absent or empty"));
        }
        foreach (var f in ReservedBranchPlanFields)
            if (Has(plan, f))
                errors.Add(new("reserved_branching", f,
                    $"{f} is reserved for branching (§7, not yet implemented) and MUST be absent"));
        if (Get(plan, "segments") is { ValueKind: JsonValueKind.Array } segs)
        {
            int i = 0;
            foreach (var s in segs.EnumerateArray())
            {
                if (s.ValueKind == JsonValueKind.Object)
                {
                    foreach (var f in ReservedStreamSegmentFields)
                        if (Has(s, f))
                            errors.Add(new("reserved_streams", $"segments[{i}].{f}",
                                $"segment {f} is reserved (§3.5) and MUST be absent"));
                    foreach (var f in ReservedBranchSegmentFields)
                        if (Has(s, f))
                            errors.Add(new("reserved_branching", $"segments[{i}].{f}",
                                $"segment {f} is reserved for branching (§7) and MUST be absent"));
                }
                i++;
            }
        }
        return errors;
    }

    /// <summary>Throw <see cref="ReservedFieldException"/> if a plan uses reserved fields.</summary>
    public static void AssertNoReservedFields(JsonElement plan, string fnName)
    {
        var errors = ReservedFieldErrors(plan);
        if (errors.Count == 0) return;
        throw new ReservedFieldException(errors[0].Code, $"{fnName}: {errors[0].Message}", errors);
    }

    /// <summary>Same check on the dictionary projection of a typed plan.</summary>
    public static void AssertNoReservedFields(Dictionary<string, object?> plan, string fnName) =>
        AssertNoReservedFields(Parse(LtxSecurity.CanonicalJSON(plan)), fnName);

    // ── validatePlan ─────────────────────────────────────────────────────────

    /// <summary>
    /// Validate a v2 or v3 plan (wire form) against spec/ltx-schema.json and the
    /// reserved-field rules (§3.5 streams, §7 branching). v1 configs must be
    /// upgraded first. Pure; never throws.
    /// Error codes: not_an_object, invalid_version, missing_field, invalid_field,
    /// invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
    /// duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
    /// invalid_delays, reserved_streams, reserved_branching.
    /// </summary>
    public static PlanValidation ValidatePlan(JsonElement plan)
    {
        var errors = new List<PlanValidationError>();
        void Err(string code, string path, string message) => errors.Add(new(code, path, message));
        if (plan.ValueKind != JsonValueKind.Object)
        {
            Err("not_an_object", "", "plan must be an object");
            return new PlanValidation(false, errors);
        }
        double? v = Num(Get(plan, "v"));
        if (v != 2 && v != 3) Err("invalid_version", "v", "v must be 2 or 3");
        foreach (var f in new[] { "title", "start", "quantum", "mode", "nodes", "segments" })
            if (!Has(plan, f)) Err("missing_field", f, $"{f} is required");
        if (Has(plan, "title") && Str(Get(plan, "title")) == null)
            Err("invalid_field", "title", "title must be a string");
        if (Has(plan, "start"))
        {
            string? s = Str(Get(plan, "start"));
            if (s == null || !DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal, out _))
                Err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp");
        }
        if (Has(plan, "quantum"))
        {
            var q = Get(plan, "quantum");
            if (!(IsInteger(q) && Num(q) >= 1 && Num(q) <= 60))
                Err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)");
        }
        if (Has(plan, "mode") && !PlanModes.Contains(Str(Get(plan, "mode"))))
            Err("invalid_mode", "mode", $"mode must be one of {string.Join(", ", PlanModes)}");

        var ids = new HashSet<string>(StringComparer.Ordinal);
        if (Has(plan, "nodes"))
        {
            var nodes = Get(plan, "nodes")!.Value;
            if (nodes.ValueKind != JsonValueKind.Array || nodes.GetArrayLength() == 0)
            {
                Err("invalid_nodes", "nodes", "nodes must be a non-empty array");
            }
            else
            {
                int hosts = 0, i = 0;
                foreach (var n in nodes.EnumerateArray())
                {
                    string? id = Str(Get(n, "id"));
                    string? role = Str(Get(n, "role"));
                    double? delay = Num(Get(n, "delay"));
                    if (n.ValueKind != JsonValueKind.Object || string.IsNullOrEmpty(id) || id.Contains('|') ||
                        Str(Get(n, "name")) == null || role == null || !Roles.Contains(role) ||
                        delay == null || !(delay >= 0))
                    {
                        Err("invalid_nodes", $"nodes[{i}]",
                            "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0");
                        i++;
                        continue;
                    }
                    if (ids.Contains(id)) Err("duplicate_node_id", $"nodes[{i}].id", $"duplicate node id {id}");
                    ids.Add(id);
                    if (role == "HOST") hosts++;
                    i++;
                }
                var h = nodes[0];
                if (hosts != 1 || h.ValueKind != JsonValueKind.Object ||
                    Str(Get(h, "role")) != "HOST" || Num(Get(h, "delay")) != 0)
                    Err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)");
            }
        }

        if (Has(plan, "segments"))
        {
            var segs = Get(plan, "segments")!.Value;
            if (segs.ValueKind != JsonValueKind.Array)
            {
                Err("invalid_segment", "segments", "segments must be an array");
            }
            else
            {
                int i = 0;
                foreach (var s in segs.EnumerateArray())
                {
                    var q = Get(s, "q");
                    if (s.ValueKind != JsonValueKind.Object || !PlanSegmentTypes.Contains(Str(Get(s, "type"))) ||
                        !(IsInteger(q) && Num(q) >= 1))
                    {
                        Err("invalid_segment", $"segments[{i}]", "segment needs a known type and integer q >= 1");
                    }
                    else if (Get(s, "speaker") is JsonElement sp)
                    {
                        string? spId = Str(sp);
                        if (spId == null || !ids.Contains(spId))
                            Err("unknown_speaker", $"segments[{i}].speaker",
                                $"speaker {(spId ?? sp.GetRawText())} is not a node id");
                    }
                    i++;
                }
            }
        }

        if (v == 2)
        {
            foreach (var f in V3OnlyFields)
                if (Has(plan, f))
                    Err("v3_field_in_v2", f, $"{f} is a v3 field and MUST NOT appear in a v2 plan (§4.3)");
        }
        else if (v == 3)
        {
            if (Get(plan, "delays") is JsonElement d)
            {
                if (d.ValueKind != JsonValueKind.Object)
                {
                    Err("invalid_delays", "delays", "delays must be an object");
                }
                else
                {
                    foreach (var p in d.EnumerateObject())
                    {
                        var parts = p.Name.Split('|');
                        double? val = Num(p.Value);
                        if (parts.Length != 2 || string.CompareOrdinal(parts[0], parts[1]) >= 0 ||
                            (ids.Count > 0 && (!ids.Contains(parts[0]) || !ids.Contains(parts[1]))) ||
                            val == null || !(val >= 0))
                            Err("invalid_delays", $"delays.{p.Name}",
                                "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)");
                    }
                }
            }
            if (Has(plan, "planVersion"))
            {
                var pv = Get(plan, "planVersion");
                if (!(IsInteger(pv) && Num(pv) >= 1))
                    Err("invalid_field", "planVersion", "planVersion must be an integer >= 1");
            }
            if (Has(plan, "prevPlanHash"))
            {
                string? pph = Str(Get(plan, "prevPlanHash"));
                if (pph == null || !Regex.IsMatch(pph, "^[0-9a-f]{64}$"))
                    Err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters");
            }
            foreach (var f in new[] { "questions", "actions" })
                if (Get(plan, f) is JsonElement fv && fv.ValueKind != JsonValueKind.Array)
                    Err("invalid_field", f, $"{f} must be an array");
        }

        errors.AddRange(ReservedFieldErrors(plan));
        return new PlanValidation(errors.Count == 0, errors);
    }

    /// <summary>Validate plan JSON text.</summary>
    public static PlanValidation ValidatePlan(string json)
    {
        JsonElement e;
        try { e = Parse(json); }
        catch (JsonException) { return new PlanValidation(false, new() { new("not_an_object", "", "plan must be an object") }); }
        return ValidatePlan(e);
    }

    /// <summary>Validate a typed v1.1 plan through its wire projection.</summary>
    public static PlanValidation ValidatePlan(PlanV11 plan) =>
        ValidatePlan(Parse(LtxSecurity.CanonicalJSON(plan.ToDict())));

    // ── planId over the wire form ────────────────────────────────────────────

    private static string CompactUpper(string s) => LtxSecurity.StripJsSpaceUpper(s);

    private static string Slice(string s, int n) => s.Length > n ? s.Substring(0, n) : s;

    /// <summary>
    /// makePlanId over plan JSON text with key order preserved. Mirrors
    /// ltx-sdk.js makePlanId(JSON.parse(json)) for v2 and v3 plans with nodes:
    /// the FROZEN v2 hash is imul31 over the UTF-16 code units of
    /// JSON.stringify in insertion order, including fields the typed models
    /// do not carry (relay, key order); v3 hashes SHA-256 over the RFC 8785
    /// canonical JSON.
    /// </summary>
    public static string MakePlanIdFromJson(string json)
    {
        var plan = Parse(json);
        var start = DateTimeOffset.Parse(Str(Get(plan, "start"))!, CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal).UtcDateTime;
        string date = start.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        var names = Get(plan, "nodes") is { ValueKind: JsonValueKind.Array } nodes
            ? nodes.EnumerateArray().Select(n => Str(Get(n, "name")) ?? "").ToList()
            : new List<string>();
        string hostStr = names.Count > 0 ? Slice(CompactUpper(names[0]), 8) : "HOST";
        string nodeStr = names.Count > 1
            ? Slice(string.Join("-", names.Skip(1).Select(n => Slice(CompactUpper(n), 4))), 16)
            : "RX";
        if (Num(Get(plan, "v")) >= 3)
            return $"LTX-{date}-{hostStr}-{nodeStr}-v3-{PlanHash(plan).Substring(0, 8)}";
        uint h = 0;
        foreach (char c in Stringify(plan)) h = unchecked(h * 31u + c);
        return $"LTX-{date}-{hostStr}-{nodeStr}-v2-{h:x8}";
    }

    /// <summary>SHA-256 hex of the canonical JSON of a plan element.</summary>
    public static string PlanHash(JsonElement plan) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(LtxSecurity.CanonicalJSON(plan)))).ToLower();

    /// <summary>SHA-256 hex of the canonical JSON of plan JSON text.</summary>
    public static string PlanHashFromJson(string json) => PlanHash(Parse(json));
}
