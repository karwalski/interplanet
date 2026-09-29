package com.interplanet.ltx;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * LtxPlans: generic (untyped) plan functions mirroring javascript/ltx/ltx-sdk.js.
 *
 * <p>{@link LtxPlan} serialises its fields in a fixed order (nodes before
 * segments), but the frozen v2 planId (LTX-SPECIFICATION.md §4.3) hashes
 * {@code JSON.stringify} of the plan <em>in insertion order</em>, and the
 * golden vectors (spec/golden/plan-ids.json) include plans with arbitrary key
 * order, attributed segments, relay objects and v3 fields. These functions
 * work on plain JSON values from {@link LtxJson#parse}.
 */
public final class LtxPlans {

    private LtxPlans() {}

    /** One validatePlan error: { code, path, message } (LTX-SPECIFICATION.md §4.6). */
    public record PlanError(String code, String path, String message) {}

    /** validatePlan result: { valid, errors }. */
    public record Validation(boolean valid, List<PlanError> errors) {}

    /**
     * Thrown by enforcement points when a plan uses a reserved field.
     * {@link #code} is the first error's code: reserved_streams or reserved_branching.
     */
    public static final class PlanException extends IllegalArgumentException {
        public final String code;
        public final List<PlanError> errors;
        public PlanException(String code, List<PlanError> errors, String message) {
            super(message);
            this.code = code;
            this.errors = errors;
        }
    }

    /** Every segment type the reference SDKs handle (core §3.4 + auxiliary). */
    public static final List<String> PLAN_SEGMENT_TYPES = List.of("PLAN_CONFIRM", "TX", "RX", "CAUCUS",
        "BUFFER", "MERGE", "SPEAK", "REST", "PAD", "OPEN", "RELAY");
    public static final List<String> PLAN_MODES = List.of("LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC");
    /** Fields that exist only in v3 plans (§4.4); MUST NOT appear in v2 (§4.3). */
    public static final List<String> V3_ONLY_FIELDS = List.of("delays", "planVersion", "prevPlanHash",
        "questions", "actions", "streams");
    /** Reserved branching identifiers (§7): MUST be absent from plans and segments. */
    public static final List<String> RESERVED_BRANCH_PLAN_FIELDS = List.of("branches", "branching");
    public static final List<String> RESERVED_BRANCH_SEGMENT_FIELDS = List.of("branch");
    /** Reserved streams identifiers (§3.5): plan streams[] empty, no segment stream. */
    public static final List<String> RESERVED_STREAM_SEGMENT_FIELDS = List.of("stream");

    private static final List<String> NODE_ROLES = List.of("HOST", "PARTICIPANT", "OBSERVER");
    private static final Pattern HEX64 = Pattern.compile("^[0-9a-f]{64}$");

    // ── JS value helpers ───────────────────────────────────────────────────

    private static boolean isNum(Object v) { return v instanceof Number; }
    private static double num(Object v) { return ((Number) v).doubleValue(); }

    /** Number.isInteger */
    private static boolean isInteger(Object v) {
        if (v instanceof Integer || v instanceof Long || v instanceof Short || v instanceof Byte) return true;
        if (v instanceof Double || v instanceof Float) {
            double d = ((Number) v).doubleValue();
            return !Double.isNaN(d) && !Double.isInfinite(d) && d == Math.floor(d);
        }
        return false;
    }

    /** JS strict equality against a number literal. */
    private static boolean numEq(Object v, int n) { return isNum(v) && num(v) == n; }

    /** JS truthiness. */
    private static boolean truthy(Object v) {
        if (v == null) return false;
        if (v instanceof Boolean) return (Boolean) v;
        if (v instanceof String) return !((String) v).isEmpty();
        if (v instanceof Number) { double d = num(v); return d != 0.0 && !Double.isNaN(d); }
        return true;
    }

    private static boolean anyIn(Object v, Collection<String> c) {
        return v instanceof String && c.contains(v);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object v) {
        return v instanceof Map ? (Map<String, Object>) v : null;
    }

    private static List<?> asList(Object v) {
        return v instanceof List ? (List<?>) v : null;
    }

    /** JS \s */
    private static boolean isJsSpace(char c) {
        return "\t\n\u000b\u000c\r       　﻿".indexOf(c) >= 0
            || (c >= ' ' && c <= ' ');
    }

    private static String stripSpaceUpper(String s) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) if (!isJsSpace(s.charAt(i))) sb.append(s.charAt(i));
        return sb.toString().toUpperCase(Locale.ROOT);
    }

    private static String take(String s, int n) { return s.length() > n ? s.substring(0, n) : s; }

    /** Date.parse; null when JS would return NaN (subset: ISO 8601 forms). */
    private static Long parseDateMs(String s) {
        try { return Instant.parse(s).toEpochMilli(); } catch (Exception ignored) {}
        try { return OffsetDateTime.parse(s).toInstant().toEpochMilli(); } catch (Exception ignored) {}
        try { return LocalDate.parse(s).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(); } catch (Exception ignored) {}
        try { return LocalDateTime.parse(s).toInstant(ZoneOffset.UTC).toEpochMilli(); } catch (Exception ignored) {}
        return null;
    }

    // ── upgradeConfig / makePlanId / planHash ──────────────────────────────

    /** upgradeConfig(cfg): v1 to v2 (unchanged for v2/v3 plans with nodes). */
    public static Map<String, Object> upgradeConfig(Map<String, Object> cfg) {
        Object v = cfg.get("v");
        List<?> nodes = asList(cfg.get("nodes"));
        if (isNum(v) && num(v) >= 2 && nodes != null && !nodes.isEmpty()) return cfg;
        String rxName = cfg.get("rxName") instanceof String ? ((String) cfg.get("rxName")).toLowerCase(Locale.ROOT) : "";
        String remoteLoc = rxName.contains("mars") ? "mars" : rxName.contains("moon") ? "moon" : "earth";
        Map<String, Object> n0 = new LinkedHashMap<>();
        n0.put("id", "N0");
        n0.put("name", truthy(cfg.get("txName")) ? cfg.get("txName") : "Earth HQ");
        n0.put("role", "HOST");
        n0.put("delay", 0L);
        n0.put("location", "earth");
        Map<String, Object> n1 = new LinkedHashMap<>();
        n1.put("id", "N1");
        n1.put("name", truthy(cfg.get("rxName")) ? cfg.get("rxName") : "Mars Hab-01");
        n1.put("role", "PARTICIPANT");
        n1.put("delay", truthy(cfg.get("delay")) ? cfg.get("delay") : 0L);
        n1.put("location", remoteLoc);
        Map<String, Object> out = new LinkedHashMap<>(cfg);
        out.put("v", 2L);
        out.put("nodes", List.of(n0, n1));
        return out;
    }

    private static String sha256Hex(String s) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b & 0xff));
            return sb.toString();
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /** SHA-256 hex of the canonical JSON of a plan (prevPlanHash, §6.4). */
    public static String planHash(Map<String, Object> plan) {
        return sha256Hex(LtxJson.canonical(plan));
    }

    /**
     * makePlanId over a plain plan map, exactly as ltx-sdk.js: v2 is the FROZEN
     * imul31 hash of JSON.stringify in insertion order (§4.3); v3 is SHA-256
     * over canonical JSON (§4.5).
     */
    public static String makePlanId(Map<String, Object> cfg) {
        Map<String, Object> c = upgradeConfig(cfg);
        Long startMs = parseDateMs(String.valueOf(c.get("start")));
        if (startMs == null) throw new IllegalArgumentException("makePlanId: invalid start " + c.get("start"));
        String date = Instant.ofEpochMilli(startMs).atOffset(ZoneOffset.UTC).toLocalDate().toString().replace("-", "");
        List<?> nodes = asList(c.get("nodes"));
        if (nodes == null) nodes = List.of();
        Map<String, Object> host = nodes.isEmpty() ? null : asMap(nodes.get(0));
        Object hostName = host == null ? null : host.get("name");
        String hostStr = take(stripSpaceUpper(truthy(hostName) ? hostName.toString() : "HOST"), 8);
        String nodeStr;
        if (nodes.size() > 1) {
            List<String> parts = new ArrayList<>();
            for (int i = 1; i < nodes.size(); i++) {
                parts.add(take(stripSpaceUpper(String.valueOf(asMap(nodes.get(i)).get("name"))), 4));
            }
            nodeStr = take(String.join("-", parts), 16);
        } else {
            nodeStr = "RX";
        }
        Object v = c.get("v");
        if (isNum(v) && num(v) >= 3) {
            return "LTX-" + date + "-" + hostStr + "-" + nodeStr + "-v3-" + planHash(c).substring(0, 8);
        }
        // FROZEN v2 path (LTX-SPECIFICATION.md §4.3): imul31 over UTF-16 code units.
        String raw = LtxJson.stringify(c);
        int h = 0;
        for (int i = 0; i < raw.length(); i++) h = 31 * h + raw.charAt(i);
        return "LTX-" + date + "-" + hostStr + "-" + nodeStr + "-v2-" + String.format("%08x", h);
    }

    // ── validatePlan (§3.5, §4, §7) ────────────────────────────────────────

    /** Reserved-field violations only (§3.5 streams, §7 branching). */
    public static List<PlanError> reservedFieldErrors(Object planValue) {
        List<PlanError> errors = new ArrayList<>();
        Map<String, Object> plan = asMap(planValue);
        if (plan == null) return errors;
        if (plan.containsKey("streams")) {
            List<?> s = asList(plan.get("streams"));
            if (s == null || !s.isEmpty()) {
                errors.add(new PlanError("reserved_streams", "streams",
                    "streams[] is reserved (§3.5) and MUST be absent or empty"));
            }
        }
        for (String f : RESERVED_BRANCH_PLAN_FIELDS) {
            if (plan.containsKey(f)) errors.add(new PlanError("reserved_branching", f,
                f + " is reserved for branching (§7, not yet implemented) and MUST be absent"));
        }
        List<?> segs = asList(plan.get("segments"));
        if (segs != null) {
            for (int i = 0; i < segs.size(); i++) {
                Map<String, Object> s = asMap(segs.get(i));
                if (s == null) continue;
                for (String f : RESERVED_STREAM_SEGMENT_FIELDS) {
                    if (s.containsKey(f)) errors.add(new PlanError("reserved_streams", "segments[" + i + "]." + f,
                        "segment " + f + " is reserved (§3.5) and MUST be absent"));
                }
                for (String f : RESERVED_BRANCH_SEGMENT_FIELDS) {
                    if (s.containsKey(f)) errors.add(new PlanError("reserved_branching", "segments[" + i + "]." + f,
                        "segment " + f + " is reserved for branching (§7) and MUST be absent"));
                }
            }
        }
        return errors;
    }

    /** Throw PlanException (code = first error code) if a plan uses reserved fields. */
    public static void assertNoReservedFields(Object plan, String fnName) {
        List<PlanError> errors = reservedFieldErrors(plan);
        if (errors.isEmpty()) return;
        throw new PlanException(errors.get(0).code(), errors, fnName + ": " + errors.get(0).message());
    }

    /**
     * Validate a v2 or v3 plan against the wire format (spec/ltx-schema.json,
     * LTX-SPECIFICATION.md §4) and the reserved-field rules (§3.5, §7).
     * Pure; never throws. Mirrors ltx-sdk.js validatePlan.
     */
    public static Validation validatePlan(Object planValue) {
        List<PlanError> errors = new ArrayList<>();
        Map<String, Object> plan = asMap(planValue);
        if (plan == null) {
            errors.add(new PlanError("not_an_object", "", "plan must be an object"));
            return new Validation(false, errors);
        }
        Object v = plan.get("v");
        if (!numEq(v, 2) && !numEq(v, 3)) errors.add(new PlanError("invalid_version", "v", "v must be 2 or 3"));
        for (String f : List.of("title", "start", "quantum", "mode", "nodes", "segments")) {
            if (!plan.containsKey(f)) errors.add(new PlanError("missing_field", f, f + " is required"));
        }
        if (plan.containsKey("title") && !(plan.get("title") instanceof String)) {
            errors.add(new PlanError("invalid_field", "title", "title must be a string"));
        }
        if (plan.containsKey("start")) {
            Object s = plan.get("start");
            if (!(s instanceof String) || parseDateMs((String) s) == null) {
                errors.add(new PlanError("invalid_field", "start", "start must be an ISO 8601 UTC timestamp"));
            }
        }
        if (plan.containsKey("quantum")) {
            Object q = plan.get("quantum");
            if (!(isInteger(q) && num(q) >= 1 && num(q) <= 60)) {
                errors.add(new PlanError("invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)"));
            }
        }
        if (plan.containsKey("mode") && !anyIn(plan.get("mode"), PLAN_MODES)) {
            errors.add(new PlanError("invalid_mode", "mode", "mode must be one of " + String.join(", ", PLAN_MODES)));
        }

        Set<String> ids = new LinkedHashSet<>();
        if (plan.containsKey("nodes")) {
            List<?> nodes = asList(plan.get("nodes"));
            if (nodes == null || nodes.isEmpty()) {
                errors.add(new PlanError("invalid_nodes", "nodes", "nodes must be a non-empty array"));
            } else {
                int hosts = 0;
                for (int i = 0; i < nodes.size(); i++) {
                    Map<String, Object> n = asMap(nodes.get(i));
                    Object id = n == null ? null : n.get("id");
                    if (n == null || !(id instanceof String) || ((String) id).isEmpty() || ((String) id).contains("|")
                        || !(n.get("name") instanceof String) || !anyIn(n.get("role"), NODE_ROLES)
                        || !isNum(n.get("delay")) || !(num(n.get("delay")) >= 0)) {
                        errors.add(new PlanError("invalid_nodes", "nodes[" + i + "]",
                            "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0"));
                        continue;
                    }
                    if (ids.contains(id)) errors.add(new PlanError("duplicate_node_id", "nodes[" + i + "].id", "duplicate node id " + id));
                    ids.add((String) id);
                    if ("HOST".equals(n.get("role"))) hosts++;
                }
                Map<String, Object> h = asMap(nodes.get(0));
                if (hosts != 1 || h == null || !"HOST".equals(h.get("role")) || !numEq(h.get("delay"), 0)) {
                    errors.add(new PlanError("invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)"));
                }
            }
        }

        if (plan.containsKey("segments")) {
            List<?> segs = asList(plan.get("segments"));
            if (segs == null) {
                errors.add(new PlanError("invalid_segment", "segments", "segments must be an array"));
            } else {
                for (int i = 0; i < segs.size(); i++) {
                    Map<String, Object> s = asMap(segs.get(i));
                    if (s == null || !anyIn(s.get("type"), PLAN_SEGMENT_TYPES)
                        || !(isInteger(s.get("q")) && num(s.get("q")) >= 1)) {
                        errors.add(new PlanError("invalid_segment", "segments[" + i + "]", "segment needs a known type and integer q >= 1"));
                        continue;
                    }
                    if (s.containsKey("speaker") && !anyIn(s.get("speaker"), ids)) {
                        errors.add(new PlanError("unknown_speaker", "segments[" + i + "].speaker",
                            "speaker " + s.get("speaker") + " is not a node id"));
                    }
                }
            }
        }

        if (numEq(v, 2)) {
            for (String f : V3_ONLY_FIELDS) {
                if (plan.containsKey(f)) errors.add(new PlanError("v3_field_in_v2", f,
                    f + " is a v3 field and MUST NOT appear in a v2 plan (§4.3)"));
            }
        } else if (numEq(v, 3)) {
            if (plan.containsKey("delays")) {
                Map<String, Object> d = asMap(plan.get("delays"));
                if (d == null) {
                    errors.add(new PlanError("invalid_delays", "delays", "delays must be an object"));
                } else {
                    for (Map.Entry<String, Object> e : d.entrySet()) {
                        String k = e.getKey();
                        String[] parts = k.split("\\|", -1);
                        if (parts.length != 2 || parts[0].compareTo(parts[1]) >= 0
                            || (!ids.isEmpty() && (!ids.contains(parts[0]) || !ids.contains(parts[1])))
                            || !isNum(e.getValue()) || !(num(e.getValue()) >= 0)) {
                            errors.add(new PlanError("invalid_delays", "delays." + k,
                                "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)"));
                        }
                    }
                }
            }
            if (plan.containsKey("planVersion")) {
                Object pv = plan.get("planVersion");
                if (!(isInteger(pv) && num(pv) >= 1)) {
                    errors.add(new PlanError("invalid_field", "planVersion", "planVersion must be an integer >= 1"));
                }
            }
            if (plan.containsKey("prevPlanHash")) {
                Object ph = plan.get("prevPlanHash");
                if (!(ph instanceof String && HEX64.matcher((String) ph).matches())) {
                    errors.add(new PlanError("invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters"));
                }
            }
            for (String f : List.of("questions", "actions")) {
                if (plan.containsKey(f) && asList(plan.get(f)) == null) {
                    errors.add(new PlanError("invalid_field", f, f + " must be an array"));
                }
            }
        }

        errors.addAll(reservedFieldErrors(plan));
        return new Validation(errors.isEmpty(), errors);
    }
}
