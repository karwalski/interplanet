/**
 * InterplanetLtx.scala - Pure Scala 3 port of ltx-sdk.js
 * Story 33.13 - Scala LTX library
 *
 * All methods are on the InterplanetLtx object.
 * No external dependencies: stdlib + java.util.Base64 + java.net.HttpURLConnection.
 *
 * Usage:
 *   val plan = InterplanetLtx.createPlan(Map("title" -> "My Session", "start" -> "2024-01-15T14:00:00Z"))
 *   val id   = InterplanetLtx.makePlanId(plan)
 *   val hash = InterplanetLtx.encodeHash(plan)
 */

import java.util.Base64
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

object InterplanetLtx:

  // ── 1. createPlan ─────────────────────────────────────────────────────────

  /**
   * Create a new LTX session plan.
   *
   * Supported config keys:
   *   title, start, quantum, mode, nodes, delay,
   *   hostName, hostLocation, remoteName, remoteLocation, segments
   */
  def createPlan(config: Map[String, Any]): LtxPlan =
    val now = Instant.now().plusSeconds(300)
    val roundedNow = Instant.ofEpochSecond((now.getEpochSecond / 60) * 60)
    val defaultStart = roundedNow.toString

    val nodes: List[LtxNode] = config.get("nodes") match
      case Some(ns: List[?]) =>
        ns.collect { case m: Map[?, ?] =>
          val mm = m.asInstanceOf[Map[String, Any]]
          LtxNode(
            id       = mm.getOrElse("id", "N0").toString,
            name     = mm.getOrElse("name", "Unknown").toString,
            role     = mm.getOrElse("role", "PARTICIPANT").toString,
            delay    = mm.getOrElse("delay", 0) match
              case i: Int => i
              case l: Long => l.toInt
              case d: Double => d.toInt
              case s: String => s.toIntOption.getOrElse(0)
              case _ => 0,
            location = mm.getOrElse("location", "earth").toString
          )
        }
      case _ =>
        List(
          LtxNode("N0", config.getOrElse("hostName",   "Earth HQ").toString,    "HOST",
                  0,
                  config.getOrElse("hostLocation", "earth").toString),
          LtxNode("N1", config.getOrElse("remoteName", "Mars Hab-01").toString, "PARTICIPANT",
                  config.getOrElse("delay", 0) match
                    case i: Int => i
                    case l: Long => l.toInt
                    case d: Double => d.toInt
                    case _ => 0,
                  config.getOrElse("remoteLocation", "mars").toString)
        )

    val segments: List[LtxSegmentTemplate] = config.get("segments") match
      case Some(ss: List[?]) =>
        ss.collect { case m: Map[?, ?] =>
          val mm = m.asInstanceOf[Map[String, Any]]
          LtxSegmentTemplate(
            segType = mm.getOrElse("type", "TX").toString,
            q       = mm.getOrElse("q", 2) match
              case i: Int => i
              case d: Double => d.toInt
              case _ => 2
          )
        }
      case _ => DEFAULT_SEGMENTS

    LtxPlan(
      v        = 2,
      title    = config.getOrElse("title",   "LTX Session").toString,
      start    = config.getOrElse("start",   defaultStart).toString,
      quantum  = config.getOrElse("quantum", DEFAULT_QUANTUM) match
        case i: Int => i
        case d: Double => d.toInt
        case _ => DEFAULT_QUANTUM,
      mode     = config.getOrElse("mode",    "LTX").toString,
      nodes    = nodes,
      segments = segments
    )

  // ── 2. upgradeConfig ──────────────────────────────────────────────────────

  /**
   * Upgrade a v1-style plan to the v2 nodes-array schema.
   * v2 plans are returned unchanged.
   */
  def upgradeConfig(plan: LtxPlan): LtxPlan =
    if plan.v >= 2 && plan.nodes.nonEmpty then plan
    else
      plan.copy(
        v = 2,
        nodes = List(
          LtxNode("N0", "Earth HQ",    "HOST",        0, "earth"),
          LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 0, "mars")
        )
      )

  // ── 3. computeSegments ────────────────────────────────────────────────────

  /**
   * Compute the timed segment array for a plan.
   * Each LtxSegment has absolute startMs/endMs in UTC milliseconds.
   */
  def computeSegments(plan: LtxPlan): List[LtxSegment] =
    val c    = upgradeConfig(plan)
    if c.quantum < 1 then
      throw new IllegalArgumentException(s"quantum must be >= 1, got ${c.quantum}")
    val qMs  = c.quantum.toLong * 60L * 1000L
    var t    = parseIsoToEpochMs(c.start)
    c.segments.map { s =>
      val durMs = s.q.toLong * qMs
      val seg = LtxSegment(s.segType, s.q, t, t + durMs, s.q * c.quantum)
      t += durMs
      seg
    }

  // ── 4. totalMin ───────────────────────────────────────────────────────────

  /** Total session duration in minutes. */
  def totalMin(plan: LtxPlan): Int =
    val c = upgradeConfig(plan)
    c.segments.foldLeft(0)((acc, s) => acc + s.q * c.quantum)

  // ── 5. makePlanId ─────────────────────────────────────────────────────────

  /**
   * Compute the deterministic plan ID string.
   * Format: LTX-YYYYMMDD-ORIGNAME-DESTNAME-v2-XXXXXXXX
   * Matches the ID generated by ltx-sdk.js.
   */
  def makePlanId(plan: LtxPlan): String =
    val c    = upgradeConfig(plan)
    val date = c.start.take(10).replace("-", "")

    val hostStr =
      val raw = if c.nodes.isEmpty then "HOST"
                else c.nodes.head.name.replaceAll("\\s+", "").toUpperCase
      if raw.length > 8 then raw.take(8) else raw

    val nodeStr =
      if c.nodes.size > 1 then
        val parts = c.nodes.tail.map { n =>
          val raw = n.name.replaceAll("\\s+", "").toUpperCase
          if raw.length > 4 then raw.take(4) else raw
        }
        val joined = parts.mkString("-")
        if joined.length > 16 then joined.take(16) else joined
      else "RX"

    val raw = c.toJson
    val hash = djbHash(raw)
    s"LTX-$date-$hostStr-$nodeStr-v2-$hash"

  // ── 6. encodeHash ─────────────────────────────────────────────────────────

  /**
   * Encode a plan config to a URL hash fragment (#l=...).
   * Uses URL-safe base64 without padding.
   */
  def encodeHash(plan: LtxPlan): String =
    val c     = upgradeConfig(plan)
    val json  = c.toJson
    val bytes = json.getBytes(StandardCharsets.UTF_8)
    val b64   = Base64.getUrlEncoder.withoutPadding.encodeToString(bytes)
    "#l=" + b64

  // ── 7. decodeHash ─────────────────────────────────────────────────────────

  /**
   * Decode a plan config from a URL hash fragment.
   * Accepts "#l=...", "l=...", or the raw base64 token.
   * Returns None if the hash is invalid.
   */
  def decodeHash(b64: String): Option[LtxPlan] =
    if b64 == null || b64.isEmpty then return None
    try
      val token = b64.replaceFirst("^#?l=", "")
      val bytes = Base64.getUrlDecoder.decode(token)
      val json  = new String(bytes, StandardCharsets.UTF_8)
      LtxPlan.fromJson(json)
    catch case _: Exception => None

  // ── 8. buildNodeUrls ──────────────────────────────────────────────────────

  /**
   * Build perspective URLs for all nodes in a plan.
   *
   * @param plan    LTX plan config
   * @param baseUrl Base page URL e.g. "https://interplanet.live/ltx.html"
   */
  def buildNodeUrls(plan: LtxPlan, baseUrl: String = ""): List[LtxNodeUrl] =
    val c    = upgradeConfig(plan)
    val hash = encodeHash(c).stripPrefix("#")  // strip leading '#'
    val base = if baseUrl == null then "" else baseUrl.replaceAll("[#?].*$", "")
    c.nodes.map { n =>
      val encodedId = java.net.URLEncoder.encode(n.id, "UTF-8")
      LtxNodeUrl(n.id, n.name, n.role, s"$base?node=$encodedId#$hash")
    }

  // ── 9. generateICS ────────────────────────────────────────────────────────

  /**
   * Generate LTX-extended iCalendar (.ics) content for a plan.
   * Uses CRLF line endings as required by RFC 5545.
   * Includes LTX-PLANID and LTX-QUANTUM custom properties.
   */
  def generateICS(plan: LtxPlan): String =
    val c        = upgradeConfig(plan)
    val segs     = computeSegments(c)
    val startMs  = parseIsoToEpochMs(c.start)
    val endMs    = if segs.isEmpty then startMs else segs.last.endMs
    val planId   = makePlanId(c)
    val host     = if c.nodes.isEmpty
                   then LtxNode("N0", "Earth HQ", "HOST", 0, "earth")
                   else c.nodes.head
    val parts    = if c.nodes.size > 1 then c.nodes.tail else Nil
    val segTpl   = c.segments.map(_.segType).mkString(",")

    def fmtDT(ms: Long): String =
      val fmt = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC)
      fmt.format(Instant.ofEpochMilli(ms))

    def toId(name: String): String =
      name.replaceAll("\\s+", "-").toUpperCase

    val partNames = if parts.isEmpty then "remote nodes"
                    else parts.map(_.name).mkString(", ")
    val delayDesc = if parts.isEmpty then "no participant delay configured"
                    else parts.map(p => s"${p.name}: ${Math.round(p.delay / 60.0)} min one-way").mkString(" \u00b7 ")

    val nodeLines = c.nodes.map(n => s"LTX-NODE:ID=${toId(n.name)};ROLE=${n.role}")
    val delayLines = parts.map { p =>
      val d = p.delay
      s"LTX-DELAY;NODEID=${toId(p.name)}:ONEWAY-MIN=$d;ONEWAY-MAX=${d + 120};ONEWAY-ASSUMED=$d"
    }
    val localTimeLines = c.nodes.filter(_.location == "mars").map { n =>
      s"LTX-LOCALTIME:NODE=${toId(n.name)};SCHEME=LMST;PARAMS=LONGITUDE:0E"
    }

    val dtstamp = fmtDT(System.currentTimeMillis())

    val lines = List(
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//InterPlanet//LTX v1.1//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      s"UID:$planId@interplanet.live",
      s"DTSTAMP:$dtstamp",
      s"DTSTART:${fmtDT(startMs)}",
      s"DTEND:${fmtDT(endMs)}",
      s"SUMMARY:${escapeIcsText(c.title)}",
      s"DESCRIPTION:LTX session \u2014 ${host.name} with $partNames\\nSignal delays: $delayDesc\\nMode: ${c.mode} \u00b7 Segment plan: $segTpl\\nGenerated by InterPlanet (https://interplanet.live)",
      "LTX:1",
      s"LTX-PLANID:$planId",
      s"LTX-QUANTUM:PT${c.quantum}M",
      s"LTX-SEGMENT-TEMPLATE:$segTpl",
      s"LTX-MODE:${c.mode}"
    ) ++ nodeLines ++ delayLines ++ List(
      "LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY"
    ) ++ localTimeLines ++ List(
      "END:VEVENT",
      "END:VCALENDAR"
    )

    lines.mkString("\r\n")

  // ── 10. formatHMS ─────────────────────────────────────────────────────────

  /**
   * Format a duration in seconds as HH:MM:SS (if >= 1 hour) or MM:SS.
   */
  def formatHMS(seconds: Int): String =
    val s = if seconds < 0 then 0 else seconds
    val h = s / 3600
    val m = (s % 3600) / 60
    val sec = s % 60
    if h > 0 then f"$h%02d:$m%02d:$sec%02d"
    else f"$m%02d:$sec%02d"

  // ── 11. formatUTC ─────────────────────────────────────────────────────────

  /**
   * Format a UTC epoch millisecond value as "YYYY-MM-DDTHH:MM:SSZ".
   */
  def formatUTC(ms: Long): String =
    val iso = Instant.ofEpochMilli(ms).toString  // "2026-03-01T14:30:45Z"
    // Trim sub-second precision if present
    val base = iso.takeWhile(_ != '.')
    if base.endsWith("Z") then base else base + "Z"

  // ── 12. escapeIcsText (Story 26.3) ────────────────────────────────────────

  /** Escape a string for RFC 5545 TEXT property values. */
  def escapeIcsText(s: String): String =
    s.replace("\\", "\\\\")
     .replace(";", "\\;")
     .replace(",", "\\,")
     .replace("\n", "\\n")

  // ── 13. planLockTimeoutMs (Story 26.4) ────────────────────────────────────

  /** Compute the plan-lock timeout in milliseconds. */
  def planLockTimeoutMs(delaySeconds: Long): Long =
    delaySeconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000L

  // ── 14. checkDelayViolation (Story 26.4) ──────────────────────────────────

  /** Check delay violation. Returns "ok", "violation", or "degraded". */
  def checkDelayViolation(declaredDelayS: Long, measuredDelayS: Long): String =
    val diff = Math.abs(measuredDelayS - declaredDelayS)
    if diff > DELAY_VIOLATION_DEGRADED_S then "degraded"
    else if diff > DELAY_VIOLATION_WARN_S then "violation"
    else "ok"

  // ── Private helpers ───────────────────────────────────────────────────────

  /**
   * Polynomial hash matching ltx-sdk.js: h = (31 * h + charCode) >>> 0
   * Returns 8-character lowercase hex string.
   */
  def djbHash(s: String): String =
    val h = s.foldLeft(0L) { (acc, c) =>
      ((acc * 31L) + c.toInt) & 0xFFFFFFFFL
    }
    f"$h%08x"

  /** Parse ISO-8601 timestamp to UTC epoch milliseconds. */
  private def parseIsoToEpochMs(iso: String): Long =
    try Instant.parse(iso).toEpochMilli
    catch case _: Exception => 0L
