# time_calc.R — Planet time calculation functions
# Ported from planet-time.js v1.1.0

#' Get the current time on a planet
#' @param planet_idx integer planet index (0-8)
#' @param utc_ms numeric UTC milliseconds
#' @param tz_offset_h numeric timezone offset in planet local hours (default 0)
#' @return list with hour, minute, second, local_hour, day_fraction, day_number,
#'   day_in_year, year_number, period_in_week, is_work_period, is_work_hour,
#'   time_str, time_str_full, sol_in_year, sols_per_year, planet_name
get_planet_time <- function(planet_idx, utc_ms, tz_offset_h = 0) {
  # Moon (8) delegates to Earth (2) schedules
  if (planet_idx == 8L) planet_idx <- 2L
  p_idx  <- as.integer(planet_idx) + 1L  # R 1-indexed
  p      <- PLANET_DATA[[p_idx]]

  elapsed_ms  <- utc_ms - p$epochMs + tz_offset_h / 24 * p$solarDayMs
  total_days  <- elapsed_ms / p$solarDayMs
  day_number  <- floor(total_days)
  day_fraction <- total_days - day_number

  local_hour <- day_fraction * 24
  h <- floor(local_hour)
  m <- floor((local_hour - h) * 60)
  s <- floor(((local_hour - h) * 60 - m) * 60)

  days_per_period    <- p$daysPerPeriod
  periods_per_week   <- p$periodsPerWeek
  work_periods_week  <- p$workPeriodsPerWeek

  # Mercury/Venus use Earth-clock scheduling (UTC day-of-week + UTC hour)
  earth_clock <- isTRUE(p$earthClockSched)
  if (earth_clock) {
    # dow = ((floor(utc_ms / 86400000) %% 7) + 3) %% 7, Mon=0..Sun=6
    utc_day    <- floor(utc_ms / 86400000)
    dow        <- ((utc_day %% 7) + 3) %% 7
    period_in_week <- as.integer(dow)
    is_work_period <- dow < work_periods_week
    ms_of_day  <- utc_ms - utc_day * 86400000
    utc_h      <- floor(ms_of_day / 3600000)
    is_work_hour <- is_work_period && utc_h >= p$workHoursStart && utc_h < p$workHoursEnd
  } else {
    total_periods  <- total_days / days_per_period
    # positive modulo for pre-epoch dates
    period_in_week <- ((floor(total_periods) %% periods_per_week) + periods_per_week) %% periods_per_week
    is_work_period <- period_in_week < work_periods_week
    is_work_hour   <- is_work_period && local_hour >= p$workHoursStart && local_hour < p$workHoursEnd
  }

  year_len_days <- p$siderealYrMs / p$solarDayMs
  year_number   <- floor(total_days / year_len_days)
  day_in_year   <- total_days - year_number * year_len_days

  sol_in_year  <- NULL
  sols_per_year <- NULL
  if (p$key == "mars") {
    sols_per_year <- round(p$siderealYrMs / p$solarDayMs)
    sol_in_year   <- floor(day_in_year)
  }

  time_str      <- sprintf("%02d:%02d", as.integer(h), as.integer(m))
  time_str_full <- sprintf("%02d:%02d:%02d", as.integer(h), as.integer(m), as.integer(s))

  list(
    planet_name    = p$name,
    hour           = as.integer(h),
    minute         = as.integer(m),
    second         = as.integer(s),
    local_hour     = local_hour,
    day_fraction   = day_fraction,
    day_number     = as.integer(day_number),
    day_in_year    = as.integer(floor(day_in_year)),
    year_number    = as.integer(year_number),
    period_in_week = as.integer(period_in_week),
    is_work_period = is_work_period,
    is_work_hour   = is_work_hour,
    time_str       = time_str,
    time_str_full  = time_str_full,
    sol_in_year    = sol_in_year,
    sols_per_year  = sols_per_year
  )
}

#' Get Mars Coordinated Time (MTC)
#' @param utc_ms numeric UTC milliseconds
#' @return list with sol, hour, minute, second, mtc_str
get_mtc <- function(utc_ms) {
  total_sols <- (utc_ms - MARS_EPOCH_MS) / MARS_SOL_MS
  sol        <- floor(total_sols)
  frac       <- total_sols - sol
  h <- floor(frac * 24)
  m <- floor((frac * 24 - h) * 60)
  s <- floor(((frac * 24 - h) * 60 - m) * 60)
  list(
    sol     = as.integer(sol),
    hour    = as.integer(h),
    minute  = as.integer(m),
    second  = as.integer(s),
    mtc_str = sprintf("%02d:%02d", as.integer(h), as.integer(m))
  )
}

#' Get Mars local time at a given zone offset
#' @param utc_ms numeric UTC milliseconds
#' @param offset_h numeric Mars local hour offset from AMT
#' @return list with sol, hour, minute, second, time_str, offset_h
get_mars_time_at_offset <- function(utc_ms, offset_h) {
  mtc       <- get_mtc(utc_ms)
  h         <- mtc$hour + offset_h
  sol_delta <- 0L
  if (h >= 24) { h <- h - 24; sol_delta <-  1L }
  if (h <   0) { h <- h + 24; sol_delta <- -1L }
  list(
    sol      = mtc$sol + sol_delta,
    hour     = as.integer(floor(h)),
    minute   = mtc$minute,
    second   = mtc$second,
    time_str = sprintf("%02d:%02d", as.integer(floor(h)), as.integer(mtc$minute)),
    offset_h = offset_h
  )
}
