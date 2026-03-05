//! Object 
//! 

const std = @import("std");
const arch = @import("../arch.zig");

const Type = enum(u8) {
    thread,
    process,
    hardware_io,
    driver,
    device,
    _,
};


pub const VTable = struct {
    deinit: *const fn(*Header) void,
};



pub const Header = struct {
    @"type": Type,
    vtable: VTable,
    ptr_count: u64 = 1,
    handle_count: u64 = 0,

    pub fn ref(self: *Header) void {
        self.ptr_count += 1;
    }

    pub fn unref(self: *Header) void {
        if (self.ptr_count == 1) return self.vtable.deinit(self);
        self.ptr_count -= 1;
    }
};



