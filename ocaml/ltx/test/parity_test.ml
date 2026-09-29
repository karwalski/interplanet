(* parity_test.ml -- LTX parity with the JS reference SDK (issue #27).
   Mirrors javascript/ltx/tests/run.js: golden planId vectors, validatePlan +
   reserved fields, reduceDecisions, buildDelayMatrix via pairDelay. *)

open Security
open V11

let passed = ref 0
let failed = ref 0

let check msg cond =
  if cond then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s\n" msg
  end

let read_file path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  s

let get v k = match obj_get v k with Some x -> x | None -> failwith ("missing " ^ k)
let codes (r : Validate.validation) = List.map (fun (e : Validate.plan_error) -> e.code) r.errors
let has_code c r = List.mem c (codes r)

let throws_code f =
  try ignore (f ()); None
  with Validate.Reserved_field_error { code; _ } -> Some code

let () =
  (* ---- Conformance: golden planId vectors (spec/golden/plan-ids.json) ---- *)
  let path =
    match List.find_opt Sys.file_exists
            [ "../../spec/golden/plan-ids.json"; "../../../spec/golden/plan-ids.json" ] with
    | Some p -> p
    | None -> failwith "spec/golden/plan-ids.json not found"
  in
  let golden = parse_json (read_file path) in
  let vectors = get_list golden "vectors" in
  check "golden vectors present" (List.length vectors >= 9);
  List.iter
    (fun gv ->
      let name = get_str gv "name" in
      let plan = get gv "plan" in
      let got = make_plan_id plan in
      check (Printf.sprintf "golden planId %s (got %s)" name got) (got = get_str gv "planId");
      match obj_get gv "planHash" with
      | Some (JStr h) -> check ("golden planHash " ^ name) (plan_hash plan = h)
      | _ -> ())
    vectors;
  let by_name n = List.find (fun gv -> get_str gv "name" = n) vectors in
  let pid n = get_str (by_name n) "planId" in
  let plan_of n = get (by_name n) "plan" in
  check "golden v2 freeze anchor" (pid "v2-freeze-check" = "LTX-20260801-EARTHHQ-MARS-v2-d132e85d");
  check "golden v2 unicode anchor" (pid "v2-unicode-title" = "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8");
  check "golden v2 order-sensitive" (pid "v2-createPlan-default" <> pid "v2-key-order-sensitive");
  check "golden v3 order-insensitive" (pid "v3-upgrade-delays" = pid "v3-key-order-insensitive");
  check "golden v3 amendment chain hash"
    (get_str (plan_of "v3-amendment") "prevPlanHash" = get_str (by_name "v3-upgrade-delays") "planHash");
  check "create_plan default quantum is 5"
    ((Interplanet_ltx.create_plan ()).Models.quantum = 5 && Interplanet_ltx.default_quantum = 5);
  check "json_stringify round-trips golden v2-relay"
    (make_plan_id (parse_json (json_stringify (plan_of "v2-relay"))) = pid "v2-relay");
  check "parse_json decodes a surrogate pair"
    (parse_json "\"\\ud83d\\ude80\"" = JStr "\xf0\x9f\x9a\x80");
  check "canonical_json escapes control characters"
    (canonical_json (JStr "a\bb\012c\001") = "\"a\\bb\\fc\\u0001\"");
  (* struct planId host/node strings drop whitespace like JS (was EARTH_HQ) *)
  (* The struct model serialises nodes before segments, so its default plan
     matches the v2-key-order-sensitive vector, not v2-createPlan-default. *)
  let sp = Interplanet_ltx.make_plan_id
      (Interplanet_ltx.create_plan ~title:"Golden Default" ~start:"2026-03-15T14:00:00.000Z"
         ~delay:840 ()) in
  check ("struct planId = golden v2-key-order-sensitive (got " ^ sp ^ ")")
    (sp = pid "v2-key-order-sensitive");

  (* ---- Plan validation: reserved streams / branching (§3.5, §7) ---- *)
  List.iter
    (fun gv ->
      check ("validate_plan accepts golden " ^ get_str gv "name")
        (Validate.validate_plan (get gv "plan")).valid)
    vectors;
  let vp_base = plan_of "v3-upgrade-delays" in
  let vp_v2 = plan_of "v2-freeze-check" in
  let v = Validate.validate_plan in
  check "validate_plan v3 empty streams ok" (v (obj_set vp_base "streams" (JArr []))).valid;
  let vs = v (obj_set vp_base "streams" (JArr [ JObj [ ("id", JStr "S1") ] ])) in
  check "validate_plan non-empty streams" ((not vs.valid) && has_code "reserved_streams" vs);
  check "validate_plan streams error path"
    ((List.find (fun (e : Validate.plan_error) -> e.code = "reserved_streams") vs.errors).path = "streams");
  check "validate_plan streams non-array" (has_code "reserved_streams" (v (obj_set vp_base "streams" (JStr "S1"))));
  check "validate_plan segment stream"
    (has_code "reserved_streams"
       (v (obj_set vp_base "segments"
             (JArr [ JObj [ ("type", JStr "TX"); ("q", JInt 1); ("stream", JStr "S1") ] ]))));
  check "validate_plan branches" (has_code "reserved_branching" (v (obj_set vp_base "branches" (JArr []))));
  check "validate_plan branching"
    (has_code "reserved_branching" (v (obj_set vp_base "branching" (JObj [ ("mode", JStr "local") ]))));
  let vb = v (obj_set vp_base "segments"
                (JArr [ JObj [ ("type", JStr "CAUCUS"); ("q", JInt 1); ("branch", JStr "B1") ] ])) in
  check "validate_plan segment branch"
    (has_code "reserved_branching" vb && (List.hd vb.errors).path = "segments[0].branch");
  check "validate_plan v2 streams is v3 field" (has_code "v3_field_in_v2" (v (obj_set vp_v2 "streams" (JArr []))));
  check "validate_plan v2 branching" (has_code "reserved_branching" (v (obj_set vp_v2 "branching" (JBool true))));
  check "validate_plan non-object" (has_code "not_an_object" (v JNull));
  check "validate_plan bad version" (has_code "invalid_version" (v (obj_set vp_v2 "v" (JInt 7))));
  check "validate_plan host not first"
    (has_code "invalid_host" (v (obj_set vp_v2 "nodes" (JArr (List.rev (get_list vp_v2 "nodes"))))));
  check "validate_plan unsorted delays key"
    (has_code "invalid_delays" (v (obj_set vp_base "delays" (JObj [ ("N1|N0", JInt 860) ]))));
  check "validate_plan unknown speaker"
    (has_code "unknown_speaker"
       (v (obj_set vp_v2 "segments"
             (JArr [ JObj [ ("type", JStr "TX"); ("q", JInt 1); ("speaker", JStr "N9") ] ]))));
  check "validate_plan quantum out of range" (has_code "invalid_quantum" (v (obj_set vp_v2 "quantum" (JInt 0))));
  let without k = function JObj kvs -> JObj (List.remove_assoc k kvs) | x -> x in
  check "validate_plan missing title" (has_code "missing_field" (v (without "title" vp_v2)));
  check "validate_plan bad mode" (has_code "invalid_mode" (v (obj_set vp_v2 "mode" (JStr "CHAT"))));
  let nodes2 = get_list vp_v2 "nodes" in
  check "validate_plan duplicate node id"
    (has_code "duplicate_node_id" (v (obj_set vp_v2 "nodes" (JArr (nodes2 @ [ List.nth nodes2 1 ])))));
  check "validate_plan bad prevPlanHash" (has_code "invalid_field" (v (obj_set vp_base "prevPlanHash" (JStr "ABC"))));

  (* Enforcement paths raise with a code *)
  check "upgrade_plan_to_v3 rejects streams"
    (throws_code (fun () ->
         upgrade_plan_to_v3 ~extras:[ ("streams", JArr [ JObj [ ("id", JStr "S1") ] ]) ] vp_v2)
     = Some "reserved_streams");
  check "upgrade_plan_to_v3 allows empty"
    (throws_code (fun () -> upgrade_plan_to_v3 ~extras:[ ("streams", JArr []) ] vp_v2) = None);
  check "upgrade_plan_to_v3 rejects branches"
    (throws_code (fun () -> upgrade_plan_to_v3 ~extras:[ ("branches", JArr []) ] vp_v2)
     = Some "reserved_branching");
  check "create_session rejects streams"
    (throws_code (fun () -> create_session (obj_set vp_base "streams" (JArr [ JInt 1 ])) "id")
     = Some "reserved_streams");
  check "create_session accepts golden" (throws_code (fun () -> create_session vp_base "id") = None);
  let up3 = upgrade_plan_to_v3 ~extras:[ ("delays", JObj [ ("N0|N1", JInt 900) ]) ] vp_v2 in
  check "upgrade_plan_to_v3 result"
    (get_int up3 "v" = 3 && get_int up3 "planVersion" = 1 && pair_delay up3 "N0" "N1" = 900);

  (* ---- Decision register (§10.3) ---- *)
  let host = generate_nik ~node_label:"HOST" () and mars = generate_nik ~node_label:"MARS" () in
  let cache = [ ("N0", host); ("N1", mars) ] in
  let mk entry_type content node_id seq ts (k : nik) =
    create_register_entry ~entry_type ~content ~session_id:"LTX-DEC-TEST" ~node_id ~seq
      ~timestamp:ts ~seed:k.priv_raw
  in
  let o kvs = JObj kvs in
  let dec1 = mk "decision" (o [ ("text", JStr "Proceed with EVA-3"); ("rationale", JStr "Weather window");
                                ("originWindow", JStr "W2") ]) "N0" 1 "2026-08-01T12:00:00.000Z" host in
  check "decision id prefix DEC" (get_str dec1 "entryId" = "DEC-N0-1");
  check "decision entry verifies" (fst (verify_register_entry dec1 cache));
  let (reg1, _) = reduce_decisions [ dec1 ] in
  let d1 = List.assoc "DEC-N0-1" reg1 in
  check "decision RECORDED" (d1.d_status = "RECORDED" && d1.d_version = 1);
  check "decision fields"
    (d1.d_text = "Proceed with EVA-3" && d1.d_recorded_by = "N0" && d1.d_rationale = Some "Weather window");
  let dec_rev = mk "decision_update" (o [ ("did", JStr "DEC-N0-1"); ("text", JStr "Proceed with EVA-3 at 14:00");
                                          ("version", JInt 2) ]) "N1" 1 "2026-08-01T12:10:00.000Z" mars in
  let dec_res = mk "decision_update" (o [ ("did", JStr "DEC-N0-1"); ("status", JStr "RESCINDED");
                                          ("version", JInt 3) ]) "N0" 2 "2026-08-01T12:20:00.000Z" host in
  check "decision_update id prefix DEC" (get_str dec_rev "entryId" = "DEC-N1-1");
  let (reg2, sup2) = reduce_decisions [ dec_res; dec1; dec_rev ] in
  let d2 = List.assoc "DEC-N0-1" reg2 in
  check "decision update applied" (d2.d_text = "Proceed with EVA-3 at 14:00");
  check "decision RESCINDED v3" (d2.d_status = "RESCINDED" && d2.d_version = 3);
  check "decision editor recorded" (d2.d_editor = Some "N0");
  check "decision older update superseded" (List.mem (get_str dec_rev "entryId") sup2);
  let dec_a = mk "decision_update" (o [ ("did", JStr "DEC-N0-1"); ("text", JStr "From N0"); ("version", JInt 5) ])
      "N0" 7 "2026-08-01T13:00:00.000Z" host in
  let dec_b = mk "decision_update" (o [ ("did", JStr "DEC-N0-1"); ("text", JStr "From N1"); ("version", JInt 5) ])
      "N1" 7 "2026-08-01T13:00:00.000Z" mars in
  let conf1 = reduce_decisions [ dec1; dec_b; dec_a ] and conf2 = reduce_decisions [ dec_a; dec1; dec_b ] in
  check "decision tie lowest nodeId wins" ((List.assoc "DEC-N0-1" (fst conf1)).d_text = "From N0");
  check "decision tie loser superseded"
    (List.mem (get_str dec_b "entryId") (snd conf1) && not (List.mem (get_str dec_a "entryId") (snd conf1)));
  check "decision reduce order-independent" (conf1 = conf2);
  let dec_hi = mk "decision_update" (o [ ("did", JStr "DEC-N0-1"); ("text", JStr "N1 v6"); ("version", JInt 6) ])
      "N1" 8 "2026-08-01T12:30:00.000Z" mars in
  check "decision higher version wins"
    ((List.assoc "DEC-N0-1" (fst (reduce_decisions [ dec1; dec_a; dec_hi ]))).d_text = "N1 v6");
  let dec_orphan = mk "decision_update" (o [ ("did", JStr "DEC-NOPE-1"); ("version", JInt 2) ])
      "N1" 9 "2026-08-01T12:40:00.000Z" mars in
  let dec_dup = obj_set (mk "decision" (o [ ("text", JStr "dup") ]) "N1" 10 "2026-08-01T12:50:00.000Z" mars)
      "entryId" (JStr "DEC-N0-1") in
  let (reg3, sup3) = reduce_decisions [ dec1; dec_orphan; dec_dup ] in
  check "decision orphan update superseded" (List.mem "DEC-N1-9" sup3);
  check "decision duplicate create ignored"
    (let d = List.assoc "DEC-N0-1" reg3 in d.d_text = "Proceed with EVA-3" && d.d_recorded_by = "N0");
  check "decision reducer ignores others"
    (List.length (fst (reduce_decisions [ dec1; dec_rev ])) = 1 && fst (reduce_actions [ dec1 ]) = []);

  (* ---- buildDelayMatrix (§3.7): sum via HOST for non-HOST pairs ---- *)
  let node id name delay loc =
    o [ ("id", JStr id); ("name", JStr name); ("role", JStr (if id = "N0" then "HOST" else "PARTICIPANT"));
        ("delay", JInt delay); ("location", JStr loc) ] in
  let dm_plan = o [
      ("v", JInt 2); ("title", JStr "Delay Matrix"); ("start", JStr "2026-06-01T12:00:00.000Z");
      ("quantum", JInt 5); ("mode", JStr "LTX-ASYNC");
      ("segments", JArr [ o [ ("type", JStr "TX"); ("q", JInt 1) ] ]);
      ("nodes", JArr [ node "N0" "Earth HQ" 0 "earth"; node "N1" "Mars Hab-01" 1240 "mars";
                       node "N2" "Jupiter Obs" 3240 "jupiter"; node "N3" "Earth Annex" 0 "earth" ]) ] in
  let dm = build_delay_matrix dm_plan in
  let dget m a b = (List.find (fun p -> p.dm_from = a && p.dm_to = b) m).dm_delay in
  check "delay matrix n*(n-1) pairs" (List.length dm = 12);
  check "delay matrix HOST to node" (dget dm "N0" "N1" = 1240 && dget dm "N1" "N0" = 1240);
  check "delay matrix non-HOST pair = sum" (dget dm "N1" "N2" = 1240 + 3240);
  check "delay matrix not max" (dget dm "N1" "N2" <> max 1240 3240);
  check "delay matrix symmetric" (List.for_all (fun p -> p.dm_delay = dget dm p.dm_to p.dm_from) dm);
  check "delay matrix zero-delay non-HOST" (dget dm "N3" "N2" = 3240 && dget dm "N3" "N0" = 0);
  check "delay matrix equals pair_delay"
    (List.for_all (fun p -> p.dm_delay = pair_delay dm_plan p.dm_from p.dm_to) dm);
  let dm3 = build_delay_matrix (upgrade_plan_to_v3 ~extras:[ ("delays", o [ ("N1|N2", JInt 2900) ]) ] dm_plan) in
  check "delay matrix v3 entry authoritative" (dget dm3 "N1" "N2" = 2900 && dget dm3 "N2" "N1" = 2900);
  check "delay matrix v3 fallback sum" (dget dm3 "N1" "N3" = 1240);
  (* The struct-model matrix in Interplanet_ltx uses the same rule. *)
  let sp_plan = Interplanet_ltx.create_plan
      ~nodes:[ { Models.id = "N0"; name = "Earth HQ"; role = "HOST"; delay = 0; location = "earth" };
               { Models.id = "N1"; name = "Mars Hab-01"; role = "PARTICIPANT"; delay = 1240; location = "mars" };
               { Models.id = "N2"; name = "Jupiter Obs"; role = "PARTICIPANT"; delay = 3240; location = "jupiter" };
               { Models.id = "N3"; name = "Earth Annex"; role = "PARTICIPANT"; delay = 0; location = "earth" } ]
      () in
  let sdm = Interplanet_ltx.build_delay_matrix sp_plan in
  check "struct delay matrix matches json matrix"
    (List.for_all
       (fun (e : Models.delay_matrix_entry) -> e.delay_seconds = dget dm e.from_id e.to_id)
       sdm && List.length sdm = 12);

  Printf.printf "\n%d passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
