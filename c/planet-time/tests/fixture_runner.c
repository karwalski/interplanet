/**
 * fixture_runner.c -- cross-validates libinterplanet against the shared
 * reference fixtures (fixtures/reference.json, generated from
 * javascript/planet-time/planet-time.js by tests/generate_fixtures.js).
 *
 * Usage: fixture_runner [path/to/reference.json]
 *        (default: fixtures/reference.json relative to the working directory)
 *
 * No external dependencies: a minimal JSON reader is included below. It
 * handles the full JSON grammar used by the fixture file (objects, arrays,
 * strings with escapes, numbers, true/false/null).
 *
 * Checked per entry (same field set as the Zig runner, which is the most
 * complete of the other ports, plus the time strings and MTC):
 *   exact:   hour, minute, second, day_number, day_in_year, year_number,
 *            period_in_week, is_work_period, is_work_hour, time_str,
 *            time_str_full, sol_in_year, sols_per_year (Mars; 0 when null),
 *            mtc.sol/hour/minute/second (Mars)
 *   within:  light_travel_s   +-1.0 s  (Earth to planet; skipped when null)
 *            helio_r_au       +-0.002 AU
 *
 * Exit 0 when every check passes, 1 otherwise.
 */

#include "libinterplanet.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Minimal JSON reader ─────────────────────────────────────────────────── */

typedef enum { JN_NULL, JN_BOOL, JN_NUM, JN_STR, JN_ARR, JN_OBJ } jn_kind_t;

typedef struct jn {
    jn_kind_t   kind;
    double      num;       /* JN_NUM, JN_BOOL (0/1) */
    char       *str;       /* JN_STR */
    char       *key;       /* member name when inside an object */
    struct jn  *child;     /* first element / member (JN_ARR, JN_OBJ) */
    struct jn  *next;      /* next sibling */
} jn_t;

typedef struct { const char *p; const char *end; int err; } jp_t;

static void jp_ws(jp_t *s) {
    while (s->p < s->end && (*s->p == ' ' || *s->p == '\t' || *s->p == '\n' || *s->p == '\r')) s->p++;
}

static jn_t *jn_new(jn_kind_t k) {
    jn_t *n = calloc(1, sizeof(jn_t));
    if (!n) { fprintf(stderr, "out of memory\n"); exit(2); }
    n->kind = k;
    return n;
}

static void jn_free(jn_t *n) {
    while (n) {
        jn_t *nx = n->next;
        jn_free(n->child);
        free(n->str);
        free(n->key);
        free(n);
        n = nx;
    }
}

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void put_utf8(char *o, size_t *n, unsigned cp) {
    if (cp < 0x80) { o[(*n)++] = (char)cp; }
    else if (cp < 0x800) { o[(*n)++] = (char)(0xC0 | (cp >> 6)); o[(*n)++] = (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) {
        o[(*n)++] = (char)(0xE0 | (cp >> 12)); o[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
        o[(*n)++] = (char)(0x80 | (cp & 0x3F));
    } else {
        o[(*n)++] = (char)(0xF0 | (cp >> 18)); o[(*n)++] = (char)(0x80 | ((cp >> 12) & 0x3F));
        o[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F)); o[(*n)++] = (char)(0x80 | (cp & 0x3F));
    }
}

static unsigned jp_hex4(jp_t *s) {
    if (s->end - s->p < 4) { s->err = 1; return 0; }
    unsigned v = 0;
    for (int i = 0; i < 4; i++) {
        int h = hexval(s->p[i]);
        if (h < 0) { s->err = 1; return 0; }
        v = (v << 4) | (unsigned)h;
    }
    s->p += 4;
    return v;
}

static char *jp_string(jp_t *s) {
    if (s->p >= s->end || *s->p != '"') { s->err = 1; return NULL; }
    s->p++;
    size_t cap = (size_t)(s->end - s->p) + 1, n = 0;
    char *o = malloc(cap);
    if (!o) { fprintf(stderr, "out of memory\n"); exit(2); }
    while (s->p < s->end && *s->p != '"') {
        char c = *s->p++;
        if (c != '\\') { o[n++] = c; continue; }
        if (s->p >= s->end) break;
        char e = *s->p++;
        switch (e) {
            case '"': o[n++] = '"'; break;
            case '\\': o[n++] = '\\'; break;
            case '/': o[n++] = '/'; break;
            case 'b': o[n++] = '\b'; break;
            case 'f': o[n++] = '\f'; break;
            case 'n': o[n++] = '\n'; break;
            case 'r': o[n++] = '\r'; break;
            case 't': o[n++] = '\t'; break;
            case 'u': {
                unsigned cp = jp_hex4(s);
                if (cp >= 0xD800 && cp < 0xDC00 && s->end - s->p >= 6 && s->p[0] == '\\' && s->p[1] == 'u') {
                    s->p += 2;
                    unsigned lo = jp_hex4(s);
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                }
                put_utf8(o, &n, cp);
                break;
            }
            default: s->err = 1; break;
        }
    }
    if (s->p >= s->end) { s->err = 1; free(o); return NULL; }
    s->p++; /* closing quote */
    o[n] = '\0';
    return o;
}

static jn_t *jp_value(jp_t *s, int depth);

static jn_t *jp_container(jp_t *s, int depth, int is_obj) {
    jn_t *n = jn_new(is_obj ? JN_OBJ : JN_ARR);
    jn_t **tail = &n->child;
    s->p++; /* [ or { */
    jp_ws(s);
    char close = is_obj ? '}' : ']';
    if (s->p < s->end && *s->p == close) { s->p++; return n; }
    for (;;) {
        char *key = NULL;
        jp_ws(s);
        if (is_obj) {
            key = jp_string(s);
            if (s->err) { free(key); return n; }
            jp_ws(s);
            if (s->p >= s->end || *s->p != ':') { s->err = 1; free(key); return n; }
            s->p++;
        }
        jn_t *v = jp_value(s, depth + 1);
        if (!v) { free(key); return n; }
        v->key = key;
        *tail = v;
        tail = &v->next;
        if (s->err) return n;
        jp_ws(s);
        if (s->p < s->end && *s->p == ',') { s->p++; continue; }
        if (s->p < s->end && *s->p == close) { s->p++; return n; }
        s->err = 1;
        return n;
    }
}

static jn_t *jp_value(jp_t *s, int depth) {
    jp_ws(s);
    if (depth > 64 || s->p >= s->end) { s->err = 1; return NULL; }
    char c = *s->p;
    if (c == '{') return jp_container(s, depth, 1);
    if (c == '[') return jp_container(s, depth, 0);
    if (c == '"') {
        jn_t *n = jn_new(JN_STR);
        n->str = jp_string(s);
        return n;
    }
    if (s->end - s->p >= 4 && strncmp(s->p, "null", 4) == 0) { s->p += 4; return jn_new(JN_NULL); }
    if (s->end - s->p >= 4 && strncmp(s->p, "true", 4) == 0) {
        s->p += 4; jn_t *n = jn_new(JN_BOOL); n->num = 1; return n;
    }
    if (s->end - s->p >= 5 && strncmp(s->p, "false", 5) == 0) {
        s->p += 5; return jn_new(JN_BOOL);
    }
    char *endp = NULL;
    double d = strtod(s->p, &endp);
    if (endp == s->p) { s->err = 1; return NULL; }
    s->p = endp;
    jn_t *n = jn_new(JN_NUM);
    n->num = d;
    return n;
}

static const jn_t *jn_get(const jn_t *obj, const char *key) {
    if (!obj || obj->kind != JN_OBJ) return NULL;
    for (const jn_t *c = obj->child; c; c = c->next)
        if (c->key && strcmp(c->key, key) == 0) return c;
    return NULL;
}

/* ── Checks ──────────────────────────────────────────────────────────────── */

static int g_pass = 0, g_fail = 0;
static char g_tag[96];

static void check_int(const char *field, const jn_t *want, long long got) {
    long long exp = 0;
    if (want && want->kind != JN_NULL) exp = (long long)llround(want->num);
    if (got == exp) { g_pass++; return; }
    g_fail++;
    printf("FAIL %s %s: expected %lld got %lld\n", g_tag, field, exp, got);
}

static void check_str(const char *field, const jn_t *want, const char *got) {
    const char *exp = (want && want->kind == JN_STR) ? want->str : "";
    if (strcmp(exp, got) == 0) { g_pass++; return; }
    g_fail++;
    printf("FAIL %s %s: expected \"%s\" got \"%s\"\n", g_tag, field, exp, got);
}

static void check_near(const char *field, const jn_t *want, double got, double tol) {
    if (!want || want->kind != JN_NUM) return; /* null: not applicable */
    if (fabs(got - want->num) <= tol) { g_pass++; return; }
    g_fail++;
    printf("FAIL %s %s: expected %.6f got %.6f (tol %g)\n", g_tag, field, want->num, got, tol);
}

static const char *PLANET_NAMES[] = {
    "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "moon"
};

static int planet_from_name(const char *s) {
    for (int i = 0; i < 9; i++)
        if (strcmp(PLANET_NAMES[i], s) == 0) return i;
    return -1;
}

static void run_entry(const jn_t *e, int idx) {
    const jn_t *pn = jn_get(e, "planet");
    const jn_t *um = jn_get(e, "utc_ms");
    if (!pn || pn->kind != JN_STR || !um || um->kind != JN_NUM) {
        g_fail++;
        printf("FAIL entry[%d]: missing planet/utc_ms\n", idx);
        return;
    }
    int pi = planet_from_name(pn->str);
    int64_t utc_ms = (int64_t)llround(um->num);
    snprintf(g_tag, sizeof(g_tag), "entry[%d] %s@%lld", idx, pn->str, (long long)utc_ms);
    if (pi < 0) {
        g_fail++;
        printf("FAIL %s: unknown planet\n", g_tag);
        return;
    }
    ipt_planet_t p = (ipt_planet_t)pi;

    ipt_planet_time_t pt;
    if (ipt_get_planet_time(p, utc_ms, 0, &pt) != 0) {
        g_fail++;
        printf("FAIL %s: ipt_get_planet_time returned error\n", g_tag);
        return;
    }
    check_int("hour",           jn_get(e, "hour"),           pt.hour);
    check_int("minute",         jn_get(e, "minute"),         pt.minute);
    check_int("second",         jn_get(e, "second"),         pt.second);
    check_int("day_number",     jn_get(e, "day_number"),     pt.day_number);
    check_int("day_in_year",    jn_get(e, "day_in_year"),    pt.day_in_year);
    check_int("year_number",    jn_get(e, "year_number"),    pt.year_number);
    check_int("period_in_week", jn_get(e, "period_in_week"), pt.period_in_week);
    check_int("is_work_period", jn_get(e, "is_work_period"), pt.is_work_period);
    check_int("is_work_hour",   jn_get(e, "is_work_hour"),   pt.is_work_hour);
    check_str("time_str",       jn_get(e, "time_str"),       pt.time_str);
    check_str("time_str_full",  jn_get(e, "time_str_full"),  pt.time_str_full);
    /* Mars only; the C struct reports 0 where the reference has null. */
    check_int("sol_in_year",    jn_get(e, "sol_in_year"),    pt.sol_in_year);
    check_int("sols_per_year",  jn_get(e, "sols_per_year"),  pt.sols_per_year);

    const jn_t *mtc = jn_get(e, "mtc");
    if (mtc && mtc->kind == JN_OBJ) {
        ipt_mtc_t m;
        if (ipt_get_mtc(utc_ms, &m) != 0) {
            g_fail++;
            printf("FAIL %s: ipt_get_mtc returned error\n", g_tag);
        } else {
            check_int("mtc.sol",    jn_get(mtc, "sol"),    m.sol);
            check_int("mtc.hour",   jn_get(mtc, "hour"),   m.hour);
            check_int("mtc.minute", jn_get(mtc, "minute"), m.minute);
            check_int("mtc.second", jn_get(mtc, "second"), m.second);
        }
    }

    check_near("light_travel_s", jn_get(e, "light_travel_s"),
               ipt_light_travel_s(IPT_EARTH, p, utc_ms), 1.0);

    ipt_helio_t h;
    if (ipt_helio_pos(p, utc_ms, &h) != 0) {
        g_fail++;
        printf("FAIL %s: ipt_helio_pos returned error\n", g_tag);
    } else {
        check_near("helio_r_au", jn_get(e, "helio_r_au"), h.r, 0.002);
    }
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "fixtures/reference.json";
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "Cannot open fixture file: %s\n", path);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); fprintf(stderr, "Empty fixture file: %s\n", path); return 1; }
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); fprintf(stderr, "out of memory\n"); return 2; }
    size_t got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[got] = '\0';

    jp_t s = { buf, buf + got, 0 };
    jn_t *root = jp_value(&s, 0);
    if (s.err || !root || root->kind != JN_OBJ) {
        fprintf(stderr, "Failed to parse fixture JSON: %s\n", path);
        jn_free(root);
        free(buf);
        return 1;
    }
    const jn_t *entries = jn_get(root, "entries");
    if (!entries || entries->kind != JN_ARR) {
        fprintf(stderr, "Fixture has no \"entries\" array: %s\n", path);
        jn_free(root);
        free(buf);
        return 1;
    }

    printf("libinterplanet C fixture runner\nFixture: %s\n", path);
    int count = 0;
    for (const jn_t *e = entries->child; e; e = e->next) run_entry(e, count++);

    const jn_t *ec = jn_get(root, "entry_count");
    if (ec && ec->kind == JN_NUM && (int)ec->num != count) {
        g_fail++;
        printf("FAIL entry_count: header says %d, file has %d\n", (int)ec->num, count);
    }

    printf("Fixture entries checked: %d\n", count);
    printf("%d passed  %d failed\n", g_pass, g_fail);
    jn_free(root);
    free(buf);
    return (g_fail > 0 || count == 0) ? 1 : 0;
}
