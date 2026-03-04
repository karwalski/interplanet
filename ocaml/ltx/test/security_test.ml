(* security_test.ml -- Epic 29, Stories 29.1 / 29.4 / 29.5 *)

let passed = ref 0
let failed = ref 0

let check msg cond =
  if cond then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s\n" msg
  end

let check_eq msg a b =
  if a = b then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s  expected=%s  got=%s\n" msg b a
  end

let () =
  (* ---- canonical_json ---- *)
  let open Security in
  check_eq "empty object" (canonical_json (JObj [])) "{}";
  check_eq "sorted keys" (canonical_json (JObj [("z",JInt 1);("a",JInt 2)])) "{\"a\":2,\"z\":1}";
  check_eq "array" (canonical_json (JArr [JInt 1;JInt 2;JInt 3])) "[1,2,3]";
  check_eq "number" (canonical_json (JInt 42)) "42";
  check_eq "bool true" (canonical_json (JBool true)) "true";
  check_eq "string" (canonical_json (JStr "hi")) "\"hi\"";
  check_eq "null" (canonical_json JNull) "null";
  check_eq "nested" (canonical_json (JObj [("b",JObj [("y",JInt 9);("x",JInt 1)]);("a",JInt 3)]))
    "{\"a\":3,\"b\":{\"x\":1,\"y\":9}}";

  (* ---- generate_nik ---- *)
  let nik  = generate_nik () in
  let nik2 = generate_nik () in
  check "key_type" (nik.key_type = "ltx-nik-v1");
  check "node_id non-empty" (String.length nik.node_id > 0);
  check "kid non-empty" (String.length nik.kid > 0);
  check "node_id is 22 chars" (String.length nik.node_id = 22);
  check "pub_key non-empty" (String.length nik.public_key_b64 > 0);
  check "priv_key non-empty" (String.length nik.private_key_b64 > 0);
  check "issued_at set" (String.length nik.issued_at > 0);
  check "expires_at set" (String.length nik.expires_at > 0);
  let nik_lbl = generate_nik ~valid_days:30 ~node_label:"TestNode" () in
  check_eq "node_label" nik_lbl.node_label "TestNode";
  check "expires after issued" (nik_lbl.expires_at > nik_lbl.issued_at);
  check "unique node_ids" (nik.node_id <> nik2.node_id);

  (* ---- is_nik_expired ---- *)
  check "fresh nik not expired" (not (is_nik_expired nik));
  let old_nik = { nik with expires_at = "2000-01-01T00:00:00Z" } in
  check "old nik expired" (is_nik_expired old_nik);

  (* ---- sign_plan / verify_plan ---- *)
  let plan = JObj [
    ("planId", JStr "p1");
    ("startAt", JStr "2026-05-01T00:00:00Z");
    ("quantum", JInt 60)] in
  let sp = sign_plan plan nik.private_key_b64 ~kid:nik.kid () in
  check "coseSign1 protected" (String.length sp.cose_sign1.protected_hdr > 0);
  check "coseSign1 signature" (String.length sp.cose_sign1.signature > 0);
  check_eq "kid in unprotected" sp.cose_sign1.kid nik.kid;

  let cache = [(nik.kid, nik)] in
  let (ok1, r1) = verify_plan sp cache in
  check "verify ok" ok1;
  check_eq "verify reason ok" r1 "ok";

  let (ok2, r2) = verify_plan sp [] in
  check "verify fails empty cache" (not ok2);
  check_eq "reason key_not_in_cache" r2 "key_not_in_cache";

  let expired_cache = [(nik.kid, { nik with expires_at = "2000-01-01T00:00:00Z" })] in
  let (ok3, r3) = verify_plan sp expired_cache in
  check "verify fails expired key" (not ok3);
  check_eq "reason key_expired" r3 "key_expired";

  let tampered = { sp with plan = JObj [("planId", JStr "TAMPERED")] } in
  let (ok4, r4) = verify_plan tampered cache in
  check "verify fails tampered" (not ok4);
  check_eq "reason payload_mismatch" r4 "payload_mismatch";

  (* ---- SequenceTracker ---- *)
  let st = new_sequence_tracker "plan-x" in
  check_eq "plan_id stored" st.plan_id "plan-x";

  let (r1a, m1a) = add_seq st "alice" 1 in
  check "first seq accepted" r1a;
  check_eq "first seq msg" m1a "ok";

  let (r2a, m2a) = add_seq st "alice" 2 in
  check "seq 2 accepted" r2a;
  check_eq "seq 2 msg" m2a "ok";

  let (r3a, m3a) = add_seq st "alice" 2 in
  check "replay rejected" (not r3a);
  check_eq "replay msg" m3a "replay";

  let (r4a, m4a) = add_seq st "alice" 10 in
  check "gap accepted" r4a;
  check_eq "gap msg" m4a "gap";

  let (c1, _) = check_seq st "alice" 10 in
  check "check_seq replay" (not c1);
  let (c2, _) = check_seq st "alice" 11 in
  check "check_seq next" c2;
  let (c3, mc) = check_seq st "alice" 20 in
  check "check_seq gap" c3;
  check_eq "check_seq gap msg" mc "gap";

  let (rb, mb) = add_seq st "bob" 5 in
  check "bob first seq" rb;
  check_eq "bob first msg" mb "ok";

  Printf.printf "\n%d passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
