// Rust port (rust/planet-time). Built by run.sh in a scratch crate with a
// path dependency on the repository copy.
use interplanet_time::{get_mtc, get_planet_time, light_travel_seconds, Planet};
use std::io::Write;

fn main() {
    let path = std::env::args().nth(1).expect("usage: probe <inputs.txt>");
    let text = std::fs::read_to_string(path).expect("read inputs");
    let mut out = std::io::BufWriter::new(std::io::stdout());
    for line in text.lines() {
        let mut it = line.split_whitespace();
        let (Some(body), Some(s)) = (it.next(), it.next()) else { continue };
        let ms: i64 = s.parse().expect("utc_ms");
        let p = Planet::from_str(body).expect("body");
        let pt = get_planet_time(p, ms, 0.0);
        let light = if body == "earth" || body == "moon" {
            "-".to_string()
        } else {
            format!("{:.3}", light_travel_seconds(Planet::Earth, p, ms))
        };
        let mtc = if body == "mars" {
            let m = get_mtc(ms);
            format!("{}\t{}\t{}\t{}", m.sol, m.hour, m.minute, m.second)
        } else {
            "-\t-\t-\t-".to_string()
        };
        writeln!(out, "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", body, ms, pt.hour, pt.minute, pt.second, pt.day_number, light, mtc)
            .unwrap();
    }
}
