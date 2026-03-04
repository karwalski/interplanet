// main.swift — Standalone test runner for InterplanetTime (no XCTest required).
// Usage: swift run RunTests
//        swift run RunTests [path/to/reference.json]

import Foundation
import InterplanetTime

let j2000Ms = InterplanetTime.j2000Ms  // 946_728_000_000

var passed = 0
var failed = 0

func check(_ name: String, _ cond: Bool) {
    if cond {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(name)")
    }
}

func checkEqual<T: Equatable>(_ name: String, _ a: T, _ b: T) {
    check("\(name): \(a) == \(b)", a == b)
}

func checkNear(_ name: String, _ a: Double, _ b: Double, accuracy: Double = 0.01) {
    check("\(name): |\(a) - \(b)| < \(accuracy)", abs(a - b) < accuracy)
}

// ── 1. Constants ──────────────────────────────────────────────────────────────
checkEqual("J2000Ms",        InterplanetTime.j2000Ms,      946_728_000_000)
checkEqual("MarsEpochMs",    InterplanetTime.marsEpochMs, -524_069_761_536)
checkEqual("MarsSolMs",      InterplanetTime.marsSolMs,    88_775_244)
checkNear ("AuSeconds",      InterplanetTime.auSeconds,   149_597_870.7/299_792.458, accuracy: 0.1)
checkEqual("PlanetsCount",   InterplanetTime.planets.count, 9)
checkEqual("OrbElems count", InterplanetTime.orbitalElements.count, 9)
check     ("LeapSeconds non-empty", !InterplanetTime.leapSeconds.isEmpty)
checkEqual("Last leap delta",  InterplanetTime.leapSeconds.last!.delta, 37)

// ── 2. TaiMinusUtc ────────────────────────────────────────────────────────────
checkEqual("TAI at J2000",        InterplanetTime.taiMinusUtc(j2000Ms),           32)
checkEqual("TAI after last leap", InterplanetTime.taiMinusUtc(1_483_228_800_001), 37)
checkEqual("TAI before first",    InterplanetTime.taiMinusUtc(0),                 10)

// ── 3. JDE / JC ───────────────────────────────────────────────────────────────
checkNear ("JDE at J2000",    InterplanetTime.jde(j2000Ms), 2_451_545.0)
checkNear ("JC at J2000",     InterplanetTime.jc(j2000Ms),  0.0)
check     ("JDE increases",   InterplanetTime.jde(j2000Ms + 86_400_000) > InterplanetTime.jde(j2000Ms))

// ── 4. Heliocentric position ──────────────────────────────────────────────────
let earthPos = InterplanetTime.helioPos("earth", j2000Ms)
checkNear ("Earth r ~ 1 AU",  earthPos.r, 1.0, accuracy: 0.05)
let marsPos  = InterplanetTime.helioPos("mars", j2000Ms)
check     ("Mars r in 1.3–1.7 AU", marsPos.r > 1.3 && marsPos.r < 1.7)
let xyR = (earthPos.x*earthPos.x + earthPos.y*earthPos.y).squareRoot()
checkNear ("XY consistent with r", xyR, earthPos.r, accuracy: 0.001)

// ── 5. Light travel ───────────────────────────────────────────────────────────
let ltEM = InterplanetTime.lightTravelSeconds("earth", "mars", j2000Ms)
check     ("E-M lt in 100–2000 s",  ltEM > 100 && ltEM < 2000)
let lt2003 = InterplanetTime.lightTravelSeconds("earth", "mars", 1_061_942_400_000)
checkNear ("E-M opposition 2003 ~185 s", lt2003, 185.0, accuracy: 30.0)
let ab = InterplanetTime.lightTravelSeconds("earth", "mars", j2000Ms)
let ba = InterplanetTime.lightTravelSeconds("mars", "earth", j2000Ms)
checkNear ("Light travel symmetric", ab, ba, accuracy: 0.001)

// ── 6. MTC ────────────────────────────────────────────────────────────────────
let mtc = InterplanetTime.getMTC(j2000Ms)
check     ("MTC hour in [0,24)",   mtc.hour >= 0 && mtc.hour < 24)
check     ("MTC minute in [0,60)", mtc.minute >= 0 && mtc.minute < 60)
check     ("MTC str format",       mtc.mtcStr.count == 5)
let mtc0 = InterplanetTime.getMTC(InterplanetTime.marsEpochMs)
checkEqual("MTC sol at Mars epoch", mtc0.sol, Int64(0))

// ── 7. GetPlanetTime ──────────────────────────────────────────────────────────
for planet in InterplanetTime.planets {
    let pt = InterplanetTime.getPlanetTime(planet, j2000Ms)
    check("\(planet) hour in [0,24)",    pt.hour >= 0 && pt.hour < 24)
    check("\(planet) minute in [0,60)",  pt.minute >= 0 && pt.minute < 60)
    check("\(planet) second in [0,60)",  pt.second >= 0 && pt.second < 60)
    check("\(planet) timeStr 5 chars",   pt.timeStr.count == 5)
    check("\(planet) timeStrFull 8 ch",  pt.timeStrFull.count == 8)
}

let base = InterplanetTime.getPlanetTime("mars", j2000Ms, tzOffsetH: 0)
let off  = InterplanetTime.getPlanetTime("mars", j2000Ms, tzOffsetH: 2)
var diff = (off.hour * 60 + off.minute) - (base.hour * 60 + base.minute)
if diff > 23*60 { diff -= 24*60 }; if diff < -23*60 { diff += 24*60 }
checkNear ("TZ offset 2h → 120 min diff", Double(diff), 120.0, accuracy: 1.0)

let marsTime = InterplanetTime.getPlanetTime("mars", j2000Ms)
check     ("Mars has solInYear",    marsTime.solInYear != nil)
checkEqual("Mars solsPerYear=669",  marsTime.solsPerYear, Int64?(669))
let earthTime = InterplanetTime.getPlanetTime("earth", j2000Ms)
check     ("Earth no solInYear",    earthTime.solInYear == nil)
checkEqual("Earth epoch hour=0",    earthTime.hour, 0)

// ── 8. Work hours ─────────────────────────────────────────────────────────────
let wh = InterplanetTime.getPlanetTime("earth", j2000Ms + 9 * 3_600_000)
check("Work hour at 9:00",    wh.isWorkHour)
check("Midnight not work",    !earthTime.isWorkHour)

// ── 9. Line of sight ──────────────────────────────────────────────────────────
let los1 = InterplanetTime.checkLineOfSight("earth", "mars", j2000Ms)
check("LOS elong > 0",                los1.elongDeg > 0)
let los2 = InterplanetTime.checkLineOfSight("earth", "mars", 1_633_651_200_000)
check("LOS blocked at conjunction",   !los2.clear)
let los3 = InterplanetTime.checkLineOfSight("earth", "mars", 1_602_547_200_000)
check("LOS clear at opposition 2020", los3.clear)

// ── 10. Meeting windows ───────────────────────────────────────────────────────
let wins = InterplanetTime.findMeetingWindows("earth", "earth", from: j2000Ms, earthDays: 1)
check("Earth+Earth always overlaps", !wins.isEmpty)
let wins2 = InterplanetTime.findMeetingWindows("earth", "mars", from: j2000Ms, earthDays: 7)
for w in wins2 {
    check("Window duration > 0", w.durationMinutes > 0)
    check("Window end > start",  w.endMs > w.startMs)
}

// ── 11. Formatting ────────────────────────────────────────────────────────────
checkEqual("format 186s",  InterplanetTime.formatLightTime(186),  "3 min 6 s")
checkEqual("format 45s",   InterplanetTime.formatLightTime(45),   "45 s")
checkEqual("format 3700s", InterplanetTime.formatLightTime(3700), "1 h 1 min 40 s")
checkEqual("format 0s",    InterplanetTime.formatLightTime(0),    "0 s")
checkEqual("format 60s",   InterplanetTime.formatLightTime(60),   "1 min")
let iso = InterplanetTime.formatPlanetTimeISO("mars", hour: 14, minute: 30, second: 0)
check("ISO contains 14:30:00", iso.contains("14:30:00"))
check("ISO contains mars",     iso.contains("mars"))

// ── 12. Cross-language fixtures (optional) ────────────────────────────────────
let fixturePath: String
if CommandLine.arguments.count > 1 {
    fixturePath = CommandLine.arguments[1]
} else {
    // Sources/RunTests/main.swift → up 5 levels → interplanet-github/
    let src = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // main.swift → RunTests/
        .deletingLastPathComponent()  // RunTests/ → Sources/
        .deletingLastPathComponent()  // Sources/ → swift/planet-time/
        .deletingLastPathComponent()  // swift/planet-time/ → swift/
        .deletingLastPathComponent()  // swift/ → interplanet-github/
    fixturePath = src.appendingPathComponent("c/planet-time/fixtures/reference.json").path
}

if FileManager.default.fileExists(atPath: fixturePath) {
    struct Entry: Decodable { let utc_ms: Int64; let planet: String; let hour: Int; let minute: Int; let light_travel_s: Double? }
    struct Fixture: Decodable { let entries: [Entry] }
    do {
        let data    = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        var fPass = 0, fFail = 0
        for e in fixture.entries {
            let pt  = InterplanetTime.getPlanetTime(e.planet, e.utc_ms)
            let tag = "\(e.planet)@\(e.utc_ms)"
            if pt.hour == e.hour { fPass += 1 } else { fFail += 1; print("FAIL fixture: \(tag) hour=\(e.hour) got \(pt.hour)") }
            if pt.minute == e.minute { fPass += 1 } else { fFail += 1; print("FAIL fixture: \(tag) min=\(e.minute) got \(pt.minute)") }
            if let ltRef = e.light_travel_s, e.planet != "earth", e.planet != "moon" {
                let lt = InterplanetTime.lightTravelSeconds("earth", e.planet, e.utc_ms)
                if abs(lt - ltRef) <= 2.0 { fPass += 1 } else { fFail += 1; print("FAIL fixture: \(tag) lt=\(ltRef) got \(lt)") }
            }
        }
        passed += fPass; failed += fFail
        print("Fixture entries checked: \(fixture.entries.count), fixture passed: \(fPass), failed: \(fFail)")
    } catch {
        print("Fixture parse error: \(error)")
    }
} else {
    print("SKIP: fixture not found at \(fixturePath)")
}

// ── Summary ───────────────────────────────────────────────────────────────────
print("\n\(passed) passed  \(failed) failed")
exit(failed > 0 ? 1 : 0)
