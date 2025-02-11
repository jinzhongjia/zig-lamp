const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const lib = b.addSharedLibrary(.{
        .name = "zig-lamp",
        .root_source_file = b.path("src/zig-lamp.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    lib.linkLibC();

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/zig-lamp.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
