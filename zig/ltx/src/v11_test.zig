// v11_test.zig — LTX v1.1 core subset conformance tests (Epic 72, Story 72.2)
// Golden vectors: src/v11.json (copy of conformance/vectors.json .v11).

const std = @import("std");
const sec = @import("security.zig");
const v11 = @import("ltx_v11.zig");
const Ed25519 = std.crypto.sign.Ed25519;

const V11_JSON = @embedFile("v11.json");

var passed: u32 = 0;
var failed: u32 = 0;

fn check(label: []const u8, cond: bool) void {
    if (cond) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n", .{label});
    }
}

fn checkStr(label: []const u8, got: []const u8, exp: []const u8) void {
    if (std.mem.eql(u8, got, exp)) {
        passed += 1;
    } else {
        failed += 1;
        std.debug.print("FAIL: {s}\n  expected={s}\n  got={s}\n", .{ label, exp, got });
    }
}

fn get(v: std.json.Value, key: []const u8) std.json.Value {
    return v.object.get(key).?;
}

fn getStr(v: std.json.Value, key: []const u8) []const u8 {
    return get(v, key).string;
}

fn getInt(v: std.json.Value, key: []const u8) i64 {
    return get(v, key).integer;
}

fn vectorPubKey(alloc: std.mem.Allocator, vec: std.json.Value) !Ed25519.PublicKey {
    const nik = get(get(vec, "key"), "nik");
    const raw = try sec.b64uDec(alloc, getStr(nik, "publicKey"));
    defer alloc.free(raw);
    var arr: [32]u8 = undefined;
    @memcpy(&arr, raw[0..32]);
    return Ed25519.PublicKey.fromBytes(arr);
}

fn hexDecode(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    const out = try alloc.alloc(u8, s.len / 2);
    for (out, 0..) |*b, i| {
        b.* = try std.fmt.parseInt(u8, s[i * 2 .. i * 2 + 2], 16);
    }
    return out;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, V11_JSON, .{});
    defer parsed.deinit();
    const vec = parsed.value;

    const pub_key = try vectorPubKey(alloc, vec);
    const nik_node_id = getStr(get(get(vec, "key"), "nik"), "nodeId");

    // ── key derivation: deterministic seed → vector public key / nodeId ──
    {
        const seed_raw = try sec.b64uDec(alloc, getStr(get(vec, "key"), "privateSeedB64"));
        defer alloc.free(seed_raw);
        var seed: [32]u8 = undefined;
        @memcpy(&seed, seed_raw[0..32]);
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        const pub_b64 = try sec.b64uEnc(alloc, &kp.public_key.bytes);
        defer alloc.free(pub_b64);
        checkStr("seed derives vector publicKey", pub_b64, getStr(get(get(vec, "key"), "nik"), "publicKey"));
        const h = sec.sha256(&kp.public_key.bytes);
        const node_id = try sec.b64uEnc(alloc, h[0..16]);
        defer alloc.free(node_id);
        checkStr("nodeId = b64u(sha256(pub)[0..16])", node_id, nik_node_id);
    }

    // ── Feature 1a: v3 planId (canonical JSON + SHA-256) ──────────────────
    {
        const sect = get(vec, "planIdV3");
        const plan = get(sect, "plan");
        const canon = try v11.canonicalJsonValue(alloc, plan);
        defer alloc.free(canon);
        checkStr("v3 canonical JSON", canon, getStr(sect, "canonicalJson"));
        const hash = try v11.planHashJson(alloc, plan);
        defer alloc.free(hash);
        checkStr("v3 sha256", hash, getStr(sect, "sha256"));
        const plan_id = try v11.makePlanIdJson(alloc, plan);
        defer alloc.free(plan_id);
        checkStr("v3 planId", plan_id, getStr(sect, "expectedPlanId"));
    }

    // ── Feature 1b: FROZEN v2 planId regression ───────────────────────────
    {
        const sect = get(vec, "planIdV2Regression");
        const plan_id = try v11.makePlanIdJson(alloc, get(sect, "plan"));
        defer alloc.free(plan_id);
        checkStr("FROZEN v2 planId regression", plan_id, getStr(sect, "expectedPlanId"));
    }

    // ── Feature 1c: pairDelay ─────────────────────────────────────────────
    {
        const sect = get(vec, "pairDelay");
        const plan = get(sect, "plan");
        for (get(sect, "cases").array.items) |case| {
            const a = getStr(case, "a");
            const b = getStr(case, "b");
            const got = try v11.pairDelayJson(alloc, plan, a, b);
            check("pairDelay case", got == getInt(case, "expected"));
        }
        const fc = get(sect, "fallbackCase");
        const got = try v11.pairDelayJson(alloc, get(fc, "plan"), getStr(fc, "a"), getStr(fc, "b"));
        check("pairDelay fallback (sum of HOST-relative)", got == getInt(fc, "expected"));
        check("pairDelay unknown node errors", if (v11.pairDelayJson(alloc, plan, "N0", "NX")) |_| false else |_| true);
    }

    // ── Feature 1d: computeSegmentsFor ────────────────────────────────────
    {
        const plan = get(get(vec, "pairDelay"), "plan");
        const start_ms = v11.parseIsoMs(getStr(plan, "start"));
        check("parseIsoMs 2040-02-01T12:00Z", start_ms == 2211710400000);

        const segs_n2 = try v11.computeSegmentsForJson(alloc, plan, "N2");
        defer alloc.free(segs_n2);
        check("N2 segment count", segs_n2.len == 4);
        checkStr("N2 seg0 neutral", segs_n2[0].perspective, "neutral");
        check("N2 seg0 offset 0", segs_n2[0].arrival_offset_s == 0);
        checkStr("N2 seg1 receive", segs_n2[1].perspective, "receive");
        check("N2 seg1 offset 2", segs_n2[1].arrival_offset_s == 2);
        // seg1 base start = start + 2q*5min = +10 min; shifted +2 s.
        check("N2 seg1 shifted start", segs_n2[1].start_ms == start_ms + 10 * 60_000 + 2000);
        checkStr("N2 seg1 speaker", segs_n2[1].speaker.?, "N0");
        checkStr("N2 seg1 label", segs_n2[1].label.?, "Opening");
        checkStr("N2 seg2 receive", segs_n2[2].perspective, "receive");
        check("N2 seg2 offset 500 (v3 matrix)", segs_n2[2].arrival_offset_s == 500);
        check("N2 seg2 shifted start", segs_n2[2].start_ms == start_ms + 25 * 60_000 + 500_000);

        const segs_n1 = try v11.computeSegmentsForJson(alloc, plan, "N1");
        defer alloc.free(segs_n1);
        checkStr("N1 seg2 transmit", segs_n1[2].perspective, "transmit");
        check("N1 seg2 unshifted", segs_n1[2].start_ms == start_ms + 25 * 60_000);
        checkStr("N1 seg1 receive", segs_n1[1].perspective, "receive");
        check("N1 seg1 offset 900", segs_n1[1].arrival_offset_s == 900);

        check("unknown viewer errors", if (v11.computeSegmentsForJson(alloc, plan, "NX")) |_| false else |_| true);
    }

    // ── Feature 2: state machine golden transition table ──────────────────
    {
        const sect = get(vec, "stateMachine");
        const plan = get(sect, "plan");
        const plan_id = try v11.makePlanIdJson(alloc, plan);
        defer alloc.free(plan_id);
        checkStr("stateMachine planId", plan_id, getStr(sect, "planId"));

        var ctx = try v11.createSession(alloc, plan, plan_id, .{ .count = @intCast(getInt(sect, "quorum")) });
        defer ctx.deinit();
        checkStr("initial state DRAFT", ctx.state.asStr(), "DRAFT");
        check("lockTimeoutMs 1800000", ctx.lock_timeout_ms == 1_800_000);

        for (get(sect, "steps").array.items) |step| {
            const ev = get(step, "event");
            const ev_type = getStr(ev, "type");
            const now_ms = getInt(ev, "nowMs");
            const event: v11.SmEvent = blk: {
                if (std.mem.eql(u8, ev_type, "START_LOCK")) break :blk .{ .start_lock = .{ .now_ms = now_ms } };
                if (std.mem.eql(u8, ev_type, "TICK")) break :blk .{ .tick = .{ .now_ms = now_ms } };
                if (std.mem.eql(u8, ev_type, "SESSION_START")) break :blk .{ .session_start = .{ .now_ms = now_ms } };
                if (std.mem.eql(u8, ev_type, "SESSION_END")) break :blk .{ .session_end = .{ .now_ms = now_ms } };
                if (std.mem.eql(u8, ev_type, "PLAN_CONFIRM")) break :blk .{ .plan_confirm = .{
                    .now_ms = now_ms,
                    .node_id = getStr(ev, "nodeId"),
                    .plan_id = getStr(ev, "planId"),
                } };
                if (std.mem.eql(u8, ev_type, "DELAY_MEASURED")) break :blk .{ .delay_measured = .{
                    .now_ms = now_ms,
                    .node_id = getStr(ev, "nodeId"),
                    .measured_delay_s = getInt(ev, "measuredDelayS"),
                } };
                if (std.mem.eql(u8, ev_type, "HOST_DECISION")) break :blk .{ .host_decision = .{
                    .now_ms = now_ms,
                    .decision = getStr(ev, "decision"),
                } };
                unreachable;
            };
            try ctx.transition(event);
            checkStr("step state", ctx.state.asStr(), getStr(step, "expectState"));
            const expect_lock = get(step, "expectLock");
            switch (expect_lock) {
                .null => check("step lock null", ctx.lock.asStr() == null),
                .string => |s| check("step lock", ctx.lock.asStr() != null and
                    std.mem.eql(u8, ctx.lock.asStr().?, s)),
                else => check("step lock shape", false),
            }
        }
    }

    // ── Feature 3: amendment-chain verification ───────────────────────────
    {
        const sect = get(vec, "amendmentChain");
        const chain = get(sect, "chain").array.items;
        const cache = [_]v11.PubKeyEntry{.{ .kid = nik_node_id, .public_key = pub_key }};

        const root_hash = try v11.planHashJson(alloc, get(chain[0], "plan"));
        defer alloc.free(root_hash);
        checkStr("root plan hash", root_hash, getStr(sect, "rootPlanHash"));

        const res = try v11.verifyAmendmentChainJson(alloc, chain, &cache);
        check("amendment chain verifies", res.ok == get(sect, "expectedValid").bool);

        // Tamper the golden field on link 1 → chain must fail.
        var tampered_doc = try std.json.parseFromSlice(std.json.Value, alloc, V11_JSON, .{});
        defer tampered_doc.deinit();
        const tampered_chain = get(get(tampered_doc.value, "amendmentChain"), "chain").array.items;
        // Mutate through getPtr so the real (shared) object map is updated.
        const tampered_plan = tampered_chain[1].object.getPtr("plan").?;
        try tampered_plan.object.put(getStr(sect, "tamperField"), .{ .string = "TAMPERED" });
        const tampered_res = try v11.verifyAmendmentChainJson(alloc, tampered_chain, &cache);
        check("tampered chain fails", !tampered_res.ok);

        // Empty chain rejected.
        const empty = try v11.verifyAmendmentChainJson(alloc, &[_]std.json.Value{}, &cache);
        check("empty chain fails", !empty.ok);
        checkStr("empty chain reason", empty.reason, "empty_chain");

        // Wrong key → per-link failure.
        const wrong = try v11.verifyAmendmentChainJson(alloc, chain, &[_]v11.PubKeyEntry{});
        check("empty key cache fails", !wrong.ok);
    }

    // ── Feature 4: register entries + reducers + entriesRoot ──────────────
    {
        const sect = get(vec, "registerEntries");
        const entries = get(sect, "entries").array.items;
        const cache = [_]v11.PubKeyEntry{
            .{ .kid = nik_node_id, .public_key = pub_key },
            .{ .kid = "N0", .public_key = pub_key },
            .{ .kid = "N1", .public_key = pub_key },
        };

        for (entries) |entry| {
            const res = try v11.verifyRegisterEntryJson(alloc, entry, &cache);
            check("register entry verifies", res.ok);
        }

        // Tampered entry must fail (mutate a fresh parse).
        var tampered_doc = try std.json.parseFromSlice(std.json.Value, alloc, V11_JSON, .{});
        defer tampered_doc.deinit();
        const t_entries = get(get(tampered_doc.value, "registerEntries"), "entries").array.items;
        try t_entries[0].object.put("timestamp", .{ .string = "2041-01-01T00:00:00.000Z" });
        const t_res = try v11.verifyRegisterEntryJson(alloc, t_entries[0], &cache);
        check("tampered entry fails", !t_res.ok);

        // Deterministic signature reproduction with the vector seed.
        {
            const seed_raw = try sec.b64uDec(alloc, getStr(get(vec, "key"), "privateSeedB64"));
            defer alloc.free(seed_raw);
            var seed: [32]u8 = undefined;
            @memcpy(&seed, seed_raw[0..32]);
            const kp = try Ed25519.KeyPair.generateDeterministic(seed);
            const msg = try v11.canonicalJsonValueSkip(alloc, entries[0], "sig");
            defer alloc.free(msg);
            const sig = try kp.sign(msg, null);
            const sig_b64 = try sec.b64uEnc(alloc, &sig.toBytes());
            defer alloc.free(sig_b64);
            checkStr("deterministic entry signature", sig_b64, getStr(entries[0], "sig"));
        }

        // Question reduction matches the golden state.
        var reduction = try v11.reduceQuestionsJson(alloc, entries);
        defer reduction.deinit();
        check("no superseded entries", reduction.superseded.items.len == 0);
        const expected = get(sect, "expectedQuestionState");
        var it = expected.object.iterator();
        while (it.next()) |kv| {
            const want = kv.value_ptr.*;
            const got = reduction.by_id.get(kv.key_ptr.*);
            check("question present", got != null);
            if (got) |q| {
                checkStr("question qid", q.qid, getStr(want, "qid"));
                checkStr("question text", q.text, getStr(want, "text"));
                checkStr("question submitter", q.submitter, getStr(want, "submitter"));
                checkStr("question urgency", q.urgency.?, getStr(want, "urgency"));
                checkStr("question status", q.status, getStr(want, "status"));
                check("question version", q.version == getInt(want, "version"));
                checkStr("question response", q.response.?, getStr(want, "response"));
                checkStr("question responder", q.responder.?, getStr(want, "responder"));
            }
        }

        // entriesRoot over ordered entries; input order must not matter.
        const root = try v11.entriesRootJson(alloc, entries);
        defer alloc.free(root);
        checkStr("entriesRoot", root, getStr(sect, "entriesRoot"));
        const reversed = [_]std.json.Value{ entries[1], entries[0] };
        const root_rev = try v11.entriesRootJson(alloc, &reversed);
        defer alloc.free(root_rev);
        checkStr("entriesRoot (reversed input)", root_rev, getStr(sect, "entriesRoot"));

        // Action reducer basics (same envelope machinery).
        var actions_doc = try std.json.parseFromSlice(std.json.Value, alloc,
            \\[
            \\ {"entryId":"ACT-N0-1","sessionId":"S","nodeId":"N0","seq":1,"type":"action",
            \\  "content":{"description":"Do the thing","owner":"N1"},
            \\  "timestamp":"2040-02-01T11:00:00.000Z","sig":"x"},
            \\ {"entryId":"ACT-N1-1","sessionId":"S","nodeId":"N1","seq":1,"type":"action_update",
            \\  "content":{"aid":"ACT-N0-1","status":"DONE","version":2},
            \\  "timestamp":"2040-02-01T11:10:00.000Z","sig":"x"}
            \\]
        , .{});
        defer actions_doc.deinit();
        var actions = try v11.reduceActionsJson(alloc, actions_doc.value.array.items);
        defer actions.deinit();
        check("no superseded actions", actions.superseded.items.len == 0);
        const a = actions.by_id.get("ACT-N0-1").?;
        checkStr("action status DONE", a.status, "DONE");
        check("action version 2", a.version == 2);
        checkStr("action description", a.description, "Do the thing");
        checkStr("action owner", a.owner.?, "N1");
    }

    // ── Feature 5: CBOR decode + COSE_Sign1 verify ────────────────────────
    {
        const sect = get(vec, "coseSign1");
        const cache = [_]v11.PubKeyEntry{.{ .kid = nik_node_id, .public_key = pub_key }};

        const raw_b64 = try sec.b64uDec(alloc, getStr(sect, "coseSign1CborB64"));
        defer alloc.free(raw_b64);
        const raw_hex = try hexDecode(alloc, getStr(sect, "coseSign1CborHex"));
        defer alloc.free(raw_hex);
        check("b64 and hex envelope bytes match", std.mem.eql(u8, raw_b64, raw_hex));

        // Structural checks: tag 18, 4-element array, alg -19, kid bytes.
        const decoded = try v11.decodeCbor(alloc, raw_b64);
        defer decoded.deinit(alloc);
        switch (decoded) {
            .tag => |t| {
                check("tag is 18", t.tag == v11.COSE_SIGN1_TAG);
                switch (t.value.*) {
                    .array => |arr| {
                        check("array length 4", arr.len == 4);
                        const protected = arr[0].bytes;
                        const pd = try v11.decodeCbor(alloc, protected);
                        defer pd.deinit(alloc);
                        switch (pd) {
                            .map => |m| {
                                check("protected has one pair", m.len == 1);
                                check("alg label 1", m[0].key.int == 1);
                                check("alg -19", m[0].val.int == -19);
                            },
                            else => check("protected is map", false),
                        }
                    },
                    else => check("tag wraps array", false),
                }
            },
            else => check("decoded is tag", false),
        }

        // Golden verification.
        const res = try v11.verifyPlanCoseJson(alloc, get(sect, "plan"), raw_b64, &cache);
        check("COSE_Sign1 verifies", res.ok == get(sect, "expectedValid").bool);

        // Tampered plan → payload mismatch.
        var tampered_doc = try std.json.parseFromSlice(std.json.Value, alloc, V11_JSON, .{});
        defer tampered_doc.deinit();
        const t_plan = tampered_doc.value.object.getPtr("coseSign1").?.object.getPtr("plan").?;
        try t_plan.object.put("title", .{ .string = "TAMPERED" });
        const t_res = try v11.verifyPlanCoseJson(alloc, t_plan.*, raw_b64, &cache);
        check("tampered plan fails", !t_res.ok);
        checkStr("tampered plan reason", t_res.reason, "payload_mismatch");

        // Unknown key.
        const nk = try v11.verifyPlanCoseJson(alloc, get(sect, "plan"), raw_b64, &[_]v11.PubKeyEntry{});
        check("empty key cache fails", !nk.ok);
        checkStr("empty cache reason", nk.reason, "key_not_in_cache");

        // Garbage CBOR rejected.
        const garbage = try v11.verifyPlanCoseJson(alloc, null, &[_]u8{ 0x00, 0x01 }, &cache);
        check("garbage CBOR fails", !garbage.ok);

        // Deterministic COSE signature: re-sign the Sig_structure with the
        // vector seed and compare to the envelope's signature bytes.
        {
            const seed_raw = try sec.b64uDec(alloc, getStr(get(vec, "key"), "privateSeedB64"));
            defer alloc.free(seed_raw);
            var seed: [32]u8 = undefined;
            @memcpy(&seed, seed_raw[0..32]);
            const kp = try Ed25519.KeyPair.generateDeterministic(seed);

            const env = try v11.decodeCbor(alloc, raw_b64);
            defer env.deinit(alloc);
            const arr = env.tag.value.array;
            var sig_items = [_]v11.CborVal{
                .{ .text = "Signature1" },
                .{ .bytes = arr[0].bytes },
                .{ .bytes = &[_]u8{} },
                .{ .bytes = arr[2].bytes },
            };
            const sig_struct = try v11.encodeCbor(alloc, .{ .array = sig_items[0..] });
            defer alloc.free(sig_struct);
            const sig = try kp.sign(sig_struct, null);
            check("deterministic COSE signature", std.mem.eql(u8, &sig.toBytes(), arr[3].bytes));
        }
    }

    // ── CBOR decoder robustness (RFC 8949 Appendix A subset) ─────────────
    {
        const IntCase = struct { hex: []const u8, want: i64 };
        const int_cases = [_]IntCase{
            .{ .hex = "00", .want = 0 },
            .{ .hex = "0a", .want = 10 },
            .{ .hex = "17", .want = 23 },
            .{ .hex = "1818", .want = 24 },
            .{ .hex = "1903e8", .want = 1000 },
            .{ .hex = "1a000f4240", .want = 1000000 },
            .{ .hex = "20", .want = -1 },
            .{ .hex = "3863", .want = -100 },
        };
        for (int_cases) |case| {
            const data = try hexDecode(alloc, case.hex);
            defer alloc.free(data);
            const val = try v11.decodeCbor(alloc, data);
            defer val.deinit(alloc);
            check("cbor int case", val.int == case.want);
        }
        {
            const data = try hexDecode(alloc, "6449455446");
            defer alloc.free(data);
            const val = try v11.decodeCbor(alloc, data);
            defer val.deinit(alloc);
            checkStr("cbor tstr IETF", val.text, "IETF");
        }
        {
            const data = try hexDecode(alloc, "83010203");
            defer alloc.free(data);
            const val = try v11.decodeCbor(alloc, data);
            defer val.deinit(alloc);
            check("cbor array [1,2,3]", val.array.len == 3 and val.array[2].int == 3);
        }
        const rejects = [_][]const u8{
            "f97c00", // float16
            "fb3ff199999999999a", // float64
            "9f01ff", // indefinite array
            "5f42010243030405ff", // indefinite bstr
            "0001", // trailing bytes
            "1903", // truncated head
            "6449455446ff", // trailing after tstr
        };
        for (rejects) |bad| {
            const data = try hexDecode(alloc, bad);
            defer alloc.free(data);
            check("cbor reject case", if (v11.decodeCbor(alloc, data)) |val| blk: {
                val.deinit(alloc);
                break :blk false;
            } else |_| true);
        }
        // Deterministic map encoding: keys sorted bytewise by encoded form.
        var map_pairs = [_]v11.CborPair{
            .{ .key = .{ .text = "b" }, .val = .{ .int = 2 } },
            .{ .key = .{ .text = "a" }, .val = .{ .int = 1 } },
        };
        const enc = try v11.encodeCbor(alloc, .{ .map = map_pairs[0..] });
        defer alloc.free(enc);
        const want = try hexDecode(alloc, "a2616101616202");
        defer alloc.free(want);
        check("cbor deterministic map encode", std.mem.eql(u8, enc, want));
    }

    std.debug.print("{d} passed  {d} failed\n", .{ passed, failed });
    if (failed > 0) std.process.exit(1);
}
