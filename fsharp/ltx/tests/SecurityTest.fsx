#!/usr/bin/env dotnet-script
// SecurityTest.fsx --- Epic 29, Stories 29.1 / 29.4 / 29.5
// Run with: dotnet fsi tests/SecurityTest.fsx

#r "nuget: NSec.Cryptography, 24.4.0"
#load "../src/Security.fs"

open InterplanetLtx.Security
open System.Collections.Generic

let mutable passed = 0
let mutable failed = 0

let check label cond =
    if cond then passed <- passed + 1
    else failed <- failed + 1; printfn "FAIL: %s" label

let checkEq label (got: 'a) (exp: 'a) =
    if got = exp then passed <- passed + 1
    else failed <- failed + 1; printfn "FAIL: %s  expected=%A  got=%A" label exp got

// ---- canonical_json ----
checkEq "empty object" (canonicalJson (dict [] :> IDictionary<string,obj>)) "{}"
checkEq "sorted keys" (canonicalJson (dict [("z",1:>obj);("a",2:>obj)] :> IDictionary<string,obj>)) "{\"a\":2,\"z\":1}"
checkEq "array" (canonicalJson [| 1:>obj; 2:>obj; 3:>obj |]) "[1,2,3]"
checkEq "number" (canonicalJson 42) "42"
checkEq "bool" (canonicalJson true) "true"
checkEq "string" (canonicalJson "hi") "\"hi\""
checkEq "null" (canonicalJson null) "null"
let nested = canonicalJson (dict [("b",dict [("y",9:>obj);("x",1:>obj)]:>obj);("a",3:>obj)] :> IDictionary<string,obj>)
checkEq "nested sorted" nested "{\"a\":3,\"b\":{\"x\":1,\"y\":9}}"

// ---- generate_nik ----
let nik1 = generateNik 365 ""
let nik2 = generateNik 365 ""
checkEq "key_type" nik1.KeyType "ltx-nik-v1"
check "node_id non-empty" (nik1.NodeId.Length > 0)
check "kid non-empty" (nik1.Kid.Length > 0)
checkEq "node_id 22 chars" nik1.NodeId.Length 22
check "pub_key non-empty" (nik1.PublicKeyB64.Length > 0)
check "priv_key non-empty" (nik1.PrivateKeyB64.Length > 0)
check "issued_at set" (nik1.IssuedAt.Length > 0)
check "expires_at set" (nik1.ExpiresAt.Length > 0)
let nikLbl = generateNik 30 "TestNode"
checkEq "node_label" nikLbl.NodeLabel "TestNode"
check "expires after issued" (nikLbl.ExpiresAt > nikLbl.IssuedAt)
check "unique node_ids" (nik1.NodeId <> nik2.NodeId)

// ---- is_nik_expired ----
check "fresh nik not expired" (not (isNikExpired nik1))
let oldNik = { nik1 with ExpiresAt = "2000-01-01T00:00:00Z" }
check "old nik expired" (isNikExpired oldNik)

// ---- sign_plan / verify_plan ----
let plan = dict [("planId","p1":>obj);("startAt","2026-05-01T00:00:00Z":>obj);("quantum",60:>obj)] :> IDictionary<string,obj>
let sp   = signPlan plan nik1
check "coseSign1 protected" (sp.CoseSign1.ProtectedHdr.Length > 0)
check "coseSign1 signature" (sp.CoseSign1.Signature.Length > 0)
checkEq "kid in unprotected" sp.CoseSign1.Kid nik1.Kid

let cache = Dictionary<string,Nik>()
cache.[nik1.Kid] <- nik1
let (ok1, r1) = verifyPlan sp cache
check "verify ok" ok1
checkEq "verify reason" r1 "ok"

let (ok2, r2) = verifyPlan sp (Dictionary<string,Nik>())
check "verify fails empty cache" (not ok2)
checkEq "reason key_not_in_cache" r2 "key_not_in_cache"

let expiredCache = Dictionary<string,Nik>()
expiredCache.[nik1.Kid] <- oldNik
let (ok3, r3) = verifyPlan sp expiredCache
check "verify fails expired key" (not ok3)
checkEq "reason key_expired" r3 "key_expired"

let tamperedPlan = dict [("planId","TAMPERED":>obj)] :> IDictionary<string,obj>
let tampered = { sp with Plan = tamperedPlan }
let (ok4, r4) = verifyPlan tampered cache
check "verify fails tampered" (not ok4)
checkEq "reason payload_mismatch" r4 "payload_mismatch"

// Wrong public key under the right kid must fail (real crypto — the old
// SHA-256 stub verified without ever touching the key).
let wrongKeyCache = Dictionary<string,Nik>()
wrongKeyCache.[nik1.Kid] <- { nik2 with Kid = nik1.Kid; NodeId = nik1.NodeId }
let (ok5, r5) = verifyPlan sp wrongKeyCache
check "verify fails wrong key" (not ok5)
checkEq "reason signature_mismatch (wrong key)" r5 "signature_mismatch"

// Corrupted signature must fail.
let flipped =
    let s = sp.CoseSign1.Signature
    (if s.[0] = 'A' then "B" else "A") + s.Substring(1)
let (ok6, r6) = verifyPlan { sp with CoseSign1 = { sp.CoseSign1 with Signature = flipped } } cache
check "verify fails corrupted sig" (not ok6)
checkEq "reason signature_mismatch (corrupt)" r6 "signature_mismatch"

// ---- deterministic Ed25519 interop vector (conformance/vectors.json .v11) ----
// Ed25519 is deterministic: signing the vector plan's canonical JSON with the
// fixed vector seed must byte-equal the golden TRANSITIONAL-envelope signature
// produced by the other ports (.v11.amendmentChain.chain[0].coseSign1).

let VECTOR_SEED       = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
let VECTOR_NODE_ID    = "Vkdap1RjR0wChd9dvyvKtw"
let VECTOR_PUBLIC_KEY = "A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg"
let VECTOR_PROTECTED  = "eyJhbGciOi0xOX0"
let VECTOR_ROOT_PAYLOAD = "eyJtb2RlIjoiTFRYLUFTWU5DIiwibm9kZXMiOlt7ImRlbGF5IjowLCJpZCI6Ik4wIiwibG9jYXRpb24iOiJlYXJ0aCIsIm5hbWUiOiJFYXJ0aCBIUSIsInJvbGUiOiJIT1NUIn0seyJkZWxheSI6OTAwLCJpZCI6Ik4xIiwibG9jYXRpb24iOiJtYXJzIiwibmFtZSI6Ik1hcnMgSGFiIiwicm9sZSI6IlBBUlRJQ0lQQU5UIn0seyJkZWxheSI6MiwiaWQiOiJOMiIsImxvY2F0aW9uIjoibW9vbiIsIm5hbWUiOiJMdW5hIEJhc2UiLCJyb2xlIjoiUEFSVElDSVBBTlQifV0sInF1YW50dW0iOjUsInNlZ21lbnRzIjpbeyJxIjoyLCJ0eXBlIjoiUExBTl9DT05GSVJNIn0seyJsYWJlbCI6Ik9wZW5pbmciLCJxIjozLCJzcGVha2VyIjoiTjAiLCJ0eXBlIjoiVFgifSx7ImxhYmVsIjoiTWFycyBSZXBvcnQiLCJxIjozLCJzcGVha2VyIjoiTjEiLCJ0eXBlIjoiVFgifSx7InEiOjIsInR5cGUiOiJNRVJHRSJ9XSwic3RhcnQiOiIyMDQwLTAyLTAxVDEyOjAwOjAwLjAwMFoiLCJ0aXRsZSI6IlZlY3RvciBTdW1taXQiLCJ2IjoyfQ"
let VECTOR_ROOT_SIG   = "2zHRgtxRFQvcNfj-XPFtqB0qg-Ipbx0CsmxgKK9zWCguMfvVADHdEYQtE1ko5z2fZnxd2MPVrx6FrFsww5hgAw"

let vnik = nikFromSeed VECTOR_SEED 7300 "Vector Node"
checkEq "vector publicKey = raw 32-byte pub b64u" vnik.PublicKeyB64 VECTOR_PUBLIC_KEY
checkEq "vector nodeId = b64u(sha256(pub)[0..15])" vnik.NodeId VECTOR_NODE_ID
checkEq "vector privateKey round-trips seed" vnik.PrivateKeyB64 VECTOR_SEED

let vNode (id: string) (name: string) (role: string) (delay: int) (location: string) : obj =
    dict [ ("id", box id); ("name", box name); ("role", box role)
           ("delay", box delay); ("location", box location) ] |> box

let vectorPlan =
    dict [
        ("v", box 2)
        ("title", box "Vector Summit")
        ("start", box "2040-02-01T12:00:00.000Z")
        ("quantum", box 5)
        ("mode", box "LTX-ASYNC")
        ("nodes", box [|
            vNode "N0" "Earth HQ" "HOST" 0 "earth"
            vNode "N1" "Mars Hab" "PARTICIPANT" 900 "mars"
            vNode "N2" "Luna Base" "PARTICIPANT" 2 "moon" |])
        ("segments", box [|
            box (dict [ ("type", box "PLAN_CONFIRM"); ("q", box 2) ])
            box (dict [ ("type", box "TX"); ("q", box 3); ("speaker", box "N0"); ("label", box "Opening") ])
            box (dict [ ("type", box "TX"); ("q", box 3); ("speaker", box "N1"); ("label", box "Mars Report") ])
            box (dict [ ("type", box "MERGE"); ("q", box 2) ]) |])
    ] :> IDictionary<string,obj>

let vsp = signPlan vectorPlan vnik
checkEq "vector protected header matches golden" vsp.CoseSign1.ProtectedHdr VECTOR_PROTECTED
checkEq "vector kid matches golden nodeId" vsp.CoseSign1.Kid VECTOR_NODE_ID
checkEq "vector payload matches golden canonical JSON" vsp.CoseSign1.Payload VECTOR_ROOT_PAYLOAD
checkEq "vector signature byte-equals golden (deterministic Ed25519)" vsp.CoseSign1.Signature VECTOR_ROOT_SIG

let vCache = Dictionary<string,Nik>()
vCache.[vnik.Kid] <- vnik
let (vOk, vReason) = verifyPlan vsp vCache
check "vector envelope verifies" vOk
checkEq "vector verify reason" vReason "ok"

// ---- SequenceTracker ----
let st = SequenceTracker("plan-x")
checkEq "plan_id stored" st.PlanId "plan-x"

let (r1a, m1a) = st.AddSeq("alice", 1L)
check "first seq accepted" r1a
checkEq "first seq msg" m1a "ok"

let (r2a, m2a) = st.AddSeq("alice", 2L)
check "seq 2 accepted" r2a
checkEq "seq 2 msg" m2a "ok"

let (r3a, m3a) = st.AddSeq("alice", 2L)
check "replay rejected" (not r3a)
checkEq "replay msg" m3a "replay"

let (r4a, m4a) = st.AddSeq("alice", 10L)
check "gap accepted" r4a
checkEq "gap msg" m4a "gap"

let (c1, _) = st.CheckSeq("alice", 10L)
check "check_seq replay" (not c1)
let (c2, _) = st.CheckSeq("alice", 11L)
check "check_seq next" c2
let (c3, mc) = st.CheckSeq("alice", 20L)
check "check_seq gap" c3
checkEq "check_seq gap msg" mc "gap"

let (rb, mb) = st.AddSeq("bob", 5L)
check "bob first seq" rb
checkEq "bob first msg" mb "ok"

printfn "\n%d passed  %d failed" passed failed
if failed > 0 then System.Environment.Exit(1)
