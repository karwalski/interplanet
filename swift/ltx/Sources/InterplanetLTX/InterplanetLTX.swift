// InterplanetLTX.swift — LTX (Light-Time eXchange) Swift library
// Story 33.7 — Swift 5.9+ · Foundation only
//
// Pure port of the Ruby/JS LTX SDK.

import Foundation
import CryptoKit

// ── Error types ─────────────────────────────────────────────────────────────

public enum LtxError: Error {
    case invalidQuantum(Int)
}

// ── Public structs ──────────────────────────────────────────────────────────

public struct LtxNode: Codable {
    public var id: String
    public var name: String
    public var role: String
    public var delay: Int
    public var location: String

    public init(id: String, name: String, role: String, delay: Int, location: String) {
        self.id = id
        self.name = name
        self.role = role
        self.delay = delay
        self.location = location
    }
}

public struct LtxSegmentTemplate: Codable {
    public var type: String
    public var q: Int

    public init(type: String, q: Int) {
        self.type = type
        self.q = q
    }
}

public struct LtxSegment: Codable {
    public var type: String
    public var q: Int
    public var startMs: Int64
    public var endMs: Int64
    public var durMin: Int
}

public struct LtxNodeURL: Codable {
    public var nodeId: String
    public var name: String
    public var role: String
    public var url: String
}

public struct LtxPlan: Codable {
    public var v: Int
    public var title: String
    public var start: String
    public var quantum: Int
    public var mode: String
    public var nodes: [LtxNode]
    public var segments: [LtxSegmentTemplate]

    public init(
        v: Int = 2,
        title: String = "LTX Session",
        start: String = "",
        quantum: Int = 3,
        mode: String = "LTX",
        nodes: [LtxNode] = [],
        segments: [LtxSegmentTemplate] = []
    ) {
        self.v = v
        self.title = title
        self.start = start
        self.quantum = quantum
        self.mode = mode
        self.nodes = nodes
        self.segments = segments
    }
}

// ── Namespace ───────────────────────────────────────────────────────────────

public enum InterplanetLTX {

    public static let version = "1.0.0"
    public static let defaultQuantum = 3
    public static let defaultAPIBase = "https://interplanet.live/api/ltx.php"

    // ── Story 26.3/26.4 additions ───────────────────────────────────────────

    /// Multiplier for plan-lock timeout: timeout = delay * factor * 1000 ms.
    public static let defaultPlanLockTimeoutFactor = 2

    /// Delay difference (seconds) above which a warning is issued.
    public static let delayViolationWarnS = 120

    /// Delay difference (seconds) above which session moves to DEGRADED.
    public static let delayViolationDegradedS = 300

    public static let defaultSegments: [LtxSegmentTemplate] = [
        .init(type: "PLAN_CONFIRM", q: 2),
        .init(type: "TX", q: 2),
        .init(type: "RX", q: 2),
        .init(type: "CAUCUS", q: 2),
        .init(type: "TX", q: 2),
        .init(type: "RX", q: 2),
        .init(type: "BUFFER", q: 1),
    ]

    // ── Session states ──────────────────────────────────────────────────────

    public enum SessionState: String, CaseIterable {
        case initState  = "INIT"
        case locked     = "LOCKED"
        case running    = "RUNNING"
        case degraded   = "DEGRADED"
        case complete   = "COMPLETE"
    }

    // ── Plan-lock timeout ────────────────────────────────────────────────────

    /// Returns the plan-lock timeout in milliseconds.
    /// timeout = delaySeconds × defaultPlanLockTimeoutFactor × 1000
    public static func planLockTimeoutMs(_ delaySeconds: Double) -> Double {
        return delaySeconds * Double(defaultPlanLockTimeoutFactor) * 1000.0
    }

    // ── Delay-matrix violation threshold ────────────────────────────────────

    /// Compare declared vs measured one-way delay and return severity.
    /// Returns "ok", "violation", or "degraded".
    public static func checkDelayViolation(declaredDelayS: Double, measuredDelayS: Double) -> String {
        let diff = abs(measuredDelayS - declaredDelayS)
        if diff > Double(delayViolationDegradedS) { return "degraded" }
        if diff > Double(delayViolationWarnS)     { return "violation" }
        return "ok"
    }

    // ── ICS text escaping ────────────────────────────────────────────────────

    /// Escape a string for use in RFC 5545 TEXT property values.
    /// Escapes: backslash → \\, semicolon → \;, comma → \,, newline → \n
    public static func escapeIcsText(_ s: String) -> String {
        return s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";",  with: "\\;")
            .replacingOccurrences(of: ",",  with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // ── Plan creation ───────────────────────────────────────────────────────

    /// Create a plan with default Earth HQ → Mars Hab-01 nodes and segments.
    public static func createPlan(title: String? = nil, start: String = "", delayS: Int = 0) -> LtxPlan {
        return LtxPlan(
            v: 2,
            title: title ?? "LTX Session",
            start: start,
            quantum: defaultQuantum,
            mode: "LTX",
            nodes: [
                LtxNode(id: "N0", name: "Earth HQ",    role: "HOST",        delay: 0,      location: "earth"),
                LtxNode(id: "N1", name: "Mars Hab-01", role: "PARTICIPANT", delay: delayS, location: "mars"),
            ],
            segments: defaultSegments.map { LtxSegmentTemplate(type: $0.type, q: $0.q) }
        )
    }

    /// Merge a partial config dictionary into a full LtxPlan with defaults filled in.
    public static func upgradeConfig(_ raw: [String: Any]) -> LtxPlan {
        let titleVal  = (raw["title"]  as? String) ?? nil
        let startVal  = (raw["start"]  as? String) ?? ""
        var plan = createPlan(title: titleVal, start: startVal, delayS: 0)

        if let q = raw["quantum"] {
            if let qi = q as? Int        { plan.quantum = qi }
            else if let qs = q as? String, let qi = Int(qs) { plan.quantum = qi }
        }
        if let m = raw["mode"] as? String { plan.mode = m }

        if let rawNodes = raw["nodes"] as? [[String: Any]] {
            plan.nodes = rawNodes.map { n in
                LtxNode(
                    id:       (n["id"]       as? String) ?? "N0",
                    name:     (n["name"]     as? String) ?? "Unknown",
                    role:     (n["role"]     as? String) ?? "HOST",
                    delay:    (n["delay"]    as? Int)    ?? 0,
                    location: (n["location"] as? String) ?? "earth"
                )
            }
        }

        if let rawSegs = raw["segments"] as? [[String: Any]] {
            plan.segments = rawSegs.map { s in
                LtxSegmentTemplate(
                    type: (s["type"] as? String) ?? "TX",
                    q:    (s["q"]    as? Int)    ?? 2
                )
            }
        }

        return plan
    }

    // ── Segment computation ─────────────────────────────────────────────────

    /// Compute the timed segment array for a plan.
    /// Throws if quantum is less than 1.
    public static func computeSegments(_ plan: LtxPlan) throws -> [LtxSegment] {
        guard plan.quantum >= 1 else {
            throw LtxError.invalidQuantum(plan.quantum)
        }
        let qMs = Int64(plan.quantum) * 60 * 1000
        var t   = parseISOMs(plan.start)
        return plan.segments.map { tmpl in
            let dur = Int64(tmpl.q) * qMs
            let seg = LtxSegment(
                type:    tmpl.type,
                q:       tmpl.q,
                startMs: t,
                endMs:   t + dur,
                durMin:  tmpl.q * plan.quantum
            )
            t += dur
            return seg
        }
    }

    /// Total session duration in minutes.
    public static func totalMin(_ plan: LtxPlan) -> Int {
        return plan.segments.reduce(0) { $0 + $1.q * plan.quantum }
    }

    /// Total session duration in minutes (convenience — ignores quantum guard).
    public static func totalMinSafe(_ plan: LtxPlan) -> Int {
        return totalMin(plan)
    }

    // ── Plan ID ─────────────────────────────────────────────────────────────

    /// Compute the deterministic plan ID string.
    /// Format: "LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX"
    public static func makePlanID(_ plan: LtxPlan) -> String {
        let startMs = parseISOMs(plan.start)
        let date = Date(timeIntervalSince1970: Double(startMs) / 1000.0)
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.dateFormat = "yyyyMMdd"
        let dateStr = fmt.string(from: date)

        var hostStr = "HOST"
        if let first = plan.nodes.first {
            let raw = first.name.replacingOccurrences(of: " ", with: "").uppercased()
            hostStr = String(raw.prefix(8))
        }

        var nodeStr = "RX"
        if plan.nodes.count > 1 {
            nodeStr = plan.nodes.dropFirst().map { n in
                String(n.name.replacingOccurrences(of: " ", with: "").uppercased().prefix(4))
            }.joined(separator: "-")
        }

        return "LTX-\(dateStr)-\(hostStr)-\(nodeStr)-v2-\(planHashHex(plan))"
    }

    // ── Encoding ────────────────────────────────────────────────────────────

    /// Encode a plan to a URL-safe base64 hash fragment ("#l=…").
    public static func encodeHash(_ plan: LtxPlan) -> String {
        let payload = b64urlEncode(planToJSON(plan))
        return "#l=\(payload)"
    }

    /// Decode a plan from a URL hash fragment ("#l=…", "l=…", or raw base64).
    public static func decodeHash(_ hash: String) -> LtxPlan? {
        var token = hash
        if token.hasPrefix("#") { token = String(token.dropFirst()) }
        if token.hasPrefix("l=") { token = String(token.dropFirst(2)) }

        guard let jsonStr = b64urlDecode(token),
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let rawNodes = (obj["nodes"] as? [[String: Any]]) ?? []
        let nodes = rawNodes.map { n in
            LtxNode(
                id:       (n["id"]       as? String) ?? "",
                name:     (n["name"]     as? String) ?? "",
                role:     (n["role"]     as? String) ?? "HOST",
                delay:    (n["delay"]    as? Int)    ?? 0,
                location: (n["location"] as? String) ?? "earth"
            )
        }

        let rawSegs = (obj["segments"] as? [[String: Any]]) ?? []
        let segments = rawSegs.map { s in
            LtxSegmentTemplate(
                type: (s["type"] as? String) ?? "TX",
                q:    (s["q"]    as? Int)    ?? 2
            )
        }

        guard !segments.isEmpty else { return nil }

        return LtxPlan(
            v:        (obj["v"]       as? Int)    ?? 2,
            title:    (obj["title"]   as? String) ?? "LTX Session",
            start:    (obj["start"]   as? String) ?? "",
            quantum:  (obj["quantum"] as? Int)    ?? defaultQuantum,
            mode:     (obj["mode"]    as? String) ?? "LTX",
            nodes:    nodes,
            segments: segments
        )
    }

    // ── Node URLs ───────────────────────────────────────────────────────────

    /// Build perspective URLs for all nodes in a plan.
    public static func buildNodeURLs(_ plan: LtxPlan, baseURL: String) -> [LtxNodeURL] {
        let hash     = encodeHash(plan)
        let hashPart = hash.hasPrefix("#") ? String(hash.dropFirst()) : hash
        let base     = baseURL.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? baseURL

        return plan.nodes.map { node in
            LtxNodeURL(
                nodeId: node.id,
                name:   node.name,
                role:   node.role,
                url:    "\(base)?node=\(node.id)#\(hashPart)"
            )
        }
    }

    // ── ICS generation ──────────────────────────────────────────────────────

    /// Generate LTX-extended iCalendar (.ics) content for a plan.
    public static func generateICS(_ plan: LtxPlan) -> String {
        let segs    = (try? computeSegments(plan)) ?? []
        let startMs = parseISOMs(plan.start)
        let endMs   = segs.last?.endMs ?? startMs
        let planId  = makePlanID(plan)

        let fmtICS: (Int64) -> String = { ms in
            let d = Date(timeIntervalSince1970: Double(ms) / 1000.0)
            let f = DateFormatter()
            f.timeZone = TimeZone(identifier: "UTC")!
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return f.string(from: d)
        }

        let dtStart = fmtICS(startMs)
        let dtEnd   = fmtICS(endMs)
        let dtStamp = fmtICS(Int64(Date().timeIntervalSince1970 * 1000))

        let segTpl    = plan.segments.map { $0.type }.joined(separator: ",")
        let hostName  = plan.nodes.first?.name ?? "Earth HQ"

        let partNames: String
        if plan.nodes.count > 1 {
            partNames = plan.nodes.dropFirst().map { $0.name }.joined(separator: ", ")
        } else {
            partNames = "remote nodes"
        }

        let delayDesc: String
        if plan.nodes.count > 1 {
            delayDesc = plan.nodes.dropFirst().map { n in
                "\(n.name): \(n.delay / 60) min one-way"
            }.joined(separator: " . ")
        } else {
            delayDesc = "no participant delay configured"
        }

        let toNID: (LtxNode) -> String = { n in
            n.name.uppercased().components(separatedBy: .whitespaces).joined(separator: "-")
        }

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//InterPlanet//LTX v1.1//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "BEGIN:VEVENT",
            "UID:\(planId)@interplanet.live",
            "DTSTAMP:\(dtStamp)",
            "DTSTART:\(dtStart)",
            "DTEND:\(dtEnd)",
            "SUMMARY:\(escapeIcsText(plan.title))",
            "DESCRIPTION:LTX session -- \(escapeIcsText(hostName)) with \(escapeIcsText(partNames))\\nSignal delays: \(escapeIcsText(delayDesc))\\nMode: \(escapeIcsText(plan.mode)) . Segment plan: \(segTpl)\\nGenerated by InterPlanet (https://interplanet.live)",
            "LTX:1",
            "LTX-PLANID:\(planId)",
            "LTX-QUANTUM:PT\(plan.quantum)M",
            "LTX-SEGMENT-TEMPLATE:\(segTpl)",
            "LTX-MODE:\(plan.mode)",
        ]

        for n in plan.nodes {
            lines.append("LTX-NODE:ID=\(toNID(n));ROLE=\(n.role)")
        }

        for n in plan.nodes.dropFirst() {
            let d = n.delay
            lines.append("LTX-DELAY;NODEID=\(toNID(n)):ONEWAY-MIN=\(d);ONEWAY-MAX=\(d + 120);ONEWAY-ASSUMED=\(d)")
        }

        lines.append("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY")

        for n in plan.nodes where n.location == "mars" {
            lines.append("LTX-LOCALTIME:NODE=\(toNID(n));SCHEME=LMST;PARAMS=LONGITUDE:0E")
        }

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // ── Formatting ──────────────────────────────────────────────────────────

    /// Format a duration in seconds as "MM:SS" (< 1 hour) or "HH:MM:SS".
    public static func formatHMS(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, sec)
        } else {
            return String(format: "%02d:%02d", m, sec)
        }
    }

    /// Format UTC epoch milliseconds as "HH:MM:SS UTC".
    public static func formatUTC(_ epochMs: Int64) -> String {
        let d = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "HH:mm:ss"
        return "\(f.string(from: d)) UTC"
    }

    // ── REST client ─────────────────────────────────────────────────────────

    /// POST the plan to the LTX session store.
    public static func storeSession(_ plan: LtxPlan, apiBase: String? = nil) async throws -> [String: Any] {
        let base = (apiBase ?? defaultAPIBase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url  = URL(string: "\(base)/session")!
        var req  = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let planJSON = planToJSON(plan)
        req.httpBody = Data("{\"plan\":\(planJSON)}".utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// GET a session plan by plan ID.
    public static func getSession(_ planID: String, apiBase: String? = nil) async throws -> LtxPlan? {
        let base    = (apiBase ?? defaultAPIBase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = planID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? planID
        let url     = URL(string: "\(base)/session/\(encoded)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let planData = (obj["plan"] as? [String: Any]) ?? obj
        // Re-encode through hash round-trip to normalise
        var tmpPlan = LtxPlan()
        tmpPlan.v        = (planData["v"]       as? Int)    ?? 2
        tmpPlan.title    = (planData["title"]   as? String) ?? "LTX Session"
        tmpPlan.start    = (planData["start"]   as? String) ?? ""
        tmpPlan.quantum  = (planData["quantum"] as? Int)    ?? defaultQuantum
        tmpPlan.mode     = (planData["mode"]    as? String) ?? "LTX"
        if let rawNodes = planData["nodes"] as? [[String: Any]] {
            tmpPlan.nodes = rawNodes.map { n in
                LtxNode(
                    id:       (n["id"]       as? String) ?? "",
                    name:     (n["name"]     as? String) ?? "",
                    role:     (n["role"]     as? String) ?? "HOST",
                    delay:    (n["delay"]    as? Int)    ?? 0,
                    location: (n["location"] as? String) ?? "earth"
                )
            }
        }
        if let rawSegs = planData["segments"] as? [[String: Any]] {
            tmpPlan.segments = rawSegs.map { s in
                LtxSegmentTemplate(
                    type: (s["type"] as? String) ?? "TX",
                    q:    (s["q"]    as? Int)    ?? 2
                )
            }
        }
        return decodeHash(encodeHash(tmpPlan))
    }

    /// Download ICS for a session by plan ID and optional node ID.
    public static func downloadICS(_ planID: String, nodeID: String? = nil, apiBase: String? = nil) async throws -> String {
        let base    = (apiBase ?? defaultAPIBase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = planID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? planID
        var urlStr  = "\(base)/ics/\(encoded)"
        if let nid = nodeID {
            let encNid = nid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? nid
            urlStr += "?node=\(encNid)"
        }
        guard let url = URL(string: urlStr) else { return "" }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Submit feedback for a session.
    public static func submitFeedback(_ planID: String, payload: [String: Any], apiBase: String? = nil) async throws -> [String: Any] {
        let base    = (apiBase ?? defaultAPIBase).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encoded = planID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? planID
        let url     = URL(string: "\(base)/feedback/\(encoded)")!
        var req     = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    /// Parse an ISO-8601 UTC string to epoch milliseconds.
    static func parseISOMs(_ iso: String) -> Int64 {
        guard !iso.isEmpty else { return 0 }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) { return Int64(d.timeIntervalSince1970 * 1000) }
        fmt.formatOptions = [.withInternetDateTime]
        return Int64((fmt.date(from: iso)?.timeIntervalSince1970 ?? 0) * 1000)
    }

    /// Serialise a plan to compact JSON with keys in canonical order:
    /// v, title, start, quantum, mode, nodes, segments
    static func planToJSON(_ plan: LtxPlan) -> String {
        let nodesJSON = plan.nodes.map { n in
            "{\"id\":\"\(escapeJSON(n.id))\",\"name\":\"\(escapeJSON(n.name))\",\"role\":\"\(escapeJSON(n.role))\",\"delay\":\(n.delay),\"location\":\"\(escapeJSON(n.location))\"}"
        }.joined(separator: ",")
        let segsJSON = plan.segments.map { s in
            "{\"type\":\"\(escapeJSON(s.type))\",\"q\":\(s.q)}"
        }.joined(separator: ",")
        return "{\"v\":\(plan.v),\"title\":\"\(escapeJSON(plan.title))\",\"start\":\"\(escapeJSON(plan.start))\",\"quantum\":\(plan.quantum),\"mode\":\"\(escapeJSON(plan.mode))\",\"nodes\":[\(nodesJSON)],\"segments\":[\(segsJSON)]}"
    }

    /// Escape a string for embedding in a JSON string value.
    private static func escapeJSON(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch.value {
            case 0x22: out += "\\\""   // "
            case 0x5C: out += "\\\\"   // backslash
            case 0x08: out += "\\b"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0C: out += "\\f"
            case 0x0D: out += "\\r"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out += String(ch)
                }
            }
        }
        return out
    }

    /// Compute the polynomial hash hex string (matches ltx-sdk.js makePlanId).
    static func planHashHex(_ plan: LtxPlan) -> String {
        let json = planToJSON(plan)
        var h: UInt32 = 0
        for byte in json.utf8 {
            h = h &* 31 &+ UInt32(byte)
        }
        return String(format: "%08x", h)
    }

    /// URL-safe base64 encode (no padding, `-` and `_` substitutions).
    private static func b64urlEncode(_ str: String) -> String {
        let data = Data(str.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// URL-safe base64 decode. Returns nil on error.
    private static func b64urlDecode(_ s: String) -> String? {
        var padded = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = padded.count % 4
        if rem != 0 { padded += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return String(data: data, encoding: .utf8)
    }


    // ════════════════════════════════════════════════════════════════
    // Security: Epic 29 (stories 29.1, 29.4, 29.5)
    // ════════════════════════════════════════════════════════════════

    // ── Canonical JSON ─────────────────────────────────────────────

    public static func canonicalJSON(_ value: Any?) -> String {
        guard let value = value else { return "null" }
        if let dict = value as? [String: Any] {
            let sortedKeys = dict.keys.sorted()
            let parts = sortedKeys.map { k -> String in
                let escapedKey = canonicalJSONStr(k)
                return "\(escapedKey):\(canonicalJSON(dict[k]))"
            }
            return "{\(parts.joined(separator: ","))}"
        }
        if let arr = value as? [Any] {
            let parts = arr.map { canonicalJSON($0) }
            return "[\(parts.joined(separator: ","))]"
        }
        if let s = value as? String  { return canonicalJSONStr(s) }
        if let b = value as? Bool    { return b ? "true" : "false" }
        if let n = value as? Int     { return "\(n)" }
        if let n = value as? Int64   { return "\(n)" }
        if let n = value as? Double  { return "\(n)" }
        return "null"
    }

    private static func canonicalJSONStr(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            default:
                if c.value < 0x20 {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out += String(c)
                }
            }
        }
        out += "\""
        return out
    }

    // ── NIK (Node Identity Key) ────────────────────────────────────

    public struct LtxNIK {
        public let nodeId:     String
        public let publicKey:  String
        public let algorithm:  String
        public let validFrom:  String
        public let validUntil: String
        public let keyVersion: Int
        public let label:      String
        public init(nodeId: String, publicKey: String, algorithm: String,
                    validFrom: String, validUntil: String, keyVersion: Int, label: String) {
            self.nodeId = nodeId; self.publicKey = publicKey; self.algorithm = algorithm
            self.validFrom = validFrom; self.validUntil = validUntil
            self.keyVersion = keyVersion; self.label = label
        }
    }

    public struct GenerateNIKResult {
        public let nik: LtxNIK
        public let privateKeyB64: String
        public init(nik: LtxNIK, privateKeyB64: String) {
            self.nik = nik; self.privateKeyB64 = privateKeyB64
        }
    }

    public static func generateNIK(validDays: Int = 365, nodeLabel: String = "") -> GenerateNIKResult {
        let privateKey = Curve25519.Signing.PrivateKey()
        let rawPub = Data(privateKey.publicKey.rawRepresentation)
        let rawSeed = Data(privateKey.rawRepresentation)
        let hash = SHA256.hash(data: rawPub)
        let hashData = Data(hash)
        let nodeId    = nikB64url(hashData.prefix(16))
        let publicKey = nikB64url(rawPub)
        let privB64   = nikB64url(rawSeed)
        let now = Date()
        let validUntilDate = now.addingTimeInterval(Double(validDays) * 86400)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let nik = LtxNIK(nodeId: nodeId, publicKey: publicKey, algorithm: "Ed25519",
                         validFrom: fmt.string(from: now), validUntil: fmt.string(from: validUntilDate),
                         keyVersion: 1, label: nodeLabel)
        return GenerateNIKResult(nik: nik, privateKeyB64: privB64)
    }

    public static func isNIKExpired(_ nik: LtxNIK) -> Bool {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        guard let t = fmt.date(from: nik.validUntil) else { return true }
        return Date() > t
    }

    public static func nikFingerprint(_ nik: LtxNIK) -> String {
        guard let rawPub = nikB64urlDecode(nik.publicKey) else { return "" }
        let hash = SHA256.hash(data: rawPub)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // ── SignPlan / VerifyPlan ──────────────────────────────────────

    public struct LtxCoseSign1 {
        public let protected:   String
        public let unprotected: [String: String]
        public let payload:     String
        public let signature:   String
        public init(protected: String, unprotected: [String: String], payload: String, signature: String) {
            self.protected = protected; self.unprotected = unprotected
            self.payload = payload; self.signature = signature
        }
    }

    public struct LtxSignedPlan {
        public let plan:      [String: Any]
        public let coseSign1: LtxCoseSign1
        public init(plan: [String: Any], coseSign1: LtxCoseSign1) {
            self.plan = plan; self.coseSign1 = coseSign1
        }
    }

    public struct LtxVerifyResult {
        public let valid:  Bool
        public let reason: String
        public init(valid: Bool, reason: String = "") {
            self.valid = valid; self.reason = reason
        }
    }

    public static func signPlan(_ plan: [String: Any], privateKeyB64: String) -> LtxSignedPlan? {
        guard let seedData = nikB64urlDecode(privateKeyB64), seedData.count == 32 else { return nil }
        guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seedData) else { return nil }
        let rawPub = Data(privateKey.publicKey.rawRepresentation)
        let protectedStr = canonicalJSON(["alg": -19] as [String: Any])
        let protectedB64 = nikB64url(Data(protectedStr.utf8))
        let payloadStr = canonicalJSON(plan)
        let payloadB64 = nikB64url(Data(payloadStr.utf8))
        let sigStruct = canonicalJSON(["Signature1", protectedB64, "", payloadB64] as [Any])
        guard let sigBytes = try? privateKey.signature(for: Data(sigStruct.utf8)) else { return nil }
        let sigB64 = nikB64url(sigBytes)
        let kidHash = SHA256.hash(data: rawPub)
        let kid = nikB64url(Data(kidHash).prefix(16))
        let cose = LtxCoseSign1(protected: protectedB64, unprotected: ["kid": kid],
                                 payload: payloadB64, signature: sigB64)
        return LtxSignedPlan(plan: plan, coseSign1: cose)
    }

    public static func verifyPlan(_ signedPlan: LtxSignedPlan, keyCache: [String: LtxNIK]) -> LtxVerifyResult {
        let cose = signedPlan.coseSign1
        guard let kid = cose.unprotected["kid"] else {
            return LtxVerifyResult(valid: false, reason: "missing_kid")
        }
        guard let nik = keyCache[kid] else {
            return LtxVerifyResult(valid: false, reason: "key_not_in_cache")
        }
        if isNIKExpired(nik) { return LtxVerifyResult(valid: false, reason: "key_expired") }
        let sigStruct = canonicalJSON(["Signature1", cose.protected, "", cose.payload] as [Any])
        guard let rawPub = nikB64urlDecode(nik.publicKey), rawPub.count == 32 else {
            return LtxVerifyResult(valid: false, reason: "invalid_public_key")
        }
        guard let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPub) else {
            return LtxVerifyResult(valid: false, reason: "invalid_public_key")
        }
        guard let sigData = nikB64urlDecode(cose.signature) else {
            return LtxVerifyResult(valid: false, reason: "invalid_signature")
        }
        guard pubKey.isValidSignature(sigData, for: Data(sigStruct.utf8)) else {
            return LtxVerifyResult(valid: false, reason: "signature_invalid")
        }
        guard let payloadData = nikB64urlDecode(cose.payload),
              let payloadStr = String(data: payloadData, encoding: .utf8) else {
            return LtxVerifyResult(valid: false, reason: "payload_decode_error")
        }
        if payloadStr != canonicalJSON(signedPlan.plan) {
            return LtxVerifyResult(valid: false, reason: "payload_mismatch")
        }
        return LtxVerifyResult(valid: true)
    }

    // ── Sequence Tracker ──────────────────────────────────────────

    public class LtxSequenceTracker {
        public let planId: String
        private var outSeq: [String: Int] = [:]
        private var inSeq:  [String: Int] = [:]
        public init(planId: String) { self.planId = planId }
        public func nextSeq(nodeId: String) -> Int {
            let cur = (outSeq[nodeId] ?? 0) + 1
            outSeq[nodeId] = cur
            return cur
        }
        public func recordSeq(nodeId: String, seq: Int) -> LtxSeqResult {
            let last = inSeq[nodeId] ?? 0
            if seq <= last { return LtxSeqResult(accepted: false, reason: "replay", gap: false, gapSize: 0) }
            let gap = seq > last + 1
            inSeq[nodeId] = seq
            return LtxSeqResult(accepted: true, reason: "", gap: gap, gapSize: gap ? seq - last - 1 : 0)
        }
    }

    public struct LtxSeqResult {
        public let accepted: Bool
        public let reason:   String
        public let gap:      Bool
        public let gapSize:  Int
        public init(accepted: Bool, reason: String, gap: Bool, gapSize: Int) {
            self.accepted = accepted; self.reason = reason; self.gap = gap; self.gapSize = gapSize
        }
    }

    public static func createSequenceTracker(planId: String) -> LtxSequenceTracker {
        return LtxSequenceTracker(planId: planId)
    }

    public static func addSeq(_ bundle: [String: Any], tracker: LtxSequenceTracker, nodeId: String) -> [String: Any] {
        var b = bundle
        b["seq"] = tracker.nextSeq(nodeId: nodeId)
        return b
    }

    public static func checkSeq(_ bundle: [String: Any], tracker: LtxSequenceTracker, senderNodeId: String) -> LtxSeqResult {
        guard let seq = bundle["seq"] as? Int else {
            return LtxSeqResult(accepted: false, reason: "missing_seq", gap: false, gapSize: 0)
        }
        return tracker.recordSeq(nodeId: senderNodeId, seq: seq)
    }

    // ── base64url helpers ──────────────────────────────────────────

    static func nikB64url(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func nikB64urlDecode(_ s: String) -> Data? {
        var padded = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = padded.count % 4
        if rem != 0 { padded += String(repeating: "=", count: 4 - rem) }
        return Data(base64Encoded: padded)
    }

}
