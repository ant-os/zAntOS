//! Physical Memory Map

var base: u64 = 0;

pub fn setBase(new_base: u64) void {
    base = new_base;
}

pub fn getPtr(comptime T: type, addr: u64) *T {
    return @ptrFromInt(base + addr);
}

pub fn read(comptime T: type, addr: u64) T {
    return getPtr(T, addr).*;
}

pub fn write(comptime T: type, addr: u64, value: T) void {
    getPtr(T, addr).* = value;
}
