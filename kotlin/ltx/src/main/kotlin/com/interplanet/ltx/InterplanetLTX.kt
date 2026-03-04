package com.interplanet.ltx

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * InterplanetLTX — Kotlin/JVM port of ltx-sdk.js.
 * Story 38.1 — Kotlin LTX library
 *
 * All public methods are on the companion object.
 *
 * @example
 * ```kotlin
 * val plan = InterplanetLTX.createPlan("Q3 Review", listOf(node1, node2))
 * val ics  = InterplanetLTX.generateICS(plan)
 * val hash = InterplanetLTX.encodeHash(plan)  // "#l=eyJ2Ij..."
 * ```
 */
object InterplanetLTX {

    // ── Constants ──────────────────────────────────────────────────────────

    const val VERSION = "1.0.0"
    const val DEFAULT_QUANTUM = 5
    const val DEFAULT_API_BASE = "https://interplanet.live/api/ltx"

    // Story 26.4 constants
    const val DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2
    const val DELAY_VIOLATION_WARN_S = 120
    const val DELAY_VIOLATION_DEGRADED_S = 300
    val SESSION_STATES: List<String> = listOf("INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE")

    val DEFAULT_SEGMENTS: List<LtxSegmentTemplate> = listOf(
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("RELAY",  2),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("RELAY",  2),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("RELAY",  2),
        LtxSegmentTemplate("REST",   2),
        LtxSegmentTemplate("REST",   2),
        LtxSegmentTemplate("BUFFER", 1),
        LtxSegmentTemplate("SPEAK",  3),
        LtxSegmentTemplate("RELAY",  2),
        LtxSegmentTemplate("OPEN",   3),
        LtxSegmentTemplate("OPEN",   3)
    )

    // ── Plan creation ──────────────────────────────────────────────────────

    /**
     * Create a new LTX session plan.
     *
     * @param title     Session title
     * @param nodes     List of participant nodes
     * @param quantum   Minutes per quantum (default: 5)
     * @param mode      Protocol mode (default: "async")
     * @param start     ISO 8601 UTC start time (default: 5 min from now, rounded to minute)
     * @param segments  Segment template (default: DEFAULT_SEGMENTS)
     */
    fun createPlan(
        title: String,
        nodes: List<LtxNode>,
        quantum: Int = DEFAULT_QUANTUM,
        mode: String = "async",
        start: String? = null,
        segments: List<LtxSegmentTemplate> = DEFAULT_SEGMENTS
    ): LtxPlan {
        val resolvedStart = if (start.isNullOrEmpty()) {
            val nowMs = System.currentTimeMillis() + 5 * 60 * 1000L
            val roundedMs = (nowMs / 60_000L) * 60_000L
            epochMsToIso(roundedMs)
        } else start

        return LtxPlan(
            v = 2,
            title = title.ifEmpty { "LTX Session" },
            start = resolvedStart,
            quantum = quantum,
            mode = mode,
            nodes = nodes,
            segments = segments
        )
    }

    // ── upgradeConfig ──────────────────────────────────────────────────────

    /**
     * Upgrade an old-style plan map (v1 or Map) to LtxPlan v2.
     * Accepts a Map<String, Any> that may contain v1-style or v2-style fields.
     */
    @Suppress("UNCHECKED_CAST")
    fun upgradeConfig(old: Map<String, Any>): LtxPlan {
        val v = when (val vv = old["v"]) {
            is Int -> vv
            is Long -> vv.toInt()
            is Number -> vv.toInt()
            else -> 1
        }
        val title = old["title"]?.toString() ?: "LTX Session"
        val start = old["start"]?.toString() ?: ""
        val quantum = when (val q = old["quantum"]) {
            is Int -> q
            is Long -> q.toInt()
            is Number -> q.toInt()
            else -> DEFAULT_QUANTUM
        }
        val mode = old["mode"]?.toString() ?: "async"

        val nodes: List<LtxNode> = when (val rawNodes = old["nodes"]) {
            is List<*> -> rawNodes.mapNotNull { n ->
                if (n is Map<*, *>) {
                    LtxNode(
                        id = n["id"]?.toString() ?: "",
                        name = n["name"]?.toString() ?: "",
                        role = n["role"]?.toString() ?: "",
                        delay = when (val d = n["delay"]) {
                            is Int -> d
                            is Long -> d.toInt()
                            is Number -> d.toInt()
                            else -> 0
                        },
                        location = n["location"]?.toString() ?: "earth"
                    )
                } else null
            }
            else -> listOf(
                LtxNode("N0", "Earth HQ",    "host",        0, "earth"),
                LtxNode("N1", "Mars Hab-01", "participant", 0, "mars")
            )
        }

        val segments: List<LtxSegmentTemplate> = when (val rawSegs = old["segments"]) {
            is List<*> -> rawSegs.mapNotNull { s ->
                if (s is Map<*, *>) {
                    LtxSegmentTemplate(
                        type = s["type"]?.toString() ?: "",
                        q = when (val q2 = s["q"]) {
                            is Int -> q2
                            is Long -> q2.toInt()
                            is Number -> q2.toInt()
                            else -> 1
                        }
                    )
                } else null
            }
            else -> DEFAULT_SEGMENTS
        }

        return LtxPlan(
            v = 2,
            title = title,
            start = start,
            quantum = quantum,
            mode = mode,
            nodes = nodes,
            segments = segments
        )
    }

    // ── escapeIcsText (Story 26.3) ─────────────────────────────────────────

    /**
     * Escape a string for RFC 5545 TEXT property values.
     * Escapes: backslash, semicolon, comma, newline.
     */
    fun escapeIcsText(s: String): String =
        s.replace("\\", "\\\\")
         .replace(";", "\\;")
         .replace(",", "\\,")
         .replace("\n", "\\n")

    // ── planLockTimeoutMs (Story 26.4) ─────────────────────────────────────

    /** Compute the plan-lock timeout in milliseconds. */
    fun planLockTimeoutMs(delaySeconds: Long): Long =
        delaySeconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000L

    // ── checkDelayViolation (Story 26.4) ───────────────────────────────────

    /** Check delay violation. Returns "ok", "violation", or "degraded". */
    fun checkDelayViolation(declaredDelayS: Long, measuredDelayS: Long): String {
        val diff = Math.abs(measuredDelayS - declaredDelayS)
        return when {
            diff > DELAY_VIOLATION_DEGRADED_S -> "degraded"
            diff > DELAY_VIOLATION_WARN_S     -> "violation"
            else                               -> "ok"
        }
    }

    // ── computeSegments ────────────────────────────────────────────────────

    /**
     * Compute the timed segment array for a plan.
     * Segments cycle through all nodes for SPEAK/RELAY types.
     * Each segment has absolute start/end times (UTC ms) and durationMs.
     */
    fun computeSegments(plan: LtxPlan): List<LtxSegment> {
        require(plan.quantum >= 1) { "quantum must be >= 1, got ${plan.quantum}" }
        val qMs = plan.quantum.toLong() * 60_000L
        var t = parseIsoMs(plan.start)
        val result = mutableListOf<LtxSegment>()
        var speakerIdx = 0
        for (s in plan.segments) {
            val durMs = s.q.toLong() * qMs
            val nodeId = when {
                plan.nodes.isEmpty() -> "N0"
                s.type == "SPEAK" || s.type == "TX" -> {
                    val id = plan.nodes[speakerIdx % plan.nodes.size].id
                    id
                }
                s.type == "RELAY" || s.type == "RX" -> {
                    plan.nodes[speakerIdx % plan.nodes.size].id
                }
                else -> plan.nodes[0].id
            }
            result.add(LtxSegment(
                segType = s.type,
                nodeId = nodeId,
                startMs = t,
                endMs = t + durMs,
                durationMs = durMs
            ))
            if (s.type == "SPEAK" || s.type == "TX") speakerIdx++
            t += durMs
        }
        return result
    }

    // ── totalMin ──────────────────────────────────────────────────────────

    /**
     * Total session duration in minutes.
     */
    fun totalMin(plan: LtxPlan): Int {
        return plan.segments.sumOf { it.q } * plan.quantum
    }

    // ── makePlanId ────────────────────────────────────────────────────────

    /**
     * Compute the deterministic plan ID string.
     * Returns e.g. "LTX-20260301-EARTHHQ-MARS-v2-a3b2c1d0"
     */
    fun makePlanId(plan: LtxPlan): String {
        val date = plan.start.substring(0, 10).replace("-", "")

        val hostStr = if (plan.nodes.isEmpty()) "HOST"
        else plan.nodes[0].name.replace(Regex("\\s+"), "").uppercase().take(8)

        val nodeStr = if (plan.nodes.size > 1) {
            plan.nodes.drop(1)
                .joinToString("-") { n -> n.name.replace(Regex("\\s+"), "").uppercase().take(4) }
                .take(16)
        } else "RX"

        val hex = makePlanHashHex(plan)
        return "LTX-$date-$hostStr-$nodeStr-v2-$hex"
    }

    // ── encodeHash / decodeHash ───────────────────────────────────────────

    /**
     * Encode a plan config to a URL hash fragment ("#l=…").
     * Uses URL-safe base64 (no +, /, or = padding).
     */
    fun encodeHash(plan: LtxPlan): String {
        val json = planToJson(plan)
        val encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray())
        return "#l=$encoded"
    }

    /**
     * Decode a plan config from a URL hash fragment.
     * Accepts "#l=…", "l=…", or the raw base64 token.
     * Returns null if the hash is invalid.
     */
    fun decodeHash(hash: String): LtxPlan? {
        return try {
            val payload = hash.removePrefix("#l=")
            val json = String(java.util.Base64.getUrlDecoder().decode(payload))
            val plan = parsePlanJson(json)
            if (plan.start.isEmpty()) null else plan
        } catch (e: Exception) { null }
    }

    // ── buildNodeUrls ─────────────────────────────────────────────────────

    /**
     * Build perspective URLs for all nodes in a plan.
     *
     * @param plan    LTX plan config
     * @param baseUrl Base page URL, e.g. "https://interplanet.live/ltx.html"
     */
    fun buildNodeUrls(plan: LtxPlan, baseUrl: String): List<LtxNodeUrl> {
        val hash = encodeHash(plan).substring(1) // strip leading '#'
        val base = baseUrl.replace(Regex("[#?].*$"), "")
        return plan.nodes.map { n ->
            val url = "$base?node=${urlEncode(n.id)}#$hash"
            LtxNodeUrl(nodeId = n.id, name = n.name, role = n.role, url = url)
        }
    }

    // ── generateICS ───────────────────────────────────────────────────────

    /**
     * Generate LTX-extended iCalendar (.ics) content for a plan.
     * Includes LTX-NODE, LTX-DELAY, LTX-READINESS extension properties.
     */
    fun generateICS(plan: LtxPlan): String {
        val segs = computeSegments(plan)
        val startMs = parseIsoMs(plan.start)
        val endMs = segs.lastOrNull()?.endMs ?: startMs
        val planId = makePlanId(plan)

        val host = plan.nodes.firstOrNull()
            ?: LtxNode("N0", "Earth HQ", "host", 0, "earth")
        val participants = if (plan.nodes.size > 1) plan.nodes.drop(1) else emptyList()

        val segTpl = plan.segments.joinToString(",") { it.type }
        val toId = { name: String -> name.replace(Regex("\\s+"), "-").uppercase() }

        val nodeLines = plan.nodes.map { n -> "LTX-NODE:ID=${toId(n.name)};ROLE=${n.role}" }
        val delayLines = participants.map { n ->
            val d = n.delay
            "LTX-DELAY;NODEID=${toId(n.name)}:ONEWAY-MIN=$d;ONEWAY-MAX=${d + 120};ONEWAY-ASSUMED=$d"
        }
        val localTimeLines = plan.nodes
            .filter { it.location == "mars" }
            .map { n -> "LTX-LOCALTIME:NODE=${toId(n.name)};SCHEME=LMST;PARAMS=LONGITUDE:0E" }

        val partNames = if (participants.isEmpty()) "remote nodes"
        else participants.joinToString(", ") { it.name }
        val delayDesc = if (participants.isEmpty()) "no participant delay configured"
        else participants.joinToString(" \u00b7 ") { p ->
            "${p.name}: ${Math.round(p.delay / 60.0)} min one-way"
        }

        val now = Instant.now()
        val fmtDt = { epochMs: Long ->
            DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
                .withZone(ZoneOffset.UTC)
                .format(Instant.ofEpochMilli(epochMs))
        }
        val fmtNow = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
            .withZone(ZoneOffset.UTC)
            .format(now)

        val lines = mutableListOf<String>()
        lines.add("BEGIN:VCALENDAR")
        lines.add("VERSION:2.0")
        lines.add("PRODID:-//InterPlanet//LTX v1.1//EN")
        lines.add("CALSCALE:GREGORIAN")
        lines.add("METHOD:PUBLISH")
        lines.add("BEGIN:VEVENT")
        lines.add("UID:$planId@interplanet.live")
        lines.add("DTSTAMP:$fmtNow")
        lines.add("DTSTART:${fmtDt(startMs)}")
        lines.add("DTEND:${fmtDt(endMs)}")
        lines.add("SUMMARY:${escapeIcsText(plan.title)}")
        lines.add("DESCRIPTION:LTX session \u2014 ${host.name} with $partNames\\n" +
            "Signal delays: $delayDesc\\n" +
            "Mode: ${plan.mode} \u00b7 Segment plan: $segTpl\\n" +
            "Generated by InterPlanet (https://interplanet.live)")
        lines.add("LTX:1")
        lines.add("LTX-PLANID:$planId")
        lines.add("LTX-QUANTUM:PT${plan.quantum}M")
        lines.add("LTX-SEGMENT-TEMPLATE:$segTpl")
        lines.add("LTX-MODE:${plan.mode}")
        lines.addAll(nodeLines)
        lines.addAll(delayLines)
        lines.add("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY")
        lines.addAll(localTimeLines)
        lines.add("END:VEVENT")
        lines.add("END:VCALENDAR")

        return lines.joinToString("\r\n") + "\r\n"
    }

    // ── formatHMS ─────────────────────────────────────────────────────────

    /**
     * Format a duration in seconds as "HH:MM:SS" (if >= 1 hour) or "MM:SS".
     */
    fun formatHMS(seconds: Int): String {
        val s = if (seconds < 0) 0 else seconds
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) "%02d:%02d:%02d".format(h, m, sec)
        else "%02d:%02d".format(m, sec)
    }

    // ── formatUTC ─────────────────────────────────────────────────────────

    /**
     * Format a UTC epoch milliseconds value as "HH:MM:SS UTC".
     */
    fun formatUTC(epochMs: Long): String {
        val iso = Instant.ofEpochMilli(epochMs).toString()
        return iso.substring(11, 19) + " UTC"
    }

    // ── Public internal helpers ────────────────────────────────────────────

    /** Expose planToJson for RestClient */
    internal fun planToJsonPublic(plan: LtxPlan) = planToJson(plan)

    // ── Private helpers ────────────────────────────────────────────────────

    internal fun planToJson(plan: LtxPlan): String {
        val nodes = plan.nodes.joinToString(",") { n ->
            """{"id":${q(n.id)},"name":${q(n.name)},"role":${q(n.role)},"delay":${n.delay},"location":${q(n.location)}}"""
        }
        val segs = plan.segments.joinToString(",") { s -> """{"type":${q(s.type)},"q":${s.q}}""" }
        return """{"v":${plan.v},"title":${q(plan.title)},"start":${q(plan.start)},"quantum":${plan.quantum},"mode":${q(plan.mode)},"nodes":[${nodes}],"segments":[${segs}]}"""
    }

    private fun q(s: String) = "\"${s.replace("\\", "\\\\").replace("\"", "\\\"")}\""

    private fun makePlanHashHex(plan: LtxPlan): String {
        val json = planToJson(plan)
        var h = 0L
        for (b in json.toByteArray()) {
            h = (h * 31L + (b.toLong() and 0xFFL)) and 0xFFFFFFFFL
        }
        return h.toString(16).padStart(8, '0')
    }

    private fun parsePlanJson(json: String): LtxPlan {
        fun strVal(key: String): String {
            val r = Regex(""""$key"\s*:\s*"((?:[^"\\]|\\.)*)"""")
            return r.find(json)?.groupValues?.get(1) ?: ""
        }
        fun intVal(key: String): Int {
            val r = Regex(""""$key"\s*:\s*(\d+)""")
            return r.find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        }

        val v = intVal("v").let { if (it == 0) 2 else it }
        val title = strVal("title")
        val start = strVal("start")
        val quantum = intVal("quantum").let { if (it == 0) DEFAULT_QUANTUM else it }
        val mode = strVal("mode")

        // Parse nodes array
        val nodes = mutableListOf<LtxNode>()
        val nodesStart = json.indexOf("\"nodes\"")
        if (nodesStart >= 0) {
            val arrStart = json.indexOf('[', nodesStart)
            if (arrStart >= 0) {
                val arrEnd = findMatchingBracket(json, arrStart, '[', ']')
                if (arrEnd > arrStart) {
                    val arrContent = json.substring(arrStart + 1, arrEnd)
                    val nodeObjects = splitJsonObjects(arrContent)
                    for (obj in nodeObjects) {
                        if (obj.trim().isEmpty()) continue
                        fun nodeStr(k: String): String {
                            val r = Regex(""""$k"\s*:\s*"((?:[^"\\]|\\.)*)"""")
                            return r.find(obj)?.groupValues?.get(1) ?: ""
                        }
                        fun nodeInt(k: String): Int {
                            val r = Regex(""""$k"\s*:\s*(\d+)""")
                            return r.find(obj)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                        }
                        nodes.add(LtxNode(
                            id = nodeStr("id"),
                            name = nodeStr("name"),
                            role = nodeStr("role"),
                            delay = nodeInt("delay"),
                            location = nodeStr("location")
                        ))
                    }
                }
            }
        }

        // Parse segments array
        val segments = mutableListOf<LtxSegmentTemplate>()
        val segsStart = json.indexOf("\"segments\"")
        if (segsStart >= 0) {
            val arrStart = json.indexOf('[', segsStart)
            if (arrStart >= 0) {
                val arrEnd = findMatchingBracket(json, arrStart, '[', ']')
                if (arrEnd > arrStart) {
                    val arrContent = json.substring(arrStart + 1, arrEnd)
                    val segObjects = splitJsonObjects(arrContent)
                    for (obj in segObjects) {
                        if (obj.trim().isEmpty()) continue
                        fun segStr(k: String): String {
                            val r = Regex(""""$k"\s*:\s*"((?:[^"\\]|\\.)*)"""")
                            return r.find(obj)?.groupValues?.get(1) ?: ""
                        }
                        fun segInt(k: String): Int {
                            val r = Regex(""""$k"\s*:\s*(\d+)""")
                            return r.find(obj)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                        }
                        segments.add(LtxSegmentTemplate(
                            type = segStr("type"),
                            q = segInt("q").let { if (it == 0) 1 else it }
                        ))
                    }
                }
            }
        }

        return LtxPlan(
            v = v,
            title = title,
            start = start,
            quantum = quantum,
            mode = mode,
            nodes = nodes,
            segments = segments
        )
    }

    /** Find the matching closing bracket/brace given the opening position. */
    private fun findMatchingBracket(s: String, start: Int, open: Char, close: Char): Int {
        var depth = 0
        var inStr = false
        var escape = false
        for (i in start until s.length) {
            val c = s[i]
            if (escape) { escape = false; continue }
            if (c == '\\' && inStr) { escape = true; continue }
            if (c == '"') { inStr = !inStr; continue }
            if (inStr) continue
            if (c == open) depth++
            else if (c == close) {
                depth--
                if (depth == 0) return i
            }
        }
        return -1
    }

    /** Split a JSON array content string into individual object strings. */
    private fun splitJsonObjects(content: String): List<String> {
        val result = mutableListOf<String>()
        var depth = 0
        var inStr = false
        var escape = false
        var start = 0
        for (i in content.indices) {
            val c = content[i]
            if (escape) { escape = false; continue }
            if (c == '\\' && inStr) { escape = true; continue }
            if (c == '"') { inStr = !inStr; continue }
            if (inStr) continue
            if (c == '{') {
                if (depth == 0) start = i
                depth++
            } else if (c == '}') {
                depth--
                if (depth == 0) {
                    result.add(content.substring(start, i + 1))
                }
            }
        }
        return result
    }

    private fun urlEncode(s: String) = java.net.URLEncoder.encode(s, "UTF-8")

    internal fun parseIsoMs(iso: String): Long {
        if (iso.length < 19) return 0L
        return try {
            val y = iso.substring(0, 4).toLong()
            val m = iso.substring(5, 7).toLong()
            val d = iso.substring(8, 10).toLong()
            val h = iso.substring(11, 13).toLong()
            val min = iso.substring(14, 16).toLong()
            val s = iso.substring(17, 19).toLong()
            val days = daysFromEpoch(y, m, d)
            days * 86_400_000L + h * 3_600_000L + min * 60_000L + s * 1_000L
        } catch (e: Exception) { 0L }
    }

    private fun daysFromEpoch(y: Long, m: Long, d: Long): Long {
        val (y2, m2) = if (m <= 2) Pair(y - 1, m + 9) else Pair(y, m - 3)
        val era = (if (y2 >= 0) y2 else y2 - 399) / 400
        val yoe = y2 - era * 400
        val doy = (153 * m2 + 2) / 5 + d - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    private fun epochMsToIso(epochMs: Long): String {
        return DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'")
            .withZone(ZoneOffset.UTC)
            .format(Instant.ofEpochMilli(epochMs))
    }
}
