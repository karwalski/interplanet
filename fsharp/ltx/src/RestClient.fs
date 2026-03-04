// RestClient.fs --- HTTP REST client methods
// F# port of ltx-sdk.js (Story 33.14)

module InterplanetLtx.RestClient

open System
open System.Net.Http
open System.Text
open InterplanetLtx.Models
open InterplanetLtx.Constants
open InterplanetLtx.InterplanetLtx

let private http = new HttpClient()

// ── storeSession ──────────────────────────────────────────────────────────────

/// Store a session plan on the server.
/// Returns the raw JSON response body.
let storeSession (plan: LtxPlan) (apiBase: string) : Async<string> =
    let url  = sprintf "%s?action=session" apiBase
    let json = toJson plan
    async {
        use content = new StringContent(json, Encoding.UTF8, "application/json")
        let! resp = http.PostAsync(url, content) |> Async.AwaitTask
        if not resp.IsSuccessStatusCode then
            let! body = resp.Content.ReadAsStringAsync() |> Async.AwaitTask
            raise (HttpRequestException(sprintf "LTX API %d: %s" (int resp.StatusCode) body))
        return! resp.Content.ReadAsStringAsync() |> Async.AwaitTask
    }

// ── getSession ───────────────────────────────────────────────────────────────

/// Retrieve a stored session plan by plan ID.
/// Returns the raw JSON response body.
let getSession (planId: string) (apiBase: string) : Async<string> =
    let enc = Uri.EscapeDataString(planId)
    let url = sprintf "%s?action=session&plan_id=%s" apiBase enc
    async {
        let! resp = http.GetAsync(url) |> Async.AwaitTask
        if not resp.IsSuccessStatusCode then
            let! body = resp.Content.ReadAsStringAsync() |> Async.AwaitTask
            raise (HttpRequestException(sprintf "LTX API %d: %s" (int resp.StatusCode) body))
        return! resp.Content.ReadAsStringAsync() |> Async.AwaitTask
    }

// ── downloadICS ──────────────────────────────────────────────────────────────

/// Download ICS content for a stored plan from the server.
/// optsJson: JSON body e.g. {"start":"2026-03-01T14:00:00Z","duration_min":39}
/// Returns the raw ICS text.
let downloadICS (planId: string) (optsJson: string) (apiBase: string) : Async<string> =
    let enc = Uri.EscapeDataString(planId)
    let url = sprintf "%s?action=ics&plan_id=%s" apiBase enc
    async {
        use content = new StringContent(optsJson, Encoding.UTF8, "application/json")
        let! resp = http.PostAsync(url, content) |> Async.AwaitTask
        if not resp.IsSuccessStatusCode then
            let! body = resp.Content.ReadAsStringAsync() |> Async.AwaitTask
            raise (HttpRequestException(sprintf "LTX API %d: %s" (int resp.StatusCode) body))
        return! resp.Content.ReadAsStringAsync() |> Async.AwaitTask
    }

// ── submitFeedback ────────────────────────────────────────────────────────────

/// Submit session feedback.
/// payloadJson: JSON body with feedback data.
/// Returns the raw JSON response body.
let submitFeedback (payloadJson: string) (apiBase: string) : Async<string> =
    let url = sprintf "%s?action=feedback" apiBase
    async {
        use content = new StringContent(payloadJson, Encoding.UTF8, "application/json")
        let! resp = http.PostAsync(url, content) |> Async.AwaitTask
        if not resp.IsSuccessStatusCode then
            let! body = resp.Content.ReadAsStringAsync() |> Async.AwaitTask
            raise (HttpRequestException(sprintf "LTX API %d: %s" (int resp.StatusCode) body))
        return! resp.Content.ReadAsStringAsync() |> Async.AwaitTask
    }
