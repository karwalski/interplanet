# test/test_unit.R — Unit tests for interplanet.time R package
# Run: Rscript test/test_unit.R
# Requires: R >= 4.0, no external packages

source("R/interplanet_time.R")

passed <- 0L
failed <- 0L

check <- function(cond, msg = "") {
  if (isTRUE(cond)) {
    passed <<- passed + 1L
  } else {
    failed <<- failed + 1L
    cat(sprintf("FAIL: %s\n", msg))
  }
}

# ── Section 1: Constants ──────────────────────────────────────────────────────

check(J2000_MS == 946728000000,    "J2000_MS value")
check(MARS_EPOCH_MS == -524069761536, "MARS_EPOCH_MS value")
check(AU_KM == 149597870.7,        "AU_KM value")
check(C_KMS == 299792.458,         "C_KMS value")
check(abs(AU_SECONDS - 499.004) < 0.001, "AU_SECONDS approx 499.004")
check(MARS_SOL_MS == 88775244,     "MARS_SOL_MS value")
check(J2000_JD == 2451545.0,       "J2000_JD value")
check(EARTH_DAY_MS == 86400000,    "EARTH_DAY_MS value")

# ── Section 2: Planet enum ────────────────────────────────────────────────────

check(Planet["MERCURY"] == 0L,  "Planet MERCURY = 0")
check(Planet["VENUS"]   == 1L,  "Planet VENUS = 1")
check(Planet["EARTH"]   == 2L,  "Planet EARTH = 2")
check(Planet["MARS"]    == 3L,  "Planet MARS = 3")
check(Planet["JUPITER"] == 4L,  "Planet JUPITER = 4")
check(Planet["SATURN"]  == 5L,  "Planet SATURN = 5")
check(Planet["URANUS"]  == 6L,  "Planet URANUS = 6")
check(Planet["NEPTUNE"] == 7L,  "Planet NEPTUNE = 7")
check(Planet["MOON"]    == 8L,  "Planet MOON = 8")
check(length(Planet) == 9L,     "Planet enum has 9 entries")

# ── Section 3: Leap seconds table ────────────────────────────────────────────

check(length(LEAP_SECS) == 28L,              "LEAP_SECS has 28 entries")
check(LEAP_SECS[[1]]$tai_utc == 10L,         "First leap second TAI-UTC = 10")
check(LEAP_SECS[[28]]$tai_utc == 37L,        "Last leap second TAI-UTC = 37")
check(LEAP_SECS[[28]]$utc_ms == 1483228800000, "Last leap second UTC ms")

# ── Section 4: JDE calculations ──────────────────────────────────────────────

# At J2000 epoch, JDE should be 2451545.0
jde_j2000 <- jde(J2000_MS)
check(abs(jde_j2000 - 2451545.0) < 0.001, "JDE at J2000 = 2451545.0 +/- 0.001")

# Julian centuries at J2000 = 0
jc_j2000 <- jc(J2000_MS)
check(abs(jc_j2000) < 0.001, "JC at J2000 approx 0")

# ── Section 5: TAI-UTC lookup ─────────────────────────────────────────────────

check(tai_minus_utc(J2000_MS) == 32L, "TAI-UTC at J2000 = 32")
check(tai_minus_utc(1483228800000) == 37L, "TAI-UTC after 2017-01-01 = 37")
check(tai_minus_utc(0) == 10L, "TAI-UTC before first entry = 10")

# ── Section 6: Kepler equation ────────────────────────────────────────────────

# E = M for e=0 (circular orbit)
check(abs(kepler_E(1.0, 0) - 1.0) < 1e-10, "kepler_E: e=0 returns M")
# Small eccentricity: E approx M
check(abs(kepler_E(1.0, 0.1) - 1.0) < 0.15, "kepler_E: small e, E near M")
# E = 0 for M = 0
check(abs(kepler_E(0, 0.5)) < 1e-10, "kepler_E: M=0 returns 0")

# ── Section 7: Heliocentric positions ────────────────────────────────────────

# Earth at J2000 should be approx 1 AU from Sun
earth_pos <- helio_pos(Planet["EARTH"], J2000_MS)
check(abs(earth_pos$r - 1.0) < 0.02, "Earth helio_r approx 1 AU at J2000")
check(!is.null(earth_pos$x), "helio_pos returns x")
check(!is.null(earth_pos$y), "helio_pos returns y")
check(!is.null(earth_pos$lon), "helio_pos returns lon")

# Mars at J2000
mars_pos <- helio_pos(Planet["MARS"], J2000_MS)
check(mars_pos$r > 1.3 && mars_pos$r < 1.7, "Mars helio_r in range 1.3-1.7 AU at J2000")

# Jupiter at J2000
jup_pos <- helio_pos(Planet["JUPITER"], J2000_MS)
check(jup_pos$r > 4.9 && jup_pos$r < 5.5, "Jupiter helio_r in range 4.9-5.5 AU at J2000")

# Moon uses Earth's orbital elements
moon_pos  <- helio_pos(Planet["MOON"], J2000_MS)
check(abs(moon_pos$r - earth_pos$r) < 0.001, "Moon uses Earth orbital elements")

# ── Section 8: Distance and light travel ─────────────────────────────────────

# Earth-Mars distance
em_dist <- body_distance_au(Planet["EARTH"], Planet["MARS"], J2000_MS)
check(em_dist > 0.5 && em_dist < 2.5, "Earth-Mars distance 0.5-2.5 AU at J2000")

# Light travel Earth to Mars at Mars close approach 2003-08-27
# utc_ms approx 1061977860000
lt_2003 <- light_travel_seconds(Planet["EARTH"], Planet["MARS"], 1061977860000)
check(lt_2003 > 171 && lt_2003 < 201, "Earth-Mars light travel ~186 s at 2003 close approach")

# Light travel Earth to Mars at opposition 2020-10-13
lt_2020 <- light_travel_seconds(Planet["EARTH"], Planet["MARS"], 1602631560000)
check(lt_2020 > 192 && lt_2020 < 222, "Earth-Mars light travel ~207 s at 2020 opposition")

# Light travel Earth to Jupiter at opposition 2023-11-03
lt_jup <- light_travel_seconds(Planet["EARTH"], Planet["JUPITER"], 1698969600000)
check(lt_jup > 1890 && lt_jup < 2130, "Earth-Jupiter light travel ~2010 s at 2023 opposition")

# ── Section 9: Line of sight ─────────────────────────────────────────────────

# At Mars opposition 2020-10-13, line of sight should be clear
los_clear <- check_line_of_sight(Planet["EARTH"], Planet["MARS"], 1602547200000)
check(los_clear$clear == TRUE, "Line of sight clear at Mars opposition 2020")
check(los_clear$blocked == FALSE, "Not blocked at Mars opposition 2020")

# Check the result has all required fields
check(!is.null(los_clear$closest_sun_au), "check_line_of_sight returns closest_sun_au")
check(!is.null(los_clear$elong_deg), "check_line_of_sight returns elong_deg")
check(los_clear$closest_sun_au > 0.5, "Sun not close to line at Mars opposition")

# ── Section 10: MTC calculations ─────────────────────────────────────────────

# MTC at J2000 (946728000000)
mtc_j2000 <- get_mtc(J2000_MS)
check(mtc_j2000$hour >= 0 && mtc_j2000$hour < 24, "MTC hour in range 0-23 at J2000")
check(mtc_j2000$minute >= 0 && mtc_j2000$minute < 60, "MTC minute in range 0-59 at J2000")
check(mtc_j2000$second >= 0 && mtc_j2000$second < 60, "MTC second in range 0-59 at J2000")
check(grepl("^\\d{2}:\\d{2}$", mtc_j2000$mtc_str), "MTC string format HH:MM")
check(!is.null(mtc_j2000$sol), "MTC has sol field")
# Reference: MTC at J2000 ~ 15:45
check(mtc_j2000$hour >= 14 && mtc_j2000$hour <= 17, "MTC hour at J2000 approx 15 +/- 2")

# ── Section 11: get_planet_time ───────────────────────────────────────────────

# All 9 planets at J2000
for (pidx in 0:8) {
  pt <- get_planet_time(pidx, J2000_MS)
  check(pt$hour >= 0 && pt$hour < 24, sprintf("Planet %d: hour in range 0-23", pidx))
  check(pt$minute >= 0 && pt$minute < 60, sprintf("Planet %d: minute in range 0-59", pidx))
  check(pt$second >= 0 && pt$second < 60, sprintf("Planet %d: second in range 0-59", pidx))
  check(grepl("^\\d{2}:\\d{2}$", pt$time_str), sprintf("Planet %d: time_str format HH:MM", pidx))
}

# Mars sol_in_year is non-NULL
mars_pt <- get_planet_time(Planet["MARS"], J2000_MS)
check(!is.null(mars_pt$sol_in_year), "Mars sol_in_year is non-NULL")
check(!is.null(mars_pt$sols_per_year), "Mars sols_per_year is non-NULL")
check(mars_pt$sols_per_year > 650 && mars_pt$sols_per_year < 700,
      "Mars sols_per_year approx 669")

# Non-Mars planets have NULL sol_in_year
earth_pt <- get_planet_time(Planet["EARTH"], J2000_MS)
check(is.null(earth_pt$sol_in_year), "Earth sol_in_year is NULL")

# Epoch check: at epochMs, planet time should be 00:00:00 (day_fraction = 0)
# At J2000_MS (epoch for Mercury, Venus, Earth, Jupiter, Saturn, Uranus, Neptune)
merc_pt <- get_planet_time(Planet["MERCURY"], J2000_MS)
check(merc_pt$day_fraction == 0, "Mercury at epoch: day_fraction = 0")

# Second and third reference timestamps
pt2 <- get_planet_time(Planet["EARTH"], 1735689600000)  # 2025-01-01
check(pt2$hour >= 0 && pt2$hour < 24, "Earth at 2025-01-01: hour in range")

pt3 <- get_planet_time(Planet["MARS"], 1602631560000)  # 2020-10-14
check(pt3$hour >= 0 && pt3$hour < 24, "Mars at 2020-10-14: hour in range")

# ── Section 12: Work hour logic ───────────────────────────────────────────────

# Earth work hours: 9-17 (workHoursStart=9, workHoursEnd=17)
# Force a specific time: find an Earth timestamp where local hour = 12
# Earth epoch = J2000_MS, solar day = 86400000 ms
# At J2000_MS itself: day_fraction = 0 -> hour = 0 (not work)
earth_pt_epoch <- get_planet_time(Planet["EARTH"], J2000_MS)
check(earth_pt_epoch$hour == 0, "Earth at epoch: hour = 0")
check(earth_pt_epoch$is_work_hour == FALSE, "Earth at epoch midnight: not work hour")

# At J2000_MS + 10.5 hours (10.5/24 of Earth day = work time)
earth_work_ms <- J2000_MS + as.integer(10.5 * 3600000)
earth_work_pt <- get_planet_time(Planet["EARTH"], earth_work_ms)
check(earth_work_pt$hour == 10, "Earth 10.5h past epoch: hour = 10")
check(earth_work_pt$is_work_period == TRUE, "Earth at 10:30: work period")
check(earth_work_pt$is_work_hour == TRUE, "Earth at 10:30: is_work_hour TRUE")

# At 20:00 (past workHoursEnd=17)
earth_late_ms <- J2000_MS + as.integer(20.5 * 3600000)
earth_late_pt <- get_planet_time(Planet["EARTH"], earth_late_ms)
check(earth_late_pt$is_work_hour == FALSE, "Earth at 20:30: not work hour")

# Mars work hours: 9-17
mars_work_ms <- MARS_EPOCH_MS + as.integer(10.5 / 24 * 88775244)
mars_work_pt <- get_planet_time(Planet["MARS"], mars_work_ms)
check(mars_work_pt$is_work_period == TRUE, "Mars at 10:30: work period")
check(mars_work_pt$is_work_hour == TRUE, "Mars at 10:30: is_work_hour TRUE")

# ── Section 13: get_mars_time_at_offset ──────────────────────────────────────

mars_offset <- get_mars_time_at_offset(J2000_MS, 0)
check(mars_offset$hour >= 0 && mars_offset$hour < 24, "get_mars_time_at_offset AMT+0: valid hour")

mars_offset_4 <- get_mars_time_at_offset(J2000_MS, 4)
check(!is.null(mars_offset_4$sol), "get_mars_time_at_offset AMT+4: has sol")
check(grepl("^\\d{2}:\\d{2}$", mars_offset_4$time_str), "get_mars_time_at_offset: time_str format")

# ── Section 14: lower_quartile_light_time ────────────────────────────────────

lq <- lower_quartile_light_time(Planet["EARTH"], Planet["MARS"], J2000_MS)
check(lq > 100 && lq < 1200, "lower_quartile Earth-Mars in range 100-1200 s")
check(is.numeric(lq), "lower_quartile_light_time returns numeric")

lq_jup <- lower_quartile_light_time(Planet["EARTH"], Planet["JUPITER"], J2000_MS)
check(lq_jup > 1000 && lq_jup < 5000, "lower_quartile Earth-Jupiter in range 1000-5000 s")

# ── Section 15: find_meeting_windows ─────────────────────────────────────────

# Earth-Earth meeting windows (should find many)
ee_windows <- find_meeting_windows(Planet["EARTH"], Planet["EARTH"], J2000_MS, earth_days = 7)
check(length(ee_windows) > 0, "Earth-Earth: some meeting windows over 7 days")
if (length(ee_windows) > 0) {
  w1 <- ee_windows[[1]]
  check(w1$start_ms < w1$end_ms, "Meeting window: start_ms < end_ms")
  check(w1$duration_min > 0, "Meeting window: duration_min > 0")
}

# Earth-Mars windows (may be empty over 7 days, but structure is valid)
em_windows <- find_meeting_windows(Planet["EARTH"], Planet["MARS"], J2000_MS, earth_days = 30)
check(is.list(em_windows), "find_meeting_windows returns a list")

# ── Section 16: format_light_time ────────────────────────────────────────────

check(format_light_time(0) == "<1ms", "format_light_time(0) = <1ms")
check(format_light_time(0.0005) == "<1ms", "format_light_time(0.0005) = <1ms")
check(format_light_time(0.5) == "500ms", "format_light_time(0.5) = 500ms")
check(format_light_time(1) == "1 s", "format_light_time(1) = 1 s")
check(format_light_time(30) == "30 s", "format_light_time(30) = 30 s")
check(format_light_time(60) == "1 min", "format_light_time(60) = 1 min")
check(format_light_time(186) == "3 min 6 s", "format_light_time(186) = 3 min 6 s")
check(format_light_time(3600) == "1h 0m", "format_light_time(3600) = 1h 0m")
check(format_light_time(3661) == "1h 1m", "format_light_time(3661) = 1h 1m")
check(is.character(format_light_time(186)), "format_light_time returns character")

# ── Section 17: format_planet_time_iso ───────────────────────────────────────

iso_earth <- format_planet_time_iso(Planet["EARTH"], J2000_MS)
check(is.character(iso_earth), "format_planet_time_iso returns character")
check(grepl("\\[", iso_earth), "format_planet_time_iso has [ bracket")
check(grepl("EAT", iso_earth), "format_planet_time_iso Earth contains EAT")

iso_mars <- format_planet_time_iso(Planet["MARS"], J2000_MS)
check(grepl("MY", iso_mars), "format_planet_time_iso Mars contains MY")
check(grepl("AMT", iso_mars), "format_planet_time_iso Mars contains AMT")

iso_moon <- format_planet_time_iso(Planet["MOON"], J2000_MS)
check(grepl("LMT", iso_moon), "format_planet_time_iso Moon contains LMT")

# ── Section 18: Helio positions at additional reference times ─────────────────

# Earth at 2025-01-01
earth_2025 <- helio_pos(Planet["EARTH"], 1735689600000)
check(earth_2025$r > 0.95 && earth_2025$r < 1.05, "Earth helio_r approx 1 AU at 2025-01-01")

# Mercury always < 0.48 AU from Sun
mercury_pos <- helio_pos(Planet["MERCURY"], J2000_MS)
check(mercury_pos$r < 0.48, "Mercury helio_r < 0.48 AU at J2000")

# Saturn always > 9 AU from Sun
saturn_pos <- helio_pos(Planet["SATURN"], J2000_MS)
check(saturn_pos$r > 9.0 && saturn_pos$r < 10.1, "Saturn helio_r 9-10 AU at J2000")

# ── Section 19: Period-in-week and work period logic ─────────────────────────

# Mercury uses earthClockSched (UTC day-of-week). At J2000 utcDay=10957:
# piw = ((10957 % 7) + 10) % 7 = (2+10)%7 = 5 (Saturday) → not a work period
merc_piw <- get_planet_time(Planet["MERCURY"], J2000_MS)
check(merc_piw$period_in_week == 5, "Mercury at epoch: period_in_week = 5 (Saturday)")
check(merc_piw$is_work_period == FALSE, "Mercury at epoch: is_work_period FALSE (Saturday)")

# ── Section 20: MTC at additional timestamps ─────────────────────────────────

# MTC at 2020-10-14 (Mars opposition period)
mtc_2020 <- get_mtc(1602631560000)
check(mtc_2020$sol > 0, "MTC sol > 0 at 2020-10-14")
check(mtc_2020$hour >= 0 && mtc_2020$hour < 24, "MTC hour valid at 2020-10-14")

# MTC at 2025-01-01
mtc_2025 <- get_mtc(1735689600000)
check(mtc_2025$sol > mtc_j2000$sol, "MTC sol increases from J2000 to 2025")

# ── Summary ───────────────────────────────────────────────────────────────────

cat(sprintf("\n%d passed  %d failed\n", passed, failed))
if (failed > 0L) quit(status = 1L)
