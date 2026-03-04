(* orbital.ml — Orbital mechanics for the Interplanetary Time Library
   Story 18.18 — OCaml port of planet-time
   Exact port of planet-time.js / libinterplanet.c orbital functions. *)

let pi     = 4.0 *. atan 1.0
let two_pi = 2.0 *. pi
let d2r    = pi /. 180.0

(* ── Leap-second / TT helpers ────────────────────────────────────────────── *)

(* TAI − UTC in seconds for a given UTC millisecond timestamp *)
let tai_minus_utc (utc_ms : float) : int =
  let offset = ref 10 in
  Array.iter (fun (s, t_ms) ->
    if utc_ms >= t_ms then offset := s
  ) Constants.leap_secs;
  !offset

(* Convert UTC milliseconds to Terrestrial Time Julian Ephemeris Day.
   TT = UTC + (TAI−UTC) + 32.184 s *)
let jde (utc_ms : float) : float =
  let tt_ms = utc_ms +. (float_of_int (tai_minus_utc utc_ms) +. 32.184) *. 1000.0 in
  Constants.unix_epoch_jd +. tt_ms /. 86400000.0

(* Julian centuries from J2000.0 *)
let jc (utc_ms : float) : float =
  (jde utc_ms -. Constants.j2000_jd) /. 36525.0

(* ── Julian Day (calendar-based) ─────────────────────────────────────────── *)

(* Compute Julian Day from calendar date and time.
   Uses the standard algorithm (integer arithmetic for Gregorian calendar). *)
let julian_day ~year ~month ~day ~hour ~minute ~(second : float) : float =
  let y = if month <= 2 then year - 1 else year in
  let m = if month <= 2 then month + 12 else month in
  let a = y / 100 in
  let b = 2 - a + (a / 4) in
  let jd_day = float_of_int (int_of_float (365.25 *. float_of_int (y + 4716)))
             +. float_of_int (int_of_float (30.6001 *. float_of_int (m + 1)))
             +. float_of_int day +. float_of_int b -. 1524.5 in
  let time_frac = (float_of_int hour +. float_of_int minute /. 60.0 +. second /. 3600.0)
                  /. 24.0 in
  jd_day +. time_frac

(* ── Kepler solver (Newton-Raphson, 50 iterations) ───────────────────────── *)

let solve_kepler (m_anom : float) (ecc : float) : float =
  let e = ref m_anom in
  for _ = 1 to 50 do
    let de = (m_anom -. !e +. ecc *. sin !e) /. (1.0 -. ecc *. cos !e) in
    e := !e +. de
  done;
  !e

(* ── Mean longitude ──────────────────────────────────────────────────────── *)

(* Mean longitude of a body in degrees for a given Julian Day.
   Body index: 0=Mercury..7=Neptune (8=Moon uses Earth's elements). *)
let mean_longitude ~(body : int) ~(jd : float) : float =
  let idx = if body = 8 then 2 else body in
  let el = Constants.orb_elems.(idx) in
  let t = (jd -. Constants.j2000_jd) /. 36525.0 in
  let l_deg = el.Constants.l0 +. el.Constants.dl *. t in
  (* normalise to [0, 360) *)
  let l = l_deg -. 360.0 *. floor (l_deg /. 360.0) in
  l

(* ── True anomaly ────────────────────────────────────────────────────────── *)

(* Solve for true anomaly given mean anomaly (radians) and eccentricity.
   Uses Newton-Raphson via Kepler's equation.  Returns radians. *)
let true_anomaly ~(mean_anomaly : float) ~(eccentricity : float) : float =
  let e_anom = solve_kepler mean_anomaly eccentricity in
  2.0 *. atan2
    (sqrt (1.0 +. eccentricity) *. sin (e_anom /. 2.0))
    (sqrt (1.0 -. eccentricity) *. cos (e_anom /. 2.0))

(* ── Ecliptic longitude ──────────────────────────────────────────────────── *)

(* Ecliptic (heliocentric) longitude of a body in degrees. *)
let ecliptic_longitude ~(body : int) ~(jd : float) : float =
  let idx = if body = 8 then 2 else body in
  let el  = Constants.orb_elems.(idx) in
  let t   = (jd -. Constants.j2000_jd) /. 36525.0 in
  let l   = ((el.Constants.l0 +. el.Constants.dl *. t) *. d2r) in
  let l   = (mod_float l two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let om  = el.Constants.om0 *. d2r in
  let m   = (mod_float (l -. om) two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let e_anom = solve_kepler m el.Constants.e0 in
  let v   = 2.0 *. atan2
              (sqrt (1.0 +. el.Constants.e0) *. sin (e_anom /. 2.0))
              (sqrt (1.0 -. el.Constants.e0) *. cos (e_anom /. 2.0)) in
  let lon = (mod_float (v +. om) two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  lon *. 180.0 /. pi

(* ── Heliocentric position ───────────────────────────────────────────────── *)

(* Heliocentric (x, y, z) position in AU.
   z is always 0.0 (ecliptic plane computation).
   Returns (x, y, z). *)
let heliocentric_pos ~(body : int) ~(jd : float) : float * float * float =
  let idx = if body = 8 then 2 else body in
  let el  = Constants.orb_elems.(idx) in
  let t   = (jd -. Constants.j2000_jd) /. 36525.0 in
  let l   = ((el.Constants.l0 +. el.Constants.dl *. t) *. d2r) in
  let l   = (mod_float l two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let om  = el.Constants.om0 *. d2r in
  let m   = (mod_float (l -. om) two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let e_anom = solve_kepler m el.Constants.e0 in
  let v   = 2.0 *. atan2
              (sqrt (1.0 +. el.Constants.e0) *. sin (e_anom /. 2.0))
              (sqrt (1.0 -. el.Constants.e0) *. cos (e_anom /. 2.0)) in
  let r   = el.Constants.a *. (1.0 -. el.Constants.e0 *. cos e_anom) in
  let lon = (mod_float (v +. om) two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let x   = r *. cos lon in
  let y   = r *. sin lon in
  (x, y, 0.0)

(* Heliocentric distance in AU for a body at a UTC ms timestamp *)
let helio_r_au ~(body : int) ~(utc_ms : float) : float =
  let idx = if body = 8 then 2 else body in
  let el  = Constants.orb_elems.(idx) in
  let t   = jc utc_ms in
  let l   = ((el.Constants.l0 +. el.Constants.dl *. t) *. d2r) in
  let l   = (mod_float l two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let om  = el.Constants.om0 *. d2r in
  let m   = (mod_float (l -. om) two_pi +. two_pi) |> fun x -> mod_float x two_pi in
  let e_anom = solve_kepler m el.Constants.e0 in
  el.Constants.a *. (1.0 -. el.Constants.e0 *. cos e_anom)

(* ── Light travel time ───────────────────────────────────────────────────── *)

(* One-way light travel time in seconds between two bodies at a given UTC ms *)
let light_travel_time ~(body1 : int) ~(body2 : int) ~(jd : float) : float =
  let (x1, y1, _) = heliocentric_pos ~body:body1 ~jd in
  let (x2, y2, _) = heliocentric_pos ~body:body2 ~jd in
  let dx = x1 -. x2 in
  let dy = y1 -. y2 in
  let dist_au = sqrt (dx *. dx +. dy *. dy) in
  dist_au *. Constants.au_seconds

(* Light travel time using utc_ms rather than JD (for fixture testing) *)
let light_travel_time_ms ~(body1 : int) ~(body2 : int) ~(utc_ms : float) : float =
  let jd = jde utc_ms in
  light_travel_time ~body1 ~body2 ~jd
