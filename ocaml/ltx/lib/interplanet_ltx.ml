(* interplanet_ltx.ml — LTX (Light-Time eXchange) SDK for OCaml
   Story 64.1 — OCaml port of the LTX SDK
   Requires: unix (standard OCaml distribution) *)

(* ── Protocol constants ──────────────────────────────────────────────────── *)

let version          = Constants.version
let default_quantum  = Constants.default_quantum
let default_api_base = Constants.default_api_base

(* ── Types (re-exported from Models) ─────────────────────────────────────── *)

type ltx_node             = Models.ltx_node
type ltx_segment_template = Models.ltx_segment_template
type ltx_plan             = Models.ltx_plan
type ltx_timed_segment    = Models.ltx_timed_segment
type ltx_node_url         = Models.ltx_node_url
type delay_matrix_entry   = Models.delay_matrix_entry

(* ── Internal utilities ─────────────────────────────────────────────────── *)

let pad2 n = Printf.sprintf "%02d" n

let str_contains haystack needle =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  if nlen = 0 then true
  else if hlen < nlen then false
  else
    let found = ref false in
    for i = 0 to hlen - nlen do
      if not !found && String.sub haystack i nlen = needle then found := true
    done;
    !found

(* Base64url encode *)
let b64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let b64encode (data : string) : string =
  let len = String.length data in
  let buf = Buffer.create ((len + 2) / 3 * 4) in
  let i = ref 0 in
  while !i < len do
    let b0 = Char.code data.[!i] in
    let b1 = if !i + 1 < len then Char.code data.[!i + 1] else 0 in
    let b2 = if !i + 2 < len then Char.code data.[!i + 2] else 0 in
    let n  = (b0 lsl 16) lor (b1 lsl 8) lor b2 in
    Buffer.add_char buf b64_chars.[n lsr 18 land 63];
    Buffer.add_char buf b64_chars.[(n lsr 12) land 63];
    Buffer.add_char buf b64_chars.[(n lsr 6)  land 63];
    Buffer.add_char buf b64_chars.[n land 63];
    i := !i + 3
  done;
  let s = Buffer.contents buf in
  let trimmed = match len mod 3 with
    | 1 -> String.sub s 0 (String.length s - 2)
    | 2 -> String.sub s 0 (String.length s - 1)
    | _ -> s
  in
  String.map (fun c -> match c with '+' -> '-' | '/' -> '_' | x -> x) trimmed

let b64decode_char c = match c with
  | 'A'..'Z' -> Char.code c - 65
  | 'a'..'z' -> Char.code c - 97 + 26
  | '0'..'9' -> Char.code c - 48 + 52
  | '+' | '-' -> 62
  | '/' | '_' -> 63
  | _ -> 0

let b64decode (s : string) : string =
  let len  = String.length s in
  let pad  = (4 - (len mod 4)) mod 4 in
  let padded = s ^ String.make pad '=' in
  let plen = String.length padded in
  let buf  = Buffer.create (plen * 3 / 4 + 1) in
  let i    = ref 0 in
  while !i + 3 < plen + 1 do
    let c0 = b64decode_char padded.[!i] in
    let c1 = b64decode_char padded.[!i + 1] in
    let c2 = b64decode_char padded.[!i + 2] in
    let c3 = b64decode_char padded.[!i + 3] in
    let n  = (c0 lsl 18) lor (c1 lsl 12) lor (c2 lsl 6) lor c3 in
    Buffer.add_char buf (Char.chr ((n lsr 16) land 255));
    if padded.[!i + 2] <> '=' then
      Buffer.add_char buf (Char.chr ((n lsr 8) land 255));
    if padded.[!i + 3] <> '=' then
      Buffer.add_char buf (Char.chr (n land 255));
    i := !i + 4
  done;
  Buffer.contents buf

(* ── JSON serialiser ─────────────────────────────────────────────────────── *)

let json_escape s =
  let buf = Buffer.create (String.length s + 4) in
  String.iter (fun c -> match c with
    | '"'  -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c    -> Buffer.add_char   buf c
  ) s;
  Buffer.contents buf

let json_string s = "\"" ^ json_escape s ^ "\""

let plan_to_json (plan : ltx_plan) : string =
  let open Models in
  let node_to_json n =
    Printf.sprintf "{\"id\":%s,\"name\":%s,\"role\":%s,\"delay\":%d,\"location\":%s}"
      (json_string n.id) (json_string n.name) (json_string n.role)
      n.delay (json_string n.location)
  in
  let seg_to_json (s : Models.ltx_segment_template) =
    Printf.sprintf "{\"type\":%s,\"q\":%d}" (json_string s.seg_type) s.q
  in
  let nodes_json = "[" ^ String.concat "," (List.map node_to_json plan.nodes) ^ "]" in
  let segs_json  = "[" ^ String.concat "," (List.map seg_to_json  plan.segments) ^ "]" in
  Printf.sprintf
    "{\"v\":%d,\"title\":%s,\"start\":%s,\"quantum\":%d,\"mode\":%s,\"nodes\":%s,\"segments\":%s}"
    plan.v (json_string plan.title) (json_string plan.start)
    plan.quantum (json_string plan.mode) nodes_json segs_json

(* ── Minimal JSON parser ─────────────────────────────────────────────────── *)

let find_string json key =
  let pattern = "\"" ^ key ^ "\":\"" in
  let plen = String.length pattern in
  let jlen = String.length json in
  let result = ref "" in
  let i = ref 0 in
  while !i <= jlen - plen do
    if String.sub json !i plen = pattern then begin
      let j   = ref (!i + plen) in
      let buf = Buffer.create 16 in
      let stop = ref false in
      while !j < jlen && not !stop do
        let c = json.[!j] in
        if c = '\\' && !j + 1 < jlen then begin
          Buffer.add_char buf json.[!j + 1]; j := !j + 2
        end else if c = '"' then stop := true
        else begin Buffer.add_char buf c; j := !j + 1 end
      done;
      result := Buffer.contents buf;
      i := jlen (* stop outer loop *)
    end else
      i := !i + 1
  done;
  !result

let find_int json key =
  let pattern = "\"" ^ key ^ "\":" in
  let plen = String.length pattern in
  let jlen = String.length json in
  let result = ref 0 in
  let i = ref 0 in
  while !i <= jlen - plen do
    if String.sub json !i plen = pattern then begin
      let j   = ref (!i + plen) in
      let buf = Buffer.create 4 in
      while !j < jlen && json.[!j] >= '0' && json.[!j] <= '9' do
        Buffer.add_char buf json.[!j]; j := !j + 1
      done;
      result := int_of_string_opt (Buffer.contents buf) |> Option.value ~default:0;
      i := jlen
    end else
      i := !i + 1
  done;
  !result

let find_array json key =
  let pattern = "\"" ^ key ^ "\":[" in
  let plen = String.length pattern in
  let jlen = String.length json in
  let result = ref "[]" in
  let i = ref 0 in
  while !i <= jlen - plen do
    if String.sub json !i plen = pattern then begin
      let start = !i + plen - 1 in
      let depth = ref 1 in
      let j = ref (start + 1) in
      while !j < jlen && !depth > 0 do
        (match json.[!j] with '[' -> incr depth | ']' -> decr depth | _ -> ());
        j := !j + 1
      done;
      result := String.sub json start (!j - start);
      i := jlen
    end else
      i := !i + 1
  done;
  !result

let split_objects arr =
  let inner =
    let len = String.length arr in
    if len >= 2 then String.sub arr 1 (len - 2) else ""
  in
  let objs  = ref [] in
  let depth = ref 0 in
  let start = ref 0 in
  String.iteri (fun i c -> match c with
    | '{' -> if !depth = 0 then start := i; incr depth
    | '}' -> decr depth;
             if !depth = 0 then
               objs := String.sub inner !start (i - !start + 1) :: !objs
    | _   -> ()
  ) inner;
  List.rev !objs

let plan_of_json json =
  try
    let open Models in
    let parse_node j =
      { id = find_string j "id"; name = find_string j "name"
      ; role = find_string j "role"; delay = find_int j "delay"
      ; location = find_string j "location" }
    in
    let parse_seg j : Models.ltx_segment_template = { seg_type = find_string j "type"; q = find_int j "q" } in
    let nodes = List.map parse_node (split_objects (find_array json "nodes")) in
    let segs  = List.map parse_seg  (split_objects (find_array json "segments")) in
    let q     = find_int json "quantum" in
    let start = find_string json "start" in
    if start = "" then None
    else Some { v        = find_int    json "v"
              ; title    = find_string json "title"
              ; start
              ; quantum  = if q = 0 then default_quantum else q
              ; mode     = find_string json "mode"
              ; nodes; segments = segs }
  with _ -> None

(* ── Config management ──────────────────────────────────────────────────── *)

let upgrade_config (plan : ltx_plan) : ltx_plan =
  let open Models in
  if plan.v >= 2 && plan.nodes <> [] then plan
  else
    let rx_name = match List.nth_opt plan.nodes 1 with
      | Some n -> n.name
      | None   -> ""
    in
    let remote_loc =
      let low = String.lowercase_ascii rx_name in
      if str_contains low "mars" then "mars"
      else if str_contains low "moon" then "moon"
      else "earth"
    in
    let nodes =
      if plan.nodes = [] then [
        { id = "N0"; name = "Earth HQ";    role = "HOST";        delay = 0; location = "earth"     };
        { id = "N1"; name = rx_name;       role = "PARTICIPANT"; delay = 0; location = remote_loc  };
      ] else plan.nodes
    in
    { plan with v = 2; nodes }

let create_plan
  ?(title           = "LTX Session")
  ?(start           = "")
  ?(quantum         = default_quantum)
  ?(mode            = "LTX")
  ?(host_name       = "Earth HQ")
  ?(host_location   = "earth")
  ?(remote_name     = "Mars Hab-01")
  ?(remote_location = "mars")
  ?(delay           = 0)
  ?(nodes           = ([] : ltx_node list))
  ?(segments        = ([] : ltx_segment_template list))
  () : ltx_plan =
  let open Models in
  let start_str =
    if start <> "" then start
    else
      let t  = Unix.time () +. 300.0 in
      let tm = Unix.gmtime t in
      Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
        (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday
        tm.tm_hour tm.tm_min tm.tm_sec
  in
  let nodes' = if nodes <> [] then nodes else [
    { id = "N0"; name = host_name;   role = "HOST";        delay = 0;     location = host_location   };
    { id = "N1"; name = remote_name; role = "PARTICIPANT"; delay = delay; location = remote_location };
  ] in
  let segs = if segments <> [] then segments
             else List.map (fun (s : Constants.segment_template) ->
               { Models.seg_type = s.seg_type; q = s.q }) Constants.default_segments in
  { v = 2; title; start = start_str; quantum; mode; nodes = nodes'; segments = segs }

(* ── ISO 8601 ────────────────────────────────────────────────────────────── *)

let parse_iso8601 s =
  (* Compute UTC Unix timestamp directly (Julian Day Number method) without
     mktime, which interprets the struct as local time. *)
  try Scanf.sscanf s "%4d-%2d-%2dT%2d:%2d:%2dZ"
    (fun yr mo dy h m sec ->
      let a = (14 - mo) / 12 in
      let y = yr + 4800 - a in
      let mn = mo + 12 * a - 3 in
      let jdn = dy + (153 * mn + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045 in
      let days = jdn - 2440588 in  (* Unix epoch = JDN 2440588 *)
      float_of_int (days * 86400 + h * 3600 + m * 60 + sec))
  with _ -> 0.0

let format_iso8601 t =
  let tm = Unix.gmtime t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

(* ── Story 26.3: ICS text escaping ──────────────────────────────────────── *)

let escape_ics_text s =
  let buf = Buffer.create (String.length s + 4) in
  String.iter (fun c -> match c with
    | '\\' -> Buffer.add_string buf "\\\\"
    | ';'  -> Buffer.add_string buf "\\;"
    | ','  -> Buffer.add_string buf "\\,"
    | '\n' -> Buffer.add_string buf "\\n"
    | c    -> Buffer.add_char   buf c
  ) s;
  Buffer.contents buf

(* ── Story 26.4: Protocol hardening ─────────────────────────────────────── *)

let plan_lock_timeout_ms delay_seconds =
  int_of_float (float_of_int delay_seconds *. float_of_int Constants.default_plan_lock_timeout_factor *. 1000.0)

let check_delay_violation declared_delay_s measured_delay_s =
  let diff = abs (measured_delay_s - declared_delay_s) in
  if diff > Constants.delay_violation_degraded_s then "degraded"
  else if diff > Constants.delay_violation_warn_s then "violation"
  else "ok"

(* ── Segment computation ─────────────────────────────────────────────────── *)

let compute_segments (plan : ltx_plan) : ltx_timed_segment list =
  let open Models in
  if plan.quantum < 1 then
    invalid_arg (Printf.sprintf "quantum must be >= 1, got %d" plan.quantum);
  let q_sec = float_of_int plan.quantum *. 60.0 in
  let t     = ref (parse_iso8601 plan.start) in
  List.map (fun (s : Models.ltx_segment_template) ->
    let dur = float_of_int s.q *. q_sec in
    let seg : Models.ltx_timed_segment =
              { seg_type  = s.seg_type
              ; q         = s.q
              ; start_iso = format_iso8601 !t
              ; end_iso   = format_iso8601 (!t +. dur)
              ; dur_min   = s.q * plan.quantum } in
    t := !t +. dur;
    seg
  ) plan.segments

let total_min (plan : ltx_plan) : int =
  List.fold_left (fun acc (s : Models.ltx_segment_template) -> acc + s.q * plan.quantum) 0 plan.segments

(* ── Delay matrix ────────────────────────────────────────────────────────── *)

let build_delay_matrix (plan : ltx_plan) : delay_matrix_entry list =
  let open Models in
  let nodes = Array.of_list plan.nodes in
  let n     = Array.length nodes in
  let result = ref [] in
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      if i <> j then begin
        let fn = nodes.(i) and tn = nodes.(j) in
        let d =
          if fn.delay = 0 || i = 0 then tn.delay
          else if tn.delay = 0 || j = 0 then fn.delay
          else fn.delay + tn.delay
        in
        result := { from_id = fn.id; from_name = fn.name
                  ; to_id   = tn.id; to_name   = tn.name
                  ; delay_seconds = d } :: !result
      end
    done
  done;
  List.rev !result

(* ── Plan ID ─────────────────────────────────────────────────────────────── *)

let djb_hash s =
  String.fold_left
    (fun h c -> Int32.logand
      (Int32.add (Int32.mul 31l h) (Int32.of_int (Char.code c)))
      0xFFFFFFFFl)
    0l s

let make_plan_id (plan : ltx_plan) : string =
  let open Models in
  let date =
    String.concat ""
      (String.split_on_char '-' (String.sub plan.start 0 (min 10 (String.length plan.start))))
  in
  let up n = String.map Char.uppercase_ascii (String.map (fun c -> if c = ' ' then '_' else c) n) in
  let host_name = (List.hd plan.nodes).name in
  let host_str =
    let s = up host_name in String.sub s 0 (min 8 (String.length s))
  in
  let node_str =
    match List.tl plan.nodes with
    | [] -> "RX"
    | parts ->
      let joined = String.concat "-"
        (List.map (fun (n : Models.ltx_node) ->
          let s = up n.name in String.sub s 0 (min 4 (String.length s))
        ) parts)
      in
      String.sub joined 0 (min 16 (String.length joined))
  in
  let raw  = plan_to_json plan in
  let hash = djb_hash raw in
  Printf.sprintf "LTX-%s-%s-%s-v2-%08lx" date host_str node_str hash

(* ── Hash encoding ───────────────────────────────────────────────────────── *)

let encode_hash (plan : ltx_plan) : string =
  "#l=" ^ b64encode (plan_to_json plan)

let decode_hash (hash : string) : ltx_plan option =
  let token =
    let s = hash in
    if String.length s > 3 && String.sub s 0 3 = "#l=" then
      String.sub s 3 (String.length s - 3)
    else if String.length s > 2 && String.sub s 0 2 = "l=" then
      String.sub s 2 (String.length s - 2)
    else s
  in
  (try plan_of_json (b64decode token) with _ -> None)

let build_node_urls (plan : ltx_plan) (base_url : string) : ltx_node_url list =
  let hash = "#l=" ^ b64encode (plan_to_json plan) in
  let base = match String.index_opt base_url '#' with
    | Some i -> String.sub base_url 0 i | None -> base_url
  in
  List.map (fun node ->
    Models.{ node_id = node.id; name = node.name; role = node.role
           ; url = Printf.sprintf "%s?node=%s%s" base node.id hash }
  ) plan.nodes

(* ── ICS generation ──────────────────────────────────────────────────────── *)

let to_ics_id name =
  String.map (fun c -> if c = ' ' then '-' else Char.uppercase_ascii c) name

let fmt_dt iso =
  let s = ref "" in
  String.iter (fun c ->
    if c <> '-' && c <> ':' then s := !s ^ String.make 1 c
  ) iso;
  !s

let generate_ics (plan : ltx_plan) : string =
  let open Models in
  let segs    = compute_segments plan in
  let plan_id = make_plan_id plan in
  let nodes   = plan.nodes in
  let parts   = List.filteri (fun i _ -> i > 0) nodes in
  let seg_tpl = String.concat "," (List.map (fun (s : Models.ltx_segment_template) -> s.seg_type) plan.segments) in
  let end_iso = match List.rev segs with hd :: _ -> hd.end_iso | [] -> plan.start in
  let now_str = format_iso8601 (Unix.time ()) in
  let node_lines = List.map (fun (n : ltx_node) ->
    "LTX-NODE:ID=" ^ to_ics_id n.name ^ ";ROLE=" ^ n.role) nodes
  in
  let delay_lines = List.map (fun (p : ltx_node) ->
    let d = p.delay in
    "LTX-DELAY;NODEID=" ^ to_ics_id p.name
    ^ ":ONEWAY-MIN=" ^ string_of_int d
    ^ ";ONEWAY-MAX=" ^ string_of_int (d + 120)
    ^ ";ONEWAY-ASSUMED=" ^ string_of_int d) parts
  in
  let lines =
    [ "BEGIN:VCALENDAR"; "VERSION:2.0"
    ; "PRODID:-//InterPlanet//LTX v1.0//EN"; "CALSCALE:GREGORIAN"; "METHOD:PUBLISH"
    ; "BEGIN:VEVENT"
    ; "UID:" ^ plan_id ^ "@interplanet.live"
    ; "DTSTAMP:" ^ fmt_dt now_str
    ; "DTSTART:" ^ fmt_dt plan.start
    ; "DTEND:" ^ fmt_dt end_iso
    ; "SUMMARY:" ^ escape_ics_text plan.title
    ; "LTX:1"; "LTX-PLANID:" ^ plan_id
    ; "LTX-QUANTUM:PT" ^ string_of_int plan.quantum ^ "M"
    ; "LTX-SEGMENT-TEMPLATE:" ^ seg_tpl
    ; "LTX-MODE:" ^ plan.mode
    ] @ node_lines @ delay_lines @ ["END:VEVENT"; "END:VCALENDAR"]
  in
  String.concat "\r\n" lines

(* ── Format utilities ────────────────────────────────────────────────────── *)

let format_hms sec =
  let sec = max 0 sec in
  let h   = sec / 3600 in
  let m   = (sec mod 3600) / 60 in
  let s   = sec mod 60 in
  if h > 0 then Printf.sprintf "%s:%s:%s" (pad2 h) (pad2 m) (pad2 s)
  else           Printf.sprintf "%s:%s"   (pad2 m) (pad2 s)
