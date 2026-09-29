/**
 * itx_plan_json.c -- wire-format plan helpers for libitx (C99, no deps).
 *
 * Mirrors javascript/ltx/ltx-sdk.js:
 *   - itx_json_parse: JSON.parse with key insertion order kept
 *   - itx_json_stringify / itx_json_canonical: JSON.stringify and the SDK's
 *     canonicalJSON (keys sorted by UTF-16 code units, RFC 8785 order)
 *   - itx_make_plan_id_json / itx_plan_hash_json: makePlanId / planHash over
 *     the plan as received (the frozen v2 hash is insertion-order sensitive)
 *   - itx_validate_plan_json: validatePlan, including reserved_streams and
 *     reserved_branching (LTX-SPECIFICATION.md 3.5, 4, 7)
 *   - itx_sha256
 *
 * Golden vectors: spec/golden/plan-ids.json (tests/test_plan_json.c).
 */

#include "../include/libitx.h"

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── JSON tree ───────────────────────────────────────────────────────────── */

struct itx_json {
    itx_json_kind_t    kind;
    double             num;
    char              *str;    /* ITX_JSON_STRING (UTF-8, NUL-terminated) */
    char              *key;    /* member name inside an object */
    struct itx_json   *child;  /* first element / member */
    struct itx_json   *next;
    size_t             count;  /* elements / members */
};

static itx_json_t *jnew(itx_json_kind_t k) {
    itx_json_t *n = (itx_json_t *)calloc(1, sizeof(itx_json_t));
    if (n) n->kind = k;
    return n;
}

void itx_json_free(itx_json_t *n) {
    while (n) {
        itx_json_t *nx = n->next;
        itx_json_free(n->child);
        free(n->str);
        free(n->key);
        free(n);
        n = nx;
    }
}

typedef struct { const char *p; const char *end; int err; int depth; } jparser_t;

static void jws(jparser_t *s) {
    while (s->p < s->end && (*s->p == ' ' || *s->p == '\t' || *s->p == '\n' || *s->p == '\r')) s->p++;
}

static int hexv(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static unsigned jhex4(jparser_t *s) {
    unsigned v = 0;
    if (s->end - s->p < 4) { s->err = 1; return 0; }
    for (int i = 0; i < 4; i++) {
        int h = hexv(s->p[i]);
        if (h < 0) { s->err = 1; return 0; }
        v = (v << 4) | (unsigned)h;
    }
    s->p += 4;
    return v;
}

static void put_utf8(char *o, size_t *n, unsigned cp) {
    if (cp < 0x80) o[(*n)++] = (char)cp;
    else if (cp < 0x800) { o[(*n)++] = (char)(0xC0 | (cp >> 6)); o[(*n)++] = (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) {
        o[(*n)++] = (char)(0xE0 | (cp >> 12)); o[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
        o[(*n)++] = (char)(0x80 | (cp & 0x3F));
    } else {
        o[(*n)++] = (char)(0xF0 | (cp >> 18)); o[(*n)++] = (char)(0x80 | ((cp >> 12) & 0x3F));
        o[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F)); o[(*n)++] = (char)(0x80 | (cp & 0x3F));
    }
}

static char *jstring(jparser_t *s) {
    if (s->p >= s->end || *s->p != '"') { s->err = 1; return NULL; }
    s->p++;
    size_t cap = (size_t)(s->end - s->p) + 4, n = 0;
    char *o = (char *)malloc(cap);
    if (!o) { s->err = 1; return NULL; }
    while (s->p < s->end && *s->p != '"') {
        char c = *s->p++;
        if ((unsigned char)c < 0x20) { s->err = 1; break; }
        if (c != '\\') { o[n++] = c; continue; }
        if (s->p >= s->end) { s->err = 1; break; }
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
                unsigned cp = jhex4(s);
                if (cp >= 0xD800 && cp < 0xDC00 && s->end - s->p >= 6 && s->p[0] == '\\' && s->p[1] == 'u') {
                    s->p += 2;
                    unsigned lo = jhex4(s);
                    cp = 0x10000 + ((cp - 0xD800) << 10) + ((lo - 0xDC00) & 0x3FF);
                }
                put_utf8(o, &n, cp);
                break;
            }
            default: s->err = 1; break;
        }
    }
    if (s->err || s->p >= s->end) { s->err = 1; free(o); return NULL; }
    s->p++;
    o[n] = '\0';
    return o;
}

static itx_json_t *jvalue(jparser_t *s);

static itx_json_t *jfind_member(itx_json_t *obj, const char *key) {
    for (itx_json_t *c = obj->child; c; c = c->next)
        if (strcmp(c->key, key) == 0) return c;
    return NULL;
}

static itx_json_t *jcontainer(jparser_t *s, int is_obj) {
    itx_json_t *n = jnew(is_obj ? ITX_JSON_OBJECT : ITX_JSON_ARRAY);
    if (!n) { s->err = 1; return NULL; }
    itx_json_t **tail = &n->child;
    char close = is_obj ? '}' : ']';
    s->p++;
    s->depth++;
    jws(s);
    if (s->p < s->end && *s->p == close) { s->p++; s->depth--; return n; }
    for (;;) {
        char *key = NULL;
        jws(s);
        if (is_obj) {
            key = jstring(s);
            if (s->err) return n;
            jws(s);
            if (s->p >= s->end || *s->p != ':') { s->err = 1; free(key); return n; }
            s->p++;
        }
        itx_json_t *v = jvalue(s);
        if (!v) { free(key); s->err = 1; return n; }
        itx_json_t *dup = is_obj ? jfind_member(n, key) : NULL;
        if (dup) {
            /* JSON.parse: a duplicate key keeps its position, last value wins */
            itx_json_t *keep_next = dup->next;
            char *keep_key = dup->key;
            itx_json_free(dup->child);
            free(dup->str);
            v->key = keep_key;
            *dup = *v;
            dup->next = keep_next;
            v->child = NULL; v->str = NULL; v->key = NULL; v->next = NULL;
            itx_json_free(v);
            free(key);
        } else {
            v->key = key;
            *tail = v;
            tail = &v->next;
            n->count++;
        }
        if (s->err) return n;
        jws(s);
        if (s->p < s->end && *s->p == ',') { s->p++; continue; }
        if (s->p < s->end && *s->p == close) { s->p++; s->depth--; return n; }
        s->err = 1;
        return n;
    }
}

static itx_json_t *jvalue(jparser_t *s) {
    jws(s);
    if (s->depth > 128 || s->p >= s->end) { s->err = 1; return NULL; }
    char c = *s->p;
    if (c == '{') return jcontainer(s, 1);
    if (c == '[') return jcontainer(s, 0);
    if (c == '"') {
        itx_json_t *n = jnew(ITX_JSON_STRING);
        if (!n) { s->err = 1; return NULL; }
        n->str = jstring(s);
        return n;
    }
    if (s->end - s->p >= 4 && strncmp(s->p, "null", 4) == 0) { s->p += 4; return jnew(ITX_JSON_NULL); }
    if (s->end - s->p >= 4 && strncmp(s->p, "true", 4) == 0) {
        s->p += 4;
        itx_json_t *n = jnew(ITX_JSON_BOOL);
        if (n) n->num = 1;
        return n;
    }
    if (s->end - s->p >= 5 && strncmp(s->p, "false", 5) == 0) { s->p += 5; return jnew(ITX_JSON_BOOL); }
    if (c == '-' || (c >= '0' && c <= '9')) {
        char *endp = NULL;
        double d = strtod(s->p, &endp);
        if (endp == s->p) { s->err = 1; return NULL; }
        s->p = endp;
        itx_json_t *n = jnew(ITX_JSON_NUMBER);
        if (n) n->num = d;
        return n;
    }
    s->err = 1;
    return NULL;
}

itx_json_t *itx_json_parse(const char *text) {
    if (!text) return NULL;
    jparser_t s = { text, text + strlen(text), 0, 0 };
    itx_json_t *v = jvalue(&s);
    jws(&s);
    if (s.err || !v || s.p != s.end) { itx_json_free(v); return NULL; }
    return v;
}

itx_json_kind_t itx_json_kind(const itx_json_t *v) { return v ? v->kind : ITX_JSON_NULL; }

const itx_json_t *itx_json_get(const itx_json_t *obj, const char *key) {
    if (!obj || obj->kind != ITX_JSON_OBJECT || !key) return NULL;
    for (const itx_json_t *c = obj->child; c; c = c->next)
        if (strcmp(c->key, key) == 0) return c;
    return NULL;
}

size_t itx_json_len(const itx_json_t *v) {
    return (v && (v->kind == ITX_JSON_ARRAY || v->kind == ITX_JSON_OBJECT)) ? v->count : 0;
}

const itx_json_t *itx_json_at(const itx_json_t *arr, size_t i) {
    if (!arr || (arr->kind != ITX_JSON_ARRAY && arr->kind != ITX_JSON_OBJECT)) return NULL;
    const itx_json_t *c = arr->child;
    while (c && i--) c = c->next;
    return c;
}

const char *itx_json_key(const itx_json_t *member) { return member ? member->key : NULL; }

const char *itx_json_str(const itx_json_t *v) {
    return (v && v->kind == ITX_JSON_STRING) ? v->str : NULL;
}

int itx_json_num(const itx_json_t *v, double *out) {
    if (!v || v->kind != ITX_JSON_NUMBER) return 0;
    if (out) *out = v->num;
    return 1;
}

/* ── String builder ──────────────────────────────────────────────────────── */

typedef struct { char *b; size_t n, cap; int err; } sb_t;

static void sb_putn(sb_t *s, const char *p, size_t n) {
    if (s->err) return;
    if (s->n + n + 1 > s->cap) {
        size_t nc = s->cap ? s->cap * 2 : 256;
        while (nc < s->n + n + 1) nc *= 2;
        char *nb = (char *)realloc(s->b, nc);
        if (!nb) { s->err = 1; return; }
        s->b = nb; s->cap = nc;
    }
    memcpy(s->b + s->n, p, n);
    s->n += n;
    s->b[s->n] = '\0';
}

static void sb_puts(sb_t *s, const char *p) { sb_putn(s, p, strlen(p)); }
static void sb_putc(sb_t *s, char c) { sb_putn(s, &c, 1); }

/* ── JavaScript-compatible serialisation ─────────────────────────────────── */

/** Number.prototype.toString (also the RFC 8785 number form). */
static void js_number(sb_t *s, double f) {
    char tmp[64], digits[32];
    if (!isfinite(f)) { sb_puts(s, "null"); return; }
    if (f == 0) { sb_putc(s, '0'); return; }
    if (f < 0) { sb_putc(s, '-'); f = -f; }
    int p;
    for (p = 1; p <= 17; p++) {
        snprintf(tmp, sizeof(tmp), "%.*e", p - 1, f);
        if (strtod(tmp, NULL) == f) break;
    }
    char *e = strchr(tmp, 'e');
    int exp = atoi(e + 1);
    int k = 0;
    for (char *q = tmp; q < e; q++) if (*q != '.') digits[k++] = *q;
    while (k > 1 && digits[k - 1] == '0') k--;
    digits[k] = '\0';
    int n = exp + 1;
    if (k <= n && n <= 21) {
        sb_puts(s, digits);
        for (int i = 0; i < n - k; i++) sb_putc(s, '0');
    } else if (0 < n && n <= 21) {
        sb_putn(s, digits, (size_t)n);
        sb_putc(s, '.');
        sb_puts(s, digits + n);
    } else if (-6 < n && n <= 0) {
        sb_puts(s, "0.");
        for (int i = 0; i < -n; i++) sb_putc(s, '0');
        sb_puts(s, digits);
    } else {
        sb_putc(s, digits[0]);
        if (k > 1) { sb_putc(s, '.'); sb_puts(s, digits + 1); }
        snprintf(tmp, sizeof(tmp), "e%c%d", n - 1 < 0 ? '-' : '+', abs(n - 1));
        sb_puts(s, tmp);
    }
}

/** JSON.stringify string quoting. */
static void js_quote(sb_t *s, const char *str) {
    sb_putc(s, '"');
    for (const unsigned char *p = (const unsigned char *)str; *p; p++) {
        switch (*p) {
            case '"':  sb_puts(s, "\\\""); break;
            case '\\': sb_puts(s, "\\\\"); break;
            case '\b': sb_puts(s, "\\b"); break;
            case '\f': sb_puts(s, "\\f"); break;
            case '\n': sb_puts(s, "\\n"); break;
            case '\r': sb_puts(s, "\\r"); break;
            case '\t': sb_puts(s, "\\t"); break;
            default:
                if (*p < 0x20) {
                    char u[8];
                    snprintf(u, sizeof(u), "\\u%04x", *p);
                    sb_puts(s, u);
                } else {
                    sb_putc(s, (char)*p);
                }
        }
    }
    sb_putc(s, '"');
}

/** Decode one UTF-8 code point; advances *p. Invalid bytes decode as themselves. */
static unsigned utf8_next(const unsigned char **p) {
    const unsigned char *q = *p;
    unsigned c = *q;
    int len = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 1;
    unsigned cp = len == 1 ? c : len == 2 ? (c & 0x1F) : len == 3 ? (c & 0x0F) : (c & 0x07);
    for (int i = 1; i < len; i++) {
        if ((q[i] & 0xC0) != 0x80) { *p = q + 1; return c; }
        cp = (cp << 6) | (q[i] & 0x3F);
    }
    *p = q + len;
    return cp;
}

/** UTF-16 code units of a code point; returns the unit count (1 or 2). */
static int utf16_units(unsigned cp, unsigned u[2]) {
    if (cp < 0x10000) { u[0] = cp; u[1] = 0; return 1; }
    cp -= 0x10000;
    u[0] = 0xD800 + (cp >> 10);
    u[1] = 0xDC00 + (cp & 0x3FF);
    return 2;
}

/** Compare UTF-8 strings by UTF-16 code units (Array.prototype.sort). */
static int utf16_cmp(const char *a, const char *b) {
    const unsigned char *pa = (const unsigned char *)a, *pb = (const unsigned char *)b;
    while (*pa && *pb) {
        unsigned ca = utf8_next(&pa), cb = utf8_next(&pb);
        if (ca == cb) continue;
        unsigned ua[2], ub[2];
        utf16_units(ca, ua);
        utf16_units(cb, ub);
        if (ua[0] != ub[0]) return ua[0] < ub[0] ? -1 : 1;
        return ua[1] < ub[1] ? -1 : 1;
    }
    return (*pa != 0) - (*pb != 0);
}

static int member_cmp(const void *x, const void *y) {
    const itx_json_t *a = *(const itx_json_t *const *)x;
    const itx_json_t *b = *(const itx_json_t *const *)y;
    return utf16_cmp(a->key, b->key);
}

static void serialize(sb_t *s, const itx_json_t *v, int canonical) {
    switch (v->kind) {
        case ITX_JSON_NULL: sb_puts(s, "null"); break;
        case ITX_JSON_BOOL: sb_puts(s, v->num != 0 ? "true" : "false"); break;
        case ITX_JSON_NUMBER: js_number(s, v->num); break;
        case ITX_JSON_STRING: js_quote(s, v->str); break;
        case ITX_JSON_ARRAY:
            sb_putc(s, '[');
            for (const itx_json_t *c = v->child; c; c = c->next) {
                if (c != v->child) sb_putc(s, ',');
                serialize(s, c, canonical);
            }
            sb_putc(s, ']');
            break;
        case ITX_JSON_OBJECT: {
            size_t n = v->count, i = 0;
            const itx_json_t **m = (const itx_json_t **)malloc((n ? n : 1) * sizeof(*m));
            if (!m) { s->err = 1; return; }
            for (const itx_json_t *c = v->child; c; c = c->next) m[i++] = c;
            if (canonical && n > 1) qsort(m, n, sizeof(*m), member_cmp);
            sb_putc(s, '{');
            for (i = 0; i < n; i++) {
                if (i) sb_putc(s, ',');
                js_quote(s, m[i]->key);
                sb_putc(s, ':');
                serialize(s, m[i], canonical);
            }
            sb_putc(s, '}');
            free(m);
            break;
        }
    }
}

char *itx_json_stringify(const itx_json_t *v) {
    if (!v) return NULL;
    sb_t s = { NULL, 0, 0, 0 };
    serialize(&s, v, 0);
    if (s.err) { free(s.b); return NULL; }
    return s.b;
}

char *itx_json_canonical(const itx_json_t *v) {
    if (!v) return NULL;
    sb_t s = { NULL, 0, 0, 0 };
    serialize(&s, v, 1);
    if (s.err) { free(s.b); return NULL; }
    return s.b;
}

char *itx_canonical_json(const char *json) {
    itx_json_t *v = itx_json_parse(json);
    char *out = itx_json_canonical(v);
    itx_json_free(v);
    return out;
}

unsigned int itx_imul31_utf16(const char *s) {
    uint32_t h = 0;
    const unsigned char *p = (const unsigned char *)s;
    while (*p) {
        unsigned u[2];
        int n = utf16_units(utf8_next(&p), u);
        for (int i = 0; i < n; i++) h = h * 31u + (uint32_t)u[i];
    }
    return (unsigned int)h;
}

/* ── SHA-256 (FIPS 180-4) ────────────────────────────────────────────────── */

static const uint32_t K256[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void sha256_block(uint32_t h[8], const unsigned char *b) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
        w[i] = ((uint32_t)b[i*4] << 24) | ((uint32_t)b[i*4+1] << 16) | ((uint32_t)b[i*4+2] << 8) | b[i*4+3];
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ROR(w[i-15], 7) ^ ROR(w[i-15], 18) ^ (w[i-15] >> 3);
        uint32_t s1 = ROR(w[i-2], 17) ^ ROR(w[i-2], 19) ^ (w[i-2] >> 10);
        w[i] = w[i-16] + s0 + w[i-7] + s1;
    }
    uint32_t a = h[0], bb = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = hh + S1 + ch + K256[i] + w[i];
        uint32_t S0 = ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22);
        uint32_t mj = (a & bb) ^ (a & c) ^ (bb & c);
        uint32_t t2 = S0 + mj;
        hh = g; g = f; f = e; e = d + t1; d = c; c = bb; bb = a; a = t1 + t2;
    }
    h[0] += a; h[1] += bb; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

void itx_sha256(const void *data, size_t len, unsigned char out[32]) {
    uint32_t h[8] = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 };
    const unsigned char *p = (const unsigned char *)data;
    size_t rem = len;
    while (rem >= 64) { sha256_block(h, p); p += 64; rem -= 64; }
    unsigned char last[128];
    memset(last, 0, sizeof(last));
    memcpy(last, p, rem);
    last[rem] = 0x80;
    size_t total = rem + 1 + 8 <= 64 ? 64 : 128;
    uint64_t bits = (uint64_t)len * 8u;
    for (int i = 0; i < 8; i++) last[total - 1 - i] = (unsigned char)(bits >> (8 * i));
    sha256_block(h, last);
    if (total == 128) sha256_block(h, last + 64);
    for (int i = 0; i < 8; i++) {
        out[i*4]   = (unsigned char)(h[i] >> 24);
        out[i*4+1] = (unsigned char)(h[i] >> 16);
        out[i*4+2] = (unsigned char)(h[i] >> 8);
        out[i*4+3] = (unsigned char)(h[i]);
    }
}

static void hex_of(const unsigned char *b, size_t n, char *out) {
    static const char hx[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) { out[i*2] = hx[b[i] >> 4]; out[i*2+1] = hx[b[i] & 15]; }
    out[n * 2] = '\0';
}

/* ── makePlanId / planHash over the wire plan ────────────────────────────── */

static int all_digits(const char *s, int a, int n) {
    for (int i = a; i < a + n; i++) if (s[i] < '0' || s[i] > '9') return 0;
    return 1;
}

static int num_at(const char *s, int a, int n) {
    int v = 0;
    for (int i = a; i < a + n; i++) v = v * 10 + (s[i] - '0');
    return v;
}

static long long days_from_civil(long long y, long long m, long long d) {
    y -= m <= 2;
    long long era = (y >= 0 ? y : y - 399) / 400;
    long long yoe = y - era * 400;
    long long doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
    long long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

/**
 * Parse the ISO 8601 forms Date.parse accepts for a plan start (YYYY-MM-DD,
 * or YYYY-MM-DDTHH:MM[:SS[.sss]] with Z or +-HH:MM) to UTC epoch ms.
 * Returns 0 on success, -1 if s is not such a timestamp.
 */
static int parse_js_date(const char *s, long long *out_ms) {
    size_t len = strlen(s);
    if (len < 10 || !all_digits(s, 0, 4) || s[4] != '-' || !all_digits(s, 5, 2) || s[7] != '-' || !all_digits(s, 8, 2))
        return -1;
    int mo = num_at(s, 5, 2), d = num_at(s, 8, 2);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return -1;
    long long ms = days_from_civil(num_at(s, 0, 4), mo, d) * 86400000LL;
    if (len == 10) { *out_ms = ms; return 0; }
    if (s[10] != 'T' || len < 16 || !all_digits(s, 11, 2) || s[13] != ':' || !all_digits(s, 14, 2)) return -1;
    int h = num_at(s, 11, 2), mi = num_at(s, 14, 2), sec = 0, frac = 0;
    size_t pos = 16;
    if (pos < len && s[pos] == ':') {
        if (pos + 3 > len || !all_digits(s, (int)pos + 1, 2)) return -1;
        sec = num_at(s, (int)pos + 1, 2);
        pos += 3;
        if (pos < len && s[pos] == '.') {
            size_t st = ++pos;
            int digits = 0;
            while (pos < len && s[pos] >= '0' && s[pos] <= '9') {
                if (digits < 3) { frac = frac * 10 + (s[pos] - '0'); digits++; }
                pos++;
            }
            if (pos == st) return -1;
            while (digits < 3) { frac *= 10; digits++; }
        }
    }
    if (h > 24 || mi > 59 || sec > 59) return -1;
    long long off = 0;
    if (pos + 1 == len && s[pos] == 'Z') off = 0;
    else if (pos + 6 == len && (s[pos] == '+' || s[pos] == '-') && s[pos + 3] == ':' &&
             all_digits(s, (int)pos + 1, 2) && all_digits(s, (int)pos + 4, 2)) {
        off = num_at(s, (int)pos + 1, 2) * 3600000LL + num_at(s, (int)pos + 4, 2) * 60000LL;
        if (s[pos] == '-') off = -off;
    } else return -1;
    *out_ms = ms + h * 3600000LL + mi * 60000LL + sec * 1000LL + frac - off;
    return 0;
}

static void yyyymmdd(long long ms, char *out) {
    long long days = ms / 86400000LL;
    if (ms % 86400000LL < 0) days--;
    long long z = days + 719468;
    long long era = (z >= 0 ? z : z - 146096) / 146097;
    long long doe = z - era * 146097;
    long long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    long long mp = (5 * doy + 2) / 153;
    long long d = doy - (153 * mp + 2) / 5 + 1;
    long long m = mp < 10 ? mp + 3 : mp - 9;
    long long y = yoe + era * 400 + (m <= 2);
    snprintf(out, 40, "%04lld%02lld%02lld", y, m, d);
}

/**
 * name.replace(/\s+/g, '').toUpperCase().slice(0, max) for ASCII case
 * mapping; the slice counts UTF-16 code units. Appends to s.
 */
static void name_token(sb_t *s, const char *name, int max) {
    const unsigned char *p = (const unsigned char *)name;
    int units = 0;
    while (*p) {
        const unsigned char *start = p;
        unsigned cp = utf8_next(&p);
        if (cp == ' ' || (cp >= 0x09 && cp <= 0x0D) || cp == 0xA0 || cp == 0xFEFF || cp == 0x1680 ||
            (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 || cp == 0x202F ||
            cp == 0x205F || cp == 0x3000) continue;
        int need = cp >= 0x10000 ? 2 : 1;
        if (units + need > max) break;
        units += need;
        if (cp >= 'a' && cp <= 'z') sb_putc(s, (char)(cp - 32));
        else sb_putn(s, (const char *)start, (size_t)(p - start));
    }
}

/** Truncate an ASCII-or-UTF-8 string held in sb to max UTF-16 units. */
static void truncate_units(sb_t *s, int max) {
    const unsigned char *p = (const unsigned char *)s->b;
    int units = 0;
    while (p && *p) {
        const unsigned char *start = p;
        unsigned cp = utf8_next(&p);
        int need = cp >= 0x10000 ? 2 : 1;
        if (units + need > max) { s->n = (size_t)(start - (const unsigned char *)s->b); s->b[s->n] = '\0'; return; }
        units += need;
    }
}

int itx_make_plan_id_value(const itx_json_t *c, char *buf) {
    if (!c || c->kind != ITX_JSON_OBJECT || !buf) return -1;
    const itx_json_t *nodes = itx_json_get(c, "nodes");
    const itx_json_t *vv = itx_json_get(c, "v");
    double v = (vv && vv->kind == ITX_JSON_NUMBER) ? vv->num : 0;
    /* upgradeConfig: v1 configs (txName/rxName/delay) must be upgraded first */
    if (!(v >= 2 && nodes && nodes->kind == ITX_JSON_ARRAY && nodes->count > 0)) return -1;
    const char *start = itx_json_str(itx_json_get(c, "start"));
    long long ms;
    if (!start || parse_js_date(start, &ms) != 0) return -1;
    char date[40];
    yyyymmdd(ms, date);

    sb_t host = { NULL, 0, 0, 0 }, rem = { NULL, 0, 0, 0 };
    const char *n0 = itx_json_str(itx_json_get(itx_json_at(nodes, 0), "name"));
    if (n0 && *n0) name_token(&host, n0, 8); else sb_puts(&host, "HOST");
    if (!host.b) sb_puts(&host, "");
    if (nodes->count > 1) {
        for (size_t i = 1; i < nodes->count; i++) {
            if (i > 1) sb_putc(&rem, '-');
            const char *nm = itx_json_str(itx_json_get(itx_json_at(nodes, i), "name"));
            name_token(&rem, nm ? nm : "", 4);
        }
        if (!rem.b) sb_puts(&rem, "");
        truncate_units(&rem, 16);
    } else {
        sb_puts(&rem, "RX");
    }

    int rc = 0;
    if (v >= 3) {
        char *canon = itx_json_canonical(c);
        if (!canon) rc = -1;
        else {
            unsigned char dg[32];
            char hex[65];
            itx_sha256(canon, strlen(canon), dg);
            hex_of(dg, 4, hex);
            snprintf(buf, ITX_PLAN_ID_LEN, "LTX-%s-%s-%s-v3-%s", date, host.b, rem.b, hex);
            free(canon);
        }
    } else {
        char *raw = itx_json_stringify(c);
        if (!raw) rc = -1;
        else {
            snprintf(buf, ITX_PLAN_ID_LEN, "LTX-%s-%s-%s-v2-%08x", date, host.b, rem.b, itx_imul31_utf16(raw));
            free(raw);
        }
    }
    free(host.b);
    free(rem.b);
    return (host.err || rem.err) ? -1 : rc;
}

int itx_make_plan_id_json(const char *plan_json, char *buf) {
    itx_json_t *v = itx_json_parse(plan_json);
    int rc = v ? itx_make_plan_id_value(v, buf) : -1;
    itx_json_free(v);
    return rc;
}

int itx_plan_hash_value(const itx_json_t *plan, char hex[65]) {
    char *canon = itx_json_canonical(plan);
    if (!canon) return -1;
    unsigned char dg[32];
    itx_sha256(canon, strlen(canon), dg);
    hex_of(dg, 32, hex);
    free(canon);
    return 0;
}

int itx_plan_hash_json(const char *plan_json, char hex[65]) {
    itx_json_t *v = itx_json_parse(plan_json);
    int rc = v ? itx_plan_hash_value(v, hex) : -1;
    itx_json_free(v);
    return rc;
}

/* ── validatePlan ────────────────────────────────────────────────────────── */

static void add_err(itx_plan_validation_t *r, const char *code, const char *path, const char *fmt, ...) {
    if (r->error_count >= ITX_MAX_PLAN_ERRORS) { r->truncated = 1; return; }
    itx_plan_error_t *e = &r->errors[r->error_count++];
    snprintf(e->code, sizeof(e->code), "%s", code);
    snprintf(e->path, sizeof(e->path), "%s", path);
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(e->message, sizeof(e->message), fmt, ap);
    va_end(ap);
}

static int str_in(const char *s, const char *const *list, int n) {
    if (!s) return 0;
    for (int i = 0; i < n; i++) if (strcmp(s, list[i]) == 0) return 1;
    return 0;
}

static int is_integer(const itx_json_t *v, double *out) {
    if (!v || v->kind != ITX_JSON_NUMBER || !isfinite(v->num) || floor(v->num) != v->num) return 0;
    if (out) *out = v->num;
    return 1;
}

static void reserved_errors(const itx_json_t *plan, itx_plan_validation_t *r) {
    if (!plan || plan->kind != ITX_JSON_OBJECT) return;
    const itx_json_t *st = itx_json_get(plan, "streams");
    if (st && !(st->kind == ITX_JSON_ARRAY && st->count == 0))
        add_err(r, "reserved_streams", "streams", "streams[] is reserved (§3.5) and MUST be absent or empty");
    static const char *const bf[] = { "branches", "branching" };
    for (int i = 0; i < 2; i++)
        if (itx_json_get(plan, bf[i]))
            add_err(r, "reserved_branching", bf[i], "%s is reserved for branching (§7, not yet implemented) and MUST be absent", bf[i]);
    const itx_json_t *segs = itx_json_get(plan, "segments");
    if (segs && segs->kind == ITX_JSON_ARRAY) {
        size_t i = 0;
        for (const itx_json_t *sg = segs->child; sg; sg = sg->next, i++) {
            char path[64];
            if (sg->kind != ITX_JSON_OBJECT) continue;
            if (itx_json_get(sg, "stream")) {
                snprintf(path, sizeof(path), "segments[%zu].stream", i);
                add_err(r, "reserved_streams", path, "segment stream is reserved (§3.5) and MUST be absent");
            }
            if (itx_json_get(sg, "branch")) {
                snprintf(path, sizeof(path), "segments[%zu].branch", i);
                add_err(r, "reserved_branching", path, "segment branch is reserved for branching (§7) and MUST be absent");
            }
        }
    }
}

const char *itx_reserved_field_code_value(const itx_json_t *plan) {
    itx_plan_validation_t r;
    memset(&r, 0, sizeof(r));
    reserved_errors(plan, &r);
    if (r.error_count == 0) return NULL;
    return strcmp(r.errors[0].code, "reserved_streams") == 0 ? "reserved_streams" : "reserved_branching";
}

const char *itx_reserved_field_code(const char *plan_json) {
    itx_json_t *v = itx_json_parse(plan_json);
    const char *code = itx_reserved_field_code_value(v);
    itx_json_free(v);
    return code;
}

int itx_validate_plan_value(const itx_json_t *plan, itx_plan_validation_t *r) {
    static const char *const modes[] = { "LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC" };
    static const char *const seg_types[] = { "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE",
                                             "SPEAK", "REST", "PAD", "OPEN", "RELAY" };
    static const char *const roles[] = { "HOST", "PARTICIPANT", "OBSERVER" };
    static const char *const required[] = { "title", "start", "quantum", "mode", "nodes", "segments" };
    static const char *const v3_only[] = { "delays", "planVersion", "prevPlanHash", "questions", "actions", "streams" };
    if (!r) return 0;
    memset(r, 0, sizeof(*r));
    if (!plan || plan->kind != ITX_JSON_OBJECT) {
        add_err(r, "not_an_object", "", "plan must be an object");
        return r->valid = 0;
    }
    const itx_json_t *vv = itx_json_get(plan, "v");
    int is_v2 = vv && vv->kind == ITX_JSON_NUMBER && vv->num == 2;
    int is_v3 = vv && vv->kind == ITX_JSON_NUMBER && vv->num == 3;
    if (!is_v2 && !is_v3) add_err(r, "invalid_version", "v", "v must be 2 or 3");
    for (int i = 0; i < 6; i++)
        if (!itx_json_get(plan, required[i])) add_err(r, "missing_field", required[i], "%s is required", required[i]);
    const itx_json_t *t = itx_json_get(plan, "title");
    if (t && t->kind != ITX_JSON_STRING) add_err(r, "invalid_field", "title", "title must be a string");
    const itx_json_t *st = itx_json_get(plan, "start");
    long long ms;
    if (st && (st->kind != ITX_JSON_STRING || parse_js_date(st->str, &ms) != 0))
        add_err(r, "invalid_field", "start", "start must be an ISO 8601 UTC timestamp");
    const itx_json_t *q = itx_json_get(plan, "quantum");
    double qv;
    if (q && !(is_integer(q, &qv) && qv >= 1 && qv <= 60))
        add_err(r, "invalid_quantum", "quantum", "quantum must be an integer 1..60 minutes (§3.2)");
    const itx_json_t *m = itx_json_get(plan, "mode");
    if (m && !str_in(itx_json_str(m), modes, 4))
        add_err(r, "invalid_mode", "mode", "mode must be one of LTX, LTX-LIVE, LTX-RELAY, LTX-ASYNC");

    const char *ids[256];
    int id_count = 0;
    const itx_json_t *nodes = itx_json_get(plan, "nodes");
    if (nodes) {
        if (nodes->kind != ITX_JSON_ARRAY || nodes->count == 0) {
            add_err(r, "invalid_nodes", "nodes", "nodes must be a non-empty array");
        } else {
            int hosts = 0;
            size_t i = 0;
            for (const itx_json_t *n = nodes->child; n; n = n->next, i++) {
                char path[48];
                const char *id = itx_json_str(itx_json_get(n, "id"));
                const char *role = itx_json_str(itx_json_get(n, "role"));
                const itx_json_t *d = itx_json_get(n, "delay");
                int ok = n->kind == ITX_JSON_OBJECT && id && *id && !strchr(id, '|') &&
                         itx_json_str(itx_json_get(n, "name")) && str_in(role, roles, 3) &&
                         d && d->kind == ITX_JSON_NUMBER && d->num >= 0;
                snprintf(path, sizeof(path), "nodes[%zu]", i);
                if (!ok) {
                    add_err(r, "invalid_nodes", path, "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0");
                    continue;
                }
                for (int k = 0; k < id_count; k++) {
                    if (strcmp(ids[k], id) == 0) {
                        snprintf(path, sizeof(path), "nodes[%zu].id", i);
                        add_err(r, "duplicate_node_id", path, "duplicate node id %s", id);
                        break;
                    }
                }
                if (id_count < 256) ids[id_count++] = id;
                if (strcmp(role, "HOST") == 0) hosts++;
            }
            const itx_json_t *h = nodes->child;
            const itx_json_t *hd = itx_json_get(h, "delay");
            const char *hr = itx_json_str(itx_json_get(h, "role"));
            int h_ok = h->kind == ITX_JSON_OBJECT && hr && strcmp(hr, "HOST") == 0 &&
                       hd && hd->kind == ITX_JSON_NUMBER && hd->num == 0;
            if (hosts != 1 || !h_ok)
                add_err(r, "invalid_host", "nodes[0]", "exactly one HOST, first in nodes[], with delay 0 (§3.1)");
        }
    }

    const itx_json_t *segs = itx_json_get(plan, "segments");
    if (segs) {
        if (segs->kind != ITX_JSON_ARRAY) {
            add_err(r, "invalid_segment", "segments", "segments must be an array");
        } else {
            size_t i = 0;
            for (const itx_json_t *sg = segs->child; sg; sg = sg->next, i++) {
                char path[64];
                double sq;
                int is_obj = sg->kind == ITX_JSON_OBJECT || sg->kind == ITX_JSON_ARRAY;
                if (!is_obj || !str_in(itx_json_str(itx_json_get(sg, "type")), seg_types, 11) ||
                    !is_integer(itx_json_get(sg, "q"), &sq) || sq < 1) {
                    snprintf(path, sizeof(path), "segments[%zu]", i);
                    add_err(r, "invalid_segment", path, "segment needs a known type and integer q >= 1");
                    continue;
                }
                const itx_json_t *sp = itx_json_get(sg, "speaker");
                if (sp) {
                    int known = 0;
                    if (sp->kind == ITX_JSON_STRING)
                        for (int k = 0; k < id_count; k++) if (strcmp(ids[k], sp->str) == 0) known = 1;
                    if (!known) {
                        char *shown = sp->kind == ITX_JSON_STRING ? NULL : itx_json_stringify(sp);
                        snprintf(path, sizeof(path), "segments[%zu].speaker", i);
                        add_err(r, "unknown_speaker", path, "speaker %s is not a node id",
                                sp->kind == ITX_JSON_STRING ? sp->str : (shown ? shown : "?"));
                        free(shown);
                    }
                }
            }
        }
    }

    if (is_v2) {
        for (int i = 0; i < 6; i++)
            if (itx_json_get(plan, v3_only[i]))
                add_err(r, "v3_field_in_v2", v3_only[i], "%s is a v3 field and MUST NOT appear in a v2 plan (§4.3)", v3_only[i]);
    } else if (is_v3) {
        const itx_json_t *d = itx_json_get(plan, "delays");
        if (d) {
            if (d->kind != ITX_JSON_OBJECT) {
                add_err(r, "invalid_delays", "delays", "delays must be an object");
            } else {
                for (const itx_json_t *e = d->child; e; e = e->next) {
                    const char *bar = strchr(e->key, '|');
                    int ok = 0;
                    if (bar && !strchr(bar + 1, '|')) {
                        size_t alen = (size_t)(bar - e->key);
                        char a[128];
                        snprintf(a, sizeof(a), "%.*s", (int)alen, e->key);
                        const char *b = bar + 1;
                        int a_known = 0, b_known = 0;
                        for (int k = 0; k < id_count; k++) {
                            if (strcmp(ids[k], a) == 0) a_known = 1;
                            if (strcmp(ids[k], b) == 0) b_known = 1;
                        }
                        ok = utf16_cmp(a, b) < 0 && (id_count == 0 || (a_known && b_known)) &&
                             e->kind == ITX_JSON_NUMBER && e->num >= 0;
                    }
                    if (!ok) {
                        char path[160];
                        snprintf(path, sizeof(path), "delays.%s", e->key);
                        add_err(r, "invalid_delays", path, "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)");
                    }
                }
            }
        }
        const itx_json_t *pv = itx_json_get(plan, "planVersion");
        double pvv;
        if (pv && !(is_integer(pv, &pvv) && pvv >= 1))
            add_err(r, "invalid_field", "planVersion", "planVersion must be an integer >= 1");
        const itx_json_t *ph = itx_json_get(plan, "prevPlanHash");
        if (ph) {
            int ok = ph->kind == ITX_JSON_STRING && strlen(ph->str) == 64;
            for (const char *c = ok ? ph->str : ""; *c; c++)
                if (!((*c >= '0' && *c <= '9') || (*c >= 'a' && *c <= 'f'))) ok = 0;
            if (!ok) add_err(r, "invalid_field", "prevPlanHash", "prevPlanHash must be 64 lowercase hex characters");
        }
        static const char *const arrs[] = { "questions", "actions" };
        for (int i = 0; i < 2; i++) {
            const itx_json_t *a = itx_json_get(plan, arrs[i]);
            if (a && a->kind != ITX_JSON_ARRAY) add_err(r, "invalid_field", arrs[i], "%s must be an array", arrs[i]);
        }
    }

    reserved_errors(plan, r);
    r->valid = r->error_count == 0 && !r->truncated;
    return r->valid;
}

int itx_validate_plan_json(const char *plan_json, itx_plan_validation_t *out) {
    itx_json_t *v = itx_json_parse(plan_json);
    int rc = itx_validate_plan_value(v, out);
    itx_json_free(v);
    return rc;
}

int itx_validation_has_code(const itx_plan_validation_t *r, const char *code) {
    if (!r || !code) return 0;
    for (int i = 0; i < r->error_count; i++) if (strcmp(r->errors[i].code, code) == 0) return 1;
    return 0;
}
