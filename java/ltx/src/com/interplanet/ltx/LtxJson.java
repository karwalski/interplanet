package com.interplanet.ltx;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * LtxJson: plain JSON values with JavaScript semantics, for the generic plan
 * layer in {@link LtxPlans}.
 *
 * <p>Values are {@code Map<String,Object>} (LinkedHashMap from {@link #parse},
 * insertion order kept), {@code List<Object>}, String, Long/Integer/Double,
 * Boolean and null. {@link #stringify} matches {@code JSON.stringify} (keys in
 * insertion order) and {@link #canonical} matches ltx-sdk.js
 * {@code canonicalJSON} (keys sorted by UTF-16 code units).
 */
public final class LtxJson {

    private LtxJson() {}

    // ── parse ──────────────────────────────────────────────────────────────

    /**
     * Parse JSON text. Objects become LinkedHashMap, arrays ArrayList,
     * integers Long (Double if they overflow), other numbers Double.
     */
    public static Object parse(String text) {
        Parser p = new Parser(text);
        p.ws();
        Object v = p.value();
        p.ws();
        if (p.i != text.length()) throw new IllegalArgumentException("JSON: trailing characters at " + p.i);
        return v;
    }

    private static final class Parser {
        final String s;
        int i = 0;
        Parser(String s) { this.s = s; }

        void ws() { while (i < s.length() && " \t\r\n".indexOf(s.charAt(i)) >= 0) i++; }

        Object value() {
            if (i >= s.length()) throw new IllegalArgumentException("JSON: unexpected end");
            char c = s.charAt(i);
            switch (c) {
                case '{': return obj();
                case '[': return arr();
                case '"': return str();
                case 't': return lit("true", Boolean.TRUE);
                case 'f': return lit("false", Boolean.FALSE);
                case 'n': return lit("null", null);
                default:  return num();
            }
        }

        Object lit(String word, Object v) {
            if (!s.startsWith(word, i)) throw new IllegalArgumentException("JSON: bad literal at " + i);
            i += word.length();
            return v;
        }

        Map<String, Object> obj() {
            Map<String, Object> m = new LinkedHashMap<>();
            i++; ws();
            if (s.charAt(i) == '}') { i++; return m; }
            while (true) {
                ws();
                String k = str();
                ws();
                if (s.charAt(i) != ':') throw new IllegalArgumentException("JSON: expected ':' at " + i);
                i++; ws();
                m.put(k, value());
                ws();
                char c = s.charAt(i++);
                if (c == '}') return m;
                if (c != ',') throw new IllegalArgumentException("JSON: expected ',' or '}' at " + (i - 1));
            }
        }

        List<Object> arr() {
            List<Object> l = new ArrayList<>();
            i++; ws();
            if (s.charAt(i) == ']') { i++; return l; }
            while (true) {
                ws();
                l.add(value());
                ws();
                char c = s.charAt(i++);
                if (c == ']') return l;
                if (c != ',') throw new IllegalArgumentException("JSON: expected ',' or ']' at " + (i - 1));
            }
        }

        String str() {
            if (s.charAt(i) != '"') throw new IllegalArgumentException("JSON: expected string at " + i);
            i++;
            StringBuilder sb = new StringBuilder();
            while (true) {
                char c = s.charAt(i++);
                if (c == '"') return sb.toString();
                if (c != '\\') { sb.append(c); continue; }
                char e = s.charAt(i++);
                switch (e) {
                    case '"':  sb.append('"'); break;
                    case '\\': sb.append('\\'); break;
                    case '/':  sb.append('/'); break;
                    case 'b':  sb.append('\b'); break;
                    case 'f':  sb.append('\f'); break;
                    case 'n':  sb.append('\n'); break;
                    case 'r':  sb.append('\r'); break;
                    case 't':  sb.append('\t'); break;
                    case 'u':
                        sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                        i += 4;
                        break;
                    default: throw new IllegalArgumentException("JSON: bad escape \\" + e);
                }
            }
        }

        Object num() {
            int start = i;
            if (s.charAt(i) == '-') i++;
            while (i < s.length() && (Character.isDigit(s.charAt(i)) || ".eE+-".indexOf(s.charAt(i)) >= 0)) i++;
            String tok = s.substring(start, i);
            if (tok.isEmpty() || tok.equals("-")) throw new IllegalArgumentException("JSON: bad number at " + start);
            if (tok.indexOf('.') >= 0 || tok.indexOf('e') >= 0 || tok.indexOf('E') >= 0) return Double.parseDouble(tok);
            try { return Long.parseLong(tok); } catch (NumberFormatException ex) { return Double.parseDouble(tok); }
        }
    }

    // ── stringify / canonical ──────────────────────────────────────────────

    /** JSON.stringify(v): insertion-order keys, no whitespace. */
    public static String stringify(Object v) {
        StringBuilder sb = new StringBuilder();
        write(sb, v, false);
        return sb.toString();
    }

    /** canonicalJSON(v) exactly as ltx-sdk.js: keys sorted by UTF-16 code units. */
    public static String canonical(Object v) {
        StringBuilder sb = new StringBuilder();
        write(sb, v, true);
        return sb.toString();
    }

    private static void write(StringBuilder sb, Object v, boolean sorted) {
        if (v == null) { sb.append("null"); return; }
        if (v instanceof Boolean) { sb.append(((Boolean) v) ? "true" : "false"); return; }
        if (v instanceof String) { quote(sb, (String) v); return; }
        if (v instanceof Integer || v instanceof Long || v instanceof Short || v instanceof Byte) {
            sb.append(v.toString()); return;
        }
        if (v instanceof Number) { sb.append(jsNumber(((Number) v).doubleValue())); return; }
        if (v instanceof Map) {
            Map<?, ?> m = (Map<?, ?>) v;
            List<String> keys = new ArrayList<>();
            for (Object k : m.keySet()) keys.add(String.valueOf(k));
            if (sorted) keys.sort(null);
            sb.append('{');
            boolean first = true;
            for (String k : keys) {
                if (!first) sb.append(',');
                first = false;
                quote(sb, k);
                sb.append(':');
                write(sb, m.get(k), sorted);
            }
            sb.append('}');
            return;
        }
        if (v instanceof List) {
            sb.append('[');
            boolean first = true;
            for (Object e : (List<?>) v) {
                if (!first) sb.append(',');
                first = false;
                write(sb, e, sorted);
            }
            sb.append(']');
            return;
        }
        quote(sb, v.toString());
    }

    /** JSON.stringify string quoting (ES2019 well-formed: lone surrogates escaped). */
    public static void quote(StringBuilder sb, String s) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '"') sb.append("\\\"");
            else if (c == '\\') sb.append("\\\\");
            else if (c == '\b') sb.append("\\b");
            else if (c == '\f') sb.append("\\f");
            else if (c == '\n') sb.append("\\n");
            else if (c == '\r') sb.append("\\r");
            else if (c == '\t') sb.append("\\t");
            else if (c < ' ') sb.append(String.format("\\u%04x", (int) c));
            else if (Character.isHighSurrogate(c) && i + 1 < s.length() && Character.isLowSurrogate(s.charAt(i + 1))) {
                sb.append(c).append(s.charAt(i + 1));
                i++;
            }
            else if (Character.isSurrogate(c)) sb.append(String.format("\\u%04x", (int) c));
            else sb.append(c);
        }
        sb.append('"');
    }

    /** ECMAScript Number::toString for finite doubles; NaN/Infinity give "null" as in JSON. */
    public static String jsNumber(double d) {
        if (Double.isNaN(d) || Double.isInfinite(d)) return "null";
        if (d == 0.0) return "0";
        BigDecimal bd = new BigDecimal(Double.toString(d)).stripTrailingZeros();
        boolean neg = bd.signum() < 0;
        String digits = bd.unscaledValue().abs().toString();
        int k = digits.length();
        int n = k - bd.scale(); // value = 0.digits * 10^n
        String body;
        if (n >= k && n <= 21) body = digits + "0".repeat(n - k);
        else if (n >= 1 && n <= 21) body = digits.substring(0, n) + "." + digits.substring(n);
        else if (n >= -5 && n <= 0) body = "0." + "0".repeat(-n) + digits;
        else {
            int e = n - 1;
            String mant = k == 1 ? digits : digits.charAt(0) + "." + digits.substring(1);
            body = mant + "e" + (e >= 0 ? "+" : "-") + Math.abs(e);
        }
        return neg ? "-" + body : body;
    }
}
