//! Per-Cpu Scheduler

const std = @import("std");
const kpcb = @import("kpcb.zig");
const irql = @import("interrupts/irql.zig");
const heap = @import("mm/heap.zig");
const arch = @import("arch.zig");
const tsc = @import("tsc.zig");
const apic = @import("apic.zig");
const logger = @import("logger.zig");
const TrapFrame = @import("interrupts.zig").TrapFrame;
const IrqSafeSpinlock = @import("interrupts/irql.zig").Lock;
pub const Thread = @import("scheduling/thread.zig");
pub const Process = @import("scheduling/process.zig");
pub const RunQueue = @import("utils/queue.zig").PriorityQueue(Thread, "queue_node", "priority", Thread.Priority);

const log = std.log.scoped(.scheduler);

const Scheduler = @This();

pending: bool = false,
yield_: bool = false,
current_thread: ?*Thread = null,
idle_thread: ?*Thread = null,
local_lock: IrqSafeSpinlock = .init,
ready_queue: RunQueue,
last_schedule_time: u64 = 0,
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

pub fn safeCurrentThreadId() Thread.Id {
    const oldIrql = irql.raise(.sync);
    const id = if (kpcb.current().scheduler.current_thread) |th| th.id else Thread.Id.null;
    irql.update(oldIrql);
    return id;
}

/// NOTE: This also aquires execlusive acess to the local scheduler.
pub fn currentThreadExclusive() ?*Thread {
    acquireExclusive();
    return localNoLocks().getCurrentThread();
}

pub fn setPendingInner(self: *Scheduler, v: bool) void {
    self.pending = v;
}

fn interrupt_tail(self: *Scheduler, frame: *TrapFrame) void {
    _ = frame;

    const currentTime = tsc.read();
    const diff = currentTime - self.last_schedule_time;
    self.last_schedule_time = currentTime;
    if (diff == currentTime) return self.setPendingInner(true);
    if (self.getCurrentThread() == null) return self.setPendingInner(true);

    const thread = self.getCurrentThread().?;

    thread.quatum -|= diff;

    return self.setPendingInner(thread.quatum == 0);
}

pub fn schedule(self: *Scheduler, frame: *TrapFrame) void {
    if (!self.enabled) return;
    irql.assertLessOrEqual(.dispatch);

    // early return in nested interrupts
    if (kpcb.current().interrupt_depth != 1) return;
    // or if the thread is already holding the lock.
    if (self.local_lock.isLocked()) return;

    self.local_lock.lock();
    defer self.local_lock.unlock();

    self.interrupt_tail(frame);

    if (self.pending or self.yield_) {
        const next = self.popNextThread() orelse if (self.yield_) self.idle_thread.? else {
            self.pending = false;
            return;
        };
        self.internalSwitchToThread(next, frame);
        self.pending = false;
        self.yield_ = false;
    }
}

fn internalSwitchToThread(self: *Scheduler, thread: *Thread, frame: *TrapFrame) void {
    if (self.current_thread == thread) {
        thread.quatum = thread.priority.quatum();
        return;
    }

    log.debug("switching to thread with id {d} ('{s}'), preempted={any}", .{ thread.id.uint, thread.name orelse "<???>", frame.vector.raw != 0x20 });
    if (self.current_thread) |current| {
        const oldState = current.swapState(.ready);

        if (oldState.isSchedulable() and current != self.idle_thread) {
            current.saved_context = .fromFrame(frame);
            if (oldState == .running) self.ready_queue.add(current);
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

    const quatum = thread.priority.quatum();

    thread.saved_context.?.applyToFrame(frame);
    thread.quatum = quatum;
    self.current_thread = thread;
}

pub fn popNextThread(self: *Scheduler) ?*Thread {
    return self.ready_queue.dequeue();
}

pub fn setIdleThread(idle: *Thread) void {
    kpcb.current().scheduler.idle_thread = idle;
}

pub fn queueThreadNoLock(self: *Scheduler, thread: *Thread) void {
    if (thread == self.idle_thread) return;

    const oldState = thread.swapState(.ready);
    std.debug.assert(oldState == .created or oldState.isSchedulable());

    self.ready_queue.add(thread);
}

pub fn registerNewReadyThread(thread: *Thread) void {
    kpcb.current().scheduler.queueThread(thread);
}

pub fn idleThreadId() Thread.Id {
    const th = kpcb.current().scheduler.idle_thread orelse return .{ .uint = 0 };
    return th.id;
}

pub fn queueThread(self: *Scheduler, thread: *Thread) void {
    self.local_lock.lockAt(.sync);
    defer self.local_lock.unlock();

    self.queueThreadNoLock(thread);
}

pub fn init(self: *Scheduler) !void {
    _ = self;
}

pub fn yield() void {
    apic.send_ipi(.{
        .vector = 0x20,
        .delivery = .fixed,
        .dest = @intCast(kpcb.local.lapic.id),
        .dest_mode = .physical,
        .shorthand = .self,
        .trigger_mode = .edge,
    });
}

pub export fn __thread_idle(_: ?*anyopaque) callconv(arch.cc) noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
