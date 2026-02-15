//! Memory Manager

const std = @import("std");
const ktest = @import("ktest.zig");

pub const PAGE_SHIFT = 12;
pub const PAGE_SIZE = 0x1000;
pub const PAGE_ALIGN = std.mem.Alignment.fromByteUnits(PAGE_SIZE);

pub const Order = enum(u5) {
    pub const raw_max: u5 = 18;

    page = 0,
    max = raw_max,
    invalid = std.math.maxInt(u5),
    _,

    pub inline fn newTruncated(v: u32) Order {
        return Order.new(
            if (v > raw_max) raw_max else @truncate(v),
        ).?;
    }

    pub inline fn new(v: u5) ?Order {
        if (v > raw_max) return null;
        return @enumFromInt(v);
    }

    pub inline fn raw(self: Order) ?u5 {
        if (!self.isValid()) return null;
        return @intFromEnum(self);
    }

    pub inline fn isValid(self: Order) bool {
        return @intFromEnum(self) <= raw_max;
    }

    pub inline fn assertValid(self: Order) void {
        if (ktest.enabled and !self.isValid()) @panic("invalid order");
    }

    pub inline fn totalPages(self: Order) u32 {
        return @as(u32, 1) << self.raw().?;
    }

    pub fn sub(self: Order, off: u5) ?Order {
        self.assertValid();

        return Order.new(self.raw().? - off);
    }

    pub fn add(self: Order, off: u5) ?Order {
        self.assertValid();

        return Order.new(self.raw().? + off);
    }
};
