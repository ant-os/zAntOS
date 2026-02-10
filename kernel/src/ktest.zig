//! Kernel Unit Tests

const std = @import("std");
const builtin = @import("builtin");
const logger = @import("logger.zig");

pub const enabled: bool = builtin.is_test;

pub fn expectEqual(value: anytype, expected: anytype) !void{
    if (expected != value) {
        try logger.println("expect value {any} but found {any}", .{expected, value});
        return error.ValuesNotEqual;
    }
}

pub fn expectEqualString(value: []const u8, expected: []const u8) !void{
    if (!std.mem.eql(u8, expected, value)) {
        try logger.println("error: expect string \"{s}\" but found \"{s}\".", .{expected, value});
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
}

