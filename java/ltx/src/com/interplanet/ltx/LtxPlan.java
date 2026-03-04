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
              .append(",\"q\":").append(s.q())
              .append("}");
        }
        sb.append("]}");
        return sb.toString();
    }

    /** Escape and quote a string for JSON. */
    private static String jsonStr(String s) {
        if (s == null) return "\"\"";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
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

    private static LtxPlan parseJson(String json) {
        int    v       = (int) numField(json, "v");
        String title   = strField(json, "title");
        String start   = strField(json, "start");
        int    quantum = (int) numField(json, "quantum");
        String mode    = strField(json, "mode");

        List<LtxNode> nodes = new ArrayList<>();
        int nIdx = json.indexOf("\"nodes\"");
        if (nIdx >= 0) {
            int arrOpen  = json.indexOf('[', nIdx);
            int arrClose = findMatchingBracket(json, arrOpen, '[', ']');
            if (arrOpen >= 0 && arrClose > arrOpen) {
                for (String obj : splitObjects(json.substring(arrOpen + 1, arrClose))) {
                    String id  = strField(obj, "id");
                    String nm  = strField(obj, "name");
                    String rl  = strField(obj, "role");
                    int    dl  = (int) numField(obj, "delay");
                    String loc = strField(obj, "location");
                    if (id != null && !id.isEmpty()) {
                        nodes.add(new LtxNode(id, nm, rl, dl, loc));
                    }
                }
            }
        }

        List<LtxSegmentTemplate> segs = new ArrayList<>();
        int sIdx = json.indexOf("\"segments\"");
        if (sIdx >= 0) {
            int arrOpen  = json.indexOf('[', sIdx);
            int arrClose = findMatchingBracket(json, arrOpen, '[', ']');
            if (arrOpen >= 0 && arrClose > arrOpen) {
                for (String obj : splitObjects(json.substring(arrOpen + 1, arrClose))) {
                    String type = strField(obj, "type");
                    int    q    = (int) numField(obj, "q");
                    if (type != null && !type.isEmpty()) {
                        segs.add(new LtxSegmentTemplate(type, q));
                    }
                }
            }
        }

        return new LtxPlan(v, title, start, quantum, mode, nodes, segs);
    }

    /** Extract a quoted string field from JSON. */
    static String strField(String json, String key) {
        String pat = "\"" + key + "\":\"";
        int i = json.indexOf(pat);
        if (i < 0) return "";
        int s = i + pat.length();
        int e = s;
        while (e < json.length() && json.charAt(e) != '"') {
            if (json.charAt(e) == '\\') e++;  // skip escaped char
            e++;
        }
        return json.substring(s, e);
    }

    /** Extract a numeric field from JSON. */
    static double numField(String json, String key) {
        String pat = "\"" + key + "\":";
        int i = json.indexOf(pat);
        if (i < 0) return 0;
        int s = i + pat.length();
        // skip whitespace
        while (s < json.length() && json.charAt(s) == ' ') s++;
        int e = s;
        while (e < json.length() && (Character.isDigit(json.charAt(e))
                || json.charAt(e) == '.' || json.charAt(e) == '-')) {
            e++;
        }
        if (s == e) return 0;
        try { return Double.parseDouble(json.substring(s, e)); }
        catch (NumberFormatException ex) { return 0; }
    }

    /** Find matching closing bracket, tracking depth. */
    private static int findMatchingBracket(String s, int open, char openCh, char closeCh) {
        int depth = 0;
        for (int i = open; i < s.length(); i++) {
            if (s.charAt(i) == openCh)  depth++;
            else if (s.charAt(i) == closeCh) { depth--; if (depth == 0) return i; }
        }
        return -1;
    }

    /** Split a JSON array body into individual object strings. */
    private static List<String> splitObjects(String arr) {
        List<String> result = new ArrayList<>();
        int depth = 0, start = -1;
        for (int i = 0; i < arr.length(); i++) {
            char c = arr.charAt(i);
            if (c == '{') { if (depth == 0) start = i; depth++; }
            else if (c == '}') {
                depth--;
                if (depth == 0 && start >= 0) {
                    result.add(arr.substring(start, i + 1));
                    start = -1;
                }
            }
        }
        return result;
    }
}
