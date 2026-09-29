/**
 * test_plan_json.c -- libitx wire-format plan tests (issue #27): golden
 * planId vectors (spec/golden/plan-ids.json), validatePlan and the reserved
 * streams / branching fields, mirroring javascript/ltx/tests/run.js.
 *
 * Usage: test_plan_json [path/to/plan-ids.json]
 *        (default ../../spec/golden/plan-ids.json, i.e. run from c/ltx)
 */

#include "../include/libitx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int passed = 0, failed = 0;

#define CHECK(name, cond) do { \
    if (cond) { passed++; } \
    else { failed++; printf("FAIL: %s\n", name); } \
} while (0)

#define SECTION(s) printf("\n-- %s --\n", s)

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *b = (char *)malloc((size_t)n + 1);
    if (!b) { fclose(f); return NULL; }
    size_t got = fread(b, 1, (size_t)n, f);
    fclose(f);
    b[got] = '\0';
    return b;
}

static const itx_json_t *by_name(const itx_json_t *vectors, const char *name) {
    for (size_t i = 0; i < itx_json_len(vectors); i++) {
        const itx_json_t *v = itx_json_at(vectors, i);
        if (strcmp(itx_json_str(itx_json_get(v, "name")), name) == 0) return v;
    }
    return NULL;
}

/** plan JSON text with `,"key":value` appended (JSON.parse: last key wins,
 *  keeping the first position, like a spread override). Caller frees. */
static char *with_field(const char *plan_json, const char *key, const char *value_json) {
    size_t n = strlen(plan_json);
    char *out = (char *)malloc(n + strlen(key) + strlen(value_json) + 8);
    memcpy(out, plan_json, n - 1); /* drop the closing brace */
    sprintf(out + n - 1, ",\"%s\":%s}", key, value_json);
    return out;
}

static int has_code(const char *plan_json, const char *code) {
    itx_plan_validation_t r;
    itx_validate_plan_json(plan_json, &r);
    return itx_validation_has_code(&r, code);
}

static int has_code_with(const char *plan_json, const char *key, const char *value_json, const char *code) {
    char *p = with_field(plan_json, key, value_json);
    int rc = has_code(p, code);
    free(p);
    return rc;
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "../../spec/golden/plan-ids.json";
    char *text = read_file(path);
    if (!text) { printf("cannot read %s\n", path); return 1; }
    itx_json_t *golden = itx_json_parse(text);
    free(text);
    if (!golden) { printf("cannot parse %s\n", path); return 1; }
    const itx_json_t *vectors = itx_json_get(golden, "vectors");

    /* ── Golden planId vectors ───────────────────────────────────────── */
    SECTION("golden planId vectors");
    CHECK("golden vectors present", itx_json_len(vectors) >= 9);
    for (size_t i = 0; i < itx_json_len(vectors); i++) {
        const itx_json_t *gv = itx_json_at(vectors, i);
        const itx_json_t *plan = itx_json_get(gv, "plan");
        char id[ITX_PLAN_ID_LEN], label[160];
        int rc = itx_make_plan_id_value(plan, id);
        snprintf(label, sizeof(label), "golden planId %s", itx_json_str(itx_json_get(gv, "name")));
        if (rc != 0 || strcmp(id, itx_json_str(itx_json_get(gv, "planId"))) != 0) printf("  got %s\n", rc == 0 ? id : "(error)");
        CHECK(label, rc == 0 && strcmp(id, itx_json_str(itx_json_get(gv, "planId"))) == 0);
        /* Same from the JSON text (the parser keeps key order). */
        char *plan_text = itx_json_stringify(plan);
        char id2[ITX_PLAN_ID_LEN];
        snprintf(label, sizeof(label), "golden planId from text %s", itx_json_str(itx_json_get(gv, "name")));
        CHECK(label, itx_make_plan_id_json(plan_text, id2) == 0 && strcmp(id, id2) == 0);
        free(plan_text);
        const char *want_hash = itx_json_str(itx_json_get(gv, "planHash"));
        if (want_hash) {
            char hex[65];
            snprintf(label, sizeof(label), "golden planHash %s", itx_json_str(itx_json_get(gv, "name")));
            CHECK(label, itx_plan_hash_value(plan, hex) == 0 && strcmp(hex, want_hash) == 0);
        }
    }
    CHECK("golden v2 freeze anchor", strcmp(itx_json_str(itx_json_get(by_name(vectors, "v2-freeze-check"), "planId")), "LTX-20260801-EARTHHQ-MARS-v2-d132e85d") == 0);
    CHECK("golden v2 unicode anchor", strcmp(itx_json_str(itx_json_get(by_name(vectors, "v2-unicode-title"), "planId")), "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8") == 0);
    CHECK("golden v2 order-sensitive", strcmp(itx_json_str(itx_json_get(by_name(vectors, "v2-createPlan-default"), "planId")),
                                              itx_json_str(itx_json_get(by_name(vectors, "v2-key-order-sensitive"), "planId"))) != 0);
    CHECK("golden v3 order-insensitive", strcmp(itx_json_str(itx_json_get(by_name(vectors, "v3-upgrade-delays"), "planId")),
                                                itx_json_str(itx_json_get(by_name(vectors, "v3-key-order-insensitive"), "planId"))) == 0);
    CHECK("golden v3 amendment chain hash",
          strcmp(itx_json_str(itx_json_get(itx_json_get(by_name(vectors, "v3-amendment"), "plan"), "prevPlanHash")),
                 itx_json_str(itx_json_get(by_name(vectors, "v3-upgrade-delays"), "planHash"))) == 0);
    CHECK("default quantum is 5", ITX_DEFAULT_QUANTUM == 5);

    /* Typed itx_make_plan_id: fixed key order v,title,start,quantum,mode,
     * nodes,segments; the v2-key-order-sensitive vector uses that order. */
    {
        itx_plan_t p;
        itx_create_plan(&p, "Golden Default", "2026-03-15T14:00:00.000Z", 840);
        char id[ITX_PLAN_ID_LEN];
        itx_make_plan_id(&p, id);
        CHECK("typed make_plan_id matches nodes-first vector",
              strcmp(id, itx_json_str(itx_json_get(by_name(vectors, "v2-key-order-sensitive"), "planId"))) == 0);
        /* v2 hash over UTF-16 code units (expected from ltx-sdk.js on the
         * unicode vector in typed key order). */
        itx_create_plan(&p, "R\xc3\xa9union Terre \xe2\x86\x94 Mars \xf0\x9f\x9a\x80", "2026-12-31T23:55:00.000Z", 860);
        strcpy(p.mode, "LTX-LIVE");
        p.seg_count = 3;
        strcpy(p.segments[0].type, "PLAN_CONFIRM"); p.segments[0].q = 2;
        strcpy(p.segments[1].type, "TX");           p.segments[1].q = 2;
        strcpy(p.segments[2].type, "RX");           p.segments[2].q = 2;
        itx_make_plan_id(&p, id);
        CHECK("typed make_plan_id hashes UTF-16", strcmp(id, "LTX-20261231-EARTHHQ-MARS-v2-06a7c14c") == 0);
    }

    /* ── Serialisation ──────────────────────────────────────────────── */
    SECTION("JS-compatible serialisation");
    {
        char *c1 = itx_canonical_json("{\"b\":[1e21,1e-7,0.5,860.0,-2.5e-9],\"\\ud83d\\ude80\":1,\"\\uff21\":2}");
        CHECK("canonical JS numbers + UTF-16 key order",
              c1 && strcmp(c1, "{\"b\":[1e+21,1e-7,0.5,860,-2.5e-9],\"\xf0\x9f\x9a\x80\":1,\"\xef\xbc\xa1\":2}") == 0);
        free(c1);
        itx_json_t *e = itx_json_parse("[\"a\\bb\\fc\\u0001\\\"\",{\"dup\":1,\"x\":0,\"dup\":2}]");
        char *s = itx_json_stringify(e);
        CHECK("stringify escapes + duplicate key", s && strcmp(s, "[\"a\\bb\\fc\\u0001\\\"\",{\"dup\":2,\"x\":0}]") == 0);
        free(s);
        itx_json_free(e);
        CHECK("parse rejects trailing data", itx_json_parse("{} x") == NULL);
        unsigned char dg[32];
        itx_sha256("abc", 3, dg);
        CHECK("sha256(abc)", dg[0] == 0xba && dg[1] == 0x78 && dg[31] == 0xad);
        itx_sha256("", 0, dg);
        CHECK("sha256(empty)", dg[0] == 0xe3 && dg[31] == 0x55);
    }

    /* ── validatePlan + reserved fields ─────────────────────────────── */
    SECTION("validatePlan: reserved fields");
    for (size_t i = 0; i < itx_json_len(vectors); i++) {
        const itx_json_t *gv = itx_json_at(vectors, i);
        itx_plan_validation_t r;
        char label[160];
        snprintf(label, sizeof(label), "validatePlan accepts golden %s", itx_json_str(itx_json_get(gv, "name")));
        CHECK(label, itx_validate_plan_value(itx_json_get(gv, "plan"), &r) == 1);
        if (!r.valid && r.error_count) printf("  %s %s\n", r.errors[0].code, r.errors[0].path);
    }
    char *base = itx_json_stringify(itx_json_get(by_name(vectors, "v3-upgrade-delays"), "plan"));
    char *v2 = itx_json_stringify(itx_json_get(by_name(vectors, "v2-freeze-check"), "plan"));
    {
        char *p = with_field(base, "streams", "[]");
        itx_plan_validation_t r;
        CHECK("validatePlan v3 empty streams ok", itx_validate_plan_json(p, &r) == 1);
        free(p);
        p = with_field(base, "streams", "[{\"id\":\"S1\"}]");
        itx_validate_plan_json(p, &r);
        CHECK("validatePlan non-empty streams", !r.valid && itx_validation_has_code(&r, "reserved_streams"));
        int path_ok = 0;
        for (int i = 0; i < r.error_count; i++)
            if (strcmp(r.errors[i].code, "reserved_streams") == 0) { path_ok = strcmp(r.errors[i].path, "streams") == 0; break; }
        CHECK("validatePlan streams error path", path_ok);
        CHECK("reserved_field_code streams", itx_reserved_field_code(p) && strcmp(itx_reserved_field_code(p), "reserved_streams") == 0);
        free(p);
    }
    CHECK("validatePlan streams non-array", has_code_with(base, "streams", "\"S1\"", "reserved_streams"));
    CHECK("validatePlan segment stream", has_code_with(base, "segments", "[{\"type\":\"TX\",\"q\":1,\"stream\":\"S1\"}]", "reserved_streams"));
    CHECK("validatePlan branches", has_code_with(base, "branches", "[]", "reserved_branching"));
    CHECK("validatePlan branching", has_code_with(base, "branching", "{\"mode\":\"local\"}", "reserved_branching"));
    {
        char *p = with_field(base, "segments", "[{\"type\":\"CAUCUS\",\"q\":1,\"branch\":\"B1\"}]");
        itx_plan_validation_t r;
        itx_validate_plan_json(p, &r);
        CHECK("validatePlan segment branch", itx_validation_has_code(&r, "reserved_branching") &&
                                             strcmp(r.errors[0].path, "segments[0].branch") == 0);
        CHECK("reserved_field_code branching", strcmp(itx_reserved_field_code(p), "reserved_branching") == 0);
        free(p);
    }
    CHECK("validatePlan v2 streams is v3 field", has_code_with(v2, "streams", "[]", "v3_field_in_v2"));
    CHECK("validatePlan v2 branching", has_code_with(v2, "branching", "true", "reserved_branching"));
    CHECK("reserved_field_code none on golden", itx_reserved_field_code(base) == NULL);

    SECTION("validatePlan: structure");
    CHECK("validatePlan non-object", has_code("null", "not_an_object"));
    CHECK("validatePlan invalid JSON", has_code("{", "not_an_object"));
    CHECK("validatePlan bad version", has_code_with(v2, "v", "7", "invalid_version"));
    CHECK("validatePlan host not first", has_code_with(v2, "nodes",
          "[{\"id\":\"N1\",\"name\":\"Mars Hab-01\",\"role\":\"PARTICIPANT\",\"delay\":860,\"location\":\"mars\"},"
          "{\"id\":\"N0\",\"name\":\"Earth HQ\",\"role\":\"HOST\",\"delay\":0,\"location\":\"earth\"}]", "invalid_host"));
    CHECK("validatePlan unsorted delays key", has_code_with(base, "delays", "{\"N1|N0\":860}", "invalid_delays"));
    CHECK("validatePlan unknown speaker", has_code_with(v2, "segments", "[{\"type\":\"TX\",\"q\":1,\"speaker\":\"N9\"}]", "unknown_speaker"));
    CHECK("validatePlan quantum out of range", has_code_with(v2, "quantum", "0", "invalid_quantum"));
    CHECK("validatePlan non-integer quantum", has_code_with(v2, "quantum", "2.5", "invalid_quantum"));
    CHECK("validatePlan bad start", has_code_with(v2, "start", "\"yesterday\"", "invalid_field"));
    CHECK("validatePlan duplicate node id", has_code_with(v2, "nodes",
          "[{\"id\":\"N0\",\"name\":\"A\",\"role\":\"HOST\",\"delay\":0},{\"id\":\"N0\",\"name\":\"B\",\"role\":\"PARTICIPANT\",\"delay\":1}]",
          "duplicate_node_id"));
    CHECK("validatePlan bad prevPlanHash", has_code_with(base, "prevPlanHash", "\"ABC\"", "invalid_field"));
    free(base);
    free(v2);
    itx_json_free(golden);

    printf("\n==========================================\n");
    printf("%d passed  %d failed\n", passed, failed);
    return failed > 0 ? 1 : 0;
}
