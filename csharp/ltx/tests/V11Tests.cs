// V11Tests.cs — Epic 72 (Story 72.3): LTX v1.1 core subset conformance tests.
// Golden constants embedded from conformance/vectors.json (.v11 section).

using InterplanetLtx;

public static class V11Tests
{
    // ── Golden vector constants (conformance/vectors.json .v11) ─────────────

    private const string NodeId = "Vkdap1RjR0wChd9dvyvKtw";
    private const string PublicKey = "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg";
    private const string ValidUntil = "2046-01-01T00:00:00.000Z";

    private const string ExpectedPlanIdV3 = "LTX-20400201-EARTHHQ-MARS-LUNA-v3-a6120a8d";
    private const string ExpectedPlanIdV2 = "LTX-20400201-EARTHHQ-MARS-LUNA-v2-3471002b";
    private const string ExpectedSha256 =
        "a6120a8db075fb40de472c30c8afcce6c8635f829621723e6855769641b1b028";
    private const string RootPlanHash =
        "58710a510afe517cbd2ed014a3fc5c33d48b9ba26cc59d7ab75613528fa9411f";
    private const string ExpectedEntriesRoot =
        "1ab1318b96825b442e6d2a43bebc11a909bc8bcf775055542a54c2faa1b96f3d";

    private const string Protected = "eyJhbGciOi0xOX0";
    private const string RootPayload =
        "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInF1YW50dW0iOjUsInNlZ21lbnRzIjpbeyJxIjoyLCJ0eXBlIjoiUExBTl9DT05GSVJNIn0seyJsYWJlbCI6Ik9wZW5pbmciLCJxIjozLCJzcGVha2VyIjoiTjAiLCJ0eXBlIjoiVFgifSx7ImxhYmVsIjoiTWFycyBSZXBvcnQiLCJxIjozLCJzcGVha2VyIjoiTjEiLCJ0eXBlIjoiVFgifSx7InEiOjIsInR5cGUiOiJNRVJHRSJ9XSwic3RhcnQiOiIyMDQwLTAyLTAxVDEyOjAwOjAwLjAwMFoiLCJ0aXRsZSI6IlZlY3RvciBTdW1taXQiLCJ2IjoyfQ";
    private const string RootSig =
        "2zHRgtxRFQvcNfj-XPFtqB0qg-Ipbx0CsmxgKK9zWCguMfvVADHdEYQtE1ko5z2fZnxd2MPVrx6FrFsww5hgAw";
    private const string AmdPayload =
        "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInBsYW5WZXJzaW9uIjoyLCJwcmV2UGxhbkhhc2giOiI1ODcxMGE1MTBhZmU1MTdjYmQyZWQwMTRhM2ZjNWMzM2Q0OGI5YmEyNmNjNTlkN2FiNzU2MTM1MjhmYTk0MTFmIiwicXVhbnR1bSI6NSwic2VnbWVudHMiOlt7InEiOjIsInR5cGUiOiJQTEFOX0NPTkZJUk0ifSx7ImxhYmVsIjoiT3BlbmluZyIsInEiOjMsInNwZWFrZXIiOiJOMCIsInR5cGUiOiJUWCJ9LHsibGFiZWwiOiJNYXJzIFJlcG9ydCIsInEiOjMsInNwZWFrZXIiOiJOMSIsInR5cGUiOiJUWCJ9LHsicSI6MiwidHlwZSI6Ik1FUkdFIn1dLCJzdGFydCI6IjIwNDAtMDItMDFUMTI6MDA6MDAuMDAwWiIsInRpdGxlIjoiVmVjdG9yIFN1bW1pdCAoYW1lbmRlZCkiLCJ2IjozfQ";
    private const string AmdSig =
        "_LfyAbDXQf-0ayJeC8-Tif9PNGMxiTHoCCYOz9C9Oa5Hg0I5GHZSa6c-HiYdOnFBkBgCr4TrrUGoJ_bKUrc7AA";

    private const string Entry1Sig =
        "-_CozI8Uz_sCodjoOab097slBkYttOnE-3jY8-MXbBPYk_B5CUP-Xem4Xz1BSokXVzoQAUP15_CWMi8oHACvDw";
    private const string Entry2Sig =
        "uvMUnPlkMCKqjpU4MPuBBQXq1O7oEKs4tUaDQHTu50G8CX4NjyeJ8cX65Ot23rVer3Ea1VrIFrEq7lKWCNz8DA";

    private const string CoseSign1CborB64 =
        "0oRDoQEyoQRQVkdap1RjR0wChd9dvyvKt1kCBXsibW9kZSI6IkxUWC1BU1lOQyIsIm5vZGVzIjpbeyJkZWxheSI6MCwiaWQiOiJO" +
        "MCIsImxvY2F0aW9uIjoiZWFydGgiLCJuYW1lIjoiRWFydGggSFEiLCJyb2xlIjoiSE9TVCJ9LHsiZGVsYXkiOjkwMCwiaWQiOiJO" +
        "MSIsImxvY2F0aW9uIjoibWFycyIsIm5hbWUiOiJNYXJzIEhhYiIsInJvbGUiOiJQQVJUSUNJUEFOVCJ9LHsiZGVsYXkiOjIsImlk" +
        "IjoiTjIiLCJsb2NhdGlvbiI6Im1vb24iLCJuYW1lIjoiTHVuYSBCYXNlIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn1dLCJxdWFudHVt" +
        "Ijo1LCJzZWdtZW50cyI6W3sicSI6MiwidHlwZSI6IlBMQU5fQ09ORklSTSJ9LHsibGFiZWwiOiJPcGVuaW5nIiwicSI6Mywic3Bl" +
        "YWtlciI6Ik4wIiwidHlwZSI6IlRYIn0seyJsYWJlbCI6Ik1hcnMgUmVwb3J0IiwicSI6Mywic3BlYWtlciI6Ik4xIiwidHlwZSI6" +
        "IlRYIn0seyJxIjoyLCJ0eXBlIjoiTUVSR0UifV0sInN0YXJ0IjoiMjA0MC0wMi0wMVQxMjowMDowMC4wMDBaIiwidGl0bGUiOiJW" +
        "ZWN0b3IgU3VtbWl0IiwidiI6Mn1YQNDg5fHexnBLnLbQ5eCoVQfGOlbfhyXYx0xD4Q42Kh8T-FgyPhB_2-QrwEuvYgmZHnDGwfzj" +
        "oxnAI_NVLJE2XQI";

    // ── Plan builders ────────────────────────────────────────────────────────

    private static List<NodeV11> VectorNodes() => new()
    {
        new NodeV11("N0", "Earth HQ", "HOST", 0, "earth"),
        new NodeV11("N1", "Mars Hab", "PARTICIPANT", 900, "mars"),
        new NodeV11("N2", "Luna Base", "PARTICIPANT", 2, "moon"),
    };

    private static List<SegmentTemplateV11> VectorSegments() => new()
    {
        new SegmentTemplateV11("PLAN_CONFIRM", 2),
        new SegmentTemplateV11("TX", 3, Speaker: "N0", Label: "Opening"),
        new SegmentTemplateV11("TX", 3, Speaker: "N1", Label: "Mars Report"),
        new SegmentTemplateV11("MERGE", 2),
    };

    private static PlanV11 PlanV2() => new()
    {
        V = 2, Title = "Vector Summit", Start = "2040-02-01T12:00:00.000Z",
        Quantum = 5, Mode = "LTX-ASYNC",
        Nodes = VectorNodes(), Segments = VectorSegments(),
    };

    private static PlanV11 PlanV3() => PlanV2() with
    {
        V = 3,
        Delays = new Dictionary<string, long> { ["N1|N2"] = 500 },
        PlanVersion = 1,
    };

    private static PlanV11 AmendedPlan() => PlanV2() with
    {
        V = 3, Title = "Vector Summit (amended)",
        PlanVersion = 2, PrevPlanHash = RootPlanHash,
    };

    private static Dictionary<string, NikV11> KidCache() => new()
    {
        [NodeId] = new NikV11(NodeId, PublicKey, ValidUntil),
    };

    public static void Run(Action<bool, string> Check)
    {
        // ── 1a. v3 planId ────────────────────────────────────────────────────
        var p3 = PlanV3();
        Check(LtxSecurity.CanonicalJSON(p3.ToDict()).Length > 0, "v11: canonical JSON produced");
        Check(LtxV11.PlanHash(p3) == ExpectedSha256, "v11 planIdV3: canonical SHA-256 matches");
        Check(LtxV11.MakePlanId(p3) == ExpectedPlanIdV3, "v11 planIdV3: expected plan id");

        // ── 1b. v2 regression (FROZEN) ───────────────────────────────────────
        Check(LtxV11.MakePlanId(PlanV2()) == ExpectedPlanIdV2, "v11 planIdV2: FROZEN v2 hash unchanged");

        // ── 1c. pairDelay ────────────────────────────────────────────────────
        Check(LtxV11.PairDelay(p3, "N0", "N1") == 900, "v11 pairDelay: N0|N1 = 900");
        Check(LtxV11.PairDelay(p3, "N1", "N0") == 900, "v11 pairDelay: N1|N0 symmetric");
        Check(LtxV11.PairDelay(p3, "N1", "N2") == 500, "v11 pairDelay: v3 matrix N1|N2 = 500");
        Check(LtxV11.PairDelay(p3, "N2", "N1") == 500, "v11 pairDelay: matrix symmetric");
        Check(LtxV11.PairDelay(p3, "N1", "N1") == 0, "v11 pairDelay: same node = 0");
        Check(LtxV11.PairDelay(PlanV2(), "N1", "N2") == 902, "v11 pairDelay: conservative fallback 902");

        // ── 1d. computeSegmentsFor ───────────────────────────────────────────
        var baseSegs = LtxV11.ComputeSegmentsV11(p3);
        var forN2 = LtxV11.ComputeSegmentsFor(p3, "N2");
        var forN0 = LtxV11.ComputeSegmentsFor(p3, "N0");
        var forN1 = LtxV11.ComputeSegmentsFor(p3, "N1");
        Check(forN2.Count == 4, "v11 segmentsFor: 4 segments");
        Check(forN2[0].Perspective == "neutral" && forN2[0].ArrivalOffsetS == 0,
            "v11 segmentsFor: PLAN_CONFIRM neutral");
        Check(forN0[1].Perspective == "transmit" && forN0[1].ArrivalOffsetS == 0,
            "v11 segmentsFor: own TX is transmit");
        Check(forN2[1].Perspective == "receive" && forN2[1].ArrivalOffsetS == 2,
            "v11 segmentsFor: N0 TX arrives at N2 +2s");
        Check(forN2[1].StartMs == baseSegs[1].StartMs + 2000,
            "v11 segmentsFor: start shifted by pair delay");
        Check(forN2[2].Perspective == "receive" && forN2[2].ArrivalOffsetS == 500,
            "v11 segmentsFor: N1 TX arrives at N2 +500s (v3 matrix)");
        Check(forN1[1].ArrivalOffsetS == 900 && forN1[1].EndMs == baseSegs[1].EndMs + 900000,
            "v11 segmentsFor: N0 TX arrives at N1 +900s");
        Check(forN0[3].Perspective == "neutral", "v11 segmentsFor: MERGE neutral");
        bool threw = false;
        try { LtxV11.ComputeSegmentsFor(p3, "NX"); } catch (ArgumentException) { threw = true; }
        Check(threw, "v11 segmentsFor: unknown viewer throws");

        // ── 3. amendment chain ───────────────────────────────────────────────
        var cache = KidCache();
        var chain = new List<SignedPlanV11>
        {
            new SignedPlanV11(PlanV2(), new CoseSign1Json(Protected, NodeId, RootPayload, RootSig)),
            new SignedPlanV11(AmendedPlan(), new CoseSign1Json(Protected, NodeId, AmdPayload, AmdSig)),
        };
        Check(LtxV11.PlanHash(PlanV2()) == RootPlanHash, "v11 amend: root plan hash matches");
        Check(LtxV11.VerifyPlanEnvelope(chain[0], cache).Valid, "v11 amend: root signature valid");
        Check(LtxV11.VerifyPlanEnvelope(chain[1], cache).Valid, "v11 amend: amendment signature valid");
        Check(LtxV11.VerifyAmendmentChain(chain, cache).Valid, "v11 amend: chain verifies");
        var tampered = new List<SignedPlanV11>
        {
            chain[0],
            chain[1] with { Plan = chain[1].Plan with { Title = "EVIL" } },
        };
        var tv = LtxV11.VerifyAmendmentChain(tampered, cache);
        Check(!tv.Valid, "v11 amend: tampered title rejected");
        Check(tv.Reason == "link_1_payload_mismatch", "v11 amend: tamper reason payload_mismatch");
        Check(!LtxV11.VerifyAmendmentChain(new List<SignedPlanV11>(), cache).Valid,
            "v11 amend: empty chain invalid");
        Check(!LtxV11.VerifyAmendmentChain(chain, new Dictionary<string, NikV11>()).Valid,
            "v11 amend: unknown key rejected");

        // ── 4. register entries + reducers ───────────────────────────────────
        var e1 = new RegisterEntryV11("QST-N1-1", "VEC-SESSION", "N1", 1, "question",
            new Dictionary<string, object?> { ["text"] = "Status?", ["urgency"] = "high" },
            "2040-02-01T11:00:00.000Z", Entry1Sig);
        var e2 = new RegisterEntryV11("QST-N0-1", "VEC-SESSION", "N0", 1, "question_response",
            new Dictionary<string, object?> { ["qid"] = "QST-N1-1", ["response"] = "Nominal", ["version"] = 2 },
            "2040-02-01T11:05:00.000Z", Entry2Sig);
        var nodeCache = new Dictionary<string, NikV11>
        {
            ["N0"] = new NikV11(NodeId, PublicKey, ValidUntil),
            ["N1"] = new NikV11(NodeId, PublicKey, ValidUntil),
        };
        Check(LtxV11.VerifyRegisterEntry(e1, nodeCache).Valid, "v11 registers: entry 1 signature valid");
        Check(LtxV11.VerifyRegisterEntry(e2, nodeCache).Valid, "v11 registers: entry 2 signature valid");
        Check(!LtxV11.VerifyRegisterEntry(e1 with { Seq = 9 }, nodeCache).Valid,
            "v11 registers: tampered entry rejected");
        Check(!LtxV11.VerifyRegisterEntry(e1, new Dictionary<string, NikV11>()).Valid,
            "v11 registers: unknown node key rejected");

        var ordered = LtxV11.OrderEntries(new List<RegisterEntryV11> { e2, e1, e1 });
        Check(ordered.Count == 2 && ordered[0].EntryId == "QST-N1-1",
            "v11 registers: dedup + (timestamp,nodeId,seq) order");

        var red = LtxV11.ReduceQuestions(new List<RegisterEntryV11> { e2, e1 });
        Check(red.ById.Count == 1 && red.ById.ContainsKey("QST-N1-1"),
            "v11 registers: reduceQuestions single question");
        var q = red.ById["QST-N1-1"];
        Check(q.Qid == "QST-N1-1" && q.Text == "Status?" && q.Submitter == "N1" &&
              q.Urgency == "high" && q.Status == "ANSWERED" && q.Version == 2 &&
              q.Response == "Nominal" && q.Responder == "N0",
            "v11 registers: question state matches expectedQuestionState");
        Check(red.Superseded.Count == 0, "v11 registers: nothing superseded");

        Check(LtxV11.EntriesRoot(ordered) == ExpectedEntriesRoot,
            "v11 registers: entriesRoot Merkle root matches");

        // action reducer sanity (no golden vector — semantics per §10.2)
        var a1 = new RegisterEntryV11("ACT-N1-2", "VEC-SESSION", "N1", 2, "action",
            new Dictionary<string, object?> { ["description"] = "Fix antenna" },
            "2040-02-01T11:10:00.000Z", "x");
        var a2 = new RegisterEntryV11("ACT-N0-2", "VEC-SESSION", "N0", 2, "action_update",
            new Dictionary<string, object?> { ["aid"] = "ACT-N1-2", ["status"] = "ACCEPTED", ["version"] = 2 },
            "2040-02-01T11:11:00.000Z", "x");
        var ar = LtxV11.ReduceActions(new List<RegisterEntryV11> { a2, a1 });
        Check(ar.ById["ACT-N1-2"].Status == "ACCEPTED" && ar.ById["ACT-N1-2"].Version == 2,
            "v11 registers: reduceActions applies update");

        // ── 5. CBOR + COSE_Sign1 ─────────────────────────────────────────────
        byte[] coseBytes = LtxSecurity.FromBase64Url(CoseSign1CborB64);
        object? decoded = LtxV11.DecodeCbor(coseBytes);
        Check(decoded is CborTagV11 t18 && t18.Tag == 18, "v11 cose: decodes to tag 18");
        var arr = ((CborTagV11)decoded!).Value as List<object?>;
        Check(arr != null && arr.Count == 4, "v11 cose: COSE_Sign1 array of 4");
        Check(LtxV11.VerifyPlanCose(PlanV2(), CoseSign1CborB64, cache).Valid,
            "v11 cose: COSE_Sign1 verifies against plan + key");
        Check(!LtxV11.VerifyPlanCose(PlanV2() with { Title = "EVIL" }, CoseSign1CborB64, cache).Valid,
            "v11 cose: mismatched plan rejected");
        Check(!LtxV11.VerifyPlanCose(PlanV2(), CoseSign1CborB64,
            new Dictionary<string, NikV11>()).Valid, "v11 cose: unknown kid rejected");
        byte[] truncated = coseBytes.Take(coseBytes.Length - 1).ToArray();
        Check(!LtxV11.VerifyPlanCose(PlanV2(), LtxSecurity.ToBase64Url(truncated), cache).Valid,
            "v11 cose: truncated CBOR rejected");
        bool floatRejected = false;
        try { LtxV11.DecodeCbor(new byte[] { 0xf9, 0x3c, 0x00 }); }
        catch (FormatException) { floatRejected = true; }
        Check(floatRejected, "v11 cbor: floats rejected");
        bool trailingRejected = false;
        try { LtxV11.DecodeCbor(new byte[] { 0x01, 0x02 }); }
        catch (FormatException) { trailingRejected = true; }
        Check(trailingRejected, "v11 cbor: trailing bytes rejected");
        Check(LtxV11.DecodeCbor(new byte[] { 0x18, 0x2a }) is long l42 && l42 == 42,
            "v11 cbor: uint decode");
        Check(LtxV11.DecodeCbor(new byte[] { 0x20 }) is long lm1 && lm1 == -1,
            "v11 cbor: negative int decode");

        // ── 2. session state machine (golden transition table) ──────────────
        var smPlan = PlanV2();
        var ctx = LtxV11.CreateSession(smPlan, ExpectedPlanIdV2, 1);
        Check(ctx.State == "DRAFT" && ctx.Lock == null, "v11 session: starts DRAFT");
        Check(ctx.LockTimeoutMs == 1800000, "v11 session: lock timeout 2×900s");
        Check(ctx.QuorumThreshold == 1, "v11 session: quorum threshold 1");

        var steps = new (SessionEventV11 Ev, string State, string? Lock)[]
        {
            (new SessionEventV11("START_LOCK", 1000), "LOCKING", null),
            (new SessionEventV11("PLAN_CONFIRM", 2000, NodeId: "N2", PlanId: ExpectedPlanIdV2), "LOCKING", null),
            (new SessionEventV11("TICK", 1800999), "LOCKING", null),
            (new SessionEventV11("TICK", 1801000), "DEGRADED", "QUORUM"),
            (new SessionEventV11("PLAN_CONFIRM", 4000000, NodeId: "N1", PlanId: ExpectedPlanIdV2), "LOCKED", "FULL"),
            (new SessionEventV11("SESSION_START", 4100000), "ACTIVE", "FULL"),
            (new SessionEventV11("DELAY_MEASURED", 4200000, NodeId: "N1", MeasuredDelayS: 1201), "DEGRADED", "FULL"),
            (new SessionEventV11("HOST_DECISION", 4300000, Decision: "continue"), "ACTIVE", "FULL"),
            (new SessionEventV11("SESSION_END", 5000000), "COMPLETE", "FULL"),
        };
        int i = 0;
        List<string>? quorumSubset = null;
        foreach (var step in steps)
        {
            ctx = LtxV11.Transition(ctx, step.Ev);
            if (ctx.Lock == "QUORUM" && quorumSubset == null) quorumSubset = ctx.Subset;
            Check(ctx.State == step.State,
                $"v11 session step {i}: {step.Ev.Type} -> state {step.State}");
            Check(ctx.Lock == step.Lock,
                $"v11 session step {i}: {step.Ev.Type} -> lock {(step.Lock ?? "null")}");
            i++;
        }
        Check(quorumSubset != null && string.Join(",", quorumSubset) == "N0,N2",
            "v11 session: quorum subset [N0,N2] (ascending delay)");
        Check(ctx.Subset == null, "v11 session: subset cleared on full-lock recovery");

        // extra machine coverage: abort / emergency hold / amendments
        var ctx2 = LtxV11.CreateSession(smPlan, ExpectedPlanIdV2, "all");
        Check(ctx2.QuorumThreshold == 2, "v11 session: quorum 'all' = 2 participants");
        ctx2 = LtxV11.Transition(ctx2, new SessionEventV11("START_LOCK", 0));
        ctx2 = LtxV11.Transition(ctx2, new SessionEventV11("HOST_DECISION", 1, Decision: "abort"));
        Check(ctx2.State == "ABORTED", "v11 session: host abort");

        var ctx3 = LtxV11.CreateSession(smPlan, ExpectedPlanIdV2, "majority");
        Check(ctx3.QuorumThreshold == 2, "v11 session: majority of 2 = 2");
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("START_LOCK", 0));
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("PLAN_CONFIRM", 1, NodeId: "N1", PlanId: ExpectedPlanIdV2));
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("PLAN_CONFIRM", 2, NodeId: "N2", PlanId: ExpectedPlanIdV2));
        Check(ctx3.State == "LOCKED" && ctx3.Lock == "FULL", "v11 session: full lock on all confirms");
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("SESSION_START", 3));
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("EOK_OVERRIDE", 4, Verified: true));
        Check(ctx3.State == "EMERGENCY_HOLD", "v11 session: verified EOK override holds");
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("HOST_DECISION", 5, Decision: "resume"));
        Check(ctx3.State == "ACTIVE", "v11 session: resume returns to prior state");
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("AMENDMENT_PROPOSED", 6,
            PlanId: "LTX-AMENDED", PlanVersion: 2, AffectedNodeIds: new List<string> { "N1" }));
        Check(ctx3.PendingAmendment != null, "v11 session: amendment pending");
        ctx3 = LtxV11.Transition(ctx3, new SessionEventV11("AMENDMENT_CONFIRMED", 7,
            NodeId: "N1", PlanId: "LTX-AMENDED"));
        Check(ctx3.PlanId == "LTX-AMENDED" && ctx3.PlanVersion == 2 && ctx3.PendingAmendment == null,
            "v11 session: amendment applied after all confirms");

        // mismatched planId confirmation does not count toward the lock
        var ctx4 = LtxV11.CreateSession(smPlan, ExpectedPlanIdV2, "all");
        ctx4 = LtxV11.Transition(ctx4, new SessionEventV11("START_LOCK", 0));
        ctx4 = LtxV11.Transition(ctx4, new SessionEventV11("PLAN_CONFIRM", 1, NodeId: "N1", PlanId: "LTX-WRONG"));
        Check(ctx4.State == "LOCKING" && ctx4.Mismatched.Contains("N1"),
            "v11 session: planId mismatch flagged (§5.5)");
    }
}
