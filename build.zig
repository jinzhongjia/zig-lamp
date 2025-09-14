const std = @import("std");
const builtin = @import("builtin");

const zig_version = builtin.zig_version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("zigLamp", .{
        .root_source_file = b.path("src/zig-lamp.zig"),
        .target = target,
        // NOTE: we can not user debug mode
        .optimize = .ReleaseSafe,
        .pic = true,
    });

    const lib = b.addLibrary(
        .{
            .name = "zig-lamp",
            .root_module = module,
            .linkage = .dynamic,
        },
    );

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .name = "zig-lamp-tests",
        .root_module = module,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
