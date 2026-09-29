/* Interop driver for c/ltx (see scripts/interop/run.js). */
#include "libitx.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void set_node(itx_node_t *n, const char *id, const char *name, const char *role,
                     int delay, const char *location) {
    snprintf(n->id, sizeof n->id, "%s", id);
    snprintf(n->name, sizeof n->name, "%s", name);
    snprintf(n->role, sizeof n->role, "%s", role);
    n->delay = delay;
    snprintf(n->location, sizeof n->location, "%s", location);
}

static int b64val(int c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '-' || c == '+') return 62;
    if (c == '_' || c == '/') return 63;
    return -1;
}

/* Decode unpadded base64url into out; returns the byte count. */
static size_t b64url_decode(const char *s, unsigned char *out) {
    size_t o = 0;
    unsigned int acc = 0;
    int bits = 0;
    for (; *s; s++) {
        int v = b64val((unsigned char)*s);
        if (v < 0) break;
        acc = (acc << 6) | (unsigned int)v;
        bits += 6;
        if (bits >= 8) { bits -= 8; out[o++] = (unsigned char)(acc >> bits); }
    }
    return o;
}

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc((size_t)n + 1);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) { perror(path); exit(1); }
    buf[n] = '\0';
    fclose(f);
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    const char *in_dir = argv[1], *out_dir = argv[2];
    char path[4096], id[ITX_PLAN_ID_LEN];

    itx_plan_t plan;
    itx_create_plan(&plan, "R\xc3\xa9union Mars \xf0\x9f\x9a\x80", "2026-03-15T14:00:00.000Z", 840);
    plan.quantum = 3;
    snprintf(plan.mode, sizeof plan.mode, "%s", "LTX-ASYNC");
    plan.node_count = 3;
    set_node(&plan.nodes[0], "N0", "Earth HQ", "HOST", 0, "earth");
    set_node(&plan.nodes[1], "N1", "Mars Hab-01", "PARTICIPANT", 840, "mars");
    set_node(&plan.nodes[2], "N2", "L-1 Gateway", "PARTICIPANT", 2, "moon");
    /* itx_seg_tmpl_t is (type, q) only: no speaker/label. */
    static const struct { const char *t; int q; } segs[] = {
        {"PLAN_CONFIRM", 2}, {"TX", 3}, {"RX", 3}, {"TX", 2}, {"BUFFER", 1}};
    plan.seg_count = 5;
    for (int i = 0; i < 5; i++) {
        snprintf(plan.segments[i].type, sizeof plan.segments[i].type, "%s", segs[i].t);
        plan.segments[i].q = segs[i].q;
    }
    printf("NOTE itx_plan_t: no speaker/label, no v3 (the C port builds no v3 plans)\n");

    char hash[ITX_HASH_BUF];
    itx_encode_hash(&plan, hash);
    unsigned char wire[ITX_HASH_BUF];
    size_t n = b64url_decode(hash + 3, wire);
    snprintf(path, sizeof path, "%s/wire-v2.json", out_dir);
    FILE *f = fopen(path, "wb");
    fwrite(wire, 1, n, f);
    fclose(f);
    itx_make_plan_id(&plan, id);
    printf("ID_V2 %s\n", id);

    for (int v = 2; v <= 3; v++) {
        snprintf(path, sizeof path, "%s/js-v%d.json", in_dir, v);
        char *json = read_file(path);
        if (itx_make_plan_id_json(json, id) != 0) { fprintf(stderr, "itx_make_plan_id_json failed\n"); return 1; }
        printf("JS_V%d %s\n", v, id);
        free(json);
    }
    return 0;
}
