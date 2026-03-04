// Formatting.swift — Human-readable formatters ported from planet-time.js.

import Foundation

public extension InterplanetTime {

    /// Format a light travel duration in seconds as a human-readable string.
    /// Examples: 45 → "45 s", 186 → "3 min 6 s", 3700 → "1 h 1 min 40 s"
    static func formatLightTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) s" }
        let h   = s / 3600
        let m   = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return sec > 0 ? "\(h) h \(m) min \(sec) s" : "\(h) h \(m) min"
        }
        return sec > 0 ? "\(m) min \(sec) s" : "\(m) min"
    }

    /// Returns a simple ISO-like string for a planet time: "planet/HH:MM:SS"
    static func formatPlanetTimeISO(_ planet: String, hour: Int, minute: Int, second: Int) -> String {
        String(format: "%@/%02d:%02d:%02d", planet, hour, minute, second)
    }
}
