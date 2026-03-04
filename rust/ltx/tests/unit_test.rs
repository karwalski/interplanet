use interplanet_ltx::*;

fn check(name: &str, cond: bool, passed: &mut i32, failed: &mut i32) {
    if cond { *passed += 1; }
    else { *failed += 1; println!("FAIL: {}", name); }
}

#[test]
fn test_all() {
    let mut passed = 0i32;
    let mut failed = 0i32;

    // -- Constants (9 checks)
    check("VERSION", VERSION == "1.0.0", &mut passed, &mut failed);
    check("DEFAULT_QUANTUM", DEFAULT_QUANTUM == 3, &mut passed, &mut failed);
    check("DEFAULT_API_BASE", DEFAULT_API_BASE.contains("interplanet.live"), &mut passed, &mut failed);
    let ds = default_segments();
    check("ds[0] PLAN_CONFIRM", ds[0].seg_type == "PLAN_CONFIRM", &mut passed, &mut failed);
    check("ds[0].q==2", ds[0].q == 2, &mut passed, &mut failed);
    check("ds[1] TX", ds[1].seg_type == "TX", &mut passed, &mut failed);
    check("ds[3] CAUCUS", ds[3].seg_type == "CAUCUS", &mut passed, &mut failed);
    check("ds[6] BUFFER", ds[6].seg_type == "BUFFER", &mut passed, &mut failed);
    check("ds[6].q==1", ds[6].q == 1, &mut passed, &mut failed);

    // -- create_plan defaults (11 checks)
    let plan = create_plan(None, "2026-03-15T14:00:00Z", 0);
    check("v==2", plan.v == 2, &mut passed, &mut failed);
    check("title default", plan.title == "LTX Session", &mut passed, &mut failed);
    check("start", plan.start == "2026-03-15T14:00:00Z", &mut passed, &mut failed);
    check("quantum==3", plan.quantum == 3, &mut passed, &mut failed);
    check("mode==LTX", plan.mode == "LTX", &mut passed, &mut failed);
    check("nodes[0].id==N0", plan.nodes[0].id == "N0", &mut passed, &mut failed);
    check("nodes[0].role==HOST", plan.nodes[0].role == "HOST", &mut passed, &mut failed);
    check("nodes[0].location==earth", plan.nodes[0].location == "earth", &mut passed, &mut failed);
    check("nodes[0].delay==0", plan.nodes[0].delay == 0, &mut passed, &mut failed);
    check("nodes[1].id==N1", plan.nodes[1].id == "N1", &mut passed, &mut failed);
    check("nodes[1].role==PARTICIPANT", plan.nodes[1].role == "PARTICIPANT", &mut passed, &mut failed);

    // -- create_plan more (5 checks)
    check("nodes[1].location==mars", plan.nodes[1].location == "mars", &mut passed, &mut failed);
    check("nodes.len==2", plan.nodes.len() == 2, &mut passed, &mut failed);
    check("segments.len==7", plan.segments.len() == 7, &mut passed, &mut failed);
    let plan2 = create_plan(Some("My Session"), "2026-04-01T09:00:00Z", 860);
    check("custom title", plan2.title == "My Session", &mut passed, &mut failed);
    check("custom delay", plan2.nodes[1].delay == 860, &mut passed, &mut failed);

    // -- upgrade_config (7 checks)
    let cfg = r#"{"title":"Upgraded","start":"2026-04-01T09:00:00Z","quantum":5}"#;
    let up = upgrade_config(cfg);
    check("upgraded title", up.title == "Upgraded", &mut passed, &mut failed);
    check("upgraded start", up.start == "2026-04-01T09:00:00Z", &mut passed, &mut failed);
    check("upgraded quantum", up.quantum == 5, &mut passed, &mut failed);
    check("upgraded mode default", up.mode == "LTX", &mut passed, &mut failed);
    check("upgraded nodes default", up.nodes.len() == 2, &mut passed, &mut failed);
    check("upgraded segs default", up.segments.len() == 7, &mut passed, &mut failed);
    let cfg2 = r#"{"title":"T","start":"2026-05-01T10:00:00Z","quantum":4,"mode":"RELAY"}"#;
    let up2 = upgrade_config(cfg2);
    check("upgraded mode RELAY", up2.mode == "RELAY", &mut passed, &mut failed);

    // -- compute_segments (11 checks)
    let segs = compute_segments(&plan).expect("compute_segments failed");
    check("segs.len==7", segs.len() == 7, &mut passed, &mut failed);
    check("segs[0].seg_type", segs[0].seg_type == "PLAN_CONFIRM", &mut passed, &mut failed);
    check("segs[0].q==2", segs[0].q == 2, &mut passed, &mut failed);
    let expected_dur0 = 2 * 3 * 60 * 1000i64; // q=2, quantum=3, ms
    check("segs[0].dur_min==6", segs[0].dur_min == 6, &mut passed, &mut failed);
    check("segs[0].end-start==dur", segs[0].end_ms - segs[0].start_ms == expected_dur0, &mut passed, &mut failed);
    check("segs[1].start==segs[0].end", segs[1].start_ms == segs[0].end_ms, &mut passed, &mut failed);
    check("segs[6].seg_type==BUFFER", segs[6].seg_type == "BUFFER", &mut passed, &mut failed);
    check("segs[6].q==1", segs[6].q == 1, &mut passed, &mut failed);
    check("segs[6].dur_min==3", segs[6].dur_min == 3, &mut passed, &mut failed);
    // contiguous
    for i in 1..segs.len() {
        check(&format!("segs contiguous {}", i), segs[i].start_ms == segs[i-1].end_ms, &mut passed, &mut failed);
    }
    // quantum guard
    let mut bad_plan = create_plan(None, "2026-03-15T14:00:00Z", 0);
    bad_plan.quantum = 0;
    check("compute_segments quantum=0 errors", compute_segments(&bad_plan).is_err(), &mut passed, &mut failed);
    bad_plan.quantum = -1;
    check("compute_segments quantum=-1 errors", compute_segments(&bad_plan).is_err(), &mut passed, &mut failed);

    // -- total_min (2 checks)
    let tm = total_min(&plan);
    check("total_min==39", tm == 39, &mut passed, &mut failed); // (2+2+2+2+2+2+1)*3=39
    let plan_q5 = create_plan(None, "2026-03-15T14:00:00Z", 0);
    let tm2 = total_min(&plan_q5);
    check("total_min q3 again", tm2 == 39, &mut passed, &mut failed);

    // -- make_plan_id (6 checks)
    let pid = make_plan_id(&plan);
    check("pid starts LTX-", pid.starts_with("LTX-"), &mut passed, &mut failed);
    check("pid has date", pid.contains("20260315"), &mut passed, &mut failed);
    check("pid has EARTHHQ", pid.contains("EARTHHQ"), &mut passed, &mut failed);
    check("pid has MARS", pid.contains("MARS"), &mut passed, &mut failed);
    check("pid has v2", pid.contains("-v2-"), &mut passed, &mut failed);
    check("pid 8 hex chars", {
        let parts: Vec<&str> = pid.split('-').collect();
        parts.last().map(|s| s.len() == 8 && s.chars().all(|c| c.is_ascii_hexdigit())).unwrap_or(false)
    }, &mut passed, &mut failed);

    // -- encode_hash / decode_hash (12 checks)
    let hash = encode_hash(&plan);
    check("hash starts #l=", hash.starts_with("#l="), &mut passed, &mut failed);
    check("hash no = padding", !hash[3..].contains('='), &mut passed, &mut failed);
    check("hash no spaces", !hash.contains(' '), &mut passed, &mut failed);
    let decoded = decode_hash(&hash).expect("decode failed");
    check("decoded v", decoded.v == plan.v, &mut passed, &mut failed);
    check("decoded title", decoded.title == plan.title, &mut passed, &mut failed);
    check("decoded start", decoded.start == plan.start, &mut passed, &mut failed);
    check("decoded quantum", decoded.quantum == plan.quantum, &mut passed, &mut failed);
    check("decoded mode", decoded.mode == plan.mode, &mut passed, &mut failed);
    check("decoded nodes.len", decoded.nodes.len() == plan.nodes.len(), &mut passed, &mut failed);
    check("decoded nodes[0].id", decoded.nodes[0].id == plan.nodes[0].id, &mut passed, &mut failed);
    check("decoded segs.len", decoded.segments.len() == plan.segments.len(), &mut passed, &mut failed);
    check("decode_hash none on bad input", decode_hash("#l=!!!").is_none(), &mut passed, &mut failed);

    // -- build_node_urls (8 checks)
    let urls = build_node_urls(&plan, "https://interplanet.live/ltx.html");
    check("urls.len==2", urls.len() == 2, &mut passed, &mut failed);
    check("url[0].node_id==N0", urls[0].node_id == "N0", &mut passed, &mut failed);
    check("url[0].role==HOST", urls[0].role == "HOST", &mut passed, &mut failed);
    check("url[0].url has node=N0", urls[0].url.contains("node=N0"), &mut passed, &mut failed);
    check("url[0].url has #l=", urls[0].url.contains("#l="), &mut passed, &mut failed);
    check("url[1].node_id==N1", urls[1].node_id == "N1", &mut passed, &mut failed);
    check("url[1].role==PARTICIPANT", urls[1].role == "PARTICIPANT", &mut passed, &mut failed);
    check("url[1].url has node=N1", urls[1].url.contains("node=N1"), &mut passed, &mut failed);

    // -- generate_ics (13 checks)
    let ics = generate_ics(&plan);
    check("ics has BEGIN:VCALENDAR", ics.contains("BEGIN:VCALENDAR"), &mut passed, &mut failed);
    check("ics has END:VCALENDAR", ics.contains("END:VCALENDAR"), &mut passed, &mut failed);
    check("ics has BEGIN:VEVENT", ics.contains("BEGIN:VEVENT"), &mut passed, &mut failed);
    check("ics has DTSTART", ics.contains("DTSTART:"), &mut passed, &mut failed);
    check("ics has SUMMARY", ics.contains("SUMMARY:LTX Session"), &mut passed, &mut failed);
    check("ics has LTX-PLANID", ics.contains("LTX-PLANID:"), &mut passed, &mut failed);
    check("ics has LTX-QUANTUM", ics.contains("LTX-QUANTUM:PT3M"), &mut passed, &mut failed);
    check("ics CRLF endings", ics.contains("\r\n"), &mut passed, &mut failed);
    check("ics ends with CRLF", ics.ends_with("\r\n"), &mut passed, &mut failed);
    check("ics has LTX-MODE", ics.contains("LTX-MODE:LTX"), &mut passed, &mut failed);
    check("ics has LTX-READINESS", ics.contains("LTX-READINESS:"), &mut passed, &mut failed);
    check("ics has LTX-LOCALTIME for mars", ics.contains("LTX-LOCALTIME:"), &mut passed, &mut failed);
    check("ics has LTX-DELAY", ics.contains("LTX-DELAY"), &mut passed, &mut failed);

    // -- format_hms (8 checks)
    check("hms 0", format_hms(0) == "00:00", &mut passed, &mut failed);
    check("hms 30", format_hms(30) == "00:30", &mut passed, &mut failed);
    check("hms 59", format_hms(59) == "00:59", &mut passed, &mut failed);
    check("hms 60", format_hms(60) == "01:00", &mut passed, &mut failed);
    check("hms 3600", format_hms(3600) == "01:00:00", &mut passed, &mut failed);
    check("hms 3661", format_hms(3661) == "01:01:01", &mut passed, &mut failed);
    check("hms 7322", format_hms(7322) == "02:02:02", &mut passed, &mut failed);
    check("hms neg", format_hms(-1) == "00:00", &mut passed, &mut failed);

    // -- format_utc (3 checks)
    check("utc epoch 0", format_utc(0) == "00:00:00 UTC", &mut passed, &mut failed);
    check("utc 14:00:00", format_utc(1773583200000i64) == "14:00:00 UTC", &mut passed, &mut failed);
    // 2026-03-15T14:00:00Z = 1742040000 seconds
    check("utc format", format_utc(3661000).ends_with("UTC"), &mut passed, &mut failed);

    // -- store_session/get_session/download_ics/submit_feedback HTTPS error (8 checks)
    let ss = store_session(&plan, None);
    check("store_session https err", ss.is_err(), &mut passed, &mut failed);
    let gs = get_session("test-id", None);
    check("get_session https err", gs.is_err(), &mut passed, &mut failed);
    let di = download_ics("test-id", None, None);
    check("download_ics https err", di.is_err(), &mut passed, &mut failed);
    let sf = submit_feedback("test-id", "{}", None);
    check("submit_feedback https err", sf.is_err(), &mut passed, &mut failed);
    // With http base to non-existent server -> connection error (Err)
    let ss2 = store_session(&plan, Some("http://localhost:19999"));
    check("store_session http err", ss2.is_err(), &mut passed, &mut failed);
    let gs2 = get_session("id", Some("http://localhost:19999"));
    check("get_session http err", gs2.is_err(), &mut passed, &mut failed);
    let di2 = download_ics("id", Some("N0"), Some("http://localhost:19999"));
    check("download_ics http err", di2.is_err(), &mut passed, &mut failed);
    let sf2 = submit_feedback("id", "{}", Some("http://localhost:19999"));
    check("submit_feedback http err", sf2.is_err(), &mut passed, &mut failed);

    // -- escape_ics_text (7 checks)
    check("escape empty", escape_ics_text("") == "", &mut passed, &mut failed);
    check("escape no special", escape_ics_text("hello") == "hello", &mut passed, &mut failed);
    check("escape semicolon", escape_ics_text("a;b") == "a\\;b", &mut passed, &mut failed);
    check("escape comma", escape_ics_text("a,b") == "a\\,b", &mut passed, &mut failed);
    check("escape backslash", escape_ics_text("a\\b") == "a\\\\b", &mut passed, &mut failed);
    check("escape newline", escape_ics_text("a\nb") == "a\\nb", &mut passed, &mut failed);
    check("escape combined", escape_ics_text("Hello, World; Test\\End") == "Hello\\, World\\; Test\\\\End", &mut passed, &mut failed);

    // -- DEGRADED state (5 checks)
    check("DEGRADED as_str", SessionState::Degraded.as_str() == "DEGRADED", &mut passed, &mut failed);
    check("SESSION_STATES[0]", SESSION_STATES[0] == "INIT", &mut passed, &mut failed);
    check("SESSION_STATES[3]", SESSION_STATES[3] == "DEGRADED", &mut passed, &mut failed);
    check("SESSION_STATES[4]", SESSION_STATES[4] == "COMPLETE", &mut passed, &mut failed);
    check("SESSION_STATES len", SESSION_STATES.len() == 5, &mut passed, &mut failed);

    // -- plan_lock_timeout_ms (3 checks)
    check("DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR", DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR == 2, &mut passed, &mut failed);
    check("plan_lock_timeout_ms(100)==200000", (plan_lock_timeout_ms(100.0) - 200000.0).abs() < 0.001, &mut passed, &mut failed);
    check("plan_lock_timeout_ms(0)==0", plan_lock_timeout_ms(0.0) == 0.0, &mut passed, &mut failed);

    // -- check_delay_violation (10 checks)
    check("DELAY_VIOLATION_WARN_S", DELAY_VIOLATION_WARN_S == 120, &mut passed, &mut failed);
    check("DELAY_VIOLATION_DEGRADED_S", DELAY_VIOLATION_DEGRADED_S == 300, &mut passed, &mut failed);
    check("violation ok exact", check_delay_violation(100.0, 100.0) == "ok", &mut passed, &mut failed);
    check("violation ok within", check_delay_violation(100.0, 210.0) == "ok", &mut passed, &mut failed);
    check("violation warn +121", check_delay_violation(100.0, 221.0) == "violation", &mut passed, &mut failed);
    check("violation warn -121", check_delay_violation(221.0, 100.0) == "violation", &mut passed, &mut failed);
    check("violation degraded +301", check_delay_violation(100.0, 401.0) == "degraded", &mut passed, &mut failed);
    check("violation boundary 120", check_delay_violation(0.0, 120.0) == "ok", &mut passed, &mut failed);
    check("violation boundary 121", check_delay_violation(0.0, 121.0) == "violation", &mut passed, &mut failed);
    check("violation boundary 301", check_delay_violation(0.0, 301.0) == "degraded", &mut passed, &mut failed);

    // -- ICS escaping in generate_ics (2 checks)
    let escape_plan = create_plan(Some("Hello, World; Test"), "2026-03-15T14:00:00Z", 0);
    let escape_ics = generate_ics(&escape_plan);
    check("ics summary escaped", escape_ics.contains("SUMMARY:Hello\\, World\\; Test"), &mut passed, &mut failed);
    check("ics quantum format PT3M", escape_ics.contains("LTX-QUANTUM:PT3M"), &mut passed, &mut failed);

    println!("
{} passed  {} failed", passed, failed);
    assert_eq!(failed, 0, "{} check(s) failed", failed);
}


#[test]
fn test_canonical_json() {
    use interplanet_ltx::{CjsonVal, canonical_json};
    use std::collections::BTreeMap;

    // Different key order → same output
    let mut m1 = BTreeMap::new();
    m1.insert("b".to_string(), CjsonVal::Int(2));
    m1.insert("a".to_string(), CjsonVal::Int(1));
    let mut m2 = BTreeMap::new();
    m2.insert("a".to_string(), CjsonVal::Int(1));
    m2.insert("b".to_string(), CjsonVal::Int(2));
    assert_eq!(canonical_json(&CjsonVal::Object(m1)), canonical_json(&CjsonVal::Object(m2.clone())));
    assert_eq!(canonical_json(&CjsonVal::Object(m2)), r#"{"a":1,"b":2}"#);

    // Nested objects
    let mut inner = BTreeMap::new();
    inner.insert("y".to_string(), CjsonVal::Int(2));
    inner.insert("x".to_string(), CjsonVal::Int(1));
    let mut outer = BTreeMap::new();
    outer.insert("z".to_string(), CjsonVal::Object(inner));
    outer.insert("a".to_string(), CjsonVal::Str("hello".into()));
    assert_eq!(canonical_json(&CjsonVal::Object(outer)), r#"{"a":"hello","z":{"x":1,"y":2}}"#);

    // Array unchanged
    let arr = CjsonVal::Array(vec![CjsonVal::Int(3), CjsonVal::Int(1), CjsonVal::Int(2)]);
    assert_eq!(canonical_json(&arr), "[3,1,2]");

    // Primitives
    assert_eq!(canonical_json(&CjsonVal::Null), "null");
    assert_eq!(canonical_json(&CjsonVal::Bool(true)), "true");
    assert_eq!(canonical_json(&CjsonVal::Bool(false)), "false");
    assert_eq!(canonical_json(&CjsonVal::Int(42)), "42");
    assert_eq!(canonical_json(&CjsonVal::Str("hello".into())), r#""hello""#);

    println!("test_canonical_json: all checks passed");
}

#[test]
fn test_generate_nik() {
    use interplanet_ltx::{generate_nik, is_nik_expired};

    let result = generate_nik(Some(30), Some("Test Node"));
    assert!(!result.nik.node_id.is_empty(), "nodeId non-empty");
    assert!(!result.nik.public_key.is_empty(), "publicKey non-empty");
    assert_eq!(result.nik.algorithm, "Ed25519");
    assert_eq!(result.nik.key_version, 1);
    assert!(!result.nik.valid_from.is_empty());
    assert!(!result.nik.valid_until.is_empty());
    assert_eq!(result.nik.label, "Test Node");
    assert!(!result.private_key_b64.is_empty(), "privateKeyB64 non-empty");

    // Two keys are different
    let r2 = generate_nik(Some(365), None);
    assert_ne!(result.nik.node_id, r2.nik.node_id, "unique nodeIds");
    assert_ne!(result.nik.public_key, r2.nik.public_key, "unique publicKeys");

    // Not expired
    assert!(!is_nik_expired(&result.nik), "not expired");

    println!("test_generate_nik: all checks passed");
}

#[test]
fn test_is_nik_expired() {
    use interplanet_ltx::{Nik, is_nik_expired};

    let past_nik = Nik {
        node_id: "x".into(), public_key: "y".into(), algorithm: "Ed25519".into(),
        valid_from: "2020-01-01T00:00:00Z".into(), valid_until: "2020-01-01T00:00:00Z".into(),
        key_version: 1, label: String::new(),
    };
    assert!(is_nik_expired(&past_nik), "past should be expired");

    let future_nik = Nik {
        node_id: "x".into(), public_key: "y".into(), algorithm: "Ed25519".into(),
        valid_from: "2099-01-01T00:00:00Z".into(), valid_until: "2099-01-01T00:00:00Z".into(),
        key_version: 1, label: String::new(),
    };
    assert!(!is_nik_expired(&future_nik), "future should not be expired");

    println!("test_is_nik_expired: all checks passed");
}

#[test]
fn test_sign_verify_plan() {
    use interplanet_ltx::{generate_nik, sign_plan, verify_plan, CjsonVal};
    use std::collections::{BTreeMap, HashMap};

    let nik_result = generate_nik(Some(365), None);

    // Build a plan as CjsonVal::Object
    let mut plan_map = BTreeMap::new();
    plan_map.insert("title".to_string(), CjsonVal::Str("LTX Session".into()));
    plan_map.insert("start".to_string(), CjsonVal::Str("2026-03-15T14:00:00Z".into()));
    plan_map.insert("quantum".to_string(), CjsonVal::Int(3));
    let plan = CjsonVal::Object(plan_map);

    // Sign
    let signed = sign_plan(plan.clone(), &nik_result.private_key_b64).expect("sign_plan failed");
    assert!(!signed.cose_sign1.protected.is_empty());
    assert!(!signed.cose_sign1.payload.is_empty());
    assert!(!signed.cose_sign1.signature.is_empty());
    let kid = signed.cose_sign1.unprotected.get("kid").expect("kid missing");
    assert_eq!(kid, &nik_result.nik.node_id, "kid must match nodeId");

    // Verify roundtrip
    let mut key_cache = HashMap::new();
    key_cache.insert(nik_result.nik.node_id.clone(), nik_result.nik.clone());
    let result = verify_plan(&signed, &key_cache);
    assert!(result.valid, "verify should pass: {}", result.reason);

    // Wrong key cache
    let empty_cache: HashMap<String, interplanet_ltx::Nik> = HashMap::new();
    let r2 = verify_plan(&signed, &empty_cache);
    assert!(!r2.valid);
    assert_eq!(r2.reason, "key_not_in_cache");

    // Tampered plan
    let mut tampered = signed.clone();
    let mut tampered_map = BTreeMap::new();
    tampered_map.insert("title".to_string(), CjsonVal::Str("TAMPERED".into()));
    tampered.plan = CjsonVal::Object(tampered_map);
    let r3 = verify_plan(&tampered, &key_cache);
    assert!(!r3.valid);
    assert_eq!(r3.reason, "payload_mismatch");

    // Expired key
    let mut expired_nik = nik_result.nik.clone();
    expired_nik.valid_until = "2020-01-01T00:00:00Z".to_string();
    let mut expired_cache = HashMap::new();
    expired_cache.insert(nik_result.nik.node_id.clone(), expired_nik);
    let r4 = verify_plan(&signed, &expired_cache);
    assert!(!r4.valid);
    assert_eq!(r4.reason, "key_expired");

    println!("test_sign_verify_plan: all checks passed");
}

#[test]
fn test_sequence_tracker() {
    use interplanet_ltx::{create_sequence_tracker, add_seq, check_seq, CjsonVal};
    use std::collections::BTreeMap;

    let mut tracker = create_sequence_tracker("plan-001");

    // AddSeq: first seq = 1
    let b1_map = {let mut m=BTreeMap::new(); m.insert("data".to_string(),CjsonVal::Str("hello".into())); CjsonVal::Object(m)};
    let b1 = add_seq(&b1_map, &mut tracker, "N0");
    match &b1 { CjsonVal::Object(m) => assert_eq!(m.get("seq"), Some(&CjsonVal::Int(1))), _ => panic!("not obj") }

    let b2 = add_seq(&b1_map, &mut tracker, "N0");
    match &b2 { CjsonVal::Object(m) => assert_eq!(m.get("seq"), Some(&CjsonVal::Int(2))), _ => panic!("not obj") }

    // Different nodeId has its own counter
    let b3 = add_seq(&b1_map, &mut tracker, "N1");
    match &b3 { CjsonVal::Object(m) => assert_eq!(m.get("seq"), Some(&CjsonVal::Int(1))), _ => panic!("not obj") }

    // CheckSeq: normal acceptance
    let in1 = {let mut m=BTreeMap::new(); m.insert("seq".to_string(),CjsonVal::Int(1)); CjsonVal::Object(m)};
    let c1 = check_seq(&in1, &mut tracker, "N0");
    assert!(c1.accepted); assert!(!c1.gap); assert_eq!(c1.gap_size, 0);

    // Replay
    let replay = check_seq(&in1, &mut tracker, "N0");
    assert!(!replay.accepted); assert_eq!(replay.reason, "replay");

    // Sequential
    let in2 = {let mut m=BTreeMap::new(); m.insert("seq".to_string(),CjsonVal::Int(2)); CjsonVal::Object(m)};
    let c2 = check_seq(&in2, &mut tracker, "N0");
    assert!(c2.accepted); assert!(!c2.gap);

    // Gap detected (seq=5, last=2, gap=2)
    let in5 = {let mut m=BTreeMap::new(); m.insert("seq".to_string(),CjsonVal::Int(5)); CjsonVal::Object(m)};
    let gap = check_seq(&in5, &mut tracker, "N0");
    assert!(gap.accepted); assert!(gap.gap); assert_eq!(gap.gap_size, 2);

    // Missing seq field
    let no_seq = {let mut m=BTreeMap::new(); m.insert("data".to_string(),CjsonVal::Str("x".into())); CjsonVal::Object(m)};
    let ms = check_seq(&no_seq, &mut tracker, "N0");
    assert!(!ms.accepted); assert_eq!(ms.reason, "missing_seq");

    println!("test_sequence_tracker: all checks passed");
}

