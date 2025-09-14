//! zig lamp library

const std = @import("std");
const zon2json = @import("zon2json.zig");
const fmtzon = @import("fmtzon.zig");
const util = @import("util.zig");
const fs = std.fs;
const Sha256 = std.crypto.hash.sha2.Sha256;

// In real world, this may set to page_size, usually it's 4096.

pub const zig2json = zon2json.parse;

pub const fmtZon = fmtzon.fmtZon;

// this function for ffi call
export fn check_shasum(file_path: [*c]const u8, shasum: [*c]const u8) bool {
    const file_path_len = std.mem.len(file_path);
    const shasum_len = std.mem.len(shasum);

    const file = fs.openFileAbsolute(file_path[0..file_path_len], .{}) catch {
        return false;
    };
    defer file.close();

    const digest = util.sha256Digest(file) catch return false;

    var hash: [64]u8 = std.mem.zeroes([64]u8);
    _ = std.fmt.bufPrint(&hash, "{x}", .{digest}) catch return false;
    for (0..shasum_len) |i| {
        if (shasum[i] != hash[i]) {
            return false;
        }
    }
    return true;
}

const _allocator: std.mem.Allocator = std.heap.smp_allocator;
var json: ?[:0]const u8 = null;

export fn get_build_zon_info(file_path: [*c]const u8) [*c]const u8 {
    var buffer: [util.BUF_SIZE]u8 = std.mem.zeroes([util.BUF_SIZE]u8);

    // free previous json
    if (json) |_json|
        _allocator.free(_json);

    // get file path length
    const file_path_len = std.mem.len(file_path);

    var file = fs.openFileAbsolute(file_path[0..file_path_len], .{ .mode = .read_only }) catch return util.empty_str;
    defer file.close();

    // no need to call deinit
    // var arr = std.array_list.Managed(u8).init(_allocator);
    var reader_interface = file.reader(&buffer).interface;

    var arr = std.Io.Writer.Allocating.init(_allocator);

    zon2json.parse(
        _allocator,
        &reader_interface,
        &arr.writer,
        null,
        .{ .file_name = file_path[0..file_path_len] },
    ) catch return util.empty_str;

    json = arr.toOwnedSliceSentinel(0) catch return util.empty_str;

    if (json == null) return util.empty_str;

    return json.?;
}

export fn free_build_zon_info() void {
    if (json) |_json| {
        _allocator.free(_json);
        json = null;
    }
}

export fn fmt_zon(source_code: [*c]const u8) [*c]const u8 {
    if (fmtzon.fmted_source) |_tmp|
        _allocator.free(_tmp);

    const source_code_len = std.mem.len(source_code);

    fmtzon.fmted_source = fmtzon.fmtZon(source_code[0..source_code_len :0], _allocator) catch return util.empty_str;

    if (fmtzon.fmted_source == null) return util.empty_str;

    return fmtzon.fmted_source.?;
}

export fn free_fmt_zon() void {
    if (fmtzon.fmted_source) |_tmp| {
        _allocator.free(_tmp);
        fmtzon.fmted_source = null;
    }
}
