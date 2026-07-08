// LtxV11.swift — LTX v1.1 core subset (Epic 72 cascade)
// pairDelay/computeSegmentsFor (§3.7/§14.3), session state machine (§5),
// amendment chains (§6.4), question/action registers (§9/§10),
// deterministic CBOR (RFC 8949) + COSE_Sign1 (RFC 9052).
//
// Swift 5.9+ · Foundation + CryptoKit only.

import Foundation
import CryptoKit

// ── Viewer-perspective segments ─────────────────────────────────────────────

/// A computed segment from a specific viewer's perspective (§14.3).
public struct LtxViewerSegment {
    public var type: String
    public var q: Int
    public var startMs: Int64
    public var endMs: Int64
    public var durMin: Int
    /// Presenting node id, when the segment is attributed.
    public var speaker: String?
    /// Agenda label, when present.
    public var label: String?
    /// "transmit" (viewer presents), "receive" (after light-time), "neutral".
    public var perspective: String
    /// Light-time shift applied to start/end, in seconds (0 unless receiving).
    public var arrivalOffsetS: Int
}

// ── Session state machine types ─────────────────────────────────────────────

/// Quorum threshold for QUORUM-LOCK (§5.6).
public enum LtxQuorum {
    case all
    case majority
    case count(Int)
}

public struct LtxPendingAmendment {
    public var planId: String
    public var planVersion: Int
    public var affectedNodeIds: [String]
    public var confirmed: [String]
    public var proposedAtMs: Int
    public var timeoutMs: Int
}

/// Session context advanced by `InterplanetLTX.transition`.
public struct LtxSessionContext {
    public var state: String
    public var plan: LtxPlan
    public var planId: String
    /// planId of the first (unamended) plan — freshness scope key.
    public var sessionRootPlanId: String
    public var planVersion: Int
    /// "FULL" | "QUORUM" | nil.
    public var lock: String?
    public var lockStartedAtMs: Int?
    public var lockTimeoutMs: Int
    /// nodeId → planId confirmed by that node.
    public var confirmations: [String: String]
    /// nodeIds that confirmed a planId different from ours (§5.5).
    public var mismatched: [String]
    public var quorumThreshold: Int
    /// Participating subset when quorum-locked (§5.3); nil = all nodes.
    public var subset: [String]?
    public var degradedReasons: [String]
    /// State to return to when leaving EMERGENCY_HOLD via HOST 'resume'.
    public var resumeState: String?
    public var pendingAmendment: LtxPendingAmendment?
}

/// transition() output: updated context + effect maps
/// ({"kind": "audit"|"notify"|"escalate", ...}) for the caller to execute.
public struct LtxTransitionResult {
    public var ctx: LtxSessionContext
    public var effects: [[String: Any]]
}

/// Register reduction result (§8.2): object states + superseded entryIds.
public struct LtxRegisterReduction {
    public var byId: [String: [String: Any]]
    public var superseded: [String]
}

// ── CBOR value model (RFC 8949 deterministic subset) ────────────────────────

/// Supported CBOR values: ints, byte strings, text strings, arrays, maps,
/// tags, booleans and null. Floats and indefinite lengths are rejected.
public indirect enum CborValue {
    case int(Int64)
    case bytes(Data)
    case text(String)
    case array([CborValue])
    case map([(CborValue, CborValue)])
    case tag(UInt64, CborValue)
    case bool(Bool)
    case null
}

public enum CborError: Error {
    case truncated
    case unsupported(String)
    case trailingBytes
}

extension InterplanetLTX {

    public static let v11SessionStates = [
        "DRAFT", "LOCKING", "LOCKED", "ACTIVE", "DEGRADED",
        "EMERGENCY_HOLD", "COMPLETE", "ABORTED",
    ]

    // ═════════════════════════════════════════════════════════════════════
    // 1. pairDelay + computeSegmentsFor (§3.7 / §14.3)
    // ═════════════════════════════════════════════════════════════════════

    /// One-way delay in seconds between two nodes (§3.7). The v3 pair matrix
    /// (`delays`, key "A|B" with ids sorted) is authoritative where present;
    /// otherwise the conservative fallback: HOST pairs use the node's
    /// declared delay, non-HOST pairs the sum of both HOST-relative delays.
    public static func pairDelay(_ plan: LtxPlan, _ nodeIdA: String, _ nodeIdB: String) -> Int? {
        if nodeIdA == nodeIdB { return 0 }
        let key = [nodeIdA, nodeIdB].sorted().joined(separator: "|")
        if let d = plan.delays?[key] { return d }
        guard let a = plan.nodes.first(where: { $0.id == nodeIdA }),
              let b = plan.nodes.first(where: { $0.id == nodeIdB }),
              let hostId = plan.nodes.first?.id
        else { return nil }
        if nodeIdA == hostId { return b.delay }
        if nodeIdB == hostId { return a.delay }
        return a.delay + b.delay
    }

    /// Compute the timed segment array from viewer V's perspective (§14.3):
    /// a segment attributed to speaker S starts for V at
    /// segStart + pairDelay(S, V). Unattributed segments keep their times.
    public static func computeSegmentsFor(_ plan: LtxPlan, viewerNodeId: String) throws -> [LtxViewerSegment] {
        guard plan.nodes.contains(where: { $0.id == viewerNodeId }) else {
            throw LtxError.invalidQuantum(-1) // no dedicated error type; viewer unknown
        }
        let base = try computeSegments(plan)
        var out: [LtxViewerSegment] = []
        for (i, seg) in base.enumerated() {
            let tpl = plan.segments[i]
            let speaker = tpl.speaker
            if speaker == nil || (tpl.type != "TX" && tpl.type != "SPEAK") {
                out.append(LtxViewerSegment(
                    type: seg.type, q: seg.q, startMs: seg.startMs, endMs: seg.endMs,
                    durMin: seg.durMin, speaker: speaker, label: tpl.label,
                    perspective: "neutral", arrivalOffsetS: 0))
                continue
            }
            if speaker == viewerNodeId {
                out.append(LtxViewerSegment(
                    type: seg.type, q: seg.q, startMs: seg.startMs, endMs: seg.endMs,
                    durMin: seg.durMin, speaker: speaker, label: tpl.label,
                    perspective: "transmit", arrivalOffsetS: 0))
                continue
            }
            let shiftS = pairDelay(plan, speaker!, viewerNodeId) ?? 0
            out.append(LtxViewerSegment(
                type: seg.type, q: seg.q,
                startMs: seg.startMs + Int64(shiftS) * 1000,
                endMs: seg.endMs + Int64(shiftS) * 1000,
                durMin: seg.durMin, speaker: speaker, label: tpl.label,
                perspective: "receive", arrivalOffsetS: shiftS))
        }
        return out
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. transition() session state machine (§5)
    // ═════════════════════════════════════════════════════════════════════

    /// 2 × one-way delay to the furthest node, in ms (§5.1).
    public static func lockTimeoutMs(_ plan: LtxPlan) -> Int {
        let maxDelayS = plan.nodes.map { $0.delay }.max() ?? 0
        return defaultPlanLockTimeoutFactor * maxDelayS * 1000
    }

    private static func participants(_ plan: LtxPlan) -> [LtxNode] {
        return plan.nodes.filter { $0.role == "PARTICIPANT" }
    }

    private static func quorumCount(_ plan: LtxPlan, _ quorum: LtxQuorum) -> Int {
        let total = participants(plan).count
        switch quorum {
        case .majority: return total / 2 + 1
        case .count(let n): return min(max(n, 1), total)
        case .all: return total
        }
    }

    /// Create a session context in DRAFT state. `planId` is supplied by the
    /// caller (makePlanID) so this module stays pure.
    public static func createSession(_ plan: LtxPlan, planId: String, quorum: LtxQuorum = .all) -> LtxSessionContext {
        return LtxSessionContext(
            state: "DRAFT",
            plan: plan,
            planId: planId,
            sessionRootPlanId: planId,
            planVersion: plan.planVersion ?? 1,
            lock: nil,
            lockStartedAtMs: nil,
            lockTimeoutMs: lockTimeoutMs(plan),
            confirmations: [:],
            mismatched: [],
            quorumThreshold: quorumCount(plan, quorum),
            subset: nil,
            degradedReasons: [],
            resumeState: nil,
            pendingAmendment: nil
        )
    }

    private static func confirmedSubset(_ ctx: LtxSessionContext) -> [String] {
        let host = ctx.plan.nodes[0]
        let confirmed = participants(ctx.plan)
            .enumerated()
            .filter { ctx.confirmations[$0.element.id] == ctx.planId }
            .sorted { a, b in
                a.element.delay != b.element.delay
                    ? a.element.delay < b.element.delay
                    : a.offset < b.offset
            }
            .map { $0.element.id }
        return [host.id] + confirmed
    }

    private static func fullLockReached(_ ctx: LtxSessionContext) -> Bool {
        return participants(ctx.plan).allSatisfy { ctx.confirmations[$0.id] == ctx.planId }
    }

    private static func quorumReached(_ ctx: LtxSessionContext) -> Bool {
        let confirmed = participants(ctx.plan)
            .filter { ctx.confirmations[$0.id] == ctx.planId }.count
        return confirmed >= ctx.quorumThreshold
    }

    /// Declared one-way delay: v3 pair-matrix HOST row, else node.delay.
    private static func declaredDelayS(_ plan: LtxPlan, _ nodeId: String) -> Int? {
        guard let node = plan.nodes.first(where: { $0.id == nodeId }) else { return nil }
        if let delays = plan.delays, let hostId = plan.nodes.first?.id {
            let key = [hostId, nodeId].sorted().joined(separator: "|")
            if let d = delays[key] { return d }
        }
        return node.delay
    }

    private static func invalidEffect(_ ctx: LtxSessionContext, _ event: [String: Any]) -> [String: Any] {
        return ["kind": "notify", "level": "warn", "code": "INVALID_EVENT",
                "detail": "\(event["type"] as? String ?? "?") ignored in state \(ctx.state)"]
    }

    private static func moved(_ ctx: LtxSessionContext, to: String, event: [String: Any],
                              effects: [[String: Any]], detail: String? = nil) -> LtxTransitionResult {
        var entry: [String: Any] = [
            "type": "state_transition",
            "from": ctx.state,
            "to": to,
            "event": event["type"] as? String ?? "",
            "atMs": event["nowMs"] as? Int ?? 0,
        ]
        if let d = detail { entry["detail"] = d }
        var next = ctx
        next.state = to
        return LtxTransitionResult(ctx: next, effects: [["kind": "audit", "entry": entry]] + effects)
    }

    private static func unchanged(_ ctx: LtxSessionContext, _ effects: [[String: Any]] = []) -> LtxTransitionResult {
        return LtxTransitionResult(ctx: ctx, effects: effects)
    }

    private static func degrade(_ ctx: LtxSessionContext, event: [String: Any], reason: String,
                                extra: [[String: Any]] = []) -> LtxTransitionResult {
        var next = ctx
        next.degradedReasons = ctx.degradedReasons + [reason]
        let effects: [[String: Any]] = [
            ["kind": "notify", "level": "warn", "code": "DEGRADED", "detail": reason],
            ["kind": "escalate", "code": "DEGRADED", "detail": reason],
        ] + extra
        if ctx.state == "DEGRADED" {
            return unchanged(next, Array(effects.prefix(1))) // already degraded
        }
        return moved(next, to: "DEGRADED", event: event, effects: effects, detail: reason)
    }

    /// Advance the session state machine. Pure and time-injected: every event
    /// carries "nowMs"; same (ctx, event) always yields the same result.
    public static func transition(_ ctx: LtxSessionContext, _ event: [String: Any]) -> LtxTransitionResult {
        let type = event["type"] as? String ?? ""
        let nowMs = event["nowMs"] as? Int ?? 0

        switch type {
        case "START_LOCK":
            if ctx.state != "DRAFT" { return unchanged(ctx, [invalidEffect(ctx, event)]) }
            let hostId = ctx.plan.nodes[0].id
            var next = ctx
            next.lockStartedAtMs = nowMs
            next.confirmations[hostId] = ctx.planId
            return moved(next, to: "LOCKING", event: event, effects: [])

        case "PLAN_CONFIRM":
            if ctx.state != "LOCKING" && ctx.state != "DEGRADED" {
                return unchanged(ctx, [invalidEffect(ctx, event)])
            }
            let nodeId = event["nodeId"] as? String ?? ""
            let planId = event["planId"] as? String ?? ""
            var next = ctx
            next.confirmations[nodeId] = planId
            if planId != ctx.planId {
                next.mismatched = ctx.mismatched.filter { $0 != nodeId } + [nodeId]
                return unchanged(next, [[
                    "kind": "notify", "level": "warn", "code": "PLANID_MISMATCH",
                    "detail": "\(nodeId) confirmed \(planId), expected \(ctx.planId) (resolve per §5.5)",
                ]])
            }
            next.mismatched = ctx.mismatched.filter { $0 != nodeId }
            if fullLockReached(next) {
                var locked = next
                locked.lock = "FULL"
                locked.subset = nil
                // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                return moved(locked, to: "LOCKED", event: event, effects: [[
                    "kind": "notify", "level": "info", "code": "LOCKED",
                    "detail": "full lock achieved",
                ]])
            }
            return unchanged(next)

        case "TICK":
            if ctx.state != "LOCKING" { return unchanged(ctx) }
            guard let startedAt = ctx.lockStartedAtMs else { return unchanged(ctx) }
            if nowMs - startedAt < ctx.lockTimeoutMs { return unchanged(ctx) }
            // Lock timeout expired (§5.1).
            if quorumReached(ctx) {
                let subset = confirmedSubset(ctx)
                var next = ctx
                next.lock = "QUORUM"
                next.subset = subset
                let missing = participants(ctx.plan)
                    .filter { ctx.confirmations[$0.id] != ctx.planId }.map { $0.id }
                return degrade(next, event: event,
                    reason: "quorum lock with subset [\(subset.joined(separator: ","))]; unconfirmed: [\(missing.joined(separator: ","))]")
            }
            return degrade(ctx, event: event, reason: "plan-lock timeout without quorum")

        case "SESSION_START":
            if ctx.state == "LOCKED" { return moved(ctx, to: "ACTIVE", event: event, effects: []) }
            if ctx.state == "DEGRADED" && ctx.lock != nil {
                // §5.2: escalation to HOST required before TX.
                return unchanged(ctx, [[
                    "kind": "escalate", "code": "DEGRADED_START",
                    "detail": "session start requested while DEGRADED; HOST decision required",
                ]])
            }
            return unchanged(ctx, [invalidEffect(ctx, event)])

        case "DELAY_MEASURED":
            if ctx.state != "ACTIVE" && ctx.state != "LOCKED" && ctx.state != "DEGRADED" {
                return unchanged(ctx)
            }
            let nodeId = event["nodeId"] as? String ?? ""
            let measured = (event["measuredDelayS"] as? NSNumber)?.doubleValue
                ?? Double(event["measuredDelayS"] as? Int ?? 0)
            guard let declared = declaredDelayS(ctx.plan, nodeId) else {
                return unchanged(ctx, [invalidEffect(ctx, event)])
            }
            let deviation = abs(measured - Double(declared))
            if deviation > Double(delayViolationDegradedS) {
                return degrade(ctx, event: event,
                    reason: "delay violation \(nodeId): measured \(measured)s vs declared \(declared)s (>\(delayViolationDegradedS)s)")
            }
            if deviation > Double(delayViolationWarnS) {
                return unchanged(ctx, [[
                    "kind": "notify", "level": "warn", "code": "DELAY_VIOLATION",
                    "detail": "\(nodeId): measured \(measured)s vs declared \(declared)s",
                ]])
            }
            return unchanged(ctx)

        case "EOK_OVERRIDE":
            if ctx.state == "COMPLETE" || ctx.state == "ABORTED" { return unchanged(ctx) }
            let verified = event["verified"] as? Bool ?? false
            let reason = event["reason"] as? String
            if !verified {
                return unchanged(ctx, [[
                    "kind": "notify", "level": "error", "code": "OVERRIDE_REJECTED",
                    "detail": reason ?? "override failed verification",
                ]])
            }
            if ctx.state == "EMERGENCY_HOLD" { return unchanged(ctx) }
            var next = ctx
            next.resumeState = ctx.state
            return moved(next, to: "EMERGENCY_HOLD", event: event, effects: [[
                "kind": "notify", "level": "error", "code": "EMERGENCY_HOLD",
                "detail": reason ?? "verified EOK override",
            ]])

        case "AMENDMENT_PROPOSED":
            if ctx.state != "ACTIVE" && ctx.state != "LOCKED" && ctx.state != "DEGRADED" {
                return unchanged(ctx, [invalidEffect(ctx, event)])
            }
            let planId = event["planId"] as? String ?? ""
            let planVersion = event["planVersion"] as? Int ?? 0
            let affected = event["affectedNodeIds"] as? [String] ?? []
            if planVersion != ctx.planVersion + 1 {
                return unchanged(ctx, [[
                    "kind": "notify", "level": "error", "code": "AMENDMENT_REJECTED",
                    "detail": "planVersion \(planVersion) != \(ctx.planVersion) + 1",
                ]])
            }
            // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
            let maxDelayS = ctx.plan.nodes
                .filter { affected.contains($0.id) }
                .map { $0.delay }.max() ?? 0
            var next = ctx
            next.pendingAmendment = LtxPendingAmendment(
                planId: planId,
                planVersion: planVersion,
                affectedNodeIds: affected,
                confirmed: [],
                proposedAtMs: nowMs,
                timeoutMs: defaultPlanLockTimeoutFactor * maxDelayS * 1000
            )
            return unchanged(next, [[
                "kind": "notify", "level": "info", "code": "AMENDMENT_PROPOSED",
                "detail": "plan \(planId) v\(planVersion); awaiting [\(affected.joined(separator: ","))]",
            ]])

        case "AMENDMENT_CONFIRMED":
            let planId = event["planId"] as? String ?? ""
            let nodeId = event["nodeId"] as? String ?? ""
            guard let pa = ctx.pendingAmendment, planId == pa.planId else {
                return unchanged(ctx, [invalidEffect(ctx, event)])
            }
            if !pa.affectedNodeIds.contains(nodeId) { return unchanged(ctx) }
            let confirmed = pa.confirmed.filter { $0 != nodeId } + [nodeId]
            if confirmed.count < pa.affectedNodeIds.count {
                var next = ctx
                var updated = pa
                updated.confirmed = confirmed
                next.pendingAmendment = updated
                return unchanged(next)
            }
            // All affected nodes confirmed — the amendment applies. The caller
            // swaps ctx.plan for the verified successor plan.
            var next = ctx
            next.planId = pa.planId
            next.planVersion = pa.planVersion
            next.pendingAmendment = nil
            return unchanged(next, [[
                "kind": "notify", "level": "info", "code": "AMENDMENT_APPLIED",
                "detail": "plan \(pa.planId) v\(pa.planVersion) in effect (root \(ctx.sessionRootPlanId))",
            ]])

        case "HOST_DECISION":
            let decision = event["decision"] as? String ?? ""
            if decision == "abort" {
                if ctx.state == "COMPLETE" || ctx.state == "ABORTED" { return unchanged(ctx) }
                return moved(ctx, to: "ABORTED", event: event, effects: [])
            }
            if decision == "resume" && ctx.state == "EMERGENCY_HOLD" {
                let back = ctx.resumeState ?? "ACTIVE"
                var next = ctx
                next.resumeState = nil
                return moved(next, to: back, event: event, effects: [])
            }
            if decision == "continue" && ctx.state == "DEGRADED" {
                // §5.2: HOST elects to continue with the confirmed subset.
                let detail = ctx.subset != nil
                    ? "continuing with subset [\(ctx.subset!.joined(separator: ","))]"
                    : "continuing despite degraded condition"
                return moved(ctx, to: "ACTIVE", event: event, effects: [[
                    "kind": "notify", "level": "warn", "code": "CONTINUE_DEGRADED",
                    "detail": detail,
                ]])
            }
            return unchanged(ctx, [invalidEffect(ctx, event)])

        case "SESSION_END":
            if ctx.state == "ACTIVE" || ctx.state == "DEGRADED" {
                return moved(ctx, to: "COMPLETE", event: event, effects: [])
            }
            return unchanged(ctx, [invalidEffect(ctx, event)])

        default:
            return unchanged(ctx, [invalidEffect(ctx, event)])
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. Amendment-chain verify (§6.4, LTX-SECURITY.md §7.6)
    // ═════════════════════════════════════════════════════════════════════

    /// SHA-256 hex of the RFC 8785 canonical JSON of a plan.
    /// Always the canonical hash — never the legacy v2 polynomial planId hash.
    public static func planHash(_ plan: [String: Any]) -> String {
        let canonical = canonicalJSON(plan)
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Convert a JSON-decoded { plan, coseSign1 } dictionary (the wire form of
    /// an amendment-chain link) into an LtxSignedPlan.
    public static func signedPlanFromDict(_ dict: [String: Any]) -> LtxSignedPlan? {
        guard let plan = dict["plan"] as? [String: Any],
              let cose = dict["coseSign1"] as? [String: Any],
              let protectedB64 = cose["protected"] as? String,
              let payload = cose["payload"] as? String,
              let signature = cose["signature"] as? String
        else { return nil }
        var unprotected: [String: String] = [:]
        if let up = cose["unprotected"] as? [String: Any] {
            for (k, v) in up { if let s = v as? String { unprotected[k] = s } }
        }
        return LtxSignedPlan(plan: plan, coseSign1: LtxCoseSign1(
            protected: protectedB64, unprotected: unprotected,
            payload: payload, signature: signature))
    }

    /// Create a signed amendment of `signedPlan` with `changes` applied.
    /// The successor is always a v3 plan (§4.4); fields managed here
    /// ('v', 'planVersion', 'prevPlanHash') cannot be overridden.
    public static func createAmendment(_ signedPlan: LtxSignedPlan,
                                       changes: [String: Any],
                                       privateKeyB64: String) -> LtxSignedPlan? {
        let prev = signedPlan.plan
        let prevVersion = prev["planVersion"] as? Int ?? 1
        var successor = prev
        for (k, v) in changes { successor[k] = v }
        successor["v"] = 3
        successor["planVersion"] = prevVersion + 1
        successor["prevPlanHash"] = planHash(prev)
        return signPlan(successor, privateKeyB64: privateKeyB64)
    }

    /// Verify an amendment chain: chain[0] is the root plan, each later
    /// element a successive amendment. Checks, per link: HOST signature
    /// against `keyCache`, planVersion increment of exactly 1, and
    /// prevPlanHash equality with the recomputed predecessor hash.
    public static func verifyAmendmentChain(_ chain: [LtxSignedPlan],
                                            keyCache: [String: LtxNIK]) -> LtxVerifyResult {
        if chain.isEmpty { return LtxVerifyResult(valid: false, reason: "empty_chain") }
        for (i, link) in chain.enumerated() {
            let sig = verifyPlan(link, keyCache: keyCache)
            if !sig.valid {
                return LtxVerifyResult(valid: false, reason: "link_\(i)_\(sig.reason)")
            }
        }
        let root = chain[0].plan
        if root["prevPlanHash"] != nil {
            return LtxVerifyResult(valid: false, reason: "root_has_prev_hash")
        }
        var prevPlan = root
        var prevVersion = root["planVersion"] as? Int ?? 1
        for i in 1..<chain.count {
            let p = chain[i].plan
            if (p["v"] as? Int) != 3 {
                return LtxVerifyResult(valid: false, reason: "link_\(i)_not_v3")
            }
            if (p["planVersion"] as? Int ?? 0) != prevVersion + 1 {
                return LtxVerifyResult(valid: false, reason: "link_\(i)_version_gap")
            }
            if (p["prevPlanHash"] as? String) != planHash(prevPlan) {
                return LtxVerifyResult(valid: false, reason: "link_\(i)_prev_hash_mismatch")
            }
            prevPlan = p
            prevVersion = p["planVersion"] as? Int ?? 0
        }
        return LtxVerifyResult(valid: true)
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. Register entries + reducers (§9/§10, LTX-SECURITY.md §9.5/§9.6)
    // ═════════════════════════════════════════════════════════════════════

    static let registerEntryPrefixes: [String: String] = [
        "question": "QST", "question_response": "QST",
        "action": "ACT", "action_update": "ACT",
        "amendment": "AMD", "state_transition": "STA",
        "merge_snapshot": "MRG", "decision": "DEC",
    ]

    /// Create a signed register entry (LTX-SECURITY.md §9.5). The signature
    /// covers the canonical JSON of the entry without 'sig'.
    public static func createRegisterEntry(type: String,
                                           content: [String: Any],
                                           sessionId: String,
                                           nodeId: String,
                                           seq: Int,
                                           timestamp: String,
                                           privateKeyB64: String,
                                           entryId: String? = nil) -> [String: Any]? {
        guard let seedData = nikB64urlDecode(privateKeyB64), seedData.count == 32,
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seedData)
        else { return nil }
        let id = entryId ?? "\(registerEntryPrefixes[type] ?? "ENT")-\(nodeId)-\(seq)"
        var unsigned: [String: Any] = [
            "entryId": id,
            "sessionId": sessionId,
            "nodeId": nodeId,
            "seq": seq,
            "type": type,
            "content": content,
            "timestamp": timestamp,
        ]
        guard let sig = try? privateKey.signature(for: Data(canonicalJSON(unsigned).utf8))
        else { return nil }
        unsigned["sig"] = nikB64url(sig)
        return unsigned
    }

    /// Verify a register entry signature against a keyCache mapping the
    /// entry's nodeId to its NIK.
    public static func verifyRegisterEntry(_ entry: [String: Any],
                                           keyCache: [String: LtxNIK]) -> LtxVerifyResult {
        guard let sig = entry["sig"] as? String, !sig.isEmpty else {
            return LtxVerifyResult(valid: false, reason: "missing_sig")
        }
        guard let nodeId = entry["nodeId"] as? String, let nik = keyCache[nodeId] else {
            return LtxVerifyResult(valid: false, reason: "key_not_in_cache")
        }
        var unsigned = entry
        unsigned.removeValue(forKey: "sig")
        guard let rawPub = nikB64urlDecode(nik.publicKey), rawPub.count == 32,
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPub),
              let sigData = nikB64urlDecode(sig)
        else { return LtxVerifyResult(valid: false, reason: "invalid_public_key") }
        let ok = pubKey.isValidSignature(sigData, for: Data(canonicalJSON(unsigned).utf8))
        return ok ? LtxVerifyResult(valid: true)
                  : LtxVerifyResult(valid: false, reason: "signature_invalid")
    }

    /// Total order: (timestamp, nodeId, seq) — §8.2.
    public static func compareEntries(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        let ta = a["timestamp"] as? String ?? "", tb = b["timestamp"] as? String ?? ""
        if ta != tb { return ta < tb }
        let na = a["nodeId"] as? String ?? "", nb = b["nodeId"] as? String ?? ""
        if na != nb { return na < nb }
        return (a["seq"] as? Int ?? 0) < (b["seq"] as? Int ?? 0)
    }

    /// De-duplicate by (nodeId, seq) and sort into the §8.2 total order.
    public static func orderEntries(_ entries: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var unique: [[String: Any]] = []
        for e in entries {
            let key = "\(e["nodeId"] as? String ?? "") \(e["seq"] as? Int ?? 0)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(e)
            }
        }
        return unique.sorted(by: compareEntries)
    }

    /// §8.2 conflict rule: higher version wins; tie → lowest editor nodeId.
    private static func conflictWins(_ inVersion: Int, _ inEditor: String,
                                     _ curVersion: Int, _ curEditor: String) -> Bool {
        if inVersion != curVersion { return inVersion > curVersion }
        return inEditor < curEditor
    }

    /// Reduce question register state from log entries (§9.4). Pure:
    /// identical entry sets (in any input order) produce identical state.
    public static func reduceQuestions(_ entries: [[String: Any]]) -> LtxRegisterReduction {
        var byId: [String: [String: Any]] = [:]
        var winners: [String: (version: Int, editor: String, entryId: String)] = [:]
        var superseded: [String] = []

        for e in orderEntries(entries) {
            let content = e["content"] as? [String: Any] ?? [:]
            let nodeId = e["nodeId"] as? String ?? ""
            let entryId = e["entryId"] as? String ?? ""
            if e["type"] as? String == "question" {
                let qid = entryId
                if byId[qid] != nil { superseded.append(entryId); continue }
                winners[qid] = (1, nodeId, entryId)
                var q: [String: Any] = [
                    "qid": qid,
                    "text": content["text"] as? String ?? "",
                    "submitter": nodeId,
                    "status": "OPEN",
                    "version": 1,
                ]
                if let u = content["urgency"] { q["urgency"] = "\(u)" }
                if let w = content["intendedWindow"] { q["intendedWindow"] = "\(w)" }
                byId[qid] = q
            } else if e["type"] as? String == "question_response" {
                let qid = content["qid"] as? String ?? ""
                guard var q = byId[qid] else { superseded.append(entryId); continue }
                let version = content["version"] as? Int ?? ((q["version"] as? Int ?? 1) + 1)
                if let current = winners[qid],
                   !conflictWins(version, nodeId, current.version, current.editor) {
                    superseded.append(entryId)
                    continue
                }
                if let current = winners[qid], current.entryId != qid {
                    superseded.append(current.entryId)
                }
                winners[qid] = (version, nodeId, entryId)
                q["status"] = content["status"] as? String == "WITHDRAWN" ? "WITHDRAWN" : "ANSWERED"
                if let r = content["response"] { q["response"] = "\(r)" }
                q["responder"] = nodeId
                q["version"] = version
                byId[qid] = q
            }
        }
        return LtxRegisterReduction(byId: byId, superseded: superseded)
    }

    static let actionStatuses = ["PROPOSED", "ACCEPTED", "REJECTED", "DONE"]

    /// Reduce action register state from log entries (§10.2).
    public static func reduceActions(_ entries: [[String: Any]]) -> LtxRegisterReduction {
        var byId: [String: [String: Any]] = [:]
        var winners: [String: (version: Int, editor: String, entryId: String)] = [:]
        var superseded: [String] = []

        for e in orderEntries(entries) {
            let content = e["content"] as? [String: Any] ?? [:]
            let nodeId = e["nodeId"] as? String ?? ""
            let entryId = e["entryId"] as? String ?? ""
            if e["type"] as? String == "action" {
                let aid = entryId
                if byId[aid] != nil { superseded.append(entryId); continue }
                winners[aid] = (1, nodeId, entryId)
                var a: [String: Any] = [
                    "aid": aid,
                    "description": content["description"] as? String ?? "",
                    "status": "PROPOSED",
                    "version": 1,
                ]
                if let o = content["owner"] { a["owner"] = "\(o)" }
                if let d = content["dueTimeUTC"] { a["dueTimeUTC"] = "\(d)" }
                if let w = content["originWindow"] { a["originWindow"] = "\(w)" }
                byId[aid] = a
            } else if e["type"] as? String == "action_update" {
                let aid = content["aid"] as? String ?? ""
                guard var a = byId[aid] else { superseded.append(entryId); continue }
                let version = content["version"] as? Int ?? ((a["version"] as? Int ?? 1) + 1)
                if let current = winners[aid],
                   !conflictWins(version, nodeId, current.version, current.editor) {
                    superseded.append(entryId)
                    continue
                }
                if let current = winners[aid], current.entryId != aid {
                    superseded.append(current.entryId)
                }
                winners[aid] = (version, nodeId, entryId)
                if let s = content["status"] as? String, actionStatuses.contains(s) {
                    a["status"] = s
                }
                if let d = content["description"] { a["description"] = "\(d)" }
                if let o = content["owner"] { a["owner"] = "\(o)" }
                if let d = content["dueTimeUTC"] { a["dueTimeUTC"] = "\(d)" }
                a["version"] = version
                byId[aid] = a
            }
        }
        return LtxRegisterReduction(byId: byId, superseded: superseded)
    }

    // ── Merkle audit-log root (RFC 9162 style) ─────────────────────────────
    // Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01||l||r).

    private static func merkleLeafHash(_ entry: [String: Any]) -> Data {
        var data = Data([0x00])
        data.append(Data(canonicalJSON(entry).utf8))
        return Data(SHA256.hash(data: data))
    }

    private static func merkleNodeHash(_ left: Data, _ right: Data) -> Data {
        var data = Data([0x01])
        data.append(left)
        data.append(right)
        return Data(SHA256.hash(data: data))
    }

    private static func merkleRootOf(_ leaves: [Data]) -> Data {
        if leaves.isEmpty { return Data(count: 32) }
        if leaves.count == 1 { return leaves[0] }
        // Split at the largest power of two strictly less than the count.
        var mid = 1
        while mid * 2 < leaves.count { mid *= 2 }
        return merkleNodeHash(merkleRootOf(Array(leaves[0..<mid])),
                              merkleRootOf(Array(leaves[mid...])))
    }

    /// Merkle log root (hex) over the §8.2-ordered entries.
    public static func entriesRoot(_ entries: [[String: Any]]) -> String {
        let leaves = orderEntries(entries).map(merkleLeafHash)
        return merkleRootOf(leaves).map { String(format: "%02x", $0) }.joined()
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. Deterministic CBOR (RFC 8949) + COSE_Sign1 (RFC 9052)
    // ═════════════════════════════════════════════════════════════════════

    public static let coseSign1Tag: UInt64 = 18
    public static let coseAlgEd25519: Int64 = -19

    private static func cborHead(_ major: UInt8, _ arg: UInt64) -> Data {
        if arg < 24 { return Data([(major << 5) | UInt8(arg)]) }
        if arg < 0x100 { return Data([(major << 5) | 24, UInt8(arg)]) }
        if arg < 0x10000 {
            return Data([(major << 5) | 25, UInt8(arg >> 8), UInt8(arg & 0xff)])
        }
        if arg < 0x1_0000_0000 {
            return Data([(major << 5) | 26,
                         UInt8((arg >> 24) & 0xff), UInt8((arg >> 16) & 0xff),
                         UInt8((arg >> 8) & 0xff), UInt8(arg & 0xff)])
        }
        var out = Data([(major << 5) | 27])
        for shift in stride(from: 56, through: 0, by: -8) {
            out.append(UInt8((arg >> UInt64(shift)) & 0xff))
        }
        return out
    }

    /// Encode a CborValue to deterministic CBOR bytes (RFC 8949 §4.2.1):
    /// definite lengths, shortest-form heads, map keys sorted bytewise.
    public static func encodeCbor(_ value: CborValue) -> Data {
        switch value {
        case .null: return Data([0xf6])
        case .bool(let b): return Data([b ? 0xf5 : 0xf4])
        case .int(let n):
            return n >= 0 ? cborHead(0, UInt64(n)) : cborHead(1, UInt64(-n - 1))
        case .text(let s):
            let bytes = Data(s.utf8)
            return cborHead(3, UInt64(bytes.count)) + bytes
        case .bytes(let b):
            return cborHead(2, UInt64(b.count)) + b
        case .tag(let t, let v):
            return cborHead(6, t) + encodeCbor(v)
        case .array(let arr):
            var out = cborHead(4, UInt64(arr.count))
            for v in arr { out.append(encodeCbor(v)) }
            return out
        case .map(let pairs):
            let encoded = pairs.map { (encodeCbor($0.0), encodeCbor($0.1)) }
                .sorted { a, b in
                    for (x, y) in zip(a.0, b.0) where x != y { return x < y }
                    return a.0.count < b.0.count
                }
            var out = cborHead(5, UInt64(encoded.count))
            for (k, v) in encoded {
                out.append(k)
                out.append(v)
            }
            return out
        }
    }

    private struct CborDecodeState {
        let buf: [UInt8]
        var pos: Int = 0
    }

    private static func cborReadHead(_ s: inout CborDecodeState) throws -> (UInt8, UInt64) {
        guard s.pos < s.buf.count else { throw CborError.truncated }
        let initial = s.buf[s.pos]
        s.pos += 1
        let major = initial >> 5
        let info = initial & 0x1f
        if info < 24 { return (major, UInt64(info)) }
        let extra: Int
        switch info {
        case 24: extra = 1
        case 25: extra = 2
        case 26: extra = 4
        case 27: extra = 8
        default: throw CborError.unsupported("indefinite lengths not supported")
        }
        guard s.pos + extra <= s.buf.count else { throw CborError.truncated }
        var arg: UInt64 = 0
        for _ in 0..<extra {
            arg = (arg << 8) | UInt64(s.buf[s.pos])
            s.pos += 1
        }
        return (major, arg)
    }

    private static func cborDecodeItem(_ s: inout CborDecodeState) throws -> CborValue {
        guard s.pos < s.buf.count else { throw CborError.truncated }
        let first = s.buf[s.pos]
        if first == 0xf6 { s.pos += 1; return .null }
        if first == 0xf5 { s.pos += 1; return .bool(true) }
        if first == 0xf4 { s.pos += 1; return .bool(false) }

        let (major, arg) = try cborReadHead(&s)
        switch major {
        case 0:
            guard arg <= UInt64(Int64.max) else { throw CborError.unsupported("integer too large") }
            return .int(Int64(arg))
        case 1:
            guard arg < UInt64(Int64.max) else { throw CborError.unsupported("integer too large") }
            return .int(-Int64(arg) - 1)
        case 2:
            guard s.pos + Int(arg) <= s.buf.count else { throw CborError.truncated }
            let bytes = Data(s.buf[s.pos..<(s.pos + Int(arg))])
            s.pos += Int(arg)
            return .bytes(bytes)
        case 3:
            guard s.pos + Int(arg) <= s.buf.count else { throw CborError.truncated }
            let bytes = Data(s.buf[s.pos..<(s.pos + Int(arg))])
            s.pos += Int(arg)
            guard let str = String(data: bytes, encoding: .utf8) else {
                throw CborError.unsupported("invalid utf8 tstr")
            }
            return .text(str)
        case 4:
            var out: [CborValue] = []
            for _ in 0..<arg { out.append(try cborDecodeItem(&s)) }
            return .array(out)
        case 5:
            var pairs: [(CborValue, CborValue)] = []
            for _ in 0..<arg {
                let k = try cborDecodeItem(&s)
                let v = try cborDecodeItem(&s)
                pairs.append((k, v))
            }
            return .map(pairs)
        case 6:
            return .tag(arg, try cborDecodeItem(&s))
        default:
            throw CborError.unsupported("major type \(major) / simple value")
        }
    }

    /// Decode deterministic CBOR bytes. Rejects floats, indefinite lengths
    /// and trailing bytes.
    public static func decodeCbor(_ bytes: Data) throws -> CborValue {
        var s = CborDecodeState(buf: [UInt8](bytes))
        let value = try cborDecodeItem(&s)
        if s.pos != s.buf.count { throw CborError.trailingBytes }
        return value
    }

    private static func coseSigStructure(_ protectedBytes: Data, _ payload: Data) -> Data {
        return encodeCbor(.array([
            .text("Signature1"), .bytes(protectedBytes), .bytes(Data()), .bytes(payload),
        ]))
    }

    /// Sign a plan as a real CBOR COSE_Sign1 (tag 18). The kid (header label
    /// 4) is the raw 16-byte NIK nodeId — first 16 bytes of SHA-256(pubkey).
    /// Returns ["plan": plan, "coseSign1CborB64": <base64url>].
    public static func signPlanCose(_ plan: [String: Any], privateKeyB64: String) -> [String: Any]? {
        guard let seedData = nikB64urlDecode(privateKeyB64), seedData.count == 32,
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seedData)
        else { return nil }
        let protectedBytes = encodeCbor(.map([(.int(1), .int(coseAlgEd25519))]))
        let payload = Data(canonicalJSON(plan).utf8)
        guard let signature = try? privateKey.signature(
            for: coseSigStructure(protectedBytes, payload)) else { return nil }
        let rawPub = Data(privateKey.publicKey.rawRepresentation)
        let kid = Data(SHA256.hash(data: rawPub)).prefix(16)
        let coseSign1 = CborValue.tag(coseSign1Tag, .array([
            .bytes(protectedBytes),
            .map([(.int(4), .bytes(Data(kid)))]),
            .bytes(payload),
            .bytes(signature),
        ]))
        return ["plan": plan, "coseSign1CborB64": nikB64url(encodeCbor(coseSign1))]
    }

    /// Verify a CBOR COSE_Sign1 plan envelope
    /// (["plan": …, "coseSign1CborB64": …]) against the key cache. Rejects
    /// non-Ed25519 algorithms (including the deprecated -8) and payloads that
    /// do not match the accompanying plan object.
    public static func verifyPlanCose(_ envelope: [String: Any],
                                      keyCache: [String: LtxNIK]) -> LtxVerifyResult {
        guard let b64 = envelope["coseSign1CborB64"] as? String else {
            return LtxVerifyResult(valid: false, reason: "missing_cose_sign1")
        }
        guard let cborData = nikB64urlDecode(b64) else {
            return LtxVerifyResult(valid: false, reason: "cbor_decode_failed")
        }
        guard let decoded = try? decodeCbor(cborData) else {
            return LtxVerifyResult(valid: false, reason: "cbor_decode_failed")
        }
        guard case .tag(let tag, let inner) = decoded, tag == coseSign1Tag else {
            return LtxVerifyResult(valid: false, reason: "not_cose_sign1")
        }
        guard case .array(let arr) = inner, arr.count == 4,
              case .bytes(let protectedBytes) = arr[0],
              case .bytes(let payload) = arr[2],
              case .bytes(let signature) = arr[3]
        else {
            return LtxVerifyResult(valid: false, reason: "malformed_cose_sign1")
        }
        guard let protectedDecoded = try? decodeCbor(protectedBytes),
              case .map(let protectedPairs) = protectedDecoded
        else {
            return LtxVerifyResult(valid: false, reason: "protected_decode_failed")
        }
        var alg: Int64? = nil
        for (k, v) in protectedPairs {
            if case .int(1) = k, case .int(let a) = v { alg = a }
        }
        guard alg == coseAlgEd25519 else {
            return LtxVerifyResult(valid: false, reason: "unsupported_alg")
        }

        var kid = ""
        if case .map(let unprotectedPairs) = arr[1] {
            for (k, v) in unprotectedPairs {
                if case .int(4) = k {
                    if case .bytes(let kb) = v { kid = nikB64url(kb) }
                    if case .text(let ks) = v { kid = ks }
                }
            }
        }
        guard !kid.isEmpty else {
            return LtxVerifyResult(valid: false, reason: "missing_kid")
        }

        var signerNIK = keyCache[kid]
        if signerNIK == nil {
            signerNIK = keyCache.values.first { $0.nodeId.hasPrefix(kid) }
        }
        guard let nik = signerNIK else {
            return LtxVerifyResult(valid: false, reason: "key_not_in_cache")
        }
        if isNIKExpired(nik) {
            return LtxVerifyResult(valid: false, reason: "key_expired")
        }

        guard let rawPub = nikB64urlDecode(nik.publicKey), rawPub.count == 32,
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPub)
        else { return LtxVerifyResult(valid: false, reason: "invalid_public_key") }
        guard pubKey.isValidSignature(signature, for: coseSigStructure(protectedBytes, payload)) else {
            return LtxVerifyResult(valid: false, reason: "signature_invalid")
        }

        if let plan = envelope["plan"] as? [String: Any],
           String(data: payload, encoding: .utf8) != canonicalJSON(plan) {
            return LtxVerifyResult(valid: false, reason: "payload_mismatch")
        }
        return LtxVerifyResult(valid: true)
    }
}
