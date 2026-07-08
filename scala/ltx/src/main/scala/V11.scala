/**
 * V11.scala -- LTX v1.1 core subset (Epic 72, Story 72.3)
 * Scala 3 port of the TypeScript reference (segments.ts / session.ts /
 * amend.ts / registers.ts / cbor.ts / cose.ts).
 *
 * Features:
 *   1. v3 planId (SHA-256 over RFC 8785 canonical JSON) + pairDelay +
 *      computeSegmentsFor (frozen v2 polynomial path kept byte-identical)
 *   2. Pure transition() session state machine (LTX-SPECIFICATION.md §5)
 *   3. Amendment-chain verification (§6.4, LTX-SECURITY.md §7.6) — per-link
 *      signatures via the existing Security.verifyPlan envelope
 *   4. Signed register entries + deterministic reducers (§8.2/§9/§10)
 *   5. Deterministic CBOR decoder + COSE_Sign1 verification (RFC 8949/9052)
 */

import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.time.Instant
import scala.util.Try

object V11:

  val VERSION = "1.1.0"
  val COSE_SIGN1_TAG = 18L
  val COSE_ALG_ED25519 = -19L
  val DELAY_VIOLATION_DEGRADE_S = 300L
  val LOCK_TIMEOUT_FACTOR = 2L

  private val SPKI_HDR = Array[Byte](0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)

  private def hex(bytes: Array[Byte]): String =
    bytes.map(b => f"${b & 0xff}%02x").mkString

  // ---- v1.1 plan model ----

  case class NodeV11(
    id:       String,
    name:     String,
    role:     String,
    delay:    Long = 0,
    location: String = "earth",
  )

  case class SegV11(
    segType: String,
    q:       Int,
    speaker: Option[String] = None,
    label:   Option[String] = None,
  )

  /** LTX plan supporting both v2 (frozen) and v3 (§4.4) schemas. */
  case class PlanV11(
    v:            Int = 2,
    title:        String = "",
    start:        String = "",
    quantum:      Int = 5,
    mode:         String = "LTX",
    nodes:        List[NodeV11] = Nil,
    segments:     List[SegV11] = Nil,
    delays:       Option[Map[String, Long]] = None, // v3 pair matrix, "A|B" sorted ids
    planVersion:  Option[Int] = None,
    prevPlanHash: Option[String] = None,
  ):
    /** Generic map projection used for canonical JSON hashing. */
    def toMap: Map[String, Any] =
      var m: Map[String, Any] = Map(
        "v" -> v,
        "title" -> title,
        "start" -> start,
        "quantum" -> quantum,
        "mode" -> mode,
        "nodes" -> nodes.map(n => Map(
          "id" -> n.id, "name" -> n.name, "role" -> n.role,
          "delay" -> n.delay, "location" -> n.location)),
        "segments" -> segments.map { s =>
          var seg: Map[String, Any] = Map("type" -> s.segType, "q" -> s.q)
          s.speaker.foreach(sp => seg = seg + ("speaker" -> sp))
          s.label.foreach(lb => seg = seg + ("label" -> lb))
          seg
        },
      )
      delays.foreach(d => m = m + ("delays" -> d))
      planVersion.foreach(pv => m = m + ("planVersion" -> pv))
      prevPlanHash.foreach(ph => m = m + ("prevPlanHash" -> ph))
      m

  /** SHA-256 hex of the RFC 8785 canonical JSON of a plan (amend.ts). */
  def planHash(p: PlanV11): String =
    hex(Security.sha256(Security.canonicalJson(p.toMap).getBytes("UTF-8")))

  // ---- FROZEN v2 JSON serialisation (insertion-order JSON.stringify) ----

  private def jsonStr(s: String): String =
    val sb = new StringBuilder("\"")
    s.foreach {
      case '"'  => sb ++= "\\\""
      case '\\' => sb ++= "\\\\"
      case '\n' => sb ++= "\\n"
      case '\r' => sb ++= "\\r"
      case '\t' => sb ++= "\\t"
      case c    => sb += c
    }
    sb += '"'
    sb.toString

  /**
   * v,title,start,quantum,mode,nodes(id,name,role,delay,location),
   * segments(type,q[,speaker][,label]) — must stay byte-identical (§4.3).
   */
  def toJsonV2(p: PlanV11): String =
    val sb = new StringBuilder("{")
    sb ++= "\"v\":" + p.v
    sb ++= ",\"title\":" + jsonStr(p.title)
    sb ++= ",\"start\":" + jsonStr(p.start)
    sb ++= ",\"quantum\":" + p.quantum
    sb ++= ",\"mode\":" + jsonStr(p.mode)
    sb ++= ",\"nodes\":["
    p.nodes.zipWithIndex.foreach { case (n, i) =>
      if i > 0 then sb += ','
      sb ++= "{\"id\":" + jsonStr(n.id)
      sb ++= ",\"name\":" + jsonStr(n.name)
      sb ++= ",\"role\":" + jsonStr(n.role)
      sb ++= ",\"delay\":" + n.delay
      sb ++= ",\"location\":" + jsonStr(n.location) + "}"
    }
    sb ++= "],\"segments\":["
    p.segments.zipWithIndex.foreach { case (s, i) =>
      if i > 0 then sb += ','
      sb ++= "{\"type\":" + jsonStr(s.segType)
      sb ++= ",\"q\":" + s.q
      s.speaker.foreach(sp => sb ++= ",\"speaker\":" + jsonStr(sp))
      s.label.foreach(lb => sb ++= ",\"label\":" + jsonStr(lb))
      sb += '}'
    }
    sb ++= "]}"
    sb.toString

  // ---- 1. plan ID (v3 SHA-256 + frozen v2 polynomial) ----

  /**
   * Deterministic plan ID. v3 plans hash SHA-256 over RFC 8785 canonical JSON
   * (§4.5, "-v3-" infix); the v2 polynomial path is FROZEN (§4.3).
   */
  def makePlanId(p: PlanV11): String =
    val date = p.start.substring(0, 10).replace("-", "")
    val hostStr =
      val h = p.nodes.headOption.map(_.name.replaceAll("\\s+", "").toUpperCase).getOrElse("HOST")
      if h.length > 8 then h.substring(0, 8) else h
    val nodeStr =
      if p.nodes.length > 1 then
        val s = p.nodes.tail.map { n =>
          val x = n.name.replaceAll("\\s+", "").toUpperCase
          if x.length > 4 then x.substring(0, 4) else x
        }.mkString("-")
        if s.length > 16 then s.substring(0, 16) else s
      else "RX"
    if p.v >= 3 then
      val digest = planHash(p)
      s"LTX-$date-$hostStr-$nodeStr-v3-${digest.substring(0, 8)}"
    else
      // FROZEN v2 path -- 32-bit polynomial hash over the JSON (UTF-16 units).
      val raw = toJsonV2(p)
      var h = 0
      raw.foreach(c => h = 31 * h + c.toInt)
      f"LTX-$date-$hostStr-$nodeStr-v2-${h & 0xffffffffL}%08x"

  // ---- 1. pairDelay + computeSegmentsFor ----

  /**
   * One-way delay in seconds between two nodes (§3.7). The v3 pair matrix is
   * authoritative where present; fallback: HOST pairs use the node's declared
   * delay, non-HOST pairs the sum of both HOST-relative delays.
   */
  def pairDelay(p: PlanV11, nodeIdA: String, nodeIdB: String): Long =
    if nodeIdA == nodeIdB then 0L
    else
      val key = List(nodeIdA, nodeIdB).sorted.mkString("|")
      p.delays.flatMap(_.get(key)) match
        case Some(d) => d
        case None =>
          val a = p.nodes.find(_.id == nodeIdA)
            .getOrElse(throw IllegalArgumentException(s"pairDelay: unknown node $nodeIdA"))
          val b = p.nodes.find(_.id == nodeIdB)
            .getOrElse(throw IllegalArgumentException(s"pairDelay: unknown node $nodeIdB"))
          val hostId = p.nodes.head.id
          if nodeIdA == hostId then b.delay
          else if nodeIdB == hostId then a.delay
          else a.delay + b.delay

  /** A computed segment from a specific viewer's perspective (§14.3). */
  case class ViewerSegmentV11(
    segType:        String,
    q:              Int,
    startMs:        Long,
    endMs:          Long,
    durMin:         Int,
    speaker:        Option[String] = None,
    label:          Option[String] = None,
    perspective:    String = "neutral", // transmit | receive | neutral
    arrivalOffsetS: Long = 0,
  )

  private def parseIsoMs(iso: String): Long = Instant.parse(iso).toEpochMilli

  /** Base timed segments (epoch ms) for a v1.1 plan. */
  def computeSegmentsV11(p: PlanV11): List[ViewerSegmentV11] =
    val qMs = p.quantum.toLong * 60000L
    var t = parseIsoMs(p.start)
    p.segments.map { s =>
      val durMs = s.q * qMs
      val seg = ViewerSegmentV11(
        segType = s.segType, q = s.q, startMs = t, endMs = t + durMs,
        durMin = s.q * p.quantum, speaker = s.speaker, label = s.label,
        perspective = "neutral", arrivalOffsetS = 0)
      t += durMs
      seg
    }

  /**
   * Timed segments from viewer V's perspective (§14.3): a segment attributed
   * to speaker S starts for V at segStart + pairDelay(S, V).
   */
  def computeSegmentsFor(p: PlanV11, viewerNodeId: String): List[ViewerSegmentV11] =
    if !p.nodes.exists(_.id == viewerNodeId) then
      throw IllegalArgumentException(s"computeSegmentsFor: unknown viewer $viewerNodeId")
    computeSegmentsV11(p).zip(p.segments).map { case (seg, tpl) =>
      tpl.speaker match
        case None => seg.copy(perspective = "neutral", arrivalOffsetS = 0)
        case Some(_) if tpl.segType != "TX" && tpl.segType != "SPEAK" =>
          seg.copy(perspective = "neutral", arrivalOffsetS = 0)
        case Some(sp) if sp == viewerNodeId =>
          seg.copy(perspective = "transmit", arrivalOffsetS = 0)
        case Some(sp) =>
          val shiftS = pairDelay(p, sp, viewerNodeId)
          seg.copy(
            startMs = seg.startMs + shiftS * 1000,
            endMs = seg.endMs + shiftS * 1000,
            perspective = "receive",
            arrivalOffsetS = shiftS)
    }

  // ---- Ed25519 helpers ----

  private def verifyBytes(data: Array[Byte], sigB64: String, nik: Security.Nik): Boolean =
    Try {
      val pubKeySpec = new X509EncodedKeySpec(SPKI_HDR ++ nik.pubRaw)
      val kf = java.security.KeyFactory.getInstance("Ed25519")
      val pubKey = kf.generatePublic(pubKeySpec)
      val verifier = Signature.getInstance("Ed25519")
      verifier.initVerify(pubKey)
      verifier.update(data)
      verifier.verify(Security.b64uDecode(sigB64))
    }.getOrElse(false)

  private def lookupKid(kid: String, keyCache: Map[String, Security.Nik]): Option[Security.Nik] =
    keyCache.get(kid).orElse(keyCache.values.find(_.nodeId.startsWith(kid)))

  // ---- 3. amendment chains (amend.ts) ----

  /** Signed plan carrying the v1.1 typed plan + the Epic-29 JSON envelope. */
  case class SignedPlanV11(plan: PlanV11, coseSign1: Security.CoseSign1)

  /** Per-link verification via the existing Security.verifyPlan envelope. */
  def verifyPlanEnvelope(sp: SignedPlanV11, keyCache: Map[String, Security.Nik]): (Boolean, String) =
    Security.verifyPlan(Security.SignedPlan(sp.plan.toMap, sp.coseSign1), keyCache)

  /**
   * Verify an amendment chain: chain(0) is the root plan, each later element a
   * successive amendment. Checks per link: signature, planVersion +1 steps,
   * prevPlanHash equality with the recomputed predecessor hash; the root must
   * carry no prevPlanHash (LTX-SECURITY.md §7.6).
   */
  def verifyAmendmentChain(chain: List[SignedPlanV11], keyCache: Map[String, Security.Nik]): (Boolean, String) =
    if chain.isEmpty then (false, "empty_chain")
    else
      val sigFailure = chain.zipWithIndex
        .map((link, i) => (i, verifyPlanEnvelope(link, keyCache)))
        .find(!_._2._1)
      sigFailure match
        case Some((i, (_, reason))) => (false, s"link_${i}_$reason")
        case None =>
          if chain.head.plan.prevPlanHash.isDefined then (false, "root_has_prev_hash")
          else
            var prevPlan = chain.head.plan
            var prevVersion = chain.head.plan.planVersion.getOrElse(1)
            var result: Option[(Boolean, String)] = None
            for (link, i) <- chain.zipWithIndex.drop(1) if result.isEmpty do
              val p = link.plan
              if p.v != 3 then result = Some((false, s"link_${i}_not_v3"))
              else if p.planVersion.getOrElse(0) != prevVersion + 1 then
                result = Some((false, s"link_${i}_version_gap"))
              else if !p.prevPlanHash.contains(planHash(prevPlan)) then
                result = Some((false, s"link_${i}_prev_hash_mismatch"))
              else
                prevPlan = p
                prevVersion = p.planVersion.getOrElse(0)
            result.getOrElse((true, "ok"))

  // ---- 4. register entries + reducers (registers.ts) ----

  case class RegisterEntryV11(
    entryId:   String,
    sessionId: String,
    nodeId:    String,
    seq:       Int,
    entryType: String,
    content:   Map[String, Any],
    timestamp: String,
    sig:       String,
  ):
    def toMap(includeSig: Boolean): Map[String, Any] =
      val base: Map[String, Any] = Map(
        "entryId" -> entryId, "sessionId" -> sessionId, "nodeId" -> nodeId,
        "seq" -> seq, "type" -> entryType, "content" -> content,
        "timestamp" -> timestamp)
      if includeSig then base + ("sig" -> sig) else base

  /** Verify a register entry signature (Ed25519 over canonical JSON sans sig). */
  def verifyRegisterEntry(e: RegisterEntryV11, keyCache: Map[String, Security.Nik]): (Boolean, String) =
    if e.sig.isEmpty then (false, "missing_sig")
    else keyCache.get(e.nodeId) match
      case None => (false, "key_not_in_cache")
      case Some(nik) =>
        val canon = Security.canonicalJson(e.toMap(false))
        if verifyBytes(canon.getBytes("UTF-8"), e.sig, nik) then (true, "ok")
        else (false, "signature_invalid")

  /** Total order (timestamp, nodeId, seq) — §8.2. */
  def compareEntries(a: RegisterEntryV11, b: RegisterEntryV11): Int =
    if a.timestamp != b.timestamp then a.timestamp.compareTo(b.timestamp)
    else if a.nodeId != b.nodeId then a.nodeId.compareTo(b.nodeId)
    else a.seq.compareTo(b.seq)

  /** De-duplicate by (nodeId, seq) and sort into the §8.2 total order. */
  def orderEntries(entries: List[RegisterEntryV11]): List[RegisterEntryV11] =
    val seen = scala.collection.mutable.LinkedHashMap[String, RegisterEntryV11]()
    entries.foreach(e => seen.getOrElseUpdate(s"${e.nodeId} ${e.seq}", e))
    seen.values.toList.sortWith((a, b) => compareEntries(a, b) < 0)

  case class QuestionStateV11(
    qid:            String,
    text:           String,
    submitter:      String,
    urgency:        Option[String] = None,
    intendedWindow: Option[String] = None,
    status:         String = "OPEN", // OPEN | ANSWERED | WITHDRAWN
    response:       Option[String] = None,
    responder:      Option[String] = None,
    version:        Int = 1,
  )

  case class ActionStateV11(
    aid:          String,
    description:  String,
    owner:        Option[String] = None,
    dueTimeUTC:   Option[String] = None,
    originWindow: Option[String] = None,
    status:       String = "PROPOSED", // PROPOSED | ACCEPTED | REJECTED | DONE
    version:      Int = 1,
  )

  private case class Versioned(version: Int, editor: String, entryId: String)

  /** §8.2 conflict rule: higher version wins; tie -> lowest editor nodeId. */
  private def wins(in: Versioned, cur: Versioned): Boolean =
    if in.version != cur.version then in.version > cur.version
    else in.editor < cur.editor

  private def optStr(content: Map[String, Any], key: String): Option[String] =
    content.get(key).map(_.toString)

  private def asInt(v: Option[Any], fallback: Int): Int = v match
    case Some(i: Int)    => i
    case Some(l: Long)   => l.toInt
    case Some(s: String) => s.toIntOption.getOrElse(fallback)
    case _               => fallback

  /** Reduce question register state from log entries (§9.4). */
  def reduceQuestions(entries: List[RegisterEntryV11]): (Map[String, QuestionStateV11], List[String]) =
    var byId = Map.empty[String, QuestionStateV11]
    var winners = Map.empty[String, Versioned]
    var superseded = List.empty[String]
    for e <- orderEntries(entries) do
      if e.entryType == "question" then
        val qid = e.entryId
        if byId.contains(qid) then superseded = superseded :+ e.entryId
        else
          winners = winners + (qid -> Versioned(1, e.nodeId, e.entryId))
          byId = byId + (qid -> QuestionStateV11(
            qid = qid,
            text = optStr(e.content, "text").getOrElse(""),
            submitter = e.nodeId,
            urgency = optStr(e.content, "urgency"),
            intendedWindow = optStr(e.content, "intendedWindow"),
            status = "OPEN", version = 1))
      else if e.entryType == "question_response" then
        val qid = optStr(e.content, "qid").getOrElse("")
        byId.get(qid) match
          case None => superseded = superseded :+ e.entryId
          case Some(q) =>
            val version = asInt(e.content.get("version"), q.version + 1)
            val incoming = Versioned(version, e.nodeId, e.entryId)
            val skip = winners.get(qid) match
              case Some(cur) if !wins(incoming, cur) =>
                superseded = superseded :+ e.entryId; true
              case Some(cur) =>
                if cur.entryId != q.qid then superseded = superseded :+ cur.entryId
                false
              case None => false
            if !skip then
              winners = winners + (qid -> incoming)
              val status =
                if optStr(e.content, "status").contains("WITHDRAWN") then "WITHDRAWN"
                else "ANSWERED"
              byId = byId + (qid -> q.copy(
                status = status,
                response = optStr(e.content, "response").orElse(q.response),
                responder = Some(e.nodeId),
                version = version))
    (byId, superseded)

  private val ACTION_STATUSES = Set("PROPOSED", "ACCEPTED", "REJECTED", "DONE")

  /** Reduce action register state from log entries (§10.2). */
  def reduceActions(entries: List[RegisterEntryV11]): (Map[String, ActionStateV11], List[String]) =
    var byId = Map.empty[String, ActionStateV11]
    var winners = Map.empty[String, Versioned]
    var superseded = List.empty[String]
    for e <- orderEntries(entries) do
      if e.entryType == "action" then
        val aid = e.entryId
        if byId.contains(aid) then superseded = superseded :+ e.entryId
        else
          winners = winners + (aid -> Versioned(1, e.nodeId, e.entryId))
          byId = byId + (aid -> ActionStateV11(
            aid = aid,
            description = optStr(e.content, "description").getOrElse(""),
            owner = optStr(e.content, "owner"),
            dueTimeUTC = optStr(e.content, "dueTimeUTC"),
            originWindow = optStr(e.content, "originWindow"),
            status = "PROPOSED", version = 1))
      else if e.entryType == "action_update" then
        val aid = optStr(e.content, "aid").getOrElse("")
        byId.get(aid) match
          case None => superseded = superseded :+ e.entryId
          case Some(a) =>
            val version = asInt(e.content.get("version"), a.version + 1)
            val incoming = Versioned(version, e.nodeId, e.entryId)
            val skip = winners.get(aid) match
              case Some(cur) if !wins(incoming, cur) =>
                superseded = superseded :+ e.entryId; true
              case Some(cur) =>
                if cur.entryId != a.aid then superseded = superseded :+ cur.entryId
                false
              case None => false
            if !skip then
              winners = winners + (aid -> incoming)
              val status = optStr(e.content, "status").filter(ACTION_STATUSES.contains).getOrElse(a.status)
              byId = byId + (aid -> a.copy(
                status = status,
                description = optStr(e.content, "description").getOrElse(a.description),
                owner = optStr(e.content, "owner").orElse(a.owner),
                dueTimeUTC = optStr(e.content, "dueTimeUTC").orElse(a.dueTimeUTC),
                version = version))
    (byId, superseded)

  // ---- Merkle root over ordered entries (merkle.ts / merge.ts) ----

  private def leafHash(entryBytes: Array[Byte]): Array[Byte] =
    Security.sha256(Array[Byte](0x00) ++ entryBytes)

  private def nodeHash(left: Array[Byte], right: Array[Byte]): Array[Byte] =
    Security.sha256(Array[Byte](0x01) ++ left ++ right)

  private def rootOf(leaves: Vector[Array[Byte]]): Array[Byte] =
    if leaves.isEmpty then Array.fill[Byte](32)(0)
    else if leaves.length == 1 then leaves.head
    else
      val mid = 1 << math.floor(math.log(leaves.length - 1) / math.log(2)).toInt
      nodeHash(rootOf(leaves.take(mid)), rootOf(leaves.drop(mid)))

  /**
   * RFC 9162-style Merkle root (hex) over an ordered entry list.
   * Leaf: SHA-256(0x00 || canonicalJSON(entry)); node: SHA-256(0x01 || L || R).
   */
  def entriesRoot(entries: List[RegisterEntryV11]): String =
    val leaves = entries.map(e =>
      leafHash(Security.canonicalJson(e.toMap(true)).getBytes("UTF-8"))).toVector
    hex(rootOf(leaves))

  // ---- 5. CBOR decode (RFC 8949 deterministic subset, cbor.ts) ----

  enum CborValue:
    case CInt(value: Long)
    case CBytes(value: Vector[Byte])
    case CText(value: String)
    case CArray(items: List[CborValue])
    case CMap(entries: List[(CborValue, CborValue)])
    case CTag(tag: Long, value: CborValue)
    case CBool(value: Boolean)
    case CNull

  import CborValue.*

  class CborException(message: String) extends Exception(message)

  private class DecodeState(val buf: Array[Byte]):
    var pos: Int = 0

  private def readHead(s: DecodeState): (Int, Long) =
    if s.pos >= s.buf.length then throw CborException("cbor: truncated")
    val initial = s.buf(s.pos) & 0xff
    s.pos += 1
    val major = initial >> 5
    val info = initial & 0x1f
    if info < 24 then (major, info.toLong)
    else if info == 24 then
      if s.pos >= s.buf.length then throw CborException("cbor: truncated")
      val v = (s.buf(s.pos) & 0xff).toLong; s.pos += 1; (major, v)
    else if info == 25 || info == 26 || info == 27 then
      val n = if info == 25 then 2 else if info == 26 then 4 else 8
      if s.pos + n > s.buf.length then throw CborException("cbor: truncated")
      var v = 0L
      for i <- 0 until n do v = (v << 8) | (s.buf(s.pos + i) & 0xff).toLong
      s.pos += n
      if info == 27 && v < 0 then throw CborException("cbor: integer too large")
      (major, v)
    else throw CborException("cbor: indefinite lengths not supported")

  private def decodeItem(s: DecodeState): CborValue =
    if s.pos >= s.buf.length then throw CborException("cbor: truncated")
    (s.buf(s.pos) & 0xff) match
      case 0xf6 => s.pos += 1; CNull
      case 0xf5 => s.pos += 1; CBool(true)
      case 0xf4 => s.pos += 1; CBool(false)
      case _ =>
        val (major, arg) = readHead(s)
        major match
          case 0 => CInt(arg)
          case 1 => CInt(-arg - 1)
          case 2 =>
            val n = arg.toInt
            if s.pos + n > s.buf.length then throw CborException("cbor: truncated bstr")
            val bytes = s.buf.slice(s.pos, s.pos + n).toVector
            s.pos += n
            CBytes(bytes)
          case 3 =>
            val n = arg.toInt
            if s.pos + n > s.buf.length then throw CborException("cbor: truncated tstr")
            val str = new String(s.buf, s.pos, n, "UTF-8")
            s.pos += n
            CText(str)
          case 4 =>
            CArray((0L until arg).map(_ => decodeItem(s)).toList)
          case 5 =>
            CMap((0L until arg).map { _ =>
              val k = decodeItem(s)
              val v = decodeItem(s)
              (k, v)
            }.toList)
          case 6 => CTag(arg, decodeItem(s))
          case _ => throw CborException(s"cbor: unsupported major type $major / simple value")

  /**
   * Decode deterministic CBOR bytes (ints, bstr, tstr, array, map, tag,
   * bool/null). Rejects floats, indefinite lengths, and trailing bytes.
   */
  def decodeCbor(bytes: Array[Byte]): CborValue =
    val s = new DecodeState(bytes)
    val value = decodeItem(s)
    if s.pos != bytes.length then throw CborException("cbor: trailing bytes")
    value

  // ---- 5. COSE_Sign1 verification (RFC 9052, cose.ts) ----

  private def encodeCborHead(major: Int, arg: Int): Array[Byte] =
    if arg < 24 then Array(((major << 5) | arg).toByte)
    else if arg < 0x100 then Array(((major << 5) | 24).toByte, arg.toByte)
    else if arg < 0x10000 then
      Array(((major << 5) | 25).toByte, (arg >> 8).toByte, arg.toByte)
    else Array(((major << 5) | 26).toByte,
      (arg >> 24).toByte, (arg >> 16).toByte, (arg >> 8).toByte, arg.toByte)

  /** Sig_structure = CBOR ["Signature1", protected, h'', payload]. */
  private def sigStructureBytes(protectedBytes: Array[Byte], payload: Array[Byte]): Array[Byte] =
    encodeCborHead(4, 4) ++
      encodeCborHead(3, 10) ++ "Signature1".getBytes("UTF-8") ++
      encodeCborHead(2, protectedBytes.length) ++ protectedBytes ++
      encodeCborHead(2, 0) ++
      encodeCborHead(2, payload.length) ++ payload

  /**
   * Verify a CBOR COSE_Sign1 plan envelope (tag 18, RFC 9052) against the key
   * cache. Rejects non-Ed25519 algorithms (protected {1: -19} required) and
   * payloads that do not match the plan's canonical JSON.
   */
  def verifyPlanCose(plan: Option[PlanV11], coseSign1CborB64: String,
                     keyCache: Map[String, Security.Nik]): (Boolean, String) =
    if coseSign1CborB64.isEmpty then (false, "missing_cose_sign1")
    else
      Try(decodeCbor(Security.b64uDecode(coseSign1CborB64))).toOption match
        case None => (false, "cbor_decode_failed")
        case Some(CTag(tag, CArray(List(CBytes(protectedV), unprotected, CBytes(payloadV), CBytes(signatureV)))))
            if tag == COSE_SIGN1_TAG =>
          val protectedBytes = protectedV.toArray
          val payload = payloadV.toArray
          val signature = signatureV.toArray
          Try(decodeCbor(protectedBytes)).toOption match
            case Some(CMap(m)) if m.contains((CInt(1L), CInt(COSE_ALG_ED25519))) =>
              val kid = unprotected match
                case CMap(um) =>
                  um.collectFirst {
                    case (CInt(4L), CBytes(kb)) => Security.b64uEncode(kb.toArray)
                    case (CInt(4L), CText(ks))  => ks
                  }
                case _ => None
              kid match
                case None => (false, "missing_kid")
                case Some(k) =>
                  lookupKid(k, keyCache) match
                    case None => (false, "key_not_in_cache")
                    case Some(nik) =>
                      if !verifyBytes(sigStructureBytes(protectedBytes, payload),
                                      Security.b64uEncode(signature), nik) then
                        (false, "signature_invalid")
                      else plan match
                        case Some(p) if new String(payload, "UTF-8") != Security.canonicalJson(p.toMap) =>
                          (false, "payload_mismatch")
                        case _ => (true, "ok")
            case Some(CMap(_)) => (false, "unsupported_alg")
            case _ => (false, "protected_decode_failed")
        case Some(CTag(_, _)) => (false, "malformed_cose_sign1")
        case Some(_) => (false, "not_cose_sign1")

  // ---- 2. session state machine (session.ts) ----

  case class SessionEventV11(
    eventType:       String,
    nowMs:           Long,
    nodeId:          Option[String] = None,
    planId:          Option[String] = None,
    measuredDelayS:  Option[Long] = None,
    decision:        Option[String] = None,
    verified:        Option[Boolean] = None,
    planVersion:     Option[Int] = None,
    affectedNodeIds: Option[List[String]] = None,
  )

  case class PendingAmendmentV11(
    planId:          String,
    planVersion:     Int,
    affectedNodeIds: List[String],
    confirmed:       List[String],
    proposedAtMs:    Long,
    timeoutMs:       Long,
  )

  case class SessionCtxV11(
    state:             String = "DRAFT",
    plan:              PlanV11,
    planId:            String,
    sessionRootPlanId: String,
    planVersion:       Int = 1,
    lock:              Option[String] = None, // FULL | QUORUM
    lockStartedAtMs:   Option[Long] = None,
    lockTimeoutMs:     Long = 0,
    confirmations:     Map[String, String] = Map.empty,
    mismatched:        List[String] = Nil,
    quorumThreshold:   Int = 1,
    subset:            Option[List[String]] = None,
    degradedReasons:   List[String] = Nil,
    resumeState:       Option[String] = None,
    pendingAmendment:  Option[PendingAmendmentV11] = None,
  )

  private def participants(p: PlanV11): List[NodeV11] =
    p.nodes.filter(_.role == "PARTICIPANT")

  /** 2 x one-way delay to the furthest node, in ms (§5.1). */
  def lockTimeoutMs(p: PlanV11): Long =
    LOCK_TIMEOUT_FACTOR * p.nodes.map(_.delay).maxOption.getOrElse(0L) * 1000L

  private def quorumCount(p: PlanV11, quorum: "all" | "majority" | Int): Int =
    val total = participants(p).length
    quorum match
      case "majority" => total / 2 + 1
      case n: Int     => math.min(math.max(n, 1), total)
      case _          => total // "all" (default)

  /** Create a session context in DRAFT state (§5). */
  def createSession(plan: PlanV11, planId: String,
                    quorum: "all" | "majority" | Int = "all"): SessionCtxV11 =
    SessionCtxV11(
      state = "DRAFT",
      plan = plan,
      planId = planId,
      sessionRootPlanId = planId,
      planVersion = plan.planVersion.getOrElse(1),
      lockTimeoutMs = lockTimeoutMs(plan),
      quorumThreshold = quorumCount(plan, quorum))

  private def fullLockReached(ctx: SessionCtxV11): Boolean =
    participants(ctx.plan).forall(n => ctx.confirmations.get(n.id).contains(ctx.planId))

  private def quorumReached(ctx: SessionCtxV11): Boolean =
    participants(ctx.plan).count(n =>
      ctx.confirmations.get(n.id).contains(ctx.planId)) >= ctx.quorumThreshold

  /** Ascending-delay fallback ordering over confirmed participants (§5.3). */
  private def confirmedSubset(ctx: SessionCtxV11): List[String] =
    val host = ctx.plan.nodes.head
    val confirmed = participants(ctx.plan)
      .filter(n => ctx.confirmations.get(n.id).contains(ctx.planId))
      .sortBy(_.delay)
      .map(_.id)
    host.id :: confirmed

  /** Declared one-way delay: v3 pair matrix HOST row, else node.delay. */
  private def declaredDelayS(p: PlanV11, nodeId: String): Option[Long] =
    p.nodes.find(_.id == nodeId).map { node =>
      p.delays.flatMap { delays =>
        val hostId = p.nodes.head.id
        val key = List(hostId, nodeId).sorted.mkString("|")
        delays.get(key)
      }.getOrElse(node.delay)
    }

  private def degrade(ctx: SessionCtxV11, reason: String): SessionCtxV11 =
    val next = ctx.copy(degradedReasons = ctx.degradedReasons :+ reason)
    if ctx.state == "DEGRADED" then next else next.copy(state = "DEGRADED")

  /**
   * Advance the session state machine. Pure: same (ctx, event) always yields
   * the same result. Side-effects of the reference implementation are
   * simplified away -- the state/lock sequence matches the reference exactly.
   */
  def transition(ctx: SessionCtxV11, ev: SessionEventV11): SessionCtxV11 =
    ev.eventType match
      case "START_LOCK" =>
        if ctx.state != "DRAFT" then ctx
        else
          val hostId = ctx.plan.nodes.head.id
          ctx.copy(
            state = "LOCKING",
            lockStartedAtMs = Some(ev.nowMs),
            confirmations = ctx.confirmations + (hostId -> ctx.planId))

      case "PLAN_CONFIRM" =>
        if ctx.state != "LOCKING" && ctx.state != "DEGRADED" then ctx
        else
          (ev.nodeId, ev.planId) match
            case (Some(nodeId), Some(planId)) =>
              var next = ctx.copy(confirmations = ctx.confirmations + (nodeId -> planId))
              if planId != ctx.planId then
                next.copy(mismatched = next.mismatched.filterNot(_ == nodeId) :+ nodeId)
              else
                next = next.copy(mismatched = next.mismatched.filterNot(_ == nodeId))
                if fullLockReached(next) then
                  // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                  next.copy(state = "LOCKED", lock = Some("FULL"), subset = None)
                else next
            case _ => ctx

      case "TICK" =>
        (ctx.state, ctx.lockStartedAtMs) match
          case ("LOCKING", Some(startedAt)) if ev.nowMs - startedAt >= ctx.lockTimeoutMs =>
            // Lock timeout expired (§5.1).
            if quorumReached(ctx) then
              val subset = confirmedSubset(ctx)
              degrade(ctx.copy(lock = Some("QUORUM"), subset = Some(subset)),
                s"quorum lock with subset [${subset.mkString(",")}]")
            else degrade(ctx, "plan-lock timeout without quorum")
          case _ => ctx

      case "SESSION_START" =>
        // DEGRADED start requires HOST_DECISION continue (§5.2).
        if ctx.state == "LOCKED" then ctx.copy(state = "ACTIVE") else ctx

      case "DELAY_MEASURED" =>
        if ctx.state != "ACTIVE" && ctx.state != "LOCKED" && ctx.state != "DEGRADED" then ctx
        else
          (ev.nodeId, ev.measuredDelayS) match
            case (Some(nodeId), Some(measured)) =>
              declaredDelayS(ctx.plan, nodeId) match
                case Some(declared) if math.abs(measured - declared) > DELAY_VIOLATION_DEGRADE_S =>
                  degrade(ctx, s"delay violation $nodeId: measured ${measured}s vs declared ${declared}s")
                case _ => ctx
            case _ => ctx

      case "EOK_OVERRIDE" =>
        if ctx.state == "COMPLETE" || ctx.state == "ABORTED" then ctx
        else if !ev.verified.contains(true) then ctx
        else if ctx.state == "EMERGENCY_HOLD" then ctx
        else ctx.copy(state = "EMERGENCY_HOLD", resumeState = Some(ctx.state))

      case "AMENDMENT_PROPOSED" =>
        if ctx.state != "ACTIVE" && ctx.state != "LOCKED" && ctx.state != "DEGRADED" then ctx
        else
          (ev.planId, ev.planVersion, ev.affectedNodeIds) match
            case (Some(planId), Some(planVersion), Some(affected))
                if planVersion == ctx.planVersion + 1 =>
              // Delta re-lock (§6.4): timeout scoped to the furthest affected node.
              val maxDelayS = ctx.plan.nodes
                .filter(n => affected.contains(n.id))
                .map(_.delay).maxOption.getOrElse(0L)
              ctx.copy(pendingAmendment = Some(PendingAmendmentV11(
                planId = planId, planVersion = planVersion,
                affectedNodeIds = affected, confirmed = Nil,
                proposedAtMs = ev.nowMs,
                timeoutMs = LOCK_TIMEOUT_FACTOR * maxDelayS * 1000L)))
            case _ => ctx

      case "AMENDMENT_CONFIRMED" =>
        (ctx.pendingAmendment, ev.nodeId, ev.planId) match
          case (Some(pa), Some(nodeId), Some(planId))
              if planId == pa.planId && pa.affectedNodeIds.contains(nodeId) =>
            val confirmed = pa.confirmed.filterNot(_ == nodeId) :+ nodeId
            if confirmed.length < pa.affectedNodeIds.length then
              ctx.copy(pendingAmendment = Some(pa.copy(confirmed = confirmed)))
            else
              // All affected nodes confirmed -- the amendment applies.
              ctx.copy(planId = pa.planId, planVersion = pa.planVersion,
                pendingAmendment = None)
          case _ => ctx

      case "HOST_DECISION" =>
        ev.decision match
          case Some("abort") =>
            if ctx.state == "COMPLETE" || ctx.state == "ABORTED" then ctx
            else ctx.copy(state = "ABORTED")
          case Some("resume") if ctx.state == "EMERGENCY_HOLD" =>
            ctx.copy(state = ctx.resumeState.getOrElse("ACTIVE"), resumeState = None)
          case Some("continue") if ctx.state == "DEGRADED" =>
            ctx.copy(state = "ACTIVE") // §5.2: HOST continues with subset.
          case _ => ctx

      case "SESSION_END" =>
        if ctx.state == "ACTIVE" || ctx.state == "DEGRADED" then ctx.copy(state = "COMPLETE")
        else ctx

      case _ => ctx
