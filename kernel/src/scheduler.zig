//! Per-Cpu Scheduler

const std = @import("std");
const kpcb = @import("kpcb.zig");
const irql = @import("interrupts/irql.zig");
const heap = @import("mm/heap.zig");
const arch = @import("arch.zig");
const TrapFrame = @import("interrupts.zig").TrapFrame;
const IrqSafeSpinlock = @import("interrupts/irql.zig").Lock;
pub const Thread = @import("scheduling/thread.zig");

const log = std.log.scoped(.scheduler);

const Scheduler = @This();

force_yield: bool = false,
current_thread: ?*Thread = null,
idle_thread: ?*Thread = null,
local_lock: IrqSafeSpinlock = .init,
ready_queue: std.DoublyLinkedList = .{},
enabled: bool = false,

pub fn setEnabled(self: *Scheduler, v: bool) void {
    self.enabled = v;
}

pub fn getCurrentThread(self: *Scheduler) ?*Thread {
    return self.current_thread;
}

pub fn schedule(self: *Scheduler, frame: *TrapFrame) void {
    if (!self.enabled) return;
    irql.assertLessOrEqual(.dispatch);

    // early return in nested interrupts
    if (kpcb.current().interrupt_depth != 1) return;
    // or if the thread is already holding the lock.
    if (self.local_lock.isLocked()) return;

    // for now just use a simple spinlock.
    self.local_lock.lock();
    defer self.local_lock.unlock();

    const next = self.popNextThread() orelse if (self.force_yield) self.idle_thread.? else return;
    self.internalSwitchToThread(next, frame);
}

fn internalSwitchToThread(self: *Scheduler, thread: *Thread, frame: *TrapFrame) void {
    if (self.current_thread) |current| {
        std.debug.assert(current.state == .running);
        current.saved_context = .fromFrame(frame);
        current.state = .ready;
        self.ready_queue.append(&current.node);
    }

    self.setRunning(thread, frame);
}

pub fn setRunning(self: *Scheduler, thread: *Thread, frame: *TrapFrame) void {
    std.debug.assert(thread.state == .ready);
    if (thread.saved_context == null) @panic("thread has no saved context");

    log.debug("switching to new thread with id {d}", .{thread.id.uint});

    thread.saved_context.?.applyToFrame(frame);
    thread.state = .running;
    self.current_thread = thread;
}

pub fn popNextThread(self: *Scheduler) ?*Thread {
    const node = self.ready_queue.popFirst() orelse return null;
    return @fieldParentPtr("node", node);
}

pub fn setIdleThread(idle: *Thread) void {
    kpcb.current().scheduler.idle_thread = idle;
}

pub fn queueThreadNoLock(self: *Scheduler, thread: *Thread) void {
    std.debug.assert(thread.state == .created);

    thread.state = .ready;
    self.ready_queue.append(&thread.node);
}

pub fn registerNewReadyThread(thread: *Thread) void {
    kpcb.current().scheduler.queueThread(thread);
}

pub fn queueThread(self: *Scheduler, thread: *Thread) void {
    self.local_lock.lock();
    defer self.local_lock.unlock();

    self.queueThreadNoLock(thread);
}

pub fn init(self: *Scheduler) !void {
    _ = self;
}

pub fn yield() void {
    // hardcoded software int for now lmao, later dyn self-ipi ig.
    asm volatile ("int $0x20");
}

pub export fn __thread_idle(_: ?*anyopaque) callconv(arch.cc) noreturn {
    log.info("running idle thread...", .{});
    while (true) {
        std.atomic.spinLoopHint();
    }
}
