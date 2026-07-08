package com.interplanet.ltx

// V11.kt -- LTX v1.1 core subset (Epic 72, Story 72.3)
// Kotlin/JVM port of the TypeScript reference (segments.ts / session.ts /
// amend.ts / registers.ts / cbor.ts / cose.ts).
//
// Features:
//   1. v3 planId (SHA-256 over RFC 8785 canonical JSON) + pairDelay +
//      computeSegmentsFor (frozen v2 polynomial path kept byte-identical)
//   2. Pure transition() session state machine (LTX-SPECIFICATION.md §5)
//   3. Amendment-chain verification (§6.4, LTX-SECURITY.md §7.6)
//   4. Signed register entries + deterministic reducers (§8.2/§9/§10)
//   5. Deterministic CBOR decoder + COSE_Sign1 verification (RFC 8949/9052)

import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.time.Instant

// ---- v1.1 data model ----

data class NodeV11(
    val id: String,
    val name: String,
    val role: String,
    val delay: Long = 0,
    val location: String = "earth"
)

data class SegmentTemplateV11(
    val type: String,
    val q: Int,
    val speaker: String? = null,
    val label: String? = null
)

/** LTX plan supporting both v2 (frozen) and v3 (§4.4) schemas. */
data class PlanV11(
    val v: Int = 2,
    val title: String = "",
    val start: String = "",
    val quantum: Int = 3,
    val mode: String = "LTX",
    val nodes: List<NodeV11> = emptyList(),
    val segments: List<SegmentTemplateV11> = emptyList(),
    /** v3 pair-delay matrix; key "A|B" with node ids sorted. */
    val delays: Map<String, Long>? = null,
    val planVersion: Int? = null,
    val prevPlanHash: String? = null
) {
    /** Generic map projection used for canonical JSON hashing. */
    fun toMap(): Map<String, Any?> {
        val m = linkedMapOf<String, Any?>(
            "v" to v,
            "title" to title,
            "start" to start,
            "quantum" to quantum,
            "mode" to mode,
            "nodes" to nodes.map { n ->
                mapOf("id" to n.id, "name" to n.name, "role" to n.role,
                      "delay" to n.delay, "location" to n.location)
            },
            "segments" to segments.map { s ->
                val seg = linkedMapOf<String, Any?>("type" to s.type, "q" to s.q)
                if (s.speaker != null) seg["speaker"] = s.speaker
                if (s.label != null) seg["label"] = s.label
                seg
            }
        )
        if (delays != null) m["delays"] = delays
        if (planVersion != null) m["planVersion"] = planVersion
        if (prevPlanHash != null) m["prevPlanHash"] = prevPlanHash
        return m
    }
}

/** A computed segment from a specific viewer's perspective (§14.3). */
data class ViewerSegmentV11(
    val type: String,
    val q: Int,
    val startMs: Long,
    val endMs: Long,
    val durMin: Int,
    val speaker: String? = null,
    val label: String? = null,
    val perspective: String = "neutral",  // transmit | receive | neutral
    val arrivalOffsetS: Long = 0
)

// ---- v1.1 security envelope / register types ----

data class NikV11(val nodeId: String, val publicKeyB64: String, val validUntil: String)

data class CoseSign1Json(
    val protected: String,
    val kid: String,
    val payload: String,
    val signature: String
)

data class SignedPlanV11(val plan: PlanV11, val coseSign1: CoseSign1Json)

data class RegisterEntryV11(
    val entryId: String,
    val sessionId: String,
    val nodeId: String,
    val seq: Int,
    val type: String,
    val content: Map<String, Any?>,
    val timestamp: String,
    val sig: String
)

data class QuestionStateV11(
    val qid: String,
    val text: String,
    val submitter: String,
    val urgency: String? = null,
    val intendedWindow: String? = null,
    val status: String = "OPEN",  // OPEN | ANSWERED | WITHDRAWN
    val response: String? = null,
    val responder: String? = null,
    val version: Int = 1
)

data class ActionStateV11(
    val aid: String,
    val description: String,
    val owner: String? = null,
    val dueTimeUTC: String? = null,
    val originWindow: String? = null,
    val status: String = "PROPOSED",  // PROPOSED | ACCEPTED | REJECTED | DONE
    val version: Int = 1
)

data class RegisterReductionV11<T>(val byId: Map<String, T>, val superseded: List<String>)

// ---- session state machine types ----

data class SessionEventV11(
    val type: String,
    val nowMs: Long,
    val nodeId: String? = null,
    val planId: String? = null,
    val measuredDelayS: Long? = null,
    val decision: String? = null,
    val verified: Boolean? = null,
    val planVersion: Int? = null,
    val affectedNodeIds: List<String>? = null
)

data class PendingAmendmentV11(
    val planId: String,
    val planVersion: Int,
    val affectedNodeIds: List<String>,
    val confirmed: List<String>,
    val proposedAtMs: Long,
    val timeoutMs: Long
)

data class SessionCtxV11(
    val state: String = "DRAFT",
    val plan: PlanV11,
    val planId: String,
    val sessionRootPlanId: String,
    val planVersion: Int = 1,
    val lock: String? = null,  // FULL | QUORUM | null
    val lockStartedAtMs: Long? = null,
    val lockTimeoutMs: Long = 0,
    val confirmations: Map<String, String> = emptyMap(),
    val mismatched: List<String> = emptyList(),
    val quorumThreshold: Int = 1,
    val subset: List<String>? = null,
    val degradedReasons: List<String> = emptyList(),
    val resumeState: String? = null,
    val pendingAmendment: PendingAmendmentV11? = null
)

// ---- CBOR value ----

/** Tagged CBOR value (major type 6). */
class CborTagV11(val tag: Long, val value: Any?)

class CborException(message: String) : Exception(message)

data class VerifyResultV11(val valid: Boolean, val reason: String? = null)

// ---- static API ----

object LtxV11 {

    const val VERSION = "1.1.0"
    const val COSE_SIGN1_TAG = 18L
    const val COSE_ALG_ED25519 = -19L
    const val DELAY_VIOLATION_DEGRADE_S = 300L
    const val LOCK_TIMEOUT_FACTOR = 2L

    private val SPKI_HEADER = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)

    private fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { String.format("%02x", it) }

    // ---- canonical JSON / hashing ----

    /** SHA-256 hex of the RFC 8785 canonical JSON of a plan (amend.ts). */
    fun planHash(plan: PlanV11): String =
        hex(sha256(LtxSecurity.canonicalJson(plan.toMap()).toByteArray(Charsets.UTF_8)))

    private fun jsonStr(s: String): String {
        val sb = StringBuilder("\"")
        for (ch in s) {
            when (ch) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> sb.append(ch)
            }
        }
        sb.append("\"")
        return sb.toString()
    }

    /**
     * FROZEN v2 JSON serialisation — insertion-order JSON.stringify equivalent:
     * v,title,start,quantum,mode,nodes(id,name,role,delay,location),
     * segments(type,q[,speaker][,label]). Must stay byte-identical (§4.3).
     */
    fun toJsonV2(p: PlanV11): String {
        val sb = StringBuilder("{")
        sb.append("\"v\":").append(p.v)
        sb.append(",\"title\":").append(jsonStr(p.title))
        sb.append(",\"start\":").append(jsonStr(p.start))
        sb.append(",\"quantum\":").append(p.quantum)
        sb.append(",\"mode\":").append(jsonStr(p.mode))
        sb.append(",\"nodes\":[")
        p.nodes.forEachIndexed { i, n ->
            if (i > 0) sb.append(',')
            sb.append("{\"id\":").append(jsonStr(n.id))
            sb.append(",\"name\":").append(jsonStr(n.name))
            sb.append(",\"role\":").append(jsonStr(n.role))
            sb.append(",\"delay\":").append(n.delay)
            sb.append(",\"location\":").append(jsonStr(n.location)).append('}')
        }
        sb.append("],\"segments\":[")
        p.segments.forEachIndexed { i, s ->
            if (i > 0) sb.append(',')
            sb.append("{\"type\":").append(jsonStr(s.type))
            sb.append(",\"q\":").append(s.q)
            if (s.speaker != null) sb.append(",\"speaker\":").append(jsonStr(s.speaker))
            if (s.label != null) sb.append(",\"label\":").append(jsonStr(s.label))
            sb.append('}')
        }
        sb.append("]}")
        return sb.toString()
    }

    // ---- 1. plan ID (v3 SHA-256 + frozen v2 polynomial) ----

    /**
     * Deterministic plan ID. v3 plans hash SHA-256 over RFC 8785 canonical JSON
     * (§4.5, "-v3-" infix); the v2 polynomial path is FROZEN (§4.3).
     */
    fun makePlanId(p: PlanV11): String {
        val date = p.start.substring(0, 10).replace("-", "")
        var hostStr = if (p.nodes.isNotEmpty())
            p.nodes[0].name.replace(Regex("\\s+"), "").uppercase() else "HOST"
        if (hostStr.length > 8) hostStr = hostStr.substring(0, 8)
        var nodeStr = if (p.nodes.size > 1) {
            p.nodes.drop(1).joinToString("-") {
                val s = it.name.replace(Regex("\\s+"), "").uppercase()
                if (s.length > 4) s.substring(0, 4) else s
            }
        } else "RX"
        if (nodeStr.length > 16) nodeStr = nodeStr.substring(0, 16)

        if (p.v >= 3) {
            val digest = planHash(p)
            return "LTX-$date-$hostStr-$nodeStr-v3-${digest.substring(0, 8)}"
        }

        // FROZEN v2 path -- 32-bit polynomial hash over the JSON (UTF-16 units).
        val raw = toJsonV2(p)
        var h = 0
        for (c in raw) h = 31 * h + c.code
        return "LTX-$date-$hostStr-$nodeStr-v2-" + String.format("%08x", h)
    }

    // ---- 1. pairDelay + computeSegmentsFor ----

    /**
     * One-way delay in seconds between two nodes (§3.7). The v3 pair matrix is
     * authoritative where present; fallback: HOST pairs use the node's declared
     * delay, non-HOST pairs the sum of both HOST-relative delays.
     */
    fun pairDelay(p: PlanV11, nodeIdA: String, nodeIdB: String): Long {
        if (nodeIdA == nodeIdB) return 0
        val key = listOf(nodeIdA, nodeIdB).sorted().joinToString("|")
        p.delays?.get(key)?.let { return it }
        val a = p.nodes.find { it.id == nodeIdA }
            ?: throw IllegalArgumentException("pairDelay: unknown node $nodeIdA")
        val b = p.nodes.find { it.id == nodeIdB }
            ?: throw IllegalArgumentException("pairDelay: unknown node $nodeIdB")
        val hostId = p.nodes[0].id
        if (nodeIdA == hostId) return b.delay
        if (nodeIdB == hostId) return a.delay
        return a.delay + b.delay
    }

    private fun parseIsoMs(iso: String): Long = Instant.parse(iso).toEpochMilli()

    /** Base timed segments (epoch ms) for a v1.1 plan. */
    fun computeSegmentsV11(p: PlanV11): List<ViewerSegmentV11> {
        val qMs = p.quantum.toLong() * 60000L
        var t = parseIsoMs(p.start)
        return p.segments.map { s ->
            val durMs = s.q * qMs
            val seg = ViewerSegmentV11(
                type = s.type, q = s.q, startMs = t, endMs = t + durMs,
                durMin = s.q * p.quantum, speaker = s.speaker, label = s.label,
                perspective = "neutral", arrivalOffsetS = 0)
            t += durMs
            seg
        }
    }

    /**
     * Timed segments from viewer V's perspective (§14.3): a segment attributed
     * to speaker S starts for V at segStart + pairDelay(S, V).
     */
    fun computeSegmentsFor(p: PlanV11, viewerNodeId: String): List<ViewerSegmentV11> {
        require(p.nodes.any { it.id == viewerNodeId }) {
            "computeSegmentsFor: unknown viewer $viewerNodeId"
        }
        return computeSegmentsV11(p).mapIndexed { i, seg ->
            val tpl = p.segments[i]
            when {
                tpl.speaker == null || (tpl.type != "TX" && tpl.type != "SPEAK") ->
                    seg.copy(perspective = "neutral", arrivalOffsetS = 0)
                tpl.speaker == viewerNodeId ->
                    seg.copy(perspective = "transmit", arrivalOffsetS = 0)
                else -> {
                    val shiftS = pairDelay(p, tpl.speaker, viewerNodeId)
                    seg.copy(
                        startMs = seg.startMs + shiftS * 1000,
                        endMs = seg.endMs + shiftS * 1000,
                        perspective = "receive",
                        arrivalOffsetS = shiftS)
                }
            }
        }
    }

    // ---- Ed25519 helpers ----

    private fun verifyBytes(data: ByteArray, sigB64: String, nik: NikV11): Boolean = try {
        val rawPub = LtxSecurity.fromBase64Url(nik.publicKeyB64)
        val kf = KeyFactory.getInstance("Ed25519")
        val pubKey = kf.generatePublic(X509EncodedKeySpec(SPKI_HEADER + rawPub))
        val sig = Signature.getInstance("Ed25519")
        sig.initVerify(pubKey)
        sig.update(data)
        sig.verify(LtxSecurity.fromBase64Url(sigB64))
    } catch (_: Exception) {
        false
    }

    private fun isExpired(nik: NikV11): Boolean = try {
        Instant.now().isAfter(Instant.parse(nik.validUntil))
    } catch (_: Exception) {
        false
    }

    private fun lookupKid(kid: String, keyCache: Map<String, NikV11>): NikV11? =
        keyCache[kid] ?: keyCache.values.find { it.nodeId.startsWith(kid) }

    /** Canonical JSON of the Sig_structure array (security.ts). */
    private fun sigStructureJson(protectedB64: String, payloadB64: String): String =
        "[\"Signature1\",${jsonStr(protectedB64)},\"\",${jsonStr(payloadB64)}]"

    /**
     * Verify the TRANSITIONAL JSON COSE_Sign1 plan envelope (LTX-SECURITY §7.2):
     * Ed25519 over canonicalJSON(["Signature1", protected, "", payload]).
     */
    fun verifyPlanEnvelope(sp: SignedPlanV11, keyCache: Map<String, NikV11>): VerifyResultV11 {
        val nik = lookupKid(sp.coseSign1.kid, keyCache)
            ?: return VerifyResultV11(false, "key_not_in_cache")
        if (isExpired(nik)) return VerifyResultV11(false, "key_expired")
        val sigStructure = sigStructureJson(sp.coseSign1.protected, sp.coseSign1.payload)
        if (!verifyBytes(sigStructure.toByteArray(Charsets.UTF_8), sp.coseSign1.signature, nik))
            return VerifyResultV11(false, "signature_invalid")
        val payloadStr = String(LtxSecurity.fromBase64Url(sp.coseSign1.payload), Charsets.UTF_8)
        if (payloadStr != LtxSecurity.canonicalJson(sp.plan.toMap()))
            return VerifyResultV11(false, "payload_mismatch")
        return VerifyResultV11(true)
    }

    // ---- 3. amendment chains (amend.ts) ----

    /**
     * Verify an amendment chain: chain[0] is the root plan, each later element
     * a successive amendment. Checks per link: signature, planVersion +1 steps,
     * prevPlanHash equality with the recomputed predecessor hash; the root must
     * carry no prevPlanHash (LTX-SECURITY.md §7.6).
     */
    fun verifyAmendmentChain(chain: List<SignedPlanV11>, keyCache: Map<String, NikV11>): VerifyResultV11 {
        if (chain.isEmpty()) return VerifyResultV11(false, "empty_chain")
        chain.forEachIndexed { i, link ->
            val sig = verifyPlanEnvelope(link, keyCache)
            if (!sig.valid) return VerifyResultV11(false, "link_${i}_${sig.reason}")
        }
        if (chain[0].plan.prevPlanHash != null)
            return VerifyResultV11(false, "root_has_prev_hash")
        var prevPlan = chain[0].plan
        var prevVersion = chain[0].plan.planVersion ?: 1
        for (i in 1 until chain.size) {
            val p = chain[i].plan
            if (p.v != 3) return VerifyResultV11(false, "link_${i}_not_v3")
            if ((p.planVersion ?: 0) != prevVersion + 1)
                return VerifyResultV11(false, "link_${i}_version_gap")
            if (p.prevPlanHash != planHash(prevPlan))
                return VerifyResultV11(false, "link_${i}_prev_hash_mismatch")
            prevPlan = p
            prevVersion = p.planVersion!!
        }
        return VerifyResultV11(true)
    }

    // ---- 4. register entries + reducers (registers.ts) ----

    private fun entryMap(e: RegisterEntryV11, includeSig: Boolean): Map<String, Any?> {
        val m = linkedMapOf<String, Any?>(
            "entryId" to e.entryId,
            "sessionId" to e.sessionId,
            "nodeId" to e.nodeId,
            "seq" to e.seq,
            "type" to e.type,
            "content" to e.content,
            "timestamp" to e.timestamp
        )
        if (includeSig) m["sig"] = e.sig
        return m
    }

    /** Verify a register entry signature (Ed25519 over canonical JSON sans sig). */
    fun verifyRegisterEntry(entry: RegisterEntryV11, keyCache: Map<String, NikV11>): VerifyResultV11 {
        if (entry.sig.isEmpty()) return VerifyResultV11(false, "missing_sig")
        val nik = keyCache[entry.nodeId] ?: return VerifyResultV11(false, "key_not_in_cache")
        val canon = LtxSecurity.canonicalJson(entryMap(entry, false))
        return if (verifyBytes(canon.toByteArray(Charsets.UTF_8), entry.sig, nik))
            VerifyResultV11(true)
        else VerifyResultV11(false, "signature_invalid")
    }

    /** Total order (timestamp, nodeId, seq) — §8.2. */
    fun compareEntries(a: RegisterEntryV11, b: RegisterEntryV11): Int {
        if (a.timestamp != b.timestamp) return a.timestamp.compareTo(b.timestamp)
        if (a.nodeId != b.nodeId) return a.nodeId.compareTo(b.nodeId)
        return a.seq.compareTo(b.seq)
    }

    /** De-duplicate by (nodeId, seq) and sort into the §8.2 total order. */
    fun orderEntries(entries: List<RegisterEntryV11>): List<RegisterEntryV11> {
        val seen = LinkedHashMap<String, RegisterEntryV11>()
        for (e in entries) seen.putIfAbsent("${e.nodeId} ${e.seq}", e)
        return seen.values.sortedWith { a, b -> compareEntries(a, b) }
    }

    private data class Versioned(val version: Int, val editor: String, val entryId: String)

    /** §8.2 conflict rule: higher version wins; tie -> lowest editor nodeId. */
    private fun wins(incoming: Versioned, current: Versioned): Boolean =
        if (incoming.version != current.version) incoming.version > current.version
        else incoming.editor < current.editor

    private fun asInt(v: Any?, fallback: Int): Int = when (v) {
        is Int -> v
        is Long -> v.toInt()
        is String -> v.toIntOrNull() ?: fallback
        else -> fallback
    }

    /** Reduce question register state from log entries (§9.4). */
    fun reduceQuestions(entries: List<RegisterEntryV11>): RegisterReductionV11<QuestionStateV11> {
        val byId = mutableMapOf<String, QuestionStateV11>()
        val winners = mutableMapOf<String, Versioned>()
        val superseded = mutableListOf<String>()

        for (e in orderEntries(entries)) {
            when (e.type) {
                "question" -> {
                    val qid = e.entryId
                    if (byId.containsKey(qid)) { superseded.add(e.entryId); continue }
                    winners[qid] = Versioned(1, e.nodeId, e.entryId)
                    byId[qid] = QuestionStateV11(
                        qid = qid,
                        text = e.content["text"]?.toString() ?: "",
                        submitter = e.nodeId,
                        urgency = e.content["urgency"]?.toString(),
                        intendedWindow = e.content["intendedWindow"]?.toString(),
                        status = "OPEN",
                        version = 1)
                }
                "question_response" -> {
                    val qid = e.content["qid"]?.toString() ?: ""
                    val q = byId[qid]
                    if (q == null) { superseded.add(e.entryId); continue }
                    val version = asInt(e.content["version"], q.version + 1)
                    val incoming = Versioned(version, e.nodeId, e.entryId)
                    val current = winners[qid]
                    if (current != null) {
                        if (!wins(incoming, current)) { superseded.add(e.entryId); continue }
                        if (current.entryId != q.qid) superseded.add(current.entryId)
                    }
                    winners[qid] = incoming
                    val status = if (e.content["status"] == "WITHDRAWN") "WITHDRAWN" else "ANSWERED"
                    byId[qid] = q.copy(
                        status = status,
                        response = e.content["response"]?.toString() ?: q.response,
                        responder = e.nodeId,
                        version = version)
                }
            }
        }
        return RegisterReductionV11(byId, superseded)
    }

    private val ACTION_STATUSES = setOf("PROPOSED", "ACCEPTED", "REJECTED", "DONE")

    /** Reduce action register state from log entries (§10.2). */
    fun reduceActions(entries: List<RegisterEntryV11>): RegisterReductionV11<ActionStateV11> {
        val byId = mutableMapOf<String, ActionStateV11>()
        val winners = mutableMapOf<String, Versioned>()
        val superseded = mutableListOf<String>()

        for (e in orderEntries(entries)) {
            when (e.type) {
                "action" -> {
                    val aid = e.entryId
                    if (byId.containsKey(aid)) { superseded.add(e.entryId); continue }
                    winners[aid] = Versioned(1, e.nodeId, e.entryId)
                    byId[aid] = ActionStateV11(
                        aid = aid,
                        description = e.content["description"]?.toString() ?: "",
                        owner = e.content["owner"]?.toString(),
                        dueTimeUTC = e.content["dueTimeUTC"]?.toString(),
                        originWindow = e.content["originWindow"]?.toString(),
                        status = "PROPOSED",
                        version = 1)
                }
                "action_update" -> {
                    val aid = e.content["aid"]?.toString() ?: ""
                    val a = byId[aid]
                    if (a == null) { superseded.add(e.entryId); continue }
                    val version = asInt(e.content["version"], a.version + 1)
                    val incoming = Versioned(version, e.nodeId, e.entryId)
                    val current = winners[aid]
                    if (current != null) {
                        if (!wins(incoming, current)) { superseded.add(e.entryId); continue }
                        if (current.entryId != a.aid) superseded.add(current.entryId)
                    }
                    winners[aid] = incoming
                    val status = e.content["status"]?.toString()
                        ?.takeIf { it in ACTION_STATUSES } ?: a.status
                    byId[aid] = a.copy(
                        status = status,
                        description = e.content["description"]?.toString() ?: a.description,
                        owner = e.content["owner"]?.toString() ?: a.owner,
                        dueTimeUTC = e.content["dueTimeUTC"]?.toString() ?: a.dueTimeUTC,
                        version = version)
                }
            }
        }
        return RegisterReductionV11(byId, superseded)
    }

    // ---- Merkle root over ordered entries (merkle.ts / merge.ts) ----

    private fun leafHash(entryBytes: ByteArray): ByteArray =
        sha256(byteArrayOf(0x00) + entryBytes)

    private fun nodeHash(left: ByteArray, right: ByteArray): ByteArray =
        sha256(byteArrayOf(0x01) + left + right)

    private fun rootOf(leaves: List<ByteArray>): ByteArray {
        if (leaves.isEmpty()) return ByteArray(32)
        if (leaves.size == 1) return leaves[0]
        val mid = 1 shl kotlin.math.floor(
            kotlin.math.log2((leaves.size - 1).toDouble())).toInt()
        return nodeHash(rootOf(leaves.subList(0, mid)), rootOf(leaves.subList(mid, leaves.size)))
    }

    /**
     * RFC 9162-style Merkle root (hex) over an ordered entry list.
     * Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01 || L || R).
     */
    fun entriesRoot(entries: List<RegisterEntryV11>): String {
        val leaves = entries.map {
            leafHash(LtxSecurity.canonicalJson(entryMap(it, true)).toByteArray(Charsets.UTF_8))
        }
        return hex(rootOf(leaves))
    }

    // ---- 5. CBOR decode (RFC 8949 deterministic subset, cbor.ts) ----

    private class DecodeState(val buf: ByteArray, var pos: Int = 0)

    private fun readHead(s: DecodeState): Pair<Int, Long> {
        if (s.pos >= s.buf.size) throw CborException("cbor: truncated")
        val initial = s.buf[s.pos].toInt() and 0xff
        s.pos += 1
        val major = initial shr 5
        val info = initial and 0x1f
        return when {
            info < 24 -> major to info.toLong()
            info == 24 -> {
                if (s.pos >= s.buf.size) throw CborException("cbor: truncated")
                val v = (s.buf[s.pos].toInt() and 0xff).toLong(); s.pos += 1; major to v
            }
            info == 25 -> {
                if (s.pos + 2 > s.buf.size) throw CborException("cbor: truncated")
                var v = 0L
                repeat(2) { v = (v shl 8) or (s.buf[s.pos + it].toLong() and 0xff) }
                s.pos += 2; major to v
            }
            info == 26 -> {
                if (s.pos + 4 > s.buf.size) throw CborException("cbor: truncated")
                var v = 0L
                repeat(4) { v = (v shl 8) or (s.buf[s.pos + it].toLong() and 0xff) }
                s.pos += 4; major to v
            }
            info == 27 -> {
                if (s.pos + 8 > s.buf.size) throw CborException("cbor: truncated")
                var v = 0L
                repeat(8) { v = (v shl 8) or (s.buf[s.pos + it].toLong() and 0xff) }
                s.pos += 8
                if (v < 0) throw CborException("cbor: integer too large")
                major to v
            }
            else -> throw CborException("cbor: indefinite lengths not supported")
        }
    }

    private fun decodeItem(s: DecodeState): Any? {
        if (s.pos >= s.buf.size) throw CborException("cbor: truncated")
        when (s.buf[s.pos].toInt() and 0xff) {
            0xf6 -> { s.pos += 1; return null }
            0xf5 -> { s.pos += 1; return true }
            0xf4 -> { s.pos += 1; return false }
        }
        val (major, arg) = readHead(s)
        return when (major) {
            0 -> arg
            1 -> -arg - 1
            2 -> {
                val n = arg.toInt()
                if (s.pos + n > s.buf.size) throw CborException("cbor: truncated bstr")
                val bytes = s.buf.copyOfRange(s.pos, s.pos + n)
                s.pos += n
                bytes
            }
            3 -> {
                val n = arg.toInt()
                if (s.pos + n > s.buf.size) throw CborException("cbor: truncated tstr")
                val str = String(s.buf, s.pos, n, Charsets.UTF_8)
                s.pos += n
                str
            }
            4 -> (0 until arg).map { decodeItem(s) }
            5 -> {
                val map = LinkedHashMap<Any, Any?>()
                for (i in 0 until arg) {
                    val k = decodeItem(s)
                    val key: Any = if (k is ByteArray) LtxSecurity.toBase64Url(k) else k!!
                    map[key] = decodeItem(s)
                }
                map
            }
            6 -> CborTagV11(arg, decodeItem(s))
            else -> throw CborException("cbor: unsupported major type $major / simple value")
        }
    }

    /**
     * Decode deterministic CBOR bytes (ints, bstr, tstr, array, map, tag,
     * bool/null). Rejects floats, indefinite lengths, and trailing bytes.
     */
    fun decodeCbor(bytes: ByteArray): Any? {
        val s = DecodeState(bytes)
        val value = decodeItem(s)
        if (s.pos != bytes.size) throw CborException("cbor: trailing bytes")
        return value
    }

    // ---- 5. COSE_Sign1 verification (RFC 9052, cose.ts) ----

    private fun encodeCborHead(major: Int, arg: Int): ByteArray = when {
        arg < 24 -> byteArrayOf(((major shl 5) or arg).toByte())
        arg < 0x100 -> byteArrayOf(((major shl 5) or 24).toByte(), arg.toByte())
        arg < 0x10000 -> byteArrayOf(((major shl 5) or 25).toByte(),
            (arg shr 8).toByte(), arg.toByte())
        else -> byteArrayOf(((major shl 5) or 26).toByte(),
            (arg shr 24).toByte(), (arg shr 16).toByte(), (arg shr 8).toByte(), arg.toByte())
    }

    /** Sig_structure = CBOR ["Signature1", protected, h'', payload]. */
    private fun sigStructureBytes(protectedBytes: ByteArray, payload: ByteArray): ByteArray =
        encodeCborHead(4, 4) +
        encodeCborHead(3, 10) + "Signature1".toByteArray(Charsets.UTF_8) +
        encodeCborHead(2, protectedBytes.size) + protectedBytes +
        encodeCborHead(2, 0) +
        encodeCborHead(2, payload.size) + payload

    /**
     * Verify a CBOR COSE_Sign1 plan envelope (tag 18, RFC 9052) against the key
     * cache. Rejects non-Ed25519 algorithms (protected {1: -19} required) and
     * payloads that do not match the plan's canonical JSON.
     */
    fun verifyPlanCose(plan: PlanV11?, coseSign1CborB64: String,
                       keyCache: Map<String, NikV11>): VerifyResultV11 {
        if (coseSign1CborB64.isEmpty()) return VerifyResultV11(false, "missing_cose_sign1")
        val decoded = try {
            decodeCbor(LtxSecurity.fromBase64Url(coseSign1CborB64))
        } catch (_: Exception) {
            return VerifyResultV11(false, "cbor_decode_failed")
        }
        if (decoded !is CborTagV11 || decoded.tag != COSE_SIGN1_TAG)
            return VerifyResultV11(false, "not_cose_sign1")
        val arr = decoded.value as? List<*> ?: return VerifyResultV11(false, "malformed_cose_sign1")
        if (arr.size != 4) return VerifyResultV11(false, "malformed_cose_sign1")
        val protectedBytes = arr[0] as? ByteArray ?: return VerifyResultV11(false, "malformed_cose_sign1")
        val payload = arr[2] as? ByteArray ?: return VerifyResultV11(false, "malformed_cose_sign1")
        val signature = arr[3] as? ByteArray ?: return VerifyResultV11(false, "malformed_cose_sign1")

        val protectedMap = try {
            decodeCbor(protectedBytes) as? Map<*, *>
        } catch (_: Exception) {
            return VerifyResultV11(false, "protected_decode_failed")
        } ?: return VerifyResultV11(false, "protected_decode_failed")
        if (protectedMap[1L] != COSE_ALG_ED25519)
            return VerifyResultV11(false, "unsupported_alg")

        val kidRaw = (arr[1] as? Map<*, *>)?.get(4L)
        val kid = when (kidRaw) {
            is ByteArray -> LtxSecurity.toBase64Url(kidRaw)
            is String -> kidRaw
            else -> ""
        }
        if (kid.isEmpty()) return VerifyResultV11(false, "missing_kid")

        val nik = lookupKid(kid, keyCache) ?: return VerifyResultV11(false, "key_not_in_cache")
        if (isExpired(nik)) return VerifyResultV11(false, "key_expired")

        val sigStructure = sigStructureBytes(protectedBytes, payload)
        if (!verifyBytes(sigStructure, LtxSecurity.toBase64Url(signature), nik))
            return VerifyResultV11(false, "signature_invalid")

        if (plan != null &&
            String(payload, Charsets.UTF_8) != LtxSecurity.canonicalJson(plan.toMap()))
            return VerifyResultV11(false, "payload_mismatch")
        return VerifyResultV11(true)
    }

    // ---- 2. session state machine (session.ts) ----

    private fun participants(p: PlanV11): List<NodeV11> =
        p.nodes.filter { it.role == "PARTICIPANT" }

    /** 2 x one-way delay to the furthest node, in ms (§5.1). */
    fun lockTimeoutMs(p: PlanV11): Long =
        LOCK_TIMEOUT_FACTOR * (p.nodes.maxOfOrNull { it.delay } ?: 0L) * 1000L

    private fun quorumCount(p: PlanV11, quorum: Any?): Int {
        val total = participants(p).size
        return when (quorum) {
            "majority" -> total / 2 + 1
            is Int -> quorum.coerceIn(1, total)
            else -> total  // "all" (default)
        }
    }

    /** Create a session context in DRAFT state (§5). */
    fun createSession(plan: PlanV11, planId: String, quorum: Any? = null): SessionCtxV11 =
        SessionCtxV11(
            state = "DRAFT",
            plan = plan,
            planId = planId,
            sessionRootPlanId = planId,
            planVersion = plan.planVersion ?: 1,
            lockTimeoutMs = lockTimeoutMs(plan),
            quorumThreshold = quorumCount(plan, quorum))

    private fun fullLockReached(ctx: SessionCtxV11): Boolean =
        participants(ctx.plan).all { ctx.confirmations[it.id] == ctx.planId }

    private fun quorumReached(ctx: SessionCtxV11): Boolean =
        participants(ctx.plan).count { ctx.confirmations[it.id] == ctx.planId } >= ctx.quorumThreshold

    /** Ascending-delay fallback ordering over confirmed participants (§5.3). */
    private fun confirmedSubset(ctx: SessionCtxV11): List<String> {
        val host = ctx.plan.nodes[0]
        val confirmed = participants(ctx.plan)
            .filter { ctx.confirmations[it.id] == ctx.planId }
            .sortedBy { it.delay }
            .map { it.id }
        return listOf(host.id) + confirmed
    }

    /** Declared one-way delay: v3 pair matrix HOST row, else node.delay. */
    private fun declaredDelayS(p: PlanV11, nodeId: String): Long? {
        val node = p.nodes.find { it.id == nodeId } ?: return null
        if (p.delays != null) {
            val hostId = p.nodes[0].id
            val key = listOf(hostId, nodeId).sorted().joinToString("|")
            p.delays[key]?.let { return it }
        }
        return node.delay
    }

    private fun degrade(ctx: SessionCtxV11, reason: String): SessionCtxV11 {
        val next = ctx.copy(degradedReasons = ctx.degradedReasons + reason)
        return if (ctx.state == "DEGRADED") next else next.copy(state = "DEGRADED")
    }

    /**
     * Advance the session state machine. Pure: same (ctx, event) always yields
     * the same result. Side-effects of the reference implementation are
     * simplified away -- the state/lock sequence matches the reference exactly.
     */
    fun transition(ctx: SessionCtxV11, ev: SessionEventV11): SessionCtxV11 {
        when (ev.type) {
            "START_LOCK" -> {
                if (ctx.state != "DRAFT") return ctx
                val hostId = ctx.plan.nodes[0].id
                return ctx.copy(
                    state = "LOCKING",
                    lockStartedAtMs = ev.nowMs,
                    confirmations = ctx.confirmations + (hostId to ctx.planId))
            }

            "PLAN_CONFIRM" -> {
                if (ctx.state != "LOCKING" && ctx.state != "DEGRADED") return ctx
                val nodeId = ev.nodeId ?: return ctx
                val planId = ev.planId ?: return ctx
                var next = ctx.copy(confirmations = ctx.confirmations + (nodeId to planId))
                if (planId != ctx.planId) {
                    return next.copy(mismatched = next.mismatched.filter { it != nodeId } + nodeId)
                }
                next = next.copy(mismatched = next.mismatched.filter { it != nodeId })
                if (fullLockReached(next)) {
                    // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                    return next.copy(state = "LOCKED", lock = "FULL", subset = null)
                }
                return next
            }

            "TICK" -> {
                if (ctx.state != "LOCKING" || ctx.lockStartedAtMs == null) return ctx
                if (ev.nowMs - ctx.lockStartedAtMs < ctx.lockTimeoutMs) return ctx
                // Lock timeout expired (§5.1).
                if (quorumReached(ctx)) {
                    val subset = confirmedSubset(ctx)
                    return degrade(ctx.copy(lock = "QUORUM", subset = subset),
                        "quorum lock with subset [${subset.joinToString(",")}]")
                }
                return degrade(ctx, "plan-lock timeout without quorum")
            }

            "SESSION_START" -> {
                // DEGRADED start requires HOST_DECISION continue (§5.2).
                return if (ctx.state == "LOCKED") ctx.copy(state = "ACTIVE") else ctx
            }

            "DELAY_MEASURED" -> {
                if (ctx.state != "ACTIVE" && ctx.state != "LOCKED" && ctx.state != "DEGRADED")
                    return ctx
                val nodeId = ev.nodeId ?: return ctx
                val measured = ev.measuredDelayS ?: return ctx
                val declared = declaredDelayS(ctx.plan, nodeId) ?: return ctx
                if (kotlin.math.abs(measured - declared) > DELAY_VIOLATION_DEGRADE_S)
                    return degrade(ctx,
                        "delay violation $nodeId: measured ${measured}s vs declared ${declared}s")
                return ctx
            }

            "EOK_OVERRIDE" -> {
                if (ctx.state == "COMPLETE" || ctx.state == "ABORTED") return ctx
                if (ev.verified != true) return ctx
                if (ctx.state == "EMERGENCY_HOLD") return ctx
                return ctx.copy(state = "EMERGENCY_HOLD", resumeState = ctx.state)
            }

            "AMENDMENT_PROPOSED" -> {
                if (ctx.state != "ACTIVE" && ctx.state != "LOCKED" && ctx.state != "DEGRADED")
                    return ctx
                val planId = ev.planId ?: return ctx
                val planVersion = ev.planVersion ?: return ctx
                val affected = ev.affectedNodeIds ?: return ctx
                if (planVersion != ctx.planVersion + 1) return ctx
                // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
                val maxDelayS = ctx.plan.nodes
                    .filter { it.id in affected }
                    .maxOfOrNull { it.delay } ?: 0L
                return ctx.copy(pendingAmendment = PendingAmendmentV11(
                    planId = planId, planVersion = planVersion,
                    affectedNodeIds = affected, confirmed = emptyList(),
                    proposedAtMs = ev.nowMs,
                    timeoutMs = LOCK_TIMEOUT_FACTOR * maxDelayS * 1000L))
            }

            "AMENDMENT_CONFIRMED" -> {
                val pa = ctx.pendingAmendment ?: return ctx
                if (ev.planId != pa.planId || ev.nodeId == null) return ctx
                if (ev.nodeId !in pa.affectedNodeIds) return ctx
                val confirmed = pa.confirmed.filter { it != ev.nodeId } + ev.nodeId
                if (confirmed.size < pa.affectedNodeIds.size)
                    return ctx.copy(pendingAmendment = pa.copy(confirmed = confirmed))
                // All affected nodes confirmed -- the amendment applies.
                return ctx.copy(planId = pa.planId, planVersion = pa.planVersion,
                    pendingAmendment = null)
            }

            "HOST_DECISION" -> {
                return when {
                    ev.decision == "abort" ->
                        if (ctx.state == "COMPLETE" || ctx.state == "ABORTED") ctx
                        else ctx.copy(state = "ABORTED")
                    ev.decision == "resume" && ctx.state == "EMERGENCY_HOLD" ->
                        ctx.copy(state = ctx.resumeState ?: "ACTIVE", resumeState = null)
                    ev.decision == "continue" && ctx.state == "DEGRADED" ->
                        ctx.copy(state = "ACTIVE")  // §5.2: HOST continues with subset.
                    else -> ctx
                }
            }

            "SESSION_END" -> {
                return if (ctx.state == "ACTIVE" || ctx.state == "DEGRADED")
                    ctx.copy(state = "COMPLETE") else ctx
            }

            else -> return ctx
        }
    }
}
