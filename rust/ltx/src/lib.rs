// interplanet_ltx -- pure-Rust LTX SDK, no external dependencies
// Story 33.8 -- Rust 1.70+

pub const VERSION: &str = "1.0.0";
pub const DEFAULT_QUANTUM: i32 = 3;
pub const DEFAULT_API_BASE: &str = "https://interplanet.live/api/ltx.php";

/// Multiplier for plan-lock timeout: timeout = delay * factor * 1000 ms.
pub const DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR: i32 = 2;

/// Delay difference (seconds) above which a warning is issued.
pub const DELAY_VIOLATION_WARN_S: i32 = 120;

/// Delay difference (seconds) above which the session moves to DEGRADED.
pub const DELAY_VIOLATION_DEGRADED_S: i32 = 300;

/// Session lifecycle state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionState {
    Init,
    Locked,
    Running,
    Degraded,
    Complete,
}

impl SessionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            SessionState::Init     => "INIT",
            SessionState::Locked   => "LOCKED",
            SessionState::Running  => "RUNNING",
            SessionState::Degraded => "DEGRADED",
            SessionState::Complete => "COMPLETE",
        }
    }
}

pub const SESSION_STATES: [&str; 5] = ["INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE"];

#[derive(Debug, Clone)]
pub struct LtxNode {
    pub id: String,
    pub name: String,
    pub role: String,
    pub delay: i32,
    pub location: String,
}

#[derive(Debug, Clone)]
pub struct LtxSegmentTemplate {
    pub seg_type: String,
    pub q: i32,
}

#[derive(Debug, Clone)]
pub struct LtxSegment {
    pub seg_type: String,
    pub q: i32,
    pub start_ms: i64,
    pub end_ms: i64,
    pub dur_min: i32,
}

#[derive(Debug, Clone)]
pub struct LtxNodeUrl {
    pub node_id: String,
    pub name: String,
    pub role: String,
    pub url: String,
}

#[derive(Debug, Clone)]
pub struct LtxPlan {
    pub v: i32,
    pub title: String,
    pub start: String,
    pub quantum: i32,
    pub mode: String,
    pub nodes: Vec<LtxNode>,
    pub segments: Vec<LtxSegmentTemplate>,
}

pub fn default_segments() -> Vec<LtxSegmentTemplate> {
    vec![
        LtxSegmentTemplate { seg_type: "PLAN_CONFIRM".into(), q: 2 },
        LtxSegmentTemplate { seg_type: "TX".into(), q: 2 },
        LtxSegmentTemplate { seg_type: "RX".into(), q: 2 },
        LtxSegmentTemplate { seg_type: "CAUCUS".into(), q: 2 },
        LtxSegmentTemplate { seg_type: "TX".into(), q: 2 },
        LtxSegmentTemplate { seg_type: "RX".into(), q: 2 },
        LtxSegmentTemplate { seg_type: "BUFFER".into(), q: 1 },
    ]
}

pub fn create_plan(title: Option<&str>, start: &str, delay_s: i32) -> LtxPlan {
    LtxPlan {
        v: 2,
        title: title.unwrap_or("LTX Session").to_string(),
        start: start.to_string(),
        quantum: DEFAULT_QUANTUM,
        mode: "LTX".to_string(),
        nodes: vec![
            LtxNode { id: "N0".into(), name: "Earth HQ".into(), role: "HOST".into(), delay: 0, location: "earth".into() },
            LtxNode { id: "N1".into(), name: "Mars Hab-01".into(), role: "PARTICIPANT".into(), delay: delay_s, location: "mars".into() },
        ],
        segments: default_segments(),
    }
}

pub fn upgrade_config(raw: &str) -> LtxPlan {
    let title   = json_str_field(raw, "title");
    let start   = json_str_field(raw, "start").unwrap_or_default();
    let mode    = json_str_field(raw, "mode");
    let v       = json_int_field(raw, "v");
    let quantum = json_int_field(raw, "quantum");
    let mut plan = create_plan(title.as_deref(), &start, 0);
    if let Some(q) = quantum { plan.quantum = q; }
    if let Some(m) = mode    { plan.mode    = m; }
    if let Some(vv) = v      { plan.v       = vv; }
    if let Some(nodes) = json_array_field(raw, "nodes") {
        plan.nodes = nodes.into_iter().map(|obj| LtxNode {
            id:       json_str_field(&obj, "id").unwrap_or_else(|| "N0".into()),
            name:     json_str_field(&obj, "name").unwrap_or_else(|| "Unknown".into()),
            role:     json_str_field(&obj, "role").unwrap_or_else(|| "HOST".into()),
            delay:    json_int_field(&obj, "delay").unwrap_or(0),
            location: json_str_field(&obj, "location").unwrap_or_else(|| "earth".into()),
        }).collect();
    }
    if let Some(segs) = json_array_field(raw, "segments") {
        plan.segments = segs.into_iter().map(|obj| LtxSegmentTemplate {
            seg_type: json_str_field(&obj, "type").unwrap_or_else(|| "TX".into()),
            q:        json_int_field(&obj, "q").unwrap_or(2),
        }).collect();
    }
    plan
}

pub fn compute_segments(plan: &LtxPlan) -> Result<Vec<LtxSegment>, String> {
    if plan.quantum < 1 {
        return Err(format!("quantum must be a positive integer, got {}", plan.quantum));
    }
    let q_ms = (plan.quantum as i64) * 60 * 1000;
    let mut t = parse_iso_ms(&plan.start);
    let segs = plan.segments.iter().map(|tmpl| {
        let dur = (tmpl.q as i64) * q_ms;
        let seg = LtxSegment {
            seg_type: tmpl.seg_type.clone(),
            q:        tmpl.q,
            start_ms: t,
            end_ms:   t + dur,
            dur_min:  tmpl.q * plan.quantum,
        };
        t += dur;
        seg
    }).collect();
    Ok(segs)
}

pub fn total_min(plan: &LtxPlan) -> i32 {
    plan.segments.iter().map(|s| s.q * plan.quantum).sum()
}

/// Returns the plan-lock timeout in milliseconds.
/// timeout = delay_seconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000
pub fn plan_lock_timeout_ms(delay_seconds: f64) -> f64 {
    delay_seconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR as f64 * 1000.0
}

/// Compares declared vs measured one-way delay and returns severity.
/// Returns "ok", "violation", or "degraded".
pub fn check_delay_violation(declared_delay_s: f64, measured_delay_s: f64) -> &'static str {
    let diff = (measured_delay_s - declared_delay_s).abs();
    if diff > DELAY_VIOLATION_DEGRADED_S as f64 {
        "degraded"
    } else if diff > DELAY_VIOLATION_WARN_S as f64 {
        "violation"
    } else {
        "ok"
    }
}

/// Escape a string for use in RFC 5545 TEXT property values.
/// Escapes: backslash → \\, semicolon → \;, comma → \,, newline → \n
pub fn escape_ics_text(s: &str) -> String {
    let s = s.replace('\\', "\\\\");
    let s = s.replace(';', "\\;");
    let s = s.replace(',', "\\,");
    s.replace('\n', "\\n")
}

pub fn make_plan_id(plan: &LtxPlan) -> String {
    let start_ms = parse_iso_ms(&plan.start);
    let date = format_date_yyyymmdd(start_ms);
    let host_str = nodes_host_str(&plan.nodes);
    let node_str = nodes_remote_str(&plan.nodes);
    let h = plan_hash_hex(plan);
    let mut id = String::from("LTX-");
    id.push_str(&date); id.push('-');
    id.push_str(&host_str); id.push('-');
    id.push_str(&node_str);
    id.push_str("-v2-"); id.push_str(&h);
    id
}

fn nodes_host_str(nodes: &[LtxNode]) -> String {
    if nodes.is_empty() { return "HOST".to_string(); }
    let s: String = nodes[0].name.chars().filter(|c| !c.is_whitespace()).collect();
    s.to_uppercase().chars().take(8).collect()
}

fn nodes_remote_str(nodes: &[LtxNode]) -> String {
    if nodes.len() <= 1 { return "RX".to_string(); }
    let parts: Vec<String> = nodes[1..].iter().map(|n| {
        let s: String = n.name.chars().filter(|c| !c.is_whitespace()).collect();
        s.to_uppercase().chars().take(4).collect()
    }).collect();
    parts.join("-")
}

pub fn encode_hash(plan: &LtxPlan) -> String {
    let json = plan_to_json(plan);
    let payload = b64url_encode(json.as_bytes());
    let mut out = String::from("#l=");
    out.push_str(&payload);
    out
}

pub fn decode_hash(hash: &str) -> Option<LtxPlan> {
    let token = hash.trim_start_matches('#').trim_start_matches("l=");
    let bytes = b64url_decode(token)?;
    let json_str = String::from_utf8(bytes).ok()?;
    let v       = json_int_field(&json_str, "v").unwrap_or(2);
    let title   = json_str_field(&json_str, "title").unwrap_or_else(|| "LTX Session".into());
    let start   = json_str_field(&json_str, "start").unwrap_or_default();
    let quantum = json_int_field(&json_str, "quantum").unwrap_or(DEFAULT_QUANTUM);
    let mode    = json_str_field(&json_str, "mode").unwrap_or_else(|| "LTX".into());
    let raw_nodes = json_array_field(&json_str, "nodes").unwrap_or_default();
    let nodes: Vec<LtxNode> = raw_nodes.into_iter().map(|obj| LtxNode {
        id:       json_str_field(&obj, "id").unwrap_or_default(),
        name:     json_str_field(&obj, "name").unwrap_or_default(),
        role:     json_str_field(&obj, "role").unwrap_or_else(|| "HOST".into()),
        delay:    json_int_field(&obj, "delay").unwrap_or(0),
        location: json_str_field(&obj, "location").unwrap_or_else(|| "earth".into()),
    }).collect();
    let raw_segs = json_array_field(&json_str, "segments").unwrap_or_default();
    let segments: Vec<LtxSegmentTemplate> = raw_segs.into_iter().map(|obj| LtxSegmentTemplate {
        seg_type: json_str_field(&obj, "type").unwrap_or_else(|| "TX".into()),
        q:        json_int_field(&obj, "q").unwrap_or(2),
    }).collect();
    if segments.is_empty() { return None; }
    Some(LtxPlan { v, title, start, quantum, mode, nodes, segments })
}

pub fn build_node_urls(plan: &LtxPlan, base_url: &str) -> Vec<LtxNodeUrl> {
    let hash = encode_hash(plan);
    let hash_part = hash.trim_start_matches('#');
    let base = match base_url.find(|c: char| c == '?' || c == '#') {
        Some(i) => &base_url[..i],
        None    => base_url,
    };
    plan.nodes.iter().map(|node| {
        let mut url = base.to_string();
        url.push_str("?node=");
        url.push_str(&node.id);
        url.push('#');
        url.push_str(hash_part);
        LtxNodeUrl { node_id: node.id.clone(), name: node.name.clone(), role: node.role.clone(), url }
    }).collect()
}

pub fn generate_ics(plan: &LtxPlan) -> String {
    let segs     = compute_segments(plan).unwrap_or_default();
    let start_ms = parse_iso_ms(&plan.start);
    let end_ms   = segs.last().map(|s| s.end_ms).unwrap_or(start_ms);
    let plan_id  = make_plan_id(plan);
    let dt_start = ics_fmt(start_ms);
    let dt_end   = ics_fmt(end_ms);
    let dt_stamp = ics_now();
    let seg_tpl  = ics_seg_tpl(plan);
    let host_name = plan.nodes.first().map(|n| n.name.as_str()).unwrap_or("Earth HQ");
    let part_names = ics_part_names(plan);
    let delay_desc = ics_delay_desc(plan);
    let mut lines: Vec<String> = Vec::new();
    lines.push("BEGIN:VCALENDAR".into());
    lines.push("VERSION:2.0".into());
    lines.push("PRODID:-//InterPlanet//LTX v1.1//EN".into());
    lines.push("CALSCALE:GREGORIAN".into());
    lines.push("METHOD:PUBLISH".into());
    lines.push("BEGIN:VEVENT".into());
    lines.push(format!("UID:{}@interplanet.live", plan_id));
    lines.push(format!("DTSTAMP:{}", dt_stamp));
    lines.push(format!("DTSTART:{}", dt_start));
    lines.push(format!("DTEND:{}", dt_end));
    lines.push(format!("SUMMARY:{}", escape_ics_text(&plan.title)));
    lines.push(format!(
        "DESCRIPTION:LTX session -- {} with {}\\nSignal delays: {}\\nMode: {} . Segment plan: {}\\nGenerated by InterPlanet (https://interplanet.live)",
        escape_ics_text(host_name), escape_ics_text(&part_names), escape_ics_text(&delay_desc),
        escape_ics_text(&plan.mode), seg_tpl
    ));
    lines.push("LTX:1".into());
    lines.push(format!("LTX-PLANID:{}", plan_id));
    lines.push(format!("LTX-QUANTUM:PT{}M", plan.quantum));
    lines.push(format!("LTX-SEGMENT-TEMPLATE:{}", seg_tpl));
    lines.push(format!("LTX-MODE:{}", plan.mode));
    for n in &plan.nodes {
        lines.push(format!("LTX-NODE:ID={};ROLE={}", node_nid(n), n.role));
    }
    for n in plan.nodes.iter().skip(1) {
        let d = n.delay;
        lines.push(format!("LTX-DELAY;NODEID={}:ONEWAY-MIN={};ONEWAY-MAX={};ONEWAY-ASSUMED={}",
            node_nid(n), d, d+120, d));
    }
    lines.push("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY".into());
    for n in plan.nodes.iter().filter(|n| n.location == "mars") {
        lines.push(format!("LTX-LOCALTIME:NODE={};SCHEME=LMST;PARAMS=LONGITUDE:0E", node_nid(n)));
    }
    lines.push("END:VEVENT".into());
    lines.push("END:VCALENDAR".into());
    lines.join("\r\n") + "\r\n"
}

fn node_nid(n: &LtxNode) -> String {
    let parts: Vec<&str> = n.name.split_whitespace().collect();
    parts.join("-").to_uppercase()
}

fn ics_seg_tpl(plan: &LtxPlan) -> String {
    let parts: Vec<&str> = plan.segments.iter().map(|s| s.seg_type.as_str()).collect();
    parts.join(",")
}

fn ics_part_names(plan: &LtxPlan) -> String {
    if plan.nodes.len() > 1 {
        let parts: Vec<&str> = plan.nodes[1..].iter().map(|n| n.name.as_str()).collect();
        parts.join(", ")
    } else { "remote nodes".to_string() }
}

fn ics_delay_desc(plan: &LtxPlan) -> String {
    if plan.nodes.len() > 1 {
        let parts: Vec<String> = plan.nodes[1..].iter()
            .map(|n| format!("{}: {} min one-way", n.name, n.delay / 60))
            .collect();
        parts.join(" . ")
    } else { "no participant delay configured".to_string() }
}

pub fn format_hms(seconds: i32) -> String {
    let s = if seconds < 0 { 0 } else { seconds };
    let h = s / 3600;
    let m = (s % 3600) / 60;
    let sec = s % 60;
    if h > 0 { format!("{:02}:{:02}:{:02}", h, m, sec) }
    else      { format!("{:02}:{:02}", m, sec) }
}

pub fn format_utc(epoch_ms: i64) -> String {
    let secs = epoch_ms.div_euclid(1000);
    let day_secs = secs.rem_euclid(86400);
    let h = day_secs / 3600;
    let m = (day_secs % 3600) / 60;
    let s = day_secs % 60;
    format!("{:02}:{:02}:{:02} UTC", h, m, s)
}

pub fn store_session(plan: &LtxPlan, api_base: Option<&str>) -> Result<String, String> {
    let base = api_base.unwrap_or(DEFAULT_API_BASE).trim_end_matches('/');
    let endpoint = format!("{}/session", base);
    let body = format!("{{\"plan\":{}}}", plan_to_json(plan));
    http_post(&endpoint, &body)
}

pub fn get_session(plan_id: &str, api_base: Option<&str>) -> Result<String, String> {
    let base = api_base.unwrap_or(DEFAULT_API_BASE).trim_end_matches('/');
    http_get(&format!("{}/session/{}", base, url_encode(plan_id)))
}

pub fn download_ics(plan_id: &str, node_id: Option<&str>, api_base: Option<&str>) -> Result<String, String> {
    let base = api_base.unwrap_or(DEFAULT_API_BASE).trim_end_matches('/');
    let mut ep = format!("{}/ics/{}", base, url_encode(plan_id));
    if let Some(nid) = node_id { ep.push_str(&format!("?node={}", url_encode(nid))); }
    http_get(&ep)
}

pub fn submit_feedback(plan_id: &str, payload: &str, api_base: Option<&str>) -> Result<String, String> {
    let base = api_base.unwrap_or(DEFAULT_API_BASE).trim_end_matches('/');
    http_post(&format!("{}/feedback/{}", base, url_encode(plan_id)), payload)
}

fn plan_to_json(plan: &LtxPlan) -> String {
    let nodes_parts: Vec<String> = plan.nodes.iter().map(|n| {
        let mut s = String::from("{");
        s.push_str(&json_quote("id")); s.push(':'); s.push_str(&json_quote(&n.id)); s.push(',');
        s.push_str(&json_quote("name")); s.push(':'); s.push_str(&json_quote(&n.name)); s.push(',');
        s.push_str(&json_quote("role")); s.push(':'); s.push_str(&json_quote(&n.role)); s.push(',');
        s.push_str(&json_quote("delay")); s.push(':'); s.push_str(&n.delay.to_string()); s.push(',');
        s.push_str(&json_quote("location")); s.push(':'); s.push_str(&json_quote(&n.location));
        s.push('}'); s
    }).collect();
    let segs_parts: Vec<String> = plan.segments.iter().map(|s| {
        let mut r = String::from("{");
        r.push_str(&json_quote("type")); r.push(':'); r.push_str(&json_quote(&s.seg_type)); r.push(',');
        r.push_str(&json_quote("q")); r.push(':'); r.push_str(&s.q.to_string());
        r.push('}'); r
    }).collect();
    let mut out = String::from("{");
    out.push_str(&json_quote("v")); out.push(':'); out.push_str(&plan.v.to_string()); out.push(',');
    out.push_str(&json_quote("title")); out.push(':'); out.push_str(&json_quote(&plan.title)); out.push(',');
    out.push_str(&json_quote("start")); out.push(':'); out.push_str(&json_quote(&plan.start)); out.push(',');
    out.push_str(&json_quote("quantum")); out.push(':'); out.push_str(&plan.quantum.to_string()); out.push(',');
    out.push_str(&json_quote("mode")); out.push(':'); out.push_str(&json_quote(&plan.mode)); out.push(',');
    out.push_str(&json_quote("nodes")); out.push(':'); out.push('['); out.push_str(&nodes_parts.join(",")); out.push(']'); out.push(',');
    out.push_str(&json_quote("segments")); out.push(':'); out.push('['); out.push_str(&segs_parts.join(",")); out.push(']');
    out.push('}'); out
}

fn json_quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"'  );
    for c in s.chars() {
        match c {
            '"'  => out.push_str("\""),
            '\\' => out.push_str("\\"),
            '\n' => out.push_str("\n"),
            '\r' => out.push_str("\r"),
            '\t' => out.push_str("\t"),
            _    => out.push(c),
        }
    }
    out.push('"'  );
    out
}

fn plan_hash_hex(plan: &LtxPlan) -> String {
    let json = plan_to_json(plan);
    let mut h: u32 = 0;
    for b in json.as_bytes() {
        h = h.wrapping_mul(31).wrapping_add(*b as u32);
    }
    format!("{:08x}", h)
}

fn parse_iso_ms(iso: &str) -> i64 {
    if iso.len() < 19 { return 0; }
    let year:  i64 = iso[0..4].parse().unwrap_or(0);
    let month: i64 = iso[5..7].parse().unwrap_or(0);
    let day:   i64 = iso[8..10].parse().unwrap_or(0);
    let hour:  i64 = iso[11..13].parse().unwrap_or(0);
    let min:   i64 = iso[14..16].parse().unwrap_or(0);
    let sec:   i64 = iso[17..19].parse().unwrap_or(0);
    let days = days_from_epoch(year, month, day);
    days * 86_400_000 + hour * 3_600_000 + min * 60_000 + sec * 1_000
}

fn days_from_epoch(y: i64, m: i64, d: i64) -> i64 {
    let (y, m) = if m <= 2 { (y - 1, m + 9) } else { (y, m - 3) };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * m + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn format_date_yyyymmdd(epoch_ms: i64) -> String {
    let days = epoch_ms.div_euclid(86_400_000) + 719_468;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let doe = days - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y   = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp  = (5 * doy + 2) / 153;
    let d   = doy - (153 * mp + 2) / 5 + 1;
    let m   = if mp < 10 { mp + 3 } else { mp - 9 };
    let y2  = if m <= 2 { y + 1 } else { y };
    format!("{:04}{:02}{:02}", y2, m, d)
}

fn ics_fmt(epoch_ms: i64) -> String {
    let secs       = epoch_ms.div_euclid(1000);
    let days_total = secs.div_euclid(86_400);
    let day_secs   = secs.rem_euclid(86_400);
    let h = day_secs / 3600;
    let m = (day_secs % 3600) / 60;
    let s = day_secs % 60;
    let days = days_total + 719_468;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let doe = days - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y   = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp  = (5 * doy + 2) / 153;
    let dd  = doy - (153 * mp + 2) / 5 + 1;
    let mo  = if mp < 10 { mp + 3 } else { mp - 9 };
    let yr  = if mo <= 2 { y + 1 } else { y };
    format!("{:04}{:02}{:02}T{:02}{:02}{:02}Z", yr, mo, dd, h, m, s)
}

fn ics_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    ics_fmt(ms)
}

const B64_CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn b64_encode(data: &[u8]) -> String {
    let mut out = String::new();
    let mut i = 0usize;
    while i < data.len() {
        let b0 = data[i] as u32;
        let b1 = if i+1 < data.len() { data[i+1] as u32 } else { 0u32 };
        let b2 = if i+2 < data.len() { data[i+2] as u32 } else { 0u32 };
        out.push(B64_CHARS[((b0 >> 2) & 63) as usize] as char);
        out.push(B64_CHARS[(((b0 & 3) << 4) | (b1 >> 4)) as usize] as char);
        if i+1 < data.len() {
            out.push(B64_CHARS[(((b1 & 15) << 2) | (b2 >> 6)) as usize] as char);
        } else { out.push('='); }
        if i+2 < data.len() {
            out.push(B64_CHARS[(b2 & 63) as usize] as char);
        } else { out.push('='); }
        i += 3;
    }
    out
}

fn b64url_encode(data: &[u8]) -> String {
    let std_b64 = b64_encode(data);
    let mut out = String::with_capacity(std_b64.len());
    for c in std_b64.chars() {
        match c {
            '+' => out.push('-'),
            '/' => out.push('_'),
            '=' => {},
            _   => out.push(c),
        }
    }
    out
}

fn b64_decode(s: &str) -> Option<Vec<u8>> {
    let sentinel: u8 = 255;
    let mut table = [sentinel; 256];
    for (i, &c) in B64_CHARS.iter().enumerate() { table[c as usize] = i as u8; }
    let mut out = Vec::new();
    let bytes: Vec<u8> = s.bytes().filter(|&b| b != b'=').collect();
    let mut i = 0usize;
    while i + 1 < bytes.len() {
        let v0 = table[bytes[i] as usize];
        let v1 = table[bytes[i+1] as usize];
        if v0 == sentinel || v1 == sentinel { return None; }
        out.push((v0 << 2) | (v1 >> 4));
        if i+2 < bytes.len() {
            let v2 = table[bytes[i+2] as usize];
            if v2 == sentinel { return None; }
            out.push(((v1 & 15) << 4) | (v2 >> 2));
            if i+3 < bytes.len() {
                let v3 = table[bytes[i+3] as usize];
                if v3 == sentinel { return None; }
                out.push(((v2 & 3) << 6) | v3);
            }
        }
        i += 4;
    }
    Some(out)
}

fn b64url_decode(s: &str) -> Option<Vec<u8>> {
    let mut t = String::with_capacity(s.len() + 4);
    for c in s.chars() {
        match c {
            '-' => t.push('+'),
            '_' => t.push('/'),
            _   => t.push(c),
        }
    }
    let pad = (4 - t.len() % 4) % 4;
    for _ in 0..pad { t.push('='); }
    b64_decode(&t)
}

fn json_str_field(json: &str, key: &str) -> Option<String> {
    let needle = format!("\"{}\"", key);
    let pos = json.find(&needle)?;
    let after_key = &json[pos + needle.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos+1..].trim_start();
    if after_colon.starts_with('"') { parse_json_string(after_colon) } else { None }
}

fn json_int_field(json: &str, key: &str) -> Option<i32> {
    let needle = format!("\"{}\"", key);
    let pos = json.find(&needle)?;
    let after_key = &json[pos + needle.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos+1..].trim_start();
    let end = after_colon.find(|c: char| !c.is_ascii_digit() && c != '-').unwrap_or(after_colon.len());
    after_colon[..end].parse().ok()
}

fn json_array_field(json: &str, key: &str) -> Option<Vec<String>> {
    let needle = format!("\"{}\"", key);
    let pos = json.find(&needle)?;
    let after_key = &json[pos + needle.len()..];
    let colon_pos = after_key.find(':')?;
    let after_colon = after_key[colon_pos+1..].trim_start();
    if !after_colon.starts_with('[') { return None; }
    let arr_content = extract_balanced(after_colon, '[', ']')? ;
    Some(extract_objects(arr_content))
}

fn parse_json_string(s: &str) -> Option<String> {
    if !s.starts_with('"') { return None; }
    let mut out = String::new();
    let mut chars = s[1..].chars();
    loop {
        match chars.next()? {
            '"' => return Some(out),
            '\\' => {
                match chars.next()? {
                    '"' => out.push('"'),
                    '\\' => out.push('\\'),
                    'n'  => out.push('\n'),
                    'r'  => out.push('\r'),
                    't'  => out.push('\t'),
                    c    => { out.push('\\'); out.push(c); }
                }
            }
            c => out.push(c),
        }
    }
}

fn extract_balanced(s: &str, open: char, close: char) -> Option<&str> {
    if !s.starts_with(open) { return None; }
    let mut depth = 0i32;
    let mut in_str = false;
    let mut escape = false;
    for (i, c) in s.char_indices() {
        if escape { escape = false; continue; }
        if in_str {
            if c == '\\' { escape = true; }
            else if c == '"' { in_str = false; }
            continue;
        }
        if c == '"' { in_str = true; continue; }
        if c == open  { depth += 1; }
        if c == close { depth -= 1; if depth == 0 { return Some(&s[..=i]); } }
    }
    None
}

fn extract_objects(arr: &str) -> Vec<String> {
    let inner = if arr.len() >= 2 { &arr[1..arr.len()-1] } else { "" };
    let mut objects = Vec::new();
    let mut i = 0usize;
    let bytes = inner.as_bytes();
    while i < bytes.len() {
        let b = bytes[i];
        if b == b' ' || b == b'\n' || b == b'\r' || b == b'\t' || b == b',' {
            i += 1; continue;
        }
        if b == b'{' {
            if let Some(obj) = extract_balanced(&inner[i..], '{', '}') {
                let len = obj.len();
                objects.push(obj.to_string());
                i += len; continue;
            }
        }
        i += 1;
    }
    objects
}

fn url_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9'
            | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => { out.push('%'); out.push_str(&format!("{:02X}", b)); }
        }
    }
    out
}

struct ParsedUrl { host: String, port: u16, path: String }

fn parse_url(url: &str) -> Result<ParsedUrl, String> {
    let s = match url.strip_prefix("http://") {
        Some(v) => v,
        None => return Err(format!("Unsupported: {}", url)),
    };
    let (hp, path) = match s.find('/') {
        Some(i) => (&s[..i], &s[i..]),
        None    => (s, "/"),
    };
    match hp.find(':') {
        Some(i) => {
            let p: u16 = hp[i+1..].parse().unwrap_or(80);
            Ok(ParsedUrl { host: hp[..i].to_string(), port: p, path: path.to_string() })
        }
        None => Ok(ParsedUrl { host: hp.to_string(), port: 80, path: path.to_string() }),
    }
}

fn http_post(url: &str, body: &str) -> Result<String, String> {
    if url.starts_with("https://") {
        return Err("HTTPS requires TLS feature".into());
    }
    use std::io::{Read, Write};
    use std::net::TcpStream;
    let pu = parse_url(url)?;
    let mut stream = TcpStream::connect(format!("{}:{}", pu.host, pu.port))
        .map_err(|e| e.to_string())?;
    let req = format!(
        "POST {} HTTP/1.0\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        pu.path, pu.host, body.len(), body
    );
    stream.write_all(req.as_bytes()).map_err(|e| e.to_string())?;
    let mut resp = String::new();
    stream.read_to_string(&mut resp).map_err(|e| e.to_string())?;
    Ok(extract_body(&resp))
}

fn http_get(url: &str) -> Result<String, String> {
    if url.starts_with("https://") {
        return Err("HTTPS requires TLS feature".into());
    }
    use std::io::{Read, Write};
    use std::net::TcpStream;
    let pu = parse_url(url)?;
    let mut stream = TcpStream::connect(format!("{}:{}", pu.host, pu.port))
        .map_err(|e| e.to_string())?;
    let req = format!(
        "GET {} HTTP/1.0\r\nHost: {}\r\nConnection: close\r\n\r\n",
        pu.path, pu.host
    );
    stream.write_all(req.as_bytes()).map_err(|e| e.to_string())?;
    let mut resp = String::new();
    stream.read_to_string(&mut resp).map_err(|e| e.to_string())?;
    Ok(extract_body(&resp))
}

fn extract_body(resp: &str) -> String {
    if let Some(pos) = resp.find("\r\n\r\n") {
        resp[pos+4..].to_string()
    } else if let Some(pos) = resp.find("

") {
        resp[pos+2..].to_string()
    } else {
        resp.to_string()
    }
}


// ════════════════════════════════════════════════════════════════════════
// Security: Epic 29 (stories 29.1, 29.4, 29.5)
// ════════════════════════════════════════════════════════════════════════

use std::collections::{BTreeMap, HashMap};
use ed25519_dalek::{SigningKey, VerifyingKey, Signer, Verifier, Signature};
use sha2::{Sha256, Digest};
use rand::rngs::OsRng;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};

/// A minimal JSON value type for canonical (sorted-key) serialisation.
#[derive(Debug, Clone, PartialEq)]
pub enum CjsonVal {
    Null,
    Bool(bool),
    Int(i64),
    Str(String),
    Array(Vec<CjsonVal>),
    Object(BTreeMap<String, CjsonVal>),
}

impl CjsonVal {
    pub fn serialize(&self) -> String {
        match self {
            CjsonVal::Null      => "null".to_string(),
            CjsonVal::Bool(b)   => if *b { "true" } else { "false" }.to_string(),
            CjsonVal::Int(n)    => n.to_string(),
            CjsonVal::Str(s)    => cjson_quote_str(s),
            CjsonVal::Array(a)  => {
                let parts: Vec<String> = a.iter().map(|v| v.serialize()).collect();
                format!("[{}]", parts.join(","))
            }
            CjsonVal::Object(m) => {
                // BTreeMap iterates keys in sorted order
                let parts: Vec<String> = m.iter()
                    .map(|(k, v)| format!("{}:{}", cjson_quote_str(k), v.serialize()))
                    .collect();
                format!("{{{}}}", parts.join(","))
            }
        }
    }
}

fn cjson_quote_str(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"'  => { o.push('\\'); o.push('"'); }
            '\\' => { o.push('\\'); o.push('\\'); }
            '\n' => { o.push('\\'); o.push('n'); }
            '\r' => { o.push('\\'); o.push('r'); }
            '\t' => { o.push('\\'); o.push('t'); }
            c if (c as u32) < 0x20 => { o.push_str(&format!("\\u{:04x}", c as u32)); }
            c    => o.push(c),
        }
    }
    o.push('"');
    o
}

/// Canonical JSON: object keys sorted lexicographically, arrays preserved.
pub fn canonical_json(v: &CjsonVal) -> String { v.serialize() }

// ── NIK (Node Identity Key) ───────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Nik {
    pub node_id:     String,  // base64url of first 16 bytes of SHA-256(raw pub key)
    pub public_key:  String,  // base64url of raw 32-byte Ed25519 public key
    pub algorithm:   String,
    pub valid_from:  String,
    pub valid_until: String,
    pub key_version: u32,
    pub label:       String,
}

pub struct GenerateNikResult {
    pub nik:             Nik,
    pub private_key_b64: String,  // base64url of raw 32-byte Ed25519 seed
}

/// Generate a new Node Identity Key using Ed25519.
/// valid_days defaults to 365. node_label defaults to "".
pub fn generate_nik(valid_days: Option<u32>, node_label: Option<&str>) -> GenerateNikResult {
    let days = valid_days.unwrap_or(365);
    let label = node_label.unwrap_or("").to_string();
    let signing_key = SigningKey::generate(&mut OsRng);
    let raw_pub: [u8; 32] = signing_key.verifying_key().to_bytes();
    let raw_seed: [u8; 32] = signing_key.to_bytes();
    let hash = Sha256::digest(&raw_pub);
    let node_id        = URL_SAFE_NO_PAD.encode(&hash[..16]);
    let public_key     = URL_SAFE_NO_PAD.encode(&raw_pub);
    let private_key_b64 = URL_SAFE_NO_PAD.encode(&raw_seed);
    let now = nik_now_ms();
    GenerateNikResult {
        nik: Nik {
            node_id, public_key, algorithm: "Ed25519".into(),
            valid_from:  ms_to_iso(now),
            valid_until: ms_to_iso(now + days as i64 * 86_400_000),
            key_version: 1, label,
        },
        private_key_b64,
    }
}

/// Returns true if the NIK valid_until is in the past.
pub fn is_nik_expired(nik: &Nik) -> bool {
    nik_now_ms() > parse_iso_ms(&nik.valid_until)
}

/// Returns the SHA-256 hex fingerprint of the NIK public key.
pub fn nik_fingerprint(nik: &Nik) -> String {
    let raw = URL_SAFE_NO_PAD.decode(&nik.public_key).unwrap_or_default();
    let hash = Sha256::digest(&raw);
    hash.iter().map(|b| format!("{:02x}", b)).collect()
}

// ── CoseSign1 / SignedPlan / VerifyResult ─────────────────────────────────

#[derive(Debug, Clone)]
pub struct CoseSign1Env {
    pub protected:   String,
    pub unprotected: HashMap<String, String>,
    pub payload:     String,
    pub signature:   String,
}

#[derive(Debug, Clone)]
pub struct SignedPlan {
    pub plan:       CjsonVal,
    pub cose_sign1: CoseSign1Env,
}

#[derive(Debug, Clone)]
pub struct VerifyResult {
    pub valid:  bool,
    pub reason: String,
}

/// Sign an LTX session plan using a COSE_Sign1-compatible structure.
/// private_key_b64 is the base64url-encoded raw 32-byte Ed25519 seed.
pub fn sign_plan(plan: CjsonVal, private_key_b64: &str) -> Result<SignedPlan, String> {
    let seed_bytes = URL_SAFE_NO_PAD.decode(private_key_b64)
        .map_err(|e| format!("base64 decode: {}", e))?;
    if seed_bytes.len() != 32 {
        return Err(format!("invalid key length: {}", seed_bytes.len()));
    }
    let seed: [u8; 32] = seed_bytes.try_into().unwrap();
    let signing_key = SigningKey::from_bytes(&seed);
    let raw_pub: [u8; 32] = signing_key.verifying_key().to_bytes();

    // Protected header: canonical JSON of {"alg": -19}
    let mut phdr = BTreeMap::new();
    phdr.insert("alg".to_string(), CjsonVal::Int(-19));
    let protected_str = canonical_json(&CjsonVal::Object(phdr));
    let protected_b64 = URL_SAFE_NO_PAD.encode(protected_str.as_bytes());

    // Payload: canonical JSON of plan
    let payload_str  = canonical_json(&plan);
    let payload_b64  = URL_SAFE_NO_PAD.encode(payload_str.as_bytes());

    // Sig_Structure: canonical JSON of the array
    let sig_struct = canonical_json(&CjsonVal::Array(vec![
        CjsonVal::Str("Signature1".into()),
        CjsonVal::Str(protected_b64.clone()),
        CjsonVal::Str(String::new()),
        CjsonVal::Str(payload_b64.clone()),
    ]));

    let sig: Signature = signing_key.sign(sig_struct.as_bytes());
    let sig_b64 = URL_SAFE_NO_PAD.encode(sig.to_bytes());

    // kid = base64url of first 16 bytes of SHA-256(raw pub key)
    let kid_hash = Sha256::digest(&raw_pub);
    let kid = URL_SAFE_NO_PAD.encode(&kid_hash[..16]);
    let mut unprotected = HashMap::new();
    unprotected.insert("kid".to_string(), kid);

    Ok(SignedPlan {
        plan,
        cose_sign1: CoseSign1Env {
            protected: protected_b64, unprotected,
            payload: payload_b64, signature: sig_b64,
        },
    })
}

/// Verify a COSE_Sign1-signed session plan envelope.
/// key_cache maps node_id to Nik.
pub fn verify_plan(sp: &SignedPlan, key_cache: &HashMap<String, Nik>) -> VerifyResult {
    let cose = &sp.cose_sign1;
    let kid = match cose.unprotected.get("kid") {
        Some(k) => k.as_str(),
        None    => return VerifyResult { valid: false, reason: "missing_kid".into() },
    };
    let nik = match key_cache.get(kid) {
        Some(n) => n,
        None    => return VerifyResult { valid: false, reason: "key_not_in_cache".into() },
    };
    if is_nik_expired(nik) {
        return VerifyResult { valid: false, reason: "key_expired".into() };
    }

    let sig_struct = canonical_json(&CjsonVal::Array(vec![
        CjsonVal::Str("Signature1".into()),
        CjsonVal::Str(cose.protected.clone()),
        CjsonVal::Str(String::new()),
        CjsonVal::Str(cose.payload.clone()),
    ]));

    let raw_pub = match URL_SAFE_NO_PAD.decode(&nik.public_key) {
        Ok(v) if v.len() == 32 => v,
        _ => return VerifyResult { valid: false, reason: "invalid_public_key".into() },
    };
    let pub_arr: [u8; 32] = raw_pub.try_into().unwrap();
    let verifying_key = match VerifyingKey::from_bytes(&pub_arr) {
        Ok(k) => k,
        Err(_) => return VerifyResult { valid: false, reason: "invalid_public_key".into() },
    };
    let sig_bytes = match URL_SAFE_NO_PAD.decode(&cose.signature) {
        Ok(v) if v.len() == 64 => v,
        _ => return VerifyResult { valid: false, reason: "invalid_signature".into() },
    };
    let sig_arr: [u8; 64] = sig_bytes.try_into().unwrap();
    let signature = Signature::from_bytes(&sig_arr);
    if verifying_key.verify(sig_struct.as_bytes(), &signature).is_err() {
        return VerifyResult { valid: false, reason: "signature_invalid".into() };
    }
    let payload_decoded = match URL_SAFE_NO_PAD.decode(&cose.payload) {
        Ok(v) => String::from_utf8(v).unwrap_or_default(),
        Err(_) => return VerifyResult { valid: false, reason: "payload_decode_error".into() },
    };
    if payload_decoded != canonical_json(&sp.plan) {
        return VerifyResult { valid: false, reason: "payload_mismatch".into() };
    }
    VerifyResult { valid: true, reason: String::new() }
}

// ── Sequence Tracker ──────────────────────────────────────────────────────

pub struct SequenceTracker {
    pub plan_id: String,
    out_seq:     HashMap<String, i64>,
    in_seq:      HashMap<String, i64>,
}

#[derive(Debug, Clone)]
pub struct SeqCheckResult {
    pub accepted: bool,
    pub reason:   String,
    pub gap:      bool,
    pub gap_size: i64,
}

/// Create a new SequenceTracker for the given plan_id.
pub fn create_sequence_tracker(plan_id: &str) -> SequenceTracker {
    SequenceTracker {
        plan_id: plan_id.into(),
        out_seq: HashMap::new(),
        in_seq:  HashMap::new(),
    }
}

impl SequenceTracker {
    /// Return and increment the outbound sequence number for node_id.
    pub fn next_seq(&mut self, node_id: &str) -> i64 {
        let cur = self.out_seq.entry(node_id.to_string()).or_insert(0);
        *cur += 1;
        *cur
    }
    /// Record an inbound sequence number; return acceptance result.
    pub fn record_seq(&mut self, node_id: &str, seq: i64) -> SeqCheckResult {
        let last = *self.in_seq.get(node_id).unwrap_or(&0);
        if seq <= last {
            return SeqCheckResult { accepted: false, reason: "replay".into(), gap: false, gap_size: 0 };
        }
        let gap = seq > last + 1;
        let gs = if gap { seq - last - 1 } else { 0 };
        self.in_seq.insert(node_id.to_string(), seq);
        SeqCheckResult { accepted: true, reason: String::new(), gap, gap_size: gs }
    }
}

/// Stamp a bundle with the next outbound sequence number for node_id.
pub fn add_seq(bundle: &CjsonVal, tracker: &mut SequenceTracker, node_id: &str) -> CjsonVal {
    let seq = tracker.next_seq(node_id);
    let mut map = match bundle {
        CjsonVal::Object(m) => m.clone(),
        _ => BTreeMap::new(),
    };
    map.insert("seq".to_string(), CjsonVal::Int(seq));
    CjsonVal::Object(map)
}

/// Check an inbound bundle seq field against the tracker.
pub fn check_seq(bundle: &CjsonVal, tracker: &mut SequenceTracker, sender: &str) -> SeqCheckResult {
    let seq = match bundle {
        CjsonVal::Object(m) => match m.get("seq") {
            Some(CjsonVal::Int(n)) => *n,
            _ => return SeqCheckResult { accepted: false, reason: "missing_seq".into(), gap: false, gap_size: 0 },
        },
        _ => return SeqCheckResult { accepted: false, reason: "missing_seq".into(), gap: false, gap_size: 0 },
    };
    tracker.record_seq(sender, seq)
}

// ── Timestamp helpers ─────────────────────────────────────────────────────

fn nik_now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now().duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64).unwrap_or(0)
}

fn ms_to_iso(ms: i64) -> String {
    let secs = ms.div_euclid(1000);
    let days_total = secs.div_euclid(86_400);
    let day_secs = secs.rem_euclid(86_400);
    let (h, m, s) = (day_secs / 3600, (day_secs % 3600) / 60, day_secs % 60);
    let days = days_total + 719_468;
    let era = if days >= 0 { days } else { days - 146_096 } / 146_097;
    let doe = days - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let dd = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let yr = if mo <= 2 { y + 1 } else { y };
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", yr, mo, dd, h, m, s)
}
