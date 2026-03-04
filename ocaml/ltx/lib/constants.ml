(* constants.ml — LTX protocol constants *)

let version = "1.0.0"
let default_quantum = 3  (* minutes per quantum *)
let default_api_base = "https://interplanet.live/api/ltx.php"

type segment_template = { seg_type: string; q: int }

let default_segments = [
  { seg_type = "PLAN_CONFIRM"; q = 2 };
  { seg_type = "TX";           q = 2 };
  { seg_type = "RX";           q = 2 };
  { seg_type = "CAUCUS";       q = 2 };
  { seg_type = "TX";           q = 2 };
  { seg_type = "RX";           q = 2 };
  { seg_type = "BUFFER";       q = 1 };
]

(* Story 26.4 constants *)
let default_plan_lock_timeout_factor = 2
let delay_violation_warn_s = 120
let delay_violation_degraded_s = 300
let session_states = [| "INIT"; "LOCKED"; "RUNNING"; "DEGRADED"; "COMPLETE" |]
