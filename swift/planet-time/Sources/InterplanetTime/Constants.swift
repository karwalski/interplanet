// Constants.swift — Ported verbatim from planet-time.js.
// All times in UTC milliseconds since Unix epoch.

import Foundation

public enum InterplanetTime {

    // MARK: - Fundamental constants

    public static let j2000Ms:     Int64  = 946_728_000_000
    public static let j2000JD:     Double = 2_451_545.0
    public static let earthDayMs:  Int64  = 86_400_000
    public static let marsEpochMs: Int64  = -524_069_761_536
    public static let marsSolMs:   Int64  = 88_775_244
    public static let auKm:        Double = 149_597_870.7
    public static let cKms:        Double = 299_792.458
    public static let auSeconds:   Double = 149_597_870.7 / 299_792.458

    // MARK: - Planet list

    public static let planets: [String] = [
        "mercury", "venus", "earth", "mars",
        "jupiter", "saturn", "uranus", "neptune", "moon"
    ]

    // MARK: - Per-planet calendar data

    public struct PlanetData {
        public let solarDayMs:          Int64
        public let siderealYrMs:        Int64
        public let epochMs:             Int64
        public let workStart:           Int
        public let workEnd:             Int
        public let daysPerPeriod:       Double
        public let periodsPerWeek:      Int
        public let workPeriodsPerWeek:  Int
        public let earthClockSched:     Bool
    }

    public static let planetData: [String: PlanetData] = {
        let ed = Double(earthDayMs)
        return [
            "mercury": PlanetData(
                solarDayMs:         Int64((175.9408 * ed).rounded()),
                siderealYrMs:       Int64((87.9691  * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 9, workEnd: 17,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: true),
            "venus": PlanetData(
                solarDayMs:         Int64((116.7500 * ed).rounded()),
                siderealYrMs:       Int64((224.701  * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 9, workEnd: 17,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: true),
            "earth": PlanetData(
                solarDayMs:         earthDayMs,
                siderealYrMs:       Int64((365.25636 * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 9, workEnd: 17,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
            "mars": PlanetData(
                solarDayMs:         marsSolMs,
                siderealYrMs:       Int64((686.9957 * ed).rounded()),
                epochMs:            marsEpochMs,
                workStart: 9, workEnd: 17,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
            "jupiter": PlanetData(
                solarDayMs:         Int64((9.9250  * 3_600_000).rounded()),
                siderealYrMs:       Int64((4332.589 * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 8, workEnd: 16,
                daysPerPeriod: 2.5, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
            "saturn": PlanetData(
                solarDayMs:         Int64((10.578 * 3_600_000).rounded()),
                siderealYrMs:       Int64((10_759.22 * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 8, workEnd: 16,
                daysPerPeriod: 2.25, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
            "uranus": PlanetData(
                solarDayMs:         Int64((17.2479 * 3_600_000).rounded()),
                siderealYrMs:       Int64((30_688.5 * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 8, workEnd: 16,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
            "neptune": PlanetData(
                solarDayMs:         Int64((16.1100 * 3_600_000).rounded()),
                siderealYrMs:       Int64((60_195.0 * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 8, workEnd: 16,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
            "moon": PlanetData(
                solarDayMs:         earthDayMs,
                siderealYrMs:       Int64((365.25636 * ed).rounded()),
                epochMs:            j2000Ms,
                workStart: 9, workEnd: 17,
                daysPerPeriod: 1.0, periodsPerWeek: 7, workPeriodsPerWeek: 5,
                earthClockSched: false),
        ]
    }()

    // MARK: - Orbital elements

    public struct OrbitalElements {
        public let L0, dL, om0, e0, a: Double
    }

    public static let orbitalElements: [String: OrbitalElements] = [
        "mercury": OrbitalElements(L0: 252.2507, dL: 149_474.0722, om0:  77.4561, e0: 0.20564, a:  0.38710),
        "venus":   OrbitalElements(L0: 181.9798, dL:  58_519.2130, om0: 131.5637, e0: 0.00677, a:  0.72333),
        "earth":   OrbitalElements(L0: 100.4664, dL:  36_000.7698, om0: 102.9373, e0: 0.01671, a:  1.00000),
        "mars":    OrbitalElements(L0: 355.4330, dL:  19_141.6964, om0: 336.0600, e0: 0.09341, a:  1.52366),
        "jupiter": OrbitalElements(L0:  34.3515, dL:   3_036.3027, om0:  14.3320, e0: 0.04849, a:  5.20336),
        "saturn":  OrbitalElements(L0:  50.0775, dL:   1_223.5093, om0:  93.0572, e0: 0.05551, a:  9.53707),
        "uranus":  OrbitalElements(L0: 314.0550, dL:     429.8633, om0: 173.0052, e0: 0.04630, a: 19.19126),
        "neptune": OrbitalElements(L0: 304.3480, dL:     219.8997, om0:  48.1234, e0: 0.00899, a: 30.06900),
        "moon":    OrbitalElements(L0: 100.4664, dL:  36_000.7698, om0: 102.9373, e0: 0.01671, a:  1.00000),
    ]

    // MARK: - Leap seconds

    public static let leapSeconds: [(utcMs: Int64, delta: Int)] = [
        (63_072_000_000, 10), (78_796_800_000, 11), (94_694_400_000, 12),
        (126_230_400_000, 13), (157_766_400_000, 14), (189_302_400_000, 15),
        (220_924_800_000, 16), (252_460_800_000, 17), (283_996_800_000, 18),
        (315_532_800_000, 19), (362_793_600_000, 20), (394_329_600_000, 21),
        (425_865_600_000, 22), (489_024_000_000, 23), (567_993_600_000, 24),
        (631_152_000_000, 25), (662_688_000_000, 26), (709_948_800_000, 27),
        (741_484_800_000, 28), (773_020_800_000, 29), (820_454_400_000, 30),
        (867_715_200_000, 31), (915_148_800_000, 32), (1_136_073_600_000, 33),
        (1_230_768_000_000, 34), (1_341_100_800_000, 35), (1_435_708_800_000, 36),
        (1_483_228_800_000, 37),
    ]
}
