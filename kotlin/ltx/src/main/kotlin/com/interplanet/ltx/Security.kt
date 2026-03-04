package com.interplanet.ltx

// Security.kt -- Epic 29 (Stories 29.1, 29.4, 29.5)
// Kotlin/JVM port of ltx-sdk.js security functions. Requires JVM 15+.

import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Base64

// ---- Models ----

data class Nik(
    val nodeId: String,
    val publicKeyB64: String,
    val validFrom: String,
    val validUntil: String,
    val keyType: String = "ltx-nik-v1",
    val nodeLabel: String = ""
)

data class NikResult(val nik: Nik, val privateKeyB64: String)

data class SignedPlan(
    val plan: Map<String, Any?>,
    val payloadB64: String,
    val sig: String,
    val signerNodeId: String
)

data class VerifyResult(val valid: Boolean, val reason: String? = null)

data class CheckSeqResult(
    val accepted: Boolean,
    val reason: String? = null,
    val gap: Boolean = false,
    val gapSize: Int = 0
)

// ---- LtxSecurity object ----

object LtxSecurity {

    private val B64 = Base64.getUrlEncoder().withoutPadding()
    private val B64D = Base64.getUrlDecoder()

    fun toBase64Url(bytes: ByteArray): String = B64.encodeToString(bytes)

    fun fromBase64Url(s: String): ByteArray {
        val padded = when (s.length % 4) {
            2 -> s + "=="
            3 -> s + "="
            else -> s
        }
        return B64D.decode(padded)
    }

    // ---- CanonicalJSON ----

    fun canonicalJson(obj: Map<String, Any?>): String {
        val sorted = obj.keys.sorted()
        val parts = sorted.map { k -> jsonStr(k) + ":" + serializeValue(obj[k]) }
        return "{" + parts.joinToString(",") + "}"
    }

    private fun serializeValue(v: Any?): String = when (v) {
        null -> "null"
        is Boolean -> if (v) "true" else "false"
        is String -> jsonStr(v)
        is Int -> v.toString()
        is Long -> v.toString()
        is Double -> v.toString()
        is Float -> v.toString()
        is Map<*, *> -> {
            @Suppress("UNCHECKED_CAST")
            canonicalJson(v as Map<String, Any?>)
        }
        is List<*> -> "[" + v.joinToString(",") { serializeValue(it) } + "]"
        else -> jsonStr(v.toString())
    }

    private fun jsonStr(s: String): String {
        val sb = StringBuilder("\"");
        for (ch in s) {
            when (ch) {
                '"' -> sb.append("\\\"");
                '\\' -> sb.append("\\\\");
                '\n' -> sb.append("\\n");
                '\r' -> sb.append("\\r");
                '\t' -> sb.append("\\t");
                else -> sb.append(ch)
            }
        }
        sb.append("\"");
        return sb.toString()
    }

    // ---- Helpers for raw key ops ----

    private val PKCS8_HEADER = byteArrayOf(0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20)
    private val SPKI_HEADER  = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)

    private fun sha256(data: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(data)

    private fun nodeIdFromRawPub(rawPub: ByteArray): String {
        val hash = sha256(rawPub)
        return hash.take(8).joinToString("") { String.format("%02x", it) }
    }

    // ---- GenerateNIK ----
    // privateKeyB64 = base64url(seed || rawPub) = 64 bytes

    fun generateNik(validDays: Int = 365, nodeLabel: String = ""): NikResult {
        val kpg = KeyPairGenerator.getInstance("Ed25519")
        val kp = kpg.generateKeyPair()
        val spki = kp.public.encoded
        val pkcs8 = kp.private.encoded
        val rawPub = spki.copyOfRange(spki.size - 32, spki.size)
        val seed = pkcs8.copyOfRange(pkcs8.size - 32, pkcs8.size)
        val combined = seed + rawPub  // 64 bytes: seed || rawPub
        val nodeId = nodeIdFromRawPub(rawPub)
        val now = Instant.now()
        val until = now.plusSeconds(validDays.toLong() * 86400L)
        val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)
        val nik = Nik(
            nodeId = nodeId,
            publicKeyB64 = toBase64Url(rawPub),
            validFrom = fmt.format(now),
            validUntil = fmt.format(until),
            keyType = "ltx-nik-v1",
            nodeLabel = nodeLabel
        )
        return NikResult(nik = nik, privateKeyB64 = toBase64Url(combined))
    }

    // ---- IsNIKExpired ----

    fun isNikExpired(nik: Nik): Boolean =
        Instant.now().isAfter(Instant.parse(nik.validUntil))

    // ---- SignPlan ----

    fun signPlan(plan: Map<String, Any?>, privKeyB64: String): SignedPlan {
        val combined = fromBase64Url(privKeyB64)
        val seed = combined.copyOfRange(0, 32)
        val rawPub = combined.copyOfRange(32, 64)
        val pkcs8Bytes = PKCS8_HEADER + seed
        val kf = KeyFactory.getInstance("Ed25519")
        val privKey = kf.generatePrivate(PKCS8EncodedKeySpec(pkcs8Bytes))
        val payStr = canonicalJson(plan)
        val payBytes = payStr.toByteArray(Charsets.UTF_8)
        val signer = Signature.getInstance("Ed25519")
        signer.initSign(privKey)
        signer.update(payBytes)
        val sigBytes = signer.sign()
        val nodeId = nodeIdFromRawPub(rawPub)
        return SignedPlan(
            plan = plan,
            payloadB64 = toBase64Url(payBytes),
            sig = toBase64Url(sigBytes),
            signerNodeId = nodeId
        )
    }

    // ---- VerifyPlan ----

    fun verifyPlan(sp: SignedPlan, keyCache: Map<String, Nik>): VerifyResult {
        val signer = keyCache[sp.signerNodeId]
            ?: return VerifyResult(false, "key_not_in_cache")
        if (isNikExpired(signer)) return VerifyResult(false, "key_expired")
        val expectedBytes = canonicalJson(sp.plan).toByteArray(Charsets.UTF_8)
        val actualBytes = fromBase64Url(sp.payloadB64)
        if (!expectedBytes.contentEquals(actualBytes))
            return VerifyResult(false, "payload_mismatch")
        val rawPub = fromBase64Url(signer.publicKeyB64)
        val spkiBytes = SPKI_HEADER + rawPub
        val kf = KeyFactory.getInstance("Ed25519")
        val pubKey = kf.generatePublic(X509EncodedKeySpec(spkiBytes))
        val sig = Signature.getInstance("Ed25519")
        sig.initVerify(pubKey)
        sig.update(actualBytes)
        val ok = sig.verify(fromBase64Url(sp.sig))
        return if (ok) VerifyResult(true) else VerifyResult(false, "signature_invalid")
    }

    // ---- SequenceTracker ----

    class SequenceTracker {
        private val rx = mutableMapOf<String, Int>()
        private val tx = mutableMapOf<String, Int>()

        fun addSeq(bundle: Map<String, Any?>, nodeId: String): Map<String, Any?> {
            val cur = tx[nodeId] ?: 0
            val next = cur + 1
            tx[nodeId] = next
            return bundle + mapOf("seq" to next)
        }

        fun checkSeq(bundle: Map<String, Any?>, nodeId: String): CheckSeqResult {
            val seqVal = bundle["seq"] as? Int
                ?: return CheckSeqResult(false, "missing_seq")
            val last = rx[nodeId] ?: 0
            if (seqVal <= last) return CheckSeqResult(false, "replay")
            val gap = seqVal > last + 1
            val gapSize = if (gap) seqVal - last - 1 else 0
            rx[nodeId] = seqVal
            return CheckSeqResult(true, null, gap, gapSize)
        }
    }
}
