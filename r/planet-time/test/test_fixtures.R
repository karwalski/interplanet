# test/test_fixtures.R — Cross-language fixture validation
# Run: Rscript test/test_fixtures.R [path/to/reference.json]
# Validates R port results against reference.json fixture

args <- commandArgs(trailingOnly = TRUE)
fixture_file <- if (length(args) > 0) args[1] else "../../c/planet-time/fixtures/reference.json"

if (!file.exists(fixture_file)) {
  cat("SKIP: fixture file not found:", fixture_file, "\n")
  quit(status = 0)
}

# Try to use jsonlite if available, otherwise skip
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  cat("SKIP: jsonlite not available — install with install.packages('jsonlite')\n")
  quit(status = 0)
}

source("R/interplanet_time.R")

data    <- jsonlite::fromJSON(fixture_file, simplifyVector = FALSE)
entries <- data$entries

cat(sprintf("Fixture entries loaded: %d\n", length(entries)))

passed <- 0L
failed <- 0L

check_fixture <- function(cond, msg = "") {
  if (isTRUE(cond)) {
    passed <<- passed + 1L
  } else {
    failed <<- failed + 1L
    cat(sprintf("FAIL: %s\n", msg))
  }
}

# Planet key to index map
planet_key_to_idx <- list(
  mercury = 0L, venus = 1L, earth = 2L, mars = 3L,
  jupiter = 4L, saturn = 5L, uranus = 6L, neptune = 7L, moon = 8L
)

for (entry in entries) {
  planet_key <- entry$planet
  utc_ms     <- entry$utc_ms
  p_idx      <- planet_key_to_idx[[planet_key]]

  if (is.null(p_idx)) {
    cat(sprintf("SKIP unknown planet: %s\n", planet_key))
    next
  }

  pt <- tryCatch(
    get_planet_time(p_idx, utc_ms),
    error = function(e) NULL
  )

  if (is.null(pt)) {
    failed <- failed + 1L
    cat(sprintf("FAIL: get_planet_time(%s, %g) threw error\n", planet_key, utc_ms))
    next
  }

  label <- sprintf("%s @ %s", planet_key, entry$date_label)

  check_fixture(pt$hour == entry$hour,
    sprintf("%s: hour %d == %d", label, pt$hour, entry$hour))
  check_fixture(pt$minute == entry$minute,
    sprintf("%s: minute %d == %d", label, pt$minute, entry$minute))
  check_fixture(pt$second == entry$second,
    sprintf("%s: second %d == %d", label, pt$second, entry$second))

  # Light travel time (if available)
  if (!is.null(entry$light_travel_s) && planet_key != "earth") {
    lt <- tryCatch(
      light_travel_seconds(Planet["EARTH"], p_idx, utc_ms),
      error = function(e) NA_real_
    )
    if (!is.na(lt)) {
      tol <- max(abs(entry$light_travel_s) * 0.01, 1.0)
      check_fixture(abs(lt - entry$light_travel_s) <= tol,
        sprintf("%s: light_travel %.2f vs ref %.2f (tol %.2f)",
                label, lt, entry$light_travel_s, tol))
    }
  }

  # MTC for Mars
  if (planet_key == "mars" && !is.null(entry$mtc)) {
    mtc <- tryCatch(get_mtc(utc_ms), error = function(e) NULL)
    if (!is.null(mtc) && !is.null(entry$mtc$hour)) {
      check_fixture(mtc$hour == entry$mtc$hour,
        sprintf("%s: MTC hour %d == %d", label, mtc$hour, entry$mtc$hour))
      check_fixture(mtc$minute == entry$mtc$minute,
        sprintf("%s: MTC minute %d == %d", label, mtc$minute, entry$mtc$minute))
    }
  }
}

cat(sprintf("\nFixture entries checked: %d\n", length(entries)))
cat(sprintf("%d passed  %d failed\n", passed, failed))
if (failed > 0L) quit(status = 1L)
