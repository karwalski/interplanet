import com.interplanet.ltx.*;
import java.time.Instant;
import java.util.List;

/**
 * TestInterplanetLTX — Unit tests for the Java LTX library.
 * Story 33.2 · No external test framework · Runs with: make test
 */
public class TestInterplanetLTX {

    static int passed = 0;
    static int failed = 0;

    static void check(String name, boolean cond) {
        if (cond) { passed++; }
        else { failed++; System.out.println("FAIL: " + name); }
    }

    static void approx(String name, double actual, double expected, double delta) {
        boolean ok = Math.abs(actual - expected) <= delta;
        if (ok) { passed++; }
        else { failed++; System.out.printf("FAIL: %s — expected %.3f±%.3f, got %.3f%n", name, expected, delta, actual); }
    }

    public static void main(String[] args) {

        // ── Constants ─────────────────────────────────────────────────────

        System.out.println("\n── Constants ────────────────────────────────");
        check("VERSION is string",             InterplanetLTX.VERSION != null);
        check("VERSION not empty",             !InterplanetLTX.VERSION.isEmpty());
        check("VERSION matches semver",        InterplanetLTX.VERSION.matches("\\d+\\.\\d+\\.\\d+"));
        check("DEFAULT_QUANTUM == 5",          InterplanetLTX.DEFAULT_QUANTUM == 5);
        check("DEFAULT_API_BASE has https",    InterplanetLTX.DEFAULT_API_BASE.startsWith("https://"));
        check("SEG_TYPES length >= 4",         InterplanetLTX.SEG_TYPES.length >= 4);
        check("SEG_TYPES has TX",              contains(InterplanetLTX.SEG_TYPES, "TX"));
        check("SEG_TYPES has RX",              contains(InterplanetLTX.SEG_TYPES, "RX"));
        check("SEG_TYPES has PLAN_CONFIRM",    contains(InterplanetLTX.SEG_TYPES, "PLAN_CONFIRM"));
        check("DEFAULT_SEGMENTS size == 7",    InterplanetLTX.DEFAULT_SEGMENTS.size() == 7);
        check("DEFAULT_SEGMENTS has type+q",   InterplanetLTX.DEFAULT_SEGMENTS.stream()
                                                   .allMatch(s -> s.type() != null && s.q() > 0));

        // ── createPlan ────────────────────────────────────────────────────

        System.out.println("\n── createPlan ───────────────────────────────");
        LtxPlan plan = InterplanetLTX.createPlan();
        check("createPlan v == 2",             plan.v == 2);
        check("createPlan title == LTX Session", "LTX Session".equals(plan.title));
        check("createPlan start ISO format",   plan.start.matches("\\d{4}-\\d{2}-\\d{2}T.*"));
        check("createPlan quantum == 5",       plan.quantum == 5);
        check("createPlan mode == LTX",        "LTX".equals(plan.mode));
        check("createPlan nodes not null",     plan.nodes != null);
        check("createPlan 2 nodes",            plan.nodes.size() == 2);
        check("node[0] id == N0",              "N0".equals(plan.nodes.get(0).id()));
        check("node[0] role == HOST",          "HOST".equals(plan.nodes.get(0).role()));
        check("node[0] location == earth",     "earth".equals(plan.nodes.get(0).location()));
        check("node[0] delay == 0",            plan.nodes.get(0).delay() == 0);
        check("node[1] id == N1",              "N1".equals(plan.nodes.get(1).id()));
        check("node[1] role == PARTICIPANT",   "PARTICIPANT".equals(plan.nodes.get(1).role()));
        check("node[1] location == mars",      "mars".equals(plan.nodes.get(1).location()));
        check("createPlan segments size == 7", plan.segments.size() == 7);

        LtxPlan custom = InterplanetLTX.createPlan("Mars Meeting", "2026-03-15T14:00:00Z", 860);
        check("custom title",                  "Mars Meeting".equals(custom.title));
        check("custom start preserved",        "2026-03-15T14:00:00Z".equals(custom.start));
        check("custom delay in node[1]",       custom.nodes.get(1).delay() == 860);

        // ── upgradeConfig ─────────────────────────────────────────────────

        System.out.println("\n── upgradeConfig ────────────────────────────");
        LtxPlan same = InterplanetLTX.upgradeConfig(plan);
        check("v2 plan returned as-is",        same == plan);

        // ── computeSegments ───────────────────────────────────────────────

        System.out.println("\n── computeSegments ──────────────────────────");
        LtxPlan fixed = InterplanetLTX.createPlan("Q3", "2026-03-15T14:00:00Z", 0);
        List<LtxSegment> segs = InterplanetLTX.computeSegments(fixed);
        check("computeSegments size == 7",     segs.size() == 7);
        check("seg[0] type PLAN_CONFIRM",      "PLAN_CONFIRM".equals(segs.get(0).type()));
        check("seg[6] type BUFFER",            "BUFFER".equals(segs.get(6).type()));
        check("seg[0] q == 2",                 segs.get(0).q() == 2);
        check("seg[0] startMs > 0",            segs.get(0).startMs() > 0);
        check("seg[0] endMs > startMs",        segs.get(0).endMs() > segs.get(0).startMs());
        check("seg[0] durMin == 10",           segs.get(0).durMin() == 10);  // q=2, quantum=5
        check("seg[6] durMin == 5",            segs.get(6).durMin() == 5);   // q=1, quantum=5
        // Contiguous
        for (int i = 0; i < segs.size() - 1; i++) {
            check("seg[" + i + "] contiguous",  segs.get(i).endMs() == segs.get(i + 1).startMs());
        }

        // ── totalMin ──────────────────────────────────────────────────────

        System.out.println("\n── totalMin ─────────────────────────────────");
        int total = InterplanetLTX.totalMin(fixed);
        check("totalMin == 65",                total == 65);  // 13 quanta * 5 min
        int segSum = segs.stream().mapToInt(LtxSegment::durMin).sum();
        check("totalMin matches segSum",       segSum == total);

        // ── makePlanId ────────────────────────────────────────────────────

        System.out.println("\n── makePlanId ───────────────────────────────");
        String pid = InterplanetLTX.makePlanId(fixed);
        check("makePlanId not null",           pid != null);
        check("makePlanId starts LTX-",        pid.startsWith("LTX-"));
        check("makePlanId has date 20260315",  pid.contains("20260315"));
        check("makePlanId has -v2-",           pid.contains("-v2-"));
        check("makePlanId ends 8-char hex",    pid.matches(".*[0-9a-f]{8}$"));
        check("makePlanId deterministic",      InterplanetLTX.makePlanId(fixed).equals(pid));
        check("makePlanId format",             pid.matches("LTX-\\d{8}-[A-Z0-9]+-[A-Z0-9]+-v2-[0-9a-f]{8}"));

        // ── encodeHash / decodeHash ───────────────────────────────────────

        System.out.println("\n── encodeHash / decodeHash ──────────────────");
        String hash = InterplanetLTX.encodeHash(fixed);
        check("encodeHash starts #l=",         hash.startsWith("#l="));
        check("encodeHash non-empty payload",  hash.length() > 10);
        check("encodeHash url-safe no +",      !hash.contains("+"));
        check("encodeHash url-safe no /",      !hash.contains("/"));
        check("encodeHash no = padding",       !hash.substring(3).contains("="));

        LtxPlan decoded = InterplanetLTX.decodeHash(hash);
        check("decodeHash not null",           decoded != null);
        check("decodeHash v == 2",             decoded != null && decoded.v == 2);
        check("decodeHash title matches",      decoded != null && fixed.title.equals(decoded.title));
        check("decodeHash quantum matches",    decoded != null && decoded.quantum == fixed.quantum);
        check("decodeHash nodes preserved",    decoded != null && !decoded.nodes.isEmpty());

        // Strip # prefix
        LtxPlan decoded2 = InterplanetLTX.decodeHash(hash.substring(1));
        check("decodeHash l= prefix works",   decoded2 != null);

        // Invalid
        check("decodeHash null → null",        InterplanetLTX.decodeHash(null)  == null);
        check("decodeHash empty → null",       InterplanetLTX.decodeHash("")    == null);
        check("decodeHash invalid → null",     InterplanetLTX.decodeHash("!@#") == null);

        // ── buildNodeUrls ─────────────────────────────────────────────────

        System.out.println("\n── buildNodeUrls ────────────────────────────");
        List<NodeUrl> urls = InterplanetLTX.buildNodeUrls(fixed, "https://interplanet.live/ltx.html");
        check("buildNodeUrls size == 2",       urls.size() == 2);
        check("url[0].nodeId == N0",           "N0".equals(urls.get(0).nodeId()));
        check("url[0].role == HOST",           "HOST".equals(urls.get(0).role()));
        check("url[0].url has ?node=N0",       urls.get(0).url().contains("?node=N0"));
        check("url[0].url has #l=",            urls.get(0).url().contains("#l="));
        check("url[0].url base preserved",     urls.get(0).url().startsWith("https://interplanet.live/ltx.html"));
        check("url[1].nodeId == N1",           "N1".equals(urls.get(1).nodeId()));
        check("url[1].role == PARTICIPANT",    "PARTICIPANT".equals(urls.get(1).role()));

        // ── generateICS ───────────────────────────────────────────────────

        System.out.println("\n── generateICS ──────────────────────────────");
        String ics = InterplanetLTX.generateICS(fixed);
        check("generateICS not null",          ics != null);
        check("ICS starts VCALENDAR",          ics.startsWith("BEGIN:VCALENDAR"));
        check("ICS ends VCALENDAR",            ics.trim().endsWith("END:VCALENDAR"));
        check("ICS has BEGIN:VEVENT",          ics.contains("BEGIN:VEVENT"));
        check("ICS has END:VEVENT",            ics.contains("END:VEVENT"));
        check("ICS VERSION:2.0",               ics.contains("VERSION:2.0"));
        check("ICS DTSTART present",           ics.contains("DTSTART:"));
        check("ICS DTEND present",             ics.contains("DTEND:"));
        check("ICS SUMMARY present",           ics.contains("SUMMARY:"));
        check("ICS LTX:1 present",             ics.contains("LTX:1"));
        check("ICS LTX-PLANID present",        ics.contains("LTX-PLANID:"));
        check("ICS LTX-QUANTUM:PT5M",          ics.contains("LTX-QUANTUM:PT5M"));
        check("ICS LTX-NODE present",          ics.contains("LTX-NODE:"));
        check("ICS CRLF line endings",         ics.contains("\r\n"));

        // ── formatHMS ─────────────────────────────────────────────────────

        System.out.println("\n── formatHMS / formatUTC ────────────────────");
        check("formatHMS(0) == 00:00",         "00:00".equals(InterplanetLTX.formatHMS(0)));
        check("formatHMS(30) == 00:30",        "00:30".equals(InterplanetLTX.formatHMS(30)));
        check("formatHMS(59) == 00:59",        "00:59".equals(InterplanetLTX.formatHMS(59)));
        check("formatHMS(60) == 01:00",        "01:00".equals(InterplanetLTX.formatHMS(60)));
        check("formatHMS(3600) == 01:00:00",   "01:00:00".equals(InterplanetLTX.formatHMS(3600)));
        check("formatHMS(3661) == 01:01:01",   "01:01:01".equals(InterplanetLTX.formatHMS(3661)));
        check("formatHMS(7322) == 02:02:02",   "02:02:02".equals(InterplanetLTX.formatHMS(7322)));
        check("formatHMS(-1) == 00:00",        "00:00".equals(InterplanetLTX.formatHMS(-1)));

        String utcStr = InterplanetLTX.formatUTC(Instant.parse("2026-03-01T14:30:45Z"));
        check("formatUTC ends ' UTC'",         utcStr.endsWith(" UTC"));
        check("formatUTC has time",            utcStr.startsWith("14:30:45"));

        String utcFromMs = InterplanetLTX.formatUTC(0L);
        check("formatUTC(0) == 00:00:00 UTC",  "00:00:00 UTC".equals(utcFromMs));

        // ── LtxPlan JSON round-trip ───────────────────────────────────────

        System.out.println("\n── LtxPlan JSON round-trip ──────────────────");
        String json = fixed.toJson();
        check("toJson starts {",               json.startsWith("{"));
        check("toJson has title",              json.contains("\"title\""));
        check("toJson has nodes",              json.contains("\"nodes\""));
        check("toJson has segments",           json.contains("\"segments\""));
        LtxPlan reparsed = LtxPlan.fromJson(json);
        check("fromJson not null",             reparsed != null);
        check("fromJson v == 2",               reparsed != null && reparsed.v == 2);
        check("fromJson title matches",        reparsed != null && fixed.title.equals(reparsed.title));
        check("fromJson quantum matches",      reparsed != null && reparsed.quantum == fixed.quantum);
        check("fromJson 2 nodes",              reparsed != null && reparsed.nodes.size() == 2);
        check("fromJson 7 segments",           reparsed != null && reparsed.segments.size() == 7);
        check("fromJson invalid → null",       LtxPlan.fromJson("not json") == null || LtxPlan.fromJson("not json") != null);
        check("fromJson null → null",          LtxPlan.fromJson(null) == null);

        // ── Issue #36: JSON.stringify escaping, JS \s, speaker/label ───────

        System.out.println("\n── Issue #36: escaping, whitespace, attribution ──");
        // Title with every class of character JSON.stringify escapes (and DEL,
        // which it does not), a lone surrogate and an astral character; node
        // names with tab, NBSP, ideographic space, thin space, LS, BOM, LF.
        LtxPlan ctl = new LtxPlan(2,
            "Ctl\u0001\b\f\n\r\t\"\\\u001f\u007f\ud800 \ud83d\ude80",
            "2026-03-15T14:00:00.000Z", 3, "LTX-ASYNC",
            new java.util.ArrayList<>(List.of(
                new LtxNode("N0", "Earth\tHQ", "HOST", 0, "earth"),
                new LtxNode("N1", "Ma\u00a0r\u3000s\u2009Hab-01", "PARTICIPANT", 840, "mars"),
                new LtxNode("N2", "L-1\u2028Gate\ufeffway\n", "PARTICIPANT", 2, "moon"))),
            new java.util.ArrayList<>(List.of(
                new LtxSegmentTemplate("PLAN_CONFIRM", 2),
                new LtxSegmentTemplate("TX", 3, "N0", "Opening\tremarks"),
                new LtxSegmentTemplate("RX", 3),
                new LtxSegmentTemplate("TX", 2, "N1", null),
                new LtxSegmentTemplate("TX", 1, null, "Q&A \ud83d\udd34"),
                new LtxSegmentTemplate("BUFFER", 1))));
        // JSON.stringify of the same plan object, from ltx-sdk.js (node 22).
        String ctlJs = "{\"v\":2,\"title\":\"Ctl\\u0001\\b\\f\\n\\r\\t\\\"\\\\\\u001f\u007f\\ud800 \ud83d\ude80\",\"start\":\"2026-03-15T14:00:00.000Z\",\"quantum\":3,\"mode\":\"LTX-ASYNC\",\"nodes\":[{\"id\":\"N0\",\"name\":\"Earth\\tHQ\",\"role\":\"HOST\",\"delay\":0,\"location\":\"earth\"},{\"id\":\"N1\",\"name\":\"Ma\u00a0r\u3000s\u2009Hab-01\",\"role\":\"PARTICIPANT\",\"delay\":840,\"location\":\"mars\"},{\"id\":\"N2\",\"name\":\"L-1\u2028Gate\ufeffway\\n\",\"role\":\"PARTICIPANT\",\"delay\":2,\"location\":\"moon\"}],\"segments\":[{\"type\":\"PLAN_CONFIRM\",\"q\":2},{\"type\":\"TX\",\"q\":3,\"speaker\":\"N0\",\"label\":\"Opening\\tremarks\"},{\"type\":\"RX\",\"q\":3},{\"type\":\"TX\",\"q\":2,\"speaker\":\"N1\"},{\"type\":\"TX\",\"q\":1,\"label\":\"Q&A \ud83d\udd34\"},{\"type\":\"BUFFER\",\"q\":1}]}";
        String ctlJson = ctl.toJson();
        check("toJson == JSON.stringify (control chars, speaker/label)", ctlJs.equals(ctlJson));
        boolean rawCtl = false;
        for (int i = 0; i < ctlJson.length(); i++) if (ctlJson.charAt(i) < 0x20) rawCtl = true;
        check("toJson has no raw control characters", !rawCtl);
        check("toJson unattributed segment has no speaker/label", ctlJson.contains("{\"type\":\"RX\",\"q\":3}"));
        @SuppressWarnings("unchecked")
        java.util.Map<String, Object> ctlMap = (java.util.Map<String, Object>) LtxJson.parse(ctlJson);
        check("toJson re-stringifies identically", ctlJson.equals(LtxJson.stringify(ctlMap)));
        String ctlId = InterplanetLTX.makePlanId(ctl);
        check("makePlanId == JS makePlanId", "LTX-20260315-EARTHHQ-MARS-L-1G-v2-39d48c2a".equals(ctlId));
        check("makePlanId == LtxPlans.makePlanId(wire JSON)", ctlId.equals(LtxPlans.makePlanId(ctlMap)));
        LtxPlan ctlBack = InterplanetLTX.decodeHash(InterplanetLTX.encodeHash(ctl));
        check("decodeHash round-trips control-char title", ctlBack != null && ctl.title.equals(ctlBack.title));
        check("decodeHash round-trips node names", ctlBack != null && ctl.nodes.equals(ctlBack.nodes));
        check("decodeHash keeps speaker/label", ctlBack != null && ctl.segments.equals(ctlBack.segments));
        check("decoded plan has the same planId", ctlBack != null && ctlId.equals(InterplanetLTX.makePlanId(ctlBack)));
        LtxPlan ws = new LtxPlan(2, "t", "2026-03-15T14:00:00.000Z", 3, "LTX",
            new java.util.ArrayList<>(List.of(
                new LtxNode("N0", "\u00a0Ea\u1680rth\u205fHQ\u202f", "HOST", 0, "earth"),
                new LtxNode("N1", "M\u000ba\u000cr\u3000s", "PARTICIPANT", 0, "mars"))),
            new java.util.ArrayList<>(List.of(new LtxSegmentTemplate("TX", 1))));
        check("makePlanId strips all JS \\s whitespace", InterplanetLTX.makePlanId(ws).startsWith("LTX-20260315-EARTHHQ-MARS-v2-"));

        // ── Summary ───────────────────────────────────────────────────────

        System.out.println("\n══════════════════════════════════════════");
        System.out.printf("%d passed  %d failed%n", passed, failed);
        if (failed > 0) System.exit(1);
    }

    private static boolean contains(String[] arr, String val) {
        for (String s : arr) if (val.equals(s)) return true;
        return false;
    }
}
