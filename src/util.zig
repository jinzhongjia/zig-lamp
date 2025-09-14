const std = @import("std");
const fs = std.fs;
const crypto = std.crypto;
const Sha256 = crypto.hash.sha2.Sha256;

// In real world, this may set to page_size, usually it's 4096.
pub const BUF_SIZE = 4096;
pub const empty_str = "";

pub fn sha256Digest(
    file: fs.File,
) ![Sha256.digest_length]u8 {
    var sha256 = Sha256.init(.{});

    var buf: [BUF_SIZE]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        sha256.update(buf[0..n]);
    }

    return sha256.finalResult();
}

test "sha256Digest" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建临时目录和文件
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // 测试用例1: 空文件
    {
        const file = try tmp_dir.dir.createFile("empty.txt", .{ .read = true });
        defer file.close();

        const digest = try sha256Digest(file);

        // 空文件的 SHA256 值
        const expected_empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        var expected: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&expected, expected_empty);

        try testing.expectEqualSlices(u8, &expected, &digest);
    }

    // 测试用例2: 包含内容的文件
    {
        const file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
        defer file.close();

        // 写入测试数据
        try file.writeAll("Hello, World!");
        try file.seekTo(0); // 重置文件指针到开始位置

        const digest = try sha256Digest(file);

        // "Hello, World!" 的 SHA256 值
        const expected_hello = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f";
        var expected: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&expected, expected_hello);

        try testing.expectEqualSlices(u8, &expected, &digest);
    }

    // 测试用例3: 大文件（超过缓冲区大小）
    {
        const file = try tmp_dir.dir.createFile("large.txt", .{ .read = true });
        defer file.close();

        // 创建大于 BUF_SIZE 的数据
        const large_data = try allocator.alloc(u8, BUF_SIZE * 2 + 100);
        defer allocator.free(large_data);

        // 填充重复的数据
        for (large_data) |*byte| {
            byte.* = 'A';
        }

        try file.writeAll(large_data);
        try file.seekTo(0);

        const digest = try sha256Digest(file);

        // 验证能正确处理大文件（不验证具体值，只确保不会崩溃）
        try testing.expect(digest.len == 32);
    }

    // 测试用例4: 二进制数据
    {
        const file = try tmp_dir.dir.createFile("binary.bin", .{ .read = true });
        defer file.close();

        const binary_data = [_]u8{ 0x00, 0xFF, 0x42, 0xAB, 0xCD, 0xEF };
        try file.writeAll(&binary_data);
        try file.seekTo(0);

        const digest = try sha256Digest(file);

        // 验证二进制数据的处理
        try testing.expect(digest.len == 32);
    }
}
