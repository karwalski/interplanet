/**
 * Security.scala -- Epic 29 security cascade for InterplanetLtx (Scala 3)
 * Stories 29.1, 29.4, 29.5
 * Uses java.security (Ed25519 / SHA-256)
 */

import java.util.Base64
import java.security.{KeyPairGenerator, MessageDigest, SecureRandom, Signature}
import java.time.{Instant, ZoneOffset}
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import scala.collection.mutable
import scala.util.Try

object Security:

  // ---- base64url helpers ----

  private val B64U = Base64.getUrlEncoder.withoutPadding
  private val B64D = Base64.getUrlDecoder

  def b64uEncode(data: Array[Byte]): String = B64U.encodeToString(data)
  def b64uDecode(s: String): Array[Byte]    = B64D.decode(s)

  // ---- canonical JSON ----

  def canonicalJson(v: Any): String = v match
    case null            => "null"
    case b: Boolean      => b.toString
    case n: Int          => n.toString
    case n: Long         => n.toString
    case n: Double       => if n == n.toLong.toDouble then n.toLong.toString else n.toString
    case s: String       => jsonStr(s)
    case arr: Seq[?]     => "[" + arr.map(canonicalJson).mkString(",") + "]"
    case arr: Array[?]   => "[" + arr.map(canonicalJson).mkString(",") + "]"
    case m: Map[?, ?]    =>
      val sorted = m.toSeq.sortBy(_._1.toString)
      "{" + sorted.map { case (k, v2) => jsonStr(k.toString) + ":" + canonicalJson(v2) }.mkString(",") + "}"
    case _               => jsonStr(v.toString)

  private def jsonStr(s: String): String =
    val sb = new StringBuilder("\"")
    s.foreach {
      case '"'  => sb ++= "\\\""
      case '\\'  => sb ++= "\\\\"
      case '\n' => sb ++= "\\n"
      case '\r' => sb ++= "\\r"
      case '\t' => sb ++= "\\t"
      case c    => sb += c
    }
    sb += '"'
    sb.toString

  // ---- SHA-256 helper ----

  def sha256(data: Array[Byte]): Array[Byte] =
    MessageDigest.getInstance("SHA-256").digest(data)

  // ---- SPKI / PKCS8 DER headers for Ed25519 ----

  private val SPKI_HDR  = Array[Byte](0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00)
  private val PKCS8_HDR = Array[Byte](0x30.toByte,0x2e.toByte,0x02.toByte,0x01.toByte,0x00.toByte,
    0x30.toByte,0x05.toByte,0x06.toByte,0x03.toByte,0x2b.toByte,0x65.toByte,0x70.toByte,
    0x04.toByte,0x22.toByte,0x04.toByte,0x20.toByte)

  // ---- NIK type ----

  case class Nik(
    keyType:       String,
    nodeId:        String,
    kid:           String,
    issuedAt:      String,
    expiresAt:     String,
    nodeLabel:     String,
    publicKeyB64:  String,
    privateKeyB64: String,
    pubRaw:        Array[Byte],
    privRaw:       Array[Byte],
  )

  // ---- ISO-8601 UTC ----

  private val ISO_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

  private def isoNow(offsetDays: Int = 0): String =
    ISO_FMT.format(Instant.now.plusSeconds(offsetDays.toLong * 86400))

  // ---- generate_nik ----

  def generateNik(validDays: Int = 365, nodeLabel: String = ""): Nik =
    val kpg = KeyPairGenerator.getInstance("Ed25519")
    kpg.initialize(255, new SecureRandom())
    val kp = kpg.generateKeyPair()
    // Extract raw 32-byte public key from SubjectPublicKeyInfo DER encoding
    val pubEncoded = kp.getPublic.getEncoded
    val pubRaw     = pubEncoded.takeRight(32)
    val privEncoded = kp.getPrivate.getEncoded
    val privRaw     = privEncoded.takeRight(32)
    val h        = sha256(pubRaw)
    val nodeId   = b64uEncode(h.take(16))
    val kid      = nodeId
    val pubDer   = SPKI_HDR ++ pubRaw
    val privDer  = PKCS8_HDR ++ privRaw
    Nik(
      keyType       = "ltx-nik-v1",
      nodeId        = nodeId,
      kid           = kid,
      issuedAt      = isoNow(),
      expiresAt     = isoNow(validDays),
      nodeLabel     = nodeLabel,
      publicKeyB64  = b64uEncode(pubDer),
      privateKeyB64 = b64uEncode(privDer),
      pubRaw        = pubRaw,
      privRaw       = privRaw,
    )

  // ---- is_nik_expired ----

  def isNikExpired(nik: Nik): Boolean =
    nik.expiresAt <= isoNow()

  // ---- COSE_Sign1 types ----

  case class CoseSign1(
    protectedHdr: String,
    kid:          String,
    payload:      String,
    signature:    String,
  )

  case class SignedPlan(
    plan:      Map[String, Any],
    coseSign1: CoseSign1,
  )

  // ---- sign_plan ----

  def signPlan(plan: Map[String, Any], nik: Nik): SignedPlan =
    val protectedJson = canonicalJson(Map("alg" -> -19))
    val protectedB64  = b64uEncode(protectedJson.getBytes("UTF-8"))
    val payloadJson   = canonicalJson(plan)
    val payloadB64    = b64uEncode(payloadJson.getBytes("UTF-8"))
    val sigStructJson = canonicalJson(Seq("Signature1", protectedB64, "", payloadB64))
    val sigStructBytes = sigStructJson.getBytes("UTF-8")
    // Sign with Ed25519 using raw private key
    val privKeySpec = new java.security.spec.PKCS8EncodedKeySpec(
      PKCS8_HDR ++ nik.privRaw)
    val kf        = java.security.KeyFactory.getInstance("Ed25519")
    val privKey   = kf.generatePrivate(privKeySpec)
    val signer    = Signature.getInstance("Ed25519")
    signer.initSign(privKey)
    signer.update(sigStructBytes)
    val sigBytes = signer.sign()
    SignedPlan(
      plan      = plan,
      coseSign1 = CoseSign1(
        protectedHdr = protectedB64,
        kid          = nik.kid,
        payload      = payloadB64,
        signature    = b64uEncode(sigBytes),
      ),
    )

  // ---- verify_plan ----

  def verifyPlan(sp: SignedPlan, keyCache: Map[String, Nik]): (Boolean, String) =
    val cs  = sp.coseSign1
    val kid = cs.kid
    keyCache.get(kid) match
      case None => (false, "key_not_in_cache")
      case Some(nik) =>
        if isNikExpired(nik) then (false, "key_expired")
        else
          val expectedPayload = b64uEncode(canonicalJson(sp.plan).getBytes("UTF-8"))
          if cs.payload != expectedPayload then (false, "payload_mismatch")
          else
            val sigStructJson  = canonicalJson(Seq("Signature1", cs.protectedHdr, "", cs.payload))
            val sigStructBytes = sigStructJson.getBytes("UTF-8")
            val pubKeySpec = new java.security.spec.X509EncodedKeySpec(
              SPKI_HDR ++ nik.pubRaw)
            val kf      = java.security.KeyFactory.getInstance("Ed25519")
            val pubKey  = kf.generatePublic(pubKeySpec)
            val verifier = Signature.getInstance("Ed25519")
            verifier.initVerify(pubKey)
            verifier.update(sigStructBytes)
            val valid = Try(verifier.verify(b64uDecode(cs.signature))).getOrElse(false)
            if valid then (true, "ok") else (false, "signature_mismatch")

  // ---- SequenceTracker ----

  class SequenceTracker(val planId: String):
    private val seqs = mutable.HashMap[String, Long]()

    def addSeq(peerId: String, seq: Long): (Boolean, String) =
      seqs.get(peerId) match
        case None =>
          seqs(peerId) = seq
          (true, "ok")
        case Some(last) =>
          if seq <= last then (false, "replay")
          else if seq > last + 1 then
            seqs(peerId) = seq
            (true, "gap")
          else
            seqs(peerId) = seq
            (true, "ok")

    def checkSeq(peerId: String, seq: Long): (Boolean, String) =
      seqs.get(peerId) match
        case None => (true, "ok")
        case Some(last) =>
          if seq <= last then (false, "replay")
          else if seq > last + 1 then (true, "gap")
          else (true, "ok")
