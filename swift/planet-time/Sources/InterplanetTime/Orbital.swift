// Orbital.swift — Orbital mechanics ported from planet-time.js.

import Foundation

public extension InterplanetTime {

    // MARK: - Leap seconds / TT

    static func taiMinusUtc(_ utcMs: Int64) -> Int {
        var tai = 10
        for ls in leapSeconds {
            if utcMs >= ls.utcMs { tai = ls.delta } else { break }
        }
        return tai
    }

    /// Julian Ephemeris Day (TT) from UTC milliseconds.
    static func jde(_ utcMs: Int64) -> Double {
        let ttMs = Double(utcMs) + Double(taiMinusUtc(utcMs)) * 1000 + 32184
        return 2_440_587.5 + ttMs / 86_400_000.0
    }

    /// Julian centuries from J2000.0 (TT).
    static func jc(_ utcMs: Int64) -> Double {
        (jde(utcMs) - j2000JD) / 36_525.0
    }

    // MARK: - Kepler solver

    private static func keplerE(_ M: Double, _ e: Double) -> Double {
        var E = M
        for _ in 0..<50 {
            let dE = (M - E + e * sin(E)) / (1.0 - e * cos(E))
            E += dE
            if abs(dE) < 1e-12 { break }
        }
        return E
    }

    // MARK: - Heliocentric position

    struct HelioPos {
        public let x, y, r, lon: Double
    }

    static func helioPos(_ planet: String, _ utcMs: Int64) -> HelioPos {
        let el = orbitalElements[planet] ?? orbitalElements["earth"]!
        let T = jc(utcMs)
        let L = (el.L0 + el.dL * T).truncatingRemainder(dividingBy: 360.0)
        let om = el.om0
        let e  = el.e0
        let a  = el.a
        let Mrad = ((L - om + 360.0).truncatingRemainder(dividingBy: 360.0)) * .pi / 180.0
        let E = keplerE(Mrad, e)
        let nu = 2.0 * atan2(sqrt(1.0 + e) * sin(E / 2.0),
                             sqrt(1.0 - e) * cos(E / 2.0))
        let r   = a * (1.0 - e * cos(E))
        let lon = (om * .pi / 180.0 + nu + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return HelioPos(x: r * cos(lon), y: r * sin(lon), r: r, lon: lon)
    }

    // MARK: - Distance & light travel

    static func bodyDistanceAu(_ a: String, _ b: String, _ utcMs: Int64) -> Double {
        let pa = helioPos(a, utcMs), pb = helioPos(b, utcMs)
        let dx = pa.x - pb.x, dy = pa.y - pb.y
        return sqrt(dx*dx + dy*dy)
    }

    static func lightTravelSeconds(_ a: String, _ b: String, _ utcMs: Int64) -> Double {
        bodyDistanceAu(a, b, utcMs) * auSeconds
    }

    // MARK: - Line of sight

    struct LineOfSight {
        public let clear, blocked, degraded: Bool
        public let closestSunAu: Double?
        public let elongDeg: Double
    }

    static func checkLineOfSight(_ a: String, _ b: String, _ utcMs: Int64) -> LineOfSight {
        let pa = helioPos(a, utcMs), pb = helioPos(b, utcMs)
        let abx = pb.x - pa.x, aby = pb.y - pa.y
        let d2  = abx*abx + aby*aby
        if d2 < 1e-20 {
            return LineOfSight(clear: true, blocked: false, degraded: false,
                               closestSunAu: nil, elongDeg: 0)
        }
        let t = max(0.0, min(1.0, -(pa.x*abx + pa.y*aby) / d2))
        let cx = pa.x + t*abx, cy = pa.y + t*aby
        let closest = sqrt(cx*cx + cy*cy)
        let dotAB = abx*pa.x + aby*pa.y
        let abMag = sqrt(d2), aMag = sqrt(pa.x*pa.x + pa.y*pa.y)
        let cosEl = (aMag > 1e-10 && abMag > 1e-10) ? -dotAB / (abMag * aMag) : 0.0
        let elongDeg = acos(max(-1, min(1, cosEl))) * 180 / .pi
        let blocked  = closest < 0.1
        let degraded = !blocked && (closest < 0.25 || elongDeg < 5.0)
        return LineOfSight(clear: !blocked && !degraded, blocked: blocked, degraded: degraded,
                           closestSunAu: closest, elongDeg: elongDeg)
    }

    // MARK: - Lower-quartile light time

    static func lowerQuartileLightTime(_ a: String, _ b: String, refMs: Int64) -> Double {
        let yearMs = Int64(365) * earthDayMs
        let step   = yearMs / 360
        var samples = (0..<360).map { i in lightTravelSeconds(a, b, refMs + Int64(i) * step) }
        samples.sort()
        return samples[Int(Double(samples.count) * 0.25)]
    }
}
