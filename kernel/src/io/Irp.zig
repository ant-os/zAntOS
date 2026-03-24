//! Input/Output Request Packet

const std = @import("std");
const ob = @import("../ob/object.zig");
const heap = @import("../mm/heap.zig");
const function = @import("function.zig");
const irql = @import("../interrupts/irql.zig");
const queue = @import("../utils/queue.zig");
const ANTSTATUS = @import("root").ANTSTATUS;


const SpinLock = @import("../sync/spin_lock.zig").SpinLock;
const Driver = @import("Driver.zig");
const Device = @import("Device.zig");
const Mutex = @import("../sync/Mutex.zig");
const Irp = @This();

pub const MAX_MAJOR_FUNCTIONS = function.MAX_MAJOR_FUNCTIONS;
pub const MajorFunction = function.MajorFunction;

pub const Priority = enum(u8) {
    lowest,
    low,
    medium,
    high,
    immediate = 0xFF,
    _,
};

pub const StackEntry = struct {
    flags: u8 = 0,
    owner: *Irp,
    status: ANTSTATUS = .uninit,
    node: std.DoublyLinkedList.Node = .{},
    major_function: MajorFunction,
    minor_function: u8 = 0,
    driver_override: ?*Driver = null,
    device: *Device,
    context: ?*anyopaque = null,
    completion: union(enum) { ignored: void, callback: extern struct {
        func: *const fn (*Irp, *StackEntry, ?*anyopaque) callconv(.c) void,
        context: ?*anyopaque = null,
    } } = .ignored,

    pub fn execute(self: *StackEntry, irp: *Irp) ANTSTATUS {
        const driver = if (self.driver_override) |drv| drv else self.device.driver orelse return .no_driver;

        const cb = driver.major_functions[@intFromEnum(self.major_function)] orelse return .unsupported;

        const params: *const anyopaque = switch (self.major_function) {
            inline else => |v| @ptrCast(&v),
        };

        const status = cb(irp, params, self.context);

        self.status = status;
        if (status == .pending) return .pending;
        if (status != .success) return status;
        return .success;
    }
};

status: ANTSTATUS = .uninit,
stack: std.DoublyLinkedList = .{},
current_entry: ?*StackEntry = null,

stack_index: u16 = 0,
stack_size: u16 = 0,
pending: u16 = 0,
error_index: u16 = 0xFFFF,

lock: SpinLock = .{},
priority: Priority = .medium,
queue_node: queue.SinglyLinkedNode = .{},

var global_queue: queue.PriorityQueue(Irp, "queue_node", "priority", Priority) = .{};
var global_lock: Mutex = .{};

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

    if (self.status == .uninit) self.status = .pending;
}

pub inline fn currentEntry(self: *Irp) ?*StackEntry {
    return self.current_entry;
}

pub fn executeSingle(self: *Irp) ?ANTSTATUS {
    self.lock.lock();
    defer self.lock.unlock();

    var status: ANTSTATUS = undefined;

    if (self.stack_index >= self.stack_size) return null;

    if (self.current_entry == null) self.current_entry = @fieldParentPtr(
        "node",
        self.stack.first orelse return null,
    );
    if (self.current_entry) |ent| {
        status = ent.execute(self);
        if (status != .pending and status != .success) {
            self.status = status;
            return status;
        }
        if (status == .pending) self.pending += 1;
        self.stack_index += 1;

        if (ent.node.next == null) return status;
        self.current_entry = @fieldParentPtr("node", ent.node.next.?);
    }

    return .success;
}
