//! Interrupts
//!

const std = @import("std");
const segmentation = @import("segmentation.zig");
const arch = @import("arch.zig");
const stacktrace = @import("debug/stacktrace.zig");
const logger = @import("logger.zig");
const kpcb = @import("kpcb.zig");
const ktest = @import("ktest.zig");
const irql = @import("interrupts/irql.zig");
const heap = @import("mm/heap.zig");

pub const Exception = enum(u8) {
    devide_error = 0,
    debug_exception = 1,
    nmi_interrupt = 2,
    breakpoint = 3,
    overflow = 4,
    out_of_range = 5,
    invalid_opcode = 6,
    device_not_available = 7,
    double_fault = 8,
    invalid_tss = 10,
    segment_not_present = 11,
    stack_segment_fault = 12,
    general_protection_fault = 13,
    page_fault = 14,
    fpu_math_fault = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_exception = 19,
    virtualization_exception = 20,
    control_protection_exception = 21,
    _,

    pub fn error_code(self: Exception) bool {
        return switch (self) {
            .double_fault,
            .invalid_tss,
            .segment_not_present,
            .general_protection_fault,
            .page_fault,
            .control_protection_exception,
            => true,
            else => false,
        };
    }
};

pub const SavedRegisters = extern struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
};

const InterruptVector = u8;

pub const TrapFrame = TrapFrameWithError(u64);
pub fn TrapFrameWithError(ErrorCode: type) type {
    if (@sizeOf(ErrorCode) > 8) @compileError(std.fmt.comptimePrint(
        "interrupt error code must be at most 8 bytes but is {d} bytes",
        .{@sizeOf(ErrorCode)},
    ));

    return extern struct {
        cr4: u64,
        cr3: u64,
        cr2: u64,
        cr0: u64,
        registers: SavedRegisters align(8),
        vector: extern union {
            raw: u8,
            exception: Exception,
        } align(8),
        error_code: ErrorCode align(8),
        rip: usize,
        cs: segmentation.Selector align(8),
        eflags: u64, // TODO: Typed EFLAGS.
        rsp: usize,
        ss: segmentation.Selector align(8),

        pub fn is_reasonable(self: *@This()) bool {
            _ = self;
            return true;
        }
    };
}

noinline fn handle_exception(exception: Exception, frame: *TrapFrame) !bool {
    try logger.println("CPU exception: {s}", .{@tagName(exception)});
    try logger.writeline("Stacktrace: ");
    try stacktrace.captureAndWriteStackTraceForFrame(
        logger.writer(),
        frame.rip,
        frame.registers.rbp,
    );

    if (exception == .breakpoint) return true;
    return false;
}

const MAX_INTERRUPT_DEPTH = 8;
const MAX_EXCEPTION_DEPTH = 8;

export fn __handle_interrupt(frame: *TrapFrame) callconv(.{ .x86_64_sysv = .{} }) void {
    kpcb.local.debug_interrupt_count += 1;

    if (frame.vector.raw < 32) {
        if (kpcb.local.exception_depth >= MAX_EXCEPTION_DEPTH) arch.halt_cpu();
        kpcb.local.exception_depth += 1;
        logger.newline() catch {};
        const handeled = handle_exception(
            frame.vector.exception,
            frame,
        ) catch unreachable;

        if (!handeled) arch.halt_cpu();

        kpcb.local.last_interrupt_handeled = true;
        kpcb.local.exception_depth -= 1;
    } else {
        if (kpcb.local.interrupt_depth >= MAX_INTERRUPT_DEPTH) arch.halt_cpu();
        kpcb.local.interrupt_depth += 1;

        const route = &kpcb.current().interrupt_routes[frame.vector.raw - 0x20];

        const handled = if (route.object) |dest| handle: {
            if (dest.isr == null) break :handle false;
            dest.lock.lockAt(dest.level);

            const result = dest.isr.?(frame, dest.private);

            dest.lock.unlock();

            break :handle result;
        } else false;

        if (!handled) {
            logger.println("unhandeled interrupt 0x{x}!", .{frame.vector.raw}) catch unreachable;
            logger.writeline("Stacktrace: ") catch unreachable;
            stacktrace.captureAndWriteStackTraceForFrame(
                logger.writer(),
                frame.rip,
                frame.registers.rbp,
            ) catch unreachable;
        }

        kpcb.local.last_interrupt_handeled = handled;
        kpcb.local.interrupt_depth -= 1;
    }

    logger.println("info: trying to continue normally...", .{}) catch unreachable;

    kpcb.current().last_interrupt_frame = frame.*;
}

pub const CpuMask = packed struct {
    bitset: std.bit_set.IntegerBitSet(64),

    pub const all: CpuMask = .{ .bitset = .initFull() };
    pub const none: CpuMask = .{ .bitset = .initEmpty() };

    pub inline fn currentCpu() CpuMask {
        var self = CpuMask.none;
        self.bitset.set(@intCast(arch.current_cpu()));
        return self;
    }

    pub inline fn includes(self: *CpuMask, cpu: u6) bool {
        return self.bitset.isSet(cpu);
    }

    pub inline fn includesCurrent(self: *CpuMask) bool {
        return self.includes(@intCast(arch.current_cpu()));
    }
};

pub const Isr = fn (frame: *TrapFrame, private: ?*anyopaque) callconv(.c) bool;
pub const Interrupt = struct {
    vector: u8,
    cpumask: CpuMask,

    lock: irql.Lock,
    level: irql.Irql,
    isr: ?*const Isr,
    private: ?*anyopaque,
    binding: union(enum(u8)) {
        none: void = 0,
        _,
    } = .none,
};

pub const InterruptRoute = struct {
    object: ?*Interrupt,
};

pub inline fn enable() void {
    asm volatile ("sti");
}

pub inline fn disable() void {
    asm volatile ("cli");
}

var global_vector_state: std.bit_set.IntegerBitSet(256) = .initFull();

pub fn allocateVector(local: bool) ?u8 {
    var bitmap = if (local) &kpcb.current().local_vector_state else &global_vector_state;
    const vector = bitmap.findFirstSet() orelse return null;
    kpcb.current().local_vector_state.set(vector);
    bitmap.unset(vector);
    std.debug.assert(!global_vector_state.isSet(vector));
    return @intCast(vector);
}

pub fn connect(isr: *const Isr, private: ?*anyopaque, level: irql.Irql, cpumask: CpuMask) !u8 {
    if (cpumask.bitset.count() > 1) @panic("multicore interrupt not implemented yet");

    const object = try heap.allocator.create(Interrupt);
    const vector = allocateVector(false) orelse return error.OutOfVectors;

    object.* = .{
        .binding = .none,
        .cpumask = cpumask,
        .isr = isr,
        .level = level,
        .private = private,
        .vector = vector,
        .lock = .init,
    };

    kpcb.current().interrupt_routes[vector - 0x20].object = object;

    return vector;
}

pub fn init() !void {
    global_vector_state.setRangeValue(
        .{ .start = 0, .end = 32 },
        false,
    );
    kpcb.current().local_vector_state.setRangeValue(
        .{ .start = 0, .end = 32 },
        false,
    );
}
