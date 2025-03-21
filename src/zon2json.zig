//! this file is from repo https://github.com/Cloudef/zig2nix
const std = @import("std");
const builtin = @import("builtin");

fn stringifyFieldName(allocator: std.mem.Allocator, ast: std.zig.Ast, idx: std.zig.Ast.Node.Index) !?[]const u8 {
    if (ast.firstToken(idx) < 2) return null;
    const slice = ast.tokenSlice(ast.firstToken(idx) - 2);
    if (slice[0] == '@') {
        const v = try std.zig.string_literal.parseAlloc(allocator, slice[1..]);
        defer allocator.free(v);
        return try std.json.stringifyAlloc(allocator, v, .{});
    }
    return try std.json.stringifyAlloc(allocator, slice, .{});
}

fn stringifyValue(allocator: std.mem.Allocator, ast: std.zig.Ast, idx: std.zig.Ast.Node.Index) !?[]const u8 {
    const index = if (comptime builtin.zig_version.minor > 14) @intFromEnum(idx) else idx;
    const slice = ast.tokenSlice(ast.nodes.items(.main_token)[index]);
    if (slice[0] == '\'') {
        switch (std.zig.parseCharLiteral(slice)) {
            .success => |v| return try std.json.stringifyAlloc(allocator, v, .{}),
            .failure => return error.parseCharLiteralFailed,
        }
    } else if (slice[0] == '"') {
        const v = try std.zig.string_literal.parseAlloc(allocator, slice);
        defer allocator.free(v);
        return try std.json.stringifyAlloc(allocator, v, .{});
    }
    switch (std.zig.number_literal.parseNumberLiteral(slice)) {
        .int => |v| return try std.json.stringifyAlloc(allocator, v, .{}),
        .float => |v| return try std.json.stringifyAlloc(allocator, v, .{}),
        .big_int => |v| return try std.json.stringifyAlloc(allocator, v, .{}),
        .failure => {},
    }
    if (std.mem.eql(u8, slice, "true")) {
        return try std.json.stringifyAlloc(allocator, true, .{});
    } else if (std.mem.eql(u8, slice, "false")) {
        return try std.json.stringifyAlloc(allocator, false, .{});
    }

    // literal
    return try std.json.stringifyAlloc(allocator, slice, .{});
}

fn stringify(allocator: std.mem.Allocator, writer: anytype, ast: std.zig.Ast, idx: std.zig.Ast.Node.Index, has_name: bool) !void {
    if (has_name) {
        if (try stringifyFieldName(allocator, ast, idx)) |name| {
            defer allocator.free(name);
            try writer.print("{s}:", .{name});
            if (std.mem.eql(u8, name, "\"fingerprint\"")) {
                const index = if (builtin.zig_version.minor > 14) @intFromEnum(idx) else idx;
                const slice = ast.tokenSlice(ast.nodes.items(.main_token)[index]);

                const v = try std.fmt.allocPrint(allocator, "\"{s}\"", .{slice});
                defer allocator.free(v);

                try writer.writeAll(v);
                return;
            }
        }
    }

    var buf: [2]std.zig.Ast.Node.Index = undefined;
    if (ast.fullStructInit(&buf, idx)) |v| {
        try writer.writeAll("{");
        for (v.ast.fields, 0..) |i, n| {
            try stringify(allocator, writer, ast, i, true);
            if (n + 1 != v.ast.fields.len) try writer.writeAll(",");
        }
        try writer.writeAll("}");
    } else if (ast.fullArrayInit(&buf, idx)) |v| {
        try writer.writeAll("[");
        for (v.ast.elements, 0..) |i, n| {
            try stringify(allocator, writer, ast, i, false);
            if (n + 1 != v.ast.elements.len) try writer.writeAll(",");
        }
        try writer.writeAll("]");
    } else if (try stringifyValue(allocator, ast, idx)) |v| {
        defer allocator.free(v);
        try writer.writeAll(v);
    } else {
        return error.UnknownType;
    }
}

pub const Options = struct {
    limit: usize = std.math.maxInt(usize),
    file_name: []const u8 = "build.zig.zon", // for errors
};

pub fn parse(allocator: std.mem.Allocator, reader: std.io.AnyReader, writer: anytype, error_writer: anytype, opts: Options) !void {
    const zon = blk: {
        var tmp = try reader.readAllAlloc(allocator, opts.limit);
        errdefer allocator.free(tmp);
        tmp = try allocator.realloc(tmp, tmp.len + 1);
        tmp[tmp.len - 1] = 0;
        break :blk tmp[0 .. tmp.len - 1 :0];
    };

    defer allocator.free(zon);
    var ast = try std.zig.Ast.parse(allocator, zon, .zon);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        if (@TypeOf(error_writer) != void) {
            for (ast.errors) |e| {
                const loc = ast.tokenLocation(ast.errorOffset(e), e.token);
                try error_writer.print("error: {s}:{}:{}: ", .{ opts.file_name, loc.line, loc.column });
                try ast.renderError(e, error_writer);
                try error_writer.writeAll("\n");
            }
        }
        return error.ParseFailed;
    }

    try stringify(allocator, writer, ast, if (builtin.zig_version.minor > 14) ast.nodes.items(.data)[0].node else ast.nodes.items(.data)[0].lhs, false);
}
