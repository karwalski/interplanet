// unit_test.zig — LTX Zig library unit tests
//
// Standalone executable: imports interplanet_ltx.zig and runs check() calls
// against the typed v2 model. Expected planIds, wire JSON and share tokens
// are the output of javascript/ltx/ltx-sdk.js for the same inputs.
// Exits with code 1 if any check fails.

const std = @import("std");
const ltx = @import("interplanet_ltx.zig");

var passed: u32 = 0;
var failed: u32 = 0;

fn check(desc: []const u8, ok: bool) void {
    if (ok) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n", .{desc});
    }
}

fn checkStr(desc: []const u8, got: []const u8, expected: []const u8) void {
    if (std.mem.eql(u8, got, expected)) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  got:      {s}\n  expected: {s}\n", .{ desc, got, expected });
    }
}

fn checkInt(desc: []const u8, got: i64, expected: i64) void {
    if (got == expected) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  got: {d}  expected: {d}\n", .{ desc, got, expected });
    }
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn checkContains(desc: []const u8, haystack: []const u8, needle: []const u8) void {
    if (contains(haystack, needle)) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}: expected to contain: {s}\n", .{ desc, needle });
    }
}

// JS: createPlan({ title: 'Test Meeting Alpha', start: '2040-01-15T14:00:00.000Z' })
const ALPHA_JSON =
    \\{"v":2,"title":"Test Meeting Alpha","start":"2040-01-15T14:00:00.000Z","quantum":5,"mode":"LTX","segments":[{"type":"PLAN_CONFIRM","q":2},{"type":"TX","q":2},{"type":"RX","q":2},{"type":"CAUCUS","q":2},{"type":"TX","q":2},{"type":"RX","q":2},{"type":"BUFFER","q":1}],"nodes":[{"id":"N0","name":"Earth HQ","role":"HOST","delay":0,"location":"earth"},{"id":"N1","name":"Mars Hab-01","role":"PARTICIPANT","delay":0,"location":"mars"}]}
;
const ALPHA_ID = "LTX-20400115-EARTHHQ-MARS-v2-b6f41f93";
const ALPHA_HASH = "#l=eyJ2IjoyLCJ0aXRsZSI6IlRlc3QgTWVldGluZyBBbHBoYSIsInN0YXJ0IjoiMjA0MC0wMS0xNVQxNDowMDowMC4wMDBaIiwicXVhbnR1bSI6NSwibW9kZSI6IkxUWCIsInNlZ21lbnRzIjpbeyJ0eXBlIjoiUExBTl9DT05GSVJNIiwicSI6Mn0seyJ0eXBlIjoiVFgiLCJxIjoyfSx7InR5cGUiOiJSWCIsInEiOjJ9LHsidHlwZSI6IkNBVUNVUyIsInEiOjJ9LHsidHlwZSI6IlRYIiwicSI6Mn0seyJ0eXBlIjoiUlgiLCJxIjoyfSx7InR5cGUiOiJCVUZGRVIiLCJxIjoxfV0sIm5vZGVzIjpbeyJpZCI6Ik4wIiwibmFtZSI6IkVhcnRoIEhRIiwicm9sZSI6IkhPU1QiLCJkZWxheSI6MCwibG9jYXRpb24iOiJlYXJ0aCJ9LHsiaWQiOiJOMSIsIm5hbWUiOiJNYXJzIEhhYi0wMSIsInJvbGUiOiJQQVJUSUNJUEFOVCIsImRlbGF5IjowLCJsb2NhdGlvbiI6Im1hcnMifV19";

// The interop representative plan (scripts/interop/plan.js): non-ASCII
// title and labels with astral characters, three nodes, speaker/label.
const REP_NODES = [_]ltx.Node{
    .{ .id = "N0", .name = "Earth HQ", .role = "HOST", .delay = 0, .location = "earth" },
    .{ .id = "N1", .name = "Mars Hab-01", .role = "PARTICIPANT", .delay = 840, .location = "mars" },
    .{ .id = "N2", .name = "L-1 Gateway", .role = "PARTICIPANT", .delay = 2, .location = "moon" },
};
const REP_SEGS = [_]ltx.SegmentTemplate{
    .{ .seg_type = "PLAN_CONFIRM", .q = 2 },
    .{ .seg_type = "TX", .q = 3, .speaker = "N0", .label = "Ouverture: état de la mission" },
    .{ .seg_type = "RX", .q = 3 },
    .{ .seg_type = "TX", .q = 2, .speaker = "N1", .label = "Réponse 🔴" },
    .{ .seg_type = "BUFFER", .q = 1 },
};
const REP_ID = "LTX-20260315-EARTHHQ-MARS-L-1G-v2-09310844";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Section 1: Constants ─────────────────────────────────────────────

    checkStr("VERSION = 1.1.0", ltx.VERSION, "1.1.0");
    checkInt("DEFAULT_QUANTUM = 5", ltx.DEFAULT_QUANTUM, 5);
    check("DEFAULT_API_BASE contains interplanettime.net", contains(ltx.DEFAULT_API_BASE, "interplanettime.net"));
    checkInt("SEG_TYPES length = 6", ltx.SEG_TYPES.len, 6);
    checkStr("SEG_TYPES[0] = PLAN_CONFIRM", ltx.SEG_TYPES[0], "PLAN_CONFIRM");
    checkStr("SEG_TYPES[3] = CAUCUS", ltx.SEG_TYPES[3], "CAUCUS");
    checkStr("SEG_TYPES[5] = MERGE", ltx.SEG_TYPES[5], "MERGE");
    checkInt("DEFAULT_SEGMENTS length = 7", ltx.DEFAULT_SEGMENTS.len, 7);
    checkStr("DEFAULT_SEGMENTS[0].type = PLAN_CONFIRM", ltx.DEFAULT_SEGMENTS[0].seg_type, "PLAN_CONFIRM");
    checkStr("DEFAULT_SEGMENTS[6].type = BUFFER", ltx.DEFAULT_SEGMENTS[6].seg_type, "BUFFER");
    checkInt("DEFAULT_SEGMENTS total quanta = 13", blk: {
        var t: u32 = 0;
        for (ltx.DEFAULT_SEGMENTS) |s| t += s.q;
        break :blk t;
    }, 13);

    // ── Section 2: formatHms ─────────────────────────────────────────────

    const hms_cases = [_]struct { m: u32, s: []const u8 }{
        .{ .m = 90, .s = "1h 30m" }, .{ .m = 45, .s = "45m" }, .{ .m = 120, .s = "2h" }, .{ .m = 0, .s = "0m" },
        .{ .m = 61, .s = "1h 1m" },  .{ .m = 60, .s = "1h" },  .{ .m = 1, .s = "1m" },   .{ .m = 150, .s = "2h 30m" },
    };
    for (hms_cases) |c| {
        const s = try ltx.formatHms(allocator, c.m);
        defer allocator.free(s);
        checkStr("formatHms", s, c.s);
    }

    // ── Section 3: createPlan defaults (v2 schema) ───────────────────────

    {
        const p = try ltx.createPlan(allocator, .{});
        defer ltx.deinitPlan(allocator, p);
        checkInt("default plan v = 2 (number)", p.v, 2);
        checkStr("default plan title", p.title, "LTX Session");
        checkInt("default plan quantum = 5", p.quantum, 5);
        checkStr("default plan mode = LTX", p.mode, "LTX");
        checkInt("default plan nodes = 2", @intCast(p.nodes.len), 2);
        checkInt("default plan segments = 7", @intCast(p.segments.len), 7);
        checkStr("default host id N0", p.nodes[0].id, "N0");
        checkStr("default host name", p.nodes[0].name, "Earth HQ");
        checkStr("default host role HOST", p.nodes[0].role, "HOST");
        checkInt("default host delay 0", p.nodes[0].delay, 0);
        checkStr("default host location", p.nodes[0].location, "earth");
        checkStr("default remote id N1", p.nodes[1].id, "N1");
        checkStr("default remote name", p.nodes[1].name, "Mars Hab-01");
        checkStr("default remote role PARTICIPANT", p.nodes[1].role, "PARTICIPANT");
        checkStr("default remote location", p.nodes[1].location, "mars");
        // Default start: whole minute, toISOString form, ~5 min from now.
        check("default start is toISOString form", p.start.len == 24 and std.mem.endsWith(u8, p.start, ":00.000Z"));
        const delta = ltx.parseIsoMs(p.start) - std.time.milliTimestamp();
        check("default start is 4..5 min ahead", delta > 4 * 60_000 - 1000 and delta <= 5 * 60_000);
        checkInt("default totalMin = 65", ltx.totalMin(p), 65);
    }

    // ── Section 4: createPlan / makePlanId / wire JSON match JS ──────────

    {
        const p = try ltx.createPlan(allocator, .{ .title = "Test Meeting Alpha", .start = "2040-01-15T14:00:00.000Z" });
        defer ltx.deinitPlan(allocator, p);
        const json = try ltx.planToJson(allocator, p);
        defer allocator.free(json);
        checkStr("wire JSON = JSON.stringify(createPlan(...))", json, ALPHA_JSON);
        const id = try ltx.makePlanId(allocator, p);
        defer allocator.free(id);
        checkStr("makePlanId = JS makePlanId", id, ALPHA_ID);
        const hash = try ltx.encodeHash(allocator, p);
        defer allocator.free(hash);
        checkStr("encodeHash = JS encodeHash", hash, ALPHA_HASH);
        checkInt("totalMin = 65", ltx.totalMin(p), 65);

        // decodeHash returns the wire JSON; every prefix form accepted
        const d1 = try ltx.decodeHash(allocator, hash);
        defer allocator.free(d1);
        checkStr("decodeHash(#l=...)", d1, ALPHA_JSON);
        const d2 = try ltx.decodeHash(allocator, hash[1..]);
        defer allocator.free(d2);
        checkStr("decodeHash(l=...)", d2, ALPHA_JSON);
        const d3 = try ltx.decodeHash(allocator, hash[3..]);
        defer allocator.free(d3);
        checkStr("decodeHash(raw token)", d3, ALPHA_JSON);

        // planFromJson round trip reproduces the same wire JSON and id
        const back = try ltx.planFromJson(allocator, d1);
        defer ltx.deinitPlan(allocator, back);
        const back_json = try ltx.planToJson(allocator, back);
        defer allocator.free(back_json);
        checkStr("planFromJson -> planToJson round-trips", back_json, ALPHA_JSON);
        const back_id = try ltx.makePlanId(allocator, back);
        defer allocator.free(back_id);
        checkStr("planFromJson keeps the planId", back_id, ALPHA_ID);
    }
    {
        const p = try ltx.createPlan(allocator, .{
            .title = "My Meeting",
            .start = "2040-06-01T10:00:00.000Z",
            .quantum = 10,
            .host_name = "Lunar Station",
            .host_location = "moon",
            .remote_name = "Europa Base",
            .remote_location = "europa",
            .delay = 1200,
        });
        defer ltx.deinitPlan(allocator, p);
        checkStr("custom host name", p.nodes[0].name, "Lunar Station");
        checkStr("custom remote location", p.nodes[1].location, "europa");
        checkInt("custom remote delay", p.nodes[1].delay, 1200);
        checkInt("custom totalMin = 130", ltx.totalMin(p), 130);
        const id = try ltx.makePlanId(allocator, p);
        defer allocator.free(id);
        checkStr("custom makePlanId = JS (HOSTSTR 8, NODESTR 4)", id, "LTX-20400601-LUNARSTA-EURO-v2-9cc339ba");
    }

    // ── Section 5: representative interop plan (UTF-16 hash, L-1G) ───────

    {
        const p = try ltx.createPlan(allocator, .{
            .title = "Réunion Mars 🚀",
            .start = "2026-03-15T14:00:00.000Z",
            .quantum = 3,
            .mode = "LTX-ASYNC",
            .nodes = &REP_NODES,
            .segments = &REP_SEGS,
        });
        defer ltx.deinitPlan(allocator, p);
        const id = try ltx.makePlanId(allocator, p);
        defer allocator.free(id);
        checkStr("representative plan makePlanId = JS", id, REP_ID);
        const json = try ltx.planToJson(allocator, p);
        defer allocator.free(json);
        checkContains("wire has speaker/label", json, "{\"type\":\"TX\",\"q\":3,\"speaker\":\"N0\",\"label\":\"Ouverture: état de la mission\"}");
        check("wire key order: segments before nodes", std.mem.indexOf(u8, json, "\"segments\"").? < std.mem.indexOf(u8, json, "\"nodes\"").?);
        checkContains("wire v is a number", json, "{\"v\":2,");
        check("UTF-16 hash differs from UTF-8 byte hash", ltx.imul31Utf16(json) != blk: {
            var h: u32 = 0;
            for (json) |c| h = h *% 31 +% @as(u32, c);
            break :blk h;
        });

        // computeSegments (JS computeSegments)
        const segs = try ltx.computeSegments(allocator, p);
        defer allocator.free(segs);
        checkInt("computeSegments count", @intCast(segs.len), 5);
        checkInt("seg[0] start = plan start", segs[0].start_ms, ltx.parseIsoMs("2026-03-15T14:00:00.000Z"));
        checkInt("seg[1] start 14:06", segs[1].start_ms, ltx.parseIsoMs("2026-03-15T14:06:00.000Z"));
        checkInt("seg[4] end 14:33", segs[4].end_ms, ltx.parseIsoMs("2026-03-15T14:33:00.000Z"));
        checkInt("seg[1] durMin 9", segs[1].dur_min, 9);
        checkInt("seg[4] durMin 3", segs[4].dur_min, 3);
        checkStr("seg[1] type TX", segs[1].seg_type, "TX");
        check("seg[1] speaker N0", segs[1].speaker != null and std.mem.eql(u8, segs[1].speaker.?, "N0"));
        check("seg[2] no speaker", segs[2].speaker == null);
        var iso_buf: [32]u8 = undefined;
        checkStr("formatIsoMs", ltx.formatIsoMs(&iso_buf, segs[4].end_ms), "2026-03-15T14:33:00.000Z");

        // buildDelayMatrix / pairDelay (§3.7.3: sum via HOST)
        const m = try ltx.buildDelayMatrix(allocator, p);
        defer allocator.free(m);
        checkInt("delay matrix pairs = 6", @intCast(m.len), 6);
        checkStr("m[0] N0->N1", m[0].to_id, "N1");
        checkInt("m[0] = 840", m[0].delay_seconds, 840);
        checkInt("m[1] N0->N2 = 2", m[1].delay_seconds, 2);
        checkInt("m[3] N1->N2 = 842 (sum)", m[3].delay_seconds, 842);
        checkInt("m[5] N2->N1 = 842 (symmetric)", m[5].delay_seconds, 842);
        checkInt("pairDelay same node = 0", try ltx.pairDelay(p, "N1", "N1"), 0);
        check("pairDelay unknown node errors", if (ltx.pairDelay(p, "N0", "X")) |_| false else |_| true);

        // buildNodeUrls (JS buildNodeUrls)
        const urls = try ltx.buildNodeUrls(allocator, p, "https://interplanet.live/ltx.html?x=1#a");
        defer ltx.freeNodeUrls(allocator, urls);
        checkInt("buildNodeUrls count = 3", @intCast(urls.len), 3);
        checkStr("url[2].node_id", urls[2].node_id, "N2");
        checkStr("url[2].role", urls[2].role, "PARTICIPANT");
        check("url[2] strips query and fragment", std.mem.startsWith(u8, urls[2].url, "https://interplanet.live/ltx.html?node=N2#l=eyJ2IjoyLCJ0aXRsZSI6IlLDqXVuaW9uIE1hcnMg8J-agCIs"));
        const hash = try ltx.encodeHash(allocator, p);
        defer allocator.free(hash);
        check("url[2] carries encodeHash", std.mem.endsWith(u8, urls[2].url, hash));
    }

    // ── Section 6: HOSTSTR / NODESTR rules ───────────────────────────────

    {
        // Whitespace (incl. tab) stripped, upper-cased (ß -> SS, Latin-1),
        // truncated in UTF-16 units (an astral char counts 2).
        const nodes = [_]ltx.Node{
            .{ .id = "A", .name = "straße  größe\tÿ", .role = "HOST", .location = "earth" },
            .{ .id = "B", .name = "  émile x", .role = "PARTICIPANT", .delay = 5, .location = "mars" },
            .{ .id = "C", .name = "🚀🚀🚀", .role = "OBSERVER", .delay = 5, .location = "moon" },
        };
        const p = try ltx.createPlan(allocator, .{ .title = "x", .start = "2040-01-15T14:00:00.000Z", .nodes = &nodes });
        defer ltx.deinitPlan(allocator, p);
        const id = try ltx.makePlanId(allocator, p);
        defer allocator.free(id);
        checkStr("name tokens match JS", id, "LTX-20400115-STRASSEG-ÉMIL-🚀🚀-v2-f01ae8de");
    }
    {
        const nodes = [_]ltx.Node{.{ .id = "A", .name = "Earth HQ", .role = "HOST", .location = "earth" }};
        const p = try ltx.createPlan(allocator, .{ .title = "Solo", .start = "2040-01-15T14:00:00.000Z", .nodes = &nodes });
        defer ltx.deinitPlan(allocator, p);
        const id = try ltx.makePlanId(allocator, p);
        defer allocator.free(id);
        checkStr("single-node plan NODESTR = RX", id, "LTX-20400115-EARTHHQ-RX-v2-83ef3d37");
    }

    // ── Section 7: generateIcs ───────────────────────────────────────────

    {
        const p = try ltx.createPlan(allocator, .{ .title = "Test Meeting Alpha", .start = "2040-01-15T14:00:00.000Z" });
        defer ltx.deinitPlan(allocator, p);
        const ics = try ltx.generateIcs(allocator, p);
        defer allocator.free(ics);
        check("ics starts with BEGIN:VCALENDAR", std.mem.startsWith(u8, ics, "BEGIN:VCALENDAR\r\n"));
        check("ics ends with END:VCALENDAR", std.mem.endsWith(u8, ics, "\r\nEND:VCALENDAR"));
        checkContains("ics UID", ics, "UID:" ++ ALPHA_ID ++ "@interplanet.live\r\n");
        checkContains("ics DTSTART", ics, "DTSTART:20400115T140000Z\r\n");
        checkContains("ics DTEND = start + 65 min", ics, "DTEND:20400115T150500Z\r\n");
        checkContains("ics SUMMARY", ics, "SUMMARY:Test Meeting Alpha\r\n");
        checkContains("ics PLANID", ics, "LTX-PLANID:" ++ ALPHA_ID ++ "\r\n");
        checkContains("ics QUANTUM", ics, "LTX-QUANTUM:PT5M\r\n");
        checkContains("ics SEGMENT-TEMPLATE", ics, "LTX-SEGMENT-TEMPLATE:PLAN_CONFIRM,TX,RX,CAUCUS,TX,RX,BUFFER\r\n");
        checkContains("ics MODE", ics, "LTX-MODE:LTX\r\n");
        checkContains("ics host node", ics, "LTX-NODE:ID=EARTH-HQ;ROLE=HOST\r\n");
        checkContains("ics participant node", ics, "LTX-NODE:ID=MARS-HAB-01;ROLE=PARTICIPANT\r\n");
        checkContains("ics delay", ics, "LTX-DELAY;NODEID=MARS-HAB-01:ONEWAY-MIN=0;ONEWAY-MAX=120;ONEWAY-ASSUMED=0\r\n");
        checkContains("ics readiness", ics, "LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY\r\n");
        checkContains("ics localtime", ics, "LTX-LOCALTIME:NODE=MARS-HAB-01;SCHEME=LMST;PARAMS=LONGITUDE:0E\r\n");
        checkContains("ics description", ics, "Signal delays: Mars Hab-01: 0 min one-way\\nMode: LTX");
    }

    // ── Section 8: escapeIcsText (Story 26.3) ────────────────────────────

    const esc_cases = [_]struct { in: []const u8, out: []const u8 }{
        .{ .in = "", .out = "" },         .{ .in = "hello", .out = "hello" }, .{ .in = "a,b", .out = "a\\,b" },
        .{ .in = "a;b", .out = "a\\;b" }, .{ .in = "a\\b", .out = "a\\\\b" }, .{ .in = "a\nb", .out = "a\\nb" },
    };
    for (esc_cases) |c| {
        const s = try ltx.escapeIcsText(allocator, c.in);
        defer allocator.free(s);
        checkStr("escapeIcsText", s, c.out);
    }
    {
        const p = try ltx.createPlan(allocator, .{ .title = "Mars,Earth;Session", .start = "2040-01-15T14:00:00.000Z" });
        defer ltx.deinitPlan(allocator, p);
        const ics = try ltx.generateIcs(allocator, p);
        defer allocator.free(ics);
        checkContains("generateIcs SUMMARY escapes title specials", ics, "SUMMARY:Mars\\,Earth\\;Session");
    }

    // ── Section 9: JSON escaping ─────────────────────────────────────────

    {
        const p = try ltx.createPlan(allocator, .{ .title = "q\"b\\n\n\x01", .start = "2040-01-15T14:00:00.000Z" });
        defer ltx.deinitPlan(allocator, p);
        const json = try ltx.planToJson(allocator, p);
        defer allocator.free(json);
        checkContains("title escaped as JSON.stringify", json, "\"title\":\"q\\\"b\\\\n\\n\\u0001\"");
        const back = try ltx.planFromJson(allocator, json);
        defer ltx.deinitPlan(allocator, back);
        checkStr("escaped title round-trips", back.title, p.title);
    }

    // ── Section 10: Story 26.4 protocol hardening ────────────────────────

    checkInt("DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2", ltx.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR, 2);
    checkInt("DELAY_VIOLATION_WARN_S = 120", ltx.DELAY_VIOLATION_WARN_S, 120);
    checkInt("DELAY_VIOLATION_DEGRADED_S = 300", ltx.DELAY_VIOLATION_DEGRADED_S, 300);
    checkInt("SESSION_STATES length = 5", @intCast(ltx.SESSION_STATES.len), 5);
    checkStr("SESSION_STATES[0] = INIT", ltx.SESSION_STATES[0], "INIT");
    checkStr("SESSION_STATES[3] = DEGRADED", ltx.SESSION_STATES[3], "DEGRADED");
    checkStr("SESSION_STATES[4] = COMPLETE", ltx.SESSION_STATES[4], "COMPLETE");

    check("planLockTimeoutMs(0) = 0", ltx.planLockTimeoutMs(0) == 0);
    check("planLockTimeoutMs(100) = 200000", ltx.planLockTimeoutMs(100) == 200_000);
    check("planLockTimeoutMs(60) = 120000", ltx.planLockTimeoutMs(60) == 120_000);
    check("planLockTimeoutMs(1000) = 2000000", ltx.planLockTimeoutMs(1000) == 2_000_000);

    checkStr("checkDelayViolation same = ok", ltx.checkDelayViolation(100, 100), "ok");
    checkStr("checkDelayViolation diff=100 = ok", ltx.checkDelayViolation(100, 200), "ok");
    checkStr("checkDelayViolation diff=120 = ok (boundary)", ltx.checkDelayViolation(100, 220), "ok");
    checkStr("checkDelayViolation diff=121 = violation", ltx.checkDelayViolation(100, 221), "violation");
    checkStr("checkDelayViolation diff=300 = violation (boundary)", ltx.checkDelayViolation(100, 400), "violation");
    checkStr("checkDelayViolation diff=301 = degraded", ltx.checkDelayViolation(100, 401), "degraded");
    checkStr("checkDelayViolation large negative = degraded", ltx.checkDelayViolation(500, 100), "degraded");
    checkStr("checkDelayViolation both zero = ok", ltx.checkDelayViolation(0, 0), "ok");

    // ── Summary ───────────────────────────────────────────────────────────

    std.debug.print("{d} passed  {d} failed\n", .{ passed, failed });
    if (failed > 0) std.process.exit(1);
}
