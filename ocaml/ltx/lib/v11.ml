(* v11.ml -- LTX v1.1 core subset for the OCaml port (Epic 72, Story 72.5).

   Mirrors typescript/ltx/src/{segments,session,amend,registers,cbor,cose}.ts:
   1. v3 planId + pairDelay + compute_segments_for
   2. transition() session state machine (pure core)
   3. amendment-chain verification
   4. register entries + reducers + Merkle entries root
   5. CBOR decode + COSE_Sign1 verify

   Plans and register entries are Security.json_val values; JObj preserves
   insertion order, which the FROZEN v2 planId hash depends on. *)

open Security

(* ---- JSON parsing (order-preserving) ---- *)

exception Json_error of string

let parse_json (src : string) : json_val =
  let n = String.length src in
  let pos = ref 0 in
  let peek () = if !pos < n then Some src.[!pos] else None in
  let skip_ws () =
    while !pos < n &&
          (match src.[!pos] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false)
    do incr pos done
  in
  let expect c =
    if !pos < n && src.[!pos] = c then incr pos
    else raise (Json_error (Printf.sprintf "expected '%c' at %d" c !pos))
  in
  let parse_string () =
    expect '"';
    let buf = Buffer.create 16 in
    let fin = ref false in
    while not !fin do
      if !pos >= n then raise (Json_error "unterminated string");
      let c = src.[!pos] in
      incr pos;
      if c = '"' then fin := true
      else if c = '\\' then begin
        if !pos >= n then raise (Json_error "bad escape");
        let e = src.[!pos] in
        incr pos;
        match e with
        | '"'  -> Buffer.add_char buf '"'
        | '\\' -> Buffer.add_char buf '\\'
        | '/'  -> Buffer.add_char buf '/'
        | 'b'  -> Buffer.add_char buf '\b'
        | 'f'  -> Buffer.add_char buf '\012'
        | 'n'  -> Buffer.add_char buf '\n'
        | 'r'  -> Buffer.add_char buf '\r'
        | 't'  -> Buffer.add_char buf '\t'
        | 'u'  ->
          let code = int_of_string ("0x" ^ String.sub src !pos 4) in
          pos := !pos + 4;
          if code < 0x80 then Buffer.add_char buf (Char.chr code)
          else if code < 0x800 then begin
            Buffer.add_char buf (Char.chr (0xC0 lor (code lsr 6)));
            Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F)))
          end else begin
            Buffer.add_char buf (Char.chr (0xE0 lor (code lsr 12)));
            Buffer.add_char buf (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
            Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F)))
          end
        | c -> raise (Json_error (Printf.sprintf "bad escape '\\%c'" c))
      end
      else Buffer.add_char buf c
    done;
    Buffer.contents buf
  in
  let parse_number () =
    let start = !pos in
    let is_num c = match c with
      | '0'..'9' | '-' | '+' | '.' | 'e' | 'E' -> true | _ -> false
    in
    while !pos < n && is_num src.[!pos] do incr pos done;
    let tok = String.sub src start (!pos - start) in
    (match int_of_string_opt tok with
     | Some i -> JInt i
     | None ->
       (match float_of_string_opt tok with
        | Some f -> JFloat f
        | None -> raise (Json_error ("bad number " ^ tok))))
  in
  let rec parse_value () =
    skip_ws ();
    match peek () with
    | Some '{' -> parse_obj ()
    | Some '[' -> parse_arr ()
    | Some '"' -> JStr (parse_string ())
    | Some 't' -> pos := !pos + 4; JBool true
    | Some 'f' -> pos := !pos + 5; JBool false
    | Some 'n' -> pos := !pos + 4; JNull
    | Some _   -> parse_number ()
    | None     -> raise (Json_error "unexpected end of input")
  and parse_obj () =
    expect '{';
    skip_ws ();
    if peek () = Some '}' then begin incr pos; JObj [] end
    else begin
      let kvs = ref [] in
      let fin = ref false in
      while not !fin do
        skip_ws ();
        let k = parse_string () in
        skip_ws ();
        expect ':';
        let v = parse_value () in
        kvs := (k, v) :: !kvs;
        skip_ws ();
        (match peek () with
         | Some ',' -> incr pos
         | Some '}' -> incr pos; fin := true
         | _ -> raise (Json_error "expected ',' or '}'"))
      done;
      JObj (List.rev !kvs)
    end
  and parse_arr () =
    expect '[';
    skip_ws ();
    if peek () = Some ']' then begin incr pos; JArr [] end
    else begin
      let items = ref [] in
      let fin = ref false in
      while not !fin do
        let v = parse_value () in
        items := v :: !items;
        skip_ws ();
        (match peek () with
         | Some ',' -> incr pos
         | Some ']' -> incr pos; fin := true
         | _ -> raise (Json_error "expected ',' or ']'"))
      done;
      JArr (List.rev !items)
    end
  in
  let v = parse_value () in
  skip_ws ();
  v

(* Insertion-order compact JSON (JS JSON.stringify equivalent) — required by
   the FROZEN v2 planId hash. canonical_json (sorted keys) is the v3 form. *)
let rec json_stringify (v : json_val) : string =
  match v with
  | JObj kvs ->
    "{" ^ String.concat ","
            (List.map (fun (k, v2) -> json_str k ^ ":" ^ json_stringify v2) kvs)
        ^ "}"
  | JArr lst -> "[" ^ String.concat "," (List.map json_stringify lst) ^ "]"
  | other -> canonical_json other

(* ---- json_val accessors ---- *)

let obj_get (v : json_val) (key : string) : json_val option =
  match v with JObj kvs -> List.assoc_opt key kvs | _ -> None

let get_str ?(default = "") v key =
  match obj_get v key with Some (JStr s) -> s | _ -> default

let get_int ?(default = 0) v key =
  match obj_get v key with
  | Some (JInt i) -> i
  | Some (JFloat f) -> int_of_float f
  | _ -> default

let get_list v key =
  match obj_get v key with Some (JArr l) -> l | _ -> []

let obj_set (v : json_val) (key : string) (value : json_val) : json_val =
  match v with
  | JObj kvs ->
    if List.mem_assoc key kvs then
      JObj (List.map (fun (k, v2) -> if k = key then (k, value) else (k, v2)) kvs)
    else JObj (kvs @ [(key, value)])
  | other -> other

(* ---- misc helpers ---- *)

let hex_of_string (s : string) : string =
  String.concat ""
    (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let djb_hash32 (s : string) : int32 =
  String.fold_left
    (fun h c ->
      Int32.logand
        (Int32.add (Int32.mul 31l h) (Int32.of_int (Char.code c)))
        0xFFFFFFFFl)
    0l s

let remove_ws (s : string) : string =
  String.concat ""
    (List.filter (fun c -> c <> " " && c <> "\t" && c <> "\n" && c <> "\r")
       (List.init (String.length s) (fun i -> String.make 1 s.[i])))

let short_name (name : string) (len : int) : string =
  let s = String.uppercase_ascii (remove_ws name) in
  String.sub s 0 (min len (String.length s))

(* "YYYY-MM-DDTHH:MM:SS(.mmm)?Z" -> Unix epoch milliseconds (UTC) *)
let parse_iso_ms (s : string) : int =
  try
    Scanf.sscanf s "%4d-%2d-%2dT%2d:%2d:%2d"
      (fun yr mo dy h m sec ->
        let a = (14 - mo) / 12 in
        let y = yr + 4800 - a in
        let mn = mo + 12 * a - 3 in
        let jdn = dy + (153 * mn + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045 in
        let days = jdn - 2440588 in
        let ms =
          if String.length s > 22 && s.[19] = '.'
          then int_of_string (String.sub s 20 3)
          else 0
        in
        (days * 86400 + h * 3600 + m * 60 + sec) * 1000 + ms)
  with _ -> 0

(* ---- 1. Plan ID (v2 FROZEN / v3 canonical, LTX-SPECIFICATION.md §4.3/§4.5) ---- *)

let make_plan_id (plan : json_val) : string =
  let start = get_str plan "start" in
  let date =
    String.concat ""
      (String.split_on_char '-'
         (String.sub start 0 (min 10 (String.length start))))
  in
  let nodes = get_list plan "nodes" in
  let host_str =
    match nodes with
    | first :: _ ->
      let name = get_str ~default:"HOST" first "name" in
      short_name (if name = "" then "HOST" else name) 8
    | [] -> "HOST"
  in
  let node_str =
    match nodes with
    | _ :: (_ :: _ as rest) ->
      let joined =
        String.concat "-" (List.map (fun nd -> short_name (get_str nd "name") 4) rest)
      in
      String.sub joined 0 (min 16 (String.length joined))
    | _ -> "RX"
  in
  if get_int ~default:1 plan "v" >= 3 then
    let digest = hex_of_string (sha256 (canonical_json plan)) in
    Printf.sprintf "LTX-%s-%s-%s-v3-%s" date host_str node_str (String.sub digest 0 8)
  else
    (* FROZEN v2 path — 32-bit polynomial hash over insertion-order JSON. *)
    Printf.sprintf "LTX-%s-%s-%s-v2-%08lx" date host_str node_str
      (djb_hash32 (json_stringify plan))

(* ---- pair_delay (LTX-SPECIFICATION.md §3.7) ---- *)

let find_node (plan : json_val) (node_id : string) : json_val option =
  List.find_opt (fun nd -> get_str nd "id" = node_id) (get_list plan "nodes")

let pair_delay (plan : json_val) (a : string) (b : string) : int =
  if a = b then 0
  else
    let key = if a < b then a ^ "|" ^ b else b ^ "|" ^ a in
    let from_matrix =
      match obj_get plan "delays" with
      | Some (JObj kvs) ->
        (match List.assoc_opt key kvs with
         | Some (JInt i) -> Some i
         | Some (JFloat f) -> Some (int_of_float f)
         | _ -> None)
      | _ -> None
    in
    match from_matrix with
    | Some d -> d
    | None ->
      let na = find_node plan a and nb = find_node plan b in
      (match na, nb with
       | None, _ -> invalid_arg ("pair_delay: unknown node " ^ a)
       | _, None -> invalid_arg ("pair_delay: unknown node " ^ b)
       | Some na, Some nb ->
         let host_id =
           match get_list plan "nodes" with
           | h :: _ -> get_str h "id"
           | [] -> ""
         in
         if a = host_id then get_int nb "delay"
         else if b = host_id then get_int na "delay"
         else get_int na "delay" + get_int nb "delay")

(* ---- compute_segments_for (LTX-SPECIFICATION.md §14.3) ---- *)

type viewer_segment = {
  vseg_type         : string;
  vq                : int;
  vstart_ms         : int;
  vend_ms           : int;
  vdur_min          : int;
  vspeaker          : string option;
  vlabel            : string option;
  vperspective      : string; (* "transmit" | "receive" | "neutral" *)
  varrival_offset_s : int;
}

let compute_segments_for (plan : json_val) (viewer : string) : viewer_segment list =
  if find_node plan viewer = None then
    invalid_arg ("compute_segments_for: unknown viewer " ^ viewer);
  let quantum = get_int plan "quantum" in
  let q_ms = quantum * 60 * 1000 in
  let t = ref (parse_iso_ms (get_str plan "start")) in
  List.map
    (fun seg ->
      let q = get_int seg "q" in
      let dur_ms = q * q_ms in
      let start_ms = !t in
      t := !t + dur_ms;
      let seg_type = get_str seg "type" in
      let speaker =
        match obj_get seg "speaker" with Some (JStr s) -> Some s | _ -> None
      in
      let label =
        match obj_get seg "label" with Some (JStr s) -> Some s | _ -> None
      in
      let base = {
        vseg_type = seg_type; vq = q;
        vstart_ms = start_ms; vend_ms = start_ms + dur_ms;
        vdur_min = q * quantum;
        vspeaker = speaker; vlabel = label;
        vperspective = "neutral"; varrival_offset_s = 0;
      } in
      match speaker with
      | None -> base
      | Some _ when seg_type <> "TX" && seg_type <> "SPEAK" -> base
      | Some sp when sp = viewer -> { base with vperspective = "transmit" }
      | Some sp ->
        let shift_s = pair_delay plan sp viewer in
        { base with
          vstart_ms = start_ms + shift_s * 1000;
          vend_ms = start_ms + dur_ms + shift_s * 1000;
          vperspective = "receive";
          varrival_offset_s = shift_s })
    (get_list plan "segments")

(* ---- 2. Session state machine (LTX-SPECIFICATION.md §5, §5.4, §6.4) ---- *)

(* Protocol constants (Story 26.4 / constants.ml; duplicated here so the
   security+v11 build stays standalone). *)
let lock_timeout_factor = 2
let delay_violation_warn_s = 120
let delay_violation_degrade_s = 300

type pending_amendment = {
  pa_plan_id        : string;
  pa_plan_version   : int;
  pa_affected       : string list;
  pa_confirmed      : string list;
  pa_proposed_at_ms : int;
  pa_timeout_ms     : int;
}

type session_ctx = {
  state                : string;
  plan                 : json_val;
  plan_id              : string;
  session_root_plan_id : string;
  plan_version         : int;
  lock                 : string option; (* "FULL" | "QUORUM" *)
  lock_started_at_ms   : int option;
  lock_timeout_ms      : int;
  confirmations        : (string * string) list; (* nodeId -> confirmed planId *)
  mismatched           : string list;
  quorum_threshold     : int;
  subset               : string list option;
  degraded_reasons     : string list;
  resume_state         : string option;
  pending_amendment    : pending_amendment option;
}

type session_quorum = QAll | QMajority | QCount of int

type session_event =
  | START_LOCK of int                                (* nowMs *)
  | PLAN_CONFIRM of int * string * string            (* nowMs, nodeId, planId *)
  | TICK of int
  | SESSION_START of int
  | DELAY_MEASURED of int * string * int             (* nowMs, nodeId, measuredDelayS *)
  | EOK_OVERRIDE of int * bool * string              (* nowMs, verified, reason *)
  | AMENDMENT_PROPOSED of int * string * int * string list
  | AMENDMENT_CONFIRMED of int * string * string     (* nowMs, nodeId, planId *)
  | HOST_DECISION of int * string                    (* nowMs, continue|abort|resume *)
  | SESSION_END of int

(* Simplified effect list (permitted by the Epic 72 cascade instructions):
   kind is "audit" | "notify" | "escalate"; audit detail is "FROM->TO". *)
type session_effect = {
  eff_kind   : string;
  eff_code   : string;
  eff_detail : string;
}

let event_now = function
  | START_LOCK n | TICK n | SESSION_START n | SESSION_END n -> n
  | PLAN_CONFIRM (n, _, _) | DELAY_MEASURED (n, _, _) -> n
  | EOK_OVERRIDE (n, _, _) | HOST_DECISION (n, _) -> n
  | AMENDMENT_PROPOSED (n, _, _, _) | AMENDMENT_CONFIRMED (n, _, _) -> n

let event_name = function
  | START_LOCK _ -> "START_LOCK" | PLAN_CONFIRM _ -> "PLAN_CONFIRM"
  | TICK _ -> "TICK" | SESSION_START _ -> "SESSION_START"
  | DELAY_MEASURED _ -> "DELAY_MEASURED" | EOK_OVERRIDE _ -> "EOK_OVERRIDE"
  | AMENDMENT_PROPOSED _ -> "AMENDMENT_PROPOSED"
  | AMENDMENT_CONFIRMED _ -> "AMENDMENT_CONFIRMED"
  | HOST_DECISION _ -> "HOST_DECISION" | SESSION_END _ -> "SESSION_END"

let participants (plan : json_val) : json_val list =
  List.filter (fun nd -> get_str nd "role" = "PARTICIPANT") (get_list plan "nodes")

(* 2 x one-way delay to the furthest node, in ms (LTX-SPECIFICATION.md §5.1). *)
let lock_timeout_ms (plan : json_val) : int =
  let max_delay =
    List.fold_left (fun m nd -> max m (get_int nd "delay")) 0 (get_list plan "nodes")
  in
  lock_timeout_factor * max_delay * 1000

let quorum_count (plan : json_val) (quorum : session_quorum) : int =
  let total = List.length (participants plan) in
  match quorum with
  | QMajority -> total / 2 + 1
  | QCount n -> min (max n 1) total
  | QAll -> total

let create_session ?(quorum = QAll) (plan : json_val) (plan_id : string) : session_ctx =
  {
    state = "DRAFT";
    plan;
    plan_id;
    session_root_plan_id = plan_id;
    plan_version = get_int ~default:1 plan "planVersion";
    lock = None;
    lock_started_at_ms = None;
    lock_timeout_ms = lock_timeout_ms plan;
    confirmations = [];
    mismatched = [];
    quorum_threshold = quorum_count plan quorum;
    subset = None;
    degraded_reasons = [];
    resume_state = None;
    pending_amendment = None;
  }

let confirmed (ctx : session_ctx) (node_id : string) : bool =
  List.assoc_opt node_id ctx.confirmations = Some ctx.plan_id

let full_lock_reached (ctx : session_ctx) : bool =
  List.for_all (fun nd -> confirmed ctx (get_str nd "id")) (participants ctx.plan)

let quorum_reached (ctx : session_ctx) : bool =
  let count =
    List.length
      (List.filter (fun nd -> confirmed ctx (get_str nd "id")) (participants ctx.plan))
  in
  count >= ctx.quorum_threshold

(* Ascending-delay fallback ordering over confirmed participants (§5.3). *)
let confirmed_subset (ctx : session_ctx) : string list =
  let host_id =
    match get_list ctx.plan "nodes" with h :: _ -> get_str h "id" | [] -> ""
  in
  let conf =
    participants ctx.plan
    |> List.filter (fun nd -> confirmed ctx (get_str nd "id"))
    |> List.stable_sort (fun a b -> compare (get_int a "delay") (get_int b "delay"))
    |> List.map (fun nd -> get_str nd "id")
  in
  host_id :: conf

(* Declared one-way delay for a node: v3 pair matrix HOST row, else node delay. *)
let declared_delay_s (plan : json_val) (node_id : string) : int option =
  match find_node plan node_id with
  | None -> None
  | Some node ->
    let from_matrix =
      match obj_get plan "delays" with
      | Some (JObj kvs) ->
        let host_id =
          match get_list plan "nodes" with h :: _ -> get_str h "id" | [] -> ""
        in
        let key =
          if host_id < node_id then host_id ^ "|" ^ node_id
          else node_id ^ "|" ^ host_id
        in
        (match List.assoc_opt key kvs with
         | Some (JInt i) -> Some i
         | Some (JFloat f) -> Some (int_of_float f)
         | _ -> None)
      | _ -> None
    in
    (match from_matrix with
     | Some d -> Some d
     | None -> Some (get_int node "delay"))

let assoc_set key value l = (key, value) :: List.remove_assoc key l

let moved (ctx : session_ctx) (to_state : string) (event : session_event)
    (effects : session_effect list) : session_ctx * session_effect list =
  let audit = {
    eff_kind = "audit";
    eff_code = event_name event;
    eff_detail = Printf.sprintf "%s->%s@%d" ctx.state to_state (event_now event);
  } in
  ({ ctx with state = to_state }, audit :: effects)

let unchanged ?(effects = []) (ctx : session_ctx) : session_ctx * session_effect list =
  (ctx, effects)

let invalid (ctx : session_ctx) (event : session_event) : session_effect =
  { eff_kind = "notify"; eff_code = "INVALID_EVENT";
    eff_detail = Printf.sprintf "%s ignored in state %s" (event_name event) ctx.state }

let degrade ?(extra = []) (ctx : session_ctx) (event : session_event) (reason : string)
    : session_ctx * session_effect list =
  let next = { ctx with degraded_reasons = ctx.degraded_reasons @ [reason] } in
  let effects =
    { eff_kind = "notify"; eff_code = "DEGRADED"; eff_detail = reason }
    :: { eff_kind = "escalate"; eff_code = "DEGRADED"; eff_detail = reason }
    :: extra
  in
  if ctx.state = "DEGRADED" then
    unchanged ~effects:[List.hd effects] next (* already degraded: notify only *)
  else moved next "DEGRADED" event effects

(* Advance the session state machine. Pure: same (ctx, event) always yields
   the same result. Returns (next_ctx, effects). *)
let transition (ctx : session_ctx) (event : session_event)
    : session_ctx * session_effect list =
  match event with
  | START_LOCK now ->
    if ctx.state <> "DRAFT" then unchanged ~effects:[invalid ctx event] ctx
    else begin
      let host_id =
        match get_list ctx.plan "nodes" with h :: _ -> get_str h "id" | [] -> ""
      in
      let next = { ctx with
        lock_started_at_ms = Some now;
        confirmations = assoc_set host_id ctx.plan_id ctx.confirmations;
      } in
      moved next "LOCKING" event []
    end

  | PLAN_CONFIRM (_, node_id, plan_id) ->
    if ctx.state <> "LOCKING" && ctx.state <> "DEGRADED" then
      unchanged ~effects:[invalid ctx event] ctx
    else begin
      let next = { ctx with
        confirmations = assoc_set node_id plan_id ctx.confirmations;
      } in
      if plan_id <> ctx.plan_id then begin
        let next = { next with
          mismatched =
            List.filter (fun id -> id <> node_id) ctx.mismatched @ [node_id];
        } in
        unchanged next ~effects:[{
          eff_kind = "notify"; eff_code = "PLANID_MISMATCH";
          eff_detail = Printf.sprintf
            "%s confirmed %s, expected %s (resolve per \xc2\xa75.5)"
            node_id plan_id ctx.plan_id;
        }]
      end else begin
        let next = { next with
          mismatched = List.filter (fun id -> id <> node_id) ctx.mismatched;
        } in
        if full_lock_reached next then
          (* Late full confirmation recovers a DEGRADED quorum lock (§5.2). *)
          let locked = { next with lock = Some "FULL"; subset = None } in
          moved locked "LOCKED" event [{
            eff_kind = "notify"; eff_code = "LOCKED";
            eff_detail = "full lock achieved";
          }]
        else unchanged next
      end
    end

  | TICK now ->
    if ctx.state <> "LOCKING" then unchanged ctx
    else begin
      match ctx.lock_started_at_ms with
      | None -> unchanged ctx
      | Some started when now - started < ctx.lock_timeout_ms -> unchanged ctx
      | Some _ ->
        (* Lock timeout expired (§5.1). *)
        if quorum_reached ctx then begin
          let subset = confirmed_subset ctx in
          let next = { ctx with lock = Some "QUORUM"; subset = Some subset } in
          let missing =
            participants ctx.plan
            |> List.filter (fun nd -> not (confirmed ctx (get_str nd "id")))
            |> List.map (fun nd -> get_str nd "id")
          in
          degrade next event
            (Printf.sprintf "quorum lock with subset [%s]; unconfirmed: [%s]"
               (String.concat "," subset) (String.concat "," missing))
        end
        else degrade ctx event "plan-lock timeout without quorum"
    end

  | SESSION_START _ ->
    if ctx.state = "LOCKED" then moved ctx "ACTIVE" event []
    else if ctx.state = "DEGRADED" && ctx.lock <> None then
      (* §5.2: escalation to HOST required before TX. *)
      unchanged ctx ~effects:[{
        eff_kind = "escalate"; eff_code = "DEGRADED_START";
        eff_detail = "session start requested while DEGRADED; HOST decision required";
      }]
    else unchanged ~effects:[invalid ctx event] ctx

  | DELAY_MEASURED (_, node_id, measured) ->
    if ctx.state <> "ACTIVE" && ctx.state <> "LOCKED" && ctx.state <> "DEGRADED"
    then unchanged ctx
    else begin
      match declared_delay_s ctx.plan node_id with
      | None -> unchanged ~effects:[invalid ctx event] ctx
      | Some declared ->
        let deviation = abs (measured - declared) in
        if deviation > delay_violation_degrade_s then
          degrade ctx event
            (Printf.sprintf "delay violation %s: measured %ds vs declared %ds (>%ds)"
               node_id measured declared delay_violation_degrade_s)
        else if deviation > delay_violation_warn_s then
          unchanged ctx ~effects:[{
            eff_kind = "notify"; eff_code = "DELAY_VIOLATION";
            eff_detail = Printf.sprintf "%s: measured %ds vs declared %ds"
              node_id measured declared;
          }]
        else unchanged ctx
    end

  | EOK_OVERRIDE (_, verified, reason) ->
    if ctx.state = "COMPLETE" || ctx.state = "ABORTED" then unchanged ctx
    else if not verified then
      unchanged ctx ~effects:[{
        eff_kind = "notify"; eff_code = "OVERRIDE_REJECTED";
        eff_detail = if reason = "" then "override failed verification" else reason;
      }]
    else if ctx.state = "EMERGENCY_HOLD" then unchanged ctx
    else begin
      let next = { ctx with resume_state = Some ctx.state } in
      moved next "EMERGENCY_HOLD" event [{
        eff_kind = "notify"; eff_code = "EMERGENCY_HOLD";
        eff_detail = if reason = "" then "verified EOK override" else reason;
      }]
    end

  | AMENDMENT_PROPOSED (now, plan_id, plan_version, affected) ->
    if ctx.state <> "ACTIVE" && ctx.state <> "LOCKED" && ctx.state <> "DEGRADED"
    then unchanged ~effects:[invalid ctx event] ctx
    else if plan_version <> ctx.plan_version + 1 then
      unchanged ctx ~effects:[{
        eff_kind = "notify"; eff_code = "AMENDMENT_REJECTED";
        eff_detail = Printf.sprintf "planVersion %d != %d + 1"
          plan_version ctx.plan_version;
      }]
    else begin
      (* Delta re-lock (§6.4): timeout scoped to the furthest affected node. *)
      let max_delay =
        get_list ctx.plan "nodes"
        |> List.filter (fun nd -> List.mem (get_str nd "id") affected)
        |> List.fold_left (fun m nd -> max m (get_int nd "delay")) 0
      in
      let pending = {
        pa_plan_id = plan_id;
        pa_plan_version = plan_version;
        pa_affected = affected;
        pa_confirmed = [];
        pa_proposed_at_ms = now;
        pa_timeout_ms = lock_timeout_factor * max_delay * 1000;
      } in
      unchanged { ctx with pending_amendment = Some pending } ~effects:[{
        eff_kind = "notify"; eff_code = "AMENDMENT_PROPOSED";
        eff_detail = Printf.sprintf "plan %s v%d; awaiting [%s]"
          plan_id plan_version (String.concat "," affected);
      }]
    end

  | AMENDMENT_CONFIRMED (_, node_id, plan_id) ->
    (match ctx.pending_amendment with
     | Some pa when plan_id = pa.pa_plan_id ->
       if not (List.mem node_id pa.pa_affected) then unchanged ctx
       else begin
         let conf =
           List.filter (fun id -> id <> node_id) pa.pa_confirmed @ [node_id]
         in
         if List.length conf < List.length pa.pa_affected then
           unchanged { ctx with
             pending_amendment = Some { pa with pa_confirmed = conf } }
         else
           (* All affected nodes confirmed — the amendment applies. *)
           let next = { ctx with
             plan_id = pa.pa_plan_id;
             plan_version = pa.pa_plan_version;
             pending_amendment = None;
           } in
           unchanged next ~effects:[{
             eff_kind = "notify"; eff_code = "AMENDMENT_APPLIED";
             eff_detail = Printf.sprintf "plan %s v%d in effect (root %s)"
               pa.pa_plan_id pa.pa_plan_version ctx.session_root_plan_id;
           }]
       end
     | _ -> unchanged ~effects:[invalid ctx event] ctx)

  | HOST_DECISION (_, decision) ->
    if decision = "abort" then begin
      if ctx.state = "COMPLETE" || ctx.state = "ABORTED" then unchanged ctx
      else moved ctx "ABORTED" event []
    end
    else if decision = "resume" && ctx.state = "EMERGENCY_HOLD" then begin
      let back = match ctx.resume_state with Some s -> s | None -> "ACTIVE" in
      moved { ctx with resume_state = None } back event []
    end
    else if decision = "continue" && ctx.state = "DEGRADED" then
      (* §5.2: HOST elects to continue with the confirmed subset. *)
      moved ctx "ACTIVE" event [{
        eff_kind = "notify"; eff_code = "CONTINUE_DEGRADED";
        eff_detail =
          (match ctx.subset with
           | Some subset ->
             Printf.sprintf "continuing with subset [%s]" (String.concat "," subset)
           | None -> "continuing despite degraded condition");
      }]
    else unchanged ~effects:[invalid ctx event] ctx

  | SESSION_END _ ->
    if ctx.state = "ACTIVE" || ctx.state = "DEGRADED" then
      moved ctx "COMPLETE" event []
    else unchanged ~effects:[invalid ctx event] ctx

(* ---- 3. Amendment chains (LTX-SPECIFICATION.md §6.4, LTX-SECURITY.md §7.6) ---- *)

(* SHA-256 hex of the canonical JSON of a plan — order-insensitive; never the
   legacy v2 polynomial planId hash. *)
let plan_hash (plan : json_val) : string =
  hex_of_string (sha256 (canonical_json plan))

(* Verify an amendment chain: chain.(0) is the root plan, each later element
   a successive amendment. Per link: signature via Security.verify_plan,
   planVersion +1 steps, prevPlanHash equality with the recomputed
   predecessor hash; the root must carry no prevPlanHash. *)
let verify_amendment_chain (chain : Security.signed_plan list)
    (key_cache : (string * Security.nik) list) : bool * string =
  match chain with
  | [] -> (false, "empty_chain")
  | root :: rest ->
    let rec check_sigs i = function
      | [] -> None
      | sp :: tl ->
        let (ok, reason) = Security.verify_plan sp key_cache in
        if not ok then Some (false, Printf.sprintf "link_%d_%s" i reason)
        else check_sigs (i + 1) tl
    in
    (match check_sigs 0 chain with
     | Some failure -> failure
     | None ->
       let root_plan = root.Security.plan in
       if obj_get root_plan "prevPlanHash" <> None then (false, "root_has_prev_hash")
       else begin
         let rec walk i prev_plan prev_version = function
           | [] -> (true, "ok")
           | sp :: tl ->
             let p = sp.Security.plan in
             if get_int p "v" <> 3 then
               (false, Printf.sprintf "link_%d_not_v3" i)
             else if get_int p "planVersion" <> prev_version + 1 then
               (false, Printf.sprintf "link_%d_version_gap" i)
             else if get_str p "prevPlanHash" <> plan_hash prev_plan then
               (false, Printf.sprintf "link_%d_prev_hash_mismatch" i)
             else walk (i + 1) p (get_int p "planVersion") tl
         in
         walk 1 root_plan (get_int ~default:1 root_plan "planVersion") rest
       end)

(* ---- 4. Register entries + reducers (LTX-SPECIFICATION.md §8.2/§9/§10) ---- *)

let entry_prefix = function
  | "question" | "question_response" -> "QST"
  | "action" | "action_update" -> "ACT"
  | "amendment" -> "AMD"
  | "state_transition" -> "STA"
  | "merge_snapshot" -> "MRG"
  | "decision" -> "DEC"
  | _ -> "ENT"

(* Create a signed register entry (LTX-SECURITY.md §9.5): Ed25519 over the
   canonical JSON of the entry without `sig`. `seed` is the raw 32-byte key. *)
let create_register_entry ~entry_type ~(content : json_val) ~session_id ~node_id
    ~seq ~timestamp ~(seed : string) : json_val =
  let entry_id = Printf.sprintf "%s-%s-%d" (entry_prefix entry_type) node_id seq in
  let unsigned = JObj [
    ("entryId", JStr entry_id);
    ("sessionId", JStr session_id);
    ("nodeId", JStr node_id);
    ("seq", JInt seq);
    ("type", JStr entry_type);
    ("content", content);
    ("timestamp", JStr timestamp);
  ] in
  let sg = Ed25519.sign (canonical_json unsigned) seed in
  match unsigned with
  | JObj kvs -> JObj (kvs @ [("sig", JStr (b64u_encode sg))])
  | _ -> unsigned

(* Verify a register entry signature against a key cache mapping the entry's
   nodeId to its NIK. *)
let verify_register_entry (entry : json_val)
    (key_cache : (string * Security.nik) list) : bool * string =
  match obj_get entry "sig" with
  | Some (JStr sig_b64) ->
    let node_id = get_str entry "nodeId" in
    (match List.assoc_opt node_id key_cache with
     | None -> (false, "key_not_in_cache")
     | Some nik ->
       let unsigned =
         match entry with
         | JObj kvs -> JObj (List.filter (fun (k, _) -> k <> "sig") kvs)
         | other -> other
       in
       if Ed25519.verify (canonical_json unsigned) (b64u_decode sig_b64)
            nik.Security.pub_raw
       then (true, "ok")
       else (false, "signature_invalid"))
  | _ -> (false, "missing_sig")

(* De-duplicate by (nodeId, seq) — first occurrence wins — and sort into the
   §8.2 total order (timestamp, nodeId, seq). *)
let order_entries (entries : json_val list) : json_val list =
  let seen = Hashtbl.create 16 in
  let uniq =
    List.filter
      (fun e ->
        let k = get_str e "nodeId" ^ "\x00" ^ string_of_int (get_int e "seq") in
        if Hashtbl.mem seen k then false
        else begin Hashtbl.add seen k (); true end)
      entries
  in
  List.stable_sort
    (fun a b ->
      compare
        (get_str a "timestamp", get_str a "nodeId", get_int a "seq")
        (get_str b "timestamp", get_str b "nodeId", get_int b "seq"))
    uniq

type question_state = {
  q_qid             : string;
  q_text            : string;
  q_submitter       : string;
  q_urgency         : string option;
  q_intended_window : string option;
  q_status          : string; (* OPEN | ANSWERED | WITHDRAWN *)
  q_response        : string option;
  q_responder       : string option;
  q_version         : int;
}

type action_state = {
  a_aid           : string;
  a_description   : string;
  a_owner         : string option;
  a_due_time_utc  : string option;
  a_origin_window : string option;
  a_status        : string; (* PROPOSED | ACCEPTED | REJECTED | DONE *)
  a_version       : int;
}

(* winner bookkeeping for the §8.2 conflict rule *)
type reg_winner = { w_version : int; w_editor : string; w_entry_id : string }

let wins incoming current =
  if incoming.w_version <> current.w_version
  then incoming.w_version > current.w_version
  else incoming.w_editor < current.w_editor

let content_str ?(default = "") (content : json_val) (key : string) : string =
  match obj_get content key with
  | Some (JStr s) -> s
  | Some (JInt i) -> string_of_int i
  | Some (JBool b) -> if b then "true" else "false"
  | _ -> default

let content_str_opt (content : json_val) (key : string) : string option =
  match obj_get content key with
  | Some (JStr s) -> Some s
  | Some (JInt i) -> Some (string_of_int i)
  | _ -> None

(* Reduce question register state from log entries (§9.4). Pure: identical
   entry sets (in any input order) produce identical state.
   Returns (by_id, superseded entryIds). *)
let reduce_questions (entries : json_val list)
    : (string * question_state) list * string list =
  let by_id = ref [] and winners = ref [] and superseded = ref [] in
  List.iter
    (fun e ->
      let content = match obj_get e "content" with Some c -> c | None -> JObj [] in
      let entry_id = get_str e "entryId" in
      let node_id = get_str e "nodeId" in
      match get_str e "type" with
      | "question" ->
        let qid = entry_id in
        if List.mem_assoc qid !by_id then superseded := !superseded @ [entry_id]
        else begin
          let state = {
            q_qid = qid;
            q_text = content_str content "text";
            q_submitter = node_id;
            q_urgency = content_str_opt content "urgency";
            q_intended_window = content_str_opt content "intendedWindow";
            q_status = "OPEN";
            q_response = None;
            q_responder = None;
            q_version = 1;
          } in
          by_id := !by_id @ [(qid, state)];
          winners := (qid, { w_version = 1; w_editor = node_id; w_entry_id = entry_id })
                     :: List.remove_assoc qid !winners
        end
      | "question_response" ->
        let qid = content_str content "qid" in
        (match List.assoc_opt qid !by_id with
         | None -> superseded := !superseded @ [entry_id]
         | Some q ->
           let version =
             match obj_get content "version" with
             | Some (JInt i) -> i
             | _ -> q.q_version + 1
           in
           let incoming =
             { w_version = version; w_editor = node_id; w_entry_id = entry_id }
           in
           let current = List.assoc_opt qid !winners in
           (match current with
            | Some cur when not (wins incoming cur) ->
              superseded := !superseded @ [entry_id]
            | _ ->
              (match current with
               | Some cur when cur.w_entry_id <> q.q_qid ->
                 superseded := !superseded @ [cur.w_entry_id]
               | _ -> ());
              let status =
                if content_str content "status" = "WITHDRAWN"
                then "WITHDRAWN" else "ANSWERED"
              in
              let state = { q with
                q_status = status;
                q_response =
                  (match content_str_opt content "response" with
                   | Some r -> Some r
                   | None -> q.q_response);
                q_responder = Some node_id;
                q_version = version;
              } in
              by_id :=
                List.map (fun (k, v) -> if k = qid then (k, state) else (k, v)) !by_id;
              winners := (qid, incoming) :: List.remove_assoc qid !winners))
      | _ -> ())
    (order_entries entries);
  (!by_id, !superseded)

let action_statuses = ["PROPOSED"; "ACCEPTED"; "REJECTED"; "DONE"]

(* Reduce action register state from log entries (§10.2). *)
let reduce_actions (entries : json_val list)
    : (string * action_state) list * string list =
  let by_id = ref [] and winners = ref [] and superseded = ref [] in
  List.iter
    (fun e ->
      let content = match obj_get e "content" with Some c -> c | None -> JObj [] in
      let entry_id = get_str e "entryId" in
      let node_id = get_str e "nodeId" in
      match get_str e "type" with
      | "action" ->
        let aid = entry_id in
        if List.mem_assoc aid !by_id then superseded := !superseded @ [entry_id]
        else begin
          let state = {
            a_aid = aid;
            a_description = content_str content "description";
            a_owner = content_str_opt content "owner";
            a_due_time_utc = content_str_opt content "dueTimeUTC";
            a_origin_window = content_str_opt content "originWindow";
            a_status = "PROPOSED";
            a_version = 1;
          } in
          by_id := !by_id @ [(aid, state)];
          winners := (aid, { w_version = 1; w_editor = node_id; w_entry_id = entry_id })
                     :: List.remove_assoc aid !winners
        end
      | "action_update" ->
        let aid = content_str content "aid" in
        (match List.assoc_opt aid !by_id with
         | None -> superseded := !superseded @ [entry_id]
         | Some a ->
           let version =
             match obj_get content "version" with
             | Some (JInt i) -> i
             | _ -> a.a_version + 1
           in
           let incoming =
             { w_version = version; w_editor = node_id; w_entry_id = entry_id }
           in
           let current = List.assoc_opt aid !winners in
           (match current with
            | Some cur when not (wins incoming cur) ->
              superseded := !superseded @ [entry_id]
            | _ ->
              (match current with
               | Some cur when cur.w_entry_id <> a.a_aid ->
                 superseded := !superseded @ [cur.w_entry_id]
               | _ -> ());
              let status =
                let s = content_str content "status" in
                if List.mem s action_statuses then s else a.a_status
              in
              let state = { a with
                a_status = status;
                a_description =
                  (match content_str_opt content "description" with
                   | Some d -> d | None -> a.a_description);
                a_owner =
                  (match content_str_opt content "owner" with
                   | Some o -> Some o | None -> a.a_owner);
                a_due_time_utc =
                  (match content_str_opt content "dueTimeUTC" with
                   | Some d -> Some d | None -> a.a_due_time_utc);
                a_version = version;
              } in
              by_id :=
                List.map (fun (k, v) -> if k = aid then (k, state) else (k, v)) !by_id;
              winners := (aid, incoming) :: List.remove_assoc aid !winners))
      | _ -> ())
    (order_entries entries);
  (!by_id, !superseded)

(* ---- Merkle entries root (RFC 9162-style, mirrors merkle.ts) ----
   Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01 || l || r);
   empty root: 64 hex zeros. *)

let rec merkle_root_of (leaves : string list) : string =
  match leaves with
  | [] -> String.make 32 '\x00'
  | [leaf] -> leaf
  | _ ->
    let n = List.length leaves in
    let mid = ref 1 in
    while !mid * 2 <= n - 1 do mid := !mid * 2 done;
    let rec split i acc = function
      | tl when i = !mid -> (List.rev acc, tl)
      | x :: tl -> split (i + 1) (x :: acc) tl
      | [] -> (List.rev acc, [])
    in
    let (left, right) = split 0 [] leaves in
    sha256 ("\x01" ^ merkle_root_of left ^ merkle_root_of right)

(* Merkle audit-log root (hex) over the ordered entries. *)
let entries_root (entries : json_val list) : string =
  order_entries entries
  |> List.map (fun e -> sha256 ("\x00" ^ canonical_json e))
  |> merkle_root_of
  |> hex_of_string

(* ---- 5. CBOR (RFC 8949 deterministic subset) + COSE_Sign1 (RFC 9052) ---- *)

type cbor =
  | CInt of int
  | CBytes of string
  | CText of string
  | CArr of cbor list
  | CMap of (cbor * cbor) list
  | CTag of int * cbor
  | CBool of bool
  | CNull

exception Cbor_error of string

let cbor_head (major : int) (arg : int) : string =
  if arg < 0 then raise (Cbor_error "negative length")
  else if arg < 24 then String.make 1 (Char.chr ((major lsl 5) lor arg))
  else if arg < 0x100 then
    Printf.sprintf "%c%c" (Char.chr ((major lsl 5) lor 24)) (Char.chr arg)
  else if arg < 0x10000 then
    Printf.sprintf "%c%c%c" (Char.chr ((major lsl 5) lor 25))
      (Char.chr (arg lsr 8)) (Char.chr (arg land 0xff))
  else if arg < 0x100000000 then
    Printf.sprintf "%c%c%c%c%c" (Char.chr ((major lsl 5) lor 26))
      (Char.chr ((arg lsr 24) land 0xff)) (Char.chr ((arg lsr 16) land 0xff))
      (Char.chr ((arg lsr 8) land 0xff)) (Char.chr (arg land 0xff))
  else raise (Cbor_error "length too large")

(* Encode a value to deterministic CBOR bytes (RFC 8949 §4.2.1: definite
   lengths, shortest heads, map keys sorted bytewise by encoded form). *)
let rec cbor_encode (v : cbor) : string =
  match v with
  | CNull -> "\xf6"
  | CBool true -> "\xf5"
  | CBool false -> "\xf4"
  | CInt i -> if i >= 0 then cbor_head 0 i else cbor_head 1 (-i - 1)
  | CBytes b -> cbor_head 2 (String.length b) ^ b
  | CText t -> cbor_head 3 (String.length t) ^ t
  | CArr items ->
    cbor_head 4 (List.length items)
    ^ String.concat "" (List.map cbor_encode items)
  | CMap kvs ->
    let encoded = List.map (fun (k, v2) -> (cbor_encode k, cbor_encode v2)) kvs in
    let sorted = List.sort (fun (a, _) (b, _) -> compare a b) encoded in
    cbor_head 5 (List.length kvs)
    ^ String.concat "" (List.map (fun (k, v2) -> k ^ v2) sorted)
  | CTag (t, v2) -> cbor_head 6 t ^ cbor_encode v2

(* Decode deterministic CBOR bytes. Rejects floats, indefinite lengths,
   truncation, and trailing bytes. *)
let cbor_decode (data : string) : cbor =
  let n = String.length data in
  let pos = ref 0 in
  let byte () =
    if !pos >= n then raise (Cbor_error "truncated");
    let b = Char.code data.[!pos] in
    incr pos;
    b
  in
  let take len =
    if !pos + len > n then raise (Cbor_error "truncated");
    let s = String.sub data !pos len in
    pos := !pos + len;
    s
  in
  let read_arg info =
    if info < 24 then info
    else if info = 24 then byte ()
    else if info = 25 then let a = byte () in (a lsl 8) lor byte ()
    else if info = 26 then
      let a = byte () in let b = byte () in let c = byte () in
      (a lsl 24) lor (b lsl 16) lor (c lsl 8) lor byte ()
    else if info = 27 then begin
      let v = ref 0 in
      for _ = 1 to 8 do v := (!v lsl 8) lor byte () done;
      !v
    end
    else raise (Cbor_error "indefinite lengths not supported")
  in
  let rec item () =
    let initial = byte () in
    let major = initial lsr 5 and info = initial land 0x1f in
    if major = 7 then begin
      match info with
      | 20 -> CBool false
      | 21 -> CBool true
      | 22 -> CNull
      | _ -> raise (Cbor_error "unsupported simple/float value")
    end
    else begin
      let arg = read_arg info in
      match major with
      | 0 -> CInt arg
      | 1 -> CInt (-arg - 1)
      | 2 -> CBytes (take arg)
      | 3 -> CText (take arg)
      | 4 ->
        let items = ref [] in
        for _ = 1 to arg do items := item () :: !items done;
        CArr (List.rev !items)
      | 5 ->
        let kvs = ref [] in
        for _ = 1 to arg do
          let k = item () in
          let v = item () in
          kvs := (k, v) :: !kvs
        done;
        CMap (List.rev !kvs)
      | 6 -> CTag (arg, item ())
      | _ -> raise (Cbor_error "unsupported major type")
    end
  in
  let v = item () in
  if !pos <> n then raise (Cbor_error "trailing bytes");
  v

(* ---- COSE_Sign1 (tag 18, alg -19 = Ed25519 per RFC 9864) ---- *)

let cose_sign1_tag = 18
let cose_alg_ed25519 = -19

let cose_sig_structure (protected_bytes : string) (payload : string) : string =
  cbor_encode (CArr [CText "Signature1"; CBytes protected_bytes;
                     CBytes ""; CBytes payload])

(* Sign a plan as a real CBOR COSE_Sign1 (tag 18); kid (label 4) is the first
   16 bytes of SHA-256(raw public key). Returns base64url CBOR bytes. *)
let sign_plan_cose (plan : json_val) (seed : string) : string =
  let protected_bytes = cbor_encode (CMap [(CInt 1, CInt cose_alg_ed25519)]) in
  let payload = canonical_json plan in
  let sg = Ed25519.sign (cose_sig_structure protected_bytes payload) seed in
  let kid = String.sub (sha256 (Ed25519.pubkey_of_seed seed)) 0 16 in
  b64u_encode
    (cbor_encode
       (CTag (cose_sign1_tag,
              CArr [CBytes protected_bytes;
                    CMap [(CInt 4, CBytes kid)];
                    CBytes payload;
                    CBytes sg])))

(* Verify a CBOR COSE_Sign1 plan envelope (base64url) against the key cache.
   Rejects non-Ed25519 algorithms (including the deprecated -8) and payloads
   that do not match the accompanying plan. *)
let verify_plan_cose ?(plan : json_val option) (cose_b64 : string)
    (key_cache : (string * Security.nik) list) : bool * string =
  let decoded =
    try Some (cbor_decode (b64u_decode cose_b64)) with _ -> None
  in
  match decoded with
  | None -> (false, "cbor_decode_failed")
  | Some (CTag (t, _)) when t <> cose_sign1_tag -> (false, "not_cose_sign1")
  | Some (CTag (_, CArr [CBytes protected_bytes; CMap unprotected;
                         CBytes payload; CBytes signature])) ->
    let protected_map =
      try (match cbor_decode protected_bytes with
           | CMap kvs -> Some kvs
           | _ -> None)
      with _ -> None
    in
    (match protected_map with
     | None -> (false, "protected_decode_failed")
     | Some pkvs ->
       if List.assoc_opt (CInt 1) pkvs <> Some (CInt cose_alg_ed25519) then
         (false, "unsupported_alg")
       else begin
         let kid =
           match List.assoc_opt (CInt 4) unprotected with
           | Some (CBytes k) -> b64u_encode k
           | Some (CText k) -> k
           | _ -> ""
         in
         if kid = "" then (false, "missing_kid")
         else begin
           let signer =
             match List.assoc_opt kid key_cache with
             | Some nik -> Some nik
             | None ->
               List.fold_left
                 (fun acc (_, nik) ->
                   match acc with
                   | Some _ -> acc
                   | None ->
                     if String.length nik.Security.node_id >= String.length kid
                        && String.sub nik.Security.node_id 0 (String.length kid) = kid
                     then Some nik else None)
                 None key_cache
           in
           match signer with
           | None -> (false, "key_not_in_cache")
           | Some nik ->
             if Security.is_nik_expired nik then (false, "key_expired")
             else if not (Ed25519.verify
                            (cose_sig_structure protected_bytes payload)
                            signature nik.Security.pub_raw)
             then (false, "signature_invalid")
             else
               (match plan with
                | Some p when payload <> canonical_json p -> (false, "payload_mismatch")
                | _ -> (true, "ok"))
         end
       end)
  | Some (CTag (_, _)) -> (false, "malformed_cose_sign1")
  | Some _ -> (false, "not_cose_sign1")
