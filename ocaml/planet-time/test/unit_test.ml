(* unit_test.ml — Interplanetary Time Library unit tests (Story 18.18)
   Tests for OCaml planet-time library.
   Includes fixture validation against reference.json (54 entries). *)

let passed = ref 0
let failed = ref 0

let check label got expected =
  if got = expected then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s\n  got:      %S\n  expected: %S\n%!" label got expected
  end

let check_int label got expected =
  check label (string_of_int got) (string_of_int expected)

let check_float label got expected delta =
  if abs_float (got -. expected) <= delta then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL: %s\n  got:      %.10f\n  expected: %.10f ± %.6f\n%!"
      label got expected delta
  end

let check_bool label got expected =
  check label (string_of_bool got) (string_of_bool expected)

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

(* ── Section 1: body_name ────────────────────────────────────────────────── *)

let () =
  check     "body_name 0 = Mercury"  (Interplanet_time.body_name 0) "Mercury";
  check     "body_name 1 = Venus"    (Interplanet_time.body_name 1) "Venus";
  check     "body_name 2 = Earth"    (Interplanet_time.body_name 2) "Earth";
  check     "body_name 3 = Mars"     (Interplanet_time.body_name 3) "Mars";
  check     "body_name 4 = Jupiter"  (Interplanet_time.body_name 4) "Jupiter";
  check     "body_name 5 = Saturn"   (Interplanet_time.body_name 5) "Saturn";
  check     "body_name 6 = Uranus"   (Interplanet_time.body_name 6) "Uranus";
  check     "body_name 7 = Neptune"  (Interplanet_time.body_name 7) "Neptune";
  check     "body_name 8 = Moon"     (Interplanet_time.body_name 8) "Moon";
  check     "body_name 99 = Unknown" (Interplanet_time.body_name 99) "Unknown"

(* ── Section 2: julian_day ───────────────────────────────────────────────── *)

(* J2000.0 = 2000-01-01T12:00:00 UTC = JD 2451545.0 *)
let j2000_jd =
  Interplanet_time.julian_day ~year:2000 ~month:1 ~day:1
    ~hour:12 ~minute:0 ~second:0.0

let () =
  check_float "julian_day J2000"  j2000_jd 2451545.0 0.0001;
  (* 1970-01-01T00:00:00 = JD 2440587.5 *)
  let unix_epoch_jd =
    Interplanet_time.julian_day ~year:1970 ~month:1 ~day:1
      ~hour:0 ~minute:0 ~second:0.0
  in
  check_float "julian_day unix epoch" unix_epoch_jd 2440587.5 0.0001;
  (* 2025-01-01T00:00:00 *)
  let jd_2025 =
    Interplanet_time.julian_day ~year:2025 ~month:1 ~day:1
      ~hour:0 ~minute:0 ~second:0.0
  in
  check_bool  "julian_day 2025 > J2000"  (jd_2025 > j2000_jd) true;
  (* half-day offset *)
  let jd_noon =
    Interplanet_time.julian_day ~year:2000 ~month:1 ~day:1
      ~hour:18 ~minute:0 ~second:0.0
  in
  check_float "julian_day noon +6h" jd_noon (j2000_jd +. 0.25) 0.0001

(* ── Section 3: mean_longitude ───────────────────────────────────────────── *)

let () =
  (* At J2000, mean longitude = L0 for each body *)
  let ml_earth = Interplanet_time.mean_longitude ~body:2 ~jd:j2000_jd in
  check_bool "mean_longitude earth in [0,360)" (ml_earth >= 0.0 && ml_earth < 360.0) true;
  let ml_mars  = Interplanet_time.mean_longitude ~body:3 ~jd:j2000_jd in
  check_bool "mean_longitude mars in [0,360)"  (ml_mars  >= 0.0 && ml_mars  < 360.0) true;
  let ml_merc  = Interplanet_time.mean_longitude ~body:0 ~jd:j2000_jd in
  check_bool "mean_longitude mercury in [0,360)" (ml_merc >= 0.0 && ml_merc < 360.0) true;
  (* Moon maps to Earth's elements *)
  let ml_moon  = Interplanet_time.mean_longitude ~body:8 ~jd:j2000_jd in
  check_float "mean_longitude moon = earth at J2000" ml_moon ml_earth 1e-6

(* ── Section 4: true_anomaly ─────────────────────────────────────────────── *)

let () =
  (* Circular orbit: e=0, M=1.0 → v=1.0 *)
  let v0 = Interplanet_time.true_anomaly ~mean_anomaly:1.0 ~eccentricity:0.0 in
  check_float "true_anomaly e=0 v=M" v0 1.0 1e-10;
  (* Low eccentricity *)
  let v1 = Interplanet_time.true_anomaly ~mean_anomaly:1.0 ~eccentricity:0.01671 in
  check_bool  "true_anomaly e=earth > M for M=1" (v1 > 1.0) true;
  (* High eccentricity (Mercury) *)
  let v2 = Interplanet_time.true_anomaly ~mean_anomaly:1.0 ~eccentricity:0.20564 in
  check_bool  "true_anomaly e=mercury > e=earth" (v2 > v1) true;
  (* At M=0 -> v=0 *)
  let v3 = Interplanet_time.true_anomaly ~mean_anomaly:0.0 ~eccentricity:0.09341 in
  check_float "true_anomaly M=0 -> v=0" v3 0.0 1e-10

(* ── Section 5: ecliptic_longitude ──────────────────────────────────────── *)

let () =
  let el_earth = Interplanet_time.ecliptic_longitude ~body:2 ~jd:j2000_jd in
  check_bool "ecliptic_longitude earth in [0,360)" (el_earth >= 0.0 && el_earth < 360.0) true;
  let el_mars  = Interplanet_time.ecliptic_longitude ~body:3 ~jd:j2000_jd in
  check_bool "ecliptic_longitude mars in [0,360)"  (el_mars  >= 0.0 && el_mars  < 360.0) true;
  let el_moon  = Interplanet_time.ecliptic_longitude ~body:8 ~jd:j2000_jd in
  check_float "ecliptic_longitude moon = earth at J2000" el_moon el_earth 1e-6

(* ── Section 6: heliocentric_pos ─────────────────────────────────────────── *)

let () =
  let (x, y, z) = Interplanet_time.heliocentric_pos ~body:2 ~jd:j2000_jd in
  let r = sqrt (x *. x +. y *. y) in
  check_float "helio_pos earth r ≈ 0.983 AU" r 0.983 0.03;
  check_float "helio_pos earth z = 0" z 0.0 1e-12;
  let (xm, ym, _) = Interplanet_time.heliocentric_pos ~body:3 ~jd:j2000_jd in
  let rm = sqrt (xm *. xm +. ym *. ym) in
  check_bool  "helio_pos mars r > 1 AU"  (rm > 1.0) true;
  check_bool  "helio_pos mars r < 1.7 AU" (rm < 1.7) true;
  (* Neptune far away *)
  let (xn, yn, _) = Interplanet_time.heliocentric_pos ~body:7 ~jd:j2000_jd in
  let rn = sqrt (xn *. xn +. yn *. yn) in
  check_bool  "helio_pos neptune r > 29 AU" (rn > 29.0) true

(* ── Section 7: light_travel_time ────────────────────────────────────────── *)

let () =
  (* Earth to Mars - should be positive *)
  let lt_em = Interplanet_time.light_travel_time ~body1:2 ~body2:3 ~jd:j2000_jd in
  check_bool  "light_travel Earth-Mars > 0"    (lt_em > 0.0) true;
  check_bool  "light_travel Earth-Mars > 100s" (lt_em > 100.0) true;
  check_bool  "light_travel Earth-Mars < 1400s" (lt_em < 1400.0) true;
  (* Earth to Jupiter - further *)
  let lt_ej = Interplanet_time.light_travel_time ~body1:2 ~body2:4 ~jd:j2000_jd in
  check_bool  "light_travel Earth-Jupiter > Earth-Mars" (lt_ej > lt_em) true;
  (* same body = 0 *)
  let lt_ee = Interplanet_time.light_travel_time ~body1:2 ~body2:2 ~jd:j2000_jd in
  check_float "light_travel Earth-Earth = 0"  lt_ee 0.0 1e-6;
  (* Mercury to Sun region - smaller *)
  let lt_mv = Interplanet_time.light_travel_time ~body1:0 ~body2:1 ~jd:j2000_jd in
  check_bool  "light_travel Mercury-Venus > 0" (lt_mv > 0.0) true

(* ── Section 8: solar_day_seconds ────────────────────────────────────────── *)

let () =
  let earth_day = Interplanet_time.solar_day_seconds ~body:2 in
  check_float "solar_day_seconds earth = 86400" earth_day 86400.0 0.1;
  let mars_day  = Interplanet_time.solar_day_seconds ~body:3 in
  check_float "solar_day_seconds mars = 88775.244" mars_day 88775.244 0.01;
  check_bool  "solar_day mars > earth"  (mars_day > earth_day) true;
  let moon_day  = Interplanet_time.solar_day_seconds ~body:8 in
  check_float "solar_day_seconds moon = earth" moon_day earth_day 0.1;
  let merc_day  = Interplanet_time.solar_day_seconds ~body:0 in
  check_bool  "solar_day mercury >> earth" (merc_day > 10.0 *. earth_day) true

(* ── Section 9: local_solar_time ─────────────────────────────────────────── *)

let () =
  (* At the planet epoch, longitude=0 -> 0 seconds *)
  (* Earth epoch = J2000 = 2000-01-01T12:00:00Z.
     Elapsed from epoch = 0, so local_time_sec = 0 *)
  let lst_earth_epoch = Interplanet_time.local_solar_time ~body:2 ~jd:j2000_jd ~longitude:0.0 in
  check_float "local_solar_time earth at epoch lon=0" lst_earth_epoch 0.0 1.0;
  (* 90 degrees east = 1/4 day *)
  let lst_q = Interplanet_time.local_solar_time ~body:2 ~jd:j2000_jd ~longitude:90.0 in
  check_float "local_solar_time earth lon=90 = 6h" lst_q (6.0 *. 3600.0) 60.0;
  (* value should be in [0, solar_day_seconds) *)
  let day_s = Interplanet_time.solar_day_seconds ~body:2 in
  check_bool  "local_solar_time earth >= 0"    (lst_q >= 0.0) true;
  check_bool  "local_solar_time earth < day_s" (lst_q < day_s) true

(* ── Section 10: sol_number ──────────────────────────────────────────────── *)

let () =
  (* At J2000, Earth epoch = J2000, so sol_number = 0 *)
  let sol_earth = Interplanet_time.sol_number ~body:2 ~jd:j2000_jd in
  check_float "sol_number earth at epoch = 0" sol_earth 0.0 1e-6;
  (* Mars epoch is different - at J2000 sol ~ 16567 *)
  let sol_mars = Interplanet_time.sol_number ~body:3 ~jd:j2000_jd in
  check_bool  "sol_number mars at J2000 > 16000" (sol_mars > 16000.0) true;
  check_bool  "sol_number mars at J2000 < 17000" (sol_mars < 17000.0) true;
  (* Later date -> larger sol *)
  let jd_later = j2000_jd +. 365.0 in
  let sol_later = Interplanet_time.sol_number ~body:2 ~jd:jd_later in
  check_bool  "sol_number increases with time" (sol_later > sol_earth) true

(* ── Section 11: planet_time record ─────────────────────────────────────── *)

let unix_ms_j2000 = 946728000000.0

let pt_mars = Interplanet_time.planet_time ~body:3 ~unix_ms:unix_ms_j2000
let pt_earth = Interplanet_time.planet_time ~body:2 ~unix_ms:unix_ms_j2000
let pt_moon  = Interplanet_time.planet_time ~body:8 ~unix_ms:unix_ms_j2000

let () =
  check_int   "planet_time mars body = 3"   pt_mars.body 3;
  check_bool  "planet_time mars jd > 0"     (pt_mars.jd > 0.0) true;
  check_bool  "planet_time mars sol > 16000" (pt_mars.sol > 16000.0) true;
  check_bool  "planet_time mars local_time_sec in [0,day)"
    (pt_mars.local_time_sec >= 0.0 && pt_mars.local_time_sec < pt_mars.day_length_sec) true;
  check_float "planet_time mars day_length = mars_sol_s"
    pt_mars.day_length_sec 88775.244 0.01;
  check_bool  "planet_time mars light_travel > 0" (pt_mars.light_travel_from_earth_sec > 0.0) true;
  check_int   "planet_time earth body = 2"   pt_earth.body 2;
  check_float "planet_time earth day_length = 86400" pt_earth.day_length_sec 86400.0 0.1;
  check_float "planet_time earth light_travel = 0" pt_earth.light_travel_from_earth_sec 0.0 1e-6;
  check_int   "planet_time moon body = 8"    pt_moon.body 8;
  check_float "planet_time moon day_length = earth" pt_moon.day_length_sec 86400.0 0.1;
  check_float "planet_time moon light_travel = 0" pt_moon.light_travel_from_earth_sec 0.0 1e-6

(* ── Section 12: get_planet_time (full, for fixture) ─────────────────────── *)

let () =
  (* Mars at J2000: hour=15, minute=45, second=34, day_number=16567 *)
  let pt = Time_calc.get_planet_time ~body:3 ~utc_ms:unix_ms_j2000 in
  check_int "get_planet_time mars J2000 hour=15"   pt.Time_calc.hour 15;
  check_int "get_planet_time mars J2000 minute=45" pt.Time_calc.minute 45;
  check_int "get_planet_time mars J2000 day=16567" pt.Time_calc.day_number 16567;
  check     "get_planet_time mars J2000 time_str"  pt.Time_calc.time_str "15:45";
  (match pt.Time_calc.sol_in_year with
   | Some si -> check_int "mars sol_in_year = 520" si 520
   | None    -> incr failed; Printf.printf "FAIL: mars sol_in_year should be Some\n%!");
  (match pt.Time_calc.sols_per_year with
   | Some sp -> check_int "mars sols_per_year = 669" sp 669
   | None    -> incr failed; Printf.printf "FAIL: mars sols_per_year should be Some\n%!");
  (* Earth at J2000: hour=0, minute=0, second=0 *)
  let pt_e = Time_calc.get_planet_time ~body:2 ~utc_ms:unix_ms_j2000 in
  check_int "get_planet_time earth J2000 hour=0"   pt_e.Time_calc.hour 0;
  check_int "get_planet_time earth J2000 minute=0" pt_e.Time_calc.minute 0;
  check_int "get_planet_time earth J2000 day_number=0" pt_e.Time_calc.day_number 0

(* ── Section 13: fixture validation ──────────────────────────────────────── *)
(* Validates all 54 entries from reference.json.
   Tolerances: helio_r ±0.001, light_travel ±10s, hour/min/sec exact. *)

let fixture_path =
  (* When built via Makefile from ocaml/planet-time/, CWD is that directory.
     reference.json is at interplanet-github/c/planet-time/fixtures/reference.json *)
  let candidates = [
    "../../c/planet-time/fixtures/reference.json";
    "../../../c/planet-time/fixtures/reference.json";
    Filename.concat (Filename.dirname Sys.argv.(0))
      "../../c/planet-time/fixtures/reference.json";
  ] in
  let found = List.fold_left
    (fun acc p -> match acc with Some _ -> acc | None ->
      if Sys.file_exists p then Some p else None)
    None candidates
  in
  match found with
  | Some p -> p
  | None ->
    Printf.eprintf "WARNING: reference.json not found; fixture test skipped\n%!";
    ""

(* ── Minimal JSON helpers ──────────────────────────────────────────────────── *)
(* Handles pretty-printed JSON with optional whitespace after ':'. *)

(* Skip whitespace (space, tab, newline) at position j in json *)
let skip_ws json jlen j =
  while !j < jlen && (json.[!j] = ' ' || json.[!j] = '\t'
                       || json.[!j] = '\n' || json.[!j] = '\r') do
    j := !j + 1
  done

let find_string_val json key =
  (* Look for "key": "value" — note colon then optional whitespace then quote *)
  let key_pattern = "\"" ^ key ^ "\":" in
  let plen = String.length key_pattern in
  let jlen = String.length json in
  let result = ref "" in
  let i = ref 0 in
  while !i <= jlen - plen do
    if String.sub json !i plen = key_pattern then begin
      let j = ref (!i + plen) in
      skip_ws json jlen j;
      (* expect opening quote *)
      if !j < jlen && json.[!j] = '"' then begin
        j := !j + 1;
        let buf = Buffer.create 16 in
        let stop = ref false in
        while !j < jlen && not !stop do
          let c = json.[!j] in
          if c = '"' then stop := true
          else begin Buffer.add_char buf c; j := !j + 1 end
        done;
        result := Buffer.contents buf
      end;
      i := jlen
    end else
      i := !i + 1
  done;
  !result

let find_float_val json key =
  let key_pattern = "\"" ^ key ^ "\":" in
  let plen = String.length key_pattern in
  let jlen = String.length json in
  let result = ref 0.0 in
  let i = ref 0 in
  while !i <= jlen - plen do
    if String.sub json !i plen = key_pattern then begin
      let j = ref (!i + plen) in
      skip_ws json jlen j;
      if !j < jlen then begin
        let first_c = json.[!j] in
        (* handle null *)
        if first_c = 'n' then begin result := nan; i := jlen end
        else begin
          let buf = Buffer.create 16 in
          let neg = first_c = '-' in
          if neg then begin Buffer.add_char buf '-'; j := !j + 1 end;
          while !j < jlen
            && (let c = json.[!j] in
                (c >= '0' && c <= '9') || c = '.' || c = 'e'
                || c = 'E' || c = '+' || c = '-')
          do
            Buffer.add_char buf json.[!j]; j := !j + 1
          done;
          let s = Buffer.contents buf in
          (match float_of_string_opt s with Some v -> result := v | None -> ());
          i := jlen
        end
      end else
        i := jlen
    end else
      i := !i + 1
  done;
  !result

let find_int_val json key =
  int_of_float (floor (find_float_val json key))

(* Extract array string by key — handles optional whitespace after ':' *)
let find_array_str json key =
  let key_pattern = "\"" ^ key ^ "\":" in
  let plen = String.length key_pattern in
  let jlen = String.length json in
  let result = ref "[]" in
  let i = ref 0 in
  while !i <= jlen - plen do
    if String.sub json !i plen = key_pattern then begin
      let j = ref (!i + plen) in
      (* skip optional whitespace *)
      while !j < jlen && (json.[!j] = ' ' || json.[!j] = '\t'
                           || json.[!j] = '\n' || json.[!j] = '\r') do
        j := !j + 1
      done;
      if !j < jlen && json.[!j] = '[' then begin
        let start = !j in
        let depth = ref 1 in
        j := !j + 1;
        while !j < jlen && !depth > 0 do
          (match json.[!j] with '[' -> incr depth | ']' -> decr depth | _ -> ());
          j := !j + 1
        done;
        result := String.sub json start (!j - start)
      end;
      i := jlen
    end else
      i := !i + 1
  done;
  !result

(* Split top-level objects from a JSON array string *)
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

(* Map planet name string to body index *)
let planet_to_body = function
  | "mercury" -> 0
  | "venus"   -> 1
  | "earth"   -> 2
  | "mars"    -> 3
  | "jupiter" -> 4
  | "saturn"  -> 5
  | "uranus"  -> 6
  | "neptune" -> 7
  | "moon"    -> 8
  | s         -> failwith ("Unknown planet: " ^ s)

let fixture_entries_checked = ref 0

let () =
  if fixture_path <> "" then begin
    (* Read fixture file *)
    let ic = open_in fixture_path in
    let n  = in_channel_length ic in
    let json = Bytes.create n in
    really_input ic json 0 n;
    close_in ic;
    let json = Bytes.to_string json in
    (* Extract entries array *)
    let entries_arr = find_array_str json "entries" in
    let entries = split_objects entries_arr in
    List.iter (fun entry ->
      let planet_str = find_string_val entry "planet" in
      let utc_ms     = find_float_val  entry "utc_ms" in
      let body       = planet_to_body planet_str in
      let label = Printf.sprintf "%s@%s" planet_str
        (find_string_val entry "date_label") in

      (* Validate helio_r_au *)
      let exp_r = find_float_val entry "helio_r_au" in
      if exp_r = exp_r (* not NaN *) then begin
        let got_r = Orbital.helio_r_au ~body ~utc_ms in
        check_float (label ^ " helio_r_au") got_r exp_r 0.001
      end;

      (* Validate light_travel_s (null for Earth and Moon) *)
      let exp_lt = find_float_val entry "light_travel_s" in
      if exp_lt = exp_lt (* not NaN *) then begin
        let got_lt = Orbital.light_travel_time_ms ~body1:2 ~body2:body ~utc_ms in
        check_float (label ^ " light_travel_s") got_lt exp_lt 10.0
      end;

      (* Validate hour, minute, second (planet time) *)
      let exp_hour = find_int_val entry "hour" in
      let exp_min  = find_int_val entry "minute" in
      let exp_sec  = find_int_val entry "second" in
      let pt = Time_calc.get_planet_time ~body ~utc_ms in
      check_int (label ^ " hour")   pt.Time_calc.hour   exp_hour;
      check_int (label ^ " minute") pt.Time_calc.minute exp_min;
      check_int (label ^ " second") pt.Time_calc.second exp_sec;

      incr fixture_entries_checked
    ) entries;
    Printf.printf "fixture entries checked: %d\n%!" !fixture_entries_checked
  end else
    Printf.printf "fixture entries checked: 0 (file not found)\n%!"

(* ── Summary ─────────────────────────────────────────────────────────────── *)

let () =
  Printf.printf "%d passed  %d failed\n%!" !passed !failed;
  if !failed > 0 then exit 1
