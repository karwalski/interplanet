# Interop driver for r/ltx (see scripts/interop/run.js).
# Usage: Rscript driver.R IN OUT   (needs jsonlite to read the JS plans)
args <- commandArgs(trailingOnly = TRUE)
in_dir <- args[[1]]; out_dir <- args[[2]]
root <- Sys.getenv("ROOT")
for (f in c("constants.R", "ltx.R", "parity.R")) source(file.path(root, "r/ltx/R", f))

plan <- create_plan(title = "Réunion Mars \U0001F680", start_iso = "2026-03-15T14:00:00.000Z",
                    quantum = 3, mode = "LTX-ASYNC", delay = 840)
plan$nodes <- list(
  ltx_node("N0", "Earth HQ", "HOST", delay = 0, location = "earth"),
  ltx_node("N1", "Mars Hab-01", "PARTICIPANT", delay = 840, location = "mars"),
  ltx_node("N2", "L-1 Gateway", "PARTICIPANT", delay = 2, location = "moon"))
# ltx_segment_spec is (type, q) only: no speaker/label.
plan$segments <- list(ltx_segment_spec("PLAN_CONFIRM", 2), ltx_segment_spec("TX", 3),
                      ltx_segment_spec("RX", 3), ltx_segment_spec("TX", 2),
                      ltx_segment_spec("BUFFER", 1))
cat("NOTE ltx_segment_spec has no speaker/label\n")

write_wire <- function(name, hash) {
  con <- file(file.path(out_dir, name), "wb")
  writeBin(charToRaw(enc2utf8(b64url_decode(sub("^#l=", "", hash)))), con)
  close(con)
}

write_wire("wire-v2.json", encode_hash(plan))
cat("ID_V2", make_plan_id(plan), "\n")

v3 <- upgrade_plan_to_v3(plan, list(delays = list(`N1|N2` = 842L)))
write_wire("wire-v3.json", encode_hash(v3))
cat("ID_V3", make_plan_id(v3), "\n")
cat("NOTE v3 via upgrade_plan_to_v3; wire via encode_hash\n")

for (v in c("2", "3")) {
  txt <- paste(readLines(file.path(in_dir, sprintf("js-v%s.json", v)), encoding = "UTF-8", warn = FALSE),
               collapse = "\n")
  cat(sprintf("JS_V%s", v), make_plan_id(jsonlite::fromJSON(txt, simplifyVector = FALSE)), "\n")
}
