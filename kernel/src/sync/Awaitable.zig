//! An object that threads can wait for. This type should only be used as a pointer not

const std = @import("std");

const SpinLock = @import("../interrupts/irql.zig").Lock;
const Thread = @import("../scheduling/thread.zig");
const Scheduler = @import("../scheduler.zig");

const Awaitable = @This();

pub fn Embedded(comptime T: type, comptime field_name: []const u8) type {
    if (!std.meta.hasMethod(T, "poll")) @compileError("type is missing poll() method");
    if (!@hasField(T, field_name)) @compileError("type is missing expected field " ++ field_name);
    return struct {
        comptime {
            if (@TypeOf(@field(T, field_name)) != @This()) @compileError("field must belong to the same embedded awaitable");
        }

        inner: Awaitable = .{
            .pollFn = &pollAdaptor,
        },

        pub fn pollAdaptor(_inner: *Awaitable, thread: *Thread) anyerror!bool {
            const self: *@This() = @fieldParentPtr("inner", _inner);
            const outer: *T = @fieldParentPtr(field_name, self);
            return T.poll(outer, thread);
        }

        pub fn get(self: *@This()) *Awaitable {
            return &self.inner;
        }
    };
}

lock: SpinLock = .init,
waiter_queue: std.DoublyLinkedList = .{},
pollFn: *const fn (*Awaitable, *Thread) anyerror!bool,

pub fn parkThreadNoLock(self: *Awaitable, thread: *Thread) void {
    self.waiter_queue.append(&thread.queue_node);
    thread.setState(.waiting);
}

pub fn parkThreadNoYield(self: *Awaitable, thread: *Thread) void {
    self.lock.lockAt(.deferred);
    defer self.lock.unlock();

    self.parkThreadNoLock(thread);
}

pub fn wakeSingle(self: *Awaitable) bool {
    self.lock.lockAt(.deferred);
    defer self.lock.unlock();

    return self.wakeSingleNoLock();
}

pub fn wakeSingleNoLock(self: *Awaitable) bool {
    if (self.waiter_queue.first == null) return false;
    if (self.waiter_queue.popFirst()) |thnode| {
        const thread: *Thread = @fieldParentPtr("queue_node", thnode);
        Scheduler.localNoLocks().queueThread(thread);
        return true;
    }

    return false;
}

pub fn wakeAll(self: *Awaitable) usize {
    var count: usize = 0;

    self.lock.lock();
    defer self.lock.unlock();

    while (self.wakeSingleNoLock()) {
        count += 1;
    }

    return count;
}
