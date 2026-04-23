//! Simple Mutex Impl.
//!
//! This struct should be passed by pointer and NOT copied.

const std = @import("std");
const heap = @import("../../mm/heap.zig");

const SpinLock = @import("../../hal/spinlock.zig").SpinLock;
const Thread = @import("../../sched/thread.zig");
const Scheduler = @import("../../sched/scheduler.zig");
const Awaitable = @import("Awaitable.zig");

const Mutex = @This();

awaitable: Awaitable = .{ .pollFn = &_pollThunk },
owner: std.atomic.Value(u32) = .init(0),

pub fn lock(self: *Mutex) !void {
    //self.awaitable.lock.lockAt(.sync);
    const thread = Scheduler.currentThread() orelse return;
    if (try self.poll(thread)) return;
    thread.setState(.waiting);
    defer thread.setState(.running);

    self.awaitable.parkThreadNoYield(thread);

    // self.awaitable.lock.unlock();

    while (self.owner.load(.acquire) != thread.id.uint) {
        Scheduler.yield();
        if (try self.poll(thread)) break;
    }
}

fn _pollThunk(awaitable: *Awaitable, thread: *Thread) anyerror!bool {
    const self: *Mutex = @fieldParentPtr("awaitable", awaitable);
    return self.poll(thread);
}

fn pollInner(self: *Mutex, thread_id: u32) anyerror!bool {
    return self.owner.cmpxchgStrong(
        0,
        thread_id,
        .acquire,
        .monotonic,
    ) == null;
}

pub fn poll(self: *Mutex, thread: *Thread) anyerror!bool {
    return self.owner.cmpxchgStrong(
        0,
        thread.id.uint,
        .acquire,
        .monotonic,
    ) == null;
}

pub fn unlock(self: *Mutex) void {
    std.debug.assert(self.owner.cmpxchgStrong(
        Scheduler.safeCurrentThreadId().uint,
        0,
        .release,
        .monotonic,
    ) == null);
    _ = self.awaitable.wakeSingleNoLock();
    Scheduler.yield();
}

pub fn new() !*Mutex {
    const self = try heap.allocator.create(Mutex);
    self.* = .{};
    return self;
}
