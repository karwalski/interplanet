import com.interplanet.ltx.*;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;

/**
 * TestParity: LTX parity with javascript/ltx/tests/run.js (issue #27):
 * golden planId vectors (spec/golden/plan-ids.json) and validatePlan with the
 * reserved streams / branching rules.
 *
 * Usage: java -cp out/classes TestParity [path/to/plan-ids.json]
 */
public class TestParity {

    static int passed = 0;
    static int failed = 0;

    static void check(String name, boolean ok) {
        if (ok) passed++;
        else { failed++; System.out.println("FAIL: " + name); }
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object v) { return (Map<String, Object>) v; }

    static List<String> codesOf(LtxPlans.Validation r) {
        List<String> out = new ArrayList<>();
        for (LtxPlans.PlanError e : r.errors()) out.add(e.code());
        return out;
    }

    /** { ...base, k: v } keeping insertion order. */
    static Map<String, Object> with(Map<String, Object> base, Object... kv) {
        Map<String, Object> out = new LinkedHashMap<>(base);
        for (int i = 0; i < kv.length; i += 2) out.put((String) kv[i], kv[i + 1]);
        return out;
    }

    static Map<String, Object> obj(Object... kv) { return with(new LinkedHashMap<>(), kv); }

    static File goldenFile(String[] args) {
        if (args.length > 0) return new File(args[0]);
        String env = System.getenv("LTX_GOLDEN");
        if (env != null) return new File(env);
        File dir = new File("").getAbsoluteFile();
        while (dir != null) {
            File f = new File(dir, "spec/golden/plan-ids.json");
            if (f.exists()) return f;
            dir = dir.getParentFile();
        }
        return new File("../../spec/golden/plan-ids.json");
    }

    public static void main(String[] args) throws Exception {
        System.out.println("── Conformance: golden planId vectors ───────");
        String text = new String(Files.readAllBytes(goldenFile(args).toPath()), StandardCharsets.UTF_8);
        Map<String, Object> golden = m(LtxJson.parse(text));
        List<Map<String, Object>> vectors = new ArrayList<>();
        for (Object o : (List<?>) golden.get("vectors")) vectors.add(m(o));
        check("golden vectors present", vectors.size() >= 9);
        Map<String, Map<String, Object>> byName = new HashMap<>();
        for (Map<String, Object> gv : vectors) {
            Map<String, Object> plan = m(gv.get("plan"));
            byName.put((String) gv.get("name"), gv);
            check("golden planId " + gv.get("name"), LtxPlans.makePlanId(plan).equals(gv.get("planId")));
            if (gv.containsKey("planHash")) {
                check("golden planHash " + gv.get("name"), LtxPlans.planHash(plan).equals(gv.get("planHash")));
            }
        }
        check("golden v2 freeze anchor", "LTX-20260801-EARTHHQ-MARS-v2-d132e85d".equals(byName.get("v2-freeze-check").get("planId")));
        check("golden v2 unicode anchor", "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8".equals(byName.get("v2-unicode-title").get("planId")));
        check("golden v2 order-sensitive", !byName.get("v2-createPlan-default").get("planId").equals(byName.get("v2-key-order-sensitive").get("planId")));
        check("golden v3 order-insensitive", byName.get("v3-upgrade-delays").get("planId").equals(byName.get("v3-key-order-insensitive").get("planId")));
        check("golden v3 amendment chain hash",
            m(byName.get("v3-amendment").get("plan")).get("prevPlanHash").equals(byName.get("v3-upgrade-delays").get("planHash")));
        check("createPlan default quantum is 5",
            InterplanetLTX.DEFAULT_QUANTUM == 5 && InterplanetLTX.createPlan().quantum == 5);
        check("stringify escapes control chars", LtxJson.stringify("a\u0001\n\"").equals("\"a\\u0001\\n\\\"\""));
        check("stringify lone surrogate escaped", LtxJson.stringify("\ud83d").equals("\"\\ud83d\""));
        check("jsNumber formats", LtxJson.jsNumber(1.5).equals("1.5") && LtxJson.jsNumber(2.0).equals("2")
            && LtxJson.jsNumber(1e21).equals("1e+21") && LtxJson.jsNumber(1e-7).equals("1e-7")
            && LtxJson.jsNumber(0.000001).equals("0.000001"));

        System.out.println("── Plan validation: reserved fields ─────────");
        for (Map<String, Object> gv : vectors) {
            check("validatePlan accepts golden " + gv.get("name"), LtxPlans.validatePlan(gv.get("plan")).valid());
        }
        Map<String, Object> vpBase = m(byName.get("v3-upgrade-delays").get("plan"));
        check("validatePlan v3 empty streams ok", LtxPlans.validatePlan(with(vpBase, "streams", List.of())).valid());
        LtxPlans.Validation vpStreams = LtxPlans.validatePlan(with(vpBase, "streams", List.of(obj("id", "S1"))));
        check("validatePlan non-empty streams", !vpStreams.valid() && codesOf(vpStreams).contains("reserved_streams"));
        check("validatePlan streams error path", vpStreams.errors().stream()
            .filter(e -> e.code().equals("reserved_streams")).findFirst().get().path().equals("streams"));
        check("validatePlan streams non-array", codesOf(LtxPlans.validatePlan(with(vpBase, "streams", "S1"))).contains("reserved_streams"));
        LtxPlans.Validation vpSegStream = LtxPlans.validatePlan(with(vpBase, "segments",
            List.of(obj("type", "TX", "q", 1, "stream", "S1"))));
        check("validatePlan segment stream", codesOf(vpSegStream).contains("reserved_streams"));
        check("validatePlan branches", codesOf(LtxPlans.validatePlan(with(vpBase, "branches", List.of()))).contains("reserved_branching"));
        check("validatePlan branching", codesOf(LtxPlans.validatePlan(with(vpBase, "branching", obj("mode", "local")))).contains("reserved_branching"));
        LtxPlans.Validation vpSegBranch = LtxPlans.validatePlan(with(vpBase, "segments",
            List.of(obj("type", "CAUCUS", "q", 1, "branch", "B1"))));
        check("validatePlan segment branch", codesOf(vpSegBranch).contains("reserved_branching")
            && vpSegBranch.errors().get(0).path().equals("segments[0].branch"));
        Map<String, Object> vpV2 = m(byName.get("v2-freeze-check").get("plan"));
        check("validatePlan v2 streams is v3 field", codesOf(LtxPlans.validatePlan(with(vpV2, "streams", List.of()))).contains("v3_field_in_v2"));
        check("validatePlan v2 branching", codesOf(LtxPlans.validatePlan(with(vpV2, "branching", true))).contains("reserved_branching"));
        check("validatePlan non-object", codesOf(LtxPlans.validatePlan(null)).contains("not_an_object"));
        check("validatePlan bad version", codesOf(LtxPlans.validatePlan(with(vpV2, "v", 7))).contains("invalid_version"));
        List<Object> reversed = new ArrayList<>((List<?>) vpV2.get("nodes"));
        Collections.reverse(reversed);
        check("validatePlan host not first", codesOf(LtxPlans.validatePlan(with(vpV2, "nodes", reversed))).contains("invalid_host"));
        check("validatePlan unsorted delays key", codesOf(LtxPlans.validatePlan(with(vpBase, "delays", obj("N1|N0", 860)))).contains("invalid_delays"));
        check("validatePlan unknown speaker", codesOf(LtxPlans.validatePlan(with(vpV2, "segments",
            List.of(obj("type", "TX", "q", 1, "speaker", "N9"))))).contains("unknown_speaker"));
        check("validatePlan quantum out of range", codesOf(LtxPlans.validatePlan(with(vpV2, "quantum", 0))).contains("invalid_quantum"));
        String code = null;
        try { LtxPlans.assertNoReservedFields(with(vpBase, "branching", obj()), "test"); }
        catch (LtxPlans.PlanException e) { code = e.code; }
        check("assertNoReservedFields throws reserved_branching", "reserved_branching".equals(code));

        System.out.println();
        System.out.println(passed + " passed  " + failed + " failed");
        if (failed > 0) System.exit(1);
    }
}
