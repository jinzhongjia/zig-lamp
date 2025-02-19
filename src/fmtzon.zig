const std = @import("std");

pub var fmted_source: ?[:0]const u8 = null;

pub fn fmtZon(source: [:0]const u8, allocator: std.mem.Allocator) ![:0]const u8 {
    var tree = try std.zig.Ast.parse(allocator, source, .zon);
    defer tree.deinit(allocator);

    var buffer = std.ArrayList(u8).init(allocator);

    try tree.renderToArrayList(&buffer, .{});
    return buffer.toOwnedSliceSentinel(0);
}
