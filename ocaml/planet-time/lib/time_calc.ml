(* time_calc.ml — Planet time calculations for the Interplanetary Time Library
   Story 18.18 — OCaml port of planet-time
   Exact port of planet-time.js / libinterplanet.c time functions. *)

(* ── Planet data helpers ─────────────────────────────────────────────────── *)

(* Map body index to planet data array index (Moon=8 -> Earth=2) *)
let pdata_idx (body : int) : int =
  if body = 8 then 2 else body

(* ── Solar day length ────────────────────────────────────────────────────── *)

(* Solar day length in seconds for a body *)
let solar_day_seconds ~(body : int) : float =
  let idx = pdata_idx body in
  Constants.planets.(idx).Constants.solar_day_ms /. 1000.0

(* ── Local solar time ────────────────────────────────────────────────────── *)

(* Local solar time in seconds since midnight for a body,
   given Julian Day and surface longitude in degrees. *)
let local_solar_time ~(body : int) ~(jd : float) ~(longitude : float) : float =
  let utc_ms = (jd -. Constants.unix_epoch_jd) *. 86400000.0 in
  let idx    = pdata_idx body in
  let pl     = Constants.planets.(idx) in
  (* timezone offset from longitude: longitude/360 * solar_day_ms *)
  let tz_ms = longitude /. 360.0 *. pl.Constants.solar_day_ms in
  let elapsed_ms = utc_ms -. pl.Constants.epoch_ms +. tz_ms in
  let total_days = elapsed_ms /. pl.Constants.solar_day_ms in
  let day_frac   = total_days -. floor total_days in
  day_frac *. pl.Constants.solar_day_ms /. 1000.0

(* ── Sol number ──────────────────────────────────────────────────────────── *)

(* Fractional sol/day number since planet epoch *)
let sol_number ~(body : int) ~(jd : float) : float =
  let utc_ms = (jd -. Constants.unix_epoch_jd) *. 86400000.0 in
  let idx    = pdata_idx body in
  let pl     = Constants.planets.(idx) in
  let elapsed_ms = utc_ms -. pl.Constants.epoch_ms in
  elapsed_ms /. pl.Constants.solar_day_ms

(* ── Planet time record ──────────────────────────────────────────────────── *)

type planet_time = {
  body                      : int;
  jd                        : float;
  sol                       : float;
  local_time_sec            : float;
  day_length_sec            : float;
  light_travel_from_earth_sec : float;
}

(* Compute planet_time record for a body given unix_ms (float) *)
let planet_time ~(body : int) ~(unix_ms : float) : planet_time =
  let jd_val = Orbital.jde unix_ms in
  let sol_val = sol_number ~body ~jd:jd_val in
  let lst = local_solar_time ~body ~jd:jd_val ~longitude:0.0 in
  let day_s = solar_day_seconds ~body in
  (* Light travel from Earth (body=2); Earth itself returns 0 *)
  let lt =
    if body = 2 || body = 8 then 0.0
    else Orbital.light_travel_time_ms ~body1:2 ~body2:body ~utc_ms:unix_ms
  in
  { body; jd = jd_val; sol = sol_val; local_time_sec = lst;
    day_length_sec = day_s; light_travel_from_earth_sec = lt }

(* ── Full planet time (for fixture validation) ───────────────────────────── *)

type full_planet_time = {
  hour            : int;
  minute          : int;
  second          : int;
  local_hour      : float;
  day_fraction    : float;
  day_number      : int;
  day_in_year     : int;
  year_number     : int;
  period_in_week  : int;
  is_work_period  : bool;
  is_work_hour    : bool;
  time_str        : string;
  time_str_full   : string;
  sol_in_year     : int option;
  sols_per_year   : int option;
  zone_id         : string option;
}

(* Zone prefix table: body index → prefix string (Earth=2, Moon=8 are absent) *)
let zone_prefix_of_body (body : int) : string option =
  match body with
  | 0 -> Some "MMT"  (* Mercury *)
  | 1 -> Some "VMT"  (* Venus   *)
  | 3 -> Some "AMT"  (* Mars    *)
  | 4 -> Some "JMT"  (* Jupiter *)
  | 5 -> Some "SMT"  (* Saturn  *)
  | 6 -> Some "UMT"  (* Uranus  *)
  | 7 -> Some "NMT"  (* Neptune *)
  | 8 -> Some "LMT"  (* Moon    *)
  | _ -> None        (* Earth (2) and unknown *)

let get_planet_time ~(body : int) ~(utc_ms : float) : full_planet_time =
  let idx = pdata_idx body in
  let pl  = Constants.planets.(idx) in
  let elapsed_ms  = utc_ms -. pl.Constants.epoch_ms in
  let total_days  = elapsed_ms /. pl.Constants.solar_day_ms in
  let day_number  = int_of_float (floor total_days) in
  let day_frac    = total_days -. floor total_days in
  let local_hour  = day_frac *. 24.0 in
  let h = int_of_float (floor local_hour) in
  let m = int_of_float (floor ((local_hour -. float_of_int h) *. 60.0)) in
  let s = int_of_float (floor (((local_hour -. float_of_int h) *. 60.0
                                 -. float_of_int m) *. 60.0)) in
  (* Mercury/Venus use Earth-clock scheduling: UTC day-of-week + UTC hour *)
  let (piw, is_work_period, is_work_hour) =
    if pl.Constants.earth_clock_sched then begin
      (* dow = ((floor(utc_ms / 86400000) % 7) + 3) % 7, Mon=0..Sun=6 *)
      let utc_day_int = int_of_float (floor (utc_ms /. 86400000.0)) in
      let dow = ((utc_day_int mod 7) + 3 + 7) mod 7 in
      let is_wp = dow < pl.Constants.work_periods_per_week in
      let ms_of_day = int_of_float utc_ms - utc_day_int * 86400000 in
      let utc_h = ms_of_day / 3600000 in
      let is_wh = is_wp
                  && utc_h >= pl.Constants.work_hours_start
                  && utc_h < pl.Constants.work_hours_end in
      (dow, is_wp, is_wh)
    end else begin
      let total_periods = total_days /. pl.Constants.days_per_period in
      let period_int    = int_of_float (floor total_periods) in
      let ppw           = pl.Constants.periods_per_week in
      let piw           = ((period_int mod ppw) + ppw) mod ppw in
      let is_wp = piw < pl.Constants.work_periods_per_week in
      let is_wh = is_wp
                  && local_hour >= float_of_int pl.Constants.work_hours_start
                  && local_hour < float_of_int pl.Constants.work_hours_end in
      (piw, is_wp, is_wh)
    end
  in
  let year_len_days = pl.Constants.sidereal_yr_ms /. pl.Constants.solar_day_ms in
  let year_number   = int_of_float (floor (total_days /. year_len_days)) in
  let day_in_year_f = total_days -. float_of_int year_number *. year_len_days in
  let day_in_year   = int_of_float (floor day_in_year_f) in
  let sol_in_year, sols_per_year =
    if idx = 3 (* Mars *) then begin
      let spy_f = Constants.planets.(3).Constants.sidereal_yr_ms
                  /. Constants.planets.(3).Constants.solar_day_ms in
      (Some day_in_year, Some (int_of_float (floor (spy_f +. 0.5))))
    end else (None, None)
  in
  let zone_id =
    match zone_prefix_of_body body with
    | None        -> None
    | Some prefix -> Some (prefix ^ "+0")
  in
  { hour = h; minute = m; second = s;
    local_hour; day_fraction = day_frac;
    day_number; day_in_year; year_number;
    period_in_week = piw; is_work_period; is_work_hour;
    time_str      = Printf.sprintf "%02d:%02d" h m;
    time_str_full = Printf.sprintf "%02d:%02d:%02d" h m s;
    sol_in_year; sols_per_year; zone_id }
