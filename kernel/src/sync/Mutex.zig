//! Simple Mutex Impl.
//!
//! This struct is just a single pointer to the actual mutex internal and should be passed by value.

const std = @import("std");
const heap = @import("../mm/heap.zig");

const SpinLock = @import("spin_lock.zig").SpinLock;
const Thread = @import("../scheduling/thread.zig");
const Scheduler = @import("../scheduler.zig");
const Awaitable = @import("Awaitable.zig");

const Mutex = @This();

awaitable: Awaitable = .{ .pollFn = &_pollThunk },
owner: std.atomic.Value(u32) = .init(0),

pub fn lock(self: *Mutex) void {
    const thread = Scheduler.currentThread().?;
    if (self.poll(thread) catch unreachable) return;

    self.awaitable.parkThreadNoYield(thread);
    while (self.owner.load(.acquire) != thread.id.uint) {
        Scheduler.yield();
    }
}

fn _pollThunk(awaitable: *Awaitable, thread: *Thread) anyerror!bool {
    const self: *Mutex = @fieldParentPtr("awaitable", awaitable);
    return self.poll(thread);
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
    self.owner.store(.null, .release);
    self.awaitable.wakeSingle();
}

pub fn new() !*Mutex {
    const self = try heap.allocator.create(Mutex);
    self.* = .{};
    return self;
}