const std = @import("std");

pub var fmted_source: ?[:0]const u8 = null;

pub fn fmtZon(source: [:0]const u8, allocator: std.mem.Allocator) ![:0]const u8 {
    var tree = try std.zig.Ast.parse(allocator, source, .zon);
    defer tree.deinit(allocator);

    const buffer = try tree.renderAlloc(allocator);
    defer allocator.free(buffer);
    // Allocate a NUL-terminated buffer and copy formatted content
    const out = try allocator.allocSentinel(u8, buffer.len, 0);
    @memcpy(out, buffer);
    return out;
}

test {
    const allocator = std.testing.allocator;

    const source =
        \\ .{
        \\     .name = .zig_lamp,
        \\     .version = "0.0.3",
        \\     .fingerprint = 0x519db185c03fa148,
        \\     .minimum_zig_version = "0.15.1",
        \\     .dependencies = .{},
        \\     .paths = .{
        \\         "build.zig",
        \\         "build.zig.zon",
        \\         "src",
        \\     },
        \\ }
    ;
    const formatted = fmtZon(source, allocator) catch {
        std.debug.print("Formatting failed\\n", .{});
        return;
    };
    defer allocator.free(formatted);
}
