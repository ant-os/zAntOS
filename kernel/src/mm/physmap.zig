//! Physical Memory Map

const mm = @import("../mm.zig");

var base: u64 = 0;

pub fn setBase(new_base: u64) void {
    base = new_base;
}

pub fn getPtr(comptime T: type, addr: u64) *volatile T {
    return @ptrFromInt(base + addr);
}

pub fn read(comptime T: type, addr: u64) T {
    const memaddr = mm.PhysicalAddress{ .uint = addr };
    const mapping: *volatile T = @ptrCast(@alignCast(
         mm.map(
            memaddr,
            @sizeOf(T),
            .{ .writable = true, .write_through = true },
        ) catch @panic("out of memory"),
    ));
    const result = mapping.*;
    mm.unmap(.of(@volatileCast(mapping)), @sizeOf(T)) catch @panic("unmap failed"); 
    return result;
}

pub fn write(comptime T: type, addr: u64, value: T) void {
    const memaddr = mm.PhysicalAddress{ .uint = addr };
    const mapping: *volatile T = @ptrCast(@alignCast(
         mm.map(
            memaddr,
            @sizeOf(T),
            .{ .writable = true, .write_through = true },
        ) catch @panic("out of memory"),
    ));
    mapping.* = value;
    mm.unmap(.of(@volatileCast(mapping)), @sizeOf(T)) catch @panic("unmap failed"); 
}
