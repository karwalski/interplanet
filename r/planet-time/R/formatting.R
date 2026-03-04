# formatting.R — Formatting utility functions
# Ported from planet-time.js v1.1.0

#' Format a light travel time (seconds) as human-readable string
#' @param seconds numeric light travel time in seconds
#' @return character string e.g. "3 min 6 s", "186 s", "1.5 h 30 m"
format_light_time <- function(seconds) {
  if (seconds < 0.001) return("<1ms")
  if (seconds < 1)     return(sprintf("%dms", as.integer(round(seconds * 1000))))
  if (seconds < 60)    return(sprintf("%d s", as.integer(floor(seconds))))
  if (seconds < 3600) {
    mins <- as.integer(floor(seconds / 60))
    secs <- as.integer(floor(seconds %% 60))
    if (secs == 0) return(sprintf("%d min", mins))
    return(sprintf("%d min %d s", mins, secs))
  }
  h <- as.integer(floor(seconds / 3600))
  m <- as.integer(round((seconds %% 3600) / 60))
  sprintf("%dh %dm", h, m)
}

#' Format a planet time result as a machine-parseable ISO-like timestamp
#' @param planet_idx integer planet index (0-8)
#' @param utc_ms numeric UTC milliseconds
#' @return character string timestamp
format_planet_time_iso <- function(planet_idx, utc_ms) {
  # effective_idx for Moon delegates to Earth schedule but we keep index for naming
  eff_idx <- if (planet_idx == 8L) 2L else as.integer(planet_idx)
  pt      <- get_planet_time(planet_idx, utc_ms)
  p       <- PLANET_DATA[[eff_idx + 1L]]

  zone_prefixes <- c(
    "MMT", "VMT", "EAT", "AMT", "JMT", "SMT", "UMT", "NMT", "LMT"
  )
  prefix   <- zone_prefixes[planet_idx + 1L]
  tz_id    <- paste0(prefix, "+0")
  hh <- sprintf("%02d", pt$hour)
  mm <- sprintf("%02d", pt$minute)
  ss <- sprintf("%02d", pt$second)

  # UTC reference
  utc_s   <- as.integer(utc_ms / 1000)
  utc_iso <- format(as.POSIXct(utc_s, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")

  if (p$key == "mars" && !is.null(pt$sol_in_year)) {
    date_str <- sprintf("MY%d-%03d", pt$year_number, pt$sol_in_year)
  } else {
    date_str <- format(as.POSIXct(utc_s, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d")
  }

  sprintf("%sT%s:%s:%s/%s[%s/%s]", date_str, hh, mm, ss, utc_iso, pt$planet_name, tz_id)
}
