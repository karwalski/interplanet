#!/usr/bin/env dotnet-script
// V11Test.fsx --- Epic 72 (Story 72.3): LTX v1.1 core subset conformance tests.
// Golden constants embedded from conformance/vectors.json (.v11 section).
// Run with: dotnet fsi tests/V11Test.fsx

#r "nuget: NSec.Cryptography, 24.4.0"
#load "../src/Security.fs"
#load "../src/V11.fs"

open System
open System.Collections.Generic
open InterplanetLtx.Security
open InterplanetLtx.V11

let mutable passed = 0
let mutable failed = 0

let check label cond =
    if cond then passed <- passed + 1
    else failed <- failed + 1; printfn "FAIL: %s" label

// ---- golden vector constants (conformance/vectors.json .v11) ----

let NODE_ID = "Vkdap1RjR0wChd9dvyvKtw"
let PUBLIC_KEY = "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"
let VALID_UNTIL = "2046-01-01T00:00:00.000Z"

let EXPECTED_PLAN_ID_V3 = "LTX-20400201-EARTHHQ-MARS-LUNA-v3-a6120a8d"
let EXPECTED_PLAN_ID_V2 = "LTX-20400201-EARTHHQ-MARS-LUNA-v2-3471002b"
let EXPECTED_SHA256 = "a6120a8db075fb40de472c30c8afcce6c8635f829621723e6855769641b1b028"
let ROOT_PLAN_HASH = "58710a510afe517cbd2ed014a3fc5c33d48b9ba26cc59d7ab75613528fa9411f"
let EXPECTED_ENTRIES_ROOT = "1ab1318b96825b442e6d2a43bebc11a909bc8bcf775055542a54c2faa1b96f3d"

let PROTECTED = "eyJhbGciOi0xOX0"
let ROOT_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInF1YW50dW0iOjUsInNlZ21lbnRzIjpbeyJxIjoyLCJ0eXBlIjoiUExBTl9DT05GSVJNIn0seyJsYWJlbCI6Ik9wZW5pbmciLCJxIjozLCJzcGVha2VyIjoiTjAiLCJ0eXBlIjoiVFgifSx7ImxhYmVsIjoiTWFycyBSZXBvcnQiLCJxIjozLCJzcGVha2VyIjoiTjEiLCJ0eXBlIjoiVFgifSx7InEiOjIsInR5cGUiOiJNRVJHRSJ9XSwic3RhcnQiOiIyMDQwLTAyLTAxVDEyOjAwOjAwLjAwMFoiLCJ0aXRsZSI6IlZlY3RvciBTdW1taXQiLCJ2IjoyfQ"
let ROOT_SIG = "2zHRgtxRFQvcNfj-XPFtqB0qg-Ipbx0CsmxgKK9zWCguMfvVADHdEYQtE1ko5z2fZnxd2MPVrx6FrFsww5hgAw"
let AMD_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInBsYW5WZXJzaW9uIjoyLCJwcmV2UGxhbkhhc2giOiI1ODcxMGE1MTBhZmU1MTdjYmQyZWQwMTRhM2ZjNWMzM2Q0OGI5YmEyNmNjNTlkN2FiNzU2MTM1MjhmYTk0MTFmIiwicXVhbnR1bSI6NSwic2VnbWVudHMiOlt7InEiOjIsInR5cGUiOiJQTEFOX0NPTkZJUk0ifSx7ImxhYmVsIjoiT3BlbmluZyIsInEiOjMsInNwZWFrZXIiOiJOMCIsInR5cGUiOiJUWCJ9LHsibGFiZWwiOiJNYXJzIFJlcG9ydCIsInEiOjMsInNwZWFrZXIiOiJOMSIsInR5cGUiOiJUWCJ9LHsicSI6MiwidHlwZSI6Ik1FUkdFIn1dLCJzdGFydCI6IjIwNDAtMDItMDFUMTI6MDA6MDAuMDAwWiIsInRpdGxlIjoiVmVjdG9yIFN1bW1pdCAoYW1lbmRlZCkiLCJ2IjozfQ"
let AMD_SIG = "_LfyAbDXQf-0ayJeC8-Tif9PNGMxiTHoCCYOz9C9Oa5Hg0I5GHZSa6c-HiYdOnFBkBgCr4TrrUGoJ_bKUrc7AA"

let ENTRY1_SIG = "-_CozI8Uz_sCodjoOab097slBkYttOnE-3jY8-MXbBPYk_B5CUP-Xem4Xz1BSokXVzoQAUP15_CWMi8oHACvDw"
let ENTRY2_SIG = "uvMUnPlkMCKqjpU4MPuBBQXq1O7oEKs4tUaDQHTu50G8CX4NjyeJ8cX65Ot23rVer3Ea1VrIFrEq7lKWCNz8DA"

let COSE_SIGN1_CBOR_B64 =
    "0oRDoQEyoQRQVkdap1RjR0wChd9dvyvKt1kCBXsibW9kZSI6IkxUWC1BU1lOQyIsIm5vZGVzIjpbeyJkZWxheSI6MCwiaWQiOiJO" +
    "MCIsImxvY2F0aW9uIjoiZWFydGgiLCJuYW1lIjoiRWFydGggSFEiLCJyb2xlIjoiSE9TVCJ9LHsiZGVsYXkiOjkwMCwiaWQiOiJO" +
    "MSIsImxvY2F0aW9uIjoibWFycyIsIm5hbWUiOiJNYXJzIEhhYiIsInJvbGUiOiJQQVJUSUNJUEFOVCJ9LHsiZGVsYXkiOjIsImlk" +
    "IjoiTjIiLCJsb2NhdGlvbiI6Im1vb24iLCJuYW1lIjoiTHVuYSBCYXNlIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn1dLCJxdWFudHVt" +
    "Ijo1LCJzZWdtZW50cyI6W3sicSI6MiwidHlwZSI6IlBMQU5fQ09ORklSTSJ9LHsibGFiZWwiOiJPcGVuaW5nIiwicSI6Mywic3Bl" +
    "YWtlciI6Ik4wIiwidHlwZSI6IlRYIn0seyJsYWJlbCI6Ik1hcnMgUmVwb3J0IiwicSI6Mywic3BlYWtlciI6Ik4xIiwidHlwZSI6" +
    "IlRYIn0seyJxIjoyLCJ0eXBlIjoiTUVSR0UifV0sInN0YXJ0IjoiMjA0MC0wMi0wMVQxMjowMDowMC4wMDBaIiwidGl0bGUiOiJW" +
    "ZWN0b3IgU3VtbWl0IiwidiI6Mn1YQNDg5fHexnBLnLbQ5eCoVQfGOlbfhyXYx0xD4Q42Kh8T-FgyPhB_2-QrwEuvYgmZHnDGwfzj" +
    "oxnAI_NVLJE2XQI"

// ---- plan builders ----

let vectorNodes = [
    { id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0L; location = "earth" }
    { id = "N1"; name = "Mars Hab"; role = "PARTICIPANT"; delay = 900L; location = "mars" }
    { id = "N2"; name = "Luna Base"; role = "PARTICIPANT"; delay = 2L; location = "moon" }
]

let vectorSegments = [
    { segType = "PLAN_CONFIRM"; q = 2; speaker = None; label = None }
    { segType = "TX"; q = 3; speaker = Some "N0"; label = Some "Opening" }
    { segType = "TX"; q = 3; speaker = Some "N1"; label = Some "Mars Report" }
    { segType = "MERGE"; q = 2; speaker = None; label = None }
]

let planV2 : PlanV11 = {
    v = 2; title = "Vector Summit"; start = "2040-02-01T12:00:00.000Z"
    quantum = 5; mode = "LTX-ASYNC"; nodes = vectorNodes; segments = vectorSegments
    delays = None; planVersion = None; prevPlanHash = None
}

let planV3 = { planV2 with v = 3; delays = Some (Map.ofList [ "N1|N2", 500L ]); planVersion = Some 1 }

let amendedPlan =
    { planV2 with
        v = 3; title = "Vector Summit (amended)"
        planVersion = Some 2; prevPlanHash = Some ROOT_PLAN_HASH }

let nik = { nodeId = NODE_ID; publicKeyB64 = PUBLIC_KEY; validUntil = VALID_UNTIL }
let kidCache = dict [ NODE_ID, nik ]
let emptyCache : IDictionary<string, NikV11> = dict []

// ---- 1a/1b. plan ids ----

check "v11 planIdV3: canonical SHA-256 matches" (planHash planV3 = EXPECTED_SHA256)
check "v11 planIdV3: expected plan id" (makePlanId planV3 = EXPECTED_PLAN_ID_V3)
check "v11 planIdV2: FROZEN v2 hash unchanged" (makePlanId planV2 = EXPECTED_PLAN_ID_V2)

// ---- 1c. pairDelay ----

check "v11 pairDelay: N0|N1 = 900" (pairDelay planV3 "N0" "N1" = 900L)
check "v11 pairDelay: N1|N0 symmetric" (pairDelay planV3 "N1" "N0" = 900L)
check "v11 pairDelay: v3 matrix N1|N2 = 500" (pairDelay planV3 "N1" "N2" = 500L)
check "v11 pairDelay: matrix symmetric" (pairDelay planV3 "N2" "N1" = 500L)
check "v11 pairDelay: same node = 0" (pairDelay planV3 "N1" "N1" = 0L)
check "v11 pairDelay: conservative fallback 902" (pairDelay planV2 "N1" "N2" = 902L)

// ---- 1d. computeSegmentsFor ----

let baseSegs = computeSegmentsV11 planV3
let forN0 = computeSegmentsFor planV3 "N0"
let forN1 = computeSegmentsFor planV3 "N1"
let forN2 = computeSegmentsFor planV3 "N2"
check "v11 segmentsFor: 4 segments" (forN2.Length = 4)
check "v11 segmentsFor: PLAN_CONFIRM neutral"
    (forN2.[0].perspective = "neutral" && forN2.[0].arrivalOffsetS = 0L)
check "v11 segmentsFor: own TX is transmit"
    (forN0.[1].perspective = "transmit" && forN0.[1].arrivalOffsetS = 0L)
check "v11 segmentsFor: N0 TX arrives at N2 +2s"
    (forN2.[1].perspective = "receive" && forN2.[1].arrivalOffsetS = 2L)
check "v11 segmentsFor: start shifted by pair delay"
    (forN2.[1].startMs = baseSegs.[1].startMs + 2000L)
check "v11 segmentsFor: N1 TX arrives at N2 +500s (v3 matrix)"
    (forN2.[2].perspective = "receive" && forN2.[2].arrivalOffsetS = 500L)
check "v11 segmentsFor: N0 TX arrives at N1 +900s"
    (forN1.[1].arrivalOffsetS = 900L && forN1.[1].endMs = baseSegs.[1].endMs + 900000L)
check "v11 segmentsFor: MERGE neutral" (forN0.[3].perspective = "neutral")
let unknownViewerThrew =
    try computeSegmentsFor planV3 "NX" |> ignore; false with _ -> true
check "v11 segmentsFor: unknown viewer throws" unknownViewerThrew

// ---- 3. amendment chain ----

let chain = [
    { plan = planV2
      coseSign1 = { protectedHdr = PROTECTED; kid = NODE_ID; payload = ROOT_PAYLOAD; signature = ROOT_SIG } }
    { plan = amendedPlan
      coseSign1 = { protectedHdr = PROTECTED; kid = NODE_ID; payload = AMD_PAYLOAD; signature = AMD_SIG } }
]
check "v11 amend: root plan hash matches" (planHash planV2 = ROOT_PLAN_HASH)
check "v11 amend: root signature valid" (fst (verifyPlanEnvelope chain.[0] kidCache))
check "v11 amend: amendment signature valid" (fst (verifyPlanEnvelope chain.[1] kidCache))
check "v11 amend: chain verifies" (fst (verifyAmendmentChain chain kidCache))
let tampered = [
    chain.[0]
    { chain.[1] with plan = { chain.[1].plan with title = "EVIL" } }
]
let tOk, tReason = verifyAmendmentChain tampered kidCache
check "v11 amend: tampered title rejected" (not tOk)
check "v11 amend: tamper reason payload_mismatch" (tReason = "link_1_payload_mismatch")
check "v11 amend: empty chain invalid" (not (fst (verifyAmendmentChain [] kidCache)))
check "v11 amend: unknown key rejected" (not (fst (verifyAmendmentChain chain emptyCache)))

// ---- 4. register entries + reducers ----

let content1 = Dictionary<string, obj>()
content1.["text"] <- box "Status?"
content1.["urgency"] <- box "high"
let entry1 = {
    entryId = "QST-N1-1"; sessionId = "VEC-SESSION"; nodeId = "N1"; seq = 1
    entryType = "question"; content = content1
    timestamp = "2040-02-01T11:00:00.000Z"; entrySig = ENTRY1_SIG
}
let content2 = Dictionary<string, obj>()
content2.["qid"] <- box "QST-N1-1"
content2.["response"] <- box "Nominal"
content2.["version"] <- box 2
let entry2 = {
    entryId = "QST-N0-1"; sessionId = "VEC-SESSION"; nodeId = "N0"; seq = 1
    entryType = "question_response"; content = content2
    timestamp = "2040-02-01T11:05:00.000Z"; entrySig = ENTRY2_SIG
}
let nodeCache = dict [ "N0", nik; "N1", nik ]

check "v11 registers: entry 1 signature valid" (fst (verifyRegisterEntry entry1 nodeCache))
check "v11 registers: entry 2 signature valid" (fst (verifyRegisterEntry entry2 nodeCache))
check "v11 registers: tampered entry rejected"
    (not (fst (verifyRegisterEntry { entry1 with seq = 9 } nodeCache)))
check "v11 registers: unknown node key rejected"
    (not (fst (verifyRegisterEntry entry1 emptyCache)))

let ordered = orderEntries [ entry2; entry1; entry1 ]
check "v11 registers: dedup + (timestamp,nodeId,seq) order"
    (ordered.Length = 2 && ordered.[0].entryId = "QST-N1-1")

let questions, superseded = reduceQuestions [ entry2; entry1 ]
check "v11 registers: reduceQuestions single question" (questions.Count = 1)
match questions.TryFind "QST-N1-1" with
| Some q ->
    check "v11 registers: question state matches expectedQuestionState"
        (q.qid = "QST-N1-1" && q.text = "Status?" && q.submitter = "N1" &&
         q.urgency = Some "high" && q.status = "ANSWERED" && q.version = 2 &&
         q.response = Some "Nominal" && q.responder = Some "N0")
| None -> check "v11 registers: question state matches expectedQuestionState" false
check "v11 registers: nothing superseded" superseded.IsEmpty

check "v11 registers: entriesRoot Merkle root matches" (entriesRoot ordered = EXPECTED_ENTRIES_ROOT)

// action reducer sanity (no golden vector — semantics per §10.2)
let actContent1 = Dictionary<string, obj>()
actContent1.["description"] <- box "Fix antenna"
let act1 = {
    entryId = "ACT-N1-2"; sessionId = "VEC-SESSION"; nodeId = "N1"; seq = 2
    entryType = "action"; content = actContent1
    timestamp = "2040-02-01T11:10:00.000Z"; entrySig = "x"
}
let actContent2 = Dictionary<string, obj>()
actContent2.["aid"] <- box "ACT-N1-2"
actContent2.["status"] <- box "ACCEPTED"
actContent2.["version"] <- box 2
let act2 = {
    entryId = "ACT-N0-2"; sessionId = "VEC-SESSION"; nodeId = "N0"; seq = 2
    entryType = "action_update"; content = actContent2
    timestamp = "2040-02-01T11:11:00.000Z"; entrySig = "x"
}
let actions, _ = reduceActions [ act2; act1 ]
match actions.TryFind "ACT-N1-2" with
| Some a -> check "v11 registers: reduceActions applies update" (a.status = "ACCEPTED" && a.version = 2)
| None -> check "v11 registers: reduceActions applies update" false

// ---- 5. CBOR + COSE_Sign1 ----

let coseBytes = b64uDecode COSE_SIGN1_CBOR_B64
match decodeCbor coseBytes with
| CTag (18L, CArray arr) -> check "v11 cose: decodes to tag 18 array of 4" (arr.Length = 4)
| _ -> check "v11 cose: decodes to tag 18 array of 4" false

check "v11 cose: COSE_Sign1 verifies against plan + key"
    (fst (verifyPlanCose (Some planV2) COSE_SIGN1_CBOR_B64 kidCache))
check "v11 cose: mismatched plan rejected"
    (not (fst (verifyPlanCose (Some { planV2 with title = "EVIL" }) COSE_SIGN1_CBOR_B64 kidCache)))
check "v11 cose: unknown kid rejected"
    (not (fst (verifyPlanCose (Some planV2) COSE_SIGN1_CBOR_B64 emptyCache)))
let truncatedB64 = b64uEncode (coseBytes.[.. coseBytes.Length - 2])
check "v11 cose: truncated CBOR rejected"
    (not (fst (verifyPlanCose (Some planV2) truncatedB64 kidCache)))
let floatRejected =
    try decodeCbor [| 0xf9uy; 0x3cuy; 0x00uy |] |> ignore; false with CborError _ -> true
check "v11 cbor: floats rejected" floatRejected
let trailingRejected =
    try decodeCbor [| 0x01uy; 0x02uy |] |> ignore; false with CborError _ -> true
check "v11 cbor: trailing bytes rejected" trailingRejected
check "v11 cbor: uint decode" (decodeCbor [| 0x18uy; 0x2auy |] = CInt 42L)
check "v11 cbor: negative int decode" (decodeCbor [| 0x20uy |] = CInt -1L)

// ---- 2. session state machine (golden transition table) ----

let ctx0 = createSession planV2 EXPECTED_PLAN_ID_V2 (Count 1)
check "v11 session: starts DRAFT" (ctx0.state = "DRAFT" && ctx0.lock = None)
check "v11 session: lock timeout 2x900s" (ctx0.lockTimeoutMs = 1800000L)
check "v11 session: quorum threshold 1" (ctx0.quorumThreshold = 1)

let steps : (SessionEventV11 * string * string option) list = [
    StartLock 1000L, "LOCKING", None
    PlanConfirm (2000L, "N2", EXPECTED_PLAN_ID_V2), "LOCKING", None
    Tick 1800999L, "LOCKING", None
    Tick 1801000L, "DEGRADED", Some "QUORUM"
    PlanConfirm (4000000L, "N1", EXPECTED_PLAN_ID_V2), "LOCKED", Some "FULL"
    SessionStart 4100000L, "ACTIVE", Some "FULL"
    DelayMeasured (4200000L, "N1", 1201L), "DEGRADED", Some "FULL"
    HostDecision (4300000L, "continue"), "ACTIVE", Some "FULL"
    SessionEnd 5000000L, "COMPLETE", Some "FULL"
]

let mutable ctx = ctx0
let mutable quorumSubset : string list option = None
steps |> List.iteri (fun i (ev, expState, expLock) ->
    ctx <- transition ctx ev
    if ctx.lock = Some "QUORUM" && quorumSubset.IsNone then quorumSubset <- ctx.subset
    check (sprintf "v11 session step %d: state %s" i expState) (ctx.state = expState)
    check (sprintf "v11 session step %d: lock %A" i expLock) (ctx.lock = expLock))
check "v11 session: quorum subset [N0,N2] (ascending delay)" (quorumSubset = Some [ "N0"; "N2" ])
check "v11 session: subset cleared on full-lock recovery" (ctx.subset = None)

// extra machine coverage: abort / emergency hold / amendments
let ctxAll = createSession planV2 EXPECTED_PLAN_ID_V2 All
check "v11 session: quorum 'all' = 2 participants" (ctxAll.quorumThreshold = 2)
let ctxAborted = transition (transition ctxAll (StartLock 0L)) (HostDecision (1L, "abort"))
check "v11 session: host abort" (ctxAborted.state = "ABORTED")

let ctxMaj = createSession planV2 EXPECTED_PLAN_ID_V2 Majority
check "v11 session: majority of 2 = 2" (ctxMaj.quorumThreshold = 2)
let mutable c3 = transition ctxMaj (StartLock 0L)
c3 <- transition c3 (PlanConfirm (1L, "N1", EXPECTED_PLAN_ID_V2))
c3 <- transition c3 (PlanConfirm (2L, "N2", EXPECTED_PLAN_ID_V2))
check "v11 session: full lock on all confirms" (c3.state = "LOCKED" && c3.lock = Some "FULL")
c3 <- transition c3 (SessionStart 3L)
c3 <- transition c3 (EokOverride (4L, true))
check "v11 session: verified EOK override holds" (c3.state = "EMERGENCY_HOLD")
c3 <- transition c3 (HostDecision (5L, "resume"))
check "v11 session: resume returns to prior state" (c3.state = "ACTIVE")
c3 <- transition c3 (AmendmentProposed (6L, "LTX-AMENDED", 2, [ "N1" ]))
check "v11 session: amendment pending" c3.pendingAmendment.IsSome
c3 <- transition c3 (AmendmentConfirmed (7L, "N1", "LTX-AMENDED"))
check "v11 session: amendment applied after all confirms"
    (c3.planId = "LTX-AMENDED" && c3.planVersion = 2 && c3.pendingAmendment.IsNone)

let mutable c4 = transition (createSession planV2 EXPECTED_PLAN_ID_V2 All) (StartLock 0L)
c4 <- transition c4 (PlanConfirm (1L, "N1", "LTX-WRONG"))
check "v11 session: planId mismatch flagged (S5.5)"
    (c4.state = "LOCKING" && List.contains "N1" c4.mismatched)

// ---- version ----

check "v11 VERSION is 1.1.0" (VERSION = "1.1.0")

printfn "\n%d passed  %d failed" passed failed
if failed > 0 then exit 1
