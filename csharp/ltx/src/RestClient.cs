// RestClient.cs — HTTP REST client methods
// C# port of ltx-sdk.js (Story 33.10)

using System.Text;

namespace InterplanetLtx;

public static class RestClient
{
    private static readonly HttpClient _http = new HttpClient();

    // ── storeSession ─────────────────────────────────────────────────────────

    /// <summary>
    /// Store a session plan on the server.
    /// Returns the raw JSON response body.
    /// </summary>
    public static async Task<string> StoreSession(LtxPlan plan, string apiBase = Constants.DEFAULT_API_BASE)
    {
        string url  = $"{apiBase}?action=session";
        string json = plan.ToJson();
        return await HttpPost(url, json);
    }

    // ── getSession ───────────────────────────────────────────────────────────

    /// <summary>
    /// Retrieve a stored session plan by plan ID.
    /// Returns the raw JSON response body.
    /// </summary>
    public static async Task<string> GetSession(string planId, string apiBase = Constants.DEFAULT_API_BASE)
    {
        string enc = Uri.EscapeDataString(planId);
        string url = $"{apiBase}?action=session&plan_id={enc}";
        var resp = await _http.GetAsync(url);
        if (!resp.IsSuccessStatusCode)
        {
            string body = await resp.Content.ReadAsStringAsync();
            throw new HttpRequestException($"LTX API {(int)resp.StatusCode}: {body}");
        }
        return await resp.Content.ReadAsStringAsync();
    }

    // ── downloadICS ──────────────────────────────────────────────────────────

    /// <summary>
    /// Download ICS content for a stored plan from the server.
    /// opts: JSON body e.g. {"start":"2026-03-01T14:00:00Z","duration_min":39}
    /// Returns the raw ICS text.
    /// </summary>
    public static async Task<string> DownloadICS(
        string planId,
        string optsJson,
        string apiBase = Constants.DEFAULT_API_BASE)
    {
        string enc = Uri.EscapeDataString(planId);
        string url = $"{apiBase}?action=ics&plan_id={enc}";
        return await HttpPost(url, optsJson);
    }

    // ── submitFeedback ───────────────────────────────────────────────────────

    /// <summary>
    /// Submit session feedback.
    /// payloadJson: JSON body with feedback data.
    /// Returns the raw JSON response body.
    /// </summary>
    public static async Task<string> SubmitFeedback(
        string payloadJson,
        string apiBase = Constants.DEFAULT_API_BASE)
    {
        string url = $"{apiBase}?action=feedback";
        return await HttpPost(url, payloadJson);
    }

    // ── Private helper ────────────────────────────────────────────────────────

    private static async Task<string> HttpPost(string url, string json)
    {
        using var content = new StringContent(json, Encoding.UTF8, "application/json");
        var resp = await _http.PostAsync(url, content);
        if (!resp.IsSuccessStatusCode)
        {
            string body = await resp.Content.ReadAsStringAsync();
            throw new HttpRequestException($"LTX API {(int)resp.StatusCode}: {body}");
        }
        return await resp.Content.ReadAsStringAsync();
    }
}
