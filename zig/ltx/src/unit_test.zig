// unit_test.zig — LTX Zig library unit tests (Sprint 65)
//
// Standalone executable: imports interplanet_ltx.zig and runs ≥80 check() calls.
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

fn checkInt(desc: []const u8, got: u32, expected: u32) void {
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
        std.debug.print("FAIL: {s} — expected to contain: {s}\n", .{ desc, needle });
    }
}

// ── Conformance vector v001 ───────────────────────────────────────────────
// title: "Test Meeting Alpha"
// start: "2040-01-15T14:00:00Z"
// quantum: 5
// host:   EARTH_HQ / Earth HQ / earth
// remote: MARS     / Mars Base / mars
// template: TX/3, RX/1, TX/2, RX/1, BUFFER/2  →  totalMin = 45
// planId: "LTX-20400115-EARTH_HQ-MARS-v2-8f812845"

const V001_TEMPLATE = [_]ltx.SegmentTemplate{
    .{ .seg_type = "TX",     .duration = 3 },
    .{ .seg_type = "RX",     .duration = 1 },
    .{ .seg_type = "TX",     .duration = 2 },
    .{ .seg_type = "RX",     .duration = 1 },
    .{ .seg_type = "BUFFER", .duration = 2 },
};

const V001_NODES = [_]ltx.Node{
    .{ .id = "EARTH_HQ", .name = "Earth HQ", .location = "earth", .is_host = true  },
    .{ .id = "MARS",     .name = "Mars Base", .location = "mars",  .is_host = false },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ── Section 1: Constants ─────────────────────────────────────────────

    checkStr("VERSION = 1.0.0", ltx.VERSION, "1.0.0");
    checkInt("DEFAULT_QUANTUM = 5", ltx.DEFAULT_QUANTUM, 5);
    check("DEFAULT_API_BASE contains interplanettime.net",
        contains(ltx.DEFAULT_API_BASE, "interplanettime.net"));
    checkInt("SEG_TYPES length = 5", ltx.SEG_TYPES.len, 5);
    checkStr("SEG_TYPES[0] = TX",     ltx.SEG_TYPES[0], "TX");
    checkStr("SEG_TYPES[1] = RX",     ltx.SEG_TYPES[1], "RX");
    checkStr("SEG_TYPES[2] = BUFFER", ltx.SEG_TYPES[2], "BUFFER");
    checkStr("SEG_TYPES[3] = HOLD",   ltx.SEG_TYPES[3], "HOLD");
    checkStr("SEG_TYPES[4] = PREP",   ltx.SEG_TYPES[4], "PREP");
    checkInt("DEFAULT_SEGMENTS length = 5", ltx.DEFAULT_SEGMENTS.len, 5);
    checkStr("DEFAULT_SEGMENTS[0].type = TX",     ltx.DEFAULT_SEGMENTS[0].seg_type, "TX");
    checkStr("DEFAULT_SEGMENTS[4].type = BUFFER", ltx.DEFAULT_SEGMENTS[4].seg_type, "BUFFER");
    checkInt("DEFAULT_SEGMENTS total quanta = 9",
        blk: {
            var t: u32 = 0;
            for (ltx.DEFAULT_SEGMENTS) |s| t += s.duration;
            break :blk t;
        }, 9);

    // ── Section 2: formatHms ─────────────────────────────────────────────

    {
        const s1 = try ltx.formatHms(allocator, 90);
        defer allocator.free(s1);
        checkStr("formatHms 90 = 1h 30m", s1, "1h 30m");
    }
    {
        const s2 = try ltx.formatHms(allocator, 45);
        defer allocator.free(s2);
        checkStr("formatHms 45 = 45m", s2, "45m");
    }
    {
        const s3 = try ltx.formatHms(allocator, 120);
        defer allocator.free(s3);
        checkStr("formatHms 120 = 2h", s3, "2h");
    }
    {
        const s4 = try ltx.formatHms(allocator, 0);
        defer allocator.free(s4);
        checkStr("formatHms 0 = 0m", s4, "0m");
    }
    {
        const s5 = try ltx.formatHms(allocator, 61);
        defer allocator.free(s5);
        checkStr("formatHms 61 = 1h 1m", s5, "1h 1m");
    }
    {
        const s6 = try ltx.formatHms(allocator, 60);
        defer allocator.free(s6);
        checkStr("formatHms 60 = 1h", s6, "1h");
    }
    {
        const s7 = try ltx.formatHms(allocator, 1);
        defer allocator.free(s7);
        checkStr("formatHms 1 = 1m", s7, "1m");
    }
    {
        const s8 = try ltx.formatHms(allocator, 150);
        defer allocator.free(s8);
        checkStr("formatHms 150 = 2h 30m", s8, "2h 30m");
    }

    // ── Section 3: createPlan defaults ───────────────────────────────────

    const default_plan = try ltx.createPlan(allocator, .{});
    checkStr("default plan v = 2",         default_plan.v,    "2");
    checkStr("default plan title",         default_plan.title, "LTX Session");
    checkInt("default plan quantum = 5",   default_plan.quantum, 5);
    checkStr("default plan mode = LTX",    default_plan.mode, "LTX");
    checkInt("default plan nodes = 2",     @intCast(default_plan.nodes.len), 2);
    check("default plan has segments",     default_plan.segments.len > 0);
    checkInt("default plan segments = 5",  @intCast(default_plan.segments.len), 5);
    check("default host is_host = true",   default_plan.nodes[0].is_host);
    check("default remote is_host = false", !default_plan.nodes[1].is_host);
    checkStr("default host location",     default_plan.nodes[0].location, "earth");
    checkStr("default remote location",   default_plan.nodes[1].location, "mars");

    // ── Section 4: createPlan custom params ─────────────────────────────

    const custom_plan = try ltx.createPlan(allocator, .{
        .title           = "My Meeting",
        .start           = "2040-06-01T10:00:00Z",
        .quantum         = 10,
        .host_id         = "LUNA",
        .host_name       = "Lunar Station",
        .host_location   = "moon",
        .remote_id       = "EUROPA",
        .remote_name     = "Europa Base",
        .remote_location = "europa",
    });
    checkStr("custom title",           custom_plan.title,          "My Meeting");
    checkInt("custom quantum = 10",    custom_plan.quantum,        10);
    checkStr("custom host name",       custom_plan.nodes[0].name,  "Lunar Station");
    checkStr("custom remote name",     custom_plan.nodes[1].name,  "Europa Base");
    checkStr("custom remote location", custom_plan.nodes[1].location, "europa");
    check("custom host is_host = true",  custom_plan.nodes[0].is_host);
    check("custom remote is_host = false", !custom_plan.nodes[1].is_host);
    checkInt("custom default segments = 5", @intCast(custom_plan.segments.len), 5);

    // ── Section 5: upgradeConfig ─────────────────────────────────────────

    {
        // A plan already at v="2" with nodes should be returned unchanged
        const v2_plan = try ltx.upgradeConfig(allocator, default_plan);
        checkStr("upgrade v2 plan: v still 2", v2_plan.v, "2");
        checkInt("upgrade v2 plan: quantum preserved", v2_plan.quantum, 5);
        checkInt("upgrade v2 plan: nodes unchanged",
            @intCast(v2_plan.nodes.len), @intCast(default_plan.nodes.len));
    }
    {
        // A plan with v != "2" should be upgraded
        const old_plan = ltx.Plan{
            .v        = "1",
            .title    = "Old Meeting",
            .start    = "2040-06-01T10:00:00Z",
            .quantum  = 3,
            .mode     = "LTX",
            .nodes    = &.{},
            .segments = &.{},
        };
        const upgraded = try ltx.upgradeConfig(allocator, old_plan);
        checkStr("upgrade v1 plan: v = 2",     upgraded.v, "2");
        checkInt("upgrade v1 plan: 2 nodes",   @intCast(upgraded.nodes.len), 2);
        check("upgraded host is_host = true",  upgraded.nodes[0].is_host);
        check("upgraded remote is_host = false", !upgraded.nodes[1].is_host);
    }

    // ── Section 6: totalMin ──────────────────────────────────────────────

    {
        // Build v001 plan manually
        const v001_segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        const v001_plan = ltx.Plan{
            .v        = "2",
            .title    = "Test Meeting Alpha",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = v001_segs,
        };
        checkInt("v001 totalMin = 45",  ltx.totalMin(v001_plan), 45);

        // Default plan: 5 segs at quantum=5: (3+1+2+1+2)*5 = 45
        checkInt("default totalMin = 45", ltx.totalMin(default_plan), 45);

        // Custom: 5 segs at quantum=10: (3+1+2+1+2)*10 = 90
        checkInt("custom totalMin = 90", ltx.totalMin(custom_plan), 90);
    }

    // ── Section 7: computeSegments ───────────────────────────────────────

    {
        const segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        checkInt("computeSegments count = 5",      @intCast(segs.len), 5);
        checkStr("seg[0] type = TX",               segs[0].seg_type, "TX");
        checkStr("seg[1] type = RX",               segs[1].seg_type, "RX");
        checkStr("seg[2] type = TX",               segs[2].seg_type, "TX");
        checkStr("seg[3] type = RX",               segs[3].seg_type, "RX");
        checkStr("seg[4] type = BUFFER",           segs[4].seg_type, "BUFFER");
        checkInt("seg[0] duration = 15",           segs[0].duration, 15);
        checkInt("seg[1] duration = 5",            segs[1].duration, 5);
        checkInt("seg[0] start_offset = 0",        segs[0].start_offset, 0);
        checkInt("seg[1] start_offset = 15",       segs[1].start_offset, 15);
        checkInt("seg[2] start_offset = 20",       segs[2].start_offset, 20);
        checkInt("seg[3] start_offset = 30",       segs[3].start_offset, 30);
        checkInt("seg[4] start_offset = 35",       segs[4].start_offset, 35);
        checkStr("seg[0] id = s1",                 segs[0].id, "s1");
        checkStr("seg[4] id = s5",                 segs[4].id, "s5");
        // TX speaker = host id
        check("seg[0] speaker = EARTH_HQ",
            segs[0].speaker != null and std.mem.eql(u8, segs[0].speaker.?, "EARTH_HQ"));
        // RX speaker = remote id
        check("seg[1] speaker = MARS",
            segs[1].speaker != null and std.mem.eql(u8, segs[1].speaker.?, "MARS"));
        // BUFFER speaker = null
        check("seg[4] speaker = null", segs[4].speaker == null);
    }

    // ── Section 8: makePlanId ────────────────────────────────────────────

    {
        const v001_segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        const v001_plan = ltx.Plan{
            .v        = "2",
            .title    = "Test Meeting Alpha",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = v001_segs,
        };
        const plan_id = try ltx.makePlanId(allocator, v001_plan);
        defer allocator.free(plan_id);

        checkContains("planId starts with LTX-",   plan_id, "LTX-");
        checkContains("planId has date 20400115",   plan_id, "20400115");
        checkContains("planId has EARTH_HQ",        plan_id, "EARTH_HQ");
        checkContains("planId has MARS",            plan_id, "MARS");
        checkContains("planId has -v2-",            plan_id, "-v2-");
        checkContains("planId golden hash 8f812845", plan_id, "8f812845");

        // Default plan has different id
        const def_id = try ltx.makePlanId(allocator, default_plan);
        defer allocator.free(def_id);
        checkContains("default planId starts with LTX-", def_id, "LTX-");
        check("different plans → different IDs", !std.mem.eql(u8, plan_id, def_id));
    }

    // ── Section 9: encodeHash / decodeHash round-trip ────────────────────

    {
        const v001_segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        const v001_plan = ltx.Plan{
            .v        = "2",
            .title    = "Test Meeting Alpha",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = v001_segs,
        };

        const original_json = try ltx.planToJson(allocator, v001_plan);
        defer allocator.free(original_json);

        const encoded = try ltx.encodeHash(allocator, v001_plan);
        defer allocator.free(encoded);

        check("encodeHash starts with #l=",
            std.mem.startsWith(u8, encoded, "#l="));
        check("encodeHash is longer than #l=", encoded.len > 3);

        const decoded = try ltx.decodeHash(allocator, encoded);
        defer allocator.free(decoded);

        checkStr("decode(encode(json)) round-trips correctly", decoded, original_json);

        // Re-encode should give same token
        const encoded_raw = encoded[3..]; // strip "#l="
        const re_decoded  = try ltx.decodeHash(allocator, encoded_raw);
        defer allocator.free(re_decoded);
        checkStr("decode without #l= prefix also works", re_decoded, original_json);

        // l= prefix variant
        var l_prefix = try allocator.alloc(u8, encoded.len - 1);
        defer allocator.free(l_prefix);
        @memcpy(l_prefix[0..], encoded[1..]); // strip leading '#'
        const re_decoded2 = try ltx.decodeHash(allocator, l_prefix);
        defer allocator.free(re_decoded2);
        checkStr("decode with l= prefix works", re_decoded2, original_json);
    }

    // ── Section 10: buildNodeUrls ────────────────────────────────────────

    {
        const v001_segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        const v001_plan = ltx.Plan{
            .v        = "2",
            .title    = "Test Meeting Alpha",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = v001_segs,
        };

        const urls = try ltx.buildNodeUrls(allocator, v001_plan,
            "https://interplanet.live/meet");
        defer {
            for (urls) |u| allocator.free(u.session_url);
            allocator.free(urls);
        }

        checkInt("buildNodeUrls count = 2", @intCast(urls.len), 2);
        checkStr("url[0].node_id = EARTH_HQ", urls[0].node_id, "EARTH_HQ");
        checkStr("url[1].node_id = MARS",     urls[1].node_id, "MARS");
        checkContains("url[0].session_url has node=EARTH_HQ",
            urls[0].session_url, "node=EARTH_HQ");
        checkContains("url[1].session_url has node=MARS",
            urls[1].session_url, "node=MARS");
        checkContains("url[0].session_url has #l=",
            urls[0].session_url, "#l=");
        checkContains("url[1].session_url has #l=",
            urls[1].session_url, "#l=");
        check("url[0].session_url starts with base",
            std.mem.startsWith(u8, urls[0].session_url, "https://"));
    }

    // ── Section 11: buildDelayMatrix ─────────────────────────────────────

    {
        const v001_segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        const v001_plan = ltx.Plan{
            .v        = "2",
            .title    = "Test Meeting Alpha",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = v001_segs,
        };

        const matrix = try ltx.buildDelayMatrix(allocator, v001_plan);
        defer {
            for (matrix) |row| allocator.free(row);
            allocator.free(matrix);
        }

        checkInt("delay matrix rows = 2",      @intCast(matrix.len), 2);
        checkInt("delay matrix cols = 2",      @intCast(matrix[0].len), 2);
        checkInt("matrix[0][0] diagonal = 0", matrix[0][0], 0);
        checkInt("matrix[1][1] diagonal = 0", matrix[1][1], 0);
        check("matrix[0][1] off-diagonal > 0", matrix[0][1] > 0);
        check("matrix[1][0] off-diagonal > 0", matrix[1][0] > 0);
        // quantum=5, host↔remote = 5*4 = 20
        checkInt("matrix[0][1] = quantum*4 = 20", matrix[0][1], 20);
        checkInt("matrix[1][0] = quantum*4 = 20", matrix[1][0], 20);

        // 3-node plan
        const three_nodes = [_]ltx.Node{
            .{ .id = "N0", .name = "Earth HQ",   .location = "earth", .is_host = true  },
            .{ .id = "N1", .name = "Mars Base",  .location = "mars",  .is_host = false },
            .{ .id = "N2", .name = "Lunar Base", .location = "moon",  .is_host = false },
        };
        const three_segs = try ltx.computeSegments(allocator, &three_nodes, &V001_TEMPLATE, 5);
        const three_plan = ltx.Plan{
            .v        = "2",
            .title    = "3-Node",
            .start    = "2040-03-01T09:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &three_nodes,
            .segments = three_segs,
        };
        const m3 = try ltx.buildDelayMatrix(allocator, three_plan);
        defer {
            for (m3) |row| allocator.free(row);
            allocator.free(m3);
        }
        checkInt("3-node matrix rows = 3", @intCast(m3.len), 3);
        checkInt("3-node diagonal[0][0] = 0", m3[0][0], 0);
        checkInt("3-node diagonal[1][1] = 0", m3[1][1], 0);
        checkInt("3-node diagonal[2][2] = 0", m3[2][2], 0);
        check("3-node off-diag[0][1] > 0", m3[0][1] > 0);
        check("3-node off-diag[1][2] > 0", m3[1][2] > 0);
    }

    // ── Section 12: generateIcs ──────────────────────────────────────────

    {
        const v001_segs = try ltx.computeSegments(allocator, &V001_NODES, &V001_TEMPLATE, 5);
        const v001_plan = ltx.Plan{
            .v        = "2",
            .title    = "Test Meeting Alpha",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = v001_segs,
        };

        const ics = try ltx.generateIcs(allocator, v001_plan);
        defer allocator.free(ics);

        checkContains("ics has BEGIN:VCALENDAR",     ics, "BEGIN:VCALENDAR");
        checkContains("ics has END:VCALENDAR",       ics, "END:VCALENDAR");
        checkContains("ics has BEGIN:VEVENT",        ics, "BEGIN:VEVENT");
        checkContains("ics has END:VEVENT",          ics, "END:VEVENT");
        checkContains("ics has LTX-PLANID:",         ics, "LTX-PLANID:");
        checkContains("ics has LTX-QUANTUM:PT5M",    ics, "LTX-QUANTUM:PT5M");
        checkContains("ics has golden hash",         ics, "8f812845");
        checkContains("ics has SUMMARY:Test Meeting Alpha",
            ics, "SUMMARY:Test Meeting Alpha");
        checkContains("ics has CRLF line endings",   ics, "\r\n");
        checkContains("ics has LTX-MODE:LTX",        ics, "LTX-MODE:LTX");
        checkContains("ics has DTSTART",             ics, "DTSTART:");
        checkContains("ics has DTEND",               ics, "DTEND:");
    }

    // ── Section 13: escapeIcsText (Story 26.3) ───────────────────────────

    {
        const s1 = try ltx.escapeIcsText(allocator, "");
        defer allocator.free(s1);
        checkStr("escapeIcsText empty", s1, "");
    }
    {
        const s2 = try ltx.escapeIcsText(allocator, "hello");
        defer allocator.free(s2);
        checkStr("escapeIcsText no specials", s2, "hello");
    }
    {
        const s3 = try ltx.escapeIcsText(allocator, "a,b");
        defer allocator.free(s3);
        checkStr("escapeIcsText comma", s3, "a\\,b");
    }
    {
        const s4 = try ltx.escapeIcsText(allocator, "a;b");
        defer allocator.free(s4);
        checkStr("escapeIcsText semicolon", s4, "a\\;b");
    }
    {
        const s5 = try ltx.escapeIcsText(allocator, "a\\b");
        defer allocator.free(s5);
        checkStr("escapeIcsText backslash", s5, "a\\\\b");
    }
    {
        const s6 = try ltx.escapeIcsText(allocator, "a\nb");
        defer allocator.free(s6);
        checkStr("escapeIcsText newline", s6, "a\\nb");
    }
    {
        // SUMMARY in ICS should use escaped title
        const special_plan = ltx.Plan{
            .v        = "2",
            .title    = "Mars,Earth;Session",
            .start    = "2040-01-15T14:00:00Z",
            .quantum  = 5,
            .mode     = "LTX",
            .nodes    = &V001_NODES,
            .segments = &.{},
        };
        const ics_sp = try ltx.generateIcs(allocator, special_plan);
        defer allocator.free(ics_sp);
        checkContains("generateIcs SUMMARY escapes title specials",
            ics_sp, "SUMMARY:Mars\\,Earth\\;Session");
    }

    // ── Section 14: Story 26.4 protocol hardening ─────────────────────────

    checkInt("DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2",
        ltx.DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR, 2);
    checkInt("DELAY_VIOLATION_WARN_S = 120",
        ltx.DELAY_VIOLATION_WARN_S, 120);
    checkInt("DELAY_VIOLATION_DEGRADED_S = 300",
        ltx.DELAY_VIOLATION_DEGRADED_S, 300);
    checkInt("SESSION_STATES length = 5",
        @intCast(ltx.SESSION_STATES.len), 5);
    checkStr("SESSION_STATES[0] = INIT",     ltx.SESSION_STATES[0], "INIT");
    checkStr("SESSION_STATES[1] = LOCKED",   ltx.SESSION_STATES[1], "LOCKED");
    checkStr("SESSION_STATES[2] = RUNNING",  ltx.SESSION_STATES[2], "RUNNING");
    checkStr("SESSION_STATES[3] = DEGRADED", ltx.SESSION_STATES[3], "DEGRADED");
    checkStr("SESSION_STATES[4] = COMPLETE", ltx.SESSION_STATES[4], "COMPLETE");

    // planLockTimeoutMs
    check("planLockTimeoutMs(0) = 0",          ltx.planLockTimeoutMs(0) == 0);
    check("planLockTimeoutMs(100) = 200000",   ltx.planLockTimeoutMs(100) == 200_000);
    check("planLockTimeoutMs(60) = 120000",    ltx.planLockTimeoutMs(60) == 120_000);
    check("planLockTimeoutMs(1000) = 2000000", ltx.planLockTimeoutMs(1000) == 2_000_000);

    // checkDelayViolation
    checkStr("checkDelayViolation same = ok",
        ltx.checkDelayViolation(100, 100), "ok");
    checkStr("checkDelayViolation diff=100 = ok",
        ltx.checkDelayViolation(100, 200), "ok");
    checkStr("checkDelayViolation diff=120 = ok (boundary)",
        ltx.checkDelayViolation(100, 220), "ok");
    checkStr("checkDelayViolation diff=121 = violation",
        ltx.checkDelayViolation(100, 221), "violation");
    checkStr("checkDelayViolation diff=300 = violation (boundary)",
        ltx.checkDelayViolation(100, 400), "violation");
    checkStr("checkDelayViolation diff=301 = degraded",
        ltx.checkDelayViolation(100, 401), "degraded");
    checkStr("checkDelayViolation large negative = degraded",
        ltx.checkDelayViolation(500, 100), "degraded");
    checkStr("checkDelayViolation both zero = ok",
        ltx.checkDelayViolation(0, 0), "ok");

    // ── Summary ───────────────────────────────────────────────────────────

    std.debug.print("{d} passed  {d} failed\n", .{ passed, failed });
    if (failed > 0) std.process.exit(1);
}
