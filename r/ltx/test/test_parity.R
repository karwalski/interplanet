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

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0L) quit(status = 1L)
