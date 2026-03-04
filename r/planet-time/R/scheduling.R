# scheduling.R — Meeting window scheduling functions
# Ported from planet-time.js v1.1.0

#' Find overlapping work windows between two planets over N Earth days
#' @param a_idx integer planet index for body A (0-8)
#' @param b_idx integer planet index for body B (0-8)
#' @param from_ms numeric UTC milliseconds start time
#' @param earth_days numeric number of Earth days to scan (default 30)
#' @param step_min numeric step size in minutes (default 15)
#' @return list of lists, each with start_ms, end_ms, duration_min
find_meeting_windows <- function(a_idx, b_idx, from_ms, earth_days = 30, step_min = 15) {
  STEP   <- step_min * 60000
  end_ms <- from_ms + earth_days * EARTH_DAY_MS
  windows  <- list()
  in_window <- FALSE
  window_start <- 0

  t <- from_ms
  while (t < end_ms) {
    ta <- get_planet_time(a_idx, t)
    tb <- get_planet_time(b_idx, t)
    overlap <- ta$is_work_hour && tb$is_work_hour
    if (overlap && !in_window) {
      in_window    <- TRUE
      window_start <- t
    } else if (!overlap && in_window) {
      in_window <- FALSE
      windows[[length(windows) + 1L]] <- list(
        start_ms     = window_start,
        end_ms       = t,
        duration_min = (t - window_start) / 60000
      )
    }
    t <- t + STEP
  }
  if (in_window) {
    windows[[length(windows) + 1L]] <- list(
      start_ms     = window_start,
      end_ms       = end_ms,
      duration_min = (end_ms - window_start) / 60000
    )
  }
  windows
}
