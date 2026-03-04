import XCTest
@testable import InterplanetTime

final class FixtureTests: XCTestCase {

    struct Entry: Decodable {
        let utc_ms: Int64
        let planet: String
        let hour: Int
        let minute: Int
        let light_travel_s: Double?
        let period_in_week: Int?
        let is_work_period: Int?
        let is_work_hour: Int?
    }
    struct Fixture: Decodable { let entries: [Entry] }

    func testCrossLanguageFixtures() throws {
        // Path: two dirs up from the test file, then c/fixtures/reference.json
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // FixtureTests.swift dir
            .deletingLastPathComponent() // InterplanetTimeTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // swift/
            .deletingLastPathComponent() // interplanet-github/
        let fixturePath = base
            .appendingPathComponent("interplanet-github/c/fixtures/reference.json")

        guard FileManager.default.fileExists(atPath: fixturePath.path) else {
            print("SKIP: reference.json not found at \(fixturePath.path)")
            return
        }

        let data    = try Data(contentsOf: fixturePath)
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)

        var passed = 0, failed = 0

        for entry in fixture.entries {
            let pt  = InterplanetTime.getPlanetTime(entry.planet, entry.utc_ms)
            let tag = "\(entry.planet)@\(entry.utc_ms)"

            if pt.hour == entry.hour {
                passed += 1
            } else {
                failed += 1
                XCTFail("\(tag) hour=\(entry.hour) got \(pt.hour)")
            }

            if pt.minute == entry.minute {
                passed += 1
            } else {
                failed += 1
                XCTFail("\(tag) minute=\(entry.minute) got \(pt.minute)")
            }

            if let ltRef = entry.light_travel_s,
               entry.planet != "earth", entry.planet != "moon" {
                let lt = InterplanetTime.lightTravelSeconds("earth", entry.planet, entry.utc_ms)
                if abs(lt - ltRef) <= 2.0 {
                    passed += 1
                } else {
                    failed += 1
                    XCTFail("\(tag) lightTravel expected \(ltRef) got \(lt)")
                }
            }

            if let expPiw = entry.period_in_week {
                if pt.periodInWeek == expPiw {
                    passed += 1
                } else {
                    failed += 1
                    XCTFail("\(tag) period_in_week=\(expPiw) got \(pt.periodInWeek)")
                }
            }

            if let expWP = entry.is_work_period {
                let got = pt.isWorkPeriod ? 1 : 0
                if got == expWP {
                    passed += 1
                } else {
                    failed += 1
                    XCTFail("\(tag) is_work_period=\(expWP) got \(got)")
                }
            }

            if let expWH = entry.is_work_hour {
                let got = pt.isWorkHour ? 1 : 0
                if got == expWH {
                    passed += 1
                } else {
                    failed += 1
                    XCTFail("\(tag) is_work_hour=\(expWH) got \(got)")
                }
            }
        }
        print("Fixture entries: \(fixture.entries.count), passed: \(passed), failed: \(failed)")
        XCTAssertEqual(failed, 0, "Fixture test failures: \(failed)")
    }
}
