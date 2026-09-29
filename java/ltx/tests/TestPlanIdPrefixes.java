import com.interplanet.ltx.*;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;

/**
 * TestPlanIdPrefixes: spec/golden/plan-id-prefixes.json (issue #37, spec
 * section 4.3). HOSTSTR / NODESTR use JS whitespace, JS toUpperCase (full
 * Unicode mapping with special casing) and UTF-16 slicing. A Java String is
 * UTF-16, so the exact JS id (planId, lone surrogates included) is expected.
 *
 * Usage: java -cp out/classes TestPlanIdPrefixes [path/to/plan-id-prefixes.json]
 */
public class TestPlanIdPrefixes {

    static int passed = 0;
    static int failed = 0;

    static void check(String name, boolean ok, String got, String want) {
        if (ok) { passed++; return; }
        failed++;
        System.out.println("FAIL: " + name + "\n  got  " + LtxJson.stringify(got) + "\n  want " + LtxJson.stringify(want));
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object v) { return (Map<String, Object>) v; }

    static File goldenFile(String[] args) {
        if (args.length > 0) return new File(args[0]);
        File dir = new File("").getAbsoluteFile();
        while (dir != null) {
            File f = new File(dir, "spec/golden/plan-id-prefixes.json");
            if (f.exists()) return f;
            dir = dir.getParentFile();
        }
        return new File("../../spec/golden/plan-id-prefixes.json");
    }

    static String prefix(String id) { return id.substring(0, id.length() - 12); }

    public static void main(String[] args) throws Exception {
        System.out.println("── Conformance: planId prefix vectors ───────");
        String text = new String(Files.readAllBytes(goldenFile(args).toPath()), StandardCharsets.UTF_8);
        List<?> vectors = (List<?>) m(LtxJson.parse(text)).get("vectors");
        check("prefix vectors present", vectors.size() >= 18, "" + vectors.size(), ">= 18");
        for (Object o : vectors) {
            Map<String, Object> gv = m(o);
            String name = (String) gv.get("name");
            String want = (String) gv.get("planId");
            Map<String, Object> plan = m(gv.get("plan"));
            // JSON path: the plan as parsed, key order preserved.
            String got = LtxPlans.makePlanId(plan);
            check("json " + name, got.equals(want), got, want);
            // JSON path from the re-serialised text.
            String got2 = LtxPlans.makePlanId(m(LtxJson.parse(LtxJson.stringify(plan))));
            check("json text " + name, got2.equals(want), got2, want);
            // Typed path (v2 only): LtxPlan writes nodes before segments, so
            // the hash matches only for nodes-first vectors; the prefix always.
            if (((Number) plan.get("v")).intValue() != 2) continue;
            LtxPlan typed = LtxPlan.fromJson(LtxJson.stringify(plan));
            String tid = InterplanetLTX.makePlanId(typed);
            check("typed prefix " + name, prefix(tid).equals(prefix(want)), tid, want);
            List<String> keys = new ArrayList<>(plan.keySet());
            if (keys.indexOf("nodes") < keys.indexOf("segments")) {
                check("typed " + name, tid.equals(want), tid, want);
            }
        }
        System.out.println();
        System.out.println(passed + " passed  " + failed + " failed");
        if (failed > 0) System.exit(1);
    }
}
