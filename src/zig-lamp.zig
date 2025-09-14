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
    // free previous json
    if (json) |_json|
        _allocator.free(_json);

    // get file path length
    const file_path_len = std.mem.len(file_path);

    var file = fs.openFileAbsolute(file_path[0..file_path_len], .{ .mode = .read_only }) catch return util.empty_str;
    defer file.close();

    // Get file metadata to know the size
    const file_stat = file.stat() catch return util.empty_str;
    const file_content = _allocator.alloc(u8, file_stat.size) catch return util.empty_str;
    defer _allocator.free(file_content);
    
    _ = file.read(file_content) catch return util.empty_str;

    // Create allocating writer for the output
    var output = std.Io.Writer.Allocating.init(_allocator);

    // Create a dummy error writer (we'll ignore errors)
    var error_output = std.Io.Writer.Allocating.init(_allocator);
    defer error_output.deinit();

    // Use parseFromSlice instead of parse
    zon2json.parseFromSlice(
        _allocator,
        file_content,
        &output.writer,
        &error_output.writer,
        .{ .file_name = file_path[0..file_path_len] },
    ) catch return util.empty_str;

    json = output.toOwnedSliceSentinel(0) catch return util.empty_str;

    if (json == null) return util.empty_str;

    return json.?;
}

export fn free_build_zon_info() void {
    if (json) |_json| {
        _allocator.free(_json);
        json = null;
    }
}

test "get_build_zon_info" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建临时目录
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // 测试用例1: 正常的 build.zig.zon 文件
    {
        const zon_content =
            \\.{
            \\    .name = "test_package",
            \\    .version = "1.0.0",
            \\    .dependencies = .{
            \\        .foo = .{
            \\            .path = "../foo",
            \\        },
            \\    },
            \\    .paths = .{
            \\        "src",
            \\        "build.zig",
            \\    },
            \\}
        ;

        // 创建测试文件
        const file = try tmp_dir.dir.createFile("test.zon", .{});
        defer file.close();
        try file.writeAll(zon_content);

        // 获取绝对路径
        var path_buf: [4096]u8 = undefined;
        const abs_path = try tmp_dir.dir.realpath("test.zon", &path_buf);
        
        // 添加 null 终止符
        var null_terminated_path: [4097]u8 = undefined;
        @memcpy(null_terminated_path[0..abs_path.len], abs_path);
        null_terminated_path[abs_path.len] = 0;

        // 调用函数
        const result = get_build_zon_info(&null_terminated_path);
        defer free_build_zon_info();

        // 验证结果不为空
        const result_len = std.mem.len(result);
        try testing.expect(result_len > 0);

        // 验证 JSON 包含预期的字段
        const json_str = result[0..result_len];
        try testing.expect(std.mem.indexOf(u8, json_str, "\"name\":\"test_package\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "\"version\":\"1.0.0\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "\"dependencies\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "\"paths\"") != null);
    }

    // 测试用例2: 复杂的 ZON 文件
    {
        const complex_zon =
            \\.{
            \\    .name = "complex_package",
            \\    .version = "2.5.3",
            \\    .minimum_zig_version = "0.14.0",
            \\    .dependencies = .{
            \\        .lib1 = .{
            \\            .url = "https://example.com/lib1.tar.gz",
            \\            .hash = "1234567890abcdef",
            \\        },
            \\        .lib2 = .{
            \\            .path = "./libs/lib2",
            \\        },
            \\    },
            \\    .paths = .{
            \\        "src",
            \\        "include",
            \\        "build.zig",
            \\        "README.md",
            \\    },
            \\}
        ;

        const file = try tmp_dir.dir.createFile("complex.zon", .{});
        defer file.close();
        try file.writeAll(complex_zon);

        var path_buf: [4096]u8 = undefined;
        const abs_path = try tmp_dir.dir.realpath("complex.zon", &path_buf);
        
        var null_terminated_path: [4097]u8 = undefined;
        @memcpy(null_terminated_path[0..abs_path.len], abs_path);
        null_terminated_path[abs_path.len] = 0;

        const result = get_build_zon_info(&null_terminated_path);
        defer free_build_zon_info();

        const result_len = std.mem.len(result);
        try testing.expect(result_len > 0);

        const json_str = result[0..result_len];
        try testing.expect(std.mem.indexOf(u8, json_str, "\"complex_package\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "\"minimum_zig_version\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "\"url\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "\"hash\"") != null);
    }

    // 测试用例3: 空的 ZON 文件
    {
        const empty_zon = ".{}";

        const file = try tmp_dir.dir.createFile("empty.zon", .{});
        defer file.close();
        try file.writeAll(empty_zon);

        var path_buf: [4096]u8 = undefined;
        const abs_path = try tmp_dir.dir.realpath("empty.zon", &path_buf);
        
        var null_terminated_path: [4097]u8 = undefined;
        @memcpy(null_terminated_path[0..abs_path.len], abs_path);
        null_terminated_path[abs_path.len] = 0;

        const result = get_build_zon_info(&null_terminated_path);
        defer free_build_zon_info();

        const result_len = std.mem.len(result);
        try testing.expect(result_len > 0);
        
        // 空对象应该返回 "{}"
        const json_str = result[0..result_len];
        try testing.expectEqualStrings("{}", json_str);
    }

    // 测试用例4: 不存在的文件
    {
        const non_existent = "/non/existent/file.zon";
        var null_terminated_path: [non_existent.len + 1]u8 = undefined;
        @memcpy(null_terminated_path[0..non_existent.len], non_existent);
        null_terminated_path[non_existent.len] = 0;

        const result = get_build_zon_info(&null_terminated_path);
        
        // 应该返回空字符串
        const result_len = std.mem.len(result);
        try testing.expectEqual(@as(usize, 0), result_len);
    }

    // 测试用例5: 连续调用（测试内存管理）
    {
        const zon1 = 
            \\.{
            \\    .name = "first",
            \\    .version = "1.0.0",
            \\}
        ;
        const zon2 = 
            \\.{
            \\    .name = "second",
            \\    .version = "2.0.0",
            \\}
        ;

        // 创建第一个文件
        const file1 = try tmp_dir.dir.createFile("first.zon", .{});
        defer file1.close();
        try file1.writeAll(zon1);

        // 创建第二个文件
        const file2 = try tmp_dir.dir.createFile("second.zon", .{});
        defer file2.close();
        try file2.writeAll(zon2);

        // 第一次调用
        var path_buf1: [4096]u8 = undefined;
        const abs_path1 = try tmp_dir.dir.realpath("first.zon", &path_buf1);
        var null_terminated_path1: [4097]u8 = undefined;
        @memcpy(null_terminated_path1[0..abs_path1.len], abs_path1);
        null_terminated_path1[abs_path1.len] = 0;

        const result1 = get_build_zon_info(&null_terminated_path1);
        const result1_len = std.mem.len(result1);
        const json_str1 = try allocator.dupe(u8, result1[0..result1_len]);
        defer allocator.free(json_str1);

        // 第二次调用（应该自动释放第一次的内存）
        var path_buf2: [4096]u8 = undefined;
        const abs_path2 = try tmp_dir.dir.realpath("second.zon", &path_buf2);
        var null_terminated_path2: [4097]u8 = undefined;
        @memcpy(null_terminated_path2[0..abs_path2.len], abs_path2);
        null_terminated_path2[abs_path2.len] = 0;

        const result2 = get_build_zon_info(&null_terminated_path2);
        defer free_build_zon_info();
        
        const result2_len = std.mem.len(result2);
        const json_str2 = result2[0..result2_len];

        // 验证两次调用的结果不同
        try testing.expect(std.mem.indexOf(u8, json_str1, "\"first\"") != null);
        try testing.expect(std.mem.indexOf(u8, json_str2, "\"second\"") != null);
    }

    // 测试用例6: 包含特殊字符的 ZON 文件
    {
        const special_zon =
            \\.{
            \\    .name = "special_chars",
            \\    .description = "Package with \"quotes\" and \n newlines",
            \\    .unicode = "你好世界 🎉",
            \\    .@"special-field" = "with-dashes",
            \\}
        ;

        const file = try tmp_dir.dir.createFile("special.zon", .{});
        defer file.close();
        try file.writeAll(special_zon);

        var path_buf: [4096]u8 = undefined;
        const abs_path = try tmp_dir.dir.realpath("special.zon", &path_buf);
        
        var null_terminated_path: [4097]u8 = undefined;
        @memcpy(null_terminated_path[0..abs_path.len], abs_path);
        null_terminated_path[abs_path.len] = 0;

        const result = get_build_zon_info(&null_terminated_path);
        defer free_build_zon_info();

        const result_len = std.mem.len(result);
        try testing.expect(result_len > 0);

        const json_str = result[0..result_len];
        // 验证特殊字符被正确处理
        try testing.expect(std.mem.indexOf(u8, json_str, "special_chars") != null);
        try testing.expect(std.mem.indexOf(u8, json_str, "special-field") != null);
    }
}

test "free_build_zon_info" {
    const testing = std.testing;
    
    // 测试多次调用 free_build_zon_info 不会崩溃
    free_build_zon_info();
    free_build_zon_info();
    
    // 创建临时目录和文件
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const zon_content = ".{ .name = \"test\" }";
    const file = try tmp_dir.dir.createFile("test.zon", .{});
    defer file.close();
    try file.writeAll(zon_content);
    
    var path_buf: [4096]u8 = undefined;
    const abs_path = try tmp_dir.dir.realpath("test.zon", &path_buf);
    
    var null_terminated_path: [4097]u8 = undefined;
    @memcpy(null_terminated_path[0..abs_path.len], abs_path);
    null_terminated_path[abs_path.len] = 0;
    
    // 获取信息后立即释放
    _ = get_build_zon_info(&null_terminated_path);
    free_build_zon_info();
    
    // 再次释放不应该崩溃
    free_build_zon_info();
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
