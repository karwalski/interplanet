package com.interplanet.ltx

// PlanJson.kt -- generic (untyped) plan layer mirroring javascript/ltx/ltx-sdk.js.
//
// The typed models (LtxPlan, PlanV11) serialise their fields in a fixed order,
// but the frozen v2 planId (LTX-SPECIFICATION.md §4.3) hashes JSON.stringify of
// the plan *in insertion order*, and the golden vectors (spec/golden/plan-ids.json)
// include plans with arbitrary key order, relay objects and v3 fields. This
// file therefore works on plain JSON values:
//
//   Map<String, Any?> (LinkedHashMap, insertion order), List<Any?>, String,
//   Long / Int / Double, Boolean, null
//
// and provides: a JSON parser, JSON.stringify and canonicalJSON equivalents,
// makePlanId / planHash over such maps, and validatePlan with the reserved
// streams (§3.5) / branching (§7) rules.

import java.math.BigDecimal
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset

/** One validatePlan error: { code, path, message } (LTX-SPECIFICATION.md §4.6). */
data class PlanError(val code: String, val path: String, val message: String)

/** validatePlan result: { valid, errors }. */
data class PlanValidation(val valid: Boolean, val errors: List<PlanError>)

/**
 * Thrown by createSession (and any other enforcement point) when a plan uses a
 * reserved field. [code] is the first error's code: reserved_streams or
 * reserved_branching; [errors] carries every violation.
 */
class LtxPlanException(val code: String, val errors: List<PlanError>, message: String) :
    IllegalArgumentException(message)

object LtxJson {

    // ---- parse ----

    /**
     * Parse JSON text. Objects become LinkedHashMap (insertion order kept),
     * arrays List, integers Long (Double if they overflow), other numbers Double.
     */
    fun parse(text: String): Any? {
        val p = Parser(text)
        p.ws()
        val v = p.value()
        p.ws()
        if (p.i != text.length) throw IllegalArgumentException("JSON: trailing characters at ${p.i}")
        return v
    }

    private class Parser(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && s[i] in " \t\r\n") i++ }
        fun value(): Any? {
            if (i >= s.length) throw IllegalArgumentException("JSON: unexpected end")
            return when (s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> num()
            }
        }
        fun lit(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) throw IllegalArgumentException("JSON: bad literal at $i")
            i += word.length
            return v
        }
        fun obj(): Map<String, Any?> {
            val m = LinkedHashMap<String, Any?>()
            i++; ws()
            if (s[i] == '}') { i++; return m }
            while (true) {
                ws()
                val k = str()
                ws()
                if (s[i] != ':') throw IllegalArgumentException("JSON: expected ':' at $i")
                i++; ws()
                // JSON.parse keeps the first position and the last value for a duplicate key.
                m[k] = value()
                ws()
                when (s[i]) {
                    ',' -> i++
                    '}' -> { i++; return m }
                    else -> throw IllegalArgumentException("JSON: expected ',' or '}' at $i")
                }
            }
        }
        fun arr(): List<Any?> {
            val l = ArrayList<Any?>()
            i++; ws()
            if (s[i] == ']') { i++; return l }
            while (true) {
                ws()
                l.add(value())
                ws()
                when (s[i]) {
                    ',' -> i++
                    ']' -> { i++; return l }
                    else -> throw IllegalArgumentException("JSON: expected ',' or ']' at $i")
                }
            }
        }
        fun str(): String {
            if (s[i] != '"') throw IllegalArgumentException("JSON: expected string at $i")
            i++
            val sb = StringBuilder()
            while (true) {
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        when (val e = s[i++]) {
                            '"' -> sb.append('"'); '\\' -> sb.append('\\'); '/' -> sb.append('/')
                            'b' -> sb.append('\b'); 'f' -> sb.append('\u000c')
                            'n' -> sb.append('\n'); 'r' -> sb.append('\r'); 't' -> sb.append('\t')
                            'u' -> { sb.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                            else -> throw IllegalArgumentException("JSON: bad escape \\$e")
                        }
                    }
                    else -> sb.append(c)
                }
            }
        }
        fun num(): Any {
            val start = i
            if (s[i] == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] in ".eE+-")) i++
            val tok = s.substring(start, i)
            if (tok.isEmpty() || tok == "-") throw IllegalArgumentException("JSON: bad number at $start")
            if (tok.any { it in ".eE" }) return tok.toDouble()
            return tok.toLongOrNull() ?: tok.toDouble()
        }
    }

    // ---- stringify (JSON.stringify semantics) ----

    /** JSON.stringify(v): insertion-order keys, no whitespace. */
    fun stringify(v: Any?): String = StringBuilder().also { write(it, v, false) }.toString()

    /** canonicalJSON(v) exactly as ltx-sdk.js: keys sorted by UTF-16 code units. */
    fun canonical(v: Any?): String = StringBuilder().also { write(it, v, true) }.toString()

    private fun write(sb: StringBuilder, v: Any?, sorted: Boolean) {
        when (v) {
            null -> sb.append("null")
            is Boolean -> sb.append(if (v) "true" else "false")
            is String -> quote(sb, v)
            is Int, is Long, is Short, is Byte -> sb.append(v.toString())
            is Double -> sb.append(jsNumber(v))
            is Float -> sb.append(jsNumber(v.toDouble()))
            is Number -> sb.append(jsNumber(v.toDouble()))
            is Map<*, *> -> {
                sb.append('{')
                val keys = v.keys.map { it.toString() }.let { if (sorted) it.sorted() else it }
                var first = true
                for (k in keys) {
                    if (!first) sb.append(',')
                    first = false
                    quote(sb, k)
                    sb.append(':')
                    write(sb, v[k], sorted)
                }
                sb.append('}')
            }
            is List<*> -> {
                sb.append('[')
                v.forEachIndexed { idx, e -> if (idx > 0) sb.append(','); write(sb, e, sorted) }
                sb.append(']')
            }
            else -> quote(sb, v.toString())
        }
    }

    /** JSON.stringify string quoting (ES2019 well-formed: lone surrogates escaped). */
    fun quote(sb: StringBuilder, s: String) {
        sb.append('"')
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                c == '"' -> sb.append("\\\"")
                c == '\\' -> sb.append("\\\\")
                c == '\b' -> sb.append("\\b")
                c == '\u000c' -> sb.append("\\f")
                c == '\n' -> sb.append("\\n")
                c == '\r' -> sb.append("\\r")
                c == '\t' -> sb.append("\\t")
                c < ' ' -> sb.append(String.format("\\u%04x", c.code))
                Character.isHighSurrogate(c) && i + 1 < s.length && Character.isLowSurrogate(s[i + 1]) -> {
                    sb.append(c).append(s[i + 1]); i++
                }
                Character.isSurrogate(c) -> sb.append(String.format("\\u%04x", c.code))
                else -> sb.append(c)
            }
            i++
        }
        sb.append('"')
    }

    /** ECMAScript Number::toString for finite doubles; NaN/Infinity -> "null" as in JSON. */
    fun jsNumber(d: Double): String {
        if (d.isNaN() || d.isInfinite()) return "null"
        if (d == 0.0) return "0"
        val bd = BigDecimal(d.toString()).stripTrailingZeros()
        val neg = bd.signum() < 0
        val digits = bd.unscaledValue().abs().toString()
        val k = digits.length
        val n = k - bd.scale()  // decimal point position: value = 0.digits * 10^n
        val body = when {
            n in k..21 -> digits + "0".repeat(n - k)
            n in 1..21 -> digits.substring(0, n) + "." + digits.substring(n)
            n in -5..0 -> "0." + "0".repeat(-n) + digits
            else -> {
                val e = n - 1
                val mant = if (k == 1) digits else digits[0] + "." + digits.substring(1)
                mant + "e" + (if (e >= 0) "+" else "-") + kotlin.math.abs(e)
            }
        }
        return if (neg) "-$body" else body
    }
}

object LtxPlans {

    /** Every segment type the reference SDKs handle (core §3.4 + auxiliary). */
    val PLAN_SEGMENT_TYPES = listOf("PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
        "SPEAK", "REST", "PAD", "OPEN", "RELAY")
    val PLAN_MODES = listOf("LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC")
    /** Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3). */
    val V3_ONLY_FIELDS = listOf("delays", "planVersion", "prevPlanHash", "questions", "actions", "streams")
    /** Reserved branching identifiers (§7): MUST be absent from plans and segments. */
    val RESERVED_BRANCH_PLAN_FIELDS = listOf("branches", "branching")
    val RESERVED_BRANCH_SEGMENT_FIELDS = listOf("branch")
    /** Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream. */
    val RESERVED_STREAM_SEGMENT_FIELDS = listOf("stream")

    private val NODE_ROLES = listOf("HOST", "PARTICIPANT", "OBSERVER")
    private val HEX64 = Regex("^[0-9a-f]{64}$")

    // ---- JS value helpers ----

    private fun isNum(v: Any?) = v is Number
    private fun num(v: Any?): Double = (v as Number).toDouble()
    /** Number.isInteger */
    private fun isInteger(v: Any?): Boolean = when (v) {
        is Int, is Long, is Short, is Byte -> true
        is Double -> !v.isInfinite() && !v.isNaN() && v == Math.floor(v)
        is Float -> v.toDouble().let { !it.isInfinite() && !it.isNaN() && it == Math.floor(it) }
        else -> false
    }
    /** JS strict equality against a number literal. */
    private fun numEq(v: Any?, n: Int) = isNum(v) && num(v) == n.toDouble()
    /** JS truthiness. */
    private fun truthy(v: Any?): Boolean = when (v) {
        null -> false
        is Boolean -> v
        is String -> v.isNotEmpty()
        is Number -> num(v) != 0.0 && !num(v).isNaN()
        else -> true
    }

    /** Array.prototype.includes / Set.prototype.has for an untyped value. */
    private fun anyIn(v: Any?, c: Collection<String>): Boolean = v is String && v in c

    /** JS \s (WhiteSpace and LineTerminator). */
    internal fun isJsSpace(c: Char): Boolean =
        c in "\t\n\u000b\u000c\r       　﻿" || c in ' '..' '

    internal fun stripSpaceUpper(s: String): String =
        s.filterNot { isJsSpace(it) }.uppercase(java.util.Locale.ROOT)

    /** Date.parse; null when JS would return NaN (subset: ISO 8601 forms). */
    private fun parseDateMs(s: String): Long? {
        try { return Instant.parse(s).toEpochMilli() } catch (_: Exception) {}
        try { return OffsetDateTime.parse(s).toInstant().toEpochMilli() } catch (_: Exception) {}
        try { return LocalDate.parse(s).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli() } catch (_: Exception) {}
        try { return LocalDateTime.parse(s).toInstant(ZoneOffset.UTC).toEpochMilli() } catch (_: Exception) {}
        return null
    }

    // ---- upgradeConfig / makePlanId / planHash ----

    /** upgradeConfig(cfg): v1 -> v2 (unchanged for v2/v3 plans with nodes). */
    fun upgradeConfig(cfg: Map<String, Any?>): Map<String, Any?> {
        val v = cfg["v"]
        val nodes = cfg["nodes"]
        if (isNum(v) && num(v) >= 2 && nodes is List<*> && nodes.isNotEmpty()) return cfg
        val rxName = (cfg["rxName"] as? String ?: "").lowercase(java.util.Locale.ROOT)
        val remoteLoc = if ("mars" in rxName) "mars" else if ("moon" in rxName) "moon" else "earth"
        val out = LinkedHashMap(cfg)
        out["v"] = 2L
        out["nodes"] = listOf(
            linkedMapOf("id" to "N0", "name" to (cfg["txName"].takeIf { truthy(it) } ?: "Earth HQ"),
                "role" to "HOST", "delay" to 0L, "location" to "earth"),
            linkedMapOf("id" to "N1", "name" to (cfg["rxName"].takeIf { truthy(it) } ?: "Mars Hab-01"),
                "role" to "PARTICIPANT", "delay" to (cfg["delay"].takeIf { truthy(it) } ?: 0L),
                "location" to remoteLoc))
        return out
    }

    private fun sha256Hex(s: String): String =
        MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))
            .joinToString("") { String.format("%02x", it) }

    /** SHA-256 hex of the canonical JSON of a plan (prevPlanHash, §6.4). */
    fun planHash(plan: Map<String, Any?>): String = sha256Hex(LtxJson.canonical(plan))

    /**
     * makePlanId over a plain plan map, exactly as ltx-sdk.js: v2 is the FROZEN
     * imul31 hash of JSON.stringify in insertion order (§4.3); v3 is SHA-256 over
     * canonical JSON (§4.5).
     */
    fun makePlanId(cfg: Map<String, Any?>): String {
        val c = upgradeConfig(cfg)
        val startMs = parseDateMs(c["start"].toString())
            ?: throw IllegalArgumentException("makePlanId: invalid start ${c["start"]}")
        val date = Instant.ofEpochMilli(startMs).atOffset(ZoneOffset.UTC).toLocalDate()
            .toString().replace("-", "")
        val nodes = (c["nodes"] as? List<*>) ?: emptyList<Any?>()
        val hostName = (nodes.firstOrNull() as? Map<*, *>)?.get("name")
        val hostStr = stripSpaceUpper(if (truthy(hostName)) hostName.toString() else "HOST").take(8)
        val nodeStr = if (nodes.size > 1)
            nodes.drop(1).joinToString("-") {
                stripSpaceUpper((it as Map<*, *>)["name"].toString()).take(4)
            }.take(16)
        else "RX"
        val v = c["v"]
        if (isNum(v) && num(v) >= 3) {
            return "LTX-$date-$hostStr-$nodeStr-v3-${planHash(c).substring(0, 8)}"
        }
        // FROZEN v2 path (LTX-SPECIFICATION.md §4.3) -- imul31 over UTF-16 code units.
        val raw = LtxJson.stringify(c)
        var h = 0
        for (ch in raw) h = 31 * h + ch.code
        return "LTX-$date-$hostStr-$nodeStr-v2-" + String.format("%08x", h)
    }

    // ---- validatePlan (§3.5, §4, §7) ----

    /** Reserved-field violations only (§3.5 streams, §7 branching). */
    fun reservedFieldErrors(plan: Any?): List<PlanError> {
        val errors = mutableListOf<PlanError>()
        if (plan !is Map<*, *>) return errors
        if (plan.containsKey("streams")) {
            val s = plan["streams"]
            if (!(s is List<*> && s.isEmpty())) {
                errors += PlanError("reserved_streams", "streams",
                    "streams[] is reserved (§3.5) and MUST be absent or empty")
            }
        }
        for (f in RESERVED_BRANCH_PLAN_FIELDS) {
            if (plan.containsKey(f)) errors += PlanError("reserved_branching", f,
                "$f is reserved for branching (§7, not yet implemented) and MUST be absent")
        }
        (plan["segments"] as? List<*>)?.forEachIndexed { i, s ->
            if (s !is Map<*, *>) return@forEachIndexed
            for (f in RESERVED_STREAM_SEGMENT_FIELDS) {
                if (s.containsKey(f)) errors += PlanError("reserved_streams", "segments[$i].$f",
                    "segment $f is reserved (§3.5) and MUST be absent")
            }
            for (f in RESERVED_BRANCH_SEGMENT_FIELDS) {
                if (s.containsKey(f)) errors += PlanError("reserved_branching", "segments[$i].$f",
                    "segment $f is reserved for branching (§7) and MUST be absent")
            }
        }
        return errors
    }

    /** Throw LtxPlanException (code = first error code) if a plan uses reserved fields. */
    fun assertNoReservedFields(plan: Any?, fnName: String) {
        val errors = reservedFieldErrors(plan)
        if (errors.isEmpty()) return
        throw LtxPlanException(errors[0].code, errors, "$fnName: ${errors[0].message}")
    }

    /**
     * Validate a v2 or v3 plan against the wire format (spec/ltx-schema.json,
     * LTX-SPECIFICATION.md §4) and the reserved-field rules (§3.5, §7).
     * Pure; never throws. Mirrors ltx-sdk.js validatePlan.
     */
    fun validatePlan(plan: Any?): PlanValidation {
        val errors = mutableListOf<PlanError>()
        fun err(code: String, path: String, message: String) { errors += PlanError(code, path, message) }
        if (plan !is Map<*, *>) {
            err("not_an_object", "", "plan must be an object")
            return PlanValidation(false, errors)
        }
        val v = plan["v"]
        if (!numEq(v, 2) && !numEq(v, 3)) err("invalid_version", "v", "v must be 2 or 3")
        for (f in listOf("title", "start", "quantum", "mode", "nodes", "segments")) {
            if (!plan.containsKey(f)) err("missing_field", f, "$f is required")
        }
        if (plan.containsKey("title") && plan["title"] !is String) err("invalid_field", "title", "title must be a string")
        if (plan.containsKey("start")) {
            val s = plan["start"]
            if (s !is String || parseDateMs(s) == null) err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
        }
        if (plan.containsKey("quantum")) {
            val q = plan["quantum"]
            if (!(isInteger(q) && num(q) >= 1 && num(q) <= 60))
                err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")
        }
        if (plan.containsKey("mode") && !anyIn(plan["mode"], PLAN_MODES)) {
            err("invalid_mode", "mode", "mode must be one of ${PLAN_MODES.joinToString(", ")}")
        }

        val ids = LinkedHashSet<String>()
        if (plan.containsKey("nodes")) {
            val nodes = plan["nodes"]
            if (nodes !is List<*> || nodes.isEmpty()) {
                err("invalid_nodes", "nodes", "nodes must be a non-empty array")
            } else {
                var hosts = 0
                nodes.forEachIndexed { i, n ->
                    val id = (n as? Map<*, *>)?.get("id")
                    if (n !is Map<*, *> || id !is String || id.isEmpty() || id.contains('|') ||
                        n["name"] !is String || !anyIn(n["role"], NODE_ROLES) ||
                        !isNum(n["delay"]) || !(num(n["delay"]) >= 0)) {
                        err("invalid_nodes", "nodes[$i]", "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0")
                        return@forEachIndexed
                    }
                    if (id in ids) err("duplicate_node_id", "nodes[$i].id", "duplicate node id $id")
                    ids += id
                    if (n["role"] == "HOST") hosts++
                }
                val h = nodes[0] as? Map<*, *>
                if (hosts != 1 || h == null || h["role"] != "HOST" || !numEq(h["delay"], 0)) {
                    err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")
                }
            }
        }

        if (plan.containsKey("segments")) {
            val segs = plan["segments"]
            if (segs !is List<*>) {
                err("invalid_segment", "segments", "segments must be an array")
            } else {
                segs.forEachIndexed { i, s ->
                    if (s !is Map<*, *> || !anyIn(s["type"], PLAN_SEGMENT_TYPES) ||
                        !(isInteger(s["q"]) && num(s["q"]) >= 1)) {
                        err("invalid_segment", "segments[$i]", "segment needs a known type and integer q >= 1")
                        return@forEachIndexed
                    }
                    if (s.containsKey("speaker") && !anyIn(s["speaker"], ids)) {
                        err("unknown_speaker", "segments[$i].speaker", "speaker ${s["speaker"]} is not a node id")
                    }
                }
            }
        }

        if (numEq(v, 2)) {
            for (f in V3_ONLY_FIELDS) {
                if (plan.containsKey(f)) err("v3_field_in_v2", f, "$f is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
            }
        } else if (numEq(v, 3)) {
            if (plan.containsKey("delays")) {
                val d = plan["delays"]
                if (d !is Map<*, *>) {
                    err("invalid_delays", "delays", "delays must be an object")
                } else {
                    for ((kAny, dv) in d) {
                        val k = kAny.toString()
                        val parts = k.split("|")
                        if (parts.size != 2 || parts[0] >= parts[1] ||
                            (ids.isNotEmpty() && (parts[0] !in ids || parts[1] !in ids)) ||
                            !isNum(dv) || !(num(dv) >= 0)) {
                            err("invalid_delays", "delays.$k", "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)")
                        }
                    }
                }
            }
            if (plan.containsKey("planVersion")) {
                val pv = plan["planVersion"]
                if (!(isInteger(pv) && num(pv) >= 1)) err("invalid_field", "planVersion", "planVersion must be an integer >= 1")
            }
            if (plan.containsKey("prevPlanHash")) {
                val ph = plan["prevPlanHash"]
                if (!(ph is String && HEX64.matches(ph))) err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")
            }
            for (f in listOf("questions", "actions")) {
                if (plan.containsKey(f) && plan[f] !is List<*>) err("invalid_field", f, "$f must be an array")
            }
        }

        errors += reservedFieldErrors(plan)
        return PlanValidation(errors.isEmpty(), errors)
    }
}
