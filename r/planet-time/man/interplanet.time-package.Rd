\name{interplanet.time-package}
\alias{interplanet.time-package}
\alias{interplanet.time}
\alias{get_planet_time}
\alias{get_mtc}
\alias{get_mars_time_at_offset}
\alias{light_travel_seconds}
\alias{body_distance_au}
\alias{helio_pos}
\alias{check_line_of_sight}
\alias{lower_quartile_light_time}
\alias{find_meeting_windows}
\alias{format_light_time}
\alias{format_planet_time_iso}
\alias{jde}
\alias{jc}
\alias{kepler_E}
\alias{tai_minus_utc}
\alias{Planet}
\alias{J2000_MS}
\alias{MARS_EPOCH_MS}
\alias{AU_KM}
\alias{C_KMS}
\alias{AU_SECONDS}
\alias{MARS_SOL_MS}
\alias{EARTH_DAY_MS}
\alias{J2000_JD}
\alias{LEAP_SECS}
\alias{ORB_ELEMS}
\alias{PLANET_DATA}
\docType{package}
\title{Interplanetary Time Calculations}
\description{
Port of \code{planet-time.js} (the InterPlanet JavaScript reference) to base R.
Times are UTC milliseconds since the Unix epoch; bodies are the indices in
\code{Planet} (Mercury 0 to Neptune 7, Moon 8).

Planet clock and calendar:
\itemize{
  \item \code{get_planet_time(planet_idx, utc_ms, tz_offset_h = 0)}: local hour,
    minute and second, day number, day in year, year number and work-schedule
    flags on a body.
  \item \code{get_mtc(utc_ms)}: Mars Coordinated Time (sol and Mars-clock time
    at the prime meridian).
  \item \code{get_mars_time_at_offset(utc_ms, offset_h)}: Mars local time at a
    zone offset.
}
Orbits and light time:
\itemize{
  \item \code{helio_pos(planet_idx, utc_ms)}: heliocentric ecliptic position (AU).
  \item \code{body_distance_au(a_idx, b_idx, utc_ms)} and
    \code{light_travel_seconds(a_idx, b_idx, utc_ms)}: distance and one-way
    light time between two bodies.
  \item \code{check_line_of_sight(a_idx, b_idx, utc_ms)}: solar conjunction check.
  \item \code{lower_quartile_light_time(a_idx, b_idx, ref_ms)}: lower-quartile
    light time over one synodic period.
  \item \code{jde}, \code{jc}, \code{tai_minus_utc}, \code{kepler_E}: time-scale
    and Kepler-equation helpers.
}
Scheduling and formatting:
\itemize{
  \item \code{find_meeting_windows(a_idx, b_idx, from_ms, earth_days = 30, step_min = 15)}:
    overlapping work hours of two bodies.
  \item \code{format_light_time(seconds)} and
    \code{format_planet_time_iso(planet_idx, utc_ms)}: display strings.
}
Constants: \code{J2000_MS}, \code{J2000_JD}, \code{MARS_EPOCH_MS},
\code{MARS_SOL_MS}, \code{EARTH_DAY_MS}, \code{AU_KM}, \code{C_KMS},
\code{AU_SECONDS}, \code{LEAP_SECS}, \code{ORB_ELEMS}, \code{PLANET_DATA}.
}
\keyword{package}
