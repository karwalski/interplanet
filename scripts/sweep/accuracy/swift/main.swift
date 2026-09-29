// Accuracy harness for swift/planet-time (see ../gen-cases-group2.js).
// Run from swift/planet-time (compiled into the library module, as `make test` does):
//   swiftc -module-name InterplanetTime Sources/InterplanetTime/*.swift \
//     ../../scripts/sweep/accuracy/swift/main.swift -o .build/Accuracy &&
//   .build/Accuracy ../../scripts/sweep/accuracy/instants-group2.txt
import Foundation

let bodies = ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "moon"]
func b(_ v: Bool) -> Int { v ? 1 : 0 }

let text = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
var out = ""
for raw in text.split(separator: "\n") {
    let line = raw.trimmingCharacters(in: .whitespaces)
    guard let ms = Int64(line) else { continue }
    for body in bodies {
        let pt = InterplanetTime.getPlanetTime(body, ms)
        let lt = InterplanetTime.lightTravelSeconds(body, "earth", ms)
        let cols: [String] = ["\(ms)", body, "\(pt.hour)", "\(pt.minute)", "\(pt.second)",
                              "\(pt.dayNumber)", "\(pt.dayInYear)", "\(pt.yearNumber)",
                              "\(pt.periodInWeek)", "\(b(pt.isWorkPeriod))", "\(b(pt.isWorkHour))",
                              String(format: "%.6f", lt)]
        out += cols.joined(separator: "\t") + "\n"
    }
    let m = InterplanetTime.getMTC(ms)
    out += "\(ms)\tmtc\t\(m.sol)\t\(m.hour)\t\(m.minute)\t\(m.second)\n"
}
print(out, terminator: "")
