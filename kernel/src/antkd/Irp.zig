//! Input/Output Request Packet

const std = @import("std");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");
const function = @import("function.zig");

const SpinLock = @import("../sync/spin_lock.zig").SpinLock;
const Driver = @import("Driver.zig");
const Device = @import("Device.zig");
const Irp = @This();

pub const MAX_MAJOR_FUNCTIONS = function.MAX_MAJOR_FUNCTIONS;
pub const MajorFunction = function.MajorFunction;

pub const Status = enum(u8) {
    init,
    pending,
    completed,
    failed,
    _,
};

pub const StackEntry = struct {
    flags: u8 = 0,
    owner: *Irp,
    status: Status = .init,
    err: ?anyerror = null,
    node: std.DoublyLinkedList.Node = .{},
    major_function: MajorFunction,
    minor_function: u64 = 0,
    driver_override: ?*Driver = null,
    device: *Device,
    context: ?*anyopaque = null,
    completion: union(enum) { ignored: void, callback: extern struct {
        func: *const fn (*Irp, *StackEntry, ?*anyopaque) callconv(.c) void,
        context: ?*anyopaque = null,
    } } = .ignored,

    pub fn execute(self: *StackEntry, irp: *Irp) anyerror!void {
        const driver = if (self.driver_override) |drv| drv else self.device.driver orelse return;

        const cb = driver.major_functions[@intFromEnum(self.major_function)] orelse return error.Unimplemented;

        const params: *const anyopaque = switch (self.major_function) {
            inline else => |v| @ptrCast(&v),
        };

        try cb(irp, params, self.context);
    }
};

status: Status = .init,
stack: std.DoublyLinkedList = .{},
current_entry: ?*StackEntry = null,

stack_index: u16 = 0,
stack_size: u16 = 0,
pending: u16 = 0,
error_index: u16 = 0xFFFF,

lock: SpinLock = .{},

pub fn create() !*Irp {
    const self = try heap.allocator.create(Irp);
    self.* = .{};
    return self;
}

pub fn addEntry(self: *Irp, device: *Device, func: MajorFunction, context: ?*anyopaque) !void {
    const entry = try heap.allocator.create(StackEntry);
    entry.* = .{
        .owner = self,
        .major_function = func,
        .device = device,
        .context = context,
    };

    self.lock.lock();
    defer self.lock.unlock();

    self.stack.append(&entry.node);
    self.stack_size += 1;

    if (self.status == .init) self.status = .pending;
}

pub inline fn currentEntry(self: *Irp) ?*StackEntry {
    return self.current_entry;
}

pub fn executeSingle(self: *Irp) ?(anyerror!void) {
    self.lock.lock();
    defer self.lock.unlock();

    if (self.stack_index >= self.stack_size) return null;

    if (self.current_entry == null) self.current_entry = @fieldParentPtr(
        "node",
        self.stack.first orelse return null,
    );
    if (self.current_entry) |ent| {
        ent.execute(self) catch |e| {
            ent.err = e;
            self.stack_index += 1;
            return e;
        };
        if (ent.status == .pending) self.pending += 1;
        self.stack_index += 1;

        if (ent.node.next == null) return;
        self.current_entry = @fieldParentPtr("node", ent.node.next.?);
    }
}
