// security.zig -- Epic 29 security cascade for InterplanetLtx (Zig)
// Stories 29.1, 29.4, 29.5
// Uses std.crypto.sign.Ed25519 and std.crypto.hash.sha2.Sha256.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Ed25519 = std.crypto.sign.Ed25519;
const Sha256  = std.crypto.hash.sha2.Sha256;
const base64url = std.base64.url_safe_no_pad;

// ---- base64url helpers ----

pub fn b64uEnc(allocator: Allocator, data: []const u8) ![]u8 {
    const enc_len = base64url.Encoder.calcSize(data.len);
    const out = try allocator.alloc(u8, enc_len);
    _ = base64url.Encoder.encode(out, data);
    return out;
}

pub fn b64uDec(allocator: Allocator, s: []const u8) ![]u8 {
    const dec_len = try base64url.Decoder.calcSizeForSlice(s);
    const out = try allocator.alloc(u8, dec_len);
    try base64url.Decoder.decode(out, s);
    return out;
}

// ---- SHA-256 helper ----

pub fn sha256(data: []const u8) [32]u8 {
    var h: [32]u8 = undefined;
    Sha256.hash(data, &h, .{});
    return h;
}

// ---- canonical JSON ----

pub const JsonVal = union(enum) {
    Null,
    Bool:  bool,
    Int:   i64,
    Float: f64,
    Str:   []const u8,
    Arr:   []const JsonVal,
    Obj:   []const KvPair,
};

pub const KvPair = struct {
    key: []const u8,
    val: JsonVal,
};

fn jsonStrBuf(allocator: Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"'  => try buf.appendSlice(allocator, "\\\""),
            '\\'  => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else  => try buf.append(allocator, c),
        }
    }
    try buf.append(allocator, '"');
}

fn writeJson(allocator: Allocator, buf: *std.ArrayList(u8), v: JsonVal) !void {
    switch (v) {
        .Null  => try buf.appendSlice(allocator, "null"),
        .Bool  => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .Int   => |n| {
            var tmp: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch "0";
            try buf.appendSlice(allocator, s);
        },
        .Float => |f| {
            var tmp: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&tmp, "{d}", .{f}) catch "0";
            try buf.appendSlice(allocator, s);
        },
        .Str   => |s| try jsonStrBuf(allocator, buf, s),
        .Arr   => |arr| {
            try buf.append(allocator, '[');
            for (arr, 0..) |item, i| {
                if (i > 0) try buf.append(allocator, ',');
                try writeJson(allocator, buf, item);
            }
            try buf.append(allocator, ']');
        },
        .Obj   => |kvs| {
            var sorted = std.ArrayList(KvPair){};
            defer sorted.deinit(allocator);
            for (kvs) |kv| try sorted.append(allocator, kv);
            std.sort.pdq(KvPair, sorted.items, {}, struct {
                pub fn lessThan(_: void, aa: KvPair, bb: KvPair) bool {
                    return std.mem.lessThan(u8, aa.key, bb.key);
                }
            }.lessThan);
            try buf.append(allocator, '{');
            for (sorted.items, 0..) |kv, i| {
                if (i > 0) try buf.append(allocator, ',');
                try jsonStrBuf(allocator, buf, kv.key);
                try buf.append(allocator, ':');
                try writeJson(allocator, buf, kv.val);
            }
            try buf.append(allocator, '}');
        },
    }
}

pub fn canonicalJson(allocator: Allocator, v: JsonVal) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeJson(allocator, &buf, v);
    return buf.toOwnedSlice(allocator);
}

// ---- SPKI / PKCS8 DER headers for Ed25519 ----

const SPKI_HDR  = [12]u8{ 0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00 };
const PKCS8_HDR = [16]u8{ 0x30,0x2e,0x02,0x01,0x00,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x04,0x22,0x04,0x20 };

// ---- NIK type ----

pub const Nik = struct {
    key_type:        []const u8,
    node_id:         []u8,
    kid:             []u8,
    issued_at:       []u8,
    expires_at:      []const u8,
    node_label:      []u8,
    public_key_b64:  []u8,
    private_key_b64: []u8,
    key_pair:        Ed25519.KeyPair,
    allocator:       Allocator,

    pub fn deinit(self: *const Nik) void {
        self.allocator.free(self.node_id);
        self.allocator.free(self.kid);
        self.allocator.free(self.issued_at);
        if (self.expires_at.len > 0) self.allocator.free(self.expires_at);
        self.allocator.free(self.node_label);
        self.allocator.free(self.public_key_b64);
        self.allocator.free(self.private_key_b64);
    }
};

// ---- ISO-8601 UTC timestamp ----

fn isoNowOffsetDays(allocator: Allocator, days: i64) ![]u8 {
    const ts = std.time.timestamp() + days * 86400;
    const epoch = std.time.epoch;
    const secs_per_day: i64 = 86400;
    const day_of_epoch = @divFloor(ts, secs_per_day);
    const day_secs     = @mod(ts, secs_per_day);
    const hh: u8 = @intCast(@divFloor(day_secs, 3600));
    const mm: u8 = @intCast(@divFloor(@mod(day_secs, 3600), 60));
    const ss: u8 = @intCast(@mod(day_secs, 60));
    const year_day = epoch.EpochSeconds{ .secs = @intCast(day_of_epoch * secs_per_day) };
    const epoch_day = year_day.getEpochDay();
    const yd = epoch_day.calculateYearDay();
    const md = yd.calculateMonthDay();
    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ yd.year, @as(u8, @intCast(@intFromEnum(md.month))), md.day_index + 1, hh, mm, ss });
}

fn isoNow(allocator: Allocator) ![]u8 {
    return isoNowOffsetDays(allocator, 0);
}

// ---- generate_nik ----

pub fn generateNik(allocator: Allocator, valid_days: i64, node_label: []const u8) !Nik {
    const kp = Ed25519.KeyPair.generate();
    const pub_raw  = kp.public_key.bytes;
    const h        = sha256(&pub_raw);
    const node_id  = try b64uEnc(allocator, h[0..16]);
    errdefer allocator.free(node_id);
    const kid      = try allocator.dupe(u8, node_id);
    errdefer allocator.free(kid);
    var pub_der: [12 + 32]u8 = undefined;
    @memcpy(pub_der[0..12],  &SPKI_HDR);
    @memcpy(pub_der[12..44], &pub_raw);
    var priv_raw: [32]u8 = undefined;
    @memcpy(&priv_raw, kp.secret_key.bytes[0..32]);
    var priv_der: [16 + 32]u8 = undefined;
    @memcpy(priv_der[0..16],  &PKCS8_HDR);
    @memcpy(priv_der[16..48], &priv_raw);
    const pub_b64  = try b64uEnc(allocator, &pub_der);
    errdefer allocator.free(pub_b64);
    const priv_b64 = try b64uEnc(allocator, &priv_der);
    errdefer allocator.free(priv_b64);
    const issued   = try isoNow(allocator);
    errdefer allocator.free(issued);
    const expires  = try isoNowOffsetDays(allocator, valid_days);
    errdefer allocator.free(expires);
    const lbl = try allocator.dupe(u8, node_label);
    return Nik{
        .key_type        = "ltx-nik-v1",
        .node_id         = node_id,
        .kid             = kid,
        .issued_at       = issued,
        .expires_at      = expires,
        .node_label      = lbl,
        .public_key_b64  = pub_b64,
        .private_key_b64 = priv_b64,
        .key_pair        = kp,
        .allocator       = allocator,
    };
}

// ---- is_nik_expired ----

pub fn isNikExpired(allocator: Allocator, nik: *const Nik) !bool {
    const now = try isoNow(allocator);
    defer allocator.free(now);
    return std.mem.order(u8, nik.expires_at, now) != .gt;
}

// ---- COSE_Sign1 types ----

pub const CoseSign1 = struct {
    protected_hdr: []u8,
    kid:           []u8,
    payload:       []u8,
    signature:     []u8,
    allocator:     Allocator,

    pub fn deinit(self: *const CoseSign1) void {
        self.allocator.free(self.protected_hdr);
        self.allocator.free(self.kid);
        self.allocator.free(self.payload);
        self.allocator.free(self.signature);
    }
};

pub const SignedPlan = struct {
    plan:       JsonVal,
    cose_sign1: CoseSign1,
    allocator:  Allocator,

    pub fn deinit(self: *const SignedPlan) void {
        self.cose_sign1.deinit();
    }
};

// ---- sign_plan ----

pub fn signPlan(allocator: Allocator, plan: JsonVal, key_pair: Ed25519.KeyPair, kid: []const u8) !SignedPlan {
    const protected_json = try canonicalJson(allocator, JsonVal{ .Obj = &[_]KvPair{
        .{ .key = "alg", .val = JsonVal{ .Int = -19 } },
    } });
    defer allocator.free(protected_json);
    const protected_b64 = try b64uEnc(allocator, protected_json);
    errdefer allocator.free(protected_b64);
    const payload_json = try canonicalJson(allocator, plan);
    defer allocator.free(payload_json);
    const payload_b64 = try b64uEnc(allocator, payload_json);
    errdefer allocator.free(payload_b64);
    const sig_struct_arr = [_]JsonVal{
        JsonVal{ .Str = "Signature1" },
        JsonVal{ .Str = protected_b64 },
        JsonVal{ .Str = "" },
        JsonVal{ .Str = payload_b64 },
    };
    const sig_struct = try canonicalJson(allocator, JsonVal{ .Arr = &sig_struct_arr });
    defer allocator.free(sig_struct);
    const sig = try key_pair.sign(sig_struct, null);
    const sig_b64 = try b64uEnc(allocator, &sig.toBytes());
    errdefer allocator.free(sig_b64);
    const kid_dup = try allocator.dupe(u8, kid);
    return SignedPlan{
        .plan       = plan,
        .cose_sign1 = CoseSign1{
            .protected_hdr = protected_b64,
            .kid           = kid_dup,
            .payload       = payload_b64,
            .signature     = sig_b64,
            .allocator     = allocator,
        },
        .allocator  = allocator,
    };
}

// ---- verify_plan ----

pub const VerifyResult = struct {
    ok:     bool,
    reason: []const u8,
};

pub const KeyCacheEntry = struct {
    kid: []const u8,
    nik: Nik,
};

pub fn verifyPlan(allocator: Allocator, sp: SignedPlan, key_cache: []const KeyCacheEntry) !VerifyResult {
    const cs  = sp.cose_sign1;
    const kid = cs.kid;
    var found_nik: ?*const Nik = null;
    for (key_cache) |*entry| {
        if (std.mem.eql(u8, entry.kid, kid)) {
            found_nik = &entry.nik;
            break;
        }
    }
    if (found_nik == null) return VerifyResult{ .ok = false, .reason = "key_not_in_cache" };
    const nik = found_nik.?;
    if (try isNikExpired(allocator, nik)) return VerifyResult{ .ok = false, .reason = "key_expired" };
    const expected_payload_json = try canonicalJson(allocator, sp.plan);
    defer allocator.free(expected_payload_json);
    const expected_payload_b64 = try b64uEnc(allocator, expected_payload_json);
    defer allocator.free(expected_payload_b64);
    if (!std.mem.eql(u8, cs.payload, expected_payload_b64))
        return VerifyResult{ .ok = false, .reason = "payload_mismatch" };
    const sig_struct_arr = [_]JsonVal{
        JsonVal{ .Str = "Signature1" },
        JsonVal{ .Str = cs.protected_hdr },
        JsonVal{ .Str = "" },
        JsonVal{ .Str = cs.payload },
    };
    const sig_struct = try canonicalJson(allocator, JsonVal{ .Arr = &sig_struct_arr });
    defer allocator.free(sig_struct);
    const sig_bytes = try b64uDec(allocator, cs.signature);
    defer allocator.free(sig_bytes);
    if (sig_bytes.len != Ed25519.Signature.encoded_length)
        return VerifyResult{ .ok = false, .reason = "signature_mismatch" };
    var sig_arr: [Ed25519.Signature.encoded_length]u8 = undefined;
    @memcpy(&sig_arr, sig_bytes[0..Ed25519.Signature.encoded_length]);
    const sig = Ed25519.Signature.fromBytes(sig_arr);
    sig.verify(sig_struct, nik.key_pair.public_key) catch
        return VerifyResult{ .ok = false, .reason = "signature_mismatch" };
    return VerifyResult{ .ok = true, .reason = "ok" };
}

// ---- SequenceTracker ----

pub const SequenceTracker = struct {
    plan_id:   []const u8,
    seqs:      std.StringHashMap(i64),
    allocator: Allocator,

    pub fn init(allocator: Allocator, plan_id: []const u8) SequenceTracker {
        return SequenceTracker{
            .plan_id   = plan_id,
            .seqs      = std.StringHashMap(i64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SequenceTracker) void {
        self.seqs.deinit();
    }

    pub const SeqResult = struct { ok: bool, reason: []const u8 };

    pub fn addSeq(self: *SequenceTracker, peer_id: []const u8, seq: i64) !SeqResult {
        const entry = try self.seqs.getOrPut(peer_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = seq;
            return SeqResult{ .ok = true, .reason = "ok" };
        }
        const last = entry.value_ptr.*;
        if (seq <= last) return SeqResult{ .ok = false, .reason = "replay" };
        if (seq > last + 1) {
            entry.value_ptr.* = seq;
            return SeqResult{ .ok = true, .reason = "gap" };
        }
        entry.value_ptr.* = seq;
        return SeqResult{ .ok = true, .reason = "ok" };
    }

    pub fn checkSeq(self: *const SequenceTracker, peer_id: []const u8, seq: i64) SeqResult {
        const last = self.seqs.get(peer_id) orelse return SeqResult{ .ok = true, .reason = "ok" };
        if (seq <= last) return SeqResult{ .ok = false, .reason = "replay" };
        if (seq > last + 1) return SeqResult{ .ok = true, .reason = "gap" };
        return SeqResult{ .ok = true, .reason = "ok" };
    }
};
