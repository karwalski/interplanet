(* interplanet_time.ml — Public API for the Interplanetary Time Library
   Story 18.18 — OCaml planet-time library
   Mirrors the planet-time.js / C / Python APIs. *)

(* ── Re-exported types ───────────────────────────────────────────────────── *)

type planet_time = Time_calc.planet_time = {
  body                      : int;
  jd                        : float;
  sol                       : float;
  local_time_sec            : float;
  day_length_sec            : float;
  light_travel_from_earth_sec : float;
}

(* ── Body names ──────────────────────────────────────────────────────────── *)

(** [body_name body] returns the display name for body index 0..8. *)
let body_name (body : int) : string =
  if body >= 0 && body < Array.length Constants.body_names
  then Constants.body_names.(body)
  else "Unknown"

(* ── Julian Day ──────────────────────────────────────────────────────────── *)

(** [julian_day ~year ~month ~day ~hour ~minute ~second] converts a UTC
    calendar date/time to Julian Day number. *)
let julian_day = Orbital.julian_day

(* ── Mean longitude ──────────────────────────────────────────────────────── *)

(** [mean_longitude ~body ~jd] returns the mean longitude of a body
    in degrees for the given Julian Day. *)
let mean_longitude = Orbital.mean_longitude

(* ── True anomaly ────────────────────────────────────────────────────────── *)

(** [true_anomaly ~mean_anomaly ~eccentricity] solves Kepler's equation
    using Newton-Raphson (50 iterations) and returns the true anomaly
    in radians. *)
let true_anomaly = Orbital.true_anomaly

(* ── Ecliptic longitude ──────────────────────────────────────────────────── *)

(** [ecliptic_longitude ~body ~jd] returns the heliocentric ecliptic
    longitude of a body in degrees. *)
let ecliptic_longitude = Orbital.ecliptic_longitude

(* ── Heliocentric position ───────────────────────────────────────────────── *)

(** [heliocentric_pos ~body ~jd] returns the heliocentric (x, y, z)
    position in AU (ecliptic plane; z = 0). *)
let heliocentric_pos = Orbital.heliocentric_pos

(* ── Light travel time ───────────────────────────────────────────────────── *)

(** [light_travel_time ~body1 ~body2 ~jd] returns one-way light travel
    time in seconds between two bodies at the given Julian Day. *)
let light_travel_time = Orbital.light_travel_time

(* ── Solar day length ────────────────────────────────────────────────────── *)

(** [solar_day_seconds ~body] returns the solar day length in seconds
    for the given body. *)
let solar_day_seconds = Time_calc.solar_day_seconds

(* ── Local solar time ────────────────────────────────────────────────────── *)

(** [local_solar_time ~body ~jd ~longitude] returns seconds since
    midnight for the local solar time at the given surface longitude
    (degrees, positive = east). *)
let local_solar_time = Time_calc.local_solar_time

(* ── Sol number ──────────────────────────────────────────────────────────── *)

(** [sol_number ~body ~jd] returns the fractional sol/day number since
    the planet's epoch. *)
let sol_number = Time_calc.sol_number

(* ── Planet time ─────────────────────────────────────────────────────────── *)

(** [planet_time ~body ~unix_ms] computes the planet_time record for the
    given body at the given Unix millisecond timestamp (float). *)
let planet_time = Time_calc.planet_time
