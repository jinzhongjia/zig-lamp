const std = @import("std");

pub var fmted_source: ?[:0]const u8 = null;

pub fn fmtZon(source: [:0]const u8, allocator: std.mem.Allocator) ![:0]const u8 {
    var tree = try std.zig.Ast.parse(allocator, source, .zon);
    defer tree.deinit(allocator);

    const buffer = try tree.renderAlloc(allocator);

    return try allocator.allocSentinel(u8, buffer.len + 1, 0);
}
