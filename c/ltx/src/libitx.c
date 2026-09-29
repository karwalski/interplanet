/**
 * libitx.c — LTX (Light-Time eXchange) C library implementation
 * Story 33.3 — C LTX library (C99, no external dependencies)
 */

#include "../include/libitx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>

/* ── Constants ───────────────────────────────────────────────────────────── */

const int  ITX_DEFAULT_QUANTUM   = 5;
const int  ITX_DEFAULT_SEG_COUNT = 7;
const char ITX_DEFAULT_API_BASE[] = "https://interplanet.live/api/ltx.php";

const itx_seg_tmpl_t ITX_DEFAULT_SEGMENTS[7] = {
    { "PLAN_CONFIRM", 2, "", "" },
    { "TX",           2, "", "" },
    { "RX",           2, "", "" },
    { "CAUCUS",       2, "", "" },
    { "TX",           2, "", "" },
    { "RX",           2, "", "" },
    { "BUFFER",       1, "", "" },
};

/* ── Internal helpers ────────────────────────────────────────────────────── */

static void _strlcpy(char *dst, const char *src, size_t n) {
    if (!dst || n == 0) return;
    if (!src) { dst[0] = '\0'; return; }
    size_t i;
    for (i = 0; i < n - 1 && src[i]; i++) dst[i] = src[i];
    dst[i] = '\0';
}

/* Append src to the NUL-terminated dst of total size n, truncating. */
static void _strlcat(char *dst, const char *src, size_t n) {
    size_t len = strlen(dst);
    if (len + 1 >= n) return;
    _strlcpy(dst + len, src, n - len);
}

/* Base64 character table */
static const char _b64chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/** URL-safe base64 encode (no padding). Returns number of chars written. */
static size_t _b64url_encode(const unsigned char *in, size_t in_len,
                              char *out, size_t out_max) {
    size_t o = 0;
    for (size_t i = 0; i < in_len; i += 3) {
        unsigned int b = ((unsigned int)in[i]) << 16;
        size_t rem = in_len - i;
        if (rem > 1) b |= ((unsigned int)in[i + 1]) << 8;
        if (rem > 2) b |= ((unsigned int)in[i + 2]);

        if (o + 4 >= out_max) break;
        out[o++] = _b64chars[(b >> 18) & 0x3f];
        out[o++] = _b64chars[(b >> 12) & 0x3f];
        if (rem > 1) out[o++] = _b64chars[(b >>  6) & 0x3f];
        if (rem > 2) out[o++] = _b64chars[(b      ) & 0x3f];
    }
    /* URL-safe substitutions (already no padding since we skip = chars) */
    for (size_t k = 0; k < o; k++) {
        if (out[k] == '+') out[k] = '-';
        else if (out[k] == '/') out[k] = '_';
    }
    if (o < out_max) out[o] = '\0';
    return o;
}

/** Base64 decode value table. */
static int _b64_val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

/** URL-safe base64 decode. Returns decoded length, or -1 on error. */
static int _b64url_decode(const char *in, size_t in_len,
                           unsigned char *out, size_t out_max) {
    /* Work on a padded copy */
    size_t padded_len = in_len;
    while (padded_len % 4) padded_len++;
    if (padded_len > 2048) return -1;

    char tmp[2048];
    size_t i;
    for (i = 0; i < in_len; i++) {
        char c = in[i];
        tmp[i] = (c == '-') ? '+' : (c == '_') ? '/' : c;
    }
    while (i < padded_len) tmp[i++] = '=';

    size_t o = 0;
    for (i = 0; i + 3 < padded_len; i += 4) {
        int v0 = _b64_val(tmp[i]);
        int v1 = _b64_val(tmp[i + 1]);
        int v2 = _b64_val(tmp[i + 2]);
        int v3 = _b64_val(tmp[i + 3]);
        if (v0 < 0 || v1 < 0) return -1;
        if (o >= out_max) return -1;
        out[o++] = (unsigned char)((v0 << 2) | (v1 >> 4));
        if (tmp[i + 2] != '=' && o < out_max)
            out[o++] = (unsigned char)((v1 << 4) | (v2 >> 2));
        if (tmp[i + 3] != '=' && o < out_max)
            out[o++] = (unsigned char)((v2 << 6) | v3);
    }
    if (o < out_max) out[o] = '\0';
    return (int)o;
}

/* Growable JSON text buffer. */
typedef struct { char *b; size_t n, cap; int err; } _jbuf_t;

static void _jput(_jbuf_t *j, const char *s) {
    size_t n = strlen(s);
    if (j->err) return;
    if (j->n + n + 1 > j->cap) {
        size_t nc = j->cap ? j->cap * 2 : 1024;
        while (nc < j->n + n + 1) nc *= 2;
        char *nb = (char *)realloc(j->b, nc);
        if (!nb) { j->err = 1; return; }
        j->b = nb; j->cap = nc;
    }
    memcpy(j->b + j->n, s, n + 1);
    j->n += n;
}

/** Append s quoted as JSON.stringify does (itx_json_quote). */
static void _jstr(_jbuf_t *j, const char *s) {
    char *q = itx_json_quote(s);
    if (!q) { j->err = 1; return; }
    _jput(j, q);
    free(q);
}

static void _jint(_jbuf_t *j, int v) {
    char num[16];
    snprintf(num, sizeof(num), "%d", v);
    _jput(j, num);
}

/**
 * Serialise a plan to compact JSON: {v, title, start, quantum, mode, nodes,
 * segments}, segments as {type, q, speaker?, label?} (speaker and label only
 * when non-empty, in ltx-sdk.js order). This is both the wire JSON and the
 * JSON the v2 planId hashes. malloc'd; NULL on allocation failure.
 */
static char *_plan_to_json(const itx_plan_t *p) {
    _jbuf_t j = { NULL, 0, 0, 0 };
    _jput(&j, "{\"v\":");        _jint(&j, p->v);
    _jput(&j, ",\"title\":");    _jstr(&j, p->title);
    _jput(&j, ",\"start\":");    _jstr(&j, p->start);
    _jput(&j, ",\"quantum\":");  _jint(&j, p->quantum);
    _jput(&j, ",\"mode\":");     _jstr(&j, p->mode);
    _jput(&j, ",\"nodes\":[");
    for (int i = 0; i < p->node_count && i < ITX_MAX_NODES; i++) {
        const itx_node_t *n = &p->nodes[i];
        _jput(&j, i > 0 ? ",{\"id\":" : "{\"id\":"); _jstr(&j, n->id);
        _jput(&j, ",\"name\":");     _jstr(&j, n->name);
        _jput(&j, ",\"role\":");     _jstr(&j, n->role);
        _jput(&j, ",\"delay\":");    _jint(&j, n->delay);
        _jput(&j, ",\"location\":"); _jstr(&j, n->location);
        _jput(&j, "}");
    }
    _jput(&j, "],\"segments\":[");
    for (int i = 0; i < p->seg_count && i < ITX_MAX_SEGMENTS; i++) {
        const itx_seg_tmpl_t *s = &p->segments[i];
        _jput(&j, i > 0 ? ",{\"type\":" : "{\"type\":"); _jstr(&j, s->type);
        _jput(&j, ",\"q\":"); _jint(&j, s->q);
        if (s->speaker[0]) { _jput(&j, ",\"speaker\":"); _jstr(&j, s->speaker); }
        if (s->label[0])   { _jput(&j, ",\"label\":");   _jstr(&j, s->label); }
        _jput(&j, "}");
    }
    _jput(&j, "]}");
    if (j.err) { free(j.b); return NULL; }
    return j.b;
}

/** Byte length of the JavaScript \s character (WhiteSpace or
 *  LineTerminator, UTF-8) at p, or 0 if p does not start with one. */
static size_t _js_space_len(const unsigned char *p) {
    if (*p == ' ' || (*p >= 0x09 && *p <= 0x0D)) return 1;
    if (p[0] == 0xC2 && p[1] == 0xA0) return 2;                           /* U+00A0 */
    if (p[0] == 0xE1 && p[1] == 0x9A && p[2] == 0x80) return 3;           /* U+1680 */
    if (p[0] == 0xE2 && p[1] == 0x80 && ((p[2] >= 0x80 && p[2] <= 0x8A) || /* U+2000..200A */
        p[2] == 0xA8 || p[2] == 0xA9 || p[2] == 0xAF)) return 3;           /* U+2028 2029 202F */
    if (p[0] == 0xE2 && p[1] == 0x81 && p[2] == 0x9F) return 3;           /* U+205F */
    if (p[0] == 0xE3 && p[1] == 0x80 && p[2] == 0x80) return 3;           /* U+3000 */
    if (p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) return 3;           /* U+FEFF */
    return 0;
}

/** Parse ISO-8601 UTC string to epoch milliseconds. */
static long long _parse_iso_ms(const char *iso) {
    int yr = 1970, mo = 1, dy = 1, hr = 0, mn = 0, sc = 0;
    if (!iso || !*iso) return 0;
    sscanf(iso, "%d-%d-%dT%d:%d:%d", &yr, &mo, &dy, &hr, &mn, &sc);
    /* Julian Day Number formula (handles Gregorian calendar) */
    long long y = yr, m = mo, d = dy;
    long long jd = (1461LL * (y + 4800LL + (m - 14LL) / 12LL)) / 4LL
                 + (367LL * (m - 2LL - 12LL * ((m - 14LL) / 12LL))) / 12LL
                 - (3LL * ((y + 4900LL + (m - 14LL) / 12LL) / 100LL)) / 4LL
                 + d - 32075LL;
    long long unix_days = jd - 2440588LL; /* JDN of 1970-01-01 */
    return (unix_days * 86400LL + (long long)hr * 3600LL
            + (long long)mn * 60LL + sc) * 1000LL;
}

/** Convert epoch milliseconds to UTC date/time components. */
static void _epoch_ms_to_utc(long long ms,
    int *yr, int *mo, int *dy, int *hr, int *mn, int *sc) {
    long long secs = ms / 1000LL;
    if (ms < 0 && ms % 1000 != 0) secs--;
    *sc = (int)(secs % 60); secs /= 60;
    *mn = (int)(secs % 60); secs /= 60;
    *hr = (int)(secs % 24); secs /= 24;
    /* Convert days since epoch to year/month/day via Julian Day Number */
    long long jd = secs + 2440588LL;
    long long l  = jd + 68569LL;
    long long n  = (4LL * l) / 146097LL;
    l = l - (146097LL * n + 3LL) / 4LL;
    long long iy = (4000LL * (l + 1LL)) / 1461001LL;
    l = l - (1461LL * iy) / 4LL + 31LL;
    long long im = (80LL * l) / 2447LL;
    *dy = (int)(l - (2447LL * im) / 80LL);
    l = im / 11LL;
    *mo = (int)(im + 2LL - 12LL * l);
    *yr = (int)(100LL * (n - 49LL) + iy + l);
}

/** Format epoch ms as iCal YYYYMMDDTHHMMSSZ. */
static void _fmt_ical_dt(long long ms, char *buf) {
    int yr, mo, dy, hr, mn, sc;
    _epoch_ms_to_utc(ms, &yr, &mo, &dy, &hr, &mn, &sc);
    snprintf(buf, 20, "%04d%02d%02dT%02d%02d%02dZ", yr, mo, dy, hr, mn, sc);
}

/** ICS node id: name.replace(/\s+/g, '-').toUpperCase() (ltx-sdk.js toId),
 *  with JavaScript's \s and ASCII case mapping. */
static void _to_id(const char *name, char *buf, size_t max) {
    const unsigned char *p = (const unsigned char *)name;
    size_t i = 0;
    while (*p && i < max - 1) {
        size_t ws = _js_space_len(p);
        if (ws) {
            buf[i++] = '-';
            while ((ws = _js_space_len(p)) > 0) p += ws;
            continue;
        }
        buf[i++] = (*p >= 'a' && *p <= 'z') ? (char)(*p - 32) : (char)*p;
        p++;
    }
    buf[i] = '\0';
}

/* ── Public API ──────────────────────────────────────────────────────────── */

void itx_create_plan(itx_plan_t *plan, const char *title,
                     const char *start_iso, int delay_sec) {
    if (!plan) return;
    memset(plan, 0, sizeof(*plan));

    plan->v       = 2;
    plan->quantum = ITX_DEFAULT_QUANTUM;
    _strlcpy(plan->title, (title && *title) ? title : "LTX Session", ITX_MAX_STR);
    _strlcpy(plan->start, (start_iso && *start_iso) ? start_iso : "", 64);
    _strlcpy(plan->mode, "LTX", 32);

    /* Default nodes: Earth HQ (HOST) + Mars Hab-01 (PARTICIPANT) */
    plan->node_count = 2;
    _strlcpy(plan->nodes[0].id,       "N0",       32);
    _strlcpy(plan->nodes[0].name,     "Earth HQ", ITX_MAX_STR);
    _strlcpy(plan->nodes[0].role,     "HOST",     32);
    plan->nodes[0].delay = 0;
    _strlcpy(plan->nodes[0].location, "earth",    32);

    _strlcpy(plan->nodes[1].id,       "N1",          32);
    _strlcpy(plan->nodes[1].name,     "Mars Hab-01", ITX_MAX_STR);
    _strlcpy(plan->nodes[1].role,     "PARTICIPANT", 32);
    plan->nodes[1].delay = delay_sec;
    _strlcpy(plan->nodes[1].location, "mars", 32);

    /* Default segments */
    plan->seg_count = ITX_DEFAULT_SEG_COUNT;
    for (int i = 0; i < ITX_DEFAULT_SEG_COUNT; i++) {
        _strlcpy(plan->segments[i].type, ITX_DEFAULT_SEGMENTS[i].type, 32);
        plan->segments[i].q = ITX_DEFAULT_SEGMENTS[i].q;
    }
}

void itx_compute_segments(const itx_plan_t *plan,
                           itx_segment_t *segs, int *seg_count) {
    if (!plan || !segs || !seg_count) return;
    long long qms = (long long)plan->quantum * 60LL * 1000LL;
    long long t   = _parse_iso_ms(plan->start);
    int n = plan->seg_count < ITX_MAX_SEGMENTS ? plan->seg_count : ITX_MAX_SEGMENTS;
    for (int i = 0; i < n; i++) {
        long long dur = (long long)plan->segments[i].q * qms;
        _strlcpy(segs[i].type, plan->segments[i].type, 32);
        segs[i].q        = plan->segments[i].q;
        segs[i].start_ms = t;
        segs[i].end_ms   = t + dur;
        segs[i].dur_min  = plan->segments[i].q * plan->quantum;
        t += dur;
    }
    *seg_count = n;
}

int itx_total_min(const itx_plan_t *plan) {
    if (!plan) return 0;
    int total = 0;
    for (int i = 0; i < plan->seg_count; i++)
        total += plan->segments[i].q * plan->quantum;
    return total;
}

void itx_make_plan_id(const itx_plan_t *plan, char *buf) {
    if (!plan || !buf) return;

    /* Date portion */
    char date[16];
    {
        int yr, mo, dy, hr, mn, sc;
        long long ms = _parse_iso_ms(plan->start);
        _epoch_ms_to_utc(ms, &yr, &mo, &dy, &hr, &mn, &sc);
        snprintf(date, sizeof(date), "%04d%02d%02d", yr, mo, dy);
    }

    /* HOSTSTR / NODESTR: JavaScript \s stripped, upper case, UTF-16 slices */
    const char *names[ITX_MAX_NODES];
    int n = plan->node_count < ITX_MAX_NODES ? plan->node_count : ITX_MAX_NODES;
    for (int i = 0; i < n; i++) names[i] = plan->nodes[i].name;
    char host_str[32], node_str[64];
    itx_plan_id_name_strs(names, n > 0 ? (size_t)n : 0, host_str, node_str);

    /* Polynomial hash matching Math.imul(31, h) + charCodeAt(i) in
     * ltx-sdk.js: over UTF-16 code units of the wire JSON. */
    char *json = _plan_to_json(plan);
    unsigned int h = json ? itx_imul31_utf16(json) : 0;
    free(json);

    snprintf(buf, ITX_PLAN_ID_LEN, "LTX-%s-%s-%s-v2-%08x",
             date, host_str, node_str, h);
}

void itx_encode_hash(const itx_plan_t *plan, char *buf) {
    if (!plan || !buf) return;
    buf[0] = '#'; buf[1] = 'l'; buf[2] = '='; buf[3] = '\0';
    char *json = _plan_to_json(plan);
    if (!json) return;
    _b64url_encode((const unsigned char *)json, strlen(json),
                   buf + 3, ITX_HASH_BUF - 3);
    free(json);
}

/** Copy a string member of a parsed JSON object, if present. */
static void _json_copy(const itx_json_t *obj, const char *key, char *dst, size_t n) {
    const char *s = itx_json_str(itx_json_get(obj, key));
    if (s) _strlcpy(dst, s, n);
}

/** Read a number member of a parsed JSON object as int, if present. */
static void _json_int(const itx_json_t *obj, const char *key, int *dst) {
    double d;
    if (itx_json_num(itx_json_get(obj, key), &d)) *dst = (int)d;
}

int itx_decode_hash(const char *hash, itx_plan_t *plan) {
    if (!hash || !plan) return -1;

    /* Strip leading "#l=" or "l=" */
    const char *token = hash;
    if (token[0] == '#') token++;
    if (token[0] == 'l' && token[1] == '=') token += 2;

    unsigned char decoded[ITX_JSON_BUF + 1];
    int len = _b64url_decode(token, strlen(token), decoded, ITX_JSON_BUF);
    if (len <= 0) return -1;
    decoded[len] = '\0';

    itx_json_t *root = itx_json_parse((const char *)decoded);
    if (!root || itx_json_kind(root) != ITX_JSON_OBJECT) { itx_json_free(root); return -1; }

    memset(plan, 0, sizeof(*plan));
    plan->v = 2; plan->quantum = ITX_DEFAULT_QUANTUM;
    _strlcpy(plan->mode, "LTX", 32);

    _json_int(root,  "v",       &plan->v);
    _json_copy(root, "title",   plan->title, ITX_MAX_STR);
    _json_copy(root, "start",   plan->start, 64);
    _json_int(root,  "quantum", &plan->quantum);
    _json_copy(root, "mode",    plan->mode,  32);

    const itx_json_t *nodes = itx_json_get(root, "nodes");
    for (size_t i = 0; i < itx_json_len(nodes) && plan->node_count < ITX_MAX_NODES; i++) {
        const itx_json_t *o = itx_json_at(nodes, i);
        if (itx_json_kind(o) != ITX_JSON_OBJECT) continue;
        itx_node_t *n = &plan->nodes[plan->node_count];
        _json_copy(o, "id",       n->id,       32);
        _json_copy(o, "name",     n->name,     ITX_MAX_STR);
        _json_copy(o, "role",     n->role,     32);
        _json_int(o,  "delay",    &n->delay);
        _json_copy(o, "location", n->location, 32);
        if (n->id[0]) plan->node_count++;
        else memset(n, 0, sizeof(*n));
    }

    const itx_json_t *segs = itx_json_get(root, "segments");
    for (size_t i = 0; i < itx_json_len(segs) && plan->seg_count < ITX_MAX_SEGMENTS; i++) {
        const itx_json_t *o = itx_json_at(segs, i);
        if (itx_json_kind(o) != ITX_JSON_OBJECT) continue;
        itx_seg_tmpl_t *s = &plan->segments[plan->seg_count];
        _json_copy(o, "type",    s->type,    32);
        _json_int(o,  "q",       &s->q);
        _json_copy(o, "speaker", s->speaker, 32);
        _json_copy(o, "label",   s->label,   ITX_MAX_STR);
        if (s->type[0]) plan->seg_count++;
        else memset(s, 0, sizeof(*s));
    }

    itx_json_free(root);
    return (plan->seg_count > 0) ? 0 : -1;
}

void itx_build_node_urls(const itx_plan_t *plan, const char *base_url,
                          itx_node_url_t *urls, int *url_count) {
    if (!plan || !urls || !url_count) return;

    char hash[ITX_HASH_BUF];
    itx_encode_hash(plan, hash);
    /* Strip leading '#' */
    const char *hash_part = (hash[0] == '#') ? hash + 1 : hash;

    /* Strip query and fragment from base_url */
    char base[512];
    _strlcpy(base, base_url ? base_url : "", sizeof(base));
    char *q = strchr(base, '?'); if (q) *q = '\0';
    char *f = strchr(base, '#'); if (f) *f = '\0';

    int n = plan->node_count < ITX_MAX_NODES ? plan->node_count : ITX_MAX_NODES;
    for (int i = 0; i < n; i++) {
        const itx_node_t *node = &plan->nodes[i];
        _strlcpy(urls[i].node_id, node->id,   32);
        _strlcpy(urls[i].name,    node->name,  ITX_MAX_STR);
        _strlcpy(urls[i].role,    node->role,  32);
        snprintf(urls[i].url, ITX_URL_BUF, "%s?node=%s#%s",
                 base, node->id, hash_part);
    }
    *url_count = n;
}

void itx_generate_ics(const itx_plan_t *plan, char *buf) {
    if (!plan || !buf) return;

    itx_segment_t segs[ITX_MAX_SEGMENTS];
    int seg_count = 0;
    itx_compute_segments(plan, segs, &seg_count);

    long long start_ms = _parse_iso_ms(plan->start);
    long long end_ms   = seg_count > 0 ? segs[seg_count - 1].end_ms : start_ms;

    char plan_id[ITX_PLAN_ID_LEN];
    itx_make_plan_id(plan, plan_id);

    char dt_start[20], dt_end[20], dt_stamp[20];
    _fmt_ical_dt(start_ms, dt_start);
    _fmt_ical_dt(end_ms,   dt_end);
    _fmt_ical_dt((long long)time(NULL) * 1000LL, dt_stamp);

    /* Build segment template string */
    /* Sized for a full plan: ITX_MAX_SEGMENTS types, ITX_MAX_NODES names. */
    char seg_tpl[ITX_MAX_SEGMENTS * 33] = "";
    for (int i = 0; i < plan->seg_count && i < ITX_MAX_SEGMENTS; i++) {
        if (i > 0) _strlcat(seg_tpl, ",", sizeof(seg_tpl));
        _strlcat(seg_tpl, plan->segments[i].type, sizeof(seg_tpl));
    }

    const itx_node_t *host = plan->node_count > 0 ? &plan->nodes[0] : NULL;
    char host_name[ITX_MAX_STR] = "Earth HQ";
    if (host) _strlcpy(host_name, host->name, ITX_MAX_STR);

    /* Build participant names and delay description */
    char part_names[ITX_MAX_NODES * (ITX_MAX_STR + 2)] = "remote nodes";
    char delay_desc[ITX_MAX_NODES * (ITX_MAX_STR + 32)] = "no participant delay configured";
    int node_count = plan->node_count < ITX_MAX_NODES ? plan->node_count : ITX_MAX_NODES;
    if (node_count > 1) {
        part_names[0] = '\0';
        delay_desc[0] = '\0';
        for (int i = 1; i < node_count; i++) {
            if (i > 1) {
                _strlcat(part_names, ", ", sizeof(part_names));
                _strlcat(delay_desc, " . ", sizeof(delay_desc));
            }
            _strlcat(part_names, plan->nodes[i].name, sizeof(part_names));
            char tmp[ITX_MAX_STR + 32];
            snprintf(tmp, sizeof(tmp), "%s: %d min one-way",
                     plan->nodes[i].name, plan->nodes[i].delay / 60);
            _strlcat(delay_desc, tmp, sizeof(delay_desc));
        }
    }

    size_t pos = 0;
    /* Output past ITX_ICS_BUF - 1 bytes is cut off, never written. */
    #define LN(fmt, ...) do { \
        int n_ = snprintf(buf + pos, ITX_ICS_BUF - pos, fmt "\r\n", ##__VA_ARGS__); \
        if (n_ > 0) pos = (pos + (size_t)n_ < ITX_ICS_BUF) ? pos + (size_t)n_ : ITX_ICS_BUF - 1; \
    } while (0)

    LN("BEGIN:VCALENDAR");
    LN("VERSION:2.0");
    LN("PRODID:-//InterPlanet//LTX v1.1//EN");
    LN("CALSCALE:GREGORIAN");
    LN("METHOD:PUBLISH");
    LN("BEGIN:VEVENT");
    LN("UID:%s@interplanet.live", plan_id);
    LN("DTSTAMP:%s", dt_stamp);
    LN("DTSTART:%s", dt_start);
    LN("DTEND:%s", dt_end);
    LN("SUMMARY:%s", plan->title);
    LN("DESCRIPTION:LTX session -- %s with %s\\nSignal delays: %s\\nMode: %s . Segment plan: %s\\nGenerated by InterPlanet (https://interplanet.live)",
       host_name, part_names, delay_desc, plan->mode, seg_tpl);
    LN("LTX:1");
    LN("LTX-PLANID:%s", plan_id);
    LN("LTX-QUANTUM:PT%dM", plan->quantum);
    LN("LTX-SEGMENT-TEMPLATE:%s", seg_tpl);
    LN("LTX-MODE:%s", plan->mode);

    /* Node lines */
    for (int i = 0; i < node_count; i++) {
        char nid[ITX_MAX_STR];
        _to_id(plan->nodes[i].name, nid, sizeof(nid));
        LN("LTX-NODE:ID=%s;ROLE=%s", nid, plan->nodes[i].role);
    }
    /* Delay lines for participants */
    for (int i = 1; i < node_count; i++) {
        char nid[ITX_MAX_STR];
        _to_id(plan->nodes[i].name, nid, sizeof(nid));
        int d = plan->nodes[i].delay;
        LN("LTX-DELAY;NODEID=%s:ONEWAY-MIN=%d;ONEWAY-MAX=%d;ONEWAY-ASSUMED=%d",
           nid, d, d + 120, d);
    }
    LN("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY");
    /* Local time lines for Mars nodes */
    for (int i = 0; i < node_count; i++) {
        if (strcmp(plan->nodes[i].location, "mars") == 0) {
            char nid[ITX_MAX_STR];
            _to_id(plan->nodes[i].name, nid, sizeof(nid));
            LN("LTX-LOCALTIME:NODE=%s;SCHEME=LMST;PARAMS=LONGITUDE:0E", nid);
        }
    }
    LN("END:VEVENT");
    LN("END:VCALENDAR");

    #undef LN
}

void itx_format_hms(int seconds, char *buf) {
    if (!buf) return;
    if (seconds < 0) seconds = 0;
    int h = seconds / 3600;
    int m = (seconds % 3600) / 60;
    int s = seconds % 60;
    if (h > 0) snprintf(buf, 12, "%02d:%02d:%02d", h, m, s);
    else        snprintf(buf, 12, "%02d:%02d", m, s);
}

void itx_format_utc(long long epoch_ms, char *buf) {
    if (!buf) return;
    int yr, mo, dy, hr, mn, sc;
    _epoch_ms_to_utc(epoch_ms, &yr, &mo, &dy, &hr, &mn, &sc);
    snprintf(buf, 16, "%02d:%02d:%02d UTC", hr, mn, sc);
}
