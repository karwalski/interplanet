// interplanet_ltx.zig — LTX (Light-Time eXchange) SDK for Zig
//
// Typed v2 plan model (LTX-SPECIFICATION.md §4.1, §4.3), mirroring
// javascript/ltx/ltx-sdk.js createPlan / makePlanId / encodeHash /
// computeSegments / buildDelayMatrix / buildNodeUrls / generateICS.
//
// Zig idioms:
//   - All allocating functions return !T and accept an Allocator
//   - Callers own all returned memory. createPlan and planFromJson return a
//     deep copy; release it with deinitPlan.
//   - The wire JSON (planToJson, the `#l=` share fragment) uses the key order
//     of the JavaScript createPlan: v, title, start, quantum, mode, segments,
//     nodes. makePlanId hashes exactly that JSON, so a typed plan transmits
//     exactly what it hashes, and a Zig createPlan plan has the same planId as
//     a JS createPlan plan built from the same values.
//
// For plans received as JSON text (any key order, v3 fields) use the
// JSON-based API in ltx_v11.zig (makePlanIdJson, planHashJson, ...).

const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Protocol constants ─────────────────────────────────────────────────────

pub const VERSION = "1.1.0";
pub const DEFAULT_QUANTUM: u32 = 5; // minutes per quantum (§3.2)
pub const DEFAULT_API_BASE = "https://api.interplanettime.net/ltx/v1";

/// Core segment types (§3.4), as ltx-sdk.js SEG_TYPES.
pub const SEG_TYPES = [_][]const u8{ "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE" };

/// Node roles (§3.1).
pub const NODE_ROLES = [_][]const u8{ "HOST", "PARTICIPANT", "OBSERVER" };

// Story 26.4 constants
pub const DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR: u32 = 2;
pub const DELAY_VIOLATION_WARN_S: u32 = 120;
pub const DELAY_VIOLATION_DEGRADED_S: u32 = 300;
pub const SESSION_STATES = [_][]const u8{ "INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE" };

/// Default segment template, as ltx-sdk.js DEFAULT_SEGMENTS.
pub const DEFAULT_SEGMENTS = [_]SegmentTemplate{
    .{ .seg_type = "PLAN_CONFIRM", .q = 2 },
    .{ .seg_type = "TX", .q = 2 },
    .{ .seg_type = "RX", .q = 2 },
    .{ .seg_type = "CAUCUS", .q = 2 },
    .{ .seg_type = "TX", .q = 2 },
    .{ .seg_type = "RX", .q = 2 },
    .{ .seg_type = "BUFFER", .q = 1 },
};

// ── Data types ─────────────────────────────────────────────────────────────

/// Plan segment `{type, q, speaker?, label?}` (§3.4, §3.4.1).
/// Wire keys: "type", "q", then "speaker" and "label" when set.
pub const SegmentTemplate = struct {
    seg_type: []const u8,
    q: u32, // duration in quanta
    speaker: ?[]const u8 = null, // node id (attributed TX/SPEAK segments)
    label: ?[]const u8 = null, // agenda label
};

/// Plan node `{id, name, role, delay, location}` (§3.1).
pub const Node = struct {
    id: []const u8,
    name: []const u8,
    role: []const u8, // "HOST" | "PARTICIPANT" | "OBSERVER"
    delay: i64 = 0, // one-way delay to the HOST in seconds
    location: []const u8,
};

/// A v2 LTX session plan (§4.1).
pub const LtxPlan = struct {
    v: u32 = 2,
    title: []const u8,
    start: []const u8, // ISO 8601 UTC
    quantum: u32, // minutes
    mode: []const u8, // "LTX" | "LTX-LIVE" | "LTX-RELAY" | "LTX-ASYNC"
    nodes: []const Node, // HOST first
    segments: []const SegmentTemplate,
};

/// A timed segment (ltx-sdk.js computeSegments).
pub const TimedSegment = struct {
    seg_type: []const u8,
    q: u32,
    start_ms: i64, // epoch ms
    end_ms: i64, // epoch ms
    dur_min: u32,
    speaker: ?[]const u8,
    label: ?[]const u8,
};

/// One ordered node pair of the delay matrix (ltx-sdk.js buildDelayMatrix).
pub const DelayPair = struct {
    from_id: []const u8,
    from_name: []const u8,
    to_id: []const u8,
    to_name: []const u8,
    delay_seconds: i64,
};

/// A per-node session URL (ltx-sdk.js buildNodeUrls). Only `url` is owned
/// by the caller; the other fields point into the plan.
pub const NodeUrl = struct {
    node_id: []const u8,
    name: []const u8,
    role: []const u8,
    url: []const u8,
};

/// Options for createPlan. Empty strings and a zero quantum fall back to the
/// defaults, as the `||` defaults of ltx-sdk.js createPlan do.
pub const CreatePlanOpts = struct {
    title: ?[]const u8 = null, // default "LTX Session"
    start: ?[]const u8 = null, // default: now, whole minute, + 5 min
    quantum: ?u32 = null, // default DEFAULT_QUANTUM
    mode: ?[]const u8 = null, // default "LTX"
    /// Explicit node list; overrides the host_* / remote_* / delay fields.
    nodes: ?[]const Node = null,
    host_name: ?[]const u8 = null, // default "Earth HQ"
    host_location: ?[]const u8 = null, // default "earth"
    remote_name: ?[]const u8 = null, // default "Mars Hab-01"
    remote_location: ?[]const u8 = null, // default "mars"
    delay: i64 = 0, // one-way delay of the default participant, seconds
    /// Segment template; default DEFAULT_SEGMENTS.
    segments: ?[]const SegmentTemplate = null,
};

// ── Plan construction and ownership ────────────────────────────────────────

fn orDefault(s: ?[]const u8, def: []const u8) []const u8 {
    if (s) |v| {
        if (v.len > 0) return v;
    }
    return def;
}

/// Create a new v2 LTX plan (ltx-sdk.js createPlan).
/// The result is a deep copy owned by the caller: free it with deinitPlan.
pub fn createPlan(allocator: Allocator, opts: CreatePlanOpts) !LtxPlan {
    const default_nodes = [_]Node{
        .{ .id = "N0", .name = orDefault(opts.host_name, "Earth HQ"), .role = "HOST", .delay = 0, .location = orDefault(opts.host_location, "earth") },
        .{ .id = "N1", .name = orDefault(opts.remote_name, "Mars Hab-01"), .role = "PARTICIPANT", .delay = opts.delay, .location = orDefault(opts.remote_location, "mars") },
    };

    var start_buf: [32]u8 = undefined;
    const start: []const u8 = if (opts.start != null and opts.start.?.len > 0) opts.start.? else blk: {
        // JS: now with seconds and ms zeroed, plus 5 minutes, toISOString().
        const now_ms = std.time.milliTimestamp();
        const minute_ms = @divFloor(now_ms, 60_000) * 60_000 + 5 * 60_000;
        break :blk formatIsoMs(&start_buf, minute_ms);
    };

    const q = opts.quantum orelse DEFAULT_QUANTUM;
    return clonePlan(allocator, .{
        .v = 2,
        .title = orDefault(opts.title, "LTX Session"),
        .start = start,
        .quantum = if (q == 0) DEFAULT_QUANTUM else q,
        .mode = orDefault(opts.mode, "LTX"),
        .nodes = opts.nodes orelse &default_nodes,
        .segments = opts.segments orelse &DEFAULT_SEGMENTS,
    });
}

/// Deep-copy a plan into allocator-owned memory (free with deinitPlan).
pub fn clonePlan(allocator: Allocator, plan: LtxPlan) !LtxPlan {
    var arena_like = std.ArrayList([]const u8){};
    defer arena_like.deinit(allocator);
    errdefer for (arena_like.items) |s| allocator.free(s);

    const nodes = try allocator.alloc(Node, plan.nodes.len);
    errdefer allocator.free(nodes);
    const segs = try allocator.alloc(SegmentTemplate, plan.segments.len);
    errdefer allocator.free(segs);

    const D = struct {
        fn dupe(a: Allocator, list: *std.ArrayList([]const u8), s: []const u8) ![]const u8 {
            const c = try a.dupe(u8, s);
            errdefer a.free(c);
            try list.append(a, c);
            return c;
        }
        fn dupeO(a: Allocator, list: *std.ArrayList([]const u8), s: ?[]const u8) !?[]const u8 {
            return if (s) |v| try dupe(a, list, v) else null;
        }
    };

    for (plan.nodes, 0..) |n, i| {
        nodes[i] = .{
            .id = try D.dupe(allocator, &arena_like, n.id),
            .name = try D.dupe(allocator, &arena_like, n.name),
            .role = try D.dupe(allocator, &arena_like, n.role),
            .delay = n.delay,
            .location = try D.dupe(allocator, &arena_like, n.location),
        };
    }
    for (plan.segments, 0..) |s, i| {
        segs[i] = .{
            .seg_type = try D.dupe(allocator, &arena_like, s.seg_type),
            .q = s.q,
            .speaker = try D.dupeO(allocator, &arena_like, s.speaker),
            .label = try D.dupeO(allocator, &arena_like, s.label),
        };
    }
    return .{
        .v = plan.v,
        .title = try D.dupe(allocator, &arena_like, plan.title),
        .start = try D.dupe(allocator, &arena_like, plan.start),
        .quantum = plan.quantum,
        .mode = try D.dupe(allocator, &arena_like, plan.mode),
        .nodes = nodes,
        .segments = segs,
    };
}

/// Free a plan returned by createPlan, clonePlan or planFromJson.
pub fn deinitPlan(allocator: Allocator, plan: LtxPlan) void {
    for (plan.nodes) |n| {
        allocator.free(n.id);
        allocator.free(n.name);
        allocator.free(n.role);
        allocator.free(n.location);
    }
    for (plan.segments) |s| {
        allocator.free(s.seg_type);
        if (s.speaker) |v| allocator.free(v);
        if (s.label) |v| allocator.free(v);
    }
    allocator.free(plan.nodes);
    allocator.free(plan.segments);
    allocator.free(plan.title);
    allocator.free(plan.start);
    allocator.free(plan.mode);
}

// ── Wire serialisation ─────────────────────────────────────────────────────

/// Append s as a JSON string literal, escaped as JSON.stringify does.
fn writeJsonString(allocator: Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(allocator, '"');
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        // A lone UTF-16 surrogate held as WTF-8 (ED A0..BF xx), as a planId
        // cut can leave one: JSON.stringify writes it as a \udxxx escape.
        if (c == 0xed and i + 2 < s.len and s[i + 1] >= 0xa0 and s[i + 1] <= 0xbf and s[i + 2] & 0xc0 == 0x80) {
            const unit: u16 = 0xd000 | (@as(u16, s[i + 1] & 0x3f) << 6) | (s[i + 2] & 0x3f);
            var tmp: [8]u8 = undefined;
            try buf.appendSlice(allocator, std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{unit}) catch unreachable);
            i += 2;
            continue;
        }
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            0x08 => try buf.appendSlice(allocator, "\\b"),
            0x0c => try buf.appendSlice(allocator, "\\f"),
            0x00...0x07, 0x0b, 0x0e...0x1f => {
                var tmp: [8]u8 = undefined;
                try buf.appendSlice(allocator, std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{c}) catch unreachable);
            },
            else => try buf.append(allocator, c),
        }
    }
    try buf.append(allocator, '"');
}

fn writeInt(allocator: Allocator, buf: *std.ArrayList(u8), n: i64) !void {
    var tmp: [24]u8 = undefined;
    try buf.appendSlice(allocator, std.fmt.bufPrint(&tmp, "{d}", .{n}) catch unreachable);
}

fn writeKey(allocator: Allocator, buf: *std.ArrayList(u8), comma: bool, key: []const u8) !void {
    if (comma) try buf.append(allocator, ',');
    try writeJsonString(allocator, buf, key);
    try buf.append(allocator, ':');
}

/// Serialise a plan to its wire JSON: compact, key order v, title, start,
/// quantum, mode, segments, nodes (as JSON.stringify of a JS createPlan
/// plan); segment keys type, q[, speaker][, label]; node keys id, name,
/// role, delay, location. This is the exact text makePlanId hashes and
/// encodeHash transmits.
pub fn planToJson(allocator: Allocator, plan: LtxPlan) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    try buf.append(allocator, '{');
    try writeKey(allocator, &buf, false, "v");
    try writeInt(allocator, &buf, plan.v);
    try writeKey(allocator, &buf, true, "title");
    try writeJsonString(allocator, &buf, plan.title);
    try writeKey(allocator, &buf, true, "start");
    try writeJsonString(allocator, &buf, plan.start);
    try writeKey(allocator, &buf, true, "quantum");
    try writeInt(allocator, &buf, plan.quantum);
    try writeKey(allocator, &buf, true, "mode");
    try writeJsonString(allocator, &buf, plan.mode);

    try writeKey(allocator, &buf, true, "segments");
    try buf.append(allocator, '[');
    for (plan.segments, 0..) |s, i| {
        if (i > 0) try buf.append(allocator, ',');
        try buf.append(allocator, '{');
        try writeKey(allocator, &buf, false, "type");
        try writeJsonString(allocator, &buf, s.seg_type);
        try writeKey(allocator, &buf, true, "q");
        try writeInt(allocator, &buf, s.q);
        if (s.speaker) |v| {
            try writeKey(allocator, &buf, true, "speaker");
            try writeJsonString(allocator, &buf, v);
        }
        if (s.label) |v| {
            try writeKey(allocator, &buf, true, "label");
            try writeJsonString(allocator, &buf, v);
        }
        try buf.append(allocator, '}');
    }
    try buf.append(allocator, ']');

    try writeKey(allocator, &buf, true, "nodes");
    try buf.append(allocator, '[');
    for (plan.nodes, 0..) |n, i| {
        if (i > 0) try buf.append(allocator, ',');
        try buf.append(allocator, '{');
        try writeKey(allocator, &buf, false, "id");
        try writeJsonString(allocator, &buf, n.id);
        try writeKey(allocator, &buf, true, "name");
        try writeJsonString(allocator, &buf, n.name);
        try writeKey(allocator, &buf, true, "role");
        try writeJsonString(allocator, &buf, n.role);
        try writeKey(allocator, &buf, true, "delay");
        try writeInt(allocator, &buf, n.delay);
        try writeKey(allocator, &buf, true, "location");
        try writeJsonString(allocator, &buf, n.location);
        try buf.append(allocator, '}');
    }
    try buf.append(allocator, ']');
    try buf.append(allocator, '}');
    return buf.toOwnedSlice(allocator);
}

/// Parse wire JSON (any key order) into a typed plan. Only v2 fields are
/// read; missing fields take the createPlan defaults. Free with deinitPlan.
/// Note: a typed plan re-serialises in planToJson key order, so for a plan
/// received from another sender compute the planId from the received text
/// (ltx_v11.makePlanIdJson), not from the parsed typed plan.
pub fn planFromJson(allocator: Allocator, json: []const u8) !LtxPlan {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return error.InvalidPlan;

    const S = struct {
        fn str(v: std.json.Value, key: []const u8) ?[]const u8 {
            if (v != .object) return null;
            const f = v.object.get(key) orelse return null;
            return if (f == .string) f.string else null;
        }
        fn int(v: std.json.Value, key: []const u8) ?i64 {
            if (v != .object) return null;
            const f = v.object.get(key) orelse return null;
            return switch (f) {
                .integer => |n| n,
                .float => |x| @intFromFloat(x),
                else => null,
            };
        }
        fn arr(v: std.json.Value, key: []const u8) []std.json.Value {
            const f = v.object.get(key) orelse return &.{};
            return if (f == .array) f.array.items else &.{};
        }
    };

    const jnodes = S.arr(root, "nodes");
    const jsegs = S.arr(root, "segments");
    const nodes = try allocator.alloc(Node, jnodes.len);
    defer allocator.free(nodes);
    const segs = try allocator.alloc(SegmentTemplate, jsegs.len);
    defer allocator.free(segs);
    for (jnodes, 0..) |n, i| nodes[i] = .{
        .id = S.str(n, "id") orelse "",
        .name = S.str(n, "name") orelse "",
        .role = S.str(n, "role") orelse (if (i == 0) "HOST" else "PARTICIPANT"),
        .delay = S.int(n, "delay") orelse 0,
        .location = S.str(n, "location") orelse "",
    };
    for (jsegs, 0..) |s, i| segs[i] = .{
        .seg_type = S.str(s, "type") orelse "",
        .q = @intCast(@max(0, S.int(s, "q") orelse 0)),
        .speaker = S.str(s, "speaker"),
        .label = S.str(s, "label"),
    };
    return clonePlan(allocator, .{
        .v = @intCast(@max(0, S.int(root, "v") orelse 2)),
        .title = S.str(root, "title") orelse "LTX Session",
        .start = S.str(root, "start") orelse "",
        .quantum = @intCast(@max(0, S.int(root, "quantum") orelse DEFAULT_QUANTUM)),
        .mode = S.str(root, "mode") orelse "LTX",
        .nodes = nodes,
        .segments = segs,
    });
}

// ── Frozen v2 planId (§4.3) ────────────────────────────────────────────────

/// UTF-16 code units of a code point (second unit 0 in the BMP).
fn utf16Units(cp: u21) [2]u16 {
    if (cp < 0x10000) return .{ @intCast(cp), 0 };
    const v = cp - 0x10000;
    return .{ 0xD800 + @as(u16, @intCast(v >> 10)), 0xDC00 + @as(u16, @intCast(v & 0x3FF)) };
}

/// Frozen v2 hash: h = imul(31, h) + charCodeAt(i) over the UTF-16 code
/// units of s, wrapping u32 (Math.imul in ltx-sdk.js).
pub fn imul31Utf16(s: []const u8) u32 {
    // Over UTF-8, or WTF-8 (a lone surrogate is one code unit).
    var h: u32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const cp = nextWtf8(s, &i);
        const u = utf16Units(cp);
        h = h *% 31 +% @as(u32, u[0]);
        if (cp >= 0x10000) h = h *% 31 +% @as(u32, u[1]);
    }
    return h;
}

// ── planId HOSTSTR / NODESTR name tokens (LTX-SPECIFICATION.md §4.3) ────────
// JS name.replace(/\s+/g, '').toUpperCase().slice(0, n): ECMAScript \s, the
// full Unicode case mapping of JS toUpperCase (generated table: every 1:1
// mapping as strided runs and every special casing, such as U+00DF to "SS")
// and a slice in UTF-16 code units. Strings are UTF-8; a lone UTF-16
// surrogate is held as WTF-8 (ED A0..BF xx). The same code is in
// interplanet_ltx.zig and ltx_v11.zig, which are built as separate modules.

// BEGIN GENERATED UPPER TABLE
// Generated by scripts/conformance/gen-upper-tables.js from JS toUpperCase, Unicode 17.0 (node 22.22.2).
const UpperRun = struct { first: u21, last: u21, stride: u21, delta: i32 };
const UpperSpecial = struct { cp: u21, up: [3]u21, len: u2 };
const upper_runs = [_]UpperRun{
    .{ .first = 0x61, .last = 0x7A, .stride = 1, .delta = -32 },
    .{ .first = 0xB5, .last = 0xB5, .stride = 1, .delta = 743 },
    .{ .first = 0xE0, .last = 0xF6, .stride = 1, .delta = -32 },
    .{ .first = 0xF8, .last = 0xFE, .stride = 1, .delta = -32 },
    .{ .first = 0xFF, .last = 0xFF, .stride = 1, .delta = 121 },
    .{ .first = 0x101, .last = 0x12F, .stride = 2, .delta = -1 },
    .{ .first = 0x131, .last = 0x131, .stride = 1, .delta = -232 },
    .{ .first = 0x133, .last = 0x137, .stride = 2, .delta = -1 },
    .{ .first = 0x13A, .last = 0x148, .stride = 2, .delta = -1 },
    .{ .first = 0x14B, .last = 0x177, .stride = 2, .delta = -1 },
    .{ .first = 0x17A, .last = 0x17E, .stride = 2, .delta = -1 },
    .{ .first = 0x17F, .last = 0x17F, .stride = 1, .delta = -300 },
    .{ .first = 0x180, .last = 0x180, .stride = 1, .delta = 195 },
    .{ .first = 0x183, .last = 0x185, .stride = 2, .delta = -1 },
    .{ .first = 0x188, .last = 0x188, .stride = 1, .delta = -1 },
    .{ .first = 0x18C, .last = 0x18C, .stride = 1, .delta = -1 },
    .{ .first = 0x192, .last = 0x192, .stride = 1, .delta = -1 },
    .{ .first = 0x195, .last = 0x195, .stride = 1, .delta = 97 },
    .{ .first = 0x199, .last = 0x199, .stride = 1, .delta = -1 },
    .{ .first = 0x19A, .last = 0x19A, .stride = 1, .delta = 163 },
    .{ .first = 0x19B, .last = 0x19B, .stride = 1, .delta = 42561 },
    .{ .first = 0x19E, .last = 0x19E, .stride = 1, .delta = 130 },
    .{ .first = 0x1A1, .last = 0x1A5, .stride = 2, .delta = -1 },
    .{ .first = 0x1A8, .last = 0x1A8, .stride = 1, .delta = -1 },
    .{ .first = 0x1AD, .last = 0x1AD, .stride = 1, .delta = -1 },
    .{ .first = 0x1B0, .last = 0x1B0, .stride = 1, .delta = -1 },
    .{ .first = 0x1B4, .last = 0x1B6, .stride = 2, .delta = -1 },
    .{ .first = 0x1B9, .last = 0x1B9, .stride = 1, .delta = -1 },
    .{ .first = 0x1BD, .last = 0x1BD, .stride = 1, .delta = -1 },
    .{ .first = 0x1BF, .last = 0x1BF, .stride = 1, .delta = 56 },
    .{ .first = 0x1C5, .last = 0x1C5, .stride = 1, .delta = -1 },
    .{ .first = 0x1C6, .last = 0x1C6, .stride = 1, .delta = -2 },
    .{ .first = 0x1C8, .last = 0x1C8, .stride = 1, .delta = -1 },
    .{ .first = 0x1C9, .last = 0x1C9, .stride = 1, .delta = -2 },
    .{ .first = 0x1CB, .last = 0x1CB, .stride = 1, .delta = -1 },
    .{ .first = 0x1CC, .last = 0x1CC, .stride = 1, .delta = -2 },
    .{ .first = 0x1CE, .last = 0x1DC, .stride = 2, .delta = -1 },
    .{ .first = 0x1DD, .last = 0x1DD, .stride = 1, .delta = -79 },
    .{ .first = 0x1DF, .last = 0x1EF, .stride = 2, .delta = -1 },
    .{ .first = 0x1F2, .last = 0x1F2, .stride = 1, .delta = -1 },
    .{ .first = 0x1F3, .last = 0x1F3, .stride = 1, .delta = -2 },
    .{ .first = 0x1F5, .last = 0x1F5, .stride = 1, .delta = -1 },
    .{ .first = 0x1F9, .last = 0x21F, .stride = 2, .delta = -1 },
    .{ .first = 0x223, .last = 0x233, .stride = 2, .delta = -1 },
    .{ .first = 0x23C, .last = 0x23C, .stride = 1, .delta = -1 },
    .{ .first = 0x23F, .last = 0x240, .stride = 1, .delta = 10815 },
    .{ .first = 0x242, .last = 0x242, .stride = 1, .delta = -1 },
    .{ .first = 0x247, .last = 0x24F, .stride = 2, .delta = -1 },
    .{ .first = 0x250, .last = 0x250, .stride = 1, .delta = 10783 },
    .{ .first = 0x251, .last = 0x251, .stride = 1, .delta = 10780 },
    .{ .first = 0x252, .last = 0x252, .stride = 1, .delta = 10782 },
    .{ .first = 0x253, .last = 0x253, .stride = 1, .delta = -210 },
    .{ .first = 0x254, .last = 0x254, .stride = 1, .delta = -206 },
    .{ .first = 0x256, .last = 0x257, .stride = 1, .delta = -205 },
    .{ .first = 0x259, .last = 0x259, .stride = 1, .delta = -202 },
    .{ .first = 0x25B, .last = 0x25B, .stride = 1, .delta = -203 },
    .{ .first = 0x25C, .last = 0x25C, .stride = 1, .delta = 42319 },
    .{ .first = 0x260, .last = 0x260, .stride = 1, .delta = -205 },
    .{ .first = 0x261, .last = 0x261, .stride = 1, .delta = 42315 },
    .{ .first = 0x263, .last = 0x263, .stride = 1, .delta = -207 },
    .{ .first = 0x264, .last = 0x264, .stride = 1, .delta = 42343 },
    .{ .first = 0x265, .last = 0x265, .stride = 1, .delta = 42280 },
    .{ .first = 0x266, .last = 0x266, .stride = 1, .delta = 42308 },
    .{ .first = 0x268, .last = 0x268, .stride = 1, .delta = -209 },
    .{ .first = 0x269, .last = 0x269, .stride = 1, .delta = -211 },
    .{ .first = 0x26A, .last = 0x26A, .stride = 1, .delta = 42308 },
    .{ .first = 0x26B, .last = 0x26B, .stride = 1, .delta = 10743 },
    .{ .first = 0x26C, .last = 0x26C, .stride = 1, .delta = 42305 },
    .{ .first = 0x26F, .last = 0x26F, .stride = 1, .delta = -211 },
    .{ .first = 0x271, .last = 0x271, .stride = 1, .delta = 10749 },
    .{ .first = 0x272, .last = 0x272, .stride = 1, .delta = -213 },
    .{ .first = 0x275, .last = 0x275, .stride = 1, .delta = -214 },
    .{ .first = 0x27D, .last = 0x27D, .stride = 1, .delta = 10727 },
    .{ .first = 0x280, .last = 0x280, .stride = 1, .delta = -218 },
    .{ .first = 0x282, .last = 0x282, .stride = 1, .delta = 42307 },
    .{ .first = 0x283, .last = 0x283, .stride = 1, .delta = -218 },
    .{ .first = 0x287, .last = 0x287, .stride = 1, .delta = 42282 },
    .{ .first = 0x288, .last = 0x288, .stride = 1, .delta = -218 },
    .{ .first = 0x289, .last = 0x289, .stride = 1, .delta = -69 },
    .{ .first = 0x28A, .last = 0x28B, .stride = 1, .delta = -217 },
    .{ .first = 0x28C, .last = 0x28C, .stride = 1, .delta = -71 },
    .{ .first = 0x292, .last = 0x292, .stride = 1, .delta = -219 },
    .{ .first = 0x29D, .last = 0x29D, .stride = 1, .delta = 42261 },
    .{ .first = 0x29E, .last = 0x29E, .stride = 1, .delta = 42258 },
    .{ .first = 0x345, .last = 0x345, .stride = 1, .delta = 84 },
    .{ .first = 0x371, .last = 0x373, .stride = 2, .delta = -1 },
    .{ .first = 0x377, .last = 0x377, .stride = 1, .delta = -1 },
    .{ .first = 0x37B, .last = 0x37D, .stride = 1, .delta = 130 },
    .{ .first = 0x3AC, .last = 0x3AC, .stride = 1, .delta = -38 },
    .{ .first = 0x3AD, .last = 0x3AF, .stride = 1, .delta = -37 },
    .{ .first = 0x3B1, .last = 0x3C1, .stride = 1, .delta = -32 },
    .{ .first = 0x3C2, .last = 0x3C2, .stride = 1, .delta = -31 },
    .{ .first = 0x3C3, .last = 0x3CB, .stride = 1, .delta = -32 },
    .{ .first = 0x3CC, .last = 0x3CC, .stride = 1, .delta = -64 },
    .{ .first = 0x3CD, .last = 0x3CE, .stride = 1, .delta = -63 },
    .{ .first = 0x3D0, .last = 0x3D0, .stride = 1, .delta = -62 },
    .{ .first = 0x3D1, .last = 0x3D1, .stride = 1, .delta = -57 },
    .{ .first = 0x3D5, .last = 0x3D5, .stride = 1, .delta = -47 },
    .{ .first = 0x3D6, .last = 0x3D6, .stride = 1, .delta = -54 },
    .{ .first = 0x3D7, .last = 0x3D7, .stride = 1, .delta = -8 },
    .{ .first = 0x3D9, .last = 0x3EF, .stride = 2, .delta = -1 },
    .{ .first = 0x3F0, .last = 0x3F0, .stride = 1, .delta = -86 },
    .{ .first = 0x3F1, .last = 0x3F1, .stride = 1, .delta = -80 },
    .{ .first = 0x3F2, .last = 0x3F2, .stride = 1, .delta = 7 },
    .{ .first = 0x3F3, .last = 0x3F3, .stride = 1, .delta = -116 },
    .{ .first = 0x3F5, .last = 0x3F5, .stride = 1, .delta = -96 },
    .{ .first = 0x3F8, .last = 0x3F8, .stride = 1, .delta = -1 },
    .{ .first = 0x3FB, .last = 0x3FB, .stride = 1, .delta = -1 },
    .{ .first = 0x430, .last = 0x44F, .stride = 1, .delta = -32 },
    .{ .first = 0x450, .last = 0x45F, .stride = 1, .delta = -80 },
    .{ .first = 0x461, .last = 0x481, .stride = 2, .delta = -1 },
    .{ .first = 0x48B, .last = 0x4BF, .stride = 2, .delta = -1 },
    .{ .first = 0x4C2, .last = 0x4CE, .stride = 2, .delta = -1 },
    .{ .first = 0x4CF, .last = 0x4CF, .stride = 1, .delta = -15 },
    .{ .first = 0x4D1, .last = 0x52F, .stride = 2, .delta = -1 },
    .{ .first = 0x561, .last = 0x586, .stride = 1, .delta = -48 },
    .{ .first = 0x10D0, .last = 0x10FA, .stride = 1, .delta = 3008 },
    .{ .first = 0x10FD, .last = 0x10FF, .stride = 1, .delta = 3008 },
    .{ .first = 0x13F8, .last = 0x13FD, .stride = 1, .delta = -8 },
    .{ .first = 0x1C80, .last = 0x1C80, .stride = 1, .delta = -6254 },
    .{ .first = 0x1C81, .last = 0x1C81, .stride = 1, .delta = -6253 },
    .{ .first = 0x1C82, .last = 0x1C82, .stride = 1, .delta = -6244 },
    .{ .first = 0x1C83, .last = 0x1C84, .stride = 1, .delta = -6242 },
    .{ .first = 0x1C85, .last = 0x1C85, .stride = 1, .delta = -6243 },
    .{ .first = 0x1C86, .last = 0x1C86, .stride = 1, .delta = -6236 },
    .{ .first = 0x1C87, .last = 0x1C87, .stride = 1, .delta = -6181 },
    .{ .first = 0x1C88, .last = 0x1C88, .stride = 1, .delta = 35266 },
    .{ .first = 0x1C8A, .last = 0x1C8A, .stride = 1, .delta = -1 },
    .{ .first = 0x1D79, .last = 0x1D79, .stride = 1, .delta = 35332 },
    .{ .first = 0x1D7D, .last = 0x1D7D, .stride = 1, .delta = 3814 },
    .{ .first = 0x1D8E, .last = 0x1D8E, .stride = 1, .delta = 35384 },
    .{ .first = 0x1E01, .last = 0x1E95, .stride = 2, .delta = -1 },
    .{ .first = 0x1E9B, .last = 0x1E9B, .stride = 1, .delta = -59 },
    .{ .first = 0x1EA1, .last = 0x1EFF, .stride = 2, .delta = -1 },
    .{ .first = 0x1F00, .last = 0x1F07, .stride = 1, .delta = 8 },
    .{ .first = 0x1F10, .last = 0x1F15, .stride = 1, .delta = 8 },
    .{ .first = 0x1F20, .last = 0x1F27, .stride = 1, .delta = 8 },
    .{ .first = 0x1F30, .last = 0x1F37, .stride = 1, .delta = 8 },
    .{ .first = 0x1F40, .last = 0x1F45, .stride = 1, .delta = 8 },
    .{ .first = 0x1F51, .last = 0x1F57, .stride = 2, .delta = 8 },
    .{ .first = 0x1F60, .last = 0x1F67, .stride = 1, .delta = 8 },
    .{ .first = 0x1F70, .last = 0x1F71, .stride = 1, .delta = 74 },
    .{ .first = 0x1F72, .last = 0x1F75, .stride = 1, .delta = 86 },
    .{ .first = 0x1F76, .last = 0x1F77, .stride = 1, .delta = 100 },
    .{ .first = 0x1F78, .last = 0x1F79, .stride = 1, .delta = 128 },
    .{ .first = 0x1F7A, .last = 0x1F7B, .stride = 1, .delta = 112 },
    .{ .first = 0x1F7C, .last = 0x1F7D, .stride = 1, .delta = 126 },
    .{ .first = 0x1FB0, .last = 0x1FB1, .stride = 1, .delta = 8 },
    .{ .first = 0x1FBE, .last = 0x1FBE, .stride = 1, .delta = -7205 },
    .{ .first = 0x1FD0, .last = 0x1FD1, .stride = 1, .delta = 8 },
    .{ .first = 0x1FE0, .last = 0x1FE1, .stride = 1, .delta = 8 },
    .{ .first = 0x1FE5, .last = 0x1FE5, .stride = 1, .delta = 7 },
    .{ .first = 0x214E, .last = 0x214E, .stride = 1, .delta = -28 },
    .{ .first = 0x2170, .last = 0x217F, .stride = 1, .delta = -16 },
    .{ .first = 0x2184, .last = 0x2184, .stride = 1, .delta = -1 },
    .{ .first = 0x24D0, .last = 0x24E9, .stride = 1, .delta = -26 },
    .{ .first = 0x2C30, .last = 0x2C5F, .stride = 1, .delta = -48 },
    .{ .first = 0x2C61, .last = 0x2C61, .stride = 1, .delta = -1 },
    .{ .first = 0x2C65, .last = 0x2C65, .stride = 1, .delta = -10795 },
    .{ .first = 0x2C66, .last = 0x2C66, .stride = 1, .delta = -10792 },
    .{ .first = 0x2C68, .last = 0x2C6C, .stride = 2, .delta = -1 },
    .{ .first = 0x2C73, .last = 0x2C73, .stride = 1, .delta = -1 },
    .{ .first = 0x2C76, .last = 0x2C76, .stride = 1, .delta = -1 },
    .{ .first = 0x2C81, .last = 0x2CE3, .stride = 2, .delta = -1 },
    .{ .first = 0x2CEC, .last = 0x2CEE, .stride = 2, .delta = -1 },
    .{ .first = 0x2CF3, .last = 0x2CF3, .stride = 1, .delta = -1 },
    .{ .first = 0x2D00, .last = 0x2D25, .stride = 1, .delta = -7264 },
    .{ .first = 0x2D27, .last = 0x2D27, .stride = 1, .delta = -7264 },
    .{ .first = 0x2D2D, .last = 0x2D2D, .stride = 1, .delta = -7264 },
    .{ .first = 0xA641, .last = 0xA66D, .stride = 2, .delta = -1 },
    .{ .first = 0xA681, .last = 0xA69B, .stride = 2, .delta = -1 },
    .{ .first = 0xA723, .last = 0xA72F, .stride = 2, .delta = -1 },
    .{ .first = 0xA733, .last = 0xA76F, .stride = 2, .delta = -1 },
    .{ .first = 0xA77A, .last = 0xA77C, .stride = 2, .delta = -1 },
    .{ .first = 0xA77F, .last = 0xA787, .stride = 2, .delta = -1 },
    .{ .first = 0xA78C, .last = 0xA78C, .stride = 1, .delta = -1 },
    .{ .first = 0xA791, .last = 0xA793, .stride = 2, .delta = -1 },
    .{ .first = 0xA794, .last = 0xA794, .stride = 1, .delta = 48 },
    .{ .first = 0xA797, .last = 0xA7A9, .stride = 2, .delta = -1 },
    .{ .first = 0xA7B5, .last = 0xA7C3, .stride = 2, .delta = -1 },
    .{ .first = 0xA7C8, .last = 0xA7CA, .stride = 2, .delta = -1 },
    .{ .first = 0xA7CD, .last = 0xA7DB, .stride = 2, .delta = -1 },
    .{ .first = 0xA7F6, .last = 0xA7F6, .stride = 1, .delta = -1 },
    .{ .first = 0xAB53, .last = 0xAB53, .stride = 1, .delta = -928 },
    .{ .first = 0xAB70, .last = 0xABBF, .stride = 1, .delta = -38864 },
    .{ .first = 0xFF41, .last = 0xFF5A, .stride = 1, .delta = -32 },
    .{ .first = 0x10428, .last = 0x1044F, .stride = 1, .delta = -40 },
    .{ .first = 0x104D8, .last = 0x104FB, .stride = 1, .delta = -40 },
    .{ .first = 0x10597, .last = 0x105A1, .stride = 1, .delta = -39 },
    .{ .first = 0x105A3, .last = 0x105B1, .stride = 1, .delta = -39 },
    .{ .first = 0x105B3, .last = 0x105B9, .stride = 1, .delta = -39 },
    .{ .first = 0x105BB, .last = 0x105BC, .stride = 1, .delta = -39 },
    .{ .first = 0x10CC0, .last = 0x10CF2, .stride = 1, .delta = -64 },
    .{ .first = 0x10D70, .last = 0x10D85, .stride = 1, .delta = -32 },
    .{ .first = 0x118C0, .last = 0x118DF, .stride = 1, .delta = -32 },
    .{ .first = 0x16E60, .last = 0x16E7F, .stride = 1, .delta = -32 },
    .{ .first = 0x16EBB, .last = 0x16ED3, .stride = 1, .delta = -27 },
    .{ .first = 0x1E922, .last = 0x1E943, .stride = 1, .delta = -34 },
};
const upper_special = [_]UpperSpecial{
    .{ .cp = 0xDF, .up = .{ 0x53, 0x53, 0x0 }, .len = 2 },
    .{ .cp = 0x149, .up = .{ 0x2BC, 0x4E, 0x0 }, .len = 2 },
    .{ .cp = 0x1F0, .up = .{ 0x4A, 0x30C, 0x0 }, .len = 2 },
    .{ .cp = 0x390, .up = .{ 0x399, 0x308, 0x301 }, .len = 3 },
    .{ .cp = 0x3B0, .up = .{ 0x3A5, 0x308, 0x301 }, .len = 3 },
    .{ .cp = 0x587, .up = .{ 0x535, 0x552, 0x0 }, .len = 2 },
    .{ .cp = 0x1E96, .up = .{ 0x48, 0x331, 0x0 }, .len = 2 },
    .{ .cp = 0x1E97, .up = .{ 0x54, 0x308, 0x0 }, .len = 2 },
    .{ .cp = 0x1E98, .up = .{ 0x57, 0x30A, 0x0 }, .len = 2 },
    .{ .cp = 0x1E99, .up = .{ 0x59, 0x30A, 0x0 }, .len = 2 },
    .{ .cp = 0x1E9A, .up = .{ 0x41, 0x2BE, 0x0 }, .len = 2 },
    .{ .cp = 0x1F50, .up = .{ 0x3A5, 0x313, 0x0 }, .len = 2 },
    .{ .cp = 0x1F52, .up = .{ 0x3A5, 0x313, 0x300 }, .len = 3 },
    .{ .cp = 0x1F54, .up = .{ 0x3A5, 0x313, 0x301 }, .len = 3 },
    .{ .cp = 0x1F56, .up = .{ 0x3A5, 0x313, 0x342 }, .len = 3 },
    .{ .cp = 0x1F80, .up = .{ 0x1F08, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F81, .up = .{ 0x1F09, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F82, .up = .{ 0x1F0A, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F83, .up = .{ 0x1F0B, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F84, .up = .{ 0x1F0C, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F85, .up = .{ 0x1F0D, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F86, .up = .{ 0x1F0E, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F87, .up = .{ 0x1F0F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F88, .up = .{ 0x1F08, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F89, .up = .{ 0x1F09, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F8A, .up = .{ 0x1F0A, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F8B, .up = .{ 0x1F0B, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F8C, .up = .{ 0x1F0C, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F8D, .up = .{ 0x1F0D, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F8E, .up = .{ 0x1F0E, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F8F, .up = .{ 0x1F0F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F90, .up = .{ 0x1F28, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F91, .up = .{ 0x1F29, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F92, .up = .{ 0x1F2A, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F93, .up = .{ 0x1F2B, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F94, .up = .{ 0x1F2C, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F95, .up = .{ 0x1F2D, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F96, .up = .{ 0x1F2E, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F97, .up = .{ 0x1F2F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F98, .up = .{ 0x1F28, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F99, .up = .{ 0x1F29, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F9A, .up = .{ 0x1F2A, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F9B, .up = .{ 0x1F2B, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F9C, .up = .{ 0x1F2C, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F9D, .up = .{ 0x1F2D, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F9E, .up = .{ 0x1F2E, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1F9F, .up = .{ 0x1F2F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA0, .up = .{ 0x1F68, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA1, .up = .{ 0x1F69, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA2, .up = .{ 0x1F6A, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA3, .up = .{ 0x1F6B, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA4, .up = .{ 0x1F6C, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA5, .up = .{ 0x1F6D, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA6, .up = .{ 0x1F6E, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA7, .up = .{ 0x1F6F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA8, .up = .{ 0x1F68, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FA9, .up = .{ 0x1F69, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FAA, .up = .{ 0x1F6A, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FAB, .up = .{ 0x1F6B, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FAC, .up = .{ 0x1F6C, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FAD, .up = .{ 0x1F6D, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FAE, .up = .{ 0x1F6E, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FAF, .up = .{ 0x1F6F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FB2, .up = .{ 0x1FBA, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FB3, .up = .{ 0x391, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FB4, .up = .{ 0x386, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FB6, .up = .{ 0x391, 0x342, 0x0 }, .len = 2 },
    .{ .cp = 0x1FB7, .up = .{ 0x391, 0x342, 0x399 }, .len = 3 },
    .{ .cp = 0x1FBC, .up = .{ 0x391, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FC2, .up = .{ 0x1FCA, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FC3, .up = .{ 0x397, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FC4, .up = .{ 0x389, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FC6, .up = .{ 0x397, 0x342, 0x0 }, .len = 2 },
    .{ .cp = 0x1FC7, .up = .{ 0x397, 0x342, 0x399 }, .len = 3 },
    .{ .cp = 0x1FCC, .up = .{ 0x397, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FD2, .up = .{ 0x399, 0x308, 0x300 }, .len = 3 },
    .{ .cp = 0x1FD3, .up = .{ 0x399, 0x308, 0x301 }, .len = 3 },
    .{ .cp = 0x1FD6, .up = .{ 0x399, 0x342, 0x0 }, .len = 2 },
    .{ .cp = 0x1FD7, .up = .{ 0x399, 0x308, 0x342 }, .len = 3 },
    .{ .cp = 0x1FE2, .up = .{ 0x3A5, 0x308, 0x300 }, .len = 3 },
    .{ .cp = 0x1FE3, .up = .{ 0x3A5, 0x308, 0x301 }, .len = 3 },
    .{ .cp = 0x1FE4, .up = .{ 0x3A1, 0x313, 0x0 }, .len = 2 },
    .{ .cp = 0x1FE6, .up = .{ 0x3A5, 0x342, 0x0 }, .len = 2 },
    .{ .cp = 0x1FE7, .up = .{ 0x3A5, 0x308, 0x342 }, .len = 3 },
    .{ .cp = 0x1FF2, .up = .{ 0x1FFA, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FF3, .up = .{ 0x3A9, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FF4, .up = .{ 0x38F, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0x1FF6, .up = .{ 0x3A9, 0x342, 0x0 }, .len = 2 },
    .{ .cp = 0x1FF7, .up = .{ 0x3A9, 0x342, 0x399 }, .len = 3 },
    .{ .cp = 0x1FFC, .up = .{ 0x3A9, 0x399, 0x0 }, .len = 2 },
    .{ .cp = 0xFB00, .up = .{ 0x46, 0x46, 0x0 }, .len = 2 },
    .{ .cp = 0xFB01, .up = .{ 0x46, 0x49, 0x0 }, .len = 2 },
    .{ .cp = 0xFB02, .up = .{ 0x46, 0x4C, 0x0 }, .len = 2 },
    .{ .cp = 0xFB03, .up = .{ 0x46, 0x46, 0x49 }, .len = 3 },
    .{ .cp = 0xFB04, .up = .{ 0x46, 0x46, 0x4C }, .len = 3 },
    .{ .cp = 0xFB05, .up = .{ 0x53, 0x54, 0x0 }, .len = 2 },
    .{ .cp = 0xFB06, .up = .{ 0x53, 0x54, 0x0 }, .len = 2 },
    .{ .cp = 0xFB13, .up = .{ 0x544, 0x546, 0x0 }, .len = 2 },
    .{ .cp = 0xFB14, .up = .{ 0x544, 0x535, 0x0 }, .len = 2 },
    .{ .cp = 0xFB15, .up = .{ 0x544, 0x53B, 0x0 }, .len = 2 },
    .{ .cp = 0xFB16, .up = .{ 0x54E, 0x546, 0x0 }, .len = 2 },
    .{ .cp = 0xFB17, .up = .{ 0x544, 0x53D, 0x0 }, .len = 2 },
};
// END GENERATED UPPER TABLE

/// Decode the code point at s[i.*] (UTF-8, or a WTF-8 surrogate) and advance;
/// an invalid byte is returned as itself.
fn nextWtf8(s: []const u8, i: *usize) u21 {
    const b = s[i.*];
    const len: usize = if (b < 0x80) 1 else if (b >> 5 == 6) 2 else if (b >> 4 == 14) 3 else if (b >> 3 == 30) 4 else 1;
    if (len == 1 or i.* + len > s.len) {
        i.* += 1;
        return b;
    }
    var cp: u21 = if (len == 2) b & 0x1f else if (len == 3) b & 0x0f else b & 0x07;
    for (s[i.* + 1 .. i.* + len]) |c| {
        if (c & 0xc0 != 0x80) {
            i.* += 1;
            return b;
        }
        cp = (cp << 6) | (c & 0x3f);
    }
    i.* += len;
    return cp;
}

/// Append cp as UTF-8 (a surrogate as its WTF-8 bytes).
fn appendWtf8(allocator: Allocator, buf: *std.ArrayList(u8), cp: u21) !void {
    if (cp < 0x80) {
        try buf.append(allocator, @intCast(cp));
    } else if (cp < 0x800) {
        try buf.appendSlice(allocator, &.{ @intCast(0xc0 | (cp >> 6)), @intCast(0x80 | (cp & 0x3f)) });
    } else if (cp < 0x10000) {
        try buf.appendSlice(allocator, &.{ @intCast(0xe0 | (cp >> 12)), @intCast(0x80 | ((cp >> 6) & 0x3f)), @intCast(0x80 | (cp & 0x3f)) });
    } else {
        try buf.appendSlice(allocator, &.{ @intCast(0xf0 | (cp >> 18)), @intCast(0x80 | ((cp >> 12) & 0x3f)), @intCast(0x80 | ((cp >> 6) & 0x3f)), @intCast(0x80 | (cp & 0x3f)) });
    }
}

/// Append the upper case of cp as String.prototype.toUpperCase does.
fn appendUpper(allocator: Allocator, buf: *std.ArrayList(u8), cp: u21) !void {
    if (cp >= 'a' and cp <= 'z') return buf.append(allocator, @intCast(cp - 32));
    if (cp >= 0xb5) {
        for (upper_special) |sp| {
            if (sp.cp == cp) {
                for (sp.up[0..sp.len]) |u| try appendWtf8(allocator, buf, u);
                return;
            }
        }
        for (upper_runs) |r| {
            if (cp < r.first) break;
            if (cp <= r.last and (cp - r.first) % r.stride == 0) {
                return appendWtf8(allocator, buf, @intCast(@as(i32, cp) + r.delta));
            }
        }
    }
    return appendWtf8(allocator, buf, cp);
}

fn isJsWhitespace(cp: u21) bool {
    return switch (cp) {
        0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}

/// s.slice(0, max) in UTF-16 code units (s is UTF-8 or WTF-8). When the cut
/// splits a surrogate pair JS keeps the lone high surrogate, and so does
/// this, as WTF-8 (planIdWtf8Hex in spec/golden/plan-id-prefixes.json).
fn sliceUtf16(allocator: Allocator, s: []const u8, max: usize) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    var units: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const start = i;
        const cp = nextWtf8(s, &i);
        const w: usize = if (cp >= 0x10000) 2 else 1;
        if (units + w > max) {
            if (units < max) try appendWtf8(allocator, &buf, @intCast(0xd800 + ((cp - 0x10000) >> 10)));
            break;
        }
        units += w;
        try buf.appendSlice(allocator, s[start..i]);
    }
    return buf.toOwnedSlice(allocator);
}

/// name.replace(/\s+/g, '').toUpperCase().slice(0, max)
fn nameToken(allocator: Allocator, name: []const u8, max: usize) ![]u8 {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var i: usize = 0;
    while (i < name.len) {
        const cp = nextWtf8(name, &i);
        if (isJsWhitespace(cp)) continue;
        try appendUpper(allocator, &buf, cp);
    }
    return sliceUtf16(allocator, buf.items, max);
}

/// Compute the deterministic v2 planId (§4.3, ltx-sdk.js makePlanId):
///   LTX-{YYYYMMDD}-{HOSTSTR}-{NODESTR}-v2-{hex8(imul31(planToJson(plan)))}
/// HOSTSTR: nodes[0].name, whitespace removed, upper-cased, 8 UTF-16 units
/// ("HOST" if there are no nodes). NODESTR: every other node name the same
/// way truncated to 4, joined by "-" and truncated to 16 ("RX" for a
/// single-node plan). The hash input is exactly the wire JSON. The typed
/// model is v2 only (plan.v must be 2); v3 plans go through
/// ltx_v11.makePlanIdJson.
pub fn makePlanId(allocator: Allocator, plan: LtxPlan) ![]u8 {
    var date_buf: [10]u8 = undefined;
    var di: usize = 0;
    for (plan.start[0..@min(10, plan.start.len)]) |c| {
        if (c != '-') {
            date_buf[di] = c;
            di += 1;
        }
    }
    const date = date_buf[0..di];

    const host_str = if (plan.nodes.len > 0 and plan.nodes[0].name.len > 0)
        try nameToken(allocator, plan.nodes[0].name, 8)
    else
        try allocator.dupe(u8, "HOST");
    defer allocator.free(host_str);

    var joined = std.ArrayList(u8){};
    defer joined.deinit(allocator);
    if (plan.nodes.len > 1) {
        for (plan.nodes[1..], 0..) |n, i| {
            if (i > 0) try joined.append(allocator, '-');
            const t = try nameToken(allocator, n.name, 4);
            defer allocator.free(t);
            try joined.appendSlice(allocator, t);
        }
    } else {
        try joined.appendSlice(allocator, "RX");
    }
    const node_str = try sliceUtf16(allocator, joined.items, 16);
    defer allocator.free(node_str);

    const json = try planToJson(allocator, plan);
    defer allocator.free(json);
    const h = imul31Utf16(json);
    return std.fmt.allocPrint(allocator, "LTX-{s}-{s}-{s}-v2-{x:0>8}", .{ date, host_str, node_str, h });
}

// ── Base64url ──────────────────────────────────────────────────────────────

/// Base64url-encode without padding.
fn b64Encode(allocator: Allocator, data: []const u8) ![]u8 {
    const enc = std.base64.url_safe_no_pad.Encoder;
    const out = try allocator.alloc(u8, enc.calcSize(data.len));
    _ = enc.encode(out, data);
    return out;
}

fn b64DecodeChar(c: u8) ?u32 {
    return switch (c) {
        'A'...'Z' => @as(u32, c) - 'A',
        'a'...'z' => @as(u32, c) - 'a' + 26,
        '0'...'9' => @as(u32, c) - '0' + 52,
        '+', '-' => 62,
        '/', '_' => 63,
        else => null,
    };
}

/// Base64 decode accepting the url-safe and standard alphabets, with or
/// without padding.
fn b64Decode(allocator: Allocator, s: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    var acc: u32 = 0;
    var bits: u5 = 0;
    for (s) |c| {
        if (c == '=') break;
        const v = b64DecodeChar(c) orelse return error.InvalidBase64;
        acc = (acc << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            try buf.append(allocator, @intCast((acc >> bits) & 0xff));
        }
    }
    return buf.toOwnedSlice(allocator);
}

/// Encode a plan as a `#l=` share fragment: base64url of planToJson.
pub fn encodeHash(allocator: Allocator, plan: LtxPlan) ![]u8 {
    const json = try planToJson(allocator, plan);
    defer allocator.free(json);
    const encoded = try b64Encode(allocator, json);
    defer allocator.free(encoded);
    return std.fmt.allocPrint(allocator, "#l={s}", .{encoded});
}

/// Decode a share fragment ("#l=...", "l=..." or the raw token) to its JSON
/// text (caller owns it). Parse it with planFromJson, or compute the
/// sender's planId from it with ltx_v11.makePlanIdJson.
pub fn decodeHash(allocator: Allocator, encoded: []const u8) ![]u8 {
    var token = encoded;
    if (std.mem.startsWith(u8, token, "#")) token = token[1..];
    if (std.mem.startsWith(u8, token, "l=")) token = token[2..];
    return b64Decode(allocator, token);
}

// ── Timing ─────────────────────────────────────────────────────────────────

fn parseDigits(s: []const u8) i64 {
    var v: i64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return v;
        v = v * 10 + @as(i64, c - '0');
    }
    return v;
}

fn daysFromCivil(y_in: i64, m_in: i64, d: i64) i64 {
    const y = if (m_in <= 2) y_in - 1 else y_in;
    const m = if (m_in <= 2) m_in + 9 else m_in - 3;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const doy = @divFloor(153 * m + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// Parse "YYYY-MM-DDTHH:MM:SS[.sss]Z" to epoch milliseconds.
pub fn parseIsoMs(iso: []const u8) i64 {
    if (iso.len < 19) return 0;
    var ms: i64 = 0;
    if (iso.len >= 23 and iso[19] == '.') ms = parseDigits(iso[20..23]);
    return daysFromCivil(parseDigits(iso[0..4]), parseDigits(iso[5..7]), parseDigits(iso[8..10])) * 86_400_000 +
        parseDigits(iso[11..13]) * 3_600_000 + parseDigits(iso[14..16]) * 60_000 +
        parseDigits(iso[17..19]) * 1000 + ms;
}

/// Format epoch ms as Date.prototype.toISOString ("YYYY-MM-DDTHH:MM:SS.sssZ").
pub fn formatIsoMs(buf: *[32]u8, epoch_ms: i64) []const u8 {
    const days = @divFloor(epoch_ms, 86_400_000);
    const tod = @mod(epoch_ms, 86_400_000);
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    const yr = yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{
        @as(u64, @intCast(yr)),                        @as(u64, @intCast(m)),                                @as(u64, @intCast(d)),
        @as(u64, @intCast(@divFloor(tod, 3_600_000))), @as(u64, @intCast(@mod(@divFloor(tod, 60_000), 60))), @as(u64, @intCast(@mod(@divFloor(tod, 1000), 60))),
        @as(u64, @intCast(@mod(tod, 1000))),
    }) catch unreachable;
}

/// Timed segments (ltx-sdk.js computeSegments): each segment lasts
/// q * quantum minutes, back to back from plan.start. Caller frees the slice
/// (the strings point into the plan).
pub fn computeSegments(allocator: Allocator, plan: LtxPlan) ![]TimedSegment {
    const q_ms: i64 = @as(i64, plan.quantum) * 60_000;
    var t = parseIsoMs(plan.start);
    const out = try allocator.alloc(TimedSegment, plan.segments.len);
    for (plan.segments, 0..) |s, i| {
        const dur = @as(i64, s.q) * q_ms;
        out[i] = .{
            .seg_type = s.seg_type,
            .q = s.q,
            .start_ms = t,
            .end_ms = t + dur,
            .dur_min = s.q * plan.quantum,
            .speaker = s.speaker,
            .label = s.label,
        };
        t += dur;
    }
    return out;
}

/// Total session duration in minutes (sum of q * quantum).
pub fn totalMin(plan: LtxPlan) u32 {
    var total: u32 = 0;
    for (plan.segments) |s| total += s.q * plan.quantum;
    return total;
}

// ── Delays (§3.7) ──────────────────────────────────────────────────────────

fn findNode(plan: LtxPlan, id: []const u8) ?Node {
    for (plan.nodes) |n| {
        if (std.mem.eql(u8, n.id, id)) return n;
    }
    return null;
}

/// One-way delay in seconds between two nodes (ltx-sdk.js pairDelay for a
/// v2 plan): the HOST (nodes[0]) to a node is that node's delay; between two
/// non-HOST nodes it is the sum of both HOST-relative delays.
pub fn pairDelay(plan: LtxPlan, node_a: []const u8, node_b: []const u8) !i64 {
    if (std.mem.eql(u8, node_a, node_b)) return 0;
    const a = findNode(plan, node_a) orelse return error.UnknownNode;
    const b = findNode(plan, node_b) orelse return error.UnknownNode;
    const host_id = plan.nodes[0].id;
    if (std.mem.eql(u8, node_a, host_id)) return b.delay;
    if (std.mem.eql(u8, node_b, host_id)) return a.delay;
    return a.delay + b.delay;
}

/// Delay matrix over every ordered node pair (ltx-sdk.js buildDelayMatrix,
/// §3.7.3). Caller frees the slice (the strings point into the plan).
pub fn buildDelayMatrix(allocator: Allocator, plan: LtxPlan) ![]DelayPair {
    var out = std.ArrayList(DelayPair){};
    errdefer out.deinit(allocator);
    for (plan.nodes, 0..) |from, i| {
        for (plan.nodes, 0..) |to, j| {
            if (i == j) continue;
            try out.append(allocator, .{
                .from_id = from.id,
                .from_name = from.name,
                .to_id = to.id,
                .to_name = to.name,
                .delay_seconds = try pairDelay(plan, from.id, to.id),
            });
        }
    }
    return out.toOwnedSlice(allocator);
}

// ── Node URLs ──────────────────────────────────────────────────────────────

/// encodeURIComponent
fn appendUriComponent(allocator: Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| {
        const keep = std.ascii.isAlphanumeric(c) or switch (c) {
            '-', '_', '.', '!', '~', '*', '\'', '(', ')' => true,
            else => false,
        };
        if (keep) {
            try buf.append(allocator, c);
        } else {
            var tmp: [3]u8 = undefined;
            try buf.appendSlice(allocator, std.fmt.bufPrint(&tmp, "%{X:0>2}", .{c}) catch unreachable);
        }
    }
}

/// Per-node session URLs (ltx-sdk.js buildNodeUrls):
/// `{base}?node={encodeURIComponent(id)}#l={token}`, where base is base_url
/// without its query and fragment. Free each `url` and the slice
/// (freeNodeUrls).
pub fn buildNodeUrls(allocator: Allocator, plan: LtxPlan, base_url: []const u8) ![]NodeUrl {
    const hash = try encodeHash(allocator, plan);
    defer allocator.free(hash);
    var base = base_url;
    if (std.mem.indexOfScalar(u8, base, '#')) |i| base = base[0..i];
    if (std.mem.indexOfScalar(u8, base, '?')) |i| base = base[0..i];

    const urls = try allocator.alloc(NodeUrl, plan.nodes.len);
    var done: usize = 0;
    errdefer {
        for (urls[0..done]) |u| allocator.free(u.url);
        allocator.free(urls);
    }
    for (plan.nodes, 0..) |node, i| {
        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);
        try buf.appendSlice(allocator, base);
        try buf.appendSlice(allocator, "?node=");
        try appendUriComponent(allocator, &buf, node.id);
        try buf.appendSlice(allocator, hash);
        urls[i] = .{ .node_id = node.id, .name = node.name, .role = node.role, .url = try buf.toOwnedSlice(allocator) };
        done += 1;
    }
    return urls;
}

pub fn freeNodeUrls(allocator: Allocator, urls: []NodeUrl) void {
    for (urls) |u| allocator.free(u.url);
    allocator.free(urls);
}

// ── Story 26.3: RFC 5545 TEXT escaping ────────────────────────────────────

/// Escape a string for RFC 5545 TEXT property values.
/// Escapes: backslash → \\, semicolon → \;, comma → \,, newline → \n
pub fn escapeIcsText(allocator: Allocator, s: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    for (s) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            ';' => try buf.appendSlice(allocator, "\\;"),
            ',' => try buf.appendSlice(allocator, "\\,"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            else => try buf.append(allocator, c),
        }
    }
    return buf.toOwnedSlice(allocator);
}

// ── Story 26.4: Protocol hardening ────────────────────────────────────────

/// Compute the plan-lock timeout in milliseconds.
pub fn planLockTimeoutMs(delay_seconds: u64) u64 {
    return delay_seconds * DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR * 1000;
}

/// Check delay violation.
/// Returns "ok", "violation", or "degraded".
pub fn checkDelayViolation(declared_delay_s: i64, measured_delay_s: i64) []const u8 {
    const diff: i64 = measured_delay_s - declared_delay_s;
    const abs_diff: u64 = if (diff < 0) @intCast(-diff) else @intCast(diff);
    if (abs_diff > DELAY_VIOLATION_DEGRADED_S) return "degraded";
    if (abs_diff > DELAY_VIOLATION_WARN_S) return "violation";
    return "ok";
}

/// Format total minutes as "Xh Ym", "Xh", "Ym", or "0m"
pub fn formatHms(allocator: Allocator, total_minutes: u32) ![]u8 {
    const h = total_minutes / 60;
    const m = total_minutes % 60;
    if (h > 0 and m > 0) {
        return std.fmt.allocPrint(allocator, "{d}h {d}m", .{ h, m });
    } else if (h > 0) {
        return std.fmt.allocPrint(allocator, "{d}h", .{h});
    } else if (m > 0) {
        return std.fmt.allocPrint(allocator, "{d}m", .{m});
    } else {
        return allocator.dupe(u8, "0m");
    }
}

// ── ICS generation ────────────────────────────────────────────────────────

/// name.replace(/\s+/g, '-').toUpperCase()
fn toIcsId(allocator: Allocator, name: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var it = (std.unicode.Utf8View.init(name) catch return error.InvalidUtf8).iterator();
    var in_ws = false;
    while (it.nextCodepoint()) |cp| {
        if (isJsWhitespace(cp)) {
            if (!in_ws) try buf.append(allocator, '-');
            in_ws = true;
            continue;
        }
        in_ws = false;
        try appendUpper(allocator, &buf, cp);
    }
    return allocator.dupe(u8, buf.items);
}

/// ICS DATE-TIME from epoch ms: "YYYYMMDDTHHMMSSZ".
fn fmtIcsDt(buf: *[16]u8, epoch_ms: i64) []const u8 {
    var iso_buf: [32]u8 = undefined;
    const iso = formatIsoMs(&iso_buf, epoch_ms);
    var k: usize = 0;
    for (iso[0..19]) |c| {
        if (c == '-' or c == ':') continue;
        buf[k] = c;
        k += 1;
    }
    buf[k] = 'Z';
    return buf[0 .. k + 1];
}

/// Generate an LTX-extended iCalendar (.ics) string for the plan
/// (ltx-sdk.js generateICS, organiser form). CRLF line endings (RFC 5545);
/// SUMMARY is RFC 5545 TEXT-escaped.
pub fn generateIcs(allocator: Allocator, plan: LtxPlan) ![]u8 {
    const plan_id = try makePlanId(allocator, plan);
    defer allocator.free(plan_id);

    const start_ms = parseIsoMs(plan.start);
    const end_ms = start_ms + @as(i64, totalMin(plan)) * 60_000;
    var b1: [16]u8 = undefined;
    var b2: [16]u8 = undefined;
    var b3: [16]u8 = undefined;
    const dt_start = fmtIcsDt(&b1, start_ms);
    const dt_end = fmtIcsDt(&b2, end_ms);
    const dt_stamp = fmtIcsDt(&b3, std.time.milliTimestamp());

    var seg_tpl = std.ArrayList(u8){};
    defer seg_tpl.deinit(allocator);
    for (plan.segments, 0..) |s, i| {
        if (i > 0) try seg_tpl.append(allocator, ',');
        try seg_tpl.appendSlice(allocator, s.seg_type);
    }

    const title = try escapeIcsText(allocator, plan.title);
    defer allocator.free(title);

    const host_name = if (plan.nodes.len > 0) plan.nodes[0].name else "Earth HQ";
    const participants = if (plan.nodes.len > 1) plan.nodes[1..] else plan.nodes[0..0];

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);
    const w = struct {
        fn line(a: Allocator, o: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
            const s = try std.fmt.allocPrint(a, fmt, args);
            defer a.free(s);
            if (o.items.len > 0) try o.appendSlice(a, "\r\n");
            try o.appendSlice(a, s);
        }
    };

    var part_names = std.ArrayList(u8){};
    defer part_names.deinit(allocator);
    var delay_desc = std.ArrayList(u8){};
    defer delay_desc.deinit(allocator);
    for (participants, 0..) |p, i| {
        if (i > 0) {
            try part_names.appendSlice(allocator, ", ");
            try delay_desc.appendSlice(allocator, " \u{00b7} ");
        }
        try part_names.appendSlice(allocator, p.name);
        const mins = @divFloor(p.delay + 30, 60); // Math.round(delay / 60)
        const d = try std.fmt.allocPrint(allocator, "{s}: {d} min one-way", .{ p.name, mins });
        defer allocator.free(d);
        try delay_desc.appendSlice(allocator, d);
    }
    if (participants.len == 0) {
        try part_names.appendSlice(allocator, "remote nodes");
        try delay_desc.appendSlice(allocator, "no participant delay configured");
    }

    try w.line(allocator, &out, "BEGIN:VCALENDAR", .{});
    try w.line(allocator, &out, "VERSION:2.0", .{});
    try w.line(allocator, &out, "PRODID:-//InterPlanet//LTX v1.1//EN", .{});
    try w.line(allocator, &out, "CALSCALE:GREGORIAN", .{});
    try w.line(allocator, &out, "METHOD:PUBLISH", .{});
    try w.line(allocator, &out, "BEGIN:VEVENT", .{});
    try w.line(allocator, &out, "UID:{s}@interplanet.live", .{plan_id});
    try w.line(allocator, &out, "DTSTAMP:{s}", .{dt_stamp});
    try w.line(allocator, &out, "DTSTART:{s}", .{dt_start});
    try w.line(allocator, &out, "DTEND:{s}", .{dt_end});
    try w.line(allocator, &out, "SUMMARY:{s}", .{title});
    try w.line(allocator, &out, "DESCRIPTION:LTX session \u{2014} {s} with {s}\\nSignal delays: {s}\\nMode: {s} \u{00b7} Segment plan: {s}\\nGenerated by InterPlanet (https://interplanet.live)", .{ host_name, part_names.items, delay_desc.items, plan.mode, seg_tpl.items });
    try w.line(allocator, &out, "LTX:1", .{});
    try w.line(allocator, &out, "LTX-PLANID:{s}", .{plan_id});
    try w.line(allocator, &out, "LTX-QUANTUM:PT{d}M", .{plan.quantum});
    try w.line(allocator, &out, "LTX-SEGMENT-TEMPLATE:{s}", .{seg_tpl.items});
    try w.line(allocator, &out, "LTX-MODE:{s}", .{plan.mode});
    for (plan.nodes) |n| {
        const id = try toIcsId(allocator, n.name);
        defer allocator.free(id);
        try w.line(allocator, &out, "LTX-NODE:ID={s};ROLE={s}", .{ id, n.role });
    }
    for (participants) |n| {
        const id = try toIcsId(allocator, n.name);
        defer allocator.free(id);
        try w.line(allocator, &out, "LTX-DELAY;NODEID={s}:ONEWAY-MIN={d};ONEWAY-MAX={d};ONEWAY-ASSUMED={d}", .{ id, n.delay, n.delay + 120, n.delay });
    }
    try w.line(allocator, &out, "LTX-READINESS:CHECK=PT10M;REQUIRED=TRUE;FALLBACK=LTX-RELAY", .{});
    for (plan.nodes) |n| {
        if (!std.mem.eql(u8, n.location, "mars")) continue;
        const id = try toIcsId(allocator, n.name);
        defer allocator.free(id);
        try w.line(allocator, &out, "LTX-LOCALTIME:NODE={s};SCHEME=LMST;PARAMS=LONGITUDE:0E", .{id});
    }
    try w.line(allocator, &out, "END:VEVENT", .{});
    try w.line(allocator, &out, "END:VCALENDAR", .{});
    return out.toOwnedSlice(allocator);
}
