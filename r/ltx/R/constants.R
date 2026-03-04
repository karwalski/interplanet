# constants.R — LTX (Light-Time eXchange) Protocol constants
# Port of ltx-sdk.js v1.0.0

# ── Protocol version ──────────────────────────────────────────────────────────

#' LTX protocol version
PROTOCOL_VERSION <- "1.0"

#' SDK version
LTX_VERSION <- "1.0.0"

# ── Segment types ─────────────────────────────────────────────────────────────

#' Valid LTX segment type strings
SEG_TYPES <- c("PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE")

# ── Mode constants ────────────────────────────────────────────────────────────

#' LTX protocol modes
LTX_MODE_LIVE  <- "LTX-LIVE"
LTX_MODE_RELAY <- "LTX-RELAY"
LTX_MODE_ASYNC <- "LTX-ASYNC"
LTX_MODE_LTX   <- "LTX"

# ── Quantum ───────────────────────────────────────────────────────────────────

#' Default quantum in minutes (matches ltx-sdk.js DEFAULT_QUANTUM)
DEFAULT_QUANTUM <- 3L

# ── Default segment template ──────────────────────────────────────────────────

#' Default segment template — list of list(type, q) matching ltx-sdk.js
DEFAULT_SEGMENTS <- list(
  list(type = "PLAN_CONFIRM", q = 2L),
  list(type = "TX",           q = 2L),
  list(type = "RX",           q = 2L),
  list(type = "CAUCUS",       q = 2L),
  list(type = "TX",           q = 2L),
  list(type = "RX",           q = 2L),
  list(type = "BUFFER",       q = 1L)
)

# ── Default API base ──────────────────────────────────────────────────────────

#' Default LTX REST API base URL
DEFAULT_API_BASE <- "https://interplanet.live/api/ltx.php"
