//! Interop driver for rust/ltx (see scripts/interop/run.js).
use base64::Engine;
use interplanet_ltx::*;
use std::collections::BTreeMap;
use std::{env, fs, path::Path};

fn node(id: &str, name: &str, role: &str, delay: i32, location: &str) -> LtxNode {
    LtxNode { id: id.into(), name: name.into(), role: role.into(), delay, location: location.into() }
}

fn seg(t: &str, q: i32, speaker: Option<&str>, label: Option<&str>) -> LtxSegmentTemplate {
    let mut s = LtxSegmentTemplate::new(t, q);
    s.speaker = speaker.map(String::from);
    s.label = label.map(String::from);
    s
}

fn unhash(h: &str) -> Vec<u8> {
    base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(h.trim_start_matches("#l="))
        .expect("base64")
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let (in_dir, out_dir) = (Path::new(&args[1]), Path::new(&args[2]));

    let mut plan = create_plan(Some("Réunion Mars 🚀"), "2026-03-15T14:00:00.000Z", 840);
    plan.quantum = 3;
    plan.mode = "LTX-ASYNC".into();
    plan.nodes = vec![
        node("N0", "Earth HQ", "HOST", 0, "earth"),
        node("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
        node("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon"),
    ];
    plan.segments = vec![
        seg("PLAN_CONFIRM", 2, None, None),
        seg("TX", 3, Some("N0"), Some("Ouverture: état de la mission")),
        seg("RX", 3, None, None),
        seg("TX", 2, Some("N1"), Some("Réponse 🔴")),
        seg("BUFFER", 1, None, None),
    ];

    fs::write(out_dir.join("wire-v2.json"), unhash(&encode_hash(&plan))).unwrap();
    println!("ID_V2 {}", make_plan_id(&plan));

    // No upgrade function for the typed plan: set the v3 fields directly.
    let mut v3 = plan.clone();
    v3.v = 3;
    v3.plan_version = Some(1);
    v3.delays = Some(BTreeMap::from([("N1|N2".to_string(), 842)]));
    fs::write(out_dir.join("wire-v3.json"), unhash(&encode_hash(&v3))).unwrap();
    println!("ID_V3 {}", make_plan_id(&v3));
    println!("NOTE v3 built by setting v/plan_version/delays on LtxPlan (no upgrade function)");

    for v in ["2", "3", "P"] {
        let json = fs::read_to_string(in_dir.join(format!("js-v{}.json", v))).unwrap();
        println!("JS_V{} {}", v, make_plan_id_from_json(&json).unwrap());
    }
}
