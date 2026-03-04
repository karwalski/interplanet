const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/interplanet_time.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    // Static library
    const lib = b.addLibrary(.{
        .name        = "interplanet_time",
        .root_module = lib_mod,
        .linkage     = .static,
    });
    b.installArtifact(lib);

    // Unit test executable
    const unit_test_mod = b.createModule(.{
        .root_source_file = b.path("test/unit_test.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    unit_test_mod.addImport("interplanet_time", lib_mod);
    const unit_tests = b.addExecutable(.{
        .name        = "unit_test",
        .root_module = unit_test_mod,
    });
    b.installArtifact(unit_tests);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit + fixture tests");
    test_step.dependOn(&run_unit_tests.step);
}
