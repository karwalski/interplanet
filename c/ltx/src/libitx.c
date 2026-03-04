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

const int  ITX_DEFAULT_QUANTUM   = 3;
const int  ITX_DEFAULT_SEG_COUNT = 7;
const char ITX_DEFAULT_API_BASE[] = "https://interplanet.live/api/ltx.php";

const itx_seg_tmpl_t ITX_DEFAULT_SEGMENTS[7] = {
    { "PLAN_CONFIRM", 2 },
    { "TX",           2 },
    { "RX",           2 },
    { "CAUCUS",       2 },
    { "TX",           2 },
    { "RX",           2 },
    { "BUFFER",       1 },
};

/* ── Internal helpers ────────────────────────────────────────────────────── */

static void _strlcpy(char *dst, const char *src, size_t n) {
    if (!dst || n == 0) return;
    if (!src) { dst[0] = '\0'; return; }
    size_t i;
    for (i = 0; i < n - 1 && src[i]; i++) dst[i] = src[i];
    dst[i] = '\0';
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

/** Append a JSON-escaped string to buf at position *pos. */
static void _json_str(char *buf, size_t *pos, size_t max, const char *s) {
    if (*pos + 2 >= max) return;
    buf[(*pos)++] = '"';
    while (*s && *pos + 2 < max) {
        if (*s == '"' || *s == '\\') buf[(*pos)++] = '\\';
        buf[(*pos)++] = *s++;
    }
    buf[(*pos)++] = '"';
}

/** Serialise a plan to compact JSON (matches JS JSON.stringify key order). */
static void _plan_to_json(const itx_plan_t *p, char *buf, size_t max) {
    size_t pos = 0;
    buf[pos++] = '{';
    /* v */
    _json_str(buf, &pos, max, "v"); buf[pos++] = ':';
    pos += snprintf(buf + pos, max - pos, "%d", p->v);
    buf[pos++] = ',';
    /* title */
    _json_str(buf, &pos, max, "title"); buf[pos++] = ':';
    _json_str(buf, &pos, max, p->title);
    buf[pos++] = ',';
    /* start */
    _json_str(buf, &pos, max, "start"); buf[pos++] = ':';
    _json_str(buf, &pos, max, p->start);
    buf[pos++] = ',';
    /* quantum */
    _json_str(buf, &pos, max, "quantum"); buf[pos++] = ':';
    pos += snprintf(buf + pos, max - pos, "%d", p->quantum);
    buf[pos++] = ',';
    /* mode */
    _json_str(buf, &pos, max, "mode"); buf[pos++] = ':';
    _json_str(buf, &pos, max, p->mode);
    buf[pos++] = ',';
    /* nodes */
    _json_str(buf, &pos, max, "nodes"); buf[pos++] = ':'; buf[pos++] = '[';
    for (int i = 0; i < p->node_count; i++) {
        if (i > 0) buf[pos++] = ',';
        const itx_node_t *n = &p->nodes[i];
        buf[pos++] = '{';
        _json_str(buf, &pos, max, "id"); buf[pos++] = ':'; _json_str(buf, &pos, max, n->id);
        buf[pos++] = ',';
        _json_str(buf, &pos, max, "name"); buf[pos++] = ':'; _json_str(buf, &pos, max, n->name);
        buf[pos++] = ',';
        _json_str(buf, &pos, max, "role"); buf[pos++] = ':'; _json_str(buf, &pos, max, n->role);
        buf[pos++] = ',';
        _json_str(buf, &pos, max, "delay"); buf[pos++] = ':';
        pos += snprintf(buf + pos, max - pos, "%d", n->delay);
        buf[pos++] = ',';
        _json_str(buf, &pos, max, "location"); buf[pos++] = ':'; _json_str(buf, &pos, max, n->location);
        buf[pos++] = '}';
    }
    buf[pos++] = ']'; buf[pos++] = ',';
    /* segments */
    _json_str(buf, &pos, max, "segments"); buf[pos++] = ':'; buf[pos++] = '[';
    for (int i = 0; i < p->seg_count; i++) {
        if (i > 0) buf[pos++] = ',';
        const itx_seg_tmpl_t *s = &p->segments[i];
        buf[pos++] = '{';
        _json_str(buf, &pos, max, "type"); buf[pos++] = ':'; _json_str(buf, &pos, max, s->type);
        buf[pos++] = ',';
        _json_str(buf, &pos, max, "q"); buf[pos++] = ':';
        pos += snprintf(buf + pos, max - pos, "%d", s->q);
        buf[pos++] = '}';
    }
    buf[pos++] = ']'; buf[pos++] = '}';
    if (pos < max) buf[pos] = '\0';
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

/** Convert node name to uppercase ID (spaces → hyphens). */
static void _to_id(const char *name, char *buf, size_t max) {
    size_t i;
    for (i = 0; i < max - 1 && name[i]; i++) {
        buf[i] = (name[i] == ' ' || name[i] == '\t') ? '-'
               : (name[i] >= 'a' && name[i] <= 'z') ? name[i] - 32
               : name[i];
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

    /* Host string: remove spaces, uppercase, max 8 chars */
    char host_str[16] = "HOST";
    if (plan->node_count > 0) {
        const char *nm = plan->nodes[0].name;
        size_t j = 0;
        for (size_t k = 0; nm[k] && j < 8; k++) {
            char c = nm[k];
            if (c == ' ' || c == '\t') continue;
            host_str[j++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
        }
        host_str[j] = '\0';
    }

    /* Node string: first 4 chars of each remote name, separated by - */
    char node_str[32] = "RX";
    if (plan->node_count > 1) {
        size_t np = 0;
        for (int i = 1; i < plan->node_count && np < 16; i++) {
            if (np > 0 && np < 15) node_str[np++] = '-';
            const char *nm = plan->nodes[i].name;
            size_t cnt = 0;
            for (size_t k = 0; nm[k] && cnt < 4 && np < 16; k++) {
                char c = nm[k];
                if (c == ' ' || c == '\t') continue;
                node_str[np++] = (c >= 'a' && c <= 'z') ? c - 32 : c;
                cnt++;
            }
        }
        node_str[np] = '\0';
    }

    /* Polynomial hash matching Math.imul(31, h) in ltx-sdk.js */
    char json_buf[ITX_JSON_BUF];
    _plan_to_json(plan, json_buf, sizeof(json_buf));
    unsigned int h = 0;
    for (const char *p = json_buf; *p; p++)
        h = 31u * h + (unsigned char)*p;

    snprintf(buf, ITX_PLAN_ID_LEN, "LTX-%s-%s-%s-v2-%08x",
             date, host_str, node_str, h);
}

void itx_encode_hash(const itx_plan_t *plan, char *buf) {
    if (!plan || !buf) return;
    char json_buf[ITX_JSON_BUF];
    _plan_to_json(plan, json_buf, sizeof(json_buf));

    buf[0] = '#'; buf[1] = 'l'; buf[2] = '='; buf[3] = '\0';
    _b64url_encode((const unsigned char *)json_buf, strlen(json_buf),
                   buf + 3, ITX_HASH_BUF - 3);
}

int itx_decode_hash(const char *hash, itx_plan_t *plan) {
    if (!hash || !plan) return -1;

    /* Strip leading "#l=" or "l=" */
    const char *token = hash;
    if (token[0] == '#') token++;
    if (token[0] == 'l' && token[1] == '=') token += 2;

    unsigned char decoded[ITX_JSON_BUF];
    int len = _b64url_decode(token, strlen(token), decoded, sizeof(decoded));
    if (len <= 0) return -1;

    /* Parse JSON fields from decoded string */
    char *json = (char *)decoded;

    /* Helper lambdas (as inline code): extract "key":value fields */
    #define _STRFIELD(key, dst, dsz) do { \
        char *p = strstr(json, "\"" key "\":\""); \
        if (p) { p += strlen("\"" key "\":\""); size_t i = 0; \
            while (*p && *p != '"' && i < (dsz)-1) (dst)[i++] = *p++; \
            (dst)[i] = '\0'; } \
    } while (0)

    #define _NUMFIELD(key, dst) do { \
        char *p = strstr(json, "\"" key "\":"); \
        if (p) { p += strlen("\"" key "\":"); dst = atoi(p); } \
    } while (0)

    memset(plan, 0, sizeof(*plan));
    plan->v = 2; plan->quantum = ITX_DEFAULT_QUANTUM;
    _strlcpy(plan->mode, "LTX", 32);

    _NUMFIELD("v",       plan->v);
    _STRFIELD("title",   plan->title,  ITX_MAX_STR);
    _STRFIELD("start",   plan->start,  64);
    _NUMFIELD("quantum", plan->quantum);
    _STRFIELD("mode",    plan->mode,   32);

    /* Parse nodes array */
    char *nodes_arr = strstr(json, "\"nodes\":[");
    if (nodes_arr) {
        nodes_arr += strlen("\"nodes\":[");
        char *p = nodes_arr;
        while (*p && *p != ']' && plan->node_count < ITX_MAX_NODES) {
            char *obj_start = strchr(p, '{');
            char *obj_end   = obj_start ? strchr(obj_start, '}') : NULL;
            if (!obj_start || !obj_end) break;
            /* Null-terminate temporarily for field extraction */
            char save = obj_end[1]; obj_end[1] = '\0';
            char *obj = obj_start;

            #define _NF(key, dst, dsz) do { \
                char *fp = strstr(obj, "\"" key "\":\""); \
                if (fp) { fp += strlen("\"" key "\":\""); size_t i = 0; \
                    while (*fp && *fp != '"' && i < (dsz)-1) (dst)[i++] = *fp++; \
                    (dst)[i] = '\0'; } \
            } while (0)

            itx_node_t *n = &plan->nodes[plan->node_count];
            _NF("id",       n->id,       32);
            _NF("name",     n->name,     ITX_MAX_STR);
            _NF("role",     n->role,     32);
            _NF("location", n->location, 32);
            { char *fp = strstr(obj, "\"delay\":"); if (fp) n->delay = atoi(fp + 8); }

            #undef _NF

            obj_end[1] = save;
            if (n->id[0]) plan->node_count++;
            p = obj_end + 1;
        }
    }

    /* Parse segments array */
    char *segs_arr = strstr(json, "\"segments\":[");
    if (segs_arr) {
        segs_arr += strlen("\"segments\":[");
        char *p = segs_arr;
        while (*p && *p != ']' && plan->seg_count < ITX_MAX_SEGMENTS) {
            char *obj_start = strchr(p, '{');
            char *obj_end   = obj_start ? strchr(obj_start, '}') : NULL;
            if (!obj_start || !obj_end) break;
            char save = obj_end[1]; obj_end[1] = '\0';
            char *obj = obj_start;

            itx_seg_tmpl_t *s = &plan->segments[plan->seg_count];
            char *fp = strstr(obj, "\"type\":\"");
            if (fp) {
                fp += 8;
                size_t i = 0;
                while (*fp && *fp != '"' && i < 31) s->type[i++] = *fp++;
                s->type[i] = '\0';
            }
            fp = strstr(obj, "\"q\":"); if (fp) s->q = atoi(fp + 4);

            obj_end[1] = save;
            if (s->type[0]) plan->seg_count++;
            p = obj_end + 1;
        }
    }

    #undef _STRFIELD
    #undef _NUMFIELD
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
    char seg_tpl[256] = "";
    for (int i = 0; i < plan->seg_count; i++) {
        if (i > 0) strcat(seg_tpl, ",");
        strcat(seg_tpl, plan->segments[i].type);
    }

    const itx_node_t *host = plan->node_count > 0 ? &plan->nodes[0] : NULL;
    char host_name[ITX_MAX_STR] = "Earth HQ";
    if (host) _strlcpy(host_name, host->name, ITX_MAX_STR);

    /* Build participant names and delay description */
    char part_names[512] = "remote nodes";
    char delay_desc[512] = "no participant delay configured";
    if (plan->node_count > 1) {
        part_names[0] = '\0';
        delay_desc[0] = '\0';
        for (int i = 1; i < plan->node_count; i++) {
            if (i > 1) { strcat(part_names, ", "); strcat(delay_desc, " . "); }
            strcat(part_names, plan->nodes[i].name);
            char tmp[128];
            snprintf(tmp, sizeof(tmp), "%s: %d min one-way",
                     plan->nodes[i].name, plan->nodes[i].delay / 60);
            strcat(delay_desc, tmp);
        }
    }

    size_t pos = 0;
    #define LN(fmt, ...) do { \
        pos += snprintf(buf + pos, ITX_ICS_BUF - pos, fmt "\r\n", ##__VA_ARGS__); \
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
    for (int i = 0; i < plan->node_count; i++) {
        char nid[ITX_MAX_STR];
        _to_id(plan->nodes[i].name, nid, sizeof(nid));
        LN("LTX-NODE:ID=%s;ROLE=%s", nid, plan->nodes[i].role);
    }
    /* Delay lines for participants */
    for (int i = 1; i < plan->node_count; i++) {
        char nid[ITX_MAX_STR];
        _to_id(plan->nodes[i].name, nid, sizeof(nid));
        int d = plan->nodes[i].delay;
        LN("LTX-DELAY;NODEID=%s:ONEWAY-MIN=%d;ONEWAY-MAX=%d;ONEWAY-ASSUMED=%d",
           nid, d, d + 120, d);
    }
    LN("LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY");
    /* Local time lines for Mars nodes */
    for (int i = 0; i < plan->node_count; i++) {
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
