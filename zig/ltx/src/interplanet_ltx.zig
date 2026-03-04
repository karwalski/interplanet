// interplanet_ltx.zig — LTX (Light-Time eXchange) SDK for Zig
// Sprint 65 — Zig port of the LTX SDK
//
// API is intentionally structured for Zig idioms:
//   - All allocating functions return !T and accept an Allocator
//   - Callers own all returned slices/strings (free with allocator)
//   - JSON serialisation uses the canonical key order: v,title,start,quantum,mode,nodes,segments

const std = @import("std");
const Allocator = std.mem.Allocator;

// ── Protocol constants ─────────────────────────────────────────────────────

pub const VERSION = "1.0.0";
pub const DEFAULT_QUANTUM: u32 = 5;
pub const DEFAULT_API_BASE = "https://api.interplanettime.net/ltx/v1";

pub const SEG_TYPES = [_][]const u8{ "TX", "RX", "BUFFER", "HOLD", "PREP" };

// Story 26.4 constants
pub const DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR: u32 = 2;
pub const DELAY_VIOLATION_WARN_S: u32 = 120;
pub const DELAY_VIOLATION_DEGRADED_S: u32 = 300;
pub const SESSION_STATES = [_][]const u8{ "INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE" };

pub const DEFAULT_SEGMENTS = [_]SegmentTemplate{
    .{ .seg_type = "TX",     .duration = 3 },
    .{ .seg_type = "RX",     .duration = 1 },
    .{ .seg_type = "TX",     .duration = 2 },
    .{ .seg_type = "RX",     .duration = 1 },
    .{ .seg_type = "BUFFER", .duration = 2 },
};

// ── Data types ─────────────────────────────────────────────────────────────

/// Segment template (duration in quanta counts, not minutes)
pub const SegmentTemplate = struct {
    seg_type: []const u8,
    duration: u32,
};

/// A node participating in the LTX session
pub const Node = struct {
    id:       []const u8,
    name:     []const u8,
    location: []const u8,
    is_host:  bool,
};

/// A computed timed segment within a plan
pub const Segment = struct {
    id:           []const u8,
    seg_type:     []const u8,
    speaker:      ?[]const u8, // null for BUFFER / HOLD / PREP
    duration:     u32,         // minutes
    start_offset: u32,         // minutes from plan start
};

/// A per-node URL for sharing a session
pub const NodeUrl = struct {
    node_id:     []const u8,
    base_url:    []const u8,
    session_url: []const u8,
};

/// A complete LTX session plan
pub const Plan = struct {
    v:        []const u8, // "2"
    title:    []const u8,
    start:    []const u8, // ISO 8601 UTC
    quantum:  u32,
    mode:     []const u8, // "LTX"
    nodes:    []const Node,
    segments: []const Segment,
};

/// Options for createPlan
pub const CreatePlanOpts = struct {
    title:           ?[]const u8 = null,
    start:           ?[]const u8 = null,
    quantum:         ?u32        = null,
    mode:            ?[]const u8 = null,
    host_id:         ?[]const u8 = null,
    host_name:       ?[]const u8 = null,
    host_location:   ?[]const u8 = null,
    remote_id:       ?[]const u8 = null,
    remote_name:     ?[]const u8 = null,
    remote_location: ?[]const u8 = null,
    /// Custom node list — overrides host_*/remote_* fields when non-empty
    nodes:           []const Node          = &.{},
    /// Custom segment template — overrides defaults when non-empty
    segments:        []const SegmentTemplate = &.{},
};

// ── Internal helpers ──────────────────────────────────────────────────────

/// Escape a string for JSON output
fn jsonEscape(allocator: Allocator, s: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    for (s) |c| {
        switch (c) {
            '"'  => try buf.appendSlice(allocator,"\\\""),
            '\\' => try buf.appendSlice(allocator,"\\\\"),
            '\n' => try buf.appendSlice(allocator,"\\n"),
            '\r' => try buf.appendSlice(allocator,"\\r"),
            '\t' => try buf.appendSlice(allocator,"\\t"),
            else => try buf.append(allocator,c),
        }
    }
    return buf.toOwnedSlice(allocator);
}

/// Serialise a Node to a JSON object string
fn nodeToJson(allocator: Allocator, node: Node) ![]u8 {
    const esc_id  = try jsonEscape(allocator, node.id);
    defer allocator.free(esc_id);
    const esc_nm  = try jsonEscape(allocator, node.name);
    defer allocator.free(esc_nm);
    const esc_loc = try jsonEscape(allocator, node.location);
    defer allocator.free(esc_loc);

    return std.fmt.allocPrint(allocator,
        "{{\"id\":\"{s}\",\"name\":\"{s}\",\"location\":\"{s}\",\"is_host\":{s}}}",
        .{ esc_id, esc_nm, esc_loc, if (node.is_host) "true" else "false" });
}

/// Serialise a Segment to a JSON object string
fn segmentToJson(allocator: Allocator, seg: Segment) ![]u8 {
    const esc_id   = try jsonEscape(allocator, seg.id);
    defer allocator.free(esc_id);
    const esc_type = try jsonEscape(allocator, seg.seg_type);
    defer allocator.free(esc_type);

    if (seg.speaker) |spk| {
        const esc_spk = try jsonEscape(allocator, spk);
        defer allocator.free(esc_spk);
        return std.fmt.allocPrint(allocator,
            "{{\"id\":\"{s}\",\"type\":\"{s}\",\"speaker\":\"{s}\",\"duration\":{d},\"start_offset\":{d}}}",
            .{ esc_id, esc_type, esc_spk, seg.duration, seg.start_offset });
    } else {
        return std.fmt.allocPrint(allocator,
            "{{\"id\":\"{s}\",\"type\":\"{s}\",\"speaker\":null,\"duration\":{d},\"start_offset\":{d}}}",
            .{ esc_id, esc_type, seg.duration, seg.start_offset });
    }
}

/// Serialise a Plan to a JSON string.
/// Key order: v, title, start, quantum, mode, nodes, segments
pub fn planToJson(allocator: Allocator, plan: Plan) ![]u8 {
    var node_parts = std.ArrayList([]u8){};
    defer {
        for (node_parts.items) |p| allocator.free(p);
        node_parts.deinit(allocator);
    }
    for (plan.nodes) |n| {
        try node_parts.append(allocator,try nodeToJson(allocator, n));
    }

    var seg_parts = std.ArrayList([]u8){};
    defer {
        for (seg_parts.items) |p| allocator.free(p);
        seg_parts.deinit(allocator);
    }
    for (plan.segments) |s| {
        try seg_parts.append(allocator,try segmentToJson(allocator, s));
    }

    const nodes_json = try std.mem.join(allocator, ",", node_parts.items);
    defer allocator.free(nodes_json);
    const segs_json  = try std.mem.join(allocator, ",", seg_parts.items);
    defer allocator.free(segs_json);

    const esc_v     = try jsonEscape(allocator, plan.v);
    defer allocator.free(esc_v);
    const esc_title = try jsonEscape(allocator, plan.title);
    defer allocator.free(esc_title);
    const esc_start = try jsonEscape(allocator, plan.start);
    defer allocator.free(esc_start);
    const esc_mode  = try jsonEscape(allocator, plan.mode);
    defer allocator.free(esc_mode);

    return std.fmt.allocPrint(allocator,
        "{{\"v\":\"{s}\",\"title\":\"{s}\",\"start\":\"{s}\",\"quantum\":{d},\"mode\":\"{s}\",\"nodes\":[{s}],\"segments\":[{s}]}}",
        .{ esc_v, esc_title, esc_start, plan.quantum, esc_mode, nodes_json, segs_json });
}

// ── DJB polynomial hash ────────────────────────────────────────────────────

/// Compute a DJB-style 32-bit hash of input and return it as an 8-char hex string.
/// Uses wrapping arithmetic (*% and +%) to match the JS/OCaml ports exactly.
fn djbHash(allocator: Allocator, input: []const u8) ![]u8 {
    var h: u32 = 0;
    for (input) |c| {
        h = h *% 31 +% @as(u32, c);
    }
    return std.fmt.allocPrint(allocator, "{x:0>8}", .{h});
}

// ── Base64url ──────────────────────────────────────────────────────────────

const B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Base64url-encode (no padding; + → -, / → _)
fn b64Encode(allocator: Allocator, data: []const u8) ![]u8 {
    const len = data.len;
    var buf = std.ArrayList(u8){};
    var i: usize = 0;
    while (i < len) : (i += 3) {
        const b0: u32 = data[i];
        const b1: u32 = if (i + 1 < len) data[i + 1] else 0;
        const b2: u32 = if (i + 2 < len) data[i + 2] else 0;
        const n  = (b0 << 16) | (b1 << 8) | b2;
        try buf.append(allocator,B64_CHARS[(n >> 18) & 63]);
        try buf.append(allocator,B64_CHARS[(n >> 12) & 63]);
        try buf.append(allocator,B64_CHARS[(n >> 6)  & 63]);
        try buf.append(allocator,B64_CHARS[ n        & 63]);
    }
    // Trim padding chars based on remainder
    const rem = len % 3;
    if (rem == 1) {
        const sz = buf.items.len;
        buf.items.len = sz - 2;
    } else if (rem == 2) {
        const sz = buf.items.len;
        buf.items.len = sz - 1;
    }
    // Convert to base64url: + → -, / → _
    for (buf.items) |*c| {
        if (c.* == '+') c.* = '-';
        if (c.* == '/') c.* = '_';
    }
    return buf.toOwnedSlice(allocator);
}

fn b64DecodeChar(c: u8) u32 {
    return switch (c) {
        'A'...'Z' => @as(u32, c) - 65,
        'a'...'z' => @as(u32, c) - 97 + 26,
        '0'...'9' => @as(u32, c) - 48 + 52,
        '+', '-'  => 62,
        '/', '_'  => 63,
        else      => 0,
    };
}

/// Base64url-decode (handles both url-safe and standard variants, no padding required)
fn b64Decode(allocator: Allocator, s: []const u8) ![]u8 {
    const pad = (4 - (s.len % 4)) % 4;
    var padded = try allocator.alloc(u8, s.len + pad);
    defer allocator.free(padded);
    @memcpy(padded[0..s.len], s);
    for (0..pad) |k| padded[s.len + k] = '=';

    var buf = std.ArrayList(u8){};
    var i: usize = 0;
    while (i + 4 <= padded.len) : (i += 4) {
        const c0 = b64DecodeChar(padded[i]);
        const c1 = b64DecodeChar(padded[i + 1]);
        const c2 = b64DecodeChar(padded[i + 2]);
        const c3 = b64DecodeChar(padded[i + 3]);
        const n  = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;
        try buf.append(allocator,@as(u8, @intCast((n >> 16) & 255)));
        if (padded[i + 2] != '=') try buf.append(allocator,@as(u8, @intCast((n >> 8) & 255)));
        if (padded[i + 3] != '=') try buf.append(allocator,@as(u8, @intCast(n & 255)));
    }
    return buf.toOwnedSlice(allocator);
}

// ── Story 26.3: RFC 5545 TEXT escaping ────────────────────────────────────

/// Escape a string for RFC 5545 TEXT property values.
/// Escapes: backslash → \\, semicolon → \;, comma → \,, newline → \n
pub fn escapeIcsText(allocator: Allocator, s: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    for (s) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            ';'  => try buf.appendSlice(allocator, "\\;"),
            ','  => try buf.appendSlice(allocator, "\\,"),
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

// ── Plan functions ─────────────────────────────────────────────────────────

/// Create a new LTX plan from options.
/// Caller owns the returned Plan and all memory it points to.
pub fn createPlan(allocator: Allocator, opts: CreatePlanOpts) !Plan {
    const title   = opts.title   orelse "LTX Session";
    const quantum = opts.quantum orelse DEFAULT_QUANTUM;
    const mode    = opts.mode    orelse "LTX";

    // Default start = 5 min from now, second-precision UTC
    // Heap-allocated so the Plan can safely outlive this scope.
    const start: []const u8 = if (opts.start) |s| s else blk: {
        const epoch_s = std.time.timestamp() + 300;
        const start_str = try epochToIso(allocator, epoch_s);
        break :blk start_str;
    };

    // Build node list
    const nodes: []const Node = if (opts.nodes.len > 0) opts.nodes else blk: {
        var ns = try allocator.alloc(Node, 2);
        ns[0] = .{
            .id       = opts.host_id       orelse "N0",
            .name     = opts.host_name     orelse "Earth HQ",
            .location = opts.host_location orelse "earth",
            .is_host  = true,
        };
        ns[1] = .{
            .id       = opts.remote_id       orelse "N1",
            .name     = opts.remote_name     orelse "Mars Hab-01",
            .location = opts.remote_location orelse "mars",
            .is_host  = false,
        };
        break :blk ns;
    };

    // Build segment template to use
    const tmpl: []const SegmentTemplate = if (opts.segments.len > 0)
        opts.segments
    else
        &DEFAULT_SEGMENTS;

    // Compute timed segments
    const segs = try computeSegments(allocator, nodes, tmpl, quantum);

    return Plan{
        .v        = "2",
        .title    = title,
        .start    = start,
        .quantum  = quantum,
        .mode     = mode,
        .nodes    = nodes,
        .segments = segs,
    };
}

/// Upgrade a v1-style plan (no is_host discrimination) to v2 schema.
/// v2 plans are returned unchanged.
pub fn upgradeConfig(allocator: Allocator, plan: Plan) !Plan {
    if (std.mem.eql(u8, plan.v, "2") and plan.nodes.len > 0) return plan;
    // Build default nodes if missing
    var nodes = try allocator.alloc(Node, 2);
    if (plan.nodes.len >= 2) {
        nodes[0] = plan.nodes[0];
        nodes[1] = plan.nodes[1];
    } else if (plan.nodes.len == 1) {
        nodes[0] = plan.nodes[0];
        nodes[1] = .{ .id = "N1", .name = "Mars Hab-01", .location = "mars", .is_host = false };
    } else {
        nodes[0] = .{ .id = "N0", .name = "Earth HQ",    .location = "earth", .is_host = true  };
        nodes[1] = .{ .id = "N1", .name = "Mars Hab-01", .location = "mars",  .is_host = false };
    }
    return Plan{
        .v        = "2",
        .title    = plan.title,
        .start    = plan.start,
        .quantum  = plan.quantum,
        .mode     = plan.mode,
        .nodes    = nodes,
        .segments = plan.segments,
    };
}

/// Sum of all segment durations in minutes
pub fn totalMin(plan: Plan) u32 {
    var total: u32 = 0;
    for (plan.segments) |s| total += s.duration;
    return total;
}

/// Compute timed Segment array from nodes, template, and quantum.
/// TX segments → host node speaker; RX segments → first non-host node speaker;
/// other types → null speaker.
pub fn computeSegments(
    allocator: Allocator,
    nodes: []const Node,
    template: []const SegmentTemplate,
    quantum: u32,
) ![]Segment {
    // Identify host and remote
    const host_id: ?[]const u8 = for (nodes) |n| {
        if (n.is_host) break n.id;
    } else null;
    const remote_id: ?[]const u8 = for (nodes) |n| {
        if (!n.is_host) break n.id;
    } else null;

    var segs = try allocator.alloc(Segment, template.len);
    var offset: u32 = 0;
    for (template, 0..) |tmpl, idx| {
        const dur     = tmpl.duration * quantum;
        const id_str  = try std.fmt.allocPrint(allocator, "s{d}", .{idx + 1});
        const speaker: ?[]const u8 = blk: {
            if (std.mem.eql(u8, tmpl.seg_type, "TX")) break :blk host_id;
            if (std.mem.eql(u8, tmpl.seg_type, "RX")) break :blk remote_id;
            break :blk null;
        };
        segs[idx] = .{
            .id           = id_str,
            .seg_type     = tmpl.seg_type,
            .speaker      = speaker,
            .duration     = dur,
            .start_offset = offset,
        };
        offset += dur;
    }
    return segs;
}

/// Compute the deterministic plan ID.
/// Format: LTX-{YYYYMMDD}-{HOST_ID}-{REMOTE_ID}-v2-{HASH8}
/// HOST_ID  = host node id uppercased, spaces removed
/// REMOTE_ID = first non-host node id uppercased, spaces removed
pub fn makePlanId(allocator: Allocator, plan: Plan) ![]u8 {
    // Extract date from ISO start string (first 10 chars: YYYY-MM-DD)
    const date_raw = plan.start[0..@min(10, plan.start.len)];
    var date_buf: [8]u8 = undefined;
    var di: usize = 0;
    for (date_raw) |c| {
        if (c != '-') {
            date_buf[di] = c;
            di += 1;
        }
    }
    const date_str = date_buf[0..di];

    // Find host and remote nodes
    var host_id: []const u8   = "HOST";
    var remote_id: []const u8 = "RX";
    for (plan.nodes) |n| {
        if (n.is_host) { host_id = n.id; }
        else if (std.mem.eql(u8, remote_id, "RX")) { remote_id = n.id; }
    }

    // Uppercase + remove spaces
    const host_str = try upperNoSpaces(allocator, host_id);
    defer allocator.free(host_str);
    const dest_str = try upperNoSpaces(allocator, remote_id);
    defer allocator.free(dest_str);

    // Hash the plan JSON
    const json = try planToJson(allocator, plan);
    defer allocator.free(json);
    const hash_full = try djbHash(allocator, json);
    defer allocator.free(hash_full);
    const hash8 = hash_full[0..@min(8, hash_full.len)];

    return std.fmt.allocPrint(allocator, "LTX-{s}-{s}-{s}-v2-{s}",
        .{ date_str, host_str, dest_str, hash8 });
}

fn upperNoSpaces(allocator: Allocator, s: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    for (s) |c| {
        if (c != ' ') try buf.append(allocator,std.ascii.toUpper(c));
    }
    return buf.toOwnedSlice(allocator);
}

/// Encode a plan as a base64url hash fragment string "#l=…"
pub fn encodeHash(allocator: Allocator, plan: Plan) ![]u8 {
    const json = try planToJson(allocator, plan);
    defer allocator.free(json);
    const encoded = try b64Encode(allocator, json);
    defer allocator.free(encoded);
    return std.fmt.allocPrint(allocator, "#l={s}", .{encoded});
}

/// Decode a plan from a base64url hash fragment.
/// Accepts "#l=…", "l=…", or raw base64url token.
/// Returns the decoded JSON string (caller owns it).
pub fn decodeHash(allocator: Allocator, encoded: []const u8) ![]u8 {
    var token = encoded;
    if (std.mem.startsWith(u8, token, "#l=")) { token = token[3..]; }
    else if (std.mem.startsWith(u8, token, "l=")) { token = token[2..]; }
    return b64Decode(allocator, token);
}

/// Build per-node session URLs for sharing.
/// session_url = base_url?node={id}#l={encoded}
pub fn buildNodeUrls(allocator: Allocator, plan: Plan, base_url: []const u8) ![]NodeUrl {
    const hash = try encodeHash(allocator, plan);
    defer allocator.free(hash);

    // Strip any existing fragment from base_url
    var clean_base = base_url;
    if (std.mem.indexOf(u8, base_url, "#")) |i| clean_base = base_url[0..i];

    var urls = try allocator.alloc(NodeUrl, plan.nodes.len);
    for (plan.nodes, 0..) |node, i| {
        const session_url = try std.fmt.allocPrint(allocator,
            "{s}?node={s}{s}", .{ clean_base, node.id, hash });
        urls[i] = .{
            .node_id     = node.id,
            .base_url    = base_url,
            .session_url = session_url,
        };
    }
    return urls;
}

/// Build an N×N delay matrix (in quantum multiples converted to seconds).
/// Same node = 0; host ↔ remote = quantum * 4 (round-trip equivalent);
/// between two non-host nodes = quantum * 2.
pub fn buildDelayMatrix(allocator: Allocator, plan: Plan) ![][]u32 {
    const n = plan.nodes.len;
    var matrix = try allocator.alloc([]u32, n);
    for (0..n) |i| {
        matrix[i] = try allocator.alloc(u32, n);
        for (0..n) |j| {
            if (i == j) {
                matrix[i][j] = 0;
            } else {
                const from_host = plan.nodes[i].is_host;
                const to_host   = plan.nodes[j].is_host;
                if (from_host or to_host) {
                    // One-way: quantum * 4 is round-trip; single pass = quantum * 2
                    matrix[i][j] = plan.quantum * 4;
                } else {
                    matrix[i][j] = plan.quantum * 2;
                }
            }
        }
    }
    return matrix;
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

fn toIcsId(allocator: Allocator, name: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    for (name) |c| {
        if (c == ' ') { try buf.append(allocator,'-'); }
        else { try buf.append(allocator,std.ascii.toUpper(c)); }
    }
    return buf.toOwnedSlice(allocator);
}

fn fmtIsoCompact(allocator: Allocator, iso: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    for (iso) |c| {
        if (c != '-' and c != ':') try buf.append(allocator,c);
    }
    return buf.toOwnedSlice(allocator);
}

/// Generate a valid iCalendar (.ics) string for the plan.
/// Uses CRLF line endings as required by RFC 5545.
/// Includes LTX-PLANID and LTX-QUANTUM custom properties.
pub fn generateIcs(allocator: Allocator, plan: Plan) ![]u8 {
    const plan_id   = try makePlanId(allocator, plan);
    defer allocator.free(plan_id);

    const dt_start  = try fmtIsoCompact(allocator, plan.start);
    defer allocator.free(dt_start);

    // Compute end time from last segment
    var end_offset: u32 = 0;
    for (plan.segments) |s| end_offset = s.start_offset + s.duration;
    // Simple end ISO: add end_offset minutes to start
    const end_iso = try addMinutesToIso(allocator, plan.start, end_offset);
    defer allocator.free(end_iso);
    const dt_end = try fmtIsoCompact(allocator, end_iso);
    defer allocator.free(dt_end);

    // Segment template string
    var seg_types = std.ArrayList(u8){};
    defer seg_types.deinit(allocator);
    for (plan.segments, 0..) |s, i| {
        if (i > 0) try seg_types.append(allocator,',');
        try seg_types.appendSlice(allocator,s.seg_type);
    }

    // Node lines
    var node_lines = std.ArrayList(u8){};
    defer node_lines.deinit(allocator);
    for (plan.nodes) |node| {
        const ics_id = try toIcsId(allocator, node.name);
        defer allocator.free(ics_id);
        const role   = if (node.is_host) "HOST" else "PARTICIPANT";
        try node_lines.appendSlice(allocator,"LTX-NODE:ID=");
        try node_lines.appendSlice(allocator,ics_id);
        try node_lines.appendSlice(allocator,";ROLE=");
        try node_lines.appendSlice(allocator,role);
        try node_lines.appendSlice(allocator,"\r\n");
    }

    // DTSTAMP: current time formatted
    const now_epoch = std.time.timestamp();
    const now_iso   = try epochToIso(allocator, now_epoch);
    defer allocator.free(now_iso);
    const dt_stamp  = try fmtIsoCompact(allocator, now_iso);
    defer allocator.free(dt_stamp);

    const seg_tpl_str = try seg_types.toOwnedSlice(allocator);
    defer allocator.free(seg_tpl_str);

    const escaped_title = try escapeIcsText(allocator, plan.title);
    defer allocator.free(escaped_title);

    return std.fmt.allocPrint(allocator,
        "BEGIN:VCALENDAR\r\n" ++
        "VERSION:2.0\r\n" ++
        "PRODID:-//InterPlanet//LTX v1.0//EN\r\n" ++
        "CALSCALE:GREGORIAN\r\n" ++
        "METHOD:PUBLISH\r\n" ++
        "BEGIN:VEVENT\r\n" ++
        "UID:{s}@interplanet.live\r\n" ++
        "DTSTAMP:{s}\r\n" ++
        "DTSTART:{s}\r\n" ++
        "DTEND:{s}\r\n" ++
        "SUMMARY:{s}\r\n" ++
        "LTX:1\r\n" ++
        "LTX-PLANID:{s}\r\n" ++
        "LTX-QUANTUM:PT{d}M\r\n" ++
        "LTX-SEGMENT-TEMPLATE:{s}\r\n" ++
        "LTX-MODE:{s}\r\n" ++
        "{s}" ++
        "END:VEVENT\r\n" ++
        "END:VCALENDAR",
        .{
            plan_id,
            dt_stamp,
            dt_start,
            dt_end,
            escaped_title,
            plan_id,
            plan.quantum,
            seg_tpl_str,
            plan.mode,
            node_lines.items,
        },
    );
}

/// Add `minutes` to an ISO 8601 UTC string and return the new ISO string.
/// Only handles the simple case: no DST, no leap-second awareness.
fn addMinutesToIso(allocator: Allocator, iso: []const u8, minutes: u32) ![]u8 {
    // Parse: YYYY-MM-DDTHH:MM:SSZ
    if (iso.len < 19) return allocator.dupe(u8, iso);
    const yr  = parseDigits(iso[0..4]);
    const mo  = parseDigits(iso[5..7]);
    const dy  = parseDigits(iso[8..10]);
    const hh  = parseDigits(iso[11..13]);
    const mm  = parseDigits(iso[14..16]);
    const ss  = parseDigits(iso[17..19]);

    const total_min = hh * 60 + mm + minutes;
    const new_hh = (total_min / 60) % 24;
    const new_mm = total_min % 60;
    const extra_days = (total_min / 60) / 24;
    _ = extra_days; // simplified: assume same day for reasonable meeting lengths
    _ = ss;

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:00Z",
        .{ yr, mo, dy, new_hh, new_mm });
}

fn parseDigits(s: []const u8) u32 {
    var v: u32 = 0;
    for (s) |c| v = v * 10 + (@as(u32, c) - '0');
    return v;
}

/// Convert a Unix epoch timestamp to an ISO 8601 UTC string
fn epochToIso(allocator: Allocator, epoch_s: i64) ![]u8 {
    const secs_per_day: i64 = 86400;
    const days = @divFloor(epoch_s, secs_per_day);
    const tod  = @mod(epoch_s, secs_per_day);
    const z    = days + 719468;
    const era  = @divFloor(z, 146097);
    const doe  = z - era * 146097;
    const yoe  = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y    = yoe + era * 400;
    const doy  = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp   = @divFloor(5 * doy + 2, 153);
    const d    = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m    = if (mp < 10) mp + 3 else mp - 9;
    const yr   = if (m <= 2) y + 1 else y;
    const hh   = @divFloor(tod, 3600);
    const mm   = @divFloor(@mod(tod, 3600), 60);
    const ss   = @mod(tod, 60);
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ yr, m, d, hh, mm, ss });
}
