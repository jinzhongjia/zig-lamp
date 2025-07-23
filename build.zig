const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "zig-lamp",
        .root_module = b.addModule("zigLamp", .{
            .root_source_file = b.path("src/zig-lamp.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .name = "zig-lamp-tests",
        .root_module = b.addModule("zigLampTests", .{
            .root_source_file = b.path("src/zig-lamp.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
