//! Device Object

const std = @import("std");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");

const SpinLock = @import("../hal/spinlock.zig").SpinLock;
const Driver = @import("Driver.zig");
const Device = @This();

pub const Location = enum(u64) { _ };

var global_list: std.DoublyLinkedList = .{};
var global_lock: SpinLock = .{};

header: ob.Header = .{
    .type = .device,
    .vtable = .{
        .deinit = &ob_deinit,
    },
},
name: []const u8,
driver: ?*Driver = null,
bus: ?*Device,
node: std.DoublyLinkedList.Node = .{},

pub fn create(name: []const u8, bus: ?*Device) !*Device {
    const self = try heap.allocator.create(Device);
    self.* = .{
        .name = name,
        .bus = bus,
    };

    global_lock.lock();
    global_list.append(&self.node);
    global_lock.unlock();

    return self;
}

pub fn ob_deinit(hdr: *ob.Header) void {
    std.debug.assert(hdr.type == .device);

    const self: *Device = @fieldParentPtr("header", hdr);
    heap.allocator.destroy(self);
}
