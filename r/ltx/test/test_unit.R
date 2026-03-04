# test/test_unit.R — Unit tests for InterplanetLtx R package
# Run: Rscript test/test_unit.R
# Requires: R >= 4.0, no mandatory external packages

source("R/constants.R")
source("R/ltx.R")

pass <- 0L
fail <- 0L

check <- function(cond, msg = "") {
  if (isTRUE(cond)) {
    pass <<- pass + 1L
    cat(sprintf("PASS: %s\n", msg))
  } else {
    fail <<- fail + 1L
    cat(sprintf("FAIL: %s\n", msg))
  }
}

# ── Section 1: Constants ──────────────────────────────────────────────────────

check(PROTOCOL_VERSION == "1.0",          "PROTOCOL_VERSION = 1.0")
check(LTX_VERSION == "1.0.0",             "LTX_VERSION = 1.0.0")
check(DEFAULT_QUANTUM == 3L,              "DEFAULT_QUANTUM = 3")
check(LTX_MODE_LIVE  == "LTX-LIVE",       "LTX_MODE_LIVE constant")
check(LTX_MODE_RELAY == "LTX-RELAY",      "LTX_MODE_RELAY constant")
check(LTX_MODE_ASYNC == "LTX-ASYNC",      "LTX_MODE_ASYNC constant")
check(LTX_MODE_LTX   == "LTX",            "LTX_MODE_LTX constant")
check(length(SEG_TYPES) == 6L,            "SEG_TYPES has 6 entries")
check("TX"           %in% SEG_TYPES,      "SEG_TYPES contains TX")
check("RX"           %in% SEG_TYPES,      "SEG_TYPES contains RX")
check("CAUCUS"       %in% SEG_TYPES,      "SEG_TYPES contains CAUCUS")
check("BUFFER"       %in% SEG_TYPES,      "SEG_TYPES contains BUFFER")
check("MERGE"        %in% SEG_TYPES,      "SEG_TYPES contains MERGE")
check("PLAN_CONFIRM" %in% SEG_TYPES,      "SEG_TYPES contains PLAN_CONFIRM")
check(length(DEFAULT_SEGMENTS) == 7L,     "DEFAULT_SEGMENTS has 7 entries")
check(DEFAULT_SEGMENTS[[1L]]$type == "PLAN_CONFIRM", "DEFAULT_SEGMENTS[1] = PLAN_CONFIRM")
check(DEFAULT_SEGMENTS[[2L]]$type == "TX",           "DEFAULT_SEGMENTS[2] = TX")
check(DEFAULT_SEGMENTS[[7L]]$type == "BUFFER",       "DEFAULT_SEGMENTS[7] = BUFFER")
check(DEFAULT_SEGMENTS[[7L]]$q == 1L,                "DEFAULT_SEGMENTS[7] q = 1")

# ── Section 2: create_plan ────────────────────────────────────────────────────

plan1 <- create_plan(
  host_name   = "Earth HQ",
  remote_name = "Mars Hab-01",
  delay       = 800,
  title       = "Test Session",
  start_iso   = "2026-01-01T12:00:00Z"
)

check(is.list(plan1),                           "create_plan returns list")
check(plan1$v == 2L,                            "create_plan: v = 2")
check(plan1$title == "Test Session",            "create_plan: title preserved")
check(plan1$start == "2026-01-01T12:00:00Z",    "create_plan: start preserved")
check(plan1$quantum == DEFAULT_QUANTUM,         "create_plan: default quantum")
check(plan1$mode == "LTX",                      "create_plan: default mode")
check(length(plan1$nodes) == 2L,                "create_plan: 2 nodes")
check(length(plan1$segments) == 7L,             "create_plan: 7 segments (default)")

# Node checks
n0 <- plan1$nodes[[1L]]
n1 <- plan1$nodes[[2L]]
check(n0$id   == "N0",              "Node 0 id = N0")
check(n0$name == "Earth HQ",        "Node 0 name = Earth HQ")
check(n0$role == "HOST",            "Node 0 role = HOST")
check(n0$delay == 0,                "Node 0 delay = 0")
check(n0$location == "earth",       "Node 0 location = earth")
check(n1$id   == "N1",              "Node 1 id = N1")
check(n1$name == "Mars Hab-01",     "Node 1 name = Mars Hab-01")
check(n1$role == "PARTICIPANT",     "Node 1 role = PARTICIPANT")
check(n1$delay == 800,              "Node 1 delay = 800")
check(n1$location == "mars",        "Node 1 location = mars")

# Default start is populated when start_iso = ""
plan_default <- create_plan()
check(nchar(plan_default$start) > 10L, "create_plan: default start is non-empty")
check(grepl("T", plan_default$start),  "create_plan: default start contains T")

# Custom mode and quantum
plan_custom <- create_plan(
  mode      = "LTX-ASYNC",
  quantum   = 5L,
  start_iso = "2026-06-01T09:00:00Z"
)
check(plan_custom$mode    == "LTX-ASYNC", "create_plan: custom mode")
check(plan_custom$quantum == 5L,          "create_plan: custom quantum")

# ── Section 3: total_min ──────────────────────────────────────────────────────

# Default segments: q = 2+2+2+2+2+2+1 = 13, quantum = 3 → 39 min
tm1 <- total_min(plan1)
check(tm1 == 39L, "total_min default plan = 39")

plan_q5 <- create_plan(quantum = 5L, start_iso = "2026-01-01T12:00:00Z")
tm5 <- total_min(plan_q5)
check(tm5 == 65L, "total_min quantum=5 plan = 65")

# ── Section 4: compute_segments ───────────────────────────────────────────────

segs <- compute_segments(plan1)
check(is.list(segs),               "compute_segments returns list")
check(length(segs) == 7L,          "compute_segments: 7 segments")
check(segs[[1L]]$type == "PLAN_CONFIRM", "compute_segments[1] type = PLAN_CONFIRM")
check(segs[[2L]]$type == "TX",           "compute_segments[2] type = TX")
check(segs[[7L]]$type == "BUFFER",       "compute_segments[7] type = BUFFER")

# start_ms of first segment = plan start
expected_start_ms <- as.numeric(as.POSIXct("2026-01-01T12:00:00Z",
                       format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")) * 1000
check(abs(segs[[1L]]$start_ms - expected_start_ms) < 1000, "compute_segments: start_ms matches")
# Each segment advances by q * quantum * 60000 ms
q_ms <- plan1$quantum * 60L * 1000L
check(segs[[2L]]$start_ms == segs[[1L]]$end_ms,             "compute_segments: contiguous")
check(segs[[1L]]$end_ms - segs[[1L]]$start_ms == 2L * q_ms, "compute_segments[1] dur = 2 quanta")
check(segs[[7L]]$dur_min == 1L * plan1$quantum,              "compute_segments[7] dur_min = 1 quantum")
# last segment end = start + total duration
total_ms <- total_min(plan1) * 60L * 1000L
check(abs(segs[[7L]]$end_ms - segs[[1L]]$start_ms - total_ms) < 1,
      "compute_segments: total span correct")

# ── Section 5: format_hms ────────────────────────────────────────────────────

check(format_hms(0)    == "00:00",       "format_hms(0) = 00:00")
check(format_hms(-5)   == "00:00",       "format_hms negative → 00:00")
check(format_hms(59)   == "00:59",       "format_hms(59) = 00:59")
check(format_hms(60)   == "01:00",       "format_hms(60) = 01:00")
check(format_hms(90)   == "01:30",       "format_hms(90) = 01:30")
check(format_hms(3600) == "01:00:00",    "format_hms(3600) = 01:00:00")
check(format_hms(3661) == "01:01:01",    "format_hms(3661) = 01:01:01")
check(format_hms(7322) == "02:02:02",    "format_hms(7322) = 02:02:02")
check(is.character(format_hms(100)),     "format_hms returns character")

# ── Section 6: format_utc ────────────────────────────────────────────────────

check(format_utc("2026-01-01T14:30:00Z") == "14:30:00 UTC", "format_utc ISO string")
check(format_utc("2026-06-15T00:00:00Z") == "00:00:00 UTC", "format_utc midnight")
check(is.character(format_utc("2026-01-01T12:00:00Z")),      "format_utc returns character")

# ── Section 7: encode_hash / decode_hash roundtrip ───────────────────────────

hash <- encode_hash(plan1)
check(is.character(hash),            "encode_hash returns character")
check(startsWith(hash, "#l="),       "encode_hash starts with #l=")
check(nchar(hash) > 10L,             "encode_hash non-trivial length")

plan_rt <- decode_hash(hash)
check(!is.null(plan_rt),                            "decode_hash returns non-null")
check(plan_rt$title == plan1$title,                 "decode_hash: title matches")
check(plan_rt$start == plan1$start,                 "decode_hash: start matches")
check(plan_rt$quantum == plan1$quantum,              "decode_hash: quantum matches")
check(plan_rt$mode == plan1$mode,                   "decode_hash: mode matches")
check(length(plan_rt$nodes) == 2L,                  "decode_hash: 2 nodes")
check(plan_rt$nodes[[1L]]$name == n0$name,          "decode_hash: host name matches")
check(plan_rt$nodes[[2L]]$delay == 800,             "decode_hash: participant delay = 800")
check(length(plan_rt$segments) == 7L,               "decode_hash: 7 segments")
check(plan_rt$segments[[1L]]$type == "PLAN_CONFIRM","decode_hash: seg[1] type = PLAN_CONFIRM")

# decode_hash accepts "l=..." without "#"
hash_no_hash <- sub("^#", "", hash)
plan_rt2 <- decode_hash(hash_no_hash)
check(!is.null(plan_rt2), "decode_hash accepts l=... without #")

# decode_hash accepts raw token
raw_token <- sub("^#l=", "", hash)
plan_rt3  <- decode_hash(raw_token)
check(!is.null(plan_rt3), "decode_hash accepts raw base64url token")

# Invalid hash returns NULL
check(is.null(decode_hash("not-valid-base64!!")), "decode_hash invalid returns NULL")

# ── Section 8: build_node_urls ────────────────────────────────────────────────

urls <- build_node_urls(plan1, "https://interplanet.live/ltx.html")
check(is.list(urls),                            "build_node_urls returns list")
check(length(urls) == 2L,                       "build_node_urls: 2 entries")
check(urls[[1L]]$node_id == "N0",               "build_node_urls[1] node_id = N0")
check(urls[[2L]]$node_id == "N1",               "build_node_urls[2] node_id = N1")
check(grepl("https://interplanet.live/ltx.html", urls[[1L]]$url), "build_node_urls[1] url contains base")
check(grepl("node=N0", urls[[1L]]$url),         "build_node_urls[1] url contains node=N0")
check(grepl("#l=",     urls[[1L]]$url),         "build_node_urls[1] url contains #l=")
check(grepl("node=N1", urls[[2L]]$url),         "build_node_urls[2] url contains node=N1")
check(urls[[1L]]$name == "Earth HQ",            "build_node_urls[1] name = Earth HQ")
check(urls[[2L]]$name == "Mars Hab-01",         "build_node_urls[2] name = Mars Hab-01")

# ── Section 9: make_plan_id ───────────────────────────────────────────────────

pid <- make_plan_id(plan1)
check(is.character(pid),            "make_plan_id returns character")
check(startsWith(pid, "LTX-"),      "make_plan_id starts with LTX-")
check(grepl("20260101", pid),       "make_plan_id contains date 20260101")
check(grepl("EARTHHQ",  pid),       "make_plan_id contains EARTHHQ")
check(grepl("MARS",     pid),       "make_plan_id contains MARS")
check(grepl("-v2-",     pid),       "make_plan_id contains -v2-")
# Hash is 8 hex chars
m <- regmatches(pid, regexpr("[0-9a-f]{8}$", pid))
check(length(m) == 1L && nchar(m) == 8L, "make_plan_id: last 8 chars are hex")

# Deterministic: same input = same output
pid2 <- make_plan_id(plan1)
check(pid == pid2, "make_plan_id is deterministic")

# Different plan → different ID
plan_diff <- create_plan(
  host_name   = "Ceres Station",
  remote_name = "Titan Base",
  delay       = 3600,
  start_iso   = "2026-03-01T08:00:00Z"
)
pid_diff <- make_plan_id(plan_diff)
check(pid != pid_diff, "make_plan_id differs for different plans")

# ── Section 10: generate_ics ─────────────────────────────────────────────────

ics <- generate_ics(plan1)
check(is.character(ics),                       "generate_ics returns character")
check(grepl("BEGIN:VCALENDAR", ics),            "ICS contains BEGIN:VCALENDAR")
check(grepl("END:VCALENDAR",   ics),            "ICS contains END:VCALENDAR")
check(grepl("BEGIN:VEVENT",    ics),            "ICS contains BEGIN:VEVENT")
check(grepl("END:VEVENT",      ics),            "ICS contains END:VEVENT")
check(grepl("VERSION:2.0",     ics),            "ICS contains VERSION:2.0")
check(grepl("PRODID:.*LTX",    ics),            "ICS PRODID contains LTX")
check(grepl("SUMMARY:Test Session", ics),       "ICS SUMMARY = Test Session")
check(grepl("LTX-PLANID:",     ics),            "ICS contains LTX-PLANID")
check(grepl("LTX-QUANTUM:",    ics),            "ICS contains LTX-QUANTUM")
check(grepl("LTX-MODE:",       ics),            "ICS contains LTX-MODE")
check(grepl("LTX-NODE:",       ics),            "ICS contains LTX-NODE")
check(grepl("LTX-DELAY;",      ics),            "ICS contains LTX-DELAY")
check(grepl("LTX-READINESS:",  ics),            "ICS contains LTX-READINESS")
check(grepl("LTX-LOCALTIME:",  ics),            "ICS contains LTX-LOCALTIME (mars node)")
check(grepl("DTSTART:",        ics),            "ICS contains DTSTART")
check(grepl("DTEND:",          ics),            "ICS contains DTEND")
# ICS lines separated by CRLF
check(grepl("\r\n", ics),                       "ICS uses CRLF line endings")

# ── Section 11: build_delay_matrix ───────────────────────────────────────────

dm <- build_delay_matrix(plan1)
check(is.list(dm),          "build_delay_matrix returns list")
check(length(dm) == 2L,     "build_delay_matrix: 2 entries for 2-node plan")
# N0→N1: delay = N1's delay (800)
dm_01 <- Filter(function(e) e$from_id == "N0" && e$to_id == "N1", dm)[[1L]]
check(dm_01$delay_seconds == 800, "delay_matrix N0→N1 = 800")
# N1→N0: delay = N1's delay (800)
dm_10 <- Filter(function(e) e$from_id == "N1" && e$to_id == "N0", dm)[[1L]]
check(dm_10$delay_seconds == 800, "delay_matrix N1→N0 = 800")

# ── Section 12: b64url roundtrip ─────────────────────────────────────────────

test_strings <- c(
  "hello world",
  '{"v":2,"title":"Test"}',
  "ASCII only",
  paste(rep("a", 100), collapse = "")
)
for (s in test_strings) {
  enc <- b64url_encode(s)
  dec <- b64url_decode(enc)
  check(identical(dec, s), sprintf("b64url roundtrip: %s", substr(s, 1L, 20L)))
  check(!grepl("=", enc),  sprintf("b64url no padding: %s", substr(s, 1L, 20L)))
  check(!grepl("\\+", enc) && !grepl("/", enc),
        sprintf("b64url URL-safe chars: %s", substr(s, 1L, 20L)))
}

# ── Section 13: JSON serialization ───────────────────────────────────────────

json_out <- .plan_to_json(plan1)
check(is.character(json_out),          ".plan_to_json returns character")
check(grepl('"v":2',      json_out),   ".plan_to_json: v=2 present")
check(grepl('"title"',    json_out),   ".plan_to_json: title key present")
check(grepl('"nodes"',    json_out),   ".plan_to_json: nodes key present")
check(grepl('"segments"', json_out),   ".plan_to_json: segments key present")
check(grepl('"delay":800', json_out),  ".plan_to_json: delay=800 present")

# Key order check: v must appear before title, title before start, etc.
v_pos    <- regexpr('"v"',       json_out)
ti_pos   <- regexpr('"title"',   json_out)
st_pos   <- regexpr('"start"',   json_out)
no_pos   <- regexpr('"nodes"',   json_out)
se_pos   <- regexpr('"segments"',json_out)
check(v_pos < ti_pos && ti_pos < st_pos && st_pos < no_pos && no_pos < se_pos,
      ".plan_to_json: canonical key order")

# ── Summary ───────────────────────────────────────────────────────────────────

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0L) quit(status = 1L)
