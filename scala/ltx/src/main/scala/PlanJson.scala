/**
 * PlanJson.scala -- generic (untyped) plan layer mirroring javascript/ltx/ltx-sdk.js.
 *
 * The typed models (LtxPlan, V11.PlanV11) serialise their fields in a fixed
 * order, but the frozen v2 planId (LTX-SPECIFICATION.md §4.3) hashes
 * JSON.stringify of the plan *in insertion order*, and the golden vectors
 * (spec/golden/plan-ids.json) include plans with arbitrary key order, relay
 * objects and v3 fields. This file therefore works on plain JSON values:
 *
 *   Map[String, Any] (VectorMap from parse, insertion order), Seq[Any],
 *   String, Long / Int / Double, Boolean, null
 *
 * and provides: a JSON parser, JSON.stringify and canonicalJSON equivalents,
 * makePlanId / planHash over such maps, and validatePlan with the reserved
 * streams (§3.5) / branching (§7) rules.
 */

import java.math.BigDecimal
import java.time.{Instant, LocalDate, LocalDateTime, OffsetDateTime, ZoneOffset}
import scala.collection.immutable.VectorMap
import scala.util.Try

/** One validatePlan error: { code, path, message } (LTX-SPECIFICATION.md §4.6). */
case class PlanError(code: String, path: String, message: String)

/** validatePlan result: { valid, errors }. */
case class PlanValidation(valid: Boolean, errors: List[PlanError])

/**
 * Thrown by createSession (and any other enforcement point) when a plan uses a
 * reserved field. `code` is the first error's code: reserved_streams or
 * reserved_branching; `errors` carries every violation.
 */
class LtxPlanException(val code: String, val errors: List[PlanError], message: String)
  extends IllegalArgumentException(message)

object LtxJson:

  // ---- parse ----

  /**
   * Parse JSON text. Objects become VectorMap (insertion order kept), arrays
   * Vector, integers Long (Double if they overflow), other numbers Double.
   */
  def parse(text: String): Any =
    val p = new Parser(text)
    p.ws()
    val v = p.value()
    p.ws()
    if p.i != text.length then throw new IllegalArgumentException(s"JSON: trailing characters at ${p.i}")
    v

  private class Parser(s: String):
    var i = 0
    def ws(): Unit = while i < s.length && " \t\r\n".indexOf(s(i)) >= 0 do i += 1
    def value(): Any =
      if i >= s.length then throw new IllegalArgumentException("JSON: unexpected end")
      s(i) match
        case '{' => obj()
        case '[' => arr()
        case '"' => str()
        case 't' => lit("true", true)
        case 'f' => lit("false", false)
        case 'n' => lit("null", null)
        case _   => num()
    def lit(word: String, v: Any): Any =
      if !s.startsWith(word, i) then throw new IllegalArgumentException(s"JSON: bad literal at $i")
      i += word.length
      v
    def obj(): Map[String, Any] =
      var m = VectorMap.empty[String, Any]
      i += 1; ws()
      if s(i) == '}' then { i += 1; return m }
      while true do
        ws()
        val k = str()
        ws()
        if s(i) != ':' then throw new IllegalArgumentException(s"JSON: expected ':' at $i")
        i += 1; ws()
        m = m.updated(k, value())
        ws()
        s(i) match
          case ',' => i += 1
          case '}' => i += 1; return m
          case _   => throw new IllegalArgumentException(s"JSON: expected ',' or '}' at $i")
      m
    def arr(): Vector[Any] =
      val b = Vector.newBuilder[Any]
      i += 1; ws()
      if s(i) == ']' then { i += 1; return b.result() }
      while true do
        ws()
        b += value()
        ws()
        s(i) match
          case ',' => i += 1
          case ']' => i += 1; return b.result()
          case _   => throw new IllegalArgumentException(s"JSON: expected ',' or ']' at $i")
      b.result()
    def str(): String =
      if s(i) != '"' then throw new IllegalArgumentException(s"JSON: expected string at $i")
      i += 1
      val sb = new StringBuilder
      while true do
        val c = s(i); i += 1
        c match
          case '"' => return sb.toString
          case '\\' =>
            val e = s(i); i += 1
            e match
              case '"'  => sb += '"'
              case '\\' => sb += '\\'
              case '/'  => sb += '/'
              case 'b'  => sb += '\b'
              case 'f'  => sb += '\f'
              case 'n'  => sb += '\n'
              case 'r'  => sb += '\r'
              case 't'  => sb += '\t'
              case 'u'  => sb += Integer.parseInt(s.substring(i, i + 4), 16).toChar; i += 4
              case _    => throw new IllegalArgumentException(s"JSON: bad escape \\$e")
          case _ => sb += c
      sb.toString
    def num(): Any =
      val start = i
      if s(i) == '-' then i += 1
      while i < s.length && (s(i).isDigit || ".eE+-".indexOf(s(i)) >= 0) do i += 1
      val tok = s.substring(start, i)
      if tok.isEmpty || tok == "-" then throw new IllegalArgumentException(s"JSON: bad number at $start")
      if tok.exists(c => ".eE".indexOf(c) >= 0) then tok.toDouble
      else tok.toLongOption.getOrElse(tok.toDouble)

  // ---- stringify (JSON.stringify semantics) ----

  /** JSON.stringify(v): insertion-order keys, no whitespace. */
  def stringify(v: Any): String = { val sb = new StringBuilder; write(sb, v, false); sb.toString }

  /** canonicalJSON(v) exactly as ltx-sdk.js: keys sorted by UTF-16 code units. */
  def canonical(v: Any): String = { val sb = new StringBuilder; write(sb, v, true); sb.toString }

  private def write(sb: StringBuilder, v: Any, sorted: Boolean): Unit = v match
    case null          => sb ++= "null"
    case b: Boolean    => sb ++= (if b then "true" else "false")
    case s: String     => quote(sb, s)
    case n: Int        => sb ++= n.toString
    case n: Long       => sb ++= n.toString
    case n: Short      => sb ++= n.toString
    case n: Byte       => sb ++= n.toString
    case d: Double     => sb ++= jsNumber(d)
    case f: Float      => sb ++= jsNumber(f.toDouble)
    case m: Map[?, ?]  =>
      sb += '{'
      val keys = m.keys.map(_.toString).toList
      val ordered = if sorted then keys.sorted else keys
      val lookup = m.asInstanceOf[Map[Any, Any]]
      var first = true
      for k <- ordered do
        if !first then sb += ','
        first = false
        quote(sb, k)
        sb += ':'
        write(sb, lookup(k), sorted)
      sb += '}'
    case xs: Iterable[?] =>
      sb += '['
      var first = true
      for e <- xs do
        if !first then sb += ','
        first = false
        write(sb, e, sorted)
      sb += ']'
    case other => quote(sb, other.toString)

  /** JSON.stringify string quoting (ES2019 well-formed: lone surrogates escaped). */
  def quote(sb: StringBuilder, s: String): Unit =
    sb += '"'
    var i = 0
    while i < s.length do
      val c = s(i)
      if c == '"' then sb ++= "\\\""
      else if c == '\\' then sb ++= "\\\\"
      else if c == '\b' then sb ++= "\\b"
      else if c == '\f' then sb ++= "\\f"
      else if c == '\n' then sb ++= "\\n"
      else if c == '\r' then sb ++= "\\r"
      else if c == '\t' then sb ++= "\\t"
      else if c < ' ' then sb ++= f"\\u${c.toInt}%04x"
      else if Character.isHighSurrogate(c) && i + 1 < s.length && Character.isLowSurrogate(s(i + 1)) then
        sb += c; sb += s(i + 1); i += 1
      else if Character.isSurrogate(c) then sb ++= f"\\u${c.toInt}%04x"
      else sb += c
      i += 1
    sb += '"'

  /** ECMAScript Number::toString for finite doubles; NaN/Infinity -> "null" as in JSON. */
  def jsNumber(d: Double): String =
    if d.isNaN || d.isInfinite then return "null"
    if d == 0.0 then return "0"
    val bd = new BigDecimal(java.lang.Double.toString(d)).stripTrailingZeros()
    val neg = bd.signum() < 0
    val digits = bd.unscaledValue().abs().toString
    val k = digits.length
    val n = k - bd.scale() // value = 0.digits * 10^n
    val body =
      if n >= k && n <= 21 then digits + "0" * (n - k)
      else if n >= 1 && n <= 21 then digits.substring(0, n) + "." + digits.substring(n)
      else if n >= -5 && n <= 0 then "0." + "0" * (-n) + digits
      else
        val e = n - 1
        val mant = if k == 1 then digits else s"${digits(0)}.${digits.substring(1)}"
        mant + "e" + (if e >= 0 then "+" else "-") + math.abs(e)
    if neg then "-" + body else body

object LtxPlans:

  /** Every segment type the reference SDKs handle (core §3.4 + auxiliary). */
  val PLAN_SEGMENT_TYPES: List[String] = List("PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
    "SPEAK", "REST", "PAD", "OPEN", "RELAY")
  val PLAN_MODES: List[String] = List("LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC")
  /** Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3). */
  val V3_ONLY_FIELDS: List[String] = List("delays", "planVersion", "prevPlanHash", "questions", "actions", "streams")
  /** Reserved branching identifiers (§7): MUST be absent from plans and segments. */
  val RESERVED_BRANCH_PLAN_FIELDS: List[String] = List("branches", "branching")
  val RESERVED_BRANCH_SEGMENT_FIELDS: List[String] = List("branch")
  /** Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream. */
  val RESERVED_STREAM_SEGMENT_FIELDS: List[String] = List("stream")

  private val NODE_ROLES = List("HOST", "PARTICIPANT", "OBSERVER")
  private val HEX64 = "^[0-9a-f]{64}$".r

  // ---- JS value helpers ----

  private def isNum(v: Any): Boolean = v match
    case _: Int | _: Long | _: Double | _: Float | _: Short | _: Byte => true
    case _ => false
  private def num(v: Any): Double = v match
    case n: Int    => n.toDouble
    case n: Long   => n.toDouble
    case n: Double => n
    case n: Float  => n.toDouble
    case n: Short  => n.toDouble
    case n: Byte   => n.toDouble
    case _         => Double.NaN
  /** Number.isInteger */
  private def isInteger(v: Any): Boolean = v match
    case _: Int | _: Long | _: Short | _: Byte => true
    case d: Double => !d.isNaN && !d.isInfinite && d == math.floor(d)
    case f: Float  => !f.isNaN && !f.isInfinite && f.toDouble == math.floor(f.toDouble)
    case _ => false
  /** JS strict equality against a number literal. */
  private def numEq(v: Any, n: Int): Boolean = isNum(v) && num(v) == n.toDouble
  /** JS truthiness. */
  private def truthy(v: Any): Boolean = v match
    case null       => false
    case b: Boolean => b
    case s: String  => s.nonEmpty
    case _ if isNum(v) => num(v) != 0.0 && !num(v).isNaN
    case _          => true
  private def anyIn(v: Any, c: Iterable[String]): Boolean = v match
    case s: String => c.exists(_ == s)
    case _         => false

  private def asMap(v: Any): Option[Map[String, Any]] = v match
    case m: Map[?, ?] => Some(m.asInstanceOf[Map[String, Any]])
    case _            => None
  private def asSeq(v: Any): Option[Seq[Any]] = v match
    case _: String    => None
    case _: Map[?, ?] => None
    case xs: Seq[?]   => Some(xs.asInstanceOf[Seq[Any]])
    case _            => None

  /** JS \s (WhiteSpace and LineTerminator). */
  private def isJsSpace(c: Char): Boolean =
    "\t\n\u000b\u000c\r       　﻿".indexOf(c) >= 0 ||
      (c >= ' ' && c <= ' ')

  def stripSpaceUpper(s: String): String =
    s.filterNot(isJsSpace).toUpperCase(java.util.Locale.ROOT)

  /** Date.parse; None when JS would return NaN (subset: ISO 8601 forms). */
  private def parseDateMs(s: String): Option[Long] =
    Try(Instant.parse(s).toEpochMilli).toOption
      .orElse(Try(OffsetDateTime.parse(s).toInstant.toEpochMilli).toOption)
      .orElse(Try(LocalDate.parse(s).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli).toOption)
      .orElse(Try(LocalDateTime.parse(s).toInstant(ZoneOffset.UTC).toEpochMilli).toOption)

  /** Replace or append a key keeping insertion order ({ ...m, k: v } in JS). */
  def withKey(m: Map[String, Any], k: String, v: Any): Map[String, Any] =
    if m.contains(k) then VectorMap.from(m.toSeq.map((kk, vv) => if kk == k then (kk, v) else (kk, vv)))
    else VectorMap.from(m.toSeq :+ (k -> v))

  // ---- upgradeConfig / makePlanId / planHash ----

  /** upgradeConfig(cfg): v1 -> v2 (unchanged for v2/v3 plans with nodes). */
  def upgradeConfig(cfg: Map[String, Any]): Map[String, Any] =
    val v = cfg.getOrElse("v", null)
    val hasNodes = asSeq(cfg.getOrElse("nodes", null)).exists(_.nonEmpty)
    if isNum(v) && num(v) >= 2 && hasNodes then cfg
    else
      val rxName = cfg.get("rxName").collect { case s: String => s }.getOrElse("").toLowerCase(java.util.Locale.ROOT)
      val remoteLoc = if rxName.contains("mars") then "mars" else if rxName.contains("moon") then "moon" else "earth"
      def or(key: String, dflt: Any): Any = cfg.get(key).filter(truthy).getOrElse(dflt)
      val nodes = Vector(
        VectorMap[String, Any]("id" -> "N0", "name" -> or("txName", "Earth HQ"), "role" -> "HOST",
          "delay" -> 0L, "location" -> "earth"),
        VectorMap[String, Any]("id" -> "N1", "name" -> or("rxName", "Mars Hab-01"), "role" -> "PARTICIPANT",
          "delay" -> or("delay", 0L), "location" -> remoteLoc))
      withKey(withKey(cfg, "v", 2L), "nodes", nodes)

  private def sha256Hex(s: String): String =
    Security.sha256(s.getBytes("UTF-8")).map(b => f"${b & 0xff}%02x").mkString

  /** SHA-256 hex of the canonical JSON of a plan (prevPlanHash, §6.4). */
  def planHash(plan: Map[String, Any]): String = sha256Hex(LtxJson.canonical(plan))

  /**
   * makePlanId over a plain plan map, exactly as ltx-sdk.js: v2 is the FROZEN
   * imul31 hash of JSON.stringify in insertion order (§4.3); v3 is SHA-256 over
   * canonical JSON (§4.5).
   */
  def makePlanId(cfg: Map[String, Any]): String =
    val c = upgradeConfig(cfg)
    val startMs = parseDateMs(String.valueOf(c.getOrElse("start", null)))
      .getOrElse(throw new IllegalArgumentException(s"makePlanId: invalid start ${c.get("start")}"))
    val date = Instant.ofEpochMilli(startMs).atOffset(ZoneOffset.UTC).toLocalDate.toString.replace("-", "")
    val nodes = asSeq(c.getOrElse("nodes", null)).getOrElse(Nil)
    val hostName = nodes.headOption.flatMap(asMap).flatMap(_.get("name")).orNull
    val hostStr = stripSpaceUpper(if truthy(hostName) then hostName.toString else "HOST").take(8)
    val nodeStr =
      if nodes.length > 1 then
        nodes.drop(1).map(n => stripSpaceUpper(String.valueOf(asMap(n).get("name")))
          .take(4)).mkString("-").take(16)
      else "RX"
    val v = c.getOrElse("v", null)
    if isNum(v) && num(v) >= 3 then
      s"LTX-$date-$hostStr-$nodeStr-v3-${planHash(c).substring(0, 8)}"
    else
      // FROZEN v2 path (LTX-SPECIFICATION.md §4.3) -- imul31 over UTF-16 code units.
      val raw = LtxJson.stringify(c)
      var h = 0
      raw.foreach(ch => h = 31 * h + ch.toInt)
      f"LTX-$date-$hostStr-$nodeStr-v2-${h}%08x"

  // ---- validatePlan (§3.5, §4, §7) ----

  /** Reserved-field violations only (§3.5 streams, §7 branching). */
  def reservedFieldErrors(plan: Any): List[PlanError] =
    val errors = List.newBuilder[PlanError]
    asMap(plan).foreach { p =>
      if p.contains("streams") && !asSeq(p("streams")).exists(_.isEmpty) then
        errors += PlanError("reserved_streams", "streams",
          "streams[] is reserved (§3.5) and MUST be absent or empty")
      for f <- RESERVED_BRANCH_PLAN_FIELDS if p.contains(f) do
        errors += PlanError("reserved_branching", f,
          s"$f is reserved for branching (§7, not yet implemented) and MUST be absent")
      asSeq(p.getOrElse("segments", null)).getOrElse(Nil).zipWithIndex.foreach { (sv, i) =>
        asMap(sv).foreach { s =>
          for f <- RESERVED_STREAM_SEGMENT_FIELDS if s.contains(f) do
            errors += PlanError("reserved_streams", s"segments[$i].$f",
              s"segment $f is reserved (§3.5) and MUST be absent")
          for f <- RESERVED_BRANCH_SEGMENT_FIELDS if s.contains(f) do
            errors += PlanError("reserved_branching", s"segments[$i].$f",
              s"segment $f is reserved for branching (§7) and MUST be absent")
        }
      }
    }
    errors.result()

  /** Throw LtxPlanException (code = first error code) if a plan uses reserved fields. */
  def assertNoReservedFields(plan: Any, fnName: String): Unit =
    val errors = reservedFieldErrors(plan)
    if errors.nonEmpty then
      throw new LtxPlanException(errors.head.code, errors, s"$fnName: ${errors.head.message}")

  /**
   * Validate a v2 or v3 plan against the wire format (spec/ltx-schema.json,
   * LTX-SPECIFICATION.md §4) and the reserved-field rules (§3.5, §7).
   * Pure; never throws. Mirrors ltx-sdk.js validatePlan.
   */
  def validatePlan(plan: Any): PlanValidation =
    val errors = List.newBuilder[PlanError]
    def err(code: String, path: String, message: String): Unit = errors += PlanError(code, path, message)
    asMap(plan) match
      case None =>
        err("not_an_object", "", "plan must be an object")
        PlanValidation(false, errors.result())
      case Some(p) =>
        val v = p.getOrElse("v", null)
        if !numEq(v, 2) && !numEq(v, 3) then err("invalid_version", "v", "v must be 2 or 3")
        for f <- List("title", "start", "quantum", "mode", "nodes", "segments") if !p.contains(f) do
          err("missing_field", f, s"$f is required")
        if p.contains("title") && !p("title").isInstanceOf[String] then
          err("invalid_field", "title", "title must be a string")
        if p.contains("start") then
          p("start") match
            case s: String if parseDateMs(s).isDefined => ()
            case _ => err("invalid_field", "start", "start must be an ISO 8601 UTC timestamp")
        if p.contains("quantum") then
          val q = p("quantum")
          if !(isInteger(q) && num(q) >= 1 && num(q) <= 60) then
            err("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)")
        if p.contains("mode") && !anyIn(p("mode"), PLAN_MODES) then
          err("invalid_mode", "mode", s"mode must be one of ${PLAN_MODES.mkString(", ")}")

        val ids = scala.collection.mutable.LinkedHashSet.empty[String]
        if p.contains("nodes") then
          asSeq(p("nodes")) match
            case Some(nodes) if nodes.nonEmpty =>
              var hosts = 0
              nodes.zipWithIndex.foreach { (nv, i) =>
                val ok = asMap(nv).exists { n =>
                  n.get("id").exists { case id: String => id.nonEmpty && !id.contains('|'); case _ => false } &&
                  n.get("name").exists(_.isInstanceOf[String]) &&
                  anyIn(n.getOrElse("role", null), NODE_ROLES) &&
                  n.get("delay").exists(d => isNum(d) && num(d) >= 0)
                }
                if !ok then
                  err("invalid_nodes", s"nodes[$i]", "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0")
                else
                  val n = asMap(nv).get
                  val id = n("id").asInstanceOf[String]
                  if ids.contains(id) then err("duplicate_node_id", s"nodes[$i].id", s"duplicate node id $id")
                  ids += id
                  if n("role") == "HOST" then hosts += 1
              }
              val h = asMap(nodes.head)
              if hosts != 1 || h.isEmpty || h.get.getOrElse("role", null) != "HOST" || !numEq(h.get.getOrElse("delay", null), 0) then
                err("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)")
            case _ =>
              err("invalid_nodes", "nodes", "nodes must be a non-empty array")

        if p.contains("segments") then
          asSeq(p("segments")) match
            case None => err("invalid_segment", "segments", "segments must be an array")
            case Some(segs) =>
              segs.zipWithIndex.foreach { (sv, i) =>
                asMap(sv) match
                  case Some(s) if anyIn(s.getOrElse("type", null), PLAN_SEGMENT_TYPES) &&
                                  isInteger(s.getOrElse("q", null)) && num(s("q")) >= 1 =>
                    if s.contains("speaker") && !anyIn(s("speaker"), ids) then
                      err("unknown_speaker", s"segments[$i].speaker", s"speaker ${s("speaker")} is not a node id")
                  case _ =>
                    err("invalid_segment", s"segments[$i]", "segment needs a known type and integer q >= 1")
              }

        if numEq(v, 2) then
          for f <- V3_ONLY_FIELDS if p.contains(f) do
            err("v3_field_in_v2", f, s"$f is a v3 field and MUST NOT appear in a v2 plan (§4.3)")
        else if numEq(v, 3) then
          if p.contains("delays") then
            asMap(p("delays")) match
              case None => err("invalid_delays", "delays", "delays must be an object")
              case Some(d) =>
                for (k, dv) <- d do
                  val parts = k.split("\\|", -1)
                  if parts.length != 2 || parts(0).compareTo(parts(1)) >= 0 ||
                     (ids.nonEmpty && (!ids.contains(parts(0)) || !ids.contains(parts(1)))) ||
                     !isNum(dv) || !(num(dv) >= 0) then
                    err("invalid_delays", s"delays.$k", "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)")
          if p.contains("planVersion") then
            val pv = p("planVersion")
            if !(isInteger(pv) && num(pv) >= 1) then err("invalid_field", "planVersion", "planVersion must be an integer >= 1")
          if p.contains("prevPlanHash") then
            p("prevPlanHash") match
              case s: String if HEX64.matches(s) => ()
              case _ => err("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters")
          for f <- List("questions", "actions") if p.contains(f) && asSeq(p(f)).isEmpty do
            err("invalid_field", f, s"$f must be an array")

        errors ++= reservedFieldErrors(p)
        val all = errors.result()
        PlanValidation(all.isEmpty, all)
