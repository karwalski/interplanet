// Parity tests mirroring javascript/ltx/tests/run.js (issue #27): golden
// planId vectors (spec/golden/plan-ids.json), validatePlan and the reserved
// streams / branching fields, reduce_decisions + merge_snapshot
// decisionRegister, and the sequence-tracker reorder window.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::rc::Rc;
use interplanet_ltx::*;

const GOLDEN: &str = include_str!("../../../spec/golden/plan-ids.json");

struct Checker { name: &'static str, passed: u32, failed: u32 }

impl Checker {
    fn new(name: &'static str) -> Self { Checker { name, passed: 0, failed: 0 } }
    fn check(&mut self, label: &str, ok: bool) {
        if ok { self.passed += 1; } else { self.failed += 1; println!("FAIL: {}", label); }
    }
    fn done(self) {
        println!("{}: {} passed {} failed", self.name, self.passed, self.failed);
        assert_eq!(self.failed, 0, "{} had failures", self.name);
    }
}

fn golden() -> Vec<JsonValue> {
    parse_ordered_json(GOLDEN).unwrap().get("vectors").unwrap().as_array().unwrap().to_vec()
}

fn by_name(vs: &[JsonValue], name: &str) -> JsonValue {
    vs.iter().find(|v| v.get("name").and_then(|x| x.as_str()) == Some(name)).unwrap().clone()
}

fn s(v: &JsonValue, k: &str) -> String { v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string() }

fn with_field(plan: &JsonValue, key: &str, value: JsonValue) -> JsonValue {
    let mut p = plan.clone();
    p.set(key, value);
    p
}

fn obj(members: &[(&str, JsonValue)]) -> JsonValue {
    JsonValue::Object(members.iter().map(|(k, v)| (k.to_string(), v.clone())).collect())
}

fn st(x: &str) -> JsonValue { JsonValue::Str(x.into()) }
fn num(x: f64) -> JsonValue { JsonValue::Number(x) }

#[test]
fn test_golden_plan_ids() {
    let mut c = Checker::new("test_golden_plan_ids");
    let vs = golden();
    c.check("golden vectors present", vs.len() >= 9);
    for v in &vs {
        let plan = v.get("plan").unwrap();
        let id = make_plan_id_from_value(plan);
        c.check(&format!("golden planId {} ({:?})", s(v, "name"), id), id.as_deref() == Ok(s(v, "planId").as_str()));
        if v.has("planHash") {
            c.check(&format!("golden planHash {}", s(v, "name")), plan_hash_from_value(plan) == s(v, "planHash"));
        }
        // Same result from the JSON text itself (key order preserved by the parser).
        let text = js_stringify(plan);
        c.check(&format!("golden planId from text {}", s(v, "name")), make_plan_id_from_json(&text).ok() == Some(s(v, "planId")));
    }
    c.check("golden v2 freeze anchor", s(&by_name(&vs, "v2-freeze-check"), "planId") == "LTX-20260801-EARTHHQ-MARS-v2-d132e85d");
    c.check("golden v2 unicode anchor", s(&by_name(&vs, "v2-unicode-title"), "planId") == "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8");
    c.check("golden v2 order-sensitive", s(&by_name(&vs, "v2-createPlan-default"), "planId") != s(&by_name(&vs, "v2-key-order-sensitive"), "planId"));
    c.check("golden v3 order-insensitive", s(&by_name(&vs, "v3-upgrade-delays"), "planId") == s(&by_name(&vs, "v3-key-order-insensitive"), "planId"));
    c.check("golden v3 amendment chain hash",
        s(by_name(&vs, "v3-amendment").get("plan").unwrap(), "prevPlanHash") == s(&by_name(&vs, "v3-upgrade-delays"), "planHash"));
    c.check("createPlan default quantum is 5", create_plan(None, "", 0).quantum == 5 && DEFAULT_QUANTUM == 5);

    // Typed LtxPlan serialises v2 in the fixed order v,title,start,quantum,
    // mode,nodes,segments: it matches the vectors that use that order.
    for name in ["v2-key-order-sensitive", "v2-conference-attributed", "v3-upgrade-delays", "v3-key-order-insensitive"] {
        let text = js_stringify(by_name(&vs, name).get("plan").unwrap());
        let typed = plan_from_cjson(&cjson_parse(&text).unwrap()).unwrap();
        c.check(&format!("typed make_plan_id {}", name), make_plan_id(&typed) == s(&by_name(&vs, name), "planId"));
    }
    // v2 hash over UTF-16 code units (expected from ltx-sdk.js on the unicode
    // vector in typed key order).
    let uni = plan_from_cjson(&cjson_parse(&js_stringify(by_name(&vs, "v2-unicode-title").get("plan").unwrap())).unwrap()).unwrap();
    c.check("typed make_plan_id hashes UTF-16", make_plan_id(&uni) == "LTX-20261231-EARTHHQ-MARS-v2-06a7c14c");
    // A quote in the title is escaped (JSON.stringify) before hashing.
    let mut quoted = create_plan(Some("Say \"hi\"\n"), "2026-03-15T14:00:00.000Z", 840);
    quoted.segments = default_segments();
    let quoted_json = format!(
        "{{\"v\":2,\"title\":{},\"start\":\"2026-03-15T14:00:00.000Z\",\"quantum\":5,\"mode\":\"LTX\",\"nodes\":[{{\"id\":\"N0\",\"name\":\"Earth HQ\",\"role\":\"HOST\",\"delay\":0,\"location\":\"earth\"}},{{\"id\":\"N1\",\"name\":\"Mars Hab-01\",\"role\":\"PARTICIPANT\",\"delay\":840,\"location\":\"mars\"}}],\"segments\":[{{\"type\":\"PLAN_CONFIRM\",\"q\":2}},{{\"type\":\"TX\",\"q\":2}},{{\"type\":\"RX\",\"q\":2}},{{\"type\":\"CAUCUS\",\"q\":2}},{{\"type\":\"TX\",\"q\":2}},{{\"type\":\"RX\",\"q\":2}},{{\"type\":\"BUFFER\",\"q\":1}}]}}",
        js_quote("Say \"hi\"\n"));
    c.check("typed make_plan_id escapes quotes", make_plan_id(&quoted) == make_plan_id_from_json(&quoted_json).unwrap());
    c.check("js_number forms", js_number(1e21) == "1e+21" && js_number(1e-7) == "1e-7" && js_number(0.5) == "0.5" && js_number(860.0) == "860");
    let mut m = BTreeMap::new();
    m.insert("\u{1F680}".to_string(), CjsonVal::Int(1));
    m.insert("\u{FF21}".to_string(), CjsonVal::Int(2));
    c.check("canonical UTF-16 key order", canonical_json(&CjsonVal::Object(m)) == "{\"\u{1F680}\":1,\"\u{FF21}\":2}");
    c.done();
}

const PREFIX_GOLDEN: &str = include_str!("../../../spec/golden/plan-id-prefixes.json");

// spec/golden/plan-id-prefixes.json (issue #37): Unicode upper-casing and
// UTF-16 slicing of HOSTSTR / NODESTR. A Rust String cannot hold the lone
// surrogate a cut can leave, so the expected id is planIdUtf8 (U+FFFD).
#[test]
fn test_golden_plan_id_prefixes() {
    let mut c = Checker::new("test_golden_plan_id_prefixes");
    let vs = parse_ordered_json(PREFIX_GOLDEN).unwrap().get("vectors").unwrap().as_array().unwrap().to_vec();
    c.check("prefix vectors present", vs.len() >= 18);
    for v in &vs {
        let name = s(v, "name");
        let want = s(v, "planIdUtf8");
        let plan = v.get("plan").unwrap();
        let id = make_plan_id_from_value(plan);
        c.check(&format!("prefix planId {} ({:?})", name, id), id.as_deref() == Ok(want.as_str()));
        let text = js_stringify(plan);
        c.check(&format!("prefix planId from text {}", name), make_plan_id_from_json(&text).ok() == Some(want.clone()));
        // Typed LtxPlan: same prefix (its key order and fields may differ).
        let typed = plan_from_cjson(&cjson_parse(&text).unwrap()).unwrap();
        let tid = make_plan_id(&typed);
        let cut = |x: &str| x[..x.len() - 12].to_string();
        c.check(&format!("prefix typed make_plan_id {} ({})", name, tid), cut(&tid) == cut(&want));
    }
    c.done();
}

#[test]
fn test_validate_plan_reserved() {
    let mut c = Checker::new("test_validate_plan_reserved");
    let vs = golden();
    for v in &vs {
        c.check(&format!("validatePlan accepts golden {}", s(v, "name")), validate_plan(v.get("plan").unwrap()).valid);
    }
    let base = by_name(&vs, "v3-upgrade-delays").get("plan").unwrap().clone();
    let v2 = by_name(&vs, "v2-freeze-check").get("plan").unwrap().clone();

    c.check("validatePlan v3 empty streams ok", validate_plan(&with_field(&base, "streams", JsonValue::Array(vec![]))).valid);
    let vs1 = validate_plan(&with_field(&base, "streams", JsonValue::Array(vec![obj(&[("id", st("S1"))])])));
    c.check("validatePlan non-empty streams", !vs1.valid && vs1.has_code("reserved_streams"));
    c.check("validatePlan streams error path", vs1.errors.iter().find(|e| e.code == "reserved_streams").map(|e| e.path.as_str()) == Some("streams"));
    c.check("validatePlan streams non-array", validate_plan(&with_field(&base, "streams", st("S1"))).has_code("reserved_streams"));
    c.check("validatePlan segment stream", validate_plan(&with_field(&base, "segments",
        JsonValue::Array(vec![obj(&[("type", st("TX")), ("q", num(1.0)), ("stream", st("S1"))])]))).has_code("reserved_streams"));
    c.check("validatePlan branches", validate_plan(&with_field(&base, "branches", JsonValue::Array(vec![]))).has_code("reserved_branching"));
    c.check("validatePlan branching", validate_plan(&with_field(&base, "branching", obj(&[("mode", st("local"))]))).has_code("reserved_branching"));
    let vb = validate_plan(&with_field(&base, "segments",
        JsonValue::Array(vec![obj(&[("type", st("CAUCUS")), ("q", num(1.0)), ("branch", st("B1"))])])));
    c.check("validatePlan segment branch", vb.has_code("reserved_branching") && vb.errors[0].path == "segments[0].branch");
    c.check("validatePlan v2 streams is v3 field", validate_plan(&with_field(&v2, "streams", JsonValue::Array(vec![]))).has_code("v3_field_in_v2"));
    c.check("validatePlan v2 branching", validate_plan(&with_field(&v2, "branching", JsonValue::Bool(true))).has_code("reserved_branching"));

    c.check("validatePlan non-object", validate_plan(&JsonValue::Null).has_code("not_an_object"));
    c.check("validatePlan bad version", validate_plan(&with_field(&v2, "v", num(7.0))).has_code("invalid_version"));
    let nodes = v2.get("nodes").unwrap().as_array().unwrap().to_vec();
    c.check("validatePlan host not first", validate_plan(&with_field(&v2, "nodes", JsonValue::Array(vec![nodes[1].clone(), nodes[0].clone()]))).has_code("invalid_host"));
    c.check("validatePlan unsorted delays key", validate_plan(&with_field(&base, "delays", obj(&[("N1|N0", num(860.0))]))).has_code("invalid_delays"));
    c.check("validatePlan unknown speaker", validate_plan(&with_field(&v2, "segments",
        JsonValue::Array(vec![obj(&[("type", st("TX")), ("q", num(1.0)), ("speaker", st("N9"))])]))).has_code("unknown_speaker"));
    c.check("validatePlan quantum out of range", validate_plan(&with_field(&v2, "quantum", num(0.0))).has_code("invalid_quantum"));
    c.check("validate_plan_json bad JSON", validate_plan_json("{").has_code("not_an_object"));

    // Enforcement paths
    let nik = generate_nik(None, Some("Earth HQ"));
    let base_cjson = cjson_parse(&js_stringify(&base)).unwrap();
    let signed = sign_plan(base_cjson, &nik.private_key_b64).unwrap();
    let mut ch = BTreeMap::new();
    ch.insert("branching".to_string(), CjsonVal::Object(BTreeMap::new()));
    let r = create_amendment(&signed, &ch, &nik.private_key_b64);
    c.check("createAmendment rejects branching", matches!(&r, Err(e) if e.starts_with("reserved_branching")));
    let mut ch = BTreeMap::new();
    ch.insert("streams".to_string(), CjsonVal::Array(vec![CjsonVal::Str("S1".into())]));
    let r = create_amendment(&signed, &ch, &nik.private_key_b64);
    c.check("createAmendment rejects streams", matches!(&r, Err(e) if e.starts_with("reserved_streams")));
    let mut ch = BTreeMap::new();
    ch.insert("title".to_string(), CjsonVal::Str("x".into()));
    ch.insert("streams".to_string(), CjsonVal::Array(vec![]));
    c.check("createAmendment ok without", create_amendment(&signed, &ch, &nik.private_key_b64).is_ok());
    let bad = js_stringify(&with_field(&base, "streams", JsonValue::Array(vec![num(1.0)])));
    let r = create_session_from_json(&bad, "id", QuorumOption::All);
    c.check("createSession rejects streams", matches!(&r, Err(e) if e.code == "reserved_streams"));
    let r = create_session_from_json(&js_stringify(&base), "id", QuorumOption::All);
    c.check("createSession accepts golden", matches!(&r, Ok(ctx) if ctx.plan.nodes.len() == 4 && ctx.state == SessionPhase::Draft));
    c.done();
}

fn mk(kind: &str, content: &[(&str, CjsonVal)], node: &str, seq: i64, ts: &str, priv_key: &str, entry_id: Option<&str>) -> RegisterEntry {
    let mut m = BTreeMap::new();
    for (k, v) in content { m.insert(k.to_string(), v.clone()); }
    create_register_entry(kind, CjsonVal::Object(m), &CreateEntryOptions {
        session_id: "LTX-DEC-TEST".into(), node_id: node.into(), seq, timestamp: ts.into(),
        private_key_b64: priv_key.into(), entry_id: entry_id.map(|x| x.to_string()),
    }).unwrap()
}

fn cs(x: &str) -> CjsonVal { CjsonVal::Str(x.into()) }

#[test]
fn test_reduce_decisions() {
    let mut c = Checker::new("test_reduce_decisions");
    let host = generate_nik(None, Some("HOST"));
    let mars = generate_nik(None, Some("MARS"));
    let mut cache = HashMap::new();
    cache.insert("N0".to_string(), host.nik.clone());
    cache.insert("N1".to_string(), mars.nik.clone());
    let hp = host.private_key_b64.clone();
    let mp = mars.private_key_b64.clone();

    let dec1 = mk("decision", &[("text", cs("Proceed with EVA-3")), ("rationale", cs("Weather window")), ("originWindow", cs("W2"))],
        "N0", 1, "2026-08-01T12:00:00.000Z", &hp, None);
    c.check("decision id prefix DEC", dec1.entry_id == "DEC-N0-1");
    c.check("decision entry verifies", verify_register_entry(&dec1, &cache).valid);
    let (r1, _) = reduce_decisions(&[dec1.clone()]);
    let d = &r1["DEC-N0-1"];
    c.check("decision RECORDED", d.status == "RECORDED" && d.version == 1);
    c.check("decision fields", d.text == "Proceed with EVA-3" && d.recorded_by == "N0"
        && d.rationale.as_deref() == Some("Weather window") && d.origin_window.as_deref() == Some("W2") && d.editor.is_none());

    let dec_rev = mk("decision_update", &[("did", cs("DEC-N0-1")), ("text", cs("Proceed with EVA-3 at 14:00")), ("version", CjsonVal::Int(2))],
        "N1", 1, "2026-08-01T12:10:00.000Z", &mp, None);
    c.check("decision_update id prefix DEC", dec_rev.entry_id == "DEC-N1-1");
    let dec_res = mk("decision_update", &[("did", cs("DEC-N0-1")), ("status", cs("RESCINDED")), ("version", CjsonVal::Int(3))],
        "N0", 2, "2026-08-01T12:20:00.000Z", &hp, None);
    let (r2, sup2) = reduce_decisions(&[dec_res.clone(), dec1.clone(), dec_rev.clone()]);
    let d = &r2["DEC-N0-1"];
    c.check("decision update applied", d.text == "Proceed with EVA-3 at 14:00");
    c.check("decision RESCINDED v3", d.status == "RESCINDED" && d.version == 3);
    c.check("decision editor recorded", d.editor.as_deref() == Some("N0"));
    c.check("decision older update superseded", sup2.contains(&dec_rev.entry_id));

    let dec_a = mk("decision_update", &[("did", cs("DEC-N0-1")), ("text", cs("From N0")), ("version", CjsonVal::Int(5))], "N0", 7, "2026-08-01T13:00:00.000Z", &hp, None);
    let dec_b = mk("decision_update", &[("did", cs("DEC-N0-1")), ("text", cs("From N1")), ("version", CjsonVal::Int(5))], "N1", 7, "2026-08-01T13:00:00.000Z", &mp, None);
    let (c1, s1) = reduce_decisions(&[dec1.clone(), dec_b.clone(), dec_a.clone()]);
    let (c2, s2) = reduce_decisions(&[dec_a.clone(), dec1.clone(), dec_b.clone()]);
    c.check("decision tie lowest nodeId wins", c1["DEC-N0-1"].text == "From N0");
    c.check("decision tie loser superseded", s1.contains(&dec_b.entry_id) && !s1.contains(&dec_a.entry_id));
    c.check("decision reduce order-independent", c1 == c2 && s1 == s2);
    let dec_hi = mk("decision_update", &[("did", cs("DEC-N0-1")), ("text", cs("N1 v6")), ("version", CjsonVal::Int(6))], "N1", 8, "2026-08-01T12:30:00.000Z", &mp, None);
    c.check("decision higher version wins", reduce_decisions(&[dec1.clone(), dec_a.clone(), dec_hi]).0["DEC-N0-1"].text == "N1 v6");

    let orphan = mk("decision_update", &[("did", cs("DEC-NOPE-1")), ("version", CjsonVal::Int(2))], "N1", 9, "2026-08-01T12:40:00.000Z", &mp, None);
    let dup = mk("decision", &[("text", cs("dup"))], "N1", 10, "2026-08-01T12:50:00.000Z", &mp, Some("DEC-N0-1"));
    let (r3, sup3) = reduce_decisions(&[dec1.clone(), orphan, dup]);
    c.check("decision orphan update superseded", sup3.contains(&"DEC-N1-9".to_string()));
    c.check("decision duplicate create ignored", r3["DEC-N0-1"].text == "Proceed with EVA-3" && r3["DEC-N0-1"].recorded_by == "N0");
    c.check("decision reducer ignores others", reduce_decisions(&[dec1.clone(), dec_rev.clone()]).0.len() == 1
        && reduce_actions(&[dec1.clone()]).0.is_empty());

    let opts = CreateEntryOptions {
        session_id: "LTX-DEC-TEST".into(), node_id: "N0".into(), seq: 99,
        timestamp: "2026-08-01T15:00:00.000Z".into(), private_key_b64: hp.clone(), entry_id: None,
    };
    let (merged, snap) = run_merge_segment(&[dec1.clone()], &[dec_rev.clone()], &cache, &opts).unwrap();
    c.check("runMergeSegment ok", merged.entries.len() == 2 && merged.rejected.is_empty());
    c.check("snapshot is merge_snapshot MRG", snap.entry_type == "merge_snapshot" && snap.entry_id == "MRG-N0-99");
    c.check("snapshot verifies", verify_register_entry(&snap, &cache).valid);
    let reg = snap.content.get("decisionRegister").and_then(|r| r.get("DEC-N0-1")).cloned().unwrap_or(CjsonVal::Null);
    c.check("snapshot decisionRegister", reg.get("version").and_then(|v| v.as_i64()) == Some(2)
        && reg.get("text").and_then(|v| v.as_str()) == Some("Proceed with EVA-3 at 14:00")
        && reg.get("editor").and_then(|v| v.as_str()) == Some("N1"));
    c.check("snapshot has question/action registers", snap.content.get("questionRegister").is_some() && snap.content.get("actionRegister").is_some());
    c.check("snapshot counts", snap.content.get("entryCount").and_then(|v| v.as_i64()) == Some(2)
        && snap.content.get("rejectedCount").and_then(|v| v.as_i64()) == Some(0));
    c.check("snapshot mergedRoot", snap.content.get("mergedRoot").and_then(|v| v.as_str()) == Some(entries_root(&merged.entries).as_str()));
    let stranger = generate_nik(None, None);
    let stray = mk("decision", &[("text", cs("stray"))], "N7", 1, "2026-08-01T12:00:00.000Z", &stranger.private_key_b64, None);
    let opts2 = CreateEntryOptions { seq: 100, ..opts };
    let (m2, snap2) = run_merge_segment(&[dec1.clone(), stray], &[], &cache, &opts2).unwrap();
    c.check("merge rejects unverifiable entry", m2.rejected.len() == 1 && m2.rejected[0].1 == "key_not_in_cache"
        && snap2.content.get("rejectedCount").and_then(|v| v.as_i64()) == Some(1));
    let ab = merge_logs(&[dec1.clone()], &[dec_rev.clone(), dec1.clone()], &cache);
    let ba = merge_logs(&[dec_rev.clone(), dec1.clone()], &[dec1.clone()], &cache);
    let ids = |m: &MergeResult| m.entries.iter().map(|e| e.entry_id.clone()).collect::<Vec<_>>();
    c.check("mergeLogs symmetric and de-duplicated", ab.entries.len() == 2 && ids(&ab) == ids(&ba));
    c.done();
}

#[test]
fn test_sequence_reorder_window() {
    let mut c = Checker::new("test_sequence_reorder_window");
    let mut tr = create_sequence_tracker("plan-001");
    tr.next_seq("N0");
    tr.next_seq("N0");
    tr.record_seq("N0", 1);
    tr.record_seq("N0", 2);
    let gap = tr.record_seq("N0", 5);
    c.check("gap detected", gap.accepted && gap.gap && gap.gap_size == 2 && !gap.late);
    tr.record_seq("N0", 6);
    c.check("lastSeenSeq correct", tr.last_seen_seq("N0") == 6);
    c.check("currentSeq correct", tr.current_seq("N0") == 2);
    c.check("missingSeqs lists gap", tr.missing_seqs("N0") == vec![3, 4]);
    let late4 = tr.record_seq("N0", 4);
    c.check("late seq accepted", late4.accepted && late4.late);
    c.check("late seq no gap, no reason", !late4.gap && late4.gap_size == 0 && late4.reason.is_empty());
    c.check("late seq keeps high-water mark", tr.last_seen_seq("N0") == 6);
    let dup4 = tr.record_seq("N0", 4);
    c.check("late seq duplicate is replay", !dup4.accepted && dup4.reason == "replay" && !dup4.late);
    c.check("in-order result late=false", !tr.record_seq("N0", 7).late);
    c.check("duplicate of in-order is replay", tr.record_seq("N0", 6).reason == "replay");
    c.check("missingSeqs after late", tr.missing_seqs("N0") == vec![3]);
    c.check("unsafe seq is invalid_seq", tr.record_seq("N0", 1i64 << 53).reason == "invalid_seq");
    let mut b = BTreeMap::new();
    b.insert("seq".to_string(), CjsonVal::Str("8".into()));
    c.check("non-integer seq is missing_seq", check_seq(&CjsonVal::Object(b), &mut tr, "N0").reason == "missing_seq");
    c.check("default reorder window", SEQ_REORDER_WINDOW == 64 && tr.reorder_window() == 64);

    let mut tw = create_sequence_tracker_with("plan-window", Box::new(MemorySeqStore::default()), Some(4)).unwrap();
    tw.record_seq("N1", 1);
    let big = tw.record_seq("N1", 10);
    c.check("window gap reported in full", big.gap && big.gap_size == 8);
    c.check("window bounds missing markers", tw.missing_seqs("N1") == vec![7, 8, 9]);
    c.check("below window rejected", tw.record_seq("N1", 5).reason == "replay");
    c.check("inside window accepted late", tw.record_seq("N1", 8).late);
    tw.record_seq("N1", 12);
    c.check("slid-out marker rejected", !tw.record_seq("N1", 7).accepted);
    c.check("slid-in gap accepted late", tw.record_seq("N1", 11).late);
    let mut t0 = create_sequence_tracker_with("plan-strict", Box::new(MemorySeqStore::default()), Some(0)).unwrap();
    t0.record_seq("N0", 1);
    t0.record_seq("N0", 3);
    c.check("window 0 = strict monotonic", t0.record_seq("N0", 2).reason == "replay");
    c.check("negative window errors", create_sequence_tracker_with("p", Box::new(MemorySeqStore::default()), Some(-1)).is_err());

    let persisted: Rc<RefCell<HashMap<String, i64>>> = Rc::new(RefCell::new(HashMap::new()));
    let mut ta = create_sequence_tracker_with("plan-persist", Box::new(persisted.clone()), None).unwrap();
    ta.record_seq("N2", 1);
    ta.record_seq("N2", 4);
    let mut tb = create_sequence_tracker_with("plan-persist", Box::new(persisted.clone()), None).unwrap();
    c.check("persisted late accepted", tb.record_seq("N2", 3).late);
    c.check("persisted late not replayable", tb.record_seq("N2", 3).reason == "replay");
    c.check("persisted replay rejected", tb.record_seq("N2", 4).reason == "replay");
    let p = persisted.borrow();
    c.check("storage key layout", p.get("ltx_seq_plan-persist_N2_rx") == Some(&4)
        && p.get("ltx_seq_plan-persist_N2_rx_miss_2") == Some(&1)
        && p.get("ltx_seq_plan-persist_N2_rx_miss_3") == Some(&0));
    c.done();
}

/// The #l= wire JSON of a typed v3 plan carries its v3 fields, so a receiver
/// hashing the wire JSON (JS makePlanId) derives the same planId as
/// make_plan_id (scripts/interop, issue #32).
#[test]
fn test_encode_hash_v3_wire_matches_plan_id() {
    use base64::Engine;
    let wire_of = |p: &LtxPlan| String::from_utf8(base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(encode_hash(p).trim_start_matches("#l=")).unwrap()).unwrap();
    let mut p = create_plan(Some("Réunion Mars 🚀"), "2026-03-15T14:00:00.000Z", 840);
    p.v = 3;
    p.plan_version = Some(1);
    p.delays = Some(BTreeMap::from([("N0|N1".to_string(), 842)]));
    let wire = wire_of(&p);
    assert!(wire.contains(r#""delays":{"N0|N1":842}"#) && wire.contains(r#""planVersion":1"#), "{}", wire);
    // JS makePlanId(JSON.parse(wire)) for this plan.
    let want = "LTX-20260315-EARTHHQ-MARS-v3-4192925c";
    assert_eq!(make_plan_id(&p), want);
    assert_eq!(make_plan_id_from_json(&wire).unwrap(), want);
    // v2 wire JSON is unchanged: no v3 keys.
    p.v = 2; p.plan_version = None; p.delays = None;
    let w2 = wire_of(&p);
    assert!(!w2.contains("delays") && !w2.contains("planVersion"), "{}", w2);
}
