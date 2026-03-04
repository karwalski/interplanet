// Security.cs -- Epic 29 (Stories 29.1, 29.4, 29.5)
// C# port of ltx-sdk.js. Uses NSec.Cryptography for Ed25519.

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using NSec.Cryptography;

namespace InterplanetLtx;

public record Nik(string NodeId, string PublicKeyB64, string ValidFrom,
    string ValidUntil, string KeyType, string NodeLabel);
public record NikResult(Nik Nik, string PrivateKeyB64);
public record SignedPlan(Dictionary<string, object?> Plan,
    string PayloadB64, string Sig, string SignerNodeId);
public record VerifyResult(bool Valid, string? Reason = null);
public record CheckSeqResult(bool Accepted, string? Reason = null,
    bool Gap = false, int GapSize = 0);

public static class LtxSecurity
{
    private static readonly SignatureAlgorithm Ed = SignatureAlgorithm.Ed25519;
    private static KeyCreationParameters ExportableKey =>
        new() { ExportPolicy = KeyExportPolicies.AllowPlaintextExport };

    internal static string ToBase64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    internal static byte[] FromBase64Url(string s)
    {
        string std = s.Replace('-', '+').Replace('_', '/');
        int mod = std.Length % 4;
        if (mod == 2) std += "==";
        else if (mod == 3) std += "=";
        return Convert.FromBase64String(std);
    }

    public static string CanonicalJSON(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                var props = element.EnumerateObject()
                    .OrderBy(p => p.Name, StringComparer.Ordinal)
                    .Select(p => JsonSerializer.Serialize(p.Name) + ":" + CanonicalJSON(p.Value));
                return "{" + string.Join(",", props) + "}";
            case JsonValueKind.Array:
                var items = element.EnumerateArray().Select(CanonicalJSON);
                return "[" + string.Join(",", items) + "]";
            default:
                return element.GetRawText();
        }
    }

    public static string CanonicalJSON(Dictionary<string, object?> dict)
    {
        var sorted = dict.OrderBy(kv => kv.Key, StringComparer.Ordinal);
        var parts = sorted.Select(kv =>
            JsonSerializer.Serialize(kv.Key) + ":" + SerializeValue(kv.Value));
        return "{" + string.Join(",", parts) + "}";
    }

    private static string SerializeValue(object? v)
    {
        if (v == null) return "null";
        if (v is bool bval) return bval ? "true" : "false";
        if (v is string sv) return JsonSerializer.Serialize(sv);
        if (v is int iv) return iv.ToString();
        if (v is long lv) return lv.ToString();
        if (v is double dv) return dv.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (v is float fv) return fv.ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (v is Dictionary<string, object?> nd) return CanonicalJSON(nd);
        if (v is System.Collections.IEnumerable seq)
        {
            var sb = new StringBuilder("[");
            bool first = true;
            foreach (var item in seq)
            {
                if (!first) sb.Append(",");
                first = false;
                sb.Append(SerializeValue(item));
            }
            sb.Append("]");
            return sb.ToString();
        }
        return JsonSerializer.Serialize(v.ToString());
    }

    public static NikResult GenerateNIK(int validDays = 365, string nodeLabel = "")
    {
        using var key = Key.Create(Ed, ExportableKey);
        byte[] rawPub = key.PublicKey.Export(KeyBlobFormat.RawPublicKey);
        string pubB64 = ToBase64Url(rawPub);
        byte[] hash = SHA256.HashData(rawPub);
        string nodeId = Convert.ToHexString(hash[..8]).ToLower();
        var now = DateTimeOffset.UtcNow;
        var until = now.AddDays(validDays);
        var nik = new Nik(
            NodeId:      nodeId,
            PublicKeyB64: pubB64,
            ValidFrom:   now.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            ValidUntil:  until.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            KeyType:     "ltx-nik-v1",
            NodeLabel:   nodeLabel);
        byte[] seed = key.Export(KeyBlobFormat.RawPrivateKey);
        return new NikResult(nik, ToBase64Url(seed));
    }

    public static bool IsNIKExpired(Nik nik) =>
        DateTimeOffset.UtcNow > DateTimeOffset.Parse(nik.ValidUntil,
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AssumeUniversal);

    public static SignedPlan SignPlan(Dictionary<string, object?> plan, string privKeyB64)
    {
        byte[] seed = FromBase64Url(privKeyB64);
        using var key = Key.Import(Ed, seed, KeyBlobFormat.RawPrivateKey, ExportableKey);
        string payStr = CanonicalJSON(plan);
        byte[] payB = Encoding.UTF8.GetBytes(payStr);
        string payB64 = ToBase64Url(payB);
        byte[] sig = Ed.Sign(key, payB);
        string sigB64 = ToBase64Url(sig);
        byte[] rawPub = key.PublicKey.Export(KeyBlobFormat.RawPublicKey);
        string nid = Convert.ToHexString(SHA256.HashData(rawPub)[..8]).ToLower();
        return new SignedPlan(plan, payB64, sigB64, nid);
    }

    public static VerifyResult VerifyPlan(SignedPlan sp, Dictionary<string, Nik> cache)
    {
        if (!cache.TryGetValue(sp.SignerNodeId, out var signer))
            return new VerifyResult(false, "key_not_in_cache");
        if (IsNIKExpired(signer))
            return new VerifyResult(false, "key_expired");
        byte[] expected = Encoding.UTF8.GetBytes(CanonicalJSON(sp.Plan));
        byte[] actual = FromBase64Url(sp.PayloadB64);
        if (!expected.SequenceEqual(actual))
            return new VerifyResult(false, "payload_mismatch");
        byte[] rawPub = FromBase64Url(signer.PublicKeyB64);
        var pubKey = PublicKey.Import(Ed, rawPub, KeyBlobFormat.RawPublicKey);
        bool ok = Ed.Verify(pubKey, actual, FromBase64Url(sp.Sig));
        return ok ? new VerifyResult(true) : new VerifyResult(false, "signature_invalid");
    }

    public class SequenceTracker
    {
        private readonly Dictionary<string, int> _rx = new();
        private readonly Dictionary<string, int> _tx = new();

        public Dictionary<string, object?> AddSeq(Dictionary<string, object?> bundle, string nodeId)
        {
            if (!_tx.TryGetValue(nodeId, out int cur)) cur = 0;
            int next = cur + 1;
            _tx[nodeId] = next;
            Dictionary<string, object?> result = new();
            foreach (var kv in bundle) result[kv.Key] = kv.Value;
            result["seq"] = (object?)next;
            return result;
        }

        public CheckSeqResult CheckSeq(Dictionary<string, object?> bundle, string nodeId)
        {
            if (!bundle.TryGetValue("seq", out var seqObj) || seqObj is not int seq)
                return new CheckSeqResult(false, "missing_seq");
            if (!_rx.TryGetValue(nodeId, out int last)) last = 0;
            if (seq <= last) return new CheckSeqResult(false, "replay");
            bool gap = seq > last + 1;
            int gs = gap ? seq - last - 1 : 0;
            _rx[nodeId] = seq;
            return new CheckSeqResult(true, null, gap, gs);
        }
    }
}
