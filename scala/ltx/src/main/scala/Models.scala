/**
 * Models.scala - LTX data model case classes
 * Story 33.13 - Scala LTX library
 */

/** A segment template entry specifying type and number of quanta. */
case class LtxSegmentTemplate(segType: String, q: Int)

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
    val segsJson = segments.map { s =>
      "{\"type\":\"" + jsonEsc(s.segType) + "\",\"q\":" + s.q + "}"
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

  private def jsonEsc(s: String): String =
    if s == null then "" else s.replace("\\", "\\\\").replace("\"", "\\\"")

object LtxPlan:
  /** Parse an LtxPlan from a JSON string. Returns None on any parse error. */
  def fromJson(json: String): Option[LtxPlan] =
    if json == null || json.trim.isEmpty then return None
    try
      val plan = parseJson(json.trim)
      if plan.start.isEmpty then None else Some(plan)
    catch case _: Exception => None

  private def parseJson(json: String): LtxPlan =
    val v       = numField(json, "v").toInt
    val title   = strField(json, "title")
    val start   = strField(json, "start")
    val quantum = numField(json, "quantum").toInt
    val mode    = strField(json, "mode")

    val nodes: List[LtxNode] =
      val nIdx = json.indexOf("\"nodes\"")
      if nIdx < 0 then Nil
      else
        val arrOpen  = json.indexOf('[', nIdx)
        val arrClose = findMatchingBracket(json, arrOpen, '[', ']')
        if arrOpen < 0 || arrClose <= arrOpen then Nil
        else
          splitObjects(json.substring(arrOpen + 1, arrClose)).flatMap { obj =>
            val id  = strField(obj, "id")
            val nm  = strField(obj, "name")
            val rl  = strField(obj, "role")
            val dl  = numField(obj, "delay").toInt
            val loc = strField(obj, "location")
            if id.nonEmpty then Some(LtxNode(id, nm, rl, dl, loc)) else None
          }

    val segs: List[LtxSegmentTemplate] =
      val sIdx = json.indexOf("\"segments\"")
      if sIdx < 0 then Nil
      else
        val arrOpen  = json.indexOf('[', sIdx)
        val arrClose = findMatchingBracket(json, arrOpen, '[', ']')
        if arrOpen < 0 || arrClose <= arrOpen then Nil
        else
          splitObjects(json.substring(arrOpen + 1, arrClose)).flatMap { obj =>
            val t = strField(obj, "type")
            val q = numField(obj, "q").toInt
            if t.nonEmpty then Some(LtxSegmentTemplate(t, q)) else None
          }

    LtxPlan(v, title, start, quantum, mode, nodes, segs)

  /** Extract a quoted string field from JSON. */
  private def strField(json: String, key: String): String =
    val pat = "\"" + key + "\":\""
    val i = json.indexOf(pat)
    if i < 0 then return ""
    var s = i + pat.length
    var e = s
    while e < json.length && json.charAt(e) != '"' do
      if json.charAt(e) == '\\' then e += 1
      e += 1
    json.substring(s, e)

  /** Extract a numeric field from JSON. */
  private def numField(json: String, key: String): Double =
    val pat = "\"" + key + "\":"
    val i = json.indexOf(pat)
    if i < 0 then return 0.0
    var s = i + pat.length
    while s < json.length && json.charAt(s) == ' ' do s += 1
    var e = s
    while e < json.length && (json.charAt(e).isDigit || json.charAt(e) == '.' || json.charAt(e) == '-') do
      e += 1
    if s == e then 0.0
    else
      try json.substring(s, e).toDouble
      catch case _: NumberFormatException => 0.0

  private def findMatchingBracket(s: String, open: Int, openCh: Char, closeCh: Char): Int =
    var depth = 0
    var i = open
    while i < s.length do
      if s.charAt(i) == openCh then depth += 1
      else if s.charAt(i) == closeCh then
        depth -= 1
        if depth == 0 then return i
      i += 1
    -1

  private def splitObjects(arr: String): List[String] =
    val result = scala.collection.mutable.ListBuffer[String]()
    var depth = 0
    var start = -1
    var i = 0
    while i < arr.length do
      val c = arr.charAt(i)
      if c == '{' then
        if depth == 0 then start = i
        depth += 1
      else if c == '}' then
        depth -= 1
        if depth == 0 && start >= 0 then
          result += arr.substring(start, i + 1)
          start = -1
      i += 1
    result.toList
