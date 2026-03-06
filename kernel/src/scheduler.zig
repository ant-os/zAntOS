//! Per-Cpu Scheduler

const std = @import("std");
const kpcb = @import("kpcb.zig");
const irql = @import("interrupts/irql.zig");
const heap = @import("mm/heap.zig");
const arch = @import("arch.zig");
const TrapFrame = @import("interrupts.zig").TrapFrame;
const IrqSafeSpinlock = @import("interrupts/irql.zig").Lock;
pub const Thread = @import("scheduling/thread.zig");
pub const Process = @import("scheduling/process.zig");

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

pub inline fn local() *Scheduler {
    return &kpcb.current().scheduler;
}

pub inline fn localNoLocks() *Scheduler {
    return &kpcb.current().scheduler;
}

pub inline fn currentThread() ?*Thread {
    return @atomicLoad(?*Thread, &local().current_thread, .monotonic);
}

pub fn getCurrentThread(self: *Scheduler) ?*Thread {
    return self.current_thread;
}

/// NOTE: This also aquires execlusive acess to the local scheduler.
pub fn currentThreadExclusive() ?*Thread {
    acquireExclusive();
    return localNoLocks().getCurrentThread();
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
        const oldState = current.swapState(.ready);

        if (oldState.isSchedulable() and current != self.idle_thread) {
            current.saved_context = .fromFrame(frame);
            if (oldState == .running) self.ready_queue.append(&current.node);
        }
    }

    self.setRunning(thread, frame);
}

pub inline fn acquireExclusive() void {
    kpcb.local.scheduler.local_lock.lock();
}

pub inline fn releaseExclusive() void {
    kpcb.local.scheduler.local_lock.unlock();
}

pub fn setRunning(self: *Scheduler, thread: *Thread, frame: *TrapFrame) void {
    if (thread.saved_context == null) @panic("thread has no saved context");
    std.debug.assert(thread.swapState(.running) == .ready);

    log.debug("switching to new thread with id {d}", .{thread.id.uint});

    thread.saved_context.?.applyToFrame(frame);
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
    const oldState = thread.swapState(.ready);
    std.debug.assert(oldState == .created or oldState.isSchedulable());

    self.ready_queue.append(&thread.node);
}

pub fn registerNewReadyThread(thread: *Thread) void {
    kpcb.current().scheduler.queueThread(thread);
}

pub fn idleThreadId() Thread.Id {
    const th = kpcb.current().scheduler.idle_thread orelse return .{ .uint = 0 };
    return th.id;
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
