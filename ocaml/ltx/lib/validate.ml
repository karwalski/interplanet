(* validate.ml -- plan validation (LTX-SPECIFICATION.md §3.5, §4, §7).

   Mirrors validatePlan / _reservedFieldErrors / _assertNoReservedFields in
   javascript/ltx/ltx-sdk.js. Plans are Security.json_val values (JObj keeps
   insertion order). [validate_plan] is pure and never raises.

   Error codes: not_an_object, invalid_version, missing_field, invalid_field,
   invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
   duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
   invalid_delays, reserved_streams, reserved_branching. *)

open Security

type plan_error = { code : string; path : string; message : string }

type validation = { valid : bool; errors : plan_error list }

(** Raised by upgrade_plan_to_v3 / create_session when a plan uses reserved
    stream or branch fields. [code] is the first error code. *)
exception Reserved_field_error of { code : string; errors : plan_error list; message : string }

let seg_types = [ "PLAN_CONFIRM"; "TX"; "RX"; "CAUCUS"; "BUFFER"; "MERGE" ]
let plan_segment_types = seg_types @ [ "SPEAK"; "REST"; "PAD"; "OPEN"; "RELAY" ]
let plan_modes = [ "LTX"; "LTX-LIVE"; "LTX-RELAY"; "LTX-ASYNC" ]
let v3_only_fields = [ "delays"; "planVersion"; "prevPlanHash"; "questions"; "actions"; "streams" ]
let reserved_branch_plan_fields = [ "branches"; "branching" ]
let reserved_branch_segment_fields = [ "branch" ]
let reserved_stream_segment_fields = [ "stream" ]
let node_roles = [ "HOST"; "PARTICIPANT"; "OBSERVER" ]

let field (v : json_val) (k : string) : json_val option =
  match v with JObj kvs -> List.assoc_opt k kvs | _ -> None

let has v k = field v k <> None

let mk code path message = { code; path; message }

(* Number.isInteger *)
let js_int = function
  | JInt i -> Some i
  | JFloat f when Float.is_integer f -> Some (int_of_float f)
  | _ -> None

let js_num = function JInt i -> Some (float_of_int i) | JFloat f -> Some f | _ -> None

(** Reserved-field violations only (§3.5 streams, §7 branching). *)
let reserved_field_errors (plan : json_val) : plan_error list =
  match plan with
  | JObj _ ->
    let streams =
      match field plan "streams" with
      | None | Some (JArr []) -> []
      | Some _ ->
        [ mk "reserved_streams" "streams" "streams[] is reserved (§3.5) and MUST be absent or empty" ]
    in
    let branches =
      List.filter_map
        (fun f ->
          if has plan f then
            Some (mk "reserved_branching" f
                    (f ^ " is reserved for branching (§7, not yet implemented) and MUST be absent"))
          else None)
        reserved_branch_plan_fields
    in
    let segs = match field plan "segments" with Some (JArr l) -> l | _ -> [] in
    let seg_errs =
      List.concat
        (List.mapi
           (fun i s ->
             match s with
             | JObj _ ->
               List.filter_map
                 (fun f ->
                   if has s f then
                     Some (mk "reserved_streams" (Printf.sprintf "segments[%d].%s" i f)
                             ("segment " ^ f ^ " is reserved (§3.5) and MUST be absent"))
                   else None)
                 reserved_stream_segment_fields
               @ List.filter_map
                   (fun f ->
                     if has s f then
                       Some (mk "reserved_branching" (Printf.sprintf "segments[%d].%s" i f)
                               ("segment " ^ f ^ " is reserved for branching (§7) and MUST be absent"))
                     else None)
                   reserved_branch_segment_fields
             | _ -> [])
           segs)
    in
    streams @ branches @ seg_errs
  | _ -> []

(** Raise [Reserved_field_error] if a plan uses reserved stream/branch fields. *)
let assert_no_reserved_fields (plan : json_val) (fn_name : string) : unit =
  match reserved_field_errors plan with
  | [] -> ()
  | first :: _ as errors ->
    raise (Reserved_field_error { code = first.code; errors; message = fn_name ^ ": " ^ first.message })

(* Date.parse(...) is finite: ISO 8601 date or date-time, optional fraction
   and Z / +hh:mm offset. *)
let valid_timestamp (s : string) : bool =
  let n = String.length s in
  let digits i len =
    i + len <= n && String.for_all (fun c -> c >= '0' && c <= '9') (String.sub s i len)
  in
  if not (n >= 10 && digits 0 4 && s.[4] = '-' && digits 5 2 && s.[7] = '-' && digits 8 2) then false
  else
    let mo = int_of_string (String.sub s 5 2) and d = int_of_string (String.sub s 8 2) in
    if mo < 1 || mo > 12 || d < 1 || d > 31 then false
    else if n = 10 then true
    else if not (n >= 16 && s.[10] = 'T' && digits 11 2 && s.[13] = ':' && digits 14 2) then false
    else
      let i = ref 16 in
      if !i + 3 <= n && s.[!i] = ':' && digits (!i + 1) 2 then i := !i + 3;
      if !i < n && s.[!i] = '.' then begin
        incr i;
        while !i < n && s.[!i] >= '0' && s.[!i] <= '9' do incr i done
      end;
      let tail = String.sub s !i (n - !i) in
      tail = "" || tail = "Z"
      || (String.length tail = 6 && (tail.[0] = '+' || tail.[0] = '-') && digits (!i + 1) 2
          && tail.[3] = ':' && digits (!i + 4) 2)

let validate_plan (plan : json_val) : validation =
  match plan with
  | JObj _ ->
    let errs = ref [] in
    let err code path message = errs := mk code path message :: !errs in
    let v = match field plan "v" with Some x -> js_int x | None -> None in
    if v <> Some 2 && v <> Some 3 then err "invalid_version" "v" "v must be 2 or 3";
    List.iter
      (fun f -> if not (has plan f) then err "missing_field" f (f ^ " is required"))
      [ "title"; "start"; "quantum"; "mode"; "nodes"; "segments" ];
    (match field plan "title" with
     | Some (JStr _) | None -> ()
     | Some _ -> err "invalid_field" "title" "title must be a string");
    (match field plan "start" with
     | None -> ()
     | Some (JStr s) when valid_timestamp s -> ()
     | Some _ -> err "invalid_field" "start" "start must be an ISO 8601 UTC timestamp");
    (match field plan "quantum" with
     | None -> ()
     | Some q ->
       (match js_int q with
        | Some q when q >= 1 && q <= 60 -> ()
        | _ -> err "invalid_quantum" "quantum" "quantum must be an integer 1..60 minutes (§3.2)"));
    (match field plan "mode" with
     | None -> ()
     | Some (JStr m) when List.mem m plan_modes -> ()
     | Some _ -> err "invalid_mode" "mode" ("mode must be one of " ^ String.concat ", " plan_modes));
    let ids = Hashtbl.create 8 in
    (match field plan "nodes" with
     | None -> ()
     | Some (JArr (_ :: _ as nodes)) ->
       let hosts = ref 0 in
       List.iteri
         (fun i n ->
           let s k = match field n k with Some (JStr x) -> Some x | _ -> None in
           let delay = match field n "delay" with Some d -> js_num d | None -> None in
           match s "id", s "name", s "role", delay with
           | Some id, Some _, Some role, Some d
             when id <> "" && not (String.contains id '|') && List.mem role node_roles && d >= 0.0 ->
             if Hashtbl.mem ids id then
               err "duplicate_node_id" (Printf.sprintf "nodes[%d].id" i) ("duplicate node id " ^ id);
             Hashtbl.replace ids id ();
             if role = "HOST" then incr hosts
           | _ ->
             err "invalid_nodes" (Printf.sprintf "nodes[%d]" i)
               "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0")
         nodes;
       let h = List.hd nodes in
       let h_ok =
         field h "role" = Some (JStr "HOST")
         && (match field h "delay" with Some d -> js_num d = Some 0.0 | None -> false)
       in
       if !hosts <> 1 || not h_ok then
         err "invalid_host" "nodes[0]" "exactly one HOST, first in nodes[], with delay 0 (§3.1)"
     | Some _ -> err "invalid_nodes" "nodes" "nodes must be a non-empty array");
    (match field plan "segments" with
     | None -> ()
     | Some (JArr segs) ->
       List.iteri
         (fun i s ->
           let type_ok = match field s "type" with Some (JStr t) -> List.mem t plan_segment_types | _ -> false in
           let q_ok = match field s "q" with Some q -> (match js_int q with Some q -> q >= 1 | None -> false) | None -> false in
           if not (type_ok && q_ok) then
             err "invalid_segment" (Printf.sprintf "segments[%d]" i) "segment needs a known type and integer q >= 1"
           else
             match field s "speaker" with
             | None -> ()
             | Some (JStr sp) when Hashtbl.mem ids sp -> ()
             | Some sp ->
               let shown = match sp with JStr x -> x | other -> canonical_json other in
               err "unknown_speaker" (Printf.sprintf "segments[%d].speaker" i)
                 ("speaker " ^ shown ^ " is not a node id"))
         segs
     | Some _ -> err "invalid_segment" "segments" "segments must be an array");
    (match v with
     | Some 2 ->
       List.iter
         (fun f ->
           if has plan f then
             err "v3_field_in_v2" f (f ^ " is a v3 field and MUST NOT appear in a v2 plan (§4.3)"))
         v3_only_fields
     | Some 3 ->
       (match field plan "delays" with
        | None -> ()
        | Some (JObj kvs) ->
          List.iter
            (fun (k, dv) ->
              let ok =
                match String.split_on_char '|' k with
                | [ a; b ] ->
                  String.compare a b < 0
                  && (Hashtbl.length ids = 0 || (Hashtbl.mem ids a && Hashtbl.mem ids b))
                  && (match js_num dv with Some d -> d >= 0.0 | None -> false)
                | _ -> false
              in
              if not ok then
                err "invalid_delays" ("delays." ^ k)
                  "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)")
            kvs
        | Some _ -> err "invalid_delays" "delays" "delays must be an object");
       (match field plan "planVersion" with
        | None -> ()
        | Some pv ->
          (match js_int pv with
           | Some p when p >= 1 -> ()
           | _ -> err "invalid_field" "planVersion" "planVersion must be an integer >= 1"));
       (match field plan "prevPlanHash" with
        | None -> ()
        | Some (JStr h)
          when String.length h = 64
               && String.for_all (fun c -> (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) h -> ()
        | Some _ -> err "invalid_field" "prevPlanHash" "prevPlanHash must be 64 lowercase hex characters");
       List.iter
         (fun f ->
           match field plan f with
           | None | Some (JArr _) -> ()
           | Some _ -> err "invalid_field" f (f ^ " must be an array"))
         [ "questions"; "actions" ]
     | _ -> ());
    let errors = List.rev !errs @ reserved_field_errors plan in
    { valid = errors = []; errors }
  | _ -> { valid = false; errors = [ mk "not_an_object" "" "plan must be an object" ] }
