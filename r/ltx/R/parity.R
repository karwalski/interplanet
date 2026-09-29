# parity.R -- LTX parity with the JS reference SDK (issue #27)
#
# Mirrors javascript/ltx/ltx-sdk.js:
#   * JSON.stringify-compatible serialisation of a plan in its own key order,
#     and the frozen v2 imul31 hash over UTF-16 code units (§4.3)
#   * v3 planId: SHA-256 over RFC 8785 canonical JSON (§4.5), planHash
#   * validate_plan (§3.5, §4, §7) incl. reserved_streams / reserved_branching
#   * upgrade_plan_to_v3 (§4.4), pair_delay (§3.7)
#
# Base R only (no digest/openssl): SHA-256 is implemented below.
# Plans are named lists; R lists keep insertion order, so a plan parsed with
# jsonlite::fromJSON(x, simplifyVector = FALSE) hashes exactly as in JS.
# JSON arrays are unnamed lists; JSON objects are named lists (an empty
# object is a list with names character(0)).

# ── JSON.stringify / canonical JSON ──────────────────────────────────────────

.json_quote <- function(s) {
  cps <- utf8ToInt(enc2utf8(s))
  if (length(cps) == 0L) return('""')
  out <- vapply(cps, function(cp) {
    if (cp == 34L) return('\\"')
    if (cp == 92L) return("\\\\")
    if (cp == 8L)  return("\\b")
    if (cp == 12L) return("\\f")
    if (cp == 10L) return("\\n")
    if (cp == 13L) return("\\r")
    if (cp == 9L)  return("\\t")
    if (cp < 32L)  return(sprintf("\\u%04x", cp))
    intToUtf8(cp)
  }, character(1L))
  paste0('"', paste(out, collapse = ""), '"')
}

.json_number <- function(x) {
  if (is.na(x) || is.infinite(x)) return("null")
  if (is.integer(x)) return(as.character(x))
  if (x == floor(x) && abs(x) < 1e21) return(sprintf("%.0f", x))
  as.character(x)
}

.is_json_object <- function(x) is.list(x) && !is.null(names(x))

#' Serialise like JavaScript JSON.stringify (no whitespace). Named lists are
#' objects in their own key order (or sorted when canonical = TRUE, RFC 8785);
#' unnamed lists are arrays; length-1 atomic vectors are scalars.
#' @param x R value
#' @param canonical logical sort object keys (RFC 8785 canonical JSON)
#' @return character JSON text
json_stringify <- function(x, canonical = FALSE) {
  if (is.null(x)) return("null")
  if (is.list(x)) {
    if (.is_json_object(x)) {
      keys <- names(x)
      if (canonical) keys <- sort(keys, method = "radix")
      parts <- vapply(keys, function(k) {
        paste0(.json_quote(k), ":", json_stringify(x[[k]], canonical))
      }, character(1L))
      return(paste0("{", paste(parts, collapse = ","), "}"))
    }
    items <- vapply(x, json_stringify, character(1L), canonical = canonical)
    return(paste0("[", paste(items, collapse = ","), "]"))
  }
  if (length(x) != 1L) {
    items <- vapply(as.list(x), json_stringify, character(1L), canonical = canonical)
    return(paste0("[", paste(items, collapse = ","), "]"))
  }
  if (is.logical(x)) return(if (is.na(x)) "null" else if (x) "true" else "false")
  if (is.numeric(x)) return(.json_number(x))
  if (is.character(x)) return(.json_quote(x))
  stop(sprintf("json_stringify: unsupported type '%s'", class(x)[[1L]]))
}

#' RFC 8785 canonical JSON (sorted keys, no whitespace).
canonical_json <- function(x) json_stringify(x, canonical = TRUE)

# ── Frozen v2 hash (§4.3) ────────────────────────────────────────────────────

#' UTF-16 code units of a UTF-8 string (astral code points become surrogate pairs).
.utf16_units <- function(s) {
  cps <- utf8ToInt(enc2utf8(s))
  astral <- cps >= 65536L
  if (!any(astral)) return(cps)
  unlist(lapply(cps, function(cp) {
    if (cp < 65536L) return(cp)
    x <- cp - 65536L
    c(55296L + x %/% 1024L, 56320L + x %% 1024L)
  }))
}

#' (Math.imul(31, h) + charCodeAt(i)) >>> 0 over the UTF-16 code units of s,
#' as 8 lowercase hex digits. Doubles hold 31 * h + unit exactly (< 2^53).
imul31_hex <- function(s) {
  h <- 0
  for (u in .utf16_units(s)) h <- (31 * h + u) %% 4294967296
  sprintf("%04x%04x", as.integer(h %/% 65536), as.integer(h %% 65536))
}

# ── SHA-256 (FIPS 180-4) in base R ───────────────────────────────────────────
# 32-bit words are doubles in [0, 2^32); bitwise ops run on 16-bit halves.

.sha_k <- c(
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2)

.w_hi <- function(x) as.integer(x %/% 65536)
.w_lo <- function(x) as.integer(x %% 65536)
.w_join <- function(hi, lo) hi * 65536 + lo
.w_and <- function(a, b) .w_join(bitwAnd(.w_hi(a), .w_hi(b)), bitwAnd(.w_lo(a), .w_lo(b)))
.w_xor <- function(a, b) .w_join(bitwXor(.w_hi(a), .w_hi(b)), bitwXor(.w_lo(a), .w_lo(b)))
.w_not <- function(a) 4294967295 - a
.w_rotr <- function(x, n) (x %/% 2^n + (x %% 2^n) * 2^(32 - n)) %% 4294967296
.w_shr <- function(x, n) x %/% 2^n

#' SHA-256 of a UTF-8 string, as lowercase hex.
sha256_hex <- function(s) {
  bytes <- as.integer(charToRaw(enc2utf8(s)))
  n <- length(bytes)
  bit_len <- n * 8
  bytes <- c(bytes, 128L, integer((55L - n) %% 64L))
  len_bytes <- integer(8L)
  v <- bit_len
  for (i in 8:1) { len_bytes[i] <- as.integer(v %% 256); v <- v %/% 256 }
  bytes <- c(bytes, len_bytes)
  h <- c(0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19)
  for (blk in seq(0L, length(bytes) - 1L, by = 64L)) {
    b <- bytes[(blk + 1L):(blk + 64L)]
    w <- numeric(64L)
    for (t in 0:15) {
      w[t + 1L] <- ((b[4L * t + 1L] * 256 + b[4L * t + 2L]) * 256 + b[4L * t + 3L]) * 256 + b[4L * t + 4L]
    }
    for (t in 16:63) {
      x15 <- w[t - 14L]; x2 <- w[t - 1L]
      s0 <- .w_xor(.w_xor(.w_rotr(x15, 7), .w_rotr(x15, 18)), .w_shr(x15, 3))
      s1 <- .w_xor(.w_xor(.w_rotr(x2, 17), .w_rotr(x2, 19)), .w_shr(x2, 10))
      w[t + 1L] <- (w[t - 15L] + s0 + w[t - 6L] + s1) %% 4294967296
    }
    a <- h[1]; bb <- h[2]; cc <- h[3]; d <- h[4]; e <- h[5]; f <- h[6]; g <- h[7]; hh <- h[8]
    for (t in 1:64) {
      S1 <- .w_xor(.w_xor(.w_rotr(e, 6), .w_rotr(e, 11)), .w_rotr(e, 25))
      ch <- .w_xor(.w_and(e, f), .w_and(.w_not(e), g))
      t1 <- (hh + S1 + ch + .sha_k[t] + w[t]) %% 4294967296
      S0 <- .w_xor(.w_xor(.w_rotr(a, 2), .w_rotr(a, 13)), .w_rotr(a, 22))
      maj <- .w_xor(.w_xor(.w_and(a, bb), .w_and(a, cc)), .w_and(bb, cc))
      t2 <- (S0 + maj) %% 4294967296
      hh <- g; g <- f; f <- e; e <- (d + t1) %% 4294967296
      d <- cc; cc <- bb; bb <- a; a <- (t1 + t2) %% 4294967296
    }
    h <- (h + c(a, bb, cc, d, e, f, g, hh)) %% 4294967296
  }
  paste(sprintf("%04x%04x", as.integer(h %/% 65536), as.integer(h %% 65536)), collapse = "")
}

#' SHA-256 hex of the canonical JSON of a plan (prevPlanHash, §6.4).
plan_hash <- function(plan) sha256_hex(canonical_json(plan))

# ── Plan validation (§3.5, §4, §7) ───────────────────────────────────────────

PLAN_SEGMENT_TYPES <- c("PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
                        "SPEAK", "REST", "PAD", "OPEN", "RELAY")
PLAN_MODES <- c("LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC")
V3_ONLY_FIELDS <- c("delays", "planVersion", "prevPlanHash", "questions", "actions", "streams")

.has <- function(x, k) is.list(x) && !is.null(names(x)) && k %in% names(x)
.is_array <- function(x) (is.list(x) && is.null(names(x))) || (is.atomic(x) && !is.null(x) && length(x) != 1L)
.is_int <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) && x == floor(x)
.is_num <- function(x) is.numeric(x) && length(x) == 1L && !is.na(x)
.is_str <- function(x) is.character(x) && length(x) == 1L && !is.na(x)
.perr <- function(code, path, message) list(code = code, path = path, message = message)

#' Reserved-field violations only (§3.5 streams, §7 branching).
reserved_field_errors <- function(plan) {
  errors <- list()
  if (!.is_json_object(plan)) return(errors)
  if (.has(plan, "streams") && !(.is_array(plan$streams) && length(plan$streams) == 0L)) {
    errors[[length(errors) + 1L]] <- .perr("reserved_streams", "streams",
      "streams[] is reserved (\u00a73.5) and MUST be absent or empty")
  }
  for (f in c("branches", "branching")) {
    if (.has(plan, f)) errors[[length(errors) + 1L]] <- .perr("reserved_branching", f,
      paste0(f, " is reserved for branching (\u00a77, not yet implemented) and MUST be absent"))
  }
  segs <- if (.is_array(plan$segments)) plan$segments else list()
  for (i in seq_along(segs)) {
    s <- segs[[i]]
    if (!.is_json_object(s)) next
    if (.has(s, "stream")) errors[[length(errors) + 1L]] <- .perr("reserved_streams",
      sprintf("segments[%d].stream", i - 1L), "segment stream is reserved (\u00a73.5) and MUST be absent")
    if (.has(s, "branch")) errors[[length(errors) + 1L]] <- .perr("reserved_branching",
      sprintf("segments[%d].branch", i - 1L), "segment branch is reserved for branching (\u00a77) and MUST be absent")
  }
  errors
}

#' Stop with an "ltx_reserved_field_error" condition (fields code, errors)
#' if a plan uses reserved stream/branch fields.
assert_no_reserved_fields <- function(plan, fn_name) {
  errors <- reserved_field_errors(plan)
  if (length(errors) == 0L) return(invisible(NULL))
  stop(structure(
    class = c("ltx_reserved_field_error", "error", "condition"),
    list(message = paste0(fn_name, ": ", errors[[1L]]$message), call = NULL,
         code = errors[[1L]]$code, errors = errors)))
}

.valid_timestamp <- function(s) {
  if (!.is_str(s)) return(FALSE)
  grepl("^\\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\\d|3[01])(T([01]\\d|2[0-4]):[0-5]\\d(:[0-5]\\d(\\.\\d+)?)?(Z|[+-]\\d{2}:\\d{2})?)?$",
        s, perl = TRUE)
}

#' Validate a v2 or v3 plan (mirrors validatePlan in ltx-sdk.js). Pure; never
#' stops. Returns list(valid = logical, errors = list of list(code, path, message)).
#' Codes: not_an_object, invalid_version, missing_field, invalid_field,
#' invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
#' duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
#' invalid_delays, reserved_streams, reserved_branching.
validate_plan <- function(plan) {
  errors <- list()
  err <- function(code, path, message) errors[[length(errors) + 1L]] <<- .perr(code, path, message)
  if (!.is_json_object(plan)) {
    err("not_an_object", "", "plan must be an object")
    return(list(valid = FALSE, errors = errors))
  }
  v <- plan$v
  is_v <- function(n) .is_num(v) && v == n
  if (!is_v(2) && !is_v(3)) err("invalid_version", "v", "v must be 2 or 3")
  for (f in c("title", "start", "quantum", "mode", "nodes", "segments")) {
    if (!.has(plan, f)) err("missing_field", f, paste0(f, " is required"))
  }
  if (.has(plan, "title") && !.is_str(plan$title)) err("invalid_field", "title", "title must be a string")
  if (.has(plan, "start") && !.valid_timestamp(plan$start)) {
    err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
  }
  if (.has(plan, "quantum") && !(.is_int(plan$quantum) && plan$quantum >= 1 && plan$quantum <= 60)) {
    err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (\u00a73.2)")
  }
  if (.has(plan, "mode") && !(.is_str(plan$mode) && plan$mode %in% PLAN_MODES)) {
    err("invalid_mode", "mode", paste0("mode must be one of ", paste(PLAN_MODES, collapse = ", ")))
  }

  ids <- character(0)
  if (.has(plan, "nodes")) {
    nodes <- plan$nodes
    if (!.is_array(nodes) || length(nodes) == 0L) {
      err("invalid_nodes", "nodes", "nodes must be a non-empty array")
    } else {
      hosts <- 0L
      for (i in seq_along(nodes)) {
        n <- nodes[[i]]
        ok <- .is_json_object(n) && .is_str(n$id) && nzchar(n$id) && !grepl("|", n$id, fixed = TRUE) &&
          .is_str(n$name) && .is_str(n$role) && n$role %in% c("HOST", "PARTICIPANT", "OBSERVER") &&
          .is_num(n$delay) && n$delay >= 0
        if (!ok) {
          err("invalid_nodes", sprintf("nodes[%d]", i - 1L),
              'node needs id (no "|"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0')
          next
        }
        if (n$id %in% ids) err("duplicate_node_id", sprintf("nodes[%d].id", i - 1L), paste0("duplicate node id ", n$id))
        ids <- union(ids, n$id)
        if (n$role == "HOST") hosts <- hosts + 1L
      }
      h <- nodes[[1L]]
      h_ok <- .is_json_object(h) && identical(h$role, "HOST") && .is_num(h$delay) && h$delay == 0
      if (hosts != 1L || !h_ok) {
        err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (\u00a73.1)")
      }
    }
  }

  if (.has(plan, "segments")) {
    segs <- plan$segments
    if (!.is_array(segs)) {
      err("invalid_segment", "segments", "segments must be an array")
    } else {
      for (i in seq_along(segs)) {
        s <- segs[[i]]
        if (!(.is_json_object(s) && .is_str(s$type) && s$type %in% PLAN_SEGMENT_TYPES &&
              .is_int(s$q) && s$q >= 1)) {
          err("invalid_segment", sprintf("segments[%d]", i - 1L), "segment needs a known type and integer q >= 1")
          next
        }
        if (.has(s, "speaker") && !(.is_str(s$speaker) && s$speaker %in% ids)) {
          err("unknown_speaker", sprintf("segments[%d].speaker", i - 1L),
              paste0("speaker ", format(s$speaker), " is not a node id"))
        }
      }
    }
  }

  if (is_v(2)) {
    for (f in V3_ONLY_FIELDS) {
      if (.has(plan, f)) err("v3_field_in_v2", f, paste0(f, " is a v3 field and MUST NOT appear in a v2 plan (\u00a74.3)"))
    }
  } else if (is_v(3)) {
    if (.has(plan, "delays")) {
      d <- plan$delays
      if (!(.is_json_object(d) || (is.list(d) && length(d) == 0L))) {
        err("invalid_delays", "delays", "delays must be an object")
      } else {
        for (k in names(d)) {
          parts <- strsplit(k, "|", fixed = TRUE)[[1L]]
          if (endsWith(k, "|")) parts <- c(parts, "")
          ok <- length(parts) == 2L && .utf16_less(parts[1L], parts[2L]) &&
            (length(ids) == 0L || (parts[1L] %in% ids && parts[2L] %in% ids)) &&
            .is_num(d[[k]]) && d[[k]] >= 0
          if (!ok) err("invalid_delays", paste0("delays.", k),
            'key must be two known node ids joined by "|" in sorted order; value >= 0 (\u00a73.7.2)')
        }
      }
    }
    if (.has(plan, "planVersion") && !(.is_int(plan$planVersion) && plan$planVersion >= 1)) {
      err("invalid_field", "planVersion", "planVersion must be an integer >= 1")
    }
    if (.has(plan, "prevPlanHash") && !(.is_str(plan$prevPlanHash) && grepl("^[0-9a-f]{64}$", plan$prevPlanHash))) {
      err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")
    }
    for (f in c("questions", "actions")) {
      if (.has(plan, f) && !.is_array(plan[[f]]) && !(is.list(plan[[f]]) && length(plan[[f]]) == 0L)) {
        err("invalid_field", f, paste0(f, " must be an array"))
      }
    }
  }

  errors <- c(errors, reserved_field_errors(plan))
  list(valid = length(errors) == 0L, errors = errors)
}

# JS string comparison a < b (UTF-16 code units).
.utf16_less <- function(a, b) {
  ua <- .utf16_units(a); ub <- .utf16_units(b)
  n <- min(length(ua), length(ub))
  for (i in seq_len(n)) if (ua[i] != ub[i]) return(ua[i] < ub[i])
  length(ua) < length(ub)
}

# ── upgrade_plan_to_v3 (§4.4) and pair_delay (§3.7) ──────────────────────────

#' Explicitly upgrade a v2 plan to v3. Never automatic: the result is a NEW
#' plan with a new (v3) planId. `extras` (named list, e.g. list(delays = ...))
#' are merged with JS spread semantics (existing keys keep their position);
#' v becomes 3 and planVersion defaults to 1. Stops with an
#' "ltx_reserved_field_error" (code reserved_streams / reserved_branching) if
#' the result carries reserved fields (§3.5, §7).
upgrade_plan_to_v3 <- function(plan, extras = list()) {
  out <- plan
  for (k in names(extras)) out[k] <- list(extras[[k]])
  out["v"] <- list(3L)
  out["planVersion"] <- list(if (!is.null(extras$planVersion)) extras$planVersion else 1L)
  assert_no_reserved_fields(out, "upgradePlanToV3")
  out
}

#' One-way delay in seconds between two nodes (§3.7). A v3 pair matrix
#' (plan$delays, sorted-id "A|B" keys) is authoritative where present;
#' otherwise HOST pairs use the node's declared delay and non-HOST pairs the
#' SUM of both HOST-relative delays (a safe upper bound via the HOST vertex).
pair_delay <- function(plan, node_id_a, node_id_b) {
  if (identical(node_id_a, node_id_b)) return(0)
  key <- if (.utf16_less(node_id_b, node_id_a)) paste0(node_id_b, "|", node_id_a) else paste0(node_id_a, "|", node_id_b)
  d <- plan$delays
  if (is.list(d) && !is.null(d[[key]]) && .is_num(d[[key]])) return(d[[key]])
  find <- function(id) {
    for (n in plan$nodes) if (identical(n$id, id)) return(n)
    NULL
  }
  a <- find(node_id_a); b <- find(node_id_b)
  if (is.null(a) || is.null(b)) {
    stop(sprintf("pair_delay: unknown node %s", if (is.null(a)) node_id_a else node_id_b))
  }
  delay_of <- function(n) if (is.null(n$delay)) 0 else n$delay
  host_id <- plan$nodes[[1L]]$id
  if (identical(node_id_a, host_id)) return(delay_of(b))
  if (identical(node_id_b, host_id)) return(delay_of(a))
  delay_of(a) + delay_of(b)
}
