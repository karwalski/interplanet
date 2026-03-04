# ltx.R — LTX (Light-Time eXchange) SDK core functions
# Port of ltx-sdk.js — story 18.21

source("R/constants.R")

# ── Base64url helpers ─────────────────────────────────────────────────────────
# Uses base64enc package when available; otherwise a pure-R implementation.

# Pure R base64 alphabet (A-Z a-z 0-9 + /)
.B64_CHARS <- c(LETTERS, letters, as.character(0:9), "+", "/")

# Pure R base64 encode from a raw vector
.b64_encode_raw <- function(raw_bytes) {
  bytes <- as.integer(raw_bytes)
  n <- length(bytes)
  out <- character(ceiling(n / 3) * 4)
  idx <- 1L
  i <- 1L
  while (i <= n) {
    b0 <- bytes[i]
    b1 <- if (i + 1L <= n) bytes[i + 1L] else 0L
    b2 <- if (i + 2L <= n) bytes[i + 2L] else 0L
    out[idx]     <- .B64_CHARS[bitwShiftR(b0, 2L) + 1L]
    out[idx + 1L] <- .B64_CHARS[bitwOr(bitwShiftL(b0 %% 4L, 4L), bitwShiftR(b1, 4L)) + 1L]
    out[idx + 2L] <- if (i + 1L <= n) .B64_CHARS[bitwOr(bitwShiftL(b1 %% 16L, 2L), bitwShiftR(b2, 6L)) + 1L] else "="
    out[idx + 3L] <- if (i + 2L <= n) .B64_CHARS[(b2 %% 64L) + 1L] else "="
    idx <- idx + 4L
    i   <- i + 3L
  }
  paste(out[seq_len(idx - 1L)], collapse = "")
}

# Decode table: ASCII code → base64 value (or -1)
.B64_DECODE_TABLE <- local({
  tbl <- integer(256L)
  tbl[] <- -1L
  chars <- c(LETTERS, letters, as.character(0:9), "+", "/")
  for (i in seq_along(chars)) tbl[utf8ToInt(chars[i]) + 1L] <- i - 1L
  tbl
})

# Pure R base64 decode to raw vector
.b64_decode_raw <- function(b64) {
  b64 <- gsub("=", "", b64)
  chars <- strsplit(b64, "")[[1L]]
  if (length(chars) == 0L) return(raw(0L))
  vals <- .B64_DECODE_TABLE[utf8ToInt(paste(chars, collapse = "")) + 1L]
  n    <- length(vals)
  # allocate maximum possible bytes
  out <- raw(floor(n * 3L / 4L) + 1L)
  j   <- 1L
  i   <- 1L
  while (i + 1L <= n) {
    v0 <- vals[i]; v1 <- vals[i + 1L]
    out[j] <- as.raw(bitwOr(bitwShiftL(v0, 2L), bitwShiftR(v1, 4L)))
    j <- j + 1L
    if (i + 2L <= n) {
      v2 <- vals[i + 2L]
      out[j] <- as.raw(bitwOr(bitwShiftL(bitwAnd(v1, 0xFL), 4L), bitwShiftR(v2, 2L)))
      j <- j + 1L
    }
    if (i + 3L <= n) {
      v3 <- vals[i + 3L]
      out[j] <- as.raw(bitwOr(bitwShiftL(bitwAnd(v2, 0x3L), 6L), v3))
      j <- j + 1L
    }
    i <- i + 4L
  }
  out[seq_len(j - 1L)]
}

# Convert a character string to raw UTF-8 bytes
.str_to_raw <- function(s) {
  writeBin(enc2utf8(s), raw())
}

#' Encode a character string to base64url (no padding).
#' @param s character string
#' @return base64url-encoded character string (no padding, URL-safe)
b64url_encode <- function(s) {
  raw_bytes <- .str_to_raw(s)
  b64 <- if (requireNamespace("base64enc", quietly = TRUE)) {
    base64enc::base64encode(raw_bytes)
  } else if (requireNamespace("openssl", quietly = TRUE)) {
    as.character(openssl::base64_encode(raw_bytes))
  } else {
    .b64_encode_raw(raw_bytes)
  }
  # Convert to base64url: replace +/ with -_, strip = and any newlines
  gsub("[\n\r=]", "", chartr("+/", "-_", b64))
}

#' Decode a base64url string back to a character string.
#' @param token base64url character string
#' @return decoded character string or NULL on error
b64url_decode <- function(token) {
  if (is.null(token) || nchar(token) == 0L) return(NULL)
  # Convert base64url to standard base64
  b64 <- chartr("-_", "+/", token)
  pad <- (4L - nchar(b64) %% 4L) %% 4L
  b64 <- paste0(b64, paste(rep("=", pad), collapse = ""))
  tryCatch({
    raw_bytes <- if (requireNamespace("base64enc", quietly = TRUE)) {
      base64enc::base64decode(b64)
    } else if (requireNamespace("openssl", quietly = TRUE)) {
      openssl::base64_decode(b64)
    } else {
      .b64_decode_raw(b64)
    }
    rawToChar(raw_bytes)
  }, error = function(e) NULL)
}

# ── JSON helpers ──────────────────────────────────────────────────────────────
# Minimal serializer/parser sufficient for the LTX plan structure.
# Uses jsonlite when available.

#' Serialize a scalar or simple R value to a JSON string.
#' Handles: NULL, logical, character (length-1), numeric (length-1),
#' named list (object), unnamed list (array).
#' @param x R value
#' @return character JSON string
.to_json <- function(x) {
  if (is.null(x)) return("null")
  if (is.logical(x) && length(x) == 1L) return(if (isTRUE(x)) "true" else "false")
  if (is.character(x) && length(x) == 1L) {
    s <- x
    s <- gsub("\\\\", "\\\\\\\\", s)
    s <- gsub('"',    '\\\\"',    s)
    s <- gsub("\n",   "\\\\n",    s)
    s <- gsub("\r",   "\\\\r",    s)
    s <- gsub("\t",   "\\\\t",    s)
    return(paste0('"', s, '"'))
  }
  if (is.numeric(x) && length(x) == 1L) {
    if (is.integer(x)) return(as.character(x))
    formatted <- format(x, scientific = FALSE, trim = TRUE)
    # Remove trailing zeros after decimal point
    formatted <- sub("(\\.\\d*?)0+$", "\\1", formatted)
    formatted <- sub("\\.$", "", formatted)
    return(formatted)
  }
  if (is.list(x)) {
    nms <- names(x)
    if (!is.null(nms) && length(nms) > 0L) {
      pairs <- mapply(function(k, v) paste0('"', k, '":', .to_json(v)),
                      nms, x, SIMPLIFY = TRUE)
      return(paste0("{", paste(pairs, collapse = ","), "}"))
    } else {
      items <- vapply(x, .to_json, character(1L))
      return(paste0("[", paste(items, collapse = ","), "]"))
    }
  }
  stop(sprintf(".to_json: unsupported type '%s'", class(x)[[1L]]))
}

#' Parse a JSON string into an R list/value.
#' Uses jsonlite when available; otherwise uses the built-in parser.
#' @param json_str character JSON string
#' @return R list or scalar value
.from_json <- function(json_str) {
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    return(jsonlite::fromJSON(json_str, simplifyVector = FALSE))
  }
  .parse_val <- function(s, pos) {
    pos <- .skip_ws(s, pos)
    ch <- substr(s, pos, pos)
    if (ch == '{') return(.parse_object(s, pos))
    if (ch == '[') return(.parse_array(s,  pos))
    .parse_primitive(s, pos)
  }

  .skip_ws <- function(s, pos) {
    while (pos <= nchar(s) && substr(s, pos, pos) %in% c(" ", "\t", "\n", "\r"))
      pos <- pos + 1L
    pos
  }

  .parse_primitive <- function(s, pos) {
    ch <- substr(s, pos, pos)
    # String
    if (ch == '"') {
      end <- pos + 1L
      while (end <= nchar(s)) {
        c2 <- substr(s, end, end)
        if (c2 == '\\') { end <- end + 2L; next }
        if (c2 == '"') break
        end <- end + 1L
      }
      raw <- substr(s, pos + 1L, end - 1L)
      raw <- gsub('\\\\"', '"',    raw)
      raw <- gsub("\\\\n",  "\n",  raw)
      raw <- gsub("\\\\r",  "\r",  raw)
      raw <- gsub("\\\\t",  "\t",  raw)
      raw <- gsub("\\\\\\\\", "\\\\", raw)
      return(list(val = raw, pos = end + 1L))
    }
    # Number
    if (grepl("^[-0-9]", ch)) {
      rest <- substr(s, pos, nchar(s))
      m <- regmatches(rest, regexpr("^-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?", rest))
      num <- if (grepl("\\.", m) || grepl("[eE]", m)) as.double(m) else as.integer(m)
      return(list(val = num, pos = pos + nchar(m)))
    }
    # Literals
    rest5 <- substr(s, pos, pos + 4L)
    if (startsWith(rest5, "true"))  return(list(val = TRUE,  pos = pos + 4L))
    if (startsWith(rest5, "false")) return(list(val = FALSE, pos = pos + 5L))
    if (startsWith(rest5, "null"))  return(list(val = NULL,  pos = pos + 4L))
    stop(sprintf("Unexpected JSON at pos %d: '%s'", pos, substr(s, pos, pos + 10L)))
  }

  .parse_object <- function(s, pos) {
    pos <- pos + 1L
    result <- list()
    pos <- .skip_ws(s, pos)
    if (substr(s, pos, pos) == '}') return(list(val = result, pos = pos + 1L))
    repeat {
      pos   <- .skip_ws(s, pos)
      key_r <- .parse_primitive(s, pos)
      key   <- key_r$val; pos <- .skip_ws(s, key_r$pos)
      pos   <- pos + 1L   # skip ':'
      val_r <- .parse_val(s, pos)
      result[[key]] <- val_r$val; pos <- .skip_ws(s, val_r$pos)
      ch <- substr(s, pos, pos)
      if (ch == '}') { pos <- pos + 1L; break }
      pos <- pos + 1L     # skip ','
    }
    list(val = result, pos = pos)
  }

  .parse_array <- function(s, pos) {
    pos <- pos + 1L
    result <- list()
    pos <- .skip_ws(s, pos)
    if (substr(s, pos, pos) == ']') return(list(val = result, pos = pos + 1L))
    repeat {
      val_r  <- .parse_val(s, pos)
      result <- c(result, list(val_r$val)); pos <- .skip_ws(s, val_r$pos)
      ch <- substr(s, pos, pos)
      if (ch == ']') { pos <- pos + 1L; break }
      pos <- pos + 1L     # skip ','
    }
    list(val = result, pos = pos)
  }

  r <- .parse_val(json_str, 1L)
  r$val
}

# ── JSON serialization of LTX plan (canonical key order) ─────────────────────

#' Serialize an LtxPlan list to JSON with canonical key order.
#' Key order: v, title, start, quantum, mode, nodes, segments.
#' Node order: id, name, role, delay, location.
#' Segment order: type, q.
#' @param plan LtxPlan list
#' @return character JSON string
.plan_to_json <- function(plan) {
  .node_to_json <- function(n) {
    paste0(
      '{"id":', .to_json(n$id),
      ',"name":', .to_json(n$name),
      ',"role":', .to_json(n$role),
      ',"delay":', .to_json(n$delay),
      ',"location":', .to_json(n$location),
      '}'
    )
  }
  .seg_to_json <- function(s) {
    paste0('{"type":', .to_json(s$type), ',"q":', .to_json(s$q), '}')
  }
  nodes_json <- paste(vapply(plan$nodes,    .node_to_json, character(1L)), collapse = ",")
  segs_json  <- paste(vapply(plan$segments, .seg_to_json,  character(1L)), collapse = ",")

  paste0(
    '{"v":', .to_json(plan$v),
    ',"title":', .to_json(plan$title),
    ',"start":', .to_json(plan$start),
    ',"quantum":', .to_json(plan$quantum),
    ',"mode":', .to_json(plan$mode),
    ',"nodes":[', nodes_json, ']',
    ',"segments":[', segs_json, ']',
    '}'
  )
}

# ── Formatting utilities ──────────────────────────────────────────────────────

#' Format seconds as "HH:MM:SS" (hours present) or "MM:SS" (hours absent).
#' Negative input is clamped to 0.
#' @param sec numeric seconds
#' @return character string e.g. "01:30:00" or "03:15"
format_hms <- function(sec) {
  if (sec < 0) sec <- 0
  h <- as.integer(floor(sec / 3600))
  m <- as.integer(floor((sec %% 3600) / 60))
  s <- as.integer(floor(sec %% 60))
  if (h > 0L) {
    sprintf("%02d:%02d:%02d", h, m, s)
  } else {
    sprintf("%02d:%02d", m, s)
  }
}

#' Format a date-time as "HH:MM:SS UTC".
#' Accepts an ISO 8601 character string, a POSIXct, or numeric seconds-since-epoch.
#' @param dt character ISO string, POSIXct, or numeric
#' @return character string e.g. "14:30:00 UTC"
format_utc <- function(dt) {
  if (is.character(dt)) {
    dt <- as.POSIXct(dt, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  } else if (is.numeric(dt)) {
    dt <- as.POSIXct(dt, origin = "1970-01-01", tz = "UTC")
  }
  paste0(format(dt, "%H:%M:%S", tz = "UTC"), " UTC")
}

# ── Plan construction ─────────────────────────────────────────────────────────

#' Create an LtxNode list.
#' @param id       character node ID (e.g. "N0")
#' @param name     character display name
#' @param role     character "HOST" or "PARTICIPANT"
#' @param delay    numeric one-way signal delay in seconds (default 0)
#' @param location character location key (default "earth")
#' @return named list (LtxNode)
ltx_node <- function(id, name, role, delay = 0, location = "earth") {
  list(id = id, name = name, role = role, delay = delay, location = location)
}

#' Create an LtxSegmentSpec list.
#' @param type character segment type (one of SEG_TYPES)
#' @param q    integer number of quanta
#' @return named list
ltx_segment_spec <- function(type, q) {
  list(type = type, q = as.integer(q))
}

# Internal: return current UTC time rounded down to the minute, plus 5 min, as ISO
.default_start <- function() {
  now  <- as.POSIXct(Sys.time(), tz = "UTC")
  secs <- as.numeric(format(now, "%S", tz = "UTC"))
  now  <- now - secs + 5 * 60
  format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

#' Create a new LTX session plan.
#'
#' Creates a plan with two nodes: N0=HOST (delay=0) and N1=PARTICIPANT.
#'
#' @param host_name       character host display name (default "Earth HQ")
#' @param remote_name     character participant display name (default "Mars Hab-01")
#' @param delay           numeric one-way signal delay in seconds (default 0)
#' @param title           character session title (default "LTX Session")
#' @param start_iso       character ISO 8601 UTC start; default: 5 min from now
#' @param quantum         integer minutes per quantum (default DEFAULT_QUANTUM = 3)
#' @param mode            character protocol mode (default "LTX")
#' @param host_location   character host location key (default "earth")
#' @param remote_location character participant location key (default "mars")
#' @param segments        list of segment specs; default: DEFAULT_SEGMENTS
#' @return LtxPlan list (v, title, start, quantum, mode, nodes, segments)
create_plan <- function(
    host_name       = "Earth HQ",
    remote_name     = "Mars Hab-01",
    delay           = 0,
    title           = "LTX Session",
    start_iso       = "",
    quantum         = DEFAULT_QUANTUM,
    mode            = "LTX",
    host_location   = "earth",
    remote_location = "mars",
    segments        = NULL
) {
  if (nchar(start_iso) == 0L) start_iso <- .default_start()
  if (is.null(segments))      segments  <- DEFAULT_SEGMENTS

  nodes     <- list(
    ltx_node("N0", host_name,   "HOST",        delay = 0,     location = host_location),
    ltx_node("N1", remote_name, "PARTICIPANT", delay = delay, location = remote_location)
  )
  seg_specs <- lapply(segments, function(s) ltx_segment_spec(s$type, s$q))

  list(
    v        = 2L,
    title    = title,
    start    = start_iso,
    quantum  = as.integer(quantum),
    mode     = mode,
    nodes    = nodes,
    segments = seg_specs
  )
}

# ── Segment computation ───────────────────────────────────────────────────────

#' Compute timed segments for a plan.
#'
#' @param plan LtxPlan list
#' @return list of LtxSegmentResult, each element a list with:
#'   type (character), start_ms (numeric), end_ms (numeric), dur_min (numeric)
compute_segments <- function(plan) {
  q_ms <- plan$quantum * 60 * 1000
  t    <- .iso_to_ms(plan$start)
  lapply(plan$segments, function(s) {
    dur_ms <- s$q * q_ms
    end_ms <- t + dur_ms
    out    <- list(type     = s$type,
                   start_ms = t,
                   end_ms   = end_ms,
                   dur_min  = s$q * plan$quantum)
    t <<- end_ms
    out
  })
}

# Internal: ISO 8601 UTC string → milliseconds since Unix epoch
.iso_to_ms <- function(iso) {
  iso <- sub("\\.\\d+Z$", "Z", iso)
  dt  <- as.POSIXct(iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  as.numeric(dt) * 1000
}

# Internal: ms since epoch → iCalendar date-time string
.ms_to_ics_dt <- function(ms) {
  dt <- as.POSIXct(ms / 1000, origin = "1970-01-01", tz = "UTC")
  format(dt, "%Y%m%dT%H%M%SZ", tz = "UTC")
}

# ── Total duration ────────────────────────────────────────────────────────────

#' Total session duration in minutes.
#' @param plan LtxPlan list
#' @return numeric total minutes
total_min <- function(plan) {
  sum(vapply(plan$segments, function(s) s$q * plan$quantum, numeric(1L)))
}

# ── Plan ID ───────────────────────────────────────────────────────────────────

# DJB2-style hash using double-precision arithmetic to avoid R integer overflow.
# Keeps the lower 32 bits (mod 2^32) at each step, stored as a double.
# Deterministic and sufficient for plan ID generation.
.hash_djb2 <- function(s) {
  chars <- utf8ToInt(s)
  h <- 0  # double
  for (ch in chars) {
    # h = (31 * h + charCode) mod 2^32
    h <- (31 * h + ch) %% (2^32)
  }
  as.integer(h %% (2^31 - 1))  # keep as non-negative integer for sprintf %08x
}

#' Compute a deterministic plan ID.
#' ID format: "LTX-{date}-{host}-{nodes}-v2-{hash8hex}"
#' @param plan LtxPlan list
#' @return character string e.g. "LTX-20260101-EARTHHQ-MARS-v2-a3b2c1d0"
make_plan_id <- function(plan) {
  date_str <- gsub("-", "", substr(plan$start, 1L, 10L))
  nodes    <- plan$nodes
  host_str <- if (length(nodes) >= 1L) {
    substr(gsub(" ", "", toupper(nodes[[1L]]$name)), 1L, 8L)
  } else "HOST"
  node_str <- if (length(nodes) > 1L) {
    parts <- vapply(nodes[-1L], function(n) {
      substr(gsub(" ", "", toupper(n$name)), 1L, 4L)
    }, character(1L))
    substr(paste(parts, collapse = "-"), 1L, 16L)
  } else "RX"

  raw <- .plan_to_json(plan)
  h   <- .hash_djb2(raw)
  hex <- sprintf("%08x", h)
  sprintf("LTX-%s-%s-%s-v2-%s", date_str, host_str, node_str, hex)
}

# ── Hash encoding / decoding ──────────────────────────────────────────────────

#' Encode a plan to a URL hash fragment ("#l=<base64url>").
#' JSON uses canonical key order: v, title, start, quantum, mode, nodes, segments.
#' @param plan LtxPlan list
#' @return character string starting with "#l="
encode_hash <- function(plan) {
  json <- .plan_to_json(plan)
  paste0("#l=", b64url_encode(json))
}

#' Decode a plan from a URL hash fragment.
#' Accepts "#l=...", "l=...", or the raw base64url token.
#' @param hash_str character
#' @return LtxPlan list or NULL on error
decode_hash <- function(hash_str) {
  token <- sub("^#?l=", "", hash_str)
  json  <- b64url_decode(token)
  if (is.null(json)) return(NULL)
  tryCatch({
    d <- .from_json(json)
    if (is.null(d)) return(NULL)
    nodes <- lapply(d$nodes, function(n) {
      ltx_node(
        id       = n$id,
        name     = n$name,
        role     = n$role,
        delay    = if (is.null(n$delay)) 0 else n$delay,
        location = if (is.null(n$location)) "earth" else n$location
      )
    })
    segs <- lapply(d$segments, function(s) {
      ltx_segment_spec(s$type, s$q)
    })
    list(
      v        = if (is.null(d$v))       2L else as.integer(d$v),
      title    = if (is.null(d$title))   "" else d$title,
      start    = if (is.null(d$start))   "" else d$start,
      quantum  = if (is.null(d$quantum)) DEFAULT_QUANTUM else as.integer(d$quantum),
      mode     = if (is.null(d$mode))    "LTX" else d$mode,
      nodes    = nodes,
      segments = segs
    )
  }, error = function(e) NULL)
}

# ── Node URLs ─────────────────────────────────────────────────────────────────

#' Build perspective URLs for all nodes in a plan.
#' @param plan     LtxPlan list
#' @param base_url character base page URL (e.g. "https://interplanet.live/ltx.html")
#' @return list of lists, each with node_id, name, url
build_node_urls <- function(plan, base_url = "") {
  json       <- .plan_to_json(plan)
  token      <- paste0("#l=", b64url_encode(json))
  clean_base <- sub("#.*$", "", sub("\\?.*$", "", base_url))
  lapply(plan$nodes, function(n) {
    list(
      node_id = n$id,
      name    = n$name,
      url     = paste0(clean_base, "?node=", n$id, token)
    )
  })
}

# ── ICS generation ────────────────────────────────────────────────────────────

#' Generate LTX-extended iCalendar (.ics) content for a plan.
#' Includes LTX-NODE, LTX-DELAY, and LTX-LOCALTIME extension properties.
#' @param plan LtxPlan list
#' @return character ICS string (lines joined by CRLF)
generate_ics <- function(plan) {
  segs     <- compute_segments(plan)
  start_ms <- segs[[1L]]$start_ms
  end_ms   <- segs[[length(segs)]]$end_ms
  plan_id  <- make_plan_id(plan)
  nodes    <- plan$nodes
  host     <- if (length(nodes) >= 1L) nodes[[1L]] else
    list(name = "Earth HQ", role = "HOST", delay = 0, location = "earth")
  parts    <- if (length(nodes) > 1L) nodes[-1L] else list()
  seg_tpl  <- paste(vapply(plan$segments, function(s) s$type, character(1L)), collapse = ",")

  now_stamp <- format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")

  .to_id <- function(name) gsub(" ", "-", toupper(name))

  node_lines <- vapply(nodes, function(n) {
    sprintf("LTX-NODE:ID=%s;ROLE=%s", .to_id(n$name), n$role)
  }, character(1L))

  delay_lines <- if (length(parts) > 0L) {
    vapply(parts, function(p) {
      d <- as.integer(round(if (is.null(p$delay)) 0 else p$delay))
      sprintf("LTX-DELAY;NODEID=%s:ONEWAY-MIN=%d;ONEWAY-MAX=%d;ONEWAY-ASSUMED=%d",
              .to_id(p$name), d, d + 120L, d)
    }, character(1L))
  } else character(0L)

  local_time_lines <- {
    mars_nodes <- Filter(function(n) isTRUE(n$location == "mars"), nodes)
    if (length(mars_nodes) > 0L) {
      vapply(mars_nodes, function(n) {
        sprintf("LTX-LOCALTIME:NODE=%s;SCHEME=LMST;PARAMS=LONGITUDE:0E", .to_id(n$name))
      }, character(1L))
    } else character(0L)
  }

  host_name  <- host$name
  part_names <- if (length(parts) > 0L) {
    paste(vapply(parts, function(p) p$name, character(1L)), collapse = ", ")
  } else "remote nodes"

  delay_desc <- if (length(parts) > 0L) {
    paste(vapply(parts, function(p) {
      d_min <- as.integer(round((if (is.null(p$delay)) 0 else p$delay) / 60))
      sprintf("%s: %d min one-way", p$name, d_min)
    }, character(1L)), collapse = " \u00b7 ")
  } else "no participant delay configured"

  lines <- c(
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//InterPlanet//LTX v1.1//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    sprintf("UID:%s@interplanet.live", plan_id),
    sprintf("DTSTAMP:%s", now_stamp),
    sprintf("DTSTART:%s", .ms_to_ics_dt(start_ms)),
    sprintf("DTEND:%s",   .ms_to_ics_dt(end_ms)),
    sprintf("SUMMARY:%s", plan$title),
    sprintf("DESCRIPTION:LTX session \u2014 %s with %s\\nSignal delays: %s\\nMode: %s \u00b7 Segment plan: %s\\nGenerated by InterPlanet (https://interplanet.live)",
            host_name, part_names, delay_desc, plan$mode, seg_tpl),
    "LTX:1",
    sprintf("LTX-PLANID:%s", plan_id),
    sprintf("LTX-QUANTUM:PT%dM", plan$quantum),
    sprintf("LTX-SEGMENT-TEMPLATE:%s", seg_tpl),
    sprintf("LTX-MODE:%s", plan$mode),
    node_lines,
    delay_lines,
    "LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY",
    local_time_lines,
    "END:VEVENT",
    "END:VCALENDAR"
  )
  paste(lines, collapse = "\r\n")
}

# ── Delay matrix ──────────────────────────────────────────────────────────────

#' Build a flat delay matrix for all node pairs in a plan.
#' Matches ltx-sdk.js buildDelayMatrix logic.
#' @param plan LtxPlan list
#' @return list of lists, each with from_id, from_name, to_id, to_name, delay_seconds
build_delay_matrix <- function(plan) {
  nodes  <- plan$nodes
  result <- list()
  for (i in seq_along(nodes)) {
    for (j in seq_along(nodes)) {
      if (i == j) next
      from <- nodes[[i]]; to <- nodes[[j]]
      fd   <- if (is.null(from$delay)) 0 else from$delay
      td   <- if (is.null(to$delay))   0 else to$delay
      delay_seconds <- if (fd == 0 || i == 1L) {
        td
      } else if (td == 0 || j == 1L) {
        fd
      } else {
        fd + td
      }
      result <- c(result, list(list(
        from_id       = from$id,
        from_name     = from$name,
        to_id         = to$id,
        to_name       = to$name,
        delay_seconds = delay_seconds
      )))
    }
  }
  result
}
