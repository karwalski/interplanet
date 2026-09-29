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

    const val VERSION = "1.1.0"
    const val DEFAULT_QUANTUM = 5
    const val DEFAULT_API_BASE = "https://interplanet.live/api/ltx"

    // Story 26.4 constants
    const val DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2
    const val DELAY_VIOLATION_WARN_S = 120
    const val DELAY_VIOLATION_DEGRADED_S = 300
    val SESSION_STATES: List<String> = listOf("INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE")

    /** Default segment template, identical to DEFAULT_SEGMENTS in
     *  javascript/ltx/ltx-sdk.js (and the other ports): 13 quanta. */
    val DEFAULT_SEGMENTS: List<LtxSegmentTemplate> = listOf(
        LtxSegmentTemplate("PLAN_CONFIRM", 2),
        LtxSegmentTemplate("TX",           2),
        LtxSegmentTemplate("RX",           2),
        LtxSegmentTemplate("CAUCUS",       2),
        LtxSegmentTemplate("TX",           2),
        LtxSegmentTemplate("RX",           2),
        LtxSegmentTemplate("BUFFER",       1)
    )

    // ── Plan creation ──────────────────────────────────────────────────────

    /**
     * Create a new LTX session plan.
     *
     * @param title     Session title
     * @param nodes     List of participant nodes
     * @param quantum   Minutes per quantum (default: 5)
     * @param mode      Protocol mode (default: "LTX", as in the JS SDK)
     * @param start     ISO 8601 UTC start time (default: 5 min from now, rounded to minute)
     * @param segments  Segment template (default: DEFAULT_SEGMENTS)
     */
    fun createPlan(
        title: String,
        nodes: List<LtxNode>,
        quantum: Int = DEFAULT_QUANTUM,
        mode: String = "LTX",
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
        val mode = old["mode"]?.toString() ?: "LTX"

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
                        },
                        speaker = s["speaker"] as? String,
                        label = s["label"] as? String
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
     * Segments cycle through all nodes for TX/RX (and legacy SPEAK/RELAY) types.
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

        // Whitespace is stripped as JS /\s+/g does: every Unicode space and
        // line terminator (NBSP, U+2028, U+3000, BOM, ...), not only ASCII.
        val hostStr = LtxPlans.stripSpaceUpper(plan.nodes.firstOrNull()?.name?.ifEmpty { null } ?: "HOST").take(8)

        val nodeStr = if (plan.nodes.size > 1) {
            plan.nodes.drop(1)
                .joinToString("-") { n -> LtxPlans.stripSpaceUpper(n.name).take(4) }
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
        val encoded = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray(Charsets.UTF_8))
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
            val json = String(java.util.Base64.getUrlDecoder().decode(payload), Charsets.UTF_8)
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
        // Attributed segments (section 3.4.1): speaker and label are written
        // after type and q, only when present, as ltx-sdk.js writes them.
        val segs = plan.segments.joinToString(",") { s ->
            buildString {
                append("""{"type":${q(s.type)},"q":${s.q}""")
                s.speaker?.let { append(""","speaker":${q(it)}""") }
                s.label?.let { append(""","label":${q(it)}""") }
                append("}")
            }
        }
        return """{"v":${plan.v},"title":${q(plan.title)},"start":${q(plan.start)},"quantum":${plan.quantum},"mode":${q(plan.mode)},"nodes":[${nodes}],"segments":[${segs}]}"""
    }

    /** Quote exactly as JSON.stringify does (control characters, lone surrogates). */
    private fun q(s: String) = StringBuilder().also { LtxJson.quote(it, s) }.toString()

    private fun makePlanHashHex(plan: LtxPlan): String {
        // FROZEN v2 hash (§4.3): imul31 over the UTF-16 code units of the
        // JSON, as JS charCodeAt does (not over UTF-8 bytes, which diverges
        // for any non-ASCII title or name).
        val json = planToJson(plan)
        var h = 0L
        for (c in json) {
            h = (h * 31L + c.code.toLong()) and 0xFFFFFFFFL
        }
        return h.toString(16).padStart(8, '0')
    }

    @Suppress("UNCHECKED_CAST")
    private fun parsePlanJson(json: String): LtxPlan {
        val m = LtxJson.parse(json) as? Map<String, Any?> ?: throw IllegalArgumentException("plan JSON is not an object")
        fun str(o: Map<String, Any?>, k: String): String = o[k] as? String ?: ""
        fun int(o: Map<String, Any?>, k: String): Int = (o[k] as? Number)?.toInt() ?: 0

        val nodes = (m["nodes"] as? List<*>).orEmpty().filterIsInstance<Map<String, Any?>>().map { n ->
            LtxNode(id = str(n, "id"), name = str(n, "name"), role = str(n, "role"),
                    delay = int(n, "delay"), location = str(n, "location"))
        }
        val segments = (m["segments"] as? List<*>).orEmpty().filterIsInstance<Map<String, Any?>>().map { s ->
            LtxSegmentTemplate(
                type = str(s, "type"),
                q = int(s, "q").let { if (it == 0) 1 else it },
                speaker = s["speaker"] as? String,
                label = s["label"] as? String
            )
        }

        return LtxPlan(
            v = int(m, "v").let { if (it == 0) 2 else it },
            title = str(m, "title"),
            start = str(m, "start"),
            quantum = int(m, "quantum").let { if (it == 0) DEFAULT_QUANTUM else it },
            mode = str(m, "mode"),
            nodes = nodes,
            segments = segments
        )
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
