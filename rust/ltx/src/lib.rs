// interplanet_ltx -- pure-Rust LTX SDK, no external dependencies
// Story 33.8 -- Rust 1.70+

pub const VERSION: &str = "1.1.0";
/// Default quantum size in minutes (LTX-SPECIFICATION.md §3.2).
pub const DEFAULT_QUANTUM: i32 = 5;
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
    /// Presenting node id for attributed TX segments (v3, LTX-SPECIFICATION.md §3.4.1).
    pub speaker: Option<String>,
    /// Agenda label for this segment (v3, LTX-SPECIFICATION.md §3.4.1).
    pub label: Option<String>,
}

impl LtxSegmentTemplate {
    pub fn new(seg_type: &str, q: i32) -> Self {
        LtxSegmentTemplate { seg_type: seg_type.into(), q, speaker: None, label: None }
    }
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
    /// v3 pair-wise one-way delays in seconds, keyed "A|B" with A < B (§4.4).
    /// MUST be None on v2 plans — the frozen v2 planId hash is order-sensitive.
    pub delays: Option<std::collections::BTreeMap<String, i64>>,
    /// v3 amendment counter; 1 for a root plan (LTX-SPECIFICATION.md §6.4).
    pub plan_version: Option<i32>,
    /// v3 SHA-256 hex of canonical JSON of the predecessor plan (§6.4).
    pub prev_plan_hash: Option<String>,
}

pub fn default_segments() -> Vec<LtxSegmentTemplate> {
    vec![
        LtxSegmentTemplate::new("PLAN_CONFIRM", 2),
        LtxSegmentTemplate::new("TX", 2),
        LtxSegmentTemplate::new("RX", 2),
        LtxSegmentTemplate::new("CAUCUS", 2),
        LtxSegmentTemplate::new("TX", 2),
        LtxSegmentTemplate::new("RX", 2),
        LtxSegmentTemplate::new("BUFFER", 1),
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
        delays: None,
        plan_version: None,
        prev_plan_hash: None,
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
            speaker:  json_str_field(&obj, "speaker"),
            label:    json_str_field(&obj, "label"),
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

/// Compute the deterministic plan ID.
///
/// v2 plans use the FROZEN legacy 32-bit polynomial hash over the ordered
/// JSON serialisation (LTX-SPECIFICATION.md §4.3) — kept byte-identical for
/// compatibility. Plans with v >= 3 hash SHA-256 over RFC 8785 canonical
/// JSON, first 8 hex digits, "-v3-" infix (§4.5) so the id spaces stay
/// disjoint.
pub fn make_plan_id(plan: &LtxPlan) -> String {
    let start_ms = parse_iso_ms(&plan.start);
    let date = format_date_yyyymmdd(start_ms);
    let host_str = nodes_host_str(&plan.nodes);
    let node_str = nodes_remote_str(&plan.nodes);
    if plan.v >= 3 {
        let digest = Sha256::digest(canonical_json(&plan_to_cjson(plan)).as_bytes());
        let hex8: String = digest.iter().take(4).map(|b| format!("{:02x}", b)).collect();
        return format!("LTX-{}-{}-{}-v3-{}", date, host_str, node_str, hex8);
    }
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
    parts.join("-").chars().take(16).collect()
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
        speaker:  json_str_field(&obj, "speaker"),
        label:    json_str_field(&obj, "label"),
    }).collect();
    if segments.is_empty() { return None; }
    Some(LtxPlan { v, title, start, quantum, mode, nodes, segments,
                   delays: None, plan_version: None, prev_plan_hash: None })
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
        if let Some(sp) = &s.speaker {
            r.push(','); r.push_str(&json_quote("speaker")); r.push(':'); r.push_str(&json_quote(sp));
        }
        if let Some(lb) = &s.label {
            r.push(','); r.push_str(&json_quote("label")); r.push(':'); r.push_str(&json_quote(lb));
        }
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

// ════════════════════════════════════════════════════════════════════════
// LTX v1.1 core subset (Epic 72, Story 72.2)
// Mirrors typescript/ltx/src: segments.ts, session.ts, amend.ts,
// registers.ts, merkle.ts, cbor.ts, cose.ts.
// ════════════════════════════════════════════════════════════════════════

// ── CjsonVal accessors and JSON parsing ───────────────────────────────────

impl CjsonVal {
    pub fn get(&self, key: &str) -> Option<&CjsonVal> {
        match self { CjsonVal::Object(m) => m.get(key), _ => None }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self { CjsonVal::Str(s) => Some(s), _ => None }
    }
    pub fn as_i64(&self) -> Option<i64> {
        match self { CjsonVal::Int(n) => Some(*n), _ => None }
    }
    pub fn as_bool(&self) -> Option<bool> {
        match self { CjsonVal::Bool(b) => Some(*b), _ => None }
    }
    pub fn as_array(&self) -> Option<&[CjsonVal]> {
        match self { CjsonVal::Array(a) => Some(a), _ => None }
    }
    pub fn as_object(&self) -> Option<&BTreeMap<String, CjsonVal>> {
        match self { CjsonVal::Object(m) => Some(m), _ => None }
    }
}

struct CjsonParser<'a> { bytes: &'a [u8], pos: usize }

impl<'a> CjsonParser<'a> {
    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len()
            && matches!(self.bytes[self.pos], b' ' | b'\t' | b'\n' | b'\r') {
            self.pos += 1;
        }
    }
    fn peek(&self) -> Option<u8> { self.bytes.get(self.pos).copied() }
    fn expect(&mut self, b: u8) -> Result<(), String> {
        if self.peek() == Some(b) { self.pos += 1; Ok(()) }
        else { Err(format!("cjson: expected '{}' at {}", b as char, self.pos)) }
    }
    fn parse_value(&mut self) -> Result<CjsonVal, String> {
        self.skip_ws();
        match self.peek().ok_or("cjson: unexpected end")? {
            b'{' => self.parse_object(),
            b'[' => self.parse_array(),
            b'"' => Ok(CjsonVal::Str(self.parse_string()?)),
            b't' => { self.expect_lit("true")?;  Ok(CjsonVal::Bool(true)) }
            b'f' => { self.expect_lit("false")?; Ok(CjsonVal::Bool(false)) }
            b'n' => { self.expect_lit("null")?;  Ok(CjsonVal::Null) }
            _    => self.parse_number(),
        }
    }
    fn expect_lit(&mut self, lit: &str) -> Result<(), String> {
        if self.bytes[self.pos..].starts_with(lit.as_bytes()) {
            self.pos += lit.len(); Ok(())
        } else { Err(format!("cjson: bad literal at {}", self.pos)) }
    }
    fn parse_object(&mut self) -> Result<CjsonVal, String> {
        self.expect(b'{')?;
        let mut map = BTreeMap::new();
        self.skip_ws();
        if self.peek() == Some(b'}') { self.pos += 1; return Ok(CjsonVal::Object(map)); }
        loop {
            self.skip_ws();
            let key = self.parse_string()?;
            self.skip_ws();
            self.expect(b':')?;
            let val = self.parse_value()?;
            map.insert(key, val);
            self.skip_ws();
            match self.peek() {
                Some(b',') => { self.pos += 1; }
                Some(b'}') => { self.pos += 1; return Ok(CjsonVal::Object(map)); }
                _ => return Err(format!("cjson: expected ',' or '}}' at {}", self.pos)),
            }
        }
    }
    fn parse_array(&mut self) -> Result<CjsonVal, String> {
        self.expect(b'[')?;
        let mut arr = Vec::new();
        self.skip_ws();
        if self.peek() == Some(b']') { self.pos += 1; return Ok(CjsonVal::Array(arr)); }
        loop {
            arr.push(self.parse_value()?);
            self.skip_ws();
            match self.peek() {
                Some(b',') => { self.pos += 1; }
                Some(b']') => { self.pos += 1; return Ok(CjsonVal::Array(arr)); }
                _ => return Err(format!("cjson: expected ',' or ']' at {}", self.pos)),
            }
        }
    }
    fn parse_string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut out = String::new();
        loop {
            let b = self.peek().ok_or("cjson: unterminated string")?;
            self.pos += 1;
            match b {
                b'"'  => return Ok(out),
                b'\\' => {
                    let e = self.peek().ok_or("cjson: bad escape")?;
                    self.pos += 1;
                    match e {
                        b'"'  => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/'  => out.push('/'),
                        b'b'  => out.push('\u{0008}'),
                        b'f'  => out.push('\u{000c}'),
                        b'n'  => out.push('\n'),
                        b'r'  => out.push('\r'),
                        b't'  => out.push('\t'),
                        b'u'  => {
                            let cp = self.parse_hex4()?;
                            if (0xD800..0xDC00).contains(&cp) {
                                // surrogate pair
                                self.expect(b'\\')?;
                                self.expect(b'u')?;
                                let lo = self.parse_hex4()?;
                                let c = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                                out.push(char::from_u32(c as u32).ok_or("cjson: bad surrogate")?);
                            } else {
                                out.push(char::from_u32(cp as u32).ok_or("cjson: bad codepoint")?);
                            }
                        }
                        _ => return Err(format!("cjson: bad escape at {}", self.pos)),
                    }
                }
                _ => {
                    // Re-decode UTF-8 starting at pos-1.
                    let start = self.pos - 1;
                    let s = std::str::from_utf8(&self.bytes[start..])
                        .map_err(|_| "cjson: invalid utf8")?;
                    let c = s.chars().next().ok_or("cjson: unexpected end")?;
                    out.push(c);
                    self.pos = start + c.len_utf8();
                }
            }
        }
    }
    fn parse_hex4(&mut self) -> Result<u32, String> {
        if self.pos + 4 > self.bytes.len() { return Err("cjson: bad \\u".into()); }
        let s = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
            .map_err(|_| "cjson: bad \\u")?;
        let v = u32::from_str_radix(s, 16).map_err(|_| "cjson: bad \\u")?;
        self.pos += 4;
        Ok(v)
    }
    fn parse_number(&mut self) -> Result<CjsonVal, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') { self.pos += 1; }
        while matches!(self.peek(), Some(b'0'..=b'9')) { self.pos += 1; }
        if matches!(self.peek(), Some(b'.') | Some(b'e') | Some(b'E')) {
            return Err("cjson: floats not supported".into());
        }
        let s = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "cjson: bad number")?;
        s.parse::<i64>().map(CjsonVal::Int)
            .map_err(|_| format!("cjson: bad number '{}'", s))
    }
}

/// Parse a JSON document into a CjsonVal (integer-only numbers; floats are
/// rejected — LTX canonical JSON never carries floats).
pub fn cjson_parse(s: &str) -> Result<CjsonVal, String> {
    let mut p = CjsonParser { bytes: s.as_bytes(), pos: 0 };
    let v = p.parse_value()?;
    p.skip_ws();
    if p.pos != p.bytes.len() {
        return Err(format!("cjson: trailing data at {}", p.pos));
    }
    Ok(v)
}

// ── Plan ⇄ CjsonVal conversion ────────────────────────────────────────────

/// Convert a plan struct to a CjsonVal (for canonical JSON / hashing).
pub fn plan_to_cjson(plan: &LtxPlan) -> CjsonVal {
    let mut m = BTreeMap::new();
    m.insert("v".into(), CjsonVal::Int(plan.v as i64));
    m.insert("title".into(), CjsonVal::Str(plan.title.clone()));
    m.insert("start".into(), CjsonVal::Str(plan.start.clone()));
    m.insert("quantum".into(), CjsonVal::Int(plan.quantum as i64));
    m.insert("mode".into(), CjsonVal::Str(plan.mode.clone()));
    m.insert("nodes".into(), CjsonVal::Array(plan.nodes.iter().map(|n| {
        let mut o = BTreeMap::new();
        o.insert("id".into(), CjsonVal::Str(n.id.clone()));
        o.insert("name".into(), CjsonVal::Str(n.name.clone()));
        o.insert("role".into(), CjsonVal::Str(n.role.clone()));
        o.insert("delay".into(), CjsonVal::Int(n.delay as i64));
        o.insert("location".into(), CjsonVal::Str(n.location.clone()));
        CjsonVal::Object(o)
    }).collect()));
    m.insert("segments".into(), CjsonVal::Array(plan.segments.iter().map(|s| {
        let mut o = BTreeMap::new();
        o.insert("type".into(), CjsonVal::Str(s.seg_type.clone()));
        o.insert("q".into(), CjsonVal::Int(s.q as i64));
        if let Some(sp) = &s.speaker { o.insert("speaker".into(), CjsonVal::Str(sp.clone())); }
        if let Some(lb) = &s.label   { o.insert("label".into(),   CjsonVal::Str(lb.clone())); }
        CjsonVal::Object(o)
    }).collect()));
    if let Some(delays) = &plan.delays {
        let mut o = BTreeMap::new();
        for (k, v) in delays { o.insert(k.clone(), CjsonVal::Int(*v)); }
        m.insert("delays".into(), CjsonVal::Object(o));
    }
    if let Some(pv) = plan.plan_version { m.insert("planVersion".into(), CjsonVal::Int(pv as i64)); }
    if let Some(ph) = &plan.prev_plan_hash { m.insert("prevPlanHash".into(), CjsonVal::Str(ph.clone())); }
    CjsonVal::Object(m)
}

/// Build a plan struct from a parsed CjsonVal plan object.
pub fn plan_from_cjson(v: &CjsonVal) -> Result<LtxPlan, String> {
    let obj = v.as_object().ok_or("plan_from_cjson: not an object")?;
    let get_str = |k: &str| obj.get(k).and_then(|x| x.as_str()).map(|s| s.to_string());
    let get_int = |k: &str| obj.get(k).and_then(|x| x.as_i64());
    let nodes = match obj.get("nodes").and_then(|x| x.as_array()) {
        Some(arr) => arr.iter().map(|n| LtxNode {
            id:       n.get("id").and_then(|x| x.as_str()).unwrap_or("N0").into(),
            name:     n.get("name").and_then(|x| x.as_str()).unwrap_or("Unknown").into(),
            role:     n.get("role").and_then(|x| x.as_str()).unwrap_or("HOST").into(),
            delay:    n.get("delay").and_then(|x| x.as_i64()).unwrap_or(0) as i32,
            location: n.get("location").and_then(|x| x.as_str()).unwrap_or("earth").into(),
        }).collect(),
        None => Vec::new(),
    };
    let segments = match obj.get("segments").and_then(|x| x.as_array()) {
        Some(arr) => arr.iter().map(|s| LtxSegmentTemplate {
            seg_type: s.get("type").and_then(|x| x.as_str()).unwrap_or("TX").into(),
            q:        s.get("q").and_then(|x| x.as_i64()).unwrap_or(2) as i32,
            speaker:  s.get("speaker").and_then(|x| x.as_str()).map(|x| x.to_string()),
            label:    s.get("label").and_then(|x| x.as_str()).map(|x| x.to_string()),
        }).collect(),
        None => Vec::new(),
    };
    let delays = obj.get("delays").and_then(|x| x.as_object()).map(|m| {
        m.iter().filter_map(|(k, v)| v.as_i64().map(|n| (k.clone(), n))).collect()
    });
    Ok(LtxPlan {
        v:       get_int("v").unwrap_or(2) as i32,
        title:   get_str("title").unwrap_or_else(|| "LTX Session".into()),
        start:   get_str("start").unwrap_or_default(),
        quantum: get_int("quantum").unwrap_or(DEFAULT_QUANTUM as i64) as i32,
        mode:    get_str("mode").unwrap_or_else(|| "LTX".into()),
        nodes, segments, delays,
        plan_version:   get_int("planVersion").map(|n| n as i32),
        prev_plan_hash: get_str("prevPlanHash"),
    })
}

// ── Feature 1: pair delays and viewer-perspective segments (§3.7, §14.3) ──

/// One-way delay in seconds between two nodes (LTX-SPECIFICATION.md §3.7).
/// The v3 pair matrix is authoritative where present; otherwise the
/// conservative fallback: HOST pairs use the node's declared delay, non-HOST
/// pairs the sum of both HOST-relative delays.
pub fn pair_delay(plan: &LtxPlan, node_id_a: &str, node_id_b: &str) -> Result<i64, String> {
    if node_id_a == node_id_b { return Ok(0); }
    if let Some(delays) = &plan.delays {
        let mut pair = [node_id_a, node_id_b];
        pair.sort();
        if let Some(d) = delays.get(&format!("{}|{}", pair[0], pair[1])) {
            return Ok(*d);
        }
    }
    let a = plan.nodes.iter().find(|n| n.id == node_id_a)
        .ok_or_else(|| format!("pairDelay: unknown node {}", node_id_a))?;
    let b = plan.nodes.iter().find(|n| n.id == node_id_b)
        .ok_or_else(|| format!("pairDelay: unknown node {}", node_id_b))?;
    let host_id = &plan.nodes[0].id;
    if node_id_a == host_id { return Ok(b.delay as i64); }
    if node_id_b == host_id { return Ok(a.delay as i64); }
    Ok(a.delay as i64 + b.delay as i64)
}

/// A computed segment from a specific viewer's perspective (§14.3).
#[derive(Debug, Clone)]
pub struct LtxViewerSegment {
    pub seg_type: String,
    pub q: i32,
    pub start_ms: i64,
    pub end_ms: i64,
    pub dur_min: i32,
    pub speaker: Option<String>,
    pub label: Option<String>,
    /// "transmit" (viewer presents), "receive" (arrives after light-time), "neutral".
    pub perspective: &'static str,
    /// Light-time shift applied to start/end, in seconds (0 unless receiving).
    pub arrival_offset_s: i64,
}

/// Compute the timed segment array from viewer V's perspective (§14.3):
/// a segment attributed to speaker S starts for V at
/// seg_start + pair_delay(S, V). Unattributed segments keep their times.
pub fn compute_segments_for(plan: &LtxPlan, viewer_node_id: &str)
    -> Result<Vec<LtxViewerSegment>, String>
{
    if !plan.nodes.iter().any(|n| n.id == viewer_node_id) {
        return Err(format!("computeSegmentsFor: unknown viewer {}", viewer_node_id));
    }
    let base = compute_segments(plan)?;
    let mut out = Vec::with_capacity(base.len());
    for (i, seg) in base.iter().enumerate() {
        let tpl = &plan.segments[i];
        let mut vs = LtxViewerSegment {
            seg_type: seg.seg_type.clone(), q: seg.q,
            start_ms: seg.start_ms, end_ms: seg.end_ms, dur_min: seg.dur_min,
            speaker: tpl.speaker.clone(), label: tpl.label.clone(),
            perspective: "neutral", arrival_offset_s: 0,
        };
        if let Some(speaker) = &tpl.speaker {
            if tpl.seg_type == "TX" || tpl.seg_type == "SPEAK" {
                if speaker == viewer_node_id {
                    vs.perspective = "transmit";
                } else {
                    let shift_s = pair_delay(plan, speaker, viewer_node_id)?;
                    vs.perspective = "receive";
                    vs.arrival_offset_s = shift_s;
                    vs.start_ms += shift_s * 1000;
                    vs.end_ms += shift_s * 1000;
                }
            }
        }
        out.push(vs);
    }
    Ok(out)
}

// ── Feature 2: session state machine (LTX-SPECIFICATION.md §5) ────────────

/// Session lifecycle phase for the v1.1 state machine (§5).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionPhase {
    Draft, Locking, Locked, Active, Degraded, EmergencyHold, Complete, Aborted,
}

impl SessionPhase {
    pub fn as_str(&self) -> &'static str {
        match self {
            SessionPhase::Draft         => "DRAFT",
            SessionPhase::Locking       => "LOCKING",
            SessionPhase::Locked        => "LOCKED",
            SessionPhase::Active        => "ACTIVE",
            SessionPhase::Degraded      => "DEGRADED",
            SessionPhase::EmergencyHold => "EMERGENCY_HOLD",
            SessionPhase::Complete      => "COMPLETE",
            SessionPhase::Aborted       => "ABORTED",
        }
    }
}

/// Plan-lock kind (§5.2/§5.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockKind { Full, Quorum }

impl LockKind {
    pub fn as_str(&self) -> &'static str {
        match self { LockKind::Full => "FULL", LockKind::Quorum => "QUORUM" }
    }
}

/// Time-injected session event: every variant carries now_ms so transition()
/// never reads a clock and stays pure.
#[derive(Debug, Clone)]
pub enum SessionEvent {
    StartLock { now_ms: i64 },
    PlanConfirm { now_ms: i64, node_id: String, plan_id: String },
    Tick { now_ms: i64 },
    SessionStart { now_ms: i64 },
    DelayMeasured { now_ms: i64, node_id: String, measured_delay_s: f64 },
    EokOverride { now_ms: i64, verified: bool, reason: Option<String> },
    AmendmentProposed { now_ms: i64, plan_id: String, plan_version: i32, affected_node_ids: Vec<String> },
    AmendmentConfirmed { now_ms: i64, node_id: String, plan_id: String },
    HostDecision { now_ms: i64, decision: String },
    SessionEnd { now_ms: i64 },
}

impl SessionEvent {
    pub fn name(&self) -> &'static str {
        match self {
            SessionEvent::StartLock { .. }          => "START_LOCK",
            SessionEvent::PlanConfirm { .. }        => "PLAN_CONFIRM",
            SessionEvent::Tick { .. }               => "TICK",
            SessionEvent::SessionStart { .. }       => "SESSION_START",
            SessionEvent::DelayMeasured { .. }      => "DELAY_MEASURED",
            SessionEvent::EokOverride { .. }        => "EOK_OVERRIDE",
            SessionEvent::AmendmentProposed { .. }  => "AMENDMENT_PROPOSED",
            SessionEvent::AmendmentConfirmed { .. } => "AMENDMENT_CONFIRMED",
            SessionEvent::HostDecision { .. }       => "HOST_DECISION",
            SessionEvent::SessionEnd { .. }         => "SESSION_END",
        }
    }
    pub fn now_ms(&self) -> i64 {
        match self {
            SessionEvent::StartLock { now_ms }
            | SessionEvent::PlanConfirm { now_ms, .. }
            | SessionEvent::Tick { now_ms }
            | SessionEvent::SessionStart { now_ms }
            | SessionEvent::DelayMeasured { now_ms, .. }
            | SessionEvent::EokOverride { now_ms, .. }
            | SessionEvent::AmendmentProposed { now_ms, .. }
            | SessionEvent::AmendmentConfirmed { now_ms, .. }
            | SessionEvent::HostDecision { now_ms, .. }
            | SessionEvent::SessionEnd { now_ms } => *now_ms,
        }
    }
}

/// Side-effect command returned by transition(); the caller executes it.
#[derive(Debug, Clone)]
pub enum SessionEffect {
    /// Audit-log payload for a state change (LTX-SECURITY.md §9.6).
    Audit { from: SessionPhase, to: SessionPhase, event: String, at_ms: i64, detail: String },
    Notify { level: String, code: String, detail: String },
    Escalate { code: String, detail: String },
}

/// Quorum threshold option for quorum lock (§5.6).
#[derive(Debug, Clone, Copy)]
pub enum QuorumOption { All, Majority, Count(usize) }

#[derive(Debug, Clone)]
pub struct PendingAmendment {
    pub plan_id: String,
    pub plan_version: i32,
    pub affected_node_ids: Vec<String>,
    pub confirmed: Vec<String>,
    pub proposed_at_ms: i64,
    pub timeout_ms: i64,
}

#[derive(Debug, Clone)]
pub struct SessionContext {
    pub state: SessionPhase,
    pub plan: LtxPlan,
    pub plan_id: String,
    /// planId of the first (unamended) plan — freshness scope key (§11).
    pub session_root_plan_id: String,
    pub plan_version: i32,
    pub lock: Option<LockKind>,
    pub lock_started_at_ms: Option<i64>,
    pub lock_timeout_ms: i64,
    /// node_id → plan_id confirmed by that node.
    pub confirmations: HashMap<String, String>,
    /// node_ids that confirmed a planId different from ours (§5.5).
    pub mismatched: Vec<String>,
    pub quorum_threshold: usize,
    /// Participating subset when quorum-locked (§5.3); None = all nodes.
    pub subset: Option<Vec<String>>,
    pub degraded_reasons: Vec<String>,
    /// Phase to return to when leaving EMERGENCY_HOLD via HOST 'resume'.
    pub resume_state: Option<SessionPhase>,
    pub pending_amendment: Option<PendingAmendment>,
}

fn session_participants(plan: &LtxPlan) -> Vec<&LtxNode> {
    plan.nodes.iter().filter(|n| n.role == "PARTICIPANT").collect()
}

/// 2 × one-way delay to the furthest node, in ms (§5.1).
pub fn lock_timeout_ms(plan: &LtxPlan) -> i64 {
    let max_delay_s = plan.nodes.iter().map(|n| n.delay.max(0) as i64).max().unwrap_or(0);
    DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR as i64 * max_delay_s * 1000
}

fn quorum_count(plan: &LtxPlan, quorum: QuorumOption) -> usize {
    let total = session_participants(plan).len();
    match quorum {
        QuorumOption::Majority => total / 2 + 1,
        QuorumOption::Count(n) => n.max(1).min(total),
        QuorumOption::All      => total,
    }
}

/// Create a session context in DRAFT state. plan_id is supplied by the
/// caller (make_plan_id) so this module stays pure.
pub fn create_session(plan: &LtxPlan, plan_id: &str, quorum: QuorumOption) -> SessionContext {
    SessionContext {
        state: SessionPhase::Draft,
        plan: plan.clone(),
        plan_id: plan_id.to_string(),
        session_root_plan_id: plan_id.to_string(),
        plan_version: plan.plan_version.unwrap_or(1),
        lock: None,
        lock_started_at_ms: None,
        lock_timeout_ms: lock_timeout_ms(plan),
        confirmations: HashMap::new(),
        mismatched: Vec::new(),
        quorum_threshold: quorum_count(plan, quorum),
        subset: None,
        degraded_reasons: Vec::new(),
        resume_state: None,
        pending_amendment: None,
    }
}

/// Ascending-delay fallback ordering over confirmed participants (§5.3).
fn confirmed_subset(ctx: &SessionContext) -> Vec<String> {
    let mut confirmed: Vec<&LtxNode> = session_participants(&ctx.plan)
        .into_iter()
        .filter(|n| ctx.confirmations.get(&n.id) == Some(&ctx.plan_id))
        .collect();
    confirmed.sort_by_key(|n| n.delay);
    let mut out = vec![ctx.plan.nodes[0].id.clone()];
    out.extend(confirmed.into_iter().map(|n| n.id.clone()));
    out
}

fn full_lock_reached(ctx: &SessionContext) -> bool {
    session_participants(&ctx.plan).iter()
        .all(|n| ctx.confirmations.get(&n.id) == Some(&ctx.plan_id))
}

fn quorum_reached(ctx: &SessionContext) -> bool {
    let confirmed = session_participants(&ctx.plan).iter()
        .filter(|n| ctx.confirmations.get(&n.id) == Some(&ctx.plan_id))
        .count();
    confirmed >= ctx.quorum_threshold
}

/// Declared one-way delay: v3 pair matrix HOST row, else node delay.
fn declared_delay_s(plan: &LtxPlan, node_id: &str) -> Option<i64> {
    let node = plan.nodes.iter().find(|n| n.id == node_id)?;
    if let Some(delays) = &plan.delays {
        let mut pair = [plan.nodes[0].id.as_str(), node_id];
        pair.sort();
        if let Some(d) = delays.get(&format!("{}|{}", pair[0], pair[1])) {
            return Some(*d);
        }
    }
    Some(node.delay as i64)
}

fn fx_invalid(ctx: &SessionContext, event: &SessionEvent) -> SessionEffect {
    SessionEffect::Notify {
        level: "warn".into(), code: "INVALID_EVENT".into(),
        detail: format!("{} ignored in state {}", event.name(), ctx.state.as_str()),
    }
}

fn fx_notify(level: &str, code: &str, detail: String) -> SessionEffect {
    SessionEffect::Notify { level: level.into(), code: code.into(), detail }
}

fn moved(mut ctx: SessionContext, to: SessionPhase, event: &SessionEvent,
         mut effects: Vec<SessionEffect>, detail: String)
    -> (SessionContext, Vec<SessionEffect>)
{
    let audit = SessionEffect::Audit {
        from: ctx.state, to, event: event.name().into(),
        at_ms: event.now_ms(), detail,
    };
    ctx.state = to;
    let mut all = vec![audit];
    all.append(&mut effects);
    (ctx, all)
}

fn degrade(mut ctx: SessionContext, event: &SessionEvent, reason: String)
    -> (SessionContext, Vec<SessionEffect>)
{
    let already = ctx.state == SessionPhase::Degraded;
    ctx.degraded_reasons.push(reason.clone());
    let effects = vec![
        fx_notify("warn", "DEGRADED", reason.clone()),
        SessionEffect::Escalate { code: "DEGRADED".into(), detail: reason.clone() },
    ];
    if already {
        return (ctx, effects[..1].to_vec()); // already degraded: notify only
    }
    moved(ctx, SessionPhase::Degraded, event, effects, reason)
}

/// Advance the session state machine.
/// Pure: same (ctx, event) always yields the same result.
pub fn transition(ctx: &SessionContext, event: &SessionEvent)
    -> (SessionContext, Vec<SessionEffect>)
{
    let ctx = ctx.clone();
    match event {
        SessionEvent::StartLock { now_ms } => {
            if ctx.state != SessionPhase::Draft {
                let fx = fx_invalid(&ctx, event);
                return (ctx, vec![fx]);
            }
            let host_id = ctx.plan.nodes[0].id.clone();
            let plan_id = ctx.plan_id.clone();
            let mut next = ctx;
            next.lock_started_at_ms = Some(*now_ms);
            next.confirmations.insert(host_id, plan_id);
            moved(next, SessionPhase::Locking, event, vec![], String::new())
        }

        SessionEvent::PlanConfirm { node_id, plan_id, .. } => {
            if ctx.state != SessionPhase::Locking && ctx.state != SessionPhase::Degraded {
                let fx = fx_invalid(&ctx, event);
                return (ctx, vec![fx]);
            }
            let mut next = ctx;
            next.confirmations.insert(node_id.clone(), plan_id.clone());
            if *plan_id != next.plan_id {
                next.mismatched.retain(|id| id != node_id);
                next.mismatched.push(node_id.clone());
                let detail = format!("{} confirmed {}, expected {} (resolve per §5.5)",
                    node_id, plan_id, next.plan_id);
                return (next, vec![fx_notify("warn", "PLANID_MISMATCH", detail)]);
            }
            next.mismatched.retain(|id| id != node_id);
            if full_lock_reached(&next) {
                next.lock = Some(LockKind::Full);
                next.subset = None;
                // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                return moved(next, SessionPhase::Locked, event,
                    vec![fx_notify("info", "LOCKED", "full lock achieved".into())],
                    String::new());
            }
            (next, vec![])
        }

        SessionEvent::Tick { now_ms } => {
            if ctx.state != SessionPhase::Locking { return (ctx, vec![]); }
            let started = match ctx.lock_started_at_ms {
                Some(t) => t, None => return (ctx, vec![]),
            };
            if now_ms - started < ctx.lock_timeout_ms { return (ctx, vec![]); }
            // Lock timeout expired (§5.1).
            if quorum_reached(&ctx) {
                let subset = confirmed_subset(&ctx);
                let missing: Vec<String> = session_participants(&ctx.plan).iter()
                    .filter(|n| ctx.confirmations.get(&n.id) != Some(&ctx.plan_id))
                    .map(|n| n.id.clone())
                    .collect();
                let mut next = ctx;
                next.lock = Some(LockKind::Quorum);
                next.subset = Some(subset.clone());
                let reason = format!("quorum lock with subset [{}]; unconfirmed: [{}]",
                    subset.join(","), missing.join(","));
                return degrade(next, event, reason);
            }
            degrade(ctx, event, "plan-lock timeout without quorum".into())
        }

        SessionEvent::SessionStart { .. } => {
            if ctx.state == SessionPhase::Locked {
                return moved(ctx, SessionPhase::Active, event, vec![], String::new());
            }
            if ctx.state == SessionPhase::Degraded && ctx.lock.is_some() {
                // §5.2: escalation to HOST required before TX.
                return (ctx, vec![SessionEffect::Escalate {
                    code: "DEGRADED_START".into(),
                    detail: "session start requested while DEGRADED; HOST decision required".into(),
                }]);
            }
            let fx = fx_invalid(&ctx, event);
            (ctx, vec![fx])
        }

        SessionEvent::DelayMeasured { node_id, measured_delay_s, .. } => {
            if ctx.state != SessionPhase::Active && ctx.state != SessionPhase::Locked
                && ctx.state != SessionPhase::Degraded {
                return (ctx, vec![]);
            }
            let declared = match declared_delay_s(&ctx.plan, node_id) {
                Some(d) => d,
                None => { let fx = fx_invalid(&ctx, event); return (ctx, vec![fx]); }
            };
            let deviation = (measured_delay_s - declared as f64).abs();
            if deviation > DELAY_VIOLATION_DEGRADED_S as f64 {
                let reason = format!("delay violation {}: measured {}s vs declared {}s (>{}s)",
                    node_id, measured_delay_s, declared, DELAY_VIOLATION_DEGRADED_S);
                return degrade(ctx, event, reason);
            }
            if deviation > DELAY_VIOLATION_WARN_S as f64 {
                let detail = format!("{}: measured {}s vs declared {}s",
                    node_id, measured_delay_s, declared);
                return (ctx, vec![fx_notify("warn", "DELAY_VIOLATION", detail)]);
            }
            (ctx, vec![])
        }

        SessionEvent::EokOverride { verified, reason, .. } => {
            if ctx.state == SessionPhase::Complete || ctx.state == SessionPhase::Aborted {
                return (ctx, vec![]);
            }
            if !verified {
                let detail = reason.clone().unwrap_or_else(|| "override failed verification".into());
                return (ctx, vec![fx_notify("error", "OVERRIDE_REJECTED", detail)]);
            }
            if ctx.state == SessionPhase::EmergencyHold { return (ctx, vec![]); }
            let detail = reason.clone().unwrap_or_else(|| "verified EOK override".into());
            let mut next = ctx;
            next.resume_state = Some(next.state);
            moved(next, SessionPhase::EmergencyHold, event,
                vec![fx_notify("error", "EMERGENCY_HOLD", detail)], String::new())
        }

        SessionEvent::AmendmentProposed { now_ms, plan_id, plan_version, affected_node_ids } => {
            if ctx.state != SessionPhase::Active && ctx.state != SessionPhase::Locked
                && ctx.state != SessionPhase::Degraded {
                let fx = fx_invalid(&ctx, event);
                return (ctx, vec![fx]);
            }
            if *plan_version != ctx.plan_version + 1 {
                let detail = format!("planVersion {} != {} + 1", plan_version, ctx.plan_version);
                return (ctx, vec![fx_notify("error", "AMENDMENT_REJECTED", detail)]);
            }
            // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
            let max_delay_s = ctx.plan.nodes.iter()
                .filter(|n| affected_node_ids.contains(&n.id))
                .map(|n| n.delay.max(0) as i64)
                .max().unwrap_or(0);
            let detail = format!("plan {} v{}; awaiting [{}]",
                plan_id, plan_version, affected_node_ids.join(","));
            let mut next = ctx;
            next.pending_amendment = Some(PendingAmendment {
                plan_id: plan_id.clone(),
                plan_version: *plan_version,
                affected_node_ids: affected_node_ids.clone(),
                confirmed: Vec::new(),
                proposed_at_ms: *now_ms,
                timeout_ms: DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR as i64 * max_delay_s * 1000,
            });
            (next, vec![fx_notify("info", "AMENDMENT_PROPOSED", detail)])
        }

        SessionEvent::AmendmentConfirmed { node_id, plan_id, .. } => {
            let pa_ok = matches!(&ctx.pending_amendment, Some(pa) if pa.plan_id == *plan_id);
            if !pa_ok {
                let fx = fx_invalid(&ctx, event);
                return (ctx, vec![fx]);
            }
            if !ctx.pending_amendment.as_ref().unwrap().affected_node_ids.contains(node_id) {
                return (ctx, vec![]);
            }
            let root_id = ctx.session_root_plan_id.clone();
            let mut next = ctx;
            {
                let pa = next.pending_amendment.as_mut().unwrap();
                pa.confirmed.retain(|id| id != node_id);
                pa.confirmed.push(node_id.clone());
                if pa.confirmed.len() < pa.affected_node_ids.len() {
                    return (next, vec![]);
                }
            }
            // All affected nodes confirmed — the amendment applies. The caller
            // swaps ctx.plan for the verified successor (transition tracks ids).
            let pa = next.pending_amendment.take().unwrap();
            next.plan_id = pa.plan_id.clone();
            next.plan_version = pa.plan_version;
            let detail = format!("plan {} v{} in effect (root {})",
                pa.plan_id, pa.plan_version, root_id);
            (next, vec![fx_notify("info", "AMENDMENT_APPLIED", detail)])
        }

        SessionEvent::HostDecision { decision, .. } => {
            if decision == "abort" {
                if ctx.state == SessionPhase::Complete || ctx.state == SessionPhase::Aborted {
                    return (ctx, vec![]);
                }
                return moved(ctx, SessionPhase::Aborted, event, vec![], String::new());
            }
            if decision == "resume" && ctx.state == SessionPhase::EmergencyHold {
                let back = ctx.resume_state.unwrap_or(SessionPhase::Active);
                let mut next = ctx;
                next.resume_state = None;
                return moved(next, back, event, vec![], String::new());
            }
            if decision == "continue" && ctx.state == SessionPhase::Degraded {
                // §5.2: HOST elects to continue with the confirmed subset.
                let detail = match &ctx.subset {
                    Some(s) => format!("continuing with subset [{}]", s.join(",")),
                    None => "continuing despite degraded condition".into(),
                };
                return moved(ctx, SessionPhase::Active, event,
                    vec![fx_notify("warn", "CONTINUE_DEGRADED", detail)], String::new());
            }
            let fx = fx_invalid(&ctx, event);
            (ctx, vec![fx])
        }

        SessionEvent::SessionEnd { .. } => {
            if ctx.state == SessionPhase::Active || ctx.state == SessionPhase::Degraded {
                return moved(ctx, SessionPhase::Complete, event, vec![], String::new());
            }
            let fx = fx_invalid(&ctx, event);
            (ctx, vec![fx])
        }
    }
}

// ── Feature 3: amendment chains (LTX-SECURITY.md §7.6) ────────────────────

/// SHA-256 hex of the RFC 8785 canonical JSON of a plan. Order-insensitive
/// and collision-resistant — never the legacy v2 polynomial planId hash.
pub fn plan_hash(plan: &CjsonVal) -> String {
    let digest = Sha256::digest(canonical_json(plan).as_bytes());
    digest.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Create a signed amendment of `signed_plan` with `changes` applied.
/// The successor is always a v3 plan (LTX-SPECIFICATION.md §4.4); fields
/// managed here ("v", "planVersion", "prevPlanHash") cannot be overridden.
pub fn create_amendment(signed_plan: &SignedPlan, changes: &BTreeMap<String, CjsonVal>,
                        private_key_b64: &str) -> Result<SignedPlan, String>
{
    let prev = signed_plan.plan.as_object()
        .ok_or("createAmendment: predecessor plan is not an object")?;
    let prev_version = prev.get("planVersion").and_then(|v| v.as_i64()).unwrap_or(1);
    let mut successor = prev.clone();
    for (k, v) in changes { successor.insert(k.clone(), v.clone()); }
    successor.insert("v".into(), CjsonVal::Int(3));
    successor.insert("planVersion".into(), CjsonVal::Int(prev_version + 1));
    successor.insert("prevPlanHash".into(), CjsonVal::Str(plan_hash(&signed_plan.plan)));
    sign_plan(CjsonVal::Object(successor), private_key_b64)
}

/// Verify an amendment chain: chain[0] is the root plan, each later element
/// a successive amendment. Checks, per link: HOST signature against
/// key_cache, planVersion increment of exactly 1, and prevPlanHash equality
/// with the recomputed predecessor hash (LTX-SECURITY.md §7.6).
pub fn verify_amendment_chain(chain: &[SignedPlan], key_cache: &HashMap<String, Nik>)
    -> VerifyResult
{
    if chain.is_empty() {
        return VerifyResult { valid: false, reason: "empty_chain".into() };
    }
    for (i, link) in chain.iter().enumerate() {
        let sig = verify_plan(link, key_cache);
        if !sig.valid {
            return VerifyResult { valid: false, reason: format!("link_{}_{}", i, sig.reason) };
        }
    }
    let root = &chain[0].plan;
    if root.get("prevPlanHash").is_some() {
        return VerifyResult { valid: false, reason: "root_has_prev_hash".into() };
    }
    let mut prev_plan = &chain[0].plan;
    let mut prev_version = root.get("planVersion").and_then(|v| v.as_i64()).unwrap_or(1);
    for (i, link) in chain.iter().enumerate().skip(1) {
        let p = &link.plan;
        if p.get("v").and_then(|v| v.as_i64()) != Some(3) {
            return VerifyResult { valid: false, reason: format!("link_{}_not_v3", i) };
        }
        if p.get("planVersion").and_then(|v| v.as_i64()).unwrap_or(0) != prev_version + 1 {
            return VerifyResult { valid: false, reason: format!("link_{}_version_gap", i) };
        }
        if p.get("prevPlanHash").and_then(|v| v.as_str()) != Some(plan_hash(prev_plan).as_str()) {
            return VerifyResult { valid: false, reason: format!("link_{}_prev_hash_mismatch", i) };
        }
        prev_plan = p;
        prev_version = p.get("planVersion").and_then(|v| v.as_i64()).unwrap_or(0);
    }
    VerifyResult { valid: true, reason: String::new() }
}

// ── Feature 4: registers (LTX-SPECIFICATION.md §8–§10) ────────────────────

/// Signed audit-log entry (LTX-SECURITY.md §9.5 envelope).
#[derive(Debug, Clone)]
pub struct RegisterEntry {
    pub entry_id: String,
    pub session_id: String,
    pub node_id: String,
    pub seq: i64,
    pub entry_type: String,
    pub content: CjsonVal,
    pub timestamp: String,
    pub sig: String,
}

fn entry_prefix(entry_type: &str) -> Option<&'static str> {
    match entry_type {
        "question" | "question_response" => Some("QST"),
        "action" | "action_update"       => Some("ACT"),
        "amendment"                      => Some("AMD"),
        "state_transition"               => Some("STA"),
        "merge_snapshot"                 => Some("MRG"),
        "decision"                       => Some("DEC"),
        _ => None,
    }
}

fn entry_to_cjson(e: &RegisterEntry, include_sig: bool) -> CjsonVal {
    let mut m = BTreeMap::new();
    m.insert("entryId".into(), CjsonVal::Str(e.entry_id.clone()));
    m.insert("sessionId".into(), CjsonVal::Str(e.session_id.clone()));
    m.insert("nodeId".into(), CjsonVal::Str(e.node_id.clone()));
    m.insert("seq".into(), CjsonVal::Int(e.seq));
    m.insert("type".into(), CjsonVal::Str(e.entry_type.clone()));
    m.insert("content".into(), e.content.clone());
    m.insert("timestamp".into(), CjsonVal::Str(e.timestamp.clone()));
    if include_sig { m.insert("sig".into(), CjsonVal::Str(e.sig.clone())); }
    CjsonVal::Object(m)
}

/// Parse a register entry from a CjsonVal object.
pub fn register_entry_from_cjson(v: &CjsonVal) -> Result<RegisterEntry, String> {
    let o = v.as_object().ok_or("register entry: not an object")?;
    let s = |k: &str| o.get(k).and_then(|x| x.as_str()).map(|x| x.to_string())
        .ok_or_else(|| format!("register entry: missing {}", k));
    Ok(RegisterEntry {
        entry_id:   s("entryId")?,
        session_id: s("sessionId")?,
        node_id:    s("nodeId")?,
        seq:        o.get("seq").and_then(|x| x.as_i64()).ok_or("register entry: missing seq")?,
        entry_type: s("type")?,
        content:    o.get("content").cloned().unwrap_or(CjsonVal::Object(BTreeMap::new())),
        timestamp:  s("timestamp")?,
        sig:        s("sig").unwrap_or_default(),
    })
}

/// Options for create_register_entry.
pub struct CreateEntryOptions {
    pub session_id: String,
    pub node_id: String,
    pub seq: i64,
    pub timestamp: String,
    pub private_key_b64: String,
    /// Explicit id; defaults to "<PREFIX>-<node_id>-<seq>".
    pub entry_id: Option<String>,
}

/// Create a signed register entry (LTX-SECURITY.md §9.5). The signature
/// covers the canonical JSON of the entry without "sig".
pub fn create_register_entry(entry_type: &str, content: CjsonVal, opts: &CreateEntryOptions)
    -> Result<RegisterEntry, String>
{
    let entry_id = match &opts.entry_id {
        Some(id) => id.clone(),
        None => {
            let prefix = entry_prefix(entry_type)
                .ok_or_else(|| format!("createRegisterEntry: unknown type {}", entry_type))?;
            format!("{}-{}-{}", prefix, opts.node_id, opts.seq)
        }
    };
    let mut entry = RegisterEntry {
        entry_id,
        session_id: opts.session_id.clone(),
        node_id: opts.node_id.clone(),
        seq: opts.seq,
        entry_type: entry_type.to_string(),
        content,
        timestamp: opts.timestamp.clone(),
        sig: String::new(),
    };
    let seed_bytes = URL_SAFE_NO_PAD.decode(&opts.private_key_b64)
        .map_err(|e| format!("base64 decode: {}", e))?;
    if seed_bytes.len() != 32 {
        return Err(format!("invalid key length: {}", seed_bytes.len()));
    }
    let seed: [u8; 32] = seed_bytes.try_into().unwrap();
    let signing_key = SigningKey::from_bytes(&seed);
    let msg = canonical_json(&entry_to_cjson(&entry, false));
    let sig: Signature = signing_key.sign(msg.as_bytes());
    entry.sig = URL_SAFE_NO_PAD.encode(sig.to_bytes());
    Ok(entry)
}

/// Verify a register entry signature against a key cache mapping the entry's
/// node_id to its NIK.
pub fn verify_register_entry(entry: &RegisterEntry, key_cache: &HashMap<String, Nik>)
    -> VerifyResult
{
    if entry.sig.is_empty() {
        return VerifyResult { valid: false, reason: "missing_sig".into() };
    }
    let nik = match key_cache.get(&entry.node_id) {
        Some(n) => n,
        None => return VerifyResult { valid: false, reason: "key_not_in_cache".into() },
    };
    let raw_pub = match URL_SAFE_NO_PAD.decode(&nik.public_key) {
        Ok(v) if v.len() == 32 => v,
        _ => return VerifyResult { valid: false, reason: "invalid_public_key".into() },
    };
    let pub_arr: [u8; 32] = raw_pub.try_into().unwrap();
    let verifying_key = match VerifyingKey::from_bytes(&pub_arr) {
        Ok(k) => k,
        Err(_) => return VerifyResult { valid: false, reason: "invalid_public_key".into() },
    };
    let sig_bytes = match URL_SAFE_NO_PAD.decode(&entry.sig) {
        Ok(v) if v.len() == 64 => v,
        _ => return VerifyResult { valid: false, reason: "invalid_signature".into() },
    };
    let sig_arr: [u8; 64] = sig_bytes.try_into().unwrap();
    let signature = Signature::from_bytes(&sig_arr);
    let msg = canonical_json(&entry_to_cjson(entry, false));
    if verifying_key.verify(msg.as_bytes(), &signature).is_err() {
        return VerifyResult { valid: false, reason: "signature_invalid".into() };
    }
    VerifyResult { valid: true, reason: String::new() }
}

/// §8.2 total order: (timestamp, node_id, seq).
pub fn compare_entries(a: &RegisterEntry, b: &RegisterEntry) -> std::cmp::Ordering {
    a.timestamp.cmp(&b.timestamp)
        .then_with(|| a.node_id.cmp(&b.node_id))
        .then_with(|| a.seq.cmp(&b.seq))
}

/// De-duplicate by (node_id, seq) and sort into the §8.2 total order.
pub fn order_entries(entries: &[RegisterEntry]) -> Vec<RegisterEntry> {
    let mut seen: std::collections::HashSet<(String, i64)> = std::collections::HashSet::new();
    let mut out: Vec<RegisterEntry> = Vec::with_capacity(entries.len());
    for e in entries {
        if seen.insert((e.node_id.clone(), e.seq)) {
            out.push(e.clone());
        }
    }
    out.sort_by(compare_entries);
    out
}

/// Reduced state of one question (§9.4).
#[derive(Debug, Clone, PartialEq)]
pub struct QuestionState {
    pub qid: String,
    pub text: String,
    pub submitter: String,
    pub urgency: Option<String>,
    pub intended_window: Option<String>,
    pub status: String, // OPEN | ANSWERED | WITHDRAWN
    pub response: Option<String>,
    pub responder: Option<String>,
    pub version: i64,
}

/// Reduced state of one action item (§10.2).
#[derive(Debug, Clone, PartialEq)]
pub struct ActionState {
    pub aid: String,
    pub description: String,
    pub owner: Option<String>,
    pub due_time_utc: Option<String>,
    pub origin_window: Option<String>,
    pub status: String, // PROPOSED | ACCEPTED | REJECTED | DONE
    pub version: i64,
}

struct Versioned { version: i64, editor: String, entry_id: String }

/// §8.2 conflict rule: higher version wins; tie → lowest editor node_id.
fn wins_conflict(incoming: &Versioned, current: &Versioned) -> bool {
    if incoming.version != current.version { incoming.version > current.version }
    else { incoming.editor < current.editor }
}

fn content_str(c: &CjsonVal, key: &str) -> Option<String> {
    c.get(key).and_then(|v| v.as_str()).map(|s| s.to_string())
}

/// Reduce question register state from log entries (§9.4). Pure: identical
/// entry sets in any input order produce identical state. Returns the state
/// map plus entry_ids superseded per §8.2 (flagged, never dropped).
pub fn reduce_questions(entries: &[RegisterEntry])
    -> (BTreeMap<String, QuestionState>, Vec<String>)
{
    let mut by_id: BTreeMap<String, QuestionState> = BTreeMap::new();
    let mut winners: BTreeMap<String, Versioned> = BTreeMap::new();
    let mut superseded: Vec<String> = Vec::new();

    for e in order_entries(entries) {
        if e.entry_type == "question" {
            let qid = e.entry_id.clone();
            if by_id.contains_key(&qid) { superseded.push(e.entry_id.clone()); continue; }
            winners.insert(qid.clone(), Versioned {
                version: 1, editor: e.node_id.clone(), entry_id: e.entry_id.clone(),
            });
            by_id.insert(qid.clone(), QuestionState {
                qid,
                text: content_str(&e.content, "text").unwrap_or_default(),
                submitter: e.node_id.clone(),
                urgency: content_str(&e.content, "urgency"),
                intended_window: content_str(&e.content, "intendedWindow"),
                status: "OPEN".into(),
                response: None,
                responder: None,
                version: 1,
            });
        } else if e.entry_type == "question_response" {
            let qid = content_str(&e.content, "qid").unwrap_or_default();
            let q = match by_id.get(&qid) {
                Some(q) => q.clone(),
                None => { superseded.push(e.entry_id.clone()); continue; }
            };
            let version = e.content.get("version").and_then(|v| v.as_i64())
                .unwrap_or(q.version + 1);
            let incoming = Versioned {
                version, editor: e.node_id.clone(), entry_id: e.entry_id.clone(),
            };
            if let Some(current) = winners.get(&qid) {
                if !wins_conflict(&incoming, current) {
                    superseded.push(e.entry_id.clone());
                    continue;
                }
                if current.entry_id != q.qid { superseded.push(current.entry_id.clone()); }
            }
            winners.insert(qid.clone(), incoming);
            let status = if content_str(&e.content, "status").as_deref() == Some("WITHDRAWN") {
                "WITHDRAWN"
            } else { "ANSWERED" };
            let mut updated = q;
            updated.status = status.into();
            if let Some(r) = content_str(&e.content, "response") { updated.response = Some(r); }
            updated.responder = Some(e.node_id.clone());
            updated.version = version;
            by_id.insert(qid, updated);
        }
    }
    (by_id, superseded)
}

/// Reduce action register state from log entries (§10.2).
pub fn reduce_actions(entries: &[RegisterEntry])
    -> (BTreeMap<String, ActionState>, Vec<String>)
{
    const ACTION_STATUSES: [&str; 4] = ["PROPOSED", "ACCEPTED", "REJECTED", "DONE"];
    let mut by_id: BTreeMap<String, ActionState> = BTreeMap::new();
    let mut winners: BTreeMap<String, Versioned> = BTreeMap::new();
    let mut superseded: Vec<String> = Vec::new();

    for e in order_entries(entries) {
        if e.entry_type == "action" {
            let aid = e.entry_id.clone();
            if by_id.contains_key(&aid) { superseded.push(e.entry_id.clone()); continue; }
            winners.insert(aid.clone(), Versioned {
                version: 1, editor: e.node_id.clone(), entry_id: e.entry_id.clone(),
            });
            by_id.insert(aid.clone(), ActionState {
                aid,
                description: content_str(&e.content, "description").unwrap_or_default(),
                owner: content_str(&e.content, "owner"),
                due_time_utc: content_str(&e.content, "dueTimeUTC"),
                origin_window: content_str(&e.content, "originWindow"),
                status: "PROPOSED".into(),
                version: 1,
            });
        } else if e.entry_type == "action_update" {
            let aid = content_str(&e.content, "aid").unwrap_or_default();
            let a = match by_id.get(&aid) {
                Some(a) => a.clone(),
                None => { superseded.push(e.entry_id.clone()); continue; }
            };
            let version = e.content.get("version").and_then(|v| v.as_i64())
                .unwrap_or(a.version + 1);
            let incoming = Versioned {
                version, editor: e.node_id.clone(), entry_id: e.entry_id.clone(),
            };
            if let Some(current) = winners.get(&aid) {
                if !wins_conflict(&incoming, current) {
                    superseded.push(e.entry_id.clone());
                    continue;
                }
                if current.entry_id != a.aid { superseded.push(current.entry_id.clone()); }
            }
            winners.insert(aid.clone(), incoming);
            let mut updated = a;
            if let Some(s) = content_str(&e.content, "status") {
                if ACTION_STATUSES.contains(&s.as_str()) { updated.status = s; }
            }
            if let Some(d) = content_str(&e.content, "description") { updated.description = d; }
            if let Some(o) = content_str(&e.content, "owner") { updated.owner = Some(o); }
            if let Some(d) = content_str(&e.content, "dueTimeUTC") { updated.due_time_utc = Some(d); }
            updated.version = version;
            by_id.insert(aid, updated);
        }
    }
    (by_id, superseded)
}

// ── Merkle log root (RFC 9162-style, story 28.5 hash scheme) ──────────────

fn merkle_leaf_hash(entry_bytes: &[u8]) -> [u8; 32] {
    let mut buf = Vec::with_capacity(1 + entry_bytes.len());
    buf.push(0x00);
    buf.extend_from_slice(entry_bytes);
    Sha256::digest(&buf).into()
}

fn merkle_node_hash(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut buf = Vec::with_capacity(65);
    buf.push(0x01);
    buf.extend_from_slice(left);
    buf.extend_from_slice(right);
    Sha256::digest(&buf).into()
}

fn merkle_root_of(leaves: &[[u8; 32]]) -> [u8; 32] {
    match leaves.len() {
        0 => [0u8; 32],
        1 => leaves[0],
        n => {
            // Largest power of two strictly less than n (RFC 9162 §2.1).
            let mut mid = 1usize;
            while mid * 2 < n { mid *= 2; }
            merkle_node_hash(&merkle_root_of(&leaves[..mid]), &merkle_root_of(&leaves[mid..]))
        }
    }
}

/// Merkle audit-log root (hex) over the §8.2-ordered entries:
/// leaf = SHA-256(0x00 || canonical_json(entry)),
/// node = SHA-256(0x01 || left || right); empty log root is 64 hex zeros.
pub fn entries_root(entries: &[RegisterEntry]) -> String {
    let leaves: Vec<[u8; 32]> = order_entries(entries).iter()
        .map(|e| merkle_leaf_hash(canonical_json(&entry_to_cjson(e, true)).as_bytes()))
        .collect();
    merkle_root_of(&leaves).iter().map(|b| format!("{:02x}", b)).collect()
}

// ── Feature 5: CBOR (RFC 8949 deterministic subset) + COSE_Sign1 ──────────

/// Minimal CBOR value (RFC 8949 deterministic subset — no floats).
#[derive(Debug, Clone, PartialEq)]
pub enum CborVal {
    Null,
    Bool(bool),
    Int(i64),
    Bytes(Vec<u8>),
    Text(String),
    Array(Vec<CborVal>),
    /// Map entries in decode order; encoding sorts bytewise by encoded key.
    Map(Vec<(CborVal, CborVal)>),
    Tag(u64, Box<CborVal>),
}

pub const COSE_SIGN1_TAG: u64 = 18;
pub const COSE_ALG_ED25519: i64 = -19;

fn cbor_encode_head(major: u8, arg: u64, out: &mut Vec<u8>) {
    if arg < 24 {
        out.push((major << 5) | arg as u8);
    } else if arg < 0x100 {
        out.push((major << 5) | 24);
        out.push(arg as u8);
    } else if arg < 0x10000 {
        out.push((major << 5) | 25);
        out.extend_from_slice(&(arg as u16).to_be_bytes());
    } else if arg < 0x1_0000_0000 {
        out.push((major << 5) | 26);
        out.extend_from_slice(&(arg as u32).to_be_bytes());
    } else {
        out.push((major << 5) | 27);
        out.extend_from_slice(&arg.to_be_bytes());
    }
}

/// Encode a value to deterministic CBOR bytes (RFC 8949 §4.2.1: definite
/// lengths, shortest-form heads, map keys sorted bytewise by encoded form).
pub fn encode_cbor(value: &CborVal) -> Vec<u8> {
    let mut out = Vec::new();
    encode_cbor_into(value, &mut out);
    out
}

fn encode_cbor_into(value: &CborVal, out: &mut Vec<u8>) {
    match value {
        CborVal::Null        => out.push(0xf6),
        CborVal::Bool(true)  => out.push(0xf5),
        CborVal::Bool(false) => out.push(0xf4),
        CborVal::Int(n) => {
            if *n >= 0 { cbor_encode_head(0, *n as u64, out); }
            else { cbor_encode_head(1, (-(n + 1)) as u64, out); }
        }
        CborVal::Bytes(b) => {
            cbor_encode_head(2, b.len() as u64, out);
            out.extend_from_slice(b);
        }
        CborVal::Text(s) => {
            cbor_encode_head(3, s.len() as u64, out);
            out.extend_from_slice(s.as_bytes());
        }
        CborVal::Array(a) => {
            cbor_encode_head(4, a.len() as u64, out);
            for item in a { encode_cbor_into(item, out); }
        }
        CborVal::Map(m) => {
            let mut pairs: Vec<(Vec<u8>, Vec<u8>)> = m.iter()
                .map(|(k, v)| (encode_cbor(k), encode_cbor(v)))
                .collect();
            pairs.sort_by(|a, b| a.0.cmp(&b.0));
            cbor_encode_head(5, pairs.len() as u64, out);
            for (k, v) in pairs {
                out.extend_from_slice(&k);
                out.extend_from_slice(&v);
            }
        }
        CborVal::Tag(t, inner) => {
            cbor_encode_head(6, *t, out);
            encode_cbor_into(inner, out);
        }
    }
}

struct CborDecoder<'a> { buf: &'a [u8], pos: usize }

impl<'a> CborDecoder<'a> {
    fn read_head(&mut self) -> Result<(u8, u64), String> {
        let initial = *self.buf.get(self.pos).ok_or("cbor: truncated")?;
        self.pos += 1;
        let major = initial >> 5;
        let info = initial & 0x1f;
        let arg = match info {
            0..=23 => info as u64,
            24 => {
                let v = *self.buf.get(self.pos).ok_or("cbor: truncated")? as u64;
                self.pos += 1; v
            }
            25 => {
                let b = self.buf.get(self.pos..self.pos + 2).ok_or("cbor: truncated")?;
                self.pos += 2;
                u16::from_be_bytes([b[0], b[1]]) as u64
            }
            26 => {
                let b = self.buf.get(self.pos..self.pos + 4).ok_or("cbor: truncated")?;
                self.pos += 4;
                u32::from_be_bytes([b[0], b[1], b[2], b[3]]) as u64
            }
            27 => {
                let b = self.buf.get(self.pos..self.pos + 8).ok_or("cbor: truncated")?;
                self.pos += 8;
                u64::from_be_bytes(b.try_into().unwrap())
            }
            _ => return Err("cbor: indefinite lengths not supported".into()),
        };
        Ok((major, arg))
    }

    fn decode_item(&mut self, depth: u32) -> Result<CborVal, String> {
        if depth > 64 { return Err("cbor: nesting too deep".into()); }
        match self.buf.get(self.pos) {
            Some(0xf6) => { self.pos += 1; return Ok(CborVal::Null); }
            Some(0xf5) => { self.pos += 1; return Ok(CborVal::Bool(true)); }
            Some(0xf4) => { self.pos += 1; return Ok(CborVal::Bool(false)); }
            _ => {}
        }
        let (major, arg) = self.read_head()?;
        match major {
            0 => {
                if arg > i64::MAX as u64 { return Err("cbor: integer too large".into()); }
                Ok(CborVal::Int(arg as i64))
            }
            1 => {
                if arg >= i64::MAX as u64 { return Err("cbor: integer too large".into()); }
                Ok(CborVal::Int(-(arg as i64) - 1))
            }
            2 => {
                let end = self.pos.checked_add(arg as usize).ok_or("cbor: truncated bstr")?;
                let b = self.buf.get(self.pos..end).ok_or("cbor: truncated bstr")?;
                self.pos = end;
                Ok(CborVal::Bytes(b.to_vec()))
            }
            3 => {
                let end = self.pos.checked_add(arg as usize).ok_or("cbor: truncated tstr")?;
                let b = self.buf.get(self.pos..end).ok_or("cbor: truncated tstr")?;
                self.pos = end;
                Ok(CborVal::Text(String::from_utf8(b.to_vec())
                    .map_err(|_| "cbor: invalid utf8 in tstr")?))
            }
            4 => {
                let mut arr = Vec::new();
                for _ in 0..arg { arr.push(self.decode_item(depth + 1)?); }
                Ok(CborVal::Array(arr))
            }
            5 => {
                let mut map = Vec::new();
                for _ in 0..arg {
                    let k = self.decode_item(depth + 1)?;
                    let v = self.decode_item(depth + 1)?;
                    map.push((k, v));
                }
                Ok(CborVal::Map(map))
            }
            6 => Ok(CborVal::Tag(arg, Box::new(self.decode_item(depth + 1)?))),
            _ => Err(format!("cbor: unsupported major type {} / simple value", major)),
        }
    }
}

/// Decode deterministic CBOR bytes to a value. Floats, indefinite lengths
/// and trailing bytes are rejected.
pub fn decode_cbor(data: &[u8]) -> Result<CborVal, String> {
    let mut d = CborDecoder { buf: data, pos: 0 };
    let v = d.decode_item(0)?;
    if d.pos != data.len() { return Err("cbor: trailing bytes".into()); }
    Ok(v)
}

fn cbor_map_get<'a>(map: &'a [(CborVal, CborVal)], key: &CborVal) -> Option<&'a CborVal> {
    map.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

/// Signed plan carrying the CBOR COSE_Sign1 envelope (base64url bytes).
#[derive(Debug, Clone)]
pub struct CoseSignedPlan {
    pub plan: Option<CjsonVal>,
    pub cose_sign1_cbor_b64: String,
}

fn cose_sig_structure_bytes(protected: &[u8], payload: &[u8]) -> Vec<u8> {
    encode_cbor(&CborVal::Array(vec![
        CborVal::Text("Signature1".into()),
        CborVal::Bytes(protected.to_vec()),
        CborVal::Bytes(Vec::new()),
        CborVal::Bytes(payload.to_vec()),
    ]))
}

/// Sign a plan as a real CBOR COSE_Sign1 (tag 18, RFC 9052). Algorithm
/// Ed25519 (COSE id -19, RFC 9864). The kid (header label 4) is the raw
/// 16-byte prefix of SHA-256(raw public key), matching generate_nik().
pub fn sign_plan_cose(plan: &CjsonVal, private_key_b64: &str) -> Result<CoseSignedPlan, String> {
    let seed_bytes = URL_SAFE_NO_PAD.decode(private_key_b64)
        .map_err(|e| format!("base64 decode: {}", e))?;
    if seed_bytes.len() != 32 {
        return Err(format!("invalid key length: {}", seed_bytes.len()));
    }
    let seed: [u8; 32] = seed_bytes.try_into().unwrap();
    let signing_key = SigningKey::from_bytes(&seed);

    let protected = encode_cbor(&CborVal::Map(vec![
        (CborVal::Int(1), CborVal::Int(COSE_ALG_ED25519)),
    ]));
    let payload = canonical_json(plan).into_bytes();
    let sig_struct = cose_sig_structure_bytes(&protected, &payload);
    let sig: Signature = signing_key.sign(&sig_struct);

    let raw_pub: [u8; 32] = signing_key.verifying_key().to_bytes();
    let kid_hash = Sha256::digest(raw_pub);
    let envelope = CborVal::Tag(COSE_SIGN1_TAG, Box::new(CborVal::Array(vec![
        CborVal::Bytes(protected),
        CborVal::Map(vec![(CborVal::Int(4), CborVal::Bytes(kid_hash[..16].to_vec()))]),
        CborVal::Bytes(payload),
        CborVal::Bytes(sig.to_bytes().to_vec()),
    ])));
    Ok(CoseSignedPlan {
        plan: Some(plan.clone()),
        cose_sign1_cbor_b64: URL_SAFE_NO_PAD.encode(encode_cbor(&envelope)),
    })
}

/// Verify a CBOR COSE_Sign1 plan envelope against the key cache. Rejects
/// non-Ed25519 algorithms (including the deprecated -8) and payloads that
/// do not match the accompanying plan object.
pub fn verify_plan_cose(envelope: &CoseSignedPlan, key_cache: &HashMap<String, Nik>)
    -> VerifyResult
{
    let fail = |reason: &str| VerifyResult { valid: false, reason: reason.into() };
    if envelope.cose_sign1_cbor_b64.is_empty() { return fail("missing_cose_sign1"); }
    let raw = match URL_SAFE_NO_PAD.decode(&envelope.cose_sign1_cbor_b64) {
        Ok(v) => v, Err(_) => return fail("cbor_decode_failed"),
    };
    let decoded = match decode_cbor(&raw) {
        Ok(v) => v, Err(_) => return fail("cbor_decode_failed"),
    };
    let arr = match decoded {
        CborVal::Tag(COSE_SIGN1_TAG, inner) => match *inner {
            CborVal::Array(a) if a.len() == 4 => a,
            _ => return fail("malformed_cose_sign1"),
        },
        _ => return fail("not_cose_sign1"),
    };
    let protected = match &arr[0] { CborVal::Bytes(b) => b.clone(), _ => return fail("malformed_cose_sign1") };
    let unprotected = match &arr[1] { CborVal::Map(m) => m.clone(), _ => return fail("malformed_cose_sign1") };
    let payload = match &arr[2] { CborVal::Bytes(b) => b.clone(), _ => return fail("malformed_cose_sign1") };
    let signature = match &arr[3] { CborVal::Bytes(b) => b.clone(), _ => return fail("malformed_cose_sign1") };

    let protected_map = match decode_cbor(&protected) {
        Ok(CborVal::Map(m)) => m, _ => return fail("protected_decode_failed"),
    };
    if cbor_map_get(&protected_map, &CborVal::Int(1)) != Some(&CborVal::Int(COSE_ALG_ED25519)) {
        return fail("unsupported_alg");
    }

    let kid = match cbor_map_get(&unprotected, &CborVal::Int(4)) {
        Some(CborVal::Bytes(b)) => URL_SAFE_NO_PAD.encode(b),
        Some(CborVal::Text(s))  => s.clone(),
        _ => return fail("missing_kid"),
    };
    if kid.is_empty() { return fail("missing_kid"); }

    let signer_nik = match key_cache.get(&kid) {
        Some(n) => n,
        None => match key_cache.values().find(|n| n.node_id.starts_with(&kid)) {
            Some(n) => n,
            None => return fail("key_not_in_cache"),
        },
    };
    if is_nik_expired(signer_nik) { return fail("key_expired"); }

    let raw_pub = match URL_SAFE_NO_PAD.decode(&signer_nik.public_key) {
        Ok(v) if v.len() == 32 => v, _ => return fail("invalid_public_key"),
    };
    let pub_arr: [u8; 32] = raw_pub.try_into().unwrap();
    let verifying_key = match VerifyingKey::from_bytes(&pub_arr) {
        Ok(k) => k, Err(_) => return fail("invalid_public_key"),
    };
    let sig_arr: [u8; 64] = match signature.try_into() {
        Ok(a) => a, Err(_) => return fail("invalid_signature"),
    };
    let sig_struct = cose_sig_structure_bytes(&protected, &payload);
    if verifying_key.verify(&sig_struct, &Signature::from_bytes(&sig_arr)).is_err() {
        return fail("signature_invalid");
    }

    if let Some(plan) = &envelope.plan {
        if payload != canonical_json(plan).into_bytes() {
            return fail("payload_mismatch");
        }
    }
    VerifyResult { valid: true, reason: String::new() }
}
