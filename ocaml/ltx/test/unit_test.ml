(* unit_test.ml — LTX OCaml library unit tests (Story 64.1) *)

let passed = ref 0
let failed = ref 0

let check label got expected =
  if got = expected then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s\n  got:      %S\n  expected: %S\n%!" label got expected
  end

let check_bool label got expected =
  check label (string_of_bool got) (string_of_bool expected)

let check_int label got expected =
  check label (string_of_int got) (string_of_int expected)

let check_float label got expected delta =
  if abs_float (got -. expected) <= delta then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s\n  got:      %f\n  expected: %f ± %f\n%!" label got expected delta
  end

let check_contains label haystack needle =
  let hlen = String.length haystack in
  let nlen = String.length needle in
  let found =
    if nlen = 0 then true
    else if hlen < nlen then false
    else begin
      let f = ref false in
      for i = 0 to hlen - nlen do
        if not !f && String.sub haystack i nlen = needle then f := true
      done; !f
    end
  in
  if found then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s — expected to contain %S\n%!" label needle
  end

let starts_with s prefix =
  let sl = String.length s and pl = String.length prefix in
  sl >= pl && String.sub s 0 pl = prefix

(* ── Helpers ─────────────────────────────────────────────────────────────── *)

let make_node id name role delay loc : Models.ltx_node =
  { Models.id; name; role; delay; location = loc }

let make_seg t q : Models.ltx_segment_template =
  { Models.seg_type = t; q }

(* Reference plan matching conformance vector v001 *)
let v001_plan =
  Interplanet_ltx.create_plan
    ~title:"Test Meeting Alpha"
    ~start:"2040-01-15T14:00:00Z"
    ~quantum:5
    ~mode:"LTX"
    ~host_name:"Earth HQ"
    ~host_location:"earth"
    ~remote_name:"Mars Base"
    ~remote_location:"mars"
    ~delay:1240
    ~segments:[
      make_seg "TX" 3; make_seg "RX" 1; make_seg "TX" 2;
      make_seg "RX" 1; make_seg "BUFFER" 2;
    ]
    ()

(* ── Section 1: Constants ────────────────────────────────────────────────── *)

let () =
  check     "version = 1.0.0"           Constants.version          "1.0.0";
  check_int "default_quantum = 3"       Constants.default_quantum  3;
  check_contains "api_base contains interplanet.live"
                  Constants.default_api_base "interplanet.live";
  check_int "default_segments count = 7"
    (List.length Constants.default_segments) 7;
  check "first segment = PLAN_CONFIRM"
    (List.hd Constants.default_segments).Constants.seg_type "PLAN_CONFIRM";
  check "last segment = BUFFER"
    (List.nth Constants.default_segments 6).Constants.seg_type "BUFFER";
  check_int "default_segments total quanta = 13"
    (List.fold_left (fun a (s : Constants.segment_template) -> a + s.q) 0 Constants.default_segments) 13

(* ── Section 2: format_hms ───────────────────────────────────────────────── *)

let () =
  check     "format_hms 0"         (Interplanet_ltx.format_hms 0)    "00:00";
  check     "format_hms 59"        (Interplanet_ltx.format_hms 59)   "00:59";
  check     "format_hms 60"        (Interplanet_ltx.format_hms 60)   "01:00";
  check     "format_hms 90"        (Interplanet_ltx.format_hms 90)   "01:30";
  check     "format_hms 3600"      (Interplanet_ltx.format_hms 3600) "01:00:00";
  check     "format_hms 3661"      (Interplanet_ltx.format_hms 3661) "01:01:01";
  check     "format_hms 7322"      (Interplanet_ltx.format_hms 7322) "02:02:02";
  check     "format_hms neg clamp" (Interplanet_ltx.format_hms (-5)) "00:00"

(* ── Section 3: create_plan defaults ─────────────────────────────────────── *)

let default_plan = Interplanet_ltx.create_plan ()

let () =
  check_int "default plan v = 2"         default_plan.Models.v       2;
  check     "default plan title"         default_plan.Models.title   "LTX Session";
  check_int "default plan quantum = 3"   default_plan.Models.quantum 3;
  check     "default plan mode = LTX"    default_plan.Models.mode    "LTX";
  check_int "default plan nodes = 2"
    (List.length default_plan.Models.nodes) 2;
  check     "default host name"
    (List.hd default_plan.Models.nodes).Models.name "Earth HQ";
  check     "default host role"
    (List.hd default_plan.Models.nodes).Models.role "HOST";
  check     "default remote location"
    (List.nth default_plan.Models.nodes 1).Models.location "mars"

(* ── Section 4: create_plan custom params ────────────────────────────────── *)

let custom_plan =
  Interplanet_ltx.create_plan
    ~title:"My Meeting"
    ~quantum:10
    ~host_name:"Lunar Station"
    ~host_location:"moon"
    ~remote_name:"Europa Base"
    ~remote_location:"moon"
    ~delay:2400
    ()

let () =
  check     "custom title"          custom_plan.Models.title    "My Meeting";
  check_int "custom quantum = 10"   custom_plan.Models.quantum  10;
  check     "custom host name"
    (List.hd custom_plan.Models.nodes).Models.name "Lunar Station";
  check     "custom remote name"
    (List.nth custom_plan.Models.nodes 1).Models.name "Europa Base";
  check     "custom remote location"
    (List.nth custom_plan.Models.nodes 1).Models.location "moon";
  check_int "custom delay"
    (List.nth custom_plan.Models.nodes 1).Models.delay 2400;
  check_int "custom default segments = 7"
    (List.length custom_plan.Models.segments) 7

(* ── Section 5: upgrade_config ──────────────────────────────────────────── *)

let v1_plan : Models.ltx_plan =
  { Models.v = 1; title = "Old Meeting"; start = "2040-06-01T10:00:00Z"
  ; quantum = 3; mode = "LTX"; nodes = []; segments = [] }

let upgraded = Interplanet_ltx.upgrade_config v1_plan

let () =
  check_int "upgrade v1 → v=2"    upgraded.Models.v              2;
  check_int "upgrade adds 2 nodes" (List.length upgraded.Models.nodes) 2;
  check     "upgraded host role"   (List.hd upgraded.Models.nodes).Models.role "HOST";
  check     "upgraded part role"
    (List.nth upgraded.Models.nodes 1).Models.role "PARTICIPANT";
  check_int "upgrade_config v2 unchanged v"
    (Interplanet_ltx.upgrade_config v001_plan).Models.v 2;
  check_int "upgrade_config idempotent nodes"
    (List.length (Interplanet_ltx.upgrade_config v001_plan).Models.nodes)
    (List.length v001_plan.Models.nodes)

(* ── Section 6: total_min ────────────────────────────────────────────────── *)

let () =
  check_int "default plan total_min = 39"   (Interplanet_ltx.total_min default_plan) 39;
  check_int "v001 plan total_min = 45"      (Interplanet_ltx.total_min v001_plan)    45;
  check_int "custom plan total_min = 130"   (Interplanet_ltx.total_min custom_plan)  130;
  let q1_plan = Interplanet_ltx.create_plan ~quantum:1 () in
  check_int "quantum=1 total_min = 13"    (Interplanet_ltx.total_min q1_plan)       13;
  let q5_plan = Interplanet_ltx.create_plan ~quantum:5 () in
  check_int "quantum=5 total_min = 65"    (Interplanet_ltx.total_min q5_plan)       65;
  let single_plan = Interplanet_ltx.create_plan
    ~segments:[make_seg "TX" 2] ~quantum:3 () in
  check_int "single-seg total_min = 6"    (Interplanet_ltx.total_min single_plan)   6

(* ── Section 7: compute_segments ────────────────────────────────────────── *)

let segs_v001 = Interplanet_ltx.compute_segments v001_plan

let () =
  check_int "v001 segment count = 5"  (List.length segs_v001) 5;
  check_int "default segment count = 7"
    (List.length (Interplanet_ltx.compute_segments default_plan)) 7;
  check "first seg type = TX"
    (List.hd segs_v001).Models.seg_type "TX";
  check "first seg start = 2040-01-15T14:00:00Z"
    (List.hd segs_v001).Models.start_iso "2040-01-15T14:00:00Z";
  check "first seg end = 2040-01-15T14:15:00Z"
    (List.hd segs_v001).Models.end_iso "2040-01-15T14:15:00Z";
  check_int "first seg dur_min = 15"
    (List.hd segs_v001).Models.dur_min 15;
  check "second seg start = 2040-01-15T14:15:00Z"
    (List.nth segs_v001 1).Models.start_iso "2040-01-15T14:15:00Z";
  check "last seg end = 2040-01-15T14:45:00Z"
    (List.nth segs_v001 4).Models.end_iso "2040-01-15T14:45:00Z"

(* ── Section 8: make_plan_id ─────────────────────────────────────────────── *)

let plan_id_v001  = Interplanet_ltx.make_plan_id v001_plan
let plan_id_def   = Interplanet_ltx.make_plan_id default_plan

let () =
  check_bool "plan_id starts with LTX-"
    (starts_with plan_id_v001 "LTX-") true;
  check_contains "plan_id contains date 20400115" plan_id_v001 "20400115";
  check_contains "plan_id contains MARS"          plan_id_v001 "MARS";
  check_contains "plan_id contains v2"            plan_id_v001 "v2";
  check_contains "plan_id golden hash 9844a312"   plan_id_v001 "9844a312";
  check_bool "default plan_id starts with LTX-"
    (starts_with plan_id_def "LTX-") true;
  check_bool "different plans → different IDs"
    (plan_id_v001 <> plan_id_def) true;
  check_contains "plan_id has -v2- separator"    plan_id_v001 "-v2-"

(* ── Section 9: encode_hash / decode_hash ───────────────────────────────── *)

let enc = Interplanet_ltx.encode_hash v001_plan
let dec = Interplanet_ltx.decode_hash enc

let () =
  check_bool "encode_hash starts with #l="
    (starts_with enc "#l=") true;
  check_bool "decode_hash returns Some" (dec <> None) true;
  (match dec with
   | None   ->
     check "decoded title"    "" "Test Meeting Alpha";
     check "decoded mode"     "" "LTX";
     check_int "decoded quantum" 0 5
   | Some d ->
     check     "decoded title"    d.Models.title   "Test Meeting Alpha";
     check     "decoded mode"     d.Models.mode    "LTX";
     check_int "decoded quantum"  d.Models.quantum 5;
     check_int "decoded node count"
       (List.length d.Models.nodes) (List.length v001_plan.Models.nodes);
     check_int "decoded segment count"
       (List.length d.Models.segments) (List.length v001_plan.Models.segments);
     let re_enc = Interplanet_ltx.encode_hash d in
     check "encode→decode→encode is stable" re_enc enc
  );
  check_bool "decode_hash invalid returns None"
    (Interplanet_ltx.decode_hash "not-a-hash" = None) true

(* ── Section 10: build_node_urls ─────────────────────────────────────────── *)

let urls = Interplanet_ltx.build_node_urls v001_plan
             "https://interplanet.live/meet"

let () =
  check_int  "node_urls count = 2"  (List.length urls) 2;
  check      "first url node_id"    (List.hd urls).Models.node_id "N0";
  check      "second url node_id"   (List.nth urls 1).Models.node_id "N1";
  check_contains "first url has node=N0"  (List.hd urls).Models.url "node=N0";
  check_contains "second url has node=N1" (List.nth urls 1).Models.url "node=N1";
  check_contains "url has #l="           (List.hd urls).Models.url "#l="

(* ── Section 11: build_delay_matrix ─────────────────────────────────────── *)

let matrix = Interplanet_ltx.build_delay_matrix v001_plan

let three_node_plan =
  Interplanet_ltx.create_plan
    ~title:"3-Node Test"
    ~start:"2040-03-01T09:00:00Z"
    ~nodes:[
      make_node "N0" "Earth HQ"   "HOST"        0    "earth";
      make_node "N1" "Mars Base"  "PARTICIPANT" 1200 "mars";
      make_node "N2" "Lunar Base" "PARTICIPANT" 120  "moon";
    ]
    ()

let () =
  check_int "delay matrix v001 has 2 entries"  (List.length matrix) 2;
  check     "first entry from_id = N0"
    (List.hd matrix).Models.from_id "N0";
  check     "first entry to_id = N1"
    (List.hd matrix).Models.to_id "N1";
  check_int "N0→N1 delay = 1240"
    (List.hd matrix).Models.delay_seconds 1240;
  check     "second entry from_id = N1"
    (List.nth matrix 1).Models.from_id "N1";
  check     "second entry to_id = N0"
    (List.nth matrix 1).Models.to_id "N0";
  check_int "N1→N0 delay = 1240"
    (List.nth matrix 1).Models.delay_seconds 1240;
  check_int "3-node delay matrix has 6 entries"
    (List.length (Interplanet_ltx.build_delay_matrix three_node_plan)) 6

(* ── Section 12: generate_ics ───────────────────────────────────────────── *)

let ics = Interplanet_ltx.generate_ics v001_plan

let () =
  check_contains "ics has BEGIN:VCALENDAR"     ics "BEGIN:VCALENDAR";
  check_contains "ics has END:VCALENDAR"       ics "END:VCALENDAR";
  check_contains "ics has BEGIN:VEVENT"        ics "BEGIN:VEVENT";
  check_contains "ics has LTX-PLANID"          ics "LTX-PLANID";
  check_contains "ics has LTX-QUANTUM:PT5M"    ics "LTX-QUANTUM:PT5M";
  check_contains "ics hash 9844a312"           ics "9844a312";
  check_contains "ics has CRLF"                ics "\r\n";
  check_contains "ics summary"                 ics "SUMMARY:Test Meeting Alpha"

(* ── Section 13: escape_ics_text (Story 26.3) ───────────────────────────── *)

let () =
  check     "escape_ics_text empty"       (Interplanet_ltx.escape_ics_text "")       "";
  check     "escape_ics_text no specials" (Interplanet_ltx.escape_ics_text "hello")  "hello";
  check     "escape_ics_text semicolon"   (Interplanet_ltx.escape_ics_text "a;b")    "a\\;b";
  check     "escape_ics_text comma"       (Interplanet_ltx.escape_ics_text "a,b")    "a\\,b";
  check     "escape_ics_text backslash"   (Interplanet_ltx.escape_ics_text "a\\b")   "a\\\\b";
  check     "escape_ics_text newline"     (Interplanet_ltx.escape_ics_text "a\nb")   "a\\nb";
  let ics_esc = Interplanet_ltx.generate_ics
    (Interplanet_ltx.create_plan
       ~title:"Hello, World; Test"
       ~start:"2024-01-15T14:00:00Z" ()) in
  check_contains "generateIcs SUMMARY escaped" ics_esc "SUMMARY:Hello\\, World\\; Test"

(* ── Section 14: Story 26.4 — protocol hardening ────────────────────────── *)

let () =
  check_int "default_plan_lock_timeout_factor = 2"
    Constants.default_plan_lock_timeout_factor 2;
  check_int "delay_violation_warn_s = 120"
    Constants.delay_violation_warn_s 120;
  check_int "delay_violation_degraded_s = 300"
    Constants.delay_violation_degraded_s 300;
  check_int "session_states length = 5"
    (Array.length Constants.session_states) 5;
  check     "session_states[3] = DEGRADED"
    Constants.session_states.(3) "DEGRADED";
  check     "session_states[0] = INIT"
    Constants.session_states.(0) "INIT";
  check_int "plan_lock_timeout_ms(100) = 200000"
    (Interplanet_ltx.plan_lock_timeout_ms 100) 200000;
  check_int "plan_lock_timeout_ms(0) = 0"
    (Interplanet_ltx.plan_lock_timeout_ms 0) 0;
  check     "check_delay_violation ok (same)"
    (Interplanet_ltx.check_delay_violation 100 100) "ok";
  check     "check_delay_violation ok within 120"
    (Interplanet_ltx.check_delay_violation 100 210) "ok";
  check     "check_delay_violation violation"
    (Interplanet_ltx.check_delay_violation 100 221) "violation";
  check     "check_delay_violation degraded"
    (Interplanet_ltx.check_delay_violation 100 401) "degraded";
  check     "check_delay_violation boundary 120 ok"
    (Interplanet_ltx.check_delay_violation 0 120) "ok";
  check     "check_delay_violation boundary 301 degraded"
    (Interplanet_ltx.check_delay_violation 0 301) "degraded"

(* ── Section 15: compute_segments quantum guard ──────────────────────────── *)

let () =
  let bad_plan = Interplanet_ltx.create_plan ~quantum:0 () in
  let bad_raised = try ignore (Interplanet_ltx.compute_segments bad_plan); false
                   with Invalid_argument _ -> true in
  check_bool "compute_segments quantum=0 raises" bad_raised true;
  let bad_plan2 = Interplanet_ltx.create_plan ~quantum:(-1) () in
  let bad_raised2 = try ignore (Interplanet_ltx.compute_segments bad_plan2); false
                    with Invalid_argument _ -> true in
  check_bool "compute_segments quantum=-1 raises" bad_raised2 true

(* ── Summary ─────────────────────────────────────────────────────────────── *)

let () =
  Printf.printf "%d passed  %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
