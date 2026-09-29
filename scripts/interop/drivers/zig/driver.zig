// Interop driver for zig/ltx (see scripts/interop/run.js).
// (a) uses the typed API in interplanet_ltx.zig (createPlan / encodeHash /
// makePlanId); (c) uses makePlanIdJson from ltx_v11.zig.
const std = @import("std");
const ltx = @import("ltx");
const v11 = @import("v11");

fn out(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(alloc, fmt, args);
    defer alloc.free(s);
    try std.fs.File.stdout().writeAll(s);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const in_dir = args[1];
    const out_dir = args[2];

    // The typed Node has no role/delay and the typed segment template has no
    // speaker/label; segments are expanded to timed entries by createPlan.
    const nodes = [_]ltx.Node{
        .{ .id = "N0", .name = "Earth HQ", .location = "earth", .is_host = true },
        .{ .id = "N1", .name = "Mars Hab-01", .location = "mars", .is_host = false },
        .{ .id = "N2", .name = "L-1 Gateway", .location = "moon", .is_host = false },
    };
    const segs = [_]ltx.SegmentTemplate{
        .{ .seg_type = "PLAN_CONFIRM", .duration = 2 }, .{ .seg_type = "TX", .duration = 3 },
        .{ .seg_type = "RX", .duration = 3 },           .{ .seg_type = "TX", .duration = 2 },
        .{ .seg_type = "BUFFER", .duration = 1 },
    };
    const plan = try ltx.createPlan(alloc, .{
        .title = "Réunion Mars 🚀",
        .start = "2026-03-15T14:00:00.000Z",
        .quantum = 3,
        .mode = "LTX-ASYNC",
        .nodes = &nodes,
        .segments = &segs,
    });
    try out(alloc, "NOTE typed Plan: nodes carry is_host (no role/delay), segments are timed (no q/label), no v3\n", .{});

    const hash = try ltx.encodeHash(alloc, plan);
    const wire = try ltx.decodeHash(alloc, hash);
    const wire_path = try std.fmt.allocPrint(alloc, "{s}/wire-v2.json", .{out_dir});
    try std.fs.cwd().writeFile(.{ .sub_path = wire_path, .data = wire });
    try out(alloc, "ID_V2 {s}\n", .{try ltx.makePlanId(alloc, plan)});

    for ([_][]const u8{ "2", "3" }) |v| {
        const path = try std.fmt.allocPrint(alloc, "{s}/js-v{s}.json", .{ in_dir, v });
        const text = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 20);
        const parsed = try std.json.parseFromSlice(std.json.Value, alloc, text, .{});
        try out(alloc, "JS_V{s} {s}\n", .{ v, try v11.makePlanIdJson(alloc, parsed.value) });
    }
}
