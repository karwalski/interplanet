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
#' speaker and label are the optional attribution of LTX-SPECIFICATION.md
#' 3.4.1; NULL is absent and is left out of the list, so the segment
#' serialises as {type, q, speaker?, label?} in ltx-sdk.js key order.
#' @param type    character segment type (one of SEG_TYPES)
#' @param q       integer number of quanta
#' @param speaker character presenting node id (e.g. "N1"), or NULL
#' @param label   character agenda title, or NULL
#' @return named list
ltx_segment_spec <- function(type, q, speaker = NULL, label = NULL) {
  s <- list(type = type, q = as.integer(q))
  if (!is.null(speaker)) s$speaker <- speaker
  if (!is.null(label))   s$label   <- label
  s
}

# ECMAScript \s (WhiteSpace and LineTerminator) as code points. The POSIX
# [[:space:]] class depends on the locale: in C.UTF-8 it keeps U+00A0 and
# U+FEFF, which JavaScript strips, and in the C locale it misreads UTF-8.
.JS_SPACE <- c(9:13, 32L, 160L, 5760L, 8192:8202, 8232L, 8233L, 8239L, 8287L, 12288L, 65279L)

# name.replace(/\s+/g, rep) with JavaScript's \s
.js_replace_space <- function(name, rep = "") {
  cps <- utf8ToInt(enc2utf8(name))
  if (length(cps) == 0L) return("")
  sp  <- cps %in% .JS_SPACE
  if (!any(sp)) return(intToUtf8(cps))
  run_start <- sp & !c(FALSE, head(sp, -1L))
  out <- vapply(seq_along(cps), function(i) {
    if (!sp[i]) intToUtf8(cps[i]) else if (run_start[i]) rep else ""
  }, character(1L))
  paste(out, collapse = "")
}

# s.slice(0, n) in UTF-16 code units. When the cut splits a surrogate pair
# JS keeps the lone high surrogate; an R string (UTF-8) cannot hold one, so
# it becomes U+FFFD, the UTF-8 form of the JS id (planIdUtf8 in
# spec/golden/plan-id-prefixes.json).
.utf16_slice <- function(s, n) {
  cps <- utf8ToInt(enc2utf8(s))
  if (length(cps) == 0L) return("")
  units <- cumsum(ifelse(cps >= 65536L, 2L, 1L))
  keep <- cps[units <= n]
  if (length(keep) < length(cps) && (if (length(keep)) units[length(keep)] else 0L) < n)
    keep <- c(keep, 0xFFFDL)
  if (length(keep) == 0L) "" else intToUtf8(keep)
}

# JS String.prototype.toUpperCase of a UTF-8 string: the full, locale
# independent Unicode case mapping (base toupper() is locale dependent and
# 1:1 only, so 'ß' stays 'ß' where JS gives "SS"), from the generated
# table below: 1:1 runs and special casings.
.js_toupper <- function(s) {
  cps <- utf8ToInt(enc2utf8(s))
  if (length(cps) == 0L) return("")
  out <- unlist(lapply(cps, function(cp) {
    if (cp >= 97L && cp <= 122L) return(cp - 32L)
    if (cp < 181L) return(cp)
    sp <- which(.ltx_upper_special[, 1L] == cp)
    if (length(sp)) { up <- .ltx_upper_special[sp[1L], 2:4]; return(up[up != 0L]) }
    r <- .ltx_upper_runs
    hit <- which(r[, 1L] <= cp & cp <= r[, 2L] & (cp - r[, 1L]) %% r[, 3L] == 0L)
    if (length(hit)) cp + r[hit[1L], 4L] else cp
  }))
  intToUtf8(out)
}

# BEGIN GENERATED UPPER TABLE
# Generated by scripts/conformance/gen-upper-tables.js from JS toUpperCase, Unicode 17.0 (node 22.22.2).
# first, last, stride, delta (flattened, 4 per run)
.ltx_upper_runs <- matrix(c(
  97L, 122L, 1L, -32L, 181L, 181L, 1L, 743L, 224L, 246L, 1L, -32L,
  248L, 254L, 1L, -32L, 255L, 255L, 1L, 121L, 257L, 303L, 2L, -1L,
  305L, 305L, 1L, -232L, 307L, 311L, 2L, -1L, 314L, 328L, 2L, -1L,
  331L, 375L, 2L, -1L, 378L, 382L, 2L, -1L, 383L, 383L, 1L, -300L,
  384L, 384L, 1L, 195L, 387L, 389L, 2L, -1L, 392L, 392L, 1L, -1L,
  396L, 396L, 1L, -1L, 402L, 402L, 1L, -1L, 405L, 405L, 1L, 97L,
  409L, 409L, 1L, -1L, 410L, 410L, 1L, 163L, 411L, 411L, 1L, 42561L,
  414L, 414L, 1L, 130L, 417L, 421L, 2L, -1L, 424L, 424L, 1L, -1L,
  429L, 429L, 1L, -1L, 432L, 432L, 1L, -1L, 436L, 438L, 2L, -1L,
  441L, 441L, 1L, -1L, 445L, 445L, 1L, -1L, 447L, 447L, 1L, 56L,
  453L, 453L, 1L, -1L, 454L, 454L, 1L, -2L, 456L, 456L, 1L, -1L,
  457L, 457L, 1L, -2L, 459L, 459L, 1L, -1L, 460L, 460L, 1L, -2L,
  462L, 476L, 2L, -1L, 477L, 477L, 1L, -79L, 479L, 495L, 2L, -1L,
  498L, 498L, 1L, -1L, 499L, 499L, 1L, -2L, 501L, 501L, 1L, -1L,
  505L, 543L, 2L, -1L, 547L, 563L, 2L, -1L, 572L, 572L, 1L, -1L,
  575L, 576L, 1L, 10815L, 578L, 578L, 1L, -1L, 583L, 591L, 2L, -1L,
  592L, 592L, 1L, 10783L, 593L, 593L, 1L, 10780L, 594L, 594L, 1L, 10782L,
  595L, 595L, 1L, -210L, 596L, 596L, 1L, -206L, 598L, 599L, 1L, -205L,
  601L, 601L, 1L, -202L, 603L, 603L, 1L, -203L, 604L, 604L, 1L, 42319L,
  608L, 608L, 1L, -205L, 609L, 609L, 1L, 42315L, 611L, 611L, 1L, -207L,
  612L, 612L, 1L, 42343L, 613L, 613L, 1L, 42280L, 614L, 614L, 1L, 42308L,
  616L, 616L, 1L, -209L, 617L, 617L, 1L, -211L, 618L, 618L, 1L, 42308L,
  619L, 619L, 1L, 10743L, 620L, 620L, 1L, 42305L, 623L, 623L, 1L, -211L,
  625L, 625L, 1L, 10749L, 626L, 626L, 1L, -213L, 629L, 629L, 1L, -214L,
  637L, 637L, 1L, 10727L, 640L, 640L, 1L, -218L, 642L, 642L, 1L, 42307L,
  643L, 643L, 1L, -218L, 647L, 647L, 1L, 42282L, 648L, 648L, 1L, -218L,
  649L, 649L, 1L, -69L, 650L, 651L, 1L, -217L, 652L, 652L, 1L, -71L,
  658L, 658L, 1L, -219L, 669L, 669L, 1L, 42261L, 670L, 670L, 1L, 42258L,
  837L, 837L, 1L, 84L, 881L, 883L, 2L, -1L, 887L, 887L, 1L, -1L,
  891L, 893L, 1L, 130L, 940L, 940L, 1L, -38L, 941L, 943L, 1L, -37L,
  945L, 961L, 1L, -32L, 962L, 962L, 1L, -31L, 963L, 971L, 1L, -32L,
  972L, 972L, 1L, -64L, 973L, 974L, 1L, -63L, 976L, 976L, 1L, -62L,
  977L, 977L, 1L, -57L, 981L, 981L, 1L, -47L, 982L, 982L, 1L, -54L,
  983L, 983L, 1L, -8L, 985L, 1007L, 2L, -1L, 1008L, 1008L, 1L, -86L,
  1009L, 1009L, 1L, -80L, 1010L, 1010L, 1L, 7L, 1011L, 1011L, 1L, -116L,
  1013L, 1013L, 1L, -96L, 1016L, 1016L, 1L, -1L, 1019L, 1019L, 1L, -1L,
  1072L, 1103L, 1L, -32L, 1104L, 1119L, 1L, -80L, 1121L, 1153L, 2L, -1L,
  1163L, 1215L, 2L, -1L, 1218L, 1230L, 2L, -1L, 1231L, 1231L, 1L, -15L,
  1233L, 1327L, 2L, -1L, 1377L, 1414L, 1L, -48L, 4304L, 4346L, 1L, 3008L,
  4349L, 4351L, 1L, 3008L, 5112L, 5117L, 1L, -8L, 7296L, 7296L, 1L, -6254L,
  7297L, 7297L, 1L, -6253L, 7298L, 7298L, 1L, -6244L, 7299L, 7300L, 1L, -6242L,
  7301L, 7301L, 1L, -6243L, 7302L, 7302L, 1L, -6236L, 7303L, 7303L, 1L, -6181L,
  7304L, 7304L, 1L, 35266L, 7306L, 7306L, 1L, -1L, 7545L, 7545L, 1L, 35332L,
  7549L, 7549L, 1L, 3814L, 7566L, 7566L, 1L, 35384L, 7681L, 7829L, 2L, -1L,
  7835L, 7835L, 1L, -59L, 7841L, 7935L, 2L, -1L, 7936L, 7943L, 1L, 8L,
  7952L, 7957L, 1L, 8L, 7968L, 7975L, 1L, 8L, 7984L, 7991L, 1L, 8L,
  8000L, 8005L, 1L, 8L, 8017L, 8023L, 2L, 8L, 8032L, 8039L, 1L, 8L,
  8048L, 8049L, 1L, 74L, 8050L, 8053L, 1L, 86L, 8054L, 8055L, 1L, 100L,
  8056L, 8057L, 1L, 128L, 8058L, 8059L, 1L, 112L, 8060L, 8061L, 1L, 126L,
  8112L, 8113L, 1L, 8L, 8126L, 8126L, 1L, -7205L, 8144L, 8145L, 1L, 8L,
  8160L, 8161L, 1L, 8L, 8165L, 8165L, 1L, 7L, 8526L, 8526L, 1L, -28L,
  8560L, 8575L, 1L, -16L, 8580L, 8580L, 1L, -1L, 9424L, 9449L, 1L, -26L,
  11312L, 11359L, 1L, -48L, 11361L, 11361L, 1L, -1L, 11365L, 11365L, 1L, -10795L,
  11366L, 11366L, 1L, -10792L, 11368L, 11372L, 2L, -1L, 11379L, 11379L, 1L, -1L,
  11382L, 11382L, 1L, -1L, 11393L, 11491L, 2L, -1L, 11500L, 11502L, 2L, -1L,
  11507L, 11507L, 1L, -1L, 11520L, 11557L, 1L, -7264L, 11559L, 11559L, 1L, -7264L,
  11565L, 11565L, 1L, -7264L, 42561L, 42605L, 2L, -1L, 42625L, 42651L, 2L, -1L,
  42787L, 42799L, 2L, -1L, 42803L, 42863L, 2L, -1L, 42874L, 42876L, 2L, -1L,
  42879L, 42887L, 2L, -1L, 42892L, 42892L, 1L, -1L, 42897L, 42899L, 2L, -1L,
  42900L, 42900L, 1L, 48L, 42903L, 42921L, 2L, -1L, 42933L, 42947L, 2L, -1L,
  42952L, 42954L, 2L, -1L, 42957L, 42971L, 2L, -1L, 42998L, 42998L, 1L, -1L,
  43859L, 43859L, 1L, -928L, 43888L, 43967L, 1L, -38864L, 65345L, 65370L, 1L, -32L,
  66600L, 66639L, 1L, -40L, 66776L, 66811L, 1L, -40L, 66967L, 66977L, 1L, -39L,
  66979L, 66993L, 1L, -39L, 66995L, 67001L, 1L, -39L, 67003L, 67004L, 1L, -39L,
  68800L, 68850L, 1L, -64L, 68976L, 68997L, 1L, -32L, 71872L, 71903L, 1L, -32L,
  93792L, 93823L, 1L, -32L, 93883L, 93907L, 1L, -27L, 125218L, 125251L, 1L, -34L
), ncol = 4L, byrow = TRUE)
# code point, up to 3 code points (0 = none)
.ltx_upper_special <- matrix(c(
  223L, 83L, 83L, 0L, 329L, 700L, 78L, 0L, 496L, 74L, 780L, 0L, 912L, 921L, 776L, 769L,
  944L, 933L, 776L, 769L, 1415L, 1333L, 1362L, 0L, 7830L, 72L, 817L, 0L, 7831L, 84L, 776L, 0L,
  7832L, 87L, 778L, 0L, 7833L, 89L, 778L, 0L, 7834L, 65L, 702L, 0L, 8016L, 933L, 787L, 0L,
  8018L, 933L, 787L, 768L, 8020L, 933L, 787L, 769L, 8022L, 933L, 787L, 834L, 8064L, 7944L, 921L, 0L,
  8065L, 7945L, 921L, 0L, 8066L, 7946L, 921L, 0L, 8067L, 7947L, 921L, 0L, 8068L, 7948L, 921L, 0L,
  8069L, 7949L, 921L, 0L, 8070L, 7950L, 921L, 0L, 8071L, 7951L, 921L, 0L, 8072L, 7944L, 921L, 0L,
  8073L, 7945L, 921L, 0L, 8074L, 7946L, 921L, 0L, 8075L, 7947L, 921L, 0L, 8076L, 7948L, 921L, 0L,
  8077L, 7949L, 921L, 0L, 8078L, 7950L, 921L, 0L, 8079L, 7951L, 921L, 0L, 8080L, 7976L, 921L, 0L,
  8081L, 7977L, 921L, 0L, 8082L, 7978L, 921L, 0L, 8083L, 7979L, 921L, 0L, 8084L, 7980L, 921L, 0L,
  8085L, 7981L, 921L, 0L, 8086L, 7982L, 921L, 0L, 8087L, 7983L, 921L, 0L, 8088L, 7976L, 921L, 0L,
  8089L, 7977L, 921L, 0L, 8090L, 7978L, 921L, 0L, 8091L, 7979L, 921L, 0L, 8092L, 7980L, 921L, 0L,
  8093L, 7981L, 921L, 0L, 8094L, 7982L, 921L, 0L, 8095L, 7983L, 921L, 0L, 8096L, 8040L, 921L, 0L,
  8097L, 8041L, 921L, 0L, 8098L, 8042L, 921L, 0L, 8099L, 8043L, 921L, 0L, 8100L, 8044L, 921L, 0L,
  8101L, 8045L, 921L, 0L, 8102L, 8046L, 921L, 0L, 8103L, 8047L, 921L, 0L, 8104L, 8040L, 921L, 0L,
  8105L, 8041L, 921L, 0L, 8106L, 8042L, 921L, 0L, 8107L, 8043L, 921L, 0L, 8108L, 8044L, 921L, 0L,
  8109L, 8045L, 921L, 0L, 8110L, 8046L, 921L, 0L, 8111L, 8047L, 921L, 0L, 8114L, 8122L, 921L, 0L,
  8115L, 913L, 921L, 0L, 8116L, 902L, 921L, 0L, 8118L, 913L, 834L, 0L, 8119L, 913L, 834L, 921L,
  8124L, 913L, 921L, 0L, 8130L, 8138L, 921L, 0L, 8131L, 919L, 921L, 0L, 8132L, 905L, 921L, 0L,
  8134L, 919L, 834L, 0L, 8135L, 919L, 834L, 921L, 8140L, 919L, 921L, 0L, 8146L, 921L, 776L, 768L,
  8147L, 921L, 776L, 769L, 8150L, 921L, 834L, 0L, 8151L, 921L, 776L, 834L, 8162L, 933L, 776L, 768L,
  8163L, 933L, 776L, 769L, 8164L, 929L, 787L, 0L, 8166L, 933L, 834L, 0L, 8167L, 933L, 776L, 834L,
  8178L, 8186L, 921L, 0L, 8179L, 937L, 921L, 0L, 8180L, 911L, 921L, 0L, 8182L, 937L, 834L, 0L,
  8183L, 937L, 834L, 921L, 8188L, 937L, 921L, 0L, 64256L, 70L, 70L, 0L, 64257L, 70L, 73L, 0L,
  64258L, 70L, 76L, 0L, 64259L, 70L, 70L, 73L, 64260L, 70L, 70L, 76L, 64261L, 83L, 84L, 0L,
  64262L, 83L, 84L, 0L, 64275L, 1348L, 1350L, 0L, 64276L, 1348L, 1333L, 0L, 64277L, 1348L, 1339L, 0L,
  64278L, 1358L, 1350L, 0L, 64279L, 1348L, 1341L, 0L
), ncol = 4L, byrow = TRUE)
# END GENERATED UPPER TABLE

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
#' @param quantum         integer minutes per quantum (default DEFAULT_QUANTUM = 5)
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
  seg_specs <- lapply(segments, function(s) ltx_segment_spec(s$type, s$q, s$speaker, s$label))

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

#' Compute a deterministic plan ID (mirrors makePlanId in ltx-sdk.js).
#'
#' v2: "LTX-{date}-{host}-{nodes}-v2-{hash8hex}", the FROZEN imul31 hash over
#' the UTF-16 code units of JSON.stringify(plan) in the plan's own key order
#' (LTX-SPECIFICATION.md 4.3). R lists keep insertion order, so a plan parsed
#' with jsonlite::fromJSON(x, simplifyVector = FALSE) hashes as in JS.
#' v3: "-v3-" and the first 8 hex of SHA-256 over canonical JSON (4.5).
#' Needs R/parity.R (json_stringify, imul31_hex, sha256_hex).
#' @param plan LtxPlan list
#' @return character string e.g. "LTX-20260101-EARTHHQ-MARS-v2-a3b2c1d0"
make_plan_id <- function(plan) {
  date_str <- gsub("-", "", substr(plan$start, 1L, 10L))
  nodes    <- plan$nodes
  # name.replace(/\s+/g, '').toUpperCase().slice(0, n): JavaScript's \s,
  # JS toUpperCase (.js_toupper), slices in UTF-16 code units
  short    <- function(name, n) .utf16_slice(.js_toupper(.js_replace_space(name)), n)
  host_str <- if (length(nodes) >= 1L && !is.null(nodes[[1L]]$name) && nzchar(nodes[[1L]]$name))
    short(nodes[[1L]]$name, 8L) else "HOST"
  node_str <- if (length(nodes) > 1L) {
    parts <- vapply(nodes[-1L], function(n) short(n$name, 4L), character(1L))
    .utf16_slice(paste(parts, collapse = "-"), 16L)
  } else "RX"

  if (!is.null(plan$v) && plan$v >= 3) {
    digest <- sha256_hex(canonical_json(plan))
    return(sprintf("LTX-%s-%s-%s-v3-%s", date_str, host_str, node_str, substr(digest, 1L, 8L)))
  }
  sprintf("LTX-%s-%s-%s-v2-%s", date_str, host_str, node_str, imul31_hex(json_stringify(plan)))
}

# ── Hash encoding / decoding ──────────────────────────────────────────────────

#' Encode a plan to a URL hash fragment ("#l=<base64url>").
#' The JSON is json_stringify(plan): the list's own key order and every field
#' it carries, i.e. exactly the bytes make_plan_id hashes for a v2 plan, so a
#' receiver derives the same planId (issue #32). A create_plan() plan keeps
#' the key order v, title, start, quantum, mode, nodes, segments; v3 fields
#' (delays, planVersion, ...) are transmitted too.
#' Needs R/parity.R (json_stringify).
#' @param plan LtxPlan list
#' @return character string starting with "#l="
encode_hash <- function(plan) {
  json <- json_stringify(plan)
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
      ltx_segment_spec(s$type, s$q, s$speaker, s$label)
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
  token      <- encode_hash(plan)
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

  .to_id <- function(name) toupper(.js_replace_space(name, "-"))  # ltx-sdk.js toId

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

#' Build a flat delay matrix for all ordered node pairs in a plan.
#' Every entry is pair_delay(plan, from, to) (LTX-SPECIFICATION.md 3.7.3):
#' a v3 plan$delays entry is authoritative where present; HOST to node is that
#' node's declared delay; node to node (neither is HOST) is the SUM of both
#' HOST-relative delays (a conservative upper bound via the HOST vertex), not
#' the max. The matrix is symmetric. Needs R/parity.R (pair_delay).
#' @param plan LtxPlan list
#' @return list of lists, each with from_id, from_name, to_id, to_name, delay_seconds
build_delay_matrix <- function(plan) {
  nodes  <- plan$nodes
  result <- list()
  for (i in seq_along(nodes)) {
    for (j in seq_along(nodes)) {
      if (i == j) next
      from <- nodes[[i]]; to <- nodes[[j]]
      result <- c(result, list(list(
        from_id       = from$id,
        from_name     = from$name,
        to_id         = to$id,
        to_name       = to$name,
        delay_seconds = pair_delay(plan, from$id, to$id)
      )))
    }
  }
  result
}
