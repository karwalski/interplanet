(* v11_test.ml -- Epic 72, Story 72.5: LTX v1.1 core subset conformance tests.
   Verified against the shared golden vectors: conformance/vectors.json §v11. *)

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

let check_eq msg a b =
  if a = b then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s  expected=%s  got=%s\n" msg b a
  end

let read_file path =
  let ic = open_in_bin path in
  let len = in_channel_length ic in
  let s = really_input_string ic len in
  close_in ic;
  s

let () =
  (* ---- load golden vectors ---- *)
  let candidates = [
    "../../../conformance/vectors.json";      (* from ocaml/ltx *)
    "../../../../conformance/vectors.json";   (* from ocaml/ltx/test *)
  ] in
  let path =
    try List.find Sys.file_exists candidates
    with Not_found -> failwith "conformance/vectors.json not found"
  in
  let root = parse_json (read_file path) in
  let v11 = match obj_get root "v11" with Some v -> v | None -> failwith "no v11" in
  let key = match obj_get v11 "key" with Some v -> v | None -> failwith "no key" in
  let nik_json = match obj_get key "nik" with Some v -> v | None -> failwith "no nik" in
  let seed = b64u_decode (get_str key "privateSeedB64") in
  let node_id = get_str nik_json "nodeId" in
  let pub_raw = b64u_decode (get_str nik_json "publicKey") in

  check "vector seed is 32 bytes" (String.length seed = 32);
  check "Ed25519 pubkey derives from vector seed"
    (Ed25519.pubkey_of_seed seed = pub_raw);
  check "nodeId = b64u(sha256(pub)[0..16))"
    (b64u_encode (String.sub (sha256 pub_raw) 0 16) = node_id);

  let vector_nik : Security.nik = {
    key_type = "ltx-nik-v1";
    node_id;
    kid = node_id;
    issued_at = get_str nik_json "validFrom";
    expires_at = get_str nik_json "validUntil";
    node_label = "";
    public_key_b64 = get_str nik_json "publicKey";
    private_key_b64 = get_str key "privateSeedB64";
    pub_raw;
    priv_raw = seed;
  } in
  let key_cache = [(node_id, vector_nik)] in

  (* ---- 1. v3 planId + v2 FROZEN regression ---- *)
  let pid3 = match obj_get v11 "planIdV3" with Some v -> v | None -> failwith "planIdV3" in
  let plan3 = match obj_get pid3 "plan" with Some v -> v | None -> failwith "plan" in
  check_eq "planIdV3: canonical JSON matches vector"
    (canonical_json plan3) (get_str pid3 "canonicalJson");
  check_eq "planIdV3: SHA-256 matches vector"
    (hex_of_string (sha256 (canonical_json plan3))) (get_str pid3 "sha256");
  check_eq "planIdV3: expected plan id"
    (make_plan_id plan3) (get_str pid3 "expectedPlanId");

  let pid2 = match obj_get v11 "planIdV2Regression" with Some v -> v | None -> failwith "planIdV2" in
  let plan2 = match obj_get pid2 "plan" with Some v -> v | None -> failwith "plan" in
  check_eq "planIdV2 FROZEN regression"
    (make_plan_id plan2) (get_str pid2 "expectedPlanId");

  (* ---- 2. pairDelay ---- *)
  let pd = match obj_get v11 "pairDelay" with Some v -> v | None -> failwith "pairDelay" in
  let pd_plan = match obj_get pd "plan" with Some v -> v | None -> failwith "plan" in
  List.iter
    (fun c ->
      let a = get_str c "a" and b = get_str c "b" in
      let expected = get_int c "expected" in
      check (Printf.sprintf "pairDelay %s|%s = %d" a b expected)
        (pair_delay pd_plan a b = expected))
    (get_list pd "cases");
  let fb = match obj_get pd "fallbackCase" with Some v -> v | None -> failwith "fallback" in
  let fb_plan = match obj_get fb "plan" with Some v -> v | None -> failwith "plan" in
  check (Printf.sprintf "pairDelay fallback = %d" (get_int fb "expected"))
    (pair_delay fb_plan (get_str fb "a") (get_str fb "b") = get_int fb "expected");

  (* ---- 3. compute_segments_for ---- *)
  let segs_n2 = compute_segments_for pd_plan "N2" in
  check "computeSegmentsFor: 4 segments" (List.length segs_n2 = 4);
  let seg1 = List.nth segs_n2 1 in       (* TX speaker N0 viewed by N2 *)
  check "computeSegmentsFor: N0 TX receive for N2" (seg1.vperspective = "receive");
  check "computeSegmentsFor: HOST pair delay 2s" (seg1.varrival_offset_s = 2);
  let seg2 = List.nth segs_n2 2 in       (* TX speaker N1 viewed by N2 *)
  check "computeSegmentsFor: v3 matrix 500s" (seg2.varrival_offset_s = 500);
  let seg_tx = List.nth (compute_segments_for pd_plan "N1") 2 in
  check "computeSegmentsFor: transmit unshifted"
    (seg_tx.vperspective = "transmit" && seg_tx.varrival_offset_s = 0);
  check "computeSegmentsFor: receive shifted by pairDelay ms"
    (seg2.vstart_ms - seg_tx.vstart_ms = 500_000);
  let seg0 = List.nth segs_n2 0 in
  check "computeSegmentsFor: unattributed neutral"
    (seg0.vperspective = "neutral" && seg0.varrival_offset_s = 0);

  (* ---- 4. amendment chain ---- *)
  let am = match obj_get v11 "amendmentChain" with Some v -> v | None -> failwith "amend" in
  let signed_of_json j : Security.signed_plan =
    let plan = match obj_get j "plan" with Some p -> p | None -> JObj [] in
    let cs = match obj_get j "coseSign1" with Some c -> c | None -> JObj [] in
    let unprot = match obj_get cs "unprotected" with Some u -> u | None -> JObj [] in
    { plan;
      cose_sign1 = {
        protected_hdr = get_str cs "protected";
        kid = get_str unprot "kid";
        payload = get_str cs "payload";
        signature = get_str cs "signature";
      } }
  in
  let chain_json = get_list am "chain" in
  let chain = List.map signed_of_json chain_json in
  check_eq "amend: root planHash matches vector"
    (plan_hash (List.hd chain).plan) (get_str am "rootPlanHash");
  let (chain_ok, chain_reason) = verify_amendment_chain chain key_cache in
  check ("amend: chain verifies (" ^ chain_reason ^ ")") chain_ok;

  (* tampering the amended title must break the chain *)
  let tamper_field = get_str am "tamperField" in
  let tampered =
    List.mapi
      (fun i sp ->
        if i = 1 then
          { sp with Security.plan = obj_set sp.Security.plan tamper_field (JStr "TAMPERED") }
        else sp)
      chain
  in
  let (tampered_ok, _) = verify_amendment_chain tampered key_cache in
  check ("amend: tampered " ^ tamper_field ^ " rejected") (not tampered_ok);
  let (empty_ok, empty_reason) = verify_amendment_chain [] key_cache in
  check "amend: empty chain rejected" (not empty_ok && empty_reason = "empty_chain");

  (* ---- 5. register entries + reducers + Merkle root ---- *)
  let re = match obj_get v11 "registerEntries" with Some v -> v | None -> failwith "registers" in
  let entries = get_list re "entries" in
  let reg_cache = [("N0", vector_nik); ("N1", vector_nik); (node_id, vector_nik)] in
  List.iter
    (fun e ->
      let (ok, reason) = verify_register_entry e reg_cache in
      check (Printf.sprintf "registers: entry %s valid (%s)"
               (get_str e "entryId") reason) ok)
    entries;
  let bad = obj_set (List.hd entries) "timestamp" (JStr "2041-01-01T00:00:00.000Z") in
  let (bad_ok, _) = verify_register_entry bad reg_cache in
  check "registers: tampered entry rejected" (not bad_ok);

  let (by_id, superseded) = reduce_questions entries in
  check "registers: nothing superseded" (superseded = []);
  let expected =
    match obj_get re "expectedQuestionState" with Some v -> v | None -> JObj []
  in
  (match obj_get expected "QST-N1-1", List.assoc_opt "QST-N1-1" by_id with
   | Some exp, Some q ->
     check_eq "registers: qid" q.q_qid (get_str exp "qid");
     check_eq "registers: text" q.q_text (get_str exp "text");
     check_eq "registers: submitter" q.q_submitter (get_str exp "submitter");
     check_eq "registers: urgency"
       (match q.q_urgency with Some u -> u | None -> "") (get_str exp "urgency");
     check_eq "registers: status" q.q_status (get_str exp "status");
     check "registers: version" (q.q_version = get_int exp "version");
     check_eq "registers: response"
       (match q.q_response with Some r -> r | None -> "") (get_str exp "response");
     check_eq "registers: responder"
       (match q.q_responder with Some r -> r | None -> "") (get_str exp "responder")
   | _ -> check "registers: expected question present" false);

  (* order invariance *)
  let (by_id_rev, _) = reduce_questions (List.rev entries) in
  check "registers: reduction order-invariant"
    (match List.assoc_opt "QST-N1-1" by_id_rev, List.assoc_opt "QST-N1-1" by_id with
     | Some a, Some b -> a = b
     | _ -> false);

  check_eq "registers: Merkle entriesRoot matches vector"
    (entries_root entries) (get_str re "entriesRoot");

  (* deterministic re-creation of entry 0 from the vector seed *)
  let e0 = List.hd entries in
  let content0 = match obj_get e0 "content" with Some c -> c | None -> JObj [] in
  let recreated =
    create_register_entry ~entry_type:"question" ~content:content0
      ~session_id:(get_str e0 "sessionId") ~node_id:(get_str e0 "nodeId")
      ~seq:(get_int e0 "seq") ~timestamp:(get_str e0 "timestamp") ~seed
  in
  check_eq "registers: created entry reproduces vector"
    (canonical_json recreated) (canonical_json e0);

  (* ---- 6. CBOR decode + COSE_Sign1 verify ---- *)
  let cs = match obj_get v11 "coseSign1" with Some v -> v | None -> failwith "cose" in
  let cose_plan = match obj_get cs "plan" with Some p -> p | None -> JObj [] in
  let cose_b64 = get_str cs "coseSign1CborB64" in

  let (cose_ok, cose_reason) = verify_plan_cose ~plan:cose_plan cose_b64 key_cache in
  check ("cose: envelope verifies (" ^ cose_reason ^ ")") cose_ok;
  let tampered_plan = obj_set cose_plan "title" (JStr "TAMPERED") in
  let (t_ok, t_reason) = verify_plan_cose ~plan:tampered_plan cose_b64 key_cache in
  check "cose: tampered plan -> payload_mismatch"
    (not t_ok && t_reason = "payload_mismatch");
  let (nc_ok, nc_reason) = verify_plan_cose ~plan:cose_plan cose_b64 [] in
  check "cose: empty cache -> key_not_in_cache"
    (not nc_ok && nc_reason = "key_not_in_cache");

  (* decoder structure checks *)
  (match cbor_decode (b64u_decode cose_b64) with
   | CTag (18, CArr [CBytes prot; CMap unprot; CBytes payload; CBytes sg]) ->
     check "cbor: protected header {1: -19}"
       (cbor_decode prot = CMap [(CInt 1, CInt (-19))]);
     (match List.assoc_opt (CInt 4) unprot with
      | Some (CBytes kid) ->
        check "cbor: kid is 16 bytes" (String.length kid = 16);
        check_eq "cbor: kid matches NIK nodeId" (b64u_encode kid) node_id
      | _ -> check "cbor: kid present" false);
     check_eq "cbor: payload is canonical plan JSON" payload (canonical_json cose_plan);
     check "cbor: signature is 64 bytes" (String.length sg = 64)
   | _ -> check "cbor: COSE_Sign1 shape" false);

  (* decoder rejections *)
  check "cbor: trailing bytes rejected"
    (try ignore (cbor_decode "\x00\x01"); false with Cbor_error _ -> true);
  check "cbor: floats rejected"
    (try ignore (cbor_decode ("\xfb" ^ String.make 8 '\x00')); false
     with Cbor_error _ -> true);
  check "cbor: indefinite lengths rejected"
    (try ignore (cbor_decode "\x5f"); false with Cbor_error _ -> true);

  (* deterministic signing reproduces the vector envelope *)
  check_eq "cose: deterministic signing reproduces vector"
    (sign_plan_cose cose_plan seed) cose_b64;

  (* ---- transitional-envelope roundtrip against upgraded security core ---- *)
  let sp = Security.sign_plan cose_plan (get_str key "privateSeedB64") ~kid:node_id () in
  check_eq "security: transitional envelope signature matches vector chain link 0"
    sp.Security.cose_sign1.signature
    ((List.hd chain).Security.cose_sign1.signature);
  let (rt_ok, _) = Security.verify_plan sp key_cache in
  check "security: transitional roundtrip verifies" rt_ok;

  (* ---- 7. session state machine golden transition table ---- *)
  let sm = match obj_get v11 "stateMachine" with Some v -> v | None -> failwith "sm" in
  let sm_plan = match obj_get sm "plan" with Some p -> p | None -> JObj [] in
  let sm_plan_id = get_str sm "planId" in
  check_eq "session: vector planId recomputes" (make_plan_id sm_plan) sm_plan_id;
  let ctx0 = create_session ~quorum:(QCount (get_int sm "quorum")) sm_plan sm_plan_id in
  check "session: starts DRAFT" (ctx0.state = "DRAFT");
  check "session: lock timeout 2x max delay" (ctx0.lock_timeout_ms = 1_800_000);

  let event_of_json ev =
    let now = get_int ev "nowMs" in
    match get_str ev "type" with
    | "START_LOCK" -> START_LOCK now
    | "PLAN_CONFIRM" -> PLAN_CONFIRM (now, get_str ev "nodeId", get_str ev "planId")
    | "TICK" -> TICK now
    | "SESSION_START" -> SESSION_START now
    | "DELAY_MEASURED" ->
      DELAY_MEASURED (now, get_str ev "nodeId", get_int ev "measuredDelayS")
    | "EOK_OVERRIDE" ->
      EOK_OVERRIDE (now,
                    (match obj_get ev "verified" with Some (JBool b) -> b | _ -> false),
                    get_str ev "reason")
    | "AMENDMENT_PROPOSED" ->
      AMENDMENT_PROPOSED (now, get_str ev "planId", get_int ev "planVersion",
                          List.map (function JStr s -> s | _ -> "")
                            (get_list ev "affectedNodeIds"))
    | "AMENDMENT_CONFIRMED" ->
      AMENDMENT_CONFIRMED (now, get_str ev "nodeId", get_str ev "planId")
    | "HOST_DECISION" -> HOST_DECISION (now, get_str ev "decision")
    | "SESSION_END" -> SESSION_END now
    | t -> failwith ("unknown event " ^ t)
  in
  let final_ctx =
    List.fold_left
      (fun (ctx, i) step ->
        let ev = match obj_get step "event" with Some e -> e | None -> JObj [] in
        let (next, _effects) = transition ctx (event_of_json ev) in
        let expect_state = get_str step "expectState" in
        let expect_lock =
          match obj_get step "expectLock" with
          | Some (JStr s) -> Some s
          | _ -> None
        in
        check (Printf.sprintf "session step %d (%s): state %s (got %s)"
                 i (get_str ev "type") expect_state next.state)
          (next.state = expect_state);
        check (Printf.sprintf "session step %d (%s): lock" i (get_str ev "type"))
          (next.lock = expect_lock);
        (next, i + 1))
      (ctx0, 0)
      (get_list sm "steps")
    |> fst
  in
  check "session: ends COMPLETE" (final_ctx.state = "COMPLETE");

  Printf.printf "\n%d passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
