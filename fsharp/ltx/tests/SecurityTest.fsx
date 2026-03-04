#!/usr/bin/env dotnet-script
// SecurityTest.fsx --- Epic 29, Stories 29.1 / 29.4 / 29.5
// Run with: dotnet fsi tests/SecurityTest.fsx

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
