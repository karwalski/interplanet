// Scheduling.swift — Meeting window finder ported from planet-time.js.

import Foundation

public extension InterplanetTime {

    struct MeetingWindow {
        public let startMs, endMs: Int64
        public let durationMinutes: Int
    }

    static func findMeetingWindows(
        _ a: String, _ b: String,
        from fromMs: Int64,
        earthDays: Int = 7,
        stepMin: Int = 15
    ) -> [MeetingWindow] {
        let stepMs = Int64(stepMin) * 60_000
        let endMs  = fromMs + Int64(earthDays) * earthDayMs
        var windows: [MeetingWindow] = []
        var inWindow = false
        var winStart = Int64(0)

        var t = fromMs
        while t < endMs {
            let ptA = getPlanetTime(a, t)
            let ptB = getPlanetTime(b, t)
            let both = ptA.isWorkHour && ptB.isWorkHour

            if both && !inWindow {
                inWindow = true; winStart = t
            } else if !both && inWindow {
                inWindow = false
                let dur = Int((t - winStart) / 60_000)
                if dur > 0 { windows.append(MeetingWindow(startMs: winStart, endMs: t, durationMinutes: dur)) }
            }
            t += stepMs
        }
        if inWindow {
            let dur = Int((endMs - winStart) / 60_000)
            if dur > 0 { windows.append(MeetingWindow(startMs: winStart, endMs: endMs, durationMinutes: dur)) }
        }
        return windows
    }
}
