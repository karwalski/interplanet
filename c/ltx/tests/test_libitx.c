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

int main(void) {
    /* ── Constants ───────────────────────────────────────────────────── */
    SECTION("Constants");
    CHECK("VERSION not empty",              strlen(ITX_VERSION_STRING) > 0);
    CHECK("VERSION is 1.0.0",              strcmp(ITX_VERSION_STRING, "1.0.0") == 0);
    CHECK("DEFAULT_QUANTUM == 3",          ITX_DEFAULT_QUANTUM == 3);
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
    CHECK("quantum == 3",                  plan.quantum == 3);
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
    CHECK("segs[0].dur_min == 6",         segs[0].dur_min == 6);
    CHECK("segs[6].dur_min == 3",         segs[6].dur_min == 3);
    /* Contiguous segments */
    for (int i = 0; i < seg_count - 1; i++) {
        char name[64];
        snprintf(name, sizeof(name), "segs[%d] contiguous", i);
        CHECK(name, segs[i].end_ms == segs[i + 1].start_ms);
    }

    /* ── itx_total_min ──────────────────────────────────────────────── */
    SECTION("itx_total_min");
    int total = itx_total_min(&plan);
    CHECK("totalMin == 39",               total == 39);
    /* Verify: 13 quanta × 3 min = 39 */
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
    CHECK("ICS has LTX-QUANTUM:PT3M",   strstr(ics, "LTX-QUANTUM:PT3M") != NULL);
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

    /* ── Summary ─────────────────────────────────────────────────────── */
    printf("\n==========================================\n");
    printf("%d passed  %d failed\n", passed, failed);
    return failed > 0 ? 1 : 0;
}
