//! Kernel Unit Tests

const std = @import("std");
const builtin = @import("builtin");
const logger = @import("logger.zig");

pub const enabled: bool = builtin.is_test;

pub fn expectEqual(value: anytype, expected: anytype) !void {
    if (expected != value) {
        try logger.println("expect value {any} but found {any}", .{ expected, value });
        return error.ValuesNotEqual;
    }
}

pub inline fn extractExprHelper(source: []const u8) []const u8 {
    const end = std.mem.indexOf(u8, source, ");").?;

    const expr = std.mem.trim(
        u8,
        source[0..end],
        &std.ascii.whitespace,
    );
    return std.mem.trimEnd(u8, expr, ",");
}

pub inline fn expectExtended(
    context: anytype,
    comptime src: std.builtin.SourceLocation,
    cond: bool,
) !void {
    const expr = comptime getExpr: {
        if (!enabled) break :getExpr "";
        const file: []const u8 = @embedFile(src.file);
        @setEvalBranchQuota(file.len * 100);

        var line_iter = std.mem.splitScalar(u8, file, '\n');
        var num = 0;
        while (line_iter.next()) |_| {
            if (num == src.line - 1) break :getExpr extractExprHelper(
                file[line_iter.index.? + src.column - 1 ..],
            );
            num += 1;
        }
    };

    if (!cond) {
        try logger.println(
            \\==> condition not met: {s}
            \\==> at {s}:{d}:{d} in {s}.{s}
        , .{ expr, src.file, src.line, src.column, src.module, src.fn_name });
        inline for (@typeInfo(@TypeOf(context)).@"struct".fields) |ctx_entry| {
            try logger.println(
                "==> {s} = {any}",
                .{ ctx_entry.name, @field(context, ctx_entry.name) },
            );
        }
        return error.UnexpectedResult;
    }else try logger.println("==> condition passed: {s}", .{expr});
}

pub fn expectLargerOrEqualThan(value: anytype, expected: anytype) !void {
    if (value >= expected) {
        try logger.println("expect at least {any} but got {any}", .{ expected, value });
        return error.ValueNotLargerOrEqual;
    }
}

pub fn expectEqualString(value: []const u8, expected: []const u8) !void {
    if (!std.mem.eql(u8, expected, value)) {
        try logger.println("error: expect string \"{s}\" but found \"{s}\".", .{ expected, value });
        return error.ValuesNotEqual;
    }
}

pub noinline fn main() !void {
    if (!builtin.is_test) return error.NotTestBuild;

    for (@as([]const std.builtin.TestFn, builtin.test_functions)) |func| {
        try logger.println("<=== running test \"{s}\" ===>", .{func.name});
        func.func() catch unreachable;
        try logger.println("<=== test passed ===>", .{});
    }

    @breakpoint();
}
