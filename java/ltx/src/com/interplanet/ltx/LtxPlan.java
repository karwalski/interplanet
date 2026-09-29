package com.interplanet.ltx;

import java.util.*;

/**
 * LtxPlan — an LTX session plan configuration (v2 schema).
 * Story 33.2 — Java LTX library
 *
 * Mutable class (not a record) so it can be built step-by-step and
 * serialised/deserialised to/from JSON without external dependencies.
 */
public final class LtxPlan {

    public int                        v;
    public String                     title;
    public String                     start;
    public int                        quantum;
    public String                     mode;
    public List<LtxNode>              nodes;
    public List<LtxSegmentTemplate>   segments;

    public LtxPlan(int v, String title, String start, int quantum, String mode,
                   List<LtxNode> nodes, List<LtxSegmentTemplate> segments) {
        this.v        = v;
        this.title    = title;
        this.start    = start;
        this.quantum  = quantum;
        this.mode     = mode;
        this.nodes    = nodes    != null ? nodes    : new ArrayList<>();
        this.segments = segments != null ? segments : new ArrayList<>();
    }

    // ── JSON serialisation ─────────────────────────────────────────────────

    /**
     * Serialise this plan to a compact JSON string.
     * Key order matches JavaScript JSON.stringify output for hash compatibility.
     */
    public String toJson() {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"v\":").append(v);
        sb.append(",\"title\":").append(jsonStr(title));
        sb.append(",\"start\":").append(jsonStr(start));
        sb.append(",\"quantum\":").append(quantum);
        sb.append(",\"mode\":").append(jsonStr(mode));
        sb.append(",\"nodes\":[");
        for (int i = 0; i < nodes.size(); i++) {
            if (i > 0) sb.append(",");
            LtxNode n = nodes.get(i);
            sb.append("{\"id\":").append(jsonStr(n.id()))
              .append(",\"name\":").append(jsonStr(n.name()))
              .append(",\"role\":").append(jsonStr(n.role()))
              .append(",\"delay\":").append(n.delay())
              .append(",\"location\":").append(jsonStr(n.location()))
              .append("}");
        }
        sb.append("],\"segments\":[");
        for (int i = 0; i < segments.size(); i++) {
            if (i > 0) sb.append(",");
            LtxSegmentTemplate s = segments.get(i);
            sb.append("{\"type\":").append(jsonStr(s.type()))
              .append(",\"q\":").append(s.q());
            // Attributed segments (§3.4.1): written only when present, in the
            // order ltx-sdk.js writes them (type, q, speaker, label).
            if (s.speaker() != null) sb.append(",\"speaker\":").append(jsonStr(s.speaker()));
            if (s.label()   != null) sb.append(",\"label\":").append(jsonStr(s.label()));
            sb.append("}");
        }
        sb.append("]}");
        return sb.toString();
    }

    /**
     * Quote a string exactly as JSON.stringify does: quote and backslash
     * escaped, \b \f \n \r \t, other control characters and lone surrogates
     * as lowercase \\u00XX / \\uXXXX.
     */
    private static String jsonStr(String s) {
        StringBuilder sb = new StringBuilder();
        LtxJson.quote(sb, s == null ? "" : s);
        return sb.toString();
    }

    // ── JSON deserialisation ───────────────────────────────────────────────

    /**
     * Parse an LtxPlan from a JSON string.
     * Returns null on any parse error.
     */
    public static LtxPlan fromJson(String json) {
        if (json == null || json.isEmpty()) return null;
        try {
            return parseJson(json.trim());
        } catch (Exception e) {
            return null;
        }
    }

    @SuppressWarnings("unchecked")
    private static LtxPlan parseJson(String json) {
        Object root = LtxJson.parse(json);
        if (!(root instanceof Map)) return null;
        Map<String, Object> m = (Map<String, Object>) root;

        List<LtxNode> nodes = new ArrayList<>();
        if (m.get("nodes") instanceof List) {
            for (Object o : (List<Object>) m.get("nodes")) {
                if (!(o instanceof Map)) continue;
                Map<String, Object> n = (Map<String, Object>) o;
                String id = str(n.get("id"));
                if (!id.isEmpty()) {
                    nodes.add(new LtxNode(id, str(n.get("name")), str(n.get("role")),
                                          (int) num(n.get("delay")), str(n.get("location"))));
                }
            }
        }

        List<LtxSegmentTemplate> segs = new ArrayList<>();
        if (m.get("segments") instanceof List) {
            for (Object o : (List<Object>) m.get("segments")) {
                if (!(o instanceof Map)) continue;
                Map<String, Object> sg = (Map<String, Object>) o;
                String type = str(sg.get("type"));
                if (!type.isEmpty()) {
                    Object sp = sg.get("speaker"), lb = sg.get("label");
                    segs.add(new LtxSegmentTemplate(type, (int) num(sg.get("q")),
                        sp instanceof String ? (String) sp : null,
                        lb instanceof String ? (String) lb : null));
                }
            }
        }

        return new LtxPlan((int) num(m.get("v")), str(m.get("title")), str(m.get("start")),
                           (int) num(m.get("quantum")), str(m.get("mode")), nodes, segs);
    }

    private static String str(Object o) { return o instanceof String ? (String) o : ""; }

    private static double num(Object o) { return o instanceof Number ? ((Number) o).doubleValue() : 0; }
}
