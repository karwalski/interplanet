package com.interplanet.ltx;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * InterplanetLTX — Java 16+ port of ltx-sdk.js.
 * Story 33.2 — Java LTX library (independent of interplanet-time Java library)
 *
 * All public methods are static.
 *
 * @example
 * <pre>
 * LtxPlan plan = InterplanetLTX.createPlan("Q3 Review", "2026-03-15T14:00:00Z", 860);
 * List<LtxSegment> segs = InterplanetLTX.computeSegments(plan);
 * String ics  = InterplanetLTX.generateICS(plan);
 * String hash = InterplanetLTX.encodeHash(plan);  // "#l=eyJ2Ij..."
 * </pre>
 */
public final class InterplanetLTX {

    private InterplanetLTX() {}

    // ── Constants ──────────────────────────────────────────────────────────

    public static final String   VERSION         = "1.0.0";
    public static final int      DEFAULT_QUANTUM  = 3;
    public static final String   DEFAULT_API_BASE = "https://interplanet.live/api/ltx.php";

    public static final String[] SEG_TYPES = {
        "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE"
    };

    public static final List<LtxSegmentTemplate> DEFAULT_SEGMENTS = List.of(
        new LtxSegmentTemplate("PLAN_CONFIRM", 2),
        new LtxSegmentTemplate("TX",           2),
        new LtxSegmentTemplate("RX",           2),
        new LtxSegmentTemplate("CAUCUS",       2),
        new LtxSegmentTemplate("TX",           2),
        new LtxSegmentTemplate("RX",           2),
        new LtxSegmentTemplate("BUFFER",       1)
    );

    // ── Plan creation ──────────────────────────────────────────────────────

    /**
     * Create a new LTX session plan with default Earth HQ → Mars Hab-01 nodes.
     *
     * @param title      Session title (null → "LTX Session")
     * @param start      ISO-8601 start time (null → now + 5 min, rounded to minute)
     * @param delaySeconds One-way light-travel delay for the remote node in seconds (0 = same planet)
     */
    public static LtxPlan createPlan(String title, String start, int delaySeconds) {
        if (title == null || title.isEmpty()) title = "LTX Session";
        if (start == null || start.isEmpty()) {
            Instant now = Instant.now().plusSeconds(300);
            // round down to the minute
            now = Instant.ofEpochSecond((now.getEpochSecond() / 60) * 60);
            start = now.toString();
        }
        List<LtxNode> nodes = new ArrayList<>();
        nodes.add(new LtxNode("N0", "Earth HQ",    "HOST",        0,             "earth"));
        nodes.add(new LtxNode("N1", "Mars Hab-01", "PARTICIPANT", delaySeconds,  "mars"));

        return new LtxPlan(2, title, start, DEFAULT_QUANTUM, "LTX",
                           nodes, new ArrayList<>(DEFAULT_SEGMENTS));
    }

    /** Create a plan with defaults (Earth HQ → Mars Hab-01, no delay). */
    public static LtxPlan createPlan() {
        return createPlan(null, null, 0);
    }

    // ── upgradeConfig ──────────────────────────────────────────────────────

    /**
     * Upgrade a v1-style plan (if v &lt; 2) to the v2 nodes-array schema.
     * v2 plans are returned unchanged.
     */
    public static LtxPlan upgradeConfig(LtxPlan cfg) {
        if (cfg.v >= 2 && cfg.nodes != null && !cfg.nodes.isEmpty()) return cfg;
        // v1 had no nodes list; synthesise from title fields stored in the plan
        // (Java callers should use createPlan directly; this handles serialised v1 round-trips)
        List<LtxNode> nodes = new ArrayList<>();
        nodes.add(new LtxNode("N0", "Earth HQ",    "HOST",        0,          "earth"));
        nodes.add(new LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 0,          "mars"));
        cfg.v     = 2;
        cfg.nodes = nodes;
        return cfg;
    }

    // ── computeSegments ────────────────────────────────────────────────────

    /**
     * Compute the timed segment array for a plan.
     * Each segment has absolute start/end times (UTC ms) and durMin.
     */
    public static List<LtxSegment> computeSegments(LtxPlan cfg) {
        cfg = upgradeConfig(cfg);
        long qMs = (long) cfg.quantum * 60 * 1000;
        long t   = parseIsoToEpochMs(cfg.start);
        List<LtxSegment> result = new ArrayList<>();
        for (LtxSegmentTemplate s : cfg.segments) {
            long durMs = s.q() * qMs;
            result.add(new LtxSegment(s.type(), s.q(), t, t + durMs, s.q() * cfg.quantum));
            t += durMs;
        }
        return result;
    }

    // ── totalMin ──────────────────────────────────────────────────────────

    /** Total session duration in minutes. */
    public static int totalMin(LtxPlan cfg) {
        cfg = upgradeConfig(cfg);
        int total = 0;
        for (LtxSegmentTemplate s : cfg.segments) total += s.q() * cfg.quantum;
        return total;
    }

    // ── makePlanId ────────────────────────────────────────────────────────

    /**
     * Compute the deterministic plan ID string.
     * Matches the ID generated by ltx-sdk.js and api/ltx.php.
     *
     * @return e.g. {@code "LTX-20260301-EARTHHQ-MARS-v2-a3b2c1d0"}
     */
    public static String makePlanId(LtxPlan cfg) {
        cfg = upgradeConfig(cfg);
        String date = cfg.start.substring(0, 10).replace("-", "");

        String hostStr = cfg.nodes.isEmpty() ? "HOST"
            : cfg.nodes.get(0).name().replaceAll("\\s+", "").toUpperCase();
        if (hostStr.length() > 8) hostStr = hostStr.substring(0, 8);

        String nodeStr;
        if (cfg.nodes.size() > 1) {
            StringBuilder sb = new StringBuilder();
            for (int i = 1; i < cfg.nodes.size(); i++) {
                if (sb.length() > 0) sb.append("-");
                String n = cfg.nodes.get(i).name().replaceAll("\\s+", "").toUpperCase();
                sb.append(n, 0, Math.min(4, n.length()));
            }
            nodeStr = sb.length() > 16 ? sb.substring(0, 16) : sb.toString();
        } else {
            nodeStr = "RX";
        }

        // Same 32-bit polynomial hash as ltx-sdk.js: h = 31*h + charCode
        String raw = cfg.toJson();
        int h = 0;
        for (int i = 0; i < raw.length(); i++) {
            h = 31 * h + raw.charAt(i);
        }
        String hash = String.format("%08x", Integer.toUnsignedLong(h));
        return "LTX-" + date + "-" + hostStr + "-" + nodeStr + "-v2-" + hash;
    }

    // ── encodeHash / decodeHash ───────────────────────────────────────────

    /**
     * Encode a plan config to a URL hash fragment ({@code #l=…}).
     * Uses URL-safe base64 (no +, /, or = padding).
     */
    public static String encodeHash(LtxPlan cfg) {
        cfg = upgradeConfig(cfg);
        byte[] json = cfg.toJson().getBytes(StandardCharsets.UTF_8);
        String b64  = Base64.getEncoder().encodeToString(json)
                            .replace('+', '-').replace('/', '_').replace("=", "");
        return "#l=" + b64;
    }

    /**
     * Decode a plan config from a URL hash fragment.
     * Accepts {@code #l=…}, {@code l=…}, or the raw base64 token.
     * Returns {@code null} if the hash is invalid.
     */
    public static LtxPlan decodeHash(String hash) {
        if (hash == null || hash.isEmpty()) return null;
        try {
            String token = hash.replaceFirst("^#?l=", "");
            String std   = token.replace('-', '+').replace('_', '/');
            // Re-add base64 padding
            int mod = std.length() % 4;
            if (mod == 2) std += "==";
            else if (mod == 3) std += "=";
            byte[] bytes = Base64.getDecoder().decode(std);
            String json  = new String(bytes, StandardCharsets.UTF_8);
            return LtxPlan.fromJson(json);
        } catch (Exception e) {
            return null;
        }
    }

    // ── buildNodeUrls ─────────────────────────────────────────────────────

    /**
     * Build perspective URLs for all nodes in a plan.
     *
     * @param cfg     LTX plan config
     * @param baseUrl Base page URL, e.g. {@code "https://interplanet.live/ltx.html"}
     */
    public static List<NodeUrl> buildNodeUrls(LtxPlan cfg, String baseUrl) {
        cfg = upgradeConfig(cfg);
        String hash = encodeHash(cfg).substring(1); // strip leading '#'
        String base = baseUrl == null ? "" : baseUrl.replaceAll("[#?].*$", "");
        List<NodeUrl> result = new ArrayList<>();
        for (LtxNode n : cfg.nodes) {
            String url = base + "?node=" + urlEncode(n.id()) + "#" + hash;
            result.add(new NodeUrl(n.id(), n.name(), n.role(), url));
        }
        return result;
    }

    // ── generateICS ───────────────────────────────────────────────────────

    /**
     * Generate LTX-extended iCalendar (.ics) content for a plan.
     * Includes {@code LTX-NODE}, {@code LTX-DELAY}, {@code LTX-LOCALTIME} extension properties.
     */
    public static String generateICS(LtxPlan cfg) {
        cfg = upgradeConfig(cfg);
        List<LtxSegment> segs = computeSegments(cfg);
        long   startMs = parseIsoToEpochMs(cfg.start);
        long   endMs   = segs.isEmpty() ? startMs : segs.get(segs.size() - 1).endMs();
        String planId  = makePlanId(cfg);

        LtxNode host   = cfg.nodes.isEmpty()
            ? new LtxNode("N0", "Earth HQ", "HOST", 0, "earth")
            : cfg.nodes.get(0);
        List<LtxNode> parts = cfg.nodes.size() > 1
            ? cfg.nodes.subList(1, cfg.nodes.size())
            : Collections.emptyList();

        String segTpl = segTemplate(cfg);

        // Build lines
        List<String> lines = new ArrayList<>();
        lines.add("BEGIN:VCALENDAR");
        lines.add("VERSION:2.0");
        lines.add("PRODID:-//InterPlanet//LTX v1.1//EN");
        lines.add("CALSCALE:GREGORIAN");
        lines.add("METHOD:PUBLISH");
        lines.add("BEGIN:VEVENT");
        lines.add("UID:" + planId + "@interplanet.live");
        lines.add("DTSTAMP:" + fmtDT(Instant.now()));
        lines.add("DTSTART:" + fmtDT(Instant.ofEpochMilli(startMs)));
        lines.add("DTEND:" + fmtDT(Instant.ofEpochMilli(endMs)));
        lines.add("SUMMARY:" + cfg.title);

        String partNames = parts.isEmpty() ? "remote nodes"
            : String.join(", ", parts.stream().map(LtxNode::name).toList());
        String delayDesc = parts.isEmpty() ? "no participant delay configured"
            : String.join(" \u00b7 ", parts.stream()
                .map(p -> p.name() + ": " + Math.round(p.delay() / 60.0) + " min one-way")
                .toList());

        lines.add("DESCRIPTION:LTX session \u2014 " + host.name() + " with " + partNames + "\\n"
            + "Signal delays: " + delayDesc + "\\n"
            + "Mode: " + cfg.mode + " \u00b7 Segment plan: " + segTpl + "\\n"
            + "Generated by InterPlanet (https://interplanet.live)");
        lines.add("LTX:1");
        lines.add("LTX-PLANID:" + planId);
        lines.add("LTX-QUANTUM:PT" + cfg.quantum + "M");
        lines.add("LTX-SEGMENT-TEMPLATE:" + segTpl);
        lines.add("LTX-MODE:" + cfg.mode);

        for (LtxNode n : cfg.nodes) {
            lines.add("LTX-NODE:ID=" + toId(n.name()) + ";ROLE=" + n.role());
        }
        for (LtxNode p : parts) {
            int d = p.delay();
            lines.add("LTX-DELAY;NODEID=" + toId(p.name())
                + ":ONEWAY-MIN=" + d + ";ONEWAY-MAX=" + (d + 120) + ";ONEWAY-ASSUMED=" + d);
        }
        lines.add("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY");
        for (LtxNode n : cfg.nodes) {
            if ("mars".equals(n.location())) {
                lines.add("LTX-LOCALTIME:NODE=" + toId(n.name()) + ";SCHEME=LMST;PARAMS=LONGITUDE:0E");
            }
        }
        lines.add("END:VEVENT");
        lines.add("END:VCALENDAR");

        return String.join("\r\n", lines);
    }

    // ── formatHMS / formatUTC ─────────────────────────────────────────────

    /**
     * Format a duration in seconds as {@code HH:MM:SS} (if &ge;1 hour) or {@code MM:SS}.
     */
    public static String formatHMS(int seconds) {
        if (seconds < 0) seconds = 0;
        int h = seconds / 3600;
        int m = (seconds % 3600) / 60;
        int s = seconds % 60;
        if (h > 0) return String.format("%02d:%02d:%02d", h, m, s);
        return String.format("%02d:%02d", m, s);
    }

    /**
     * Format an Instant as {@code HH:MM:SS UTC}.
     */
    public static String formatUTC(Instant instant) {
        String iso = instant.toString();  // "2026-03-01T14:30:45Z"
        return iso.substring(11, 19) + " UTC";
    }

    /**
     * Format a UTC epoch milliseconds value as {@code HH:MM:SS UTC}.
     */
    public static String formatUTC(long epochMs) {
        return formatUTC(Instant.ofEpochMilli(epochMs));
    }

    // ── REST client ───────────────────────────────────────────────────────

    /**
     * Store a session plan on the server.
     * Returns the raw JSON response body.
     */
    public static String storeSession(LtxPlan cfg) throws Exception {
        return storeSession(cfg, DEFAULT_API_BASE);
    }

    public static String storeSession(LtxPlan cfg, String apiBase) throws Exception {
        cfg = upgradeConfig(cfg);
        return httpPost(apiBase + "?action=session", cfg.toJson());
    }

    /**
     * Retrieve a stored session plan by plan ID.
     * Returns the raw JSON response body.
     */
    public static String getSession(String planId) throws Exception {
        return getSession(planId, DEFAULT_API_BASE);
    }

    public static String getSession(String planId, String apiBase) throws Exception {
        String url = apiBase + "?action=session&plan_id=" + urlEncode(planId);
        HttpClient client = HttpClient.newHttpClient();
        HttpRequest req   = HttpRequest.newBuilder(URI.create(url)).GET().build();
        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() < 200 || resp.statusCode() >= 300) {
            throw new RuntimeException("LTX API " + resp.statusCode() + ": " + resp.body());
        }
        return resp.body();
    }

    /**
     * Download ICS content for a stored plan.
     * Returns the raw ICS string.
     *
     * @param opts JSON body: e.g. {@code {"start":"2026-03-01T14:00:00Z","duration_min":39}}
     */
    public static String downloadICS(String planId, String optsJson) throws Exception {
        return downloadICS(planId, optsJson, DEFAULT_API_BASE);
    }

    public static String downloadICS(String planId, String optsJson, String apiBase) throws Exception {
        String url = apiBase + "?action=ics&plan_id=" + urlEncode(planId);
        return httpPost(url, optsJson);
    }

    /**
     * Submit session feedback.
     * Returns the raw JSON response body.
     *
     * @param payloadJson JSON body with feedback data
     */
    public static String submitFeedback(String payloadJson) throws Exception {
        return submitFeedback(payloadJson, DEFAULT_API_BASE);
    }

    public static String submitFeedback(String payloadJson, String apiBase) throws Exception {
        return httpPost(apiBase + "?action=feedback", payloadJson);
    }

    // ── Private helpers ────────────────────────────────────────────────────

    private static String httpPost(String url, String json) throws Exception {
        HttpClient  client = HttpClient.newHttpClient();
        HttpRequest req    = HttpRequest.newBuilder(URI.create(url))
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(json))
            .build();
        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() < 200 || resp.statusCode() >= 300) {
            throw new RuntimeException("LTX API " + resp.statusCode() + ": " + resp.body());
        }
        return resp.body();
    }

    private static String urlEncode(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8);
    }

    private static String fmtDT(Instant instant) {
        // iCal UTC format: 20260301T140000Z
        return DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'")
                                .withZone(ZoneOffset.UTC)
                                .format(instant);
    }

    private static String toId(String name) {
        return name.replaceAll("\\s+", "-").toUpperCase();
    }

    private static String segTemplate(LtxPlan cfg) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < cfg.segments.size(); i++) {
            if (i > 0) sb.append(",");
            sb.append(cfg.segments.get(i).type());
        }
        return sb.toString();
    }

    /** Parse ISO-8601 timestamp to UTC epoch milliseconds. */
    static long parseIsoToEpochMs(String iso) {
        // Accepts "2026-03-01T12:00:00.000Z" or "2026-03-01T12:00:00Z"
        try {
            return Instant.parse(iso).toEpochMilli();
        } catch (Exception e) {
            return 0L;
        }
    }
}
