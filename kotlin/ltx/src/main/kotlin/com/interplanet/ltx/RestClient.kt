package com.interplanet.ltx

import java.net.HttpURLConnection
import java.net.URL
import java.io.OutputStreamWriter

/**
 * RestClient — HTTP client for the InterPlanet LTX REST API.
 * Story 38.1 — Kotlin LTX library
 */
object RestClient {

    /**
     * Store a session plan on the server.
     * Returns the raw JSON response body.
     */
    fun storeSession(plan: LtxPlan, apiBase: String = InterplanetLTX.DEFAULT_API_BASE): String {
        val json = """{"plan":${InterplanetLTX.planToJsonPublic(plan)}}"""
        return httpPost("$apiBase/session", json)
    }

    /**
     * Retrieve a stored session plan by plan ID.
     * Returns the raw JSON response body.
     */
    fun getSession(planId: String, apiBase: String = InterplanetLTX.DEFAULT_API_BASE): String =
        httpGet("$apiBase/session/${urlEncode(planId)}")

    /**
     * Download ICS content for a stored plan.
     * Returns the raw ICS string.
     */
    fun downloadICS(planId: String, nodeId: String? = null, apiBase: String = InterplanetLTX.DEFAULT_API_BASE): String {
        val url = "$apiBase/ics/${urlEncode(planId)}" + (if (nodeId != null) "?node=${urlEncode(nodeId)}" else "")
        return httpGet(url)
    }

    /**
     * Submit session feedback.
     * Returns the raw JSON response body.
     */
    fun submitFeedback(planId: String, payload: String, apiBase: String = InterplanetLTX.DEFAULT_API_BASE): String =
        httpPost("$apiBase/feedback/${urlEncode(planId)}", payload)

    // ── Private helpers ────────────────────────────────────────────────────

    private fun urlEncode(s: String) = java.net.URLEncoder.encode(s, "UTF-8")

    private fun httpPost(url: String, body: String): String {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "POST"; conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 5000; conn.readTimeout = 10000
            OutputStreamWriter(conn.outputStream).use { it.write(body) }
            conn.inputStream.bufferedReader().readText()
        } catch (e: Exception) { throw RuntimeException("HTTP POST failed: ${e.message}") }
    }

    private fun httpGet(url: String): String {
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.connectTimeout = 5000; conn.readTimeout = 10000
            conn.inputStream.bufferedReader().readText()
        } catch (e: Exception) { throw RuntimeException("HTTP GET failed: ${e.message}") }
    }
}
