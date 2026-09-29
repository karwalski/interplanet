# Accuracy harness for r/planet-time (see ../gen-cases-group2.js).
# Run from r/planet-time:
#   LC_ALL=C.UTF-8 Rscript ../../scripts/sweep/accuracy/r/accuracy.R ../../scripts/sweep/accuracy/instants-group2.txt
source("R/interplanet_time.R")

args <- commandArgs(trailingOnly = TRUE)
bodies <- c(mercury = 0L, venus = 1L, earth = 2L, mars = 3L, jupiter = 4L,
            saturn = 5L, uranus = 6L, neptune = 7L, moon = 8L)
b <- function(v) if (isTRUE(v)) 1L else 0L

out <- character(0)
for (line in trimws(readLines(args[1]))) {
  if (!nzchar(line)) next
  ms <- as.numeric(line)
  for (name in names(bodies)) {
    idx <- bodies[[name]]
    pt <- get_planet_time(idx, ms)
    lt <- light_travel_seconds(idx, Planet[["EARTH"]], ms)
    out <- c(out, paste(line, name, pt$hour, pt$minute, pt$second, pt$day_number,
                        pt$day_in_year, pt$year_number, pt$period_in_week,
                        b(pt$is_work_period), b(pt$is_work_hour),
                        sprintf("%.6f", lt), sep = "\t"))
  }
  m <- get_mtc(ms)
  out <- c(out, paste(line, "mtc", format(m$sol, scientific = FALSE), m$hour, m$minute,
                      m$second, sep = "\t"))
}
writeLines(out)
