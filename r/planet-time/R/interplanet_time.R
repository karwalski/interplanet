# interplanet_time.R — Package entry point
# Sources all module files in dependency order.
# Must be sourced with working directory set to the package root (r/).

# Determine the R/ directory relative to this file or the working directory
.find_r_dir <- function() {
  # When source() is called with a path, the file location is available
  # via sys.frame() in some R versions. Use it if available.
  this_file <- tryCatch({
    normalizePath(sys.frame(1)$ofile, mustWork = FALSE)
  }, error = function(e) "")

  if (nchar(this_file) > 0 && file.exists(this_file)) {
    return(dirname(normalizePath(this_file)))
  }

  # Fallback: look for R/ relative to the current working directory
  if (dir.exists("R") && file.exists(file.path("R", "constants.R"))) {
    return("R")
  }

  # Last resort: same directory (for when file is directly in R/)
  "."
}

.r_dir <- .find_r_dir()

source(file.path(.r_dir, "constants.R"))
source(file.path(.r_dir, "orbital.R"))
source(file.path(.r_dir, "time_calc.R"))
source(file.path(.r_dir, "scheduling.R"))
source(file.path(.r_dir, "formatting.R"))
