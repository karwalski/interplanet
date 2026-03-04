// SecurityTests.cs -- Epic 29 security cascade tests (Stories 29.1, 29.4, 29.5)
// Tests: canonicalJSON, generateNIK, isNIKExpired, signVerify, sequenceTracker

using InterplanetLtx;
using System.Text.Json;

public static class SecurityTests
{
    public static void Run(Action<bool, string> Check)
    {
        var dA = new Dictionary<string, object?> { ["z"] = (object?)"last", ["a"] = "first", ["m"] = "mid" };
        var dB = new Dictionary<string, object?> { ["m"] = (object?)"mid", ["z"] = "last", ["a"] = "first" };
        string cA = LtxSecurity.CanonicalJSON(dA);
        string cB = LtxSecurity.CanonicalJSON(dB);
        Check(cA == cB,                        "canonicalJSON: key order normalised");
        Check(cA == "{\"a\":\"first\",\"m\":\"mid\",\"z\":\"last\"}",
                                              "canonicalJSON: exact output");

        var doc = JsonDocument.Parse("{\"z\":1,\"a\":2,\"m\":3}");
        string cDoc = LtxSecurity.CanonicalJSON(doc.RootElement);
        Check(cDoc == "{\"a\":2,\"m\":3,\"z\":1}",   "canonicalJSON: JsonElement sorted");

        // ---- generateNIK_fields ----
        var nikResult = LtxSecurity.GenerateNIK();
        var nik = nikResult.Nik;
        Check(nik.NodeId.Length == 16,               "generateNIK: nodeId is 16 hex chars");
        Check(nik.NodeId == nik.NodeId.ToLower(),    "generateNIK: nodeId is lowercase hex");
        Check(nik.PublicKeyB64.Length > 0,           "generateNIK: publicKeyB64 set");
        Check(nikResult.PrivateKeyB64.Length > 0,    "generateNIK: privateKeyB64 set");
        Check(nik.KeyType == "ltx-nik-v1",           "generateNIK: KeyType=ltx-nik-v1");
        Check(nik.ValidFrom.EndsWith("Z"),           "generateNIK: validFrom UTC ISO");
        Check(nik.ValidUntil.EndsWith("Z"),          "generateNIK: validUntil UTC ISO");
        Check(!LtxSecurity.IsNIKExpired(nik),        "generateNIK: fresh NIK not expired");
        var nik30 = LtxSecurity.GenerateNIK(validDays: 30, nodeLabel: "test");
        Check(nik30.Nik.NodeLabel == "test",         "generateNIK: nodeLabel set");

        // ---- isNIKExpired ----
        var expiredNik = nik with { ValidUntil = "2020-01-01T00:00:00Z" };
        Check(LtxSecurity.IsNIKExpired(expiredNik),  "isNIKExpired: past date true");
        var futureNik = nik with { ValidUntil = "2099-01-01T00:00:00Z" };
        Check(!LtxSecurity.IsNIKExpired(futureNik),  "isNIKExpired: future date false");

        // ---- signVerifyPlan_valid ----
        var nikR = LtxSecurity.GenerateNIK();
        var plan = new Dictionary<string, object?>
            { ["title"] = (object?)"Test Session", ["start"] = "2024-01-15T14:00:00Z", ["quantum"] = 3 };
        var signed = LtxSecurity.SignPlan(plan, nikR.PrivateKeyB64);
        Check(signed.PayloadB64.Length > 0,          "signPlan: payloadB64 set");
        Check(signed.Sig.Length > 0,                 "signPlan: sig set");
        Check(signed.SignerNodeId.Length == 16,       "signPlan: signerNodeId 16 hex");
        Check(signed.SignerNodeId == nikR.Nik.NodeId, "signPlan: signerNodeId matches NIK");
        var keyCache = new Dictionary<string, Nik> { [nikR.Nik.NodeId] = nikR.Nik };
        var vOk = LtxSecurity.VerifyPlan(signed, keyCache);
        Check(vOk.Valid,                             "verifyPlan: valid returns true");
        Check(vOk.Reason == null,                    "verifyPlan: reason null on success");

        // ---- signVerifyPlan_tampered ----
        var tamperedPlan = new Dictionary<string, object?>
            { ["title"] = (object?)"TAMPERED", ["start"] = "2024-01-15T14:00:00Z", ["quantum"] = 3 };
        var tSigned = new SignedPlan(tamperedPlan, signed.PayloadB64, signed.Sig, signed.SignerNodeId);
        var vTampered = LtxSecurity.VerifyPlan(tSigned, keyCache);
        Check(!vTampered.Valid,                      "verifyPlan tampered: false");
        Check(vTampered.Reason == "payload_mismatch","verifyPlan tampered: payload_mismatch");

        // ---- signVerifyPlan_wrong_key ----
        Dictionary<string, Nik> emptyCache = new();
        var vNoKey = LtxSecurity.VerifyPlan(signed, emptyCache);
        Check(!vNoKey.Valid,                         "verifyPlan wrong key: false");
        Check(vNoKey.Reason == "key_not_in_cache",   "verifyPlan wrong key: key_not_in_cache");

        // ---- sequenceTracker_replay ----
        var tracker = new LtxSecurity.SequenceTracker();
        string nid = "node-alpha";
        var b1 = new Dictionary<string, object?> { ["data"] = (object?)"first" };
        var s1 = tracker.AddSeq(b1, nid);
        Check(s1["seq"] is int v1 && v1 == 1,       "addSeq: first seq=1");
        var s2 = tracker.AddSeq(new Dictionary<string, object?> { ["data"] = (object?)"x" }, nid);
        Check(s2["seq"] is int v2 && v2 == 2,       "addSeq: second seq=2");
        var r1 = tracker.CheckSeq(s1, nid);
        Check(r1.Accepted,                          "checkSeq: seq=1 accepted");
        Check(!r1.Gap,                              "checkSeq: seq=1 no gap");
        var r1r = tracker.CheckSeq(s1, nid);
        Check(!r1r.Accepted,                        "checkSeq replay: not accepted");
        Check(r1r.Reason == "replay",               "checkSeq replay: reason=replay");

        // ---- sequenceTracker_gap ----
        var tracker2 = new LtxSecurity.SequenceTracker();
        string nid2 = "node-beta";
        Dictionary<string, object?>[] bs = new Dictionary<string, object?>[5];
        for (int i = 0; i < 5; i++)
            bs[i] = tracker2.AddSeq(new Dictionary<string, object?> { ["i"] = (object?)i }, nid2);
        var gr1 = tracker2.CheckSeq(bs[0], nid2);
        Check(gr1.Accepted && !gr1.Gap,              "checkSeq: seq=1 ok no gap");
        var gr2 = tracker2.CheckSeq(bs[1], nid2);
        Check(gr2.Accepted && !gr2.Gap,              "checkSeq: seq=2 ok no gap");
        var gr5 = tracker2.CheckSeq(bs[4], nid2);
        Check(gr5.Accepted,                          "checkSeq gap: seq=5 accepted");
        Check(gr5.Gap,                               "checkSeq gap: Gap=true");
        Check(gr5.GapSize == 2,                      "checkSeq gap: GapSize=2");
    }
}
