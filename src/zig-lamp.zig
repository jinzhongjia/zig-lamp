//! zig lamp library

const std = @import("std");
const fs = std.fs;
const Sha256 = std.crypto.hash.sha2.Sha256;

// In real world, this may set to page_size, usually it's 4096.
const BUF_SIZE = 4096;

pub export fn sha256_digest(file_path: [*c]const u8, shasum: [*c]const u8) bool {
    const file_path_len = std.mem.len(file_path);
    const shasum_len = std.mem.len(shasum);

    const file = fs.openFileAbsolute(file_path[0..file_path_len], .{}) catch {
        return false;
    };
    defer file.close();

    var sha256 = Sha256.init(.{});
    const rdr = file.reader();

    var buf: [BUF_SIZE]u8 = undefined;
    var n = rdr.read(&buf) catch return false;

    while (n != 0) {
        sha256.update(buf[0..n]);
        n = rdr.read(&buf) catch return false;
    }

    const digest = sha256.finalResult();

    var hash: [64]u8 = std.mem.zeroes([64]u8);
    _ = std.fmt.bufPrint(&hash, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch return false;
    for (0..shasum_len) |i| {
        if (shasum[i] != hash[i]) {
            return false;
        }
    }
    return true;
}
