// LTX v1.1 core subset conformance tests (Epic 72, Story 72.2).
// Golden vectors: tests/v11.json (copy of conformance/vectors.json .v11).

use std::collections::{BTreeMap, HashMap};
use interplanet_ltx::*;

const V11_JSON: &str = include_str!("v11.json");

fn vectors() -> CjsonVal {
    cjson_parse(V11_JSON).expect("parse v11.json")
}

fn vector_nik(v: &CjsonVal) -> Nik {
    let nik = v.get("key").unwrap().get("nik").unwrap();
    let s = |k: &str| nik.get(k).unwrap().as_str().unwrap().to_string();
    Nik {
        node_id: s("nodeId"),
        public_key: s("publicKey"),
        algorithm: s("algorithm"),
        valid_from: s("validFrom"),
        valid_until: s("validUntil"),
        key_version: nik.get("keyVersion").unwrap().as_i64().unwrap() as u32,
        label: String::new(),
    }
}

fn key_cache(v: &CjsonVal, extra_ids: &[&str]) -> HashMap<String, Nik> {
    let nik = vector_nik(v);
    let mut cache = HashMap::new();
    cache.insert(nik.node_id.clone(), nik.clone());
    for id in extra_ids {
        cache.insert(id.to_string(), nik.clone());
    }
    cache
}

fn signed_plan_from_cjson(link: &CjsonVal) -> SignedPlan {
    let cose = link.get("coseSign1").unwrap();
    let mut unprotected = HashMap::new();
    if let Some(u) = cose.get("unprotected").and_then(|x| x.as_object()) {
        for (k, val) in u {
            unprotected.insert(k.clone(), val.as_str().unwrap().to_string());
        }
    }
    SignedPlan {
        plan: link.get("plan").unwrap().clone(),
        cose_sign1: CoseSign1Env {
            protected: cose.get("protected").unwrap().as_str().unwrap().into(),
            unprotected,
            payload: cose.get("payload").unwrap().as_str().unwrap().into(),
            signature: cose.get("signature").unwrap().as_str().unwrap().into(),
        },
    }
}

fn register_entries(v: &CjsonVal) -> Vec<RegisterEntry> {
    v.get("registerEntries").unwrap().get("entries").unwrap()
        .as_array().unwrap().iter()
        .map(|e| register_entry_from_cjson(e).expect("parse entry"))
        .collect()
}

// ── Feature 1: v3 planId + pairDelay + computeSegmentsFor ─────────────────

#[test]
fn test_v11_plan_id_v3() {
    let v = vectors();
    let sect = v.get("planIdV3").unwrap();
    let plan_cjson = sect.get("plan").unwrap();
    let plan = plan_from_cjson(plan_cjson).unwrap();

    assert_eq!(canonical_json(&plan_to_cjson(&plan)),
               sect.get("canonicalJson").unwrap().as_str().unwrap());
    assert_eq!(canonical_json(plan_cjson),
               sect.get("canonicalJson").unwrap().as_str().unwrap());
    assert_eq!(plan_hash(plan_cjson), sect.get("sha256").unwrap().as_str().unwrap());
    assert_eq!(make_plan_id(&plan), sect.get("expectedPlanId").unwrap().as_str().unwrap());
}

#[test]
fn test_v11_plan_id_v2_regression() {
    // FROZEN v2 polynomial hash — if this breaks the v2 hash changed: STOP.
    let v = vectors();
    let sect = v.get("planIdV2Regression").unwrap();
    let plan = plan_from_cjson(sect.get("plan").unwrap()).unwrap();
    assert_eq!(make_plan_id(&plan), sect.get("expectedPlanId").unwrap().as_str().unwrap());
}

#[test]
fn test_v11_pair_delay() {
    let v = vectors();
    let sect = v.get("pairDelay").unwrap();
    let plan = plan_from_cjson(sect.get("plan").unwrap()).unwrap();
    for case in sect.get("cases").unwrap().as_array().unwrap() {
        let a = case.get("a").unwrap().as_str().unwrap();
        let b = case.get("b").unwrap().as_str().unwrap();
        let expected = case.get("expected").unwrap().as_i64().unwrap();
        assert_eq!(pair_delay(&plan, a, b).unwrap(), expected, "pair_delay({},{})", a, b);
    }
    let fc = sect.get("fallbackCase").unwrap();
    let fplan = plan_from_cjson(fc.get("plan").unwrap()).unwrap();
    assert_eq!(
        pair_delay(&fplan,
                   fc.get("a").unwrap().as_str().unwrap(),
                   fc.get("b").unwrap().as_str().unwrap()).unwrap(),
        fc.get("expected").unwrap().as_i64().unwrap()
    );
    assert!(pair_delay(&plan, "N0", "NX").is_err(), "unknown node must error");
}

#[test]
fn test_v11_compute_segments_for() {
    let v = vectors();
    let plan = plan_from_cjson(v.get("pairDelay").unwrap().get("plan").unwrap()).unwrap();
    let base = compute_segments(&plan).unwrap();

    // Viewer N2: seg1 (TX by N0) shifts 2 s; seg2 (TX by N1) shifts 500 s (v3 matrix).
    let segs_n2 = compute_segments_for(&plan, "N2").unwrap();
    assert_eq!(segs_n2.len(), base.len());
    assert_eq!(segs_n2[0].perspective, "neutral");
    assert_eq!(segs_n2[0].arrival_offset_s, 0);
    assert_eq!(segs_n2[1].perspective, "receive");
    assert_eq!(segs_n2[1].arrival_offset_s, 2);
    assert_eq!(segs_n2[1].start_ms, base[1].start_ms + 2000);
    assert_eq!(segs_n2[1].end_ms, base[1].end_ms + 2000);
    assert_eq!(segs_n2[1].speaker.as_deref(), Some("N0"));
    assert_eq!(segs_n2[1].label.as_deref(), Some("Opening"));
    assert_eq!(segs_n2[2].perspective, "receive");
    assert_eq!(segs_n2[2].arrival_offset_s, 500);
    assert_eq!(segs_n2[2].start_ms, base[2].start_ms + 500_000);

    // Viewer N1: transmits seg2, receives seg1 after 900 s.
    let segs_n1 = compute_segments_for(&plan, "N1").unwrap();
    assert_eq!(segs_n1[2].perspective, "transmit");
    assert_eq!(segs_n1[2].arrival_offset_s, 0);
    assert_eq!(segs_n1[2].start_ms, base[2].start_ms);
    assert_eq!(segs_n1[1].perspective, "receive");
    assert_eq!(segs_n1[1].arrival_offset_s, 900);

    assert!(compute_segments_for(&plan, "NX").is_err(), "unknown viewer must error");
}

// ── Feature 2: session state machine golden transition table ──────────────

#[test]
fn test_v11_state_machine() {
    let v = vectors();
    let sect = v.get("stateMachine").unwrap();
    let plan = plan_from_cjson(sect.get("plan").unwrap()).unwrap();
    let plan_id = sect.get("planId").unwrap().as_str().unwrap();
    assert_eq!(make_plan_id(&plan), plan_id);

    let quorum = sect.get("quorum").unwrap().as_i64().unwrap() as usize;
    let mut ctx = create_session(&plan, plan_id, QuorumOption::Count(quorum));
    assert_eq!(ctx.state.as_str(), "DRAFT");
    assert_eq!(ctx.lock_timeout_ms, 1_800_000);

    for (i, step) in sect.get("steps").unwrap().as_array().unwrap().iter().enumerate() {
        let ev = step.get("event").unwrap();
        let ev_type = ev.get("type").unwrap().as_str().unwrap();
        let now_ms = ev.get("nowMs").unwrap().as_i64().unwrap();
        let event = match ev_type {
            "START_LOCK"    => SessionEvent::StartLock { now_ms },
            "TICK"          => SessionEvent::Tick { now_ms },
            "SESSION_START" => SessionEvent::SessionStart { now_ms },
            "SESSION_END"   => SessionEvent::SessionEnd { now_ms },
            "PLAN_CONFIRM"  => SessionEvent::PlanConfirm {
                now_ms,
                node_id: ev.get("nodeId").unwrap().as_str().unwrap().into(),
                plan_id: ev.get("planId").unwrap().as_str().unwrap().into(),
            },
            "DELAY_MEASURED" => SessionEvent::DelayMeasured {
                now_ms,
                node_id: ev.get("nodeId").unwrap().as_str().unwrap().into(),
                measured_delay_s: ev.get("measuredDelayS").unwrap().as_i64().unwrap() as f64,
            },
            "HOST_DECISION" => SessionEvent::HostDecision {
                now_ms,
                decision: ev.get("decision").unwrap().as_str().unwrap().into(),
            },
            other => panic!("unhandled event type {}", other),
        };
        let (next, _effects) = transition(&ctx, &event);
        ctx = next;
        let expect_state = step.get("expectState").unwrap().as_str().unwrap();
        assert_eq!(ctx.state.as_str(), expect_state, "step {} ({}) state", i, ev_type);
        let got_lock = ctx.lock.map(|l| l.as_str());
        match step.get("expectLock").unwrap() {
            CjsonVal::Null => assert_eq!(got_lock, None, "step {} ({}) lock", i, ev_type),
            other => assert_eq!(got_lock, other.as_str(), "step {} ({}) lock", i, ev_type),
        }
    }
}

// ── Feature 3: amendment-chain verification ────────────────────────────────

#[test]
fn test_v11_amendment_chain() {
    let v = vectors();
    let sect = v.get("amendmentChain").unwrap();
    let cache = key_cache(&v, &[]);
    let chain: Vec<SignedPlan> = sect.get("chain").unwrap().as_array().unwrap()
        .iter().map(signed_plan_from_cjson).collect();

    assert_eq!(plan_hash(&chain[0].plan),
               sect.get("rootPlanHash").unwrap().as_str().unwrap());

    let res = verify_amendment_chain(&chain, &cache);
    assert!(res.valid == sect.get("expectedValid").unwrap().as_bool().unwrap(),
            "chain verify: {}", res.reason);

    // Tamper the golden field on link 1 → chain must fail.
    let tamper_field = sect.get("tamperField").unwrap().as_str().unwrap();
    let mut tampered = chain.clone();
    if let CjsonVal::Object(m) = &mut tampered[1].plan {
        m.insert(tamper_field.into(), CjsonVal::Str("TAMPERED".into()));
    }
    assert!(!verify_amendment_chain(&tampered, &cache).valid, "tampered chain must fail");

    // Empty chain rejected.
    let empty = verify_amendment_chain(&[], &cache);
    assert!(!empty.valid);
    assert_eq!(empty.reason, "empty_chain");

    // create_amendment round-trip with a fresh key.
    let gen = generate_nik(Some(30), None);
    let mut root = BTreeMap::new();
    root.insert("v".to_string(), CjsonVal::Int(2));
    root.insert("title".to_string(), CjsonVal::Str("Root".into()));
    root.insert("start".to_string(), CjsonVal::Str("2040-02-01T12:00:00.000Z".into()));
    let signed_root = sign_plan(CjsonVal::Object(root), &gen.private_key_b64).unwrap();
    let mut changes = BTreeMap::new();
    changes.insert("title".to_string(), CjsonVal::Str("Root (amended)".into()));
    let amended = create_amendment(&signed_root, &changes, &gen.private_key_b64).unwrap();
    let mut cache2 = HashMap::new();
    cache2.insert(gen.nik.node_id.clone(), gen.nik.clone());
    let res2 = verify_amendment_chain(&[signed_root, amended], &cache2);
    assert!(res2.valid, "createAmendment chain: {}", res2.reason);
}

// ── Feature 4: register entries + reducers + entriesRoot ──────────────────

#[test]
fn test_v11_register_entries() {
    let v = vectors();
    let sect = v.get("registerEntries").unwrap();
    let cache = key_cache(&v, &["N0", "N1"]);
    let entries = register_entries(&v);

    for e in &entries {
        let res = verify_register_entry(e, &cache);
        assert!(res.valid, "entry {} should verify: {}", e.entry_id, res.reason);
        let mut tampered = e.clone();
        tampered.timestamp = "2041-01-01T00:00:00.000Z".into();
        assert!(!verify_register_entry(&tampered, &cache).valid,
                "tampered entry {} must fail", e.entry_id);
    }

    let (by_id, superseded) = reduce_questions(&entries);
    assert!(superseded.is_empty(), "no entries should be superseded");
    let expected = sect.get("expectedQuestionState").unwrap().as_object().unwrap();
    for (qid, want) in expected {
        let got = by_id.get(qid).unwrap_or_else(|| panic!("missing question {}", qid));
        assert_eq!(got.qid, want.get("qid").unwrap().as_str().unwrap());
        assert_eq!(got.text, want.get("text").unwrap().as_str().unwrap());
        assert_eq!(got.submitter, want.get("submitter").unwrap().as_str().unwrap());
        assert_eq!(got.urgency.as_deref(), want.get("urgency").and_then(|x| x.as_str()));
        assert_eq!(got.status, want.get("status").unwrap().as_str().unwrap());
        assert_eq!(got.version, want.get("version").unwrap().as_i64().unwrap());
        assert_eq!(got.response.as_deref(), want.get("response").and_then(|x| x.as_str()));
        assert_eq!(got.responder.as_deref(), want.get("responder").and_then(|x| x.as_str()));
    }

    // entriesRoot is deterministic regardless of input order.
    let expected_root = sect.get("entriesRoot").unwrap().as_str().unwrap();
    assert_eq!(entries_root(&entries), expected_root);
    let reversed: Vec<RegisterEntry> = entries.iter().rev().cloned().collect();
    assert_eq!(entries_root(&reversed), expected_root);

    // Round-trip: create + verify a fresh entry with the vector seed;
    // deterministic Ed25519 must reproduce the golden signature.
    let seed = v.get("key").unwrap().get("privateSeedB64").unwrap().as_str().unwrap();
    let mut content = BTreeMap::new();
    content.insert("text".to_string(), CjsonVal::Str("Status?".into()));
    content.insert("urgency".to_string(), CjsonVal::Str("high".into()));
    let entry = create_register_entry("question", CjsonVal::Object(content), &CreateEntryOptions {
        session_id: "VEC-SESSION".into(),
        node_id: "N1".into(),
        seq: 1,
        timestamp: "2040-02-01T11:00:00.000Z".into(),
        private_key_b64: seed.into(),
        entry_id: None,
    }).unwrap();
    assert_eq!(entry.entry_id, "QST-N1-1");
    assert_eq!(entry.sig, entries[0].sig, "deterministic signature must match vector");

    // reduce_actions basic behaviour with the same envelope machinery.
    let mk = |entry_id: &str, node: &str, typ: &str, content: CjsonVal, ts: &str| RegisterEntry {
        entry_id: entry_id.into(), session_id: "S".into(), node_id: node.into(),
        seq: 1, entry_type: typ.into(), content, timestamp: ts.into(), sig: "x".into(),
    };
    let mut c1 = BTreeMap::new();
    c1.insert("description".to_string(), CjsonVal::Str("Do the thing".into()));
    c1.insert("owner".to_string(), CjsonVal::Str("N1".into()));
    let mut c2 = BTreeMap::new();
    c2.insert("aid".to_string(), CjsonVal::Str("ACT-N0-1".into()));
    c2.insert("status".to_string(), CjsonVal::Str("DONE".into()));
    c2.insert("version".to_string(), CjsonVal::Int(2));
    let actions = vec![
        mk("ACT-N0-1", "N0", "action", CjsonVal::Object(c1), "2040-02-01T11:00:00.000Z"),
        mk("ACT-N1-1", "N1", "action_update", CjsonVal::Object(c2), "2040-02-01T11:10:00.000Z"),
    ];
    let (a_by_id, a_superseded) = reduce_actions(&actions);
    assert!(a_superseded.is_empty());
    let a = a_by_id.get("ACT-N0-1").unwrap();
    assert_eq!(a.status, "DONE");
    assert_eq!(a.version, 2);
    assert_eq!(a.description, "Do the thing");
    assert_eq!(a.owner.as_deref(), Some("N1"));
}

// ── Feature 5: CBOR decode + COSE_Sign1 verify ─────────────────────────────

fn hex_decode(s: &str) -> Vec<u8> {
    (0..s.len()).step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

#[test]
fn test_v11_cose_sign1() {
    let v = vectors();
    let sect = v.get("coseSign1").unwrap();
    let cache = key_cache(&v, &[]);
    let b64 = sect.get("coseSign1CborB64").unwrap().as_str().unwrap();
    let hex = sect.get("coseSign1CborHex").unwrap().as_str().unwrap();

    // Structural CBOR checks: tag 18, 4-element array, alg -19; b64 == hex bytes.
    let raw = hex_decode(hex);
    let decoded = decode_cbor(&raw).unwrap();
    match &decoded {
        CborVal::Tag(COSE_SIGN1_TAG, inner) => match inner.as_ref() {
            CborVal::Array(a) => {
                assert_eq!(a.len(), 4);
                let protected = match &a[0] { CborVal::Bytes(b) => b, _ => panic!("protected") };
                match decode_cbor(protected).unwrap() {
                    CborVal::Map(m) => assert_eq!(m[0], (CborVal::Int(1), CborVal::Int(-19))),
                    _ => panic!("protected map"),
                }
            }
            _ => panic!("expected array"),
        },
        _ => panic!("expected tag 18"),
    }

    // Golden verification.
    let env = CoseSignedPlan {
        plan: Some(sect.get("plan").unwrap().clone()),
        cose_sign1_cbor_b64: b64.to_string(),
    };
    let res = verify_plan_cose(&env, &cache);
    assert_eq!(res.valid, sect.get("expectedValid").unwrap().as_bool().unwrap(),
               "verify_plan_cose: {}", res.reason);

    // Tampered plan → payload mismatch.
    let mut tampered_plan = BTreeMap::new();
    tampered_plan.insert("title".to_string(), CjsonVal::Str("TAMPERED".into()));
    let tampered = CoseSignedPlan {
        plan: Some(CjsonVal::Object(tampered_plan)),
        cose_sign1_cbor_b64: b64.to_string(),
    };
    assert!(!verify_plan_cose(&tampered, &cache).valid, "tampered plan must fail");

    // Unknown key → key_not_in_cache.
    let empty_res = verify_plan_cose(&env, &HashMap::new());
    assert!(!empty_res.valid);
    assert_eq!(empty_res.reason, "key_not_in_cache");

    // Garbage CBOR rejected.
    let garbage = CoseSignedPlan { plan: None, cose_sign1_cbor_b64: "AAAA".into() };
    assert!(!verify_plan_cose(&garbage, &cache).valid);

    // Deterministic signing with the vector seed reproduces the golden bytes.
    let seed = v.get("key").unwrap().get("privateSeedB64").unwrap().as_str().unwrap();
    let signed = sign_plan_cose(sect.get("plan").unwrap(), seed).unwrap();
    assert_eq!(signed.cose_sign1_cbor_b64, b64, "sign_plan_cose must reproduce golden bytes");
    assert!(verify_plan_cose(&signed, &cache).valid);
}

#[test]
fn test_v11_cbor_decoder() {
    // RFC 8949 Appendix A vectors (deterministic subset).
    let cases: Vec<(&str, CborVal)> = vec![
        ("00", CborVal::Int(0)),
        ("0a", CborVal::Int(10)),
        ("17", CborVal::Int(23)),
        ("1818", CborVal::Int(24)),
        ("1903e8", CborVal::Int(1000)),
        ("1a000f4240", CborVal::Int(1_000_000)),
        ("20", CborVal::Int(-1)),
        ("3863", CborVal::Int(-100)),
        ("f4", CborVal::Bool(false)),
        ("f5", CborVal::Bool(true)),
        ("f6", CborVal::Null),
        ("60", CborVal::Text("".into())),
        ("6161", CborVal::Text("a".into())),
        ("6449455446", CborVal::Text("IETF".into())),
        ("83010203", CborVal::Array(vec![CborVal::Int(1), CborVal::Int(2), CborVal::Int(3)])),
    ];
    for (hex, want) in cases {
        assert_eq!(decode_cbor(&hex_decode(hex)).unwrap(), want, "decode {}", hex);
    }

    // Map {"a": 1, "b": [2, 3]}.
    match decode_cbor(&hex_decode("a26161016162820203")).unwrap() {
        CborVal::Map(m) => {
            assert_eq!(m[0], (CborVal::Text("a".into()), CborVal::Int(1)));
        }
        other => panic!("expected map, got {:?}", other),
    }

    // Rejections: floats, indefinite lengths, trailing bytes, truncation.
    for bad in ["f97c00", "fb3ff199999999999a", "9f01ff", "5f42010243030405ff",
                "0001", "1903", "6449455446ff"] {
        assert!(decode_cbor(&hex_decode(bad)).is_err(), "decode {} should fail", bad);
    }

    // Encode determinism: map keys sorted bytewise by encoded form.
    let enc = encode_cbor(&CborVal::Map(vec![
        (CborVal::Text("b".into()), CborVal::Int(2)),
        (CborVal::Text("a".into()), CborVal::Int(1)),
    ]));
    let hex: String = enc.iter().map(|b| format!("{:02x}", b)).collect();
    assert_eq!(hex, "a2616101616202");
}
