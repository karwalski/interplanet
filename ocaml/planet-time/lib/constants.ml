(* constants.ml — Interplanetary Time Library constants
   Story 18.18 — OCaml port of planet-time
   All numeric values taken verbatim from planet-time.js / C / Python. *)

(* ── Astronomical constants ──────────────────────────────────────────────── *)

let au_km       = 149597870.7          (* 1 AU in km, IAU 2012 *)
let c_kms       = 299792.458           (* speed of light km/s, SI exact *)
let au_seconds  = au_km /. c_kms       (* ≈ 499.004 s *)

(* ── Epoch constants ─────────────────────────────────────────────────────── *)

let j2000_jd    = 2451545.0            (* Julian Day of J2000.0 *)
let j2000_ms    = 946728000000.0       (* J2000.0 as Unix ms *)
let unix_epoch_jd = 2440587.5          (* Julian Day of 1970-01-01 00:00:00 UTC *)

let mars_epoch_ms  = -524069761536.0   (* 1953-05-24T09:03:58.464Z *)
let mars_sol_ms    = 88775244.0        (* Mars solar day in ms *)

let earth_day_ms   = 86400000.0        (* Earth solar day in ms *)

(* ── Body identifiers ────────────────────────────────────────────────────── *)
(* 0=Mercury 1=Venus 2=Earth 3=Mars 4=Jupiter 5=Saturn 6=Uranus 7=Neptune 8=Moon *)

let body_names = [|
  "Mercury"; "Venus"; "Earth"; "Mars";
  "Jupiter"; "Saturn"; "Uranus"; "Neptune"; "Moon"
|]

(* ── Planet data (indexed 0..7 for Mercury..Neptune; Moon maps to Earth) ── *)
(* solar_day_ms, sidereal_yr_ms, days_per_period, periods_per_week,
   work_periods_per_week, work_hours_start, work_hours_end, epoch_ms *)

type planet_data = {
  solar_day_ms        : float;
  sidereal_yr_ms      : float;
  days_per_period     : float;
  periods_per_week    : int;
  work_periods_per_week : int;
  work_hours_start    : int;
  work_hours_end      : int;
  epoch_ms            : float;
  earth_clock_sched   : bool;  (* true for Mercury and Venus *)
}

let planets = [|
  (* 0: Mercury — Earth-clock scheduling *)
  { solar_day_ms       = 175.9408 *. earth_day_ms;
    sidereal_yr_ms     = 87.9691  *. earth_day_ms;
    days_per_period    = 1.0; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 9; work_hours_end = 17;
    epoch_ms           = j2000_ms; earth_clock_sched = true };
  (* 1: Venus — Earth-clock scheduling *)
  { solar_day_ms       = 116.7500 *. earth_day_ms;
    sidereal_yr_ms     = 224.701  *. earth_day_ms;
    days_per_period    = 1.0; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 9; work_hours_end = 17;
    epoch_ms           = j2000_ms; earth_clock_sched = true };
  (* 2: Earth *)
  { solar_day_ms       = earth_day_ms;
    sidereal_yr_ms     = 365.25636 *. earth_day_ms;
    days_per_period    = 1.0; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 9; work_hours_end = 17;
    epoch_ms           = j2000_ms; earth_clock_sched = false };
  (* 3: Mars *)
  { solar_day_ms       = 88775244.0;
    sidereal_yr_ms     = 686.9957 *. earth_day_ms;
    days_per_period    = 1.0; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 9; work_hours_end = 17;
    epoch_ms           = mars_epoch_ms; earth_clock_sched = false };
  (* 4: Jupiter *)
  { solar_day_ms       = 9.9250 *. 3600000.0;
    sidereal_yr_ms     = 4332.589 *. earth_day_ms;
    days_per_period    = 2.5; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 8; work_hours_end = 16;
    epoch_ms           = j2000_ms; earth_clock_sched = false };
  (* 5: Saturn — Mankovich et al. 2023: 10.578 h *)
  { solar_day_ms       = 38080800.0;
    sidereal_yr_ms     = 10759.22 *. earth_day_ms;
    days_per_period    = 2.25; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 8; work_hours_end = 16;
    epoch_ms           = j2000_ms; earth_clock_sched = false };
  (* 6: Uranus *)
  { solar_day_ms       = 17.2479 *. 3600000.0;
    sidereal_yr_ms     = 30688.5 *. earth_day_ms;
    days_per_period    = 1.0; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 8; work_hours_end = 16;
    epoch_ms           = j2000_ms; earth_clock_sched = false };
  (* 7: Neptune *)
  { solar_day_ms       = 16.1100 *. 3600000.0;
    sidereal_yr_ms     = 60195.0 *. earth_day_ms;
    days_per_period    = 1.0; periods_per_week = 7;
    work_periods_per_week = 5; work_hours_start = 8; work_hours_end = 16;
    epoch_ms           = j2000_ms; earth_clock_sched = false };
|]

(* ── Orbital elements (Meeus Table 31.a) ─────────────────────────────────── *)
(* L0: mean longitude at J2000 (deg), dL: rate (deg/Julian century),
   om0: longitude of perihelion (deg), e0: eccentricity, a: semi-major axis (AU)
   Indexed 0..7 Mercury..Neptune; Moon maps to Earth (index 2). *)

type orb_elems = {
  l0  : float;  (* mean longitude at J2000, degrees *)
  dl  : float;  (* rate, degrees per Julian century *)
  om0 : float;  (* longitude of perihelion, degrees *)
  e0  : float;  (* eccentricity at J2000 *)
  a   : float;  (* semi-major axis, AU *)
}

let orb_elems = [|
  { l0=252.2507; dl=149474.0722; om0= 77.4561; e0=0.20564; a=0.38710 }; (* Mercury *)
  { l0=181.9798; dl= 58519.2130; om0=131.5637; e0=0.00677; a=0.72333 }; (* Venus   *)
  { l0=100.4664; dl= 36000.7698; om0=102.9373; e0=0.01671; a=1.00000 }; (* Earth   *)
  { l0=355.4330; dl= 19141.6964; om0=336.0600; e0=0.09341; a=1.52366 }; (* Mars    *)
  { l0= 34.3515; dl=  3036.3027; om0= 14.3320; e0=0.04849; a=5.20336 }; (* Jupiter *)
  { l0= 50.0775; dl=  1223.5093; om0= 93.0572; e0=0.05551; a=9.53707 }; (* Saturn  *)
  { l0=314.0550; dl=   429.8633; om0=173.0052; e0=0.04630; a=19.1912 }; (* Uranus  *)
  { l0=304.3480; dl=   219.8997; om0= 48.1234; e0=0.00899; a=30.0690 }; (* Neptune *)
|]

(* ── Leap-second table ───────────────────────────────────────────────────── *)
(* [TAI-UTC (seconds), UTC onset as Unix ms] *)

let leap_secs = [|
  (10,    63072000000.0);  (* 1972-01-01 *)
  (11,    78796800000.0);  (* 1972-07-01 *)
  (12,    94694400000.0);  (* 1973-01-01 *)
  (13,   126230400000.0);  (* 1974-01-01 *)
  (14,   157766400000.0);  (* 1975-01-01 *)
  (15,   189302400000.0);  (* 1976-01-01 *)
  (16,   220924800000.0);  (* 1977-01-01 *)
  (17,   252460800000.0);  (* 1978-01-01 *)
  (18,   283996800000.0);  (* 1979-01-01 *)
  (19,   315532800000.0);  (* 1980-01-01 *)
  (20,   362793600000.0);  (* 1981-07-01 *)
  (21,   394329600000.0);  (* 1982-07-01 *)
  (22,   425865600000.0);  (* 1983-07-01 *)
  (23,   489024000000.0);  (* 1985-07-01 *)
  (24,   567993600000.0);  (* 1988-01-01 *)
  (25,   631152000000.0);  (* 1990-01-01 *)
  (26,   662688000000.0);  (* 1991-01-01 *)
  (27,   709948800000.0);  (* 1992-07-01 *)
  (28,   741484800000.0);  (* 1993-07-01 *)
  (29,   773020800000.0);  (* 1994-07-01 *)
  (30,   820454400000.0);  (* 1996-01-01 *)
  (31,   867715200000.0);  (* 1997-07-01 *)
  (32,   915148800000.0);  (* 1999-01-01 *)
  (33,  1136073600000.0);  (* 2006-01-01 *)
  (34,  1230768000000.0);  (* 2009-01-01 *)
  (35,  1341100800000.0);  (* 2012-07-01 *)
  (36,  1435708800000.0);  (* 2015-07-01 *)
  (37,  1483228800000.0);  (* 2017-01-01 - current as of 2025 *)
|]
