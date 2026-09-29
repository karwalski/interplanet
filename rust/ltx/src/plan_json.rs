//! Wire-format plan helpers that mirror ltx-sdk.js exactly:
//!
//! - [`parse_ordered_json`]: `JSON.parse` with key insertion order kept
//! - [`make_plan_id_from_json`] / [`plan_hash_from_json`]: `makePlanId` /
//!   `planHash` over the plan exactly as received (the frozen v2 hash is
//!   insertion-order sensitive, LTX-SPECIFICATION.md §4.3)
//! - [`validate_plan`]: `validatePlan` (§3.5, §4, §7), including the reserved
//!   streams / branching rules
//!
//! Golden vectors: spec/golden/plan-ids.json.

use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

use crate::CjsonVal;

/// A JSON value that keeps object key insertion order, as a JavaScript
/// object does. Numbers are f64, as in JavaScript.
#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    Null,
    Bool(bool),
    Number(f64),
    Str(String),
    Array(Vec<JsonValue>),
    Object(Vec<(String, JsonValue)>),
}

impl JsonValue {
    /// Object member lookup (None for non-objects or absent keys).
    pub fn get(&self, key: &str) -> Option<&JsonValue> {
        match self {
            JsonValue::Object(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }
    /// `Object.prototype.hasOwnProperty`.
    pub fn has(&self, key: &str) -> bool { self.get(key).is_some() }
    pub fn as_str(&self) -> Option<&str> {
        match self { JsonValue::Str(s) => Some(s), _ => None }
    }
    pub fn as_f64(&self) -> Option<f64> {
        match self { JsonValue::Number(n) => Some(*n), _ => None }
    }
    pub fn as_array(&self) -> Option<&[JsonValue]> {
        match self { JsonValue::Array(a) => Some(a), _ => None }
    }
    /// Assign `key` in place when present, else append (JS assignment order).
    pub fn set(&mut self, key: &str, value: JsonValue) {
        if let JsonValue::Object(m) = self {
            if let Some(slot) = m.iter_mut().find(|(k, _)| k == key) {
                slot.1 = value;
            } else {
                m.push((key.to_string(), value));
            }
        }
    }
}

impl From<&CjsonVal> for JsonValue {
    fn from(v: &CjsonVal) -> Self {
        match v {
            CjsonVal::Null => JsonValue::Null,
            CjsonVal::Bool(b) => JsonValue::Bool(*b),
            CjsonVal::Int(n) => JsonValue::Number(*n as f64),
            CjsonVal::Str(s) => JsonValue::Str(s.clone()),
            CjsonVal::Array(a) => JsonValue::Array(a.iter().map(JsonValue::from).collect()),
            CjsonVal::Object(m) => JsonValue::Object(m.iter().map(|(k, v)| (k.clone(), JsonValue::from(v))).collect()),
        }
    }
}

// ── Parser ─────────────────────────────────────────────────────────────────

struct Parser<'a> { b: &'a [u8], pos: usize, depth: usize }

impl<'a> Parser<'a> {
    fn ws(&mut self) {
        while self.pos < self.b.len() && matches!(self.b[self.pos], b' ' | b'\t' | b'\n' | b'\r') { self.pos += 1; }
    }
    fn peek(&self) -> Option<u8> { self.b.get(self.pos).copied() }
    fn eat(&mut self, c: u8) -> Result<(), String> {
        if self.peek() == Some(c) { self.pos += 1; Ok(()) } else { Err(format!("json: expected '{}' at {}", c as char, self.pos)) }
    }
    fn lit(&mut self, s: &str, v: JsonValue) -> Result<JsonValue, String> {
        if self.b[self.pos..].starts_with(s.as_bytes()) { self.pos += s.len(); Ok(v) } else { Err(format!("json: bad literal at {}", self.pos)) }
    }
    fn value(&mut self) -> Result<JsonValue, String> {
        self.ws();
        if self.depth > 128 { return Err("json: nesting too deep".into()); }
        match self.peek().ok_or("json: unexpected end")? {
            b'{' => {
                self.pos += 1;
                self.depth += 1;
                let mut obj = JsonValue::Object(Vec::new());
                self.ws();
                if self.peek() == Some(b'}') { self.pos += 1; self.depth -= 1; return Ok(obj); }
                loop {
                    self.ws();
                    let k = self.string()?;
                    self.ws();
                    self.eat(b':')?;
                    let v = self.value()?;
                    obj.set(&k, v);
                    self.ws();
                    match self.peek() {
                        Some(b',') => self.pos += 1,
                        Some(b'}') => { self.pos += 1; self.depth -= 1; return Ok(obj); }
                        _ => return Err(format!("json: expected ',' or '}}' at {}", self.pos)),
                    }
                }
            }
            b'[' => {
                self.pos += 1;
                self.depth += 1;
                let mut arr = Vec::new();
                self.ws();
                if self.peek() == Some(b']') { self.pos += 1; self.depth -= 1; return Ok(JsonValue::Array(arr)); }
                loop {
                    arr.push(self.value()?);
                    self.ws();
                    match self.peek() {
                        Some(b',') => self.pos += 1,
                        Some(b']') => { self.pos += 1; self.depth -= 1; return Ok(JsonValue::Array(arr)); }
                        _ => return Err(format!("json: expected ',' or ']' at {}", self.pos)),
                    }
                }
            }
            b'"' => Ok(JsonValue::Str(self.string()?)),
            b't' => self.lit("true", JsonValue::Bool(true)),
            b'f' => self.lit("false", JsonValue::Bool(false)),
            b'n' => self.lit("null", JsonValue::Null),
            _ => {
                let start = self.pos;
                while self.pos < self.b.len() && matches!(self.b[self.pos], b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9') { self.pos += 1; }
                let s = std::str::from_utf8(&self.b[start..self.pos]).map_err(|_| "json: bad number")?;
                s.parse::<f64>().map(JsonValue::Number).map_err(|_| format!("json: bad number '{}'", s))
            }
        }
    }
    fn hex4(&mut self) -> Result<u32, String> {
        let s = self.b.get(self.pos..self.pos + 4).ok_or("json: bad \\u")?;
        let v = u32::from_str_radix(std::str::from_utf8(s).map_err(|_| "json: bad \\u")?, 16).map_err(|_| "json: bad \\u")?;
        self.pos += 4;
        Ok(v)
    }
    fn string(&mut self) -> Result<String, String> {
        self.eat(b'"')?;
        let mut out = String::new();
        loop {
            let c = self.peek().ok_or("json: unterminated string")?;
            self.pos += 1;
            match c {
                b'"' => return Ok(out),
                b'\\' => {
                    let e = self.peek().ok_or("json: bad escape")?;
                    self.pos += 1;
                    match e {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let mut cp = self.hex4()?;
                            if (0xD800..0xDC00).contains(&cp) && self.b[self.pos..].starts_with(b"\\u") {
                                self.pos += 2;
                                let lo = self.hex4()?;
                                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo.wrapping_sub(0xDC00) & 0x3FF);
                            }
                            out.push(char::from_u32(cp).unwrap_or('\u{FFFD}'));
                        }
                        _ => return Err(format!("json: bad escape at {}", self.pos)),
                    }
                }
                _ => {
                    let start = self.pos - 1;
                    let len = match c { 0x00..=0x7F => 1, 0xC0..=0xDF => 2, 0xE0..=0xEF => 3, _ => 4 };
                    let s = std::str::from_utf8(self.b.get(start..start + len).ok_or("json: bad utf8")?).map_err(|_| "json: bad utf8")?;
                    out.push_str(s);
                    self.pos = start + len;
                }
            }
        }
    }
}

/// Parse JSON like `JSON.parse`, preserving object key order. A duplicate key
/// keeps its first position and takes the last value.
pub fn parse_ordered_json(s: &str) -> Result<JsonValue, String> {
    let mut p = Parser { b: s.as_bytes(), pos: 0, depth: 0 };
    let v = p.value()?;
    p.ws();
    if p.pos != p.b.len() { return Err(format!("json: trailing data at {}", p.pos)); }
    Ok(v)
}

// ── JavaScript-compatible serialisation ────────────────────────────────────

/// `Number.prototype.toString` (also the RFC 8785 number form).
pub fn js_number(f: f64) -> String {
    if !f.is_finite() { return "null".into(); }
    if f == 0.0 { return "0".into(); }
    let neg = f < 0.0;
    let s = format!("{:e}", f.abs()); // shortest digits, e.g. "8.6e2"
    let (mant, exp) = s.split_once('e').unwrap_or((&s, "0"));
    let exp: i32 = exp.parse().unwrap_or(0);
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    let k = digits.len() as i32;
    let n = exp + 1;
    let out = if k <= n && n <= 21 {
        format!("{}{}", digits, "0".repeat((n - k) as usize))
    } else if 0 < n && n <= 21 {
        format!("{}.{}", &digits[..n as usize], &digits[n as usize..])
    } else if -6 < n && n <= 0 {
        format!("0.{}{}", "0".repeat((-n) as usize), digits)
    } else {
        let e = n - 1;
        let frac = if k > 1 { format!(".{}", &digits[1..]) } else { String::new() };
        format!("{}{}e{}{}", &digits[..1], frac, if e < 0 { '-' } else { '+' }, e.abs())
    };
    if neg { format!("-{}", out) } else { out }
}

/// Quote a string as `JSON.stringify` does.
pub fn js_quote(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\u{0008}' => o.push_str("\\b"),
            '\u{000c}' => o.push_str("\\f"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn utf16_cmp(a: &str, b: &str) -> std::cmp::Ordering { a.encode_utf16().cmp(b.encode_utf16()) }

fn serialize(v: &JsonValue, canonical: bool, out: &mut String) {
    match v {
        JsonValue::Null => out.push_str("null"),
        JsonValue::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        JsonValue::Number(n) => out.push_str(&js_number(*n)),
        JsonValue::Str(s) => out.push_str(&js_quote(s)),
        JsonValue::Array(a) => {
            out.push('[');
            for (i, e) in a.iter().enumerate() {
                if i > 0 { out.push(','); }
                serialize(e, canonical, out);
            }
            out.push(']');
        }
        JsonValue::Object(m) => {
            let mut members: Vec<&(String, JsonValue)> = m.iter().collect();
            if canonical { members.sort_by(|a, b| utf16_cmp(&a.0, &b.0)); }
            out.push('{');
            for (i, (k, e)) in members.into_iter().enumerate() {
                if i > 0 { out.push(','); }
                out.push_str(&js_quote(k));
                out.push(':');
                serialize(e, canonical, out);
            }
            out.push('}');
        }
    }
}

/// `JSON.stringify` (insertion order).
pub fn js_stringify(v: &JsonValue) -> String { let mut s = String::new(); serialize(v, false, &mut s); s }

/// ltx-sdk.js `canonicalJSON`: keys sorted by UTF-16 code units at every level.
pub fn canonical_json_ordered(v: &JsonValue) -> String { let mut s = String::new(); serialize(v, true, &mut s); s }

/// Frozen v2 planId hash: `h = imul(31, h) + charCodeAt(i)` over UTF-16 units.
pub fn imul31(s: &str) -> u32 {
    s.encode_utf16().fold(0u32, |h, u| h.wrapping_mul(31).wrapping_add(u as u32))
}

// ── makePlanId / planHash over the wire plan ──────────────────────────────

fn utf16_prefix(s: &str, max: usize) -> String {
    let units: Vec<u16> = s.encode_utf16().take(max).collect();
    String::from_utf16_lossy(&units)
}

fn name_token(name: &str, max: usize) -> String {
    let stripped: String = name.chars().filter(|c| !c.is_whitespace() && *c != '\u{FEFF}').collect();
    utf16_prefix(&stripped.to_uppercase(), max)
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Parse the ISO 8601 forms `Date.parse` accepts for a plan start
/// (YYYY-MM-DD, or YYYY-MM-DDTHH:MM[:SS[.sss]] with Z or ±HH:MM). Returns
/// UTC epoch milliseconds.
pub fn parse_js_date(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    let num = |a: usize, n: usize| -> Option<i64> {
        let part = b.get(a..a + n)?;
        if !part.iter().all(|c| c.is_ascii_digit()) { return None; }
        std::str::from_utf8(part).ok()?.parse().ok()
    };
    if b.len() < 10 || b[4] != b'-' || b[7] != b'-' { return None; }
    let (y, mo, d) = (num(0, 4)?, num(5, 2)?, num(8, 2)?);
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) { return None; }
    let day_ms = days_from_civil(y, mo, d) * 86_400_000;
    if b.len() == 10 { return Some(day_ms); }
    if b[10] != b'T' || b.len() < 16 || b[13] != b':' { return None; }
    let (h, mi) = (num(11, 2)?, num(14, 2)?);
    let mut pos = 16;
    let mut sec = 0;
    let mut ms = 0;
    if b.get(pos) == Some(&b':') {
        sec = num(pos + 1, 2)?;
        pos += 3;
        if b.get(pos) == Some(&b'.') {
            let start = pos + 1;
            let mut end = start;
            while end < b.len() && b[end].is_ascii_digit() { end += 1; }
            if end == start { return None; }
            let frac = std::str::from_utf8(&b[start..end]).ok()?;
            let frac3: String = format!("{:0<3}", frac).chars().take(3).collect();
            ms = frac3.parse().ok()?;
            pos = end;
        }
    }
    if h > 24 || mi > 59 || sec > 59 { return None; }
    let offset_ms = match b.get(pos) {
        Some(b'Z') if pos + 1 == b.len() => 0,
        Some(c @ (b'+' | b'-')) if pos + 6 == b.len() && b[pos + 3] == b':' => {
            let off = num(pos + 1, 2)? * 3_600_000 + num(pos + 4, 2)? * 60_000;
            if *c == b'+' { off } else { -off }
        }
        _ => return None,
    };
    Some(day_ms + h * 3_600_000 + mi * 60_000 + sec * 1000 + ms - offset_ms)
}

fn yyyymmdd(ms: i64) -> String {
    let days = ms.div_euclid(86_400_000);
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{:04}{:02}{:02}", y, m, d)
}

/// `upgradeConfig`: v2+ plans with nodes unchanged; v1 configs
/// (txName/rxName/delay) gain v:2 and nodes.
fn upgrade_config_value(cfg: &JsonValue) -> JsonValue {
    let v = cfg.get("v").and_then(|x| x.as_f64()).unwrap_or(0.0);
    if v >= 2.0 && cfg.get("nodes").and_then(|x| x.as_array()).map_or(false, |a| !a.is_empty()) {
        return cfg.clone();
    }
    let s = |k: &str, def: &str| cfg.get(k).and_then(|x| x.as_str()).filter(|x| !x.is_empty()).unwrap_or(def).to_string();
    let rx = cfg.get("rxName").and_then(|x| x.as_str()).unwrap_or("").to_lowercase();
    let loc = if rx.contains("mars") { "mars" } else if rx.contains("moon") { "moon" } else { "earth" };
    let delay = cfg.get("delay").and_then(|x| x.as_f64()).filter(|d| *d != 0.0).unwrap_or(0.0);
    let node = |id: &str, name: String, role: &str, delay: f64, loc: &str| JsonValue::Object(vec![
        ("id".into(), JsonValue::Str(id.into())), ("name".into(), JsonValue::Str(name)),
        ("role".into(), JsonValue::Str(role.into())), ("delay".into(), JsonValue::Number(delay)),
        ("location".into(), JsonValue::Str(loc.into())),
    ]);
    let mut out = cfg.clone();
    out.set("v", JsonValue::Number(2.0));
    out.set("nodes", JsonValue::Array(vec![
        node("N0", s("txName", "Earth HQ"), "HOST", 0.0, "earth"),
        node("N1", s("rxName", "Mars Hab-01"), "PARTICIPANT", delay, loc),
    ]));
    out
}

/// `makePlanId` over a plan value exactly as received. Unlike
/// [`crate::make_plan_id`] (which serialises the typed `LtxPlan` in a fixed
/// key order) this keeps the wire key order the frozen v2 hash depends on,
/// and every field the plan carries (relay, questions, streams, ...).
pub fn make_plan_id_from_value(plan: &JsonValue) -> Result<String, String> {
    if !matches!(plan, JsonValue::Object(_)) { return Err("makePlanId: plan must be a JSON object".into()); }
    let c = upgrade_config_value(plan);
    let start = c.get("start").and_then(|x| x.as_str()).unwrap_or("");
    let ms = parse_js_date(start).ok_or_else(|| format!("makePlanId: invalid start {:?}", start))?;
    let date = yyyymmdd(ms);
    let nodes = c.get("nodes").and_then(|x| x.as_array()).unwrap_or(&[]);
    let host_str = nodes.first().and_then(|n| n.get("name")).and_then(|x| x.as_str())
        .filter(|s| !s.is_empty()).map(|s| name_token(s, 8)).unwrap_or_else(|| "HOST".into());
    let node_str = if nodes.len() > 1 {
        let parts: Vec<String> = nodes[1..].iter()
            .map(|n| name_token(n.get("name").and_then(|x| x.as_str()).unwrap_or(""), 4)).collect();
        utf16_prefix(&parts.join("-"), 16)
    } else { "RX".into() };
    if c.get("v").and_then(|x| x.as_f64()).unwrap_or(0.0) >= 3.0 {
        let digest = Sha256::digest(canonical_json_ordered(&c).as_bytes());
        let hex8: String = digest.iter().take(4).map(|b| format!("{:02x}", b)).collect();
        return Ok(format!("LTX-{}-{}-{}-v3-{}", date, host_str, node_str, hex8));
    }
    Ok(format!("LTX-{}-{}-{}-v2-{:08x}", date, host_str, node_str, imul31(&js_stringify(&c))))
}

/// `makePlanId` over a plan's JSON text, preserving key order.
pub fn make_plan_id_from_json(json: &str) -> Result<String, String> {
    make_plan_id_from_value(&parse_ordered_json(json)?)
}

/// `planHash` over a plan value: SHA-256 hex of its canonical JSON (§6.4).
pub fn plan_hash_from_value(plan: &JsonValue) -> String {
    Sha256::digest(canonical_json_ordered(plan).as_bytes()).iter().map(|b| format!("{:02x}", b)).collect()
}

/// `planHash` over a plan's JSON text.
pub fn plan_hash_from_json(json: &str) -> Result<String, String> {
    Ok(plan_hash_from_value(&parse_ordered_json(json)?))
}

// ── validatePlan (LTX-SPECIFICATION.md §3.5, §4, §7) ──────────────────────

/// One validatePlan finding.
#[derive(Debug, Clone, PartialEq)]
pub struct PlanError {
    pub code: String,
    pub path: String,
    pub message: String,
}

/// validatePlan result.
#[derive(Debug, Clone, PartialEq)]
pub struct PlanValidation {
    pub valid: bool,
    pub errors: Vec<PlanError>,
}

impl PlanValidation {
    /// True when any error carries `code`.
    pub fn has_code(&self, code: &str) -> bool { self.errors.iter().any(|e| e.code == code) }
}

/// Error from a constructing path (create_amendment, create_session_from_json)
/// for a plan with reserved stream / branching fields. `code` is the first
/// error's code ("reserved_streams" or "reserved_branching").
#[derive(Debug, Clone, PartialEq)]
pub struct ReservedFieldError {
    pub code: String,
    pub errors: Vec<PlanError>,
    pub message: String,
}

impl std::fmt::Display for ReservedFieldError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { f.write_str(&self.message) }
}

impl std::error::Error for ReservedFieldError {}

const PLAN_SEGMENT_TYPES: [&str; 11] = ["PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE", "SPEAK", "REST", "PAD", "OPEN", "RELAY"];
const PLAN_MODES: [&str; 4] = ["LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC"];
const V3_ONLY_FIELDS: [&str; 6] = ["delays", "planVersion", "prevPlanHash", "questions", "actions", "streams"];

fn perr(code: &str, path: impl Into<String>, message: impl Into<String>) -> PlanError {
    PlanError { code: code.into(), path: path.into(), message: message.into() }
}

/// Reserved-field violations only (§3.5 streams, §7 branching).
pub fn reserved_field_errors(plan: &JsonValue) -> Vec<PlanError> {
    let mut errs = Vec::new();
    if !matches!(plan, JsonValue::Object(_)) { return errs; }
    if let Some(s) = plan.get("streams") {
        if !matches!(s, JsonValue::Array(a) if a.is_empty()) {
            errs.push(perr("reserved_streams", "streams", "streams[] is reserved (§3.5) and MUST be absent or empty"));
        }
    }
    for f in ["branches", "branching"] {
        if plan.has(f) {
            errs.push(perr("reserved_branching", f, format!("{} is reserved for branching (§7, not yet implemented) and MUST be absent", f)));
        }
    }
    if let Some(segs) = plan.get("segments").and_then(|x| x.as_array()) {
        for (i, s) in segs.iter().enumerate() {
            if s.has("stream") {
                errs.push(perr("reserved_streams", format!("segments[{}].stream", i), "segment stream is reserved (§3.5) and MUST be absent"));
            }
            if s.has("branch") {
                errs.push(perr("reserved_branching", format!("segments[{}].branch", i), "segment branch is reserved for branching (§7) and MUST be absent"));
            }
        }
    }
    errs
}

/// Err with a [`ReservedFieldError`] if `plan` uses reserved fields.
pub fn assert_no_reserved_fields(plan: &JsonValue, fn_name: &str) -> Result<(), ReservedFieldError> {
    let errors = reserved_field_errors(plan);
    match errors.first() {
        None => Ok(()),
        Some(first) => Err(ReservedFieldError {
            code: first.code.clone(),
            message: format!("{}: {}", fn_name, first.message),
            errors,
        }),
    }
}

fn js_integer(v: Option<&JsonValue>) -> Option<f64> {
    v.and_then(|x| x.as_f64()).filter(|f| f.is_finite() && f.fract() == 0.0)
}

/// Validate a v2 or v3 plan against the wire format (spec/ltx-schema.json,
/// §4) and the reserved-field rules (§3.5 streams, §7 branching), mirroring
/// ltx-sdk.js validatePlan. Pure; never panics.
///
/// Error codes: not_an_object, invalid_version, missing_field, invalid_field,
/// invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
/// duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
/// invalid_delays, reserved_streams, reserved_branching.
pub fn validate_plan(plan: &JsonValue) -> PlanValidation {
    let mut errs: Vec<PlanError> = Vec::new();
    if !matches!(plan, JsonValue::Object(_)) {
        errs.push(perr("not_an_object", "", "plan must be an object"));
        return PlanValidation { valid: false, errors: errs };
    }
    let v = plan.get("v").and_then(|x| x.as_f64());
    let (is_v2, is_v3) = (v == Some(2.0), v == Some(3.0));
    if !is_v2 && !is_v3 { errs.push(perr("invalid_version", "v", "v must be 2 or 3")); }
    for f in ["title", "start", "quantum", "mode", "nodes", "segments"] {
        if !plan.has(f) { errs.push(perr("missing_field", f, format!("{} is required", f))); }
    }
    if let Some(t) = plan.get("title") {
        if t.as_str().is_none() { errs.push(perr("invalid_field", "title", "title must be a string")); }
    }
    if let Some(s) = plan.get("start") {
        if s.as_str().and_then(parse_js_date).is_none() {
            errs.push(perr("invalid_field", "start", "start must be an ISO 8601 UTC timestamp"));
        }
    }
    if plan.has("quantum") && !js_integer(plan.get("quantum")).map_or(false, |q| (1.0..=60.0).contains(&q)) {
        errs.push(perr("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)"));
    }
    if let Some(m) = plan.get("mode") {
        if !m.as_str().map_or(false, |s| PLAN_MODES.contains(&s)) {
            errs.push(perr("invalid_mode", "mode", format!("mode must be one of {}", PLAN_MODES.join(", "))));
        }
    }

    let mut ids: Vec<String> = Vec::new();
    if let Some(nv) = plan.get("nodes") {
        match nv.as_array() {
            Some(nodes) if !nodes.is_empty() => {
                let mut hosts = 0;
                for (i, n) in nodes.iter().enumerate() {
                    let id = n.get("id").and_then(|x| x.as_str());
                    let role = n.get("role").and_then(|x| x.as_str());
                    let delay = n.get("delay").and_then(|x| x.as_f64());
                    let ok = matches!(n, JsonValue::Object(_))
                        && id.map_or(false, |s| !s.is_empty() && !s.contains('|'))
                        && n.get("name").and_then(|x| x.as_str()).is_some()
                        && role.map_or(false, |r| ["HOST", "PARTICIPANT", "OBSERVER"].contains(&r))
                        && delay.map_or(false, |d| d >= 0.0);
                    if !ok {
                        errs.push(perr("invalid_nodes", format!("nodes[{}]", i), "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0"));
                        continue;
                    }
                    let id = id.unwrap().to_string();
                    if ids.contains(&id) {
                        errs.push(perr("duplicate_node_id", format!("nodes[{}].id", i), format!("duplicate node id {}", id)));
                    }
                    ids.push(id);
                    if role == Some("HOST") { hosts += 1; }
                }
                let h = &nodes[0];
                let h_ok = matches!(h, JsonValue::Object(_))
                    && h.get("role").and_then(|x| x.as_str()) == Some("HOST")
                    && h.get("delay").and_then(|x| x.as_f64()) == Some(0.0);
                if hosts != 1 || !h_ok {
                    errs.push(perr("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)"));
                }
            }
            _ => errs.push(perr("invalid_nodes", "nodes", "nodes must be a non-empty array")),
        }
    }

    if let Some(sv) = plan.get("segments") {
        match sv.as_array() {
            None => errs.push(perr("invalid_segment", "segments", "segments must be an array")),
            Some(segs) => {
                for (i, s) in segs.iter().enumerate() {
                    let is_obj = matches!(s, JsonValue::Object(_) | JsonValue::Array(_));
                    let type_ok = s.get("type").and_then(|x| x.as_str()).map_or(false, |t| PLAN_SEGMENT_TYPES.contains(&t));
                    let q_ok = js_integer(s.get("q")).map_or(false, |q| q >= 1.0);
                    if !is_obj || !type_ok || !q_ok {
                        errs.push(perr("invalid_segment", format!("segments[{}]", i), "segment needs a known type and integer q >= 1"));
                        continue;
                    }
                    if let Some(sp) = s.get("speaker") {
                        if !sp.as_str().map_or(false, |x| ids.iter().any(|id| id == x)) {
                            let shown = sp.as_str().map(|x| x.to_string()).unwrap_or_else(|| js_stringify(sp));
                            errs.push(perr("unknown_speaker", format!("segments[{}].speaker", i), format!("speaker {} is not a node id", shown)));
                        }
                    }
                }
            }
        }
    }

    if is_v2 {
        for f in V3_ONLY_FIELDS {
            if plan.has(f) {
                errs.push(perr("v3_field_in_v2", f, format!("{} is a v3 field and MUST NOT appear in a v2 plan (§4.3)", f)));
            }
        }
    } else if is_v3 {
        if let Some(d) = plan.get("delays") {
            match d {
                JsonValue::Object(m) => {
                    for (k, val) in m {
                        let parts: Vec<&str> = k.split('|').collect();
                        let ok = parts.len() == 2
                            && utf16_cmp(parts[0], parts[1]) == std::cmp::Ordering::Less
                            && (ids.is_empty() || (ids.iter().any(|x| x == parts[0]) && ids.iter().any(|x| x == parts[1])))
                            && val.as_f64().map_or(false, |x| x >= 0.0);
                        if !ok {
                            errs.push(perr("invalid_delays", format!("delays.{}", k), "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)"));
                        }
                    }
                }
                _ => errs.push(perr("invalid_delays", "delays", "delays must be an object")),
            }
        }
        if plan.has("planVersion") && !js_integer(plan.get("planVersion")).map_or(false, |p| p >= 1.0) {
            errs.push(perr("invalid_field", "planVersion", "planVersion must be an integer >= 1"));
        }
        if let Some(ph) = plan.get("prevPlanHash") {
            let ok = ph.as_str().map_or(false, |s| s.len() == 64 && s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')));
            if !ok { errs.push(perr("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")); }
        }
        for f in ["questions", "actions"] {
            if let Some(x) = plan.get(f) {
                if x.as_array().is_none() { errs.push(perr("invalid_field", f, format!("{} must be an array", f))); }
            }
        }
    }

    errs.extend(reserved_field_errors(plan));
    PlanValidation { valid: errs.is_empty(), errors: errs }
}

/// validatePlan over a plan's JSON text (a parse error is `not_an_object`).
pub fn validate_plan_json(json: &str) -> PlanValidation {
    match parse_ordered_json(json) {
        Ok(v) => validate_plan(&v),
        Err(e) => PlanValidation { valid: false, errors: vec![perr("not_an_object", "", format!("plan is not valid JSON: {}", e))] },
    }
}

/// Convert a sorted-key CjsonVal object map to a JsonValue object.
pub fn json_from_cjson_map(m: &BTreeMap<String, CjsonVal>) -> JsonValue {
    JsonValue::Object(m.iter().map(|(k, v)| (k.clone(), JsonValue::from(v))).collect())
}
