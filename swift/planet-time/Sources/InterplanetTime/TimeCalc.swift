// TimeCalc.swift — Planet time calculations ported from planet-time.js.

import Foundation

public extension InterplanetTime {

    struct PlanetTime {
        public let hour, minute, second: Int
        public let localHour, dayFraction: Double
        public let dayNumber, dayInYear, yearNumber: Int64
        public let periodInWeek: Int
        public let isWorkPeriod, isWorkHour: Bool
        public let timeStr, timeStrFull: String  // "HH:MM", "HH:MM:SS"
        public let solInYear, solsPerYear: Int64? // Mars only
        public let zoneId: String?               // e.g. "AMT+4"; nil for Earth
    }

    struct MTC {
        public let sol: Int64
        public let hour, minute, second: Int
        public let mtcStr: String // "HH:MM"
    }

    private static let zonePrefix: [String: String] = [
        "mars":    "AMT",
        "moon":    "LMT",
        "mercury": "MMT",
        "venus":   "VMT",
        "jupiter": "JMT",
        "saturn":  "SMT",
        "uranus":  "UMT",
        "neptune": "NMT",
    ]

    static func getPlanetTime(_ planet: String, _ utcMs: Int64, tzOffsetH: Double = 0) -> PlanetTime {
        let effective = planet == "moon" ? "earth" : planet
        let pd = planetData[effective]!
        let solarDay = Double(pd.solarDayMs)

        let elapsedMs  = Double(utcMs - pd.epochMs) + tzOffsetH / 24.0 * solarDay
        let totalDays  = elapsedMs / solarDay
        let dayNumber  = Int64(floor(totalDays))
        let dayFrac    = totalDays - Double(dayNumber)
        let localHour  = dayFrac * 24.0
        let hour       = Int(localHour)
        let minF       = (localHour - Double(hour)) * 60.0
        let minute     = Int(minF)
        let second     = Int((minF - Double(minute)) * 60.0)

        // Work period (positive modulo)
        let piw: Int
        let isWorkPeriod: Bool
        let isWorkHour: Bool
        if pd.earthClockSched {
            // Mercury/Venus: solar day >> circadian rhythm; use UTC Earth-clock scheduling
            // UTC day-of-week: ((floor(utcMs / 86400000) % 7 + 10) % 7 → Mon=0..Sun=6
            // (+7 before +3 ensures positive result for pre-1970 timestamps)
            let utcDay = Int64(floor(Double(utcMs) / Double(86400_000)))
            piw = Int(((utcDay % 7) + 10) % 7)
            isWorkPeriod = piw < pd.workPeriodsPerWeek
            // UTC hour within the day — positive modulo handles pre-1970 timestamps
            let msInDay = ((utcMs % 86400_000) + 86400_000) % 86400_000
            let utcHour = Double(msInDay) / 3_600_000.0
            isWorkHour = isWorkPeriod && utcHour >= Double(pd.workStart) && utcHour < Double(pd.workEnd)
        } else {
            let totalPeriods = totalDays / pd.daysPerPeriod
            piw = ((Int(floor(totalPeriods)) % pd.periodsPerWeek) + pd.periodsPerWeek) % pd.periodsPerWeek
            isWorkPeriod = piw < pd.workPeriodsPerWeek
            isWorkHour = isWorkPeriod && localHour >= Double(pd.workStart) && localHour < Double(pd.workEnd)
        }

        let yearLenDays = Double(pd.siderealYrMs) / solarDay
        let yearNumber  = Int64(floor(totalDays / yearLenDays))
        let dayInYear   = Int64(floor(totalDays - Double(yearNumber) * yearLenDays))

        let solInYear:   Int64? = effective == "mars" ? dayInYear : nil
        let solsPerYear: Int64? = effective == "mars" ? Int64((Double(pd.siderealYrMs) / solarDay).rounded()) : nil

        var zoneId: String? = nil
        if planet != "earth", let prefix = zonePrefix[planet] {
            let off = Int(tzOffsetH)
            let sign = off < 0 ? "-" : "+"
            zoneId = "\(prefix)\(sign)\(abs(off))"
        }

        let h2 = String(format: "%02d", hour)
        let m2 = String(format: "%02d", minute)
        let s2 = String(format: "%02d", second)

        return PlanetTime(
            hour: hour, minute: minute, second: second,
            localHour: localHour, dayFraction: dayFrac,
            dayNumber: dayNumber, dayInYear: dayInYear, yearNumber: yearNumber,
            periodInWeek: piw, isWorkPeriod: isWorkPeriod, isWorkHour: isWorkHour,
            timeStr: "\(h2):\(m2)", timeStrFull: "\(h2):\(m2):\(s2)",
            solInYear: solInYear, solsPerYear: solsPerYear,
            zoneId: zoneId
        )
    }

    static func getMTC(_ utcMs: Int64) -> MTC {
        let ms     = Double(utcMs - marsEpochMs)
        let sol    = Int64(floor(ms / Double(marsSolMs)))
        var fracMs = ms.truncatingRemainder(dividingBy: Double(marsSolMs))
        if fracMs < 0 { fracMs += Double(marsSolMs) }
        let totalSec = fracMs / 1000.0
        let hour   = Int(totalSec / 3600.0)
        let minute = Int(totalSec.truncatingRemainder(dividingBy: 3600.0) / 60.0)
        let second = Int(totalSec.truncatingRemainder(dividingBy: 60.0))
        return MTC(sol: sol, hour: hour, minute: minute, second: second,
                   mtcStr: String(format: "%02d:%02d", hour, minute))
    }
}
