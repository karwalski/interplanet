// parity_test.zig: parity with javascript/ltx/tests/run.js (issue #27):
// golden planId vectors (spec/golden/plan-ids.json), validatePlan and the
// reserved streams / branching fields, buildDelayMatrix via pairDelay, and
// reduceDecisions + merge_snapshot decisionRegister.
//
// Run from zig/ltx (zig build test sets the working directory); the golden
// file is read at runtime from ../../spec/golden/plan-ids.json.

const std = @import("std");
const v11 = @import("ltx_v11.zig");
const ltx = @import("interplanet_ltx.zig");
const Ed25519 = std.crypto.sign.Ed25519;

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

fn get(v: std.json.Value, key: []const u8) std.json.Value {
    return v.object.get(key).?;
}

fn str(v: std.json.Value, key: []const u8) []const u8 {
    return get(v, key).string;
}

fn byName(vectors: []std.json.Value, name: []const u8) std.json.Value {
    for (vectors) |v| {
        if (std.mem.eql(u8, str(v, "name"), name)) return v;
    }
    unreachable;
}

/// Parse `json` into `arena` (the value lives as long as the arena).
fn parse(arena: std.mem.Allocator, json: []const u8) !std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{});
}

/// Copy of an object value with `key` set (in place if present, else appended).
fn withField(arena: std.mem.Allocator, plan: std.json.Value, key: []const u8, val: std.json.Value) !std.json.Value {
    var obj = try plan.object.clone();
    _ = &arena;
    try obj.put(key, val);
    return .{ .object = obj };
}

fn validateHas(alloc: std.mem.Allocator, plan: std.json.Value, code: []const u8) !bool {
    var r = try v11.validatePlanJson(alloc, plan);
    defer r.deinit();
    return r.hasCode(code);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const golden_text = std.fs.cwd().readFileAlloc(arena, "../../spec/golden/plan-ids.json", 1 << 20) catch |err| {
        std.debug.print("cannot read ../../spec/golden/plan-ids.json: {}\n", .{err});
        std.process.exit(1);
    };
    const golden = try parse(arena, golden_text);
    const vectors = get(golden, "vectors").array.items;

    // ── Golden planId vectors ────────────────────────────────────────────
    check("golden vectors present", vectors.len >= 9);
    for (vectors) |gv| {
        const plan = get(gv, "plan");
        const id = try v11.makePlanIdJson(alloc, plan);
        defer alloc.free(id);
        const ok = std.mem.eql(u8, id, str(gv, "planId"));
        if (!ok) std.debug.print("  {s}: got {s}\n", .{ str(gv, "name"), id });
        check("golden planId", ok);
        if (gv.object.get("planHash")) |ph| {
            const h = try v11.planHashJson(alloc, plan);
            defer alloc.free(h);
            check("golden planHash", std.mem.eql(u8, h, ph.string));
        }
    }
    check("golden v2 freeze anchor", std.mem.eql(u8, str(byName(vectors, "v2-freeze-check"), "planId"), "LTX-20260801-EARTHHQ-MARS-v2-d132e85d"));
    check("golden v2 unicode anchor", std.mem.eql(u8, str(byName(vectors, "v2-unicode-title"), "planId"), "LTX-20261231-EARTHHQ-MARS-v2-7bc93af8"));
    check("golden v2 order-sensitive", !std.mem.eql(u8, str(byName(vectors, "v2-createPlan-default"), "planId"), str(byName(vectors, "v2-key-order-sensitive"), "planId")));
    check("golden v3 order-insensitive", std.mem.eql(u8, str(byName(vectors, "v3-upgrade-delays"), "planId"), str(byName(vectors, "v3-key-order-insensitive"), "planId")));
    check("golden v3 amendment chain hash", std.mem.eql(u8, str(get(byName(vectors, "v3-amendment"), "plan"), "prevPlanHash"), str(byName(vectors, "v3-upgrade-delays"), "planHash")));
    {
        // JS number form and UTF-16 key order in canonical JSON.
        const nums = try parse(arena, "{\"b\":[1e21,1e-7,0.5,860.0,-2.5e-9],\"\\ud83d\\ude80\":1,\"\\uff21\":2}");
        const canon = try v11.canonicalJsonValue(alloc, nums);
        defer alloc.free(canon);
        check("canonical JS numbers + UTF-16 key order", std.mem.eql(u8, canon, "{\"b\":[1e+21,1e-7,0.5,860,-2.5e-9],\"\u{1F680}\":1,\"\u{FF21}\":2}"));
        const esc = try parse(arena, "[\"a\\bb\\fc\\u0001\"]");
        const esc_out = try v11.stringifyValue(alloc, esc);
        defer alloc.free(esc_out);
        check("stringify escapes like JSON.stringify", std.mem.eql(u8, esc_out, "[\"a\\bb\\fc\\u0001\"]"));
    }

    // ── validatePlan + reserved fields ───────────────────────────────────
    for (vectors) |gv| {
        var r = try v11.validatePlanJson(alloc, get(gv, "plan"));
        defer r.deinit();
        if (!r.valid()) std.debug.print("  {s}: {s}\n", .{ str(gv, "name"), r.errors.items[0].message });
        check("validatePlan accepts golden", r.valid());
    }
    const base = get(byName(vectors, "v3-upgrade-delays"), "plan");
    const v2 = get(byName(vectors, "v2-freeze-check"), "plan");
    check("validatePlan v3 empty streams ok", !(try validateHas(alloc, try withField(arena, base, "streams", try parse(arena, "[]")), "reserved_streams")));
    {
        var r = try v11.validatePlanJson(alloc, try withField(arena, base, "streams", try parse(arena, "[{\"id\":\"S1\"}]")));
        defer r.deinit();
        check("validatePlan non-empty streams", !r.valid() and r.hasCode("reserved_streams"));
        var path_ok = false;
        for (r.errors.items) |e| {
            if (std.mem.eql(u8, e.code, "reserved_streams")) {
                path_ok = std.mem.eql(u8, e.path, "streams");
                break;
            }
        }
        check("validatePlan streams error path", path_ok);
    }
    check("validatePlan streams non-array", try validateHas(alloc, try withField(arena, base, "streams", .{ .string = "S1" }), "reserved_streams"));
    check("validatePlan segment stream", try validateHas(alloc, try withField(arena, base, "segments", try parse(arena, "[{\"type\":\"TX\",\"q\":1,\"stream\":\"S1\"}]")), "reserved_streams"));
    check("validatePlan branches", try validateHas(alloc, try withField(arena, base, "branches", try parse(arena, "[]")), "reserved_branching"));
    check("validatePlan branching", try validateHas(alloc, try withField(arena, base, "branching", try parse(arena, "{\"mode\":\"local\"}")), "reserved_branching"));
    {
        var r = try v11.validatePlanJson(alloc, try withField(arena, base, "segments", try parse(arena, "[{\"type\":\"CAUCUS\",\"q\":1,\"branch\":\"B1\"}]")));
        defer r.deinit();
        check("validatePlan segment branch", r.hasCode("reserved_branching") and std.mem.eql(u8, r.errors.items[0].path, "segments[0].branch"));
    }
    check("validatePlan v2 streams is v3 field", try validateHas(alloc, try withField(arena, v2, "streams", try parse(arena, "[]")), "v3_field_in_v2"));
    check("validatePlan v2 branching", try validateHas(alloc, try withField(arena, v2, "branching", .{ .bool = true }), "reserved_branching"));
    check("validatePlan non-object", try validateHas(alloc, .null, "not_an_object"));
    check("validatePlan bad version", try validateHas(alloc, try withField(arena, v2, "v", .{ .integer = 7 }), "invalid_version"));
    {
        const nodes = get(v2, "nodes").array.items;
        var rev = std.json.Array.init(arena);
        try rev.append(nodes[1]);
        try rev.append(nodes[0]);
        check("validatePlan host not first", try validateHas(alloc, try withField(arena, v2, "nodes", .{ .array = rev }), "invalid_host"));
    }
    check("validatePlan unsorted delays key", try validateHas(alloc, try withField(arena, base, "delays", try parse(arena, "{\"N1|N0\":860}")), "invalid_delays"));
    check("validatePlan unknown speaker", try validateHas(alloc, try withField(arena, v2, "segments", try parse(arena, "[{\"type\":\"TX\",\"q\":1,\"speaker\":\"N9\"}]")), "unknown_speaker"));
    check("validatePlan quantum out of range", try validateHas(alloc, try withField(arena, v2, "quantum", .{ .integer = 0 }), "invalid_quantum"));
    check("validatePlan non-integer quantum", try validateHas(alloc, try withField(arena, v2, "quantum", .{ .float = 2.5 }), "invalid_quantum"));

    // Enforcement: createSession
    {
        const bad = try withField(arena, base, "streams", try parse(arena, "[1]"));
        check("createSession rejects streams", if (v11.createSession(alloc, bad, "id", .all)) |_| false else |err| err == error.ReservedStreams);
        const bad_b = try withField(arena, base, "branching", try parse(arena, "{}"));
        check("createSession rejects branching", if (v11.createSession(alloc, bad_b, "id", .all)) |_| false else |err| err == error.ReservedBranching);
        var ctx = try v11.createSession(alloc, base, "id", .all);
        defer ctx.deinit();
        check("createSession accepts golden", ctx.state == .draft);
        check("reservedFieldCode none on golden", v11.reservedFieldCode(get(byName(vectors, "v3-amendment"), "plan")) == null);
    }

    // ── buildDelayMatrix via pairDelay (§3.7.3) ──────────────────────────
    {
        const dm_plan = try parse(arena,
            \\{"v":2,"title":"Delay Matrix","start":"2026-06-01T12:00:00.000Z","quantum":5,"mode":"LTX-ASYNC",
            \\"segments":[{"type":"TX","q":1}],
            \\"nodes":[{"id":"N0","name":"Earth HQ","role":"HOST","delay":0,"location":"earth"},
            \\{"id":"N1","name":"Mars Hab-01","role":"PARTICIPANT","delay":1240,"location":"mars"},
            \\{"id":"N2","name":"Jupiter Obs","role":"PARTICIPANT","delay":3240,"location":"jupiter"},
            \\{"id":"N3","name":"Earth Annex","role":"PARTICIPANT","delay":0,"location":"earth"}]}
        );
        const dm = try v11.buildDelayMatrixJson(alloc, dm_plan);
        defer alloc.free(dm);
        const dmGet = struct {
            fn f(m: []const v11.DelayPair, a: []const u8, b: []const u8) i64 {
                for (m) |p| {
                    if (std.mem.eql(u8, p.from_id, a) and std.mem.eql(u8, p.to_id, b)) return p.delay_seconds;
                }
                return -1;
            }
        }.f;
        check("delay matrix n*(n-1) pairs", dm.len == 12);
        check("delay matrix HOST to node", dmGet(dm, "N0", "N1") == 1240 and dmGet(dm, "N1", "N0") == 1240);
        check("delay matrix non-HOST pair = sum", dmGet(dm, "N1", "N2") == 1240 + 3240);
        check("delay matrix not max", dmGet(dm, "N1", "N2") != 3240);
        var symmetric = true;
        var equals_pair = true;
        for (dm) |p| {
            if (p.delay_seconds != dmGet(dm, p.to_id, p.from_id)) symmetric = false;
            if (p.delay_seconds != try v11.pairDelayJson(alloc, dm_plan, p.from_id, p.to_id)) equals_pair = false;
        }
        check("delay matrix symmetric", symmetric);
        check("delay matrix zero-delay non-HOST", dmGet(dm, "N3", "N2") == 3240 and dmGet(dm, "N3", "N0") == 0);
        check("delay matrix equals pairDelay", equals_pair);
        check("delay matrix names", std.mem.eql(u8, dm[0].from_name, "Earth HQ") and std.mem.eql(u8, dm[0].to_name, "Mars Hab-01"));
        var v3 = try withField(arena, dm_plan, "v", .{ .integer = 3 });
        v3 = try withField(arena, v3, "delays", try parse(arena, "{\"N1|N2\":2900}"));
        v3 = try withField(arena, v3, "planVersion", .{ .integer = 1 });
        const dm3 = try v11.buildDelayMatrixJson(alloc, v3);
        defer alloc.free(dm3);
        check("delay matrix v3 entry authoritative", dmGet(dm3, "N1", "N2") == 2900 and dmGet(dm3, "N2", "N1") == 2900);
        check("delay matrix v3 fallback sum", dmGet(dm3, "N1", "N3") == 1240);
    }

    // ── Decision register + merge snapshot (§10.3, §8.4) ─────────────────
    {
        const host = Ed25519.KeyPair.generate();
        const mars = Ed25519.KeyPair.generate();
        const cache = [_]v11.PubKeyEntry{
            .{ .kid = "N0", .public_key = host.public_key },
            .{ .kid = "N1", .public_key = mars.public_key },
        };
        const Mk = struct {
            fn f(a: std.mem.Allocator, kind: []const u8, content: []const u8, node: []const u8, seq: i64, ts: []const u8, kp: Ed25519.KeyPair, entry_id: ?[]const u8) !std.json.Value {
                const c = try std.json.parseFromSliceLeaky(std.json.Value, a, content, .{});
                return v11.createRegisterEntryJson(a, kind, c, .{ .session_id = "LTX-DEC-TEST", .node_id = node, .seq = seq, .timestamp = ts, .key_pair = kp, .entry_id = entry_id });
            }
        };
        const mk = Mk.f;
        const dec1 = try mk(arena, "decision", "{\"text\":\"Proceed with EVA-3\",\"rationale\":\"Weather window\",\"originWindow\":\"W2\"}", "N0", 1, "2026-08-01T12:00:00.000Z", host, null);
        check("decision id prefix DEC", std.mem.eql(u8, str(dec1, "entryId"), "DEC-N0-1"));
        check("decision entry verifies", (try v11.verifyRegisterEntryJson(alloc, dec1, &cache)).ok);
        {
            var r = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{dec1});
            defer r.deinit();
            const d = r.by_id.get("DEC-N0-1").?;
            check("decision RECORDED", std.mem.eql(u8, d.status, "RECORDED") and d.version == 1);
            check("decision fields", std.mem.eql(u8, d.text, "Proceed with EVA-3") and std.mem.eql(u8, d.recorded_by, "N0") and
                std.mem.eql(u8, d.rationale.?, "Weather window") and std.mem.eql(u8, d.origin_window.?, "W2") and d.editor == null);
        }
        const dec_rev = try mk(arena, "decision_update", "{\"did\":\"DEC-N0-1\",\"text\":\"Proceed with EVA-3 at 14:00\",\"version\":2}", "N1", 1, "2026-08-01T12:10:00.000Z", mars, null);
        check("decision_update id prefix DEC", std.mem.eql(u8, str(dec_rev, "entryId"), "DEC-N1-1"));
        const dec_res = try mk(arena, "decision_update", "{\"did\":\"DEC-N0-1\",\"status\":\"RESCINDED\",\"version\":3}", "N0", 2, "2026-08-01T12:20:00.000Z", host, null);
        {
            var r = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{ dec_res, dec1, dec_rev });
            defer r.deinit();
            const d = r.by_id.get("DEC-N0-1").?;
            check("decision update applied", std.mem.eql(u8, d.text, "Proceed with EVA-3 at 14:00"));
            check("decision RESCINDED v3", std.mem.eql(u8, d.status, "RESCINDED") and d.version == 3);
            check("decision editor recorded", std.mem.eql(u8, d.editor.?, "N0"));
            var found = false;
            for (r.superseded.items) |id| found = found or std.mem.eql(u8, id, "DEC-N1-1");
            check("decision older update superseded", found);
        }
        const dec_a = try mk(arena, "decision_update", "{\"did\":\"DEC-N0-1\",\"text\":\"From N0\",\"version\":5}", "N0", 7, "2026-08-01T13:00:00.000Z", host, null);
        const dec_b = try mk(arena, "decision_update", "{\"did\":\"DEC-N0-1\",\"text\":\"From N1\",\"version\":5}", "N1", 7, "2026-08-01T13:00:00.000Z", mars, null);
        {
            var c1 = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{ dec1, dec_b, dec_a });
            defer c1.deinit();
            var c2 = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{ dec_a, dec1, dec_b });
            defer c2.deinit();
            check("decision tie lowest nodeId wins", std.mem.eql(u8, c1.by_id.get("DEC-N0-1").?.text, "From N0"));
            var has_b = false;
            var has_a = false;
            for (c1.superseded.items) |id| {
                has_b = has_b or std.mem.eql(u8, id, "DEC-N1-7");
                has_a = has_a or std.mem.eql(u8, id, "DEC-N0-7");
            }
            check("decision tie loser superseded", has_b and !has_a);
            var same = c1.superseded.items.len == c2.superseded.items.len;
            if (same) {
                for (c1.superseded.items, c2.superseded.items) |x, y| same = same and std.mem.eql(u8, x, y);
            }
            const d1 = c1.by_id.get("DEC-N0-1").?;
            const d2 = c2.by_id.get("DEC-N0-1").?;
            check("decision reduce order-independent", same and std.mem.eql(u8, d1.text, d2.text) and d1.version == d2.version and std.mem.eql(u8, d1.editor.?, d2.editor.?));
        }
        const dec_hi = try mk(arena, "decision_update", "{\"did\":\"DEC-N0-1\",\"text\":\"N1 v6\",\"version\":6}", "N1", 8, "2026-08-01T12:30:00.000Z", mars, null);
        {
            var r = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{ dec1, dec_a, dec_hi });
            defer r.deinit();
            check("decision higher version wins", std.mem.eql(u8, r.by_id.get("DEC-N0-1").?.text, "N1 v6"));
        }
        const orphan = try mk(arena, "decision_update", "{\"did\":\"DEC-NOPE-1\",\"version\":2}", "N1", 9, "2026-08-01T12:40:00.000Z", mars, null);
        const dup = try mk(arena, "decision", "{\"text\":\"dup\"}", "N1", 10, "2026-08-01T12:50:00.000Z", mars, "DEC-N0-1");
        {
            var r = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{ dec1, orphan, dup });
            defer r.deinit();
            var found = false;
            for (r.superseded.items) |id| found = found or std.mem.eql(u8, id, "DEC-N1-9");
            check("decision orphan update superseded", found);
            const d = r.by_id.get("DEC-N0-1").?;
            check("decision duplicate create ignored", std.mem.eql(u8, d.text, "Proceed with EVA-3") and std.mem.eql(u8, d.recorded_by, "N0"));
            var only = try v11.reduceDecisionsJson(alloc, &[_]std.json.Value{ dec1, dec_rev });
            defer only.deinit();
            var acts = try v11.reduceActionsJson(alloc, &[_]std.json.Value{dec1});
            defer acts.deinit();
            check("decision reducer ignores others", only.by_id.count() == 1 and acts.by_id.count() == 0);
        }
        {
            var seg = try v11.runMergeSegmentJson(alloc, &[_]std.json.Value{dec1}, &[_]std.json.Value{dec_rev}, &cache, .{
                .session_id = "LTX-DEC-TEST",
                .node_id = "N0",
                .seq = 99,
                .timestamp = "2026-08-01T15:00:00.000Z",
                .key_pair = host,
            });
            defer seg.deinit();
            check("runMergeSegment ok", seg.merged.entries.len == 2 and seg.merged.rejected.len == 0);
            check("snapshot is merge_snapshot MRG", std.mem.eql(u8, str(seg.snapshot, "type"), "merge_snapshot") and std.mem.eql(u8, str(seg.snapshot, "entryId"), "MRG-N0-99"));
            check("snapshot verifies", (try v11.verifyRegisterEntryJson(alloc, seg.snapshot, &cache)).ok);
            const content = get(seg.snapshot, "content");
            const reg = get(get(content, "decisionRegister"), "DEC-N0-1");
            check("snapshot decisionRegister", get(reg, "version").integer == 2 and std.mem.eql(u8, str(reg, "text"), "Proceed with EVA-3 at 14:00") and std.mem.eql(u8, str(reg, "editor"), "N1"));
            check("snapshot has question/action registers", content.object.get("questionRegister") != null and content.object.get("actionRegister") != null);
            check("snapshot counts", get(content, "entryCount").integer == 2 and get(content, "rejectedCount").integer == 0);
            const root = try v11.entriesRootJson(alloc, seg.merged.entries);
            defer alloc.free(root);
            check("snapshot mergedRoot", std.mem.eql(u8, str(content, "mergedRoot"), root));
        }
        {
            const stranger = Ed25519.KeyPair.generate();
            const stray = try mk(arena, "decision", "{\"text\":\"stray\"}", "N7", 1, "2026-08-01T12:00:00.000Z", stranger, null);
            var seg = try v11.runMergeSegmentJson(alloc, &[_]std.json.Value{ dec1, stray }, &[_]std.json.Value{}, &cache, .{
                .session_id = "LTX-DEC-TEST",
                .node_id = "N0",
                .seq = 100,
                .timestamp = "2026-08-01T15:00:00.000Z",
                .key_pair = host,
            });
            defer seg.deinit();
            check("merge rejects unverifiable entry", seg.merged.rejected.len == 1 and std.mem.eql(u8, seg.merged.rejected[0].reason, "key_not_in_cache") and
                get(get(seg.snapshot, "content"), "rejectedCount").integer == 1);
            var ab = try v11.mergeLogsJson(alloc, &[_]std.json.Value{dec1}, &[_]std.json.Value{ dec_rev, dec1 }, &cache);
            defer ab.deinit();
            var ba = try v11.mergeLogsJson(alloc, &[_]std.json.Value{ dec_rev, dec1 }, &[_]std.json.Value{dec1}, &cache);
            defer ba.deinit();
            var same = ab.entries.len == 2 and ba.entries.len == 2;
            if (same) {
                for (ab.entries, ba.entries) |x, y| same = same and std.mem.eql(u8, str(x, "entryId"), str(y, "entryId"));
            }
            check("mergeLogs symmetric and de-duplicated", same);
        }
    }

    // ── planId prefix vectors (spec/golden/plan-id-prefixes.json) ───────
    // Unicode upper-casing and UTF-16 slicing of HOSTSTR / NODESTR (issue
    // #37). Zig strings are bytes and hold a lone surrogate as WTF-8, so the
    // expected id is the planIdWtf8Hex bytes.
    {
        const ptext = std.fs.cwd().readFileAlloc(arena, "../../spec/golden/plan-id-prefixes.json", 1 << 20) catch |err| {
            std.debug.print("cannot read ../../spec/golden/plan-id-prefixes.json: {}\n", .{err});
            std.process.exit(1);
        };
        // std.json rejects a lone surrogate escape, which the exact JS planId
        // fields carry (\ud83d): map those to \ufffd before parsing (the
        // test uses planIdWtf8Hex).
        const pfixed = try arena.dupe(u8, ptext);
        var k: usize = 0;
        while (std.mem.indexOfPos(u8, pfixed, k, "\\ud8")) |at| : (k = at + 6) {
            const lone = at + 12 > pfixed.len or !std.mem.eql(u8, pfixed[at + 6 .. at + 9], "\\ud") or
                !(pfixed[at + 9] == 'c' or pfixed[at + 9] == 'd' or pfixed[at + 9] == 'e' or pfixed[at + 9] == 'f');
            if (lone) @memcpy(pfixed[at .. at + 6], "\\ufffd");
        }
        const pvectors = get(try parse(arena, pfixed), "vectors").array.items;
        check("prefix vectors present", pvectors.len >= 18);
        for (pvectors) |gv| {
            const name = str(gv, "name");
            const hex = str(gv, "planIdWtf8Hex");
            const want = try arena.alloc(u8, hex.len / 2);
            _ = try std.fmt.hexToBytes(want, hex);
            const plan = get(gv, "plan");
            const id = try v11.makePlanIdJson(alloc, plan);
            defer alloc.free(id);
            const label = try std.fmt.allocPrint(arena, "prefix planId {s} (got {s})", .{ name, id });
            check(label, std.mem.eql(u8, id, want));
            const text = try v11.stringifyValue(alloc, plan);
            defer alloc.free(text);
            const id2 = try v11.makePlanIdJson(alloc, try parse(arena, text));
            defer alloc.free(id2);
            check(try std.fmt.allocPrint(arena, "prefix planId from JSON text {s}", .{name}), std.mem.eql(u8, id2, want));
            // Typed LtxPlan (v2 model): same prefix.
            if (std.mem.eql(u8, str(plan, "mode"), "LTX") and get(plan, "v").integer == 2) {
                const typed = try ltx.planFromJson(alloc, text);
                defer ltx.deinitPlan(alloc, typed);
                const tid = try ltx.makePlanId(alloc, typed);
                defer alloc.free(tid);
                const tl = try std.fmt.allocPrint(arena, "prefix typed makePlanId {s} (got {s})", .{ name, tid });
                check(tl, tid.len == want.len and std.mem.eql(u8, tid[0 .. tid.len - 12], want[0 .. want.len - 12]));
            }
            const js = try v11.stringifyValue(alloc, .{ .string = id });
            defer alloc.free(js);
            check(try std.fmt.allocPrint(arena, "prefix lone surrogate stringifies as \\udxxx {s}", .{name}), (std.mem.indexOf(u8, js, "\\ud8") != null) == get(gv, "loneSurrogate").bool);
        }
    }

    std.debug.print("{d} passed  {d} failed\n", .{ passed, failed });
    if (failed > 0) std.process.exit(1);
}
