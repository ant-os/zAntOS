const std = @import("std");
const klog = std.log.scoped(.kernel_paging);

pub fn translateAddr(addr: usize) !usize {
    _ = addr;

    @panic("todo");
}

const MapOptions = packed struct { writable: bool = true, noCache: bool = false, writeThrough: bool = false, noSwap: bool = false, relocatable: bool = false };

pub fn mapPage(physical: usize, virtual: *anyopaque, attributes: MapOptions) !void {
    _ = physical;
    _ = virtual;
    _ = attributes;
}

pub fn unmapPage(virtual: *anyopaque) !void {
    _ = virtual;

    @panic("todo");
}

pub fn init() !void {
    klog.info("Initializing kernel paging...", .{});

    return error.NotImplemented;
}
