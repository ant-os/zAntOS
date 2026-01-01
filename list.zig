const std = @import("std");

pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        data: [*]T,
        len: usize,
        capacity: usize,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator, preallocate: usize) Self {
            return .{
                .data = alloc.alloc(T, preallocate),
                .len = preallocate,
                .capacity = preallocate,
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data[0..self.capacity]);
        }
    };
}
