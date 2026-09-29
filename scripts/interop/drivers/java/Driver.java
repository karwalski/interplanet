// Interop driver for java/ltx (see scripts/interop/run.js).
import com.interplanet.ltx.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public class Driver {
    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        Path in = Paths.get(args[0]), out = Paths.get(args[1]);
        // UTF-8 stdout whatever the platform default (stdout.encoding).
        System.setOut(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out), true, StandardCharsets.UTF_8));

        LtxPlan plan = InterplanetLTX.createPlan("Réunion Mars 🚀", "2026-03-15T14:00:00.000Z", 840);
        plan.quantum = 3;
        plan.mode = "LTX-ASYNC";
        plan.nodes = new ArrayList<>(List.of(
            new LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
            new LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
            new LtxNode("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")));
        plan.segments = new ArrayList<>(List.of(
            new LtxSegmentTemplate("PLAN_CONFIRM", 2),
            new LtxSegmentTemplate("TX", 3, "N0", "Ouverture: état de la mission"),
            new LtxSegmentTemplate("RX", 3),
            new LtxSegmentTemplate("TX", 2, "N1", "Réponse 🔴"),
            new LtxSegmentTemplate("BUFFER", 1)));
        System.out.println("NOTE no typed v3 upgrade");

        String token = InterplanetLTX.encodeHash(plan).substring(3);
        Files.write(out.resolve("wire-v2.json"), Base64.getUrlDecoder().decode(token));
        System.out.println("ID_V2 " + InterplanetLTX.makePlanId(plan));

        for (String v : new String[] {"2", "3", "P"}) {
            String json = new String(Files.readAllBytes(in.resolve("js-v" + v + ".json")), StandardCharsets.UTF_8);
            System.out.println("JS_V" + v + " " + LtxPlans.makePlanId((Map<String, Object>) LtxJson.parse(json)));
        }

        // Issue #36 extra case (not a run.js column): control characters, a
        // lone surrogate and JS \s whitespace (tab, NBSP, U+3000, U+2028,
        // BOM, LF) in the title and node names, plus a speaker-only and a
        // label-only segment. The typed wire JSON must be exactly what
        // JSON.stringify writes for it, and the typed planId must equal the
        // JSON-based planId of that wire and the JS reference id (computed
        // with ltx-sdk.js makePlanId on the same plan object).
        LtxPlan ctl = new LtxPlan(2,
            "Ctl\u0001\b\f\n\r\t\"\\\u001f\u007f\ud800 \ud83d\ude80",
            "2026-03-15T14:00:00.000Z", 3, "LTX-ASYNC",
            new ArrayList<>(List.of(
                new LtxNode("N0", "Earth\tHQ", "HOST", 0, "earth"),
                new LtxNode("N1", "Ma\u00a0r\u3000s\u2009Hab-01", "PARTICIPANT", 840, "mars"),
                new LtxNode("N2", "L-1\u2028Gate\ufeffway\n", "PARTICIPANT", 2, "moon"))),
            new ArrayList<>(List.of(
                new LtxSegmentTemplate("PLAN_CONFIRM", 2),
                new LtxSegmentTemplate("TX", 3, "N0", "Opening\tremarks"),
                new LtxSegmentTemplate("RX", 3),
                new LtxSegmentTemplate("TX", 2, "N1", null),
                new LtxSegmentTemplate("TX", 1, null, "Q&A \ud83d\udd34"),
                new LtxSegmentTemplate("BUFFER", 1))));
        String ctlRef = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-39d48c2a";
        String ctlToken = InterplanetLTX.encodeHash(ctl).substring(3);
        byte[] ctlWire = Base64.getUrlDecoder().decode(ctlToken);
        Files.write(out.resolve("wire-ctl.json"), ctlWire);
        String ctlJson = new String(ctlWire, StandardCharsets.UTF_8);
        Map<String, Object> ctlMap = (Map<String, Object>) LtxJson.parse(ctlJson);
        String ctlId = InterplanetLTX.makePlanId(ctl);
        String ctlJsonId = LtxPlans.makePlanId(ctlMap);
        boolean ctlOk = ctlJson.equals(LtxJson.stringify(ctlMap)) && ctlId.equals(ctlJsonId) && ctlId.equals(ctlRef);
        System.out.println("NOTE ctl/whitespace case: typed " + ctlId + ", JSON " + ctlJsonId + ", JS " + ctlRef
            + (ctlOk ? " (ok)" : " (MISMATCH)"));
        if (!ctlOk) System.exit(1);
    }
}
