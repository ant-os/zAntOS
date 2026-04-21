//! Device Object

const std = @import("std");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");
const SpinLock = @import("../hal/spinlock.zig").SpinLock;
const Irp = @import("Irp.zig");
const antk = @import("../antk/antk.zig");
const arch = @import("../hal/arch/arch.zig");
const ANTSTATUS = @import("../antk/status.zig").ANTSTATUS;

const Driver = @import("Driver.zig");

const Device = @This();

pub const Location = enum(u64) { _ };

pub const Callback = ?*const fn (irp: *Irp, *const Irp.MajorFunction.Payload, ?*anyopaque) callconv(arch.cc) ANTSTATUS;

var global_list: std.DoublyLinkedList = .{};
var global_lock: SpinLock = .{};

pub var knownObjectType: ob.KnownTypeInstance = .{
    .name = "Driver",
    .base_vtable = .{},
};

state: enum { init, loaded, unloading, poisoned } = .init,
node: std.DoublyLinkedList.Node = .{},
name: []const u8,
hardware_ids: []const []const u8,
major_functions: [Irp.MAX_MAJOR_FUNCTIONS]Callback = .{null} ** Irp.MAX_MAJOR_FUNCTIONS,
_entryFn: *const @TypeOf(antk.c.AntkDriverEntry),

pub fn create(name: []const u8, hardware_ids: []const []const u8, entry: *const @TypeOf(antk.antkDriverEntry)) !*Driver {
    const self = try heap.allocator.create(Driver);
    self.* = .{
        .name = name,
        .hardware_ids = hardware_ids,
        ._entryFn = @ptrCast(entry),
    };

    global_lock.lock();
    global_list.append(&self.node);
    global_lock.unlock();

    return self;
}


pub fn setCallback(self: *Driver, func_id: Irp.MajorFunction.Tag, cb: Callback) void {
    self.major_functions[@intFromEnum(func_id)] = cb;
}
