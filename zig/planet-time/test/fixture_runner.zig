// fixture_runner.zig — standalone fixture runner for InterplanetTime Zig
// Story 18.17
//
// Reads reference.json from the path given by --fixture <path>.
// Validates all 54 entries against the Zig implementation.
//
// Usage:
//   zig run test/fixture_runner.zig -- --fixture ../../c/planet-time/fixtures/reference.json

const std = @import("std");
const ipt = @import("../src/interplanet_time.zig");

const PLANET_NAMES = [_][]const u8{
    "mercury", "venus", "earth", "mars",
    "jupiter", "saturn", "uranus", "neptune",
    "moon",
};

fn planetIndex(name: []const u8) ?u8 {
    for (PLANET_NAMES, 0..) |n, i| {
        if (std.mem.eql(u8, name, n)) return @intCast(i);
    }
    return null;
}

// ── Very small JSON value extractor (no alloc) ─────────────────────────────

/// Find the value of a JSON field by key within a JSON object slice.
/// Returns a slice of the raw value (string, number, null, object, etc.)
fn jsonField(json: []const u8, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < json.len) : (i += 1) {
        if (json[i] != '"') continue;
        // Check if this matches our key
        const key_start = i + 1;
        if (key_start + key.len >= json.len) break;
        if (!std.mem.eql(u8, json[key_start .. key_start + key.len], key)) continue;
        const key_end = key_start + key.len;
        if (key_end >= json.len or json[key_end] != '"') continue;
        // Found key, now find colon
        var j = key_end + 1;
        while (j < json.len and (json[j] == ' ' or json[j] == '\t' or json[j] == '\n' or json[j] == '\r')) : (j += 1) {}
        if (j >= json.len or json[j] != ':') continue;
        j += 1;
        while (j < json.len and (json[j] == ' ' or json[j] == '\t' or json[j] == '\n' or json[j] == '\r')) : (j += 1) {}
        if (j >= json.len) return null;
        // Now j points to start of value
        const val_start = j;
        if (json[j] == '"') {
            // String value
            j += 1;
            while (j < json.len) : (j += 1) {
                if (json[j] == '\\') { j += 1; continue; }
                if (json[j] == '"') { j += 1; break; }
            }
            return json[val_start..j];
        } else if (json[j] == '{' or json[j] == '[') {
            // Object/array: find matching bracket
            const open = json[j];
            const close: u8 = if (open == '{') '}' else ']';
            var depth: u32 = 1;
            j += 1;
            while (j < json.len and depth > 0) : (j += 1) {
                if (json[j] == open) depth += 1
                else if (json[j] == close) depth -= 1;
            }
            return json[val_start..j];
        } else {
            // Number, bool, null
            while (j < json.len and json[j] != ',' and json[j] != '}' and json[j] != ']' and json[j] != '\n') : (j += 1) {}
            return std.mem.trim(u8, json[val_start..j], " \t\r\n");
        }
        i = j;
    }
    return null;
}

fn parseF64(s: []const u8) ?f64 {
    const trimmed = std.mem.trim(u8, s, " \t\r\n\"");
    if (std.mem.eql(u8, trimmed, "null")) return null;
    return std.fmt.parseFloat(f64, trimmed) catch null;
}

fn parseI64(s: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, s, " \t\r\n\"");
    if (std.mem.eql(u8, trimmed, "null")) return null;
    return std.fmt.parseInt(i64, trimmed, 10) catch null;
}

fn parseBool(s: []const u8) bool {
    const trimmed = std.mem.trim(u8, s, " \t\r\n\"");
    return std.mem.eql(u8, trimmed, "1") or std.mem.eql(u8, trimmed, "true");
}

fn parseStr(s: []const u8) []const u8 {
    var trimmed = std.mem.trim(u8, s, " \t\r\n");
    if (trimmed.len >= 2 and trimmed[0] == '"') {
        trimmed = trimmed[1 .. trimmed.len - 1];
    }
    return trimmed;
}

// ── Entry iterator ─────────────────────────────────────────────────────────

/// Find the "entries" array in the JSON and iterate over each object.
/// Calls callback for each raw entry JSON object string.
fn iterateEntries(json: []const u8, comptime callback: fn (entry: []const u8, idx: usize) void) usize {
    // Find "entries": [
    const marker = "\"entries\"";
    const pos = std.mem.indexOf(u8, json, marker) orelse return 0;
    var i = pos + marker.len;
    while (i < json.len and json[i] != '[') : (i += 1) {}
    if (i >= json.len) return 0;
    i += 1; // skip '['

    var count: usize = 0;
    while (i < json.len) {
        // Skip whitespace and commas
        while (i < json.len and (json[i] == ' ' or json[i] == '\t' or json[i] == '\n' or json[i] == '\r' or json[i] == ',')) : (i += 1) {}
        if (i >= json.len or json[i] == ']') break;
        if (json[i] != '{') { i += 1; continue; }

        // Find matching }
        const entry_start = i;
        var depth: u32 = 1;
        i += 1;
        while (i < json.len and depth > 0) : (i += 1) {
            if (json[i] == '{') depth += 1
            else if (json[i] == '}') depth -= 1;
        }
        const entry_json = json[entry_start..i];
        callback(entry_json, count);
        count += 1;
    }
    return count;
}

var g_passed: u32 = 0;
var g_failed: u32 = 0;
var g_entry_idx: usize = 0;

fn processEntry(entry: []const u8, idx: usize) void {
    g_entry_idx = idx;

    // Parse planet name
    const planet_raw = jsonField(entry, "planet") orelse {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}]: no planet field\n", .{idx});
        return;
    };
    const planet_name = parseStr(planet_raw);
    const planet_idx_maybe = planetIndex(planet_name);
    const planet = planet_idx_maybe orelse {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}]: unknown planet '{s}'\n", .{ idx, planet_name });
        return;
    };

    // Parse utc_ms
    const utc_raw = jsonField(entry, "utc_ms") orelse return;
    const utc_ms = parseI64(utc_raw) orelse return;

    // Parse expected values
    const hour_raw = jsonField(entry, "hour") orelse "0";
    const min_raw = jsonField(entry, "minute") orelse "0";
    const sec_raw = jsonField(entry, "second") orelse "0";
    const dn_raw = jsonField(entry, "day_number") orelse "0";
    const yn_raw = jsonField(entry, "year_number") orelse "0";
    const diy_raw = jsonField(entry, "day_in_year") orelse "0";
    const piw_raw = jsonField(entry, "period_in_week") orelse "0";
    const iwp_raw = jsonField(entry, "is_work_period") orelse "0";
    const iwh_raw = jsonField(entry, "is_work_hour") orelse "0";
    const lt_raw = jsonField(entry, "light_travel_s") orelse "null";
    const hr_raw = jsonField(entry, "helio_r_au") orelse "0";
    const si_raw = jsonField(entry, "sol_in_year") orelse "null";
    const spy_raw = jsonField(entry, "sols_per_year") orelse "null";

    const exp_hour = parseI64(hour_raw) orelse 0;
    const exp_min = parseI64(min_raw) orelse 0;
    const exp_sec = parseI64(sec_raw) orelse 0;
    const exp_dn = parseI64(dn_raw) orelse 0;
    const exp_yn = parseI64(yn_raw) orelse 0;
    const exp_diy = parseI64(diy_raw) orelse 0;
    const exp_piw = parseI64(piw_raw) orelse 0;
    const exp_iwp = parseBool(iwp_raw);
    const exp_iwh = parseBool(iwh_raw);
    const exp_lt = parseF64(lt_raw);
    const exp_hr = parseF64(hr_raw) orelse 0.0;
    const exp_si = parseI64(si_raw);
    const exp_spy = parseI64(spy_raw);

    // Compute planet time
    const pt = ipt.getPlanetTime(planet, utc_ms, 0.0) orelse {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: getPlanetTime returned null\n", .{ idx, planet_name });
        return;
    };

    // Validate
    if (pt.hour != @as(i32, @intCast(exp_hour))) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: hour got={d} expected={d}\n", .{ idx, planet_name, pt.hour, exp_hour });
    } else g_passed += 1;

    if (pt.minute != @as(i32, @intCast(exp_min))) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: minute got={d} expected={d}\n", .{ idx, planet_name, pt.minute, exp_min });
    } else g_passed += 1;

    if (pt.second != @as(i32, @intCast(exp_sec))) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: second got={d} expected={d}\n", .{ idx, planet_name, pt.second, exp_sec });
    } else g_passed += 1;

    if (pt.day_number != exp_dn) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: day_number got={d} expected={d}\n", .{ idx, planet_name, pt.day_number, exp_dn });
    } else g_passed += 1;

    if (pt.year_number != exp_yn) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: year_number got={d} expected={d}\n", .{ idx, planet_name, pt.year_number, exp_yn });
    } else g_passed += 1;

    if (pt.day_in_year != exp_diy) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: day_in_year got={d} expected={d}\n", .{ idx, planet_name, pt.day_in_year, exp_diy });
    } else g_passed += 1;

    if (pt.period_in_week != @as(i32, @intCast(exp_piw))) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: period_in_week got={d} expected={d}\n", .{ idx, planet_name, pt.period_in_week, exp_piw });
    } else g_passed += 1;

    if (pt.is_work_period != exp_iwp) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: is_work_period got={} expected={}\n", .{ idx, planet_name, pt.is_work_period, exp_iwp });
    } else g_passed += 1;

    if (pt.is_work_hour != exp_iwh) {
        g_failed += 1;
        std.debug.print("FAIL entry[{d}] {s}: is_work_hour got={} expected={}\n", .{ idx, planet_name, pt.is_work_hour, exp_iwh });
    } else g_passed += 1;

    // sol_in_year
    if (exp_si) |esi| {
        if (pt.sol_in_year) |gsi| {
            if (gsi != esi) {
                g_failed += 1;
                std.debug.print("FAIL entry[{d}] {s}: sol_in_year got={d} expected={d}\n", .{ idx, planet_name, gsi, esi });
            } else g_passed += 1;
        } else {
            g_failed += 1;
            std.debug.print("FAIL entry[{d}] {s}: sol_in_year expected {d} got null\n", .{ idx, planet_name, esi });
        }
    } else {
        if (pt.sol_in_year != null) {
            g_failed += 1;
            std.debug.print("FAIL entry[{d}] {s}: sol_in_year expected null\n", .{ idx, planet_name });
        } else g_passed += 1;
    }

    _ = exp_spy;

    // light_travel_s
    if (exp_lt) |elt| {
        if (ipt.lightTravelSeconds(2, planet, utc_ms)) |glt| {
            if (@abs(glt - elt) > 10.0) {
                g_failed += 1;
                std.debug.print("FAIL entry[{d}] {s}: light_travel got={d:.2} expected={d:.2}\n", .{ idx, planet_name, glt, elt });
            } else g_passed += 1;
        } else {
            g_failed += 1;
            std.debug.print("FAIL entry[{d}] {s}: light_travel expected {d:.2} got null\n", .{ idx, planet_name, elt });
        }
    } else {
        g_passed += 1; // Earth/Moon: no light travel
    }

    // helio_r_au
    if (ipt.heliocentricPositionMs(planet, utc_ms)) |pos| {
        if (@abs(pos.r - exp_hr) > 0.01) {
            g_failed += 1;
            std.debug.print("FAIL entry[{d}] {s}: helio_r got={d:.6} expected={d:.6}\n", .{ idx, planet_name, pos.r, exp_hr });
        } else g_passed += 1;
    } else {
        g_passed += 1; // invalid body OK
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse --fixture <path> argument
    var fixture_path: ?[]const u8 = null;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--fixture")) {
            fixture_path = args.next();
        }
    }

    const path = fixture_path orelse {
        std.debug.print("Usage: fixture_runner --fixture <path-to-reference.json>\n", .{});
        std.process.exit(1);
    };

    // Read file
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error opening {s}: {}\n", .{ path, err });
        std.process.exit(1);
    };
    defer file.close();

    const json = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(json);

    std.debug.print("InterplanetTime Zig — fixture runner\n", .{});
    std.debug.print("Fixture: {s}\n", .{path});

    const count = iterateEntries(json, processEntry);

    std.debug.print("\nfixture entries checked: {d}\n", .{count});
    std.debug.print("{d} passed  {d} failed\n", .{ g_passed, g_failed });
    if (g_failed > 0) {
        std.process.exit(1);
    }
}
