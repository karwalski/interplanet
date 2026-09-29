# test/test_parity.R -- LTX parity with the JS reference SDK (issue #27)
# Mirrors javascript/ltx/tests/run.js: golden planId vectors, validatePlan +
# reserved fields, buildDelayMatrix via pairDelay.
# Run from r/ltx: Rscript test/test_parity.R   (needs jsonlite for the vectors)

source("R/constants.R")
source("R/ltx.R")
source("R/parity.R")

pass <- 0L
fail <- 0L
check <- function(cond, msg = "") {
  if (isTRUE(cond)) {
    pass <<- pass + 1L
  } else {
    fail <<- fail + 1L
    cat(sprintf("FAIL: %s\n", msg))
  }
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  cat("SKIP: jsonlite is needed to read spec/golden/plan-ids.json\n")
  quit(status = 1L)
}
parse_json <- function(txt) jsonlite::fromJSON(txt, simplifyVector = FALSE)
codes <- function(r) vapply(r$errors, function(e) e$code, character(1L))
with_key <- function(x, k, v) { x[k] <- list(v); x }

# ── Conformance: planId prefix vectors (spec/golden/plan-id-prefixes.json) ─
# Unicode upper-casing and UTF-16 slicing of HOSTSTR / NODESTR (issue #37).
# R strings are UTF-8 and cannot hold a lone surrogate, so the expected id is
# planIdUtf8 (a surrogate pair split by the cut becomes U+FFFD).

prefix_golden <- parse_json(paste(readLines("../../spec/golden/plan-id-prefixes.json", encoding = "UTF-8",
                                            warn = FALSE), collapse = "\n"))
check(length(prefix_golden$vectors) >= 18L, "prefix vectors present")
for (gv in prefix_golden$vectors) {
  want <- gv$planIdUtf8
  got <- make_plan_id(gv$plan)
  check(identical(got, want), sprintf("prefix planId %s (got %s)", gv$name, got))
  check(identical(make_plan_id(parse_json(json_stringify(gv$plan))), want), paste("prefix planId from JSON text", gv$name))
  # decode_hash gives the typed (nodes-first) plan: same prefix
  wire <- decode_hash(encode_hash(gv$plan))
  check(identical(substr(make_plan_id(wire), 1L, nchar(want) - 12L), substr(want, 1L, nchar(want) - 12L)),
        paste("prefix planId of decode_hash", gv$name))
  typed <- create_plan(title = gv$plan$title, start_iso = gv$plan$start)
  typed$nodes <- lapply(gv$plan$nodes, function(n)
    list(id = n$id, name = n$name, role = n$role, delay = n$delay, location = n$location))
  tid <- make_plan_id(typed)
  cut <- function(id) substr(id, 1L, nchar(id) - 12L)
  check(identical(cut(tid), cut(want)), sprintf("prefix typed planId %s (got %s)", gv$name, tid))
}
check(identical(.js_toupper("stra\u00dfe \ufb01 \u0149 \u0390 \u1fb3 \u0587 \u023f"),
                "STRASSE FI \u02bcN \u0399\u0308\u0301 \u0391\u0399 \u0535\u0552 \u2c7e"),
      ".js_toupper full mapping")

# ── Conformance: golden planId vectors (spec/golden/plan-ids.json) ───────────

golden <- parse_json(paste(readLines("../../spec/golden/plan-ids.json", encoding = "UTF-8", warn = FALSE),
                           collapse = "\n"))
vectors <- golden$vectors
check(length(vectors) >= 9L, "golden vectors present")
by_name <- list()
for (gv in vectors) {
  by_name[[gv$name]] <- gv
  got <- make_plan_id(gv$plan)
  check(identical(got, gv$planId), sprintf("golden planId %s (got %s)", gv$name, got))
  if (!is.null(gv$planHash)) check(identical(plan_hash(gv$plan), gv$planHash), paste("golden planHash", gv$name))
}
check(by_name[["v2-freeze-check"]]$planId == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d", "golden v2 freeze anchor")
check(by_name[["v2-unicode-title"]]$planId == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8", "golden v2 unicode anchor")
check(by_name[["v2-createPlan-default"]]$planId != by_name[["v2-key-order-sensitive"]]$planId, "golden v2 order-sensitive")
check(by_name[["v3-upgrade-delays"]]$planId == by_name[["v3-key-order-insensitive"]]$planId, "golden v3 order-insensitive")
check(by_name[["v3-amendment"]]$plan$prevPlanHash == by_name[["v3-upgrade-delays"]]$planHash, "golden v3 amendment chain hash")
check(create_plan()$quantum == 5L && DEFAULT_QUANTUM == 5L, "create_plan default quantum is 5")
# create_plan lists are ordered v, title, start, quantum, mode, nodes, segments,
# so the default plan reproduces the v2-key-order-sensitive vector.
sp <- make_plan_id(create_plan(title = "Golden Default", start_iso = "2026-03-15T14:00:00.000Z", delay = 840))
check(identical(sp, by_name[["v2-key-order-sensitive"]]$planId),
      paste("create_plan planId = golden v2-key-order-sensitive, got", sp))
check(identical(json_stringify(parse_json('{"b":1,"a":[true,null,"x\\"y"],"e":[],"o":{}}')),
                '{"b":1,"a":[true,null,"x\\"y"],"e":[],"o":{}}'),
      "json_stringify preserves order, null, escapes, empty array/object")
check(identical(sha256_hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
      "sha256 FIPS 180-2 abc vector")

# ── Plan validation: reserved streams / branching (§3.5, §7) ─────────────────

for (gv in vectors) check(isTRUE(validate_plan(gv$plan)$valid), paste("validate_plan accepts golden", gv$name))
vp_base <- by_name[["v3-upgrade-delays"]]$plan
vp_v2 <- by_name[["v2-freeze-check"]]$plan
check(isTRUE(validate_plan(with_key(vp_base, "streams", list()))$valid), "validate_plan v3 empty streams ok")
vs <- validate_plan(with_key(vp_base, "streams", list(list(id = "S1"))))
check(!vs$valid && "reserved_streams" %in% codes(vs), "validate_plan non-empty streams")
check(Filter(function(e) e$code == "reserved_streams", vs$errors)[[1L]]$path == "streams", "validate_plan streams error path")
check("reserved_streams" %in% codes(validate_plan(with_key(vp_base, "streams", "S1"))), "validate_plan streams non-array")
check("reserved_streams" %in% codes(validate_plan(with_key(vp_base, "segments", list(list(type = "TX", q = 1L, stream = "S1"))))),
      "validate_plan segment stream")
check("reserved_branching" %in% codes(validate_plan(with_key(vp_base, "branches", list()))), "validate_plan branches")
check("reserved_branching" %in% codes(validate_plan(with_key(vp_base, "branching", list(mode = "local")))), "validate_plan branching")
vb <- validate_plan(with_key(vp_base, "segments", list(list(type = "CAUCUS", q = 1L, branch = "B1"))))
check("reserved_branching" %in% codes(vb) && vb$errors[[1L]]$path == "segments[0].branch", "validate_plan segment branch")
check("v3_field_in_v2" %in% codes(validate_plan(with_key(vp_v2, "streams", list()))), "validate_plan v2 streams is v3 field")
check("reserved_branching" %in% codes(validate_plan(with_key(vp_v2, "branching", TRUE))), "validate_plan v2 branching")
check("not_an_object" %in% codes(validate_plan(NULL)), "validate_plan non-object")
check("invalid_version" %in% codes(validate_plan(with_key(vp_v2, "v", 7L))), "validate_plan bad version")
check("invalid_host" %in% codes(validate_plan(with_key(vp_v2, "nodes", rev(vp_v2$nodes)))), "validate_plan host not first")
check("invalid_delays" %in% codes(validate_plan(with_key(vp_base, "delays", list(`N1|N0` = 860L)))),
      "validate_plan unsorted delays key")
check("unknown_speaker" %in% codes(validate_plan(with_key(vp_v2, "segments", list(list(type = "TX", q = 1L, speaker = "N9"))))),
      "validate_plan unknown speaker")
check("invalid_quantum" %in% codes(validate_plan(with_key(vp_v2, "quantum", 0L))), "validate_plan quantum out of range")
check("missing_field" %in% codes(validate_plan(vp_v2[setdiff(names(vp_v2), "title")])), "validate_plan missing title")
check("invalid_mode" %in% codes(validate_plan(with_key(vp_v2, "mode", "CHAT"))), "validate_plan bad mode")
check("duplicate_node_id" %in% codes(validate_plan(with_key(vp_v2, "nodes", c(vp_v2$nodes, vp_v2$nodes[2L])))),
      "validate_plan duplicate node id")
check("invalid_field" %in% codes(validate_plan(with_key(vp_base, "prevPlanHash", "ABC"))), "validate_plan bad prevPlanHash")
check(isTRUE(validate_plan(create_plan(start_iso = "2026-03-15T14:00:00Z"))$valid), "validate_plan accepts create_plan output")

throws_code <- function(expr) {
  tryCatch({ force(expr); NA_character_ }, ltx_reserved_field_error = function(e) e$code)
}
check(identical(throws_code(upgrade_plan_to_v3(vp_v2, list(streams = list(list(id = "S1"))))), "reserved_streams"),
      "upgrade_plan_to_v3 rejects streams")
check(is.na(throws_code(upgrade_plan_to_v3(vp_v2, list(streams = list())))), "upgrade_plan_to_v3 allows empty")
check(identical(throws_code(upgrade_plan_to_v3(vp_v2, list(branches = list()))), "reserved_branching"),
      "upgrade_plan_to_v3 rejects branches")
up3 <- upgrade_plan_to_v3(vp_v2, list(delays = list(`N0|N1` = 900L)))
check(up3$v == 3L && up3$planVersion == 1L && pair_delay(up3, "N0", "N1") == 900 && vp_v2$v == 2L,
      "upgrade_plan_to_v3 result, input unchanged")
check(isTRUE(validate_plan(up3)$valid), "upgraded plan validates")

# ── buildDelayMatrix (§3.7): sum via HOST for non-HOST pairs ─────────────────

dm_plan <- list(
  v = 2L, title = "Delay Matrix", start = "2026-06-01T12:00:00.000Z", quantum = 5L, mode = "LTX-ASYNC",
  segments = list(list(type = "TX", q = 1L)),
  nodes = list(
    ltx_node("N0", "Earth HQ",    "HOST",        0,    "earth"),
    ltx_node("N1", "Mars Hab-01", "PARTICIPANT", 1240, "mars"),
    ltx_node("N2", "Jupiter Obs", "PARTICIPANT", 3240, "jupiter"),
    ltx_node("N3", "Earth Annex", "PARTICIPANT", 0,    "earth")))
dm_get <- function(m, a, b) Filter(function(p) p$from_id == a && p$to_id == b, m)[[1L]]$delay_seconds
dm <- build_delay_matrix(dm_plan)
check(length(dm) == 12L, "delay matrix n*(n-1) pairs")
check(dm_get(dm, "N0", "N1") == 1240 && dm_get(dm, "N1", "N0") == 1240, "delay matrix HOST to node")
check(dm_get(dm, "N1", "N2") == 1240 + 3240, "delay matrix non-HOST pair = sum")
check(dm_get(dm, "N1", "N2") != max(1240, 3240), "delay matrix not max")
check(all(vapply(dm, function(p) p$delay_seconds == dm_get(dm, p$to_id, p$from_id), logical(1L))), "delay matrix symmetric")
check(dm_get(dm, "N3", "N2") == 3240 && dm_get(dm, "N3", "N0") == 0, "delay matrix zero-delay non-HOST")
check(all(vapply(dm, function(p) p$delay_seconds == pair_delay(dm_plan, p$from_id, p$to_id), logical(1L))),
      "delay matrix equals pair_delay")
dm3 <- build_delay_matrix(upgrade_plan_to_v3(dm_plan, list(delays = list(`N1|N2` = 2900L))))
check(dm_get(dm3, "N1", "N2") == 2900 && dm_get(dm3, "N2", "N1") == 2900, "delay matrix v3 entry authoritative")
check(dm_get(dm3, "N1", "N3") == 1240, "delay matrix v3 fallback sum")

# ── Wire JSON = hashed JSON (issue #32) ───────────────────────────────────────
# encode_hash must transmit what make_plan_id hashes, v3 fields included, so a
# receiver computing the planId from the #l= wire JSON gets the same id.
wire_of <- function(p) b64url_decode(sub("^#l=", "", encode_hash(p)))
wp <- create_plan(title = "Réunion Mars \U0001F680", start_iso = "2026-03-15T14:00:00Z", delay = 840)
check(make_plan_id(parse_json(wire_of(wp))) == make_plan_id(wp), "v2 planId of wire JSON equals make_plan_id")
wv3 <- upgrade_plan_to_v3(wp, list(delays = list(`N0|N1` = 842L)))
check(grepl('"delays":{"N0|N1":842}', wire_of(wv3), fixed = TRUE), "v3 wire JSON carries delays")
check(make_plan_id(wv3) == "LTX-20260315-EARTHHQ-MARS-v3-cd55a366", "v3 planId matches JS")
check(make_plan_id(parse_json(wire_of(wv3))) == make_plan_id(wv3), "v3 planId of wire JSON equals make_plan_id")

# ── Attributed segments (speaker/label, 3.4.1) and JS string rules (#36) ────
rep_nodes <- list(
  ltx_node("N0", "Earth HQ", "HOST", delay = 0, location = "earth"),
  ltx_node("N1", "Mars Hab-01", "PARTICIPANT", delay = 840, location = "mars"),
  ltx_node("N2", "L-1 Gateway", "PARTICIPANT", delay = 2, location = "moon"))
att <- create_plan(title = "Réunion Mars \U0001F680", start_iso = "2026-03-15T14:00:00.000Z",
                   quantum = 3, mode = "LTX-ASYNC",
                   segments = list(
                     list(type = "PLAN_CONFIRM", q = 2),
                     list(type = "TX", q = 3, speaker = "N0", label = "Ouverture: état de la mission"),
                     list(type = "RX", q = 3),
                     list(type = "TX", q = 2, speaker = "N1", label = "Réponse \U0001F534"),
                     list(type = "BUFFER", q = 1)))
att$nodes <- rep_nodes
aw <- enc2utf8(wire_of(att))
Encoding(aw) <- "UTF-8"
want_segs <- paste0('"segments":[{"type":"PLAN_CONFIRM","q":2},{"type":"TX","q":3,"speaker":"N0",',
                    '"label":"Ouverture: état de la mission"},{"type":"RX","q":3},',
                    '{"type":"TX","q":2,"speaker":"N1","label":"Réponse \U0001F534"},{"type":"BUFFER","q":1}]}')
check(endsWith(aw, want_segs), "attributed wire segments (JS key order, absent fields omitted)")
# JS makePlanId of the same object (nodes before segments)
check(make_plan_id(att) == "LTX-20260315-EARTHHQ-MARS-L-1G-v2-1e382346", "attributed typed planId == JS")
check(make_plan_id(parse_json(aw)) == make_plan_id(att), "attributed typed planId == JSON planId of wire")
back <- decode_hash(encode_hash(att))
check(identical(back$segments[[2]]$speaker, "N0") && identical(back$segments[[4]]$label, "Réponse \U0001F534") &&
        is.null(back$segments[[1]]$speaker) && is.null(back$segments[[1]]$label),
      "decode_hash keeps speaker/label")
check(make_plan_id(back) == make_plan_id(att), "decode_hash round trip planId")
check(identical(names(ltx_segment_spec("RX", 2, label = "Q&A")), c("type", "q", "label")),
      "label without speaker")

# Control characters, JS whitespace (/\s/ is Unicode-aware in JS) and
# non-whitespace look-alikes (U+0085, U+200B) in node names. R strings
# cannot hold U+0000, so the JS vector's label is the six characters \u0000.
wsp <- create_plan(title = "C\u0001\b\t\n\v\f\r\u001f\"\\/\u007f  é\U0001F680",
                   start_iso = "2026-03-15T14:00:00.000Z", quantum = 3, mode = "LTX",
                   segments = list(list(type = "TX", q = 2, speaker = "N1"),
                                   list(type = "RX", q = 2, label = "Q\\u0000&A")))
wsp$nodes <- list(
  ltx_node("N0", "Earth \tHQ", "HOST", delay = 0, location = "earth"),
  ltx_node("N1", "　M a rs", "PARTICIPANT", delay = 840, location = "mars"),
  ltx_node("N2", "﻿L\u0085u​na", "PARTICIPANT", delay = 2, location = "moon"))
check(make_plan_id(wsp) == "LTX-20260315-EARTHHQ-MARS-L\u0085U​-v2-741793bf", "JS whitespace + escaping planId == JS")
ww <- enc2utf8(wire_of(wsp))
Encoding(ww) <- "UTF-8"
check(startsWith(ww, paste0('{"v":2,"title":"C\\u0001\\b\\t\\n\\u000b\\f\\r\\u001f\\"\\\\/',
                            "\u007f  é\U0001F680", '",')),
      "escaping matches JSON.stringify")
check(make_plan_id(parse_json(ww)) == make_plan_id(wsp), "JSON planId of the escaped wire == typed")
check(grepl("LTX-NODE:ID=EARTH-HQ;ROLE=HOST", generate_ics(wsp), fixed = TRUE), "ICS node id uses JS whitespace")

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0L) quit(status = 1L)
