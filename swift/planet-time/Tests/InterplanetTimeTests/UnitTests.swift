import XCTest
@testable import InterplanetTime

final class InterplanetTimeTests: XCTestCase {

    let j2000Ms = InterplanetTime.j2000Ms  // 946_728_000_000

    // MARK: - 1. Constants

    func testJ2000Ms() {
        XCTAssertEqual(InterplanetTime.j2000Ms, 946_728_000_000)
    }

    func testMarsEpochMs() {
        XCTAssertEqual(InterplanetTime.marsEpochMs, -524_069_761_536)
    }

    func testMarsSolMs() {
        XCTAssertEqual(InterplanetTime.marsSolMs, 88_775_244)
    }

    func testAuSeconds() {
        let expected = 149_597_870.7 / 299_792.458
        XCTAssertEqual(InterplanetTime.auSeconds, expected, accuracy: 0.1)
    }

    func testPlanetsCount() {
        XCTAssertEqual(InterplanetTime.planets.count, 9)
    }

    func testOrbitalElementsCount() {
        XCTAssertEqual(InterplanetTime.orbitalElements.count, 9)
    }

    func testLeapSecondsNonEmpty() {
        XCTAssertFalse(InterplanetTime.leapSeconds.isEmpty)
    }

    func testLeapSecondsLastDelta() {
        XCTAssertEqual(InterplanetTime.leapSeconds.last!.delta, 37)
    }

    // MARK: - 2. TaiMinusUtc

    func testTaiAtJ2000() {
        XCTAssertEqual(InterplanetTime.taiMinusUtc(j2000Ms), 32)
    }

    func testTaiAfterLastLeap() {
        XCTAssertEqual(InterplanetTime.taiMinusUtc(1_483_228_800_001), 37)
    }

    func testTaiBeforeFirst() {
        XCTAssertEqual(InterplanetTime.taiMinusUtc(0), 10)
    }

    // MARK: - 3. JDE / JC

    func testJdeAtJ2000() {
        XCTAssertEqual(InterplanetTime.jde(j2000Ms), 2_451_545.0, accuracy: 0.01)
    }

    func testJcAtJ2000() {
        XCTAssertEqual(InterplanetTime.jc(j2000Ms), 0.0, accuracy: 0.01)
    }

    func testJdeIncreases() {
        let a = InterplanetTime.jde(j2000Ms)
        let b = InterplanetTime.jde(j2000Ms + 86_400_000)
        XCTAssertGreaterThan(b, a)
    }

    func testJcAfterCentury() {
        let hundredYears = Int64(100.0 * 365.25 * 86_400_000)
        XCTAssertEqual(InterplanetTime.jc(j2000Ms + hundredYears), 1.0, accuracy: 0.01)
    }

    // MARK: - 4. Heliocentric position

    func testEarthDistanceNearOneAu() {
        let pos = InterplanetTime.helioPos("earth", j2000Ms)
        XCTAssertEqual(pos.r, 1.0, accuracy: 0.05)
    }

    func testMarsDistanceInRange() {
        let pos = InterplanetTime.helioPos("mars", j2000Ms)
        XCTAssertGreaterThan(pos.r, 1.3)
        XCTAssertLessThan(pos.r, 1.7)
    }

    func testXYConsistentWithR() {
        let pos = InterplanetTime.helioPos("earth", j2000Ms)
        let r   = (pos.x*pos.x + pos.y*pos.y).squareRoot()
        XCTAssertEqual(r, pos.r, accuracy: 0.001)
    }

    // MARK: - 5. Light travel

    func testEarthMarsAtJ2000() {
        let lt = InterplanetTime.lightTravelSeconds("earth", "mars", j2000Ms)
        XCTAssertGreaterThan(lt, 100)
        XCTAssertLessThan(lt, 2000)
    }

    func testEarthMarsOpposition2003() {
        // 2003-08-27: historic closest approach
        let lt = InterplanetTime.lightTravelSeconds("earth", "mars", 1_061_942_400_000)
        XCTAssertEqual(lt, 185.0, accuracy: 30.0)
    }

    func testEarthJupiter() {
        let lt = InterplanetTime.lightTravelSeconds("earth", "jupiter", j2000Ms)
        XCTAssertGreaterThan(lt, 1000)
        XCTAssertLessThan(lt, 5000)
    }

    func testSymmetric() {
        let ab = InterplanetTime.lightTravelSeconds("earth", "mars", j2000Ms)
        let ba = InterplanetTime.lightTravelSeconds("mars", "earth", j2000Ms)
        XCTAssertEqual(ab, ba, accuracy: 0.001)
    }

    // MARK: - 6. MTC

    func testMtcAtJ2000() {
        let mtc = InterplanetTime.getMTC(j2000Ms)
        XCTAssertGreaterThanOrEqual(mtc.hour, 0)
        XCTAssertLessThan(mtc.hour, 24)
        XCTAssertGreaterThanOrEqual(mtc.minute, 0)
        XCTAssertLessThan(mtc.minute, 60)
    }

    func testMtcStrFormat() {
        let mtc = InterplanetTime.getMTC(j2000Ms)
        XCTAssertEqual(mtc.mtcStr.count, 5)
        XCTAssertEqual(mtc.mtcStr[mtc.mtcStr.index(mtc.mtcStr.startIndex, offsetBy: 2)], ":")
    }

    func testMtcSolAtMarsEpoch() {
        let mtc = InterplanetTime.getMTC(InterplanetTime.marsEpochMs)
        XCTAssertEqual(mtc.sol, 0)
    }

    // MARK: - 7. GetPlanetTime

    func assertValidTime(_ planet: String, file: StaticString = #file, line: UInt = #line) {
        let pt = InterplanetTime.getPlanetTime(planet, j2000Ms)
        XCTAssertGreaterThanOrEqual(pt.hour, 0, file: file, line: line)
        XCTAssertLessThan(pt.hour, 24, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pt.minute, 0, file: file, line: line)
        XCTAssertLessThan(pt.minute, 60, file: file, line: line)
        XCTAssertGreaterThanOrEqual(pt.second, 0, file: file, line: line)
        XCTAssertLessThan(pt.second, 60, file: file, line: line)
        XCTAssertEqual(pt.timeStr.count, 5, file: file, line: line)
        XCTAssertEqual(pt.timeStrFull.count, 8, file: file, line: line)
    }

    func testAllPlanets() {
        for p in InterplanetTime.planets { assertValidTime(p) }
    }

    func testTzOffsetShiftsHour() {
        let base = InterplanetTime.getPlanetTime("mars", j2000Ms, tzOffsetH: 0)
        let off  = InterplanetTime.getPlanetTime("mars", j2000Ms, tzOffsetH: 2)
        var diff = (off.hour * 60 + off.minute) - (base.hour * 60 + base.minute)
        if diff > 23 * 60 { diff -= 24 * 60 }
        if diff < -23 * 60 { diff += 24 * 60 }
        XCTAssertEqual(Double(diff), 120.0, accuracy: 1.0)
    }

    func testMarsHasSolInYear() {
        let pt = InterplanetTime.getPlanetTime("mars", j2000Ms)
        XCTAssertNotNil(pt.solInYear)
        XCTAssertEqual(pt.solsPerYear, 669)
    }

    func testEarthNoSolInYear() {
        let pt = InterplanetTime.getPlanetTime("earth", j2000Ms)
        XCTAssertNil(pt.solInYear)
        XCTAssertNil(pt.solsPerYear)
    }

    func testEarthEpochHourIsZero() {
        let pt = InterplanetTime.getPlanetTime("earth", j2000Ms)
        XCTAssertEqual(pt.hour, 0)
    }

    // MARK: - 8. Work-hour logic

    func testWorkHourAtNine() {
        let ms = j2000Ms + 9 * 3_600_000
        let pt = InterplanetTime.getPlanetTime("earth", ms)
        XCTAssertGreaterThanOrEqual(pt.hour, 9)
        XCTAssertLessThan(pt.hour, 17)
        XCTAssertTrue(pt.isWorkHour)
    }

    func testRestHourAtMidnight() {
        let pt = InterplanetTime.getPlanetTime("earth", j2000Ms)
        XCTAssertEqual(pt.hour, 0)
        XCTAssertFalse(pt.isWorkHour)
    }

    func testRestHourAt23() {
        let ms = j2000Ms + 23 * 3_600_000
        let pt = InterplanetTime.getPlanetTime("earth", ms)
        XCTAssertEqual(pt.hour, 23)
        XCTAssertFalse(pt.isWorkHour)
    }

    // MARK: - 9. Line of sight

    func testLosEarthMarsAtJ2000() {
        let los = InterplanetTime.checkLineOfSight("earth", "mars", j2000Ms)
        XCTAssertGreaterThan(los.elongDeg, 0)
    }

    func testLosBlockedConjunction2021() {
        // 2021-10-08: Mars near superior conjunction
        let los = InterplanetTime.checkLineOfSight("earth", "mars", 1_633_651_200_000)
        XCTAssertFalse(los.clear)
    }

    func testLosOpposition2020() {
        // 2020-10-13: Mars opposition — clear path
        let los = InterplanetTime.checkLineOfSight("earth", "mars", 1_602_547_200_000)
        XCTAssertTrue(los.clear)
    }

    func testLosClosestSunPresent() {
        let los = InterplanetTime.checkLineOfSight("earth", "jupiter", j2000Ms)
        XCTAssertNotNil(los.closestSunAu)
    }

    // MARK: - 10. Meeting windows

    func testEarthEarthAlwaysOverlaps() {
        let wins = InterplanetTime.findMeetingWindows("earth", "earth", from: j2000Ms, earthDays: 1)
        XCTAssertFalse(wins.isEmpty)
    }

    func testWindowsHavePositiveDuration() {
        let wins = InterplanetTime.findMeetingWindows("earth", "mars", from: j2000Ms, earthDays: 7)
        for w in wins {
            XCTAssertGreaterThan(w.durationMinutes, 0)
            XCTAssertGreaterThan(w.endMs, w.startMs)
        }
    }

    // MARK: - 11. Formatting

    func testFormat186Seconds() {
        XCTAssertEqual(InterplanetTime.formatLightTime(186), "3 min 6 s")
    }

    func testFormatSecondsOnly() {
        XCTAssertEqual(InterplanetTime.formatLightTime(45), "45 s")
    }

    func testFormatHours() {
        XCTAssertEqual(InterplanetTime.formatLightTime(3700), "1 h 1 min 40 s")
    }

    func testFormatZero() {
        XCTAssertEqual(InterplanetTime.formatLightTime(0), "0 s")
    }

    func testFormatOneMinute() {
        XCTAssertEqual(InterplanetTime.formatLightTime(60), "1 min")
    }

    func testFormatPlanetTimeISO() {
        let s = InterplanetTime.formatPlanetTimeISO("mars", hour: 14, minute: 30, second: 0)
        XCTAssertTrue(s.contains("14:30:00"))
        XCTAssertTrue(s.contains("mars"))
    }
}
