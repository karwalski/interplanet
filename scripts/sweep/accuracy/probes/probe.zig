// Zig port (zig/planet-time). Usage:
//   zig run --dep interplanet_time -Mroot=probe.zig -Minterplanet_time=<src> -- <inputs.txt>
const std = @import("std");
const ipt = @import("interplanet_time");

const BODIES = [_][]const u8{ "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "moon" };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const text = try std.fs.cwd().readFileAlloc(alloc, args[1], 1 << 24);
    defer alloc.free(text);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    const w = out.writer(alloc);

    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        const body = f.next() orelse continue;
        const ms = try std.fmt.parseInt(i64, f.next() orelse continue, 10);
        var p: u8 = 255;
        for (BODIES, 0..) |b, i| {
            if (std.mem.eql(u8, b, body)) p = @intCast(i);
        }
        const pt = ipt.getPlanetTime(p, ms, 0.0) orelse {
            try w.print("{s}\t{d}\terror\n", .{ body, ms });
            continue;
        };
        try w.print("{s}\t{d}\t{d}\t{d}\t{d}\t{d}\t", .{ body, ms, pt.hour, pt.minute, pt.second, pt.day_number });
        if (p == 2 or p == 8) {
            try w.writeAll("-\t");
        } else if (ipt.lightTravelSeconds(2, p, ms)) |lt| {
            try w.print("{d:.3}\t", .{lt});
        } else {
            try w.writeAll("null\t");
        }
        if (p == 3) {
            const m = ipt.getMtc(ms);
            try w.print("{d}\t{d}\t{d}\t{d}\n", .{ m.sol, m.hour, m.minute, m.second });
        } else {
            try w.writeAll("-\t-\t-\t-\n");
        }
    }
    try std.fs.File.stdout().writeAll(out.items);
}
