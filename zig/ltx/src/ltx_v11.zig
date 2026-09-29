// ltx_v11.zig — LTX v1.1 core subset (Epic 72, Story 72.2)
//
// Mirrors typescript/ltx/src: segments.ts, session.ts, amend.ts,
// registers.ts, merkle.ts, cbor.ts, cose.ts.
//
// These functions operate on the shared LTX wire format: plans and register
// entries as parsed std.json.Value trees (std.json object maps preserve key
// insertion order, which the frozen v2 planId hash depends on). The existing
// struct-based Plan API in interplanet_ltx.zig is unchanged.
//
// Effects note: transition() applies the LTX-SPECIFICATION.md §5 state
// machine and exposes state + lock outputs (the audit/notify/escalate effect
// list of the reference implementation is simplified away per the port
// cascade allowance; the state/lock sequence matches the golden table).

const std = @import("std");
const sec = @import("security.zig");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;

pub const V11_VERSION = "1.1.0";

pub const DELAY_VIOLATION_WARN_S: i64 = 120;
pub const DELAY_VIOLATION_DEGRADED_S: i64 = 300;
pub const LOCK_TIMEOUT_FACTOR: i64 = 2;

// ── JSON serialisation (canonical + insertion-order) ──────────────────────

fn writeJsonString(alloc: Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(alloc, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            0x08 => try buf.appendSlice(alloc, "\\b"),
            0x0c => try buf.appendSlice(alloc, "\\f"),
            0x00...0x07, 0x0b, 0x0e...0x1f => {
                var tmp: [8]u8 = undefined;
                const esc = std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{c}) catch unreachable;
                try buf.appendSlice(alloc, esc);
            },
            else => try buf.append(alloc, c),
        }
    }
    try buf.append(alloc, '"');
}

fn writeJsonValue(
    alloc: Allocator,
    buf: *std.ArrayList(u8),
    v: std.json.Value,
    sorted: bool,
    skip_top_key: ?[]const u8,
) !void {
    switch (v) {
        .null => try buf.appendSlice(alloc, "null"),
        .bool => |b| try buf.appendSlice(alloc, if (b) "true" else "false"),
        .integer => |n| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch unreachable;
            try buf.appendSlice(alloc, s);
        },
        .float => |f| try writeJsNumber(alloc, buf, f),
        .number_string => |ns| try writeJsNumber(alloc, buf, std.fmt.parseFloat(f64, ns) catch return error.InvalidNumber),
        .string => |s| try writeJsonString(alloc, buf, s),
        .array => |arr| {
            try buf.append(alloc, '[');
            for (arr.items, 0..) |item, i| {
                if (i > 0) try buf.append(alloc, ',');
                try writeJsonValue(alloc, buf, item, sorted, null);
            }
            try buf.append(alloc, ']');
        },
        .object => |obj| {
            var keys = std.ArrayList([]const u8){};
            defer keys.deinit(alloc);
            for (obj.keys()) |k| {
                if (skip_top_key) |skip| {
                    if (std.mem.eql(u8, k, skip)) continue;
                }
                try keys.append(alloc, k);
            }
            if (sorted) {
                std.sort.pdq([]const u8, keys.items, {}, struct {
                    pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                        return utf16Less(a, b);
                    }
                }.lessThan);
            }
            try buf.append(alloc, '{');
            for (keys.items, 0..) |k, i| {
                if (i > 0) try buf.append(alloc, ',');
                try writeJsonString(alloc, buf, k);
                try buf.append(alloc, ':');
                try writeJsonValue(alloc, buf, obj.get(k).?, sorted, null);
            }
            try buf.append(alloc, '}');
        },
    }
}

/// Number.prototype.toString (also the RFC 8785 number form).
fn writeJsNumber(alloc: Allocator, buf: *std.ArrayList(u8), f: f64) !void {
    if (!std.math.isFinite(f)) return buf.appendSlice(alloc, "null");
    if (f == 0) return buf.append(alloc, '0');
    var tmp: [64]u8 = undefined;
    const e_form = try std.fmt.bufPrint(&tmp, "{e}", .{@abs(f)}); // d[.ddd]e[-]X
    const e_at = std.mem.indexOfScalar(u8, e_form, 'e').?;
    const exp = try std.fmt.parseInt(i32, e_form[e_at + 1 ..], 10);
    var digits_buf: [40]u8 = undefined;
    var k: usize = 0;
    for (e_form[0..e_at]) |c| {
        if (c != '.') {
            digits_buf[k] = c;
            k += 1;
        }
    }
    const digits = digits_buf[0..k];
    const n: i32 = exp + 1;
    const ki: i32 = @intCast(k);
    if (f < 0) try buf.append(alloc, '-');
    if (ki <= n and n <= 21) {
        try buf.appendSlice(alloc, digits);
        try buf.appendNTimes(alloc, '0', @intCast(n - ki));
    } else if (0 < n and n <= 21) {
        try buf.appendSlice(alloc, digits[0..@intCast(n)]);
        try buf.append(alloc, '.');
        try buf.appendSlice(alloc, digits[@intCast(n)..]);
    } else if (-6 < n and n <= 0) {
        try buf.appendSlice(alloc, "0.");
        try buf.appendNTimes(alloc, '0', @intCast(-n));
        try buf.appendSlice(alloc, digits);
    } else {
        try buf.append(alloc, digits[0]);
        if (k > 1) {
            try buf.append(alloc, '.');
            try buf.appendSlice(alloc, digits[1..]);
        }
        const e = n - 1;
        var eb: [16]u8 = undefined;
        try buf.appendSlice(alloc, try std.fmt.bufPrint(&eb, "e{s}{d}", .{ if (e < 0) "-" else "+", @abs(e) }));
    }
}

/// UTF-16 code units of a code point (second unit 0 for the BMP).
fn utf16Units(cp: u21) [2]u16 {
    if (cp < 0x10000) return .{ @intCast(cp), 0 };
    const v = cp - 0x10000;
    return .{ 0xD800 + @as(u16, @intCast(v >> 10)), 0xDC00 + @as(u16, @intCast(v & 0x3FF)) };
}

/// Compare two UTF-8 strings by UTF-16 code units, as JavaScript
/// Array.prototype.sort and RFC 8785 order object keys.
pub fn utf16Less(a: []const u8, b: []const u8) bool {
    var ia = (std.unicode.Utf8View.init(a) catch return std.mem.lessThan(u8, a, b)).iterator();
    var ib = (std.unicode.Utf8View.init(b) catch return std.mem.lessThan(u8, a, b)).iterator();
    while (true) {
        const ca = ia.nextCodepoint() orelse return ib.nextCodepoint() != null;
        const cb = ib.nextCodepoint() orelse return false;
        if (ca == cb) continue;
        const ua = utf16Units(ca);
        const ub = utf16Units(cb);
        if (ua[0] != ub[0]) return ua[0] < ub[0];
        return ua[1] < ub[1];
    }
}

/// Frozen v2 planId hash: h = imul(31, h) + charCodeAt(i) over the UTF-16
/// code units of s (so non-ASCII titles hash as in JavaScript).
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

/// RFC 8785 canonical JSON of a parsed value: object keys sorted by UTF-16
/// code units at every level (as ltx-sdk.js canonicalJSON), compact
/// separators, JavaScript number form.
pub fn canonicalJsonValue(alloc: Allocator, v: std.json.Value) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(alloc);
    try writeJsonValue(alloc, &buf, v, true, null);
    return buf.toOwnedSlice(alloc);
}

/// Canonical JSON of an object value with one top-level key omitted
/// (used to serialise register entries without their "sig" field).
pub fn canonicalJsonValueSkip(alloc: Allocator, v: std.json.Value, skip: []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(alloc);
    try writeJsonValue(alloc, &buf, v, true, skip);
    return buf.toOwnedSlice(alloc);
}

/// Insertion-order compact JSON — mirrors JS JSON.stringify over a parsed
/// document (std.json object maps preserve key insertion order). This is the
/// byte stream the FROZEN v2 polynomial planId hash is computed over.
pub fn stringifyValue(alloc: Allocator, v: std.json.Value) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(alloc);
    try writeJsonValue(alloc, &buf, v, false, null);
    return buf.toOwnedSlice(alloc);
}

// ── Small JSON accessors ───────────────────────────────────────────────────

fn objGet(v: std.json.Value, key: []const u8) ?std.json.Value {
    return switch (v) {
        .object => |obj| obj.get(key),
        else => null,
    };
}

fn objStr(v: std.json.Value, key: []const u8) ?[]const u8 {
    const f = objGet(v, key) orelse return null;
    return switch (f) {
        .string => |s| s,
        else => null,
    };
}

fn objInt(v: std.json.Value, key: []const u8) ?i64 {
    const f = objGet(v, key) orelse return null;
    return switch (f) {
        .integer => |n| n,
        else => null,
    };
}

fn objArr(v: std.json.Value, key: []const u8) ?[]std.json.Value {
    const f = objGet(v, key) orelse return null;
    return switch (f) {
        .array => |a| a.items,
        else => null,
    };
}

fn hexEncode(alloc: Allocator, bytes: []const u8) ![]u8 {
    const out = try alloc.alloc(u8, bytes.len * 2);
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 15];
    }
    return out;
}

// ── ISO time parsing (UTC, ms precision ignored beyond seconds) ───────────

fn parseDigitsI64(s: []const u8) i64 {
    var v: i64 = 0;
    for (s) |c| v = v * 10 + @as(i64, c - '0');
    return v;
}

fn daysFromCivil(y_in: i64, m_in: i64, d: i64) i64 {
    const y = if (m_in <= 2) y_in - 1 else y_in;
    const m = if (m_in <= 2) m_in + 9 else m_in - 3;
    const era = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe = y - era * 400;
    const doy = @divFloor(153 * m + 2, 5) + d - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// Parse an ISO 8601 UTC string ("YYYY-MM-DDTHH:MM:SS[.sss]Z") to epoch ms.
pub fn parseIsoMs(iso: []const u8) i64 {
    if (iso.len < 19) return 0;
    const year = parseDigitsI64(iso[0..4]);
    const month = parseDigitsI64(iso[5..7]);
    const day = parseDigitsI64(iso[8..10]);
    const hour = parseDigitsI64(iso[11..13]);
    const min = parseDigitsI64(iso[14..16]);
    const s = parseDigitsI64(iso[17..19]);
    return daysFromCivil(year, month, day) * 86_400_000 +
        hour * 3_600_000 + min * 60_000 + s * 1000;
}

// ── Feature 1: v3 planId + pairDelay + computeSegmentsFor ─────────────────

fn upperNoWhitespace(alloc: Allocator, s: []const u8, max: usize) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(alloc);
    for (s) |c| {
        if (buf.items.len >= max) break;
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') continue;
        try buf.append(alloc, std.ascii.toUpper(c));
    }
    return buf.toOwnedSlice(alloc);
}

/// Compute the deterministic plan ID for a wire-format (JSON) plan.
///
/// v2 plans use the FROZEN legacy 32-bit polynomial hash over the
/// insertion-order JSON serialisation (LTX-SPECIFICATION.md §4.3) — kept
/// byte-identical for compatibility. Plans with v >= 3 hash SHA-256 over
/// RFC 8785 canonical JSON, first 8 hex digits, "-v3-" infix (§4.5).
pub fn makePlanIdJson(alloc: Allocator, plan: std.json.Value) ![]u8 {
    const start = objStr(plan, "start") orelse "";
    var date_buf: [8]u8 = undefined;
    var di: usize = 0;
    for (start[0..@min(10, start.len)]) |c| {
        if (c != '-') {
            date_buf[di] = c;
            di += 1;
        }
    }
    const date = date_buf[0..di];

    const nodes = objArr(plan, "nodes") orelse &[_]std.json.Value{};
    const host_str = if (nodes.len > 0)
        try upperNoWhitespace(alloc, objStr(nodes[0], "name") orelse "HOST", 8)
    else
        try alloc.dupe(u8, "HOST");
    defer alloc.free(host_str);

    var node_str: []u8 = undefined;
    if (nodes.len > 1) {
        var parts = std.ArrayList(u8){};
        errdefer parts.deinit(alloc);
        for (nodes[1..], 0..) |n, i| {
            if (i > 0) try parts.append(alloc, '-');
            const p = try upperNoWhitespace(alloc, objStr(n, "name") orelse "", 4);
            defer alloc.free(p);
            try parts.appendSlice(alloc, p);
        }
        if (parts.items.len > 16) parts.items.len = 16;
        node_str = try parts.toOwnedSlice(alloc);
    } else {
        node_str = try alloc.dupe(u8, "RX");
    }
    defer alloc.free(node_str);

    const v = objInt(plan, "v") orelse 2;
    if (v >= 3) {
        const canon = try canonicalJsonValue(alloc, plan);
        defer alloc.free(canon);
        const digest = sec.sha256(canon);
        const hex8 = try hexEncode(alloc, digest[0..4]);
        defer alloc.free(hex8);
        return std.fmt.allocPrint(alloc, "LTX-{s}-{s}-{s}-v3-{s}", .{ date, host_str, node_str, hex8 });
    }

    // FROZEN v2 path: 32-bit polynomial over the UTF-16 code units of the
    // insertion-order JSON (Math.imul / charCodeAt in ltx-sdk.js).
    const raw = try stringifyValue(alloc, plan);
    defer alloc.free(raw);
    const h = imul31Utf16(raw);
    return std.fmt.allocPrint(alloc, "LTX-{s}-{s}-{s}-v2-{x:0>8}", .{ date, host_str, node_str, h });
}

/// One-way delay in seconds between two nodes (LTX-SPECIFICATION.md §3.7).
/// The v3 pair matrix (plan.delays, key "A|B" with ids sorted) is
/// authoritative where present; otherwise the conservative fallback: HOST
/// pairs use the node's declared delay, non-HOST pairs the sum of both
/// HOST-relative delays.
pub fn pairDelayJson(alloc: Allocator, plan: std.json.Value, node_a: []const u8, node_b: []const u8) !i64 {
    if (std.mem.eql(u8, node_a, node_b)) return 0;
    if (objGet(plan, "delays")) |delays| {
        const lo = if (std.mem.lessThan(u8, node_a, node_b)) node_a else node_b;
        const hi = if (std.mem.lessThan(u8, node_a, node_b)) node_b else node_a;
        const key = try std.fmt.allocPrint(alloc, "{s}|{s}", .{ lo, hi });
        defer alloc.free(key);
        if (objInt(delays, key)) |d| return d;
    }
    const nodes = objArr(plan, "nodes") orelse return error.UnknownNode;
    var a: ?std.json.Value = null;
    var b: ?std.json.Value = null;
    for (nodes) |n| {
        const id = objStr(n, "id") orelse continue;
        if (std.mem.eql(u8, id, node_a)) a = n;
        if (std.mem.eql(u8, id, node_b)) b = n;
    }
    if (a == null or b == null) return error.UnknownNode;
    const host_id = objStr(nodes[0], "id") orelse "";
    if (std.mem.eql(u8, node_a, host_id)) return objInt(b.?, "delay") orelse 0;
    if (std.mem.eql(u8, node_b, host_id)) return objInt(a.?, "delay") orelse 0;
    return (objInt(a.?, "delay") orelse 0) + (objInt(b.?, "delay") orelse 0);
}

/// A computed segment from a specific viewer's perspective (§14.3).
/// String fields reference the parsed plan document.
pub const ViewerSegment = struct {
    seg_type: []const u8,
    q: i64,
    start_ms: i64,
    end_ms: i64,
    dur_min: i64,
    speaker: ?[]const u8,
    label: ?[]const u8,
    /// "transmit" (viewer presents), "receive", or "neutral".
    perspective: []const u8,
    /// Light-time shift applied to start/end, in seconds (0 unless receiving).
    arrival_offset_s: i64,
};

/// Compute the timed segment array from viewer V's perspective (§14.3):
/// a segment attributed to speaker S starts for V at
/// segStart + pairDelay(S, V). Unattributed segments keep their times.
/// Caller frees the returned slice.
pub fn computeSegmentsForJson(alloc: Allocator, plan: std.json.Value, viewer: []const u8) ![]ViewerSegment {
    const nodes = objArr(plan, "nodes") orelse return error.UnknownViewer;
    var known = false;
    for (nodes) |n| {
        if (std.mem.eql(u8, objStr(n, "id") orelse "", viewer)) known = true;
    }
    if (!known) return error.UnknownViewer;

    const quantum = objInt(plan, "quantum") orelse 5;
    const segments = objArr(plan, "segments") orelse &[_]std.json.Value{};
    var t: i64 = parseIsoMs(objStr(plan, "start") orelse "");
    var out = try alloc.alloc(ViewerSegment, segments.len);
    errdefer alloc.free(out);
    for (segments, 0..) |tpl, i| {
        const q = objInt(tpl, "q") orelse 2;
        const dur_ms = q * quantum * 60_000;
        const seg_type = objStr(tpl, "type") orelse "TX";
        var vs = ViewerSegment{
            .seg_type = seg_type,
            .q = q,
            .start_ms = t,
            .end_ms = t + dur_ms,
            .dur_min = q * quantum,
            .speaker = objStr(tpl, "speaker"),
            .label = objStr(tpl, "label"),
            .perspective = "neutral",
            .arrival_offset_s = 0,
        };
        if (vs.speaker) |speaker| {
            if (std.mem.eql(u8, seg_type, "TX") or std.mem.eql(u8, seg_type, "SPEAK")) {
                if (std.mem.eql(u8, speaker, viewer)) {
                    vs.perspective = "transmit";
                } else {
                    const shift_s = try pairDelayJson(alloc, plan, speaker, viewer);
                    vs.perspective = "receive";
                    vs.arrival_offset_s = shift_s;
                    vs.start_ms += shift_s * 1000;
                    vs.end_ms += shift_s * 1000;
                }
            }
        }
        out[i] = vs;
        t += dur_ms;
    }
    return out;
}

// ── Feature 2: session state machine (LTX-SPECIFICATION.md §5) ────────────

pub const SmState = enum {
    draft,
    locking,
    locked,
    active,
    degraded,
    emergency_hold,
    complete,
    aborted,

    pub fn asStr(self: SmState) []const u8 {
        return switch (self) {
            .draft => "DRAFT",
            .locking => "LOCKING",
            .locked => "LOCKED",
            .active => "ACTIVE",
            .degraded => "DEGRADED",
            .emergency_hold => "EMERGENCY_HOLD",
            .complete => "COMPLETE",
            .aborted => "ABORTED",
        };
    }
};

pub const SmLock = enum {
    none,
    full,
    quorum,

    pub fn asStr(self: SmLock) ?[]const u8 {
        return switch (self) {
            .none => null,
            .full => "FULL",
            .quorum => "QUORUM",
        };
    }
};

/// Quorum threshold option for quorum lock (§5.6).
pub const QuorumOpt = union(enum) { all, majority, count: usize };

pub const SmEvent = union(enum) {
    start_lock: struct { now_ms: i64 },
    plan_confirm: struct { now_ms: i64, node_id: []const u8, plan_id: []const u8 },
    tick: struct { now_ms: i64 },
    session_start: struct { now_ms: i64 },
    delay_measured: struct { now_ms: i64, node_id: []const u8, measured_delay_s: i64 },
    eok_override: struct { now_ms: i64, verified: bool },
    amendment_proposed: struct { now_ms: i64, plan_id: []const u8, plan_version: i64, affected_node_ids: []const []const u8 },
    amendment_confirmed: struct { now_ms: i64, node_id: []const u8, plan_id: []const u8 },
    host_decision: struct { now_ms: i64, decision: []const u8 },
    session_end: struct { now_ms: i64 },
};

const PendingAmendment = struct {
    plan_id: []u8,
    plan_version: i64,
    affected_node_ids: [][]u8,
    confirmed: std.ArrayList([]u8),
    proposed_at_ms: i64,
    timeout_ms: i64,
};

/// Session state machine context (§5). Pure with injected time: every event
/// carries now_ms; transition() never reads a clock.
pub const SessionCtx = struct {
    alloc: Allocator,
    state: SmState,
    plan: std.json.Value,
    plan_id: []u8,
    session_root_plan_id: []u8,
    plan_version: i64,
    lock: SmLock,
    lock_started_at_ms: ?i64,
    lock_timeout_ms: i64,
    /// node_id → confirmed plan_id (both duped, owned by the context).
    confirmations: std.StringHashMap([]u8),
    quorum_threshold: usize,
    /// Participating subset when quorum-locked (§5.3); null = all nodes.
    subset: ?[][]u8,
    resume_state: ?SmState,
    pending_amendment: ?PendingAmendment,

    pub fn deinit(self: *SessionCtx) void {
        self.alloc.free(self.plan_id);
        self.alloc.free(self.session_root_plan_id);
        var it = self.confirmations.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*);
        }
        self.confirmations.deinit();
        self.freeSubset();
        self.freePending();
    }

    fn freeSubset(self: *SessionCtx) void {
        if (self.subset) |subset| {
            for (subset) |s| self.alloc.free(s);
            self.alloc.free(subset);
            self.subset = null;
        }
    }

    fn freePending(self: *SessionCtx) void {
        if (self.pending_amendment) |*pa| {
            self.alloc.free(pa.plan_id);
            for (pa.affected_node_ids) |s| self.alloc.free(s);
            self.alloc.free(pa.affected_node_ids);
            for (pa.confirmed.items) |s| self.alloc.free(s);
            pa.confirmed.deinit(self.alloc);
            self.pending_amendment = null;
        }
    }

    fn setConfirmation(self: *SessionCtx, node_id: []const u8, plan_id: []const u8) !void {
        const gop = try self.confirmations.getOrPut(node_id);
        if (gop.found_existing) {
            self.alloc.free(gop.value_ptr.*);
        } else {
            gop.key_ptr.* = try self.alloc.dupe(u8, node_id);
        }
        gop.value_ptr.* = try self.alloc.dupe(u8, plan_id);
    }

    fn participantCount(self: *const SessionCtx) usize {
        const nodes = objArr(self.plan, "nodes") orelse return 0;
        var n: usize = 0;
        for (nodes) |node| {
            if (std.mem.eql(u8, objStr(node, "role") orelse "", "PARTICIPANT")) n += 1;
        }
        return n;
    }

    fn confirmedCount(self: *const SessionCtx) usize {
        const nodes = objArr(self.plan, "nodes") orelse return 0;
        var n: usize = 0;
        for (nodes) |node| {
            if (!std.mem.eql(u8, objStr(node, "role") orelse "", "PARTICIPANT")) continue;
            const id = objStr(node, "id") orelse continue;
            if (self.confirmations.get(id)) |confirmed| {
                if (std.mem.eql(u8, confirmed, self.plan_id)) n += 1;
            }
        }
        return n;
    }

    fn fullLockReached(self: *const SessionCtx) bool {
        return self.confirmedCount() == self.participantCount();
    }

    /// Ascending-delay ordering over confirmed participants (§5.3),
    /// HOST first. Caller-owned memory managed by the context.
    fn buildConfirmedSubset(self: *SessionCtx) ![][]u8 {
        const nodes = objArr(self.plan, "nodes") orelse return &[_][]u8{};
        const Item = struct { id: []const u8, delay: i64 };
        var items = std.ArrayList(Item){};
        defer items.deinit(self.alloc);
        for (nodes) |node| {
            if (!std.mem.eql(u8, objStr(node, "role") orelse "", "PARTICIPANT")) continue;
            const id = objStr(node, "id") orelse continue;
            const confirmed = self.confirmations.get(id) orelse continue;
            if (!std.mem.eql(u8, confirmed, self.plan_id)) continue;
            try items.append(self.alloc, .{ .id = id, .delay = objInt(node, "delay") orelse 0 });
        }
        std.sort.pdq(Item, items.items, {}, struct {
            pub fn lessThan(_: void, a: Item, b: Item) bool {
                return a.delay < b.delay;
            }
        }.lessThan);
        var out = try self.alloc.alloc([]u8, items.items.len + 1);
        const host_id = if (nodes.len > 0) objStr(nodes[0], "id") orelse "" else "";
        out[0] = try self.alloc.dupe(u8, host_id);
        for (items.items, 0..) |item, i| out[i + 1] = try self.alloc.dupe(u8, item.id);
        return out;
    }

    /// Declared one-way delay: v3 pair matrix HOST row, else node delay.
    fn declaredDelayS(self: *const SessionCtx, node_id: []const u8) ?i64 {
        const nodes = objArr(self.plan, "nodes") orelse return null;
        var node: ?std.json.Value = null;
        for (nodes) |n| {
            if (std.mem.eql(u8, objStr(n, "id") orelse "", node_id)) node = n;
        }
        if (node == null) return null;
        if (objGet(self.plan, "delays") != null) {
            const host_id = objStr(nodes[0], "id") orelse "";
            const d = pairDelayJson(self.alloc, self.plan, host_id, node_id) catch null;
            if (d) |dd| if (!std.mem.eql(u8, host_id, node_id)) return dd;
        }
        return objInt(node.?, "delay") orelse 0;
    }

    fn degrade(self: *SessionCtx) void {
        // Reasons are not tracked (effects simplified to state+lock outputs).
        self.state = .degraded;
    }

    /// Advance the state machine (LTX-SPECIFICATION.md §5). Deterministic:
    /// the same context and event sequence always yields the same states.
    pub fn transition(self: *SessionCtx, event: SmEvent) !void {
        switch (event) {
            .start_lock => |ev| {
                if (self.state != .draft) return;
                const nodes = objArr(self.plan, "nodes") orelse return;
                const host_id = if (nodes.len > 0) objStr(nodes[0], "id") orelse "" else "";
                self.lock_started_at_ms = ev.now_ms;
                try self.setConfirmation(host_id, self.plan_id);
                self.state = .locking;
            },
            .plan_confirm => |ev| {
                if (self.state != .locking and self.state != .degraded) return;
                try self.setConfirmation(ev.node_id, ev.plan_id);
                if (!std.mem.eql(u8, ev.plan_id, self.plan_id)) return; // §5.5 mismatch
                if (self.fullLockReached()) {
                    self.lock = .full;
                    self.freeSubset();
                    // Late full confirmation recovers a DEGRADED quorum lock (§5.2).
                    self.state = .locked;
                }
            },
            .tick => |ev| {
                if (self.state != .locking) return;
                const started = self.lock_started_at_ms orelse return;
                if (ev.now_ms - started < self.lock_timeout_ms) return;
                // Lock timeout expired (§5.1).
                if (self.confirmedCount() >= self.quorum_threshold) {
                    self.freeSubset();
                    self.subset = try self.buildConfirmedSubset();
                    self.lock = .quorum;
                }
                self.degrade();
            },
            .session_start => {
                if (self.state == .locked) self.state = .active;
                // DEGRADED: §5.2 escalation to HOST required (host_decision continue).
            },
            .delay_measured => |ev| {
                if (self.state != .active and self.state != .locked and self.state != .degraded) return;
                const declared = self.declaredDelayS(ev.node_id) orelse return;
                const diff = ev.measured_delay_s - declared;
                const deviation: i64 = if (diff < 0) -diff else diff;
                if (deviation > DELAY_VIOLATION_DEGRADED_S) self.degrade();
                // WARN band emits a notification only (no state change).
            },
            .eok_override => |ev| {
                if (self.state == .complete or self.state == .aborted) return;
                if (!ev.verified) return;
                if (self.state == .emergency_hold) return;
                self.resume_state = self.state;
                self.state = .emergency_hold;
            },
            .amendment_proposed => |ev| {
                if (self.state != .active and self.state != .locked and self.state != .degraded) return;
                if (ev.plan_version != self.plan_version + 1) return;
                // Delta re-lock (§6.4): timeout scoped to furthest affected node.
                var max_delay: i64 = 0;
                if (objArr(self.plan, "nodes")) |nodes| {
                    for (nodes) |node| {
                        const id = objStr(node, "id") orelse continue;
                        for (ev.affected_node_ids) |affected| {
                            if (std.mem.eql(u8, id, affected)) {
                                const d = objInt(node, "delay") orelse 0;
                                if (d > max_delay) max_delay = d;
                            }
                        }
                    }
                }
                self.freePending();
                var affected = try self.alloc.alloc([]u8, ev.affected_node_ids.len);
                for (ev.affected_node_ids, 0..) |id, i| affected[i] = try self.alloc.dupe(u8, id);
                self.pending_amendment = .{
                    .plan_id = try self.alloc.dupe(u8, ev.plan_id),
                    .plan_version = ev.plan_version,
                    .affected_node_ids = affected,
                    .confirmed = std.ArrayList([]u8){},
                    .proposed_at_ms = ev.now_ms,
                    .timeout_ms = LOCK_TIMEOUT_FACTOR * max_delay * 1000,
                };
            },
            .amendment_confirmed => |ev| {
                if (self.pending_amendment == null) return;
                const pa = &self.pending_amendment.?;
                if (!std.mem.eql(u8, ev.plan_id, pa.plan_id)) return;
                var affected = false;
                for (pa.affected_node_ids) |id| {
                    if (std.mem.eql(u8, id, ev.node_id)) affected = true;
                }
                if (!affected) return;
                for (pa.confirmed.items) |id| {
                    if (std.mem.eql(u8, id, ev.node_id)) return; // already confirmed
                }
                try pa.confirmed.append(self.alloc, try self.alloc.dupe(u8, ev.node_id));
                if (pa.confirmed.items.len < pa.affected_node_ids.len) return;
                // All affected nodes confirmed — the amendment applies.
                self.alloc.free(self.plan_id);
                self.plan_id = try self.alloc.dupe(u8, pa.plan_id);
                self.plan_version = pa.plan_version;
                self.freePending();
            },
            .host_decision => |ev| {
                if (std.mem.eql(u8, ev.decision, "abort")) {
                    if (self.state == .complete or self.state == .aborted) return;
                    self.state = .aborted;
                } else if (std.mem.eql(u8, ev.decision, "resume") and self.state == .emergency_hold) {
                    self.state = self.resume_state orelse .active;
                    self.resume_state = null;
                } else if (std.mem.eql(u8, ev.decision, "continue") and self.state == .degraded) {
                    // §5.2: HOST elects to continue with the confirmed subset.
                    self.state = .active;
                }
            },
            .session_end => {
                if (self.state == .active or self.state == .degraded) self.state = .complete;
            },
        }
    }
};

/// 2 × one-way delay to the furthest node, in ms (§5.1).
pub fn lockTimeoutMsJson(plan: std.json.Value) i64 {
    var max_delay: i64 = 0;
    if (objArr(plan, "nodes")) |nodes| {
        for (nodes) |node| {
            const d = objInt(node, "delay") orelse 0;
            if (d > max_delay) max_delay = d;
        }
    }
    return LOCK_TIMEOUT_FACTOR * max_delay * 1000;
}

/// Create a session context in DRAFT state. plan_id is supplied by the
/// caller (makePlanIdJson) so this module stays pure. The plan value must
/// outlive the context. Like ltx-sdk.js createSession, a plan that uses
/// reserved fields (§3.5, §7) is refused with error.ReservedStreams or
/// error.ReservedBranching.
pub fn createSession(alloc: Allocator, plan: std.json.Value, plan_id: []const u8, quorum: QuorumOpt) !SessionCtx {
    try assertNoReservedFields(plan);
    var ctx = SessionCtx{
        .alloc = alloc,
        .state = .draft,
        .plan = plan,
        .plan_id = try alloc.dupe(u8, plan_id),
        .session_root_plan_id = try alloc.dupe(u8, plan_id),
        .plan_version = objInt(plan, "planVersion") orelse 1,
        .lock = .none,
        .lock_started_at_ms = null,
        .lock_timeout_ms = lockTimeoutMsJson(plan),
        .confirmations = std.StringHashMap([]u8).init(alloc),
        .quorum_threshold = 0,
        .subset = null,
        .resume_state = null,
        .pending_amendment = null,
    };
    const total = ctx.participantCount();
    ctx.quorum_threshold = switch (quorum) {
        .all => total,
        .majority => total / 2 + 1,
        .count => |n| @min(@max(n, 1), total),
    };
    return ctx;
}

// ── Ed25519 verification against raw public keys ──────────────────────────

/// Key cache entry mapping a kid / nodeId to a raw Ed25519 public key.
pub const PubKeyEntry = struct {
    kid: []const u8,
    public_key: Ed25519.PublicKey,
};

pub const V11VerifyResult = struct {
    ok: bool,
    reason: []const u8,
};

fn findKey(cache: []const PubKeyEntry, kid: []const u8) ?Ed25519.PublicKey {
    for (cache) |entry| {
        if (std.mem.eql(u8, entry.kid, kid)) return entry.public_key;
    }
    // COSE kid may be a prefix of a longer nodeId.
    for (cache) |entry| {
        if (kid.len > 0 and std.mem.startsWith(u8, entry.kid, kid)) return entry.public_key;
    }
    return null;
}

fn verifyRawSig(msg: []const u8, sig_bytes: []const u8, public_key: Ed25519.PublicKey) bool {
    if (sig_bytes.len != 64) return false;
    var arr: [64]u8 = undefined;
    @memcpy(&arr, sig_bytes[0..64]);
    const sig = Ed25519.Signature.fromBytes(arr);
    sig.verify(msg, public_key) catch return false;
    return true;
}

// ── Feature 3: amendment chains (LTX-SECURITY.md §7.6) ────────────────────

/// SHA-256 hex of the RFC 8785 canonical JSON of a plan. Order-insensitive
/// and collision-resistant — never the legacy v2 polynomial planId hash.
/// Caller frees.
pub fn planHashJson(alloc: Allocator, plan: std.json.Value) ![]u8 {
    const canon = try canonicalJsonValue(alloc, plan);
    defer alloc.free(canon);
    const digest = sec.sha256(canon);
    return hexEncode(alloc, &digest);
}

/// Verify one TRANSITIONAL JSON COSE_Sign1 envelope (LTX-SECURITY.md §7.2):
/// link is a {plan, coseSign1:{protected,unprotected:{kid},payload,signature}}
/// wire object; signature is Ed25519 over the canonical JSON Sig_structure.
pub fn verifySignedPlanJson(alloc: Allocator, link: std.json.Value, cache: []const PubKeyEntry) !V11VerifyResult {
    const plan = objGet(link, "plan") orelse return .{ .ok = false, .reason = "missing_plan" };
    const cose = objGet(link, "coseSign1") orelse return .{ .ok = false, .reason = "missing_cose_sign1" };
    const protected = objStr(cose, "protected") orelse return .{ .ok = false, .reason = "missing_protected" };
    const payload = objStr(cose, "payload") orelse return .{ .ok = false, .reason = "missing_payload" };
    const signature = objStr(cose, "signature") orelse return .{ .ok = false, .reason = "missing_signature" };
    const unprotected = objGet(cose, "unprotected") orelse return .{ .ok = false, .reason = "missing_kid" };
    const kid = objStr(unprotected, "kid") orelse return .{ .ok = false, .reason = "missing_kid" };

    const public_key = findKey(cache, kid) orelse return .{ .ok = false, .reason = "key_not_in_cache" };

    // Payload must equal base64url(canonical JSON of the plan).
    const canon = try canonicalJsonValue(alloc, plan);
    defer alloc.free(canon);
    const expected_payload = try sec.b64uEnc(alloc, canon);
    defer alloc.free(expected_payload);
    if (!std.mem.eql(u8, payload, expected_payload)) {
        return .{ .ok = false, .reason = "payload_mismatch" };
    }

    // Sig_structure = canonical JSON of ["Signature1", protected, "", payload].
    const sig_struct = try std.fmt.allocPrint(alloc, "[\"Signature1\",\"{s}\",\"\",\"{s}\"]", .{ protected, payload });
    defer alloc.free(sig_struct);
    const sig_bytes = sec.b64uDec(alloc, signature) catch return .{ .ok = false, .reason = "signature_invalid" };
    defer alloc.free(sig_bytes);
    if (!verifyRawSig(sig_struct, sig_bytes, public_key)) {
        return .{ .ok = false, .reason = "signature_invalid" };
    }
    return .{ .ok = true, .reason = "ok" };
}

/// Verify an amendment chain: chain[0] is the root plan, each later element
/// a successive amendment. Checks, per link: HOST signature against cache,
/// planVersion increment of exactly 1, and prevPlanHash equality with the
/// recomputed predecessor hash (LTX-SECURITY.md §7.6).
pub fn verifyAmendmentChainJson(alloc: Allocator, chain: []const std.json.Value, cache: []const PubKeyEntry) !V11VerifyResult {
    if (chain.len == 0) return .{ .ok = false, .reason = "empty_chain" };
    for (chain) |link| {
        const res = try verifySignedPlanJson(alloc, link, cache);
        if (!res.ok) return res;
    }
    const root = objGet(chain[0], "plan").?;
    if (objGet(root, "prevPlanHash") != null) {
        return .{ .ok = false, .reason = "root_has_prev_hash" };
    }
    var prev_plan = root;
    var prev_version: i64 = objInt(root, "planVersion") orelse 1;
    for (chain[1..]) |link| {
        const p = objGet(link, "plan").?;
        if ((objInt(p, "v") orelse 0) != 3) return .{ .ok = false, .reason = "link_not_v3" };
        if ((objInt(p, "planVersion") orelse 0) != prev_version + 1) {
            return .{ .ok = false, .reason = "link_version_gap" };
        }
        const prev_hash = try planHashJson(alloc, prev_plan);
        defer alloc.free(prev_hash);
        const declared = objStr(p, "prevPlanHash") orelse "";
        if (!std.mem.eql(u8, declared, prev_hash)) {
            return .{ .ok = false, .reason = "link_prev_hash_mismatch" };
        }
        prev_plan = p;
        prev_version = objInt(p, "planVersion") orelse 0;
    }
    return .{ .ok = true, .reason = "ok" };
}

// ── Feature 4: register entries + reducers (§8–§10) ───────────────────────

/// Verify a register entry (wire-format JSON object) signature: Ed25519 over
/// the canonical JSON of the entry without "sig", against the entry's nodeId
/// in the cache (LTX-SECURITY.md §9.5).
pub fn verifyRegisterEntryJson(alloc: Allocator, entry: std.json.Value, cache: []const PubKeyEntry) !V11VerifyResult {
    const sig = objStr(entry, "sig") orelse return .{ .ok = false, .reason = "missing_sig" };
    const node_id = objStr(entry, "nodeId") orelse return .{ .ok = false, .reason = "missing_node_id" };
    const public_key = findKey(cache, node_id) orelse return .{ .ok = false, .reason = "key_not_in_cache" };
    const msg = try canonicalJsonValueSkip(alloc, entry, "sig");
    defer alloc.free(msg);
    const sig_bytes = sec.b64uDec(alloc, sig) catch return .{ .ok = false, .reason = "signature_invalid" };
    defer alloc.free(sig_bytes);
    if (!verifyRawSig(msg, sig_bytes, public_key)) {
        return .{ .ok = false, .reason = "signature_invalid" };
    }
    return .{ .ok = true, .reason = "ok" };
}

fn entryLessThan(_: void, a: std.json.Value, b: std.json.Value) bool {
    const ta = objStr(a, "timestamp") orelse "";
    const tb = objStr(b, "timestamp") orelse "";
    switch (std.mem.order(u8, ta, tb)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    const na = objStr(a, "nodeId") orelse "";
    const nb = objStr(b, "nodeId") orelse "";
    switch (std.mem.order(u8, na, nb)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return (objInt(a, "seq") orelse 0) < (objInt(b, "seq") orelse 0);
}

/// De-duplicate by (nodeId, seq) and sort into the §8.2 total order
/// (timestamp, nodeId, seq). Caller frees the returned slice.
pub fn orderEntriesJson(alloc: Allocator, entries: []const std.json.Value) ![]std.json.Value {
    var out = std.ArrayList(std.json.Value){};
    errdefer out.deinit(alloc);
    for (entries) |e| {
        const nid = objStr(e, "nodeId") orelse "";
        const seq = objInt(e, "seq") orelse 0;
        var dup = false;
        for (out.items) |seen| {
            if (std.mem.eql(u8, objStr(seen, "nodeId") orelse "", nid) and
                (objInt(seen, "seq") orelse 0) == seq) dup = true;
        }
        if (!dup) try out.append(alloc, e);
    }
    std.sort.pdq(std.json.Value, out.items, {}, entryLessThan);
    return out.toOwnedSlice(alloc);
}

/// Reduced state of one question (§9.4). Strings reference the entries.
pub const QuestionState = struct {
    qid: []const u8,
    text: []const u8,
    submitter: []const u8,
    urgency: ?[]const u8,
    intended_window: ?[]const u8,
    status: []const u8, // OPEN | ANSWERED | WITHDRAWN
    response: ?[]const u8,
    responder: ?[]const u8,
    version: i64,
};

pub const QuestionReduction = struct {
    by_id: std.StringArrayHashMap(QuestionState),
    /// entryIds of entries that lost a §8.2 conflict (flagged, never dropped).
    superseded: std.ArrayList([]const u8),
    alloc: Allocator,

    pub fn deinit(self: *QuestionReduction) void {
        self.by_id.deinit();
        self.superseded.deinit(self.alloc);
    }
};

const Versioned = struct { version: i64, editor: []const u8, entry_id: []const u8 };

/// §8.2 conflict rule: higher version wins; tie → lowest editor nodeId.
fn winsConflict(incoming: Versioned, current: Versioned) bool {
    if (incoming.version != current.version) return incoming.version > current.version;
    return std.mem.lessThan(u8, incoming.editor, current.editor);
}

/// Reduce question register state from log entries (§9.4). Pure: identical
/// entry sets in any input order produce identical state.
pub fn reduceQuestionsJson(alloc: Allocator, entries: []const std.json.Value) !QuestionReduction {
    var result = QuestionReduction{
        .by_id = std.StringArrayHashMap(QuestionState).init(alloc),
        .superseded = std.ArrayList([]const u8){},
        .alloc = alloc,
    };
    errdefer result.deinit();
    var winners = std.StringArrayHashMap(Versioned).init(alloc);
    defer winners.deinit();

    const ordered = try orderEntriesJson(alloc, entries);
    defer alloc.free(ordered);

    for (ordered) |e| {
        const entry_type = objStr(e, "type") orelse "";
        const entry_id = objStr(e, "entryId") orelse "";
        const node_id = objStr(e, "nodeId") orelse "";
        const content = objGet(e, "content") orelse continue;
        if (std.mem.eql(u8, entry_type, "question")) {
            if (result.by_id.get(entry_id) != null) {
                try result.superseded.append(alloc, entry_id);
                continue;
            }
            try winners.put(entry_id, .{ .version = 1, .editor = node_id, .entry_id = entry_id });
            try result.by_id.put(entry_id, .{
                .qid = entry_id,
                .text = objStr(content, "text") orelse "",
                .submitter = node_id,
                .urgency = objStr(content, "urgency"),
                .intended_window = objStr(content, "intendedWindow"),
                .status = "OPEN",
                .response = null,
                .responder = null,
                .version = 1,
            });
        } else if (std.mem.eql(u8, entry_type, "question_response")) {
            const qid = objStr(content, "qid") orelse "";
            const q = result.by_id.get(qid) orelse {
                try result.superseded.append(alloc, entry_id);
                continue;
            };
            const version = objInt(content, "version") orelse (q.version + 1);
            const incoming = Versioned{ .version = version, .editor = node_id, .entry_id = entry_id };
            if (winners.get(qid)) |current| {
                if (!winsConflict(incoming, current)) {
                    try result.superseded.append(alloc, entry_id);
                    continue;
                }
                if (!std.mem.eql(u8, current.entry_id, q.qid)) {
                    try result.superseded.append(alloc, current.entry_id);
                }
            }
            try winners.put(qid, incoming);
            var updated = q;
            const status = objStr(content, "status") orelse "";
            updated.status = if (std.mem.eql(u8, status, "WITHDRAWN")) "WITHDRAWN" else "ANSWERED";
            if (objStr(content, "response")) |r| updated.response = r;
            updated.responder = node_id;
            updated.version = version;
            try result.by_id.put(qid, updated);
        }
    }
    return result;
}

/// Reduced state of one action item (§10.2). Strings reference the entries.
pub const ActionState = struct {
    aid: []const u8,
    description: []const u8,
    owner: ?[]const u8,
    due_time_utc: ?[]const u8,
    origin_window: ?[]const u8,
    status: []const u8, // PROPOSED | ACCEPTED | REJECTED | DONE
    version: i64,
};

pub const ActionReduction = struct {
    by_id: std.StringArrayHashMap(ActionState),
    superseded: std.ArrayList([]const u8),
    alloc: Allocator,

    pub fn deinit(self: *ActionReduction) void {
        self.by_id.deinit();
        self.superseded.deinit(self.alloc);
    }
};

/// Reduce action register state from log entries (§10.2).
pub fn reduceActionsJson(alloc: Allocator, entries: []const std.json.Value) !ActionReduction {
    const statuses = [_][]const u8{ "PROPOSED", "ACCEPTED", "REJECTED", "DONE" };
    var result = ActionReduction{
        .by_id = std.StringArrayHashMap(ActionState).init(alloc),
        .superseded = std.ArrayList([]const u8){},
        .alloc = alloc,
    };
    errdefer result.deinit();
    var winners = std.StringArrayHashMap(Versioned).init(alloc);
    defer winners.deinit();

    const ordered = try orderEntriesJson(alloc, entries);
    defer alloc.free(ordered);

    for (ordered) |e| {
        const entry_type = objStr(e, "type") orelse "";
        const entry_id = objStr(e, "entryId") orelse "";
        const node_id = objStr(e, "nodeId") orelse "";
        const content = objGet(e, "content") orelse continue;
        if (std.mem.eql(u8, entry_type, "action")) {
            if (result.by_id.get(entry_id) != null) {
                try result.superseded.append(alloc, entry_id);
                continue;
            }
            try winners.put(entry_id, .{ .version = 1, .editor = node_id, .entry_id = entry_id });
            try result.by_id.put(entry_id, .{
                .aid = entry_id,
                .description = objStr(content, "description") orelse "",
                .owner = objStr(content, "owner"),
                .due_time_utc = objStr(content, "dueTimeUTC"),
                .origin_window = objStr(content, "originWindow"),
                .status = "PROPOSED",
                .version = 1,
            });
        } else if (std.mem.eql(u8, entry_type, "action_update")) {
            const aid = objStr(content, "aid") orelse "";
            const a = result.by_id.get(aid) orelse {
                try result.superseded.append(alloc, entry_id);
                continue;
            };
            const version = objInt(content, "version") orelse (a.version + 1);
            const incoming = Versioned{ .version = version, .editor = node_id, .entry_id = entry_id };
            if (winners.get(aid)) |current| {
                if (!winsConflict(incoming, current)) {
                    try result.superseded.append(alloc, entry_id);
                    continue;
                }
                if (!std.mem.eql(u8, current.entry_id, a.aid)) {
                    try result.superseded.append(alloc, current.entry_id);
                }
            }
            try winners.put(aid, incoming);
            var updated = a;
            if (objStr(content, "status")) |s| {
                for (statuses) |valid| {
                    if (std.mem.eql(u8, s, valid)) updated.status = s;
                }
            }
            if (objStr(content, "description")) |d| updated.description = d;
            if (objStr(content, "owner")) |o| updated.owner = o;
            if (objStr(content, "dueTimeUTC")) |d| updated.due_time_utc = d;
            updated.version = version;
            try result.by_id.put(aid, updated);
        }
    }
    return result;
}

// ── Merkle log root (RFC 9162-style, story 28.5 hash scheme) ──────────────

fn merkleLeafHash(alloc: Allocator, entry_bytes: []const u8) ![32]u8 {
    const buf = try alloc.alloc(u8, 1 + entry_bytes.len);
    defer alloc.free(buf);
    buf[0] = 0x00;
    @memcpy(buf[1..], entry_bytes);
    return sec.sha256(buf);
}

fn merkleNodeHash(left: [32]u8, right: [32]u8) [32]u8 {
    var buf: [65]u8 = undefined;
    buf[0] = 0x01;
    @memcpy(buf[1..33], &left);
    @memcpy(buf[33..65], &right);
    return sec.sha256(&buf);
}

fn merkleRootOf(leaves: []const [32]u8) [32]u8 {
    if (leaves.len == 0) return [_]u8{0} ** 32;
    if (leaves.len == 1) return leaves[0];
    // Largest power of two strictly less than n (RFC 9162 §2.1).
    var mid: usize = 1;
    while (mid * 2 < leaves.len) mid *= 2;
    return merkleNodeHash(merkleRootOf(leaves[0..mid]), merkleRootOf(leaves[mid..]));
}

/// Merkle audit-log root (hex) over the §8.2-ordered entries:
/// leaf = SHA-256(0x00 || canonicalJSON(entry)),
/// node = SHA-256(0x01 || left || right); empty log root is 64 hex zeros.
/// Caller frees.
pub fn entriesRootJson(alloc: Allocator, entries: []const std.json.Value) ![]u8 {
    const ordered = try orderEntriesJson(alloc, entries);
    defer alloc.free(ordered);
    const leaves = try alloc.alloc([32]u8, ordered.len);
    defer alloc.free(leaves);
    for (ordered, 0..) |e, i| {
        const canon = try canonicalJsonValue(alloc, e);
        defer alloc.free(canon);
        leaves[i] = try merkleLeafHash(alloc, canon);
    }
    const root = merkleRootOf(leaves);
    return hexEncode(alloc, &root);
}

// ── Feature 5: CBOR (RFC 8949 deterministic subset) + COSE_Sign1 ──────────

pub const COSE_SIGN1_TAG: u64 = 18;
pub const COSE_ALG_ED25519: i64 = -19;

pub const CborPair = struct { key: CborVal, val: CborVal };

/// Minimal CBOR value (RFC 8949 deterministic subset — no floats).
/// bytes / text slices reference the decoded input buffer.
pub const CborVal = union(enum) {
    null_v,
    bool_v: bool,
    int: i64,
    bytes: []const u8,
    text: []const u8,
    array: []CborVal,
    map: []CborPair,
    tag: struct { tag: u64, value: *CborVal },

    /// Free nested allocations made by decodeCbor.
    pub fn deinit(self: CborVal, alloc: Allocator) void {
        switch (self) {
            .array => |arr| {
                for (arr) |item| item.deinit(alloc);
                alloc.free(arr);
            },
            .map => |m| {
                for (m) |pair| {
                    pair.key.deinit(alloc);
                    pair.val.deinit(alloc);
                }
                alloc.free(m);
            },
            .tag => |t| {
                t.value.deinit(alloc);
                alloc.destroy(t.value);
            },
            else => {},
        }
    }
};

fn cborEncodeHead(alloc: Allocator, buf: *std.ArrayList(u8), major: u8, arg: u64) !void {
    if (arg < 24) {
        try buf.append(alloc, (major << 5) | @as(u8, @intCast(arg)));
    } else if (arg < 0x100) {
        try buf.append(alloc, (major << 5) | 24);
        try buf.append(alloc, @intCast(arg));
    } else if (arg < 0x10000) {
        try buf.append(alloc, (major << 5) | 25);
        try buf.append(alloc, @intCast(arg >> 8));
        try buf.append(alloc, @intCast(arg & 0xff));
    } else if (arg < 0x1_0000_0000) {
        try buf.append(alloc, (major << 5) | 26);
        var shift: u6 = 24;
        while (true) {
            try buf.append(alloc, @intCast((arg >> shift) & 0xff));
            if (shift == 0) break;
            shift -= 8;
        }
    } else {
        try buf.append(alloc, (major << 5) | 27);
        var shift: u6 = 56;
        while (true) {
            try buf.append(alloc, @intCast((arg >> shift) & 0xff));
            if (shift == 0) break;
            shift -= 8;
        }
    }
}

fn encodeCborInto(alloc: Allocator, buf: *std.ArrayList(u8), v: CborVal) Allocator.Error!void {
    switch (v) {
        .null_v => try buf.append(alloc, 0xf6),
        .bool_v => |b| try buf.append(alloc, if (b) @as(u8, 0xf5) else 0xf4),
        .int => |n| {
            if (n >= 0) {
                try cborEncodeHead(alloc, buf, 0, @intCast(n));
            } else {
                try cborEncodeHead(alloc, buf, 1, @intCast(-(n + 1)));
            }
        },
        .bytes => |b| {
            try cborEncodeHead(alloc, buf, 2, b.len);
            try buf.appendSlice(alloc, b);
        },
        .text => |s| {
            try cborEncodeHead(alloc, buf, 3, s.len);
            try buf.appendSlice(alloc, s);
        },
        .array => |arr| {
            try cborEncodeHead(alloc, buf, 4, arr.len);
            for (arr) |item| try encodeCborInto(alloc, buf, item);
        },
        .map => |m| {
            // Deterministic: sort by encoded key bytes (RFC 8949 §4.2.1).
            const Enc = struct { k: []u8, v: []u8 };
            var pairs = std.ArrayList(Enc){};
            defer {
                for (pairs.items) |p| {
                    alloc.free(p.k);
                    alloc.free(p.v);
                }
                pairs.deinit(alloc);
            }
            for (m) |pair| {
                try pairs.append(alloc, .{
                    .k = try encodeCbor(alloc, pair.key),
                    .v = try encodeCbor(alloc, pair.val),
                });
            }
            std.sort.pdq(Enc, pairs.items, {}, struct {
                pub fn lessThan(_: void, a: Enc, b: Enc) bool {
                    return std.mem.lessThan(u8, a.k, b.k);
                }
            }.lessThan);
            try cborEncodeHead(alloc, buf, 5, pairs.items.len);
            for (pairs.items) |p| {
                try buf.appendSlice(alloc, p.k);
                try buf.appendSlice(alloc, p.v);
            }
        },
        .tag => |t| {
            try cborEncodeHead(alloc, buf, 6, t.tag);
            try encodeCborInto(alloc, buf, t.value.*);
        },
    }
}

/// Encode a value to deterministic CBOR bytes (RFC 8949 §4.2.1: definite
/// lengths, shortest-form heads, map keys sorted bytewise by encoded form).
/// Caller frees.
pub fn encodeCbor(alloc: Allocator, v: CborVal) Allocator.Error![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(alloc);
    try encodeCborInto(alloc, &buf, v);
    return buf.toOwnedSlice(alloc);
}

const CborDecoder = struct {
    buf: []const u8,
    pos: usize,

    fn readHead(self: *CborDecoder) !struct { major: u8, arg: u64 } {
        if (self.pos >= self.buf.len) return error.CborTruncated;
        const initial = self.buf[self.pos];
        self.pos += 1;
        const major = initial >> 5;
        const info = initial & 0x1f;
        var arg: u64 = 0;
        switch (info) {
            0...23 => arg = info,
            24 => {
                if (self.pos + 1 > self.buf.len) return error.CborTruncated;
                arg = self.buf[self.pos];
                self.pos += 1;
            },
            25 => {
                if (self.pos + 2 > self.buf.len) return error.CborTruncated;
                arg = std.mem.readInt(u16, self.buf[self.pos..][0..2], .big);
                self.pos += 2;
            },
            26 => {
                if (self.pos + 4 > self.buf.len) return error.CborTruncated;
                arg = std.mem.readInt(u32, self.buf[self.pos..][0..4], .big);
                self.pos += 4;
            },
            27 => {
                if (self.pos + 8 > self.buf.len) return error.CborTruncated;
                arg = std.mem.readInt(u64, self.buf[self.pos..][0..8], .big);
                self.pos += 8;
            },
            else => return error.CborIndefiniteUnsupported,
        }
        return .{ .major = major, .arg = arg };
    }

    fn decodeItem(self: *CborDecoder, alloc: Allocator, depth: u32) anyerror!CborVal {
        if (depth > 64) return error.CborNestingTooDeep;
        if (self.pos >= self.buf.len) return error.CborTruncated;
        switch (self.buf[self.pos]) {
            0xf6 => {
                self.pos += 1;
                return .null_v;
            },
            0xf5 => {
                self.pos += 1;
                return .{ .bool_v = true };
            },
            0xf4 => {
                self.pos += 1;
                return .{ .bool_v = false };
            },
            else => {},
        }
        const head = try self.readHead();
        switch (head.major) {
            0 => {
                if (head.arg > std.math.maxInt(i64)) return error.CborIntTooLarge;
                return .{ .int = @intCast(head.arg) };
            },
            1 => {
                if (head.arg >= std.math.maxInt(i64)) return error.CborIntTooLarge;
                return .{ .int = -@as(i64, @intCast(head.arg)) - 1 };
            },
            2, 3 => {
                const len: usize = @intCast(head.arg);
                if (self.pos + len > self.buf.len) return error.CborTruncated;
                const slice = self.buf[self.pos .. self.pos + len];
                self.pos += len;
                if (head.major == 2) return .{ .bytes = slice };
                if (!std.unicode.utf8ValidateSlice(slice)) return error.CborInvalidUtf8;
                return .{ .text = slice };
            },
            4 => {
                var arr = std.ArrayList(CborVal){};
                errdefer {
                    for (arr.items) |item| item.deinit(alloc);
                    arr.deinit(alloc);
                }
                var i: u64 = 0;
                while (i < head.arg) : (i += 1) {
                    try arr.append(alloc, try self.decodeItem(alloc, depth + 1));
                }
                return .{ .array = try arr.toOwnedSlice(alloc) };
            },
            5 => {
                var m = std.ArrayList(CborPair){};
                errdefer {
                    for (m.items) |pair| {
                        pair.key.deinit(alloc);
                        pair.val.deinit(alloc);
                    }
                    m.deinit(alloc);
                }
                var i: u64 = 0;
                while (i < head.arg) : (i += 1) {
                    const k = try self.decodeItem(alloc, depth + 1);
                    errdefer k.deinit(alloc);
                    const v = try self.decodeItem(alloc, depth + 1);
                    try m.append(alloc, .{ .key = k, .val = v });
                }
                return .{ .map = try m.toOwnedSlice(alloc) };
            },
            6 => {
                const inner = try alloc.create(CborVal);
                errdefer alloc.destroy(inner);
                inner.* = try self.decodeItem(alloc, depth + 1);
                return .{ .tag = .{ .tag = head.arg, .value = inner } };
            },
            else => return error.CborUnsupportedType, // major 7: floats / simple
        }
    }
};

/// Decode deterministic CBOR bytes to a value. Floats, indefinite lengths
/// and trailing bytes are rejected. Free with value.deinit(alloc).
pub fn decodeCbor(alloc: Allocator, data: []const u8) !CborVal {
    var d = CborDecoder{ .buf = data, .pos = 0 };
    const v = try d.decodeItem(alloc, 0);
    errdefer v.deinit(alloc);
    if (d.pos != data.len) return error.CborTrailingBytes;
    return v;
}

fn cborMapGetInt(m: []const CborPair, key: i64) ?CborVal {
    for (m) |pair| {
        switch (pair.key) {
            .int => |n| if (n == key) return pair.val,
            else => {},
        }
    }
    return null;
}

/// Verify a CBOR COSE_Sign1 plan envelope (RFC 9052, tag 18) against the key
/// cache. Rejects non-Ed25519 algorithms (protected header {1: -19} required;
/// the deprecated -8 is rejected) and payloads that do not match the plan.
/// Pass plan = null to skip the payload/plan equality check.
pub fn verifyPlanCoseJson(
    alloc: Allocator,
    plan: ?std.json.Value,
    cose_sign1_bytes: []const u8,
    cache: []const PubKeyEntry,
) !V11VerifyResult {
    const decoded = decodeCbor(alloc, cose_sign1_bytes) catch {
        return .{ .ok = false, .reason = "cbor_decode_failed" };
    };
    defer decoded.deinit(alloc);

    const arr = switch (decoded) {
        .tag => |t| blk: {
            if (t.tag != COSE_SIGN1_TAG) return .{ .ok = false, .reason = "not_cose_sign1" };
            switch (t.value.*) {
                .array => |a| break :blk a,
                else => return .{ .ok = false, .reason = "malformed_cose_sign1" },
            }
        },
        else => return .{ .ok = false, .reason = "not_cose_sign1" },
    };
    if (arr.len != 4) return .{ .ok = false, .reason = "malformed_cose_sign1" };
    const protected = switch (arr[0]) {
        .bytes => |b| b,
        else => return .{ .ok = false, .reason = "malformed_cose_sign1" },
    };
    const unprotected = switch (arr[1]) {
        .map => |m| m,
        else => return .{ .ok = false, .reason = "malformed_cose_sign1" },
    };
    const payload = switch (arr[2]) {
        .bytes => |b| b,
        else => return .{ .ok = false, .reason = "malformed_cose_sign1" },
    };
    const signature = switch (arr[3]) {
        .bytes => |b| b,
        else => return .{ .ok = false, .reason = "malformed_cose_sign1" },
    };

    const protected_decoded = decodeCbor(alloc, protected) catch {
        return .{ .ok = false, .reason = "protected_decode_failed" };
    };
    defer protected_decoded.deinit(alloc);
    const protected_map = switch (protected_decoded) {
        .map => |m| m,
        else => return .{ .ok = false, .reason = "protected_decode_failed" },
    };
    const alg = cborMapGetInt(protected_map, 1) orelse return .{ .ok = false, .reason = "unsupported_alg" };
    switch (alg) {
        .int => |n| if (n != COSE_ALG_ED25519) return .{ .ok = false, .reason = "unsupported_alg" },
        else => return .{ .ok = false, .reason = "unsupported_alg" },
    }

    const kid_val = cborMapGetInt(unprotected, 4) orelse return .{ .ok = false, .reason = "missing_kid" };
    const kid: []u8 = switch (kid_val) {
        .bytes => |b| try sec.b64uEnc(alloc, b),
        .text => |s| try alloc.dupe(u8, s),
        else => return .{ .ok = false, .reason = "missing_kid" },
    };
    defer alloc.free(kid);
    if (kid.len == 0) return .{ .ok = false, .reason = "missing_kid" };

    const public_key = findKey(cache, kid) orelse return .{ .ok = false, .reason = "key_not_in_cache" };

    // Sig_structure = CBOR ["Signature1", protected, h'', payload].
    var sig_items = [_]CborVal{
        .{ .text = "Signature1" },
        .{ .bytes = protected },
        .{ .bytes = &[_]u8{} },
        .{ .bytes = payload },
    };
    const sig_struct = try encodeCbor(alloc, .{ .array = sig_items[0..] });
    defer alloc.free(sig_struct);
    if (!verifyRawSig(sig_struct, signature, public_key)) {
        return .{ .ok = false, .reason = "signature_invalid" };
    }

    if (plan) |p| {
        const canon = try canonicalJsonValue(alloc, p);
        defer alloc.free(canon);
        if (!std.mem.eql(u8, payload, canon)) {
            return .{ .ok = false, .reason = "payload_mismatch" };
        }
    }
    return .{ .ok = true, .reason = "ok" };
}

// ════════════════════════════════════════════════════════════════════════
// Parity with ltx-sdk.js (issue #27): validatePlan + reserved fields,
// buildDelayMatrix via pairDelay, decision register, merge snapshot.
// ════════════════════════════════════════════════════════════════════════

// ── validatePlan (LTX-SPECIFICATION.md §3.5, §4, §7) ──────────────────────

/// One validatePlan finding. code is static; path and message are owned.
pub const PlanError = struct {
    code: []const u8,
    path: []u8,
    message: []u8,
};

/// validatePlan result. Call deinit.
pub const PlanValidation = struct {
    errors: std.ArrayList(PlanError),
    alloc: Allocator,

    pub fn valid(self: PlanValidation) bool {
        return self.errors.items.len == 0;
    }

    pub fn hasCode(self: PlanValidation, code: []const u8) bool {
        for (self.errors.items) |e| {
            if (std.mem.eql(u8, e.code, code)) return true;
        }
        return false;
    }

    pub fn deinit(self: *PlanValidation) void {
        for (self.errors.items) |e| {
            self.alloc.free(e.path);
            self.alloc.free(e.message);
        }
        self.errors.deinit(self.alloc);
    }

    fn add(self: *PlanValidation, code: []const u8, comptime path_fmt: []const u8, path_args: anytype, comptime msg_fmt: []const u8, msg_args: anytype) !void {
        const path = try std.fmt.allocPrint(self.alloc, path_fmt, path_args);
        errdefer self.alloc.free(path);
        const message = try std.fmt.allocPrint(self.alloc, msg_fmt, msg_args);
        try self.errors.append(self.alloc, .{ .code = code, .path = path, .message = message });
    }
};

const PLAN_SEGMENT_TYPES = [_][]const u8{ "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE", "SPEAK", "REST", "PAD", "OPEN", "RELAY" };
const PLAN_MODES = [_][]const u8{ "LTX", "LTX-LIVE", "LTX-RELAY", "LTX-ASYNC" };
const V3_ONLY_FIELDS = [_][]const u8{ "delays", "planVersion", "prevPlanHash", "questions", "actions", "streams" };
const NODE_ROLES = [_][]const u8{ "HOST", "PARTICIPANT", "OBSERVER" };

fn inList(list: []const []const u8, v: ?std.json.Value) bool {
    const val = v orelse return false;
    const str = switch (val) {
        .string => |x| x,
        else => return false,
    };
    for (list) |item| {
        if (std.mem.eql(u8, item, str)) return true;
    }
    return false;
}

/// typeof v === 'number' → its value.
fn jsNumberOf(v: ?std.json.Value) ?f64 {
    const val = v orelse return null;
    return switch (val) {
        .integer => |n| @floatFromInt(n),
        .float => |f| f,
        .number_string => |ns| std.fmt.parseFloat(f64, ns) catch null,
        else => null,
    };
}

/// Number.isInteger(v) → its value.
fn jsIntegerOf(v: ?std.json.Value) ?f64 {
    const f = jsNumberOf(v) orelse return null;
    if (!std.math.isFinite(f) or @floor(f) != f) return null;
    return f;
}

fn isJsObject(v: std.json.Value) bool {
    return switch (v) {
        .object, .array => true,
        else => false,
    };
}

fn has(v: std.json.Value, key: []const u8) bool {
    return objGet(v, key) != null;
}

/// First reserved-field violation code ("reserved_streams" or
/// "reserved_branching"), in the order validatePlan reports them; null if none.
pub fn reservedFieldCode(plan: std.json.Value) ?[]const u8 {
    if (plan != .object) return null;
    if (objGet(plan, "streams")) |st| {
        const ok = switch (st) {
            .array => |a| a.items.len == 0,
            else => false,
        };
        if (!ok) return "reserved_streams";
    }
    if (has(plan, "branches") or has(plan, "branching")) return "reserved_branching";
    if (objArr(plan, "segments")) |segs| {
        for (segs) |sg| {
            if (sg != .object) continue;
            if (has(sg, "stream")) return "reserved_streams";
            if (has(sg, "branch")) return "reserved_branching";
        }
    }
    return null;
}

/// error.ReservedStreams / error.ReservedBranching when plan uses reserved
/// stream or branching fields (§3.5, §7).
pub fn assertNoReservedFields(plan: std.json.Value) error{ ReservedStreams, ReservedBranching }!void {
    const code = reservedFieldCode(plan) orelse return;
    if (std.mem.eql(u8, code, "reserved_streams")) return error.ReservedStreams;
    return error.ReservedBranching;
}

fn addReservedErrors(r: *PlanValidation, plan: std.json.Value) !void {
    if (plan != .object) return;
    if (objGet(plan, "streams")) |st| {
        const ok = switch (st) {
            .array => |a| a.items.len == 0,
            else => false,
        };
        if (!ok) try r.add("reserved_streams", "streams", .{}, "streams[] is reserved (§3.5) and MUST be absent or empty", .{});
    }
    for ([_][]const u8{ "branches", "branching" }) |f| {
        if (has(plan, f)) try r.add("reserved_branching", "{s}", .{f}, "{s} is reserved for branching (§7, not yet implemented) and MUST be absent", .{f});
    }
    if (objArr(plan, "segments")) |segs| {
        for (segs, 0..) |sg, i| {
            if (sg != .object) continue;
            if (has(sg, "stream")) try r.add("reserved_streams", "segments[{d}].stream", .{i}, "segment stream is reserved (§3.5) and MUST be absent", .{});
            if (has(sg, "branch")) try r.add("reserved_branching", "segments[{d}].branch", .{i}, "segment branch is reserved for branching (§7) and MUST be absent", .{});
        }
    }
}

fn containsStr(list: []const []const u8, s: []const u8) bool {
    for (list) |x| {
        if (std.mem.eql(u8, x, s)) return true;
    }
    return false;
}

/// Validate a v2 or v3 wire plan against spec/ltx-schema.json (§4) and the
/// reserved-field rules (§3.5 streams, §7 branching), mirroring ltx-sdk.js
/// validatePlan. Error codes: not_an_object, invalid_version, missing_field,
/// invalid_field, invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
/// duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
/// invalid_delays, reserved_streams, reserved_branching. Caller deinits.
pub fn validatePlanJson(alloc: Allocator, plan: std.json.Value) !PlanValidation {
    var r = PlanValidation{ .errors = std.ArrayList(PlanError){}, .alloc = alloc };
    errdefer r.deinit();
    if (plan != .object) {
        try r.add("not_an_object", "", .{}, "plan must be an object", .{});
        return r;
    }
    const v = jsNumberOf(objGet(plan, "v"));
    const is_v2 = v != null and v.? == 2;
    const is_v3 = v != null and v.? == 3;
    if (!is_v2 and !is_v3) try r.add("invalid_version", "v", .{}, "v must be 2 or 3", .{});
    for ([_][]const u8{ "title", "start", "quantum", "mode", "nodes", "segments" }) |f| {
        if (!has(plan, f)) try r.add("missing_field", "{s}", .{f}, "{s} is required", .{f});
    }
    if (objGet(plan, "title")) |t| {
        if (t != .string) try r.add("invalid_field", "title", .{}, "title must be a string", .{});
    }
    if (objGet(plan, "start")) |st| {
        const ok = switch (st) {
            .string => |x| isIsoTimestamp(x),
            else => false,
        };
        if (!ok) try r.add("invalid_field", "start", .{}, "start must be an ISO 8601 UTC timestamp", .{});
    }
    if (has(plan, "quantum")) {
        const q = jsIntegerOf(objGet(plan, "quantum"));
        if (q == null or q.? < 1 or q.? > 60) try r.add("invalid_quantum", "quantum", .{}, "quantum must be an integer 1..60 minutes (§3.2)", .{});
    }
    if (objGet(plan, "mode")) |m| {
        if (!inList(&PLAN_MODES, m)) try r.add("invalid_mode", "mode", .{}, "mode must be one of LTX, LTX-LIVE, LTX-RELAY, LTX-ASYNC", .{});
    }

    var ids = std.ArrayList([]const u8){};
    defer ids.deinit(alloc);
    if (objGet(plan, "nodes")) |nv| {
        const nodes: []std.json.Value = switch (nv) {
            .array => |a| a.items,
            else => &[_]std.json.Value{},
        };
        if (nodes.len == 0) {
            try r.add("invalid_nodes", "nodes", .{}, "nodes must be a non-empty array", .{});
        } else {
            var hosts: usize = 0;
            for (nodes, 0..) |n, i| {
                const id = objStr(n, "id");
                const delay = jsNumberOf(objGet(n, "delay"));
                const ok = n == .object and id != null and id.?.len > 0 and
                    std.mem.indexOfScalar(u8, id.?, '|') == null and objStr(n, "name") != null and
                    inList(&NODE_ROLES, objGet(n, "role")) and delay != null and delay.? >= 0;
                if (!ok) {
                    try r.add("invalid_nodes", "nodes[{d}]", .{i}, "node needs id (no \"|\"), name, role HOST|PARTICIPANT|OBSERVER, delay >= 0", .{});
                    continue;
                }
                if (containsStr(ids.items, id.?)) try r.add("duplicate_node_id", "nodes[{d}].id", .{i}, "duplicate node id {s}", .{id.?});
                try ids.append(alloc, id.?);
                if (std.mem.eql(u8, objStr(n, "role").?, "HOST")) hosts += 1;
            }
            const h = nodes[0];
            const h_delay = jsNumberOf(objGet(h, "delay"));
            const h_ok = h == .object and std.mem.eql(u8, objStr(h, "role") orelse "", "HOST") and h_delay != null and h_delay.? == 0;
            if (hosts != 1 or !h_ok) try r.add("invalid_host", "nodes[0]", .{}, "exactly one HOST, first in nodes[], with delay 0 (§3.1)", .{});
        }
    }

    if (objGet(plan, "segments")) |sv| {
        switch (sv) {
            .array => |a| for (a.items, 0..) |sg, i| {
                const q = jsIntegerOf(objGet(sg, "q"));
                if (!isJsObject(sg) or !inList(&PLAN_SEGMENT_TYPES, objGet(sg, "type")) or q == null or q.? < 1) {
                    try r.add("invalid_segment", "segments[{d}]", .{i}, "segment needs a known type and integer q >= 1", .{});
                    continue;
                }
                if (objGet(sg, "speaker")) |sp| {
                    const known = switch (sp) {
                        .string => |x| containsStr(ids.items, x),
                        else => false,
                    };
                    if (!known) {
                        const shown = switch (sp) {
                            .string => |x| try alloc.dupe(u8, x),
                            else => try stringifyValue(alloc, sp),
                        };
                        defer alloc.free(shown);
                        try r.add("unknown_speaker", "segments[{d}].speaker", .{i}, "speaker {s} is not a node id", .{shown});
                    }
                }
            },
            else => try r.add("invalid_segment", "segments", .{}, "segments must be an array", .{}),
        }
    }

    if (is_v2) {
        for (V3_ONLY_FIELDS) |f| {
            if (has(plan, f)) try r.add("v3_field_in_v2", "{s}", .{f}, "{s} is a v3 field and MUST NOT appear in a v2 plan (§4.3)", .{f});
        }
    } else if (is_v3) {
        if (objGet(plan, "delays")) |d| {
            switch (d) {
                .object => |obj| for (obj.keys(), obj.values()) |k, val| {
                    var ok = false;
                    if (std.mem.indexOfScalar(u8, k, '|')) |bar| {
                        const a = k[0..bar];
                        const b = k[bar + 1 ..];
                        const dv = jsNumberOf(val);
                        ok = std.mem.indexOfScalar(u8, b, '|') == null and utf16Less(a, b) and
                            (ids.items.len == 0 or (containsStr(ids.items, a) and containsStr(ids.items, b))) and
                            dv != null and dv.? >= 0;
                    }
                    if (!ok) try r.add("invalid_delays", "delays.{s}", .{k}, "key must be two known node ids joined by \"|\" in sorted order; value >= 0 (§3.7.2)", .{});
                },
                else => try r.add("invalid_delays", "delays", .{}, "delays must be an object", .{}),
            }
        }
        if (has(plan, "planVersion")) {
            const pv = jsIntegerOf(objGet(plan, "planVersion"));
            if (pv == null or pv.? < 1) try r.add("invalid_field", "planVersion", .{}, "planVersion must be an integer >= 1", .{});
        }
        if (objGet(plan, "prevPlanHash")) |ph| {
            var ok = false;
            if (ph == .string and ph.string.len == 64) {
                ok = true;
                for (ph.string) |c| {
                    if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'))) ok = false;
                }
            }
            if (!ok) try r.add("invalid_field", "prevPlanHash", .{}, "prevPlanHash must be 64 lowercase hex characters", .{});
        }
        for ([_][]const u8{ "questions", "actions" }) |f| {
            if (objGet(plan, f)) |x| {
                if (x != .array) try r.add("invalid_field", "{s}", .{f}, "{s} must be an array", .{f});
            }
        }
    }

    try addReservedErrors(&r, plan);
    return r;
}

/// ISO 8601 forms Date.parse accepts for a plan start: YYYY-MM-DD, or
/// YYYY-MM-DDTHH:MM[:SS[.sss]] followed by Z or ±HH:MM.
fn isIsoTimestamp(s: []const u8) bool {
    const digitsAt = struct {
        fn f(x: []const u8, a: usize, n: usize) bool {
            if (x.len < a + n) return false;
            for (x[a .. a + n]) |c| {
                if (c < '0' or c > '9') return false;
            }
            return true;
        }
    }.f;
    if (!digitsAt(s, 0, 4) or s.len < 10 or s[4] != '-' or !digitsAt(s, 5, 2) or s[7] != '-' or !digitsAt(s, 8, 2)) return false;
    const mo = parseDigitsI64(s[5..7]);
    const d = parseDigitsI64(s[8..10]);
    if (mo < 1 or mo > 12 or d < 1 or d > 31) return false;
    if (s.len == 10) return true;
    if (s[10] != 'T' or !digitsAt(s, 11, 2) or s.len < 16 or s[13] != ':' or !digitsAt(s, 14, 2)) return false;
    if (parseDigitsI64(s[11..13]) > 24 or parseDigitsI64(s[14..16]) > 59) return false;
    var pos: usize = 16;
    if (pos < s.len and s[pos] == ':') {
        if (!digitsAt(s, pos + 1, 2) or parseDigitsI64(s[pos + 1 .. pos + 3]) > 59) return false;
        pos += 3;
        if (pos < s.len and s[pos] == '.') {
            pos += 1;
            const start = pos;
            while (pos < s.len and s[pos] >= '0' and s[pos] <= '9') pos += 1;
            if (pos == start) return false;
        }
    }
    if (pos + 1 == s.len and s[pos] == 'Z') return true;
    if (pos + 6 == s.len and (s[pos] == '+' or s[pos] == '-') and s[pos + 3] == ':' and digitsAt(s, pos + 1, 2) and digitsAt(s, pos + 4, 2)) return true;
    return false;
}

// ── buildDelayMatrix via pairDelay (LTX-SPECIFICATION.md §3.7.3) ──────────

/// One ordered node pair of a delay matrix. Strings reference the plan.
pub const DelayPair = struct {
    from_id: []const u8,
    from_name: []const u8,
    to_id: []const u8,
    to_name: []const u8,
    delay_seconds: i64,
};

/// Delay matrix over all ordered node pairs of a wire plan, mirroring
/// ltx-sdk.js buildDelayMatrix: every entry is pairDelayJson(plan, from, to),
/// so a v3 plan.delays entry is authoritative, HOST pairs use the node's
/// declared delay, and non-HOST pairs the SUM of both HOST-relative delays
/// (the conservative bound via the HOST vertex, never the max). The matrix is
/// symmetric. Caller frees the returned slice.
pub fn buildDelayMatrixJson(alloc: Allocator, plan: std.json.Value) ![]DelayPair {
    const nodes = objArr(plan, "nodes") orelse &[_]std.json.Value{};
    var out = std.ArrayList(DelayPair){};
    errdefer out.deinit(alloc);
    for (nodes, 0..) |from, i| {
        for (nodes, 0..) |to, j| {
            if (i == j) continue;
            const from_id = objStr(from, "id") orelse "";
            const to_id = objStr(to, "id") orelse "";
            try out.append(alloc, .{
                .from_id = from_id,
                .from_name = objStr(from, "name") orelse "",
                .to_id = to_id,
                .to_name = objStr(to, "name") orelse "",
                .delay_seconds = try pairDelayJson(alloc, plan, from_id, to_id),
            });
        }
    }
    return out.toOwnedSlice(alloc);
}

// ── Decision register (LTX-SPECIFICATION.md §10.3) ────────────────────────

/// entryId prefix per register entry type (LTX-SECURITY.md §9.6).
pub fn entryPrefix(entry_type: []const u8) ?[]const u8 {
    const table = [_][2][]const u8{
        .{ "question", "QST" },        .{ "question_response", "QST" },
        .{ "action", "ACT" },          .{ "action_update", "ACT" },
        .{ "amendment", "AMD" },       .{ "state_transition", "STA" },
        .{ "merge_snapshot", "MRG" },  .{ "decision", "DEC" },
        .{ "decision_update", "DEC" },
    };
    for (table) |row| {
        if (std.mem.eql(u8, row[0], entry_type)) return row[1];
    }
    return null;
}

/// Reduced state of one decision (§10.3). Strings reference the entries.
pub const DecisionState = struct {
    did: []const u8,
    text: []const u8,
    recorded_by: []const u8,
    rationale: ?[]const u8,
    origin_window: ?[]const u8,
    status: []const u8, // RECORDED | RESCINDED
    editor: ?[]const u8,
    version: i64,
};

pub const DecisionReduction = struct {
    by_id: std.StringArrayHashMap(DecisionState),
    superseded: std.ArrayList([]const u8),
    alloc: Allocator,

    pub fn deinit(self: *DecisionReduction) void {
        self.by_id.deinit();
        self.superseded.deinit(self.alloc);
    }
};

/// Reduce decision register state from log entries (§10.3), mirroring
/// ltx-sdk.js reduceDecisions: `decision` records (did = entryId, version 1),
/// `decision_update` references content.did and revises text/rationale or
/// rescinds. §8.2 conflicts: higher object version wins, then the lowest
/// editor nodeId; losers, orphan updates and duplicate creates are returned
/// in superseded. Pure.
pub fn reduceDecisionsJson(alloc: Allocator, entries: []const std.json.Value) !DecisionReduction {
    const statuses = [_][]const u8{ "RECORDED", "RESCINDED" };
    var result = DecisionReduction{
        .by_id = std.StringArrayHashMap(DecisionState).init(alloc),
        .superseded = std.ArrayList([]const u8){},
        .alloc = alloc,
    };
    errdefer result.deinit();
    var winners = std.StringArrayHashMap(Versioned).init(alloc);
    defer winners.deinit();

    const ordered = try orderEntriesJson(alloc, entries);
    defer alloc.free(ordered);

    for (ordered) |e| {
        const entry_type = objStr(e, "type") orelse "";
        const entry_id = objStr(e, "entryId") orelse "";
        const node_id = objStr(e, "nodeId") orelse "";
        const content = objGet(e, "content") orelse continue;
        if (std.mem.eql(u8, entry_type, "decision")) {
            if (result.by_id.get(entry_id) != null) {
                try result.superseded.append(alloc, entry_id);
                continue;
            }
            try winners.put(entry_id, .{ .version = 1, .editor = node_id, .entry_id = entry_id });
            try result.by_id.put(entry_id, .{
                .did = entry_id,
                .text = objStr(content, "text") orelse "",
                .recorded_by = node_id,
                .rationale = objStr(content, "rationale"),
                .origin_window = objStr(content, "originWindow"),
                .status = "RECORDED",
                .editor = null,
                .version = 1,
            });
        } else if (std.mem.eql(u8, entry_type, "decision_update")) {
            const did = objStr(content, "did") orelse "";
            const d = result.by_id.get(did) orelse {
                try result.superseded.append(alloc, entry_id);
                continue;
            };
            const version = objInt(content, "version") orelse (d.version + 1);
            const incoming = Versioned{ .version = version, .editor = node_id, .entry_id = entry_id };
            if (winners.get(did)) |current| {
                if (!winsConflict(incoming, current)) {
                    try result.superseded.append(alloc, entry_id);
                    continue;
                }
                if (!std.mem.eql(u8, current.entry_id, d.did)) {
                    try result.superseded.append(alloc, current.entry_id);
                }
            }
            try winners.put(did, incoming);
            var updated = d;
            if (objStr(content, "status")) |st| {
                for (statuses) |valid| {
                    if (std.mem.eql(u8, st, valid)) updated.status = st;
                }
            }
            if (objStr(content, "text")) |t| updated.text = t;
            if (objStr(content, "rationale")) |ra| updated.rationale = ra;
            updated.editor = node_id;
            updated.version = version;
            try result.by_id.put(did, updated);
        }
    }
    return result;
}

// ── Register entry creation + merge (LTX-SPECIFICATION.md §8.2, §8.4) ─────

/// Options for createRegisterEntryJson / runMergeSegmentJson.
pub const EntryOpts = struct {
    session_id: []const u8,
    node_id: []const u8,
    seq: i64,
    timestamp: []const u8,
    key_pair: Ed25519.KeyPair,
    /// Explicit entryId; defaults to "<PREFIX>-<nodeId>-<seq>".
    entry_id: ?[]const u8 = null,
};

/// Create a signed register entry as a wire-format JSON object (LTX-SECURITY
/// §9.5): Ed25519 over the canonical JSON of the entry without "sig". All
/// memory comes from `arena` (use an ArenaAllocator).
pub fn createRegisterEntryJson(arena: Allocator, entry_type: []const u8, content: std.json.Value, opts: EntryOpts) !std.json.Value {
    const entry_id = if (opts.entry_id) |id| try arena.dupe(u8, id) else blk: {
        const prefix = entryPrefix(entry_type) orelse return error.UnknownEntryType;
        break :blk try std.fmt.allocPrint(arena, "{s}-{s}-{d}", .{ prefix, opts.node_id, opts.seq });
    };
    var obj = std.json.ObjectMap.init(arena);
    try obj.put("entryId", .{ .string = entry_id });
    try obj.put("sessionId", .{ .string = try arena.dupe(u8, opts.session_id) });
    try obj.put("nodeId", .{ .string = try arena.dupe(u8, opts.node_id) });
    try obj.put("seq", .{ .integer = opts.seq });
    try obj.put("type", .{ .string = try arena.dupe(u8, entry_type) });
    try obj.put("content", content);
    try obj.put("timestamp", .{ .string = try arena.dupe(u8, opts.timestamp) });
    const msg = try canonicalJsonValue(arena, .{ .object = obj });
    const sig = try opts.key_pair.sign(msg, null);
    try obj.put("sig", .{ .string = try sec.b64uEnc(arena, &sig.toBytes()) });
    return .{ .object = obj };
}

pub const RejectedEntry = struct {
    entry: std.json.Value,
    reason: []const u8,
};

/// mergeLogsJson result: verified entries in §8.2 order, plus rejects.
pub const MergeLogsResult = struct {
    entries: []std.json.Value,
    rejected: []RejectedEntry,
    alloc: Allocator,

    pub fn deinit(self: *MergeLogsResult) void {
        self.alloc.free(self.entries);
        self.alloc.free(self.rejected);
    }
};

/// Deterministic merge of two entry logs (§8.2): verify every entry, union
/// de-duplicated by (nodeId, seq), order totally. Symmetric by construction.
/// Mirrors ltx-sdk.js mergeLogs. Entries reference the inputs.
pub fn mergeLogsJson(alloc: Allocator, a: []const std.json.Value, b: []const std.json.Value, cache: []const PubKeyEntry) !MergeLogsResult {
    var verified = std.ArrayList(std.json.Value){};
    defer verified.deinit(alloc);
    var rejected = std.ArrayList(RejectedEntry){};
    errdefer rejected.deinit(alloc);
    for ([_][]const std.json.Value{ a, b }) |list| {
        for (list) |e| {
            const res = try verifyRegisterEntryJson(alloc, e, cache);
            if (res.ok) try verified.append(alloc, e) else try rejected.append(alloc, .{ .entry = e, .reason = res.reason });
        }
    }
    const ordered = try orderEntriesJson(alloc, verified.items);
    return .{ .entries = ordered, .rejected = try rejected.toOwnedSlice(alloc), .alloc = alloc };
}

/// runMergeSegmentJson result. The snapshot lives in `arena`. Call deinit.
pub const MergeSegmentResult = struct {
    merged: MergeLogsResult,
    snapshot: std.json.Value,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *MergeSegmentResult) void {
        self.merged.deinit();
        self.arena.deinit();
    }
};

fn putStr(arena: Allocator, obj: *std.json.ObjectMap, key: []const u8, val: ?[]const u8) !void {
    if (val) |v| try obj.put(key, .{ .string = try arena.dupe(u8, v) });
}

/// MERGE segment (§8.4): mergeLogsJson, then a HOST-signed merge_snapshot
/// entry carrying mergedRoot, entryCount, rejectedCount, questionRegister,
/// actionRegister, decisionRegister and superseded (questions, then actions,
/// then decisions). Mirrors ltx-sdk.js runMergeSegment.
pub fn runMergeSegmentJson(alloc: Allocator, local: []const std.json.Value, remote: []const std.json.Value, cache: []const PubKeyEntry, opts: EntryOpts) !MergeSegmentResult {
    var merged = try mergeLogsJson(alloc, local, remote, cache);
    errdefer merged.deinit();
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    errdefer arena_state.deinit();
    const arena = arena_state.allocator();

    var questions = try reduceQuestionsJson(alloc, merged.entries);
    defer questions.deinit();
    var actions = try reduceActionsJson(alloc, merged.entries);
    defer actions.deinit();
    var decisions = try reduceDecisionsJson(alloc, merged.entries);
    defer decisions.deinit();

    var q_reg = std.json.ObjectMap.init(arena);
    for (questions.by_id.keys(), questions.by_id.values()) |k, q| {
        var o = std.json.ObjectMap.init(arena);
        try putStr(arena, &o, "qid", q.qid);
        try putStr(arena, &o, "text", q.text);
        try putStr(arena, &o, "submitter", q.submitter);
        try putStr(arena, &o, "urgency", q.urgency);
        try putStr(arena, &o, "intendedWindow", q.intended_window);
        try putStr(arena, &o, "status", q.status);
        try o.put("version", .{ .integer = q.version });
        try putStr(arena, &o, "response", q.response);
        try putStr(arena, &o, "responder", q.responder);
        try q_reg.put(try arena.dupe(u8, k), .{ .object = o });
    }
    var a_reg = std.json.ObjectMap.init(arena);
    for (actions.by_id.keys(), actions.by_id.values()) |k, a| {
        var o = std.json.ObjectMap.init(arena);
        try putStr(arena, &o, "aid", a.aid);
        try putStr(arena, &o, "description", a.description);
        try putStr(arena, &o, "owner", a.owner);
        try putStr(arena, &o, "dueTimeUTC", a.due_time_utc);
        try putStr(arena, &o, "originWindow", a.origin_window);
        try putStr(arena, &o, "status", a.status);
        try o.put("version", .{ .integer = a.version });
        try a_reg.put(try arena.dupe(u8, k), .{ .object = o });
    }
    var d_reg = std.json.ObjectMap.init(arena);
    for (decisions.by_id.keys(), decisions.by_id.values()) |k, d| {
        var o = std.json.ObjectMap.init(arena);
        try putStr(arena, &o, "did", d.did);
        try putStr(arena, &o, "text", d.text);
        try putStr(arena, &o, "recordedBy", d.recorded_by);
        try putStr(arena, &o, "rationale", d.rationale);
        try putStr(arena, &o, "originWindow", d.origin_window);
        try putStr(arena, &o, "status", d.status);
        try putStr(arena, &o, "editor", d.editor);
        try o.put("version", .{ .integer = d.version });
        try d_reg.put(try arena.dupe(u8, k), .{ .object = o });
    }
    var sup = std.json.Array.init(arena);
    for ([_][]const []const u8{ questions.superseded.items, actions.superseded.items, decisions.superseded.items }) |list| {
        for (list) |id| try sup.append(.{ .string = try arena.dupe(u8, id) });
    }
    const root = try entriesRootJson(arena, merged.entries);
    var content = std.json.ObjectMap.init(arena);
    try content.put("mergedRoot", .{ .string = root });
    try content.put("entryCount", .{ .integer = @intCast(merged.entries.len) });
    try content.put("rejectedCount", .{ .integer = @intCast(merged.rejected.len) });
    try content.put("questionRegister", .{ .object = q_reg });
    try content.put("actionRegister", .{ .object = a_reg });
    try content.put("decisionRegister", .{ .object = d_reg });
    try content.put("superseded", .{ .array = sup });
    const snapshot = try createRegisterEntryJson(arena, "merge_snapshot", .{ .object = content }, opts);
    return .{ .merged = merged, .snapshot = snapshot, .arena = arena_state };
}
