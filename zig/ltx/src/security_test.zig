// security_test.zig -- Epic 29, Stories 29.1 / 29.4 / 29.5

const std = @import("std");
const sec = @import("security.zig");

var passed: u32 = 0;
var failed: u32 = 0;

fn check(label: []const u8, cond: bool) void {
    if (cond) { passed += 1; }
    else {
        failed += 1;
        std.debug.print("FAIL: {s}\n", .{label});
    }
}

fn checkStr(label: []const u8, got: []const u8, exp: []const u8) void {
    if (std.mem.eql(u8, got, exp)) { passed += 1; }
    else {
        failed += 1;
        std.debug.print("FAIL: {s}  expected={s}  got={s}\n", .{label, exp, got});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // ---- canonical_json ----
    {
        const r1 = try sec.canonicalJson(allocator, sec.JsonVal{ .Obj = &[_]sec.KvPair{} });
        defer allocator.free(r1);
        checkStr("empty object", r1, "{}");

        const kvs = [_]sec.KvPair{
            .{ .key = "z", .val = sec.JsonVal{ .Int = 1 } },
            .{ .key = "a", .val = sec.JsonVal{ .Int = 2 } },
        };
        const r2 = try sec.canonicalJson(allocator, sec.JsonVal{ .Obj = &kvs });
        defer allocator.free(r2);
        checkStr("sorted keys", r2, "{\"a\":2,\"z\":1}");

        const arr = [_]sec.JsonVal{ sec.JsonVal{ .Int = 1 }, sec.JsonVal{ .Int = 2 }, sec.JsonVal{ .Int = 3 } };
        const r3 = try sec.canonicalJson(allocator, sec.JsonVal{ .Arr = &arr });
        defer allocator.free(r3);
        checkStr("array", r3, "[1,2,3]");

        const r4 = try sec.canonicalJson(allocator, sec.JsonVal{ .Int = 42 });
        defer allocator.free(r4);
        checkStr("number", r4, "42");

        const r5 = try sec.canonicalJson(allocator, sec.JsonVal{ .Bool = true });
        defer allocator.free(r5);
        checkStr("bool", r5, "true");

        const r6 = try sec.canonicalJson(allocator, sec.JsonVal{ .Str = "hi" });
        defer allocator.free(r6);
        checkStr("string", r6, "\"hi\"");

        const r7 = try sec.canonicalJson(allocator, sec.JsonVal.Null);
        defer allocator.free(r7);
        checkStr("null", r7, "null");
    }

    // ---- generate_nik ----
    const nik1 = try sec.generateNik(allocator, 365, "");
    defer nik1.deinit();
    const nik2 = try sec.generateNik(allocator, 365, "");
    defer nik2.deinit();

    checkStr("key_type", nik1.key_type, "ltx-nik-v1");
    check("node_id non-empty", nik1.node_id.len > 0);
    check("kid non-empty", nik1.kid.len > 0);
    check("node_id is 22 chars", nik1.node_id.len == 22);
    check("pub_key non-empty", nik1.public_key_b64.len > 0);
    check("priv_key non-empty", nik1.private_key_b64.len > 0);
    check("issued_at set", nik1.issued_at.len > 0);
    check("expires_at set", nik1.expires_at.len > 0);

    const nik_lbl = try sec.generateNik(allocator, 30, "TestNode");
    defer nik_lbl.deinit();
    checkStr("node_label", nik_lbl.node_label, "TestNode");
    check("expires after issued", std.mem.order(u8, nik_lbl.expires_at, nik_lbl.issued_at) == .gt);
    check("unique node_ids", !std.mem.eql(u8, nik1.node_id, nik2.node_id));

    // ---- is_nik_expired ----
    const fresh_expired = try sec.isNikExpired(allocator, &nik1);
    check("fresh nik not expired", !fresh_expired);

    const old_nik = sec.Nik{
        .key_type        = nik1.key_type,
        .node_id         = nik1.node_id,
        .kid             = nik1.kid,
        .issued_at       = nik1.issued_at,
        .expires_at      = "2000-01-01T00:00:00Z",
        .node_label      = nik1.node_label,
        .public_key_b64  = nik1.public_key_b64,
        .private_key_b64 = nik1.private_key_b64,
        .key_pair        = nik1.key_pair,
        .allocator       = allocator,
    };
    const old_expired = try sec.isNikExpired(allocator, &old_nik);
    check("old nik expired", old_expired);

    // ---- sign_plan / verify_plan ----
    const plan_kvs = [_]sec.KvPair{
        .{ .key = "planId",  .val = sec.JsonVal{ .Str = "p1" } },
        .{ .key = "quantum", .val = sec.JsonVal{ .Int = 60 } },
        .{ .key = "startAt", .val = sec.JsonVal{ .Str = "2026-05-01T00:00:00Z" } },
    };
    const plan = sec.JsonVal{ .Obj = &plan_kvs };
    const sp = try sec.signPlan(allocator, plan, nik1.key_pair, nik1.kid);
    defer sp.deinit();

    check("coseSign1 protected", sp.cose_sign1.protected_hdr.len > 0);
    check("coseSign1 signature", sp.cose_sign1.signature.len > 0);
    checkStr("kid in unprotected", sp.cose_sign1.kid, nik1.kid);

    const cache = [_]sec.KeyCacheEntry{
        .{ .kid = nik1.kid, .nik = nik1 },
    };
    const vr1 = try sec.verifyPlan(allocator, sp, &cache);
    check("verify ok", vr1.ok);
    checkStr("verify reason", vr1.reason, "ok");

    const vr2 = try sec.verifyPlan(allocator, sp, &[_]sec.KeyCacheEntry{});
    check("verify fails empty cache", !vr2.ok);
    checkStr("reason key_not_in_cache", vr2.reason, "key_not_in_cache");

    const expired_cache = [_]sec.KeyCacheEntry{
        .{ .kid = nik1.kid, .nik = old_nik },
    };
    const vr3 = try sec.verifyPlan(allocator, sp, &expired_cache);
    check("verify fails expired key", !vr3.ok);
    checkStr("reason key_expired", vr3.reason, "key_expired");

    // tamper with plan
    const tampered_plan_kvs = [_]sec.KvPair{
        .{ .key = "planId", .val = sec.JsonVal{ .Str = "TAMPERED" } },
    };
    const tampered_sp = sec.SignedPlan{
        .plan      = sec.JsonVal{ .Obj = &tampered_plan_kvs },
        .cose_sign1 = sp.cose_sign1,
        .allocator  = allocator,
    };
    const vr4 = try sec.verifyPlan(allocator, tampered_sp, &cache);
    check("verify fails tampered", !vr4.ok);
    checkStr("reason payload_mismatch", vr4.reason, "payload_mismatch");

    // ---- SequenceTracker ----
    var st = sec.SequenceTracker.init(allocator, "plan-x");
    defer st.deinit();

    checkStr("plan_id stored", st.plan_id, "plan-x");

    const r1 = try st.addSeq("alice", 1);
    check("first seq accepted", r1.ok);
    checkStr("first seq msg", r1.reason, "ok");

    const r2 = try st.addSeq("alice", 2);
    check("seq 2 accepted", r2.ok);
    checkStr("seq 2 msg", r2.reason, "ok");

    const r3 = try st.addSeq("alice", 2);
    check("replay rejected", !r3.ok);
    checkStr("replay msg", r3.reason, "replay");

    const r4 = try st.addSeq("alice", 10);
    check("gap accepted", r4.ok);
    checkStr("gap msg", r4.reason, "gap");

    const c1 = st.checkSeq("alice", 10);
    check("check_seq replay", !c1.ok);
    const c2 = st.checkSeq("alice", 11);
    check("check_seq next", c2.ok);
    const c3 = st.checkSeq("alice", 20);
    check("check_seq gap", c3.ok);
    checkStr("check_seq gap msg", c3.reason, "gap");

    const rb = try st.addSeq("bob", 5);
    check("bob first seq", rb.ok);
    checkStr("bob first msg", rb.reason, "ok");

    std.debug.print("{d} passed  {d} failed\n", .{ passed, failed });
    if (failed > 0) std.process.exit(1);
}
