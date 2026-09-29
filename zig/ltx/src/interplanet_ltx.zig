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
    for (s) |c| {
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
    var h: u32 = 0;
    var it = (std.unicode.Utf8View.init(s) catch {
        for (s) |c| h = h *% 31 +% @as(u32, c);
        return h;
    }).iterator();
    while (it.nextCodepoint()) |cp| {
        const u = utf16Units(cp);
        h = h *% 31 +% @as(u32, u[0]);
        if (cp >= 0x10000) h = h *% 31 +% @as(u32, u[1]);
    }
    return h;
}

/// JavaScript `\s` (WhiteSpace and LineTerminator code points).
fn isJsWhitespace(cp: u21) bool {
    return switch (cp) {
        0x09...0x0d, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}

/// Append the upper case of cp as String.prototype.toUpperCase does, for
/// ASCII and Latin-1 (other code points are kept as they are).
fn appendUpper(allocator: Allocator, buf: *std.ArrayList(u8), cp: u21) !void {
    const up: u21 = switch (cp) {
        'a'...'z' => cp - 32,
        0xdf => return buf.appendSlice(allocator, "SS"), // sharp s
        0xb5 => 0x039c, // micro sign -> GREEK CAPITAL MU
        0xe0...0xf6, 0xf8...0xfe => cp - 32,
        0xff => 0x0178,
        else => cp,
    };
    var tmp: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(up, &tmp) catch unreachable;
    try buf.appendSlice(allocator, tmp[0..n]);
}

/// Truncate UTF-8 s to at most max UTF-16 code units (String.slice(0, max)),
/// never splitting a surrogate pair.
fn sliceUtf16(s: []const u8, max: usize) []const u8 {
    var units: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        const w: usize = if (len == 4) 2 else 1;
        if (units + w > max) break;
        units += w;
        i += len;
    }
    return s[0..@min(i, s.len)];
}

/// name.replace(/\s+/g, '').toUpperCase().slice(0, max)
fn nameToken(allocator: Allocator, name: []const u8, max: usize) ![]u8 {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    var it = (std.unicode.Utf8View.init(name) catch return error.InvalidUtf8).iterator();
    while (it.nextCodepoint()) |cp| {
        if (isJsWhitespace(cp)) continue;
        try appendUpper(allocator, &buf, cp);
    }
    return allocator.dupe(u8, sliceUtf16(buf.items, max));
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

    const host_str = if (plan.nodes.len > 0)
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
    const node_str = sliceUtf16(joined.items, 16);

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
