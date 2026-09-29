/**
 * Models.scala - LTX data model case classes
 * Story 33.13 - Scala LTX library
 */

/**
 * A segment template entry specifying type and number of quanta, and
 * optionally the presenting node id (speaker) and an agenda title (label):
 * the attributed segments of LTX-SPECIFICATION.md section 3.4.1. None means
 * absent; absent fields are not serialised.
 */
case class LtxSegmentTemplate(
  segType: String,
  q:       Int,
  speaker: Option[String] = None,
  label:   Option[String] = None
)

/** A node (participant) in an LTX session. */
case class LtxNode(
  id:       String,
  name:     String,
  role:     String,
  delay:    Int,
  location: String
)

/** A computed timed segment with absolute start/end timestamps in UTC ms. */
case class LtxSegment(
  segType: String,
  q:       Int,
  startMs: Long,
  endMs:   Long,
  durMin:  Int
)

/** A node URL for a specific participant perspective. */
case class LtxNodeUrl(
  nodeId: String,
  name:   String,
  role:   String,
  url:    String
)

/**
 * The full LTX session plan configuration (v2 schema).
 * toJson key order: v, title, start, quantum, mode, nodes, segments
 * nodes MUST come before segments to match JS JSON.stringify hash.
 */
case class LtxPlan(
  v:        Int,
  title:    String,
  start:    String,
  quantum:  Int,
  mode:     String,
  nodes:    List[LtxNode],
  segments: List[LtxSegmentTemplate]
):
  def toJson: String =
    // Manual JSON builder - key order MUST be: v, title, start, quantum, mode, nodes, segments
    // The literal patterns "nodes":[ and "segments":[ are intentional for hash compatibility.
    val nodesJson = nodes.map { n =>
      "{\"id\":\"" + jsonEsc(n.id) + "\",\"name\":\"" + jsonEsc(n.name) +
      "\",\"role\":\"" + jsonEsc(n.role) + "\",\"delay\":" + n.delay +
      ",\"location\":\"" + jsonEsc(n.location) + "\"}"
    }.mkString(",")
    // Attributed segments (section 3.4.1): speaker and label follow type and
    // q, only when present, as ltx-sdk.js writes them.
    val segsJson = segments.map { s =>
      "{\"type\":\"" + jsonEsc(s.segType) + "\",\"q\":" + s.q +
      s.speaker.map(sp => ",\"speaker\":\"" + jsonEsc(sp) + "\"").getOrElse("") +
      s.label.map(lb => ",\"label\":\"" + jsonEsc(lb) + "\"").getOrElse("") + "}"
    }.mkString(",")
    val sb = new java.lang.StringBuilder
    sb.append("{\"v\":").append(v)
    sb.append(",\"title\":\"").append(jsonEsc(title)).append("\"")
    sb.append(",\"start\":\"").append(jsonEsc(start)).append("\"")
    sb.append(",\"quantum\":").append(quantum)
    sb.append(",\"mode\":\"").append(jsonEsc(mode)).append("\"")
    sb.append(",\"nodes\":[").append(nodesJson).append("]")
    sb.append(",\"segments\":[").append(segsJson).append("]")
    sb.append("}")
    sb.toString

  /**
   * The inside of a JSON string exactly as JSON.stringify writes it: quote,
   * backslash, \b \f \n \r \t, other control characters and lone surrogates
   * as lowercase \\u00XX / \\uXXXX.
   */
  private def jsonEsc(s: String): String =
    if s == null then ""
    else
      val sb = new StringBuilder
      LtxJson.quote(sb, s)
      sb.substring(1, sb.length - 1)

object LtxPlan:
  /** Parse an LtxPlan from a JSON string. Returns None on any parse error. */
  def fromJson(json: String): Option[LtxPlan] =
    if json == null || json.trim.isEmpty then return None
    try
      val plan = parseJson(json.trim)
      if plan.start.isEmpty then None else Some(plan)
    catch case _: Exception => None

  private def parseJson(json: String): LtxPlan =
    val m = LtxJson.parse(json) match
      case o: Map[?, ?] => o.asInstanceOf[Map[String, Any]]
      case _            => throw new IllegalArgumentException("plan JSON is not an object")
    def str(o: Map[String, Any], k: String): String = o.get(k) match
      case Some(s: String) => s
      case _               => ""
    def num(o: Map[String, Any], k: String): Int = o.get(k) match
      case Some(n: Long)   => n.toInt
      case Some(n: Double) => n.toInt
      case _               => 0
    def opt(o: Map[String, Any], k: String): Option[String] = o.get(k) match
      case Some(s: String) => Some(s)
      case _               => None
    def objs(k: String): List[Map[String, Any]] = m.get(k) match
      case Some(xs: Seq[?]) => xs.toList.collect { case o: Map[?, ?] => o.asInstanceOf[Map[String, Any]] }
      case _                => Nil

    val nodes = objs("nodes").flatMap { n =>
      val id = str(n, "id")
      if id.nonEmpty then Some(LtxNode(id, str(n, "name"), str(n, "role"), num(n, "delay"), str(n, "location")))
      else None
    }
    val segs = objs("segments").flatMap { sg =>
      val t = str(sg, "type")
      if t.nonEmpty then Some(LtxSegmentTemplate(t, num(sg, "q"), opt(sg, "speaker"), opt(sg, "label")))
      else None
    }
    LtxPlan(num(m, "v"), str(m, "title"), str(m, "start"), num(m, "quantum"), str(m, "mode"), nodes, segs)
