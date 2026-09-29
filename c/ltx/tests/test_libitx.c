/**
 * test_libitx.c — Unit tests for libitx C LTX library
 * Story 33.3 · C99 · Runs with: make test
 */

#include "../include/libitx.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int passed = 0, failed = 0;

#define CHECK(name, cond) do { \
    if (cond) { passed++; } \
    else { failed++; printf("FAIL: %s\n", name); } \
} while (0)

#define SECTION(s) printf("\n-- %s --\n", s)

/* Wire JSON of a "#l=" hash (base64url, no padding). malloc'd. */
static char *wire_of(const char *hash) {
    static const char *tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    const char *t = hash + 3;
    size_t n = strlen(t), o = 0;
    char *out = (char *)malloc(n + 1);
    unsigned acc = 0; int bits = 0;
    for (size_t i = 0; i < n; i++) {
        const char *c = strchr(tbl, t[i]);
        if (!c) break;
        acc = (acc << 6) | (unsigned)(c - tbl); bits += 6;
        if (bits >= 8) { bits -= 8; out[o++] = (char)((acc >> bits) & 0xFF); }
    }
    out[o] = '\0';
    return out;
}

static void set_node(itx_node_t *n, const char *id, const char *name, const char *role,
                     int delay, const char *loc) {
    snprintf(n->id, sizeof(n->id), "%s", id);
    snprintf(n->name, sizeof(n->name), "%s", name);
    snprintf(n->role, sizeof(n->role), "%s", role);
    n->delay = delay;
    snprintf(n->location, sizeof(n->location), "%s", loc);
}

static void set_seg(itx_seg_tmpl_t *s, const char *type, int q, const char *speaker, const char *label) {
    memset(s, 0, sizeof(*s));
    snprintf(s->type, sizeof(s->type), "%s", type);
    s->q = q;
    if (speaker) snprintf(s->speaker, sizeof(s->speaker), "%s", speaker);
    if (label) snprintf(s->label, sizeof(s->label), "%s", label);
}

/* The interop representative plan (scripts/interop/plan.js), typed. */
static void rep_plan(itx_plan_t *p) {
    itx_create_plan(p, "R\xc3\xa9union Mars \xf0\x9f\x9a\x80", "2026-03-15T14:00:00.000Z", 840);
    p->quantum = 3;
    snprintf(p->mode, sizeof(p->mode), "LTX-ASYNC");
    p->node_count = 3;
    set_node(&p->nodes[0], "N0", "Earth HQ", "HOST", 0, "earth");
    set_node(&p->nodes[1], "N1", "Mars Hab-01", "PARTICIPANT", 840, "mars");
    set_node(&p->nodes[2], "N2", "L-1 Gateway", "PARTICIPANT", 2, "moon");
    p->seg_count = 5;
    set_seg(&p->segments[0], "PLAN_CONFIRM", 2, NULL, NULL);
    set_seg(&p->segments[1], "TX", 3, "N0", "Ouverture: \xc3\xa9tat de la mission");
    set_seg(&p->segments[2], "RX", 3, NULL, NULL);
    set_seg(&p->segments[3], "TX", 2, "N1", "R\xc3\xa9ponse \xf0\x9f\x94\xb4");
    set_seg(&p->segments[4], "BUFFER", 1, NULL, NULL);
}

int main(void) {
    /* ── Constants ───────────────────────────────────────────────────── */
    SECTION("Constants");
    CHECK("VERSION not empty",              strlen(ITX_VERSION_STRING) > 0);
    CHECK("VERSION is 1.0.0",              strcmp(ITX_VERSION_STRING, "1.0.0") == 0);
    CHECK("DEFAULT_QUANTUM == 5",          ITX_DEFAULT_QUANTUM == 5);
    CHECK("DEFAULT_SEG_COUNT == 7",        ITX_DEFAULT_SEG_COUNT == 7);
    CHECK("DEFAULT_API_BASE has https",    strncmp(ITX_DEFAULT_API_BASE, "https://", 8) == 0);
    CHECK("DEFAULT_SEGMENTS[0] PLAN_CONFIRM", strcmp(ITX_DEFAULT_SEGMENTS[0].type, "PLAN_CONFIRM") == 0);
    CHECK("DEFAULT_SEGMENTS[1] TX",        strcmp(ITX_DEFAULT_SEGMENTS[1].type, "TX") == 0);
    CHECK("DEFAULT_SEGMENTS[2] RX",        strcmp(ITX_DEFAULT_SEGMENTS[2].type, "RX") == 0);
    CHECK("DEFAULT_SEGMENTS[6] BUFFER",    strcmp(ITX_DEFAULT_SEGMENTS[6].type, "BUFFER") == 0);
    CHECK("DEFAULT_SEGMENTS[0] q == 2",    ITX_DEFAULT_SEGMENTS[0].q == 2);
    CHECK("DEFAULT_SEGMENTS[6] q == 1",    ITX_DEFAULT_SEGMENTS[6].q == 1);

    /* ── itx_create_plan ────────────────────────────────────────────── */
    SECTION("itx_create_plan");
    itx_plan_t plan;
    itx_create_plan(&plan, NULL, "2026-03-15T14:00:00Z", 0);
    CHECK("v == 2",                        plan.v == 2);
    CHECK("title == LTX Session",          strcmp(plan.title, "LTX Session") == 0);
    CHECK("start preserved",               strcmp(plan.start, "2026-03-15T14:00:00Z") == 0);
    CHECK("quantum == 5",                  plan.quantum == 5);
    CHECK("mode == LTX",                   strcmp(plan.mode, "LTX") == 0);
    CHECK("node_count == 2",              plan.node_count == 2);
    CHECK("nodes[0].id == N0",             strcmp(plan.nodes[0].id, "N0") == 0);
    CHECK("nodes[0].role == HOST",         strcmp(plan.nodes[0].role, "HOST") == 0);
    CHECK("nodes[0].location == earth",    strcmp(plan.nodes[0].location, "earth") == 0);
    CHECK("nodes[0].delay == 0",           plan.nodes[0].delay == 0);
    CHECK("nodes[1].id == N1",             strcmp(plan.nodes[1].id, "N1") == 0);
    CHECK("nodes[1].role == PARTICIPANT",  strcmp(plan.nodes[1].role, "PARTICIPANT") == 0);
    CHECK("nodes[1].location == mars",     strcmp(plan.nodes[1].location, "mars") == 0);
    CHECK("seg_count == 7",               plan.seg_count == 7);

    itx_plan_t plan2;
    itx_create_plan(&plan2, "Q3 Review", "2026-06-01T10:00:00Z", 860);
    CHECK("custom title",                  strcmp(plan2.title, "Q3 Review") == 0);
    CHECK("custom delay",                  plan2.nodes[1].delay == 860);

    /* ── itx_compute_segments ───────────────────────────────────────── */
    SECTION("itx_compute_segments");
    itx_segment_t segs[ITX_MAX_SEGMENTS];
    int seg_count = 0;
    itx_compute_segments(&plan, segs, &seg_count);
    CHECK("seg_count == 7",               seg_count == 7);
    CHECK("segs[0].type PLAN_CONFIRM",     strcmp(segs[0].type, "PLAN_CONFIRM") == 0);
    CHECK("segs[6].type BUFFER",           strcmp(segs[6].type, "BUFFER") == 0);
    CHECK("segs[0].q == 2",               segs[0].q == 2);
    CHECK("segs[0].start_ms > 0",         segs[0].start_ms > 0);
    CHECK("segs[0].end_ms > start_ms",     segs[0].end_ms > segs[0].start_ms);
    CHECK("segs[0].dur_min == 10",        segs[0].dur_min == 10);
    CHECK("segs[6].dur_min == 5",         segs[6].dur_min == 5);
    /* Contiguous segments */
    for (int i = 0; i < seg_count - 1; i++) {
        char name[64];
        snprintf(name, sizeof(name), "segs[%d] contiguous", i);
        CHECK(name, segs[i].end_ms == segs[i + 1].start_ms);
    }

    /* ── itx_total_min ──────────────────────────────────────────────── */
    SECTION("itx_total_min");
    int total = itx_total_min(&plan);
    CHECK("totalMin == 65",               total == 65);
    /* Verify: 13 quanta × 5 min = 65 */
    int seg_sum = 0;
    for (int i = 0; i < seg_count; i++) seg_sum += segs[i].dur_min;
    CHECK("totalMin matches seg sum",      seg_sum == total);

    /* ── itx_make_plan_id ───────────────────────────────────────────── */
    SECTION("itx_make_plan_id");
    char pid[ITX_PLAN_ID_LEN];
    itx_make_plan_id(&plan, pid);
    CHECK("planId not empty",             strlen(pid) > 0);
    CHECK("planId starts LTX-",           strncmp(pid, "LTX-", 4) == 0);
    CHECK("planId has date 20260315",      strstr(pid, "20260315") != NULL);
    CHECK("planId has -v2-",              strstr(pid, "-v2-") != NULL);
    /* Deterministic */
    char pid2[ITX_PLAN_ID_LEN];
    itx_make_plan_id(&plan, pid2);
    CHECK("planId deterministic",          strcmp(pid, pid2) == 0);
    /* Format check: LTX-YYYYMMDD-HOST-NODE-v2-XXXXXXXX */
    CHECK("planId length > 20",           strlen(pid) > 20);

    /* ── itx_encode_hash / itx_decode_hash ──────────────────────────── */
    SECTION("itx_encode_hash / itx_decode_hash");
    char hash[ITX_HASH_BUF];
    itx_encode_hash(&plan, hash);
    CHECK("hash starts #l=",              strncmp(hash, "#l=", 3) == 0);
    CHECK("hash non-empty payload",       strlen(hash) > 10);
    CHECK("hash url-safe (no +)",         strchr(hash, '+') == NULL);
    CHECK("hash url-safe (no /)",         strchr(hash, '/') == NULL);
    CHECK("hash no = padding",            strchr(hash + 3, '=') == NULL);

    itx_plan_t decoded;
    int rc = itx_decode_hash(hash, &decoded);
    CHECK("decodeHash returns 0",         rc == 0);
    CHECK("decoded v == 2",               decoded.v == 2);
    CHECK("decoded title matches",        strcmp(decoded.title, plan.title) == 0);
    CHECK("decoded quantum matches",      decoded.quantum == plan.quantum);
    CHECK("decoded node_count == 2",      decoded.node_count == 2);
    CHECK("decoded seg_count == 7",       decoded.seg_count == 7);

    /* Strip # prefix */
    itx_plan_t decoded2;
    int rc2 = itx_decode_hash(hash + 1, &decoded2);  /* "l=eyJ..." */
    CHECK("decode without # works",       rc2 == 0);

    /* Invalid */
    itx_plan_t bad;
    int rc_bad = itx_decode_hash("!@#$%", &bad);
    CHECK("invalid hash returns -1",      rc_bad != 0);

    /* ── itx_build_node_urls ────────────────────────────────────────── */
    SECTION("itx_build_node_urls");
    itx_node_url_t urls[ITX_MAX_NODES];
    int url_count = 0;
    itx_build_node_urls(&plan, "https://interplanet.live/ltx.html", urls, &url_count);
    CHECK("url_count == 2",              url_count == 2);
    CHECK("urls[0].nodeId == N0",        strcmp(urls[0].node_id, "N0") == 0);
    CHECK("urls[0].role == HOST",        strcmp(urls[0].role, "HOST") == 0);
    CHECK("urls[0].url has ?node=N0",    strstr(urls[0].url, "?node=N0") != NULL);
    CHECK("urls[0].url has #l=",        strstr(urls[0].url, "#l=") != NULL);
    CHECK("urls[0].url has base",        strncmp(urls[0].url, "https://interplanet.live", 24) == 0);
    CHECK("urls[1].nodeId == N1",        strcmp(urls[1].node_id, "N1") == 0);
    CHECK("urls[1].role == PARTICIPANT", strcmp(urls[1].role, "PARTICIPANT") == 0);

    /* ── itx_generate_ics ───────────────────────────────────────────── */
    SECTION("itx_generate_ics");
    char ics[ITX_ICS_BUF];
    itx_generate_ics(&plan, ics);
    CHECK("ICS starts VCALENDAR",        strncmp(ics, "BEGIN:VCALENDAR", 15) == 0);
    CHECK("ICS has END:VCALENDAR",       strstr(ics, "END:VCALENDAR") != NULL);
    CHECK("ICS has BEGIN:VEVENT",        strstr(ics, "BEGIN:VEVENT") != NULL);
    CHECK("ICS has END:VEVENT",          strstr(ics, "END:VEVENT") != NULL);
    CHECK("ICS has VERSION:2.0",         strstr(ics, "VERSION:2.0") != NULL);
    CHECK("ICS has DTSTART",             strstr(ics, "DTSTART:") != NULL);
    CHECK("ICS has DTEND",               strstr(ics, "DTEND:") != NULL);
    CHECK("ICS has SUMMARY",             strstr(ics, "SUMMARY:") != NULL);
    CHECK("ICS has LTX:1",              strstr(ics, "LTX:1") != NULL);
    CHECK("ICS has LTX-PLANID",         strstr(ics, "LTX-PLANID:") != NULL);
    CHECK("ICS has LTX-QUANTUM:PT5M",   strstr(ics, "LTX-QUANTUM:PT5M") != NULL);
    CHECK("ICS has LTX-NODE",           strstr(ics, "LTX-NODE:") != NULL);
    CHECK("ICS has CRLF",               strstr(ics, "\r\n") != NULL);

    /* ── itx_format_hms ─────────────────────────────────────────────── */
    SECTION("itx_format_hms / itx_format_utc");
    char hms[12];
    itx_format_hms(0, hms);
    CHECK("formatHMS(0) == 00:00",       strcmp(hms, "00:00") == 0);
    itx_format_hms(30, hms);
    CHECK("formatHMS(30) == 00:30",      strcmp(hms, "00:30") == 0);
    itx_format_hms(59, hms);
    CHECK("formatHMS(59) == 00:59",      strcmp(hms, "00:59") == 0);
    itx_format_hms(60, hms);
    CHECK("formatHMS(60) == 01:00",      strcmp(hms, "01:00") == 0);
    itx_format_hms(3600, hms);
    CHECK("formatHMS(3600) == 01:00:00", strcmp(hms, "01:00:00") == 0);
    itx_format_hms(3661, hms);
    CHECK("formatHMS(3661) == 01:01:01", strcmp(hms, "01:01:01") == 0);
    itx_format_hms(7322, hms);
    CHECK("formatHMS(7322) == 02:02:02", strcmp(hms, "02:02:02") == 0);
    itx_format_hms(-1, hms);
    CHECK("formatHMS(-1) == 00:00",      strcmp(hms, "00:00") == 0);

    /* formatUTC: 2026-03-01T14:30:45Z = epoch 1772375445000 */
    char utc[16];
    itx_format_utc(1772375445000LL, utc);
    CHECK("formatUTC has time part",     strncmp(utc, "14:30:45", 8) == 0);
    CHECK("formatUTC ends UTC",          strstr(utc, "UTC") != NULL);
    itx_format_utc(0LL, utc);
    CHECK("formatUTC(0) == 00:00:00 UTC", strcmp(utc, "00:00:00 UTC") == 0);

    /* ── Attributed segments (speaker/label, 3.4.1) and JS string rules (#36) ── */
    SECTION("attributed segments");
    {
        itx_plan_t ap;
        rep_plan(&ap);
        char ahash[ITX_HASH_BUF], aid[ITX_PLAN_ID_LEN], jid[ITX_PLAN_ID_LEN];
        itx_encode_hash(&ap, ahash);
        char *aw = wire_of(ahash);
        const char *want_segs = "\"segments\":[{\"type\":\"PLAN_CONFIRM\",\"q\":2},{\"type\":\"TX\",\"q\":3,"
            "\"speaker\":\"N0\",\"label\":\"Ouverture: \xc3\xa9tat de la mission\"},{\"type\":\"RX\",\"q\":3},"
            "{\"type\":\"TX\",\"q\":2,\"speaker\":\"N1\",\"label\":\"R\xc3\xa9ponse \xf0\x9f\x94\xb4\"},"
            "{\"type\":\"BUFFER\",\"q\":1}]}";
        size_t wl = strlen(aw), sl = strlen(want_segs);
        CHECK("attributed wire segments (JS key order, absent omitted)",
              wl > sl && strcmp(aw + wl - sl, want_segs) == 0);
        itx_make_plan_id(&ap, aid);
        /* JS makePlanId of the same object (nodes before segments) */
        CHECK("attributed typed planId == JS", strcmp(aid, "LTX-20260315-EARTHHQ-MARS-L-1G-v2-1e382346") == 0);
        CHECK("attributed typed planId == JSON planId of wire",
              itx_make_plan_id_json(aw, jid) == 0 && strcmp(aid, jid) == 0);
        itx_plan_t back;
        CHECK("decode attributed hash", itx_decode_hash(ahash, &back) == 0);
        CHECK("decode keeps speaker/label", strcmp(back.segments[1].speaker, "N0") == 0 &&
              strcmp(back.segments[3].label, "R\xc3\xa9ponse \xf0\x9f\x94\xb4") == 0 &&
              back.segments[0].speaker[0] == '\0' && back.segments[0].label[0] == '\0');
        CHECK("decode keeps non-ASCII title", strcmp(back.title, ap.title) == 0);
        char bid[ITX_PLAN_ID_LEN];
        itx_make_plan_id(&back, bid);
        CHECK("decode round trip planId", strcmp(bid, aid) == 0);
        free(aw);

        itx_plan_t lp;
        rep_plan(&lp);
        lp.seg_count = 1;
        set_seg(&lp.segments[0], "RX", 2, NULL, "Q&A {\"x\"}");
        itx_encode_hash(&lp, ahash);
        aw = wire_of(ahash);
        CHECK("label without speaker", strstr(aw, "\"segments\":[{\"type\":\"RX\",\"q\":2,\"label\":\"Q&A {\\\"x\\\"}\"}]}") != NULL);
        CHECK("decode label with quote and brace",
              itx_decode_hash(ahash, &back) == 0 && strcmp(back.segments[0].label, "Q&A {\"x\"}") == 0);
        free(aw);

        /* Control characters, JS whitespace (/\s/ is Unicode-aware in JS) and
         * non-whitespace look-alikes (U+0085, U+200B) in node names. */
        itx_plan_t wp;
        rep_plan(&wp);
        snprintf(wp.title, sizeof(wp.title), "%s",
                 "C\x01\b\t\n\v\f\r\x1f\"\\/\x7f\xe2\x80\xa8\xe2\x80\xa9\xc3\xa9\xf0\x9f\x9a\x80");
        snprintf(wp.mode, sizeof(wp.mode), "LTX");
        set_node(&wp.nodes[0], "N0", "Earth\xc2\xa0\tHQ", "HOST", 0, "earth");
        set_node(&wp.nodes[1], "N1", "\xe3\x80\x80M\xe2\x80\x83" "a\xe2\x80\xa8rs", "PARTICIPANT", 840, "mars");
        set_node(&wp.nodes[2], "N2", "\xef\xbb\xbfL\xc2\x85u\xe2\x80\x8bna", "PARTICIPANT", 2, "moon");
        wp.seg_count = 2;
        set_seg(&wp.segments[0], "TX", 2, "N1", NULL);
        set_seg(&wp.segments[1], "RX", 2, NULL, "Q\\u0000&A");
        /* C strings cannot hold U+0000, so the JS vector's label is "Q\u0000&A"
         * spelt as the six characters \u0000: escape the backslash instead. */
        itx_make_plan_id(&wp, aid);
        itx_encode_hash(&wp, ahash);
        aw = wire_of(ahash);
        CHECK("JS whitespace + escaping planId == JS",
              strcmp(aid, "LTX-20260315-EARTHHQ-MARS-L\xc2\x85U\xe2\x80\x8b-v2-741793bf") == 0);
        const char *want_head = "{\"v\":2,\"title\":\"C\\u0001\\b\\t\\n\\u000b\\f\\r\\u001f\\\"\\\\/"
            "\x7f\xe2\x80\xa8\xe2\x80\xa9\xc3\xa9\xf0\x9f\x9a\x80\",";
        CHECK("escaping matches JSON.stringify", strncmp(aw, want_head, strlen(want_head)) == 0);        CHECK("typed planId == JSON planId of wire (escapes)",
              itx_make_plan_id_json(aw, jid) == 0 && strcmp(aid, jid) == 0);
        free(aw);
        char *ics = (char *)malloc(ITX_ICS_BUF);
        itx_generate_ics(&wp, ics);
        CHECK("ICS node id uses JS whitespace", strstr(ics, "LTX-NODE:ID=EARTH-HQ;ROLE=HOST") != NULL);
        free(ics);

        /* Lone UTF-16 surrogates (WTF-8 bytes): JSON.stringify writes \udxxx. */
        itx_plan_t sp;
        rep_plan(&sp);
        snprintf(sp.title, sizeof(sp.title), "%s", "x\xed\xa0\x80y\xed\xb0\x80z");
        snprintf(sp.segments[1].label, sizeof(sp.segments[1].label), "%s", "\xed\xaf\xbf");
        itx_make_plan_id(&sp, aid);
        itx_encode_hash(&sp, ahash);
        aw = wire_of(ahash);
        CHECK("lone surrogates escaped as JSON.stringify",
              strstr(aw, "\"title\":\"x\\ud800y\\udc00z\"") && strstr(aw, "\"label\":\"\\udbff\""));
        CHECK("lone surrogates typed planId == JS", strcmp(aid, "LTX-20260315-EARTHHQ-MARS-L-1G-v2-35164df8") == 0);
        CHECK("lone surrogates JSON planId == JS",
              itx_make_plan_id_json(aw, jid) == 0 && strcmp(jid, "LTX-20260315-EARTHHQ-MARS-L-1G-v2-35164df8") == 0);
        free(aw);
        char *q = itx_json_quote("\xed\xa0\xbd\xed\xba\x80");
        CHECK("CESU-8 pair joined", q && strcmp(q, "\"\xf0\x9f\x9a\x80\"") == 0);
        free(q);
        itx_json_t *hv = itx_json_parse("\"\\ud800\\u0041\"");
        char *hs = hv ? itx_json_stringify(hv) : NULL;
        CHECK("high surrogate then non-low kept apart", hs && strcmp(hs, "\"\\ud800A\"") == 0);
        free(hs);
        itx_json_free(hv);
    }

    /* ── Summary ─────────────────────────────────────────────────────── */
    printf("\n==========================================\n");
    printf("%d passed  %d failed\n", passed, failed);
    return failed > 0 ? 1 : 0;
}
