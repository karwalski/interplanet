const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/interplanet_ltx.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "interplanet_ltx",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    // Unit test executable (existing)
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/unit_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addExecutable(.{
        .name = "unit_test",
        .root_module = test_mod,
    });
    b.installArtifact(unit_tests);

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Security test executable (Epic 29)
    const sec_test_mod = b.createModule(.{
        .root_source_file = b.path("src/security_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const sec_tests = b.addExecutable(.{
        .name = "security_test",
        .root_module = sec_test_mod,
    });
    b.installArtifact(sec_tests);

    const run_sec_tests = b.addRunArtifact(sec_tests);

    // LTX v1.1 conformance test executable (Epic 72, Story 72.2)
    const v11_test_mod = b.createModule(.{
        .root_source_file = b.path("src/v11_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const v11_tests = b.addExecutable(.{
        .name = "v11_test",
        .root_module = v11_test_mod,
    });
    b.installArtifact(v11_tests);

    const run_v11_tests = b.addRunArtifact(v11_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_sec_tests.step);
    test_step.dependOn(&run_v11_tests.step);
}
