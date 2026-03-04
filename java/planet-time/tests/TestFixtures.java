import com.interplanet.time.*;
import java.nio.file.*;
import java.util.regex.*;

/**
 * TestFixtures — cross-language fixture validation for the Java library.
 * Reads libinterplanet/fixtures/reference.json and checks Java results match.
 * Story 18.2
 */
public class TestFixtures {

    static int passed = 0;
    static int failed = 0;

    static void check(String name, boolean cond) {
        if (cond) { passed++; }
        else { failed++; System.out.println("FAIL: " + name); }
    }

    static void checkApprox(String name, double actual, double expected, double delta) {
        boolean ok = Math.abs(actual - expected) <= delta;
        if (ok) { passed++; }
        else { failed++; System.out.printf("FAIL: %s — expected %.3f, got %.3f%n", name, expected, actual); }
    }

    // Extract a string-valued field from an entry block, e.g. "planet": "mars"
    static String extractStr(String block, String field) {
        Pattern p = Pattern.compile("\"" + field + "\"\\s*:\\s*\"(\\w+)\"");
        Matcher m = p.matcher(block);
        return m.find() ? m.group(1) : null;
    }

    // Extract a long-valued field from an entry block, e.g. "utc_ms": 946728000000
    static Long extractLong(String block, String field) {
        Pattern p = Pattern.compile("\"" + field + "\"\\s*:\\s*(-?\\d+)");
        Matcher m = p.matcher(block);
        return m.find() ? Long.parseLong(m.group(1)) : null;
    }

    // Extract a double-valued field from an entry block, e.g. "light_travel_s": 706.75
    // Returns null if the field is absent or its value is "null".
    static Double extractDouble(String block, String field) {
        Pattern p = Pattern.compile("\"" + field + "\"\\s*:\\s*([\\d.eE+\\-]+)");
        Matcher m = p.matcher(block);
        return m.find() ? Double.parseDouble(m.group(1)) : null;
    }

    public static void main(String[] args) throws Exception {
        // Locate reference.json — passed as arg[0] or falls back to sibling directory
        String jsonPath = args.length > 0 ? args[0]
            : "../c/fixtures/reference.json";

        Path p = Path.of(jsonPath).toAbsolutePath().normalize();
        if (!Files.exists(p)) {
            System.out.println("SKIP: fixture file not found at " + p);
            System.out.println("0 passed  0 failed  (fixtures skipped)");
            return;
        }

        String json = Files.readString(p);

        // Find the "entries" array content
        int entriesStart = json.indexOf("\"entries\"");
        if (entriesStart < 0) {
            System.out.println("FAIL: no 'entries' key in fixture file");
            System.exit(1);
        }

        // Extract each entry block: matches { ... } at the top-level entries array depth
        // Each entry block begins with optional whitespace + '{' and ends with '}'
        // Allow one level of nested {} (e.g. "mtc": {...} in Mars entries)
        Pattern blockPat = Pattern.compile(
            "\\{(?:[^{}]|\\{[^{}]*\\})*\"utc_ms\"(?:[^{}]|\\{[^{}]*\\})*\\}",
            Pattern.DOTALL
        );
        Matcher m = blockPat.matcher(json.substring(entriesStart));
        int count = 0;

        while (m.find()) {
            String block = m.group();

            Long   utcMs   = extractLong(block, "utc_ms");
            String pName   = extractStr(block, "planet");
            Long   expHour = extractLong(block, "hour");
            Long   expMin  = extractLong(block, "minute");
            Double lt      = extractDouble(block, "light_travel_s");

            if (utcMs == null || pName == null || expHour == null || expMin == null) continue;

            Planet planet = Planet.fromString(pName);
            if (planet == null) continue;

            PlanetTime pt = InterplanetTime.getPlanetTime(planet, utcMs);
            String tag    = pName + "@" + utcMs;

            check(tag + " hour=" + expHour, pt.hour() == expHour.intValue());
            check(tag + " minute=" + expMin, pt.minute() == expMin.intValue());

            if (lt != null && planet != Planet.EARTH && planet != Planet.MOON) {
                double actLt = InterplanetTime.lightTravelSeconds(Planet.EARTH, planet, utcMs);
                checkApprox(tag + " lightTravel", actLt, lt, 2.0);
            }

            count++;
        }

        System.out.printf("Fixture entries checked: %d%n", count);
        System.out.printf("%d passed  %d failed%n", passed, failed);

        if (failed > 0) System.exit(1);
    }
}
