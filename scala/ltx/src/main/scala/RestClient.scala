/**
 * RestClient.scala - REST API client for the LTX server
 * Story 33.13 - Scala LTX library
 *
 * Uses java.net.HttpURLConnection (no external dependencies).
 */

import java.io.{BufferedReader, InputStreamReader, OutputStream}
import java.net.{HttpURLConnection, URL, URLEncoder}
import java.nio.charset.StandardCharsets

object RestClient:

  /**
   * Store a session plan on the server.
   * Returns the raw JSON response body.
   *
   * @param plan    LTX plan config
   * @param apiBase API base URL (default: DEFAULT_API_BASE)
   */
  def storeSession(plan: LtxPlan, apiBase: String = DEFAULT_API_BASE): String =
    val c   = InterplanetLtx.upgradeConfig(plan)
    val url = s"$apiBase?action=session"
    httpPost(url, c.toJson)

  /**
   * Retrieve a stored session plan by plan ID.
   * Returns the raw JSON response body.
   *
   * @param planId  Plan ID string (e.g. "LTX-20260101-EARTHHQ-MARS-v2-a3b2c1d0")
   * @param apiBase API base URL (default: DEFAULT_API_BASE)
   */
  def getSession(planId: String, apiBase: String = DEFAULT_API_BASE): String =
    val encoded = URLEncoder.encode(planId, "UTF-8")
    val url = s"$apiBase?action=session&plan_id=$encoded"
    httpGet(url)

  /**
   * Download ICS content for a stored plan.
   * Returns the raw ICS string.
   *
   * @param planId   Plan ID string
   * @param optsJson JSON body: e.g. {"start":"2026-03-01T14:00:00Z","duration_min":39}
   * @param apiBase  API base URL (default: DEFAULT_API_BASE)
   */
  def downloadICS(planId: String, optsJson: String, apiBase: String = DEFAULT_API_BASE): String =
    val encoded = URLEncoder.encode(planId, "UTF-8")
    val url = s"$apiBase?action=ics&plan_id=$encoded"
    httpPost(url, optsJson)

  /**
   * Submit session feedback.
   * Returns the raw JSON response body.
   *
   * @param payloadJson JSON body with feedback data
   * @param apiBase     API base URL (default: DEFAULT_API_BASE)
   */
  def submitFeedback(payloadJson: String, apiBase: String = DEFAULT_API_BASE): String =
    val url = s"$apiBase?action=feedback"
    httpPost(url, payloadJson)

  // ── Private HTTP helpers ───────────────────────────────────────────────────

  private def httpPost(urlStr: String, json: String): String =
    val url  = new URL(urlStr)
    val conn = url.openConnection().asInstanceOf[HttpURLConnection]
    try
      conn.setRequestMethod("POST")
      conn.setRequestProperty("Content-Type", "application/json")
      conn.setDoOutput(true)
      val bytes = json.getBytes(StandardCharsets.UTF_8)
      conn.setFixedLengthStreamingMode(bytes.length)
      val out: OutputStream = conn.getOutputStream
      try out.write(bytes)
      finally out.close()
      readResponse(conn)
    finally
      conn.disconnect()

  private def httpGet(urlStr: String): String =
    val url  = new URL(urlStr)
    val conn = url.openConnection().asInstanceOf[HttpURLConnection]
    try
      conn.setRequestMethod("GET")
      readResponse(conn)
    finally
      conn.disconnect()

  private def readResponse(conn: HttpURLConnection): String =
    val code = conn.getResponseCode
    val stream = if code < 400 then conn.getInputStream else conn.getErrorStream
    val reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))
    try
      val sb = new StringBuilder
      var line = reader.readLine()
      while line != null do
        sb.append(line).append("\n")
        line = reader.readLine()
      if code < 200 || code >= 300 then
        throw new RuntimeException(s"LTX API $code: ${sb.toString.trim}")
      sb.toString.trim
    finally
      reader.close()
