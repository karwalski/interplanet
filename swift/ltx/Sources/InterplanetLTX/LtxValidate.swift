// LtxValidate.swift — plan validation (LTX-SPECIFICATION.md §3.5, §4, §7) and
// planId over the wire form of a plan (spec/golden/plan-ids.json).
//
// Swift port of validatePlan / _reservedFieldErrors / _assertNoReservedFields
// and makePlanId(JSON.parse(json)) in javascript/ltx/ltx-sdk.js.
//
// JSONSerialization does not keep object key order, but the FROZEN v2 planId
// hashes JSON.stringify output in insertion order, so this file carries a
// small order-preserving JSON reader (LtxJSON) for that purpose.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto  // swift-crypto on Linux (same API as CryptoKit)
#endif

// ── Validation result types ─────────────────────────────────────────────────

/// One validation failure: a stable code, the JSON path and a message.
public struct LtxPlanError: Equatable {
    public let code: String
    public let path: String
    public let message: String
    public init(code: String, path: String, message: String) {
        self.code = code; self.path = path; self.message = message
    }
}

/// Result of `InterplanetLTX.validatePlan`.
public struct LtxPlanValidation {
    public let valid: Bool
    public let errors: [LtxPlanError]
    public var codes: [String] { errors.map { $0.code } }
}

/// Thrown by amendment and session creation when a plan uses the reserved
/// streams (§3.5) or branching (§7) fields. `code` is the first violation's
/// code ('reserved_streams' or 'reserved_branching'); `errors` lists all.
public struct LtxReservedFieldError: Error {
    public let code: String
    public let message: String
    public let errors: [LtxPlanError]
}

// ── Sequence tracker storage ────────────────────────────────────────────────

/// Storage adapter for sequence tracker state (e.g. persistent storage so the
/// reorder window survives restarts). Implementing `delete` is optional: the
/// default stores 0, which the tracker treats as absent.
public protocol LtxSeqStorage: AnyObject {
    func get(_ key: String) -> Int?
    func set(_ key: String, _ value: Int)
    func delete(_ key: String)
}

extension LtxSeqStorage {
    public func delete(_ key: String) { set(key, 0) }
}

// ── Order-preserving JSON value ─────────────────────────────────────────────

/// A parsed JSON value that keeps object key order (needed for the frozen v2
/// planId, which hashes JSON.stringify output in insertion order).
public indirect enum LtxJSON {
    case object([(String, LtxJSON)])
    case array([LtxJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// Parse JSON text. Returns nil on malformed input or trailing data.
    public static func parse(_ text: String) -> LtxJSON? {
        var p = LtxJSONParser(Array(text.utf8))
        p.skipWS()
        guard let v = p.value() else { return nil }
        p.skipWS()
        return p.i == p.b.count ? v : nil
    }

    /// Value of `key` in an object (nil for other kinds or a missing key).
    public subscript(key: String) -> LtxJSON? {
        if case .object(let kv) = self { return kv.first { $0.0 == key }?.1 }
        return nil
    }

    /// Compact serialisation identical to JavaScript JSON.stringify.
    public func stringify() -> String {
        switch self {
        case .object(let kv):
            return "{" + kv.map { LtxJSON.quote($0.0) + ":" + $0.1.stringify() }
                .joined(separator: ",") + "}"
        case .array(let a):
            return "[" + a.map { $0.stringify() }.joined(separator: ",") + "]"
        case .string(let s): return LtxJSON.quote(s)
        case .number(let d): return LtxJSON.jsNumber(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        }
    }

    /// Foundation form ([String: Any], [Any], String, Int/Double, Bool,
    /// NSNull) for validatePlan and canonicalJSON.
    public var foundationValue: Any {
        switch self {
        case .object(let kv):
            var d: [String: Any] = [:]
            for (k, v) in kv { d[k] = v.foundationValue }
            return d
        case .array(let a): return a.map { $0.foundationValue }
        case .string(let s): return s
        case .number(let d):
            if d.rounded() == d && abs(d) < 9_007_199_254_740_992 { return Int(d) }
            return d
        case .bool(let b): return b
        case .null: return NSNull()
        }
    }

    /// JSON.stringify string quoting: escapes quote, backslash and control
    /// characters; everything else, including non-ASCII, is emitted raw.
    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) }
                else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }

    /// JavaScript Number-to-String for the values plans carry: integral
    /// values without a fraction, others in Swift's shortest round-trip form.
    static func jsNumber(_ d: Double) -> String {
        if !d.isFinite { return "null" }
        if d.rounded() == d && abs(d) < 1e21 {
            return d == 0 ? "0" : String(format: "%.0f", d)
        }
        return "\(d)"
    }
}

struct LtxJSONParser {
    let b: [UInt8]
    var i = 0
    init(_ b: [UInt8]) { self.b = b }

    mutating func skipWS() {
        while i < b.count, [0x20, 0x09, 0x0A, 0x0D].contains(b[i]) { i += 1 }
    }

    mutating func value() -> LtxJSON? {
        guard i < b.count else { return nil }
        switch b[i] {
        case UInt8(ascii: "{"): return object()
        case UInt8(ascii: "["): return array()
        case UInt8(ascii: "\""): return string().map { .string($0) }
        case UInt8(ascii: "t"): return literal("true", .bool(true))
        case UInt8(ascii: "f"): return literal("false", .bool(false))
        case UInt8(ascii: "n"): return literal("null", .null)
        default: return number()
        }
    }

    mutating func literal(_ word: String, _ v: LtxJSON) -> LtxJSON? {
        let w = Array(word.utf8)
        guard i + w.count <= b.count, Array(b[i..<i + w.count]) == w else { return nil }
        i += w.count
        return v
    }

    mutating func object() -> LtxJSON? {
        i += 1
        var kv: [(String, LtxJSON)] = []
        skipWS()
        if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .object(kv) }
        while true {
            skipWS()
            guard i < b.count, b[i] == UInt8(ascii: "\""), let k = string() else { return nil }
            skipWS()
            guard i < b.count, b[i] == UInt8(ascii: ":") else { return nil }
            i += 1
            skipWS()
            guard let v = value() else { return nil }
            // JSON.parse keeps the first position and the last value of a key.
            if let idx = kv.firstIndex(where: { $0.0 == k }) { kv[idx].1 = v }
            else { kv.append((k, v)) }
            skipWS()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            if b[i] == UInt8(ascii: "}") { i += 1; return .object(kv) }
            return nil
        }
    }

    mutating func array() -> LtxJSON? {
        i += 1
        var a: [LtxJSON] = []
        skipWS()
        if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
        while true {
            skipWS()
            guard let v = value() else { return nil }
            a.append(v)
            skipWS()
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            if b[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
            return nil
        }
    }

    mutating func hex4() -> UInt32? {
        guard i + 4 <= b.count,
              let v = UInt32(String(decoding: b[i..<i + 4], as: UTF8.self), radix: 16)
        else { return nil }
        i += 4
        return v
    }

    mutating func string() -> String? {
        i += 1
        var bytes: [UInt8] = []
        while i < b.count {
            let c = b[i]
            if c == UInt8(ascii: "\"") {
                i += 1
                return String(decoding: bytes, as: UTF8.self)
            }
            if c == UInt8(ascii: "\\") {
                i += 1
                guard i < b.count else { return nil }
                let e = b[i]
                i += 1
                var scalar: UInt32
                switch e {
                case UInt8(ascii: "\""): scalar = 0x22
                case UInt8(ascii: "\\"): scalar = 0x5C
                case UInt8(ascii: "/"): scalar = 0x2F
                case UInt8(ascii: "b"): scalar = 0x08
                case UInt8(ascii: "f"): scalar = 0x0C
                case UInt8(ascii: "n"): scalar = 0x0A
                case UInt8(ascii: "r"): scalar = 0x0D
                case UInt8(ascii: "t"): scalar = 0x09
                case UInt8(ascii: "u"):
                    guard let hi = hex4() else { return nil }
                    scalar = hi
                    if (0xD800...0xDBFF).contains(hi), i + 6 <= b.count,
                       b[i] == UInt8(ascii: "\\"), b[i + 1] == UInt8(ascii: "u") {
                        let save = i
                        i += 2
                        if let lo = hex4(), (0xDC00...0xDFFF).contains(lo) {
                            scalar = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                default: return nil
                }
                // Lone surrogates cannot live in a Swift String.
                let u = Unicode.Scalar(scalar) ?? Unicode.Scalar(0xFFFD)!
                bytes.append(contentsOf: Array(String(Character(u)).utf8))
                continue
            }
            bytes.append(c)
            i += 1
        }
        return nil
    }

    mutating func number() -> LtxJSON? {
        let start = i
        while i < b.count, "+-0123456789.eE".utf8.contains(b[i]) { i += 1 }
        guard i > start,
              let d = Double(String(decoding: b[start..<i], as: UTF8.self))
        else { return nil }
        return .number(d)
    }
}

// ── Validation ──────────────────────────────────────────────────────────────

extension InterplanetLTX {

    /// Core segment types (§3.4) plus the auxiliary types the SDKs handle.
    public static let planSegmentTypes = [
        "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
        "SPEAK", "REST", "PAD", "OPEN", "RELAY",
    ]
    public static let planModes = ["LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC"]
    /// Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3).
    public static let v3OnlyFields = [
        "delays", "planVersion", "prevPlanHash", "questions", "actions", "streams",
    ]
    static let reservedBranchPlanFields = ["branches", "branching"]
    static let reservedBranchSegmentFields = ["branch"]
    static let reservedStreamSegmentFields = ["stream"]

    /// Numeric value of a JSON number (booleans excluded, also on Darwin
    /// where NSNumber(true) bridges to Int).
    static func jsonNumber(_ v: Any?) -> Double? {
        guard let v = v else { return nil }
        if let n = v as? NSNumber {
            if isBooleanNumber(n) { return nil }
            return n.doubleValue
        }
        if let i = v as? Int { return Double(i) }
        if let d = v as? Double { return d }
        return nil
    }

    static func jsonInteger(_ v: Any?) -> Double? {
        guard let d = jsonNumber(v), d.isFinite, d.rounded() == d else { return nil }
        return d
    }

    static func isJSONNull(_ v: Any?) -> Bool { v == nil || v is NSNull }

    /// Reserved-field violations only (§3.5 streams, §7 branching).
    public static func reservedFieldErrors(_ plan: Any?) -> [LtxPlanError] {
        var errors: [LtxPlanError] = []
        guard let plan = plan as? [String: Any] else { return errors }
        if let streams = plan["streams"] {
            if !((streams as? [Any])?.isEmpty ?? false) {
                errors.append(LtxPlanError(code: "reserved_streams", path: "streams",
                    message: "streams[] is reserved (§3.5) and MUST be absent or empty"))
            }
        }
        for f in reservedBranchPlanFields where plan[f] != nil {
            errors.append(LtxPlanError(code: "reserved_branching", path: f,
                message: "\(f) is reserved for branching (§7, not yet implemented) and MUST be absent"))
        }
        for (i, seg) in ((plan["segments"] as? [Any]) ?? []).enumerated() {
            guard let s = seg as? [String: Any] else { continue }
            for f in reservedStreamSegmentFields where s[f] != nil {
                errors.append(LtxPlanError(code: "reserved_streams", path: "segments[\(i)].\(f)",
                    message: "segment \(f) is reserved (§3.5) and MUST be absent"))
            }
            for f in reservedBranchSegmentFields where s[f] != nil {
                errors.append(LtxPlanError(code: "reserved_branching", path: "segments[\(i)].\(f)",
                    message: "segment \(f) is reserved for branching (§7) and MUST be absent"))
            }
        }
        return errors
    }

    /// Throw LtxReservedFieldError if a plan uses reserved stream/branch fields.
    public static func assertNoReservedFields(_ plan: [String: Any], _ fnName: String) throws {
        let errors = reservedFieldErrors(plan)
        guard let first = errors.first else { return }
        throw LtxReservedFieldError(code: first.code,
                                    message: "\(fnName): \(first.message)",
                                    errors: errors)
    }

    /// Validate a v2 or v3 plan (wire form: a JSON object as [String: Any])
    /// against spec/ltx-schema.json and the reserved-field rules (§3.5
    /// streams, §7 branching). v1 configs must be upgraded first. Pure;
    /// never throws.
    ///
    /// Error codes: not_an_object, invalid_version, missing_field,
    /// invalid_field, invalid_quantum, invalid_mode, invalid_nodes,
    /// invalid_host, duplicate_node_id, invalid_segment, unknown_speaker,
    /// v3_field_in_v2, invalid_delays, reserved_streams, reserved_branching.
    public static func validatePlan(_ planValue: Any?) -> LtxPlanValidation {
        var errors: [LtxPlanError] = []
        func err(_ code: String, _ path: String, _ message: String) {
            errors.append(LtxPlanError(code: code, path: path, message: message))
        }
        guard let plan = planValue as? [String: Any] else {
            err("not_an_object", "", "plan must be an object")
            return LtxPlanValidation(valid: false, errors: errors)
        }
        let v = jsonNumber(plan["v"])
        if v != 2 && v != 3 { err("invalid_version", "v", "v must be 2 or 3") }
        for f in ["title", "start", "quantum", "mode", "nodes", "segments"] where plan[f] == nil {
            err("missing_field", f, "\(f) is required")
        }
        if let t = plan["title"], !(t is String) {
            err("invalid_field", "title", "title must be a string")
        }
        if let s = plan["start"] {
            let str = s as? String
            if str == nil || parseISODate(str!) == nil {
                err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
            }
        }
        if plan["quantum"] != nil {
            let q = jsonInteger(plan["quantum"])
            if q == nil || q! < 1 || q! > 60 {
                err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")
            }
        }
        if let m = plan["mode"] {
            if !planModes.contains((m as? String) ?? "\u{0}") {
                err("invalid_mode", "mode", "mode must be one of \(planModes.joined(separator: ", "))")
            }
        }

        var ids = Set<String>()
        if let nodesVal = plan["nodes"] {
            if let nodes = nodesVal as? [Any], !nodes.isEmpty {
                var hosts = 0
                for (i, nv) in nodes.enumerated() {
                    guard let n = nv as? [String: Any],
                          let id = n["id"] as? String, !id.isEmpty, !id.contains("|"),
                          n["name"] is String,
                          let role = n["role"] as? String,
                          ["HOST", "PARTICIPANT", "OBSERVER"].contains(role),
                          let delay = jsonNumber(n["delay"]), delay >= 0
                    else {
                        err("invalid_nodes", "nodes[\(i)]",
                            "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0")
                        continue
                    }
                    if ids.contains(id) { err("duplicate_node_id", "nodes[\(i)].id", "duplicate node id \(id)") }
                    ids.insert(id)
                    if role == "HOST" { hosts += 1 }
                }
                let h = nodes[0] as? [String: Any]
                if hosts != 1 || h == nil || (h!["role"] as? String) != "HOST" || jsonNumber(h!["delay"]) != 0 {
                    err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")
                }
            } else {
                err("invalid_nodes", "nodes", "nodes must be a non-empty array")
            }
        }

        if let segsVal = plan["segments"] {
            if let segs = segsVal as? [Any] {
                for (i, sv) in segs.enumerated() {
                    guard let s = sv as? [String: Any],
                          let type = s["type"] as? String, planSegmentTypes.contains(type),
                          let q = jsonInteger(s["q"]), q >= 1
                    else {
                        err("invalid_segment", "segments[\(i)]", "segment needs a known type and integer q >= 1")
                        continue
                    }
                    if let sp = s["speaker"] {
                        let spId = sp as? String
                        if spId == nil || !ids.contains(spId!) {
                            err("unknown_speaker", "segments[\(i)].speaker", "speaker \(sp) is not a node id")
                        }
                    }
                }
            } else {
                err("invalid_segment", "segments", "segments must be an array")
            }
        }

        if v == 2 {
            for f in v3OnlyFields where plan[f] != nil {
                err("v3_field_in_v2", f, "\(f) is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
            }
        } else if v == 3 {
            if let dv = plan["delays"] {
                if let d = dv as? [String: Any] {
                    for k in d.keys.sorted() {
                        let parts = k.components(separatedBy: "|")
                        let val = jsonNumber(d[k])
                        if parts.count != 2 || !utf16Less(parts[0], parts[1]) ||
                            (!ids.isEmpty && (!ids.contains(parts[0]) || !ids.contains(parts[1]))) ||
                            val == nil || !(val! >= 0) {
                            err("invalid_delays", "delays.\(k)",
                                "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)")
                        }
                    }
                } else {
                    err("invalid_delays", "delays", "delays must be an object")
                }
            }
            if plan["planVersion"] != nil {
                let pv = jsonInteger(plan["planVersion"])
                if pv == nil || pv! < 1 {
                    err("invalid_field", "planVersion", "planVersion must be an integer >= 1")
                }
            }
            if let pph = plan["prevPlanHash"] {
                let s = pph as? String
                let ok = s != nil && s!.utf8.count == 64 &&
                    s!.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
                if !ok { err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters") }
            }
            for f in ["questions", "actions"] {
                if let fv = plan[f], !(fv is [Any]) { err("invalid_field", f, "\(f) must be an array") }
            }
        }

        errors.append(contentsOf: reservedFieldErrors(plan))
        return LtxPlanValidation(valid: errors.isEmpty, errors: errors)
    }

    /// Validate plan JSON text (parsed with key order preserved).
    public static func validatePlan(json: String) -> LtxPlanValidation {
        return validatePlan(LtxJSON.parse(json)?.foundationValue)
    }

    /// JavaScript string comparison: UTF-16 code unit order.
    static func utf16Less(_ a: String, _ b: String) -> Bool {
        return Array(a.utf16).lexicographicallyPrecedes(Array(b.utf16))
    }

    static func parseISODate(_ iso: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: iso)
    }

    // ── planId over the wire form ───────────────────────────────────────────

    /// JS String.prototype.slice(0, n) on UTF-16 code units. A Swift String
    /// cannot hold the lone surrogate JS leaves when the cut splits a
    /// surrogate pair; decoding repairs it to U+FFFD, the UTF-8 form of the
    /// JS id (planIdUtf8 in spec/golden/plan-id-prefixes.json).
    static func jsSlice(_ s: String, _ n: Int) -> String {
        let u = Array(s.utf16)
        return u.count <= n ? s : String(decoding: u[0..<n], as: UTF16.self)
    }

    /// ECMAScript \s (WhiteSpace and LineTerminator). Unicode White_Space
    /// (`properties.isWhitespace`) differs: it has U+0085 and not U+FEFF.
    static func isJSWhitespace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029,
             0x202F, 0x205F, 0x3000, 0xFEFF: return true
        default: return false
        }
    }

    /// JS name.replace(/\s+/g, '').toUpperCase(). `uppercased()` is the full,
    /// locale-independent Unicode mapping (special casing included).
    static func jsCompactUpper(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars where !isJSWhitespace(c) { out.append(c) }
        return String(out).uppercased()
    }

    /// HOSTSTR: (name || 'HOST') compacted, upper-cased, 8 UTF-16 units.
    static func jsHostStr(_ name: String?) -> String {
        guard let name = name, !name.isEmpty else { return "HOST" }
        return jsSlice(jsCompactUpper(name), 8)
    }

    /// makePlanId over plan JSON text, parsed with key order preserved.
    /// Mirrors ltx-sdk.js makePlanId(JSON.parse(json)) for v2 and v3 plans
    /// with nodes: the FROZEN v2 hash is imul31 over the UTF-16 code units of
    /// JSON.stringify in insertion order, including fields the typed LtxPlan
    /// does not model (relay, key order); v3 hashes SHA-256 over the RFC 8785
    /// canonical JSON. Returns nil for unparseable input.
    public static func makePlanID(json: String) -> String? {
        guard let root = LtxJSON.parse(json), case .object = root,
              case .string(let start)? = root["start"],
              let date = parseISODate(start)
        else { return nil }
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")!
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd"
        let dateStr = fmt.string(from: date)

        var names: [String] = []
        if case .array(let nodes)? = root["nodes"] {
            for n in nodes {
                if case .string(let name)? = n["name"] { names.append(name) } else { names.append("") }
            }
        }
        let hostStr = jsHostStr(names.first)
        let nodeStr = names.count > 1
            ? jsSlice(names.dropFirst().map { jsSlice(jsCompactUpper($0), 4) }.joined(separator: "-"), 16)
            : "RX"

        if case .number(let v)? = root["v"], v >= 3 {
            let digest = planHash(root.foundationValue as? [String: Any] ?? [:])
            return "LTX-\(dateStr)-\(hostStr)-\(nodeStr)-v3-\(String(digest.prefix(8)))"
        }
        var h: UInt32 = 0
        for unit in root.stringify().utf16 { h = h &* 31 &+ UInt32(unit) }
        return "LTX-\(dateStr)-\(hostStr)-\(nodeStr)-v2-\(String(format: "%08x", h))"
    }

    /// planHash over plan JSON text (SHA-256 of the canonical JSON).
    public static func planHash(json: String) -> String? {
        guard let dict = LtxJSON.parse(json)?.foundationValue as? [String: Any] else { return nil }
        return planHash(dict)
    }
}
