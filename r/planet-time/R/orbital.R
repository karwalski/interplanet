# orbital.R — Orbital mechanics functions
# Ported from planet-time.js v1.1.0

#' Get TAI minus UTC offset for a given UTC millisecond timestamp
#' @param utc_ms numeric UTC milliseconds
#' @return integer TAI-UTC offset in seconds
tai_minus_utc <- function(utc_ms) {
  offset <- 10L
  for (entry in LEAP_SECS) {
    if (utc_ms >= entry$utc_ms) {
      offset <- entry$tai_utc
    } else {
      break
    }
  }
  offset
}

#' Convert UTC ms to Terrestrial Time Julian Ephemeris Day
#' @param utc_ms numeric UTC milliseconds
#' @return numeric JDE
jde <- function(utc_ms) {
  tt_ms <- utc_ms + (tai_minus_utc(utc_ms) + 32.184) * 1000
  2440587.5 + tt_ms / 86400000
}

#' Julian centuries since J2000.0
#' @param utc_ms numeric UTC milliseconds
#' @return numeric Julian centuries
jc <- function(utc_ms) {
  (jde(utc_ms) - J2000_JD) / 36525
}

#' Solve Kepler's equation M = E - e*sin(E) by Newton-Raphson
#' @param M numeric mean anomaly in radians
#' @param e numeric eccentricity
#' @return numeric eccentric anomaly E in radians
kepler_E <- function(M, e) {
  E <- M
  for (i in seq_len(50)) {
    dE <- (M - E + e * sin(E)) / (1 - e * cos(E))
    E <- E + dE
    if (abs(dE) < 1e-12) break
  }
  E
}

#' Get planet index for orbital element lookup (moon -> earth index)
#' @param planet_idx integer planet index (0-8)
#' @return integer orbital element index
.orb_idx <- function(planet_idx) {
  # Moon (8) uses Earth (2) orbital elements
  if (planet_idx == 8L) 2L else as.integer(planet_idx)
}

#' Heliocentric position of a planet
#' @param planet_idx integer planet index (0-8)
#' @param utc_ms numeric UTC milliseconds
#' @return list with x, y, r, lon (all in AU; lon in radians)
helio_pos <- function(planet_idx, utc_ms) {
  idx <- .orb_idx(planet_idx) + 1L  # R is 1-indexed
  el <- ORB_ELEMS[[idx]]

  T   <- jc(utc_ms)
  D2R <- pi / 180
  TAU <- 2 * pi

  L   <- (((el$L0 + el$dL * T) * D2R) %% TAU + TAU) %% TAU
  om  <- el$om0 * D2R
  M   <- ((L - om) %% TAU + TAU) %% TAU
  e   <- el$e0
  a   <- el$a

  E   <- kepler_E(M, e)
  v   <- 2 * atan2(sqrt(1 + e) * sin(E / 2), sqrt(1 - e) * cos(E / 2))
  r   <- a * (1 - e * cos(E))
  lon <- ((v + om) %% TAU + TAU) %% TAU

  list(x = r * cos(lon), y = r * sin(lon), r = r, lon = lon)
}

#' Distance in AU between two solar system bodies
#' @param a_idx integer planet index for body A
#' @param b_idx integer planet index for body B
#' @param utc_ms numeric UTC milliseconds
#' @return numeric distance in AU
body_distance_au <- function(a_idx, b_idx, utc_ms) {
  pA <- helio_pos(a_idx, utc_ms)
  pB <- helio_pos(b_idx, utc_ms)
  dx <- pA$x - pB$x
  dy <- pA$y - pB$y
  sqrt(dx * dx + dy * dy)
}

#' One-way light travel time between two bodies
#' @param a_idx integer planet index for body A
#' @param b_idx integer planet index for body B
#' @param utc_ms numeric UTC milliseconds
#' @return numeric light travel time in seconds
light_travel_seconds <- function(a_idx, b_idx, utc_ms) {
  body_distance_au(a_idx, b_idx, utc_ms) * AU_SECONDS
}

#' Check whether the line of sight between two bodies is obstructed by the Sun
#' @param a_idx integer planet index for body A
#' @param b_idx integer planet index for body B
#' @param utc_ms numeric UTC milliseconds
#' @return list with clear, blocked, degraded, closest_sun_au, elong_deg
check_line_of_sight <- function(a_idx, b_idx, utc_ms) {
  pA  <- helio_pos(a_idx, utc_ms)
  pB  <- helio_pos(b_idx, utc_ms)
  dx  <- pB$x - pA$x
  dy  <- pB$y - pA$y
  d2  <- dx * dx + dy * dy
  dist <- sqrt(d2)

  # Closest approach of segment A->B to the Sun (origin)
  t  <- max(0, min(1, -(pA$x * dx + pA$y * dy) / d2))
  cx <- pA$x + t * dx
  cy <- pA$y + t * dy
  closest_sun_au <- sqrt(cx * cx + cy * cy)

  # Solar elongation at A
  cos_el  <- (-pA$x * dx - pA$y * dy) / (pA$r * dist)
  cos_el  <- max(-1, min(1, cos_el))
  elong_deg <- acos(cos_el) * 180 / pi

  blocked  <- closest_sun_au < 0.01
  degraded <- !blocked && closest_sun_au < 0.05

  list(
    clear          = !blocked && !degraded,
    blocked        = blocked,
    degraded       = degraded,
    closest_sun_au = closest_sun_au,
    elong_deg      = elong_deg
  )
}

#' Sample light travel time over one Earth year and return the 25th-percentile
#' @param a_idx integer planet index for body A
#' @param b_idx integer planet index for body B
#' @param ref_ms numeric reference UTC milliseconds
#' @return numeric 25th-percentile light travel time in seconds
lower_quartile_light_time <- function(a_idx, b_idx, ref_ms) {
  SAMPLES <- 360L
  step    <- 365.25 * EARTH_DAY_MS / SAMPLES
  times   <- numeric(SAMPLES)
  for (i in seq_len(SAMPLES)) {
    times[i] <- light_travel_seconds(a_idx, b_idx, ref_ms + (i - 1) * step)
  }
  times <- sort(times)
  times[floor(SAMPLES * 0.25) + 1L]
}
