// Interop driver for java/ltx (see scripts/interop/run.js).
import com.interplanet.ltx.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public class Driver {
    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        Path in = Paths.get(args[0]), out = Paths.get(args[1]);

        LtxPlan plan = InterplanetLTX.createPlan("Réunion Mars 🚀", "2026-03-15T14:00:00.000Z", 840);
        plan.quantum = 3;
        plan.mode = "LTX-ASYNC";
        plan.nodes = new ArrayList<>(List.of(
            new LtxNode("N0", "Earth HQ", "HOST", 0, "earth"),
            new LtxNode("N1", "Mars Hab-01", "PARTICIPANT", 840, "mars"),
            new LtxNode("N2", "L-1 Gateway", "PARTICIPANT", 2, "moon")));
        // LtxSegmentTemplate is (type, q) only: no speaker/label.
        plan.segments = new ArrayList<>(List.of(
            new LtxSegmentTemplate("PLAN_CONFIRM", 2), new LtxSegmentTemplate("TX", 3),
            new LtxSegmentTemplate("RX", 3), new LtxSegmentTemplate("TX", 2),
            new LtxSegmentTemplate("BUFFER", 1)));
        System.out.println("NOTE typed LtxSegmentTemplate has no speaker/label; no typed v3 upgrade");

        String token = InterplanetLTX.encodeHash(plan).substring(3);
        Files.write(out.resolve("wire-v2.json"), Base64.getUrlDecoder().decode(token));
        System.out.println("ID_V2 " + InterplanetLTX.makePlanId(plan));

        for (String v : new String[] {"2", "3"}) {
            String json = new String(Files.readAllBytes(in.resolve("js-v" + v + ".json")), StandardCharsets.UTF_8);
            System.out.println("JS_V" + v + " " + LtxPlans.makePlanId((Map<String, Object>) LtxJson.parse(json)));
        }
    }
}
