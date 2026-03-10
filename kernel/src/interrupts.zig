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
const apic = @import("apic.zig");

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

pub noinline fn handle_localirq(frame: *TrapFrame) bool {
    return kpcb.current().irq_router.doRouteVector(frame.vector.raw, frame);
}

export fn __handle_interrupt(frame: *TrapFrame) callconv(.{ .x86_64_sysv = .{} }) void {
    kpcb.local.debug_interrupt_count +%= 1;

    var handled: bool = false;
    const isException = frame.vector.raw < 32;

    if (isException) {
        if (kpcb.local.exception_depth >= MAX_EXCEPTION_DEPTH) arch.halt_cpu();
        kpcb.local.exception_depth += 1;
        logger.newline() catch {};
        handled = handle_exception(
            frame.vector.exception,
            frame,
        ) catch unreachable;
    } else {
        if (kpcb.local.interrupt_depth >= MAX_INTERRUPT_DEPTH) arch.halt_cpu();
        kpcb.local.interrupt_depth += 1;

        handled = handle_localirq(frame);

        if (!handled) {
            logger.println("unhandeled interrupt 0x{x}!", .{frame.vector.raw}) catch unreachable;
            logger.writeline("Stacktrace: ") catch unreachable;
            stacktrace.captureAndWriteStackTraceForFrame(
                logger.writer(),
                frame.rip,
                frame.registers.rbp,
            ) catch unreachable;
        }
    }

    if (!handled and isException) arch.halt_cpu();

    const original_frame: TrapFrame = frame.*;

    if (irql.current().raw() <= irql.Irql.dispatch.raw() and kpcb.local.interrupt_depth == 1) {
        kpcb.current().scheduler.schedule(frame);
    }

    kpcb.local.last_interrupt_handeled = handled;
    if (isException) kpcb.local.exception_depth -= 1 else kpcb.local.interrupt_depth -= 1;

    kpcb.current().last_interrupt_frame = original_frame;
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

    pub fn cpuCount(self: *CpuMask) usize {
        return self.bitset.count();
    }

    pub inline fn includesCurrent(self: *CpuMask) bool {
        return self.includes(@intCast(arch.current_cpu()));
    }
};

pub const FancyInterruptVector = packed struct(u8) {
    index: u4,
    irql: irql.Irql,
};

pub const Isr = fn (frame: *TrapFrame, private: ?*anyopaque) callconv(.c) bool;
pub const Interrupt = struct {
    cpumask: CpuMask,
    vector_hint: ?u8 = null,

    delivery_mode: apic.DeliveryMode = .fixed,
    polarity: apic.Polarity = .active_high,
    trigger_mode: apic.TriggerMode = .edge,

    lock: irql.Lock,
    level: irql.Irql,
    isr: ?*const Isr,
    private: ?*anyopaque,
    binding: union(enum(u8)) {
        none: void = 0,
        lapic: apic.LocalApic.LvtIndex = 1,
        _,
    } = .none,

    pub fn attach(self: *Interrupt, isr: *const Isr, private: ?*anyopaque) void {
        self.isr = isr;
        self.private = private;
    }

    pub fn bindAndConnectLocal(self: *Interrupt, entry_idx: apic.LocalApic.LvtIndex) !void {
        irql.current().assertHigherOrEqual(.sync);

        if (self.cpumask.cpuCount() != 1 or !self.cpumask.includesCurrent()) return error.InvalidObject;

        self.binding = .{ .lapic = entry_idx };

        try kpcb.current().irq_router.register(self);

        var lvtEntry = apic.LocalApic.readRawRegister(apic.LocalApic.LvtEntry, @intFromEnum(entry_idx));

        lvtEntry.masked = false;
        lvtEntry.vector = self.vector_hint orelse @panic("vector hint not present");
        lvtEntry.trigger_mode = self.trigger_mode;
        lvtEntry.delivery_mode = self.delivery_mode;

        apic.LocalApic.writeRawRegister(apic.LocalApic.LvtEntry, @intFromEnum(entry_idx), lvtEntry);
    }

    pub fn sendEoi(self: *Interrupt) void {
        switch (self.binding) {
            .lapic => apic.eoi(),
            else => {},
        }
    }
};

pub const IrqRoute = struct {
    object: ?*Interrupt,
};

pub inline fn enable() void {
    asm volatile ("sti");
}

pub inline fn disable() void {
    asm volatile ("cli");
}

pub const IrqRouter = struct {
    const USABLE_VECTOR_BASE = 31;

    const Bitset = std.bit_set.IntegerBitSet(0xF);

    const full_bitset = Bitset.initEmpty();
    const high_bitmap = blk: {
        var set = full_bitset;
        set.unset(0xF - 1);
        break :blk set;
    };

    routes: [0xE0]?*Interrupt = .{null} ** 0xE0,
    vectors: [0xE]Bitset = blk: {
        var sets: [0xE]Bitset = .{Bitset.initFull()} ** 0xE;
        // reserve the surpisous interrupt vector
        sets[0xD].unset(0xE);
        break :blk sets;
    },

    pub const init: IrqRouter = .{};

    pub fn register(self: *IrqRouter, irq: *Interrupt) !void {
        const level = irq.level;
        if (level.raw() <= irql.Irql.async.raw()) return error.InvalidIrql;

        const set = &self.vectors[level.raw() - 2];

        const index = set.toggleFirstSet() orelse return error.NoMoreVectors;

        const vector: u8 = @bitCast(FancyInterruptVector{
            .irql = irq.level,
            .index = @intCast(index),
        });

        if (self.routes[vector - USABLE_VECTOR_BASE] != null) return error.AlreadyInitalized;

        irq.vector_hint = vector;

        self.routes[vector - USABLE_VECTOR_BASE] = irq;
    }

    pub fn getIrqForVector(self: *const IrqRouter, vector: u8) ?*Interrupt {
        return self.routes[vector - USABLE_VECTOR_BASE];
    }

    pub fn doRouteVector(self: *IrqRouter, vector: u8, frame: *TrapFrame) bool {
        std.debug.assert(vector == frame.vector.raw);

        const irq = self.getIrqForVector(frame.vector.raw) orelse return false;

        if (irq.isr == null) return false;
        irq.lock.lockAt(irq.level);

        const result = irq.isr.?(frame, irq.private);

        irq.sendEoi();

        irq.lock.unlock();

        return result;
    }
};

pub fn create(level: irql.Irql) !*Interrupt {
    const irq = try heap.allocator.create(Interrupt);

    irq.* = .{
        .binding = .none,
        .cpumask = .currentCpu(),
        .isr = null,
        .private = null,
        .level = level,
        .lock = .init,
    };

    return irq;
}

pub fn init() !void {}
