//! fixture_check — cross-validates the Rust crate against
//! `libinterplanet/fixtures/reference.json` (54 entries).
//!
//! Uses only the standard library for JSON parsing (simple line-by-line
//! extraction; the fixture file is pretty-printed and machine-generated).
//!
//! Exit 0 on success; exit 1 if any assertion fails.

use std::path::PathBuf;
use interplanet_time::{
    get_planet_time, helio_pos, light_travel_seconds, Planet,
};

// ── Tiny JSON helpers (stdlib-only) ──────────────────────────────────────────

/// Extract the string value of a JSON field from a single line, e.g.
/// `  "planet": "mars",` → `"mars"`.
fn str_field<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let needle = format!("\"{}\":", key);
    let start  = line.find(needle.as_str())? + needle.len();
    let rest   = line[start..].trim();
    if rest.starts_with('"') {
        let inner = &rest[1..];
        let end   = inner.find('"')?;
        Some(&inner[..end])
    } else {
        None
    }
}

/// Extract the numeric value of a JSON field from a single line (may be null).
fn num_field(line: &str, key: &str) -> Option<f64> {
    let needle = format!("\"{}\":", key);
    let start  = line.find(needle.as_str())? + needle.len();
    let rest   = line[start..].trim();
    if rest.starts_with("null") { return None; }
    // strip trailing comma / brace
    let end = rest.find(|c: char| c == ',' || c == '}' || c == '\n')
                  .unwrap_or(rest.len());
    rest[..end].trim().parse::<f64>().ok()
}

// ── Entry struct ──────────────────────────────────────────────────────────────

#[derive(Default)]
struct Entry {
    utc_ms:       i64,
    planet:       String,
    hour:         i32,
    minute:       i32,
    second:       i32,
    light_travel: Option<f64>,
    helio_r_au:   Option<f64>,
}

// ── Parse fixture ─────────────────────────────────────────────────────────────

fn parse_fixture(json: &str) -> Vec<Entry> {
    let mut entries = Vec::new();
    let mut cur: Option<Entry> = None;
    let mut in_entries = false;

    for raw_line in json.lines() {
        let line = raw_line.trim();

        if line.contains("\"entries\"") { in_entries = true; continue; }
        if !in_entries { continue; }

        // Start of new object
        if line == "{" {
            cur = Some(Entry::default());
            continue;
        }
        // End of object
        if line == "}" || line == "}," {
            if let Some(e) = cur.take() {
                if !e.planet.is_empty() { entries.push(e); }
            }
            continue;
        }
        // "]" closes the entries array — stop
        if line == "]" || line == "]," { break; }

        let Some(ref mut e) = cur else { continue };

        if let Some(v) = str_field(line, "planet") { e.planet = v.to_string(); }
        if let Some(v) = num_field(line, "utc_ms")  { e.utc_ms = v as i64; }
        if let Some(v) = num_field(line, "hour")    { e.hour   = v as i32; }
        if let Some(v) = num_field(line, "minute")  { e.minute = v as i32; }
        if let Some(v) = num_field(line, "second")  { e.second = v as i32; }
        if line.contains("\"light_travel_s\"") {
            e.light_travel = num_field(line, "light_travel_s");
        }
        if line.contains("\"helio_r_au\"") {
            e.helio_r_au = num_field(line, "helio_r_au");
        }
    }
    entries
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn main() {
    // Locate reference.json relative to this crate's root.
    // Expected layout: …/interplanet-github/rust/planet-time/  (crate root)
    //                  …/interplanet-github/c/planet-time/fixtures/reference.json
    let manifest = std::env::var("CARGO_MANIFEST_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."));
    let fixture_path = manifest.join("../../c/planet-time/fixtures/reference.json");

    let json = std::fs::read_to_string(&fixture_path).unwrap_or_else(|e| {
        eprintln!("Cannot read fixture: {}: {}", fixture_path.display(), e);
        std::process::exit(1);
    });

    let entries = parse_fixture(&json);
    println!("Loaded {} entries from fixture.", entries.len());

    let mut pass = 0usize;
    let mut fail = 0usize;

    for (i, entry) in entries.iter().enumerate() {
        let planet = match Planet::from_str(&entry.planet) {
            Some(p) => p,
            None => {
                eprintln!("  [{}] unknown planet '{}'", i, entry.planet);
                fail += 1;
                continue;
            }
        };

        let pt = get_planet_time(planet, entry.utc_ms, 0.0);

        // hour / minute / second
        if pt.hour != entry.hour || pt.minute != entry.minute || pt.second != entry.second {
            eprintln!(
                "  FAIL [{}] {} @ {}: expected {:02}:{:02}:{:02} got {:02}:{:02}:{:02}",
                i, entry.planet, entry.utc_ms,
                entry.hour, entry.minute, entry.second,
                pt.hour, pt.minute, pt.second,
            );
            fail += 1;
        } else {
            pass += 1;
        }

        // light_travel_s (Earth→planet only; null for Earth itself)
        if let Some(expected_lt) = entry.light_travel {
            let got_lt = light_travel_seconds(Planet::Earth, planet, entry.utc_ms);
            if (got_lt - expected_lt).abs() > 1.0 {
                eprintln!(
                    "  FAIL [{}] {} light_travel: expected {:.3} got {:.3} (delta {:.3})",
                    i, entry.planet, expected_lt, got_lt, (got_lt - expected_lt).abs()
                );
                fail += 1;
            } else {
                pass += 1;
            }
        }

        // helio_r_au
        if let Some(expected_r) = entry.helio_r_au {
            let hp = helio_pos(planet, entry.utc_ms);
            if (hp.r - expected_r).abs() > 0.002 {
                eprintln!(
                    "  FAIL [{}] {} helio_r: expected {:.5} got {:.5} (delta {:.5})",
                    i, entry.planet, expected_r, hp.r, (hp.r - expected_r).abs()
                );
                fail += 1;
            } else {
                pass += 1;
            }
        }
    }

    println!("Fixture check: {} passed, {} failed", pass, fail);
    if fail > 0 { std::process::exit(1); }
}
